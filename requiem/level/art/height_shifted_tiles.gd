class_name HeightShiftedTiles
extends Node2D
## Draws the tiles of a hidden TileMapLayer shifted by HeightShift, each by the shift of its own
## centre, in whole art pixels. Lives at the same scale and position as the source layer.

@export var source: TileMapLayer:
	set(value):
		if source != null and source.changed.is_connected(_on_source_changed):
			source.changed.disconnect(_on_source_changed)
		source = value
		if source != null:
			source.changed.connect(_on_source_changed)
		_cells_dirty = true
		queue_redraw()
@export var height_factor := HeightShift.DEFAULT_FACTOR

var _cells: Array[Dictionary] = []
var _cells_dirty := true
var _last_view_origin := Vector2(INF, INF)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var display := get_tree().root.get_node_or_null("PixelDisplay")
	if display == null or display.world_view == null:
		return
	var origin: Vector2 = display.world_view.canvas_transform.origin
	if origin != _last_view_origin:
		_last_view_origin = origin
		queue_redraw()


func _on_source_changed() -> void:
	_cells_dirty = true
	queue_redraw()


func _read_cells() -> void:
	_cells.clear()
	_cells_dirty = false
	if source == null or source.tile_set == null:
		return
	var tile_size := Vector2(source.tile_set.tile_size)
	for cell in source.get_used_cells():
		var atlas := source.tile_set.get_source(source.get_cell_source_id(cell)) as TileSetAtlasSource
		if atlas == null:
			continue
		var coords := source.get_cell_atlas_coords(cell)
		var alternative := source.get_cell_alternative_tile(cell)
		var data := atlas.get_tile_data(coords, alternative)
		_cells.append({
			"texture": atlas.texture,
			"region": atlas.get_tile_texture_region(coords),
			"origin": Vector2(cell) * tile_size,
			"flip_h": data.flip_h,
			"flip_v": data.flip_v,
			"transpose": data.transpose,
		})


func _draw() -> void:
	if _cells_dirty:
		_read_cells()
	if source == null or source.tile_set == null:
		return
	var tile_size := Vector2(source.tile_set.tile_size)
	var scale_factor := global_transform.get_scale().x
	for entry: Dictionary in _cells:
		var origin: Vector2 = entry["origin"]
		var centre := origin + tile_size * 0.5
		var shift := (HeightShift.offset_for(to_global(centre), height_factor) / scale_factor).round()
		var size := tile_size
		var rect_origin := origin + shift
		if entry["flip_h"]:
			rect_origin.x += size.x
			size.x = -size.x
		if entry["flip_v"]:
			rect_origin.y += size.y
			size.y = -size.y
		draw_texture_rect_region(entry["texture"], Rect2(rect_origin, size), entry["region"], Color.WHITE, entry["transpose"])
