class_name CharacterSprite
extends Node2D
## A character built from stacked art-lab sheets: Lower, Upper, ArmRight and Head, each a Sprite2D
## with the sheet as hframes (160x160 frames, pivot (80, 80)). Nothing here is specific to one
## character: the player, the ranger and Eli all use it. The art faces south, so the node rotates by
## facing - PI/2. Each layer plays its own clip; head poses are picked from the five head frames.

signal sound_frame(part: StringName, clip: StringName, frame: int)
signal event_frame(kind: StringName, clip: StringName, frame: int)
signal clip_finished(part: StringName, clip: StringName)

const PARTS: Array[StringName] = [&"lower", &"upper", &"arm_right", &"head"]
const PIVOT := Vector2(80, 80)
const HEAD_POSE_DEGREES := [70.0, 35.0, 0.0, -35.0, -70.0]
const HEAD_POSES_CLIP := "girl_head_poses"
const STEP_RADIANS := PI / 8.0

## Displayed rotation snaps to 22.5 degrees when true (gameplay facing is unchanged).
var steps_mode := false
var facing := PI / 2.0
var head_turn_deg := 0.0
var mirror := false

var _layers := {}
var _players := {}
var _head_pose_clip := {}


func _init() -> void:
	for part in PARTS:
		var sprite := Sprite2D.new()
		sprite.name = String(part).capitalize().replace("_", "")
		sprite.centered = true
		sprite.scale = Vector2.ONE * Units.ART_SCALE
		sprite.visible = false
		add_child(sprite)
		_layers[part] = sprite
		_players[part] = {"clip": {}, "frame": 0, "time": 0.0, "rate": 1.0, "reverse": false, "loop": true,
			"hold_last": false, "finished": false, "last_frame": -1}
	_head_pose_clip = CharacterClips.get_clip(HEAD_POSES_CLIP)
	_apply_rotation()


func _process(delta: float) -> void:
	for part in PARTS:
		_advance(part, delta)
	_refresh_layout()


## Starts a clip on one layer. Options: rate, reverse, mirror, loop, hold_last, frame, restart.
func play(part: StringName, sheet_name: String, options := {}) -> void:
	var state: Dictionary = _players[part]
	var clip := CharacterClips.get_clip(sheet_name)
	var same: bool = not clip.is_empty() and state["clip"].get("name", "") == clip.get("name", "x")
	if same and not options.get("restart", false):
		state["rate"] = options.get("rate", state["rate"])
		state["reverse"] = options.get("reverse", state["reverse"])
		return
	state["clip"] = clip
	state["rate"] = options.get("rate", 1.0)
	state["reverse"] = options.get("reverse", false)
	state["loop"] = options.get("loop", clip.get("loop", true) if not clip.is_empty() else true)
	state["hold_last"] = options.get("hold_last", clip.get("hold_last_frame", false) if not clip.is_empty() else false)
	state["finished"] = false
	state["last_frame"] = -1
	var frame_count: int = clip["frames"].size() if not clip.is_empty() else 0
	state["frame"] = clampi(options.get("frame", frame_count - 1 if state["reverse"] else 0), 0, maxi(frame_count - 1, 0))
	state["time"] = 0.0
	var sprite: Sprite2D = _layers[part]
	sprite.visible = not clip.is_empty() and part != &"head"
	if not clip.is_empty():
		sprite.texture = clip["texture"]
		sprite.hframes = clip["hframes"]
		sprite.frame = state["frame"]
	_refresh_layout()


func stop(part: StringName) -> void:
	(_players[part] as Dictionary)["clip"] = {}
	(_layers[part] as Sprite2D).visible = false
	if part == &"head":
		_refresh_layout()


func set_mirror(value: bool) -> void:
	mirror = value
	_refresh_layout()


func set_rate(part: StringName, rate: float, reverse := false) -> void:
	(_players[part] as Dictionary)["rate"] = rate
	(_players[part] as Dictionary)["reverse"] = reverse


func clip_name(part: StringName) -> String:
	return (_players[part] as Dictionary)["clip"].get("name", "")


func frame_of(part: StringName) -> int:
	return (_players[part] as Dictionary)["frame"]


func is_finished(part: StringName) -> bool:
	return (_players[part] as Dictionary)["finished"]


func set_frame(part: StringName, frame: int) -> void:
	var state: Dictionary = _players[part]
	var count: int = state["clip"]["frames"].size() if not state["clip"].is_empty() else 0
	state["frame"] = clampi(frame, 0, maxi(count - 1, 0))
	state["time"] = 0.0
	state["last_frame"] = -1
	_refresh_layout()


## Shows a head pose (girl_head_poses) for the turn of the head against the upper body.
func set_head_turn(degrees: float) -> void:
	head_turn_deg = degrees


func set_facing(angle: float) -> void:
	facing = angle
	_apply_rotation()


func hide_head() -> void:
	(_layers[&"head"] as Sprite2D).visible = false
	(_players[&"head"] as Dictionary)["clip"] = {}


## Global position of an anchor (hand_right, hand_left, flashlight_tip, head_center, hip_center).
func anchor_global(anchor: String) -> Vector2:
	return to_global(_anchor_local(anchor))


func flashlight_tip_global() -> Vector2:
	return anchor_global("flashlight_tip")


## Direction of the beam in global radians: the art's flashlight angle (degrees out from straight
## ahead, which is south in the art) rotated by the node.
func flashlight_angle_global() -> float:
	var anchors: Dictionary = _frame_data(&"arm_right").get("anchors", {})
	if not anchors.has("flashlight_angle_deg"):
		anchors = _frame_data(&"upper").get("anchors", {})
	var degrees: float = anchors.get("flashlight_angle_deg", 0.0)
	if mirror:
		degrees = -degrees
	return global_rotation + PI / 2.0 + deg_to_rad(degrees)


func has_anchor(anchor: String) -> bool:
	for part in [&"arm_right", &"upper", &"lower", &"head"]:
		if _frame_data(part).get("anchors", {}).has(anchor):
			return true
	return false


# --- Internals --------------------------------------------------------------

func _frame_data(part: StringName) -> Dictionary:
	var state: Dictionary = _players[part]
	var clip: Dictionary = state["clip"]
	if clip.is_empty():
		return {}
	var frames: Array = clip["frames"]
	return frames[clampi(state["frame"], 0, frames.size() - 1)] if not frames.is_empty() else {}


func _anchor_local(anchor: String) -> Vector2:
	for part in [&"arm_right", &"upper", &"lower", &"head"]:
		var anchors: Dictionary = _frame_data(part).get("anchors", {})
		if anchors.has(anchor):
			var point := Vector2(anchors[anchor][0], anchors[anchor][1])
			if part == &"upper" or part == &"arm_right":
				point += _frame_data(&"upper").get("upper_offset", Vector2.ZERO) if part == &"arm_right" else Vector2.ZERO
			return _art_to_local(point)
	if anchor == "head_center" and _head_pose_clip.has("frames"):
		var anchors: Dictionary = _head_pose_clip["frames"][_head_frame()].get("anchors", {})
		if anchors.has("head_center"):
			return _art_to_local(Vector2(anchors["head_center"][0], anchors["head_center"][1]) + _head_offset())
	return Vector2.ZERO


func _art_to_local(art_point: Vector2) -> Vector2:
	var point := art_point - PIVOT
	if mirror:
		point.x = -point.x
	return point * Units.ART_SCALE


func _head_frame() -> int:
	var best := 0
	var best_distance := INF
	for index in HEAD_POSE_DEGREES.size():
		var distance := absf(float(HEAD_POSE_DEGREES[index]) - head_turn_deg)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


func _head_offset() -> Vector2:
	var offset: Vector2 = _frame_data(&"upper").get("head_offset", Vector2.ZERO)
	offset += _frame_data(&"upper").get("upper_offset", Vector2.ZERO)
	return offset


func _advance(part: StringName, delta: float) -> void:
	var state: Dictionary = _players[part]
	var clip: Dictionary = state["clip"]
	if clip.is_empty() or state["finished"]:
		_emit_frame_events(part)
		return
	var frames: Array = clip["frames"]
	var rate := maxf(state["rate"], 0.0)
	state["time"] += delta * 1000.0 * rate
	while frames.size() > 1 and state["time"] >= float(frames[state["frame"]]["ms"]):
		state["time"] -= float(frames[state["frame"]]["ms"])
		var next: int = state["frame"] + (-1 if state["reverse"] else 1)
		if next >= frames.size() or next < 0:
			if state["loop"]:
				next = frames.size() - 1 if state["reverse"] else 0
			else:
				state["finished"] = true
				clip_finished.emit(part, StringName(clip["name"]))
				if not state["hold_last"]:
					state["frame"] = 0 if state["reverse"] else frames.size() - 1
				break
		state["frame"] = next
		_emit_frame_events(part)
	_emit_frame_events(part)


func _emit_frame_events(part: StringName) -> void:
	var state: Dictionary = _players[part]
	var clip: Dictionary = state["clip"]
	if clip.is_empty() or state["last_frame"] == state["frame"]:
		return
	state["last_frame"] = state["frame"]
	var frame: int = state["frame"]
	if frame in clip["sound_frames"]:
		sound_frame.emit(part, StringName(clip["name"]), frame)
	if frame == clip["projectile_frame"]:
		event_frame.emit(&"projectile", StringName(clip["name"]), frame)
	if frame == clip["action_frame"]:
		event_frame.emit(&"action", StringName(clip["name"]), frame)


func _refresh_layout() -> void:
	var upper_data := _frame_data(&"upper")
	var upper_offset: Vector2 = upper_data.get("upper_offset", Vector2.ZERO)
	for part in PARTS:
		var sprite: Sprite2D = _layers[part]
		var state: Dictionary = _players[part]
		sprite.flip_h = mirror
		if part == &"head":
			_refresh_head(sprite, upper_data)
			continue
		if state["clip"].is_empty():
			continue
		sprite.frame = state["frame"]
		var offset := upper_offset if part == &"upper" or part == &"arm_right" else Vector2.ZERO
		sprite.offset = _mirrored(offset)


func _refresh_head(sprite: Sprite2D, upper_data: Dictionary) -> void:
	var sprint_head: Dictionary = (_players[&"head"] as Dictionary)["clip"]
	if not sprint_head.is_empty():
		sprite.visible = true
		sprite.texture = sprint_head["texture"]
		sprite.hframes = sprint_head["hframes"]
		sprite.frame = (_players[&"head"] as Dictionary)["frame"]
		sprite.offset = Vector2.ZERO
		return
	if _head_pose_clip.is_empty() or upper_data.is_empty() or not (_layers[&"head"] as Sprite2D).visible and not head_enabled:
		sprite.visible = false
		return
	sprite.visible = true
	sprite.texture = _head_pose_clip["texture"]
	sprite.hframes = _head_pose_clip["hframes"]
	sprite.frame = _head_frame()
	sprite.offset = _mirrored(_head_offset())


var head_enabled := true


func _mirrored(offset: Vector2) -> Vector2:
	return Vector2(-offset.x if mirror else offset.x, offset.y)


func _apply_rotation() -> void:
	var angle := facing - PI / 2.0
	rotation = snappedf(angle, STEP_RADIANS) if steps_mode else angle
