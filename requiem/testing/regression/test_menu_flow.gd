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
	Preferences.storage_path = "user://requiem-menu-test-%s.cfg" % OS.get_process_id()
	Preferences.load_preferences()
	# Keep the runner alive while exercising the real scene replacement.
	get_tree().current_scene = null
	var menu = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await frames(4)
	check(menu._pages["main"].visible, "Production entry opens the main menu")
	menu._pages["main"].get_child(1).grab_focus()
	menu._pages["main"].get_child(1).pressed.emit()
	await frames(2)
	check(menu._pages["settings"].visible, "Settings is reachable from the menu")
	menu._pages["settings"].get_child(2).pressed.emit()
	await frames(2)
	check(menu._pages["controls"].visible, "Controls are reachable inside Settings")
	menu.get_node("%ControlsBack").pressed.emit()
	await frames(2)
	check(menu._pages["settings"].visible, "Controls returns to Settings")
	menu._show_page("main")
	await frames(2)
	check(menu.get_node("%SettingsButton").has_focus(), "Back restores Settings focus")
	menu.get_node("%CreditsButton").pressed.emit()
	await get_tree().create_timer(0.85).timeout
	check(is_instance_valid(menu._credits) and menu._credits.visible, "Credits scene is reachable")
	check(menu._credits.team_credits == menu.team_credits, "Credits preserves every established name and role")
	check(menu._credits.back_button.has_focus(), "Credits focuses Back for keyboard navigation")
	check(menu._credits.back_button.get_global_rect().end.y <= menu.size.y, "Credits Back stays within the viewport")
	var first_position: float = menu._credits._travel
	await get_tree().create_timer(1.0).timeout
	check(menu._credits._travel > first_position, "Credits advances automatically without input")
	menu._credits.licenses_button.pressed.emit()
	var paused_position_roll: float = menu._credits._travel
	await frames(5)
	check(menu._credits._licenses.visible and menu._credits._travel == paused_position_roll, "License reader pauses the roll")
	menu._credits.licenses_button.pressed.emit()
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	menu._credits._input(escape)
	menu._credits.request_back()
	await get_tree().create_timer(0.85).timeout
	check(not is_instance_valid(menu._credits) and menu.get_node("Column").visible, "Escape restores menu after fade")
	check(menu.get_node("%CreditsButton").has_focus(), "Returning restores Credits button focus")
	menu.get_node("%CreditsButton").pressed.emit()
	await get_tree().create_timer(0.85).timeout
	menu._credits.back_button.pressed.emit()
	await get_tree().create_timer(0.85).timeout
	check(not is_instance_valid(menu._credits), "Back button returns to menu on repeat visit")
	menu.get_node("%CreditsButton").pressed.emit()
	await get_tree().create_timer(0.85).timeout
	menu._credits._elapsed = 2.0
	menu._credits._travel = menu._credits._content_height + menu.size.y + 200
	await get_tree().create_timer(0.85).timeout
	check(not is_instance_valid(menu._credits), "Completed credits returns automatically to the menu")
	menu._show_page("quit")
	await frames(2)
	check(menu._pages["quit"].get_child(1).has_focus(), "Quit defaults to Cancel")
	menu._pages["quit"].get_child(1).pressed.emit()
	await frames(2)
	check(menu._pages["main"].visible, "Cancel keeps the application open")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	menu._unhandled_input(cancel)
	await frames(2)
	check(menu._pages["quit"].visible, "Escape on main opens confirmation")
	menu._unhandled_input(cancel)
	await frames(2)
	check(menu._pages["main"].visible, "Escape cancels Quit")
	menu._show_page("display")
	menu._fullscreen.button_pressed = true
	Preferences.set_volume("Master", 0.0)
	Preferences.load_preferences()
	check(Preferences.fullscreen and AudioServer.is_bus_mute(0), "Display and mute preferences survive reload")
	menu._fullscreen.button_pressed = false
	var real_scene: String = menu.game_scene
	menu.game_scene = "res://missing-menu-test-scene.tscn"
	menu._start_game()
	await frames(2)
	check(menu._pages["error"].visible and not LoadingScreen._root.visible, "Failed loading offers recovery")
	menu._pages["error"].get_child(2).pressed.emit()
	await frames(2)
	check(menu._pages["main"].visible, "Loading error can return to main")
	menu.game_scene = real_scene
	menu._show_page("audio")
	var slider: HSlider = menu._pages["audio"].get_child(0).get_child(1)
	slider.value = 0.5
	var chosen_volume := AudioServer.get_bus_volume_db(0)
	menu._show_page("main")
	menu._pages["main"].get_child(0).pressed.emit()
	check(LoadingScreen._root.visible, "Play opens the loading screen")
	menu._start_game()
	check(menu._starting, "Duplicate Play remains in the same transition")
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
	DirAccess.remove_absolute(Preferences.storage_path)
	get_tree().quit(0 if failures == 0 else 1)
