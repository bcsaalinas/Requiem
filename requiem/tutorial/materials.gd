extends RefCounted
## Tile atlas regions directly in Godot; generated source images are kept intact.
const ATLAS := preload("res://tutorial/assets/art/materials_atlas.png")
static func paint(canvas: CanvasItem, bounds: Rect2, cell: int, tile_size := 256.0, tint := Color.WHITE) -> void:
	var cell_size := Vector2(ATLAS.get_size())*.5
	var origin := Vector2(cell%2,floori(cell/2.0))*cell_size
	for y in range(ceili(bounds.size.y/tile_size)):
		for x in range(ceili(bounds.size.x/tile_size)):
			var start := Vector2(x,y)*tile_size
			var size := (bounds.size-start).min(Vector2.ONE*tile_size)
			canvas.draw_texture_rect_region(ATLAS,Rect2(bounds.position+start,size),Rect2(origin,size/tile_size*cell_size),tint)

static func scenery_material(floor_surface := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = preload("res://tutorial/scenery.gdshader")
	if floor_surface:
		result.set_shader_parameter("saturation",.10)
		result.set_shader_parameter("contrast",.50)
		result.set_shader_parameter("gain",.68)
		result.set_shader_parameter("detail_radius",3.5)
	return result
