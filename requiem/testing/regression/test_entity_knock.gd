extends Node
## The entity knocks (headless), Step 18: behind a switch that is off by default. When it is
## on and the entity stands still on its patrol next to a door, it knocks on it once, at most
## once every entity_knock_gap, from where it stands, on the Entity bus, with its own knock set
## (never the house's knock), only while Viv hears it in ring 2 or 1. It is only a sound: no
## noise, and nothing the entity does or knows changes. The knock set is empty today, so the
## checks that need a file use a stand-in (one of its taps, renamed into the knock folder in
## memory): no file is added to the project.

const KNOCK := EntityAudio.KNOCK
## A tap of the entity, prepared at the level a knock would be (-20 LUFS): the stand-in.
const STAND_IN_SET := "entity/pat_tap"
## Positions relative to the kitchen door's doorway (house zone, pixels). The kitchen wall runs
## north-south through the door: the vestibule is to the east (+x), the kitchen to the west.
const BY_DOOR := Vector2(44, 0)                 # 1.4 u from the doorway, in the vestibule
const BY_DOOR_KITCHEN := Vector2(-44, 0)        # the same, on the kitchen side
## Viv, relative to the entity standing BY_DOOR.
const VIV_NEAR := Vector2(192, 0)               # 6 u across the vestibule: ring 2
const VIV_NEAR_EDGE := Vector2(136, 0)          # 4.25 u: ring 2, as close as ring 2 gets
const VIV_ON_TOP := Vector2(64, 0)              # 2 u: ring 3
const VIV_SOMEWHERE := Vector2(320, -96)        # 10.4 u: ring 1
## Viv in the vestibule, the entity in the kitchen by the door: a wall in the way.
const VIV_BEYOND_WALL := Vector2(120, -180)
## The middle of the vestibule: no doorway within reach. Viv 6 u from it.
const NO_DOOR := Vector2(640, 300)
const NO_DOOR_VIV := Vector2(640, 492)
## Far off in the altar room: ring 0 from by the kitchen door.
const FAR := Vector2(1110, 600)
## The loudest peak any prepared file has (tools/audio/prepare_sounds.py, CEILING_DB).
const PREPARED_PEAK_DB := -1.0
## How long a scene is watched for a knock that must not come.
const WATCH := 1.2

var failures: Array[String] = []
var checks := 0
var settings: SoundSettings
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
var house := Vector2.ZERO
var door: Door
var doorway := Vector2.ZERO
var noises := 0
## Every knock that played: { voice, stream, volume_db, at, entity_at, heard_at, panning }.
var knocks: Array[Dictionary] = []
var stand_ins: Array[AudioStream] = []
## How many knocks the played signal reported (counted apart from `knocks`).
var signalled := 0
## The settings this suite changes, as they were.
var _saved := {}


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func near(a: float, b: float, tolerance := 0.05) -> bool:
	return absf(a - b) <= tolerance


func _ready() -> void:
	settings = SoundSettings.current()
	for key in ["entity_knocks_enabled", "entity_knock_gap", "entity_knock_first", "entity_knock_still"]:
		_saved[key] = settings.get(key)
	check_settings()
	await set_up()
	await check_off()
	await check_empty()
	await check_knock()
	await check_gap()
	await check_never()
	await check_after_alert()
	await check_wall()
	await check_patrol()
	await check_stops()
	check_house()
	await check_audit()
	check(noises == 0, "No knock made a noise the entity could hear (%d noise events)" % noises)
	for key in _saved:
		settings.set(key, _saved[key])
	use_stand_in(false)
	game.queue_free()
	await frames(3)
	print("[Entity knock tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func check_settings() -> void:
	check(not settings.entity_knocks_enabled, "The switch is off by default")
	check(near(settings.entity_knock_gap, 120.0) and near(settings.entity_knock_first, 30.0) and near(settings.entity_knock_still, 0.4)
		and near(settings.entity_knock_door_u, 1.5) and near(settings.entity_knock_db, -6.0),
		"At most once every 2 minutes, not in its first 30 s of calm, after 0.4 s standing still, within 1.5 u of a doorway, 6 dB under its file")
	check(not FileAccess.get_file_as_string("res://audio/sound_settings.tres").contains("knock"),
		"The values live in sound_settings.gd; sound_settings.tres stores none")
	check(EntityAudio.KNOCK_FOLDER == "res://assets/audio/entity/knock/" and DirAccess.dir_exists_absolute(EntityAudio.KNOCK_FOLDER)
		and FileAccess.file_exists(EntityAudio.KNOCK_FOLDER + ".gitkeep") and SoundLibrary.files(KNOCK).is_empty(),
		"Its own set, entity/knock, is there and empty today")
	check(not SoundLibrary._warned.has(KNOCK), "Looking at the empty folder warns nothing")
	check(not settings.house_knock.begins_with(EntityAudio.KNOCK_FOLDER) and not settings.house_knock.begins_with(HouseVoice.ENTITY_FILES),
		"The house's knock lives elsewhere (%s)" % settings.house_knock.get_file())
	var source := FileAccess.get_file_as_string("res://entities/entity_audio.gd")
	check(not source.contains("NoiseManager") and not source.contains("house_knock"),
		"The entity's sounds never call NoiseManager and never name the house's knock")
	# The stand-ins: the entity's own taps, renamed into the knock folder in memory only.
	for tap in SoundLibrary.files(STAND_IN_SET):
		var copy := tap.duplicate() as AudioStream
		copy.take_over_path(EntityAudio.KNOCK_FOLDER + "stand_in_" + tap.resource_path.get_file())
		stand_ins.append(copy)
	check(stand_ins.size() >= 2, "Stand-in knocks were made from the entity's taps (%d)" % stand_ins.size())


## The stand-in files in the knock set (on), or the real, empty folder again (off).
func use_stand_in(on: bool) -> void:
	SoundLibrary._sets.erase(KNOCK)
	SoundLibrary._files.erase(KNOCK)
	if on:
		SoundLibrary._files[KNOCK] = stand_ins.duplicate()


func set_up() -> void:
	GameState.reset()
	NoiseManager.noise_emitted.connect(func(_at: Vector2, _radius: float, _source: int, _duration: float) -> void: noises += 1)
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
	house = game.world.zones["house"].global_position
	door = game.world.interactables["kitchen_door"]["node"]
	doorway = door.get_noise_origin()
	# Nobody moves or makes a sound here: both are placed by hand, and it stands still.
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	var route: Array[Vector2] = [doorway + BY_DOOR]
	entity.reset_encounter(doorway + BY_DOOR, route)
	entity.show()
	entity.active = true
	entity.set_physics_process(false)
	audio.played.connect(_on_played)
	noises = 0


func _on_played(set_id: String, voice: AudioStreamPlayer2D) -> void:
	if set_id == KNOCK:
		knocks.append({"voice": voice, "stream": voice.stream, "volume_db": voice.volume_db, "at": voice.global_position,
			"entity_at": entity.global_position, "heard_at": audio.heard.global_position, "panning": voice.panning_strength,
			"bus": voice.bus, "ring": audio.heard_ring, "clock": audio._clock})


## Puts the entity and Viv in place (world pixels); it is heard from there at once.
func place(entity_at: Vector2, viv_at: Vector2) -> void:
	entity.global_position = entity_at
	entity.velocity = Vector2.ZERO
	game.player.global_position = viv_at
	await frames(2)
	audio.placed()
	await frames(1)


## A clean start for one scene: no knock yet, nothing calm yet, nothing remembered.
func fresh() -> void:
	knocks.clear()
	audio._last_knock = -INF
	audio._end_pause(true)
	audio._knock.stop()


## It walks off for a moment and stops again: a new patrol pause.
func new_pause() -> void:
	entity.velocity = Vector2(Units.to_px(settings.moving_speed_u) * 4.0, 0.0)
	var walked := 0
	while audio._paused_for > 0.0 or walked < 2:
		await get_tree().process_frame
		walked += 1
	entity.velocity = Vector2.ZERO
	await get_tree().process_frame


func check_off() -> void:
	use_stand_in(true)
	fresh()
	await place(doorway + BY_DOOR, doorway + BY_DOOR + VIV_NEAR)
	settings.entity_knock_first = 0.0
	await seconds(WATCH * 2.0)
	check(audio.heard_ring == 2 and Dread.awareness_of(entity, audio) == Dread.Awareness.PAUSED,
		"Set up: it stands still on its patrol by the kitchen door, Viv across the room (ring %d)" % audio.heard_ring)
	check(knocks.is_empty() and not audio._knock.playing and audio._knock.stream == null and not audio.plays.has(KNOCK)
		and audio._calm_for == 0.0 and audio._paused_for == 0.0 and audio.last_knock.is_empty(),
		"Switched off (the default), with files there, it never knocks and nothing of the knock even counts")


func check_empty() -> void:
	use_stand_in(false)
	fresh()
	settings.entity_knocks_enabled = true
	await seconds(WATCH)
	check(knocks.is_empty() and not audio._knock.playing and not SoundLibrary._warned.has(KNOCK),
		"Switched on with the folder empty, it never knocks, and nothing is warned")


func check_knock() -> void:
	use_stand_in(true)
	fresh()
	var state: int = entity.current_state
	var awareness: int = Dread.awareness
	var at: Vector2 = entity.global_position
	signalled = 0
	var callback := func(set_id: String, _voice: AudioStreamPlayer2D) -> void: signalled += int(set_id == KNOCK)
	audio.played.connect(callback)
	await seconds(settings.entity_knock_still + 0.3)
	check(knocks.size() == 1 and signalled == 1, "Switched on, with a file, standing by a door in ring 2: one knock (%d)" % knocks.size())
	if knocks.is_empty():
		audio.played.disconnect(callback)
		return
	var knock: Dictionary = knocks[0]
	var voice: AudioStreamPlayer2D = knock.voice
	check(voice == audio._knock and voice.name == "Knock" and voice.get_parent() == audio and voice.get_parent() != audio.heard,
		"It plays on its own voice, Knock, on the entity itself (not under Heard)")
	check(knock.at.distance_to(knock.entity_at) < 0.5, "From where it stands (%s, it stands at %s)" % [knock.at, knock.entity_at])
	check(knock.bus == AudioBus.ENTITY, "On the Entity bus")
	var path: String = knock.stream.resource_path
	check(path.begins_with(EntityAudio.KNOCK_FOLDER) and path != settings.house_knock and not stand_ins.filter(func(s: AudioStream) -> bool: return s == knock.stream).is_empty(),
		"From its own knock set, not the house's knock (%s)" % path)
	var expected: float = SoundLibrary.gain_db(KNOCK) + settings.entity_knock_db + EntityAudio.position_db(audio.heard_u, audio.reach_limit_u()) + audio.masked_db()
	check(near(knock.volume_db, expected, 0.01) and knock.volume_db < settings.entity_knock_db,
		"At the set's level, %.0f dB, less what it loses on the way (%.1f dB, expected %.1f)" % [settings.entity_knock_db, knock.volume_db, expected])
	check(near(knock.panning, audio._panning, 0.001) and voice.max_distance >= EntityAudio.NO_ENGINE_FALLOFF_PX,
		"Placed as exactly as distance allows, with the engine's own falloff off")
	check(voice.pitch_scale >= 1.0 - settings.set_pitch_range - 0.001 and voice.pitch_scale <= 1.0 + settings.set_pitch_range + 0.001,
		"Its pitch varies a little, like every set (%.3f)" % voice.pitch_scale)
	check(audio.last_set == KNOCK and int(audio.plays.get(KNOCK, 0)) == 1 and audio.last_knock.get("door") == door,
		"The read-outs see it: played was emitted, it is counted, and it knocked on the kitchen door")
	check(noises == 0 and entity.current_state == state and Dread.awareness == awareness and Dread.awareness_of(entity, audio) == Dread.Awareness.PAUSED
		and entity.global_position == at and entity.velocity == Vector2.ZERO and not entity.is_listening(),
		"No noise; its state, what it knows and where it stands are what they were")
	await seconds(WATCH * 2.0)
	check(knocks.size() == 1, "Once in a pause, however long it stands there")
	audio.played.disconnect(callback)


func check_gap() -> void:
	settings.entity_knock_gap = 3.0
	fresh()
	await seconds(settings.entity_knock_still + 0.3)
	var first := knocks.size()
	for pause in 3:
		await new_pause()
		await seconds(settings.entity_knock_still + 0.3)
	check(first == 1 and knocks.size() == 1, "Not again within the gap, also across three more pauses (%d)" % knocks.size())
	# Still standing in the last of those pauses when the gap runs out: it knocks then, once.
	await until_knocks(2, settings.entity_knock_gap)
	check(knocks.size() == 2 and knocks[1].clock - knocks[0].clock >= settings.entity_knock_gap,
		"Once the gap is over it knocks again (%.1f s apart)" % (knocks[1].clock - knocks[0].clock if knocks.size() == 2 else 0.0))
	await new_pause()
	await seconds(settings.entity_knock_still + 0.3)
	check(knocks.size() == 2, "And then not in the next pause, within the gap again (%s)" % [knocks.map(func(k: Dictionary) -> String: return "%.2f" % k.clock)])
	settings.entity_knock_gap = float(_saved["entity_knock_gap"])


## One scene where it must not knock: `set_up` changes something, `undo` puts it back.
func never(what: String, entity_at: Vector2, viv_at: Vector2, set_up_scene: Callable, undo: Callable) -> void:
	fresh()
	await place(entity_at, viv_at)
	set_up_scene.call()
	await seconds(WATCH)
	check(knocks.is_empty() and not audio._knock.playing, "Never %s" % what)
	undo.call()
	await frames(1)


func check_never() -> void:
	var by_door := doorway + BY_DOOR
	var nothing := func() -> void: pass
	await place(by_door, by_door + VIV_ON_TOP)
	check(audio.heard_ring == 3, "Set up: Viv on top of it (ring %d)" % audio.heard_ring)
	await never("with Viv on top of it (ring 3)", by_door, by_door + VIV_ON_TOP, nothing, nothing)
	await place(by_door, house + FAR)
	check(audio.heard_ring == 0, "Set up: Viv far off in the house (ring %d)" % audio.heard_ring)
	await never("with nobody to hear it (ring 0)", by_door, house + FAR, nothing, nothing)
	var spent: bool = audio._last_knock == -INF
	check(spent, "And the gap is not spent on a knock nobody hears")
	await never("while it walks", by_door, by_door + VIV_NEAR,
		func() -> void: entity.velocity = Vector2(Units.to_px(settings.moving_speed_u) * 4.0, 0.0),
		func() -> void: entity.velocity = Vector2.ZERO)
	await place(house + NO_DOOR, house + NO_DOOR_VIV)
	check(audio.heard_ring == 2, "Set up: in the middle of the vestibule, Viv across the room (ring %d)" % audio.heard_ring)
	await never("with no door within reach", house + NO_DOOR, house + NO_DOOR_VIV, nothing, nothing)
	await never("while it listens", by_door, by_door + VIV_NEAR,
		func() -> void: entity._listening = 60.0, func() -> void: entity._listening = 0.0)
	await never("while it searches", by_door, by_door + VIV_NEAR,
		func() -> void: entity.current_state = EntityAudio.SEARCH, func() -> void: entity.current_state = EntityAudio.PATROL)
	await never("while it hunts", by_door, by_door + VIV_NEAR,
		func() -> void: entity.current_state = EntityAudio.HUNT, func() -> void: entity.current_state = EntityAudio.PATROL)
	await never("while it catches", by_door, by_door + VIV_NEAR,
		func() -> void: entity.sprite_rig.mode = "catch", func() -> void: entity.sprite_rig.reset())
	await never("when Viv is dead", by_door, by_door + VIV_NEAR,
		func() -> void: GameState.is_dead = true, func() -> void: GameState.is_dead = false)
	await never("while it is hidden", by_door, by_door + VIV_NEAR, entity.hide, entity.show)
	await never("while it is inactive", by_door, by_door + VIV_NEAR,
		func() -> void: entity.active = false, func() -> void: entity.active = true)
	settings.entity_knock_first = 60.0
	await never("in its first moments of calm (entity_knock_first)", by_door, by_door + VIV_NEAR, nothing, nothing)
	settings.entity_knock_first = 0.0
	# And with everything back, the same place knocks: the scenes above were the only reason.
	fresh()
	await place(by_door, by_door + VIV_NEAR)
	await seconds(settings.entity_knock_still + 0.3)
	check(knocks.size() == 1, "Back in the same place, nothing else changed, it knocks")


## It just gave up a search (or heard something): not before it has been calm again for a while.
func check_after_alert() -> void:
	settings.entity_knock_first = 2.0
	fresh()
	await place(doorway + BY_DOOR, doorway + BY_DOOR + VIV_NEAR)
	entity.current_state = EntityAudio.SEARCH
	await seconds(0.5)
	entity.current_state = EntityAudio.PATROL
	await seconds(settings.entity_knock_first - 0.5)
	var early := knocks.size()
	await seconds(1.0)
	check(early == 0 and knocks.size() == 1, "After a search it waits until it has been calm for entity_knock_first, then knocks (%d, %d)" % [early, knocks.size()])
	settings.entity_knock_first = 0.0


## The entity in the kitchen, Viv in the vestibule: its other sounds come round through the
## doorway, the knock from where it stands.
func check_wall() -> void:
	fresh()
	await place(doorway + BY_DOOR_KITCHEN, doorway + VIV_BEYOND_WALL)
	var reading := Acoustics.reading(entity)
	await seconds(settings.entity_knock_still + 0.3)
	print("[Entity knock] wall: ring %d, blocked %s, through opening %s, heard from %s, entity %s, Heard %s" % [
		audio.heard_ring, reading.blocked, reading.through_opening, reading.heard_from - house, entity.global_position - house, audio.heard.global_position - house])
	check(settings.doorway_panning and reading.blocked and reading.through_opening and audio.heard.global_position.distance_to(entity.global_position) > 8.0,
		"Set up: a wall in the way, its other position sounds come from the doorway (ring %d)" % audio.heard_ring)
	check(knocks.size() == 1 and knocks[0].at.distance_to(knocks[0].entity_at) < 0.5 and knocks[0].at.distance_to(knocks[0].heard_at) > 8.0
		and knocks[0].voice.get_parent() == audio,
		"With a wall in the way the knock still comes from where it stands, not from the doorway")


## The real thing: it walks its patrol, and pauses by the door now and then.
func check_patrol() -> void:
	fresh()
	settings.entity_knock_gap = float(_saved["entity_knock_gap"])
	var by_door := doorway + BY_DOOR
	var away := by_door + Vector2(0, -160)
	var route: Array[Vector2] = [by_door, away]
	for each in game.world.zones["house"].get_node("Doors").get_children():
		if each is Door:
			each.noise_radius_u = 0.0          # a door it pushes open makes its own noise; not ours
			each.quiet_noise_radius_u = 0.0
	entity.reset_encounter(by_door, route)
	entity.show()
	entity.active = true
	entity.set_physics_process(true)
	game.player.global_position = by_door + VIV_NEAR
	await frames(2)
	audio.placed()
	var pauses := 0
	var was_still := false
	var moved_while_knocking := false
	var clock := 0.0
	while clock < 30.0 and pauses < 3:
		await get_tree().physics_frame
		clock += get_physics_process_delta_time()
		var still: bool = Dread.awareness_of(entity, audio) == Dread.Awareness.PAUSED
		if still and not was_still:
			pauses += 1
		was_still = still
		if audio._knock.playing and entity.velocity.length() > Units.to_px(settings.moving_speed_u):
			moved_while_knocking = true
	entity.set_physics_process(false)
	entity.velocity = Vector2.ZERO
	check(pauses >= 3, "On its real patrol it paused by the door and away from it (%d pauses)" % pauses)
	check(knocks.size() == 1 and knocks[0].entity_at.distance_to(doorway) <= Units.to_px(settings.entity_knock_door_u) + 0.5,
		"It knocked once, in a pause by the door, and not again within two minutes (%d)" % knocks.size())
	check(entity.get_state_name() == "PATROL" and not moved_while_knocking, "It stayed on its patrol; the knock never moved it")


## Waits (up to `limit` s) for a knock to start; true when one is playing.
func knock_starts(limit := 2.0) -> bool:
	await until_knocks(1, limit)
	return audio._knock.playing


## Waits until `count` knocks have played, or `limit` seconds.
func until_knocks(count: int, limit: float) -> void:
	var clock := 0.0
	while knocks.size() < count and clock < limit:
		await get_tree().process_frame
		clock += get_process_delta_time()


func check_stops() -> void:
	fresh()
	await place(doorway + BY_DOOR, doorway + BY_DOOR + VIV_NEAR)
	var playing: bool = await knock_starts()
	audio.stop_all()
	check(playing and not audio._knock.playing, "stop_all() cuts the knock")
	fresh()
	await new_pause()
	playing = await knock_starts()
	GameState.is_dead = true
	await frames(2)
	check(playing and not audio._knock.playing, "Her death cuts the knock")
	GameState.is_dead = false


func check_house() -> void:
	check(not HouseVoice.allowed(stand_ins[0]) and not HouseVoice.allowed(SoundLibrary.files(STAND_IN_SET)[0]),
		"The house still refuses every file of the entity, the knock folder too")
	check(settings.house_knock.get_file() == "door_knock_01.wav" and not settings.house_knock.contains("/entity/"),
		"And the house's knock is still its own file")


## The loudest the Master meter (or another bus's) reads over `time` seconds.
func master_peak(time: float, bus_name: StringName = &"Master") -> float:
	var bus := AudioServer.get_bus_index(bus_name)
	var loudest := -INF
	var clock := 0.0
	while clock < time:
		await get_tree().process_frame
		clock += get_process_delta_time()
		loudest = maxf(loudest, maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0)))
	return loudest


## A knock in ring 2, as close as ring 2 gets, is no jump scare.
func check_audit() -> void:
	var overlay: Node = preload("res://testing/tools/noise_debug.gd").new()
	add_child(overlay)
	overlay.enabled = true
	var audit: Node = overlay.audit
	settings.entity_knock_gap = 0.0
	var by_door := doorway + BY_DOOR
	await place(by_door, by_door + VIV_NEAR_EDGE)
	await seconds(1.0)          # its breath settles in
	check(audio.heard_ring == 2, "Set up: Viv as close as ring 2 gets (ring %d, %.1f u)" % [audio.heard_ring, audio.heard_u])
	audit.clear()
	fresh()
	var loudest := -INF
	var breath_only := -INF
	for file in stand_ins.size():
		await new_pause()
		breath_only = maxf(breath_only, await master_peak(settings.entity_knock_still * 0.75))
		loudest = maxf(loudest, await master_peak(1.0))
	print("[Entity knock] audit: %d knocks, Master peaks at %.1f dB with only its breath, %.1f dB with the knock; %s" % [
		knocks.size(), breath_only, loudest, audit.summary()])
	check(knocks.size() >= stand_ins.size() and audit.readings > 50 and loudest > settings.audit_floor_db,
		"The knocks were heard on the real Master meter (%d knocks, loudest %.1f dB)" % [knocks.size(), loudest])
	check(audit.unexplained().is_empty(), "No knock is a jump scare: %s" % audit.summary())
	# The worst case, worked out rather than metered (a short tap is caught unevenly by the
	# headless meters): a knock file as loud as the sound tools let any file be (peaks at -1 dB),
	# panned hard to one side, out of complete silence, as near as ring 2 allows.
	var level: float = knocks.back().volume_db
	var worst: float = PREPARED_PEAK_DB + level + AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioBus.ENTITY)) \
		+ AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master"))
	print("[Entity knock] worst case: knock at %.1f dB, Entity bus %.1f dB, Master %.1f dB: peaks at %.1f dB, %.1f dB over the audit's floor (%.1f while she holds her breath to listen)" % [
		level, AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioBus.ENTITY)), AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master")),
		worst, worst - settings.audit_floor_db, worst - settings.audit_floor_db + settings.listen_entity_db])
	check(worst - settings.audit_floor_db < settings.audit_jump_db,
		"Even out of complete silence, hard to one side, the loudest file a knock may be would rise less than the audit's %.0f dB (%.1f dB)" % [
		settings.audit_jump_db, worst - settings.audit_floor_db])
	settings.entity_knock_gap = float(_saved["entity_knock_gap"])
	overlay.queue_free()
