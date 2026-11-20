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
## - patrols pick random points, sometimes the place it last heard something, with uneven pauses
##   and now and then a stop mid-way; where the Director is on (child "Director",
##   entities/entity_director.gd) it picks the points instead, by where Viv is, and never tells,
## - CLAW TAPS: now and then, unaware, standing at a door Viv is on the other side of, it
##   taps three times on the wood and stands listening. Its own sound, from where it is.
signal caught
## Emitted with the exact position of every sound it hears.
signal heard_noise(at: Vector2, source: int)
## Emitted when it freezes to listen: the moment it knows something made a sound.
signal listen_started
## Emitted when it gives up a search and goes back to its patrol (SEARCH -> PATROL).
signal stood_down
## Emitted when it starts to tap on the wood at `door` (null: a wall near it).
signal tapped(door: Door)

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
## Chance per second of walking that it stops mid-way, for no reason the player can hear:
## silence without a click (0: it only stops at its patrol points).
@export_range(0.0, 1.0, 0.01, "suffix:/s") var patrol_stop_chance := 0.05
## Random range (s) of such a stop.
@export var patrol_stop_range := Vector2(0.8, 1.6)
@export_group("Claw taps")
## Off: it never taps.
@export var claw_taps := true
## Random range (s) between two rounds of taps, and before the first one.
@export var tap_gap_range := Vector2(60.0, 120.0)
## Random range (s) it stands listening after the taps.
@export var tap_listen_range := Vector2(2.0, 3.0)
## How much quieter than its floor pats a tap is. Out of a silent house, as near as it may
## tap, a tap must stay under what the jump-scare audit calls a sudden rise.
@export_range(-24.0, 0.0, 0.5, "suffix:dB") var tap_db := -8.0
## On a patrol pause it taps when the middle of a doorway is within this.
@export_range(0.0, 6.0, 0.25, "suffix:u") var tap_door_u := 1.5
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
## Chooses its patrol points by where Viv is, when the scene has one and it is on (child
## Director, entities/entity_director.gd). It only ever hands back a point of the route.
var director: EntityDirector
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
## Seconds until it may tap again, the taps still to come of this round, and the time to the next.
var _tap_cooldown := 0.0
var _taps_left := 0
var _tap_next := 0.0
var _drag: AudioStreamPlayer2D
var _feel_player: AudioStreamPlayer2D
var _feel_left := 0.0
var _tap_wait := 0.0
var _resetting := false

## Three taps of its claws on the wood (the set its floor pats use), this far apart.
const TAP_SET := "entity/pat_tap"
const TAP_COUNT := 3
const TAP_SPACING := Vector2(0.24, 0.36)
## Seconds it stands there before the first tap.
const TAP_LEAD := 0.5

func _ready() -> void:
	super._ready()
	_sprite.hide()
	sprite_rig = $SpriteRig
	audio = get_node_or_null("EntityAudio") as EntityAudio
	director = get_node_or_null("Director") as EntityDirector
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
	_tick_taps(delta)
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
	elif patrol_stop_chance > 0.0 and randf() < patrol_stop_chance * delta:
		# It stops mid-way and stands there. No click: it heard nothing.
		_patrol_wait = randf_range(patrol_stop_range.x, patrol_stop_range.y)

func _end_patrol_leg() -> void:
	_pick_next_patrol_point()
	_patrol_wait = randf_range(patrol_pause_range.x, patrol_pause_range.y)
	# A pause next to a door: it may tap on it.
	var door := _door_within(tap_door_u)
	if door != null and _may_tap(door):
		_patrol_wait = maxf(_patrol_wait, _begin_taps(door))

## On patrol it stands in front of a closed door before it pushes it (EntityAI). Now and
## then it taps on that door first, and listens.
func wants_door(door: Door) -> int:
	var waiting_already := _door == door
	var push := super.wants_door(door)
	if push == Door.Push.WAIT and not waiting_already and current_state == State.PATROL and _may_tap(door):
		_door_wait = maxf(_door_wait, _begin_taps(door))
	return push

# ------------------------------------------------------------------ taps ---

## Toying. It taps only while it knows nothing and is on patrol; when Viv cannot see where
## it stands (its room is not shown to her, or a wall or a closed door is between them); and
## when its sound reaches her without being on top of her (ring 1 or 2). The taps are its
## own claws, played from where it is: never a fake, and never a noise it can hear itself.
func _may_tap(_door_there: Door) -> bool:
	if not claw_taps or _tap_cooldown > 0.0 or _taps_left > 0 or audio == null or not active or GameState.is_dead:
		return false
	if current_state != State.PATROL or _listening > 0.0:
		return false
	if Dread.awareness_of(self, audio) > Dread.Awareness.PAUSED:
		return false
	var ring: int = Acoustics.reading(self).ring
	return ring >= 1 and ring <= 2 and is_hidden_from_viv()

## Starts a round of taps; returns how long it will stand there (the taps, then the listening).
func _begin_taps(door: Door) -> float:
	_taps_left = TAP_COUNT
	_tap_next = TAP_LEAD
	_tap_cooldown = randf_range(minf(tap_gap_range.x, tap_gap_range.y), maxf(tap_gap_range.x, tap_gap_range.y))
	tapped.emit(door)
	return TAP_LEAD + TAP_COUNT * TAP_SPACING.y + randf_range(minf(tap_listen_range.x, tap_listen_range.y), maxf(tap_listen_range.x, tap_listen_range.y))

func _tick_taps(delta: float) -> void:
	_tap_cooldown = maxf(_tap_cooldown - delta, 0.0)
	if _taps_left <= 0:
		return
	# Anything that takes its attention ends the round.
	if current_state != State.PATROL or _listening > 0.0 or GameState.is_dead:
		_taps_left = 0
		return
	_tap_next -= delta
	if _tap_next <= 0.0:
		_taps_left -= 1
		_tap_next = randf_range(TAP_SPACING.x, TAP_SPACING.y)
		if audio != null:
			audio.play_set(TAP_SET, tap_db)

## True while a round of taps is still sounding.
func is_tapping() -> bool:
	return _taps_left > 0

## Whether Viv cannot see where it stands: with Rooms, its room is not shown to her; without,
## a wall or a closed door is between the two. Call it from _physics_process (it casts a ray).
func is_hidden_from_viv() -> bool:
	var viv := get_tree().get_first_node_in_group(&"player") as Node2D
	if viv == null:
		return false
	for node in get_tree().get_nodes_in_group(RoomVisibility.ROOMS_GROUP):
		var rooms := node as RoomVisibility
		if rooms == null or not rooms.is_visible_in_tree():
			continue
		var room := rooms.room_at(global_position)
		if room != null:
			return not rooms.is_open_to_player(room)
	var skipped: Array[RID] = [get_rid()]
	if viv is CollisionObject2D:
		skipped.append((viv as CollisionObject2D).get_rid())
	if Acoustics.wall_between(global_position, viv.global_position, get_world_2d(), skipped):
		return true
	var line := AcousticReading.new()
	line.emitter_at = global_position
	line.listener_at = viv.global_position
	return _closed_doors_on(line) > 0

## The nearest shown door whose doorway is within `reach_u` of it (null: none).
func _door_within(reach_u: float) -> Door:
	var reach := Units.to_px(reach_u)
	var nearest: Door = null
	for node in get_tree().get_nodes_in_group(Door.DOOR_GROUP):
		var door := node as Door
		if door == null or not door.is_visible_in_tree():
			continue
		var distance := door.get_noise_origin().distance_to(global_position)
		if distance <= reach:
			reach = distance
			nearest = door
	return nearest

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

## Random point of the route, never the same point twice in a row; the Director's choice
## where it is on. Now and then it first walks to a place it heard something: a one-off
## detour, the route itself is never changed.
func _pick_next_patrol_point() -> void:
	if _detour == Vector2.INF and not _memory.is_empty() and randf() < revisit_chance:
		_detour = _memory.pick_random()
		return
	_detour = Vector2.INF
	if is_directed():
		route_index = director.pick(route, route_index)
		return
	var previous := route_index
	if route.size() > 1:
		while route_index == previous:
			route_index = randi() % route.size()

## True while the Director chooses its patrol points.
func is_directed() -> bool:
	return director != null and director.enabled and route.size() > 1

## The Director sends it elsewhere at once (a back-off began): the point it was walking to
## is dropped for a new one. Only ever on patrol; nothing it has heard is touched.
func redirect_patrol() -> void:
	if current_state != State.PATROL or _listening > 0.0 or not is_directed():
		return
	_detour = Vector2.INF
	route_index = director.pick(route, route_index)

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
	_search_light = true          # a reset is not an escape: nothing is learned from it
	_change_state(State.PATROL)
	_resetting = false
	persistence = 0
	_door = null
	_door_waited = null
	_door_locked = false
	_door_wait = 0.0
	_taps_left = 0
	_tap_cooldown = randf_range(minf(tap_gap_range.x, tap_gap_range.y), maxf(tap_gap_range.x, tap_gap_range.y)) * 0.5
	active = false
	_feel_left = 0.0
	sprite_rig.reset()
	if director != null:
		director.reset()
	if audio != null:
		audio.reset()
