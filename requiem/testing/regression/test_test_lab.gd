extends Node

var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://tutorial/tutorial.tscn", "F5 retains the playable tutorial")
	check(not ProjectSettings.has_setting("autoload/NoiseDebug"), "Production has no noise-debug autoload")
	var lab = preload("res://testing/test_lab.tscn").instantiate()
	add_child(lab)
	check(lab.menu.visible and not lab.toolbar.visible, "Lab opens at its launcher")
	await lab.launch(lab.TUTORIAL)
	await frames(8)
	check(lab.active_scene.zone == "bedroom" and not lab.active_scene.has_node("CameraTestOverlay"), "Normal tutorial has no comparison overlay")
	check(not lab.noise.enabled, "Noise overlay starts off")
	lab.active_scene._toggle_pause()
	check(get_tree().paused, "Tutorial can pause inside the lab")
	await lab.show_menu()
	check(not get_tree().paused and lab.active_scene == null and lab.menu.visible, "Returning from pause clears the scene and resumes the lab")
	await lab.launch(lab.COMPARISON)
	await frames(12)
	lab.active_scene.jump_to_zone(2)
	await frames(4)
	check(lab.active_scene.zone == "forest", "Comparison area shortcuts still work")
	check(get_viewport().get_camera_2d() == lab.active_scene.camera_rig.camera, "Comparison owns the active camera")
	await lab.launch(lab.SANDBOX)
	await frames(20)
	var sandbox = lab.active_scene
	check(sandbox.get_node("Map").get_used_cells().size() > 0 and sandbox.get_node("NavigationRegion2D").navigation_polygon != null, "Mechanics sandbox paints before navigation initializes")
	check(sandbox.get_node("Props").get_child_count() > 0, "Sandbox contains the real shared altar")
	check(sandbox.get_node("Player/ActionState").has_flashlight, "Sandbox starts equipped")
	check(sandbox.get_node("Player/Throw").get_script() == preload("res://player/throw.gd"), "Sandbox uses shared throwables instead of the tutorial inventory adapter")
	await lab.show_menu()
	check(not GameState.is_dead and not GameState.is_praying and GameOverUi.label.text == "", "Scenario exit clears shared death and prayer state")
	check(not lab.noise.enabled and not lab.noise.is_processing_unhandled_input(), "Debug keyboard handling is disabled in the menu")
	lab.queue_free()
	await frames(3)
	print("[Test Lab checks] %d/%d passed" % [checks - failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
