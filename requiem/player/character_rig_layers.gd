@tool
extends RefCounted
## Independent sparse poses baked from the original strict-overhead v2 rig.
## All returned anchors are source canvas pixels; subtract pivot, apply .5
## actor scale, then rotate by body heading. Original SpriteFrames stay usable.

const LEFT_ATLAS: Texture2D = preload("res://player/art/girl_rig_v2/left_leg_layers.png")
const RIGHT_ATLAS: Texture2D = preload("res://player/art/girl_rig_v2/right_leg_layers.png")
const UPPER_ATLAS: Texture2D = preload("res://player/art/girl_rig_v2/upper_layers.png")
const FLASHLIGHT: Texture2D = preload("res://player/art/girl_rig_v2/flashlight_layer.png")
const ANCHORS := preload("res://player/art/girl_rig_v2/action_layer_anchors.gd")
const DIRECTIONS: Array[String] = ["s", "sw", "w", "nw", "n", "ne", "e", "se"]
const PIVOT := Vector2(128, 128)
const FLASHLIGHT_MUZZLE_DISTANCE := 15.0

## Returns lower_texture/region and upper_texture/region for draw_texture_rect_region,
## flashlight_texture and flashlight_rect (grip-relative, before wrist rotation),
## right_hand/muzzle in source canvas pixels, flashlight_angle in body-local
## Godot radians (south = PI/2), and the common pivot. aim_step is -2..2.
func get_pose(state: String, frame: int, relative_direction: String,
		aim_step: int, equipped: bool) -> Dictionary:
	if state != "walk" and state != "sprint":
		state = "idle"
	frame = 0 if state == "idle" else posmod(frame, 8)
	var direction_index := DIRECTIONS.find(relative_direction)
	if direction_index < 0:
		direction_index = 0
	var lower_index := 0
	if state != "idle":
		lower_index = (65 if state == "sprint" else 1) + direction_index * 8 + frame
	var mode := clampi(aim_step, -2, 2) + 3 if equipped else 0
	var state_offset := 9 if state == "sprint" else (1 if state == "walk" else 0)
	var upper_index := mode * 17 + state_offset + frame
	var anchors: Dictionary = ANCHORS.FRAMES[upper_index]
	return {
		"lower_texture": LEFT_ATLAS,
		"lower_region": _region(lower_index),
		"upper_texture": UPPER_ATLAS,
		"upper_region": _region(upper_index),
		"flashlight_texture": FLASHLIGHT,
		"flashlight_rect": Rect2(-16, -20, 32, 48),
		"right_hand": anchors["right_hand"],
		"muzzle": anchors["muzzle"],
		"flashlight_angle": float(anchors["flashlight_angle"]),
		"pivot": PIVOT,
	}


func _region(index: int) -> Rect2:
	return Rect2((index % 8) * 256, floori(float(index) / 8.0) * 256, 256, 256)


## Both leg sheets use the same registered canvas and authored contact metadata.
func get_lower_pose(state: String, frame: int, direction: String) -> Dictionary:
	var direction_index := maxi(DIRECTIONS.find(direction), 0)
	var index := 0
	if state in ["walk", "sprint"]:
		index = (65 if state == "sprint" else 1) + direction_index * 8 + posmod(frame, 8)
	return _lower_pose(index)


func get_turn_pose(sign: int, frame: int) -> Dictionary:
	return _lower_pose((129 if sign >= 0 else 133) + clampi(frame, 0, 3))


func _lower_pose(index: int) -> Dictionary:
	return {
		"left_texture": LEFT_ATLAS, "right_texture": RIGHT_ATLAS,
		"region": _region(index), "metadata": ANCHORS.LOWER_FRAMES[index], "pivot": PIVOT,
	}
