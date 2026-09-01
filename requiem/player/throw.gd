extends Node

# Throw (verbo secundario de la spec de Requiem)
#
# Se pone como hijo del Player, en un nodo llamado EXACTAMENTE "Throw".
# Usa las acciones de input "throw" (tecla recomendada: Q) y
# "switch_throwable" (tecla recomendada: Tab).
#
# El objeto vuela hacia el cursor y hace ruido EN EL PUNTO DONDE CAE, no
# donde estas tu. Es la unica mecanica que deja al jugador mandar a la
# entidad a un lugar que el elige, en vez de solo escaparse del ruido propio.
#
# Maneja DOS objetos:
#
#   - Piedra: municion infinita, un solo golpe de ruido al caer.
#
#   - Despertador: 2 por noche, sigue sonando alarm_duration segundos en el
#     mismo punto. Re-emite cada alarm_tick_interval porque entity_ai.gd
#     ignora el parametro `duration` de NoiseManager: un solo emit largo no
#     haria nada, la entidad tiene que volver a oirlo para seguir apuntando ahi.
#
# NO hay que tocar entity_ai.gd: su _on_noise_emitted ya trae
# `if current_state != State.HUNT`, o sea que un objeto lanzado no interrumpe
# a una entidad que ya viene en caceria, tal como pide la spec.
#
# UNIDADES: 1 u = 32 px. Distancias y radios se exportan en unidades.
const PX_PER_UNIT: float = 32.0

enum Throwable { PIEDRA, DESPERTADOR }

@export_group("Lanzamiento (u)")
## Distancia maxima. Si hay pared antes, el objeto cae justo antes de ella.
@export var throw_distance_u: float = 6.0
## Radio del ruido al impactar. Igual para los dos objetos.
@export var impact_noise_radius_u: float = 8.0

@export_group("Tiempos")
## Animacion de lanzamiento: no puedes volver a lanzar mientras dura.
@export var windup_time: float = 0.5
## Enfriamiento despues de la animacion.
@export var cooldown_time: float = 1.0
## Cuanto tarda el objeto en llegar del jugador al punto de caida.
@export var flight_time: float = 0.35

@export_group("Despertador")
@export var alarm_charges: int = 2
## Cuanto sigue sonando despues de caer.
@export var alarm_duration: float = 15.0
## Cada cuanto vuelve a avisar a NoiseManager mientras suena.
@export var alarm_tick_interval: float = 0.5

@export_group("Colision")
## Capa fisica de las paredes; debe coincidir con la del TileMapLayer.
@export var wall_mask: int = 1

@export_group("Visual")
@export var piedra_color: Color = Color(0.85, 0.85, 0.8)
@export var despertador_color: Color = Color(1.0, 0.85, 0.35)
@export var projectile_size: float = 6.0

@export_group("Audio")
@export var piedra_clips: Array[AudioStream] = []
@export var despertador_clips: Array[AudioStream] = []
@export var volume_db: float = -6.0

var selected: int = Throwable.PIEDRA
var alarms_left: int = 0
var is_throwing: bool = false

var _windup_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _pending_landing: Vector2 = Vector2.ZERO
var _pending_kind: int = Throwable.PIEDRA
var _audio_player: AudioStreamPlayer2D

## Objetos en el aire: { "node", "from", "to", "t", "kind" }
var _in_flight: Array = []
## Despertadores sonando: { "position", "time_left", "tick" }
var _ringing: Array = []

@onready var player: Node2D = get_parent()

# --- Etiqueta de municion en pantalla ---
var _bar_layer: CanvasLayer
var _ammo_label: Label


func _ready() -> void:
	alarms_left = alarm_charges

	_audio_player = AudioStreamPlayer2D.new()
	add_child(_audio_player)

	_bar_layer = CanvasLayer.new()
	add_child(_bar_layer)

	# Debajo de las barras de HoldBreath (y=20 pulmon, y=54 agotamiento)
	# y de la bateria de Flashlight (y=88).
	_ammo_label = Label.new()
	_ammo_label.position = Vector2(20, 122)
	_ammo_label.add_theme_font_size_override("font_size", 14)
	_bar_layer.add_child(_ammo_label)

	_update_label()


func _physics_process(delta: float) -> void:
	if GameState.is_dead:
		return

	_tick_timers(delta)
	_tick_flight(delta)
	_tick_ringing(delta)

	if Input.is_action_just_pressed("switch_throwable"):
		_switch_throwable()

	if Input.is_action_just_pressed("throw") and can_throw():
		_start_throw()

	_update_label()


func _tick_timers(delta: float) -> void:
	if _windup_timer > 0.0:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			_release_object()
	elif _cooldown_timer > 0.0:
		_cooldown_timer = max(0.0, _cooldown_timer - delta)


func _switch_throwable() -> void:
	if selected == Throwable.PIEDRA:
		selected = Throwable.DESPERTADOR
	else:
		selected = Throwable.PIEDRA


## True si puedes lanzar ahorita: sin animacion en curso, sin enfriamiento,
## sin bloqueo por gasp forzado, y con municion del objeto seleccionado.
func can_throw() -> bool:
	if is_throwing or _cooldown_timer > 0.0:
		return false

	var hold_breath: Node = player.get_node_or_null("HoldBreath")
	if hold_breath != null and hold_breath.is_locked:
		return false

	if selected == Throwable.DESPERTADOR and alarms_left <= 0:
		return false

	return true


## El punto de caida se calcula AL EMPEZAR la animacion, no al soltarla: asi
## el jugador apunta y se compromete, en vez de corregir a media animacion.
func _start_throw() -> void:
	is_throwing = true
	_windup_timer = windup_time
	_pending_kind = selected
	_pending_landing = _compute_landing()

	if _pending_kind == Throwable.DESPERTADOR:
		alarms_left -= 1


## Hacia el cursor, a throw_distance_u como maximo. Si hay pared en medio,
## cae justo antes de ella en vez de atravesarla.
func _compute_landing() -> Vector2:
	var origin: Vector2 = player.global_position
	var direction: Vector2 = player.get_global_mouse_position() - origin

	if direction.length_squared() < 1.0:
		direction = Vector2.RIGHT
	direction = direction.normalized()

	var target: Vector2 = origin + direction * throw_distance_u * PX_PER_UNIT

	var space := player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(origin, target, wall_mask)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		return target

	# Se retrocede un poco para que no quede incrustado en la pared.
	return hit.position - direction * 4.0


## Fin de la animacion: el objeto sale de la mano y empieza a volar.
## El sprite se agrega al NIVEL, no al Player: si fuera hijo del Player se
## moveria con el y el punto de caida no se quedaria quieto.
func _release_object() -> void:
	is_throwing = false
	_cooldown_timer = cooldown_time

	var texture := PlaceholderTexture2D.new()
	texture.size = Vector2(projectile_size, projectile_size)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.modulate = _color_for(_pending_kind)
	sprite.global_position = player.global_position
	player.get_parent().add_child(sprite)

	_in_flight.append({
		"node": sprite,
		"from": player.global_position,
		"to": _pending_landing,
		"t": 0.0,
		"kind": _pending_kind,
	})


func _tick_flight(delta: float) -> void:
	for i in range(_in_flight.size() - 1, -1, -1):
		var flying: Dictionary = _in_flight[i]
		flying["t"] += delta / max(flight_time, 0.001)

		var sprite: Sprite2D = flying["node"]

		if flying["t"] < 1.0:
			sprite.global_position = flying["from"].lerp(flying["to"], flying["t"])
			continue

		_impact(flying["to"], flying["kind"])
		sprite.queue_free()
		_in_flight.remove_at(i)


## El objeto toca el suelo: ruido en el punto de caida, no en el jugador.
func _impact(landing: Vector2, kind: int) -> void:
	_emit_impact(landing)
	_play_random_clip(_clips_for(kind), landing)

	if kind == Throwable.DESPERTADOR:
		_ringing.append({
			"position": landing,
			"time_left": alarm_duration,
			"tick": alarm_tick_interval,
		})


## El despertador re-emite en el mismo punto hasta que se le acaba la cuerda.
func _tick_ringing(delta: float) -> void:
	for i in range(_ringing.size() - 1, -1, -1):
		var alarm: Dictionary = _ringing[i]
		alarm["time_left"] -= delta
		alarm["tick"] -= delta

		if alarm["tick"] <= 0.0:
			alarm["tick"] = alarm_tick_interval
			_emit_impact(alarm["position"])
			_play_random_clip(despertador_clips, alarm["position"])

		if alarm["time_left"] <= 0.0:
			_ringing.remove_at(i)


func _emit_impact(at: Vector2) -> void:
	NoiseManager.emit_noise(at, impact_noise_radius_u * PX_PER_UNIT, NoiseManager.SourceType.THROW)


func _play_random_clip(clips: Array[AudioStream], at: Vector2) -> void:
	if clips.is_empty():
		return

	_audio_player.global_position = at
	_audio_player.volume_db = volume_db
	_audio_player.stream = clips[randi() % clips.size()]
	_audio_player.play()


func _color_for(kind: int) -> Color:
	return despertador_color if kind == Throwable.DESPERTADOR else piedra_color


func _clips_for(kind: int) -> Array[AudioStream]:
	return despertador_clips if kind == Throwable.DESPERTADOR else piedra_clips


func _update_label() -> void:
	var ammo := "%d" % alarms_left if selected == Throwable.DESPERTADOR else "inf"
	var state := ""

	if is_throwing:
		state = "  (lanzando)"
	elif _cooldown_timer > 0.0:
		state = "  (%.1fs)" % _cooldown_timer
	elif not can_throw():
		state = "  (sin municion)"

	_ammo_label.text = "[Q] %s  x%s   [Tab] cambiar%s" % [
		Throwable.keys()[selected].capitalize(), ammo, state
	]
	_ammo_label.modulate = Color(1, 1, 1, 0.85) if can_throw() else Color(1, 1, 1, 0.4)


func get_alarms_left() -> int:
	return alarms_left


## Recarga los despertadores. Para llamar al empezar una noche nueva.
func reset_charges() -> void:
	alarms_left = alarm_charges
