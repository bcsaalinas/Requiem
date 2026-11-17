extends CharacterBody2D
## Real noise attracts a human listener; only unobstructed vision tracks the player.
signal caught
signal spotted
@export var patrol_offsets: Array[Vector2] = [Vector2.ZERO, Vector2(-50,120), Vector2(-110,30)]
@export var sight_range := 260.0
@export var sight_half_angle := 48.0
@export var chase_speed := 125.0
var active := false
var distracted := false
var stone_distraction_completed := false
var target := Vector2.ZERO
var home := Vector2.ZERO
var investigating := false
var chasing := false
var wait_left := 0.0
var patrol_index := 0
var travel_time := 0.0
var gait_phase := 0.0
var facing := Vector2.DOWN
var lesson_waiting := true
var _stone_target := false
var _lost_sight := 0.0
var _player: Node2D
@onready var agent: NavigationAgent2D = $NavigationAgent2D

func _ready() -> void:
	home = global_position
	target = home
	NoiseManager.noise_emitted.connect(_hear)

func reset_patrol() -> void:
	global_position = home
	target = home
	agent.target_position = home
	velocity = Vector2.ZERO
	facing = Vector2.RIGHT
	lesson_waiting = true
	investigating = false
	chasing = false
	distracted = false
	stone_distraction_completed = false
	_stone_target = false
	_lost_sight = 0.0
	wait_left = 1.0
	patrol_index = 0
	travel_time = 0.0

func _hear(at: Vector2, radius: float, source: int, _duration: float) -> void:
	if not active: return
	# A stone can interrupt a search after losing sight, even during pursuit persistence.
	if chasing and (source != NoiseManager.SourceType.THROW or can_see_player()): return
	if global_position.distance_to(at) > radius: return
	chasing = false
	_lost_sight = 0.0
	target = at
	agent.target_position = at
	investigating = true
	distracted = false
	_stone_target = source == NoiseManager.SourceType.THROW and at.distance_to(home) >= 75.0
	if _stone_target: lesson_waiting = false
	facing = global_position.direction_to(at)
	$Appearance.heard_noise()
	wait_left = 0.6
	travel_time = 0.0

func can_see_player() -> bool:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null or not _player.can_process(): return false
	var difference := _player.global_position - global_position
	if difference.length() > sight_range: return false
	if difference.length() > 25.0 and facing.dot(difference.normalized()) < cos(deg_to_rad(sight_half_angle)): return false
	var query := PhysicsRayQueryParameters2D.create(global_position,_player.global_position,1)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == _player

func _physics_process(delta: float) -> void:
	velocity = Vector2.ZERO
	if active and NavigationServer2D.map_get_iteration_id(agent.get_navigation_map()) > 0:
		var sees := can_see_player()
		if sees:
			if not chasing:
				spotted.emit()
				$Appearance.noticed()
			chasing = true
			distracted = false
			_stone_target = false
			_lost_sight = 0.0
			target = _player.global_position
			agent.target_position = target
			wait_left = 0.0
			if global_position.distance_to(target) < 28.0:
				active = false
				caught.emit()
				return
		elif chasing:
			_lost_sight += delta
			if _lost_sight > 2.0:
				chasing = false
				investigating = true
		if wait_left > 0.0:
			wait_left -= delta
		elif global_position.distance_to(target) < 25.0:
			if investigating and not chasing:
				distracted = _stone_target
				if distracted: stone_distraction_completed = true
				investigating = false
				wait_left = 12.0 if distracted else 2.5
			elif not chasing:
				_next_patrol()
		elif not agent.is_navigation_finished():
			velocity = global_position.direction_to(agent.get_next_path_position()) * (chase_speed if chasing else (70.0 if investigating else 42.0))
			move_and_slide()
			travel_time += delta
			if travel_time > 8.0 and not investigating and not chasing: _next_patrol()
		elif not chasing:
			# An unreachable impact must never leave the patrol stuck indefinitely.
			travel_time += delta
			if travel_time > 4.0:
				investigating = false
				_next_patrol()
	var moving := velocity.length() > 2.0
	if moving:
		facing = velocity.normalized()
		gait_phase = fmod(gait_phase + velocity.length() * delta / 64.0,1.0)
	$Appearance.present(delta)

func _next_patrol() -> void:
	if lesson_waiting:
		facing = Vector2.RIGHT
		target = home
		agent.target_position = home
		wait_left = 0.5
		return
	if patrol_offsets.is_empty(): return
	distracted = false
	_stone_target = false
	patrol_index = (patrol_index + 1) % patrol_offsets.size()
	target = home + patrol_offsets[patrol_index]
	agent.target_position = target
	wait_left = 1.0
	travel_time = 0.0

func set_focused(value: bool) -> void:
	$Appearance.set_focused(value)
