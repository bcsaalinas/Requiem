extends Node
const CaptureOutput := preload("res://testing/tools/capture_output.gd")
## Camera integration checks. Add -- --capture to save rendered comparison frames.

var game: Node2D
var failures: Array[String] = []
var checks := 0
@export var capture_frames := false


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame


func within_region(message: String) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var inverse := game.get_canvas_transform().affine_inverse()
	var bounds: Rect2 = game.World.REGIONS[game.zone].grow(0.5)
	for corner in [Vector2.ZERO, Vector2(viewport_size.x, 0), viewport_size,
		Vector2(0, viewport_size.y)]:
		check(bounds.has_point(inverse * corner), message + " · " + str(corner))
	check(Rect2(Vector2.ZERO, viewport_size).has_point(
		game.get_canvas_transform() * game.player.global_position), message + " · player stays visible")


func capture(id: String) -> void:
	if not capture_frames: return
	await RenderingServer.frame_post_draw
	var output := CaptureOutput.path("phantom-camera/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_viewport().get_texture().get_image().save_png(output + id + ".png")


func _ready() -> void:
	capture_frames = capture_frames or OS.get_cmdline_user_args().has("--capture")
	game = preload("res://testing/experiments/phantom_tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(10)
	check(get_viewport().get_camera_2d() == game.camera_rig.camera, "Phantom camera is current")
	check(not game.player.get_node("Camera2D").enabled, "Original camera cannot compete with the rig")
	check(game.camera_rig.exploration.is_active(), "Exploration shot is selected by the addon host")
	check(not game.camera_rig.camera.position_smoothing_enabled, "Only Phantom Camera supplies damping")
	within_region("Initial bedroom framing")

	# Exercise the real player physics with the camera updating after that movement.
	Input.action_press("hold_breath")
	Input.action_press("move_right")
	var start_x: float = game.camera_rig.camera.global_position.x
	await frames(90)
	Input.action_release("move_right")
	Input.action_release("hold_breath")
	await frames(15)
	check(game.camera_rig.camera.global_position.x > start_x + 15.0, "Framed tracking follows real player movement")
	within_region("Moving player framing")
	game.player.set_physics_process(false)
	game.player.velocity = Vector2.ZERO

	for resolution in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1920, 800)]:
		get_window().size = resolution
		await frames(5)
		for area in ["bedroom", "hallway", "forest", "house", "loop"]:
			game.enter_zone(area)
			await frames(3)
			check(game.camera_rig.active_shot == "Exploration", "Area cut resets the selected shot: " + area)
			within_region("Area boundaries %s %s" % [area, resolution])

	get_window().size = Vector2i(1280, 720)
	if capture_frames: get_window().mode = Window.MODE_FULLSCREEN
	await frames(5)
	game.enter_zone("hallway", Vector2(1930, 340))
	game._tick_hallway(0.01)
	await frames(35)
	check(game.camera_rig.hallway.is_active(), "Occupied door activates hallway framing")
	within_region("Hallway door framing")
	await capture("01-hallway-phantom")
	game.set_native_camera(true)
	await frames(5)
	check(get_viewport().get_camera_2d() == game.player.get_node("Camera2D"), "Comparison switches to original camera")
	within_region("Original hallway comparison")
	await capture("02-hallway-original")
	game.set_native_camera(false)
	game.player.position = Vector2(2110, 485)
	game._tick_hallway(0.01)
	await frames(30)
	check(game.camera_rig.exploration.is_active(), "Refuge returns to exploration framing")

	game.enter_zone("house", Vector2(5870, 800))
	game._on_rock_landed(Vector2(5870, 692))
	await frames(20)
	check(game.camera_rig.reveal.is_active(), "Window impact activates group framing")
	check(game.sequence == "reveal", "Camera settles within the existing 1.15-second reveal")
	within_region("Window reveal framing")
	await capture("03-window-phantom")
	# Interrupt a live shot by leaving the area: no intermediate empty space is rendered.
	game.enter_zone("forest")
	await frames(2)
	check(game.camera_rig.exploration.is_active(), "Area cut interrupts reveal tween")
	within_region("Immediate forest cut")
	game._tick_sequence(2.0)
	await frames(2)
	check(game.camera_rig.exploration.is_active(), "Expired reveal cannot reclaim the camera after an area cut")

	game.enter_zone("house", Vector2(6230, 410))
	game.interact("friend")
	check(game.player.process_mode == Node.PROCESS_MODE_DISABLED, "Friend dialogue locks player processing")
	await frames(45)
	check(game.camera_rig.altar.is_active(), "Independent camera keeps framing the altar during dialogue")
	var friend_screen: Vector2 = game.get_canvas_transform() * game.world.props["friend"].global_position
	check(get_viewport().get_visible_rect().has_point(friend_screen), "Eli stays in the story frame")
	within_region("Altar dialogue framing")
	await capture("04-altar-phantom")
	game.set_native_camera(true)
	await frames(5)
	within_region("Original altar comparison during dialogue")
	await capture("05-altar-original")
	game.set_native_camera(false)
	await frames(45)

	# Pausing preserves both the camera and the pre-existing dialogue input lock.
	game._toggle_pause()
	var paused_transform: Transform2D = game.camera_rig.camera.global_transform
	await frames(12)
	check(game.camera_rig.camera.global_transform.is_equal_approx(paused_transform), "Pause freezes the camera")
	game._toggle_pause()
	check(game.player.process_mode == Node.PROCESS_MODE_DISABLED, "Resume preserves dialogue lock")
	while not game.dialogue.is_empty(): game.advance_dialogue()
	await frames(145)
	check(game.sequence_step == 1, "Attack reaches its original blackout timing")
	check(game.camera_rig.altar.is_active(), "Altar shot remains active through the blackout")
	await frames(85)
	check(game.attack_finished, "Camera experiment preserves attack completion")
	check(game.camera_rig.exploration.is_active(), "Attack releases the camera to exploration")
	within_region("Aftermath framing")
	await capture("06-aftermath-phantom")

	game.request_reset("Camera retry test")
	await frames(10)
	check(not game.resetting and game.camera_rig.exploration.is_active(), "Retry clears transient camera shots")
	check(not game.camera_rig.impact.is_emitting(), "Retry clears camera shake")
	within_region("Retry framing")
	game.jump_to_zone(4)
	await frames(5)
	check(game.zone == "loop" and game.camera_rig.exploration.is_active(), "Test shortcut enters the impossible room")
	check(not game.entity.active and not game.entity.visible, "Camera never tracks a hidden presence")
	within_region("Impossible room framing")
	await capture("07-loop-phantom")

	game.queue_free()
	await frames(3)
	print("[Phantom Camera tests] %d/%d passed" % [checks - failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)
