@tool
class_name WallWindow
extends Node2D
## A window set into an east-west wall, two tiles wide. It blocks movement like the wall around it
## but lets light through its glass: only the frame posts occlude. The origin is the floor line
## below the wall face, like Door, so both y-sort with the wall.
##
## The window art is two (or more) cells of the zone's ArtWallTops layer, placed by the zone art
## baker and listed in the `art_cells` metadata. Breaking swaps those cells through the three
## breaking frames and drops the glass shards on the room side.

signal broken_changed(is_broken: bool)

const BREAKING_FIRST := Vector2i(4, 7)
const BROKEN_FRAME := 2
const FRAME_SECONDS := 0.09
const SHARD_X_ART_PX := 18.0
const SHARD_HEIGHT_ART_PX := 24.0

## Exterior windows show the cracked pane (the breakable one); interior ones the plain window.
@export var exterior := false
## 1 when the room is south of the wall, -1 when it is north (shards fall on that side).
@export_range(-1, 1, 2) var room_side := 1:
	set(value):
		room_side = value
		_place_shards()
@export var broken := false:
	set(value):
		var changed := value != broken
		broken = value
		if not is_inside_tree():
			return
		_refresh(changed and not Engine.is_editor_hint())
		if changed and not Engine.is_editor_hint():
			broken_changed.emit(broken)

var _tween: Tween
## Each art cell's intact tile (atlas coords, alternative), so unbreaking restores it exactly.
var _intact: Dictionary = {}


func _ready() -> void:
	_place_shards()
	_refresh(false)


## Windows can be interaction targets (the tutorial's latch); the art itself does not react.
func set_focused(_value: bool) -> void:
	pass


## The cells of the window in the zone's ArtWallTops layer.
func get_art_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if has_meta("art_cells"):
		for cell: Vector2 in get_meta("art_cells"):
			cells.append(Vector2i(cell))
		return cells
	var origin := Vector2i(position / Units.TILE_PX)
	cells.append(Vector2i(origin.x - 1, origin.y - 1))
	cells.append(Vector2i(origin.x, origin.y - 1))
	return cells


func _tops_layer() -> TileMapLayer:
	var node := get_parent()
	while node != null:
		var layer := node.get_node_or_null("ArtWallTops") as TileMapLayer
		if layer != null:
			return layer
		node = node.get_parent()
	return null


func _refresh(animate: bool) -> void:
	var shards := get_node_or_null("Shards") as CanvasItem
	if shards != null:
		shards.visible = broken
	if _tween != null:
		_tween.kill()
	if not broken:
		_restore_intact()
		return
	if animate:
		_tween = create_tween()
		for frame in BROKEN_FRAME + 1:
			_tween.tween_callback(_set_frame.bind(frame))
			_tween.tween_interval(FRAME_SECONDS)
	else:
		_set_frame(BROKEN_FRAME)


func _set_frame(frame: int) -> void:
	var layer := _tops_layer()
	if layer == null:
		return
	for cell in get_art_cells():
		if not _intact.has(cell):
			_intact[cell] = [layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]
		# Keep the cell's flip/transpose alternative: the pane faces the same way as the intact one.
		layer.set_cell(cell, 0, BREAKING_FIRST + Vector2i(frame, 0), _intact[cell][1])


func _restore_intact() -> void:
	var layer := _tops_layer()
	if layer == null:
		return
	for cell: Vector2i in _intact:
		layer.set_cell(cell, 0, _intact[cell][0], _intact[cell][1])
	_intact.clear()


## Shards lie on the room-side floor cells next to the wall: the decal's wall edge touches the wall
## and it sits at x 18-57 of the 80 px cell.
func _place_shards() -> void:
	if not is_inside_tree():
		return
	var cell := float(Units.TILE_PX)
	var art := Units.ART_SCALE
	var height := SHARD_HEIGHT_ART_PX * art
	var row_top := 0.0 if room_side == 1 else -4.0 * cell
	for index in 2:
		var shard := get_node_or_null("Shards/Shards" + ["A", "B"][index]) as Sprite2D
		if shard == null:
			continue
		var wall_edge_top := room_side == 1
		shard.flip_v = not wall_edge_top
		var y := row_top if wall_edge_top else row_top + cell - height
		shard.position = Vector2(-cell + index * cell + SHARD_X_ART_PX * art, y)
