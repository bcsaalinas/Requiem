extends StaticBody2D
## Altar de Ofrenda Tradicional para la Hacienda Requiem
##
## Respeta las especificaciones del ritual de rezo:
##   - Mantiene "pray" (E) continuo durante 12.0 s.
##   - Enraíza al jugador vía GameState.begin_prayer(self).
##   - Emite ruido cada 0.5 s (radio 6 u) y un pulso a t=2.0 s (radio 8 u) que atrae a la entidad.
##   - Al completarse, consagra la ofrenda con luz dorada permanente y registra el progreso en GameState.

signal altar_completed(altar: Node)

const PX_PER_UNIT: float = Units.PX_PER_UNIT

@export_group("Ritual")
@export var altar_name: String = "Ofrenda"
@export var pray_duration: float = 12.0
var offering_display: Sprite2D
var _can_place_offering: Callable

@export_group("Ruido (u)")
@export var pray_noise_radius_u: float = 6.0
@export var pray_noise_interval: float = 0.5

@export_group("Pulso")
@export var pulse_at_time: float = 2.0
@export var pulse_radius_u: float = 8.0
@export var pulse_duration: float = 1.5

@export_group("Audio")
## She prays aloud here. The voice itself is played by her prayer audio (player/prayer_audio.gd,
## the set viv/prayer_voice), once, at the level in audio/sound_settings.gd: this altar plays
## nothing itself.
@export var prayer_spoken := true

var jugador_cerca: bool = false
var tiempo_interaccion: float = 0.0
var is_completed: bool = false
var offering_placed := false
var _wait_for_prayer_release := false

@onready var label_texto: Label = $Label
@onready var barra_progreso: ProgressBar = $ProgressBar
@onready var sprite: Sprite2D = $Sprite
@onready var area_2d: Area2D = get_node_or_null("Area2D")
@onready var light_left: PointLight2D = get_node_or_null("LightLeft")
@onready var light_right: PointLight2D = get_node_or_null("LightRight")
@onready var light_center: PointLight2D = get_node_or_null("LightCenter")

var jugador_ref: CharacterBody2D = null
var _estaba_rezando: bool = false
var _timer_ruido: float = 0.0
var _pulse_disparado: bool = false
var _pulse_restante: float = 0.0
var _color_base: Color = Color.WHITE


func _ready() -> void:
	if is_instance_valid(sprite):
		_color_base = sprite.modulate
	if is_instance_valid(barra_progreso):
		barra_progreso.hide()
		barra_progreso.value = 0.0
	if is_instance_valid(label_texto):
		# The prompt to pray is the HUD's ("E · Pray at ..."): this label only marks a prayed altar.
		label_texto.text = ""
		label_texto.hide()
	if is_instance_valid(area_2d):
		area_2d.body_entered.connect(_on_area_2d_body_entered)
		area_2d.body_exited.connect(_on_area_2d_body_exited)


func _process(delta: float) -> void:
	if is_completed:
		return
	var pray_key := Input.is_action_pressed("pray") or Input.is_key_pressed(KEY_E)
	if pray_key and Input.is_action_pressed("hold_breath"):
		_wait_for_prayer_release = true
	if _wait_for_prayer_release and not pray_key:
		_wait_for_prayer_release = false

	# Detección directa por distancia al jugador (máxima robustez)
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if is_instance_valid(player):
		jugador_ref = player
		var offset: Vector2 = get_meta("interaction_offset", Vector2.ZERO)
		var distance := (global_position + offset).distance_to(player.global_position)
		jugador_cerca = distance <= 85.0
	else:
		jugador_cerca = false
		jugador_ref = null

	if not _player_can_pray():
		cancel_prayer(true)
		return

	if jugador_cerca and pray_key:
		if is_instance_valid(barra_progreso):
			barra_progreso.show()

		if not _estaba_rezando:
			_timer_ruido = 0.0
			_pulse_disparado = false
			_pulse_restante = 0.0
			if not GameState.begin_prayer(self):
				if is_instance_valid(barra_progreso):
					barra_progreso.hide()
				return
			_estaba_rezando = true
			_avisar_ruido()

		tiempo_interaccion += delta
		_tick_pulso(delta)

		_timer_ruido += delta
		if _timer_ruido >= pray_noise_interval:
			_timer_ruido = 0.0
			_avisar_ruido()

		if is_instance_valid(barra_progreso):
			barra_progreso.value = (tiempo_interaccion / pray_duration) * 100.0

		if tiempo_interaccion >= pray_duration:
			_interaccion_completada()
	else:
		if _estaba_rezando:
			cancel_prayer(false)


func _player_can_pray() -> bool:
	return not is_completed and not GameState.is_dead and is_instance_valid(jugador_ref) \
		and jugador_ref.can_process() and can_begin_prayer() \
		and not _wait_for_prayer_release


func can_begin_prayer() -> bool:
	return not is_completed and offering_placed and _can_place_offering.is_valid() and _can_place_offering.call()


func place_offering() -> void:
	if not _can_place_offering.is_valid() or not _can_place_offering.call():
		return
	offering_placed = true
	_wait_for_prayer_release = true
	if is_instance_valid(offering_display):
		offering_display.show()


func configure_offering(display: Sprite2D, can_place: Callable) -> void:
	offering_display = display
	_can_place_offering = can_place


func get_prayer_elapsed() -> float:
	return tiempo_interaccion


func get_prayer_target() -> Vector2:
	return global_position


func _tick_pulso(delta: float) -> void:
	if not _pulse_disparado and tiempo_interaccion >= pulse_at_time:
		_pulse_disparado = true
		_pulse_restante = pulse_duration
		_avisar_ruido()

	if _pulse_restante > 0.0:
		_pulse_restante = maxf(0.0, _pulse_restante - delta)

	_refrescar_color()


func _radio_actual_u() -> float:
	return pulse_radius_u if _pulse_restante > 0.0 else pray_noise_radius_u


func _refrescar_color() -> void:
	if not is_instance_valid(sprite):
		return
	if _pulse_restante > 0.0:
		var t: float = _pulse_restante / maxf(pulse_duration, 0.001)
		sprite.modulate = _color_base.lerp(Color(1.6, 1.4, 0.9), t)
	else:
		sprite.modulate = _color_base


func cancel_prayer(immediate := true) -> void:
	_estaba_rezando = false
	tiempo_interaccion = 0.0
	_timer_ruido = 0.0
	_pulse_disparado = false
	_pulse_restante = 0.0
	_refrescar_color()
	if is_instance_valid(barra_progreso):
		barra_progreso.value = 0.0
		barra_progreso.hide()
	GameState.end_prayer(self, immediate)


func _exit_tree() -> void:
	if _estaba_rezando or GameState.prayer_source == self:
		cancel_prayer(true)


func _interaccion_completada() -> void:
	is_completed = true
	cancel_prayer(false)

	if is_instance_valid(label_texto):
		label_texto.text = "Prayed"
		label_texto.show()
	if is_instance_valid(barra_progreso):
		barra_progreso.hide()

	# Resplandor dorado cálido permanente
	if is_instance_valid(light_left):
		var tw := create_tween()
		tw.tween_property(light_left, "energy", 2.2, 0.8)
		tw.parallel().tween_property(light_left, "color", Color("#ffd580"), 0.8)
	if is_instance_valid(light_right):
		var tw := create_tween()
		tw.tween_property(light_right, "energy", 2.2, 0.8)
		tw.parallel().tween_property(light_right, "color", Color("#ffd580"), 0.8)
	if is_instance_valid(light_center):
		var tw := create_tween()
		tw.tween_property(light_center, "energy", 2.0, 0.8)

	altar_completed.emit(self)
	GameState.register_altar_prayed(self)


func _on_area_2d_body_entered(body: Node2D) -> void:
	if is_completed:
		return
	if body is CharacterBody2D and body.is_in_group("player"):
		jugador_cerca = true
		jugador_ref = body


func _on_area_2d_body_exited(body: Node2D) -> void:
	if body == jugador_ref:
		jugador_cerca = false
		cancel_prayer(false)
		jugador_ref = null


func _avisar_ruido() -> void:
	var posicion := jugador_ref.global_position if jugador_ref != null else global_position
	NoiseManager.emit_noise(posicion, _radio_actual_u() * PX_PER_UNIT, NoiseManager.SourceType.PRAY)
