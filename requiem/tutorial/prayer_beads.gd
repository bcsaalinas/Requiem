extends ProgressBar
## The altar already owns elapsed prayer and cancellation.
const CORD := preload("res://assets/art/hud/interaction_cord.png")
const FILLED := preload("res://assets/art/hud/interaction_prayed.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("fill", empty)
	add_theme_stylebox_override("background", empty)

func _draw() -> void:
	var art_size := CORD.get_size()
	var origin := ((size - art_size) * 0.5).round()
	draw_texture(CORD, origin)
	var beads := clampi(floori(ratio * 7.0), 0, 7)
	if beads > 0:
		var region := Rect2(0, 0, 10 + 14 * (beads - 1), art_size.y)
		draw_texture_rect_region(FILLED, Rect2(origin, region.size), region)
