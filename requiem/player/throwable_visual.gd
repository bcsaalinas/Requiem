@tool
extends Node2D
## Small, shared hand/projectile silhouettes; no extra light or effect emitter.

var kind := 0:
	set(value):
		kind = value
		queue_redraw()
var size := 6.0
var color := Color(0.85, 0.85, 0.8)

const PEBBLE := preload("res://assets/art/items/item_pebble_a.png")


func _draw() -> void:
	var radius := size * 0.5
	if kind == 0:
		var pebble_size := PEBBLE.get_size() * Units.ART_SCALE
		draw_texture_rect(PEBBLE, Rect2(-pebble_size * 0.5, pebble_size), false)
	else:
		draw_rect(Rect2(Vector2(-radius, -radius), Vector2.ONE * size), color.darkened(.2))
		draw_circle(Vector2.ZERO, radius * .7, color)
		draw_line(Vector2.ZERO, Vector2(0, -radius * .45), Color("3f4039"), 1.0)
