@tool
class_name WallWindow
extends Node2D
## A window set into an east-west wall, two tiles wide. It blocks movement like the wall around it
## but lets light through its glass: only the frame posts occlude. The origin is the floor line
## below the wall face, like Door, so both y-sort with the wall.
##
## The window art is the 2-unit box window cutaway from art-lab (wall_top_window_box*.png), drawn
## shifted away from the screen centre like the wall tops around it. For walls deeper than one
## cell the canvas is split at split_y_px and the floor-of-opening filler piece is inserted
## between the outer and inner halves. Breaking swaps the composed art to the broken state and
## drops the glass shards on the room side; "Unlatch" swaps to the swung pane.

signal broken_changed(is_broken: bool)

const BOX_CANVAS := Vector2i(160, 120)
## Centre of the 2x1 wall cells inside the canvas (art px); the sill overhangs sit outside it.
const BOX_ANCHOR_PX := Vector2(80, 56)
const BOX_SPLIT_Y_PX := 56
const BURST_MS := [90, 95, 105, 110]
const SHARD_X_ART_PX := 18.0
const SHARD_HEIGHT_ART_PX := 24.0

const BOX_INTACT := preload("res://assets/art/tiles/wall_top_window_box.png")
const BOX_BROKEN := preload("res://assets/art/tiles/wall_top_window_box_broken.png")
const BOX_UNLATCHED := preload("res://assets/art/tiles/wall_top_window_box_unlatched.png")
const BOX_FILLER := preload("res://assets/art/tiles/wall_top_window_box_filler.png")

## Exterior windows show the cracked pane (the breakable one); interior ones the plain window.
@export var exterior := false
## 1 when the room is south of the wall, -1 when it is north (shards fall on that side).
@export_range(-1, 1, 2) var room_side := 1:
	set(value):
		room_side = value
		_place_shards()
		_redraw_box()
## Draw the box above the porch roof layers so the inner sill and curtain tops stay readable.
@export var over_roof := false:
	set(value):
		over_roof = value
		if _box != null:
			_box.z_index = 47 if over_roof else 41
			_sync_burst_z()
## Wall cells the window opening is cut through; more than one adds filler copies between halves.
@export_range(1, 4) var wall_depth := 1:
	set(value):
		wall_depth = value
		_redraw_box()
@export var broken := false:
	set(value):
		var changed := value != broken
		broken = value
		if not is_inside_tree():
			return
		_refresh(changed and not Engine.is_editor_hint())
		if changed and not Engine.is_editor_hint():
			broken_changed.emit(broken)
## The pane has been reached through and swung open after the break.
var unlatched := false:
	set(value):
		unlatched = value
		_redraw_box()

var _tween: Tween
var _box: Sprite2D
var _last_view_origin := Vector2(INF, INF)


func _ready() -> void:
	_place_shards()
	_build_box()
	_refresh(false)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _box == null:
		return
	var display := get_tree().root.get_node_or_null("PixelDisplay")
	if display == null or display.world_view == null:
		return
	var origin: Vector2 = display.world_view.canvas_transform.origin
	if origin != _last_view_origin:
		_last_view_origin = origin
		_apply_shift()


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
	var burst := get_node_or_null("Burst") as Sprite2D
	if burst != null:
		burst.visible = false
	if _tween != null:
		_tween.kill()
	_redraw_box()
	if broken and animate:
		_play_burst()


func _play_burst() -> void:
	var burst := get_node_or_null("Burst") as Sprite2D
	if burst == null:
		return
	burst.frame = 0
	burst.visible = true
	_tween = create_tween()
	for frame in burst.hframes:
		_tween.tween_callback(burst.set_frame.bind(frame))
		_tween.tween_interval(BURST_MS[mini(frame, BURST_MS.size() - 1)] / 1000.0)
	_tween.tween_callback(burst.hide)


# --- Box window art ----------------------------------------------------------

func _state_texture() -> Texture2D:
	if unlatched:
		return BOX_UNLATCHED
	if broken:
		return BOX_BROKEN
	return BOX_INTACT


func _build_box() -> void:
	if Engine.is_editor_hint():
		return
	# The box piece replaces the old window cells on the wall-top layer.
	var layer := _tops_layer()
	if layer != null:
		for cell in get_art_cells():
			layer.erase_cell(cell)
		var shifted := layer.get_parent().get_node_or_null("ArtWallTopsShifted")
		if shifted != null and shifted.has_method("refresh"):
			shifted.refresh()
	_box = Sprite2D.new()
	_box.name = "BoxArt"
	_box.scale = Vector2.ONE * Units.ART_SCALE
	_box.z_as_relative = false
	_box.z_index = 47 if over_roof else 41
	_box.centered = false
	add_child(_box)
	_sync_burst_z()
	_redraw_box()


## The flying glass draws immediately above its own box, so the porch roof
## order never swallows it.
func _sync_burst_z() -> void:
	var burst := get_node_or_null("Burst") as Sprite2D
	if burst != null:
		burst.z_index = _box.z_index + 1


func _redraw_box() -> void:
	if _box == null:
		return
	_box.texture = _compose(_state_texture())
	# The anchor sits at the centre of the two wall cells, at the bottom of the outer half.
	# With the piece flipped for a north-side room the same point is mirrored inside the canvas.
	var anchor := BOX_ANCHOR_PX if room_side == 1 else Vector2(BOX_ANCHOR_PX.x, _box.texture.get_height() - BOX_ANCHOR_PX.y)
	_box.position = Vector2(0, -Units.TILE_PX * 0.5) - anchor * Units.ART_SCALE
	_apply_shift()


func _apply_shift() -> void:
	if _box == null:
		return
	var centre := _box.position + _box.texture.get_size() * Units.ART_SCALE * 0.5
	_box.offset = HeightShift.offset_for(global_position + centre)


## Assembles the drawn piece: whole canvas for a one-cell wall; outer half, one filler per extra
## cell, then inner half for deeper walls. Mirrored vertically when the room is on the north side.
func _compose(texture: Texture2D) -> ImageTexture:
	var src := texture.get_image()
	if wall_depth <= 1:
		return ImageTexture.create_from_image(src)
	var outer := src.get_region(Rect2i(0, 0, BOX_CANVAS.x, BOX_SPLIT_Y_PX))
	var inner := src.get_region(Rect2i(0, BOX_SPLIT_Y_PX, BOX_CANVAS.x, BOX_CANVAS.y - BOX_SPLIT_Y_PX))
	var filler := BOX_FILLER.get_image()
	var out := Image.create(BOX_CANVAS.x, BOX_CANVAS.y + (wall_depth - 1) * filler.get_height(), false, Image.FORMAT_RGBA8)
	var y := 0
	for piece: Image in [inner, filler, outer] if room_side == -1 else [outer, filler, inner]:
		if room_side == -1:
			piece.flip_y()
		out.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(0, y))
		y += piece.get_height()
		for extra in (wall_depth - 2):
			if piece == filler:
				var copy := filler.duplicate() as Image
				if room_side == -1:
					copy.flip_y()
				out.blit_rect(copy, Rect2i(Vector2i.ZERO, copy.get_size()), Vector2i(0, y))
				y += copy.get_height()
	return ImageTexture.create_from_image(out)


## Shards lie on the room-side floor cells next to the wall: the decal's wall edge touches the wall
## and it sits at x 18-57 of the 80 px cell.
func _place_shards() -> void:
	if not is_inside_tree():
		return
	var cell := float(Units.TILE_PX)
	var art := Units.ART_SCALE
	var height := SHARD_HEIGHT_ART_PX * art
	for index in 2:
		var shard := get_node_or_null("Shards/Shards" + ["A", "B"][index]) as Sprite2D
		if shard == null:
			continue
		var side := room_side if index == 0 else -room_side
		var row_top := 0.0 if side == 1 else -4.0 * cell
		var wall_edge_top := side == 1
		shard.flip_v = not wall_edge_top
		var y := row_top if wall_edge_top else row_top + cell - height
		shard.position = Vector2(-cell + index * cell + SHARD_X_ART_PX * art, y)
