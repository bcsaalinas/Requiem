extends Label
## The verb and binding come from the existing interaction prompt.
const CAP := preload("res://assets/art/hud/interaction_keycap.png")
var _key_plate := TextureRect.new()

func _ready() -> void:
	_key_plate.texture = CAP
	_key_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_key_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_key_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_plate.show_behind_parent = true
	add_child(_key_plate)
	draw.connect(_place_plate)

func _place_plate() -> void:
	_key_plate.visible = text == "E" or text.begins_with("E · ")
	if _key_plate.visible:
		var glyph := get_character_bounds(0)
		_key_plate.size = Vector2(26, 26)
		_key_plate.position = (glyph.get_center() - _key_plate.size * 0.5).round()
