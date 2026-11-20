extends Control
## Small north-up map: the player stays in the centre while terrain scrolls underneath.
const Terrain := preload("res://tutorial/minimap_terrain.gd")
const FONT := preload("res://assets/fonts/cormorant_garamond/CormorantGaramond.ttf")
const GOLD := Color("c4a778")
var atlas: Node
var terrain: Control
var _title := ""

func _ready() -> void:
	position = Vector2(28, 24)
	size = Vector2(220, 198)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clip := Control.new()
	clip.position = Vector2(10, 38)
	clip.size = Vector2(200, 148)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	terrain = Terrain.new()
	terrain.atlas = atlas
	terrain.size = clip.size
	terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(terrain)
	refresh()

func refresh() -> void:
	var title: String = atlas.TITLES[atlas.game.zone]
	if _title != title:
		_title = title
		queue_redraw()
	terrain.queue_redraw()

func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.035, 0.055, 0.05, 0.92)
	panel.border_color = Color(0.65, 0.58, 0.41, 0.65)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(5)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 5
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(5, 5, 210, 188), Color(0.6, 0.6, 0.43, 0.12), false, 1)
	draw_string(FONT, Vector2(13, 27), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIPalette.TEXT)
	draw_string(FONT, Vector2(191, 26), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)
	draw_line(Vector2(10, 33), Vector2(210, 33), Color(0.65, 0.58, 0.41, 0.3))
	for point in [Vector2(8, 8), Vector2(212, 8), Vector2(8, 190), Vector2(212, 190)]:
		draw_circle(point, 1.3, GOLD, true, -1, true)
