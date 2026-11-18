@tool
extends "res://tutorial/art.gd"
## Use the same textured pickup rendering and golden focus contour as the phone.
const NOTE := preload("res://tutorial/assets/art/abuela_note.svg")
func _ready() -> void:
	kind = "phone"
	super._ready()

func _draw() -> void:
	paint_sprite(NOTE, Rect2(-4,-61,28,36), Rect2(Vector2.ZERO,NOTE.get_size()))
