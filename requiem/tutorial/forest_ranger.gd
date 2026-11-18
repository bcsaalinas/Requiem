extends CharacterBody2D
## The trail warden. He walks an authored beat (the Marker2D children of `patrol_path`, in order,
## there and back), stops at the posts to sweep his torch, and sees exactly what his beam lights:
## a player inside the cone with a clear line starts a chase. Noise still pulls him off the beat.
signal caught
signal spotted
## Marker2D children are the beat, walked in order and then back again. A marker's rotation is
## where he looks while he waits there; its "pause" metadata is how long (seconds; 0 walks through).
@export var patrol_path: NodePath
## Reach and half angle of his sight. RangerVisual draws the torch beam to this exact cone.
@export var sight_range := 284.0
@export_range(5.0, 80.0) var sight_half_angle := 24.0
## Seconds at the far end of the beam before he is sure. Right in front of him it is instant.
@export var notice_seconds := 0.45
## Once he is chasing he also keeps track of anyone this close, in the beam or not.
@export var chase_near_radius := 80.0
@export var patrol_speed := 42.0
@export var investigate_speed := 70.0
@export var chase_speed := 125.0

## Inside this distance of the beam's start there is no doubt at all.
const NOTICE_INSTANT_DISTANCE := 70.0
const TOUCH_DISTANCE := 25.0
const ARRIVE_DISTANCE := 25.0
## While a stone has his attention he hears only this fraction of a noise's reach: a walk has to
## be almost on top of him, a sprint still carries. This is what makes the stone open the trail.
const STONE_FOCUS_HEARING := 0.34

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
## How long the player has been in the beam without him being sure yet.
var suspicion := 0.0
var _posts: Array[Dictionary] = []
var _patrol_step := 1
## True while he walks to a post he has not yet stopped at.
var _post_pending := false
var _stone_target := false
var _lost_sight := 0.0
var _player: Node2D
@onready var agent: NavigationAgent2D = $NavigationAgent2D

func _ready() -> void:
	home = global_position
	target = home
	_read_posts()
	NoiseManager.noise_emitted.connect(_hear)

## The beat always starts at his own position; markers add the rest of the route.
func _read_posts() -> void:
	_posts.clear()
	var path := get_node_or_null(patrol_path)
	if path != null:
		for child in path.get_children():
			if child is Marker2D:
				_posts.append({"position": child.global_position, "look": Vector2.from_angle(child.global_rotation),
					"pause": float(child.get_meta("pause", 0.0))})
	if _posts.is_empty():
		_posts.append({"position": home, "look": Vector2.RIGHT, "pause": 1.0})

func reset_patrol() -> void:
	global_position = home
	target = home
	agent.target_position = home
	velocity = Vector2.ZERO
	facing = _posts[0]["look"]
	investigating = false
	chasing = false
	distracted = false
	stone_distraction_completed = false
	suspicion = 0.0
	_stone_target = false
	_lost_sight = 0.0
	wait_left = maxf(_posts[0]["pause"], 1.0)
	patrol_index = 0
	_patrol_step = 1
	_post_pending = false
	travel_time = 0.0
	if has_node("Appearance"): $Appearance.snap_to_facing()

func _hear(at: Vector2, radius: float, source: int, _duration: float) -> void:
	if not active: return
	# A stone can interrupt a search after losing sight, even during pursuit persistence.
	if chasing and (source != NoiseManager.SourceType.THROW or can_see_player()): return
	var busy_with_stone := _stone_target and (investigating or distracted) and source != NoiseManager.SourceType.THROW
	if global_position.distance_to(at) > radius * (STONE_FOCUS_HEARING if busy_with_stone else 1.0): return
	chasing = false
	_lost_sight = 0.0
	target = at
	agent.target_position = at
	investigating = true
	distracted = false
	_post_pending = false
	_stone_target = source == NoiseManager.SourceType.THROW and at.distance_to(home) >= 75.0
	facing = global_position.direction_to(at)
	$Appearance.heard_noise()
	wait_left = 0.6
	travel_time = 0.0

## Where the beam starts and where it points: the drawn torch when there is one.
func beam_origin() -> Vector2:
	return $Appearance.beam_origin() if has_node("Appearance") else global_position

func beam_direction() -> Vector2:
	return $Appearance.beam_direction() if has_node("Appearance") else facing

## True when the point sits inside the lit cone (no walls considered).
func in_beam(point: Vector2) -> bool:
	var from_torch := point - beam_origin()
	var distance := from_torch.length()
	if distance > sight_range: return false
	return distance < 1.0 or beam_direction().dot(from_torch / distance) >= cos(deg_to_rad(sight_half_angle))

func can_see_player() -> bool:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null or not _player.can_process(): return false
	var at := _player.global_position
	var from_body := global_position.distance_to(at)
	if from_body > TOUCH_DISTANCE and not in_beam(at) and not (chasing and from_body <= chase_near_radius):
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, at, 1)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == _player

## A glimpse at the end of the beam takes a moment to register; up close there is no doubt.
func _is_sure(delta: float) -> bool:
	if chasing: return true
	suspicion += delta
	var distance := beam_origin().distance_to(_player.global_position)
	var needed := notice_seconds * clampf((distance - NOTICE_INSTANT_DISTANCE) / maxf(sight_range - NOTICE_INSTANT_DISTANCE, 1.0), 0.0, 1.0)
	return suspicion >= needed

func _physics_process(delta: float) -> void:
	velocity = Vector2.ZERO
	if active and NavigationServer2D.map_get_iteration_id(agent.get_navigation_map()) > 0:
		var sees := can_see_player()
		if not sees: suspicion = maxf(suspicion - delta * 2.0, 0.0)
		if sees and _is_sure(delta):
			if not chasing:
				spotted.emit()
				$Appearance.noticed()
			chasing = true
			investigating = false
			distracted = false
			_stone_target = false
			_post_pending = false
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
				suspicion = 0.0
		if wait_left > 0.0:
			wait_left -= delta
		elif global_position.distance_to(target) < ARRIVE_DISTANCE:
			if chasing:
				pass
			elif investigating:
				distracted = _stone_target
				if distracted: stone_distraction_completed = true
				investigating = false
				wait_left = 12.0 if distracted else 2.5
			elif _post_pending:
				_stop_at_post()
			else:
				_next_patrol()
		elif not agent.is_navigation_finished():
			velocity = global_position.direction_to(agent.get_next_path_position()) * (chase_speed if chasing else (investigate_speed if investigating else patrol_speed))
			move_and_slide()
			travel_time += delta
			if travel_time > 12.0 and not investigating and not chasing: _next_patrol(true)
		elif not chasing:
			# An unreachable impact must never leave the patrol stuck indefinitely.
			travel_time += delta
			if travel_time > 4.0:
				investigating = false
				_next_patrol(true)
	var moving := velocity.length() > 2.0
	if moving:
		facing = velocity.normalized()
		gait_phase = fmod(gait_phase + velocity.length() * delta / 64.0,1.0)
	$Appearance.present(delta)

## At a post he looks where the marker points for as long as it says, sweeping the torch.
func _stop_at_post() -> void:
	_post_pending = false
	var post: Dictionary = _posts[patrol_index]
	if post["pause"] > 0.0:
		facing = post["look"]
		wait_left = post["pause"]

## Walks on to the next post of the beat. After a search or a stone he rejoins the beat at the
## post he was heading for, so the route stays the one the player has been watching.
## `skip` gives up on a post he cannot reach and moves to the one after it.
func _next_patrol(skip := false) -> void:
	var rejoining := not skip and (distracted or _stone_target
		or global_position.distance_to(_posts[patrol_index]["position"]) > ARRIVE_DISTANCE * 2.0)
	distracted = false
	_stone_target = false
	travel_time = 0.0
	if not rejoining and _posts.size() > 1:
		if patrol_index + _patrol_step < 0 or patrol_index + _patrol_step >= _posts.size():
			_patrol_step = -_patrol_step
		patrol_index += _patrol_step
	elif not rejoining:
		wait_left = 0.5
		return
	target = _posts[patrol_index]["position"]
	agent.target_position = target
	_post_pending = true

func set_focused(value: bool) -> void:
	$Appearance.set_focused(value)
