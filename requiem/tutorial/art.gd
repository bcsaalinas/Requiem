@tool
extends Node2D
## Original textured sprites; their visual height is independent of collision footprints.
@export var kind: String = "crate"
@export var dimensions: Vector2 = Vector2(48, 48)
@export var tint: Color = Color("82755a")
## Draws a small pickup this many px higher than its node, so it can rest on a desk or a chest
## while it still y-sorts at the furniture's front edge.
@export var lift := 0.0
@export_group("Actor animation")
const Materials := preload("res://tutorial/materials.gd")
const VELADORA := preload("res://assets/art/ritual/ritual_veladora.png")
const VELADORA_UNLIT := preload("res://assets/art/ritual/ritual_veladora_unlit.png")
const VELADORA_FLICKER_MS := [260.0, 180.0, 140.0]
const VELADORA_FRAME := 32.0
const DETAILS := preload("res://tutorial/assets/art/details_atlas.png")
const DETAIL_REGIONS := {
 "rocks":Rect2(.788,.115,.177,.315),
 "candle":Rect2(.787,.54,.19,.37),
}
const ITEMS := {
 "flashlight":preload("res://assets/art/items/item_flashlight.png"),
 "battery":preload("res://assets/art/items/item_battery.png"),
 "phone":preload("res://assets/art/items/item_phone.png"),
}
const ITEM_GLINTS := {
 "flashlight":preload("res://assets/art/items/item_flashlight_glint.png"),
 "battery":preload("res://assets/art/items/item_battery_glint.png"),
 "phone":preload("res://assets/art/items/item_phone_glint.png"),
}
const PHONE_LIT := preload("res://assets/art/items/item_phone_lit.png")
## Pickups have to be found in rooms that are mostly black. Three cues, none of which lights the room:
## a cold star that twinkles on the item whether or not any light reaches it, an outline once she is
## close enough to take it, and (the phone only) a screen that really glows until it is read.
const BEACON := preload("res://assets/art/vfx/vfx_glint.png")
## Small star, large star, small star, then dark for the rest of the period.
const BEACON_MS := [90.0, 170.0, 120.0]
const BEACON_FRAMES := [1, 0, 1]
const BEACON_PERIOD := 2.4
const OUTLINE_SHADER := preload("res://tutorial/pickup_outline.gdshader")
const PHONE_GLOW := preload("res://assets/art/lights/light_lamp_pool.png")
# durations_ms copied from the item JSONs; every glint loops the same two numbers.
const GLINT_MS := [160.0, 480.0]
const PHONE_LIT_MS := [360.0, 360.0]
const SPRITES := preload("res://tutorial/assets/art/props_atlas.png")
var focused := false
var focal_sprite: Sprite2D
var rim_sprite: Sprite2D
var glint: Sprite2D
var beacon: Sprite2D
var outline: Sprite2D
var screen: Sprite2D
var screen_glow: PointLight2D
var extinguished := false
## The phone's incoming-message screen stays lit until the first read.
var screen_lit := true
var clock := 0.0
## Painted body pose; contact shadows and the physical player stay fixed.

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1
	# One light layer: every light reaches every receiver; walls, doors and tall props occlude.
	light_mask = 1
	if kind != "candle" and not ITEMS.has(kind):
		material = Materials.scenery_material()
	if ITEMS.has(kind):
		glint = Sprite2D.new()
		glint.name = "Glint"
		glint.texture = ITEM_GLINTS[kind]
		glint.hframes = 2
		glint.scale = Vector2.ONE * Units.ART_SCALE
		glint.position = Vector2(0.0, -lift)
		add_child(glint,false,Node.INTERNAL_MODE_BACK)
	if ITEMS.has(kind):
		_add_pickup_cues(ITEMS[kind])
	if kind == "phone":
		_add_phone_screen()
	if kind in ["rocks"]:
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

## True for the things she takes or reads off a surface (they carry the pickup cues).
func is_pickup() -> bool:
	return is_instance_valid(beacon)


## Where the item is drawn, which is where its prompt belongs (the node sits at the furniture's edge).
func get_prompt_anchor() -> Vector2:
	return global_position + Vector2(0.0, -lift)


func _add_pickup_cues(item_texture: Texture2D) -> void:
	var at := Vector2(0.0, -lift)
	outline = Sprite2D.new()
	outline.name = "Outline"
	outline.texture = item_texture
	outline.region_enabled = true
	outline.region_rect = Rect2(Vector2(-1.0, -1.0), item_texture.get_size() + Vector2(2.0, 2.0))
	outline.scale = Vector2.ONE * Units.ART_SCALE
	outline.position = at
	outline.visible = false
	outline.material = ShaderMaterial.new()
	outline.material.shader = OUTLINE_SHADER
	add_child(outline,false,Node.INTERNAL_MODE_BACK)
	beacon = Sprite2D.new()
	beacon.name = "Beacon"
	beacon.texture = BEACON
	beacon.hframes = 2
	beacon.scale = Vector2.ONE * Units.ART_SCALE
	beacon.position = at
	beacon.z_index = 1
	beacon.visible = false
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	beacon.material = unlit
	add_child(beacon,false,Node.INTERNAL_MODE_BACK)


## The unread message: the screen is its own light, so it is the one thing visible from the bed.
func _add_phone_screen() -> void:
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	screen = Sprite2D.new()
	screen.name = "Screen"
	screen.texture = PHONE_LIT
	screen.hframes = 2
	screen.scale = Vector2.ONE * Units.ART_SCALE
	screen.position = Vector2(0.0, -lift)
	screen.material = unlit
	add_child(screen,false,Node.INTERNAL_MODE_BACK)
	screen_glow = PointLight2D.new()
	screen_glow.name = "ScreenGlow"
	screen_glow.texture = PHONE_GLOW
	screen_glow.texture_scale = Units.ART_SCALE
	screen_glow.color = Color("8fa9b8")
	screen_glow.position = Vector2(0.0, -lift)
	screen_glow.range_item_cull_mask = 5
	add_child(screen_glow,false,Node.INTERNAL_MODE_BACK)


func _process(delta: float) -> void:
	clock += delta
	if is_instance_valid(glint):
		glint.frame = _cycle_frame(GLINT_MS)
	if is_instance_valid(beacon):
		_tick_beacon()
	if is_instance_valid(screen):
		screen.visible = screen_lit
		screen.frame = _cycle_frame(PHONE_LIT_MS)
		screen_glow.visible = screen_lit
		screen_glow.energy = 0.9 if screen.frame == 0 else 0.65
	if kind == "candle":
		queue_redraw()


## The twinkle is staggered per item so a desk of pickups never blinks in unison.
func _tick_beacon() -> void:
	if Engine.is_editor_hint() or (kind == "phone" and screen_lit):
		beacon.visible = false
		return
	var time_ms := fposmod(clock + fposmod(position.x * 0.137 + position.y * 0.071, BEACON_PERIOD), BEACON_PERIOD) * 1000.0
	beacon.visible = false
	for index in BEACON_MS.size():
		if time_ms < BEACON_MS[index]:
			beacon.visible = true
			beacon.frame = BEACON_FRAMES[index]
			return
		time_ms -= BEACON_MS[index]


func _draw() -> void:
	if ITEMS.has(kind):
		var texture: Texture2D = ITEMS[kind]
		var size := texture.get_size() * Units.ART_SCALE
		draw_texture_rect(texture, Rect2(Vector2(0.0, -lift) - size * 0.5, size), false)
		return
	if DETAIL_REGIONS.has(kind):
		_draw_detail()

func _cycle_frame(durations: Array) -> int:
	var cycle_ms := 0.0
	for duration: float in durations:
		cycle_ms += duration
	var time_ms := fposmod(clock * 1000.0, cycle_ms)
	var frame := 0
	while time_ms >= durations[frame]:
		time_ms -= durations[frame]
		frame += 1
	return frame

func _draw_veladora() -> void:
	var cycle_ms := 0.0
	for duration: float in VELADORA_FLICKER_MS:
		cycle_ms += duration
	var time_ms := fposmod(clock * 1000.0 + position.x * 37.0 + position.y * 11.0, cycle_ms)
	var frame := 0
	while time_ms >= VELADORA_FLICKER_MS[frame]:
		time_ms -= VELADORA_FLICKER_MS[frame]
		frame += 1
	var half := Vector2.ONE * VELADORA_FRAME * 0.5 * Units.ART_SCALE
	draw_texture_rect_region(VELADORA, Rect2(-half, half * 2.0), Rect2(frame * VELADORA_FRAME, 0.0, VELADORA_FRAME, VELADORA_FRAME))


func _draw_veladora_unlit() -> void:
	var half := Vector2.ONE * VELADORA_FRAME * 0.5 * Units.ART_SCALE
	draw_texture_rect_region(VELADORA_UNLIT, Rect2(-half, half * 2.0), Rect2(0.0, 0.0, VELADORA_FRAME, VELADORA_FRAME))


func _draw_detail() -> void:
	if kind == "candle":
		if extinguished:
			_draw_veladora_unlit()
		else:
			_draw_veladora()
		return
	var region: Rect2 = DETAIL_REGIONS[kind]
	region.position *= DETAILS.get_size()
	region.size *= DETAILS.get_size()
	var size := Vector2(32,32)
	# Pickups at real scale next to the 58 px girl; the focus rim keeps them readable.
	match kind:
		"rocks": size=Vector2(30,23)
		"candle": size=Vector2(25,27)
	var bottom := 12.0
	paint_sprite(DETAILS,Rect2(Vector2(-size.x*.5,bottom-size.y-lift),size),region)

func set_focused(value: bool) -> void:
	if focused == value: return
	focused = value
	if is_instance_valid(outline): outline.visible = value
	queue_redraw()

func paint_sprite(atlas: Texture2D, target: Rect2, source: Rect2, albedo := Color.WHITE) -> void:
	var emphasized := is_instance_valid(focal_sprite)
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
	style.set_shader_parameter("accent",accent)
	style.set_shader_parameter("value_floor",floor_value)
	style.set_shader_parameter("value_range",value_range)
	style.set_shader_parameter("rim_strength",rim)
	style.set_shader_parameter("color_mix",.55 if kind in ["rocks"] else .18)

	# Reuse the same atlas crop for a subtle contour, never an unlit sprite body.
	rim_sprite.texture = focal_sprite.texture
	rim_sprite.region_rect = focal_sprite.region_rect
	rim_sprite.position = focal_sprite.position
	rim_sprite.scale = focal_sprite.scale
	for parameter in ["atlas_texture","atlas_bounds","edge_step","accent","rim_strength"]:
		rim_sprite.material.set_shader_parameter(parameter,style.get_shader_parameter(parameter))
