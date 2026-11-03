@tool
class_name Room
extends Area2D
## One interior (or outdoor) space. Its Cover hides everything inside until the player enters or
## an open door connects it to the room the player stands in. Lights and walls still decide what
## is actually visible once the cover is lifted.
##
## Children: "Shape" (CollisionPolygon2D, the walkable inside, reaching half into door gaps) and
## optionally "Cover" (Polygon2D drawn over the room). The cover copies Shape unless it has its own
## polygon. Outdoor rooms have no Cover; they only tell RoomVisibility where the player is.

signal player_entered(room: Room)
signal player_exited(room: Room)

## Doors in this room's walls. A door listed by two rooms connects them; a door listed by one
## room leads outside (or to another zone).
@export var doors: Array[Door] = []
## Seconds the cover takes to fade in or out.
@export_range(0.0, 2.0, 0.05) var fade_time := 0.3

var revealed := true
var _tween: Tween


func _ready() -> void:
	monitorable = false
	var cover := get_cover()
	if cover != null:
		cover.light_mask = 0
		if cover.polygon.is_empty():
			var shape := get_node_or_null("Shape") as CollisionPolygon2D
			if shape != null:
				cover.polygon = shape.polygon
	if Engine.is_editor_hint():
		return
	body_entered.connect(func(body: Node2D):
		if body.is_in_group("player"): player_entered.emit(self))
	body_exited.connect(func(body: Node2D):
		if body.is_in_group("player"): player_exited.emit(self))


func get_cover() -> Polygon2D:
	return get_node_or_null("Cover") as Polygon2D


func has_cover() -> bool:
	return get_cover() != null


## Shows or hides the inside. `instant` skips the fade (zone loads, checkpoint restores).
func set_revealed(value: bool, instant := false) -> void:
	var cover := get_cover()
	if cover == null:
		revealed = true
		return
	if value == revealed and not instant:
		return
	revealed = value
	if _tween != null:
		_tween.kill()
	var target := 0.0 if value else 1.0
	if instant or fade_time <= 0.0 or not is_inside_tree():
		cover.modulate.a = target
		cover.visible = target > 0.0
		return
	cover.visible = true
	_tween = create_tween()
	_tween.tween_property(cover, "modulate:a", target, fade_time)
	if value:
		_tween.tween_callback(func(): cover.visible = false)
