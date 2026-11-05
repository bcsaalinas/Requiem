extends Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func wait_frames(count := 4) -> void:
	for i in count:
		await get_tree().process_frame
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")
func run() -> void:
	get_tree().current_scene = null
	get_tree().change_scene_to_file(Exhibit.MENU)
	await get_tree().scene_changed
	await wait_frames()
	Exhibit._show_attract()
	check(Exhibit.attracting and Exhibit._overlay.visible, "Attract screen is visible")
	check(get_window().content_scale_size == Vector2i(1920,1080) and get_window().content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT, "Render resolution is fixed at 1080p")
	check(get_window().content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP and not ProjectSettings.get_setting("display/window/size/resizable"), "Aspect ratio and window resize are locked")
	var drift := InputEventJoypadMotion.new()
	drift.axis_value = 0.12
	check(not Exhibit._meaningful_input(drift), "Small controller drift does not wake the build")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	Exhibit._input(key)
	check(not Exhibit.attracting and get_tree().current_scene.scene_file_path == Exhibit.MENU, "First input dismisses attract without starting gameplay")
	Exhibit.idle_seconds = 51
	Exhibit._process(0.01)
	check(Exhibit._warning.visible, "Last ten idle seconds show a warning")
	Exhibit._input(key)
	check(Exhibit.idle_seconds == 0 and not Exhibit._warning.visible, "Input cancels the warning")
	get_tree().current_scene._open_credits()
	await get_tree().create_timer(0.5).timeout
	Exhibit.idle_seconds = 59.99
	Exhibit._process(0.02)
	await get_tree().create_timer(0.5).timeout
	check(Exhibit.attracting and not is_instance_valid(get_tree().current_scene._credits), "Sixty idle seconds clears subpages and returns to attract")
	Exhibit.dismiss_attract()
	get_tree().change_scene_to_file(Exhibit.GAME)
	await get_tree().scene_changed
	await wait_frames(10)
	var game = get_tree().current_scene
	check(game.hud.breath.get_global_rect().end.y <= 1080, "Vital meters remain inside the 1080p frame")
	game._toggle_pause()
	var old_id: int = game.get_instance_id()
	key.keycode = KEY_R
	Exhibit._input(key)
	await get_tree().create_timer(0.8).timeout
	game = get_tree().current_scene
	check(game.get_instance_id() != old_id and game.zone == "bedroom", "R resets to a fresh bedroom in under one second")
	check(not get_tree().paused and not PauseMenu.is_open, "Fast reset clears pause")
	while not game.dialogue.is_empty():
		game.advance_dialogue()
	game._begin_game_over()
	old_id = game.get_instance_id()
	var select := InputEventJoypadButton.new()
	select.button_index = JOY_BUTTON_BACK
	select.pressed = true
	Exhibit._input(select)
	await get_tree().create_timer(0.8).timeout
	check(get_tree().current_scene.get_instance_id() != old_id and not is_instance_valid(GameOverUi.screen), "Select resets from game-over and clears overlay")
	get_tree().current_scene._toggle_pause()
	Exhibit.idle_seconds = 59.99
	Exhibit._process(0.02)
	await get_tree().create_timer(0.5).timeout
	check(Exhibit.attracting and not get_tree().paused, "Idle timeout also recovers a paused game")
	print("[Exhibit tests] %d/%d passed" % [checks-failures,checks])
	get_tree().quit(0 if failures == 0 else 1)
