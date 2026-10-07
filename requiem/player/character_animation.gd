@tool
extends RefCounted
## Selects authored views without rotating the sprite or interpolating its pixels.

const DIRECTIONS: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]
const TURN_HYSTERESIS := deg_to_rad(7.0)
const SETTLE_STEP_SECONDS := 0.06

var animation: StringName = &"idle_s"
var frame := 0
var facing: StringName = &"s"
var phase := 0.25
var _direction_index := 2
var _was_moving := false
var _clock_offset := 0.0
var _settle_elapsed := 0.0
var _settling := false
var _settle_frame := 0
var _settle_phase := 0.0


func reset(frames: SpriteFrames) -> void:
	_was_moving = false
	_settling = false
	phase = 0.25
	frame = 0
	animation = _select(frames, "idle")


func advance(frames: SpriteFrames, delta: float, moving: bool,
		direction: Vector2, clock_phase: float, sprint: bool) -> void:
	if frames == null:
		return
	if moving:
		_update_facing(direction)
		if not _was_moving:
			# Restart from the settled pose, even when the footstep clock reset.
			_clock_offset = phase - clock_phase
		phase = fposmod(clock_phase + _clock_offset, 1.0)
		animation = _select(frames, "sprint" if sprint else "walk")
		frame = _frame_at_phase(frames, animation, phase)
		_settling = false
	else:
		if _was_moving:
			_settle_elapsed = 0.0
			_settling = true
			# Passing poses gather both feet under the shared neutral silhouette.
			_settle_phase = floorf(phase * 2.0) * 0.5 + 0.25
			_settle_frame = _frame_at_phase(frames, animation, _settle_phase)
		if _settling:
			_settle_elapsed += delta
			if _settle_elapsed >= SETTLE_STEP_SECONDS:
				frame = _settle_frame
				phase = _settle_phase
			if _settle_elapsed >= SETTLE_STEP_SECONDS * 2.0:
				_settling = false
		if not _settling:
			animation = _select(frames, "idle")
			frame = 0
			# Retain the gathered-foot phase through idle for a connected restart.
	_was_moving = moving


func _update_facing(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	var angle := direction.angle()
	var current_angle := float(_direction_index) * PI / 4.0
	if absf(angle_difference(current_angle, angle)) <= PI / 8.0 + TURN_HYSTERESIS:
		return
	_direction_index = posmod(roundi(angle / (PI / 4.0)), DIRECTIONS.size())
	facing = DIRECTIONS[_direction_index]


func _select(frames: SpriteFrames, state: String) -> StringName:
	var desired := StringName(state + "_" + String(facing))
	if _has_frames(frames, desired):
		return desired
	# A missing action can reuse its matching view, never a rotated south image.
	var walk := StringName("walk_" + String(facing))
	if _has_frames(frames, walk):
		return walk
	if _has_frames(frames, animation):
		return animation
	# Keep older optional skins loadable while a complete resource is authored.
	for fallback in [&"walk_s", &"walk_south"]:
		if _has_frames(frames, fallback):
			return fallback
	return &""


func _has_frames(frames: SpriteFrames, name: StringName) -> bool:
	return frames != null and frames.has_animation(name) and frames.get_frame_count(name) > 0


func _frame_at_phase(frames: SpriteFrames, name: StringName, at: float) -> int:
	if not _has_frames(frames, name):
		return 0
	var count := frames.get_frame_count(name)
	return mini(int(fposmod(at, 1.0) * count), count - 1)
