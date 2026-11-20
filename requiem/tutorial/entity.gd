extends "res://entities/entity_ai.gd"
## The house entity of the tutorial, La Amortajada: a crouched figure in a burial shroud, blind,
## seen from straight above. Hearing (two certainties, through doorways), the check, the hunt
## (3.9 u/s, never abandoned before the spot) and the rule "it goes to the place a sound came
## from, never to the player" come from EntityAI. This layer makes that rule readable, and it
## owns the one decision the player can act on:
## - LISTENING IS THE DECISION. Whatever it hears, it first freezes with its head cocked to the
##   sound (the click). A clearly-heard sound ends in the scream and a hunt. A barely-heard one
##   ends in a check, with no scream, unless it hears a second sound once second_strike_grace
##   has passed: the second noise is the one that gets you. While it checks or searches, every
##   sound it can hear ends in a hunt.
## - it is drawn only where a real light lands on it (entity_lit.gdshader, light layer 3),
## - the sprite rig (entity_sprite_rig.gd) shows each state with the entity-lab clips: walk, idle
##   looks, listen (ear toward the sound), the scream, pursuit, feeling the floor, scuttle, catch,
## - a hunt starts with a scream it stands still for (hunt_start_hold): the player's warning,
## - light means nothing to it: it reacts to the flashlight's click, never to its beam,
## - where a hunt or a check ends it feels the floor for the sound, not for you,
## - its breathing stops while it listens and a dragging loop follows it while it moves,
## - every sound it hears is reported (heard_noise) with the spot the sound came from,
## - patrols pick random points, sometimes the place it last heard something, with uneven pauses.
signal caught
## Emitted with the exact position of every sound it hears.
signal heard_noise(at: Vector2, source: int)
## Emitted when it freezes to listen: the moment it knows something made a sound.
signal listen_started
## Emitted when it gives up a search and goes back to its patrol (SEARCH -> PATROL).
signal stood_down

@export_group("Listening")
## Random range (s) it stands still, head turned toward a clearly-heard sound, before the scream.
@export var listen_time_range := Vector2(0.7, 1.2)
## The same for a barely-heard sound: longer, because this is where the player gets to stop.
@export var faint_listen_time_range := Vector2(1.4, 2.2)
## While it listens to a barely-heard sound, further faint sounds only turn its head for this
## long (the foot she plants as she stops is not held against her). After it, any sound it
## hears makes the listening end in a hunt.
@export_range(0.0, 2.0, 0.05, "suffix:s") var second_strike_grace := 0.9
## Once a second sound has turned a check into a hunt, it still listens at least this long.
@export_range(0.0, 1.0, 0.05, "suffix:s") var second_strike_hold := 0.4
@export_group("Readability")
## Seconds it screams standing still when a hunt starts, before it runs (hunt_start clip: 1.3 s).
@export_range(0.0, 2.0, 0.05) var hunt_start_hold := 1.3
## Seconds from the catch to the game over screen: the grab and fold (1.34 s) and a beat of stillness.
@export_range(0.0, 4.0, 0.05) var catch_screen_delay := 1.9
@export_group("Floor feeling")
## Seconds it feels the floor at each SEARCH point (counted inside the search's duration).
@export_range(0.0, 3.0, 0.05) var search_feel_time := 1.2
@export_group("Patrol route")
## Random pause range at each patrol point, in seconds.
@export var patrol_pause_range := Vector2(0.9, 2.8)
## Chance that it walks to a place where it heard something before, between two patrol points.
@export_range(0.0, 1.0, 0.05) var revisit_chance := 0.35
@export_group("Audio")
## Left empty: the drag loop is EntityAudio's now (entities/entity_audio.gd).
@export var drag_clip: AudioStream
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
## Everything it sounds like (child EntityAudio, entities/entity_audio.gd).
var audio: EntityAudio
## Source type of the last sound it heard (for the "it heard your ..." explanation).
var last_heard_source := -1
## How well it heard that sound (EntityAI.Heard).
var last_heard_grade := Heard.NONE
var _listening := 0.0
## Seconds since it froze to listen.
var _listen_clock := 0.0
## What the listening ends in: State.HUNT or State.INVESTIGATE.
var _listen_outcome := State.HUNT
var _listen_faintness := 1.0
var _scream_left := 0.0
var _memory: Array[Vector2] = []
## A place it heard something, walked to once between two patrol points (Vector2.INF: none).
var _detour := Vector2.INF
var _drag: AudioStreamPlayer2D
var _feel_player: AudioStreamPlayer2D
var _feel_left := 0.0
var _tap_wait := 0.0
var _resetting := false

func _ready() -> void:
	super._ready()
	_sprite.hide()
	sprite_rig = $SpriteRig
	audio = get_node_or_null("EntityAudio") as EntityAudio
	state_changed.connect(func(previous: int, current: int) -> void:
		if previous == State.SEARCH and current == State.PATROL and not _resetting: stood_down.emit())
	color_by_state = false
	log_state_changes = false
	_drag = AudioStreamPlayer2D.new()
	_drag.bus = AudioBus.ENTITY
	_drag.stream = drag_clip
	_drag.volume_db = drag_volume_db
	_drag.max_distance = 900.0
	add_child(_drag)
	_feel_player = AudioStreamPlayer2D.new()
	_feel_player.bus = AudioBus.ENTITY
	_feel_player.stream = feel_clip
	_feel_player.volume_db = feel_volume_db
	_feel_player.max_distance = 600.0
	add_child(_feel_player)

func _physics_process(delta: float) -> void:
	if not active:
		_inbox.clear()
		velocity = Vector2.ZERO
		_update_drag(false)
		return
	# Sounds that reached it between two physics steps are weighed now, also while it listens.
	if not GameState.is_dead:
		_drain_inbox()
	if _listening > 0.0:
		_listening -= delta
		_listen_clock += delta
		_halt()
		_update_drag(false)
		if _listening <= 0.0 and not GameState.is_dead:
			_end_listen()
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

func _listens() -> bool:
	return active and not GameState.is_dead

## It heard a sound (EntityAI weighed it: clear or faint). Nothing is decided here at once:
## it freezes and listens, and what it hears while it listens decides.
func _react(at: Vector2, source: int, heard: int, faintness: float) -> void:
	last_heard_position = at
	last_heard_source = source
	last_heard_grade = heard
	_feel_left = 0.0
	_remember(at)
	heard_noise.emit(at, source)
	if _listening > 0.0:
		# Already listening. A clear sound, or any sound once the grace is over, is the second
		# strike: the check becomes a hunt. Inside the grace a faint sound only turns its head.
		if _listen_outcome != State.HUNT:
			if heard == Heard.CLEAR or _listen_clock >= second_strike_grace:
				_listen_outcome = State.HUNT
				_listening = maxf(_listening, second_strike_hold)
			else:
				_listen_faintness = faintness
		return
	if current_state == State.HUNT:
		_start_hunt()                          # the target moves, no new scream
		return
	# While it checks or searches its ears are sharp: barely heard counts as clearly heard.
	var alert := current_state == State.INVESTIGATE or current_state == State.SEARCH
	_listen_outcome = State.HUNT if (heard == Heard.CLEAR or alert) else State.INVESTIGATE
	_listen_faintness = faintness
	var span := listen_time_range if _listen_outcome == State.HUNT else faint_listen_time_range
	_begin_listen(randf_range(span.x, span.y))

## Its breathing stops while it listens: the silence is the tell. The click follows (EntityAudio).
func _begin_listen(seconds: float) -> void:
	_listening = seconds
	_listen_clock = 0.0
	_breath_player.stop()
	listen_started.emit()
	if _listening <= 0.0:
		_end_listen()

func _end_listen() -> void:
	_listening = 0.0
	_resume_breathing()
	if _listen_outcome == State.HUNT:
		_start_hunt()
	else:
		_start_investigate(_listen_faintness)

## Story use: it turns to a place it heard before it became active (the prayer that stopped).
## The same chain as a clearly-heard sound: the listening tell, the scream, the run, the floor feeling.
func notice(at: Vector2) -> void:
	if not active or GameState.is_dead:
		return
	last_heard_position = at
	last_heard_grade = Heard.CLEAR
	_feel_left = 0.0
	_remember(at)
	heard_noise.emit(at, NoiseManager.SourceType.PRAY)
	_listen_outcome = State.HUNT
	_listen_faintness = 0.0
	_listening = randf_range(listen_time_range.x, listen_time_range.y)
	_listen_clock = 0.0
	_breath_player.stop()
	listen_started.emit()

func is_listening() -> bool:
	return _listening > 0.0

## What its listening will end in right now: "HUNT" or "INVESTIGATE" ("" when it is not listening).
func listen_outcome_name() -> String:
	return State.keys()[_listen_outcome] if _listening > 0.0 else ""

## True during the scream hold that starts a hunt.
func is_screaming() -> bool:
	return _scream_left > 0.0 and active

## It stands where the sound was and feels the floor for it: the end of a hunt that reached
## the spot (until hunt_linger runs out) and a moment at each search point.
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
	var target := _detour if _detour != Vector2.INF else route[route_index]
	nav_agent.target_position = target
	_move_along_path(patrol_speed_u)
	if _reached(target) or nav_agent.is_navigation_finished():
		_end_patrol_leg()

func _end_patrol_leg() -> void:
	_pick_next_patrol_point()
	_patrol_wait = randf_range(patrol_pause_range.x, patrol_pause_range.y)

## On patrol a point it cannot get to is skipped; everything else as EntityAI.
func _on_stuck() -> void:
	if current_state == State.PATROL:
		if not route.is_empty():
			_end_patrol_leg()
		return
	super._on_stuck()

## EntityAI's search, plus a moment of floor feeling at each point; the search's duration still ends it.
func _tick_search(delta: float) -> void:
	if _feel_left > 0.0:
		_feel_left -= delta
		_state_timer += delta
		_halt()
		if _state_timer >= _search_length:
			_change_state(State.PATROL)
		return
	super._tick_search(delta)

func _on_search_point_reached() -> void:
	_feel_left = search_feel_time

## Random point of the route, never the same point twice in a row. Now and then it first walks
## to a place it heard something: a one-off detour, the route itself is never changed.
func _pick_next_patrol_point() -> void:
	if _detour == Vector2.INF and not _memory.is_empty() and randf() < revisit_chance:
		_detour = _memory.pick_random()
		return
	_detour = Vector2.INF
	var previous := route_index
	if route.size() > 1:
		while route_index == previous:
			route_index = randi() % route.size()

func _remember(at: Vector2) -> void:
	_memory.append(at)
	if _memory.size() > 4:
		_memory.pop_front()

func set_breathing(on: bool) -> void:
	if audio != null:
		audio.set_breathing(on)
	if on:
		_resume_breathing()
	else:
		_breath_player.stop()

func _resume_breathing() -> void:
	if not _breath_player.playing:
		_play_breath_clip()

func _update_drag(moving: bool) -> void:
	if moving and not _drag.playing and drag_clip != null and audio == null:
		_drag.pitch_scale = randf_range(0.8, 0.95)
		_drag.play()
	elif not moving and _drag.playing:
		_drag.stop()

func _update_feel_audio(delta: float) -> void:
	if feel_clip == null or audio != null or not is_feeling():
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
	_inbox.clear()
	_memory.clear()
	_detour = Vector2.INF
	_listening = 0.0
	_listen_clock = 0.0
	_listen_outcome = State.HUNT
	_listen_faintness = 1.0
	_scream_left = 0.0
	_hunt_timer = 0.0
	_hunt_travel = 0.0
	_state_timer = 0.0
	_check_pause = 0.0
	_check_stopped = true
	_clear_stuck()
	_patrol_wait = 1.5
	last_heard_source = -1
	last_heard_grade = Heard.NONE
	last_judgement = {}
	_resetting = true
	_change_state(State.PATROL)
	_resetting = false
	active = false
	_feel_left = 0.0
	sprite_rig.reset()
	if audio != null:
		audio.reset()
