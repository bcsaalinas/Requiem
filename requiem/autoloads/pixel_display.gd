extends Node
## The whole display in one place.
##
## The world always renders into a fixed 1920x1080 image (WorldView), so every player sees
## exactly the same part of the world on any screen. That image is scaled to the window by
## pixel_display.gdshader: nearest at whole-number scales, sharp bilinear in between, a box
## downscale below 1080p, with black bars on other aspect ratios. The UI is drawn natively on
## top at the window's real resolution, laid out on a 1280x720 canvas and scaled by ui_scale,
## so text is sharp everywhere.
##
## The world still lives in the root window's canvas: cameras only render it into WorldView
## (custom_viewport), and the root hides it with canvas_cull_mask. The root canvas transform is
## kept equal to "world -> window pixels" so mouse aim, prompts and follow-viewport layers work.

signal layout_changed

const WORLD_SIZE := Vector2i(1920, 1080)
const WORLD_BIT := 1 << 19
const UI_CANVAS := Vector2(1280, 720)
const SNAP_TOLERANCE_PX := 2.0
const DISPLAY_LAYER := -128
const LATE_PRIORITY := 1000
const ORIGIN_EPSILON := 0.001

var world_view: SubViewport
var _display_layer: CanvasLayer
var _bars: ColorRect
var _image: TextureRect
var _cameras: Array[Camera2D] = []
var _layout: Dictionary = {}


## Where the world image and the UI canvas sit in a window of the given pixel size.
## Returns image_rect (Rect2i), image_scale (float), ui_origin (Vector2) and ui_scale (float).
static func layout_for(window: Vector2i, pixel_perfect: bool) -> Dictionary:
	var fit := minf(float(window.x) / WORLD_SIZE.x, float(window.y) / WORLD_SIZE.y)
	var image_scale := fit
	if pixel_perfect:
		if fit >= 1.0:
			image_scale = floorf(fit)
	else:
		var whole := roundf(fit)
		if whole >= 1.0 and absf(fit * WORLD_SIZE.x - whole * WORLD_SIZE.x) <= SNAP_TOLERANCE_PX \
				and absf(fit * WORLD_SIZE.y - whole * WORLD_SIZE.y) <= SNAP_TOLERANCE_PX:
			image_scale = whole
	var image_size := Vector2i(roundi(WORLD_SIZE.x * image_scale), roundi(WORLD_SIZE.y * image_scale))
	var image_origin := Vector2i(((Vector2(window) - Vector2(image_size)) * 0.5).floor())
	var ui_scale := minf(window.x / UI_CANVAS.x, window.y / UI_CANVAS.y)
	return {
		"image_rect": Rect2i(image_origin, image_size),
		"image_scale": image_scale,
		"ui_origin": ((Vector2(window) - UI_CANVAS * ui_scale) * 0.5 + Vector2.ONE * ORIGIN_EPSILON).floor(),
		"ui_scale": ui_scale,
	}


## The layout for the current root window size and display mode.
func layout() -> Dictionary:
	var root := (Engine.get_main_loop() as SceneTree).root
	return layout_for(root.size, Preferences.display_mode == Preferences.DISPLAY_PIXEL_PERFECT)


## Window pixels to the 1280x720 UI canvas.
func to_ui(window_point: Vector2) -> Vector2:
	var current := layout()
	return (window_point - current["ui_origin"]) / current["ui_scale"]


## World position into the legacy UI's 1280 x 720 coordinate space.
func world_to_ui(world_point: Vector2) -> Vector2:
	var current := layout()
	var view_point: Vector2 = world_view.get_canvas_transform() * world_point
	var image_rect: Rect2i = current["image_rect"]
	var window_point := Vector2(image_rect.position) + view_point * float(current["image_scale"])
	return to_ui(window_point)


func _init() -> void:
	world_view = SubViewport.new()
	world_view.name = "WorldView"
	world_view.size = WORLD_SIZE
	world_view.world_2d = (Engine.get_main_loop() as SceneTree).root.world_2d
	world_view.transparent_bg = false
	world_view.disable_3d = true
	world_view.audio_listener_enable_2d = false
	world_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	world_view.snap_2d_transforms_to_pixel = true
	world_view.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Set up on entering the tree rather than in _ready: when the main scene is a game scene (F6, or
## the editor's Run Current Scene) its nodes enter the tree before any autoload is ready.
func _enter_tree() -> void:
	process_priority = LATE_PRIORITY
	var root := get_tree().root
	if DisplayServer.get_name() == "headless":
		root.size = WORLD_SIZE
	add_child(world_view)
	root.canvas_cull_mask = ~WORLD_BIT

	_display_layer = CanvasLayer.new()
	_display_layer.layer = DISPLAY_LAYER
	add_child(_display_layer)
	_bars = ColorRect.new()
	_bars.color = Color.BLACK
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display_layer.add_child(_bars)
	_image = TextureRect.new()
	_image.texture = world_view.get_texture()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.material = ShaderMaterial.new()
	_image.material.shader = preload("res://autoloads/pixel_display.gdshader")
	_image.hide()
	_display_layer.add_child(_image)

	root.size_changed.connect(_refresh)
	Preferences.display_mode_changed.connect(_refresh)
	RenderingServer.frame_pre_draw.connect(_apply_composite_transform)
	get_tree().node_added.connect(_mark_world)
	_mark_world_tree(root)
	_refresh()


func _process(_delta: float) -> void:
	_apply_composite_transform()


## Renders the world through this camera into WorldView and shows the image. The camera must get
## its custom_viewport before it enters the tree (see PixelCamera._init), or it stays current in
## the root window.
func attach_camera(camera: Camera2D) -> void:
	if camera.custom_viewport != world_view:
		camera.custom_viewport = world_view
	if not _cameras.has(camera):
		_cameras.append(camera)
	_update_active()


func detach_camera(camera: Camera2D) -> void:
	_cameras.erase(camera)
	_update_active()


## For CanvasLayers that post-process the world (they render into WorldView, not the window).
func attach_world_layer(layer: CanvasLayer) -> void:
	layer.custom_viewport = world_view


## True while a camera renders the world.
func has_camera() -> bool:
	return not _cameras.is_empty()


func _update_active() -> void:
	var active := not _cameras.is_empty()
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	_image.visible = active
	if not active:
		get_tree().root.canvas_transform = Transform2D.IDENTITY


func _refresh() -> void:
	_layout = layout()
	var rect: Rect2i = _layout["image_rect"]
	_image.position = Vector2(rect.position)
	_image.size = Vector2(rect.size)
	var material := _image.material as ShaderMaterial
	material.set_shader_parameter("source_size", Vector2(WORLD_SIZE))
	material.set_shader_parameter("image_scale", float(rect.size.x) / WORLD_SIZE.x)
	get_tree().root.oversampling_override = _layout["ui_scale"]
	_apply_composite_transform()
	layout_changed.emit()


func _apply_composite_transform() -> void:
	if _cameras.is_empty() or _layout.is_empty():
		return
	var rect: Rect2i = _layout["image_rect"]
	var fit := Transform2D(0.0, Vector2.ONE * (float(rect.size.x) / WORLD_SIZE.x), 0.0, Vector2(rect.position))
	get_tree().root.canvas_transform = fit * world_view.canvas_transform


func _mark_world(node: Node) -> void:
	var item := node as Node2D
	if item == null or item.get_parent() is CanvasItem or item.get_canvas_layer_node() != null:
		return
	if item.get_viewport() == get_tree().root:
		item.visibility_layer = WORLD_BIT


func _mark_world_tree(node: Node) -> void:
	_mark_world(node)
	for child in node.get_children():
		_mark_world_tree(child)
