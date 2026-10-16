@tool
extends RefCounted
## Pelvis selection and per-foot contacts for sparse authored leg sheets.
## PlayerMotion supplies the gait; this solver preserves each support contact.

const STEP := PI / 4.0
const DIRECTIONS := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const PASSING_FRAMES := [2, 6]
const TURN_FRAME_SECONDS := 0.075
const MAX_OFFSET := 12.0
const MIN_BOOT_SPACING := 9.05
const RECOVERY_SPEED := 100.0

var heading := PI / 2.0
var direction := "s"
var is_turning := false
var turn_frame := 0
var last_result: Dictionary = {}

var _travel_heading := PI / 2.0
var _backward := false
var _was_moving := false
var _last_frame := -1
var _last_state := ""
var _frame_elapsed := 0.0
var _pose_duration := 0.9 / 8.0
var _pose_durations: Array[float] = []
var _previous_origin := Vector2.ZERO
var _has_origin := false
var _turn_sign := 1
var _turn_elapsed := 0.0
var _replants := 0
var _feet: Dictionary = {}


func reset(initial_heading: float) -> void:
	heading = _quantize(initial_heading)
	direction = "s"
	_travel_heading = heading
	_backward = false
	_was_moving = false
	_last_frame = -1
	_last_state = ""
	_frame_elapsed = 0.0
	_pose_duration = 0.9 / 8.0
	_pose_durations.clear()
	_has_origin = false
	is_turning = false
	turn_frame = 0
	_turn_elapsed = 0.0
	_replants = 0
	_feet.clear()
	last_result.clear()


func advance(delta: float, state: String, frame: int, moving: bool,
		travel_angle: float, body_angle: float, world_origin: Vector2,
		ground_offset: Vector2, scale: float, rig_layers: RefCounted) -> Dictionary:
	delta = maxf(delta, 0.0)
	var velocity := Vector2.ZERO
	if _has_origin and delta > 0.0:
		velocity = (world_origin - _previous_origin) / delta
	_previous_origin = world_origin
	_has_origin = true
	var new_frame := frame != _last_frame or state != _last_state
	_frame_elapsed += delta
	if new_frame:
		if state != _last_state:
			_pose_durations.clear()
			_pose_duration = rig_layers.get_cycle_seconds(state) / 8.0
		if _last_frame >= 0 and moving and _was_moving and state == _last_state and _frame_elapsed > 0.0:
			_pose_durations.append(clampf(_frame_elapsed, 0.04, 0.25))
			if _pose_durations.size() > 8:
				_pose_durations.pop_front()
			_pose_duration = 0.0
			for duration in _pose_durations:
				_pose_duration += duration / _pose_durations.size()
		_frame_elapsed = 0.0
	var pose: Dictionary
	if moving:
		_update_travel_heading(travel_angle, body_angle, not _was_moving)
		if not _was_moving or (new_frame and frame in PASSING_FRAMES):
			_commit_heading(travel_angle)
		is_turning = false
		_turn_elapsed = 0.0
		pose = rig_layers.get_lower_pose(state, frame, direction)
	elif state == "idle":
		pose = _idle_pose(delta, body_angle, rig_layers)
	else:
		# Retain the authored gather frames while locomotion settles to idle.
		pose = rig_layers.get_lower_pose(state, frame, direction)
	var pivot := _point(pose.get("pivot", Vector2(128, 128)))
	var metadata: Dictionary = pose["metadata"]
	var offsets: Dictionary = {}
	var boots: Dictionary = {}
	var contacts: Dictionary = {}
	var rotations: Dictionary = {}
	var toes: Dictionary = {}
	for side in ["left", "right"]:
		var leg: Dictionary = metadata[side]
		var landing_bias := _landing_bias(side, state, frame, velocity, scale, delta, rig_layers) if moving else Vector2.ZERO
		_advance_foot(side, leg, pivot, world_origin, ground_offset,
			scale, landing_bias, delta, moving and _was_moving and state != _last_state)
	_clear_boot_overlap()
	for side in ["left", "right"]:
		var result: Dictionary = _feet[side]
		offsets[side] = result["offset"]
		boots[side] = result["world"]
		contacts[side] = result["contact"]
		rotations[side] = result["rotation"]
		toes[side] = result["toe"]
	_last_frame = frame
	_last_state = state
	_was_moving = moving
	last_result = {
		"pose": pose, "heading": heading, "offsets": offsets, "boots": boots,
		"contacts": contacts, "rotations": rotations, "toes": toes,
		"turning": is_turning, "direction": direction,
		"frame": turn_frame if is_turning else frame, "replants": _replants,
	}
	return last_result


func _update_travel_heading(travel_angle: float, body_angle: float, starting: bool) -> void:
	if starting or absf(angle_difference(_travel_heading, travel_angle)) > STEP * 0.5 + deg_to_rad(7.0):
		_travel_heading = _quantize(travel_angle)
	var aim_difference := absf(angle_difference(_travel_heading, body_angle))
	if starting:
		_backward = aim_difference > PI / 2.0
	elif _backward and aim_difference < deg_to_rad(75.0):
		_backward = false
	elif not _backward and aim_difference > deg_to_rad(105.0):
		_backward = true


func _commit_heading(travel_angle: float) -> void:
	var desired := _travel_heading + (PI if _backward else 0.0)
	var difference := angle_difference(heading, desired)
	var candidate := heading + clampf(difference, -STEP, STEP)
	# A long sideways interval cannot match full travel with a short correction
	# stride. Commit the travel axis at this safe handoff; planted legs retain
	# their own world angle and center until each is free to take its next step.
	var axis_difference := minf(absf(angle_difference(candidate, travel_angle)),
		absf(angle_difference(candidate + PI, travel_angle)))
	if axis_difference >= STEP - 0.001 and absf(difference) < PI - 0.001:
		candidate = desired
	heading = _quantize(candidate)
	var relative := _travel_heading - (heading - PI / 2.0)
	direction = DIRECTIONS[posmod(roundi(relative / STEP), 8)]


func _idle_pose(delta: float, body_angle: float, rig_layers: RefCounted) -> Dictionary:
	if is_turning:
		_turn_elapsed += delta
		if _turn_elapsed >= TURN_FRAME_SECONDS:
			_turn_elapsed -= TURN_FRAME_SECONDS
			if turn_frame < 3:
				turn_frame += 1
			else:
				heading = _quantize(heading + _turn_sign * STEP)
				is_turning = false
				_turn_elapsed = 0.0
				return rig_layers.get_lower_pose("idle", 0, "s")
	if not is_turning:
		var difference := angle_difference(heading, body_angle)
		if absf(difference) > STEP * 0.5 + deg_to_rad(7.0):
			_turn_sign = 1 if difference > 0.0 else -1
			turn_frame = 0
			_turn_elapsed = 0.0
			is_turning = true
	if is_turning:
		return rig_layers.get_turn_pose(_turn_sign, turn_frame)
	return rig_layers.get_lower_pose("idle", 0, "s")


func _advance_foot(side: String, leg: Dictionary, pivot: Vector2,
		world_origin: Vector2, ground_offset: Vector2, scale: float,
		landing_bias: Vector2, delta: float, rebase_swing := false) -> Dictionary:
	if not _feet.has(side):
		_feet[side] = {
			"valid": false, "contact": false, "released": false,
			"anchor": Vector2.ZERO, "world": Vector2.ZERO, "offset": Vector2.ZERO,
			"rotation": heading, "toe": 0.0,
			"swing_from": Vector2.ZERO, "swing_start": 0.0,
		}
	var foot: Dictionary = _feet[side]
	var was_contact := bool(foot["contact"])
	var authored_contact: bool = leg["contact"]
	var local_toe := float(leg["toe_angle"])
	var progress := float(leg.get("swing_progress", 0.0))
	var rotation := heading
	if authored_contact and foot["contact"]:
		rotation = float(foot["toe"]) - local_toe + PI / 2.0
	var local_boot := ground_offset + ((_point(leg["boot"]) - pivot) * scale).rotated(rotation - PI / 2.0)
	var nominal := world_origin + local_boot
	var contact := authored_contact and not bool(foot["released"])
	var offset: Vector2 = foot["offset"]
	if contact:
		if not foot["contact"]:
			foot["anchor"] = nominal + landing_bias
			foot["toe"] = rotation - PI / 2.0 + local_toe
		offset = Vector2(foot["anchor"]) - nominal
		if offset.length() > MAX_OFFSET + 0.001:
			# Abrupt reversals or stops can exceed a coat-hidden attachment.
			# Release this contact explicitly and recover, rather than teleporting
			# a still-planted foot or letting the trouser detach from the pelvis.
			contact = false
			foot["released"] = true
			_replants += 1
			offset = offset.limit_length(MAX_OFFSET)
	elif not authored_contact:
		if foot["contact"] or foot["released"] or not foot["valid"] or rebase_swing:
			# A new gait uses different nominal geometry. Carry the visible free
			# foot into that swing instead of snapping to its new authored boot.
			var carried := Vector2(foot["world"]) - nominal if foot["valid"] else Vector2.ZERO
			foot["swing_from"] = carried.limit_length(MAX_OFFSET)
			foot["swing_start"] = progress
		foot["released"] = false
		var fraction := clampf((progress - float(foot["swing_start"])) / maxf(0.001, 1.0 - float(foot["swing_start"])), 0.0, 1.0)
		fraction = fraction * fraction * (3.0 - 2.0 * fraction)
		offset = Vector2(foot["swing_from"]).lerp(landing_bias, fraction)
	else:
		# Recover a released leg in the air; a settled idle foot may plant again.
		offset = offset.move_toward(landing_bias, RECOVERY_SPEED * delta)
		if not _was_moving and not is_turning and offset.length() < 0.01:
			contact = true
			foot["released"] = false
			foot["anchor"] = nominal + offset
	offset = offset.limit_length(MAX_OFFSET)
	foot["nominal"] = nominal
	foot["offset"] = offset
	foot["world"] = nominal + offset
	foot["rotation"] = rotation
	foot["toe"] = rotation - PI / 2.0 + local_toe
	foot["contact"] = contact
	foot["continuing"] = contact and was_contact
	foot["valid"] = true
	return foot


func _landing_bias(side: String, state: String, frame: int, velocity: Vector2,
		scale: float, delta: float, rig_layers: RefCounted) -> Vector2:
	# Center the reachable stance around the actual root displacement and the
	# authored backward foot stroke. This also accommodates the slower breath
	# cadence without inventing another animation clock.
	if velocity.is_zero_approx():
		return Vector2.ZERO
	var first_frame := frame
	for ahead in range(8):
		var next: Dictionary = rig_layers.get_lower_pose(state, frame + ahead, direction)["metadata"][side]
		if next["contact"]:
			first_frame = frame + ahead
			break
	var first: Dictionary = rig_layers.get_lower_pose(state, first_frame, direction)["metadata"][side]
	var origin := _point(first["boot"])
	var minimum := Vector2.ZERO
	var maximum := Vector2.ZERO
	for ahead in range(8):
		var next: Dictionary = rig_layers.get_lower_pose(state, first_frame + ahead, direction)["metadata"][side]
		if not next["contact"]:
			break
		var sample := velocity * _pose_duration * ahead + ((_point(next["boot"]) - origin) * scale).rotated(heading - PI / 2.0)
		var held_end := sample + velocity * maxf(0.0, _pose_duration - delta * 0.5)
		minimum = minimum.min(sample).min(held_end)
		maximum = maximum.max(sample).max(held_end)
	return ((minimum + maximum) * 0.5).limit_length(MAX_OFFSET)


func _clear_boot_overlap() -> void:
	var left: Dictionary = _feet["left"]
	var right: Dictionary = _feet["right"]
	if Vector2(left["world"]).distance_to(right["world"]) >= MIN_BOOT_SPACING:
		return
	# A planted boot owns its spot. Redirect the free leg's short correction
	# step instead of allowing opposite-facing sheets to meet at that spot.
	var side := "left" if not left["continuing"] else "right"
	if left["contact"] and not right["contact"]:
		side = "right"
	var foot: Dictionary = _feet[side]
	var support: Dictionary = _feet["right" if side == "left" else "left"]
	var apart := Vector2(foot["world"]) - Vector2(support["world"])
	var lane := Vector2.RIGHT if side == "left" else Vector2.LEFT
	lane = lane.rotated(heading - PI / 2.0)
	if apart.length_squared() < 0.01:
		apart = lane
	var target := Vector2(support["world"]) + apart.normalized() * MIN_BOOT_SPACING
	var offset := (target - Vector2(foot["nominal"])).limit_length(MAX_OFFSET)
	if (Vector2(foot["nominal"]) + offset).distance_to(support["world"]) < MIN_BOOT_SPACING - 0.001:
		apart = Vector2(foot["nominal"]) - Vector2(support["world"])
		if apart.length_squared() < 0.01:
			apart = lane
		offset = apart.normalized() * MAX_OFFSET
	if foot["continuing"]:
		foot["contact"] = false
		foot["released"] = true
		_replants += 1
	foot["offset"] = offset
	foot["world"] = Vector2(foot["nominal"]) + offset
	if foot["contact"]:
		foot["anchor"] = foot["world"]


func _quantize(angle: float) -> float:
	return wrapf(roundf(angle / STEP) * STEP, -PI, PI)


func _point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	return Vector2(float(value[0]), float(value[1]))
