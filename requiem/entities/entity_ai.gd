extends CharacterBody2D

enum State { IDLE, INVESTIGATE, HUNT }

# UNIDADES: 1 u = 32 px, misma convencion que player.gd.
const PX_PER_UNIT: float = 32.0

@export_group("Oido")
@export var hearing_range: float = 1500.0

@export_group("Investigacion")
@export var investigate_timeout: float = 6.0
@export var arrival_threshold: float = 8.0

@export_group("Movimiento")
## Velocidad de la Entity en unidades por segundo. 3.0 u = exactamente la misma
## que el jugador caminando (walk_speed_u en player.gd): decision de diseño,
## no un placeholder. Se convierte a px/s con PX_PER_UNIT al moverse.
@export var move_speed_u: float = 3.0

@export_group("Cacería")
@export var catch_radius: float = 20.0

@export_group("Debug")
@export var log_state_changes: bool = true

var current_state: int = State.IDLE
var last_heard_position: Vector2 = Vector2.ZERO
var investigate_timer: float = 0.0
var nav_agent: NavigationAgent2D


func _ready() -> void:
	var sprite = Sprite2D.new()
	var greybox_texture = PlaceholderTexture2D.new()
	greybox_texture.size = Vector2(32, 32)
	sprite.texture = greybox_texture
	sprite.modulate = Color(0.9, 0.15, 0.15)
	add_child(sprite)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(26, 26)
	collision.shape = shape
	add_child(collision)

	nav_agent = NavigationAgent2D.new()
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = arrival_threshold
	add_child(nav_agent)

	var catch_area = Area2D.new()
	var catch_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = catch_radius
	catch_shape.shape = circle
	catch_area.add_child(catch_shape)
	add_child(catch_area)
	catch_area.body_entered.connect(_on_catch_area_body_entered)

	NoiseManager.noise_emitted.connect(_on_noise_emitted)


func _physics_process(delta: float) -> void:
	if GameState.is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
			move_and_slide()
		State.INVESTIGATE:
			_tick_investigate(delta)
		State.HUNT:
			nav_agent.target_position = last_heard_position
			_move_along_path()


func _on_catch_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		GameState.kill_player()


func _on_noise_emitted(noise_position: Vector2, radius: float, source_type: int, _duration: float) -> void:
	if GameState.is_dead:
		return

	var distance := global_position.distance_to(noise_position)
	var within_hearing := distance <= hearing_range
	var within_radius := distance <= radius

	if not within_hearing or not within_radius:
		return

	last_heard_position = noise_position

	if source_type == NoiseManager.SourceType.PRAY and distance <= 250.0:
		_change_state(State.HUNT)
		return

	if current_state != State.HUNT:
		_change_state(State.INVESTIGATE)

	investigate_timer = 0.0


func _tick_investigate(delta: float) -> void:
	nav_agent.target_position = last_heard_position
	_move_along_path()
	investigate_timer += delta

	var arrived := global_position.distance_to(last_heard_position) <= arrival_threshold

	if arrived or investigate_timer >= investigate_timeout:
		_change_state(State.IDLE)


func _move_along_path() -> void:
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var next_path_position: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = (next_path_position - global_position).normalized()

	velocity = direction * move_speed_u * PX_PER_UNIT
	move_and_slide()


func _change_state(new_state: int) -> void:
	if current_state == new_state:
		return

	current_state = new_state
	investigate_timer = 0.0

	if log_state_changes:
		print("[EntityAI] Estado -> ", State.keys()[new_state])


func get_state_name() -> String:
	return State.keys()[current_state]
