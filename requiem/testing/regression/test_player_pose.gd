extends Node2D
## Pose regressions for the CharacterSprite rig: every sheet loads, the beam leaves the drawn
## flashlight_tip along the true aim, the legs follow the angle between travel and facing, and
## planted boots come from the lower sheet.

var checks := 0
var failures: Array[String] = []
var completed_scenarios := 0
var player: CharacterBody2D
var aim: Node
var appearance: Node2D
var action: Node
var animator: Node
var _sample_count := 0
var _max_tip_error := 0.0
var _max_beam_error := 0.0
var _zones_seen := {}

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
	check_sheets()
	GameState.reset()
	release_movement()
	player = preload("res://player/player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	aim = player.get_node("PlayerAim")
	appearance = player.get_node("Appearance")
	action = player.get_node("ActionState")
	animator = player.get_node("VivAnimator")
	action.has_flashlight = true
	player.get_node("FootstepNoise").walk_clips.clear()
	player.get_node("FootstepNoise").sprint_clips.clear()
	player.get_node("HoldBreath").exertion_rise_rate_percent = 0.0
	await frames(4)
	await check_stationary_sweep()
	await check_moving_sweep()
	await check_reversal_and_boundary_response()
	check_sweep_metrics()
	release_movement()
	player.queue_free()
	await get_tree().process_frame
	check(completed_scenarios == 3, "Every source and runtime pose scenario completed")
	print("[Player pose tests] %d/%d passed; %d sampled frames; tip error %.4f px; beam error %.4f degrees" \
		% [checks - failures.size(), checks, _sample_count, _max_tip_error, rad_to_deg(_max_beam_error)])
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


func set_cursor(angle: float, radius := 500.0) -> void:
	aim.set_target(player.global_position + Vector2.from_angle(angle) * radius)


func check_sheets() -> void:
	var broken := 0
	var dir := DirAccess.open(CharacterClips.DIRECTORY)
	for file in dir.get_files():
		if file.begins_with("girl_") and file.ends_with(".json"):
			var clip := CharacterClips.get_clip(file)
			var texture: Texture2D = clip.get("texture")
			if clip.is_empty() or texture == null or texture.get_width() != clip["hframes"] * 160 \
					or clip["frames"].size() != clip["hframes"] and file != "girl_head_poses.json":
				broken += 1
	check(broken == 0, "Every girl sheet loads with 160 px frames and one JSON entry per frame (%d broken)" % broken)
	var tip: Dictionary = CharacterClips.get_clip("girl_arm_right_on_dummy")
	check(tip.is_empty() and not CharacterClips.get_clip("girl_walk_arm_right_on").is_empty(),
		"Arm sheets exist per carry state")
	completed_scenarios += 0


func observe_pose() -> void:
	if aim == null or appearance == null: return
	_sample_count += 1
	var rig: CharacterSprite = appearance.rig
	if not rig.has_anchor("flashlight_tip") or aim.beam_obstructed: return
	_max_tip_error = maxf(_max_tip_error, rig.flashlight_tip_global().distance_to(aim.get_muzzle_global_position()))
	_max_beam_error = maxf(_max_beam_error, absf(angle_difference(player.get_node("flashlight").global_rotation, aim.aim_angle)))
	var lower: String = rig.clip_name(&"lower")
	if lower != "":
		_zones_seen[lower] = true


func check_stationary_sweep() -> void:
	for degree in range(360):
		set_cursor(deg_to_rad(degree))
		await frames(1)
	check(player.velocity.length() < 0.001, "A full circle of cursor aim cannot move the player root")
	check(appearance.rig.clip_name(&"lower") == "girl_stand_lower", "Aiming in place keeps the standing legs")
	completed_scenarios += 1


func check_moving_sweep() -> void:
	for index in range(DIRECTIONS.size()):
		move_direction(DIRECTIONS[index])
		for sample in range(120):
			set_cursor(deg_to_rad(sample * 3.0 + index * 45.0))
			await frames(1)
		check(absf(player.get_speed_u() - player.walk_speed_u) < 0.02,
			"Pose repair preserves normalized walk speed for travel direction %d" % index)
	release_movement()
	await frames(60)
	completed_scenarios += 1


func check_reversal_and_boundary_response() -> void:
	for degree in [0, 45, 90, 135]:
		release_movement()
		set_cursor(deg_to_rad(degree))
		await frames(45)
		set_cursor(deg_to_rad(degree + 180))
		await frames(60)
		check(absf(angle_difference(player.get_node("flashlight").global_rotation, deg_to_rad(degree + 180))) < deg_to_rad(5.0),
			"A sudden 180-degree cursor reversal from %d finishes with the beam aimed at its target" % degree)
	# Walking away from the aim plays the legs reversed; across it, the side step.
	set_cursor(0.0)
	move_direction(Vector2.LEFT)
	await frames(40)
	var clip: String = appearance.rig.clip_name(&"lower")
	check(clip == "girl_walk_lower" and appearance.rig._players[&"lower"]["reverse"],
		"Travelling away from the aim plays the walk legs reversed")
	move_direction(Vector2.DOWN)
	await frames(40)
	check(appearance.rig.clip_name(&"lower") == "girl_side_step_lower", "Travelling across the aim plays the side step")
	move_direction(Vector2.RIGHT)
	await frames(40)
	check(appearance.rig.clip_name(&"lower") == "girl_walk_lower" and not appearance.rig._players[&"lower"]["reverse"],
		"Travelling toward the aim plays the walk legs forward")
	release_movement()
	completed_scenarios += 1


func check_sweep_metrics() -> void:
	check(_sample_count > 1000, "The sweeps sampled real rig frames")
	check(_max_tip_error < 0.5, "The beam leaves the drawn flashlight tip (worst %.4f px)" % _max_tip_error)
	check(_max_beam_error < deg_to_rad(0.1), "The beam heading is the aim heading (worst %.4f degrees)" % rad_to_deg(_max_beam_error))
	check(_zones_seen.has("girl_walk_lower") and _zones_seen.has("girl_side_step_lower"),
		"The sweeps exercised both the walk and the side-step legs")
