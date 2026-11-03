class_name SafeLight
extends Area2D
## A lit refuge in the parents' hallway: noises made inside it are never heard by the parents.
## The rectangle of its CollisionShape2D is the safe area, so designers see it in the editor.


func contains(point: Vector2) -> bool:
	for child in get_children():
		var shape := child as CollisionShape2D
		if shape != null and shape.shape is RectangleShape2D:
			var size: Vector2 = (shape.shape as RectangleShape2D).size
			if Rect2(-size * 0.5, size).has_point(shape.to_local(point)):
				return true
	return false
