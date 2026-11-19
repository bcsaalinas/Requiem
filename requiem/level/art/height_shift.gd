class_name HeightShift
extends RefCounted
## Wall tops, door leaves and other tall art are drawn shifted away from the screen centre by a
## small fraction of their distance to it, so walls read as having height. The shift is measured
## in whole world-image pixels, so it never breaks the pixel grid.

const DEFAULT_FACTOR := 0.008


## World offset for a point at the given height. Zero in the editor or while no camera is attached.
static func offset_for(world_point: Vector2, factor := DEFAULT_FACTOR) -> Vector2:
	if Engine.is_editor_hint():
		return Vector2.ZERO
	var display := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("PixelDisplay")
	if display == null or display.world_view == null:
		return Vector2.ZERO
	var view_transform: Transform2D = display.world_view.canvas_transform
	var canvas_scale := view_transform.get_scale().x
	if canvas_scale <= 0.0 or not display.has_camera():
		return Vector2.ZERO
	var image_point := view_transform * world_point
	var image_offset := ((image_point - Vector2(display.WORLD_SIZE) / 2.0) * factor).round()
	return image_offset / canvas_scale
