extends Node
## Show-floor flow on the production scenes: fast reset, idle timer, attract mode, safety killzones,
## the 1080p lock and the 2 m text floor.

const World := preload("res://tutorial/world.gd")
const Attract := preload("res://tutorial/attract_mode.gd")

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

func scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""

func wait_for_scene(path: String, limit := 600) -> void:
	for i in range(limit):
		await frames(1)
		if scene_path() == path:
			break
	await frames(4)

func key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	return event

func button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event

## Every string on `root` must clear the floor. Nothing that shows text may slip under it.
func check_text_floor(root: Node, screen: String, skip: Node = null) -> void:
	var seen := 0
	for node in root.find_children("*", "", true, false):
		if skip != null and (node == skip or skip.is_ancestor_of(node)):
			continue
		if (node is Label or node is Button) and node.text != "":
			seen += 1
			var size: int = node.get_theme_font_size("font_size")
			check(size >= UIPalette.MIN_TEXT_SIZE, "%s: '%s' is %d, under the 2 m floor" % [screen, node.text, size])
	check(seen > 0, "%s shows text to measure" % screen)

func start_game() -> Node:
	get_tree().change_scene_to_file(Kiosk.GAME_SCENE)
	await wait_for_scene(Kiosk.GAME_SCENE)
	var game := get_tree().current_scene
	while not game.dialogue.is_empty():
		game.advance_dialogue()
	return game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")

func run() -> void:
	check_display_lock()
	# The runner sits beside the scenes it drives, so scene changes cannot free it.
	get_tree().current_scene = null
	get_tree().change_scene_to_file(Kiosk.TITLE_SCENE)
	await wait_for_scene(Kiosk.TITLE_SCENE)
	check(Kiosk.idle_seconds == 60.0, "The idle timer is 60 seconds")
	await check_input_filter()
	await check_idle_and_attract()
	await check_fast_reset()
	await check_killzones()
	await check_readability()
	finish()

func check_display_lock() -> void:
	check(ProjectSettings.get_setting("display/window/size/window_width_override") == 1920
		and ProjectSettings.get_setting("display/window/size/window_height_override") == 1080, "The window opens at 1920x1080")
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1280
		and ProjectSettings.get_setting("display/window/size/viewport_height") == 720, "The canvas stays 1280x720, so framing and layout are unchanged")
	check(not ProjectSettings.get_setting("display/window/size/resizable"), "The window cannot be resized")
	check(get_window().content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "Other aspect ratios letterbox instead of showing more of the world")

func check_input_filter() -> void:
	Kiosk._idle_time = 10.0
	var drift := InputEventMouseMotion.new()
	drift.relative = Vector2(1, 0)
	Kiosk._on_window_input(drift)
	var stick := InputEventJoypadMotion.new()
	stick.axis_value = 0.1
	Kiosk._on_window_input(stick)
	check(Kiosk._idle_time >= 10.0, "Mouse jitter and stick drift are not a visitor")
	drift.relative = Vector2(30, 0)
	Kiosk._on_window_input(drift)
	check(Kiosk._idle_time < 1.0, "A real mouse move restarts the idle timer")
	Input.action_press("move_right")
	Kiosk._idle_time = 10.0
	await frames(2)
	check(Kiosk._idle_time < 1.0, "A held key counts as someone at the booth")
	Input.action_release("move_right")

func check_idle_and_attract() -> void:
	Kiosk.idle_seconds = 0.3
	await wait_for_scene(Kiosk.ATTRACT_SCENE)
	check(scene_path() == Kiosk.ATTRACT_SCENE, "Idling on the title opens attract mode")
	var attract := get_tree().current_scene
	for i in range(900):
		await frames(1)
		if attract.game != null:
			break
	check(attract.game != null, "Attract mode loads the real game")
	check_text_floor(attract.get_child(0), "Attract overlay")
	await frames(60)
	var game: Node2D = attract.game
	var start: Vector2 = attract.SHOTS[0].route[0]
	check(game.zone == "hallway" and game.player.position.x > start.x + 20.0, "She walks the first shot on real input")
	check(not game.hud.visible and game.flashlight.is_on, "The HUD is hidden and her light is on")
	check(not game.complete and game.dialogue.is_empty(), "The story stays asleep")
	check(Kiosk._idle_time == 0.0, "Attract mode does not time itself out")
	attract._shot_clock = attract._shot.time
	await frames(90)
	check(game.zone == "forest", "The reel moves on to the next shot")
	attract._shot_clock = attract._shot.time
	await frames(90)
	check(game.zone == "house" and game.entity.active and game.entity.visible, "The last shot brings out the entity")
	game.entity.global_position = game.player.global_position
	await frames(10)
	check(not GameState.is_dead and GameOverUi.screen == null, "A catch in attract mode never reaches the game over screen")
	attract._shot_clock = attract._shot.time
	await frames(90)
	check(game.zone == "hallway" and not game.attack_finished, "The reel loops and the house calms down again")
	Kiosk._on_window_input(key(KEY_SPACE))
	await wait_for_scene(Kiosk.TITLE_SCENE)
	check(scene_path() == Kiosk.TITLE_SCENE, "Any input wakes the title")
	for action in Attract.ACTIONS:
		check(not Input.is_action_pressed(action), "Attract mode leaves %s released" % action)
	# A run left alone goes the same way, from anywhere in it.
	Kiosk.idle_seconds = 60.0
	var run := await start_game()
	run._toggle_pause()
	Kiosk.idle_seconds = 0.3
	await wait_for_scene(Kiosk.ATTRACT_SCENE)
	check(scene_path() == Kiosk.ATTRACT_SCENE, "Idling on the pause menu opens attract mode")
	check(not get_tree().paused and not PauseMenu.is_open, "Leaving a paused run clears the pause")
	Kiosk.idle_seconds = 60.0
	Kiosk._on_window_input(button(JOY_BUTTON_A))
	await wait_for_scene(Kiosk.TITLE_SCENE)
	check(scene_path() == Kiosk.TITLE_SCENE, "A gamepad button wakes the title")

func check_fast_reset() -> void:
	var game := await start_game()
	var reset_key := key(KEY_R)
	game._input(reset_key)
	check(not game.resetting, "In the shipping run R no longer restarts the checkpoint")
	check(InputMap.action_has_event("fast_reset", reset_key), "R is bound to fast reset")
	Kiosk._on_window_input(reset_key)
	await wait_for_scene(Kiosk.TITLE_SCENE)
	check(scene_path() == Kiosk.TITLE_SCENE, "R drops the run to the title")
	game = await start_game()
	game._toggle_pause()
	Kiosk._on_window_input(button(JOY_BUTTON_BACK))
	await wait_for_scene(Kiosk.TITLE_SCENE)
	check(scene_path() == Kiosk.TITLE_SCENE and not get_tree().paused and not PauseMenu.is_open, "Select resets from the pause menu")
	game = await start_game()
	GameState.kill_player()
	await frames(2)
	check(GameOverUi.screen != null, "Game over screen is up")
	Kiosk._on_window_input(key(KEY_R))
	await wait_for_scene(Kiosk.TITLE_SCENE)
	await frames(4)
	check(scene_path() == Kiosk.TITLE_SCENE and not GameState.is_dead and not is_instance_valid(GameOverUi.screen), "R resets from the game over screen")
	Kiosk._on_window_input(key(KEY_R))
	await frames(4)
	check(scene_path() == Kiosk.TITLE_SCENE, "R on the title stays on the title")
	# Test rigs load the game beside the runner and keep R as a checkpoint restart.
	var rig: Node = load(Kiosk.GAME_SCENE).instantiate()
	rig.test_mode = true
	add_child(rig)
	await frames(3)
	rig._input(key(KEY_R))
	check(rig.resetting, "Test rigs keep R as a checkpoint restart")
	rig.queue_free()
	await frames(10)

func check_killzones() -> void:
	var game := await start_game()
	var zones: Node = game.get_node("SafetyKillzones")
	check(zones.get_child_count() == World.REGIONS.size() * 4, "Every zone is framed on all four sides")
	for zone in World.REGIONS:
		var region: Rect2 = World.REGIONS[zone]
		for marker in game.world.nodes_in(zone, "Markers"):
			check(region.grow(zones.MARGIN - 1.0).has_point(marker.global_position), "%s/%s sits clear of the killzones" % [zone, marker.name])
	var safe: Vector2 = game.player.position
	var region: Rect2 = World.REGIONS["bedroom"]
	for escape in [Vector2(region.get_center().x, region.end.y + 150.0), Vector2(region.end.x + 150.0, region.get_center().y),
			Vector2(region.get_center().x, region.position.y - 150.0), Vector2(region.position.x - 150.0, region.get_center().y)]:
		game.player.position = escape
		await frames(6)
		check(game.resetting, "Leaving the level at %s trips a killzone" % escape)
		for i in range(90):
			await frames(1)
			if not game.resetting:
				break
		check(not game.resetting and game.player.position == safe and game.zone == "bedroom", "The player is back at the checkpoint after %s" % escape)
	check(not GameState.is_dead, "A killzone is a safety net, not a death")
	Kiosk.go_to_title()
	await wait_for_scene(Kiosk.TITLE_SCENE)

func check_readability() -> void:
	var menu := get_tree().current_scene
	for page in ["main", "controls", "audio"]:
		menu._show_page(page)
		await frames(2)
		check_text_floor(menu, "Main menu " + page)
	var game := await start_game()
	check_text_floor(game.hud, "HUD", game.hud.help_panel)
	check_text_floor(PauseMenu, "Pause menu")
	game._toggle_pause()
	for page in PauseMenu._pages:
		PauseMenu._show_page(page)
		await frames(3)
		var panel: Rect2 = PauseMenu._panel.get_global_rect()
		check(get_viewport().get_visible_rect().encloses(panel), "The pause %s page fits on screen" % page)
		for node in (PauseMenu._pages[page] as Control).find_children("*", "Control", true, false):
			check(panel.encloses(node.get_global_rect()), "Pause %s keeps %s inside its panel" % [page, node.name])
	game._toggle_pause()
	check_text_floor(LoadingScreen, "Loading screen")
	GameState.kill_player()
	await frames(2)
	check_text_floor(GameOverUi.screen, "Game over")
	Kiosk.go_to_title()
	await wait_for_scene(Kiosk.TITLE_SCENE)

func finish() -> void:
	print("[Kiosk tests] %d/%d passed" % [checks - failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
