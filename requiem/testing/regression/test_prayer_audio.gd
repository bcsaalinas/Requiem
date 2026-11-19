extends Node2D
## Prayer without voices (headless): praying is a state of its own, and nothing in it speaks.
## A real altar and a real player; E is pressed with Input.action_press and the altar's clock
## is stepped one physics frame at a time, so its noise is the same every run.
##
## Checks: the altar has no voice (the scene, the Prayer Studio, and a whole prayer in which its
## player never plays); its noise is exactly what the altar's numbers say, and the same with
## BodyAudio's "Prayer" removed; Music, Ambience and World sink slowly (slower than holding her
## breath) while the entity's buses and her body are never touched; her mood breathing slows
## at the same level; her heart beats for the prayer, and a hunt still wins; the prayer tone is
## silent with no file and nothing is reported, and with a stand-in file it rises with her
## progress and leaves with the world; the world comes back over 3 s after a whole prayer,
## sooner after a short one, at once when she dies, on a new attempt or when the player is
## freed; holding her breath while she prays is her listening, with no jump either way.

const AltarScene := preload("res://altar/altar.tscn")
const PrayerAudio := preload("res://player/prayer_audio.gd")
const HeartAudio := preload("res://player/heart_audio.gd")
const DULLED: Array[StringName] = [AudioBus.MUSIC, AudioBus.AMBIENCE, AudioBus.WORLD]
const UNTOUCHED: Array[StringName] = [AudioBus.ENTITY, AudioBus.ENTITY_FAR, AudioBus.BODY]
## A little time on top of every wait, for frames.
const MARGIN := 0.3

## A stand-in entity: Dread reads what it knows from these few members only.
class FakeEntity extends CharacterBody2D:
	var current_state := EntityAudio.PATROL
	var active := true
	var listening := false
	func is_listening() -> bool:
		return listening

var failures: Array[String] = []
var checks := 0
var settings: SoundSettings
var player: CharacterBody2D
var breath: Node
var body: BodyAudio
var prayer: Node
var heart: HeartAudio
var altar_root: Node2D
var altar: Node
var dt := 1.0 / 60.0
## Every PRAY noise of the prayer being recorded: { radius, source, elapsed }.
var recorded: Array[Dictionary] = []
var recording := false
var other_noises := 0
## Breath releases and gasps of her own during the suite: the only other noise she may make.
var own_breath := 0
var ended := 0
var last_immediate := false


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame


func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func near(a: float, b: float, tolerance := 0.05) -> bool:
	return absf(a - b) <= tolerance


## One physics frame, with the altar's clock moved on by exactly one frame while E is held.
func tick() -> void:
	if is_instance_valid(altar) and Input.is_action_pressed("pray"):
		altar._process(dt)
	await get_tree().physics_frame


func _ready() -> void:
	settings = SoundSettings.current()
	dt = 1.0 / float(Engine.physics_ticks_per_second)
	GameState.reset()
	release_inputs()
	SoundLibrary.clear()
	NoiseManager.noise_emitted.connect(_on_noise)
	GameState.prayer_ended.connect(func(_source: Node, immediate: bool) -> void:
		ended += 1
		last_immediate = immediate)
	check_settings()
	check_no_voices_in_files()
	await set_up()
	var whole: Array[Dictionary] = await check_whole_prayer()
	await check_short_prayer()
	await check_listening_and_reset()
	await check_death()
	await check_tone()
	await check_hunt()
	await check_parity(whole)
	await check_freed_player()
	check(other_noises <= own_breath,
		"Nothing here made a noise the entity can hear but the altar's own (%d other noises, %d of her own breath)" % [other_noises, own_breath])
	release_inputs()
	SoundLibrary.clear()
	GameState.reset()
	await frames(3)
	print("[Prayer audio tests] %d/%d passed" % [checks - failures.size(), checks])
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)


func _on_noise(_at: Vector2, radius: float, source: int, _duration: float) -> void:
	if source != NoiseManager.SourceType.PRAY:
		other_noises += 1
		return
	if recording:
		recorded.append({"radius": radius, "source": source,
			"elapsed": altar.get_prayer_elapsed() if is_instance_valid(altar) else -1.0})


func release_inputs() -> void:
	for action_name in ["pray", "hold_breath", "sprint", "throw", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action_name)


func check_settings() -> void:
	check(settings.prayer_cutoff_hz < settings.listen_cutoff_hz and settings.prayer_in > settings.listen_in,
		"Prayer goes further than holding her breath (%.0f Hz < %.0f Hz) and slower (%.1f s > %.1f s)" % [
			settings.prayer_cutoff_hz, settings.listen_cutoff_hz, settings.prayer_in, settings.listen_in])
	check(near(settings.prayer_return, 3.0, 0.001) and settings.prayer_cut < settings.prayer_return
		and settings.viv_breath_prayer_pitch < 1.0 and settings.heart_prayer > 0.0 and settings.prayer_tone_db.x < settings.prayer_tone_db.y,
		"The world returns over 3 s, a cut is quicker, her breathing slows, her heart beats and the tone rises")
	check(MixDirector.Priority.LISTEN > MixDirector.Priority.PRAYER and MixDirector.Priority.PRAYER > MixDirector.Priority.THREAT,
		"Holding her breath outranks prayer, prayer outranks the mood of the house")
	var source := FileAccess.get_file_as_string("res://player/prayer_audio.gd")
	check(not source.contains("NoiseManager") and not source.contains("AudioServer") and not source.contains("AudioBus.ENTITY")
		and not source.contains("AudioBus.BODY") and not source.contains("duck(") and not source.contains("focus("),
		"prayer_audio.gd makes no noise, moves no level and never asks for the entity's buses or her body's")
	var altar_source := FileAccess.get_file_as_string("res://altar/body_altar.gd")
	check(altar_source.contains("NoiseManager.emit_noise(posicion, _radio_actual_u() * PX_PER_UNIT, NoiseManager.SourceType.PRAY)"),
		"The altar still makes its own noise, the one way it always did")


func check_no_voices_in_files() -> void:
	var scene_text := FileAccess.get_file_as_string("res://altar/altar.tscn")
	var root: Node = AltarScene.instantiate()
	var clips: Array = root.get_node("BodyAltar").pray_clips
	root.free()
	check(clips.is_empty() and not scene_text.contains("whispering") and not scene_text.contains("pray_clips"),
		"The altar scene has no pray clips: the whispering voices are gone")
	var studio := FileAccess.get_file_as_string("res://testing/experiments/prayer_studio.gd")
	check(not studio.contains("pray_clips.assign") and not studio.contains("sound(\"prayer\")"),
		"The Prayer Studio gives its altar no voice either")


func set_up() -> void:
	player = preload("res://player/player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	breath = player.get_node("HoldBreath")
	breath.breath_released.connect(func(_quiet: bool, _lung: float) -> void: own_breath += 1)
	breath.forced_gasp_started.connect(func(_reason: StringName, _duration: float) -> void: own_breath += 1)
	body = player.get_node("BodyAudio")
	prayer = body.prayer
	heart = body.heart as HeartAudio
	await frames(3)
	check(prayer != null and prayer.name == "Prayer" and prayer.get_parent() == body and prayer.get_script() == PrayerAudio
		and prayer.tone.bus == AudioBus.SFX and not AudioBus.MIXABLE.has(AudioBus.SFX) and not AudioBus.MUFFLEABLE.has(AudioBus.SFX)
		and AudioBus.SFX_FAMILY.has(AudioBus.SFX),
		"Her prayer is a child of BodyAudio; its tone plays on SFX (the effects slider's bus, never ducked or dulled)")


func new_altar() -> void:
	release_inputs()
	if is_instance_valid(altar_root):
		altar_root.queue_free()
	altar_root = AltarScene.instantiate()
	altar_root.position = Vector2(0, -56)
	add_child(altar_root)
	altar = altar_root.get_node("BodyAltar")
	altar.set_process(false)
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	await frames(3)
	altar._on_area_2d_body_entered(player)


func cutoff(bus_name: StringName) -> float:
	return MixDirector.cutoff_hz(bus_name)


func all_at(value: float, tolerance := 1.0) -> bool:
	return DULLED.all(func(bus_name: StringName) -> bool: return near(cutoff(bus_name), value, tolerance))


func mood_loop() -> AudioStreamPlayer:
	return body._loops[body.mood] if body.mood != "" else null


## Waits (with E as it is) until the request is gone or `longest` has passed; returns how long.
func wait_until_open(longest: float) -> float:
	var began := now()
	while MixDirector.is_active(PrayerAudio.PRAYER) and now() - began < longest:
		await tick()
	return now() - began


## Presses E and holds it for `seconds` (or until the prayer ends).
func pray(seconds: float) -> void:
	Input.action_press("pray")
	var began := now()
	var ended_before := ended
	while now() - began < seconds and ended == ended_before:
		await tick()


## The whole twelve seconds, then the return. Returns the altar's noise, for the parity check.
func check_whole_prayer() -> Array[Dictionary]:
	await new_altar()
	# Let her breathing settle in first (it fades in when she appears).
	await get_tree().create_timer(settings.viv_breath_crossfade + MARGIN).timeout
	check(not GameState.is_praying and is_zero_approx(prayer.depth) and all_at(settings.open_hz)
		and not MixDirector.is_active(PrayerAudio.PRAYER) and is_zero_approx(heart.amount) and not heart.playing,
		"Before she prays: the house is open and her heart is silent")
	var loop := mood_loop()
	var loop_db: float = loop.volume_db if loop != null else 0.0
	var gains := {}
	for bus_name in UNTOUCHED:
		gains[bus_name] = MixDirector.gain_db(bus_name)
	recorded.clear()
	recording = true
	Input.action_press("pray")
	var began := now()
	var ended_before := ended
	var checked_early := false
	var checked_deep := false
	var checked_heart := false
	var altar_spoke := false
	var tone_played := false
	var untouched := true
	var level_kept := true
	var cutoff_rose := false
	var status_line := ""
	var last := settings.open_hz
	while ended == ended_before and now() - began < altar.pray_duration + 2.0:
		await tick()
		var t := now() - began
		if is_instance_valid(altar) and (altar._audio_player.playing or altar._audio_player.stream != null):
			altar_spoke = true
		tone_played = tone_played or prayer.tone.playing
		for bus_name in UNTOUCHED:
			if not near(cutoff(bus_name), settings.open_hz, 0.5) or not near(MixDirector.gain_db(bus_name), gains[bus_name], 0.01):
				untouched = false
		if loop != null and (not loop.playing or not near(loop.volume_db, loop_db, 0.01)):
			level_kept = false
		if cutoff(AudioBus.WORLD) > last + 0.5 and ended == ended_before:
			cutoff_rose = true
		last = cutoff(AudioBus.WORLD)
		if not checked_early and t >= settings.listen_in:
			checked_early = true
			var floor_hz := PrayerAudio.prayer_hz((settings.listen_in + 2.0 * dt + 0.05) / settings.prayer_in)
			check(prayer.depth <= (t + 0.05) / settings.prayer_in and DULLED.all(func(bus_name: StringName) -> bool:
				return cutoff(bus_name) >= floor_hz and cutoff(bus_name) > 2.0 * settings.listen_cutoff_hz),
				"Slow in: %.2f s into the prayer the house is barely dulled (depth %.2f, World %.0f Hz; holding her breath would be at %.0f Hz)" % [
					t, prayer.depth, cutoff(AudioBus.WORLD), settings.listen_cutoff_hz])
		if not checked_deep and t >= settings.prayer_in + MARGIN:
			checked_deep = true
			status_line = prayer.status()
			check(is_equal_approx(prayer.depth, 1.0) and all_at(settings.prayer_cutoff_hz),
				"After %.1f s Music, Ambience and World are at %.0f Hz (%.0f / %.0f / %.0f)" % [settings.prayer_in, settings.prayer_cutoff_hz,
					cutoff(AudioBus.MUSIC), cutoff(AudioBus.AMBIENCE), cutoff(AudioBus.WORLD)])
			check(loop != null and near(loop.pitch_scale, settings.viv_breath_prayer_pitch, 0.001)
				and near(body._loops[BodyAudio.PANT].pitch_scale, 1.0, 0.001),
				"Her %s breathing has slowed to %.2f (her panting would play as recorded)" % [body.mood, loop.pitch_scale if loop != null else 0.0])
		if not checked_heart and t >= settings.prayer_in + settings.heart_rise_time + MARGIN:
			checked_heart = true
			check(heart.playing and heart.reason == HeartAudio.PRAYER and near(heart.amount, settings.heart_prayer, 0.01)
				and near(heart.level_db(), HeartAudio.level_for(settings.heart_prayer), 0.5) and heart.level_db() > HeartAudio.SILENT_DB + 30.0,
				"Her heart beats for the prayer: %.2f (%s), %.1f dB" % [heart.amount, heart.reason, heart.level_db()])
	recording = false
	var whole: Array[Dictionary] = recorded.duplicate()
	release_inputs()
	var end_time := now()
	check(ended == ended_before + 1 and not last_immediate and not GameState.is_praying and (not is_instance_valid(altar) or altar.is_queued_for_deletion()),
		"The prayer completed after %.1f s, as a normal end" % (end_time - began))
	check(not altar_spoke, "Through the whole prayer the altar's own player never played and held no voice")
	check(untouched, "The Entity, EntityFar and Body buses stayed open and at their level the whole time")
	check(level_kept, "Her breathing kept its level while it slowed")
	check(not cutoff_rose, "While she prayed the house only ever sank, it never jumped back up")
	check(not tone_played and not prayer.has_tone() and not SoundLibrary._warned.has(PrayerAudio.TONE),
		"The tone's folder is empty: no tone, and nothing was reported about it")
	check(status_line.begins_with("praying · world dulled 100%") and status_line.ends_with("tone: no file"),
		"The read-out says so: \"%s\"" % status_line)
	check_noise(whole)
	# Nothing after the end.
	var count := whole.size()
	await frames(10)
	check(recorded.size() == count, "Nothing more is heard from the altar once the prayer is over")
	# The return.
	var halfway := false
	var falling := true
	last = cutoff(AudioBus.WORLD)
	while now() - end_time < settings.prayer_return + MARGIN:
		await tick()
		if cutoff(AudioBus.WORLD) < last - 0.5:
			falling = false
		last = cutoff(AudioBus.WORLD)
		if not halfway and now() - end_time >= settings.prayer_return * 0.5:
			halfway = true
			check(DULLED.all(func(bus_name: StringName) -> bool:
				return cutoff(bus_name) > settings.prayer_cutoff_hz * 1.5 and cutoff(bus_name) < settings.open_hz * 0.5),
				"%.1f s after the end the world is on its way back (World %.0f Hz)" % [now() - end_time, cutoff(AudioBus.WORLD)])
	check(all_at(settings.open_hz) and not MixDirector.is_active(PrayerAudio.PRAYER) and is_zero_approx(prayer.depth),
		"After %.1f s the world is back, open, and the prayer's request is gone" % settings.prayer_return)
	check(falling, "The world came back smoothly, never sinking again on the way")
	check(loop != null and near(loop.pitch_scale, 1.0, 0.001) and near(loop.volume_db, loop_db, 0.01),
		"Her breathing is back to its own pace and level")
	await frames(3)
	check(is_zero_approx(heart.amount) and not heart.playing and heart.reason == &"", "And her heart is silent again")
	return whole


## The altar's noise through one whole prayer, against the altar's own numbers.
func check_noise(events: Array[Dictionary]) -> void:
	var small := Units.to_px(float(altar_number(&"pray_noise_radius_u")))
	var big := Units.to_px(float(altar_number(&"pulse_radius_u")))
	var interval := float(altar_number(&"pray_noise_interval"))
	var pulse_at := float(altar_number(&"pulse_at_time"))
	var pulse_end := pulse_at + float(altar_number(&"pulse_duration"))
	var duration := float(altar_number(&"pray_duration"))
	var eps := 0.0001
	check(not events.is_empty() and near(events[0].radius, small, 0.01) and near(events[0].elapsed, 0.0, eps),
		"The first noise comes at once, at %.0f u" % Units.to_u(small))
	check(events.all(func(e: Dictionary) -> bool: return e.source == NoiseManager.SourceType.PRAY),
		"Every noise of the prayer is a PRAY noise")
	var pulse_index := -1
	for i in events.size():
		if events[i].elapsed >= pulse_at - eps:
			pulse_index = i
			break
	check(pulse_index > 0 and near(events[pulse_index].radius, big, 0.01) and events[pulse_index].elapsed < pulse_at + dt + eps,
		"The pulse makes its own noise at %.1f s, at %.0f u" % [pulse_at, Units.to_u(big)])
	var radii_right := true
	for e in events:
		var inside: bool = e.elapsed >= pulse_at - eps and e.elapsed < pulse_end - dt - eps
		var outside: bool = e.elapsed < pulse_at - eps or e.elapsed > pulse_end + dt + eps
		if (inside and not near(e.radius, big, 0.01)) or (outside and not near(e.radius, small, 0.01)):
			radii_right = false
	check(radii_right, "%.0f u from %.1f to %.1f s, %.0f u the rest of the time" % [Units.to_u(big), pulse_at, pulse_end, Units.to_u(small)])
	var gaps_right := true
	var previous := 0.0
	for i in range(1, events.size()):
		if i == pulse_index:
			continue
		var gap: float = events[i].elapsed - previous
		if gap < interval - eps or gap > interval + dt + eps:
			gaps_right = false
		previous = events[i].elapsed
	var periodic := events.size() - 2
	check(gaps_right and periodic >= floori(duration / (interval + dt)) and periodic <= floori(duration / interval)
		and events.back().elapsed <= duration + eps,
		"Then one every %.1f s until the end: %d noises in all" % [interval, events.size()])


func altar_number(property: StringName) -> Variant:
	var root: Node = AltarScene.instantiate()
	var value: Variant = root.get_node("BodyAltar").get(property)
	root.free()
	return value


## A prayer let go after a second has less to come back from.
func check_short_prayer() -> void:
	await new_altar()
	await pray(1.0)
	var depth: float = prayer.depth
	release_inputs()
	altar._process(dt)    # the altar sees E released: a normal end
	var back := await wait_until_open(settings.prayer_return + MARGIN)
	check(not last_immediate and back <= depth * settings.prayer_return + MARGIN and back < settings.prayer_return - 0.5
		and all_at(settings.open_hz),
		"A prayer let go after 1 s (depth %.2f) is back in %.2f s, sooner than %.0f s" % [depth, back, settings.prayer_return])


## Holding her breath while she prays is her listening; then a new attempt cuts the prayer.
func check_listening_and_reset() -> void:
	await new_altar()
	await pray(settings.prayer_in + MARGIN)
	check(all_at(settings.prayer_cutoff_hz), "Deep in the prayer: %.0f Hz" % cutoff(AudioBus.WORLD))
	breath.reset_input_latch()
	Input.action_press("hold_breath")
	var biggest := 0.0
	var last := cutoff(AudioBus.WORLD)
	var began := now()
	while now() - began < settings.listen_in + MARGIN:
		await tick()
		biggest = maxf(biggest, absf(log(cutoff(AudioBus.WORLD) / last) / log(2.0)))
		last = cutoff(AudioBus.WORLD)
	check(breath.is_holding and GameState.is_praying and MixDirector.is_active(PrayerAudio.PRAYER) and all_at(settings.listen_cutoff_hz),
		"Holding her breath while she prays: her listening decides (%.0f Hz)" % cutoff(AudioBus.WORLD))
	Input.action_release("hold_breath")
	began = now()
	while now() - began < settings.listen_out + MARGIN:
		await tick()
		biggest = maxf(biggest, absf(log(cutoff(AudioBus.WORLD) / last) / log(2.0)))
		last = cutoff(AudioBus.WORLD)
	check(GameState.is_praying and all_at(settings.prayer_cutoff_hz),
		"She breathes again: the prayer takes the house back (%.0f Hz)" % cutoff(AudioBus.WORLD))
	check(biggest < 0.25, "No jump either way: at most %.2f octaves in one frame" % biggest)
	release_inputs()
	GameState.reset()
	var back := await wait_until_open(settings.prayer_return)
	check(last_immediate and back <= settings.prayer_cut + MARGIN * 0.5 and all_at(settings.open_hz),
		"A new attempt cuts the prayer: open in %.2f s (prayer_cut %.1f s)" % [back, settings.prayer_cut])


func check_death() -> void:
	await new_altar()
	await pray(settings.prayer_in + MARGIN)
	GameState.kill_player()
	release_inputs()
	var back := await wait_until_open(settings.prayer_return)
	check(last_immediate and back <= settings.prayer_cut + MARGIN * 0.5 and all_at(settings.open_hz),
		"She dies while praying: the prayer's low-pass is gone in %.2f s" % back)
	await frames(3)
	check(heart.prayer_amount == 0.0 and not heart.playing, "And her heart is silent")
	GameState.reset()
	await frames(3)


## With a stand-in file the tone plays: it rises with her progress and leaves with the world.
func check_tone() -> void:
	var stand_in: Array[AudioStream] = [load("res://assets/audio/horror-jam-kit 2/WAV/Foley/creak_02.wav") as AudioStream]
	SoundLibrary._files[PrayerAudio.TONE] = stand_in
	await new_altar()
	Input.action_press("pray")
	var began := now()
	var first := INF
	var falls := false
	var step := 0.0
	var last: float = prayer.tone_db()
	while now() - began < 4.0:
		await tick()
		var level: float = prayer.tone.volume_db
		if prayer.tone.playing and first == INF:
			first = level
		if level < last - 0.01:
			falls = true
		if last > -40.0:
			step = maxf(step, level - last)
		last = level
	var expected: float = lerpf(settings.prayer_tone_db.x, settings.prayer_tone_db.y, altar.get_prayer_elapsed() / altar.pray_duration)
	check(prayer.tone.playing and prayer.tone.bus == AudioBus.SFX and near(prayer.tone.volume_db, expected, 0.2),
		"With a file the tone plays on SFX at %.1f dB (%.1f expected for her progress)" % [prayer.tone.volume_db, expected])
	check(first <= -40.0 and step < 1.0 and not falls,
		"It comes in from silence (first at %.1f dB), never steps (at most %.2f dB a frame) and never falls while she prays" % [first, step])
	check(prayer.status().contains("tone ") and prayer.status().contains("dB"), "The read-out gives its level: \"%s\"" % prayer.status())
	release_inputs()
	altar._process(dt)
	var rises := false
	last = prayer.tone.volume_db
	while MixDirector.is_active(PrayerAudio.PRAYER) and now() - began < 4.0 + settings.prayer_return + MARGIN:
		await tick()
		if prayer.tone.volume_db > last + 0.01:
			rises = true
		last = prayer.tone.volume_db
	await frames(2)
	check(not rises and not prayer.tone.playing and prayer.tone.volume_db <= PrayerAudio.SILENT_DB and all_at(settings.open_hz),
		"It fades out with the world and stops")
	SoundLibrary.clear()


## A hunt during prayer: her heart beats for the hunt.
func check_hunt() -> void:
	await new_altar()
	await pray(settings.prayer_in + MARGIN)
	var entity := FakeEntity.new()
	entity.current_state = EntityAudio.HUNT
	add_child(entity)
	entity.set_physics_process(false)
	Dread.watch(entity)
	var began := now()
	while now() - began < settings.threat_lag.y + settings.threat_rise_time + settings.heart_rise_time + MARGIN:
		await tick()
	var hunt: float = HeartAudio.push(Dread.threat, settings.heart_threat_from, settings.heart_threat)
	check(GameState.is_praying and heart.reason == HeartAudio.THREAT and near(heart.amount, hunt, 0.01) and hunt > heart.prayer_amount
		and near(heart.prayer_amount, settings.heart_prayer, 0.01),
		"Hunted while she prays, the hunt wins: %.2f (%s) over the prayer's %.2f" % [heart.amount, heart.reason, heart.prayer_amount])
	entity.queue_free()
	release_inputs()
	GameState.reset()
	await wait_until_open(settings.prayer_return)
	await frames(3)


## The same prayer with BodyAudio's "Prayer" removed: the altar's noise is the same.
func check_parity(whole: Array[Dictionary]) -> void:
	body.remove_child(prayer)
	prayer.free()
	await new_altar()
	recorded.clear()
	recording = true
	Input.action_press("pray")
	var ended_before := ended
	var steps := 0
	while ended == ended_before and steps < ceili(altar.pray_duration / dt) + 10:
		altar._process(dt)
		steps += 1
	recording = false
	var without: Array[Dictionary] = recorded.duplicate()
	release_inputs()
	var same := without.size() == whole.size()
	for i in mini(without.size(), whole.size()):
		if not is_equal_approx(without[i].radius, whole[i].radius) or not is_equal_approx(without[i].elapsed, whole[i].elapsed):
			same = false
	check(same and not whole.is_empty(), "Without the prayer's sound the altar makes the same %d noises at the same radii (%d)" % [whole.size(), without.size()])
	await frames(3)
	# Put her prayer back, as BodyAudio makes it.
	prayer = PrayerAudio.new()
	prayer.name = "Prayer"
	body.prayer = prayer
	body.add_child(prayer)
	await frames(2)


## The player leaves mid-prayer: no request is left behind.
func check_freed_player() -> void:
	await new_altar()
	await pray(settings.prayer_in * 0.5)
	check(MixDirector.is_active(PrayerAudio.PRAYER) and cutoff(AudioBus.WORLD) < settings.open_hz * 0.5,
		"Halfway in (World %.0f Hz)" % cutoff(AudioBus.WORLD))
	player.queue_free()
	await frames(2)
	altar._process(dt)
	release_inputs()
	await frames(2)
	check(not MixDirector.is_active(PrayerAudio.PRAYER) and all_at(settings.open_hz) and not GameState.is_praying,
		"The player freed mid-prayer leaves no request behind: the house is open")
