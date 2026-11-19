class_name LegacyUi
extends RefCounted
## The legacy UIs were laid out on a 1280x720 canvas. They are drawn natively at the window's
## real resolution: the canvas is scaled by the UI factor and centred (PixelDisplay.layout), and
## refitted whenever the window or display mode changes. UI drawn later at 960x540 would use the
## same pattern with its own canvas size.

static var _roots: Array[Control] = []
static var _layers: Array[CanvasLayer] = []
static var _connected := false


## For full-screen roots: anchors resolve against the window and ignore a CanvasLayer scale, so the
## root itself is resized, scaled and placed.
static func fit_root(root: Control) -> void:
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.size = PixelDisplay.UI_CANVAS
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_roots.append(root)
	_track()
	_place(root)


## For layers whose children use fixed 1280x720 positions and no full-screen root.
static func fit_layer(layer: CanvasLayer) -> void:
	_layers.append(layer)
	_track()
	_place_layer(layer)


## Window pixels to the 1280x720 UI canvas.
static func to_ui(window_point: Vector2) -> Vector2:
	return PixelDisplay.to_ui(window_point)


static func _track() -> void:
	if not _connected:
		_connected = true
		PixelDisplay.layout_changed.connect(_refit)


static func _refit() -> void:
	var valid_roots: Array[Control] = []
	for root in _roots:
		if is_instance_valid(root):
			valid_roots.append(root)
	_roots = valid_roots
	var valid_layers: Array[CanvasLayer] = []
	for layer in _layers:
		if is_instance_valid(layer):
			valid_layers.append(layer)
	_layers = valid_layers
	for root in _roots:
		_place(root)
	for layer in _layers:
		_place_layer(layer)


static func _place(root: Control) -> void:
	var current := PixelDisplay.layout()
	root.position = current["ui_origin"]
	root.scale = Vector2.ONE * float(current["ui_scale"])


static func _place_layer(layer: CanvasLayer) -> void:
	var current := PixelDisplay.layout()
	layer.offset = current["ui_origin"]
	layer.scale = Vector2.ONE * float(current["ui_scale"])
