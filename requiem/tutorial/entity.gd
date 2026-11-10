extends "res://entities/entity_ai.gd"
## The house entity of the tutorial. Hearing, hunt speed (3.9 u/s), hunt persistence (5 s) and the
## rule "it goes to the exact place a sound came from, never to the player" come from EntityAI.
## This layer only makes that rule readable and the creature less predictable:
## - it freezes and turns toward a new sound before it moves (the listening tell),
## - its breathing stops while it listens and a dragging loop follows it while it moves,
## - every sound it hears is reported (heard_noise) with the spot it now walks to,
## - patrols pick random points, sometimes the place it last heard something, with uneven pauses.
signal caught
## Emitted with the exact position it now walks to.
signal heard_noise(at: Vector2, source: int)

@export_group("Readability")
## Seconds it stands still, turned toward a new sound, before it starts the hunt.
@export_range(0.0, 2.0, 0.05) var listen_time := 0.7
## Hearing multiplier while it is not yet alert (EntityAI already applies 1.6 while alert).
@export_range(1.0, 2.0, 0.05) var calm_hearing_multiplier := 1.25
@export_group("Patrol")
## Random pause range at each patrol point, in seconds.
@export var patrol_pause_range := Vector2(0.9, 2.8)
## Chance that the next patrol point is a place where it heard something before.
@export_range(0.0, 1.0, 0.05) var revisit_chance := 0.35
@export_group("Audio")
@export var drag_clip: AudioStream = preload("res://tutorial/assets/audio/behind_wall.wav")
@export var drag_volume_db := -14.0

var route: Array[Vector2] = []
var route_index := 0
var active := false
var appearance: Node2D
## Source type of the last sound it heard (for the "it heard your ..." explanation).
var last_heard_source := -1
var _listening := 0.0
var _memory: Array[Vector2] = []
var _drag: AudioStreamPlayer2D
var _sway := 0.0

func _ready() -> void:
	super._ready()
	_sprite.hide()
	appearance = $Appearance
	color_by_state = false
	log_state_changes = false
	_drag = AudioStreamPlayer2D.new()
	_drag.stream = drag_clip
	_drag.volume_db = drag_volume_db
	_drag.max_distance = 900.0
	add_child(_drag)

func _physics_process(delta: float) -> void:
	_update_readability()
	if not active:
		velocity = Vector2.ZERO
		_update_drag(false)
		return
	if _listening > 0.0:
		_listening -= delta
		_halt()
		_update_drag(false)
		if _listening <= 0.0 and not GameState.is_dead:
			_resume_breathing()
			_start_hunt()
		return
	super._physics_process(delta)
	_update_drag(velocity.length() > 4.0)
	_update_pose(delta)

## Hearing keeps EntityAI's step rule (heard when the distance is within the sound's radius),
## with a calm multiplier on top; a new sound first triggers the listening tell.
func _on_noise_emitted(at: Vector2, radius: float, source: int, _duration: float) -> void:
	if not active or GameState.is_dead:
		return
	if global_position.distance_to(at) > hearing_range_u * PX_PER_UNIT:
		return
	if global_position.distance_to(at) > radius * hearing_multiplier():
		return
	last_heard_position = at
	last_heard_source = source
	_remember(at)
	heard_noise.emit(at, source)
	if current_state == State.HUNT or _listening > 0.0:
		if current_state == State.HUNT:
			_start_hunt()
		return
	# Its breathing stops while it listens: the silence is the tell. The hunt stinger follows.
	_listening = listen_time
	_breath_player.stop()
	if listen_time <= 0.0:
		_listening = 0.0
		_resume_breathing()
		_start_hunt()

## Multiplier applied to a sound's radius at this moment (x1.6 while it hunts or searches).
func hearing_multiplier() -> float:
	if current_state == State.HUNT or current_state == State.SEARCH:
		return alert_hearing_multiplier
	return calm_hearing_multiplier

func is_listening() -> bool:
	return _listening > 0.0

func _tick_patrol(delta: float) -> void:
	if route.is_empty(): return
	if _patrol_wait > 0:
		_patrol_wait -= delta
		_halt()
		return
	nav_agent.target_position = route[route_index]
	_move_along_path(patrol_speed_u)
	if _reached(route[route_index]) or nav_agent.is_navigation_finished():
		_pick_next_patrol_point()
		_patrol_wait = randf_range(patrol_pause_range.x, patrol_pause_range.y)

## Random point of the route, or a place it heard something; never the same point twice in a row.
func _pick_next_patrol_point() -> void:
	if not _memory.is_empty() and randf() < revisit_chance:
		route[route_index] = _memory.pick_random()
		return
	var previous := route_index
	if route.size() > 1:
		while route_index == previous:
			route_index = randi() % route.size()

func _remember(at: Vector2) -> void:
	_memory.append(at)
	if _memory.size() > 4:
		_memory.pop_front()

func _resume_breathing() -> void:
	if not _breath_player.playing:
		_play_breath_clip()

func _update_drag(moving: bool) -> void:
	if moving and not _drag.playing and drag_clip != null:
		_drag.pitch_scale = randf_range(0.8, 0.95)
		_drag.play()
	elif not moving and _drag.playing:
		_drag.stop()

## A slow sway while it walks, a jerk toward the sound while it listens.
func _update_pose(delta: float) -> void:
	_sway += delta * (5.0 if current_state == State.HUNT else 2.2)
	appearance.rotation = sin(_sway) * 0.06

func _on_catch_area_body_entered(body: Node2D) -> void:
	if active and body.is_in_group("player"):
		_play_stinger(catch_clips)
		caught.emit()

func reset_encounter(at: Vector2, points: Array[Vector2]) -> void:
	global_position = at
	route = points.duplicate()
	route_index = 0
	velocity = Vector2.ZERO
	_search_queue.clear()
	_memory.clear()
	_listening = 0.0
	_hunt_timer = 0.0
	_state_timer = 0.0
	_patrol_wait = 1.5
	last_heard_source = -1
	_change_state(State.PATROL)
	active = false

func _update_readability() -> void:
	var pressure := 0.0
	var observer := get_tree().get_first_node_in_group("player") as Node2D
	if active and visible and is_instance_valid(observer):
		var distance := global_position.distance_to(observer.global_position)
		if distance<7.0*PX_PER_UNIT:
			var query := PhysicsRayQueryParameters2D.create(observer.global_position,global_position,1)
			query.exclude = [observer.get_rid(),get_rid()]
			if get_world_2d().direct_space_state.intersect_ray(query).is_empty():
				pressure=1.0-smoothstep(2.0*PX_PER_UNIT,7.0*PX_PER_UNIT,distance)
	appearance.set_threat_pressure(maxf(pressure, 0.6 if _listening > 0.0 and pressure > 0.0 else 0.0))
	# The listening tell: it turns its body toward the sound before it moves.
	if _listening > 0.0:
		var to_sound := last_heard_position - global_position
		if to_sound.length() > 1.0:
			appearance.rotation = lerp_angle(appearance.rotation, clampf(to_sound.angle() - PI * 0.5, -0.5, 0.5), 0.2)
