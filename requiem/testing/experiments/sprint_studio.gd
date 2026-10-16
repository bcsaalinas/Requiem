extends "res://testing/experiments/breath_studio.gd"
## Real movement and foot contacts in safe production rooms. No story sequence
## or enemy can interrupt this station; speed, effort and collision remain live.

const AREA_ZONES := ["bedroom", "hallway", "forest"]
const AREA_SPAWNS := [Vector2(385, 440), Vector2(2100, 348), Vector2(3820, 430)]
var audio_button: Button


func _ready() -> void:
	forest_cued = true
	super._ready()
	entity.active = false
	entity.hide()
	thrower.available = false
	flashlight.click_clips.assign([sound("switch")])
	set_equipment_mode(2)
	hud.subtitle.text = "WASD + Shift to sprint. Aim across your path to inspect each planted foot."


func _build_studio_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SprintStudioOverlay"
	layer.layer = 30
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(20, 16)
	panel.add_theme_constant_override("separation", 5)
	layer.add_child(panel)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	panel.add_child(heading)
	heading.add_child(_label("SPRINT STUDIO · SAFE SANDBOX", 16))
	studio_status = _label("", 14)
	heading.add_child(studio_status)
	panel.add_child(_label("WASD move · Shift sprint · Cursor aim · Space hold breath · F light · R reset · Esc pause · F1 Test Lab", 13))
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	panel.add_child(controls)
	_studio_button(controls, "Reset run", reset_studio_sprint)
	equipment_button = _studio_button(controls, "", func():
		set_equipment_mode((get_equipment_mode() + 1) % 3))
	equipment_button.tooltip_text = "Cycle through no flashlight, flashlight off, and flashlight on."
	area_selector = OptionButton.new()
	area_selector.focus_mode = Control.FOCUS_NONE
	for area in ["Lit bedroom", "Dark hallway", "Forest path"]:
		area_selector.add_item(area)
	area_selector.item_selected.connect(set_studio_area)
	controls.add_child(area_selector)
	effects_button = _studio_button(controls, "", func():
		set_effects_enabled(not player.get_node("SprintDust").enabled))
	effects_button.tooltip_text = "Compare foot-contact dust while the same sprint animation and mechanics continue."
	audio_button = _studio_button(controls, "Steps: on", func():
		set_step_audio_enabled(not player.get_node("FootstepAudio").enabled))
	audio_button.tooltip_text = "Compare audible foot plants without changing enemy-hearing events."


func set_step_audio_enabled(value: bool) -> void:
	var step_audio := player.get_node("FootstepAudio")
	step_audio.enabled = value
	if not value: step_audio.reset_audio()
	audio_button.text = "Steps: on" if value else "Steps: off"


func get_equipment_mode() -> int:
	return 0 if not has_flashlight else (2 if flashlight.is_on else 1)


func set_equipment_mode(mode: int) -> void:
	mode = clampi(mode, 0, 2)
	set_equipped(mode > 0)
	flashlight.is_on = mode == 2
	flashlight._refresh_light()
	_update_equipment_label()


func _update_equipment_label() -> void:
	if is_instance_valid(equipment_button):
		equipment_button.text = ["Flashlight: absent", "Flashlight: off", "Flashlight: on"][get_equipment_mode()]


func set_effects_enabled(show_effects: bool) -> void:
	var dust := player.get_node("SprintDust")
	dust.enabled = show_effects
	dust.effects_strength = 1.0 if show_effects else 0.0
	if not show_effects:
		dust.clear_dust()
	if is_instance_valid(effects_button):
		effects_button.text = "Dust: on" if show_effects else "Dust: off"


func set_studio_area(index: int) -> void:
	area_selector.select(clampi(index, 0, AREA_ZONES.size() - 1))
	reset_studio_sprint()


func reset_studio_sprint() -> void:
	for action_name in ["pray", "throw", "hold_breath", "sprint", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action_name)
	GameState.reset()
	thrower.clear_pending()
	thrower.available = false
	reset_studio_breath()
	player.velocity = Vector2.ZERO
	player.is_sprinting = false
	player.get_node("FootstepNoise").footstep_timer = 0.0
	var index := area_selector.selected
	enter_zone(AREA_ZONES[index], AREA_SPAWNS[index], false)
	player.get_node("PlayerMotion").reset_pose()
	player.get_node("PlayerAim").clear_target()
	player.get_node("PlayerAim").reset_pose()
	player.get_node("SprintDust").clear_dust()
	player.get_node("Camera2D").reset_smoothing()
	forest_cued = true


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(studio_status):
		return
	var motion := player.get_node("PlayerMotion")
	var dust := player.get_node("SprintDust")
	studio_status.text = "%s · %.1f u/s · Dust %d · Effort %d%%" % [
		motion.mode, player.get_speed_u(), dust.particles.size(), roundi(breath.exertion_percent)]
	_update_equipment_label()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_R and not _paused:
			reset_studio_sprint()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F1 and not get_parent().has_method("show_menu"):
			get_tree().paused = false
			get_tree().change_scene_to_file.call_deferred("res://testing/test_lab.tscn")
			get_viewport().set_input_as_handled()
			return
	super._input(event)


func _on_rock_landed(_at: Vector2) -> void:
	pass
