extends Node

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	# Keep the runner alive while exercising the real scene replacement.
	get_tree().current_scene = null
	var menu = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await frames(4)
	check(menu._pages["main"].visible, "Production entry opens the main menu")
	menu._pages["main"].get_child(1).pressed.emit()
	await frames(2)
	check(menu._pages["controls"].visible, "Controls are reachable from the menu")
	menu._show_page("audio")
	var slider: HSlider = menu._pages["audio"].get_child(0).get_child(1)
	slider.value = 0.5
	var chosen_volume := AudioServer.get_bus_volume_db(0)
	menu._show_page("main")
	menu._pages["main"].get_child(0).pressed.emit()
	check(LoadingScreen._root.visible, "Play opens the loading screen")
	for i in range(600):
		await frames(1)
		if not is_instance_valid(menu) and get_tree().current_scene != null:
			break
	var game = get_tree().current_scene
	if game == null or is_instance_valid(menu):
		check(false, "Loading reaches the playable tutorial within ten seconds")
		finish()
		return
	await frames(4)
	check(game.scene_file_path == "res://tutorial/tutorial.tscn" and game.zone == "bedroom", "Play loads the production bedroom")
	check(not LoadingScreen._root.visible, "Loading overlay releases gameplay")
	while not game.dialogue.is_empty():
		game.advance_dialogue()
	var start: Vector2 = game.player.position
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	check(game.player.position.x > start.x + 10, "Real movement works after the menu transition")
	game._toggle_pause()
	await frames(3)
	check(get_tree().paused and PauseMenu.is_open, "Pause opens during gameplay")
	var paused_position: Vector2 = game.player.position
	Input.action_press("move_right")
	await frames(10)
	Input.action_release("move_right")
	check(game.player.position == paused_position, "Pause freezes player movement")
	PauseMenu._pages["main"].get_child(0).pressed.emit()
	check(not get_tree().paused and not PauseMenu.is_open, "Resume button releases the game")
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), chosen_volume), "Resume preserves volume selected in the main menu")
	game._toggle_pause()
	await frames(20)
	check(PauseMenu._root.visible, "Rapid resume and reopen keeps the pause menu visible")
	game.queue_free()
	get_tree().current_scene = null
	await frames(20)
	check(not get_tree().paused and not PauseMenu.is_open and not PauseMenu._root.visible, "Leaving a paused scene clears the global pause menu")
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), chosen_volume), "Leaving a paused scene restores audio volume")
	finish()

func finish() -> void:
	print("[Menu flow tests] %d/%d passed" % [checks - failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
