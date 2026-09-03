extends CharacterBody2D

# EntityAI (la entidad que te caza)
#
# Maquina de CUATRO estados. Cada uno tiene su propia velocidad y su propia
# forma de oir:
#
#   PATROL      - Ronda el nivel por puntos al azar de la malla navegable.
#                 Lenta. Es el estado "no sabe que existes". Antes esto era
#                 IDLE y la entidad se quedaba parada para siempre.
#   INVESTIGATE - Oyo algo. Camina al punto exacto donde sono.
#   SEARCH      - Llego y no habia nadie. Revisa varios puntos alrededor antes
#                 de rendirse. Antes se rendia en el instante de llegar.
#   HUNT        - Sabe que estas ahi. Es MAS RAPIDA QUE TU CAMINANDO (3.9 vs
#                 3.2 u/s), asi que no puedes zafarte andando: o esprintas y
#                 pagas agotamiento, o le cortas el rastro de ruido.
#
# OIDO: la regla base es la de la spec, sin falloff: te oye si
# distance <= radius del ruido. Encima de eso hay dos capas:
#
#   - hearing_range_u: tope duro de seguridad, MUY por encima del radio mas
#     grande del juego (8 u). En la practica nunca corta nada; existe para que
#     un radio absurdo por bug no se oiga desde el otro extremo del mapa.
#
#   - alert_hearing_multiplier: mientras CAZA o BUSCA, oye los mismos ruidos
#     como si fueran mas grandes. Estar en su radar te vuelve mas ruidoso: es
#     la espiral que tienes que romper quedandote quieto o aguantando la
#     respiracion.
#
# UNIDADES: 1 u = 32 px, misma convencion que player.gd. TODO radio, distancia
# y velocidad se exporta en unidades. Ya no queda un solo pixel crudo aqui.
const PX_PER_UNIT: float = 32.0

enum State { PATROL, INVESTIGATE, SEARCH, HUNT }

@export_group("Oido (u)")
## Tope de seguridad, no una mecanica: esta por encima de todo radio real.
@export var hearing_range_u: float = 40.0
## Un ruido con radio >= esto la manda directo a HUNT, sin pasar por investigar.
@export var hunt_trigger_radius_u: float = 6.0
## Rezar a menos de esto = te ubico seguro (spec: 4 u).
@export var pray_hunt_radius_u: float = 4.0
## Mientras CAZA o BUSCA, multiplica el radio de todo ruido que le llega.
@export var alert_hearing_multiplier: float = 1.6

@export_group("Memoria")
## Varios ruidos dentro de esta ventana escalan INVESTIGATE -> HUNT.
@export var escalation_window: float = 6.0
## Cuantos ruidos hacen falta dentro de la ventana para escalar.
@export var escalation_noise_count: int = 3

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

var current_state: int = State.PATROL
var last_heard_position: Vector2 = Vector2.ZERO
var nav_agent: NavigationAgent2D

var _sprite: Sprite2D
var _spawn_position: Vector2
var _state_timer: float = 0.0
var _hunt_timer: float = 0.0
var _patrol_target: Vector2 = Vector2.ZERO
var _has_patrol_target: bool = false
var _patrol_wait: float = 0.0
var _search_queue: Array[Vector2] = []
## Marcas de tiempo (s) de los ruidos recientes, para la escalada por memoria.
var _recent_noises: Array[float] = []


func _ready() -> void:
	_spawn_position = global_position

	_sprite = Sprite2D.new()
	var greybox_texture = PlaceholderTexture2D.new()
	greybox_texture.size = Vector2(32, 32)
	_sprite.texture = greybox_texture
	add_child(_sprite)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(26, 26)
	collision.shape = shape
	add_child(collision)

	nav_agent = NavigationAgent2D.new()
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = arrival_threshold_u * PX_PER_UNIT
	add_child(nav_agent)

	var catch_area = Area2D.new()
	var catch_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = catch_radius_u * PX_PER_UNIT
	catch_shape.shape = circle
	catch_area.add_child(catch_shape)
	add_child(catch_area)
	catch_area.body_entered.connect(_on_catch_area_body_entered)

	NoiseManager.noise_emitted.connect(_on_noise_emitted)
	_refresh_color()


func _physics_process(delta: float) -> void:
	if GameState.is_dead:
		_halt()
		return

	_forget_old_noises()

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

func _on_noise_emitted(noise_position: Vector2, radius: float, source_type: int, _duration: float) -> void:
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

	last_heard_position = noise_position
	_recent_noises.append(_now())

	# Rezar cerca = te ubico seguro, pase lo que pase (spec: 4 u).
	if source_type == NoiseManager.SourceType.PRAY and distance <= pray_hunt_radius_u * PX_PER_UNIT:
		_start_hunt()
		return

	# Un solo ruido fuerte basta.
	if radius >= hunt_trigger_radius_u * PX_PER_UNIT:
		_start_hunt()
		return

	# Varios ruidos chicos seguidos tambien: te triangulo.
	if _recent_noises.size() >= escalation_noise_count:
		_start_hunt()
		return

	# Ya te viene cazando: el ruido solo le renueva la certeza.
	if current_state == State.HUNT:
		_hunt_timer = 0.0
		return

	_change_state(State.INVESTIGATE)


func _forget_old_noises() -> void:
	var cutoff := _now() - escalation_window
	while not _recent_noises.is_empty() and _recent_noises[0] < cutoff:
		_recent_noises.remove_at(0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


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
		GameState.kill_player()


func _start_hunt() -> void:
	_hunt_timer = 0.0
	_change_state(State.HUNT)


func _change_state(new_state: int) -> void:
	if current_state == new_state:
		return

	current_state = new_state
	_state_timer = 0.0

	if new_state == State.PATROL:
		_has_patrol_target = false
		_recent_noises.clear()

	_refresh_color()

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
