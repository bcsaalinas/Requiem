extends Node2D
## Exercise accepted altar rituals, their presentation, and shared rig attachment.
## The altar remains the only clock for costs, progress, hearing and completion.

const RigLayers := preload("res://player/character_rig_layers.gd")
const AltarScene := preload("res://altar/altar.tscn")
const GRIP_LENS := Vector2(16, 34)
const DIRECTIONS := [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

var checks := 0
var completed_scenarios := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var noises: Array[Dictionary] = []
var player: CharacterBody2D
var altar: Node
var altar_root: Node2D
var feedback: Node
var breath: Node
var breath_feedback: Node
var thrower: Node
var appearance: Node2D
var aim: Node
var action: Node
var flashlight: PointLight2D
var motion: Node
var _pose_samples := 0
var _minimum_boot_spacing := INF
var _minimum_lane_clearance := INF
var _minimum_rearward_distance := INF
var _maximum_leg_reach := 0.0
var _kneel_samples := 0
var _lens_error := 0.0
var _wrist_bend := 0.0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame


func exit_frames() -> int:
	return ceili(feedback.EXIT_SECONDS * Engine.physics_ticks_per_second) + 3


func lower_is_kneeling() -> bool:
	var lower: Dictionary = appearance.get_actor_lower_pose()
	return lower.get("kneeling", false) and lower.pose.left_texture == RigLayers.PRAYER_LEFT_ATLAS \
		and lower.pose.right_texture == RigLayers.PRAYER_RIGHT_ATLAS


func release_inputs() -> void:
	for input_action in ["move_left", "move_right", "move_up", "move_down", "sprint", "hold_breath", "throw", "pray"]:
		Input.action_release(input_action)


func create_altar(at := Vector2(0, -56)) -> Node2D:
	var root: Node2D = AltarScene.instantiate()
	root.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.position = at
	add_child(root)
	var body := root.get_node("BodyAltar")
	body.pray_clips.clear()
	body.set_process(false)
	return root


func reset_scenario() -> void:
	release_inputs()
	get_tree().paused = false
	GameState.reset()
	if is_instance_valid(altar_root):
		altar_root.queue_free()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.is_sprinting = false
	feedback.set_physics_process(true)
	feedback.enabled = true
	feedback.reset_feedback()
	thrower.clear_pending()
	thrower.available = true
	thrower.rocks = 3
	breath.cancel_holding()
	breath.is_locked = false
	breath._lock_timer = 0.0
	breath.reset_input_latch()
	breath.lung_percent = 100.0
	breath.exertion_percent = 0.0
	breath_feedback.reset_feedback()
	action.has_flashlight = true
	flashlight.is_on = true
	flashlight.battery_percent = 100.0
	appearance.actor_facing = &"s"
	motion.reset_pose()
	aim.reset_pose()
	aim.set_target(Vector2.DOWN * 2048.0)
	await frames(3)
	altar_root = create_altar()
	altar = altar_root.get_node("BodyAltar")
	await frames(3)
	altar._on_area_2d_body_entered(player)
	events.clear()
	noises.clear()


func start_manual(seconds := 0.1) -> void:
	Input.action_press("pray")
	altar._process(seconds)
	feedback._physics_process(0.0)
	aim._apply_pose()


func _ready() -> void:
	GameState.reset()
	release_inputs()
	GameState.prayer_started.connect(func(source: Node): events.append({"event": &"start", "source": source}))
	GameState.prayer_ended.connect(func(source: Node, immediate: bool):
		events.append({"event": &"end", "source": source, "immediate": immediate}))
	NoiseManager.noise_emitted.connect(func(at: Vector2, radius: float, source: int, _duration: float):
		if source == NoiseManager.SourceType.PRAY:
			noises.append({"at": at, "radius": radius, "source": source}))
	player = preload("res://player/player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	feedback = player.get_node("PrayerFeedback")
	breath = player.get_node("HoldBreath")
	breath_feedback = player.get_node("BreathFeedback")
	thrower = player.get_node("Throw")
	appearance = player.get_node("Appearance")
	aim = player.get_node("PlayerAim")
	action = player.get_node("ActionState")
	flashlight = player.get_node("flashlight")
	motion = player.get_node("PlayerMotion")
	for clips in [breath.hold_clips, breath.exhale_clips, breath.gasp_clips, breath.forced_gasp_clips,
		breath.exertion_clips, flashlight.click_clips, thrower.piedra_clips, thrower.despertador_clips,
		player.get_node("FootstepNoise").walk_clips, player.get_node("FootstepNoise").sprint_clips]:
		clips.clear()
	await check_live_entry_and_release()
	await check_partial_release_and_reentry()
	await check_pause_and_clock()
	await check_priority_and_breath()
	await check_unarmed_facing()
	await check_interruptions()
	await check_owner_and_eligibility()
	await check_mechanic_parity()
	await check_prayer_shapes()
	check(completed_scenarios == 9, "Every prayer integration scenario reaches its final assertions")
	check(_minimum_boot_spacing >= 9.05 and _minimum_lane_clearance > 0.0,
		"Kneeling feet keep separate anatomical lanes (%.3f px spacing; %.3f px lane clearance)" % [_minimum_boot_spacing, _minimum_lane_clearance])
	check(_minimum_rearward_distance > 2.0 and _kneel_samples > 0,
		"Every held kneel puts both boots visibly behind the hips (%.3f px minimum)" % _minimum_rearward_distance)
	check(_maximum_leg_reach <= 30.01,
		"Kneeling keeps each hip-to-ankle attachment inside the established leg envelope (%.3f px)" % _maximum_leg_reach)
	check(_lens_error <= 0.51, "Every equipped prayer pose keeps the beam at its painted lens (%.5f px)" % _lens_error)
	check(_wrist_bend <= 15.01, "Prayer retains the existing wrist limit (%.5f degrees)" % _wrist_bend)
	release_inputs()
	GameState.reset()
	if is_instance_valid(altar_root):
		altar_root.queue_free()
	player.queue_free()
	await frames(3)
	print("[Prayer feedback tests] %d/%d passed; %d pose samples" % [checks - failures.size(), checks, _pose_samples])
	get_tree().quit(0 if failures.is_empty() else 1)


func check_live_entry_and_release() -> void:
	await reset_scenario()
	altar.set_process(true)
	Input.action_press("pray")
	await frames(3)
	check(GameState.is_praying and GameState.prayer_source == altar and events.size() == 1,
		"Holding E inside the real altar accepts exactly one owned ritual")
	check(feedback.phase == &"entry" and appearance._rig_pose.upper_texture == RigLayers.PRAYER_ATLAS,
		"The accepted ritual starts the character's authored prayer entry")
	check(not action.can_move() and not action.can_aim() and not action.can_throw(),
		"Prayer retains the existing movement, cursor and throwing restrictions")
	Input.action_press("move_right")
	Input.action_press("sprint")
	var start := player.global_position
	await frames(42)
	check(feedback.phase == &"loop" and lower_is_kneeling() and player.global_position.distance_to(start) < 0.01 and not player.is_sprinting,
		"Sustained prayer reaches its full kneeling pose while real movement and sprint input stay rooted")
	check(absf(angle_difference(aim.body_angle, -PI / 2.0)) < deg_to_rad(3.0),
		"The player turns naturally toward the accepted altar rather than following the cursor behind it")
	Input.action_release("pray")
	await frames(2)
	check(not GameState.is_praying and GameState.prayer_source == null and action.can_move() and feedback.phase == &"exit"
		and lower_is_kneeling() and player.global_position.x > start.x,
		"Releasing E immediately returns movement while the kneeling legs begin their short authored rise")
	check(is_zero_approx(altar.get_prayer_elapsed()) and not altar.barra_progreso.visible and not altar._audio_player.playing,
		"Releasing prayer clears the actual progress, progress bar and ritual audio")
	await frames(exit_frames())
	check(feedback.phase == &"idle" and not lower_is_kneeling() and player.global_position.x > start.x + 10.0
		and appearance.get_actor_lower_pose() == appearance._lower_pose,
		"The short rise restores the independent walking legs without extending the movement lock")
	completed_scenarios += 1


func check_partial_release_and_reentry() -> void:
	await reset_scenario()
	feedback.set_physics_process(false)
	start_manual(0.12)
	check(feedback.phase == &"entry" and absf(feedback.pose_phase - 0.12 / feedback.ENTRY_SECONDS) < 0.001,
		"Entry uses the real ritual's elapsed time")
	var hand_before: Vector2 = appearance.get_actor_hand_position()
	var boots_before := {"left": appearance.get_actor_boot_position("left"), "right": appearance.get_actor_boot_position("right")}
	var entry_phase: float = feedback.pose_phase
	Input.action_release("pray")
	altar._process(0.0)
	feedback._physics_process(0.0)
	aim._apply_pose()
	check(feedback.phase == &"exit" and absf(feedback.pose_phase - (1.0 - entry_phase)) < 0.001
		and appearance.get_actor_hand_position().distance_to(hand_before) < 0.001
		and appearance.get_actor_boot_position("left").distance_to(boots_before.left) < 0.001
		and appearance.get_actor_boot_position("right").distance_to(boots_before.right) < 0.001,
		"An early release reverses the current kneel with no hand or foot jump")
	feedback._physics_process(0.04)
	aim._apply_pose()
	var exit_phase: float = feedback.pose_phase
	hand_before = appearance.get_actor_hand_position()
	boots_before = {"left": appearance.get_actor_boot_position("left"), "right": appearance.get_actor_boot_position("right")}
	Input.action_press("pray")
	altar._process(0.0)
	feedback._physics_process(0.0)
	aim._apply_pose()
	check(feedback.phase == &"entry" and absf(feedback.pose_phase - (1.0 - exit_phase)) < 0.001
		and appearance.get_actor_hand_position().distance_to(hand_before) < 0.001
		and appearance.get_actor_boot_position("left").distance_to(boots_before.left) < 0.001
		and appearance.get_actor_boot_position("right").distance_to(boots_before.right) < 0.001,
		"Re-pressing E during the rise resumes from the same hands and kneeling feet")
	check(is_zero_approx(altar.get_prayer_elapsed()) and events.size() == 3 and noises.size() == 2,
		"A restarted bow begins a fresh ritual and exactly one new start noise without retaining ritual progress")
	altar._process(feedback.ENTRY_SECONDS + 0.02)
	feedback._physics_process(0.0)
	check(feedback.phase == &"loop" and altar.get_prayer_elapsed() < feedback.ENTRY_SECONDS + 0.03,
		"Re-entry reaches the sustained pose without fast-forwarding altar progress")
	completed_scenarios += 1


func check_pause_and_clock() -> void:
	await reset_scenario()
	altar.set_process(true)
	Input.action_press("pray")
	await frames(ceili(feedback.ENTRY_SECONDS * Engine.physics_ticks_per_second) + 4)
	get_tree().paused = true
	var elapsed: float = altar.get_prayer_elapsed()
	var visual: float = feedback.pose_phase
	var event_count := noises.size()
	await frames(12)
	check(is_equal_approx(altar.get_prayer_elapsed(), elapsed) and is_equal_approx(feedback.pose_phase, visual)
		and noises.size() == event_count,
		"Tree pause freezes altar progress, its animation phase and every prayer hearing event together")
	get_tree().paused = false
	await frames(4)
	check(altar.get_prayer_elapsed() > elapsed and feedback.phase == &"loop",
		"Unpausing resumes the same accepted ritual without replaying the entry")
	altar.set_process(false)
	elapsed = altar.get_prayer_elapsed()
	feedback._physics_process(0.7)
	check(is_equal_approx(altar.get_prayer_elapsed(), elapsed)
		and absf(feedback.pose_phase - fposmod(elapsed - feedback.ENTRY_SECONDS, feedback.LOOP_SECONDS) / feedback.LOOP_SECONDS) < 0.001,
		"Extra presentation updates cannot advance or desynchronize the authoritative ritual clock")
	completed_scenarios += 1


func check_priority_and_breath() -> void:
	await reset_scenario()
	thrower._start_throw()
	start_manual(feedback.ENTRY_SECONDS + 0.08)
	await frames(2)
	check(not thrower.is_throwing and player.get_node("ThrowFeedback").phase == &"idle"
		and appearance._rig_pose.upper_texture == RigLayers.PRAYER_ATLAS,
		"Accepted prayer interrupts an unfinished throw and owns the upper-body pose")
	Input.action_press("hold_breath")
	var lung_before: float = breath.lung_percent
	await frames(4)
	check(breath.is_holding and breath.lung_percent < lung_before and feedback.phase == &"loop"
		and appearance._rig_pose.upper_texture == RigLayers.PRAYER_ATLAS,
		"Holding breath during prayer retains its real resource costs underneath the prayer pose")
	breath.lung_percent = 0.01
	await frames(2)
	check(breath.is_locked and action.get_action() == &"forced_gasp" and GameState.is_praying
		and appearance._rig_pose.upper_texture == RigLayers.BREATH_ATLAS and lower_is_kneeling()
		and feedback.phase == &"loop" and appearance._prayer_track == &"idle",
		"Forced gasp takes upper-body priority while the continuing ritual keeps both legs kneeling")
	var before: float = altar.get_prayer_elapsed()
	altar._process(2.1)
	check(altar.get_prayer_elapsed() > before + 2.0,
		"Gasp presentation never freezes or rewinds the underlying prayer timer")
	Input.action_release("hold_breath")
	breath._lock_timer = 0.001
	await frames(3)
	check(not breath.is_locked and feedback.phase == &"loop" and appearance._rig_pose.upper_texture == RigLayers.PRAYER_ATLAS,
		"Finishing the gasp returns to the current ritual loop without replaying prayer entry")
	Input.action_press("hold_breath")
	breath.lung_percent = 0.01
	await frames(2)
	Input.action_release("pray")
	altar._process(0.0)
	feedback._physics_process(0.0)
	aim._apply_pose()
	check(breath.is_locked and feedback.phase == &"exit" and lower_is_kneeling()
		and appearance._rig_pose.upper_texture == RigLayers.BREATH_ATLAS and not GameState.is_praying,
		"Releasing E during a gasp raises the kneeling legs without interrupting the gasp's upper-body recovery")
	await frames(exit_frames())
	check(breath.is_locked and feedback.phase == &"idle" and not lower_is_kneeling()
		and appearance._rig_pose.upper_texture == RigLayers.BREATH_ATLAS,
		"The completed rise restores standing legs while the remaining gasp lock keeps its own timing")
	completed_scenarios += 1


func check_unarmed_facing() -> void:
	await reset_scenario()
	action.has_flashlight = false
	start_manual(feedback.ENTRY_SECONDS + 0.08)
	await frames(55)
	check(absf(angle_difference(aim.body_angle, -PI / 2.0)) < deg_to_rad(3.0) and not appearance.actor_equipped,
		"Before flashlight pickup, prayer still turns the character toward its real altar")
	Input.action_release("pray")
	altar._process(0.0)
	await frames(exit_frames())
	check(feedback.phase == &"idle" and absf(angle_difference(aim.body_angle, -PI / 2.0)) < deg_to_rad(3.0),
		"Finishing an unarmed prayer keeps the new resting direction without snapping backward")
	var before: float = aim.body_angle
	Input.action_press("move_right")
	await frames(1)
	check(absf(angle_difference(before, aim.body_angle))
		<= deg_to_rad(aim.body_turn_speed_degrees) / float(Engine.physics_ticks_per_second) + 0.002,
		"Resuming travel after unarmed prayer gathers toward movement at the existing body turn rate")
	await frames(50)
	check(absf(angle_difference(aim.body_angle, 0.0)) < deg_to_rad(3.0) and player.velocity.x > 95.0,
		"Unarmed prayer returns cleanly to ordinary movement-facing")
	completed_scenarios += 1


func check_interruptions() -> void:
	for blocker in [&"death", &"disabled", &"teleport", &"leaving", &"reset", &"reset_exit", &"death_exit", &"teleport_exit", &"source_deleted"]:
		await reset_scenario()
		start_manual(feedback.ENTRY_SECONDS + 0.08)
		match blocker:
			&"death": GameState.kill_player()
			&"disabled":
				player.process_mode = Node.PROCESS_MODE_DISABLED
				altar._process(0.0)
			&"teleport":
				player.global_position += Vector2.RIGHT * Units.to_px(4.0)
				altar._process(0.0)
			&"leaving": altar._on_area_2d_body_exited(player)
			&"reset": GameState.reset()
			&"reset_exit", &"death_exit", &"teleport_exit":
				Input.action_release("pray")
				altar._process(0.0)
				feedback._physics_process(0.05)
				check(feedback.phase == &"exit", "%s fixture reaches its unowned visual exit" % blocker)
				match blocker:
					&"reset_exit": GameState.reset()
					&"death_exit": GameState.kill_player()
					&"teleport_exit": player.global_position += Vector2.RIGHT * Units.to_px(4.0)
				if blocker != &"reset_exit":
					feedback._physics_process(0.0)
					check(feedback.phase == &"idle", "%s clears the exit on the next presentation update" % blocker)
			&"source_deleted": altar_root.queue_free()
		if blocker in [&"death", &"reset", &"reset_exit"]:
			check(feedback.phase == &"idle" and not GameState.is_praying and not lower_is_kneeling(),
				"%s clears prayer presentation and kneeling legs synchronously with the state transition" % blocker)
		Input.action_release("pray")
		await frames(exit_frames())
		check(not GameState.is_praying and GameState.prayer_source == null and feedback.phase == &"idle"
			and not lower_is_kneeling() and appearance._prayer_lower_track == &"idle",
			"%s clears prayer ownership and leaves no stale prayer upper body or kneeling legs" % blocker)
		if is_instance_valid(altar):
			check(is_zero_approx(altar.get_prayer_elapsed()) and not altar._estaba_rezando
				and not altar.barra_progreso.visible and not altar._audio_player.playing,
				"%s clears actual ritual progress, UI and sound" % blocker)
	completed_scenarios += 1


func check_owner_and_eligibility() -> void:
	await reset_scenario()
	altar._on_area_2d_body_exited(player)
	var visitor := CharacterBody2D.new()
	add_child(visitor)
	altar._on_area_2d_body_entered(visitor)
	start_manual(0.1)
	check(not GameState.is_praying and feedback.phase == &"idle" and noises.is_empty(),
		"An unrelated CharacterBody cannot become the player for prayer or produce a false animation")
	visitor.queue_free()
	altar._on_area_2d_body_entered(player)
	start_manual(0.1)
	var second_root := create_altar(Vector2(56, 0))
	var second := second_root.get_node("BodyAltar")
	second._on_area_2d_body_entered(player)
	second._process(0.25)
	check(GameState.prayer_source == altar and not second._estaba_rezando and is_zero_approx(second.get_prayer_elapsed())
		and events.size() == 1 and noises.size() == 1,
		"Overlapping altar areas cannot claim the same prayer, double its noise or advance two rituals")
	GameState.end_prayer(second)
	second.cancel_prayer()
	check(GameState.is_praying and GameState.prayer_source == altar,
		"A non-owning altar cannot cancel the accepted ritual")
	second_root.queue_free()
	await reset_scenario()
	GameState.is_praying = true
	var facing: float = aim.body_angle
	await frames(4)
	check(feedback.phase == &"idle" and is_equal_approx(aim.body_angle, facing)
		and appearance._rig_pose.upper_texture != RigLayers.PRAYER_ATLAS and not lower_is_kneeling(),
		"A legacy global prayer flag without a real source cannot fabricate prayer, kneeling legs or an aim target")
	GameState.reset()
	start_manual(feedback.ENTRY_SECONDS + 0.08)
	feedback.enabled = false
	feedback._physics_process(0.0)
	aim._apply_pose()
	check(GameState.is_praying and feedback.phase == &"idle" and not lower_is_kneeling()
		and appearance._rig_pose.upper_texture != RigLayers.PRAYER_ATLAS,
		"Disabling prayer presentation clears both authored layers while the real ritual keeps its ownership")
	completed_scenarios += 1


func mechanic_sample(presentation_enabled: bool) -> Dictionary:
	await reset_scenario()
	feedback.enabled = presentation_enabled
	feedback.set_physics_process(false)
	Input.action_press("pray")
	var pulse_checks := []
	for step in range(48):
		altar._process(0.25)
		feedback._physics_process(0.25)
		if step in [6, 7, 13]:
			pulse_checks.append({"elapsed": altar.get_prayer_elapsed(), "active": altar._pulse_restante > 0.0})
	return {"noises": noises.duplicate(true), "pulse_checks": pulse_checks,
		"finished": altar.is_queued_for_deletion(), "praying": GameState.is_praying,
		"event_count": events.size(), "bar_visible": altar.barra_progreso.visible}


func check_mechanic_parity() -> void:
	var active := await mechanic_sample(true)
	var disabled := await mechanic_sample(false)
	check(active == disabled, "Enabling prayer animation preserves completion, every hearing event and the altar pulse timeline")
	check(active.finished and not active.praying and active.event_count == 2 and not active.bar_visible,
		"The original twelve-second ritual completes once, releases ownership and removes the actual altar")
	check(active.noises.size() == 26 and active.noises[0].radius == Units.to_px(6.0)
		and active.noises[4].radius == Units.to_px(8.0) and active.noises[-1].radius == Units.to_px(6.0),
		"Prayer retains six-unit start and half-second noise, its single eight-unit pulse and its original ending noise")
	check(not active.pulse_checks[0].active and active.pulse_checks[1].active and not active.pulse_checks[2].active,
		"The altar pulse begins at the existing two-second threshold and ends within its 1.5-second window")
	completed_scenarios += 1


func check_prayer_shapes() -> void:
	await reset_scenario()
	altar_root.queue_free()
	await frames(3)
	var track_coverage := {}
	for equipment in range(3):
		action.has_flashlight = equipment > 0
		flashlight.is_on = equipment == 2
		flashlight._refresh_light()
		for heading in range(8):
			appearance.actor_facing = DIRECTIONS[heading]
			aim.reset_pose()
			var lower: Dictionary = appearance._lower_pose.duplicate(true)
			for arm_step in (range(-2, 3) if equipment > 0 else [0]):
				aim._arm_step = arm_step
				aim.aim_angle = heading * PI / 4.0 + arm_step * PI / 8.0 + (deg_to_rad(15.0) if equipment > 0 else 0.0)
				for track in RigLayers.PRAYER_ANCHORS.TRACKS:
					var count: int = RigLayers.PRAYER_ANCHORS.TRACKS[track].count
					for frame in range(count):
						var fraction := frame / float(maxi(count - 1, 1))
						appearance.set_prayer_pose(StringName(track), fraction)
						appearance.set_prayer_lower_pose(StringName(track), fraction)
						aim._apply_pose()
						_pose_samples += 1
						observe_kneeling_legs(track)
						if equipment > 0:
							var grip: Transform2D = appearance.get_actor_grip_transform()
							_lens_error = maxf(_lens_error, appearance.to_global(grip * GRIP_LENS).distance_to(aim.get_beam_global_position()))
							var grip_heading: float = (appearance.global_transform * grip).basis_xform(Vector2.DOWN).angle()
							var forearm_heading: float = appearance.global_rotation + appearance._rig_rotation + appearance._rig_pose.flashlight_angle
							_wrist_bend = maxf(_wrist_bend, absf(rad_to_deg(angle_difference(forearm_heading, grip_heading))))
						track_coverage["%d:%d:%s" % [equipment, heading, track]] = true
			appearance.set_prayer_lower_pose(&"idle", 0.0)
			check(appearance._lower_pose == lower and appearance.get_actor_lower_pose() == lower,
				"Clearing prayer restores the untouched ordinary leg solver for equipment %d heading %d" % [equipment, heading])
		check(appearance.actor_equipped == (equipment > 0) and flashlight.is_on == (equipment == 2),
			"Prayer retains absent, unlit and lit flashlight ownership state %d" % equipment)
	check(track_coverage.size() == 3 * 8 * 3 and _pose_samples == 8 * 11 * RigLayers.PRAYER_ANCHORS.FRAMES_PER_MODE,
		"Every authored entry, loop and exit frame covers all eight headings and all available equipment/aim modes")
	check(appearance._rig_pose.upper_texture == RigLayers.PRAYER_ATLAS,
		"The exhaustive pose sweep renders the authored prayer atlas")
	check_lower_track_seams()
	completed_scenarios += 1


func observe_kneeling_legs(track: String) -> void:
	var lower: Dictionary = appearance.get_actor_lower_pose()
	var left: Vector2 = appearance.get_actor_boot_position("left")
	var right: Vector2 = appearance.get_actor_boot_position("right")
	_minimum_boot_spacing = minf(_minimum_boot_spacing, left.distance_to(right))
	for side in ["left", "right"]:
		var leg: Dictionary = lower.pose.metadata[side]
		var transform_at_leg: Transform2D = appearance.get_actor_leg_transform(side)
		var hip: Vector2 = transform_at_leg * Vector2(leg.hip)
		var ankle: Vector2 = transform_at_leg * Vector2(leg.ankle)
		var boot: Vector2 = appearance.get_actor_boot_position(side)
		var body_boot: Vector2 = (boot - appearance.actor_ground_offset).rotated(-appearance._rig_rotation)
		_minimum_lane_clearance = minf(_minimum_lane_clearance, body_boot.x * (1.0 if side == "left" else -1.0))
		_maximum_leg_reach = maxf(_maximum_leg_reach, hip.distance_to(ankle))
		if track == "loop":
			var behind: Vector2 = (hip - boot).rotated(-appearance._rig_rotation)
			_minimum_rearward_distance = minf(_minimum_rearward_distance, behind.y)
			_kneel_samples += 1


func check_lower_track_seams() -> void:
	var layers := RigLayers.new()
	var standing: Dictionary = layers.get_lower_pose("idle", 0, "s")
	for track in ["entry", "exit"]:
		var endpoint: Dictionary = layers.get_prayer_lower_pose(track, 0.0 if track == "entry" else 1.0)
		check(is_zero_approx(endpoint.metadata.kneel_weight)
			and endpoint.metadata.left == standing.metadata.left and endpoint.metadata.right == standing.metadata.right,
			"Prayer %s standing endpoint preserves the original planted leg geometry" % track)
	var count: int = RigLayers.PRAYER_ANCHORS.TRACKS.entry.count
	var exact_reverse := true
	for frame in range(count):
		var fraction := frame / float(maxi(count - 1, 1))
		var entry: Dictionary = layers.get_prayer_lower_pose("entry", fraction)
		var exit: Dictionary = layers.get_prayer_lower_pose("exit", 1.0 - fraction)
		exact_reverse = exact_reverse and entry.metadata.left == exit.metadata.left and entry.metadata.right == exit.metadata.right
	check(exact_reverse, "Every kneeling entry frame reverses into the exact same leg pose on an interrupted exit")
	var held: Dictionary = layers.get_prayer_lower_pose("entry", 1.0)
	var stable_loop := true
	for frame in range(RigLayers.PRAYER_ANCHORS.TRACKS.loop.count):
		var loop: Dictionary = layers.get_prayer_lower_pose("loop", frame / float(maxi(RigLayers.PRAYER_ANCHORS.TRACKS.loop.count - 1, 1)))
		stable_loop = stable_loop and loop.metadata.left == held.metadata.left and loop.metadata.right == held.metadata.right
	check(stable_loop, "The sustained prayer holds the folded legs steady beneath the restrained upper-body breathing")
