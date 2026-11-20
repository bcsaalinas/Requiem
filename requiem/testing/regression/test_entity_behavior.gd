extends Node
## It listens before it hunts (headless), in the real house of the tutorial.
## A barely-heard noise makes it come and check, with no scream. A clearly-heard noise, or a
## second noise once its attention is up, makes it scream and hunt. It hears through doorways
## and less through closed doors, never hears itself, always reaches the spot of a hunt,
## searches for as long as it should and through a door, and never stays stuck.

## The Hacienda's ears (the script's own values): the house of the tutorial is gentler.
const CLEAR_GAIN := 2.0
const FAINT_GAIN := 3.5
const STEP_U := 3.0

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
## Middle of the vestibule's north end: 14 u of open floor to the south of it.
var north := Vector2.ZERO
var kitchen_door: Door
var altar_door: Door
## Awareness cues since the last clear(): the moments, in order.
var cues: Array[StringName] = []
## State changes since the last clear(): { from, to, time }.
var states: Array[Dictionary] = []
## Every noise event since the last clear(): { at, radius, source }.
var noises: Array[Dictionary] = []
var listens := 0
var stand_downs := 0
var stucks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	await set_up()
	await check_two_certainties()
	await check_walls_and_doors()
	await check_faint_is_a_check()
	await check_second_strike()
	await check_clear_is_a_hunt()
	await check_alert_ears()
	await check_never_hears_itself()
	await check_noise_between_steps()
	await check_hunt_arrives_then_searches()
	await check_stuck()
	check_route_never_wears()
	game.queue_free()
	await frames(3)
	print("[Entity behavior tests] %d/%d passed" % [checks - failures.size(), checks])
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)


func set_up() -> void:
	GameState.reset()
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	audio = entity.audio
	var fresh: CharacterBody2D = preload("res://tutorial/tutorial_entity.tscn").instantiate()
	check(is_equal_approx(fresh.clear_gain, CLEAR_GAIN) and is_equal_approx(fresh.faint_gain, FAINT_GAIN),
		"The entity scene's own ears are the Hacienda's: clear x%.1f, faint x%.1f" % [fresh.clear_gain, fresh.faint_gain])
	fresh.free()
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	check(is_equal_approx(entity.clear_gain, game.HOUSE_CLEAR_GAIN) and is_equal_approx(entity.faint_gain, game.HOUSE_FAINT_GAIN)
		and game.HOUSE_CLEAR_GAIN < CLEAR_GAIN and game.HOUSE_FAINT_GAIN < FAINT_GAIN,
		"In the house of the tutorial its ears are gentler (clear x%.1f, faint x%.1f)" % [entity.clear_gain, entity.faint_gain])
	entity.clear_gain = CLEAR_GAIN
	entity.faint_gain = FAINT_GAIN
	# Patrol2 is in the middle of the vestibule; its north end is 5.5 u up from there.
	north = game.world.marker("house", "Patrol2") + Vector2.UP * Units.to_px(5.5)
	kitchen_door = game.world.interactables["kitchen_door"]["node"]
	altar_door = game.world.zones["house"].get_node("Doors/AltarDoor")
	game.player.process_mode = Node.PROCESS_MODE_DISABLED      # she makes no sound of her own here
	game.player.global_position = game.world.marker("house", "SpawnFromForest")
	entity.get_node("CollisionShape2D").disabled = false
	audio.awareness_played.connect(func(moment: StringName, _set_id: String, _stream: AudioStream, _level: float) -> void: cues.append(moment))
	entity.state_changed.connect(func(from: int, to: int) -> void: states.append({"from": from, "to": to, "time": now()}))
	entity.listen_started.connect(func() -> void: listens += 1)
	entity.stood_down.connect(func() -> void: stand_downs += 1)
	entity.stuck.connect(func() -> void: stucks += 1)
	NoiseManager.noise_emitted.connect(func(at: Vector2, radius: float, source: int, _duration: float) -> void:
		noises.append({"at": at, "radius": radius, "source": source}))


## Puts the entity at `at`, shown, active, unaware and standing still.
func arm(at: Vector2) -> void:
	var route: Array[Vector2] = [game.world.marker("house", "Patrol2"), game.world.marker("house", "Patrol6")]
	entity.reset_encounter(at, route)
	entity.show()
	entity.active = true
	entity._patrol_wait = 999.0
	await frames(3)
	clear()


func clear() -> void:
	cues.clear()
	states.clear()
	noises.clear()
	listens = 0
	stand_downs = 0
	stucks = 0


func step_at(at: Vector2, radius_u := STEP_U) -> void:
	NoiseManager.emit_noise(at, Units.to_px(radius_u), NoiseManager.SourceType.FOOTSTEP)


func went_to(state: int) -> Array:
	return states.filter(func(change: Dictionary) -> bool: return change.to == state)


## Waits (at most `limit` physics frames) until `done` says so.
func until(done: Callable, limit := 1200) -> void:
	for tick in range(limit):
		if done.call(): return
		await frames(1)


# ------------------------------------------------------------------- hearing ---

## One noise, three outcomes, by how far it is.
func check_two_certainties() -> void:
	await arm(north)
	var south := Vector2.DOWN
	var near: Dictionary = entity.measure_noise(north + south * Units.to_px(5.0), Units.to_px(STEP_U))
	var far: Dictionary = entity.measure_noise(north + south * Units.to_px(8.0), Units.to_px(STEP_U))
	var gone: Dictionary = entity.measure_noise(north + south * Units.to_px(11.0), Units.to_px(STEP_U))
	check(near.heard == entity.Heard.CLEAR and is_equal_approx(near.clear_u, 6.0) and not near.blocked,
		"A walking step 5 u away in the same room is clearly heard (clear within %.1f u)" % near.clear_u)
	check(far.heard == entity.Heard.FAINT and is_equal_approx(far.faint_u, 10.5) and far.faintness > 0.0 and far.faintness < 1.0,
		"The same step 8 u away is barely heard (faint within %.1f u, faintness %.2f)" % [far.faint_u, far.faintness])
	check(gone.heard == entity.Heard.NONE, "And 11 u away it is not heard at all")
	var held: Dictionary = entity.measure_noise(north + south * Units.to_px(4.0), Units.to_px(1.0))
	check(held.heard == entity.Heard.NONE, "A held-breath step 4 u away is not heard: holding her breath is how she crosses its room")
	var pebble: Dictionary = entity.measure_noise(north + south * Units.to_px(13.0), Units.to_px(8.0))
	check(pebble.heard == entity.Heard.CLEAR, "A pebble 13 u away is clearly heard")
	check(entity.hear(north + south * Units.to_px(5.0), Units.to_px(STEP_U)) == entity.Heard.CLEAR, "hear() gives the same answer")
	check(not entity.is_listening() and listens == 0 and states.is_empty(), "Measuring a noise changes nothing: only a noise event makes it react")


## Sound goes through doorways, not through walls; a closed door on the way muffles it.
func check_walls_and_doors() -> void:
	kitchen_door.snap(false)
	# Just inside the vestibule, with the kitchen on the other side of the wall.
	var here: Vector2 = kitchen_door.get_noise_origin() + Vector2(60, -212)
	var through_wall: Vector2 = here + Vector2.LEFT * Units.to_px(3.75)
	var open_air: Vector2 = here + Vector2.RIGHT * Units.to_px(3.75)
	await arm(here)
	var free: Dictionary = entity.measure_noise(open_air, Units.to_px(STEP_U))
	var closed: Dictionary = entity.measure_noise(through_wall, Units.to_px(8.0))
	check(not free.blocked and is_equal_approx(free.distance_u, 3.75) and free.heard == entity.Heard.CLEAR,
		"3.75 u away in the same room, a step travels 3.75 u and is clearly heard")
	check(closed.blocked and closed.distance_u > 3.75 * 2.0,
		"The same 3.75 u through a wall is a long way round: %.1f u" % closed.distance_u)
	check(entity.measure_noise(through_wall, Units.to_px(STEP_U)).heard == entity.Heard.NONE, "A step behind that wall is not heard")
	check(closed.doors == 1, "The way round passes one closed door (found %d)" % closed.doors)
	kitchen_door.snap(true)
	await frames(2)
	var open: Dictionary = entity.measure_noise(through_wall, Units.to_px(8.0))
	check(open.doors == 0 and is_equal_approx(closed.distance_u - open.distance_u, entity.door_muffle_u),
		"With the door open the same sound is %.1f u nearer (%.1f u, was %.1f u)" % [entity.door_muffle_u, open.distance_u, closed.distance_u])
	# A noise loud enough to be clear through the open door and only faint through the closed one.
	var between_u: float = (open.distance_u + closed.distance_u) * 0.5 / CLEAR_GAIN
	check(entity.hear(through_wall, Units.to_px(between_u)) == entity.Heard.CLEAR, "A %.1f u noise behind the open door is clearly heard" % between_u)
	kitchen_door.snap(false)
	await frames(2)
	check(entity.hear(through_wall, Units.to_px(between_u)) == entity.Heard.FAINT, "Close the door and the same noise is barely heard")
	# A door on the straight line is wood, not a wall: it muffles all the same.
	var doorway := kitchen_door.get_noise_origin()
	await arm(doorway + Vector2(70, 0))
	var across: Dictionary = entity.measure_noise(doorway + Vector2(-70, 0), Units.to_px(STEP_U))
	check(not across.blocked and across.doors == 1 and is_equal_approx(across.distance_u, Units.to_u(140.0) + entity.door_muffle_u),
		"Straight through a closed door: the door's %.1f u on top of the distance (%.1f u)" % [entity.door_muffle_u, across.distance_u])


# ----------------------------------------------------------------- listening ---

## Barely heard, and nothing more: the click, no scream, it comes to look and goes away.
func check_faint_is_a_check() -> void:
	await arm(north)
	entity.faint_listen_time_range = Vector2(1.4, 1.4)
	entity.light_search_duration_range = Vector2(2.5, 2.5)
	var spot: Vector2 = north + Vector2.DOWN * Units.to_px(8.0)
	step_at(spot)
	check(entity.is_listening() and listens == 1 and entity.listen_outcome_name() == "INVESTIGATE" and entity.last_heard_grade == entity.Heard.FAINT,
		"A barely-heard step makes it freeze and listen, on its way to a check")
	check(entity.last_judgement.get("heard") == entity.Heard.FAINT and entity.last_judgement.get("source") == NoiseManager.SourceType.FOOTSTEP,
		"What it made of the noise is kept for the overlay")
	check(Dread.awareness_of(entity, audio) == Dread.Awareness.HEARD, "While it listens the house knows it heard something")
	var started := now()
	await until(func() -> bool: return not entity.is_listening(), 200)
	check(absf(now() - started - 1.4) < 0.25, "It listens for the longer, faint time (%.2f s)" % (now() - started))
	check(entity.get_state_name() == "INVESTIGATE" and not entity.is_screaming() and not cues.has(&"scream") and cues.has(&"heard"),
		"Nothing more: it clicks, does not scream, and starts a check (cues %s)" % [cues])
	var off: float = Units.to_u(entity.check_target.distance_to(spot))
	check(off >= 0.25 and off <= entity.investigate_error_u + 0.75 and entity.last_heard_position == spot,
		"It walks to about where the sound was (%.2f u off), and still knows where it really was" % off)
	check(Dread.awareness_of(entity, audio) == Dread.Awareness.SEARCHING, "A check counts as searching for the music and the house voice")
	await frames(30)
	var speed: float = Units.to_u(entity.velocity.length())
	check(is_equal_approx(speed, entity.investigate_speed_u) and speed < 2.5,
		"It creeps at %.1f u/s: slower than Viv holding her breath" % speed)
	# One stop on the way, to listen.
	var stopped := false
	for tick in range(600):
		await frames(1)
		stopped = stopped or entity.is_check_paused()
		if entity.get_state_name() != "INVESTIGATE": break
	check(stopped, "It stops once on the way, to listen")
	check(entity.get_state_name() == "SEARCH" and entity.global_position.distance_to(entity.check_target) <= Units.to_px(1.0),
		"At the place it looks around")
	var search_started := now()
	await until(func() -> bool: return entity.get_state_name() == "PATROL", 400)
	await frames(2)
	check(entity.get_state_name() == "PATROL" and absf(now() - search_started - 2.5) < 0.4, "A short look (%.1f s), then back to its patrol" % (now() - search_started))
	check(stand_downs == 1 and cues.has(&"stand_down") and not cues.has(&"scream") and not cues.has(&"lost") and went_to(entity.State.HUNT).is_empty(),
		"It stands down out loud, and there never was a scream, a hunt or a lost trail (cues %s)" % [cues])
	entity.faint_listen_time_range = Vector2(1.4, 2.2)
	entity.light_search_duration_range = Vector2(5.0, 8.0)


## The second noise is the one that gets you, once the grace is over.
func check_second_strike() -> void:
	var spot: Vector2 = north + Vector2.DOWN * Units.to_px(8.0)
	entity.faint_listen_time_range = Vector2(2.0, 2.0)
	# Inside the grace: the foot she plants as she stops is not held against her.
	await arm(north)
	step_at(spot)
	await frames(24)                           # 0.4 s
	step_at(spot + Vector2(40, 0))
	check(entity.is_listening() and entity.listen_outcome_name() == "INVESTIGATE" and listens == 1
		and entity.last_heard_position == spot + Vector2(40, 0),
		"A second faint step 0.4 s after the first only turns its head (grace %.1f s)" % entity.second_strike_grace)
	await until(func() -> bool: return not entity.is_listening(), 200)
	check(entity.get_state_name() == "INVESTIGATE" and not cues.has(&"scream"), "And it still only comes to look")
	# After the grace.
	await arm(north)
	step_at(spot)
	await frames(66)                           # 1.1 s
	step_at(spot + Vector2(40, 0))
	check(entity.is_listening() and entity.listen_outcome_name() == "HUNT" and listens == 1,
		"A second faint step 1.1 s after the first turns the check into a hunt")
	await until(func() -> bool: return not entity.is_listening(), 200)
	await until(func() -> bool: return cues.has(&"scream"), 120)
	check(entity.get_state_name() == "HUNT" and entity.is_screaming() and cues.has(&"scream") and entity.last_heard_position == spot + Vector2(40, 0),
		"It screams and hunts the place of the second step")
	check(went_to(entity.State.INVESTIGATE).is_empty(), "Without ever starting the check")
	# A clear noise needs no grace.
	await arm(north)
	step_at(spot)
	await frames(12)                           # 0.2 s
	step_at(north + Vector2.DOWN * Units.to_px(4.0))
	check(entity.listen_outcome_name() == "HUNT", "A clearly-heard step while it listens is a hunt at once, grace or not")
	# The scream never comes right on top of the second noise.
	await arm(north)
	step_at(spot)
	await frames(114)                          # 1.9 s of the 2.0
	step_at(spot)
	var struck := now()
	await until(func() -> bool: return not entity.is_listening(), 200)
	check(now() - struck >= entity.second_strike_hold - 0.05, "After a late second noise it still listens %.1f s before it screams (%.2f s)" % [entity.second_strike_hold, now() - struck])
	entity.faint_listen_time_range = Vector2(1.4, 2.2)


## Clearly heard: the click, the scream, the hunt to the exact spot.
func check_clear_is_a_hunt() -> void:
	await arm(north)
	var spot: Vector2 = north + Vector2.DOWN * Units.to_px(4.0)
	step_at(spot)
	check(entity.is_listening() and entity.listen_outcome_name() == "HUNT" and entity.last_heard_grade == entity.Heard.CLEAR,
		"A clearly-heard step makes it listen, on its way to a hunt")
	var started := now()
	await until(func() -> bool: return not entity.is_listening(), 200)
	var listened := now() - started
	check(listened >= 0.65 and listened <= 1.3, "It listens 0.7 to 1.2 s first: no hunt without warning (%.2f s)" % listened)
	await until(func() -> bool: return cues.has(&"scream"), 120)
	check(entity.get_state_name() == "HUNT" and cues.has(&"scream") and entity.last_heard_position == spot, "Then it screams and hunts the exact spot")
	check(went_to(entity.State.INVESTIGATE).is_empty(), "No check on the way")


## Once something has its attention, barely heard counts as clearly heard.
func check_alert_ears() -> void:
	entity.faint_listen_time_range = Vector2(1.4, 1.4)
	await arm(north)
	var spot: Vector2 = north + Vector2.DOWN * Units.to_px(8.0)
	step_at(spot)
	await until(func() -> bool: return entity.get_state_name() == "INVESTIGATE", 200)
	await frames(20)
	clear()
	# Still far enough from it to be only barely heard.
	var again: Vector2 = entity.global_position + Vector2.DOWN * Units.to_px(8.0)
	check(entity.hear(again, Units.to_px(STEP_U)) == entity.Heard.FAINT, "While it checks, a step 8 u from it is still only barely heard")
	step_at(again)
	check(entity.is_listening() and listens == 1 and entity.listen_outcome_name() == "HUNT", "But now it ends in a hunt: its ears are sharp")
	await until(func() -> bool: return cues.has(&"scream"), 300)
	check(entity.get_state_name() == "HUNT" and cues.has(&"scream") and entity.last_heard_position == again, "It screams and hunts that step")
	# And a new noise during the hunt moves the target, with no new scream.
	await until(func() -> bool: return not entity.is_screaming(), 200)
	clear()
	var elsewhere: Vector2 = north + Vector2.RIGHT * Units.to_px(2.0)
	var grade: int = entity.hear(elsewhere, Units.to_px(STEP_U))
	step_at(elsewhere)
	await frames(10)
	check(grade != entity.Heard.NONE and entity.get_state_name() == "HUNT" and listens == 0 and not cues.has(&"scream")
		and not entity.is_screaming() and entity.last_heard_position == elsewhere,
		"During a hunt a new noise moves the target: no click, no second scream")
	entity.faint_listen_time_range = Vector2(1.4, 2.2)


# ----------------------------------------------------------------- its own noise ---

func check_never_hears_itself() -> void:
	await arm(north)
	NoiseManager.emit_noise(entity.global_position + Vector2(20, 0), Units.to_px(8.0), NoiseManager.SourceType.ENVIRONMENT, 0.0, entity)
	await frames(3)
	check(not entity.is_listening() and listens == 0 and entity.last_judgement.is_empty() and noises.size() == 1,
		"A noise it made itself is sent, and it does not even weigh it")
	check(NoiseManager.current_emitter == null, "Who made a noise is only known while it is being sent")
	NoiseManager.emit_noise(entity.global_position + Vector2(20, 0), Units.to_px(8.0), NoiseManager.SourceType.ENVIRONMENT)
	check(entity.is_listening(), "The same noise from anything else is heard")
	# The door it pushes open: Viv hears it, and it is no noise event at all.
	kitchen_door.snap(false)
	var doorway := kitchen_door.get_noise_origin()
	await arm(doorway + Vector2(70, 0))
	entity.global_position = doorway + Vector2(26, 0)
	await until(func() -> bool: return kitchen_door.is_open, 150)       # on patrol it stands outside first
	check(kitchen_door.is_open, "It pushes a closed door open by walking into it")
	check(noises.is_empty() and not entity.is_listening() and listens == 0 and states.is_empty(),
		"The door it pushed made no noise event (%d): it does not hunt its own door" % noises.size())
	# The same door opened by Viv is a noise, right next to it.
	kitchen_door.snap(false)
	await arm(doorway + Vector2(70, 0))
	entity.global_position = doorway + Vector2(120, 0)
	await frames(2)
	clear()
	kitchen_door.open()
	check(noises.size() == 1 and noises[0].source == NoiseManager.SourceType.DOOR and entity.is_listening(),
		"A door Viv opens still creaks for it to hear")
	kitchen_door.snap(false)


## Noises that arrive between two physics steps (a click from input) are weighed on the next one.
func check_noise_between_steps() -> void:
	await arm(north)
	await get_tree().process_frame
	check(not Engine.is_in_physics_frame(), "(this noise is sent outside the physics step)")
	step_at(north + Vector2.DOWN * Units.to_px(4.0))
	var at_once: bool = entity.is_listening()
	await frames(2)
	check(not at_once and entity.is_listening() and listens == 1, "A noise sent between two physics steps is heard on the next step, once")
	# While it is not active nothing is kept for later.
	await arm(north)
	entity.active = false
	await get_tree().process_frame
	step_at(north + Vector2.DOWN * Units.to_px(4.0))
	await frames(2)
	entity.active = true
	await frames(3)
	check(not entity.is_listening() and listens == 0, "A noise made while it is not active is not remembered")


# ------------------------------------------------------------ hunt and search ---

## A hunt across the house gets there before it gives up; then it searches long enough, and
## its last stop is through a door of the room the sound was in.
func check_hunt_arrives_then_searches() -> void:
	kitchen_door.snap(false)
	altar_door.snap(true)
	entity.hunt_linger = 1.0
	entity.search_duration_range = Vector2(7.0, 7.0)
	var rooms: RoomVisibility = game.world.rooms("house")
	await arm(game.world.marker("house", "Patrol1"))              # the altar room
	var spot: Vector2 = game.world.marker("house", "Patrol3")     # the kitchen, two doors away
	NoiseManager.emit_noise(spot, Units.to_px(60.0), NoiseManager.SourceType.ENVIRONMENT)
	check(entity.is_listening() and entity.listen_outcome_name() == "HUNT", "A loud noise across the house is clearly heard")
	await until(func() -> bool: return entity.get_state_name() == "HUNT" and not entity.is_screaming(), 300)
	var launched := now()
	clear()
	var door_stop := Vector2.INF
	for tick in range(1500):
		await frames(1)
		if entity.get_state_name() == "SEARCH":
			door_stop = entity._search_queue.back() if not entity._search_queue.is_empty() else Vector2.INF
			break
	var ran := now() - launched
	check(entity.get_state_name() == "SEARCH" and ran > 5.0 and entity.global_position.distance_to(spot) <= Units.to_px(1.0),
		"The hunt ran %.1f s, longer than the old 5 s limit, and gave up only on the spot" % ran)
	check(kitchen_door.is_open and noises.is_empty(), "It pushed the kitchen door open on its way, without a noise event")
	check(cues.has(&"lost"), "Losing the trail has its groan")
	check(entity._search_queue.size() == entity.search_points + 1, "The search has %d points and one door (%d stops)" % [entity.search_points, entity._search_queue.size()])
	var beyond: Room = rooms.room_at(door_stop) if door_stop != Vector2.INF else null
	check(rooms.room_at(spot).name == "Kitchen" and beyond != null and beyond.name == "Vestibule",
		"Its last stop is through the kitchen's door, in the next room (%s)" % (beyond.name if beyond != null else "none"))
	var search_started := now()
	await until(func() -> bool: return entity.get_state_name() != "SEARCH", 900)
	await frames(2)
	var searched := now() - search_started
	check(entity.get_state_name() == "PATROL" and absf(searched - 7.0) < 0.5, "It searches for all of its time (%.1f s of 7 s), never less because it ran out of points" % searched)
	check(stand_downs == 1 and cues.has(&"stand_down"), "And gives up out loud")
	entity.hunt_linger = 3.0
	entity.search_duration_range = Vector2(12.0, 18.0)
	check(entity.search_duration_range.x >= 12.0 and entity.light_search_duration_range.y < entity.search_duration_range.x,
		"A search after a hunt lasts 12 s or more; the look after a check is shorter")
	kitchen_door.snap(false)


## Something it cannot pass is in the way: it drops the target instead of pushing forever.
func check_stuck() -> void:
	await arm(north)
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(Units.to_px(12.0), 16.0)
	shape.shape = box
	wall.add_child(shape)
	game.world.add_child(wall)
	wall.global_position = north + Vector2.DOWN * Units.to_px(3.0)      # across the room, not on the mesh
	await frames(2)
	var spot: Vector2 = north + Vector2.DOWN * Units.to_px(9.0)
	NoiseManager.emit_noise(spot, Units.to_px(8.0), NoiseManager.SourceType.THROW)
	await until(func() -> bool: return entity.get_state_name() == "HUNT" and not entity.is_screaming(), 300)
	var launched := now()
	clear()
	await until(func() -> bool: return stucks > 0, 400)
	var took := now() - launched
	check(stucks == 1 and took < entity.stuck_time + 2.0, "Blocked on its way, it notices in %.1f s" % took)
	check(entity.get_state_name() == "SEARCH" and entity._search_centre.distance_to(entity.global_position) <= Units.to_px(0.5),
		"And searches where it stands instead of pushing at the wall")
	wall.queue_free()
	await frames(2)
	# Standing still on purpose is never "stuck".
	await arm(north)
	await frames(150)
	check(stucks == 0 and entity.get_state_name() == "PATROL", "Standing still on its patrol is not being stuck")


## A revisit is a one-off detour: the route itself is never changed.
func check_route_never_wears() -> void:
	var route: Array[Vector2] = [Vector2(10, 10), Vector2(20, 20), Vector2(30, 30)]
	entity.reset_encounter(north, route)
	entity.revisit_chance = 1.0
	entity._remember(Vector2(999, 999))
	var detours := 0
	for turn in 40:
		entity._pick_next_patrol_point()
		detours += int(entity._detour != Vector2.INF)
	check(entity.route == route, "After 40 patrol legs with revisits its route is still its route")
	check(detours == 20, "A revisit is always followed by a real patrol point (%d detours in 40 legs)" % detours)
	entity.revisit_chance = 0.35
