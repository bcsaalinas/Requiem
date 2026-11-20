extends Node
var game: Node2D
var checks := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await get_tree().process_frame
	game.dialogue.clear()
	game.sequence = ""
	var map: Node = game.field_map
	var mini: Control = map.sheet
	check(mini.is_visible_in_tree(), "Minimap is visible without opening a menu")
	check(mini.size.x <= 240 and mini.size.y <= 210, "Minimap stays compact")
	check(mini.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Minimap does not intercept aiming or clicks")
	check(not get_tree().paused and not PauseMenu.is_open, "Minimap does not pause gameplay")
	check(game.hud.root.get_node_or_null("MapButton") == null, "Full-screen map button removed")
	check(not game.has_method("_toggle_map"), "Full-screen map entry point removed")
	check(map.explored.has("bedroom") and not map.explored.has("house"), "Exploration starts locally")
	var terrain: Control = mini.terrain
	var fixed_landmark: Vector2 = game.player.global_position + Vector2(80, 0)
	var before: Vector2 = terrain.project_point(fixed_landmark)
	game.player.global_position += Vector2(40, 0)
	mini.refresh()
	check(terrain.project_point(game.player.global_position).is_equal_approx(terrain.size / 2), "Player remains centred")
	check(terrain.project_point(fixed_landmark).is_equal_approx(before - Vector2(40 * terrain.ZOOM, 0)), "Terrain scrolls opposite to player movement")
	var map_key := InputEventKey.new()
	map_key.physical_keycode = KEY_M
	map_key.pressed = true
	game._input(map_key)
	check(not get_tree().paused, "M no longer opens or pauses a large map")
	game.enter_zone("house", Vector2(5744, 830), false)
	map._process(0.2)
	check(map.selected == "house", "Zone transitions immediately update minimap")
	check(map.known(Vector2(544, 830), "house"), "Player location is explored")
	check(not map.known(Vector2(1100, 160), "house"), "Unseen distant rooms stay hidden")
	game.hud.hide()
	check(not mini.is_visible_in_tree(), "Minimap follows HUD visibility")
	game.hud.show()
	game._toggle_pause()
	check(get_tree().paused and PauseMenu.is_open, "Normal pause menu remains functional")
	game._toggle_pause()
	check(not get_tree().paused, "Normal resume remains functional")
	if "--capture-map" in OS.get_cmdline_user_args():
		game.has_flashlight = true
		game.flashlight.battery_percent = 100
		game.flashlight.enabled = true
		game.player.global_position = Vector2(5808, 480)
		game.world.rooms("house").sync_to(game.player.global_position)
		map.record_position()
		game.entity.active = false
		game._frame_camera()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/requiem-minimap-before.png")
		game.player.global_position += Vector2(100, 0)
		map.record_position()
		mini.refresh()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/requiem-minimap-after.png")
	game.queue_free()
	await get_tree().process_frame
	for player in MusicDirector.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	print("[Minimap tests] %d/%d passed" % [checks - failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)
