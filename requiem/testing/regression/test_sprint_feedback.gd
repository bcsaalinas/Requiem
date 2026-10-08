extends Node2D
## Exercise sprint through real physics, painted rig anchors, and hearing events.
## Dense angle sweeps protect the independently planted feet during aim changes.

const RigLayers := preload("res://player/character_rig_layers.gd")
const CharacterAnimation := preload("res://player/character_animation.gd")
const LegPose := preload("res://player/leg_pose.gd")
const DIRECTIONS := [Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1),
	Vector2.LEFT, Vector2(-1, -1), Vector2.UP, Vector2(1, -1)]
const FACING := [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]
const GRIP_LENS := Vector2(16, 34)

var checks := 0
var failures: Array[String] = []
var completed_scenarios := 0
var player: CharacterBody2D
var appearance: Node2D
var motion: Node
var aim: Node
var action: Node
var breath: Node
var dust: Node2D
var footsteps: Node
var thrower: Node
var flashlight: PointLight2D
var noises: Array[Dictionary] = []
var _previous_lower: Dictionary = {}
var _previous_toes: Dictionary = {}
var _sample_count := 0
var _pose_count := 0
var _contact_count := 0
var _maximum_contact_drift := 0.0
var _maximum_contact_turn := 0.0
var _maximum_boot_error := 0.0
var _maximum_leg_reach := 0.0
var _maximum_hip_distance := 0.0
var _minimum_spacing := INF
var _minimum_parallel_spacing := INF
var _maximum_lens_error := 0.0
var _maximum_wrist_bend := 0.0
var _maximum_particles := 0
var _maximum_emission_error := 0.0
var _unexpected_emissions := 0
var _sample_contacts := {"left": false, "right": false}
var _sample_emissions := 0
var _sample_label := ""
var _worst_contact := ""
var _relative_directions := {}


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func release_inputs() -> void:
	for input_action in ["move_left", "move_right", "move_up", "move_down", "sprint", "hold_breath", "throw", "pray"]:
		Input.action_release(input_action)


func move_direction(direction: Vector2, sprint := true) -> void:
	for input_action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(input_action)
	if direction.x < 0.0: Input.action_press("move_left")
	if direction.x > 0.0: Input.action_press("move_right")
	if direction.y < 0.0: Input.action_press("move_up")
	if direction.y > 0.0: Input.action_press("move_down")
	if sprint: Input.action_press("sprint")


func frames(count: int, observe := false) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame
		if observe: observe_pose()


func reset_scenario() -> void:
	release_inputs()
	get_tree().paused = false
	GameState.reset()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.is_sprinting = false
	breath.cancel_holding()
	breath.is_locked = false
	breath._lock_timer = 0.0
	breath.reset_input_latch()
	breath.exertion_percent = 0.0
	breath.lung_percent = 100.0
	breath.exertion_rise_rate_percent = 6.0
	player.get_node("BreathFeedback").reset_feedback()
	player.get_node("PrayerFeedback").reset_feedback()
	thrower.clear_pending()
	thrower.available = true
	thrower.rocks = 4
	action.has_flashlight = true
	flashlight.is_on = true
	flashlight.battery_percent = 100.0
	appearance.actor_facing = &"s"
	footsteps.footstep_timer = 0.0
	motion.set_enabled(true)
	aim.reset_pose()
	aim.set_target(Vector2.DOWN * 2048.0)
	dust.enabled = true
	dust.effects_strength = 1.0
	dust.clear_dust()
	await frames(3)
	_previous_lower.clear()
	_previous_toes.clear()
	_sample_contacts = appearance.get_actor_lower_pose().contacts.duplicate()
	_sample_emissions = dust.emitted_puffs
	noises.clear()


func _ready() -> void:
	GameState.reset()
	release_inputs()
	player = preload("res://player/player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	appearance = player.get_node("Appearance")
	motion = player.get_node("PlayerMotion")
	aim = player.get_node("PlayerAim")
	action = player.get_node("ActionState")
	breath = player.get_node("HoldBreath")
	dust = player.get_node("SprintDust")
	footsteps = player.get_node("FootstepNoise")
	thrower = player.get_node("Throw")
	flashlight = player.get_node("flashlight")
	for clips in [footsteps.walk_clips, footsteps.sprint_clips, breath.hold_clips,
		breath.exhale_clips, breath.gasp_clips, breath.forced_gasp_clips, breath.exertion_clips,
		thrower.piedra_clips, thrower.despertador_clips, flashlight.click_clips]:
		clips.clear()
	NoiseManager.noise_emitted.connect(func(_at: Vector2, radius: float, source: int, _duration: float):
		noises.append({"radius": radius, "source": source}))
	check_source_poses()
	check_clock_transitions()
	await check_direction_sweeps()
	await check_dust_and_blocked_motion()
	await check_interruptions()
	await check_action_overlaps()
	await check_mechanic_parity()
	await check_upper_pose_sweep()
	check_runtime_metrics()
	check(completed_scenarios == 8, "Every sprint source, movement, effect and interruption scenario completes")
	release_inputs()
	GameState.reset()
	player.queue_free()
	await frames(3)
	print("[Sprint feedback tests] %d/%d passed; %d live frames; %d upper poses; contact drift %.5f px; minimum boot spacing %.3f px" \
		% [checks - failures.size(), checks, _sample_count, _pose_count, _maximum_contact_drift, _minimum_spacing])
	get_tree().quit(0 if failures.is_empty() else 1)


func check_source_poses() -> void:
	var layers := RigLayers.new()
	var anchors = RigLayers.SPRINT_ANCHORS
	check(anchors.FRAMES.size() == 48 and anchors.LOWER_FRAMES.size() == 64,
		"Sprint has eight upper poses in six equipment modes and eight independent leg poses in eight travel directions")
	check(is_equal_approx(anchors.CYCLE_SECONDS, 0.6) and is_equal_approx(anchors.STRIDE_DISTANCE, 103.68),
		"The new visual stride covers 3.24 units in 0.60 seconds at the existing 5.4 u/s sprint speed")
	var min_lane_width := INF
	var min_boot_alpha := 1.0
	var max_reach := 0.0
	var bad_contact_lift := 0.0
	var airborne_frames := 0
	var correct_atlases := true
	var left_image: Image = RigLayers.SPRINT_LEFT_ATLAS.get_image()
	var right_image: Image = RigLayers.SPRINT_RIGHT_ATLAS.get_image()
	for direction in RigLayers.DIRECTIONS:
		for frame in range(8):
			var pose: Dictionary = layers.get_lower_pose("sprint", frame, direction)
			correct_atlases = correct_atlases and pose.left_texture == RigLayers.SPRINT_LEFT_ATLAS \
				and pose.right_texture == RigLayers.SPRINT_RIGHT_ATLAS
			var metadata: Dictionary = pose.metadata
			min_lane_width = minf(min_lane_width, (Vector2(metadata.left.boot) - Vector2(metadata.right.boot)).x)
			if not metadata.left.contact and not metadata.right.contact: airborne_frames += 1
			for side in ["left", "right"]:
				var leg: Dictionary = metadata[side]
				max_reach = maxf(max_reach, Vector2(leg.hip).distance_to(leg.ankle))
				var image: Image = left_image if side == "left" else right_image
				var pixel := Vector2i(pose.region.position) + Vector2i(Vector2(leg.boot).round())
				min_boot_alpha = minf(min_boot_alpha, image.get_pixelv(pixel).a)
				if leg.contact: bad_contact_lift = maxf(bad_contact_lift, absf(float(leg.lift)))
	check(correct_atlases, "Every sprint direction uses the new independent left and right leg sheets")
	check(min_lane_width >= 18.0, "Authored sprint boots retain separate anatomical lanes at all diagonal and sideways angles")
	check(max_reach <= 60.01 and min_boot_alpha > 0.1,
		"Every new sprint boot anchor lands on visible artwork within the established anatomical leg reach")
	check(bad_contact_lift < 0.001 and airborne_frames >= 8,
		"Sprint distinguishes planted support from raised recovery and includes a readable flight phase")
	var min_cuff_alpha := 1.0
	var upper_image: Image = RigLayers.SPRINT_UPPER_ATLAS.get_image()
	for index in range(8, 48):
		var cuff: Vector2 = anchors.FRAMES[index].right_hand
		var at := Vector2i((index % 8) * 256, floori(float(index) / 8.0) * 256) + Vector2i(cuff.round())
		var alpha := 0.0
		for x in range(-3, 4):
			for y in range(-3, 4): alpha = maxf(alpha, upper_image.get_pixelv(at + Vector2i(x, y)).a)
		min_cuff_alpha = minf(min_cuff_alpha, alpha)
	check(min_cuff_alpha > 0.4, "All forty equipped sprint poses paint the sleeve around the rigid hand/torch socket")
	completed_scenarios += 1


func check_clock_transitions() -> void:
	var resource: SpriteFrames = appearance.actor_frames
	var max_phase_jump := 0.0
	var max_swing_jump := 0.0
	var duration_error := 0.0
	var layers := RigLayers.new()
	for frame in range(8):
		var controller := CharacterAnimation.new()
		controller.reset(resource)
		controller.advance(resource, 0.0, true, Vector2.DOWN, 0.0, false)
		controller.advance(resource, 0.0, true, Vector2.DOWN, fposmod(frame / 8.0 - 0.25, 1.0), false)
		var before: float = controller.phase
		controller.advance(resource, 0.0, true, Vector2.DOWN, 0.87, true)
		max_phase_jump = maxf(max_phase_jump, absf(controller.phase - before))
		check(controller.frame == frame and controller.animation == &"sprint_s",
			"Walk to sprint preserves contact phase %d when changing to an unrelated distance clock" % frame)
		controller.advance(resource, 0.0, true, Vector2.DOWN, 0.11, false)
		max_phase_jump = maxf(max_phase_jump, absf(controller.phase - before))
		check(controller.frame == frame and controller.animation == &"walk_s",
			"Sprint to walk or held movement preserves contact phase %d when returning to the footstep clock" % frame)
		for state in ["walk", "sprint"]:
			var solver := LegPose.new()
			solver.reset(PI / 2.0)
			var first: Dictionary = solver.advance(1.0 / 60.0, state, frame, true, PI / 2.0, PI / 2.0,
				Vector2.ZERO, appearance.actor_ground_offset, appearance.actor_frame_scale, layers)
			var next_state := "sprint" if state == "walk" else "walk"
			var second: Dictionary = solver.advance(0.0, next_state, frame, true, PI / 2.0, PI / 2.0,
				Vector2.ZERO, appearance.actor_ground_offset, appearance.actor_frame_scale, layers)
			duration_error = maxf(duration_error, absf(solver._pose_duration - layers.get_cycle_seconds(next_state) / 8.0))
			for side in ["left", "right"]:
				if not first.contacts[side] and not second.contacts[side]:
					max_swing_jump = maxf(max_swing_jump, Vector2(first.boots[side]).distance_to(second.boots[side]))
	check(max_phase_jump < 0.0001, "Changing locomotion clocks never skips an authored cycle phase")
	check(duration_error < 0.0001, "Contact prediction adopts the new gait's duration on its first frame")
	check(max_swing_jump <= LegPose.MAX_OFFSET + 0.01,
		"Switching geometry mid-swing stays within the existing bounded foot correction (%.3f px)" % max_swing_jump)
	completed_scenarios += 1


func check_direction_sweeps() -> void:
	await reset_scenario()
	breath.exertion_rise_rate_percent = 0.0
	for index in range(8):
		move_direction(DIRECTIONS[index])
		_sample_label = "sprint travel %d with rotating aim" % index
		for sample in range(72):
			aim.set_target(player.global_position + Vector2.from_angle(index * PI / 4.0 + sample * TAU / 72.0) * 500.0)
			await frames(1, true)
		check(motion.mode == "Sprint" and absf(player.get_speed_u() - 5.4) < 0.02,
			"Sprint keeps its normalized gameplay speed through a full aim sweep in direction %d" % index)
		check(appearance.get_actor_lower_pose().pose.left_texture == RigLayers.SPRINT_LEFT_ATLAS,
			"Real movement renders the new sprint feet in direction %d" % index)
	for index in [1, 5, 3, 7]:
		move_direction(DIRECTIONS[index])
		_sample_label = "diagonal reversal with near opposite aim %d" % index
		for sample in range(36):
			aim.set_target(player.global_position + Vector2.from_angle(DIRECTIONS[index].angle() + PI + sin(sample * 0.2) * 0.1) * 32.0)
			await frames(1, true)
	check(dust.emitted_puffs > 24, "The real eight-direction sprint produces repeated foot-plant dust")
	completed_scenarios += 1


func observe_pose() -> void:
	var lower: Dictionary = appearance.get_actor_lower_pose()
	if lower.is_empty(): return
	_sample_count += 1
	_relative_directions[String(lower.direction)] = true
	var toes := {}
	var boots := {}
	for side in ["left", "right"]:
		var leg: Dictionary = lower.pose.metadata[side]
		var transform_at_leg: Transform2D = appearance.get_actor_leg_transform(side)
		var boot: Vector2 = appearance.to_global(transform_at_leg * Vector2(leg.boot))
		boots[side] = boot
		toes[side] = transform_at_leg.get_rotation() + float(leg.toe_angle)
		_maximum_boot_error = maxf(_maximum_boot_error, boot.distance_to(lower.boots[side]))
		_maximum_leg_reach = maxf(_maximum_leg_reach, (transform_at_leg * Vector2(leg.hip)).distance_to(transform_at_leg * Vector2(leg.ankle)))
		_maximum_hip_distance = maxf(_maximum_hip_distance, appearance.to_global(transform_at_leg * Vector2(leg.hip)).distance_to(appearance.global_position))
		if not _previous_lower.is_empty() and lower.contacts[side] and _previous_lower.contacts[side]:
			_contact_count += 1
			var drift: float = boot.distance_to(_previous_lower.boots[side])
			if drift > _maximum_contact_drift:
				_maximum_contact_drift = drift
				_worst_contact = "%s %s" % [_sample_label, side]
			_maximum_contact_turn = maxf(_maximum_contact_turn, absf(angle_difference(_previous_toes[side], toes[side])))
	var spacing: float = Vector2(boots.left).distance_to(boots.right)
	_minimum_spacing = minf(_minimum_spacing, spacing)
	if absf(sin(float(toes.left) - float(toes.right))) < sin(deg_to_rad(15.0)):
		_minimum_parallel_spacing = minf(_minimum_parallel_spacing, spacing)
	_previous_lower = lower.duplicate(true)
	_previous_lower.boots = boots
	_previous_toes = toes
	observe_grip()
	_maximum_particles = maxi(_maximum_particles, dust.particles.size())
	var new_contacts := 0
	for side in ["left", "right"]:
		if lower.contacts[side] and not _sample_contacts[side]: new_contacts += 1
	var emitted: int = dust.emitted_puffs - _sample_emissions
	if emitted > new_contacts * 3: _unexpected_emissions += emitted
	for puff in dust.particles:
		if is_zero_approx(float(puff.age)):
			_maximum_emission_error = maxf(_maximum_emission_error, Vector2(puff.position).distance_to(lower.boots[puff.foot]))
	_sample_contacts = lower.contacts.duplicate()
	_sample_emissions = dust.emitted_puffs


func observe_grip() -> void:
	if not action.has_flashlight: return
	var grip: Transform2D = appearance.get_actor_grip_transform()
	if not aim.beam_obstructed:
		_maximum_lens_error = maxf(_maximum_lens_error, appearance.to_global(grip * GRIP_LENS).distance_to(aim.get_beam_global_position()))
	var heading: float = (appearance.global_transform * grip).basis_xform(Vector2.DOWN).angle()
	var forearm: float = appearance.global_rotation + appearance._rig_rotation + appearance._rig_pose.flashlight_angle
	_maximum_wrist_bend = maxf(_maximum_wrist_bend, absf(rad_to_deg(angle_difference(forearm, heading))))


func check_dust_and_blocked_motion() -> void:
	await reset_scenario()
	Input.action_press("sprint")
	var emitted: int = dust.emitted_puffs
	await frames(15)
	check(dust.emitted_puffs == emitted and dust.particles.is_empty(), "Holding sprint at rest creates no dust")
	move_direction(Vector2.RIGHT, false)
	await frames(40)
	check(dust.emitted_puffs == emitted, "Ordinary walking does not produce sprint dust")
	Input.action_press("sprint")
	await frames(45)
	check(not dust.particles.is_empty() and dust.emitted_puffs > emitted, "Accepted sprint foot plants create visible ground puffs")
	var puff: Dictionary = dust.particles[-1]
	var origin: Vector2 = puff.position
	var velocity: Vector2 = puff.velocity
	player.global_position += Vector2(18, 4)
	dust._physics_process(1.0 / 60.0)
	check(Vector2(puff.position).distance_to(origin + velocity / 60.0) < 0.001
		and dust.global_transform == Transform2D.IDENTITY,
		"Existing dust drifts in world space without following a moving player parent")
	Input.action_press("hold_breath")
	await frames(4)
	emitted = dust.emitted_puffs
	await frames(36)
	check(motion.mode == "Held breath" and dust.emitted_puffs == emitted and dust.particles.is_empty(),
		"Held breath overrides sprint and lets its old dust finish fading without emitting new puffs")
	Input.action_release("hold_breath")
	await frames(45)
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(32, 300)
	collider.shape = shape
	wall.position = player.position + Vector2(56, 0)
	wall.add_child(collider)
	add_child(wall)
	await frames(45)
	var phase: float = motion._sprint_clock
	emitted = dust.emitted_puffs
	await frames(32)
	check(motion.mode == "Idle" and is_equal_approx(motion._sprint_clock, phase)
		and dust.emitted_puffs == emitted and dust.particles.is_empty(),
		"Pushing into a real wall stops both the distance-driven stride and dust despite held sprint input")
	wall.queue_free()
	await frames(35)
	check(motion.mode == "Sprint" and dust.emitted_puffs > emitted, "Actual movement after a wall clears resumes sprint and new foot scuffs")
	release_inputs()
	await frames(60)
	emitted = dust.emitted_puffs
	await frames(15)
	check(dust.emitted_puffs == emitted and dust.particles.is_empty(), "Stopping fades every sprint puff without a stationary emission tail")
	completed_scenarios += 1


func check_interruptions() -> void:
	for blocker in ["pause", "death", "disabled", "teleport", "reset", "fx_disabled", "zero_strength"]:
		await reset_scenario()
		move_direction(Vector2.RIGHT)
		await frames(48)
		check(not dust.particles.is_empty(), "%s fixture contains live sprint dust" % blocker)
		var snapshot: Array = dust.particles.duplicate(true)
		var phase: float = motion._sprint_clock
		var emitted: int = dust.emitted_puffs
		match blocker:
			"pause": get_tree().paused = true
			"death": GameState.kill_player()
			"disabled": player.process_mode = Node.PROCESS_MODE_DISABLED
			"teleport": player.global_position += Vector2(400, 0)
			"reset": GameState.reset()
			"fx_disabled": dust.enabled = false
			"zero_strength": dust.effects_strength = 0.0
		if blocker in ["death", "reset"]:
			check(dust.particles.is_empty(), "%s synchronously clears old sprint particles" % blocker)
		if blocker == "pause":
			await frames(6)
			check(dust.particles == snapshot and is_equal_approx(motion._sprint_clock, phase)
				and dust.emitted_puffs == emitted, "Pause freezes sprint phase, existing dust and emissions together")
		else:
			if blocker == "reset":
				release_inputs()
				player.velocity = Vector2.ZERO
			await frames(1)
			check(dust.particles.is_empty() and dust.emitted_puffs == emitted,
				"%s leaves no stale dust or artificial teleport trail on the next physics update" % blocker)
	completed_scenarios += 1


func check_action_overlaps() -> void:
	await reset_scenario()
	move_direction(Vector2.RIGHT)
	await frames(50)
	thrower._start_throw()
	await frames(8)
	check(thrower.is_throwing and appearance._rig_pose.upper_texture == RigLayers.THROW_ATLAS
		and appearance.get_actor_lower_pose().pose.left_texture == RigLayers.SPRINT_LEFT_ATLAS,
		"Throw windup owns the upper body while a moving sprint retains its independent running legs")
	thrower.cancel_windup()
	breath.exertion_percent = 99.99
	await frames(3)
	var emitted: int = dust.emitted_puffs
	await frames(32)
	check(breath.is_locked and motion.mode == "Idle" and dust.emitted_puffs == emitted and dust.particles.is_empty()
		and appearance._rig_pose.upper_texture == RigLayers.BREATH_ATLAS,
		"A genuine exertion gasp interrupts sprint, owns the body and stops new dust for the existing movement lock")
	await reset_scenario()
	move_direction(Vector2.RIGHT)
	await frames(48)
	var altar_root: Node2D = preload("res://altar/altar.tscn").instantiate()
	altar_root.position = player.position + Vector2(0, -56)
	add_child(altar_root)
	var altar := altar_root.get_node("BodyAltar")
	altar.pray_clips.clear()
	altar.set_process(false)
	altar._on_area_2d_body_entered(player)
	Input.action_press("pray")
	altar._process(0.4)
	emitted = dust.emitted_puffs
	await frames(32)
	check(GameState.is_praying and motion.mode == "Idle" and dust.emitted_puffs == emitted
		and dust.particles.is_empty() and appearance.get_actor_lower_pose().get("kneeling", false),
		"An accepted altar prayer replaces sprint with its kneeling feet and fades existing dust")
	Input.action_release("pray")
	altar._process(0.0)
	altar_root.queue_free()
	completed_scenarios += 1


func mechanic_sample(presentation: bool) -> Dictionary:
	await reset_scenario()
	motion.set_enabled(presentation)
	dust.enabled = presentation
	move_direction(Vector2.RIGHT)
	var footfalls: Array[Dictionary] = []
	for step in range(90):
		var before := noises.size()
		action._physics_process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
		footsteps._physics_process(1.0 / 60.0)
		breath._physics_process(1.0 / 60.0)
		motion._physics_process(1.0 / 60.0)
		aim._physics_process(1.0 / 60.0)
		dust._physics_process(1.0 / 60.0)
		if noises.size() > before:
			footfalls.append({"step": step, "noise": noises[-1].duplicate()})
	return {"position": player.position, "speed": player.get_speed_u(), "exertion": breath.exertion_percent,
		"lung": breath.lung_percent, "timer": footsteps.footstep_timer, "footfalls": footfalls}


func check_mechanic_parity() -> void:
	var visible := await mechanic_sample(true)
	var hidden := await mechanic_sample(false)
	check(visible == hidden, "Enabling sprint animation and dust preserves displacement, speed, lung/exertion costs and every hearing event")
	check(absf(visible.speed - 5.4) < 0.002 and absf(visible.exertion - 9.0) < 0.002 and visible.lung == 100.0,
		"Ninety real movement updates retain 5.4 u/s speed, six-percent-per-second exertion and full lungs")
	check(visible.footfalls.size() == 3 and visible.footfalls[0].noise.radius == 192.0
		and visible.footfalls[0].noise.source == NoiseManager.SourceType.SPRINT
		and is_equal_approx(footsteps.footstep_interval, 0.45),
		"The shorter visual run retains the original 0.45-second footstep clock and six-unit sprint hearing cost")
	completed_scenarios += 1


func check_upper_pose_sweep() -> void:
	await reset_scenario()
	var all_sprint := true
	for equipment in range(3):
		action.has_flashlight = equipment > 0
		flashlight.is_on = equipment == 2
		for heading in range(8):
			appearance.actor_facing = FACING[heading]
			aim.reset_pose()
			appearance.actor_animation = &"sprint_s"
			for arm_step in (range(-2, 3) if equipment > 0 else [0]):
				aim._arm_step = arm_step
				aim.aim_angle = heading * PI / 4.0 + arm_step * PI / 8.0 + (deg_to_rad(15.0) if equipment > 0 else 0.0)
				for frame in range(8):
					appearance.actor_frame = frame
					aim._apply_pose()
					all_sprint = all_sprint and appearance._rig_pose.upper_texture == RigLayers.SPRINT_UPPER_ATLAS
					observe_grip()
					_pose_count += 1
		check(appearance.actor_equipped == (equipment > 0) and flashlight.is_on == (equipment == 2),
			"Sprint preserves absent, unlit and lit flashlight ownership mode %d" % equipment)
	check(all_sprint and _pose_count == 704, "Every sprint upper frame covers all eight headings and all eleven flashlight ownership/aim modes")
	completed_scenarios += 1


func check_runtime_metrics() -> void:
	check(_sample_count >= 720 and _contact_count > 300 and _relative_directions.size() >= 5,
		"Dense real sprint sweeps exercise planted contacts, aim/travel disagreement and abrupt diagonal reversals")
	check(_maximum_contact_drift < 0.05,
		"A continuing sprint support foot stays planted through every heading (%.5f px; %s)" % [_maximum_contact_drift, _worst_contact])
	check(_maximum_contact_turn < deg_to_rad(0.1), "A planted sprint boot never spins with the turning torso")
	check(_maximum_boot_error < 0.01, "Rendered sprint boot pixels follow the solver's independent world contacts")
	check(_minimum_spacing >= 7.0 and _minimum_parallel_spacing >= 9.0,
		"Sprint steering and reversals keep visible boots separated (%.3f px; parallel %.3f px)" % [_minimum_spacing, _minimum_parallel_spacing])
	check(_maximum_leg_reach <= 30.01 and _maximum_hip_distance <= 21.0,
		"Running feet stay within anatomical reach and attached under the coat")
	check(_maximum_lens_error <= 0.51 and _maximum_wrist_bend <= 15.01,
		"All sprint poses retain the painted lens origin and fifteen-degree wrist limit (%.5f px; %.4f degrees)" % [_maximum_lens_error, _maximum_wrist_bend])
	# Heel birth is at most 6px rearward plus 2.15px lateral: 6.375px radial.
	check(_unexpected_emissions == 0 and _maximum_emission_error < 6.4,
		"Dust starts only on newly planted real feet beside the corresponding heel")
	check(_maximum_particles > 0 and _maximum_particles <= dust.MAX_PUFFS,
		"Sustained sprint effects remain bounded to the small fixed particle budget")
