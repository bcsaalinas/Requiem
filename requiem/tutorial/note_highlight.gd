@tool
extends "res://tutorial/art.gd"
## Abuela's letter, lying on the desk beside the flashlight.
const NOTE := preload("res://assets/art/items/item_note.png")
const NOTE_GLINT := preload("res://assets/art/items/item_note_glint.png")

func _ready() -> void:
	kind = "note"
	super._ready()
	material = null
	glint = Sprite2D.new()
	glint.name = "Glint"
	glint.texture = NOTE_GLINT
	glint.hframes = 2
	glint.scale = Vector2.ONE * Units.ART_SCALE
	glint.position = Vector2(0.0, -lift)
	add_child(glint,false,Node.INTERNAL_MODE_BACK)
	_add_pickup_cues(NOTE)

func _draw() -> void:
	var size := NOTE.get_size() * Units.ART_SCALE
	draw_texture_rect(NOTE, Rect2(Vector2(0.0, -lift) - size * 0.5, size), false)
