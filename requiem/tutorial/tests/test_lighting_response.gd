extends Node
var game: Node2D
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frame() -> Image:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func sprite_luminance(picture: Image, sprite: Sprite2D) -> float:
	var atlas := sprite.texture.get_image()
	var transform := sprite.get_global_transform_with_canvas()
	var bounds: Vector4 = sprite.material.get_shader_parameter("atlas_bounds")
	var total := 0.0
	var count := 0
	for y in range(int(bounds.y*atlas.get_height()),int(bounds.w*atlas.get_height()),3):
		for x in range(int(bounds.x*atlas.get_width()),int(bounds.z*atlas.get_width()),3):
			if atlas.get_pixel(x,y).a<.95: continue
			var local := Vector2(x,y)-sprite.region_rect.position
			var sample_at := Vector2i(transform*local)
			if Rect2i(Vector2i.ZERO,picture.get_size()).has_point(sample_at):
				var c := picture.get_pixelv(sample_at)
				total += c.r*.2126+c.g*.7152+c.b*.0722
				count += 1
	check(count>20,"Lighting measurement contains visible opaque sprite pixels")
	return total/maxi(count,1)

func _ready() -> void:
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	get_window().size = Vector2i(1280,720)
	game.set_process(false)
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	game.entity.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.get_node("Camera2D").position_smoothing_enabled = false
	for child in game.player.get_children():
		if child is PointLight2D: child.enabled = false
	game.enter_zone("bedroom",Vector2(620,270))
	var actor: Node2D
	for child in game.player.get_children():
		if child.get_script()==game.Art: actor=child
	var lit := await frame()
	var actor_lit := sprite_luminance(lit,actor.focal_sprite)
	var pickup_lit := sprite_luminance(lit,game.world.props.battery.focal_sprite)
	for child in game.world.scene_nodes:
		if child is PointLight2D: child.enabled = false
	var dark := await frame()
	var actor_dark := sprite_luminance(dark,actor.focal_sprite)
	var pickup_dark := sprite_luminance(dark,game.world.props.battery.focal_sprite)
	print("[Light response] player lit/dark ",actor_lit/actor_dark,"; battery lit/dark ",pickup_lit/pickup_dark)
	check(actor_lit>actor_dark*2.0,"Player body responds to actual lighting")
	check(pickup_lit>pickup_dark*2.0,"Pickup body responds to actual lighting")
	check(not game.world.landmarks["BedroomDeskLight"].get_node("PropLight").enabled,"Prop illumination switches off with its source")
	lit.save_png("res://docs/organic-tutorial/lighting-polish/light-response-on.png")
	dark.save_png("res://docs/organic-tutorial/lighting-polish/light-response-off.png")
	# Candle story changes and flashlight transforms share the original sources.
	game.world.set_house_danger(true)
	await frame()
	var altar: PointLight2D = game.world.landmarks["AltarLeftLight"]
	var face_light: PointLight2D = altar.get_node("PropLight")
	check(is_equal_approx(face_light.energy,altar.energy) and face_light.color==altar.color,"Aftermath changes both floor and prop lighting")
	game.flashlight.enabled=true
	game.flashlight.rotation=.7
	game.flashlight.scale=Vector2(1,.45)
	await frame()
	var beam: PointLight2D = game.flashlight.get_node("PropLight")
	check(beam.global_transform.is_equal_approx(game.flashlight.global_transform),"Prop light preserves flashlight aim and held-breath cone width")
	# The physical door/window blockers remain on the layer used by both lighting passes.
	for body in [game.world.props.entry_collision,game.world.window_body]:
		for child in body.get_children():
			if child is LightOccluder2D:
				check(child.occluder_light_mask==1,"Closed entrance occludes floor and prop illumination")
	# Render receivers on the far side of an actual house partition, then remove only its shadow.
	game.flashlight.enabled=false
	game.enter_zone("house",Vector2(6000,510))
	var probe_light: PointLight2D = game.world.lamp(Vector2(5890,450),Color.WHITE,3.0,1.5)
	var probes: Array[ColorRect] = []
	for mask in [1,2]:
		var receiver := ColorRect.new()
		receiver.position = Vector2(6000,430+mask*20)
		receiver.size = Vector2(12,12)
		receiver.light_mask = mask
		game.world.add_child(receiver)
		probes.append(receiver)
	var wall_shadow: LightOccluder2D
	for body in game.world.scene_nodes:
		if body is StaticBody2D and body.position.is_equal_approx(Vector2(5940,260)):
			for child in body.get_children():
				if child is LightOccluder2D: wall_shadow = child
	check(wall_shadow!=null,"Partition shadow fixture exists")
	var blocked := await frame()
	wall_shadow.hide()
	var unblocked := await frame()
	for receiver in probes:
		var pixel := Vector2i(game.get_canvas_transform()*(receiver.position+Vector2(6,6)))
		var shadow_value := blocked.get_pixelv(pixel).get_luminance()
		var clear_value := unblocked.get_pixelv(pixel).get_luminance()
		print("[Wall occlusion] layer ",receiver.light_mask," blocked ",shadow_value," open ",clear_value)
		check(clear_value>shadow_value*2.0,"Partition blocks rendered light on receiver layer %d"%receiver.light_mask)
	wall_shadow.show()
	probe_light.queue_free()
	game.queue_free()
	await get_tree().process_frame
	print("[Light response] ",checks-failures,"/",checks," passed")
	get_tree().quit(1 if failures else 0)
