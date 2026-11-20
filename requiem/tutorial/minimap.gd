extends Control
## The terrain scrolls under a fixed heading and north mark.
const Terrain := preload("res://tutorial/minimap_terrain.gd")
const LABEL_COLOR := Color("8d817b")

var atlas: Node
var terrain: Control
var _title: Label
var _font := SystemFont.new()

func _ready() -> void:
	position = Vector2(28, 24)
	size = Vector2(198, 198)
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	terrain = Terrain.new()
	terrain.atlas = atlas
	terrain.size = size
	terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(terrain)

	_font.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_title = _add_label(Vector2(9, 5))
	var north := _add_label(Vector2(size.x - 16, 5))
	north.text = "N"
	refresh()

func _add_label(at: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_color_override("font_shadow_color", Color("121010"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = at
	add_child(label)
	return label

func refresh() -> void:
	_title.text = String(atlas.TITLES[atlas.game.zone]).to_upper()
	terrain.queue_redraw()
