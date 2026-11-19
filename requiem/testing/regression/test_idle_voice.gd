extends Node
## The entity's idle voice (headless): on patrol it mumbles now and then while it walks, never
## the same phrase twice running; searching, the voice is lower and rarer and it sniffs in
## short steady runs; it never speaks while it listens, screams or hunts.

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
var settings: SoundSettings
var home := Vector2.ZERO
## Sniffs since the last clear, as times in seconds.
var sniffs: Array[float] = []
var awareness: Array[StringName] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func _ready() -> void:
	settings = SoundSettings.current()
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
	home = game.world.marker("house", "Patrol1")
	game.player.global_position = game.world.marker("house", "Patrol4")
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	# This suite is about when it speaks, so it listens from right beside the entity, where
	# nothing is lost on the way (test_rings covers what distance does to its voice).
	Acoustics.set_listener(entity)
	entity.get_node("CollisionShape2D").disabled = false
	for door in game.world.zones["house"].get_node("Doors").get_children():
		if door is Door:
			door.noise_radius_u = 0.0
			door.quiet_noise_radius_u = 0.0
	audio.played.connect(func(set_id: String, _voice: AudioStreamPlayer2D) -> void:
		if set_id == EntityAudio.SNIFF: sniffs.append(Time.get_ticks_msec() / 1000.0))
	audio.awareness_played.connect(func(moment: StringName, _set: String, _stream: AudioStream, _level: float) -> void: awareness.append(moment))
	check_settings()
	await check_patrol()
	await check_pause()
	await check_silences()
	await check_search()
	game.queue_free()
	await frames(3)
	print("[Idle voice tests] %d/%d passed" % [checks - failures.size(), checks])
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)


func arm(walking: bool) -> void:
	var route: Array[Vector2] = [game.world.marker("house", "Patrol2"), game.world.marker("house", "Patrol3")]
	entity.reset_encounter(home, route)
	entity.show()
	entity.active = true
	entity._patrol_wait = 0.0 if walking else 999.0
	await frames(30 if walking else 3)
	sniffs.clear()
	awareness.clear()


## Lets the next phrase start now; returns true if one did within a few frames.
func prompt() -> bool:
	audio._talk.stop()
	audio._talk_wait = 0.0
	await frames(3)
	return audio._talk.playing


func check_settings() -> void:
	check(settings.talk_interval_patrol == Vector2(6, 15) and settings.talk_interval_search == Vector2(10, 20)
		and is_equal_approx(settings.talk_pitch_search, 0.9), "Patrol: a phrase every 6-15 s. Search: every 10-20 s, at pitch 0.9")
	check(settings.sniff_run_count == Vector2i(2, 4), "Sniff runs are 2 to 4 sniffs long")
	check(SoundLibrary.files(EntityAudio.MUMBLE).size() >= 10 and SoundLibrary.files(EntityAudio.SNIFF).size() >= 10
		and SoundLibrary.files(EntityAudio.SNIFF).all(func(stream: AudioStream) -> bool: return stream.get_length() < 0.6),
		"There are many phrases to say, and every sniff file is a single sniff")
	check(audio._talk.bus == AudioBus.ENTITY, "The voice plays on the Entity bus")


func check_patrol() -> void:
	await arm(true)
	check(entity.velocity.length() > 4.0 and not audio._talk.playing and audio._talk_wait >= settings.talk_interval_patrol.x - 1.0,
		"It starts its patrol without talking at once")
	var said: Array[AudioStream] = []
	var waits_ok := true
	var pitches_ok := true
	for index in 40:
		if entity.velocity.length() <= 4.0:         # keep it walking between prompts
			entity._patrol_wait = 0.0
			await frames(20)
		if not await prompt():
			continue
		var stream: AudioStream = audio.last_talk.stream
		said.append(stream)
		var floor_wait: float = stream.get_length() / audio._talk.pitch_scale + settings.talk_min_gap
		waits_ok = waits_ok and audio._talk_wait >= settings.talk_interval_patrol.x - 0.1 \
			and audio._talk_wait <= maxf(settings.talk_interval_patrol.y, floor_wait) + 0.1
		pitches_ok = pitches_ok and audio._talk.pitch_scale >= 0.94 - 0.001 and audio._talk.pitch_scale <= 1.06 + 0.001
	var repeats := 0
	var distinct := {}
	for index in said.size():
		distinct[said[index]] = true
		repeats += int(index > 0 and said[index] == said[index - 1])
	check(said.size() >= 30, "While it walks its patrol it talks whenever its wait is over (%d phrases)" % said.size())
	check(repeats == 0, "It never says the same phrase twice in a row")
	check(distinct.size() >= 12, "It has many different things to mumble (%d different phrases in %d)" % [distinct.size(), said.size()])
	check(waits_ok, "After each phrase the next waits 6 to 15 s, and never starts on top of the last")
	check(pitches_ok, "On patrol the voice keeps its natural pitch (0.94 to 1.06)")
	check(audio._talk.global_position.distance_to(entity.global_position) < 1.0 and audio.last_talk.state == "PATROL",
		"The voice comes from where it is")
	check(is_equal_approx(SoundLibrary.gain_db(EntityAudio.MUMBLE), 0.0)
		and SoundLibrary.gain_db(EntityAudio.HEARD_VOICE) + settings.heard_voice_gain_db > SoundLibrary.gain_db(EntityAudio.MUMBLE) + settings.set_volume_range_db - 0.01,
		"Even at its loudest, idle talking stays under the heard-you voice")


func check_pause() -> void:
	# Standing at a patrol point it does not start to talk.
	await arm(false)
	check(not await prompt() and entity.velocity.length() < 1.0, "Standing still at a patrol point, it does not start talking")
	check(audio.breath_set() == EntityAudio.BREATH_CALM, "But it goes on breathing")
	# A phrase it was saying when it stops trails off; breathing continues; no click.
	await arm(true)
	entity._patrol_wait = 0.0
	await frames(20)
	check(await prompt(), "Walking, it talks")
	var before: float = audio._talk.volume_db
	entity._patrol_wait = 999.0
	await frames(int((settings.talk_pause_grace + settings.talk_pause_fade * 0.5) * 60.0))
	var midway: float = audio._talk.volume_db
	check(audio._talk.playing and midway < before - 3.0 and midway > EntityAudio.SILENT_DB,
		"When it pauses, the phrase trails off rather than cutting (%.0f dB on the way down)" % midway)
	await frames(int(settings.talk_pause_fade * 60.0) + 10)
	check(not audio._talk.playing and audio.breath_set() == EntityAudio.BREATH_CALM and not audio.is_dragging(),
		"Then it is quiet: no talk, no steps, still breathing")
	check(awareness.is_empty() and int(audio.plays.get(EntityAudio.NECK_CLICK, 0)) == 0, "A pause makes no click and no awareness cue")


func check_silences() -> void:
	await arm(true)
	entity._patrol_wait = 0.0
	await frames(20)
	check(await prompt(), "It is talking when the sound comes")
	NoiseManager.emit_noise(entity.global_position + Vector2(30, 0), Units.to_px(8.0), NoiseManager.SourceType.THROW)
	check(entity.is_listening() and not audio._talk.playing, "A phrase it is saying is cut off the instant it hears something")
	var spoke := false
	audio._talk_wait = 0.0
	while entity.is_listening() or entity.is_screaming():
		audio._talk_wait = 0.0
		await frames(1)
		spoke = spoke or audio._talk.playing
	check(not spoke, "It never speaks while it listens or screams")
	entity.last_heard_position = game.world.marker("house", "Patrol3")
	for tick in 90:
		audio._talk_wait = 0.0
		await frames(1)
		spoke = spoke or audio._talk.playing
	check(entity.get_state_name() == "HUNT" and not spoke, "Nor while it hunts")
	check(sniffs.is_empty(), "It does not sniff outside a search")


func check_search() -> void:
	entity.search_duration = 60.0
	entity._hunt_timer = entity.hunt_persistence
	await frames(3)
	check(entity.get_state_name() == "SEARCH" and audio._talk_wait >= settings.talk_interval_search.x - 0.2,
		"When the search begins, its next phrase is at least 10 s away")
	check(audio._sniff_wait >= 0.0 and audio._sniff_run_wait > audio._sniff_wait, "The single sniff after 'lost' comes first, runs of sniffs after it")
	# The voice of the search.
	var pitches: Array[float] = []
	var waits_ok := true
	var said: Array[AudioStream] = []
	for index in 12:
		if await prompt():
			pitches.append(audio._talk.pitch_scale)
			said.append(audio.last_talk.stream)
			var floor_wait: float = audio.last_talk.stream.get_length() / audio._talk.pitch_scale + settings.talk_min_gap
			waits_ok = waits_ok and audio._talk_wait >= settings.talk_interval_search.x - 0.1 \
				and audio._talk_wait <= maxf(settings.talk_interval_search.y, floor_wait) + 0.1
	check(pitches.size() >= 10 and pitches.all(func(pitch: float) -> bool: return pitch > 0.86 and pitch < 0.935),
		"Searching, its voice is lower and slower: pitch 0.9 (%s)" % [pitches.slice(0, 4)])
	check(waits_ok and audio.last_talk.state == "SEARCH", "And sparser: 10 to 20 s between phrases")
	var repeats := 0
	for index in range(1, said.size()):
		repeats += int(said[index] == said[index - 1])
	check(repeats == 0, "Still never the same phrase twice in a row")
	audio._talk.stop()
	# Sniffing while it scuttles.
	sniffs.clear()
	var runs: Array = []
	for attempt in 6:
		var scuttling := false
		for tick in 300:
			await frames(1)
			if entity.get_state_name() == "SEARCH" and entity.velocity.length() > 4.0:
				scuttling = true
				break
			if entity._search_queue.is_empty() or entity._feel_left > 0.3:
				entity._feel_left = 0.0
				entity._search_queue.clear()
				entity._search_queue.append(game.world.marker("house", "Patrol%d" % (2 + attempt % 3)))
		if not scuttling:
			continue
		sniffs.clear()
		audio._sniff_wait = -1.0
		audio._sniffs_left = 0
		audio._sniff_run_wait = 0.02
		await get_tree().create_timer(settings.sniff_run_count.y * settings.sniff_run_pace.y + 0.5).timeout
		if not sniffs.is_empty():
			runs.append(sniffs.duplicate())
		if runs.size() >= 3:
			break
	check(runs.size() >= 3, "While it scuttles in a search, it sniffs (%d runs heard)" % runs.size())
	check(runs.all(func(run: Array) -> bool: return run.size() >= 2 and run.size() <= 4),
		"Each run is 2 to 4 sniffs (%s)" % [runs.map(func(run: Array) -> int: return run.size())])
	var steady := true
	var paced := true
	for run: Array in runs:
		var gaps: Array = []
		for index in range(1, run.size()):
			gaps.append(run[index] - run[index - 1])
		paced = paced and gaps.all(func(gap: float) -> bool: return gap > settings.sniff_run_pace.x - 0.06 and gap < settings.sniff_run_pace.y + 0.06)
		steady = steady and (gaps.is_empty() or gaps.max() - gaps.min() < 0.06)
	check(paced and steady, "Inside a run the sniffs come at one steady pace")
	# The wait for the next run started when this one did, and only counts down once the run is
	# over: after the time listened here, at least this much of the shortest wait is left.
	var listened: float = settings.sniff_run_count.y * settings.sniff_run_pace.y + 0.5
	check((audio._sniff_run_wait >= settings.sniff_run_interval.x - listened - 0.1 and audio._sniff_run_wait <= settings.sniff_run_interval.y)
		or audio._sniffs_left > 0, "And the next run waits its turn")
	# Standing down ends the sniffing and brings the idle talk back later.
	sniffs.clear()
	entity._change_state(entity.State.PATROL)
	await frames(2)
	check(audio._sniff_run_wait < 0.0 and audio._sniffs_left == 0 and awareness.has(&"stand_down"), "Giving up ends the sniffing")
	check(audio._talk_wait >= settings.talk_after_stand_down.x - 0.2 and audio._talk_wait <= settings.talk_after_stand_down.y + 0.1,
		"Its idle talking comes back a few seconds after the breath out")
