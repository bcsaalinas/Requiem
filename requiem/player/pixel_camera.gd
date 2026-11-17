class_name PixelCamera
extends Camera2D
## Follows the parent like Camera2D position smoothing, but the view centre always lands on a
## whole screen pixel, so art never shimmers against the floor while scrolling.

const GRID_EPSILON := 0.001

@export var follow_speed := 5.0
@export var teleport_distance_u := 3.0

var _smoothed := Vector2.ZERO
var _last_target := Vector2.ZERO
var _was_enabled := false


func _init() -> void:
	custom_viewport = PixelDisplay.world_view


func _enter_tree() -> void:
	PixelDisplay.attach_camera(self)


func _exit_tree() -> void:
	PixelDisplay.detach_camera(self)


func _ready() -> void:
	top_level = true
	position_smoothing_enabled = false
	zoom = Vector2.ONE * Units.CAMERA_ZOOM
	snap_to_target()


func _process(delta: float) -> void:
	if not enabled:
		_was_enabled = false
		return
	var target := _target()
	if not _was_enabled or target.distance_to(_last_target) > Units.to_px(teleport_distance_u):
		_smoothed = target
	else:
		_smoothed += (target - _smoothed) * minf(follow_speed * delta, 1.0)
	_was_enabled = true
	_last_target = target
	_apply()


## Jumps straight to the parent, e.g. on zone changes.
func snap_to_target() -> void:
	_last_target = _target()
	_smoothed = _last_target
	_apply()


func _target() -> Vector2:
	var parent := get_parent() as Node2D
	return parent.global_position if parent != null else global_position


func _apply() -> void:
	var step := Vector2.ONE / zoom
	var half_view := Vector2(PixelDisplay.WORLD_SIZE) * 0.5 / zoom
	global_position = Vector2(
		_axis(_smoothed.x, limit_left, limit_right, half_view.x, step.x),
		_axis(_smoothed.y, limit_top, limit_bottom, half_view.y, step.y))
	force_update_scroll()


func _axis(value: float, limit_min: int, limit_max: int, half_view: float, step: float) -> float:
	var lo := limit_min + half_view
	var hi := limit_max - half_view
	if lo > hi:
		return snappedf((limit_min + limit_max) * 0.5, step)
	lo = ceilf(lo / step - GRID_EPSILON) * step
	hi = floorf(hi / step + GRID_EPSILON) * step
	return clampf(snappedf(value, step), lo, hi)
