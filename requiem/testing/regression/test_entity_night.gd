extends Node
## What makes it richer through a night (headless), in the real house of the tutorial:
## - DOORS: on patrol and in a check it stands in front of a closed door before it pushes it;
##   in a hunt it slams it; a locked door it tries, waits at, and gives up. None of it is a
##   noise it can hear.
## - LEARNING: every hunt she escapes makes its next search longer and wider, up to a limit.
##   A check teaches it nothing, and neither does her death.
## - CLAW TAPS: unaware, at a door she is on the other side of, it taps three times and
##   stands listening. Only where she can hear it and cannot see it, and not often.

const TAP_SET := "entity/pat_tap"
## The loudest peak the sound tools let any prepared file have.
const PREPARED_PEAK_DB := -1.0

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
var settings: SoundSettings
var door: Door
var doorway := Vector2.ZERO
var rooms: RoomVisibility
## Either side of the kitchen door, 3 u from the middle of its doorway.
var vestibule_side := Vector2.ZERO
var kitchen_side := Vector2.ZERO
var noises := 0
var listens := 0
var stucks := 0
var pushes: Array[bool] = []          # one per push: was it a slam
var rattles := 0
var taps: Array[float] = []           # when each tap sounded
var tap_rounds: Array = []            # the door of each round
var lessons: Array[int] = []
var cues: Array[StringName] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Waits (at most `limit` physics frames) until `done` says so.
func until(done: Callable, limit := 900) -> void:
	for tick in range(limit):
		if done.call(): return
		await frames(1)


func _ready() -> void:
	settings = SoundSettings.current()
	await set_up()
	await check_waits_at_a_door()
	await check_slams_in_a_hunt()
	await check_hears_while_it_waits()
	await check_locked_door()
	check_what_it_wants()
	await check_points_of_interest()
	await check_learning()
	await check_taps()
	await check_when_it_does_not_tap()
	await check_tap_is_no_jump_scare()
	await check_the_night()
	game.queue_free()
	await frames(3)
	print("[Entity night tests] %d/%d passed" % [checks - failures.size(), checks])
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
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	check(entity.persistence_max == 0 and not entity.claw_taps, "In the first house it learns nothing and never taps")
	rooms = game.world.rooms("house")
	door = game.world.interactables["kitchen_door"]["node"]
	doorway = door.get_noise_origin()
	vestibule_side = doorway + Vector2(96, 0)
	kitchen_side = doorway + Vector2(-96, 0)
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	entity.get_node("CollisionShape2D").disabled = false
	NoiseManager.noise_emitted.connect(func(_at: Vector2, _radius: float, _source: int, _duration: float) -> void: noises += 1)
	entity.listen_started.connect(func() -> void: listens += 1)
	entity.stuck.connect(func() -> void: stucks += 1)
	entity.learned.connect(func(level: int) -> void: lessons.append(level))
	entity.tapped.connect(func(at: Door) -> void: tap_rounds.append(at))
	door.pushed.connect(func(_by: Node2D, slammed: bool) -> void: pushes.append(slammed))
	door.rattled.connect(func(_by: Node2D) -> void: rattles += 1)
	audio.played.connect(func(set_id: String, _voice: AudioStreamPlayer2D) -> void:
		if set_id == TAP_SET: taps.append(now()))
	audio.awareness_played.connect(func(moment: StringName, _set_id: String, _stream: AudioStream, _level: float) -> void: cues.append(moment))


func clear() -> void:
	noises = 0
	listens = 0
	stucks = 0
	rattles = 0
	pushes.clear()
	taps.clear()
	tap_rounds.clear()
	lessons.clear()
	cues.clear()


## Puts it in the vestibule, 3 u from the shut kitchen door, about to walk through it into
## the kitchen; Viv far away on the porch unless `viv` says otherwise.
func arm(viv := Vector2.INF, locked := false) -> void:
	door.locked = false
	door.snap(false)
	door.locked = locked
	var route: Array[Vector2] = [kitchen_side + Vector2(-64, 0), vestibule_side + Vector2(128, -96)]
	entity.reset_encounter(vestibule_side, route)
	entity.show()
	entity.active = true
	entity.revisit_chance = 0.0
	entity._patrol_wait = 0.0
	entity._tap_cooldown = 0.0
	game.player.global_position = viv if viv != Vector2.INF else game.world.marker("house", "SpawnFromForest")
	rooms.sync_to(game.player.global_position)
	await frames(2)
	audio.placed()
	await frames(1)
	clear()


# --------------------------------------------------------------------- doors ---

func check_waits_at_a_door() -> void:
	entity.door_wait_range = Vector2(1.0, 1.0)
	await arm()
	await until(func() -> bool: return entity.is_at_door(), 400)
	var arrived := now()
	check(entity.is_at_door() and not door.is_open and entity.get_state_name() == "PATROL", "On patrol it stops in front of a closed door")
	await frames(20)
	check(not door.is_open and is_zero_approx(entity.velocity.length()) and pushes.is_empty(), "It stands there, and the door stays shut")
	check(Dread.awareness_of(entity, audio) == Dread.Awareness.PAUSED, "For the house it is only a pause on its patrol")
	await until(func() -> bool: return door.is_open, 200)
	var waited := now() - arrived
	check(door.is_open and absf(waited - 1.0) < 0.2 and pushes == [false], "After its wait (%.2f s of 1.0) it pushes the door open: a push, not a slam" % waited)
	check(noises == 0 and listens == 0 and stucks == 0, "The push is no noise event, and it does not react to it")
	await until(func() -> bool: return entity.global_position.x < doorway.x - 40.0, 400)
	check(entity.global_position.x < doorway.x - 40.0 and not entity.is_at_door(), "Then it walks through")
	# A check waits at the door too.
	await arm()
	entity.last_heard_position = kitchen_side + Vector2(-64, 0)
	entity._start_investigate(0.0)
	await until(func() -> bool: return entity.is_at_door() or door.is_open, 400)
	check(entity.is_at_door() and not door.is_open and entity.get_state_name() == "INVESTIGATE", "Checking a faint sound, it also stops in front of the door first")
	await until(func() -> bool: return door.is_open, 200)
	check(door.is_open and pushes == [false] and noises == 0, "And pushes it after its wait")
	entity.door_wait_range = Vector2(0.6, 1.4)


func check_slams_in_a_hunt() -> void:
	await arm()
	entity.last_heard_position = kitchen_side + Vector2(-64, 0)
	entity._start_hunt()
	await until(func() -> bool: return not entity.is_screaming(), 200)
	var stood := false
	for tick in range(400):
		await frames(1)
		stood = stood or entity.is_at_door()
		if door.is_open: break
	check(door.is_open and pushes == [true] and not stood, "In a hunt it does not wait: it slams the door open")
	check(noises == 0 and listens == 0, "The slam is no noise event either")
	# The leaf of a slammed door swings faster than a pushed one.
	door.snap(false)
	entity.global_position = vestibule_side
	await frames(3)
	entity._change_state(entity.State.SEARCH)
	door.push_open(entity)
	await frames(6)
	var pushed_swing := door.swing
	door.snap(false)
	entity._change_state(entity.State.HUNT)
	door.push_open(entity)
	await frames(6)
	check(door.swing > pushed_swing * 1.5, "A slammed leaf swings faster (%.2f open after 0.1 s, a pushed one %.2f)" % [door.swing, pushed_swing])


## It hears her while it stands at the door: the door does not hold the hunt up.
func check_hears_while_it_waits() -> void:
	entity.door_wait_range = Vector2(30.0, 30.0)
	await arm()
	await until(func() -> bool: return entity.is_at_door(), 400)
	clear()
	NoiseManager.emit_noise(kitchen_side + Vector2(-64, 0), Units.to_px(8.0), NoiseManager.SourceType.THROW)
	check(entity.is_listening() and not door.is_open, "It hears a pebble beyond the door it is standing at, and listens")
	await until(func() -> bool: return entity.get_state_name() == "HUNT", 200)
	await frames(2)
	check(door.is_open and pushes == [true], "The hunt begins with the door slammed open")
	await until(func() -> bool: return entity.global_position.distance_to(kitchen_side + Vector2(-64, 0)) < Units.to_px(1.0), 500)
	check(entity.global_position.distance_to(kitchen_side + Vector2(-64, 0)) < Units.to_px(1.0) and stucks == 0, "And it reaches the pebble: it was never stuck at the door")
	entity.door_wait_range = Vector2(0.6, 1.4)


func check_locked_door() -> void:
	entity.locked_door_wait = 1.0
	await arm(Vector2.INF, true)
	var first: int = entity.route_index
	await until(func() -> bool: return rattles > 0, 400)
	var tried := now()
	check(rattles == 1 and entity.is_at_door() and not door.is_open and noises == 0, "It tries a locked door (the rattle), with no noise event")
	await frames(20)
	check(is_zero_approx(entity.velocity.length()) and stucks == 0, "And stands at it, instead of pushing against it")
	await until(func() -> bool: return stucks > 0, 200)
	check(stucks == 1 and absf(now() - tried - 1.0) < 0.2 and not door.is_open, "After %.1f s it gives that way up" % entity.locked_door_wait)
	check(entity.get_state_name() == "PATROL" and entity.route_index != first and not entity.is_at_door(), "On patrol: it turns to its next marker")
	check(rattles == 1 and pushes.is_empty() and listens == 0, "One rattle, no push, and nothing heard")
	# In a hunt it searches where it stands.
	await arm(Vector2.INF, true)
	entity.last_heard_position = kitchen_side + Vector2(-64, 0)
	entity._start_hunt()
	await until(func() -> bool: return stucks > 0, 600)
	check(rattles == 1 and stucks == 1 and entity.get_state_name() == "SEARCH" and not door.is_open
		and entity._search_centre.distance_to(entity.global_position) < Units.to_px(0.5),
		"Hunting a sound behind a locked door: the rattle, the wait, and it searches where it stands")
	door.locked = false
	entity.locked_door_wait = 1.5


func check_what_it_wants() -> void:
	var two: Array[Vector2] = [vestibule_side, kitchen_side]
	entity.reset_encounter(vestibule_side, two)
	entity._change_state(entity.State.HUNT)
	check(entity.wants_door(door) == Door.Push.SLAM, "Asked by a door: hunting, it wants to slam it")
	entity._change_state(entity.State.SEARCH)
	check(entity.wants_door(door) == Door.Push.OPEN and not entity.is_at_door(), "Searching, to push it at once")
	entity.reset_encounter(vestibule_side, two)
	check(entity.wants_door(door) == Door.Push.WAIT and entity.is_at_door(), "On patrol, to wait in front of it")
	entity.reset_encounter(vestibule_side, two)
	entity.door_wait_range = Vector2.ZERO
	check(entity.wants_door(door) == Door.Push.OPEN, "With no wait set, it pushes at once")
	entity.door_wait_range = Vector2(0.6, 1.4)


# ------------------------------------------------------- marked hiding corners ---

## A search after a hunt also looks into the hiding corners the level marks in that room.
func check_points_of_interest() -> void:
	var spot: Vector2 = game.world.marker("house", "Patrol3")          # the kitchen
	var corners: Array[Marker2D] = []
	# Two corners of the kitchen, and one in the vestibule, on the other side of the wall.
	for at: Vector2 in [doorway + Vector2(-250, -330), doorway + Vector2(-90, -330), doorway + Vector2(120, -330)]:
		var marker := Marker2D.new()
		marker.add_to_group(entity.POI_GROUP)
		game.world.zones["house"].add_child(marker)
		marker.global_position = at
		corners.append(marker)
	await arm()
	entity._patrol_wait = 999.0
	check(rooms.room_at(corners[0].global_position).name == "Kitchen" and rooms.room_at(corners[1].global_position).name == "Kitchen"
		and rooms.room_at(corners[2].global_position).name == "Vestibule", "Set up: two marked corners in the kitchen, one next door")
	entity._begin_search(false, spot)
	var visits := func(marker: Marker2D) -> bool:
		return entity._search_queue.any(func(point: Vector2) -> bool: return point.distance_to(marker.global_position) < Units.to_px(1.0))
	check(visits.call(corners[0]) and visits.call(corners[1]), "A search after a hunt in the kitchen also goes to the kitchen's marked corners")
	check(not visits.call(corners[2]), "Not to the one in the room next door, however near it is")
	check(entity._search_queue.size() == entity.search_points + 2 + 1, "On top of its own points and its door (%d stops)" % entity._search_queue.size())
	entity.reset_encounter(vestibule_side, [vestibule_side] as Array[Vector2])
	entity._begin_search(true, spot)
	check(not visits.call(corners[0]) and not visits.call(corners[1]) and entity._search_queue.size() == entity.light_search_points,
		"The short look after a check does not: only a real search knows the corners")
	entity.reset_encounter(vestibule_side, [vestibule_side] as Array[Vector2])
	for marker in corners:
		marker.queue_free()
	await frames(2)


# ------------------------------------------------------------------ learning ---

func check_learning() -> void:
	var spot: Vector2 = game.world.marker("house", "Patrol3")          # the kitchen
	var two: Array[Vector2] = [vestibule_side, kitchen_side]
	entity.persistence_max = 3
	entity.search_duration_range = Vector2(0.4, 0.4)
	entity.light_search_duration_range = Vector2(0.4, 0.4)
	entity.persistence_search_time = 0.2
	await arm()
	entity.active = true
	entity._patrol_wait = 999.0
	# The short look after a check teaches it nothing.
	entity._begin_search(true, spot)
	await until(func() -> bool: return entity.get_state_name() == "PATROL", 200)
	check(entity.persistence == 0 and lessons.is_empty(), "A check that finds nothing teaches it nothing")
	# Every hunt she escapes is a level.
	var lengths: Array[float] = []
	var stops: Array[int] = []
	## Per hunt: how many stops come after the door, and whether they are all in the room past it.
	var after_door: Array[int] = []
	var next_room := true
	for hunt in 4:
		entity._begin_search(false, spot)
		lengths.append(entity._search_length)
		var queue: Array[Vector2] = entity._search_queue.duplicate()
		stops.append(queue.size())
		# The door stop follows the first pass: its own points, plus one per level.
		var door_at: int = entity.search_points + mini(hunt, entity.persistence_max) * entity.persistence_search_points
		var door_room := rooms.room_at(queue[door_at]) if door_at < queue.size() else null
		next_room = next_room and door_room != null and door_room.name == "Vestibule"
		after_door.append(queue.size() - door_at - 1)
		for index in range(door_at + 1, queue.size()):
			next_room = next_room and queue[index].distance_to(queue[door_at]) <= Units.to_px(entity.light_search_radius_u + 0.5) \
				and rooms.room_at(queue[index]) != rooms.room_at(spot)
		await until(func() -> bool: return entity.get_state_name() == "PATROL", 300)
	check(lessons == [1, 2, 3] and entity.persistence == 3, "Each hunt she escapes is a level, up to %d and no further (%s)" % [entity.persistence_max, lessons])
	check(is_equal_approx(lengths[1] - lengths[0], 0.2) and is_equal_approx(lengths[3] - lengths[0], 0.6),
		"Each level makes the next search longer by the set time (%s)" % [lengths])
	check(stops[1] == stops[0] + 1, "And adds a point to it (%s stops)" % [stops])
	check(after_door == [0, 0, entity.NEXT_ROOM_POINTS, entity.NEXT_ROOM_POINTS] and next_room and stops[2] == stops[1] + 1 + entity.NEXT_ROOM_POINTS,
		"From level %d it also looks around in the room past the door: %d more stops there (%s after the door)" % [entity.persistence_next_room_level, entity.NEXT_ROOM_POINTS, after_door])
	# Her death teaches it nothing.
	entity.reset_encounter(vestibule_side, two)
	check(entity.persistence == 0, "A new attempt starts with nothing learned")
	entity.show()
	entity.active = true
	entity._patrol_wait = 999.0
	lessons.clear()
	entity._begin_search(false, spot)
	GameState.kill_player()
	await frames(60)
	entity.reset_encounter(vestibule_side, two)
	GameState.reset()
	check(entity.persistence == 0 and lessons.is_empty(), "It never learns from her dying")
	entity.persistence_max = 0
	entity.search_duration_range = Vector2(12.0, 18.0)
	entity.light_search_duration_range = Vector2(5.0, 8.0)
	entity.persistence_search_time = 3.0


# ---------------------------------------------------------------------- taps ---

## Viv in the kitchen, 6 u from the door (ring 2); it comes to that door from the vestibule.
func check_taps() -> void:
	entity.claw_taps = true
	entity.door_wait_range = Vector2(1.0, 1.0)
	entity.tap_listen_range = Vector2(2.0, 2.0)
	var viv := doorway + Vector2(-192, 0)
	await arm(viv)
	check(entity.is_hidden_from_viv(), "Set up: with the door shut, the room it stands in is not shown to her")
	await until(func() -> bool: return entity.is_at_door(), 400)
	var arrived := now()
	check(audio.heard_ring == 2, "Set up: she hears it near, not on top of her (ring %d)" % audio.heard_ring)
	check(tap_rounds.size() == 1 and tap_rounds[0] == door and entity.is_tapping(), "Unaware, at a door she is behind, it starts to tap on it")
	await until(func() -> bool: return taps.size() >= 3 or door.is_open, 200)
	check(taps.size() == 3 and not door.is_open, "Three taps of its claws, from where it stands, the door still shut")
	if taps.size() == 3:
		check(taps[1] - taps[0] > 0.15 and taps[2] - taps[1] > 0.15 and taps[2] - taps[0] < 1.0, "A quarter of a second apart (%.2f s, %.2f s)" % [taps[1] - taps[0], taps[2] - taps[1]])
	var last_tap := now()
	await until(func() -> bool: return door.is_open, 400)
	check(door.is_open and now() - last_tap >= 1.9 and pushes == [false], "It stands listening for %.0f s (%.1f s), then pushes the door" % [entity.tap_listen_range.x, now() - last_tap])
	check(now() - arrived > 2.5, "Longer at the door than without the taps (%.1f s)" % (now() - arrived))
	check(noises == 0 and listens == 0 and entity.get_state_name() == "PATROL" and cues.is_empty(),
		"The taps are no noise event: it hears nothing, and nothing says it knows anything")
	check(entity._tap_cooldown >= entity.tap_gap_range.x - 5.0, "The next round is at least %.0f s away" % entity.tap_gap_range.x)
	# Not again at the next door.
	door.snap(false)
	var again: Array[Vector2] = [kitchen_side + Vector2(-64, 0), vestibule_side]
	entity.reset_encounter(vestibule_side, again)
	entity.show()
	entity.active = true
	entity._patrol_wait = 0.0
	entity._tap_cooldown = 60.0
	await frames(3)
	audio.placed()
	clear()
	await until(func() -> bool: return door.is_open, 600)
	check(door.is_open and tap_rounds.is_empty() and taps.is_empty(), "Inside that time it only waits and pushes: no taps")
	entity.door_wait_range = Vector2(0.6, 1.4)
	entity.tap_listen_range = Vector2(2.0, 3.0)


func check_when_it_does_not_tap() -> void:
	var viv := doorway + Vector2(-192, 0)
	await arm(viv)
	entity._patrol_wait = 999.0
	entity.global_position = doorway + Vector2(60, 0)        # by the door, clear of its doorway
	await frames(2)
	audio.placed()
	await frames(1)
	check(not entity.is_at_door() and entity._may_tap(door), "Set up: standing by the door, she behind it and near, it may tap")
	entity.claw_taps = false
	check(not entity._may_tap(door), "Not when taps are switched off")
	entity.claw_taps = true
	entity._tap_cooldown = 10.0
	check(not entity._may_tap(door), "Not before the gap since the last round is over")
	entity._tap_cooldown = 0.0
	# She can see where it stands.
	door.snap(true)
	await frames(2)
	check(not entity.is_hidden_from_viv() and not entity._may_tap(door), "Not when the door is open and its room is shown to her")
	door.snap(false)
	await frames(2)
	# On top of her, and too far to hear.
	game.player.global_position = doorway + Vector2(-40, 0)
	rooms.sync_to(game.player.global_position)
	await frames(2)
	audio.placed()
	await frames(1)
	check(audio.heard_ring == 3 and not entity._may_tap(door), "Not when it is on top of her (ring %d)" % audio.heard_ring)
	door.snap(false)
	game.player.global_position = game.world.marker("house", "Patrol4")      # the far end of the altar room
	rooms.sync_to(game.player.global_position)
	await frames(2)
	audio.placed()
	await frames(1)
	check(audio.heard_ring == 0 and not entity._may_tap(door), "Not when she is too far to hear it (ring %d)" % audio.heard_ring)
	# Once it knows something.
	game.player.global_position = viv
	rooms.sync_to(viv)
	await frames(2)
	audio.placed()
	await frames(1)
	check(entity._may_tap(door), "(back where it may)")
	entity._change_state(entity.State.SEARCH)
	check(not entity._may_tap(door), "Not while it searches: only while it knows nothing")
	entity._change_state(entity.State.PATROL)
	NoiseManager.emit_noise(entity.global_position + Vector2(20, 0), Units.to_px(8.0), NoiseManager.SourceType.THROW)
	check(entity.is_listening() and not entity._may_tap(door), "Not while it listens")
	# A round under way ends the moment it hears something.
	await arm(viv)
	entity.door_wait_range = Vector2(1.0, 1.0)
	await until(func() -> bool: return entity.is_tapping(), 400)
	NoiseManager.emit_noise(entity.global_position + Vector2(20, 0), Units.to_px(8.0), NoiseManager.SourceType.THROW)
	await frames(3)
	var so_far := taps.size()
	await frames(60)
	check(not entity.is_tapping() and taps.size() == so_far and so_far < 3, "Hearing something cuts a round of taps short (%d of 3 sounded)" % so_far)
	entity.door_wait_range = Vector2(0.6, 1.4)


## The same reasoning as the entity's knock: the loudest a tap may be, as near as ring 2 gets,
## out of complete silence, rises less than what the audit calls a jump.
func check_tap_is_no_jump_scare() -> void:
	await arm(doorway + Vector2(-76, 0))
	entity._patrol_wait = 999.0
	entity.global_position = doorway + Vector2(60, 0)
	await frames(2)
	audio.placed()
	await frames(1)
	check(audio.heard_ring == 2 and audio.heard_u < settings.ring_on_top_u + 0.5, "Set up: Viv as close as ring 2 gets (ring %d, %.1f u)" % [audio.heard_ring, audio.heard_u])
	check(entity.tap_db <= -6.0, "A tap is softer than its floor pats (%.0f dB)" % entity.tap_db)
	var voice := audio.play_set(TAP_SET, entity.tap_db)
	check(voice != null and voice.bus == AudioBus.ENTITY, "A tap this near gets through, on the Entity bus")
	if voice == null:
		return
	var worst: float = PREPARED_PEAK_DB + voice.volume_db + AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioBus.ENTITY)) \
		+ AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master"))
	print("[Entity night] worst case: tap at %.1f dB peaks at %.1f dB, %.1f dB over the audit's floor" % [voice.volume_db, worst, worst - settings.audit_floor_db])
	check(worst - settings.audit_floor_db < settings.audit_jump_db,
		"Out of complete silence, the loudest a tap may be rises less than the audit's %.0f dB (%.1f dB)" % [settings.audit_jump_db, worst - settings.audit_floor_db])
	voice.stop()


# ------------------------------------------------------------------ the night ---

## The Hacienda switches learning and taps on; the stairs keep what it learned; a death does not.
func check_the_night() -> void:
	entity.claw_taps = true        # as the scene has it; the first house switched it off
	game._entity_claw_taps = true
	game.enter_zone("mansion_ground", Vector2.INF, false)
	await frames(4)
	check(entity.persistence_max == 3 and entity.claw_taps and entity.persistence == 0, "In the Hacienda it learns (up to %d) and may tap" % entity.persistence_max)
	entity.persistence = 2
	game.enter_zone("mansion_upper", Vector2.INF, false)
	await frames(4)
	check(entity.persistence == 2, "Up the stairs it still knows what it learned that night")
	game.resetting = true
	game.enter_zone("mansion_ground", Vector2.INF, false)
	await frames(4)
	game.resetting = false
	check(entity.persistence == 0, "After a death and a retry it has learned nothing")
	entity.persistence = 3
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	check(entity.persistence == 0 and entity.persistence_max == 0 and not entity.claw_taps, "Back in the first house both are off again")
