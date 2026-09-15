extends Node

func _ready() -> void:
	var game=preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode=true
	add_child(game)
	get_window().size=Vector2i(1280,800)
	for zone in ["bedroom","hallway","forest","house","loop"]:
		game.enter_zone(zone)
		game.encounter_grace=999
		game.banner_time=0
		game.hud.banner.text=""
		if zone=="house": game.player.position=Vector2(6210,465)
		game.player.get_node("Camera2D").reset_smoothing()
		for i in range(5): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/private/tmp/requiem-"+zone+".png")
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
