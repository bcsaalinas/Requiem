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
	rocks -= 1
	super._start_throw()

func _impact(landing: Vector2, kind: int) -> void:
	super._impact(landing, kind)
	rock_landed.emit(landing)

func _update_label() -> void:
	if _ammo_label != null: _ammo_label.hide()

func clear_pending() -> void:
	for flight in _in_flight:
		if is_instance_valid(flight["node"]): flight["node"].queue_free()
	_in_flight.clear()
	_ringing.clear()
	is_throwing = false
	_windup_timer = 0.0
	_cooldown_timer = 0.0
