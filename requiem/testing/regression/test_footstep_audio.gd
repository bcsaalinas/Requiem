extends Node2D

var checks := 0
var failures := 0
var player: CharacterBody2D
var audio: Node
var motion: Node
var appearance: Node
var breath: Node
var footsteps: Node
var aim: Node
var events: Array[Dictionary] = []
var noises: Array[Dictionary] = []
var previous_contacts := {"left": true, "right": true}
var expected_plants := 0
var observing := false
var mismatches := 0
var frame_number := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame


func release_inputs() -> void:
	for action in ["move_right", "move_left", "move_up", "move_down", "sprint", "hold_breath"]:
		Input.action_release(action)


func reset_case() -> void:
	observing = false
	release_inputs()
	get_tree().paused = false
	GameState.reset()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	breath.cancel_holding()
	breath.is_locked = false
	breath._lock_timer = 0.0
	breath.exertion_percent = 0.0
	breath.lung_percent = 100.0
	breath.reset_input_latch()
	footsteps.footstep_timer = 0.0
	motion.reset_pose()
	aim.reset_pose()
	aim.set_target(Vector2(2000, 0))
	audio.enabled = true
	audio.reset_audio()
	await frames(3)
	events.clear()
	noises.clear()
	previous_contacts = appearance.get_actor_lower_pose().contacts.duplicate()
	expected_plants = 0
	mismatches = 0


func on_step(side: String, at: Vector2, mode: String, clip: AudioStream, pitch: float, gain: float) -> void:
	var lower: Dictionary = appearance.get_actor_lower_pose()
	if not bool(lower.contacts.get(side, false)) or bool(previous_contacts.get(side, false)) \
			or at.distance_to(Vector2(lower.boots[side])) > 0.001:
		mismatches += 1
	events.append({"frame": Engine.get_physics_frames(), "side": side, "at": at,
		"mode": mode, "clip": clip, "pitch": pitch, "gain": gain})


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(appearance): return
	var contacts: Dictionary = appearance.get_actor_lower_pose().get("contacts", {})
	if observing and motion.mode != "Idle":
		for side in ["left", "right"]:
			if bool(contacts.get(side, false)) and not bool(previous_contacts.get(side, false)):
				expected_plants += 1
	previous_contacts = contacts.duplicate()
	frame_number += 1


func _ready() -> void:
	process_physics_priority = 40
	GameState.reset()
	player = preload("res://player/player.tscn").instantiate()
	add_child(player)
	player.get_node("Camera2D").enabled = false
	audio = player.get_node("FootstepAudio")
	appearance = player.get_node("Appearance")
	motion = player.get_node("PlayerMotion")
	breath = player.get_node("HoldBreath")
	footsteps = player.get_node("FootstepNoise")
	aim = player.get_node("PlayerAim")
	breath.hold_clips.clear()
	breath.exertion_clips.clear()
	audio.step_played.connect(on_step)
	NoiseManager.noise_emitted.connect(func(at: Vector2, radius: float, source: int, _duration: float):
		noises.append({"at": at, "radius": radius, "source": source}))
	check(footsteps.walk_clips.size() == 8, "Production player has eight one-shots")
	for clip in footsteps.walk_clips:
		check(clip is AudioStreamWAV and clip.get_length() > 0.2 and clip.get_length() <= 0.27,
			"Each imported clip is a short WAV impact")
		check(clip.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Footstep clips never loop")
	check(audio.process_physics_priority > aim.process_physics_priority, "Audio consumes current resolved contacts")
	check(audio._voices.size() == 3, "Audio has a bounded three-voice pool")
	await exercise_mode("Walk", false, false, 180, 0.45, -6.0, 3.0)
	await exercise_mode("Sprint", true, false, 180, 0.30, -3.5, 6.0)
	await exercise_mode("Held breath", true, true, 210, 0.70, -14.0, 1.0)
	await reset_case()
	observing = true
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(60)
	Input.action_release("move_right")
	Input.action_press("move_left")
	Input.action_press("move_up")
	for index in range(90):
		aim.set_target(player.position + Vector2.from_angle(index * TAU / 90.0) * 1000)
		await frames(1)
	check(mismatches == 0 and events.size() == expected_plants, "Reversals and all aim angles neither miss nor duplicate contacts")
	release_inputs()
	await frames(35)
	var count: int = audio.played_steps
	for index in range(30):
		aim.set_target(player.position + Vector2.from_angle(index * 0.3) * 1000)
		await frames(1)
	check(audio.played_steps == count, "Stationary pivots and settling do not make steps")
	check(not any_voice_playing(), "Short tails finish after stopping")
	await lifecycle_checks()
	var audible := await parity_run(true)
	var muted := await parity_run(false)
	check(audible.noises == muted.noises, "Audio enable/disable preserves exact hearing events and positions")
	check(audible.position.is_equal_approx(muted.position) and is_equal_approx(audible.exertion, muted.exertion),
		"Audio preserves movement and exertion")
	check(audible.steps > 4 and muted.steps == 0, "Mute affects only presentation")
	# Private sample selection must not consume the gameplay RNG sequence.
	seed(7721)
	var expected_random := randi()
	seed(7721)
	audio._play_step("left", player.position, "Walk")
	check(randi() == expected_random, "Sound variation does not consume global RNG")
	release_inputs()
	GameState.reset()
	player.queue_free()
	await frames(4)
	print("[Footstep audio tests] %d/%d passed" % [checks - failures, checks])
	get_tree().quit(1 if failures else 0)


func exercise_mode(mode: String, sprint: bool, held: bool, ticks: int, cadence: float, gain: float, radius: float) -> void:
	await reset_case()
	observing = true
	Input.action_press("move_right")
	if sprint: Input.action_press("sprint")
	if held: Input.action_press("hold_breath")
	await frames(ticks)
	check(events.size() >= 3, mode + " emits multiple real steps")
	check(events.size() == expected_plants and mismatches == 0, mode + " has exactly one same-frame sound per visible plant")
	var mode_events: Array = events.filter(func(e): return e.mode == mode)
	check(mode_events.size() >= 3, mode + " selects the correct mix")
	var cadence_ok := true
	for index in range(2, mode_events.size()):
		var gap: float = (mode_events[index].frame - mode_events[index - 1].frame) / 60.0
		cadence_ok = cadence_ok and absf(gap - cadence) < 0.07
	check(cadence_ok, mode + " cadence follows its gait")
	var variation_ok := true
	for index in range(events.size()):
		var e: Dictionary = events[index]
		variation_ok = variation_ok and e.pitch >= 0.965 and e.pitch <= 1.035
		if index > 0: variation_ok = variation_ok and e.clip != events[index-1].clip
		if e.mode == mode: variation_ok = variation_ok and absf(e.gain - gain) <= 0.701
	check(variation_ok, mode + " varies gently without immediate sample repeats")
	var matching_noises: Array = noises.filter(func(n): return is_equal_approx(n.radius, Units.to_px(radius)))
	check(matching_noises.size() >= 3, mode + " retains existing hearing radius")
	var voice: AudioStreamPlayer2D = audio._voices[(audio._voice_index + 2) % 3]
	var plant_position := voice.global_position
	player.position += Vector2(1, 0)
	check(voice.global_position.is_equal_approx(plant_position), "Released sound stays at the plant in world space")


func any_voice_playing() -> bool:
	for voice in audio._voices:
		if voice.playing: return true
	return false


func lifecycle_checks() -> void:
	await reset_case()
	Input.action_press("move_right")
	Input.action_press("sprint")
	await frames(50)
	var before: int = audio.played_steps
	get_tree().paused = true
	await frames(10)
	check(audio.played_steps == before, "Pause freezes sound triggers")
	get_tree().paused = false
	await frames(20)
	check(audio.played_steps > before, "Unpause resumes normal plants")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(2)
	check(not any_voice_playing(), "Disabled player clears sound tails")
	await reset_case()
	Input.action_press("move_right")
	await frames(50)
	GameState.is_praying = true
	await frames(2)
	check(not any_voice_playing(), "Prayer cancels footstep tails")
	GameState.is_praying = false
	breath.is_locked = true
	await frames(2)
	check(not any_voice_playing(), "Forced recovery cannot play footsteps")
	await reset_case()
	audio._play_step("left", player.position, "Walk")
	GameState.player_died.emit()
	check(not any_voice_playing(), "Death clears tails synchronously")
	audio._play_step("left", player.position, "Walk")
	GameState.reset()
	check(not any_voice_playing(), "Reset clears tails synchronously")
	before = audio.played_steps
	player.position += Vector2(500, 0)
	await frames(1)
	check(audio.played_steps == before and not any_voice_playing(), "Teleport does not create a phantom step")
	# A real collision blocks displacement even while movement input is held.
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(16, 300)
	shape.shape = rectangle
	wall.add_child(shape)
	wall.position = player.position + Vector2(55, 0)
	add_child(wall)
	Input.action_press("move_right")
	Input.action_press("sprint")
	await frames(70)
	before = audio.played_steps
	await frames(45)
	check(audio.played_steps == before and not any_voice_playing(), "Pushing a real wall produces no footsteps")
	wall.queue_free()
	await frames(2)


func parity_run(with_audio: bool) -> Dictionary:
	await reset_case()
	audio.enabled = with_audio
	var start: int = audio.played_steps
	Input.action_press("move_right")
	Input.action_press("sprint")
	await frames(110)
	return {"noises": noises.duplicate(true), "position": player.position,
		"exertion": breath.exertion_percent, "steps": audio.played_steps - start}
