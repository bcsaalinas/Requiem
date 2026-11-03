extends Node
## Rendered lighting checks (needs a display: run_checks.py --rendered).
## One light per source, one light layer: walls (tile occlusion) and closed doors stop light,
## an open door lets it through, and story lighting changes the real lamps.
const CaptureOutput := preload("res://testing/tools/capture_output.gd")
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
	# The window may be resized by the desktop; samples must use rendered pixels.
	var transform := get_viewport().get_final_transform()*sprite.get_global_transform_with_canvas()
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

func probe_value(picture: Image, receiver: CanvasItem) -> float:
	var pixel := Vector2i(get_viewport().get_final_transform()*receiver.get_global_transform_with_canvas()*Vector2(6,6))
	return picture.get_pixelv(pixel).get_luminance()

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
	# Stand in the desk lamp's pool, next to the flashlight on the desk.
	var desk_lamp: PointLight2D = game.world.landmarks["DeskLamp"]
	game.enter_zone("bedroom",desk_lamp.global_position+Vector2(-50,30))
	var actor: Node2D
	for child in game.player.get_children():
		if child.get_script()==game.Art: actor=child
	var lit := await frame()
	var actor_lit := sprite_luminance(lit,actor.focal_sprite)
	var pickup_lit := sprite_luminance(lit,game.world.props.flashlight.focal_sprite)
	for zone_node in game.world.zones.values():
		for light in zone_node.find_children("*","PointLight2D",true,false):
			light.enabled = false
	var dark := await frame()
	var actor_dark := sprite_luminance(dark,actor.focal_sprite)
	var pickup_dark := sprite_luminance(dark,game.world.props.flashlight.focal_sprite)
	print("[Light response] player lit/dark ",actor_lit/actor_dark,"; flashlight pickup lit/dark ",pickup_lit/pickup_dark)
	check(actor_lit>actor_dark*2.0,"Player body responds to actual lighting")
	check(pickup_lit>pickup_dark*2.0,"Pickup body responds to actual lighting")
	lit.save_png(CaptureOutput.path("lighting-polish/light-response-on.png"))
	dark.save_png(CaptureOutput.path("lighting-polish/light-response-off.png"))
	for zone_node in game.world.zones.values():
		for light in zone_node.find_children("*","PointLight2D",true,false):
			light.enabled = true
			check(light.get_child_count()==0 or not light.get_child(0) is PointLight2D,"Every lamp is a single light with no hidden companion copy")
	# Story lighting changes the real lamps.
	var altar: PointLight2D = game.world.landmarks["AltarLeftLight"]
	var rest_energy := altar.energy
	game.world.set_house_danger(true)
	check(altar.energy<rest_energy and altar.color==Color("71889b"),"Aftermath dims the altar lamp itself")
	game.world.set_house_danger(false)
	# A closed door stops light; the open door lets the same light through.
	game.flashlight.enabled = false
	var door: Door = game.world.interactables["altar_door"]["node"]
	game.enter_zone("house",door.global_position+Vector2(-90,-32))
	for light in game.world.zones["house"].find_children("*","PointLight2D",true,false):
		light.enabled = false
	var probe_light: PointLight2D = game.world.lamp(door.global_position+Vector2(-60,-32),Color.WHITE,2.0,1.6)
	var receiver := ColorRect.new()
	receiver.position = door.global_position+Vector2(60,-38)
	receiver.size = Vector2(12,12)
	receiver.z_index = 60
	game.world.add_child(receiver)
	door.snap(false)
	var shut := await frame()
	door.snap(true)
	var open := await frame()
	var shut_value := probe_value(shut,receiver)
	var open_value := probe_value(open,receiver)
	print("[Door occlusion] shut ",shut_value," open ",open_value)
	check(open_value>shut_value*2.0,"A closed door blocks light that the open door lets through")
	# A wall blocks it too: the receiver beside the doorway stays dark with the door open.
	receiver.position = door.global_position+Vector2(60,-170)
	var walled := await frame()
	var walls: TileMapLayer = game.world.zones["house"].get_node("Walls")
	walls.occlusion_enabled = false
	var unwalled := await frame()
	walls.occlusion_enabled = true
	print("[Wall occlusion] blocked ",probe_value(walled,receiver)," open ",probe_value(unwalled,receiver))
	check(probe_value(unwalled,receiver)>probe_value(walled,receiver)*2.0,"The partition wall blocks rendered light")
	open.save_png(CaptureOutput.path("lighting-polish/door-open.png"))
	shut.save_png(CaptureOutput.path("lighting-polish/door-shut.png"))
	probe_light.queue_free()
	receiver.queue_free()
	game.queue_free()
	await get_tree().process_frame
	print("[Light response] ",checks-failures,"/",checks," passed")
	get_tree().quit(1 if failures else 0)
