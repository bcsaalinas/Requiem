extends "res://entities/entity_ai.gd"
## The house entity of the tutorial, La Amortajada: a crouched figure in a burial shroud, blind,
## seen from straight above. Hearing, hunt speed (3.9 u/s), hunt persistence (5 s) and the rule
## "it goes to the exact place a sound came from, never to the player" come from EntityAI. This
## layer only makes that rule readable:
## - it is drawn only where a real light lands on it (entity_lit.gdshader, light layer 3),
## - the sprite rig (entity_sprite_rig.gd) shows each state with the entity-lab clips: walk, idle
##   looks, listen (ear toward the sound), the scream, pursuit, feeling the floor, scuttle, catch,
## - it freezes, head cocked toward a new sound, before it moves (the listening tell),
## - a hunt starts with a scream it stands still for (hunt_start_hold): the player's warning,
## - light means nothing to it: it reacts to the flashlight's click, never to its beam,
## - where a hunt ends it feels the floor for the sound, not for you,
## - its breathing stops while it listens and a dragging loop follows it while it moves,
## - every sound it hears is reported (heard_noise) with the spot it now walks to,
## - patrols pick random points, sometimes the place it last heard something, with uneven pauses.
signal caught
## Emitted with the exact position it now walks to.
signal heard_noise(at: Vector2, source: int)

@export_group("Readability")
## Random range (s) it stands still, head turned toward a new sound, before it starts the hunt.
@export var listen_time_range := Vector2(0.7, 1.2)
## Hearing multiplier while it is not yet alert (EntityAI already applies 1.6 while alert).
@export_range(1.0, 2.0, 0.05) var calm_hearing_multiplier := 1.25
## Seconds it screams standing still when a hunt starts, before it runs (hunt_start clip: 1.3 s).
@export_range(0.0, 2.0, 0.05) var hunt_start_hold := 1.3
## Seconds from the catch to the game over screen: the grab and fold (1.34 s) and a beat of stillness.
@export_range(0.0, 4.0, 0.05) var catch_screen_delay := 1.9
@export_group("Floor feeling")
## Seconds it feels the floor at each SEARCH point (counted inside search_duration).
@export_range(0.0, 3.0, 0.05) var search_feel_time := 1.2
@export_group("Patrol")
## Random pause range at each patrol point, in seconds.
@export var patrol_pause_range := Vector2(0.9, 2.8)
## Chance that the next patrol point is a place where it heard something before.
@export_range(0.0, 1.0, 0.05) var revisit_chance := 0.35
@export_group("Audio")
@export var drag_clip: AudioStream = preload("res://tutorial/assets/audio/behind_wall.wav")
@export var drag_volume_db := -14.0
## Optional soft pat/tap while it feels the floor (empty: silent).
@export var feel_clip: AudioStream
@export var feel_volume_db := -20.0
## Random seconds between two pats.
@export var feel_tap_interval := Vector2(0.5, 1.0)

var route: Array[Vector2] = []
var route_index := 0
var active := false
## The sprite rig that draws it (child SpriteRig, entity_sprite_rig.gd).
var sprite_rig: Node2D
## Source type of the last sound it heard (for the "it heard your ..." explanation).
var last_heard_source := -1
var _listening := 0.0
var _scream_left := 0.0
var _memory: Array[Vector2] = []
var _drag: AudioStreamPlayer2D
var _feel_player: AudioStreamPlayer2D
var _feel_left := 0.0
var _tap_wait := 0.0

func _ready() -> void:
	super._ready()
	_sprite.hide()
	sprite_rig = $SpriteRig
	color_by_state = false
	log_state_changes = false
	_drag = AudioStreamPlayer2D.new()
	_drag.stream = drag_clip
	_drag.volume_db = drag_volume_db
	_drag.max_distance = 900.0
	add_child(_drag)
	_feel_player = AudioStreamPlayer2D.new()
	_feel_player.stream = feel_clip
	_feel_player.volume_db = feel_volume_db
	_feel_player.max_distance = 600.0
	add_child(_feel_player)

func _physics_process(delta: float) -> void:
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
	# The scream: it stands still, then runs. The stop is the player's warning.
	if _scream_left > 0.0 and not GameState.is_dead:
		_scream_left -= delta
		_halt()
		_update_drag(false)
		return
	super._physics_process(delta)
	_update_drag(velocity.length() > 4.0)
	_update_feel_audio(delta)

## A new hunt starts with the scream hold; a hunt that only changes target does not.
func _start_hunt() -> void:
	var was_hunting := current_state == State.HUNT
	super._start_hunt()
	if not was_hunting:
		_scream_left = hunt_start_hold

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
	_feel_left = 0.0
	_remember(at)
	heard_noise.emit(at, source)
	if current_state == State.HUNT or _listening > 0.0:
		if current_state == State.HUNT:
			_start_hunt()
		return
	# Its breathing stops while it listens: the silence is the tell. The hunt stinger follows.
	_listening = randf_range(listen_time_range.x, listen_time_range.y)
	_breath_player.stop()
	if _listening <= 0.0:
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

## True during the scream hold that starts a hunt.
func is_screaming() -> bool:
	return _scream_left > 0.0 and active

## It stands where the sound was and feels the floor for it: the end of a hunt that reached
## the spot (until hunt_persistence runs out) and a moment at each search point.
func is_feeling() -> bool:
	if not active or _listening > 0.0:
		return false
	if current_state == State.SEARCH:
		return _feel_left > 0.0
	return current_state == State.HUNT and nav_agent.is_navigation_finished()

## The lethal contact: it stops, faces the player and plays the catch (the caller stops the AI).
func play_catch(target: Vector2) -> void:
	_scream_left = 0.0
	_listening = 0.0
	velocity = Vector2.ZERO
	_update_drag(false)
	sprite_rig.play_catch(target)

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

## EntityAI's search, plus a moment of floor feeling at each point; search_duration still ends it.
func _tick_search(delta: float) -> void:
	if _feel_left > 0.0:
		_feel_left -= delta
		_state_timer += delta
		_halt()
		if _state_timer >= search_duration:
			_change_state(State.PATROL)
		return
	var remaining := _search_queue.size()
	super._tick_search(delta)
	if current_state == State.SEARCH and _search_queue.size() < remaining:
		_feel_left = search_feel_time

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

func _update_feel_audio(delta: float) -> void:
	if feel_clip == null or not is_feeling():
		_tap_wait = 0.3
		return
	_tap_wait -= delta
	if _tap_wait <= 0.0:
		_feel_player.pitch_scale = randf_range(0.85, 1.1)
		_feel_player.play()
		_tap_wait = randf_range(feel_tap_interval.x, feel_tap_interval.y)

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
	_scream_left = 0.0
	_hunt_timer = 0.0
	_state_timer = 0.0
	_patrol_wait = 1.5
	last_heard_source = -1
	_change_state(State.PATROL)
	active = false
	_feel_left = 0.0
	sprite_rig.reset()
