extends "res://player/throw.gd"
## Tutorial inventory adapter; inherited trajectory, timings and noise are unchanged.
signal rock_landed(at: Vector2)
var rocks := 0
var available := true

func can_throw() -> bool:
	return available and rocks > 0 and super.can_throw()

func _switch_throwable() -> void:
	pass # Only collected rocks are introduced in this segment.

func _start_throw() -> void:
	if not can_throw():
		return
	super._start_throw()
	if is_throwing:
		rocks -= 1

func _impact(landing: Vector2, kind: int) -> void:
	super._impact(landing, kind)
	rock_landed.emit(landing)


var aiming := false
var aim_wake: Node2D

func _ready() -> void:
	super._ready()
	aim_wake = VfxSheet.new()
	aim_wake.top_level = true
	aim_wake.z_index = 49
	aim_wake.loops = true
	add_child(aim_wake)
	aim_wake.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			aiming = can_throw()
		elif aiming:
			aiming = false
			_start_throw()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not can_throw() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		aiming = false
	aim_wake.visible = aiming
	if not aiming: return
	var landing := _compute_landing()
	aim_wake.global_position = player.global_position
	aim_wake.global_rotation = (landing - player.global_position).angle()
	if aim_wake.frame_ms.is_empty():
		aim_wake.play(TRAIL_TEXTURE, 3, TRAIL_MS, TRAIL_ANCHOR, true)

func clear_pending() -> void:
	aiming = false
	if is_instance_valid(aim_wake): aim_wake.hide()
	super.clear_pending()
