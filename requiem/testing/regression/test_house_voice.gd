extends Node
## The house voice (headless): the house's own quiet sounds.
## They come from rooms Viv is not in, on World, quietly, with a soft start; effects are rare,
## far apart and never repeat; one roll in six is "nothing" (the ambience thins). None plays
## while the entity is alert or near, just after an awareness cue, or while she prays, and the
## voice can always say why it is silent. One loud thing she does may be answered by a single
## knock. It never plays an entity file and never makes noise the entity can hear.

const VESTIBULE_A := Vector2(520, 400)
const VESTIBULE_B := Vector2(680, 400)
const BEHIND_WALL := "res://tutorial/assets/audio/behind_wall.wav"
const ENTITY_FILE_SET := "entity/claws_walk"

var failures: Array[String] = []
var checks := 0
var settings: SoundSettings
var game: Node2D
var entity: CharacterBody2D
var house := Vector2.ZERO
var rooms := {}
var noises := 0
## Everything the house sounded since the last clear: { family, file, at, level, caption, time, voice_db, bus }.
var sounds: Array[Dictionary] = []
var thinnings := 0
var captions_before := false


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


## Frames of the game itself (the house voice keeps its time there).
func ticks(count: int) -> void:
	for i in range(count): await get_tree().process_frame


func seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func near(a: float, b: float, tolerance := 0.05) -> bool:
	return absf(a - b) <= tolerance


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	settings = SoundSettings.current()
	check_settings()
	check_no_house()
	await set_up()
	await check_effects()
	await check_nothing()
	await check_gates()
	await check_answer()
	await check_settle()
	await check_story()
	check(HouseVoice.violations == 0 and HouseVoice.history.all(func(entry: Dictionary) -> bool: return entry.gate == ""),
		"Nothing the house did played while its gates were closed")
	check(noises == 0, "The house made no noise the entity could hear (%d)" % noises)
	Preferences.captions = captions_before
	game.queue_free()
	await frames(3)
	check(not HouseVoice.in_a_house() and HouseVoice.gate() == "no house here", "When the level goes, the house voice goes with it")
	print("[House voice tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func check_settings() -> void:
	check(settings.house_max_lufs == -26.0, "No house sound is louder than -26 LUFS")
	check(settings.house_effect_gap.x >= 90.0 and settings.house_effect_gap.y >= settings.house_effect_gap.x, "Effects are at least 90 s apart")
	check(settings.house_nothing_one_in == 6 and near(settings.house_nothing_time, 4.0, 0.001), "One roll in six is nothing: the ambience thins for 4 s")
	check(settings.house_after_cue == 20.0, "After an awareness cue the house is quiet for 20 s")
	check(near(settings.house_answer_delay, 1.0, 0.3), "The answering knock comes about a second later")
	var effects: Array[Dictionary] = HouseVoice.effects()
	check(effects.size() >= 4 and effects.all(func(entry: Dictionary) -> bool: return ResourceLoader.exists(entry.file)), "The house has a knock, a creak, a fall and a dragged chair (%d effects)" % effects.size())
	check(effects.all(func(entry: Dictionary) -> bool:
		return float(entry.lufs) + HouseVoice.level_for(float(entry.lufs)) <= settings.house_max_lufs + 0.001 and HouseVoice.level_for(float(entry.lufs)) <= 0.0),
		"Each is turned down to -26 LUFS or less, and none is ever turned up")
	check(effects.all(func(entry: Dictionary) -> bool:
		return not String(entry.file).begins_with(HouseVoice.ENTITY_FILES) and not String(entry.file).contains(HouseVoice.BEHIND_WALL)),
		"None is a file of the entity, or the dragging behind the wall")
	check(effects.any(func(entry: Dictionary) -> bool: return entry.file == settings.house_knock), "The answering knock is one of them")
	var source := FileAccess.get_file_as_string("res://audio/house_voice.gd")
	check(not source.contains("NoiseManager") and not source.contains("AudioServer"), "The house voice makes no noise and touches no bus itself")
	check(MixDirector.Priority.HOUSE > MixDirector.Priority.THREAT and MixDirector.Priority.HOUSE < MixDirector.Priority.PRAYER,
		"Thinning the ambience wins over the slow mood of the house, and anything she does wins over it")
	check(SoundLibrary.files(HouseVoice.SETTLE).is_empty() and SoundLibrary.files(HouseVoice.EFFECTS).is_empty() and SoundLibrary._warned.is_empty(),
		"The house's own sound folders are empty today, and that is not a warning")


func check_no_house() -> void:
	check(not HouseVoice.in_a_house() and HouseVoice.gate() == "no house here" and not HouseVoice.answer() and HouseVoice.spot_away() == Vector2.INF,
		"Outside a house there is no house voice")


func set_up() -> void:
	GameState.reset()
	captions_before = Preferences.captions
	Preferences.captions = true
	NoiseManager.noise_emitted.connect(func(_at: Vector2, _radius: float, _source: int, _duration: float) -> void: noises += 1)
	HouseVoice.sounded.connect(_on_sounded)
	HouseVoice.thinned.connect(func() -> void: thinnings += 1)
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	check(game.in_unease() and HouseVoice.in_a_house() and HouseVoice.story_holds, "Before the key, the tutorial tells the house's part itself (%s %s %s)" % [game.in_unease(), HouseVoice.in_a_house(), HouseVoice.story_holds])
	game.has_key = true          # past the tutorial's own unease and the arrival: the house is its own now
	await frames(3)
	house = game.world.zones["house"].global_position
	for room: String in game.UNEASE_SPOTS:
		rooms[room] = game.UNEASE_SPOTS[room].map(func(spot: Vector2) -> Vector2: return house + spot)
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.global_position = house + VESTIBULE_A
	game.world.rooms("house").sync_to(game.player.global_position)
	# The entity stands at the far end of the house, unaware.
	var far: Vector2 = game.world.marker("house", "Patrol4")
	var route: Array[Vector2] = [far]
	entity.reset_encounter(far, route)
	entity.show()
	entity.set_physics_process(false)
	await frames(3)
	entity.audio.placed()
	await seconds(0.4)
	noises = 0
	check(HouseVoice.in_a_house() and game._room_name() == "Vestibule" and not game.house_story() and not HouseVoice.story_holds,
		"In the house, past its story, the house voice knows the rooms and which one she is in")
	check(Dread.awareness <= Dread.Awareness.PAUSED and Acoustics.nearest_ring() < 2 and HouseVoice.gate() == "",
		"It is unaware and far off: the house may speak")
	check(HouseVoice.effect_gate().begins_with("it only just became safe") and HouseVoice.status().begins_with("settling"),
		"On coming in, the house waits a little before anything: %s" % HouseVoice.status())
	HouseVoice._open_wait = 0.0
	check(HouseVoice._effect_wait >= settings.house_effect_gap.x - 2.0 and HouseVoice.effect_gate().contains("far apart") and HouseVoice.status().begins_with("settling"),
		"The first effect is 90 s away or more, and the read-out says so: %s" % HouseVoice.status())


func _on_sounded(family: StringName, stream: AudioStream, at: Vector2, level_db: float, caption: String) -> void:
	var voice: AudioStreamPlayer2D = null
	for candidate in HouseVoice.get_children():
		if candidate is AudioStreamPlayer2D and candidate.stream == stream and candidate.global_position.is_equal_approx(at):
			voice = candidate
	sounds.append({"family": family, "file": stream.resource_path, "at": at, "level": level_db, "caption": caption, "time": now(),
		"voice": voice, "start_db": voice.volume_db if voice != null else 0.0, "bus": voice.bus if voice != null else &""})


## The room a place belongs to ("" when it is none of the house voice's places).
func room_of(at: Vector2) -> String:
	for room: String in rooms:
		for spot: Vector2 in rooms[room]:
			if spot.is_equal_approx(at): return room
	return ""


func check_effects() -> void:
	sounds.clear()
	thinnings = 0
	for roll in 60:
		HouseVoice.hurry()
		await ticks(2)
	var effects := sounds.filter(func(sound: Dictionary) -> bool: return sound.family == &"effect")
	check(effects.size() + thinnings == 60 and effects.size() >= 35, "Each time its turn comes it makes an effect or thins the ambience (%d effects, %d times nothing)" % [effects.size(), thinnings])
	check(thinnings >= 1 and thinnings <= 25, "About one roll in six is nothing (%d in 60)" % thinnings)
	var repeats := 0
	for index in range(1, effects.size()):
		repeats += int(effects[index].file == effects[index - 1].file)
	var used := {}
	for sound in effects: used[sound.file] = true
	check(repeats == 0 and used.size() == settings.house_effects.size(), "Never the same effect twice in a row, and every effect gets its turn (%d different)" % used.size())
	check(effects.all(func(sound: Dictionary) -> bool: return room_of(sound.at) != "" and room_of(sound.at) != "Vestibule"),
		"Every one comes from a room she is not in")
	check(effects.all(func(sound: Dictionary) -> bool: return sound.bus == AudioBus.WORLD), "On the World bus")
	var quiet := true
	for sound in effects:
		var entry: Dictionary = settings.house_effects.filter(func(candidate: Dictionary) -> bool: return candidate.file == sound.file)[0]
		quiet = quiet and float(entry.lufs) + sound.level <= settings.house_max_lufs + 0.001 and sound.caption == entry.caption
	check(quiet, "Each at -26 LUFS or less, with its caption")
	check(effects.all(func(sound: Dictionary) -> bool: return near(sound.start_db, sound.level + settings.house_attack_from_db, 0.5)),
		"Each starts soft: %.0f dB down" % -settings.house_attack_from_db)
	await seconds(settings.house_attack + 0.1)
	if effects.is_empty():
		return
	var last: Dictionary = effects.back()
	check(not is_instance_valid(last.voice) or near(last.voice.volume_db, last.level, 0.1), "And rises to its level in a moment")
	check(HouseVoice._effect_wait >= settings.house_effect_gap.x - 2.0, "After an effect the next is again 90 s away or more (%.0f s)" % HouseVoice._effect_wait)
	check(game.hud.caption.text == last.caption, "The level shows its caption: %s" % game.hud.caption.text)


func check_nothing() -> void:
	await seconds(settings.house_nothing_time + settings.house_nothing_fade + 0.3)      # any thinning from the rolls above is over
	var mood: float = settings.threat_world_db * MixDirector.recede()
	check(not MixDirector.is_active(HouseVoice.NOTHING_MIX) and near(MixDirector.gain_db(AudioBus.AMBIENCE), mood, 0.1), "Before: the ambience is where the mood of the house has it (%.1f dB)" % mood)
	var began := now()
	HouseVoice._nothing()
	await seconds(settings.house_nothing_fade + 0.2)
	check(MixDirector.is_active(HouseVoice.NOTHING_MIX) and near(MixDirector.gain_db(AudioBus.AMBIENCE), mood + settings.house_nothing_db, 0.3)
		and near(MixDirector.gain_db(AudioBus.WORLD), settings.threat_world_db * MixDirector.recede(), 0.1) and is_zero_approx(MixDirector.gain_db(AudioBus.MUSIC)),
		"Nothing: the ambience alone thins, %.0f dB under where it was (%.1f dB)" % [-settings.house_nothing_db, MixDirector.gain_db(AudioBus.AMBIENCE)])
	while MixDirector.is_active(HouseVoice.NOTHING_MIX) and now() - began < settings.house_nothing_time + 2.0:
		await ticks(1)
	check(near(now() - began, settings.house_nothing_time, 0.3), "It stays thin for about 4 s (%.1f s)" % (now() - began))
	await seconds(settings.house_nothing_fade + 0.2)
	check(near(MixDirector.gain_db(AudioBus.AMBIENCE), settings.threat_world_db * MixDirector.recede(), 0.1), "And then it returns")


## Asks for an effect on every frame for a while; returns how many sounds the house made.
func insist(time: float) -> int:
	sounds.clear()
	thinnings = 0
	var until := now() + time
	while now() < until:
		HouseVoice.hurry()
		HouseVoice._settle_wait = 0.0
		HouseVoice.answer()
		await ticks(1)
	return sounds.size() + thinnings


func check_gates() -> void:
	# Near.
	var far: Vector2 = entity.global_position
	entity.global_position = house + VESTIBULE_B
	await frames(2)
	entity.audio.placed()
	await frames(2)
	check(Acoustics.nearest_ring() >= 2 and HouseVoice.gate().begins_with("it is near") and HouseVoice.status().begins_with("silent: it is near"),
		"With it in the same room the house is silent, and says why: %s" % HouseVoice.gate())
	var made := await insist(0.6)
	check(made == 0 and not HouseVoice.answer(), "Nothing plays and nothing answers while it is near")
	entity.global_position = far
	await frames(2)
	entity.audio.placed()
	await frames(2)
	check(HouseVoice.gate() == "" and HouseVoice.effect_gate().begins_with("it only just became safe") and HouseVoice._open_wait >= settings.house_gate_settle.x - 0.2
		and HouseVoice._open_wait <= settings.house_gate_settle.y, "When it has gone, the house still waits a while before an effect (%.0f s)" % HouseVoice._open_wait)
	# Alert: heard, hunting, searching.
	entity.active = true
	entity.set_physics_process(true)
	entity.listen_time_range = Vector2(0.8, 0.8)
	entity.search_duration = 3.0
	var before := noises
	NoiseManager.emit_noise(entity.global_position + Vector2.LEFT * Units.to_px(3.0), Units.to_px(40.0), NoiseManager.SourceType.ENVIRONMENT)
	noises = before              # that one was this test's, not the house's
	await frames(3)
	check(Dread.awareness == Dread.Awareness.HEARD and HouseVoice.gate() == "it is alert (heard)", "The moment it hears something the house falls silent: %s" % HouseVoice.gate())
	var during := 0
	var seen := {}
	var deadline := now() + 14.0
	while now() < deadline:
		during += await insist(0.1)
		seen[Dread.awareness] = true
		if Dread.awareness == Dread.Awareness.HUNTING:
			entity._hunt_timer = entity.hunt_persistence       # the trail goes cold
		if seen.has(Dread.Awareness.SEARCHING) and Dread.awareness <= Dread.Awareness.PAUSED:
			break
	check(seen.has(Dread.Awareness.HEARD) and seen.has(Dread.Awareness.HUNTING) and seen.has(Dread.Awareness.SEARCHING) and during == 0,
		"Through the listen, the hunt and the search the house makes no sound at all")
	# Just after: the cue gate.
	entity.set_physics_process(false)
	entity.velocity = Vector2.ZERO
	entity.global_position = far
	await frames(2)
	entity.audio.placed()
	await frames(3)
	check(Dread.awareness <= Dread.Awareness.PAUSED and HouseVoice.gate().begins_with("an awareness cue played"),
		"After it has stood down the house stays quiet for 20 s more: %s" % HouseVoice.gate())
	made = await insist(0.5)
	check(made == 0, "And nothing plays in that time")
	HouseVoice._since_cue = settings.house_after_cue + 1.0
	await frames(2)
	check(HouseVoice.gate() == "" and HouseVoice._open_wait > 0.0, "Then it may speak again, after its wait")
	# Praying.
	GameState.is_praying = true
	var held := HouseVoice.gate()
	made = await insist(0.3)
	check(held == "she is praying" and made == 0, "While she prays the house is silent")
	GameState.is_praying = false
	await ticks(2)
	made = await insist(0.2)
	check(made >= 1, "Once every gate is open, it speaks")
	await seconds(settings.house_nothing_time + settings.house_nothing_fade + 0.2)


func check_answer() -> void:
	HouseVoice._since_answer = INF
	sounds.clear()
	var asked := now()
	check(HouseVoice.answer() and not HouseVoice.answer(), "A loud thing she does is answered once, however often it is asked")
	await seconds(settings.house_answer_delay + 0.3)
	check(sounds.size() == 1 and sounds[0].family == &"answer" and sounds[0].file == settings.house_knock and room_of(sounds[0].at) != "Vestibule"
		and near(sounds[0].time - asked, settings.house_answer_delay, 0.25),
		"A single knock from another room, about a second later (%.2f s)" % ((sounds[0].time - asked) if not sounds.is_empty() else -1.0))
	check(not HouseVoice.answer(), "And not again straight away")
	# Through the tutorial: a trunk lid or a rattled door asks the house.
	HouseVoice._since_answer = INF
	sounds.clear()
	game._house_answers()
	await seconds(settings.house_answer_delay + 0.3)
	check(sounds.size() == 1 and sounds[0].family == &"answer", "A slammed trunk in the tutorial is answered the same way")
	# An answer that would land in danger is dropped.
	HouseVoice._since_answer = INF
	sounds.clear()
	HouseVoice.answer()
	GameState.is_praying = true
	await seconds(settings.house_answer_delay + 0.3)
	GameState.is_praying = false
	check(sounds.is_empty(), "An answer that would come while its gates are closed is dropped, not delayed")


## The settling sounds: silent while their folder is empty; with a file in it, frequent and very quiet.
func check_settle() -> void:
	await ticks(2)
	sounds.clear()
	HouseVoice._settle_wait = 0.0
	await ticks(3)
	check(sounds.is_empty() and HouseVoice._settle_wait >= settings.house_settle_gap.x - 0.2 and not SoundLibrary._warned.has(HouseVoice.SETTLE),
		"With the settle folder empty the house does not settle, and does not complain")
	# A stand-in file, as if one had been dropped in each folder.
	var stand_in: Array[AudioStream] = [load(settings.house_effects[3].file) as AudioStream]
	SoundLibrary._files[HouseVoice.SETTLE] = stand_in
	SoundLibrary._files[HouseVoice.EFFECTS] = stand_in
	check(HouseVoice.effects().size() == settings.house_effects.size() + 1, "A file dropped in house/effects becomes an effect, with no code change")
	HouseVoice._settle_wait = 0.0
	await ticks(3)
	check(sounds.size() == 1 and sounds[0].family == &"settle" and room_of(sounds[0].at) != "Vestibule" and sounds[0].bus == AudioBus.WORLD
		and near(sounds[0].level, HouseVoice.level_for(settings.house_set_lufs) + settings.house_settle_db, 0.01) and sounds[0].caption == "",
		"A file dropped in house/settle is heard: from another room, %.0f dB under the effects, with no caption" % -settings.house_settle_db)
	SoundLibrary.clear()
	await frames(2)


## The tutorial's own part still goes through the same voice.
func check_story() -> void:
	sounds.clear()
	entity.hide()
	await frames(2)
	game.has_key = false         # back before the key: the tutorial tells this part itself
	await frames(2)
	check(game.in_unease() and game.house_story() and HouseVoice.story_holds and HouseVoice.gate() == "the level is telling its own part",
		"Before the key the tutorial tells the house's part, and the house voice keeps out of it")
	var made := await insist(0.3)
	check(made == 0, "So the house says nothing by itself then")
	var count: int = game.unease_count
	game.unease_time = game.unease_next
	await frames(3)
	check(game.unease_count == count + 1 and (room_of(game.unease_last_at) not in ["", "Vestibule"] or game.unease_last_at.distance_to(game.player.global_position) < game.UNEASE_BEHIND_DISTANCE + 1.0),
		"The tutorial's unease still sounds, from a room she is not in or right behind her")
	var drag := load(BEHIND_WALL) as AudioStream
	var own := HouseVoice.play(drag, house + VESTIBULE_B, -8.0, 1.0, game)
	check(own != null and own.get_parent() == game and own.bus == AudioBus.WORLD and own.is_in_group(HouseVoice.GROUP),
		"Before anything is in the house, the tutorial may still play its dragging behind the wall")
	var entity_file: AudioStream = SoundLibrary.files(ENTITY_FILE_SET)[0]
	check(HouseVoice.play(entity_file, house + VESTIBULE_B, -8.0) == null, "The house never plays a file of the entity")
	entity.show()
	await frames(2)
	check(Dread.entity_about() and HouseVoice.play(drag, house + VESTIBULE_B, -8.0, 1.0, game) == null,
		"And once the entity is out in the house, never the dragging behind the wall")
	game.has_key = true
