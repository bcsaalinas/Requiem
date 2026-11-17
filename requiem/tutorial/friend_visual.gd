extends Node2D
## Eli, the friend in the house: kneels once, then prays facing the altar (north). `fallen` is story
## state only; the story hides him instead of moving him.

var kind := "friend"
var fallen := false
var rig: CharacterSprite


func _ready() -> void:
	rig = CharacterSprite.new()
	add_child(rig)
	rig.head_enabled = false
	rig.hide_head()
	rig.set_facing(-PI / 2.0)
	rig.clip_finished.connect(_on_clip_finished)
	rig.play(&"upper", "eli_pray_kneel", {"loop": false, "hold_last": true})
	rig.play(&"lower", "girl_pray_kneel_lower", {"loop": false, "hold_last": true})


func _process(_delta: float) -> void:
	if rig.clip_name(&"upper") == "eli_pray_kneel":
		rig.set_rate(&"lower", 0.0)
		rig.set_frame(&"lower", rig.frame_of(&"upper"))


func set_focused(_value: bool) -> void:
	pass


func _on_clip_finished(part: StringName, clip: StringName) -> void:
	if part == &"upper" and clip == &"eli_pray_kneel":
		rig.play(&"upper", "eli_pray_loop")
		rig.play(&"lower", "girl_pray_loop_lower")
