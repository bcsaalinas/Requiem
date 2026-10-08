@tool
extends Node2D
## Small, shared hand/projectile silhouettes; no extra light or effect emitter.

var kind := 0:
	set(value):
		kind = value
		queue_redraw()
var size := 6.0
var color := Color(0.85, 0.85, 0.8)


func _draw() -> void:
	var radius := size * 0.5
	if kind == 0:
		var points := PackedVector2Array([
			Vector2(-1.0, -.3), Vector2(-.35, -.85), Vector2(.7, -.65),
			Vector2(1, .2), Vector2(.3, .8), Vector2(-.7, .65)
		])
		for index in range(points.size()): points[index] *= radius
		draw_colored_polygon(points, color)
		draw_line(Vector2(-.35, -.5) * radius, Vector2(.4, -.4) * radius, color.lightened(.15), 1.0)
	else:
		draw_rect(Rect2(Vector2(-radius, -radius), Vector2.ONE * size), color.darkened(.2))
		draw_circle(Vector2.ZERO, radius * .7, color)
		draw_line(Vector2.ZERO, Vector2(0, -radius * .45), Color("3f4039"), 1.0)
