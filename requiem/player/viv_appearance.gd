extends Node2D
## The player's Appearance: hosts the CharacterSprite rig and keeps the entry points the mechanics and
## feedback scripts already call (aim, throw, footsteps, dust, motion, breath/throw/prayer feedback).
## VivAnimator reads the poses these setters store and drives the rig.

signal landed(side: String)

static var _boot_cache := {}

@export var actor_frame_scale := Units.ART_SCALE
var actor_ground_offset := Vector2.ZERO
var actor_motion_offset := Vector2.ZERO
var actor_is_moving := false
var actor_animation: StringName = &"idle_s"
var actor_frame := 0
var actor_facing: StringName = &"s"
var actor_equipped := false
var actor_rig_enabled := true

var breath_track: StringName = &"idle"
var breath_phase := 0.0
var throw_track: StringName = &"idle"
var throw_phase := 0.0
var throw_kind := -1
var prayer_track: StringName = &"idle"
var prayer_phase := 0.0
var prayer_lower_track: StringName = &"idle"
var prayer_lower_phase := 0.0
var pose_body_angle := PI / 2.0
var pose_wrist_angle := PI / 2.0
var pose_arm_step := 0

var rig: CharacterSprite
var _contacts := {"left": false, "right": false}
var _boots := {"left": Vector2.ZERO, "right": Vector2.ZERO}


func _init() -> void:
	rig = CharacterSprite.new()
	rig.name = "Rig"
	add_child(rig)
	rig.sound_frame.connect(_on_sound_frame)


func _process(_delta: float) -> void:
	var clip_name: String = rig.clip_name(&"lower")
	if clip_name == "":
		return
	var points := _boot_points(clip_name, rig.frame_of(&"lower"))
	for side in ["left", "right"]:
		if points.has(side):
			_boots[side] = rig.to_global(rig._art_to_local(points[side]))


func reset_actor_gait() -> void:
	actor_is_moving = false
	_contacts = {"left": false, "right": false}


func set_actor_gait(_cycle_phase: float, moving: bool, _direction := Vector2.ZERO, _equipped := false, _delta := 0.0) -> void:
	actor_is_moving = moving


func set_actor_pose(body_angle: float, wrist_angle: float, _relative_direction: String, equipped: bool, arm_step := 99) -> void:
	pose_body_angle = body_angle
	pose_wrist_angle = wrist_angle
	pose_arm_step = arm_step
	actor_equipped = equipped


func set_breath_pose(track: StringName, phase: float) -> void:
	breath_track = track
	breath_phase = phase


func set_throw_pose(track: StringName, phase: float, kind_id := -1) -> void:
	throw_track = track
	throw_phase = phase
	throw_kind = kind_id


func set_prayer_pose(track: StringName, phase: float) -> void:
	prayer_track = track
	prayer_phase = phase


func set_prayer_lower_pose(track: StringName, phase: float) -> void:
	prayer_lower_track = track
	prayer_lower_phase = phase


func set_actor_lower_pose(_pose: Dictionary) -> void:
	pass


## Foot contacts and boot positions resolved from the lower sheet's sound frames.
func get_actor_lower_pose() -> Dictionary:
	return {"contacts": _contacts, "boots": _boots}


func set_focused(_value: bool) -> void:
	pass


func set_threat_pressure(_value: float) -> void:
	pass


func get_actor_hand_position() -> Vector2:
	return to_local(rig.anchor_global("hand_right"))


func get_actor_muzzle_position() -> Vector2:
	return to_local(rig.flashlight_tip_global() if rig.has_anchor("flashlight_tip") else rig.anchor_global("hand_right"))


func get_actor_throw_hand_position() -> Vector2:
	return to_local(rig.anchor_global("hand_left"))


func get_actor_boot_position(side: String) -> Vector2:
	return to_local(_boots.get(side, global_position))


func _on_sound_frame(part: StringName, clip: StringName, frame: int) -> void:
	if part != &"lower" or not (String(clip).ends_with("_lower")):
		return
	var boots := _boot_points(String(clip), frame)
	if boots.is_empty():
		return
	var landing := "left" if boots["left"].y >= boots["right"].y else "right"
	for side in ["left", "right"]:
		_boots[side] = rig.to_global(rig._art_to_local(boots[side]))
		_contacts[side] = side == landing
	landed.emit(landing)


## Centroid of the opaque pixels in each half (x < 80 right, x >= 80 left) of a lower-sheet frame.
static func _boot_points(clip_name: String, frame: int) -> Dictionary:
	var key := "%s:%d" % [clip_name, frame]
	if _boot_cache.has(key):
		return _boot_cache[key]
	var clip := CharacterClips.get_clip(clip_name)
	var result := {}
	if not clip.is_empty():
		var image: Image = (clip["texture"] as Texture2D).get_image()
		var sums := {"left": Vector2.ZERO, "right": Vector2.ZERO}
		var counts := {"left": 0, "right": 0}
		for y in 160:
			for x in 160:
				if image.get_pixel(frame * 160 + x, y).a > 0.5:
					var side := "left" if x >= 80 else "right"
					sums[side] += Vector2(x, y)
					counts[side] += 1
		for side in ["left", "right"]:
			result[side] = sums[side] / maxi(counts[side], 1) if counts[side] > 0 else Vector2(80, 80)
	_boot_cache[key] = result
	return result
