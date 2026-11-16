class_name LegacyUi
extends RefCounted
## The legacy UIs were laid out on a 1280x720 canvas that canvas_items stretch scaled by 1.5 to 1080p.
## With viewport stretch that scaling is gone, so each legacy UI gets its 1280x720 canvas back and is
## scaled explicitly. UI drawn later at 960x540 uses the same pattern with a scale of 2.

const CANVAS := Vector2(1280, 720)
const SCALE := 1.5


## For full-screen roots: anchors resolve against the viewport and ignore a CanvasLayer scale, so the
## root itself is resized and scaled.
static func fit_root(root: Control) -> void:
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = CANVAS
	root.scale = Vector2.ONE * SCALE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## For layers whose children use fixed 1280x720 positions and no full-screen root.
static func fit_layer(layer: CanvasLayer) -> void:
	layer.scale = Vector2.ONE * SCALE
