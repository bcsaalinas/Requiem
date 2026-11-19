extends Node2D
## A pile of throwable pebbles seen from straight above. Three pebbles glint, in turn, where light falls.

const GLINT_STARTS := {"A/Glint": 0.0, "B2/Glint": 0.21, "C3/Glint": 0.43}


func _ready() -> void:
	for path in GLINT_STARTS:
		var glint := get_node(path) as AnimatedSprite2D
		var time: float = GLINT_STARTS[path]
		var frame := 0
		var length := glint.sprite_frames.get_frame_duration(&"glint", frame)
		while time >= length:
			time -= length
			frame += 1
			length = glint.sprite_frames.get_frame_duration(&"glint", frame)
		glint.set_frame_and_progress(frame, time / length)


## Piles take part in the tutorial interaction highlight; the art itself does not react.
func set_focused(_value: bool) -> void:
	pass
