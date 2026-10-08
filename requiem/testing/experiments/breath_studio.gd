extends "res://tutorial/tutorial.gd"
## One safe place to review the real breath mechanic against production art.
## Presets only set starting resources; animation and effects follow live input.

var studio_status: Label
var equipment_button: Button
var effects_button: Button
var area_selector: OptionButton


func _ready() -> void:
	test_mode = true
	start_zone = "hallway"
	# The tutorial's automated mode silences clips. Keep their real presentation
	# in this interactive station while suppressing story and enemy reactions.
	var walk_audio: Array[AudioStream] = player.get_node("FootstepNoise").walk_clips.duplicate()
	var hold_audio: Array[AudioStream] = player.get_node("HoldBreath").hold_clips.duplicate()
	var exertion_audio: Array[AudioStream] = player.get_node("HoldBreath").exertion_clips.duplicate()
	super._ready()
	player.get_node("FootstepNoise").walk_clips.assign(walk_audio)
	breath.hold_clips.assign(hold_audio)
	breath.exertion_clips.assign(exertion_audio)
	entity.process_mode = Node.PROCESS_MODE_DISABLED
	thrower.available = false
	_build_studio_controls()
	set_effects_enabled(true)
	set_equipped(true)
	set_studio_area(0)


func _build_studio_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BreathStudioOverlay"
	layer.layer = 30
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(20, 16)
	panel.add_theme_constant_override("separation", 5)
	layer.add_child(panel)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	panel.add_child(heading)
	var title := _label("BREATH STUDIO · SAFE SANDBOX", 16)
	heading.add_child(title)
	studio_status = _label("", 14)
	heading.add_child(studio_status)
	panel.add_child(_label("WASD move · Shift sprint · Space hold / release · F light · R reset · Esc pause · No story triggers", 13))
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	panel.add_child(controls)
	_studio_button(controls, "Reset breath", func(): reset_studio_breath())
	_studio_button(controls, "Low air · 25%", func(): reset_studio_breath(25.0, 0.0))
	_studio_button(controls, "High exertion · 90%", func(): reset_studio_breath(100.0, 90.0))
	equipment_button = _studio_button(controls, "", func(): set_equipped(not has_flashlight))
	area_selector = OptionButton.new()
	area_selector.focus_mode = Control.FOCUS_NONE
	area_selector.add_item("Dark hallway")
	area_selector.add_item("Lit bedroom")
	area_selector.item_selected.connect(set_studio_area)
	controls.add_child(area_selector)
	effects_button = _studio_button(controls, "", func():
		set_effects_enabled(player.get_node("BreathFeedback").effects_strength <= 0.0))
	effects_button.tooltip_text = "Compare arcs and edge shading. Character animation and vital signs stay active."


func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("dfd9be"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _studio_button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	# Space must always reach HoldBreath, even after clicking a preset.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func set_equipped(equipped: bool) -> void:
	has_flashlight = equipped
	flashlight.battery_percent = 100.0
	flashlight.is_on = equipped
	flashlight.set_process(equipped)
	flashlight.set_process_unhandled_input(equipped)
	flashlight._refresh_light()
	equipment_button.text = "Flashlight: equipped" if equipped else "Flashlight: absent"


func set_effects_enabled(show_effects: bool) -> void:
	player.get_node("BreathFeedback").effects_strength = 1.0 if show_effects else 0.0
	effects_button.text = "Effects: on" if show_effects else "Effects: off"


func set_studio_area(index: int) -> void:
	# The middle of the real corridor and its bedroom recovery light provide
	# different backgrounds without changing the art or scene lighting.
	var selected_zone := "hallway" if index == 0 else "bedroom"
	var spawn := Vector2(2100, 348) if index == 0 else Vector2(385, 440)
	enter_zone(selected_zone, spawn, false)
	area_selector.select(index)
	reset_studio_breath()


func reset_studio_breath(lung := 100.0, exertion := 0.0) -> void:
	Input.action_release("hold_breath")
	breath.cancel_holding()
	breath.is_locked = false
	breath._lock_timer = 0.0
	breath.lung_percent = lung
	breath.exertion_percent = exertion
	if breath.has_method("reset_input_latch"):
		breath.reset_input_latch()
	var feedback := player.get_node_or_null("BreathFeedback")
	if feedback != null:
		feedback.reset_feedback()
	breath._update_bars()
	flashlight.battery_percent = 100.0
	flashlight._refresh_light()


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(studio_status): return
	var feedback := player.get_node_or_null("BreathFeedback")
	var phase: String = feedback.phase_name if feedback != null else String(player.get_node("ActionState").get_action())
	studio_status.text = "%s · Air %d%% · Exertion %d%%" % [phase.capitalize(), roundi(breath.lung_percent), roundi(breath.exertion_percent)]


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_F11:
		_toggle_fullscreen()
	elif key in [KEY_H, KEY_ESCAPE]:
		_toggle_pause()
	elif key == KEY_R and not _paused:
		reset_studio_breath()
	else:
		return
	get_viewport().set_input_as_handled()


func _tick_hallway(_delta: float) -> void:
	pass


func _find_interaction() -> void:
	nearest = ""
	hud.prompt.text = ""


func _on_noise(_at: Vector2, _radius: float, _source: int, _duration: float) -> void:
	# Hearing events remain observable through the lab's F3 overlay, but the
	# tutorial's hidden parental listeners cannot reset a breath review.
	pass
