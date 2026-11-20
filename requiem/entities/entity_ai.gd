extends CharacterBody2D

# EntityAI (the entity that hunts you)
#
# It is blind. It never knows where the player is: it knows where a SOUND was, and how sure
# it is of it. Four states:
#
#   PATROL      - Walks the level, slowly. "It does not know you exist."
#   INVESTIGATE - (the design calls it CHECK) It barely heard something. It creeps to ABOUT
#                 where the sound was, stops once on the way to listen, takes a short look
#                 around and goes back to its patrol. This is the player's warning: any
#                 noise it hears from here on is a hunt.
#   HUNT        - It clearly heard something, or heard a second thing while its attention was
#                 up. It runs to the EXACT spot, faster than the player walks (3.9 vs 3.2 u/s).
#                 It never gives up before it gets there; on the spot it waits hunt_linger.
#   SEARCH      - It lost the trail: it checks points around the last sound, the hiding
#                 corners the level marks there (group "entity_poi"), and steps through a
#                 nearby door before it gives up and goes back to PATROL.
#
# HEARING has two certainties (hear()). Every noise has a radius (how loud it is):
#   inside radius x clear_gain  -> clearly heard  -> HUNT
#   inside radius x faint_gain  -> barely heard   -> INVESTIGATE (HUNT once it is alert)
# Distance is measured the way sound travels (audio/acoustics.gd): the straight line when no
# wall is in the way, otherwise mostly the walking path through the doorways, and every
# closed door on the way adds door_muffle_u. It never hears a noise it made itself.
#
# DOORS: it pushes a closed door open by walking into it (level/door/door.gd asks it what it
# wants). On patrol and in a check it first stands in front of the door for a moment: you
# hear it stop outside. In a hunt it slams it. A locked door it tries, waits at, and gives up.
#
# LEARNING: every hunt the player escapes makes its next search longer and wider, up to
# persistence_max. It never learns from the player dying.
#
# This script decides at once. tutorial/entity.gd adds the listening pause in between, where
# a second noise turns "it comes to look" into "it hunts".
#
# UNITS: 1 u = 32 px, the same as player.gd. Every radius, distance and speed is exported in
# units.
const PX_PER_UNIT: float = Units.PX_PER_UNIT

enum State { PATROL, INVESTIGATE, SEARCH, HUNT }
## How well it heard a noise.
enum Heard { NONE, FAINT, CLEAR }

## A check lands at least this far from the sound, however clearly-faint it was.
const INVESTIGATE_ERROR_MIN_U := 0.5
## Checks shorter than this have no stop on the way.
const INVESTIGATE_STOP_MIN_U := 3.0
## Tries to find a point in the same space as a sound (no wall between the two).
const POINT_TRIES := 6
## Each search pass after the first covers this much of the radius of the one before.
const SEARCH_TIGHTEN := 0.6
const SEARCH_MIN_RADIUS_U := 1.5
## A closed door muffles a sound whose way passes within this of the middle of its doorway.
const DOORWAY_REACH_PX := 40.0
## How far past the middle of a doorway it steps when a search takes it through a door.
const DOOR_STEP_THROUGH_U := 2.5
## Level designers mark hiding corners by putting a Node2D (a Marker2D) in this group.
const POI_GROUP := &"entity_poi"
const MAX_POINTS_OF_INTEREST := 3
## Points it checks in the room past the door, once it has learned to (Learning).
const NEXT_ROOM_POINTS := 2

## Emitted only when the real FSM changes state; audio listens here without observing noise directly.
signal state_changed(previous: int, current: int)
## It could not get where it was going (a locked door, or stuck_time of pushing at something):
## it dropped that target.
signal stuck
## It lost a hunt and will search harder next time: the new level (1..persistence_max).
signal learned(level: int)

@export_group("Hearing")
## Safety cap, not a mechanic: it is above every real hearing distance.
@export var hearing_range_u: float = 40.0
## A noise is clearly heard within its radius times this.
@export_range(1.0, 4.0, 0.05) var clear_gain: float = 2.0
## A noise is barely heard within its radius times this (never less than clear_gain).
@export_range(1.0, 6.0, 0.05) var faint_gain: float = 3.5
## Every closed door on a sound's way adds this much distance (two doors at most).
@export_range(0.0, 8.0, 0.5, "suffix:u") var door_muffle_u: float = 3.0

@export_group("Speed (u/s)")
## On patrol: slow, so it reads differently from when it has heard you.
@export var patrol_speed_u: float = 2.2
## Checking a barely-heard noise. Slower than the player holding her breath (2.5 u/s).
@export var investigate_speed_u: float = 2.2
## Searching.
@export var move_speed_u: float = 3.0
## Hunting: FASTER than walking (3.2) and SLOWER than sprinting (5.4).
@export var hunt_speed_u: float = 3.9

@export_group("Check")
## A check goes to a point up to this far from the sound: the fainter, the further off.
@export_range(0.0, 6.0, 0.25, "suffix:u") var investigate_error_u: float = 2.5
## Random range (s) of its one stop on the way, to listen.
@export var investigate_stop_range := Vector2(0.8, 1.5)
## A check that has not arrived after this long looks around where it is.
@export var investigate_timeout: float = 14.0

@export_group("Hunt")
## Seconds it stays on the spot, with nothing new to hear, before it starts to search.
@export var hunt_linger: float = 3.0
## Safety: a hunt that cannot reach its spot searches where it is after this long.
@export var hunt_max_travel: float = 20.0

@export_group("Search")
## Random range (s) a search lasts after a hunt.
@export var search_duration_range := Vector2(12.0, 18.0)
## Radius around the last sound in which a search checks points.
@export var search_radius_u: float = 6.0
## Points of its first pass; later passes are tighter.
@export var search_points: int = 5
## The short look around that ends a check.
@export var light_search_duration_range := Vector2(5.0, 8.0)
@export var light_search_radius_u: float = 3.0
@export var light_search_points: int = 2
## A search after a hunt ends by stepping through one door this near the sound (0: never).
@export_range(0.0, 20.0, 0.5, "suffix:u") var search_door_reach_u: float = 8.0

@export_group("Doors")
## Random range (s) it stands in front of a closed door before it pushes it, on patrol and in
## a check. In a hunt it slams the door at once.
@export var door_wait_range := Vector2(0.6, 1.4)
## Seconds it stands at a locked door after trying it, before it gives that way up.
@export_range(0.0, 5.0, 0.1, "suffix:s") var locked_door_wait: float = 1.5

@export_group("Learning")
## How many times it can learn from a hunt the player escaped (0: it never learns).
@export_range(0, 5) var persistence_max: int = 3
## Each level makes a search after a hunt this much longer...
@export_range(0.0, 10.0, 0.5, "suffix:s") var persistence_search_time: float = 3.0
## ...and adds this many points to its first pass.
@export_range(0, 4) var persistence_search_points: int = 1
## From this level on, the search also looks around in the room past its door.
@export_range(1, 5) var persistence_next_room_level: int = 2

@export_group("Patrol")
## Seconds it stands still at each patrol point.
@export var patrol_pause: float = 1.5
## With no baked mesh yet, it patrols within this radius of its spawn.
@export var patrol_fallback_radius_u: float = 6.0

@export_group("Distances (u)")
## How close to a point counts as having arrived.
@export var arrival_threshold_u: float = 0.5
## Catch radius: if it touches you, you die.
@export var catch_radius_u: float = 0.75

@export_group("Stuck")
## It drops its target when it has tried to move for this long and got nowhere (0: never).
@export_range(0.0, 5.0, 0.1, "suffix:s") var stuck_time: float = 1.5
## "Nowhere" is less than this.
@export_range(0.05, 1.0, 0.05, "suffix:u") var stuck_distance_u: float = 0.2

@export_group("Debug")
@export var log_state_changes: bool = true
## Colours the greybox by state.
@export var color_by_state: bool = true

@export_group("Audio")
## Breathing loop while it patrols, checks or searches.
@export var breath_calm_clips: Array[AudioStream] = []
## Breathing loop while it hunts: louder and faster.
@export var breath_hunt_clips: Array[AudioStream] = []
## One hit on ENTERING the hunt.
@export var hunt_stinger_clips: Array[AudioStream] = []
## Positional cues on entering the lesser states.
@export var investigate_cue_clips: Array[AudioStream] = []
@export var search_cue_clips: Array[AudioStream] = []
@export var state_cue_volume_db: float = -13.0
## One hit when it catches you.
@export var catch_clips: Array[AudioStream] = []
@export var breath_volume_db: float = -10.0
## How much louder the breathing is (on top of breath_volume_db) in HUNT.
@export var hunt_breath_volume_boost_db: float = 6.0
@export var stinger_volume_db: float = -2.0

var current_state: int = State.PATROL
## Where the last sound it heard really was. A hunt runs here.
var last_heard_position: Vector2 = Vector2.ZERO
## Where a check walks to: near last_heard_position, never exactly on it.
var check_target: Vector2 = Vector2.ZERO
## The last noise it weighed, heard or not (measure_noise(), plus source and state). For the
## F3 overlay and the tests.
var last_judgement: Dictionary = {}
var nav_agent: NavigationAgent2D

var _sprite: Sprite2D
var _breath_player: AudioStreamPlayer2D
var _stinger_player: AudioStreamPlayer2D
## The EntityAudio child, when the scene has one. It then makes every sound of the entity, and
## the clip arrays above stay unused, so nothing ever plays twice.
var _entity_audio: Node
var _spawn_position: Vector2
var _state_timer: float = 0.0
## Seconds it has stood on the spot of a hunt.
var _hunt_timer: float = 0.0
## Seconds since the hunt last got a new target.
var _hunt_travel: float = 0.0
var _patrol_target: Vector2 = Vector2.ZERO
var _has_patrol_target: bool = false
var _patrol_wait: float = 0.0
var _search_queue: Array[Vector2] = []
var _search_length: float = 0.0
var _search_centre: Vector2 = Vector2.ZERO
var _search_radius_px: float = 0.0
var _search_count: int = 0
## The search under way is the short look after a check, not the search after a hunt.
var _search_light: bool = false
## How many hunts the player has escaped (0..persistence_max): see Learning.
var persistence: int = 0
## The closed door it stands in front of (null: none), how long it still stands there, and
## whether it found it locked.
var _door: Door = null
var _door_wait: float = 0.0
var _door_locked: bool = false
## The door it has finished waiting at: asked again, it pushes.
var _door_waited: Door = null
var _check_start_px: float = 0.0
var _check_stop_at: float = 0.5
var _check_stopped: bool = true
var _check_pause: float = 0.0
## Noises that arrived outside the physics step, weighed on the next one.
var _inbox: Array = []
var _stuck_anchor: Vector2 = Vector2.INF
var _stuck_for: float = 0.0


func _ready() -> void:
	_spawn_position = global_position

	_sprite = $DebugSprite
	nav_agent = $NavigationAgent2D
	nav_agent.target_desired_distance = arrival_threshold_u * PX_PER_UNIT
	$CatchArea/CollisionShape2D.shape.radius = catch_radius_u * PX_PER_UNIT
	$CatchArea.body_entered.connect(_on_catch_area_body_entered)

	NoiseManager.noise_emitted.connect(_on_noise_emitted)
	_refresh_color()

	# Direct children of the CharacterBody2D: they follow its transform by themselves.
	_entity_audio = get_node_or_null("EntityAudio")
	_breath_player = AudioStreamPlayer2D.new()
	_breath_player.bus = AudioBus.ENTITY
	add_child(_breath_player)
	_breath_player.finished.connect(_on_breath_finished)

	_stinger_player = AudioStreamPlayer2D.new()
	_stinger_player.bus = AudioBus.ENTITY
	add_child(_stinger_player)

	_play_breath_clip()


func _exit_tree() -> void:
	for audio in [_breath_player, _stinger_player]:
		if is_instance_valid(audio):
			audio.stop()
			audio.stream = null


func _physics_process(delta: float) -> void:
	if GameState.is_dead:
		_inbox.clear()
		_halt()
		if _breath_player.playing:
			_breath_player.stop()
		return

	_drain_inbox()
	if _door != null and not _tick_door(delta):
		return
	if stuck_time > 0.0 and _stuck_for >= stuck_time:
		_clear_stuck()
		stuck.emit()
		_on_stuck()

	match current_state:
		State.PATROL:
			_tick_patrol(delta)
		State.INVESTIGATE:
			_tick_investigate(delta)
		State.SEARCH:
			_tick_search(delta)
		State.HUNT:
			_tick_hunt(delta)


# ----------------------------------------------------------------- states ---

## Walks to random points of the mesh, with a pause at each. The pause matters: an entity
## that never stops reads as a robot.
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


## A check: it creeps to check_target, stops once on the way, and looks around when it gets
## there. `faintness`: 0 at the edge of clearly heard, 1 at the edge of its hearing.
func _start_investigate(faintness: float = 1.0) -> void:
	var error_u := lerpf(minf(INVESTIGATE_ERROR_MIN_U, investigate_error_u), investigate_error_u, clampf(faintness, 0.0, 1.0))
	check_target = _point_near(last_heard_position, Units.to_px(error_u), Units.to_px(error_u))
	_check_start_px = global_position.distance_to(check_target)
	_check_stop_at = randf_range(0.35, 0.65)
	_check_stopped = _check_start_px < Units.to_px(INVESTIGATE_STOP_MIN_U)
	_check_pause = 0.0
	_change_state(State.INVESTIGATE)


func _tick_investigate(delta: float) -> void:
	_state_timer += delta
	if _check_pause > 0.0:
		_check_pause -= delta
		_halt()
		return

	nav_agent.target_position = check_target
	_move_along_path(investigate_speed_u)

	if not _check_stopped and global_position.distance_to(check_target) <= _check_start_px * _check_stop_at:
		_check_stopped = true
		_check_pause = randf_range(investigate_stop_range.x, investigate_stop_range.y)
		return

	if _reached(check_target) or nav_agent.is_navigation_finished() or _state_timer >= investigate_timeout:
		_begin_search(true, global_position)


## True during the one stop of a check, where it stands and listens.
func is_check_paused() -> bool:
	return current_state == State.INVESTIGATE and _check_pause > 0.0


## It got to the sound and nobody was there: it checks points around it until its time is
## up. This is what turns "it gave up on the spot" into "it is looking for you".
func _tick_search(delta: float) -> void:
	_state_timer += delta

	if _state_timer >= _search_length:
		_change_state(State.PATROL)
		return

	if _search_queue.is_empty():
		# Time left: another pass, tighter.
		_search_radius_px = maxf(_search_radius_px * SEARCH_TIGHTEN, Units.to_px(SEARCH_MIN_RADIUS_U))
		_search_queue = _search_pass(_search_centre, _search_radius_px, maxi(_search_count - 1, 2))

	var target: Vector2 = _search_queue[0]
	nav_agent.target_position = target
	_move_along_path(move_speed_u)

	if _reached(target) or nav_agent.is_navigation_finished():
		_search_queue.remove_at(0)
		_on_search_point_reached()


## For the layer that draws it: it just arrived at a search point.
func _on_search_point_reached() -> void:
	pass


## Runs to the last sound at hunt_speed_u. Every new noise moves the target and starts the
## count again, so while you keep making noise it NEVER stops hunting. The wait only counts
## once it stands on the spot: a hunt across the house still arrives.
func _tick_hunt(delta: float) -> void:
	nav_agent.target_position = last_heard_position
	_move_along_path(hunt_speed_u)

	_hunt_travel += delta
	if nav_agent.is_navigation_finished():
		_hunt_timer += delta
	if _hunt_timer >= hunt_linger or _hunt_travel >= hunt_max_travel:
		_begin_search(false, last_heard_position if nav_agent.is_navigation_finished() else global_position)


## `light`: the short look around that ends a check (fewer points, closer, no door).
## `around`: the middle of the search.
func _begin_search(light: bool = false, around: Vector2 = last_heard_position) -> void:
	_search_light = light
	# What it has learned only counts for the search after a hunt.
	var level := 0 if light else persistence
	_search_centre = around
	_search_radius_px = Units.to_px(light_search_radius_u if light else search_radius_u)
	_search_count = maxi((light_search_points if light else search_points) + level * persistence_search_points, 1)
	var span := light_search_duration_range if light else search_duration_range
	_search_length = randf_range(minf(span.x, span.y), maxf(span.x, span.y)) + level * persistence_search_time
	# After a hunt it also looks into the hiding corners the level marks near the sound.
	var marked: Array[Vector2] = _points_of_interest(around) if not light else ([] as Array[Vector2])
	_search_queue = _search_pass(_search_centre, _search_radius_px, _search_count, marked)
	if not light:
		var door_stop := _door_stop(around)
		if door_stop != Vector2.INF:
			_search_queue.append(door_stop)
			if level >= persistence_next_room_level:
				# It has lost her often enough to look past the door too.
				for i in range(NEXT_ROOM_POINTS):
					_search_queue.append(_point_near(door_stop, Units.to_px(light_search_radius_u)))
	_change_state(State.SEARCH)


## `count` points around `centre`, and `also` (marked places): the nearest one first, the
## others in no order, so it doubles back like something feeling its way.
func _search_pass(centre: Vector2, radius_px: float, count: int, also: Array[Vector2] = []) -> Array[Vector2]:
	var found: Array[Vector2] = also.duplicate()
	for i in range(count):
		found.append(_point_near(centre, radius_px))
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return global_position.distance_squared_to(a) < global_position.distance_squared_to(b))
	var points: Array[Vector2] = []
	if found.is_empty():
		return points
	points.append(found.pop_front())
	found.shuffle()
	points.append_array(found)
	return points


## Hiding corners marked in the level (any Node2D in the group "entity_poi") that belong to
## the place a sound came from: with Rooms, the ones in the room the sound was in; without,
## the ones inside the search radius with no wall between them and the sound. At most
## MAX_POINTS_OF_INTEREST of them, picked at random, never by where the player is.
func _points_of_interest(spot: Vector2) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if not is_inside_tree():
		return found
	var rooms := _rooms_at(spot)
	var room: Room = rooms.room_at(spot) if rooms != null else null
	var skipped: Array[RID] = [get_rid()]
	for node in get_tree().get_nodes_in_group(POI_GROUP):
		var marker := node as Node2D
		if marker == null or not marker.is_visible_in_tree():
			continue
		var at := marker.global_position
		var belongs: bool
		if room != null:
			belongs = rooms.room_at(at) == room
		else:
			belongs = at.distance_to(spot) <= Units.to_px(search_radius_u) and not Acoustics.wall_between(spot, at, get_world_2d(), skipped)
		if belongs:
			found.append(_nav_point(at))
	found.shuffle()
	if found.size() > MAX_POINTS_OF_INTEREST:
		found.resize(MAX_POINTS_OF_INTEREST)
	return found


## The shown RoomVisibility that has a room at `spot` (null: this part of the level has no Rooms).
func _rooms_at(spot: Vector2) -> RoomVisibility:
	for node in get_tree().get_nodes_in_group(RoomVisibility.ROOMS_GROUP):
		var rooms := node as RoomVisibility
		if rooms != null and rooms.is_visible_in_tree() and rooms.room_at(spot) != null:
			return rooms
	return null


## A point just past one door near `spot`, on its far side: the last stop of a search. The
## door is one of the room the sound was in when the level has Rooms, otherwise any door
## within search_door_reach_u. It is chosen at random, never by where the player is.
## Vector2.INF: no door to try.
func _door_stop(spot: Vector2) -> Vector2:
	if search_door_reach_u <= 0.0 or not is_inside_tree():
		return Vector2.INF
	var candidates: Array[Door] = []
	var rooms := _rooms_at(spot)
	if rooms != null:
		for door in rooms.room_at(spot).doors:
			if door != null and not door.locked:
				candidates.append(door)
	if candidates.is_empty():
		var reach := Units.to_px(search_door_reach_u)
		for node in get_tree().get_nodes_in_group(Door.DOOR_GROUP):
			var door := node as Door
			if door != null and not door.locked and door.is_visible_in_tree() and door.get_noise_origin().distance_to(spot) <= reach:
				candidates.append(door)
	if candidates.is_empty():
		return Vector2.INF
	var chosen: Door = candidates.pick_random()
	var gap := chosen.get_noise_origin()
	# A FRONT door is crossed north-south, a SIDE door east-west.
	var across := chosen.global_transform.basis_xform(Vector2.DOWN if chosen.style == Door.Style.FRONT else Vector2.RIGHT).normalized()
	var side := 1.0 if (gap - spot).dot(across) >= 0.0 else -1.0
	return _nav_point(gap + across * side * Units.to_px(DOOR_STEP_THROUGH_U))


# ---------------------------------------------------------------- hearing ---

## How well it hears a noise of `radius_px` made at `at`: Heard.CLEAR, FAINT or NONE.
## Call it from _physics_process (it casts a ray).
func hear(at: Vector2, radius_px: float) -> int:
	return int(measure_noise(at, radius_px).heard)


## Everything about how a noise reaches it:
##   radius_u, clear_u, faint_u  the noise and the two distances it is heard within
##   distance_u                  how far the sound travels to it (doors included)
##   blocked, doors              a wall is in the way; closed doors counted on the way
##   heard                       Heard.NONE, FAINT or CLEAR
##   faintness                   0 at the edge of clearly heard, 1 at the edge of its hearing
func measure_noise(at: Vector2, radius_px: float) -> Dictionary:
	var radius_u := Units.to_u(radius_px)
	var clear_u := radius_u * clear_gain
	var faint_u := radius_u * maxf(faint_gain, clear_gain)
	var straight_u := Units.to_u(global_position.distance_to(at))
	var result := {"at": at, "radius_u": radius_u, "clear_u": clear_u, "faint_u": faint_u, "distance_u": straight_u,
		"blocked": false, "doors": 0, "heard": Heard.NONE, "faintness": 1.0}
	# Sound never travels less than the straight line: past these, nothing else is worth measuring.
	if straight_u > hearing_range_u or straight_u > faint_u:
		return result
	var skipped: Array[RID] = [get_rid()]
	var reading := Acoustics.measure_between(at, global_position, get_world_2d(), nav_agent.get_navigation_map(), skipped)
	var doors := mini(_closed_doors_on(reading), 2)
	var distance_u := reading.acoustic_u + door_muffle_u * doors
	result.distance_u = distance_u
	result.blocked = reading.blocked
	result.doors = doors
	if distance_u <= clear_u:
		result.heard = Heard.CLEAR
		result.faintness = 0.0
	elif distance_u <= faint_u:
		result.heard = Heard.FAINT
		result.faintness = inverse_lerp(clear_u, faint_u, distance_u) if faint_u > clear_u else 1.0
	return result


## Closed doors on the way of a measured sound: along the walking path when a wall is in the
## way, otherwise along the straight line (a door on it is not a wall, only wood).
func _closed_doors_on(reading: AcousticReading) -> int:
	if not is_inside_tree():
		return 0
	var way := reading.path if (reading.blocked and reading.path.size() >= 2) else PackedVector2Array([reading.emitter_at, reading.listener_at])
	var count := 0
	for node in get_tree().get_nodes_in_group(Door.DOOR_GROUP):
		var door := node as Door
		if door == null or door.is_open or not door.is_visible_in_tree():
			continue
		var gap := door.get_noise_origin()
		for index in range(1, way.size()):
			if Geometry2D.get_closest_point_to_segment(gap, way[index - 1], way[index]).distance_to(gap) <= DOORWAY_REACH_PX:
				count += 1
				break
	return count


## Whether it takes in noise at all right now.
func _listens() -> bool:
	return not GameState.is_dead


func _on_noise_emitted(noise_position: Vector2, radius: float, source_type: int, _duration: float) -> void:
	# It never hears itself: its own doors, and anything else it sets off.
	if not _listens() or NoiseManager.current_emitter == self:
		return
	# Weighing a noise casts a ray. Noises that arrive outside the physics step (the flashlight
	# click comes from input, the prayer from _process) wait for the next one.
	if Engine.is_in_physics_frame():
		_judge(noise_position, radius, source_type)
	else:
		_inbox.append([noise_position, radius, source_type])


func _drain_inbox() -> void:
	if _inbox.is_empty():
		return
	var waiting := _inbox
	_inbox = []
	for noise in waiting:
		if _listens():
			_judge(noise[0], noise[1], noise[2])


func _judge(at: Vector2, radius: float, source: int) -> void:
	var result := measure_noise(at, radius)
	result["source"] = source
	result["state"] = current_state
	last_judgement = result
	if int(result.heard) == Heard.NONE:
		return
	_react(at, source, int(result.heard), float(result.faintness))


## It heard a noise. A clear one is a hunt. A faint one makes it come and check, unless
## something already has its attention: then faint counts as clear.
func _react(at: Vector2, _source: int, heard: int, faintness: float) -> void:
	last_heard_position = at
	if heard == Heard.CLEAR or current_state != State.PATROL:
		_start_hunt()
	else:
		_start_investigate(faintness)


# ------------------------------------------------------------------ doors ---

## Asked by a closed door it walked into (Door.push_open): what it wants to do with it.
## Hunting, it slams it. Searching, it pushes it. On patrol and in a check it stands in
## front of it first (door_wait_range) and pushes it when that is over.
func wants_door(door: Door) -> int:
	match current_state:
		State.HUNT:
			return Door.Push.SLAM
		State.SEARCH:
			return Door.Push.OPEN
	if _door_waited == door or maxf(door_wait_range.x, door_wait_range.y) <= 0.0:
		return Door.Push.OPEN
	if _door != door:
		_door = door
		_door_locked = false
		_door_wait = randf_range(minf(door_wait_range.x, door_wait_range.y), maxf(door_wait_range.x, door_wait_range.y))
	return Door.Push.WAIT


## Told by a locked door it walked into: it stands there for locked_door_wait, then gives
## that way up (as if it had been stuck).
func door_refused(door: Door) -> void:
	if _door == door and _door_locked:
		return
	_door = door
	_door_locked = true
	_door_wait = locked_door_wait


## True while it stands in front of a closed door (waiting to push it, or having found it locked).
func is_at_door() -> bool:
	return _door != null


## One step of standing at a door. Returns true when it is free to move again.
func _tick_door(delta: float) -> bool:
	if not is_instance_valid(_door) or (_door.is_open and not _door_locked):
		_door = null
		return true
	_door_wait -= delta
	if _door_wait > 0.0:
		_halt()
		return false
	var door := _door
	var was_locked := _door_locked
	_door = null
	if was_locked:
		_clear_stuck()
		stuck.emit()
		_on_stuck()
	else:
		_door_waited = door
		door.push_open(self)
		_door_waited = null
	return true


## Whatever it was waiting at a door for is over (it now hunts or searches): an unlocked
## door it stood in front of is pushed now, by the new state's rule.
func _leave_door() -> void:
	if _door == null:
		return
	var door := _door
	var was_locked := _door_locked
	_door = null
	if is_instance_valid(door) and not was_locked and not door.is_open:
		door.push_open(self)


# --------------------------------------------------------------- movement ---

func _move_along_path(speed_u: float) -> void:
	if nav_agent.is_navigation_finished():
		_halt()
		return

	var next_path_position: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = (next_path_position - global_position).normalized()

	velocity = direction * speed_u * PX_PER_UNIT
	move_and_slide()
	_watch_stuck()


func _halt() -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	_clear_stuck()


func _reached(point: Vector2) -> bool:
	return global_position.distance_to(point) <= arrival_threshold_u * PX_PER_UNIT


## Counts how long it has been trying to move without getting anywhere.
func _watch_stuck() -> void:
	if _stuck_anchor == Vector2.INF or global_position.distance_to(_stuck_anchor) >= Units.to_px(stuck_distance_u):
		_stuck_anchor = global_position
		_stuck_for = 0.0
	else:
		_stuck_for += get_physics_process_delta_time()


func _clear_stuck() -> void:
	_stuck_anchor = Vector2.INF
	_stuck_for = 0.0


## It could not get to where it was going (the mesh runs through door gaps, and a locked
## door stops the body, not the path). It drops that target: on patrol the next point, in a
## check or a hunt it searches where it stands, in a search the next point.
func _on_stuck() -> void:
	match current_state:
		State.PATROL:
			_has_patrol_target = false
			_patrol_wait = patrol_pause
		State.INVESTIGATE:
			_begin_search(true, global_position)
		State.HUNT:
			_begin_search(false, global_position)
		State.SEARCH:
			if not _search_queue.is_empty():
				_search_queue.remove_at(0)


## The nearest walkable point (the point itself with no baked mesh).
func _nav_point(point: Vector2) -> Vector2:
	var map: RID = nav_agent.get_navigation_map()
	if map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0:
		return NavigationServer2D.map_get_closest_point(map, point)
	return point


## A walkable point between `min_px` and `radius_px` from `centre`, in the same space when
## one can be found (no wall between the two): it looks where the sound could have been, not
## behind the wall next to it. Call it from _physics_process (it casts rays).
func _point_near(centre: Vector2, radius_px: float, min_px: float = 0.0) -> Vector2:
	var skipped: Array[RID] = [get_rid()]
	for attempt in POINT_TRIES:
		# sqrt(randf()) spreads the points evenly by AREA, not by radius.
		var distance := lerpf(min_px, radius_px, sqrt(randf())) if radius_px > min_px else radius_px
		var point := _nav_point(centre + Vector2.from_angle(randf() * TAU) * distance)
		if not Acoustics.wall_between(centre, point, get_world_2d(), skipped):
			return point
	return _nav_point(centre)


## A random point of the walkable mesh. If it is not baked yet (nav_setup bakes it with
## call_deferred), it patrols near its spawn instead of standing stiff.
func _random_map_point() -> Vector2:
	var map: RID = nav_agent.get_navigation_map()
	if map.is_valid():
		var p: Vector2 = NavigationServer2D.map_get_random_point(map, 1, false)
		if p != Vector2.ZERO:
			return p

	var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	return _spawn_position + offset * patrol_fallback_radius_u * PX_PER_UNIT


# ------------------------------------------------------------------ misc ---

func _on_catch_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_play_stinger(catch_clips)
		GameState.kill_player()


func _start_hunt() -> void:
	_hunt_timer = 0.0
	_hunt_travel = 0.0
	_change_state(State.HUNT)


func _change_state(new_state: int) -> void:
	if current_state == new_state:
		return

	var was_hunting := current_state == State.HUNT
	var previous_state := current_state
	current_state = new_state
	state_changed.emit(previous_state, new_state)
	_state_timer = 0.0
	_clear_stuck()
	if new_state == State.HUNT or new_state == State.SEARCH:
		_leave_door()
	# A search after a hunt that ends with nothing found: she escaped, and it learns.
	if previous_state == State.SEARCH and new_state == State.PATROL and not _search_light and persistence < persistence_max:
		persistence += 1
		learned.emit(persistence)

	if new_state == State.PATROL:
		_has_patrol_target = false

	_refresh_color()

	# The breathing only RESTARTS on the calm <-> hunt border: the beat of "found you" /
	# "lost you". Inside PATROL/INVESTIGATE/SEARCH it keeps its own loop.
	if new_state == State.HUNT and not was_hunting:
		_play_stinger(hunt_stinger_clips)
		_play_breath_clip()
	elif was_hunting and new_state != State.HUNT:
		_play_breath_clip()
	if new_state == State.INVESTIGATE:
		_play_state_cue(investigate_cue_clips)
	elif new_state == State.SEARCH:
		_play_state_cue(search_cue_clips)

	if log_state_changes:
		print("[EntityAI] State -> ", State.keys()[new_state])


## The greybox changes colour with the state: dull grey on patrol, orange checking, yellow
## searching, full red hunting.
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

## Breathing loop: when a clip ends it chains the next one (from the calm or the hunt list by
## the state AT THAT MOMENT), so a state change mid-clip shows on the next cycle, except on
## the calm <-> hunt border, where it is forced at once.
func _play_breath_clip() -> void:
	if GameState.is_dead or _entity_audio != null:
		return

	var hunting := current_state == State.HUNT
	var searching := current_state == State.SEARCH or current_state == State.INVESTIGATE
	# With no DEDICATED hunt clip it reuses the calm one: it still sounds different, because
	# the volume and the pitch go up below.
	var clips := breath_hunt_clips if (hunting and not breath_hunt_clips.is_empty()) else breath_calm_clips
	if clips.is_empty():
		return

	_breath_player.volume_db = breath_volume_db + (hunt_breath_volume_boost_db if hunting else (2.0 if searching else 0.0))
	_breath_player.pitch_scale = 1.15 if hunting else (1.06 if searching else (0.94 if current_state == State.PATROL else 1.0))
	_breath_player.stream = clips[randi() % clips.size()]
	_breath_player.play()


func _on_breath_finished() -> void:
	_play_breath_clip()


func _play_stinger(clips: Array[AudioStream]) -> void:
	if clips.is_empty() or _entity_audio != null:
		return
	_stinger_player.volume_db = stinger_volume_db
	_stinger_player.stream = clips[randi() % clips.size()]
	_stinger_player.play()


func _play_state_cue(clips: Array[AudioStream]) -> void:
	if clips.is_empty() or _entity_audio != null:
		return
	_stinger_player.volume_db = state_cue_volume_db
	_stinger_player.pitch_scale = randf_range(0.96, 1.04)
	_stinger_player.stream = clips[randi() % clips.size()]
	_stinger_player.play()
