extends Node2D
## Flashes a parent door's listening edge red when one of the player's sounds reaches it, so
## "he heard you, through this door" reads without text.
## Lives in a CanvasLayer that follows the viewport, so the near-black CanvasModulate of the world
## does not hide it while it still moves with the camera.

@export var heard_color := Color(0.92, 0.3, 0.22, 0.95)
@export var flash_time := 1.6

var _edges: Array[Dictionary] = []


## Flashes the listener edge from `edge_from` to `edge_to` (global).
func flash(edge_from: Vector2, edge_to: Vector2) -> void:
	_edges.append({"from": edge_from, "to": edge_to, "age": 0.0})


func clear() -> void:
	_edges.clear()


func _process(delta: float) -> void:
	for edge in _edges:
		edge.age += delta
	_edges = _edges.filter(func(edge): return edge.age < flash_time)
	queue_redraw()


func _draw() -> void:
	for edge in _edges:
		var color := heard_color
		color.a *= 1.0 - edge.age / flash_time
		draw_line(edge.from, edge.to, color, 4.0, true)
