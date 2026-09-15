extends Node
## Fixed-camera comparison of the existing artwork under the lighting treatment.
func _ready() -> void:
	var game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	get_window().size = Vector2i(1280,720)
	game.set_process(false)
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	game.entity.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.get_node("Camera2D").position_smoothing_enabled = false
	for child in game.player.get_children():
		if child is PointLight2D: child.enabled = false
	var suffix := "before" if OS.get_cmdline_user_args().has("--baseline") else "after"
	var shots := {
		"bedroom":Vector2(620,270), "hallway":Vector2(2110,450),
		"forest":Vector2(3810,480), "house":Vector2(6230,455), "loop":Vector2(7675,460)
	}
	for zone in shots:
		game.enter_zone(zone,shots[zone])
		game.player.get_node("Camera2D").force_update_scroll()
		game.hud.subtitle.text = ""
		game.hud.prompt.text = ""
		for i in range(4): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://docs/organic-tutorial/lighting-polish/%s-%s.png"%[zone,suffix])
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
