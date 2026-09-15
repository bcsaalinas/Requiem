extends Node
## Measure rendered foreground against the same scene with that sprite hidden.
var game: Node2D
var failed := false

func frame() -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _ready() -> void:
	game=preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode=true
	add_child(game)
	get_window().size=Vector2i(1280,800)
	game.set_process(false)
	game.player.process_mode=Node.PROCESS_MODE_DISABLED
	game.entity.process_mode=Node.PROCESS_MODE_DISABLED
	for node in game.player.get_children():
		if node is PointLight2D: node.enabled=false
	var actor: Node2D
	for node in game.player.get_children():
		if node.get_script()==game.Art: actor=node
	actor.set_process(false)
	game.hud.banner.text=""
	await frame()
	await frame()
	await measure("player-bedroom",actor.focal_sprite,1.7)
	await measure("battery-bedroom",game.world.props["battery"].focal_sprite,1.5)
	(await frame()).save_png("res://docs/organic-tutorial/readability/bedroom-after.png")
	game.enter_zone("forest")
	game.hud.banner.text=""
	await frame()
	await frame()
	await measure("player-forest",actor.focal_sprite,1.7)
	await measure("forest-rocks",game.world.props["forest_rocks"].focal_sprite,1.5)
	(await frame()).save_png("res://docs/organic-tutorial/readability/forest-after.png")
	game.enter_zone("house")
	game.hud.banner.text=""
	game.player.position=Vector2(5890,400)
	game.entity.position=Vector2(6000,400)
	game.entity.show()
	game.entity.active=true
	game.entity._update_readability()
	if game.entity.appearance.threat_pressure>0:
		failed=true
		push_error("A wall must prevent the foreground threat accent")
	game.player.position=Vector2(6070,640)
	game.entity.position=Vector2(6130,600)
	game.entity._update_readability()
	if game.entity.appearance.threat_pressure<.8:
		failed=true
		push_error("An unobstructed nearby threat must become readable")
	game.player.get_node("Camera2D").reset_smoothing()
	await frame()
	await frame()
	await measure("nearby-threat",game.entity.appearance.focal_sprite,1.5)
	(await frame()).save_png("res://docs/organic-tutorial/readability/nearby-threat.png")
	print("[Readability] ","FAIL" if failed else "PASS — foreground contrast and threat occlusion")
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failed else 0)

func measure(id: String, sprite: Sprite2D, minimum_ratio: float) -> void:
	if not sprite.visible or sprite.texture==null:
		failed=true
		push_error(id+" focal sprite is missing")
		return
	var foreground := await frame()
	sprite.hide()
	var background := await frame()
	sprite.show()
	var atlas := sprite.texture.get_image()
	var inverse := sprite.get_global_transform_with_canvas().affine_inverse()
	var bounds: Vector4=sprite.material.get_shader_parameter("atlas_bounds")
	var front := 0.0
	var back := 0.0
	var samples := 0
	for y in range(foreground.get_height()):
		for x in range(foreground.get_width()):
			var uv := (inverse*Vector2(x+.5,y+.5)+sprite.region_rect.position)/Vector2(atlas.get_size())
			if uv.x<bounds.x or uv.y<bounds.y or uv.x>=bounds.z or uv.y>=bounds.w: continue
			var pixel := Vector2i(uv*Vector2(atlas.get_size()))
			if atlas.get_pixelv(pixel).a<.95: continue
			front+=luminance(foreground.get_pixel(x,y))
			back+=luminance(background.get_pixel(x,y))
			samples+=1
	var ratio := front/maxf(back,.001)
	print("[Readability] ",id," foreground/background = ",snappedf(ratio,.01)," over ",samples," opaque sprite pixels")
	if samples<20 or ratio<minimum_ratio:
		failed=true
		push_error(id+" does not separate sufficiently from its actual background")

func luminance(color: Color) -> float:
	return color.r*.2126+color.g*.7152+color.b*.0722
