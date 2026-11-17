extends Node2D
## The ranger's look on a CharacterSprite: his sheets draw the whole body over Viv's lower sheets.
## The body eases toward the gameplay facing at 240 deg/s; gameplay owns where he looks and walks.

const TURN_DEGREES := 240.0
const TURN_REPEAT_MIN := deg_to_rad(60.0)
const WALK_SPEED_U := 3.2
const NOTICE_SECONDS := 0.66

var rig: CharacterSprite
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


## Clips whose frames each name their own lower frame (turn and notice).
func _follow_frame_lower() -> void:
	var clip := CharacterClips.get_clip(rig.clip_name(&"upper"))
	var frames: Array = clip["frames"]
	var entry: Dictionary = frames[clampi(rig.frame_of(&"upper"), 0, frames.size() - 1)]
	if entry["lower"] == "":
		return
	rig.play(&"lower", entry["lower"], {"rate": 0.0})
	rig.set_frame(&"lower", entry["lower_frame"])
