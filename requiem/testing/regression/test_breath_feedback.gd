extends Node2D
## Real-input presentation checks plus a compact exhaustive upper-pose sweep.
## Gameplay parity is checked with presentation enabled and disabled.

const RigLayers := preload("res://player/character_rig_layers.gd")
const GRIP_LENS := Vector2(16, 34)
const DIRECTIONS := [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

var checks := 0
var completed_scenarios := 0
var failures: Array[String] = []
var noises: Array[Dictionary] = []
var player: CharacterBody2D
var breath: Node
var feedback: Node
var appearance: Node2D
var aim: Node
var action: Node
var flashlight: PointLight2D
var motion: Node
var _watch_boots := false
var _held_boots: Dictionary = {}
var _boot_drift := 0.0
var _lens_error := 0.0
var _wrist_bend := 0.0
var _pose_samples := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame
		if _watch_boots:
			observe_alignment()
			observe_fixed_boots()


func release_inputs() -> void:
	for input_action in ["hold_breath", "move_right", "sprint", "throw", "pray"]:
		Input.action_release(input_action)


func reset_scenario() -> void:
	_watch_boots = false
	release_inputs()
	GameState.reset()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.velocity = Vector2.ZERO
	player.is_sprinting = false
	breath.cancel_holding()
	breath.is_locked = false
	breath._lock_timer = 0.0
	breath.reset_input_latch()
	breath.lung_percent = 100.0
	breath.exertion_percent = 0.0
	feedback.enabled = true
	feedback.reset_feedback()
	action.has_flashlight = true
	flashlight.is_on = true
	flashlight.battery_percent = 100.0
	motion.reset_pose()
	aim.reset_pose()
	aim.set_target(player.global_position + Vector2.DOWN * 2048.0)
	noises.clear()
	await frames(3)


func world_boots() -> Dictionary:
	var lower: Dictionary = appearance.get_actor_lower_pose()
	var result := {}
	for side in ["left", "right"]:
		result[side] = appearance.to_global(appearance.get_actor_leg_transform(side) * lower.pose.metadata[side].boot)
	return result


func watch_fixed_boots() -> void:
	_held_boots = world_boots()
	_watch_boots = true


func observe_fixed_boots() -> void:
	var actual := world_boots()
	for side in ["left", "right"]:
		_boot_drift = maxf(_boot_drift, actual[side].distance_to(_held_boots[side]))


func observe_alignment() -> void:
	_pose_samples += 1
	if not action.has_flashlight:
		return
	var grip: Transform2D = appearance.get_actor_grip_transform()
	var painted_lens: Vector2 = appearance.to_global(grip * GRIP_LENS)
	_lens_error = maxf(_lens_error, painted_lens.distance_to(aim.get_beam_global_position()))
	var grip_heading: float = (appearance.global_transform * grip).basis_xform(Vector2.DOWN).angle()
	var forearm_heading: float = appearance.global_rotation + appearance._rig_rotation + appearance._rig_pose.flashlight_angle
	_wrist_bend = maxf(_wrist_bend, absf(rad_to_deg(angle_difference(forearm_heading, grip_heading))))


func _ready() -> void:
	GameState.reset()
	release_inputs()
	player = preload("res://player/player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	breath = player.get_node("HoldBreath")
	feedback = player.get_node("BreathFeedback")
	appearance = player.get_node("Appearance")
	aim = player.get_node("PlayerAim")
	action = player.get_node("ActionState")
	flashlight = player.get_node("flashlight")
	motion = player.get_node("PlayerMotion")
	for clips in [breath.hold_clips, breath.exhale_clips, breath.gasp_clips,
		breath.forced_gasp_clips, breath.exertion_clips, flashlight.click_clips,
		player.get_node("FootstepNoise").walk_clips, player.get_node("FootstepNoise").sprint_clips]:
		clips.clear()
	NoiseManager.noise_emitted.connect(func(_at: Vector2, radius: float, source: int, _duration: float):
		noises.append({"radius": radius, "source": source}))
	await check_hold_and_release()
	await check_forced_feedback()
	await check_exertion_warning()
	await check_interruptions_and_pause()
	await check_mechanic_parity()
	await check_all_breath_shapes()
	check(completed_scenarios == 6, "Every breath feedback scenario reaches its final assertions")
	check(_boot_drift < 0.001, "Holding, gasping and upper-body breath poses leave planted boots fixed (%.5f px)" % _boot_drift)
	check(_lens_error <= 0.51, "Every equipped breath pose keeps the beam within half a pixel of its painted lens (%.5f px)" % _lens_error)
	check(_wrist_bend <= 15.01, "Breath overlays retain the straight-arm wrist limit (%.5f degrees)" % _wrist_bend)
	release_inputs()
	GameState.reset()
	player.queue_free()
	await frames(3)
	print("[Breath feedback tests] %d/%d passed; %d pose samples" % [checks - failures.size(), checks, _pose_samples])
	get_tree().quit(0 if failures.is_empty() else 1)


func check_hold_and_release() -> void:
	await reset_scenario()
	watch_fixed_boots()
	Input.action_press("hold_breath")
	await frames(2)
	check(feedback.phase == &"inhale" and feedback.cue == &"inhale" and feedback.cue_age < 0.1,
		"Accepted Space input immediately starts the inhale pose and inward visual cue")
	check(appearance._breath_track == &"inhale" and appearance._rig_pose.upper_texture == RigLayers.BREATH_ATLAS,
		"The real player renders the authored inhale upper-body sheet")
	await frames(18)
	check(feedback.phase == &"hold" and feedback.hold_focus > 0.95 and breath.is_holding,
		"Inhale settles into a sustained hold with responsive focus feedback")
	check(noises.is_empty() and breath.lung_percent < 96.0 and breath.exertion_percent > 1.0,
		"Hold feedback adds no hearing event and actual resources continue changing")
	breath.lung_percent = 30.0
	await frames(12)
	check(feedback.phase == &"strain" and feedback.strain > 0.2 and feedback.lung_pressure > 0.2,
		"Low actual air drives tension and the strain pose")
	check(feedback._vfx._edge.material.get_shader_parameter("strength") > 0.0
		and feedback._vfx._edge.material.get_shader_parameter("strength") <= 0.17,
		"Low-air edge shading is present and remains within the restrained opacity cap")
	Input.action_release("hold_breath")
	await frames(2)
	check(feedback.phase == &"release" and feedback.cue == &"release" and not breath.is_holding,
		"A safe voluntary release starts the controlled exhale and release cue")
	check(noises.size() == 1 and is_equal_approx(noises[0].radius, Units.to_px(1.0)),
		"Controlled exhale preserves its single 1-unit gameplay noise")
	await frames(32)
	check(feedback.phase == &"idle" and feedback.hold_focus < 0.1,
		"The controlled release settles back to idle without replaying its cue")
	await reset_scenario()
	breath.lung_percent = 18.0
	Input.action_press("hold_breath")
	await frames(2)
	Input.action_release("hold_breath")
	await frames(2)
	check(feedback.phase == &"release_loud" and feedback.cue == &"release_loud" and not breath.is_locked,
		"A low-air voluntary release has a distinct loud reaction without a forced lock")
	check(noises.size() == 1 and is_equal_approx(noises[0].radius, Units.to_px(5.0)),
		"The loud release retains exactly one 5-unit gameplay noise")
	completed_scenarios += 1


func check_forced_feedback() -> void:
	await reset_scenario()
	watch_fixed_boots()
	breath.lung_percent = 0.1
	Input.action_press("hold_breath")
	await frames(2)
	check(feedback.phase == &"gasp" and feedback.cue == &"gasp" and breath.is_locked
		and not breath.is_holding and breath.needs_release,
		"Air exhaustion produces a real forced-gasp pose, cue and input latch")
	check(noises.size() == 1 and is_equal_approx(noises[0].radius, Units.to_px(7.0)),
		"The forced visual response emits only the existing 7-unit gameplay noise")
	await frames(20)
	check(feedback.phase == &"recovery" and feedback.recovery_fraction > 0.1
		and feedback.get_meter_caption() == "RECOVERING", "The initial gasp transitions into visible locked recovery")
	var remaining: float = breath.get_recovery_remaining()
	var recovery_phase: float = feedback.pose_phase
	get_tree().paused = true
	await frames(8)
	check(is_equal_approx(remaining, breath.get_recovery_remaining()) and is_equal_approx(recovery_phase, feedback.pose_phase),
		"Pause freezes recovery animation and the actual movement lock together")
	get_tree().paused = false
	await frames(70)
	check(breath.is_locked and feedback.phase == &"recovery", "The breath overlay respects the full existing two-second lock")
	await frames(40)
	check(not breath.is_locked and feedback.phase == &"idle" and breath.needs_release
		and feedback.get_meter_caption() == "RELEASE SPACE" and feedback.hold_focus < 0.01,
		"Space held through recovery cannot falsely restart a hold or its reward")
	check(noises.size() == 1 and breath.lung_percent > 1.0,
		"Recovery refills air without a repeated gasp or extra visual hearing event")
	Input.action_release("hold_breath")
	await frames(10)
	Input.action_press("hold_breath")
	await frames(2)
	check(feedback.phase == &"inhale" and breath.is_holding and feedback.cue == &"inhale",
		"Releasing then pressing again gives the new accepted hold its own inhale feedback")
	completed_scenarios += 1


func check_exertion_warning() -> void:
	await reset_scenario()
	breath.exertion_percent = 92.0
	Input.action_press("hold_breath")
	await frames(20)
	check(breath.lung_percent > 90.0 and feedback.lung_pressure == 0.0
		and feedback.exertion_pressure > 0.8 and feedback.strain > 0.75 and feedback.phase == &"strain",
		"High exertion creates visible strain even with plenty of air remaining")
	breath.exertion_percent = 99.99
	await frames(2)
	check(feedback.phase == &"gasp" and breath.is_locked and breath.lung_percent > 90.0,
		"Exertion exhaustion receives the same forced recovery feedback without pretending air is empty")
	check(noises.size() == 1 and is_equal_approx(noises[0].radius, Units.to_px(7.0)),
		"The exertion reaction preserves its one existing forced-noise event")
	completed_scenarios += 1


func check_interruptions_and_pause() -> void:
	await reset_scenario()
	Input.action_press("hold_breath")
	await frames(15)
	var before := [feedback.phase, feedback.pose_phase, feedback.hold_focus, feedback.cue_age, breath.lung_percent]
	get_tree().paused = true
	await frames(8)
	check(before == [feedback.phase, feedback.pose_phase, feedback.hold_focus, feedback.cue_age, breath.lung_percent],
		"Pause freezes held animation, effect progress and lung resources")
	get_tree().paused = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(3)
	check(feedback.phase == &"idle" and feedback.cue == &"" and feedback.hold_focus == 0.0
		and appearance._breath_track == &"idle" and not feedback._vfx.visible,
		"Dialogue disabling clears breath feedback and hides the visual overlay")
	check(noises.is_empty(), "An interrupted hold never gives an exhale reward or gameplay noise")
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	await frames(3)
	check(feedback.phase == &"inhale" and breath.is_holding,
		"Restored input starts a new real hold rather than replaying an exhale")
	GameState.is_dead = true
	await frames(3)
	check(feedback.phase == &"idle" and feedback.cue == &"" and not feedback._vfx.visible
		and noises.is_empty(), "Death clears breath visuals without adding a reward or phantom exhale")
	await reset_scenario()
	breath.lung_percent = 0.1
	Input.action_press("hold_breath")
	await frames(49)
	check(feedback.phase == &"recovery", "The interruption fixture reaches the middle of real forced recovery")
	var recovery_remaining: float = breath.get_recovery_remaining()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(3)
	check(feedback.phase == &"idle" and feedback.cue == &""
		and is_equal_approx(recovery_remaining, breath.get_recovery_remaining()),
		"Dialogue hides an in-progress recovery without spending its remaining mechanic lock")
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	await frames(2)
	check(feedback.phase == &"recovery" and feedback.cue == &"" and feedback.recovery_fraction > 0.3,
		"Resuming a partially completed lock restores recovery rather than replaying the initial gasp")
	check(noises.size() == 1, "Resuming interrupted recovery adds no repeated forced hearing event")
	completed_scenarios += 1


func compare_mechanics(presentation_enabled: bool) -> Dictionary:
	release_inputs()
	breath.cancel_holding()
	breath.is_locked = false
	breath._lock_timer = 0.0
	breath.reset_input_latch()
	breath.lung_percent = 100.0
	breath.exertion_percent = 10.0
	feedback.reset_feedback()
	feedback.enabled = presentation_enabled
	noises.clear()
	Input.action_press("hold_breath")
	for index in range(90):
		breath._physics_process(1.0 / 60.0)
		feedback._physics_process(1.0 / 60.0)
	Input.action_release("hold_breath")
	for index in range(30):
		breath._physics_process(1.0 / 60.0)
		feedback._physics_process(1.0 / 60.0)
	return {"lung": breath.lung_percent, "exertion": breath.exertion_percent,
		"locked": breath.is_locked, "noises": noises.duplicate(true)}


func check_mechanic_parity() -> void:
	await reset_scenario()
	# Explicit equal physics steps avoid wall-clock variability in this comparison.
	breath.set_physics_process(false)
	feedback.set_physics_process(false)
	var active := compare_mechanics(true)
	var disabled := compare_mechanics(false)
	check(active == disabled, "Enabling the full visual feedback does not change resource totals, hearing events or recovery locks")
	check(is_equal_approx(active.lung, 75.0) and is_equal_approx(active.exertion, 17.0)
		and active.noises.size() == 1 and is_equal_approx(active.noises[0].radius, Units.to_px(1.0)),
		"Presentation parity also matches the established drain, refill and exertion rates")
	breath.set_physics_process(true)
	feedback.set_physics_process(true)
	feedback.enabled = true
	completed_scenarios += 1


func check_all_breath_shapes() -> void:
	await reset_scenario()
	var variants := {}
	var expected_samples := 0
	for equipment in range(3):
		action.has_flashlight = equipment > 0
		flashlight.is_on = equipment == 2
		flashlight._refresh_light()
		for heading in range(8):
			appearance.actor_facing = DIRECTIONS[heading]
			aim.reset_pose()
			var angle := heading * PI / 4.0
			var arm_step := heading % 5 - 2 if equipment > 0 else 0
			aim._arm_step = arm_step
			aim.aim_angle = angle + arm_step * PI / 8.0 + (deg_to_rad(15.0) if equipment > 0 else 0.0)
			_held_boots = world_boots()
			for track in RigLayers.BREATH_ANCHORS.TRACKS:
				var count: int = RigLayers.BREATH_ANCHORS.TRACKS[track].count
				for frame in range(count):
					appearance.set_breath_pose(StringName(track), frame / float(maxi(count - 1, 1)))
					aim._apply_pose()
					observe_alignment()
					observe_fixed_boots()
					variants["%d:%d:%s" % [equipment, heading, track]] = true
					expected_samples += 1
		check(appearance.actor_equipped == (equipment > 0) and flashlight.is_on == (equipment == 2),
			"Breath poses retain equipment ownership and torch power state %d" % equipment)
	check(variants.size() == 3 * 8 * 7 and expected_samples == 3 * 8 * RigLayers.BREATH_ANCHORS.FRAMES_PER_MODE,
		"All seven authored tracks cover eight headings with absent, unlit and lit flashlight variants")
	check(appearance._rig_pose.upper_texture == RigLayers.BREATH_ATLAS,
		"Every sampled action ends on the dedicated breath atlas rather than an idle substitute")
	completed_scenarios += 1
