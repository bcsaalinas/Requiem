extends Node
## The house voice (headless): the house's own quiet sounds.
## They come from rooms Viv is not in, on World, quietly, with a soft start; effects are rare,
## far apart and never repeat; one roll in six is "nothing" (the ambience thins). None plays
## while the entity is alert or near, just after an awareness cue, or while she prays, and the
## voice can always say why it is silent. One loud thing she does may be answered by a single
## knock; if she keeps being loud, each answer comes a little closer (never from her room, up to
## -22 LUFS, three steps) until a quiet minute. After an effect, a door she cannot see may be
## found ajar, with a creak only she hears: drawn open, never really opened, once per run.
## It never plays an entity file and never makes noise the entity can hear.

const VESTIBULE_A := Vector2(520, 400)
const VESTIBULE_B := Vector2(680, 400)
const BEHIND_WALL := "res://tutorial/assets/audio/behind_wall.wav"
const ENTITY_FILE_SET := "entity/claws_walk"
## The door tests' own small layout, far from everything.
const ARENA := Vector2(-20000, -20000)
const DOOR_SCENE := preload("res://level/door/door_side.tscn")
## Where the door tests' effect sounds (arena px): the locked and the open door are nearer to it
## than any door that may be left ajar.
const EFFECT_AT := Vector2(700, 260)
## A second knock for the tests that need two knock files (not added to the repo: put in the
## knock set's place for the test only). Not one of house_effects, not of the entity.
const SECOND_KNOCK := "res://assets/audio/horror-jam-kit 2/WAV/Foley/metal_scrape_01.wav"
## Effect rolls driven directly to measure the share of knocks.
const ROLLS := 600

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
## Times a knock was asked for (hurry_knock) by insist(), and knocks that sounded meanwhile.
var knock_asks := 0
var knocks_heard := 0


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
	await check_knocks()
	await check_nothing()
	await check_gates()
	await check_answer()
	await check_escalation()
	await check_ajar()
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
	check(settings.house_max_lufs == -26.0, "No house sound is louder than -26 LUFS (except the answer that has come closest, up to -22)")
	check(settings.house_escalate_steps == 3 and settings.house_escalate_max_lufs == -22.0 and settings.house_escalate_window == 40.0
		and settings.house_escalate_reset == 60.0 and settings.house_answer_min_u == 3.0 and settings.house_escalate_window > settings.house_answer_gap,
		"The answer comes closer in at most 3 steps, to -22 LUFS at most; loud things 40 s apart or less raise it, a quiet minute resets it")
	check(settings.house_ajar and settings.house_ajar_chance == 0.5 and settings.house_ajar_delay == Vector2(8.0, 20.0) and settings.house_ajar_swing == 0.2
		and settings.house_ajar_min_u == 10.0 and settings.house_ajar_caption != "", "After an effect, half the time a door may be found ajar 8-20 s later (20% open, 10 u away or more)")
	var creak_entry: Array = settings.house_effects.filter(func(entry: Dictionary) -> bool: return entry.file == settings.house_ajar_creak)
	check(ResourceLoader.exists(settings.house_ajar_creak) and not settings.house_ajar_creak.begins_with(HouseVoice.ENTITY_FILES)
		and creak_entry.size() == 1 and float(creak_entry[0].lufs) == settings.house_ajar_creak_lufs
		and settings.house_ajar_creak_lufs + HouseVoice.level_for(settings.house_ajar_creak_lufs) <= settings.house_max_lufs + 0.001 and HouseVoice.level_for(settings.house_ajar_creak_lufs) <= 0.0,
		"The door's creak is a measured house file (%.1f LUFS), turned down to -26 LUFS like every house sound, never up" % settings.house_ajar_creak_lufs)
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
	check(near(settings.house_knock_share, 0.6, 0.001) and near(settings.house_knock_max_gain_db, 4.0, 0.001) and settings.house_knock_caption != "",
		"Most effects are knocks (60%), and a knock may be turned up by 4 dB at most")
	var knocks: Array[Dictionary] = HouseVoice.knocks()
	check(SoundLibrary.files(HouseVoice.KNOCK).is_empty() and not SoundLibrary._warned.has(HouseVoice.KNOCK) and knocks.size() == 1
		and knocks[0].file == settings.house_knock and near(float(knocks[0].lufs), -28.9, 0.001) and knocks[0].caption == "[Knocking, somewhere in the house]"
		and HouseVoice.effects().size() == settings.house_effects.size(),
		"Today the house knocks with one file, the answer's own (-28.9 LUFS, with its caption); house/knock is empty, and effects() is as it was")
	var knock_lufs := float(knocks[0].lufs) if not knocks.is_empty() else NAN
	check(near(HouseVoice.knock_level_for(knock_lufs), settings.house_max_lufs - knock_lufs, 0.001) and near(knock_lufs + HouseVoice.knock_level_for(knock_lufs), settings.house_max_lufs, 0.001),
		"A knock plays at the loudest the house may be: today's file %.1f dB up, at %.0f LUFS" % [HouseVoice.knock_level_for(knock_lufs), knock_lufs + HouseVoice.knock_level_for(knock_lufs)])
	check(near(HouseVoice.knock_level_for(-40.0), settings.house_knock_max_gain_db, 0.001) and near(HouseVoice.knock_level_for(-14.0), settings.house_max_lufs + 14.0, 0.001)
		and -14.0 + HouseVoice.knock_level_for(-14.0) <= settings.house_max_lufs + 0.001,
		"A very quiet knock file is turned up by %.0f dB at most; a loud one is turned down to -26 LUFS" % settings.house_knock_max_gain_db)


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


## With house_knock_share 0 the effects are as they were before the knocks: each effect,
## the knock among them, in turn, never twice running.
func check_effects() -> void:
	var share_before: float = settings.house_knock_share
	settings.house_knock_share = 0.0
	sounds.clear()
	thinnings = 0
	for roll in 60:
		HouseVoice.hurry()
		await ticks(2)
	settings.house_knock_share = share_before
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


## Rolls the next effect `count` times as the house would (without playing them): the families
## and files chosen, in order.
func roll(count: int) -> Array[Dictionary]:
	var picks: Array[Dictionary] = []
	for index in count:
		var picked: Dictionary = HouseVoice.pick_effect()
		if picked.is_empty():
			picks.append({"family": &"", "file": ""})
			continue
		HouseVoice._remember_effect(picked.entry, picked.family)
		picks.append({"family": picked.family, "file": picked.entry.file})
	return picks


## The longest run of effects in a row that are the same file.
func longest_run(picks: Array[Dictionary]) -> int:
	var longest := 0
	var run := 0
	for index in picks.size():
		run = run + 1 if index > 0 and picks[index].file == picks[index - 1].file else 1
		longest = maxi(longest, run)
	return longest


## Of the picks of one family, how many times one followed the same file.
func repeats_within(picks: Array[Dictionary], family: StringName) -> int:
	var own := picks.filter(func(pick: Dictionary) -> bool: return pick.family == family)
	var repeats := 0
	for index in range(1, own.size()):
		repeats += int(own[index].file == own[index - 1].file)
	return repeats


func share_of_knocks(picks: Array[Dictionary]) -> float:
	return picks.filter(func(pick: Dictionary) -> bool: return pick.family == &"knock").size() / float(maxi(picks.size(), 1))


## The knock: the house's signature. Most effects are a knock, at the loudest the house may be.
func check_knocks() -> void:
	var share_before: float = settings.house_knock_share
	var share: float = settings.house_knock_share
	var knock_file: String = settings.house_knock
	# One knock file (today): a knock may follow a knock, never a third time.
	var picks := roll(ROLLS)
	# With one file a third knock in a row is refused, so the share heard is p(1+p)/(1+p+p²).
	var expected := share * (1.0 + share) / (1.0 + share + share * share)
	check(near(share_of_knocks(picks), expected, 0.06) and share_of_knocks(picks) > 0.4,
		"With one knock file, %.0f%% of %d effects are knocks (%.0f%% expected: a 60%% chance each time, never a third in a row)" % [share_of_knocks(picks) * 100.0, ROLLS, expected * 100.0])
	var others: Array[Dictionary] = picks.filter(func(pick: Dictionary) -> bool: return pick.family == &"effect")
	var each_other := {}
	for pick in others: each_other[pick.file] = int(each_other.get(pick.file, 0)) + 1
	var most_other := 0
	for file: String in each_other: most_other = maxi(most_other, int(each_other[file]))
	check(each_other.size() == settings.house_effects.size() - 1 and not each_other.has(knock_file) and share_of_knocks(picks) * ROLLS > 2.0 * most_other,
		"The rest are the creak, the fall and the chair; knocks come more than twice as often as any of them (%s)" % [each_other])
	check(longest_run(picks) <= HouseVoice.KNOCKS_IN_A_ROW and picks.any(func(pick: Dictionary) -> bool: return pick.family == &"knock")
		and not picks.any(func(pick: Dictionary) -> bool: return pick.family == &""),
		"Two knocks may follow each other, never three effects in a row of the one knock file (longest run %d)" % longest_run(picks))
	check(repeats_within(picks, &"effect") == 0, "The other effects never repeat among themselves")
	# Share 1, one file: knock, knock, then one of the others.
	settings.house_knock_share = 1.0
	picks = roll(60)
	var after_two := true
	for index in range(2, picks.size()):
		if picks[index - 1].family == &"knock" and picks[index - 2].family == &"knock" and picks[index - 1].file == picks[index - 2].file:
			after_two = after_two and picks[index].family == &"effect"
	check(near(share_of_knocks(picks), 2.0 / 3.0, 0.05) and after_two and longest_run(picks) <= HouseVoice.KNOCKS_IN_A_ROW,
		"At share 1 with one file every effect is a knock but each third, which is one of the others (%.0f%% knocks)" % (share_of_knocks(picks) * 100.0))
	# Share 0: as before there were knocks.
	settings.house_knock_share = 0.0
	picks = roll(ROLLS)
	var used := {}
	for pick in picks: used[pick.file] = true
	check(share_of_knocks(picks) == 0.0 and used.has(knock_file) and used.size() == settings.house_effects.size() and longest_run(picks) == 1,
		"At share 0 the knock is just one of the effects, never twice running, as it was")
	# Two knock files (a stand-in in house/knock for the test): never the same file twice running.
	var second: Array[AudioStream] = [load(SECOND_KNOCK) as AudioStream]
	SoundLibrary._files[HouseVoice.KNOCK] = second
	settings.house_knock_share = share
	check(HouseVoice.knocks().size() == 2 and HouseVoice.knocks()[1].file == SECOND_KNOCK and near(float(HouseVoice.knocks()[1].lufs), settings.house_set_lufs, 0.001)
		and HouseVoice.knocks()[1].caption == settings.house_knock_caption and HouseVoice.effects().size() == settings.house_effects.size(),
		"A file dropped in house/knock becomes a knock with no code change (at %.0f LUFS, with the knocking caption), not another effect" % settings.house_set_lufs)
	picks = roll(ROLLS)
	var files := {}
	for pick in picks:
		if pick.family == &"knock": files[pick.file] = true
	check(near(share_of_knocks(picks), share, 0.06) and files.size() == 2,
		"With two knock files, %.0f%% of %d effects are knocks (%.0f%% asked), from both files" % [share_of_knocks(picks) * 100.0, ROLLS, share * 100.0])
	check(repeats_within(picks, &"knock") == 0 and repeats_within(picks, &"effect") == 0, "Never the same knock file twice running, nor the same other effect")
	settings.house_knock_share = 1.0
	picks = roll(40)
	check(share_of_knocks(picks) == 1.0 and repeats_within(picks, &"knock") == 0, "At share 1 with two files every effect is a knock, the two in turn")
	# The dropped file is heard as a knock: after the house's own knock, the next is the other.
	HouseVoice._remember_effect(HouseVoice.knocks()[0], &"knock")
	sounds.clear()
	HouseVoice.hurry_knock()
	await ticks(3)
	check(sounds.size() == 1 and sounds[0].family == &"knock" and sounds[0].file == SECOND_KNOCK
		and near(sounds[0].level, HouseVoice.knock_level_for(settings.house_set_lufs), 0.01) and sounds[0].caption == settings.house_knock_caption,
		"And it is heard as a knock, at its level, with its caption (%s)" % [sounds.map(func(sound: Dictionary) -> String: return "%s %s" % [sound.family, String(sound.file).get_file()])])
	SoundLibrary._files.erase(HouseVoice.KNOCK)
	settings.house_knock_share = share
	await seconds(settings.house_nothing_time + settings.house_nothing_fade + 0.2)
	# Today's knock, played as the house plays it: at -26 LUFS, from another room, on World, soft.
	var chance_before: float = settings.house_ajar_chance
	settings.house_ajar_chance = 1.0
	HouseVoice.begin_run()
	HouseVoice._knocks_running = 0
	HouseVoice._last_knock = ""
	sounds.clear()
	thinnings = 0
	var history_before := HouseVoice.history.size()
	HouseVoice.hurry_knock()
	await ticks(3)
	var knock: Dictionary = sounds[0] if not sounds.is_empty() else {}
	var lufs := lufs_of(knock_file)
	check(sounds.size() == 1 and thinnings == 0 and knock.family == &"knock" and knock.file == knock_file and HouseVoice.history.back().family == &"knock",
		"Asked for (J), a knock comes, never a nothing, and is told apart as a knock in the history")
	check(not knock.is_empty() and near(knock.level, HouseVoice.knock_level_for(lufs), 0.01) and near(lufs + knock.level, settings.house_max_lufs, 0.01)
		and lufs + knock.level <= settings.house_max_lufs + 0.001,
		"It plays %.1f dB up: at %.1f LUFS, the loudest the house may be, never louder" % [knock.get("level", NAN), lufs + float(knock.get("level", NAN))])
	check(not knock.is_empty() and room_of(knock.at) not in ["", "Vestibule"] and knock.bus == AudioBus.WORLD and near(knock.start_db, knock.level + settings.house_attack_from_db, 0.5)
		and knock.caption == "[Knocking, somewhere in the house]" and game.hud.caption.text == knock.caption,
		"From a room she is not in, on World, with a soft start, and the level shows its caption")
	check(HouseVoice._effect_wait >= settings.house_effect_gap.x - 2.0 and HouseVoice._ajar_wait >= 0.0,
		"Like any effect it sets the next one 90 s away or more (%.0f s), and a door may be found ajar after it" % HouseVoice._effect_wait)
	HouseVoice._ajar_wait = -1.0
	settings.house_ajar_chance = chance_before
	HouseVoice.begin_run()
	check(not HouseVoice.status().is_empty() and HouseVoice.knock_text() == "knocks 60% of effects, 1 knock file" and HouseVoice.status().contains(HouseVoice.knock_text()),
		"The read-out says what the next effect can be: %s" % HouseVoice.status())
	HouseVoice._knocks_running = HouseVoice.KNOCKS_IN_A_ROW
	HouseVoice._last_knock = knock_file
	check(HouseVoice.knock_text().begins_with("next effect not a knock"), "And when two knocks have just come, that the next will not be one: %s" % HouseVoice.knock_text())
	settings.house_knock_share = share_before
	await seconds(settings.house_attack + 0.1)


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
		HouseVoice.hurry_knock()
		knock_asks += 1
		HouseVoice._settle_wait = 0.0
		HouseVoice.answer()
		await ticks(1)
	knocks_heard += sounds.filter(func(sound: Dictionary) -> bool: return sound.family == &"knock").size()
	return sounds.size() + thinnings


func check_gates() -> void:
	knock_asks = 0
	knocks_heard = 0
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
	check(knock_asks > 20 and knocks_heard == 0 and HouseVoice.violations == 0,
		"Near, alert, just after a cue and while she prays, a knock asked for %d times never comes" % knock_asks)
	await ticks(2)
	made = await insist(0.2)
	check(made >= 1 and knocks_heard >= 1, "Once every gate is open, it speaks (asked for, a knock)")
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


## How loud a file of house_effects is (LUFS).
func lufs_of(file: String) -> float:
	for entry: Dictionary in settings.house_effects:
		if entry.file == file: return float(entry.lufs)
	return NAN


## How far a place is from her (u).
func from_her(at: Vector2) -> float:
	return Units.to_u(at.distance_to(game.player.global_position))


## The room of a layout a place belongs to ("" for none).
func room_in(layout: Dictionary, at: Vector2) -> String:
	for room: String in layout:
		for spot: Vector2 in layout[room]:
			if spot.is_equal_approx(at): return room
	return ""


## She does something loud (past the 12 s gap): the knocks that answer it, with the step it was at.
func loud() -> Array[Dictionary]:
	HouseVoice._since_answer = INF
	sounds.clear()
	HouseVoice.answer()
	await seconds(settings.house_answer_delay + 0.25)
	var knocks: Array[Dictionary] = []
	for sound in sounds:
		if sound.family == &"answer":
			sound["step"] = HouseVoice.answer_step
			knocks.append(sound)
	return knocks


## Rooms around her, with places at these distances (u): one in her own room (1 u), one nearer
## than an answer may ever come (2 u), and others from 4 to 25 u.
func ladder(at: Vector2) -> Dictionary:
	return {
		"Here": [at + Vector2(0, Units.to_px(1.0))],
		"Near": [at + Vector2(Units.to_px(2.0), 0), at + Vector2(Units.to_px(4.0), 0), at + Vector2(Units.to_px(6.0), 0)],
		"Mid": [at + Vector2(0, -Units.to_px(9.0)), at + Vector2(0, -Units.to_px(12.0))],
		"Far": [at + Vector2(-Units.to_px(15.0), 0), at + Vector2(-Units.to_px(20.0), 0), at + Vector2(-Units.to_px(25.0), 0)],
	}


## If she keeps being loud, each answer comes a little closer and may be a little louder.
func check_escalation() -> void:
	var delay_before: float = settings.house_answer_delay
	var knock_before: String = settings.house_knock
	settings.house_answer_delay = 0.2       # the waits brought forward; the logic is the same
	var her: Vector2 = game.player.global_position
	var layout := ladder(her)
	var here := func() -> String: return "Here"
	HouseVoice.enter(layout, here, game.player)
	await ticks(2)
	check(HouseVoice.gate() == "" and HouseVoice.answer_step == 0 and not HouseVoice.status().contains("answers:"), "Before anything loud the answer is at step 0: %s" % HouseVoice.status())
	# The real knock is quieter than every step's limit: it is played as it is, never turned up.
	var knock_lufs := lufs_of(settings.house_knock)
	var never_up := true
	for step in settings.house_escalate_steps + 1:
		HouseVoice.answer_step = step
		never_up = never_up and is_zero_approx(HouseVoice.answer_level_for(knock_lufs)) and knock_lufs <= HouseVoice.answer_cap()
	HouseVoice.answer_step = settings.house_escalate_steps
	never_up = never_up and near(HouseVoice.answer_cap(), settings.house_escalate_max_lufs, 0.001)
	HouseVoice.answer_step = 0
	check(never_up and near(HouseVoice.answer_cap(), settings.house_max_lufs, 0.001),
		"The limit rises from -26 to -22 LUFS with the step; the knock file (%.1f LUFS) is under every one, so it is never turned up" % knock_lufs)
	# A louder stand-in for the knock (the creak, -17.1 LUFS), so that the rising limit is heard.
	settings.house_knock = settings.house_effects[1].file
	var stand_in := lufs_of(settings.house_knock)
	# The first answer is today's, from anywhere allowed: asked until it lands far enough out
	# for three nearer places to exist.
	var answers: Array[Dictionary] = []
	var firsts_ok := true
	for attempt in 30:
		HouseVoice._reset_escalation()
		var first := await loud()
		firsts_ok = firsts_ok and (first.size() == 1 and first[0].step == 0 and room_in(layout, first[0].at) not in ["", "Here"]
			and from_her(first[0].at) >= settings.house_answer_min_u and near(stand_in + first[0].level, settings.house_max_lufs, 0.01))
		if first.size() == 1 and from_her(first[0].at) >= 11.9:
			answers = first
			break
	check(firsts_ok and answers.size() == 1, "The first answer is today's: one knock, from a room she is not in, at -26 LUFS (step 0)")
	for turn in settings.house_escalate_steps:
		var knocks := await loud()
		check(knocks.size() == 1, "Each loud thing within the window is answered by exactly one knock (%d)" % knocks.size())
		if knocks.size() == 1: answers.append(knocks[0])
	var report := ", ".join(PackedStringArray(answers.map(func(knock: Dictionary) -> String:
		return "step %d %.1f u %.1f LUFS" % [knock.step, from_her(knock.at), stand_in + knock.level])))
	print("[House voice tests] escalation: %s" % report)
	var closer := answers.size() == settings.house_escalate_steps + 1
	for index in range(1, answers.size()):
		closer = closer and (from_her(answers[index].at) < from_her(answers[index - 1].at) - 0.01 and answers[index].step == index
			and answers[index].level > answers[index - 1].level + 0.01)
	check(closer, "Each answer is nearer than the one before, and a little louder, step by step: %s" % report)
	check(answers.all(func(knock: Dictionary) -> bool: return room_in(layout, knock.at) not in ["", "Here"] and from_her(knock.at) >= settings.house_answer_min_u - 0.001),
		"None from her own room, none nearer than %.0f u" % settings.house_answer_min_u)
	var top: Dictionary = answers.back() if not answers.is_empty() else {"level": INF}
	check(near(stand_in + top.level, settings.house_escalate_max_lufs, 0.01) and stand_in + top.level <= settings.house_escalate_max_lufs + 0.001,
		"At the top step the knock is at -22 LUFS, and not above it (%.2f LUFS)" % (stand_in + top.level))
	check(HouseVoice.status().contains("answers: step 3 of 3 (quiet resets it in"), "The read-out names the step: %s" % HouseVoice.status())
	var fifth := await loud()
	check(fifth.size() == 1 and fifth[0].step == settings.house_escalate_steps and not answers.is_empty()
		and from_her(fifth[0].at) >= from_her(top.at) - 0.01 and near(fifth[0].level, top.level, 0.001),
		"A fifth stays at the top step: not nearer, not louder")
	# Further apart than the window: the step holds.
	HouseVoice._reset_escalation()
	await loud()
	var second := await loud()
	HouseVoice._since_accepted = settings.house_escalate_window + 1.0
	var later := await loud()
	check(second.size() == 1 and second[0].step == 1 and later.size() == 1 and later[0].step == 1
		and near(from_her(later[0].at), from_her(second[0].at), 0.01) and near(later[0].level, second[0].level, 0.001),
		"Two answers further apart than the window: the step does not rise, and it comes from as far as the last")
	# A refused call: nothing plays, the step stays, the quiet starts again.
	HouseVoice._since_loud = 30.0
	GameState.is_praying = true
	var refused := await loud()
	GameState.is_praying = false
	check(refused.is_empty() and HouseVoice.answer_step == 1 and HouseVoice._since_loud < 1.0,
		"Refused while she prays: no knock, the step stays, and the quiet minute starts again")
	HouseVoice._since_loud = 30.0
	HouseVoice._since_answer = 0.0
	sounds.clear()
	var inside_gap := HouseVoice.answer()
	await seconds(settings.house_answer_delay + 0.25)
	check(not inside_gap and sounds.is_empty() and HouseVoice.answer_step == 1 and HouseVoice._since_loud < 1.0,
		"Refused inside the 12 s gap: the same")
	HouseVoice._since_cue = 0.0
	var after_cue := HouseVoice.answer()
	HouseVoice._since_cue = INF
	check(not after_cue and HouseVoice.answer_step == 1, "Refused after an awareness cue too (alert and near: see the gates above)")
	# A quiet minute.
	HouseVoice._since_loud = settings.house_escalate_reset + 0.5
	await ticks(2)
	check(HouseVoice.answer_step == 0 and not HouseVoice.status().contains("answers:"), "After a quiet minute it is back to step 0: %s" % HouseVoice.status())
	var again := await loud()
	check(again.size() == 1 and again[0].step == 0 and near(stand_in + again[0].level, settings.house_max_lufs, 0.01) and room_in(layout, again[0].at) not in ["", "Here"],
		"And the next answer is today's again: anywhere allowed, at -26 LUFS")
	# The step resets on GameState.reset(), leave() and enter().
	await loud()
	var raised := HouseVoice.answer_step
	GameState.reset()
	var after_reset := HouseVoice.answer_step
	await loud()
	await loud()
	HouseVoice.leave()
	var after_leave := HouseVoice.answer_step
	HouseVoice.enter(layout, here, game.player)
	await loud()
	await loud()
	var raised_again := HouseVoice.answer_step
	HouseVoice.enter(layout, here, game.player)
	check(raised == 1 and after_reset == 0 and after_leave == 0 and raised_again == 1 and HouseVoice.answer_step == 0,
		"The step goes back to 0 on a new attempt (GameState.reset), on leaving the house and on entering one")
	# Nothing nearer allowed: the nearest allowed place.
	var tight := {
		"Here": [her + Vector2(Units.to_px(1.0), 0)],
		"Other": [her + Vector2(Units.to_px(2.0), 0), her + Vector2(Units.to_px(5.0), 0), her + Vector2(0, Units.to_px(9.0))],
	}
	HouseVoice.enter(tight, here, game.player)
	var tight_answers: Array[Dictionary] = []
	for turn in 3:
		tight_answers.append_array(await loud())
	check(tight_answers.size() == 3 and HouseVoice.answer_step == 2 and near(from_her(tight_answers[2].at), 5.0, 0.01)
		and tight_answers.all(func(knock: Dictionary) -> bool: return room_in(tight, knock.at) == "Other" and from_her(knock.at) >= settings.house_answer_min_u),
		"With nothing nearer allowed it comes from the nearest allowed place (5 u): never her room, never nearer than 3 u")
	settings.house_knock = knock_before
	settings.house_answer_delay = delay_before
	game._enter_house_voice()
	await ticks(2)
	HouseVoice._open_wait = 0.0


var arena: Node2D
var ears: Node2D
## Door name -> how many times it sent opened / closed.
var door_signals := {}
var left_ajar: Array = []


func add_door(door_name: String, at: Vector2) -> Door:
	var door := DOOR_SCENE.instantiate() as Door
	door.name = door_name
	arena.add_child(door)
	door.global_position = ARENA + at
	door.opened.connect(func() -> void: door_signals[door_name] = int(door_signals.get(door_name, 0)) + 1)
	door.closed.connect(func() -> void: door_signals[door_name] = int(door_signals.get(door_name, 0)) + 1)
	return door


## An effect of the house sounds at EFFECT_AT; returns the aftermath sounds that came within `wait` s.
func effect_then(wait: float) -> Array[Dictionary]:
	sounds.clear()
	HouseVoice._play_entry(&"effect", settings.house_effects[2], ARENA + EFFECT_AT)
	await seconds(wait)
	var found: Array[Dictionary] = []
	for sound in sounds:
		if sound.family == &"aftermath": found.append(sound)
	return found


## The aftermath: a door she cannot see is found ajar, with a creak she hears and it does not.
func check_ajar() -> void:
	var chance_before: float = settings.house_ajar_chance
	var delay_before: Vector2 = settings.house_ajar_delay
	settings.house_ajar_chance = 1.0
	settings.house_ajar_delay = Vector2(0.2, 0.2)
	# A small layout: she listens at ARENA, a wall runs north-south 100 px east of her, and
	# doors stand around it.
	arena = Node2D.new()
	arena.name = "AjarArena"
	add_child(arena)
	ears = Node2D.new()
	arena.add_child(ears)
	ears.global_position = ARENA
	var wall := StaticBody2D.new()
	wall.add_to_group(Acoustics.WALL_GROUP)
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 4000)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	arena.add_child(wall)
	wall.global_position = ARENA + Vector2(100, 0)
	var nearest := add_door("Nearest", Vector2(700, 0))           # behind the wall, 22 u: the one
	var farther := add_door("Farther", Vector2(1300, 0))          # behind the wall, farther from the effect
	var shut_fast := add_door("Locked", Vector2(700, 250))        # nearest the effect, but locked
	shut_fast.locked = true
	var open_one := add_door("Open", Vector2(700, 500))
	var crowded := add_door("Crowded", Vector2(700, -300))        # someone stands in its doorway
	var too_near := add_door("TooNear", Vector2(250, 0))          # behind the wall, under 10 u
	var in_sight := add_door("InSight", Vector2(-700, 0))         # far, but on her side of the wall
	nearest.creak = null                                          # no creak of its own: the house's
	var body := CharacterBody2D.new()
	var body_shape := CollisionShape2D.new()
	var small := RectangleShape2D.new()
	small.size = Vector2(12, 12)
	body_shape.shape = small
	body.add_child(body_shape)
	arena.add_child(body)
	body.global_position = crowded.global_position + Vector2(0, -32)
	await frames(4)
	open_one.snap(true)
	await frames(4)
	door_signals.clear()
	var doors: Array[Door] = [nearest, farther, shut_fast, open_one, crowded, too_near, in_sight]
	var layout := {"Here": [ARENA + Vector2(0, 40)], "East": [ARENA + EFFECT_AT]}
	var here := func() -> String: return "Here"
	HouseVoice.enter(layout, here, ears, doors)
	HouseVoice.begin_run()
	left_ajar.clear()
	var on_ajar := func(door: Door) -> void: left_ajar.append(door)
	HouseVoice.door_left_ajar.connect(on_ajar)
	await ticks(2)
	var candidates := HouseVoice.ajar_candidates(ARENA + EFFECT_AT)
	check(candidates.size() == 2 and candidates[0] == nearest and candidates[1] == farther, "Only doors shut, unlocked, with nobody in the doorway, 10 u away or more and behind a wall may be left ajar, nearest the effect first: %s"
		% [candidates.map(func(door: Door) -> String: return door.name)])
	var occluder_before: bool = nearest.get_node("Occluder").visible
	var audio: AudioStreamPlayer2D = nearest.get_node("Audio")
	var stream_before := audio.stream
	var noises_before := noises
	var aware_before := Dread.awareness
	var gate_open := HouseVoice.gate() == ""
	# The effect, its wait, and the creak's length for the leaf to finish moving.
	var creak_length := (load(settings.house_ajar_creak) as AudioStream).get_length()
	var aftermath := await effect_then(settings.house_ajar_delay.y + creak_length + 0.3)
	var swung := doors.filter(func(door: Door) -> bool: return door != open_one and not is_zero_approx(door.swing))
	print("[House voice tests] ajar: %s swing %.2f open %s · creak %.1f LUFS at %s" % [swung.map(func(door: Door) -> String: return door.name), nearest.swing, nearest.is_open,
		settings.house_ajar_creak_lufs + (aftermath[0].level if not aftermath.is_empty() else NAN), aftermath[0].at - ARENA if not aftermath.is_empty() else Vector2.INF])
	check(gate_open and swung.size() == 1 and swung[0] == nearest and near(nearest.swing, settings.house_ajar_swing, 0.001) and not nearest.is_open,
		"After an effect and its wait, exactly one door is ajar (%.2f), the eligible one nearest the effect, and it is still shut" % nearest.swing)
	check(not (nearest.get_node("Blocker/Shape") as CollisionShape2D).disabled and nearest.get_node("Occluder").visible == occluder_before
		and (nearest.get_node("LeafBody/Shape") as CollisionShape2D).disabled,
		"Its blocker still stops bodies, its light occluder is unchanged, its swung-leaf body stays off")
	check(door_signals.is_empty() and noises == noises_before and not audio.playing and audio.stream == stream_before,
		"No door sent opened, no noise was made (the entity hears nothing), and the door's own player did not play")
	check(Dread.awareness == aware_before and Dread.awareness <= Dread.Awareness.PAUSED, "The entity, unaware and far off, stays unaware")
	check(aftermath.size() == 1 and aftermath[0].at.is_equal_approx(nearest.get_noise_origin()) and aftermath[0].bus == AudioBus.WORLD
		and aftermath[0].file == settings.house_ajar_creak and not String(aftermath[0].file).begins_with(HouseVoice.ENTITY_FILES)
		and settings.house_ajar_creak_lufs + aftermath[0].level <= settings.house_max_lufs + 0.001 and aftermath[0].caption == settings.house_ajar_caption
		and near(aftermath[0].start_db, aftermath[0].level + settings.house_attack_from_db, 0.5),
		"She hears it: one creak from that door, on World, at -26 LUFS or less, with a soft start and its caption")
	check(HouseVoice.history.back().family == &"aftermath" and HouseVoice.history.back().gate == "" and HouseVoice.ajar_done
		and left_ajar.size() == 1 and left_ajar[0] == nearest and game.hud.caption.text == settings.house_ajar_caption,
		"It is written down, said with door_left_ajar, and the level shows its caption: %s" % game.hud.caption.text)
	# Once per run: not again, also after a new attempt.
	GameState.reset()
	var second := await effect_then(settings.house_ajar_delay.y + 0.3)
	check(second.is_empty() and HouseVoice.ajar_done and is_zero_approx(farther.swing) and left_ajar.size() == 1,
		"A second effect never does it again in the same run, also after a new attempt")
	# Opening the ajar door afterwards: it opens as any door, all the way.
	check(nearest.open(false, true), "She can open the door left ajar")
	await seconds(nearest.swing_time + 0.2)
	check(nearest.is_open and near(nearest.swing, 1.0, 0.001) and (nearest.get_node("Blocker/Shape") as CollisionShape2D).disabled,
		"And it ends fully open (%.2f)" % nearest.swing)
	# A new run: it may happen again (the open door no longer qualifies).
	HouseVoice.begin_run()
	var new_run := await effect_then(settings.house_ajar_delay.y + 0.3)
	check(new_run.size() == 1 and new_run[0].at.is_equal_approx(farther.get_noise_origin()) and left_ajar.back() == farther,
		"begin_run() allows it again: this time the next door")
	await seconds(creak_length)
	nearest.snap(false)
	farther.snap(false)
	# Switched off.
	settings.house_ajar = false
	HouseVoice.begin_run()
	var off := await effect_then(settings.house_ajar_delay.y + 0.3)
	settings.house_ajar = true
	check(off.is_empty() and is_zero_approx(nearest.swing) and is_zero_approx(farther.swing) and not HouseVoice.ajar_done, "house_ajar = false switches it off: no leaf, no creak")
	# The gate closes during the wait: the attempt is dropped, the run keeps its chance.
	sounds.clear()
	HouseVoice._play_entry(&"effect", settings.house_effects[2], ARENA + EFFECT_AT)
	GameState.is_praying = true
	await seconds(settings.house_ajar_delay.y + 0.3)
	GameState.is_praying = false
	check(sounds.all(func(sound: Dictionary) -> bool: return sound.family != &"aftermath") and is_zero_approx(nearest.swing) and is_zero_approx(farther.swing)
		and not HouseVoice.ajar_done and HouseVoice._ajar_wait < 0.0, "Never while the gate is closed: no leaf, no creak, and the chance is kept")
	# No door qualifies: nothing happens, and the chance is kept for a later effect.
	nearest.locked = true
	farther.locked = true
	var none := await effect_then(settings.house_ajar_delay.y + 0.3)
	nearest.locked = false
	farther.locked = false
	var later := await effect_then(settings.house_ajar_delay.y + 0.3)
	check(none.is_empty() and later.size() == 1 and later[0].at.is_equal_approx(nearest.get_noise_origin()),
		"With no door that qualifies nothing happens, and a later effect may still do it")
	await seconds(creak_length)
	# No doors given: nothing, and nothing goes wrong. A door freed meanwhile is skipped.
	HouseVoice.enter(layout, here, ears)
	HouseVoice.begin_run()
	var no_doors := await effect_then(settings.house_ajar_delay.y + 0.3)
	HouseVoice.enter(layout, here, ears, doors)
	farther.free()
	var still := HouseVoice.ajar_candidates(ARENA + EFFECT_AT)
	check(no_doors.is_empty() and HouseVoice._ajar_wait < 0.0 and still.is_empty(), "With no doors given nothing happens; a door freed meanwhile is skipped")
	HouseVoice.door_left_ajar.disconnect(on_ajar)
	settings.house_ajar_chance = chance_before
	settings.house_ajar_delay = delay_before
	HouseVoice.begin_run()
	arena.queue_free()
	game._enter_house_voice()
	await ticks(2)
	HouseVoice._open_wait = 0.0


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
