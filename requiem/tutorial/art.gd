@tool
extends Node2D
## Original textured sprites; their visual height is independent of collision footprints.
@export var kind: String = "crate"
@export var dimensions: Vector2 = Vector2(48, 48)
@export var tint: Color = Color("82755a")
const Materials := preload("res://tutorial/materials.gd")
const DETAILS := preload("res://tutorial/assets/art/details_atlas.png")
const DETAIL_REGIONS := {
 "flashlight":Rect2(.025,.08,.205,.35), "battery":Rect2(.325,.09,.10,.34),
 "phone":Rect2(.545,.09,.175,.37), "rocks":Rect2(.788,.115,.177,.315),
 "window":Rect2(.075,.50,.10,.445), "broken":Rect2(.326,.50,.10,.445),
 "marker":Rect2(.55,.50,.18,.455), "candle":Rect2(.787,.54,.19,.37),
}
const SPRITES := preload("res://tutorial/assets/art/props_atlas.png")
const CELLS := {
 "bed": Rect2(95,0,190,317), "desk": Rect2(366,20,250,283),
 "shelf": Rect2(694,0,205,316), "chair": Rect2(1005,46,207,264),
 "tree": Rect2(0,322,320,318), "spruce": Rect2(340,322,265,318),
 "altar": Rect2(666,370,282,269), "crate": Rect2(994,416,260,209),
 "door": Rect2(63,670,242,258), "lantern": Rect2(446,669,91,264),
 "rug": Rect2(694,641,206,306), "coats": Rect2(1005,674,234,254),
 "actor": Rect2(94,950,186,237), "friend": Rect2(375,975,215,240),
 "fallen": Rect2(638,1020,318,181), "entity": Rect2(996,946,252,322),
}
var focused := false
var threat_pressure := 0.0
var focal_sprite: Sprite2D
var rim_sprite: Sprite2D
var listening := false
var fallen := false
var broken := false
var extinguished := false
var clock := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 0 if kind == "rug" else 1
	light_mask = 1 if kind in ["actor","friend","entity","wall","rug","glass"] else 2
	material = Materials.scenery_material()
	if kind == "tree":
		material.set_shader_parameter("gain",.70)
		material.set_shader_parameter("saturation",.12)
	if kind == "rug":
		material.set_shader_parameter("saturation",.08)
		material.set_shader_parameter("contrast",.38)
		material.set_shader_parameter("gain",.56)
		material.set_shader_parameter("detail_radius",3.0)
	if kind in ["actor","friend","entity","flashlight","battery","phone","rocks","marker","window","door"]:
		focal_sprite = Sprite2D.new()
		focal_sprite.name = "ReadabilitySprite"
		focal_sprite.light_mask = light_mask
		focal_sprite.centered = false
		focal_sprite.region_enabled = true
		var focal_material := ShaderMaterial.new()
		focal_material.shader = preload("res://tutorial/focal_sprite.gdshader")
		focal_sprite.material = focal_material
		# Rendering helpers must not become duplicate authored nodes when the world is saved.
		add_child(focal_sprite,false,Node.INTERNAL_MODE_BACK)
		rim_sprite = Sprite2D.new()
		rim_sprite.name = "ReadabilityContour"
		rim_sprite.centered = false
		rim_sprite.region_enabled = true
		var rim_material := ShaderMaterial.new()
		rim_material.shader = preload("res://tutorial/readability_rim.gdshader")
		rim_sprite.material = rim_material
		add_child(rim_sprite,false,Node.INTERNAL_MODE_BACK)

func _process(delta: float) -> void:
	clock += delta
	if kind in ["actor", "friend", "entity", "candle", "phone", "altar"] or listening:
		queue_redraw()

func _draw() -> void:
	var r := Rect2(-dimensions / 2, dimensions)
	if DETAIL_REGIONS.has(kind):
		_draw_detail()
		return
	if CELLS.has(kind):
		_draw_sprite()
		return
	match kind:
		"wall":
			Materials.paint(self,r,2,160,Color(.46,.47,.43))
			var face := Rect2(r.position.x,r.end.y-minf(30,r.size.y),r.size.x,minf(30,r.size.y))
			Materials.paint(self,face,0,220,Color(.34,.31,.28))
			draw_line(Vector2(r.position.x,face.position.y),Vector2(r.end.x,face.position.y),Color("736857"),2)
			draw_line(Vector2(r.position.x,r.end.y-2),Vector2(r.end.x,r.end.y-2),Color("151612"),4)
		"glass":
			for i in range(11):
				var p := Vector2(sin(i*7.0)*28, cos(i*5.0)*16)
				draw_line(p, p+Vector2(5,-4), Color("9aaca6"), 2)

func paint_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(32): points.append(center + Vector2(cos(i*TAU/32), sin(i*TAU/32))*radius)
	draw_colored_polygon(points, color)

func _draw_sprite() -> void:
	var id := "fallen" if kind == "friend" and fallen else kind
	if kind == "tree" and int(position.x) % 3 == 0: id = "spruce"
	var region: Rect2 = CELLS[id]
	region = region.intersection(Rect2(Vector2.ZERO,SPRITES.get_size()))
	var size := dimensions
	var bottom := dimensions.y * .5
	match kind:
		"actor": size = Vector2(42,58); bottom = 20
		"friend":
			size = Vector2(48,58) if not fallen else Vector2(73,42)
			bottom = 22
		"entity": size = Vector2(45,92); bottom = 24
		"tree": size = Vector2(155,185); bottom = 30
		"bed": size = Vector2(dimensions.x,dimensions.y)
		"desk": size = Vector2(dimensions.x, maxf(90,dimensions.x*.72))
		"shelf": size = Vector2(dimensions.x,maxf(135,dimensions.y))
		"coats": size = Vector2(116,95); bottom = 12
		"chair": size = Vector2(75,96); bottom = 32
		"crate": size = Vector2(dimensions.x,dimensions.y*1.2)
		"altar": size = Vector2(148,128); bottom = 38
		"door":
			size = Vector2(maxf(48,dimensions.x),98)
			bottom = dimensions.y*.5
		"lantern": size = Vector2(19,55); bottom = 12
	# Contact shadows ground props without changing their physical footprints.
	if kind != "rug":
		paint_ellipse(Vector2(2,bottom-3),Vector2(size.x*.34,8),Color(0,0,0,.08))
		paint_ellipse(Vector2(2,bottom-3),Vector2(size.x*.27,5),Color(0,0,0,.14))
	var offset := Vector2(-size.x*.5,bottom-size.y)
	if kind == "actor": offset.y += sin(clock*2.0)*.6
	var albedo := Color(1.15,1.12,1.07) if kind != "entity" else Color(.42,.45,.46,.75)
	paint_sprite(SPRITES,Rect2(offset.floor(),size),region,albedo)
	if listening:
		# A cold line below the occupied door, interrupted by two shifting feet.
		var y := bottom + 3
		draw_line(Vector2(-30,y),Vector2(30,y),Color("a6b4ad"),3)
		var shift := sin(clock*.65)*8
		for x in [-12.0,10.0]:
			draw_rect(Rect2(x+shift-4,y-2,8,6),Color("141712"))

func _draw_detail() -> void:
	var key := "broken" if kind == "window" and broken else kind
	var region: Rect2 = DETAIL_REGIONS[key]
	region.position *= DETAILS.get_size()
	region.size *= DETAILS.get_size()
	var size := Vector2(32,32)
	match kind:
		"flashlight": size=Vector2(36,30)
		"battery": size=Vector2(14,25)
		"phone": size=Vector2(24,28)
		"rocks": size=Vector2(41,32)
		"window": size=Vector2(42,91)
		"marker": size=Vector2(40,55)
		"candle": size=Vector2(25,27)
	var bottom := 12.0
	if kind == "window": bottom=dimensions.y*.5
	if kind == "candle" and extinguished:
		region.position.y += region.size.y*.27
		region.size.y *= .73
		size.y *= .73
	paint_sprite(DETAILS,Rect2(Vector2(-size.x*.5,bottom-size.y),size),region)

func set_focused(value: bool) -> void:
	if focused == value: return
	focused = value
	queue_redraw()

func set_threat_pressure(value: float) -> void:
	if is_equal_approx(value,threat_pressure): return
	threat_pressure = value
	queue_redraw()

func paint_sprite(atlas: Texture2D, target: Rect2, source: Rect2, albedo := Color.WHITE) -> void:
	var emphasized := is_instance_valid(focal_sprite) and (kind != "door" or focused) and (kind != "entity" or threat_pressure>.01)
	if is_instance_valid(focal_sprite):
		focal_sprite.visible=emphasized
		rim_sprite.visible=emphasized
	if not emphasized:
		draw_texture_rect_region(atlas,target,source,albedo)
		return
	# Pad the draw quad for a one-pixel rim and a dark separating edge.
	var ratio := source.size/target.size
	var padded := source.grow_individual(ratio.x*2,ratio.y*2,ratio.x*2,ratio.y*2)
	focal_sprite.texture=atlas
	focal_sprite.region_rect=padded
	focal_sprite.position=target.position-Vector2(2,2)
	focal_sprite.scale=target.size/source.size
	var style := focal_sprite.material as ShaderMaterial
	style.set_shader_parameter("atlas_texture",atlas)
	style.set_shader_parameter("atlas_bounds",Vector4(source.position.x/atlas.get_width(),source.position.y/atlas.get_height(),source.end.x/atlas.get_width(),source.end.y/atlas.get_height()))
	style.set_shader_parameter("edge_step",ratio/atlas.get_size())
	var accent := Color("e1b967")
	var floor_value := .17
	var value_range := .68
	var rim := .28 if not focused else .65
	if kind == "actor":
		accent=Color("bedbd5"); floor_value=.18; value_range=.72; rim=.45
	elif kind == "friend":
		accent=Color("baaea0"); floor_value=.12; value_range=.54; rim=.30
	elif kind == "marker":
		floor_value=.15; rim=.42
	elif kind in ["window","door"]:
		floor_value=.10 if not focused else .18; rim=.20 if not focused else .70
	elif kind == "entity":
		accent=Color("b99a96"); floor_value=.12+threat_pressure*.20
		value_range=.25; rim=threat_pressure*.62
	style.set_shader_parameter("accent",accent)
	style.set_shader_parameter("value_floor",floor_value)
	style.set_shader_parameter("value_range",value_range)
	style.set_shader_parameter("rim_strength",rim)
	style.set_shader_parameter("color_mix",.55 if kind in ["marker","battery","flashlight","rocks","phone"] else .18)

	# Reuse the same atlas crop for a subtle contour, never an unlit sprite body.
	rim_sprite.texture = focal_sprite.texture
	rim_sprite.region_rect = focal_sprite.region_rect
	rim_sprite.position = focal_sprite.position
	rim_sprite.scale = focal_sprite.scale
	for parameter in ["atlas_texture","atlas_bounds","edge_step","accent","rim_strength"]:
		rim_sprite.material.set_shader_parameter(parameter,style.get_shader_parameter(parameter))
