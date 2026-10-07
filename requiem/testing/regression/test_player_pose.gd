extends Node2D
## Pose regressions inspect the attachment's painted pixels as well as runtime
## transforms. Matching two getters cannot prove that a visible hand grips a prop.

var checks := 0
var failures: Array[String] = []
var completed_scenarios := 0
var player: CharacterBody2D
var aim: Node
var appearance: Node2D
var action: Node
var grip_image: Image
var upper_image: Image
var _previous_lower: Dictionary = {}
var _previous_toes: Dictionary = {}
var _sample_count := 0
var _max_grip_error := 0.0
var _max_wrist_bend := 0.0
var _worst_wrist_case := ""
var _max_renderer_boot_error := 0.0
var _max_planted_drift := 0.0
var _max_planted_toe_turn := 0.0
var _minimum_boot_spacing := INF
var _minimum_parallel_boot_spacing := INF
var _max_limb_reach := 0.0
var _max_hip_attachment := 0.0
var _contact_samples := 0
var _seen_turning := false
var _seen_relative_directions: Dictionary = {}
var _worst_contact_case := ""
var _worst_spacing_case: Dictionary = {}
var _sample_label := ""

const GRIP_PATH := "res://player/art/girl_rig_v2/flashlight_layer.png"
const GRIP_WRIST := Vector2(16, 20)
const GRIP_KNUCKLE := Vector2(16, 25)
const GRIP_THUMB := Vector2(12, 27)
const GRIP_LENS := Vector2(16, 34)
const RigLayers := preload("res://player/character_rig_layers.gd")
const PoseAnchors := preload("res://player/art/girl_rig_v2/action_layer_anchors.gd")
const DIRECTIONS := [Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1),
	Vector2.LEFT, Vector2(-1, -1), Vector2.UP, Vector2(1, -1)]


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for frame in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame
		if is_instance_valid(player): observe_pose()


func _ready() -> void:
	check_grip_artwork()
	check_authored_legs()
	if OS.get_cmdline_user_args().has("--source-only"):
		print("[Player pose source tests] %d/%d passed" % [checks - failures.size(), checks])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	GameState.reset()
	release_movement()
	player = preload("res://player/player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	aim = player.get_node("PlayerAim")
	appearance = player.get_node("Appearance")
	action = player.get_node("ActionState")
	action.has_flashlight = true
	player.get_node("FootstepNoise").walk_clips.clear()
	player.get_node("FootstepNoise").sprint_clips.clear()
	player.get_node("HoldBreath").exertion_rise_rate_percent = 0.0
	await frames(4)
	await check_stationary_sweep()
	await check_moving_sweep()
	await check_reversal_and_boundary_response()
	await check_wrist_aim_response()
	check_sweep_metrics()
	release_movement()
	player.queue_free()
	await get_tree().process_frame
	check(completed_scenarios == 6, "Every source and runtime pose scenario completed")
	print("[Player pose tests] %d/%d passed; %d sampled frames; contact drift %.4f px; grip cap error %.4f px; wrist bend %.4f degrees" \
		% [checks - failures.size(), checks, _sample_count, _max_planted_drift, _max_grip_error, _max_wrist_bend])
	get_tree().quit(0 if failures.is_empty() else 1)


func release_movement() -> void:
	for input_action in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(input_action)


func move_direction(direction: Vector2) -> void:
	release_movement()
	if direction.x < 0.0: Input.action_press("move_left")
	if direction.x > 0.0: Input.action_press("move_right")
	if direction.y < 0.0: Input.action_press("move_up")
	if direction.y > 0.0: Input.action_press("move_down")


func is_painted_skin(at: Vector2) -> bool:
	var pixel := grip_image.get_pixelv(Vector2i(at))
	return pixel.a > 0.8 and pixel.r > 0.5 and pixel.g > 0.35 \
		and pixel.r - pixel.g > 0.07 and pixel.g > pixel.b


func check_grip_artwork() -> void:
	grip_image = (load(GRIP_PATH) as Texture2D).get_image()
	check(grip_image != null and grip_image.get_size() == Vector2i(32, 48),
		"The shared grip texture preserves its registered drawing canvas")
	if grip_image == null: return
	check(is_painted_skin(GRIP_WRIST), "The rotating attachment contains a painted wrist at its sleeve pivot")
	check(is_painted_skin(GRIP_KNUCKLE), "The rotating attachment contains visible knuckles across the flashlight grip")
	check(is_painted_skin(GRIP_THUMB), "The rotating attachment contains a thumb beside the barrel")
	var barrel := grip_image.get_pixel(17, 32)
	var lens := grip_image.get_pixelv(Vector2i(GRIP_LENS))
	check(barrel.a > 0.8 and barrel.r < 0.4 and lens.a > 0.5,
		"The same attachment contains the opaque barrel and its forward lens")
	check(grip_image.get_pixel(16, 38).a < 0.1,
		"The muzzle landmark remains near the visible cap, not inside a longer drawn barrel")
	upper_image = RigLayers.UPPER_ATLAS.get_image()
	var minimum_cuff_alpha := 1.0
	var worst_cuff_index := -1
	for index in range(17, PoseAnchors.FRAMES.size()):
		var hand: Vector2 = PoseAnchors.FRAMES[index].right_hand
		var atlas_at := Vector2i((index % 8) * 256, floori(float(index) / 8.0) * 256) + Vector2i(hand.round())
		var cuff_alpha := 0.0
		for x in range(-3, 4):
			for y in range(-3, 4):
				cuff_alpha = maxf(cuff_alpha, upper_image.get_pixelv(atlas_at + Vector2i(x, y)).a)
		if cuff_alpha < minimum_cuff_alpha:
			minimum_cuff_alpha = cuff_alpha
			worst_cuff_index = index
	check(minimum_cuff_alpha > 0.4,
		"Every equipped upper pose has painted sleeve pixels overlapping the attachment's wrist")
	if minimum_cuff_alpha <= 0.4:
		print("[Pose cuff failure] upper index %d, max local alpha %.4f, wrist %s" \
			% [worst_cuff_index, minimum_cuff_alpha, PoseAnchors.FRAMES[worst_cuff_index].right_hand])
	completed_scenarios += 1


func check_authored_legs() -> void:
	var left_image: Image = RigLayers.LEFT_ATLAS.get_image()
	var right_image: Image = RigLayers.RIGHT_ATLAS.get_image()
	var min_signed_width := INF
	var min_spacing := INF
	var max_reach := 0.0
	var min_boot_alpha := 1.0
	var contact_lift_error := 0.0
	var swing_frames := 0
	for index in range(PoseAnchors.LOWER_FRAMES.size()):
		var pose: Dictionary = PoseAnchors.LOWER_FRAMES[index]
		var atlas_offset := Vector2i((index % 8) * 256, floori(float(index) / 8.0) * 256)
		var separation: Vector2 = pose.left.boot - pose.right.boot
		min_signed_width = minf(min_signed_width, separation.rotated(-pose.pelvis_angle).x)
		min_spacing = minf(min_spacing, separation.length())
		for side in ["left", "right"]:
			var foot: Dictionary = pose[side]
			max_reach = maxf(max_reach, foot.hip.distance_to(foot.ankle))
			var texture: Image = left_image if side == "left" else right_image
			var at := atlas_offset + Vector2i(foot.boot.round())
			min_boot_alpha = minf(min_boot_alpha, texture.get_pixelv(at).a)
			if foot.contact:
				contact_lift_error = maxf(contact_lift_error, absf(foot.lift))
			else:
				swing_frames += 1
	check(PoseAnchors.LOWER_FRAMES.size() == 137, "All idle, eight-direction walk/sprint, and pivot poses are inspected")
	check(min_signed_width >= 18.0 and min_spacing >= 18.0,
		"Authored diagonal and sideways strides never cross or overlap the 18px-wide boots")
	check(max_reach <= 60.01, "Every authored ankle remains within the rig's anatomical leg reach")
	check(min_boot_alpha > 0.1, "Boot anchors land on opaque boot artwork in each separate leg plate")
	check(contact_lift_error < 0.001 and swing_frames > 64,
		"The source poses distinguish grounded contacts from visibly raised recovery steps")
	var layers := RigLayers.new()
	var max_turn_drift := 0.0
	var max_turn_toe_change := 0.0
	for sign in [-1, 1]:
		var previous: Dictionary = layers.get_lower_pose("idle", 0, "s").metadata
		for frame in range(4):
			var current: Dictionary = layers.get_turn_pose(sign, frame).metadata
			for side in ["left", "right"]:
				if previous[side].contact and current[side].contact:
					max_turn_drift = maxf(max_turn_drift, previous[side].boot.distance_to(current[side].boot))
					max_turn_toe_change = maxf(max_turn_toe_change,
						absf(angle_difference(previous[side].toe_angle, current[side].toe_angle)))
			previous = current
	check(max_turn_drift < 0.001 and max_turn_toe_change < 0.001,
		"Authored pivot steps preserve the planted support boot and its toe direction")
	completed_scenarios += 1


func observe_pose() -> void:
	if aim == null or appearance == null: return
	var lower: Dictionary = appearance.get_actor_lower_pose()
	if lower.is_empty(): return
	_sample_count += 1
	var grip: Transform2D = appearance.get_actor_grip_transform()
	var lens_world: Vector2 = appearance.to_global(grip * GRIP_LENS)
	# The painted barrel points down in its texture. Measure the actual draw
	# transform against the baked forearm, including reversal transition frames.
	var grip_world: Transform2D = appearance.global_transform * grip
	var grip_heading := grip_world.basis_xform(Vector2.DOWN).angle()
	var forearm_heading: float = appearance.global_rotation + appearance._rig_rotation \
		+ appearance._rig_pose.flashlight_angle
	var wrist_bend := absf(rad_to_deg(angle_difference(forearm_heading, grip_heading)))
	if wrist_bend > _max_wrist_bend:
		_max_wrist_bend = wrist_bend
		_worst_wrist_case = "%s: %.4f degrees" % [_sample_label, wrist_bend]
	if not aim.beam_obstructed:
		_max_grip_error = maxf(_max_grip_error, lens_world.distance_to(aim.get_beam_global_position()))
	_seen_turning = _seen_turning or bool(lower.get("turning", false))
	_seen_relative_directions[String(lower.get("direction", ""))] = true
	var world_boots: Dictionary = {}
	var toes: Dictionary = {}
	for side in ["left", "right"]:
		var leg: Dictionary = lower.pose.metadata[side]
		var transform_at_leg: Transform2D = appearance.get_actor_leg_transform(side)
		var world_boot: Vector2 = appearance.to_global(transform_at_leg * leg.boot)
		var world_hip: Vector2 = appearance.to_global(transform_at_leg * leg.hip)
		var world_ankle: Vector2 = appearance.to_global(transform_at_leg * leg.ankle)
		world_boots[side] = world_boot
		toes[side] = transform_at_leg.get_rotation() + float(leg.toe_angle)
		_max_renderer_boot_error = maxf(_max_renderer_boot_error, world_boot.distance_to(lower.boots[side]))
		_max_limb_reach = maxf(_max_limb_reach, world_hip.distance_to(world_ankle))
		_max_hip_attachment = maxf(_max_hip_attachment, world_hip.distance_to(appearance.global_position))
		if not _previous_lower.is_empty() and lower.contacts[side] and _previous_lower.contacts[side]:
			var drift: float = world_boot.distance_to(_previous_lower.boots[side])
			if drift > _max_planted_drift:
				_max_planted_drift = drift
				_worst_contact_case = "%s %s: %.4f px" % [_sample_label, side, drift]
			_max_planted_toe_turn = maxf(_max_planted_toe_turn,
				absf(angle_difference(float(_previous_toes[side]), float(toes[side]))))
			_contact_samples += 1
	var boot_spacing: float = world_boots.left.distance_to(world_boots.right)
	if absf(sin(float(toes.left) - float(toes.right))) < sin(deg_to_rad(15.0)):
		_minimum_parallel_boot_spacing = minf(_minimum_parallel_boot_spacing, boot_spacing)
	if boot_spacing < _minimum_boot_spacing:
		_minimum_boot_spacing = boot_spacing
		_worst_spacing_case = {"scenario": _sample_label, "sample": _sample_count,
			"distance": boot_spacing, "position": player.global_position, "velocity": player.velocity,
			"body": aim.pose_body_angle, "aim": aim.aim_angle,
			"pose": lower.pose.metadata.state, "frame": lower.get("frame", -1),
			"direction": lower.get("direction", ""), "boots": world_boots.duplicate(),
			"contacts": lower.contacts.duplicate(), "offsets": lower.offsets.duplicate(),
			"rotations": lower.get("rotations", {}).duplicate(), "replants": lower.get("replants", 0)}
	_previous_lower = lower.duplicate(true)
	_previous_lower.boots = world_boots
	_previous_toes = toes


func set_cursor(angle: float, radius := 500.0) -> void:
	aim.set_target(player.global_position + Vector2.from_angle(angle) * radius)


func check_stationary_sweep() -> void:
	_sample_label = "stationary clockwise"
	for degree in range(360):
		set_cursor(deg_to_rad(degree))
		await frames(1)
	_sample_label = "stationary counterclockwise"
	for degree in range(359, -1, -1):
		set_cursor(deg_to_rad(degree))
		await frames(1)
	check(player.velocity.length() < 0.001, "A full circle of cursor aim cannot move the player root")
	completed_scenarios += 1


func check_moving_sweep() -> void:
	for index in range(DIRECTIONS.size()):
		var direction: Vector2 = DIRECTIONS[index]
		move_direction(direction)
		_sample_label = "travel %d rotating aim" % index
		for sample in range(120):
			set_cursor(deg_to_rad(sample * 3.0 + index * 45.0))
			await frames(1)
		check(absf(player.get_speed_u() - player.walk_speed_u) < 0.02,
			"Pose repair preserves normalized walk speed for travel direction %d" % index)
	release_movement()
	await frames(60)
	completed_scenarios += 1


func check_reversal_and_boundary_response() -> void:
	for direction in [Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]:
		move_direction(direction)
		Input.action_press("sprint")
		_sample_label = "diagonal sprint reversal %s" % direction
		for sample in range(60):
			set_cursor(direction.angle() + PI + deg_to_rad(sin(sample * 0.2) * 8.0))
			await frames(1)
		check(absf(player.get_speed_u() - player.sprint_speed_u) < 0.02,
			"Diagonal reversal preserves sprint speed for %s" % direction)
	release_movement()
	await frames(60)
	for sector in range(8):
		var boundary := deg_to_rad(sector * 45.0 + 22.5)
		_sample_label = "sector boundary %d" % sector
		set_cursor(boundary)
		await frames(45)
		for sample in range(12):
			set_cursor(boundary + deg_to_rad(1.0 if sample % 2 == 0 else -1.0), 100.0)
			await frames(1)
	completed_scenarios += 1


func grip_world_heading() -> float:
	var transform_at_grip: Transform2D = appearance.global_transform * appearance.get_actor_grip_transform()
	return transform_at_grip.basis_xform(Vector2.DOWN).angle()


func check_wrist_aim_response() -> void:
	release_movement()
	for degree in [0, 45, 90, 135]:
		_sample_label = "aim reversal from %d" % degree
		set_cursor(deg_to_rad(degree))
		await frames(45)
		set_cursor(deg_to_rad(degree + 180))
		await frames(60)
		check(absf(angle_difference(grip_world_heading(), deg_to_rad(degree + 180))) < deg_to_rad(5.0),
			"A sudden 180-degree cursor reversal from %d finishes with the drawn torch aimed at its target" % degree)
	for radius in [25.0, 32.0, 48.0]:
		for degree in [0, 90, 180, 270]:
			_sample_label = "near cursor %.0fpx at %d" % [radius, degree]
			set_cursor(deg_to_rad(degree), radius)
			await frames(45)
		check(aim.has_valid_target, "The %.0fpx near-cursor case exercises valid aiming outside the deadzone" % radius)
		var held_heading := grip_world_heading()
		_sample_label = "deadzone after %.0fpx aim" % radius
		for degree in range(0, 360, 30):
			set_cursor(deg_to_rad(degree), 12.0)
			await frames(1)
		check(not aim.has_valid_target and absf(angle_difference(held_heading, grip_world_heading())) < 0.001,
			"Entering the deadzone after %.0fpx aiming holds the corrected grip direction without jitter" % radius)
	completed_scenarios += 1


func check_sweep_metrics() -> void:
	check(_sample_count > 2200 and _contact_samples > 1000,
		"Dense stationary, diagonal, reversing, and boundary sweeps exercise real contact transitions")
	check(_max_grip_error <= 0.51,
		"Across all headings the beam starts within half a pixel of the actual painted lens cap")
	check(_max_wrist_bend <= 15.01,
		"Dense, near-cursor, deadzone, and sudden-reversal aiming keep the drawn grip within 15 degrees of its forearm (%s)" % _worst_wrist_case)
	check(_max_renderer_boot_error < 0.01,
		"The independently drawn leg plates place visible boot anchors at the controller's world contacts")
	check(_max_limb_reach <= 30.01,
		"Runtime transforms preserve the maximum anatomical leg reach at gameplay scale")
	check(_max_hip_attachment <= 21.0,
		"Contact compensation keeps each leg attached beneath the character's coat")
	check(_max_planted_drift < 0.05,
		"A continuing planted contact never jumps when aim, travel, or pose sectors change (%s)" % _worst_contact_case)
	check(_max_planted_toe_turn < deg_to_rad(0.1),
		"A continuing planted support foot does not spin its toe while the torso turns")
	check(_minimum_boot_spacing >= 7.0,
		"Runtime steering keeps the two visible boot centers separate (minimum %.4f px)" % _minimum_boot_spacing)
	check(_minimum_parallel_boot_spacing >= 9.0,
		"Approximately parallel boots retain at least their painted 9px width (minimum %.4f px)" % _minimum_parallel_boot_spacing)
	if _minimum_boot_spacing < 7.0: print("[Pose spacing failure] ", _worst_spacing_case)
	check(_seen_turning and _seen_relative_directions.size() >= 5,
		"The sweep covers staged pivots and multiple travel directions relative to the pelvis")
