extends "res://testing/experiments/breath_studio.gd"
## The shared player and finite tutorial inventory in a safe production room.
## All throws, movement and breath use their real input and mechanic clocks.

const REFILL_ROCKS := 3


func _ready() -> void:
	super._ready()
	entity.active = false
	entity.hide()
	thrower.available = true
	thrower.piedra_clips.assign([sound("rock")])
	flashlight.click_clips.assign([sound("switch")])
	reset_studio_throw()


func _build_studio_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ThrowStudioOverlay"
	layer.layer = 30
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(20, 16)
	panel.add_theme_constant_override("separation", 5)
	layer.add_child(panel)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	panel.add_child(heading)
	heading.add_child(_label("THROW STUDIO · SAFE SANDBOX", 16))
	studio_status = _label("", 14)
	heading.add_child(studio_status)
	panel.add_child(_label("Q throw · Cursor aim · WASD move · Shift sprint · Space hold breath · F light · R refill · Esc pause", 13))
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	panel.add_child(controls)
	_studio_button(controls, "Reset / refill 3 rocks", reset_studio_throw)
	equipment_button = _studio_button(controls, "", func():
		set_equipment_mode((get_equipment_mode() + 1) % 3))
	equipment_button.tooltip_text = "Cycle through no flashlight, flashlight off, and flashlight on."
	area_selector = OptionButton.new()
	area_selector.focus_mode = Control.FOCUS_NONE
	area_selector.add_item("Dark hallway")
	area_selector.add_item("Lit bedroom")
	area_selector.item_selected.connect(set_studio_area)
	controls.add_child(area_selector)


func set_effects_enabled(show_effects: bool) -> void:
	# Preserve the shared breath presentation without the breath studio controls.
	player.get_node("BreathFeedback").effects_strength = 1.0 if show_effects else 0.0


func get_equipment_mode() -> int:
	return 0 if not has_flashlight else (2 if flashlight.is_on else 1)


func set_equipment_mode(mode: int) -> void:
	set_equipped(mode > 0)
	flashlight.is_on = mode == 2
	flashlight._refresh_light()
	_update_equipment_label()


func _update_equipment_label() -> void:
	if is_instance_valid(equipment_button):
		equipment_button.text = ["Flashlight: absent", "Flashlight: off", "Flashlight: on"][get_equipment_mode()]


func set_studio_area(index: int) -> void:
	super.set_studio_area(index)
	reset_studio_throw()


func reset_studio_throw() -> void:
	for action_name in ["throw", "hold_breath", "sprint", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action_name)
	thrower.clear_pending()
	thrower.rocks = REFILL_ROCKS
	thrower.available = true
	player.velocity = Vector2.ZERO
	player.get_node("FootstepNoise").footstep_timer = 0.0
	reset_studio_breath()
	player.get_node("PlayerMotion").reset_pose()
	player.get_node("PlayerAim").reset_pose()
	var feedback := player.get_node_or_null("ThrowFeedback")
	if feedback != null:
		feedback.reset_feedback()


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(studio_status): return
	var state := "Ready"
	var feedback := player.get_node_or_null("ThrowFeedback")
	if feedback != null and feedback.phase == &"windup":
		state = "Preparing"
	elif feedback != null and feedback.phase == &"follow_through":
		state = "Released"
	elif thrower._cooldown_timer > 0.0:
		state = "Ready in %.1fs" % thrower._cooldown_timer
	elif thrower.rocks <= 0:
		state = "Refill with R"
	elif not thrower.can_throw():
		state = "Recovering"
	studio_status.text = "%s · Rocks %d / %d · Air %d%%" % [state, thrower.rocks, REFILL_ROCKS, roundi(breath.lung_percent)]
	_update_equipment_label()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_R and not _paused:
			reset_studio_throw()
			get_viewport().set_input_as_handled()
			return
	super._input(event)


func _on_rock_landed(_at: Vector2) -> void:
	# Impacts still produce real noise, but cannot begin a tutorial sequence.
	pass
