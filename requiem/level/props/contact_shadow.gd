@tool
extends Node2D
## Shade where a piece of furniture meets the floor, so it reads as standing on
## it rather than pasted over it. Drawn as a few nested rectangles: the alpha
## steps in bands, like the light pools, so the edge stays pixel art.
##
## Place the node at the centre of the prop's footprint. The shade is black with
## alpha, so it only shows where a light reaches the floor around the prop.

## Footprint the shade hugs, in world pixels (usually the collision size).
@export var size := Vector2(100.0, 36.0):
	set(value):
		size = value
		queue_redraw()
## How far past the footprint the outer band reaches, per side.
@export var spread := 6.0:
	set(value):
		spread = value
		queue_redraw()
## Shift of the shade, mostly southward: the floor in front of a prop is the side
## the camera sees, so that is where contact reads.
@export var drop := Vector2(0.0, 3.0):
	set(value):
		drop = value
		queue_redraw()
## Opacity right at the footprint edge.
@export_range(0.0, 1.0) var strength := 0.55:
	set(value):
		strength = value
		queue_redraw()
@export_range(1, 6) var steps := 3:
	set(value):
		steps = value
		queue_redraw()


func _draw() -> void:
	var band := Color(0.0, 0.0, 0.0, strength / float(steps))
	for index in range(steps):
		var grow := spread * (1.0 - float(index) / float(steps))
		draw_rect(Rect2(-size * 0.5 + drop - Vector2.ONE * grow, size + Vector2.ONE * grow * 2.0), band)
