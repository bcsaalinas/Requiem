extends CharacterBody2D

# EntityAI (la entidad que te caza)
#
# Maquina de CUATRO estados. INVESTIGATE y SEARCH siguen existiendo en el
# codigo (por si se quiere volver a un oido mas gradual) pero HOY son
# inalcanzables: cualquier ruido que se oiga manda derecho a HUNT, ver nota
# en _on_noise_emitted.
#
#   PATROL      - Ronda el nivel por puntos al azar de la malla navegable.
#                 Lenta. Es el estado "no sabe que existes". Antes esto era
#                 IDLE y la entidad se quedaba parada para siempre.
#   INVESTIGATE - (inalcanzable hoy) Caminaba al punto exacto donde sono un
#                 ruido suelto antes de comprometerse a cazar.
#   SEARCH      - A donde cae HUNT cuando se le acaba hunt_persistence sin
#                 oir nada nuevo: revisa varios puntos alrededor del ultimo
#                 ruido antes de rendirse y volver a PATROL.
#   HUNT        - Sabe que estas ahi y te sigue de verdad. Es MAS RAPIDA QUE
#                 TU CAMINANDO (3.9 vs 3.2 u/s), asi que no puedes zafarte
#                 andando: o esprintas y pagas agotamiento, o le cortas el
#                 rastro de ruido el tiempo suficiente (hunt_persistence).
#
# OIDO: sin falloff, te oye si distance <= radius del ruido (mas grande
# mientras CAZA o BUSCA, ver alert_hearing_multiplier: estar en su radar te
# vuelve mas ruidoso, la espiral que tienes que romper quedandote quieto o
# aguantando la respiracion). CUALQUIER ruido que pase ese filtro la manda
# derecho a HUNT -- no hace falta que sea fuerte ni que se repita, y no hace
# falta acercarse mas de lo que ya hizo que se oyera la primera vez.
# hearing_range_u es solo un tope duro de seguridad MUY por encima del radio
# mas grande del juego; en la practica nunca corta nada real.
#
# UNIDADES: 1 u = 32 px, misma convencion que player.gd. TODO radio, distancia
# y velocidad se exporta en unidades. Ya no queda un solo pixel crudo aqui.
const PX_PER_UNIT: float = Units.PX_PER_UNIT

enum State { PATROL, INVESTIGATE, SEARCH, HUNT }

@export_group("Oido (u)")
## Tope de seguridad, no una mecanica: esta por encima de todo radio real.
@export var hearing_range_u: float = 40.0
## Mientras CAZA o BUSCA, multiplica el radio de todo ruido que le llega.
@export var alert_hearing_multiplier: float = 1.6

@export_group("Velocidad (u/s)")
## Rondando: lenta, para que se lea distinto de cuando ya te oyo.
@export var patrol_speed_u: float = 2.2
## Velocidad base de la spec. Se usa al investigar y al buscar.
@export var move_speed_u: float = 3.0
## Cazando: MAS rapida que caminar (3.2) y MAS lenta que esprintar (5.4).
@export var hunt_speed_u: float = 3.9

@export_group("Tiempos (s)")
@export var investigate_timeout: float = 6.0
@export var search_duration: float = 5.0
## Sin oir nada nuevo por este tiempo, la caceria baja a SEARCH.
@export var hunt_persistence: float = 5.0
## Cuanto se queda quieta al llegar a un punto de ronda.
@export var patrol_pause: float = 1.5

@export_group("Distancias (u)")
## A que distancia de un punto se considera que ya llego.
@export var arrival_threshold_u: float = 0.5
## Radio de captura: si te toca, mueres.
@export var catch_radius_u: float = 0.75
## Radio alrededor del ultimo ruido en el que SEARCH revisa puntos.
@export var search_radius_u: float = 4.0
## Cuantos puntos revisa antes de rendirse.
@export var search_points: int = 3
## Si la malla aun no esta horneada, ronda dentro de este radio del spawn.
@export var patrol_fallback_radius_u: float = 6.0

@export_group("Debug")
@export var log_state_changes: bool = true
## Colorea el greybox segun el estado. Se lee de un vistazo que esta haciendo.
@export var color_by_state: bool = true

@export_group("Audio")
## Respiracion en bucle mientras ronda/investiga/busca: grave y constante, de fondo.
@export var breath_calm_clips: Array[AudioStream] = []
## Respiracion en bucle mientras caza: mas fuerte y rapida. Es lo que delata,
## de oido, que ya sabe donde estas antes de que la veas.
@export var breath_hunt_clips: Array[AudioStream] = []
## Un solo golpe de sonido al ENTRAR en HUNT (el "te encontre").
@export var hunt_stinger_clips: Array[AudioStream] = []
## Un solo golpe de sonido al atraparte.
@export var catch_clips: Array[AudioStream] = []
@export var breath_volume_db: float = -10.0
## Cuanto sube el volumen de la respiracion (encima de breath_volume_db) en HUNT.
@export var hunt_breath_volume_boost_db: float = 6.0
@export var stinger_volume_db: float = -2.0

var current_state: int = State.PATROL
var last_heard_position: Vector2 = Vector2.ZERO
var nav_agent: NavigationAgent2D

var _sprite: Sprite2D
var _breath_player: AudioStreamPlayer2D
var _stinger_player: AudioStreamPlayer2D
var _spawn_position: Vector2
var _state_timer: float = 0.0
var _hunt_timer: float = 0.0
var _patrol_target: Vector2 = Vector2.ZERO
var _has_patrol_target: bool = false
var _patrol_wait: float = 0.0
var _search_queue: Array[Vector2] = []


func _ready() -> void:
	_spawn_position = global_position

	_sprite = $DebugSprite
	nav_agent = $NavigationAgent2D
	nav_agent.target_desired_distance = arrival_threshold_u * PX_PER_UNIT
	$CatchArea/CollisionShape2D.shape.radius = catch_radius_u * PX_PER_UNIT
	$CatchArea.body_entered.connect(_on_catch_area_body_entered)

	NoiseManager.noise_emitted.connect(_on_noise_emitted)
	_refresh_color()

	# Hijos directos del CharacterBody2D: heredan su transform solos, no hace
	# falta actualizar global_position a mano como en los componentes del Player.
	_breath_player = AudioStreamPlayer2D.new()
	add_child(_breath_player)
	_breath_player.finished.connect(_on_breath_finished)

	_stinger_player = AudioStreamPlayer2D.new()
	add_child(_stinger_player)

	_play_breath_clip()


func _physics_process(delta: float) -> void:
	if GameState.is_dead:
		_halt()
		if _breath_player.playing:
			_breath_player.stop()
		return

	match current_state:
		State.PATROL:
			_tick_patrol(delta)
		State.INVESTIGATE:
			_tick_investigate(delta)
		State.SEARCH:
			_tick_search(delta)
		State.HUNT:
			_tick_hunt(delta)


# ---------------------------------------------------------------- estados ---

## Ronda puntos al azar de la malla, con una pausa en cada uno. La pausa
## importa: una entidad que nunca se detiene se lee como un robot.
func _tick_patrol(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		_halt()
		return

	if not _has_patrol_target:
		_patrol_target = _random_map_point()
		_has_patrol_target = true

	nav_agent.target_position = _patrol_target
	_move_along_path(patrol_speed_u)

	if _reached(_patrol_target) or nav_agent.is_navigation_finished():
		_has_patrol_target = false
		_patrol_wait = patrol_pause


func _tick_investigate(delta: float) -> void:
	nav_agent.target_position = last_heard_position
	_move_along_path(move_speed_u)
	_state_timer += delta

	if _reached(last_heard_position) or _state_timer >= investigate_timeout:
		_begin_search()


## Llego al ruido y no habia nadie: revisa search_points puntos alrededor.
## Esto es lo que convierte "se rindio al tocar el punto" en "te esta buscando".
func _tick_search(delta: float) -> void:
	_state_timer += delta

	if _state_timer >= search_duration or _search_queue.is_empty():
		_change_state(State.PATROL)
		return

	var target: Vector2 = _search_queue[0]
	nav_agent.target_position = target
	_move_along_path(move_speed_u)

	if _reached(target) or nav_agent.is_navigation_finished():
		_search_queue.remove_at(0)


## Persigue el ultimo ruido a hunt_speed_u. Cada ruido nuevo reinicia el
## contador, asi que mientras sigas sonando NUNCA deja de cazarte.
func _tick_hunt(delta: float) -> void:
	nav_agent.target_position = last_heard_position
	_move_along_path(hunt_speed_u)

	_hunt_timer += delta
	if _hunt_timer >= hunt_persistence:
		_begin_search()


func _begin_search() -> void:
	_search_queue.clear()

	var map: RID = nav_agent.get_navigation_map()
	var radius_px := search_radius_u * PX_PER_UNIT

	for i in range(search_points):
		var angle := randf() * TAU
		# sqrt(randf()) reparte los puntos parejo por AREA, no por radio:
		# sin el, casi todos caerian pegados al centro.
		var dist := sqrt(randf()) * radius_px
		var raw := last_heard_position + Vector2(cos(angle), sin(angle)) * dist
		if map.is_valid():
			raw = NavigationServer2D.map_get_closest_point(map, raw)
		_search_queue.append(raw)

	_change_state(State.SEARCH)


# ------------------------------------------------------------------ oido ---

func _on_noise_emitted(noise_position: Vector2, radius: float, _source_type: int, _duration: float) -> void:
	if GameState.is_dead:
		return

	var distance := global_position.distance_to(noise_position)

	# Tope de seguridad. Nunca deberia cortar nada real.
	if distance > hearing_range_u * PX_PER_UNIT:
		return

	# Regla de la spec (step function, sin falloff), pero con las orejas
	# paradas si ya anda alerta.
	var effective_radius := radius
	if current_state == State.HUNT or current_state == State.SEARCH:
		effective_radius *= alert_hearing_multiplier

	if distance > effective_radius:
		return

	# Cualquier ruido que de verdad se oiga (ya paso el filtro de arriba) la
	# manda derecho a HUNT: una vez te oye, te sigue. Antes un paso suelto
	# solo la mandaba a INVESTIGATE (caminar a ese punto nada mas y
	# resignarse si no habia nadie), asi que alejarte justo despues de un
	# solo paso la despistaba sola. _start_hunt() ya renueva el temporizador
	# aunque ya este cazando, asi que cubre tambien el caso "ya te viene
	# cazando, esto solo confirma".
	last_heard_position = noise_position
	_start_hunt()


# ------------------------------------------------------------- movimiento ---

func _move_along_path(speed_u: float) -> void:
	if nav_agent.is_navigation_finished():
		_halt()
		return

	var next_path_position: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = (next_path_position - global_position).normalized()

	velocity = direction * speed_u * PX_PER_UNIT
	move_and_slide()


func _halt() -> void:
	velocity = Vector2.ZERO
	move_and_slide()


func _reached(point: Vector2) -> bool:
	return global_position.distance_to(point) <= arrival_threshold_u * PX_PER_UNIT


## Punto al azar de la malla navegable. Si todavia no esta horneada (nav_setup
## la hornea con call_deferred), ronda cerca del spawn para no quedarse tiesa.
func _random_map_point() -> Vector2:
	var map: RID = nav_agent.get_navigation_map()
	if map.is_valid():
		var p: Vector2 = NavigationServer2D.map_get_random_point(map, 1, false)
		if p != Vector2.ZERO:
			return p

	var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	return _spawn_position + offset * patrol_fallback_radius_u * PX_PER_UNIT


# ----------------------------------------------------------------- varios ---

func _on_catch_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_play_stinger(catch_clips)
		GameState.kill_player()


func _start_hunt() -> void:
	_hunt_timer = 0.0
	_change_state(State.HUNT)


func _change_state(new_state: int) -> void:
	if current_state == new_state:
		return

	var was_hunting := current_state == State.HUNT
	current_state = new_state
	_state_timer = 0.0

	if new_state == State.PATROL:
		_has_patrol_target = false

	_refresh_color()

	# La respiracion solo se REINICIA de golpe al cruzar la frontera
	# calma <-> caza: es el latido dramatico de "te encontre" / "te perdi".
	# Dentro de PATROL/INVESTIGATE/SEARCH sigue su propio bucle sin cortes.
	if new_state == State.HUNT and not was_hunting:
		_play_stinger(hunt_stinger_clips)
		_play_breath_clip()
	elif was_hunting and new_state != State.HUNT:
		_play_breath_clip()

	if log_state_changes:
		print("[EntityAI] Estado -> ", State.keys()[new_state])


## El greybox cambia de color segun el estado: gris apagado rondando, naranja
## investigando, amarillo buscando, rojo pleno cazando.
func _refresh_color() -> void:
	if not color_by_state or _sprite == null:
		return

	match current_state:
		State.PATROL:
			_sprite.modulate = Color(0.45, 0.20, 0.20)
		State.INVESTIGATE:
			_sprite.modulate = Color(0.95, 0.50, 0.15)
		State.SEARCH:
			_sprite.modulate = Color(1.00, 0.85, 0.20)
		State.HUNT:
			_sprite.modulate = Color(1.00, 0.10, 0.10)


func get_state_name() -> String:
	return State.keys()[current_state]


# ------------------------------------------------------------------ audio ---

## Respiracion en bucle: cada vez que un clip termina, encadena el siguiente
## (con la lista de calma o de caza segun el estado ACTUAL, leido en ese
## instante). Asi un cambio de estado a mitad de clip se refleja solo en el
## proximo ciclo, salvo en la frontera calma<->caza que se fuerza al toque.
func _play_breath_clip() -> void:
	if GameState.is_dead:
		return

	var hunting := current_state == State.HUNT
	# Si todavia no hay un clip DEDICADO de caza, reusa el de calma: igual
	# suena distinto porque el volumen y el pitch ya suben mas abajo.
	var clips := breath_hunt_clips if (hunting and not breath_hunt_clips.is_empty()) else breath_calm_clips
	if clips.is_empty():
		return

	_breath_player.volume_db = breath_volume_db + (hunt_breath_volume_boost_db if hunting else 0.0)
	_breath_player.pitch_scale = 1.15 if hunting else 1.0
	_breath_player.stream = clips[randi() % clips.size()]
	_breath_player.play()


func _on_breath_finished() -> void:
	_play_breath_clip()


func _play_stinger(clips: Array[AudioStream]) -> void:
	if clips.is_empty():
		return
	_stinger_player.volume_db = stinger_volume_db
	_stinger_player.stream = clips[randi() % clips.size()]
	_stinger_player.play()
