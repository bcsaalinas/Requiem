extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	var game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = not OS.get_cmdline_user_args().has("--fullscreen-check")
	add_child(game)
	if not game.test_mode:
		await get_tree().create_timer(1.0).timeout
		check(get_window().mode==Window.MODE_FULLSCREEN,"Normal play starts fullscreen")
		game._toggle_fullscreen()
		await get_tree().create_timer(1.0).timeout
		check(get_window().mode==Window.MODE_WINDOWED,"Fullscreen toggle returns to windowed play")
		while not game.dialogue.is_empty(): game.advance_dialogue()
	game.player.set_physics_process(false)
	var camera: Camera2D = game.player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	for resolution in [Vector2i(1280,720),Vector2i(1280,800),Vector2i(1920,800)]:
		get_window().size = resolution
		for i in range(5): await get_tree().process_frame
		game.has_flashlight = false
		game.enter_zone("bedroom",Vector2(620,270))
		game._find_interaction()
		for i in range(5): await get_tree().process_frame
		var viewport: Rect2 = get_viewport().get_visible_rect()
		print("[Presentation] ",resolution," root ",game.hud.root.size," meters ",game.hud.breath.get_global_rect()," inventory ",game.hud.inventory.get_global_rect())
		check(viewport.encloses(game.hud.prompt.get_global_rect()),"Interaction prompt fits viewport")
		check(game.hud.breath.get_global_rect().position.y > viewport.size.y-80,"Meters stay at the bottom")
		var world_view := Rect2(game.get_canvas_transform().affine_inverse()*Vector2.ZERO,viewport.size/camera.zoom)
		check(game.World.REGIONS.bedroom.grow(1).encloses(world_view),"Camera does not show outside the room")
		check(viewport.has_point(game.get_canvas_transform()*game.player.position),"Player remains in view")
		game.has_flashlight = true
		game.batteries = 2
		game.thrower.rocks = 3
		game.hud.update_inventory(true,2,3)
		game.hud.subtitle.text = ""
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://docs/organic-tutorial/screenshots/clean-%dx%d.png"%[resolution.x,resolution.y])
		var lines: Array[String] = ["ELI: I'm at my aunt's old house. Follow the yellow trail marks. Bring a light."]
		game.show_dialogue(lines)
		for i in range(3): await get_tree().process_frame
		check(viewport.encloses(game.hud.subtitle.get_global_rect()),"Dialogue fits viewport")
		check(not game.hud.subtitle.get_global_rect().intersects(game.hud.prompt.get_global_rect()),"Continue prompt does not overlap dialogue")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://docs/organic-tutorial/screenshots/dialogue-%dx%d.png"%[resolution.x,resolution.y])
		game.advance_dialogue()
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	check(get_tree().paused and game.hud.help_panel.visible,"Escape opens pause menu")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/organic-tutorial/screenshots/pause-menu.png")
	game.hud.resume_requested.emit()
	check(not get_tree().paused,"Resume button unpauses gameplay")
	game.queue_free()
	await get_tree().process_frame
	print("[Presentation] ","PASS" if failures==0 else "FAIL", " — responsive camera, prompts, dialogue and pause")
	get_tree().quit(0 if failures==0 else 1)
