@tool
extends Node2D
## Light escaping an occupied room, interrupted by moving feet behind its closed door.
@export var phase_offset := 0.0
var clock := 0.0

func _process(delta: float) -> void:
	clock += delta
	var phase := clock + phase_offset
	var shift := sin(phase * 0.7) * 9.0
	$LeftFoot.position = Vector2(-12 + shift, 10 + sin(phase * 1.1) * 1.5)
	$RightFoot.position = Vector2(12 + shift, 10 - sin(phase * 1.1) * 1.5)
	queue_redraw()

func _draw() -> void:
	# Only the narrow slit emits light; actual LightOccluder2D feet cast the floor shadows.
	draw_line(Vector2(-32, 0), Vector2(32, 0), Color("bc765e"), 3)
	for foot in [$LeftFoot, $RightFoot]:
		draw_rect(Rect2(foot.position.x - 4, -2, 8, 5), Color("100d0d"))
