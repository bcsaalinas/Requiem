extends Node2D
## The ranger's look on a CharacterSprite: his sheets draw the whole body over Viv's lower sheets.
## The body eases toward the gameplay facing at 240 deg/s; gameplay owns where he looks and walks.
## His torch beam is drawn to the ranger's sight cone, and the ranger reads the beam back from
## here (beam_origin, beam_direction): what the light touches is what he sees, sweep included.

const TURN_DEGREES := 240.0
const TURN_REPEAT_MIN := deg_to_rad(60.0)
const WALK_SPEED_U := 3.2
const NOTICE_SECONDS := 0.66
const BEAM := preload("res://assets/art/lights/light_ranger_beam_solid.png")
## From light_ranger_beam_solid.json: the painted tip, reach and half angle of the cone.
const BEAM_TIP := Vector2(6.0, 128.0)
const BEAM_REACH := 237.0
const BEAM_HALF_ANGLE := 24.0
const BEAM_TEXTURE_SCALE := 1.2

var rig: CharacterSprite
var torch: PointLight2D
var _body_facing := 0.0
var _turning_to_noise := false
var _notice_left := 0.0
@onready var ranger: Node2D = get_parent()


func _ready() -> void:
	rig = CharacterSprite.new()
	add_child(rig)
	rig.head_enabled = false
	rig.hide_head()
	_body_facing = ranger.facing.angle()
	rig.set_facing(_body_facing)
	torch = PointLight2D.new()
	torch.name = "Torch"
	torch.texture = BEAM
	torch.range_item_cull_mask = 5
	torch.shadow_enabled = true
	torch.shadow_filter = Light2D.SHADOW_FILTER_NONE
	torch.shadow_item_cull_mask = 3
	torch.texture_scale = BEAM_TEXTURE_SCALE
	torch.offset = (BEAM.get_size() * 0.5 - BEAM_TIP) * BEAM_TEXTURE_SCALE
	# Stretch the art to the ranger's own numbers, so tuning his sight retunes the light.
	var reach: float = ranger.sight_range / (BEAM_REACH * BEAM_TEXTURE_SCALE)
	torch.scale = Vector2(reach, reach * tan(deg_to_rad(ranger.sight_half_angle)) / tan(deg_to_rad(BEAM_HALF_ANGLE)))
	add_child(torch)
	rig.play(&"upper", "ranger_stand")
	rig.play(&"lower", "girl_stand_lower")
	_place_torch()


func beam_origin() -> Vector2:
	return torch.global_position


func beam_direction() -> Vector2:
	return Vector2.from_angle(torch.global_rotation)


## Faces the gameplay heading at once (patrol resets), with the beam already there.
func snap_to_facing() -> void:
	if rig == null: return
	_body_facing = ranger.facing.angle()
	_turning_to_noise = false
	_notice_left = 0.0
	rig.set_facing(_body_facing)
	_place_torch()


func _place_torch() -> void:
	torch.global_position = rig.anchor_global("flashlight_tip")
	torch.global_rotation = rig.flashlight_angle_global()


func heard_noise() -> void:
	if absf(angle_difference(_body_facing, ranger.facing.angle())) > TURN_REPEAT_MIN * 0.5:
		_turning_to_noise = true


func noticed() -> void:
	_notice_left = NOTICE_SECONDS
	_turning_to_noise = false


func set_focused(_value: bool) -> void:
	pass


func present(delta: float) -> void:
	var target: float = ranger.facing.angle()
	_body_facing = rotate_toward(_body_facing, target, deg_to_rad(TURN_DEGREES) * delta)
	rig.set_facing(_body_facing)
	var speed: float = ranger.velocity.length()
	_notice_left = maxf(_notice_left - delta, 0.0)
	if _notice_left > 0.0:
		rig.play(&"upper", "ranger_notice", {"loop": false, "hold_last": true})
		_follow_frame_lower()
	elif _turning_to_noise:
		rig.play(&"upper", "ranger_turn_to_noise", {"loop": true})
		var turning := absf(angle_difference(_body_facing, target)) > deg_to_rad(2.0)
		if rig.frame_of(&"upper") == 2:
			if turning:
				rig.set_frame(&"upper", 0)
			else:
				_turning_to_noise = false
		_follow_frame_lower()
	elif speed > 2.0:
		rig.play(&"lower", "girl_walk_lower", {"rate": clampf(speed / 32.0 / WALK_SPEED_U, 0.25, 2.5)})
		rig.play(&"upper", "ranger_walk", {"rate": 0.0})
		rig.set_frame(&"upper", rig.frame_of(&"lower"))
	elif ranger.distracted or ranger.investigating or ranger.chasing:
		rig.play(&"upper", "ranger_stand")
		rig.play(&"lower", "girl_stand_lower")
	else:
		rig.play(&"upper", "ranger_sweep")
		rig.play(&"lower", "girl_stand_lower")
	_place_torch()


## Clips whose frames each name their own lower frame (turn and notice).
func _follow_frame_lower() -> void:
	var clip := CharacterClips.get_clip(rig.clip_name(&"upper"))
	var frames: Array = clip["frames"]
	var entry: Dictionary = frames[clampi(rig.frame_of(&"upper"), 0, frames.size() - 1)]
	if entry["lower"] == "":
		return
	rig.play(&"lower", entry["lower"], {"rate": 0.0})
	rig.set_frame(&"lower", entry["lower_frame"])
