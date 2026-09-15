extends Node
## Rendered verification: environment readability comes from static fixtures alone.
func _ready() -> void:
	var game=preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode=true
	add_child(game)
	get_window().size=Vector2i(1280,800)
	for child in game.player.get_children():
		if child is PointLight2D: child.enabled=false
	for zone in ["bedroom","hallway","forest","house","loop"]:
		game.enter_zone(zone)
		game.encounter_grace=999
		game.banner_time=0
		game.hud.banner.text=""
		if zone=="house": game.player.position=Vector2(5990,540)
		game.player.get_node("Camera2D").reset_smoothing()
		for i in range(5): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame: Image=get_viewport().get_texture().get_image()
		frame.save_png("res://docs/organic-tutorial/lighting/"+zone+".png")
		if zone=="hallway":
			var safe:=brightness(frame,game.get_canvas_transform()*Vector2(2110,455))
			var danger:=brightness(frame,game.get_canvas_transform()*Vector2(1930,348))
			print("[Lighting] Hall recovery luminance ",safe,"; listening crossing ",danger)
			if safe<danger*2.0:
				push_error("Recovery pocket must visibly outshine the listening crossing")
				get_tree().quit(1)
				return
		if zone=="house":
			game.attack_finished=true
			game.world.set_house_danger(true)
			for i in range(3): await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://docs/organic-tutorial/lighting/house-after.png")
			game.attack_finished=false
	print("[Lighting] PASS — static-only captures saved for all five spaces")
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()

func brightness(frame: Image, center: Vector2) -> float:
	var total:=0.0
	for y in range(-5,6):
		for x in range(-5,6):
			var p:=Vector2i(center)+Vector2i(x,y)
			var color:=frame.get_pixel(clampi(p.x,0,frame.get_width()-1),clampi(p.y,0,frame.get_height()-1))
			total+=color.r*.2126+color.g*.7152+color.b*.0722
	return total/121.0
