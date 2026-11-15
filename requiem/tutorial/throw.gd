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

func _update_label() -> void:
	if _ammo_label != null: _ammo_label.hide()

var aiming := false
var aim_arc: Line2D

func _ready() -> void:
	super._ready()
	aim_arc = Line2D.new()
	aim_arc.top_level = true
	aim_arc.width = 1.5
	aim_arc.default_color = Color(0.85,0.79,0.63,0.65)
	aim_arc.z_index = 10
	add_child(aim_arc)
	aim_arc.hide()

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
	aim_arc.visible = aiming
	if not aiming: return
	var landing := _compute_landing()
	var points := PackedVector2Array()
	for index in range(25):
		var t := float(index) / 24.0
		points.append(player.global_position.lerp(landing,t) + Vector2(0,-sin(t*PI)*28.0))
	aim_arc.points = points

func clear_pending() -> void:
	aiming = false
	if is_instance_valid(aim_arc): aim_arc.hide()
	super.clear_pending()
