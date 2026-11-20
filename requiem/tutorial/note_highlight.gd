@tool
extends "res://tutorial/art.gd"
## Abuela's letter, lying on the desk beside the flashlight.
const NOTE := preload("res://assets/art/items/item_note.png")
const NOTE_GLINT := preload("res://assets/art/items/item_note_glint.png")

func _ready() -> void:
	kind = "note"
	item_texture = NOTE
	item_glint = NOTE_GLINT
	super._ready()
