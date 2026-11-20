extends Node
## Nothing calm is a sudden loud rise beside her (headless, the real house).
## The jump-scare audit logs a rise on Master of more than audit_jump_db (18 dB) within
## audit_jump_window (0.1 s), measured from no lower than audit_floor_db. While the entity knows
## nothing (unaware, or standing still on its patrol) nothing explains such a rise. So here it
## stands calm 1.5 u from Viv with nothing between them (ring 3, full level), the music drone
## is away, and every file of every set it can sound while calm is played through its real path
## (play_set with the cue's own gain, the idle voice's _say, its breath and drag loops starting).
## Each one-shot is played at the top of its random level (+set_volume_range_db): the worst case.
## The Master meter is read every frame the way the audit reads it. Every rise must stay at
## least 1 dB under the audit's threshold, also while she holds her breath (the entity +2 dB).
## The suite prints one table: set, loudest file, peak, rise, rise while holding.
##
## This has its own suite because playing every mumbled phrase takes over a minute, and the
## runner gives each suite three minutes.

const VESTIBULE_A := Vector2(520, 400)
## 1.5 u from Viv, the same room, nothing between them.
const BESIDE_HER := Vector2(568, 400)
## What it can sound while calm: the set, the cue that plays it (its cue_gain_db), and how it
## is started. "step"/"tick": an animation cue; "talk": its idle voice; "loop": a loop starting.
const CALM_SETS := [
	["entity/claws_walk", "footstep_left", "step"],
	["entity/pat_tap", "claw_tick", "tick"],
	[EntityAudio.MUMBLE, "", "talk"],
	[EntityAudio.BREATH_CALM, "", "loop"],
	[EntityAudio.DRAG, "", "loop"],
]
## Short sounds are played this many times each; the loudest reading counts.
const CLICK_TRIES := 2
## Meter readings per frame while a sound plays, and the pause between two (microseconds).
const SAMPLES_PER_FRAME := 16
const SAMPLE_GAP_USEC := 500
## Readings before a sound starts, and after it ends.
const LEAD := 0.15
const TAIL := 0.2
## A loop is watched through one whole turn of its file, and this much more (its fade-in is
## loop_fade).
const LOOP_WATCH := 1.0

var failures: Array[String] = []
var checks := 0
var settings: SoundSettings
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
var body: BodyAudio
var house := Vector2.ZERO
var noises := 0
var master := 0
var calm_always := true
var kept_grace := 0.0
## Results per set: { file, peak, rise, rise_holding }.
var results := {}


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


func _ready() -> void:
	settings = SoundSettings.current()
	master = AudioServer.get_bus_index(AudioBus.MASTER)
	await set_up()
	await measure_all(false)
	await measure_loudest_holding()
	print_table()
	check_rule()
	check(calm_always, "It stayed calm (unaware or standing still on its patrol) through every measurement")
	check(noises == 0, "None of it made a noise the entity could hear (%d)" % noises)
	settings.talk_pause_grace = kept_grace
	game.queue_free()
	await frames(3)
	print("[Calm beside her tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


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
	game.has_key = true
	house = game.world.zones["house"].global_position
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	body = game.player.get_node("BodyAudio") as BodyAudio
	game.player.global_position = house + VESTIBULE_A
	game.world.rooms("house").sync_to(game.player.global_position)
	var route: Array[Vector2] = [house + BESIDE_HER]
	entity.reset_encounter(house + BESIDE_HER, route)
	entity.show()
	entity.active = true
	# It stands where it is put: nothing moves it, and its animations cue nothing on their own
	# (each sound is played here, one file at a time).
	entity.set_physics_process(false)
	entity.velocity = Vector2.ZERO
	entity.sprite_rig.cue.disconnect(audio.play_cue)
	await frames(3)
	audio.placed()
	await frames(2)
	check(audio.heard_ring == 3 and absf(audio.heard_u - 1.5) < 0.2 and not Acoustics.reading(entity).blocked,
		"It stands 1.5 u from her with nothing between them: ring %d, %.2f u" % [audio.heard_ring, audio.heard_u])
	check(Dread.awareness_of(entity, audio) <= Dread.Awareness.PAUSED, "It knows nothing: %s" % Dread.awareness_name())
	# The drone away, all the way out.
	MusicDirector.turn_drone(false)
	MusicDirector.drone_wait = INF          # and it stays away until this suite is done
	var music := AudioServer.get_bus_index(AudioBus.MUSIC)
	var deadline := now() + settings.music_drone_fade_out + 1.0
	while now() < deadline and peak(music) > settings.audit_floor_db - 20.0:
		await get_tree().process_frame
	check(not MusicDirector.drone_in and peak(music) <= settings.audit_floor_db - 20.0,
		"The music drone is away (Music at %.0f dB)" % peak(music))
	# While it stands still its idle phrase would trail off; here each phrase is heard whole.
	kept_grace = settings.talk_pause_grace
	settings.talk_pause_grace = 999.0
	audio._talk_wait = 1.0e9
	await seconds(settings.loop_fade + 0.3)
	print("[Calm beside her] Master at rest, breathing beside her: %.1f dB" % peak(master))


func peak(bus: int) -> float:
	return maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))


func note_calm() -> void:
	calm_always = calm_always and Dread.awareness_of(entity, audio) <= Dread.Awareness.PAUSED


## Starts something with `start` and watches Master for `watch` seconds the way the audit does:
## the loudest peak, and the largest rise within audit_jump_window, from no lower than the floor.
func measure(start: Callable, watch: float) -> Dictionary:
	var recent: Array = []
	var deadline := now() + LEAD
	while now() < deadline:
		recent.append([now(), maxf(peak(master), settings.audit_floor_db)])
		await get_tree().process_frame
	start.call()
	var top := -INF
	var rise := 0.0
	deadline = now() + watch
	while now() < deadline:
		await get_tree().process_frame
		note_calm()
		# The meter holds the peak of the last block the mixer made (about 10 ms); read once a
		# frame it misses some blocks, and a click's loudest instant is in one of them. So it is
		# read many times in each frame.
		for sample in SAMPLES_PER_FRAME:
			var time := Time.get_ticks_usec() / 1000000.0
			var level := peak(master)
			top = maxf(top, level)
			level = maxf(level, settings.audit_floor_db)
			while not recent.is_empty() and time - float(recent[0][0]) > settings.audit_jump_window:
				recent.pop_front()
			var lowest := level
			for reading: Array in recent:
				lowest = minf(lowest, float(reading[1]))
			rise = maxf(rise, level - lowest)
			recent.append([time, level])
			OS.delay_usec(SAMPLE_GAP_USEC)
	return {"peak": top, "rise": rise}


## Plays `file` of the calm set `entry` once through its real path; returns { peak, rise }.
func play_file(entry: Array, file: AudioStream) -> Dictionary:
	var set_id: String = entry[0]
	var kind: String = entry[2]
	var kept_set: Variant = SoundLibrary._sets.get(set_id)
	var kept_files: Array[AudioStream] = SoundLibrary.files(set_id)
	var only: Array[AudioStream] = [file]
	SoundLibrary._files[set_id] = only
	var result := {}
	match kind:
		"step", "tick":
			var one := AudioStreamRandomizer.new()
			one.add_stream(-1, file)
			one.random_pitch = 1.0
			one.random_volume_offset_db = 0.0
			SoundLibrary._sets[set_id] = one
			var gain := float(settings.cue_gain_db.get(entry[1], 0.0)) + settings.set_volume_range_db
			var plays := func() -> void: audio.play_set(set_id, gain)
			result = await measure(plays, file.get_length() + TAIL)
		"talk":
			var says := func() -> void:
				audio._say(false)
				audio._talk.set_meta(&"level", SoundLibrary.gain_db(set_id) + settings.set_volume_range_db)
				audio._talk.volume_db = audio._heard_db(float(audio._talk.get_meta(&"level")))
			result = await measure(says, file.get_length() / (1.0 - settings.set_pitch_range) + TAIL)
			audio._talk.stop()
			audio._talk_wait = 1.0e9
		"loop":
			SoundLibrary._sets.erase(set_id)
			var starts := func() -> void:
				if set_id == EntityAudio.DRAG:
					entity.velocity = Vector2(Units.to_px(1.0), 0.0)       # it walks: its shroud drags
				else:
					audio.stop_all()                                         # its breath starts again
			# Watched from its start through one whole turn of the loop: the breaths inside it
			# rise out of near silence too, not only its start.
			result = await measure(starts, file.get_length() + LOOP_WATCH)
			entity.velocity = Vector2.ZERO
	SoundLibrary._files[set_id] = kept_files
	if kept_set == null:
		SoundLibrary._sets.erase(set_id)
	else:
		SoundLibrary._sets[set_id] = kept_set
	if kind == "loop":
		# Back to its own take of the breath, and the drag faded out, before the next sound.
		audio.stop_all()
		await seconds(settings.loop_fade + 0.3)
	return result


## Every file of every calm set, beside her.
func measure_all(holding: bool) -> void:
	for entry: Array in CALM_SETS:
		var set_id: String = entry[0]
		var tries := CLICK_TRIES if entry[2] in ["step", "tick"] else 1
		var loudest := {"file": "", "peak": -INF, "rise": -INF}
		for file in SoundLibrary.files(set_id):
			var best := {"peak": -INF, "rise": -INF}
			for attempt in tries:
				var reading := await play_file(entry, file)
				best.peak = maxf(best.peak, reading.peak)
				best.rise = maxf(best.rise, reading.rise)
			if best.rise > loudest.rise:
				loudest = {"file": file.resource_path.get_file(), "stream": file, "peak": best.peak, "rise": best.rise}
		results[set_id] = loudest
		print("[Calm beside her] %s: loudest %s, peak %.1f dB, rise %.1f dB" % [set_id, loudest.file, loudest.peak, loudest.rise])


## The loudest file of each set again, while she holds her breath.
func measure_loudest_holding() -> void:
	# She holds her breath to listen: BodyAudio's own listening, held at its full amount (it
	# runs on its own and would let go, since nobody presses the key here).
	body.set_process(false)
	body.listen = 1.0
	body._apply_listening()
	await seconds(settings.listen_in + 0.3)
	check(MixDirector.gain_db(AudioBus.ENTITY) >= settings.listen_entity_db - 0.01, "Holding her breath, the entity is %.0f dB up" % MixDirector.gain_db(AudioBus.ENTITY))
	for entry: Array in CALM_SETS:
		var set_id: String = entry[0]
		var tries := CLICK_TRIES + 1 if entry[2] in ["step", "tick"] else 1
		var best := -INF
		for attempt in tries:
			var reading := await play_file(entry, results[set_id].stream)
			best = maxf(best, reading.rise)
		results[set_id].rise_holding = best
	body.listen = 0.0
	body._apply_listening()
	body.set_process(true)
	await seconds(settings.listen_out + 0.2)


func print_table() -> void:
	print("[Calm beside her] calm, 1.5 u from her, no drone · position level beside her %.1f dB (calm trim %.1f dB of position_calm_near_db %.1f) · rule: every rise at most %.0f dB" % [
		audio.position_level_db(), audio.calm_trim_db(), settings.position_calm_near_db, settings.audit_jump_db - 1.0])
	print("[Calm beside her] | set | loudest file | peak on Master | rise | rise while holding her breath |")
	for entry: Array in CALM_SETS:
		var result: Dictionary = results[entry[0]]
		print("[Calm beside her] | %s | %s | %.1f dB | %.1f dB | %.1f dB |" % [entry[0], result.file, result.peak, result.rise, result.get("rise_holding", -1.0)])


func check_rule() -> void:
	var limit := settings.audit_jump_db - 1.0
	check(is_equal_approx(audio.calm_trim_db(), settings.position_calm_near_db) and settings.position_calm_near_db <= 0.0,
		"Calm and 1.5 u from her, its position sounds are held down by the whole calm trim (%.1f dB)" % audio.calm_trim_db())
	# What the trim would have to be, from these readings: every rise moves with it dB for dB
	# while the house under it is quieter than the audit's floor.
	var worst := -INF
	for entry: Array in CALM_SETS:
		worst = maxf(worst, maxf(results[entry[0]].rise, float(results[entry[0]].get("rise_holding", -INF))) - audio.calm_trim_db())
	print("[Calm beside her] untrimmed, the worst rise would be %.1f dB: a trim of %.1f dB is needed, %.1f dB is set" % [
		worst, minf(0.0, limit - worst), settings.position_calm_near_db])
	for entry: Array in CALM_SETS:
		var result: Dictionary = results[entry[0]]
		check(result.peak > settings.audit_floor_db - 30.0, "%s was heard on Master (peak %.1f dB)" % [entry[0], result.peak])
		check(result.rise <= limit, "Calm beside her, %s rises at most %.0f dB (%.1f dB, %s)" % [entry[0], limit, result.rise, result.file])
		check(float(result.get("rise_holding", INF)) <= limit,
			"Also while she holds her breath (%.1f dB)" % float(result.get("rise_holding", INF)))
