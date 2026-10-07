extends Node2D
## Exercise presentation through real player physics and the existing noise bus.

var player: CharacterBody2D
var motion: Node
var footsteps: Node
var checks := 0
var failures: Array[String] = []
var noises: Array[Dictionary] = []
var planted_steps := 0
var max_lift := 0.0
var walk_frames_seen: Dictionary = {}
const CharacterAnimation := preload("res://player/character_animation.gd")
const FACING_VECTORS := {
	"s": Vector2.DOWN, "sw": Vector2(-1, 1), "w": Vector2.LEFT,
	"nw": Vector2(-1, -1), "n": Vector2.UP, "ne": Vector2(1, -1),
	"e": Vector2.RIGHT, "se": Vector2(1, 1),
}


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame
		max_lift = maxf(max_lift, -player.get_node("Appearance").actor_motion_offset.y)
		var appearance: Node2D = player.get_node("Appearance")
		if String(appearance.actor_animation).begins_with("walk_"):
			walk_frames_seen[appearance.actor_frame] = true
		if footsteps.footstep_timer == 0.0 and motion.mode != "Idle":
			planted_steps += 1
			check(absf(player.get_node("Appearance").actor_motion_offset.y) < 0.001,
				"Gameplay footfall resets the legacy procedural body offset")


func _ready() -> void:
	GameState.reset()
	player = preload("res://player/player.tscn").instantiate()
	add_child(player)
	player.get_node("Camera2D").enabled = false
	motion = player.get_node("PlayerMotion")
	footsteps = player.get_node("FootstepNoise")
	check_animation_contract(player.get_node("Appearance").actor_frames)
	footsteps.walk_clips.clear()
	footsteps.sprint_clips.clear()
	player.get_node("HoldBreath").hold_clips.clear()
	player.get_node("HoldBreath").exertion_clips.clear()
	NoiseManager.noise_emitted.connect(func(at: Vector2, radius: float, source: int, _duration: float):
		noises.append({"at":at, "radius":radius, "source":source}))
	await frames(3)
	var collider_start: Transform2D = player.get_node("CollisionShape2D").transform
	var light_start: Transform2D = player.get_node("LocalLight").transform
	Input.action_press("move_right")
	await frames(90)
	var walk_lift := max_lift
	check(motion.mode == "Walk" and walk_lift > 1.8, "Walking retains legacy procedural feedback for atlas skins")
	check(planted_steps >= 2, "Real walking exercised planted footfalls")
	check(not noises.is_empty() and noises[-1].radius == 96.0,
		"Walking retains the existing hearing radius")
	check(is_equal_approx(footsteps.footstep_interval, 0.45), "Walking cadence is unchanged")
	check(player.get_node("Appearance").actor_frames.resource_path == "res://player/art/girl_rig_v2/girl_frames.tres",
		"The shared player scene equips the coherent directional girl")
	check(player.get_node("Appearance").actor_animation == &"walk_e",
		"Right input displays the authored east view")
	check(walk_frames_seen.size() == 8,
		"Real movement visits every authored walk frame across the footstep cycle")
	check(player.get_node("CollisionShape2D").transform == collider_start,
		"Painted body never moves the collider")
	check(player.get_node("LocalLight").transform == light_start,
		"Painted body never moves the physical light")

	max_lift = 0.0
	Input.action_press("sprint")
	await frames(75)
	check(motion.mode == "Sprint" and max_lift > walk_lift * 1.35,
		"Sprinting has stronger body feedback")
	check(noises[-1].radius == 192.0, "Sprinting retains its hearing cost")
	check(player.get_node("Appearance").actor_animation == &"sprint_e",
		"Sprinting displays its dedicated matching view")
	max_lift = 0.0
	Input.action_press("hold_breath")
	await frames(90)
	check(motion.mode == "Held breath" and max_lift < walk_lift * 0.55,
		"Held breath overrides sprint and makes the gait restrained")
	check(noises[-1].radius == 32.0 and is_equal_approx(footsteps.held_footstep_interval, 0.7),
		"Held footsteps retain their radius and cadence")
	check(player.get_node("Appearance").actor_animation == &"walk_e",
		"Held breath uses the girl fallback with the existing slower footstep clock")

	Input.action_release("hold_breath")
	Input.action_release("sprint")
	Input.action_release("move_right")
	await frames(90)
	var stopped_noises := noises.size()
	await frames(45)
	check(motion.mode == "Idle" and player.get_node("Appearance").actor_motion_offset == Vector2.ZERO,
		"Stopping settles to idle")
	check(noises.size() == stopped_noises, "Presentation cannot emit noise at rest")
	check(player.get_node("Appearance").actor_animation == &"idle_e" and player.get_node("Appearance").actor_frame == 0,
		"Stopping settles to the same rig's neutral pose and retains facing")
	await check_input_directions()

	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 200)
	shape.shape = rect
	wall.position = player.position + Vector2(80, 0)
	wall.add_child(shape)
	add_child(wall)
	Input.action_press("move_right")
	await frames(100)
	check(motion.mode == "Idle" and player.get_node("Appearance").actor_motion_offset == Vector2.ZERO,
		"Pushing into a wall cannot animate walking in place")
	check(player.get_node("Appearance").actor_animation == &"idle_e",
		"The authored walk stops when collision prevents actual movement")
	wall.queue_free()
	await frames(30)
	check(motion.mode == "Walk", "Moving again resumes the gait")
	GameState.is_praying = true
	await frames(30)
	check(motion.mode == "Idle" and player.get_node("Appearance").actor_animation == &"idle_e",
		"A prayer movement lock settles to matching idle despite held movement input")
	GameState.is_praying = false
	await frames(30)
	check(motion.mode == "Walk", "Unlocking movement resumes the authored gait")
	get_tree().paused = true
	var paused_pose: Vector2 = player.get_node("Appearance").actor_motion_offset
	var paused_frame: int = player.get_node("Appearance").actor_frame
	await frames(12)
	check(player.get_node("Appearance").actor_motion_offset == paused_pose, "Pause freezes the pose")
	check(player.get_node("Appearance").actor_frame == paused_frame, "Pause freezes the authored frame")
	get_tree().paused = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(60)
	check(motion.mode == "Idle" and player.get_node("Appearance").actor_motion_offset == Vector2.ZERO,
		"Dialogue lock settles independently of disabled player processing")
	check(player.get_node("Appearance").actor_animation == &"idle_e",
		"Dialogue lock shows the girl still")
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await frames(30)
	motion.set_enabled(false)
	var before := player.position
	await frames(30)
	check(player.position.x > before.x and player.get_node("Appearance").actor_motion_offset == Vector2.ZERO,
		"Comparison disables body feedback without changing physical movement")
	motion.set_enabled(true)
	await frames(30)
	player.position += Vector2(400, 0)
	await frames(1)
	check(motion.gait_phase == 0.0 and player.get_node("Appearance").actor_motion_offset == Vector2.ZERO,
		"Teleport resets the gait immediately")
	Input.action_release("move_right")
	player.queue_free()
	await get_tree().process_frame
	var game := preload("res://testing/experiments/phantom_tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	game._input(key)
	check(not game.player.get_node("PlayerMotion").enabled and not game.using_native_camera,
		"V compares body feedback without switching the camera")
	game._input(key)
	check(game.player.get_node("PlayerMotion").enabled,
		"V restores feedback for the playable review")
	game.queue_free()
	await get_tree().process_frame
	print("[Player motion tests] %d/%d passed" % [checks - failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func check_animation_contract(resource: SpriteFrames) -> void:
	var neutral := resource.get_frame_texture(&"idle_s", 0) as AtlasTexture
	var identity_atlas: Texture2D = neutral.atlas if neutral != null else null
	for facing: String in FACING_VECTORS:
		for action in ["idle", "walk", "sprint"]:
			var name := StringName(action + "_" + facing)
			check(resource.has_animation(name), "Authored animation exists: %s" % name)
			if not resource.has_animation(name): continue
			var expected := 1 if action == "idle" else 8
			check(resource.get_frame_count(name) == expected,
				"%s uses %d deliberate poses, within the 24-frame limit" % [name, expected])
			for index in range(resource.get_frame_count(name)):
				var texture := resource.get_frame_texture(name, index)
				check(texture is AtlasTexture and texture.get_size() == Vector2(256, 256)
					and texture.atlas == identity_atlas,
					"%s frame %d shares the neutral pose's atlas and registered canvas" % [name, index])
	var controller := CharacterAnimation.new()
	controller.reset(resource)
	controller.advance(resource, 0.0, true, Vector2.DOWN, 0.0, false)
	check(controller.frame == 2 and is_equal_approx(controller.phase, 0.25),
		"Starting from neutral enters the closest passing pose")
	for facing: String in FACING_VECTORS:
		controller.advance(resource, 1.0 / 60.0, true, FACING_VECTORS[facing], 0.125, false)
		check(controller.animation == StringName("walk_" + facing),
			"Direction selects its own perspective: %s" % facing)
		check(is_equal_approx(controller.phase, 0.375) and controller.frame == 3,
			"Turning preserves gait phase for %s" % facing)
		controller.advance(resource, 0.0, true, FACING_VECTORS[facing], 0.125, true)
		check(controller.animation == StringName("sprint_" + facing) and controller.frame == 3,
			"Walk to sprint preserves the same contact phase for %s" % facing)
		controller.advance(resource, 0.0, true, FACING_VECTORS[facing], 0.125, false)
		check(controller.animation == StringName("walk_" + facing) and controller.frame == 3,
			"Sprint to walk preserves the same contact phase for %s" % facing)
	controller.advance(resource, 0.06, false, Vector2.ZERO, 0.0, false)
	check(controller.frame == 2, "Stopping gathers the feet in the nearest passing pose")
	controller.advance(resource, 0.06, false, Vector2.ZERO, 0.0, false)
	check(controller.animation == &"idle_se" and controller.frame == 0 and is_equal_approx(controller.phase, 0.25),
		"Stopping reaches matching neutral in at most two pose changes")
	controller.advance(resource, 0.0, true, Vector2(1, 1), 0.0, false)
	check(controller.frame == 2 and controller.animation == &"walk_se",
		"Restart resumes the gathered-foot phase retained during idle")
	controller.advance(resource, 0.0, true, Vector2.RIGHT, 0.2, false)
	controller.advance(resource, 0.0, true, Vector2.from_angle(deg_to_rad(24)), 0.2, false)
	check(controller.facing == &"e", "Small direction jitter does not flicker adjacent views")


func check_input_directions() -> void:
	var appearance: Node2D = player.get_node("Appearance")
	for facing: String in FACING_VECTORS:
		var vector: Vector2 = FACING_VECTORS[facing]
		set_direction_input(vector, true)
		await frames(60)
		check(appearance.actor_animation == StringName("walk_" + facing),
			"Real WASD movement selects %s" % facing)
		check(absf(player.get_speed_u() - player.walk_speed_u) < 0.01,
			"%s walking has normalized speed, including diagonals" % facing)
		Input.action_press("sprint")
		await frames(45)
		check(appearance.actor_animation == StringName("sprint_" + facing),
			"Real sprint movement selects %s" % facing)
		check(absf(player.get_speed_u() - player.sprint_speed_u) < 0.02,
			"%s sprinting has normalized speed, including diagonals" % facing)
		Input.action_release("sprint")
		set_direction_input(vector, false)
		await frames(45)
		check(appearance.actor_animation == StringName("idle_" + facing),
			"Real stop retains matching %s idle" % facing)


func set_direction_input(direction: Vector2, pressed: bool) -> void:
	var actions: Array[String] = []
	if direction.x < 0: actions.append("move_left")
	if direction.x > 0: actions.append("move_right")
	if direction.y < 0: actions.append("move_up")
	if direction.y > 0: actions.append("move_down")
	for action in actions:
		if pressed: Input.action_press(action)
		else: Input.action_release(action)
