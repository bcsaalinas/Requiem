extends Node
## The jump-scare audit and the audio read-out (headless).
## The audit watches Master for a rise of more than 18 dB within 100 ms. The scream is the one
## sound meant to do that; any other rise must be explained (her own action, the heard-you cue,
## or 0.7 s of warning), and no sound of the house may play while its gates are closed. This
## runs a calm stretch, the house voice and a whole encounter in the real house and asserts
## the audit found nothing unexplained. It also checks the read-out of the noise overlay
## (testing/tools/noise_debug.gd): threat, presence, ring, clarity, wall, last cues, the house.

const Audit := preload("res://testing/tools/jump_scare_audit.gd")
const NoiseOverlay := preload("res://testing/tools/noise_debug.gd")
const AUDIT_PATH := "res://testing/tools/jump_scare_audit.gd"
const OVERLAY_PATH := "res://testing/tools/noise_debug.gd"
const KITCHEN_BY_WALL := Vector2(368, 176)
const VESTIBULE_BY_WALL := Vector2(432, 176)
const VESTIBULE_A := Vector2(520, 400)
const VESTIBULE_B := Vector2(680, 400)
## Far in the kitchen: the altar door is 22 u away, behind the kitchen wall.
const KITCHEN_FAR := Vector2(150, 200)
## The calm soak: its patrol across the vestibule, passing her and stopping right by her
## (1.6 u), then away again. Viv stands at VESTIBULE_A.
const SOAK_ROUTE: Array[Vector2] = [Vector2(440, 456), Vector2(552, 440), Vector2(700, 456), Vector2(552, 456)]
const SOAK_TIME := 60.0
const WALK := "entity/claws_walk"

var failures: Array[String] = []
var checks := 0
var settings: SoundSettings
var game: Node2D
var entity: CharacterBody2D
var overlay: Node
var house := Vector2.ZERO
var far := Vector2.ZERO
var cues: Array[StringName] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func until(condition: Callable, limit: float) -> bool:
	var deadline := now() + limit
	while now() < deadline:
		if condition.call(): return true
		await get_tree().process_frame
	return condition.call()


func _ready() -> void:
	settings = SoundSettings.current()
	check_settings()
	check_detection()
	check_causes()
	check_house_breach()
	await set_up()
	await check_calm_soak()
	await check_read_out()
	await check_real_jump()
	await check_calm_and_house()
	await check_encounter()
	game.queue_free()
	await frames(3)
	print("[Jump-scare audit tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func check_settings() -> void:
	check(settings.audit_jump_db == 18.0 and is_equal_approx(settings.audit_jump_window, 0.1), "The audit looks for a rise of more than 18 dB within 100 ms")
	check(is_equal_approx(settings.audit_warning, 0.7), "A warning is 0.7 s or more")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.contains("testing/*") and AUDIT_PATH.begins_with("res://testing/") and OVERLAY_PATH.begins_with("res://testing/"),
		"The audit and the read-out are development tools: testing/ is left out of the exported game")
	check(not ProjectSettings.has_setting("autoload/JumpScareAudit") and not ProjectSettings.has_setting("autoload/NoiseDebug"), "Neither is an autoload")
	var runner := FileAccess.get_file_as_string("res://testing/run_checks.py")
	check(runner.contains('"test_entity_audio"') and runner.contains('"test_awareness"') and runner.contains('"test_jump_scare_audit"'),
		"The full run has the rig cue test, the fairness test and this audit")
	var source := FileAccess.get_file_as_string(AUDIT_PATH) + FileAccess.get_file_as_string(OVERLAY_PATH)
	check(not source.contains("emit_noise") and not source.contains(".play(") and not source.contains("volume_db ="),
		"Both only watch: they make no noise and change no sound")


## A stand-alone audit fed with readings of this test's own.
func new_audit() -> Node:
	var audit: Node = Audit.new()
	add_child(audit)
	audit.set_process(false)
	return audit


## Feeds readings { seconds from the start: dB } to an audit, in order.
func feed(audit: Node, start: float, readings: Array) -> void:
	for reading: Array in readings:
		audit.sample(start + float(reading[0]), float(reading[1]))


func check_detection() -> void:
	var audit := new_audit()
	var start: float = audit.now() + 100.0      # far from anything that could explain a rise
	feed(audit, start, [[0.00, -20.0], [0.02, -20.0], [0.04, -20.0], [0.06, -3.0]])
	check(audit.rises.size() == 0, "A rise of 17 dB is not logged")
	feed(audit, start + 1.0, [[0.00, -20.0], [0.02, -20.0], [0.06, -1.0], [0.08, -1.0], [0.10, -1.0], [0.12, 0.0]])
	check(audit.rises.size() == 1 and is_equal_approx(audit.rises[0].jump_db, 19.0) and is_equal_approx(audit.rises[0].from_db, -20.0)
		and is_equal_approx(audit.rises[0].to_db, -1.0), "A rise of 19 dB within 100 ms is logged, once, with where it came from and went to")
	check(audit.rises[0].cause == audit.UNEXPLAINED and not audit.rises[0].explained and audit.unexplained().size() == 1,
		"With nothing to explain it, it is marked unexplained")
	audit.clear()
	feed(audit, start + 2.0, [[0.00, -22.0], [0.13, -1.0]])
	check(audit.rises.is_empty(), "The same rise over 130 ms is not sudden")
	var ramp: Array = []
	for step in 40:
		ramp.append([step * 0.02, -26.0 + step * 0.65])
	feed(audit, start + 3.0, ramp)
	check(audit.rises.is_empty(), "A swell of 25 dB over 0.8 s is not logged")
	feed(audit, start + 5.0, [[0.00, -200.0], [0.02, -200.0], [0.04, -10.0]])
	check(audit.rises.is_empty(), "Out of silence, something of %.0f dB is not a jump: silence counts as %.0f dB" % [-10.0, settings.audit_floor_db])
	feed(audit, start + 6.0, [[0.00, -200.0], [0.02, -200.0], [0.04, -6.0]])
	check(audit.rises.size() == 1 and is_equal_approx(audit.rises[0].from_db, settings.audit_floor_db), "Out of silence, something of -6 dB is")
	check(audit.readings == 48 and audit.loudest_db > -1.0 and audit.loudest_db < 0.0, "It counts its readings and keeps the loudest (%d, %.1f dB)" % [audit.readings, audit.loudest_db])
	check(audit.summary().begins_with("1 sudden rises, 1 unexplained, 0 house sounds while gated") and audit.summary().contains("UNEXPLAINED"), "Its summary says so: %s" % audit.summary())
	check(audit.rises[0].sound == "", "Told of no sound, it names none")
	audit.clear()
	feed(audit, start + 7.0, [[0.00, -200.0], [0.03, -2.0], [0.06, -200.0], [0.09, -1.0]])
	check(audit.rises.size() == 1, "A meter that flickers as a sound starts gives one entry, not two")
	feed(audit, start + 7.5, [[0.00, -200.0], [0.03, -2.0]])
	check(audit.rises.size() == 2, "The next sound, half a second later, is logged again")
	audit.clear()
	audit.note_sound("pat_tap", start + 7.95)
	feed(audit, start + 8.0, [[0.00, -200.0], [0.04, -6.0]])
	check(audit.rises.size() == 1 and audit.rises[0].sound == "pat_tap" and absf(float(audit.rises[0].sound_ago) - 0.09) < 0.001 and audit.summary().contains("after pat_tap"),
		"Told what played last, a logged rise names it and how long before: %s" % audit.summary())
	audit.queue_free()


## One sudden rise at `after` seconds from now; returns the audit's last entry ({} when none).
func rise(audit: Node, after: float) -> Dictionary:
	var before: int = audit.rises.size()
	feed(audit, audit.now() + after, [[0.00, -24.0], [0.02, -24.0], [0.04, -2.0], [0.06, -2.0], [0.2, -24.0]])
	return audit.rises.back() if audit.rises.size() > before else {}


func check_causes() -> void:
	var audit := new_audit()
	check(not rise(audit, 0.0).explained, "Nothing happened: a rise is unexplained")
	audit.clear()
	NoiseManager.emit_noise(Vector2.ZERO, 10.0, NoiseManager.SourceType.FOOTSTEP)
	var own := rise(audit, 0.1)
	check(own.explained and own.cause == "her own action", "She made a noise in that instant: her own action")
	check(not rise(audit, 0.1 + settings.audit_own_action + 0.3).explained, "A moment later that no longer explains anything")
	audit.clear()
	var press := InputEventKey.new()
	press.keycode = KEY_E
	press.pressed = true
	audit._input(press)
	check(rise(audit, 0.1).cause == "her own action", "She pressed a key in that instant: her own action")
	audit.clear()
	audit.sample(audit.now() + 50.0, -24.0)
	audit.sample(audit.now() + 50.04, -2.0, AudioBus.BODY)
	check(audit.rises.size() == 1 and audit.rises[0].explained and audit.rises[0].bus == AudioBus.BODY and String(audit.rises[0].cause).begins_with("her own action"),
		"A rise on her own bus (her steps, her breath) is her own action")
	audit.sample(audit.now() + 60.0, -24.0)
	audit.sample(audit.now() + 60.04, -2.0, AudioBus.WORLD)
	check(audit.rises.size() == 2 and not audit.rises[1].explained and audit.rises[1].bus == AudioBus.WORLD, "The same rise on the World bus is not")
	audit.clear()
	Dread.cue_played.emit(&"heard")
	var heard := rise(audit, 0.2)
	check(heard.explained and String(heard.cause).begins_with("it heard her"), "The heard-you cue is explained: it only ever answers a noise")
	var warned := rise(audit, 1.0)
	check(warned.explained and String(warned.cause).begins_with("warned 1.0 s"), "A rise a second after the heard-you cue was warned of")
	check(not rise(audit, 1.0 + settings.audit_aftermath + 1.0).explained, "Long after the encounter that warning is spent")
	audit.clear()
	Dread.cue_played.emit(&"heard")
	Dread.cue_played.emit(&"scream")
	check(rise(audit, 0.2).is_empty() and audit.screams == 1 and audit.rises.is_empty(), "The scream is the one sound meant to jump: counted, not logged")
	check(String(rise(audit, settings.audit_scream_time + 0.3).cause).begins_with("warned"), "After the scream, rises are logged again")
	audit.clear()
	Dread.cue_played.emit(&"stand_down")
	check(not rise(audit, 0.1).explained, "A cue that is not the heard-you cue warns of nothing by itself")
	audit.queue_free()


func check_house_breach() -> void:
	var audit := new_audit()
	var knock := load(settings.house_knock) as AudioStream
	HouseVoice.sounded.emit(&"effect", knock, Vector2.ZERO, -12.0, "")
	check(audit.house_breaches.size() == 1 and audit.house_breaches[0].reason == "no house here" and audit.house_breaches[0].file == settings.house_knock
		and audit.summary().contains("1 house sounds while gated"), "A house sound that plays while its gates are closed is logged, with the reason")
	HouseVoice.sounded.emit(&"story", knock, Vector2.ZERO, -12.0, "")
	check(audit.house_breaches.size() == 1, "A level's own story sound is not the house voice's")
	audit.queue_free()


func set_up() -> void:
	GameState.reset()
	Dread.cue_played.connect(func(moment: StringName) -> void: cues.append(moment))
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	game.has_key = true          # past the tutorial's own story: the house is its own
	house = game.world.zones["house"].global_position
	far = game.world.marker("house", "Patrol4")
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.global_position = house + VESTIBULE_A
	game.world.rooms("house").sync_to(game.player.global_position)
	overlay = NoiseOverlay.new()
	add_child(overlay)
	overlay.enabled = true
	HouseVoice._since_cue = INF      # the cues this test made up above are not the house's business
	await place(far)


## A minute of its patrol past and up to her, with the drone away: its steps, taps, breath and
## mumbling in a silent house. It knows nothing all along, so nothing explains a sudden rise:
## there must be none.
func check_calm_soak() -> void:
	var audit: Node = overlay.audit
	MusicDirector.turn_drone(false)
	MusicDirector.drone_wait = INF
	var music := AudioServer.get_bus_index(AudioBus.MUSIC)
	var deadline := now() + settings.music_drone_fade_out + 1.0
	while now() < deadline and AudioServer.get_bus_peak_volume_left_db(music, 0) > settings.audit_floor_db - 20.0:
		await get_tree().process_frame
	var route: Array[Vector2] = []
	for point in SOAK_ROUTE:
		route.append(house + point)
	entity.reset_encounter(route[0], route)
	entity.show()
	entity.active = true
	await frames(3)
	entity.audio.placed()
	var audio: EntityAudio = entity.audio
	var steps_before := int(audio.plays.get(WALK, 0))
	var taps_before := int(audio.plays.get("entity/pat_tap", 0))
	var said_before := int(audio.plays.get(EntityAudio.MUMBLE, 0))
	var nearest := INF
	var calm := true
	audit.clear()
	deadline = now() + SOAK_TIME
	while now() < deadline:
		await get_tree().process_frame
		nearest = minf(nearest, Units.to_u(entity.global_position.distance_to(game.player.global_position)))
		calm = calm and Dread.awareness_of(entity, audio) <= Dread.Awareness.PAUSED
	var steps := int(audio.plays.get(WALK, 0)) - steps_before
	print("[Jump-scare audit] calm soak, %.0f s, no drone: %d walking steps, %d taps, %d phrases, nearest %.1f u · %s · loudest %.1f dB" % [
		SOAK_TIME, steps, int(audio.plays.get("entity/pat_tap", 0)) - taps_before, int(audio.plays.get(EntityAudio.MUMBLE, 0)) - said_before,
		nearest, audit.summary(), audit.loudest_db])
	for entry: Dictionary in audit.rises:
		print("[Jump-scare audit]   +%.1f dB (%.0f to %.0f dB) on %s, after %s · %s" % [entry.jump_db, entry.from_db, entry.to_db, entry.bus, entry.sound, entry.cause])
	check(calm and nearest < 2.0 and steps > 10, "A minute of its calm patrol, past and up to her (nearest %.1f u, %d steps heard)" % [nearest, steps])
	check(audit.unexplained().is_empty(), "With the drone away, nothing it does calm beside her is a sudden rise: %s" % audit.summary())
	MusicDirector.turn_drone(true)
	await place(far)
	audit.clear()


## Puts the entity somewhere, shown, active, unaware and standing still.
func place(at: Vector2) -> void:
	var route: Array[Vector2] = [at]
	entity.reset_encounter(at, route)
	entity.show()
	entity.active = true
	entity._patrol_wait = 999.0
	await frames(3)
	entity.audio.placed()
	await frames(3)


func line(index: int) -> String:
	return String(overlay.audio_text()).split("\n")[index]


func check_read_out() -> void:
	await seconds(0.6)
	var text: String = overlay.audio_text()
	check(text.split("\n").size() == 5 and overlay.audio_label.text == text, "With the overlay on, the read-out shows five lines")
	check(line(0).contains("threat %.2f (%s)" % [Dread.threat, Dread.awareness_name()]) and line(0).contains("presence %.2f" % Dread.presence),
		"Threat and presence: %s" % line(0))
	check(overlay.nearest_voice() == entity.audio and line(1).begins_with("it: ring 0, gone · clarity 0.00 · wall in the way: "),
		"Across the house there is nothing of it to hear: %s" % line(1))
	check(line(3) == "house voice: " + HouseVoice.status() and line(3).contains("settling"), "The house voice may speak, and says what it waits for: %s" % line(3))
	check(line(4).begins_with("jump audit: ") and line(4).contains(overlay.audit.summary()), "The audit's count: %s" % line(4))
	# Behind the wall.
	game.player.global_position = house + VESTIBULE_BY_WALL
	await place(house + KITCHEN_BY_WALL)
	var reading: AcousticReading = Acoustics.reading(entity)
	check(reading.blocked and reading.ring == 1 and line(1).begins_with("it: ring 1, somewhere · clarity %.2f · wall in the way: yes · heard from: the doorway (" % reading.clarity),
		"Behind the wall, heard from the doorway: %s" % line(1))
	# In the same room.
	game.player.global_position = house + VESTIBULE_A
	await place(house + VESTIBULE_B)
	reading = Acoustics.reading(entity)
	check(not reading.blocked and reading.ring == 2 and line(1) == "it: ring 2, near · clarity %.2f · wall in the way: no · heard from: where it is" % reading.clarity,
		"In the same room, heard from where it is: %s" % line(1))
	check(line(3).begins_with("house voice: silent: it is near (ring 2)"), "And that is why the house is silent: %s" % line(3))
	var canvas := Rect2(Vector2.ZERO, PixelDisplay.UI_CANVAS)
	check(canvas.encloses(overlay.audio_label.get_global_rect()) and overlay.audio_label.position.x < 40.0
		and overlay.audio_label.get_global_rect().end.y > PixelDisplay.UI_CANVAS.y - 80.0, "It sits at the bottom left of the screen: %s" % overlay.audio_label.get_global_rect())
	# The last cue on each channel.
	entity.audio.play_set("entity/claws_walk")
	await frames(2)
	check(line(2).contains("where it is (B): claws_walk, 0."), "A position sound shows on channel B: %s" % line(2))
	overlay.enabled = false
	var frozen: String = overlay.audio_label.text
	entity.audio.play_set("entity/sniff")
	await frames(3)
	check(overlay.audio_label.text == frozen and overlay.audio_text().contains("(B): sniff"), "Switched off, the label rests; the tool still knows")
	overlay.enabled = true
	await place(far)
	entity.hide()
	await seconds(1.0 / settings.acoustics_rate + 0.1)       # Acoustics measures 5 times a second
	check(line(1) == "it: nothing to hear (ring 0 · clarity 0.00 · wall in the way: no)", "With no entity out, it says so: %s" % line(1))
	entity.show()
	await frames(2)


## The meter is real: a loud sound out of nowhere is caught and marked unexplained.
func check_real_jump() -> void:
	var audit: Node = overlay.audit
	await seconds(0.5)
	audit.clear()
	var loud := AudioStreamPlayer.new()
	loud.stream = SoundLibrary.files("entity/scream")[0]
	loud.bus = AudioBus.ENTITY
	loud.volume_db = 6.0
	add_child(loud)
	loud.play()
	await until(func() -> bool: return not audit.rises.is_empty(), 1.5)
	loud.stop()
	loud.queue_free()
	check(audit.rises.size() >= 1 and not audit.rises[0].explained and audit.rises[0].jump_db > settings.audit_jump_db and audit.loudest_db > settings.audit_floor_db + settings.audit_jump_db
		and audit.rises[0].bus == AudioBus.ENTITY,
		"A loud sound out of nowhere is caught on the real Master meter, unexplained (%s, loudest %.0f dB)" % [audit.summary(), audit.loudest_db])
	check(line(4).contains("1 unexplained") or line(4).contains("unexplained") and not line(4).contains(" 0 unexplained"), "And the read-out shows it: %s" % line(4))
	await seconds(0.6)
	audit.clear()


## Calm: it walks about in her room, the house makes its sounds. Nothing jumps.
func check_calm_and_house() -> void:
	var audit: Node = overlay.audit
	var route: Array[Vector2] = [house + VESTIBULE_B, house + Vector2(680, 560)]
	entity.reset_encounter(house + VESTIBULE_B, route)
	entity.show()
	entity.active = true
	entity._patrol_wait = 0.0
	await frames(3)
	entity.audio.placed()
	await seconds(4.0)
	check(audit.readings > 100 and audit.loudest_db > -60.0 and int(entity.audio.plays.get("entity/claws_walk", 0)) >= 2,
		"It walks about in her room for four seconds and is heard (%d claw steps, loudest %.0f dB)" % [int(entity.audio.plays.get("entity/claws_walk", 0)), audit.loudest_db])
	check(audit.unexplained().is_empty(), "Nothing it does unaware is a jump: %s" % [audit.unexplained()])
	# The house, with it far away.
	await place(far)
	HouseVoice._since_cue = INF
	var before: int = HouseVoice.history.size()
	var played := 0
	for turn in 8:
		HouseVoice.hurry()
		await seconds(0.35)
	for entry: Dictionary in HouseVoice.history:
		played += int(entry.family == &"effect")
	check(HouseVoice.gate() == "" and played >= 3 and HouseVoice.history.size() >= before, "The house makes its sounds (%d effects)" % played)
	check(audit.unexplained().is_empty() and audit.house_breaches.is_empty() and HouseVoice.violations == 0,
		"No house sound is a jump, and none played while its gates were closed: %s" % audit.summary())
	await seconds(settings.house_nothing_time)
	# The answer at its top step, from the nearest place it may come from.
	HouseVoice.answer_step = settings.house_escalate_steps
	HouseVoice._since_accepted = 0.0
	HouseVoice._answer_distance = 0.0
	HouseVoice._since_loud = 0.0          # she has been loud lately: no quiet minute resets it
	HouseVoice._since_answer = INF
	var answered: bool = HouseVoice.answer()
	await seconds(settings.house_answer_delay + 1.0)
	var knock: Dictionary = HouseVoice.history.back()
	check(answered and knock.family == &"answer" and HouseVoice.answer_step == settings.house_escalate_steps
		and audit.unexplained().is_empty() and audit.house_breaches.is_empty(),
		"The answer at its top step, from the nearest place (%.1f u), is no jump: %s" % [Units.to_u(knock.at.distance_to(game.player.global_position)), audit.summary()])
	# A door found ajar, with its creak: she is in the kitchen, the altar door shut, far and behind a wall.
	var altar_door: Door = game.world.interactables["altar_door"]["node"]
	altar_door.snap(false)
	game.player.global_position = house + KITCHEN_FAR
	game.world.rooms("house").sync_to(game.player.global_position)
	await frames(3)
	HouseVoice.begin_run()
	HouseVoice._ajar_from = house + Vector2(1008, 250)
	var gate: String = HouseVoice.gate()
	HouseVoice._leave_ajar()
	await seconds(2.5)
	check(gate == "" and HouseVoice.ajar_done and HouseVoice.history.back().family == &"aftermath" and is_equal_approx(altar_door.swing, settings.house_ajar_swing)
		and not altar_door.is_open and audit.unexplained().is_empty() and audit.house_breaches.is_empty() and HouseVoice.violations == 0,
		"A door found ajar, with its creak, is no jump either: %s" % audit.summary())
	altar_door.snap(true)
	HouseVoice.begin_run()
	HouseVoice._reset_escalation()          # back to the first answer for what follows
	game.player.global_position = house + VESTIBULE_A
	game.world.rooms("house").sync_to(game.player.global_position)
	await frames(3)


## A whole encounter beside her: only the scream jumps; everything else was warned of.
func check_encounter() -> void:
	var audit: Node = overlay.audit
	await place(house + VESTIBULE_B)
	cues.clear()
	entity.listen_time_range = Vector2(0.9, 0.9)
	entity.hunt_persistence = 2.0
	entity.search_duration = 3.0
	NoiseManager.emit_noise(entity.global_position + Vector2.RIGHT * Units.to_px(3.0), Units.to_px(40.0), NoiseManager.SourceType.ENVIRONMENT)
	await frames(3)
	check(Dread.awareness == Dread.Awareness.HEARD and line(3) == "house voice: silent: it is alert (heard)", "It hears: the read-out says why the house is silent: %s" % line(3))
	check(await until(func() -> bool: return cues.has(&"heard"), 1.0) and line(2).contains("what it knows (A): heard ("), "And shows the heard-you cue on channel A: %s" % line(2))
	check(await until(func() -> bool: return cues.has(&"scream"), 3.0), "It screams")
	await seconds(0.3)
	check(line(2).contains("(A): scream (scream)") or line(2).contains("(A): foot_slam"), "The scream shows on channel A: %s" % line(2))
	check(await until(func() -> bool: return Dread.awareness == Dread.Awareness.SEARCHING, 8.0), "It hunts, then loses the trail")
	check(await until(func() -> bool: return cues.has(&"stand_down"), 8.0), "It gives up")
	await seconds(1.5)
	check(line(2).contains("(A): stand_down"), "The stand-down shows on channel A: %s" % line(2))
	print("[Jump-scare audit] after the encounter: %s · screams %d · loudest %.0f dB" % [audit.summary(), audit.screams, audit.loudest_db])
	for entry: Dictionary in audit.rises:
		print("[Jump-scare audit]   +%.0f dB (%.0f to %.0f dB) on %s, after %s · %s" % [entry.jump_db, entry.from_db, entry.to_db, entry.bus, entry.sound, entry.cause])
	check(audit.rises.all(func(entry: Dictionary) -> bool: return entry.sound != ""), "Each logged rise names the sound of the entity that played last")
	check(audit.unexplained().is_empty(), "Through the whole encounter nothing jumped unexplained: %s" % [audit.unexplained()])
	check(audit.rises.all(func(entry: Dictionary) -> bool: return entry.explained) and audit.house_breaches.is_empty() and HouseVoice.violations == 0,
		"Every sudden rise had its warning or was her own, and the house kept its gates")
	check(audit.loudest_db > settings.audit_floor_db, "And the encounter was loud enough to be measured (loudest %.0f dB)" % audit.loudest_db)
	entity.listen_time_range = Vector2(0.7, 1.2)
	entity.hunt_persistence = 5.0
	entity.search_duration = 5.0
