extends CanvasLayer
## Exhibition flow. Always processes, including pause/game-over and menu subpages.
const MENU := "res://tutorial/main_menu.tscn"
const GAME := "res://tutorial/tutorial.tscn"
const IDLE_SECONDS := 60.0
const TIPS := ["A blind thing is listening.", "Move quietly. Hold your breath.", "Every breath betrays you."]
var enabled := true
var idle_seconds := 0.0
var attracting := false
var transitioning := false
var _overlay: Control
var _warning: Label
var _invitation: Label
var _tip: Label
var _clock := 0.0

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	configure_display()
	_build()
	_start.call_deferred()

func configure_display() -> void:
	var window := get_window()
	window.content_scale_size = Vector2i(1920, 1080)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.unresizable = true

## Keep authored 720p UI composition, rasterized at 1.5x into the fixed 1080p viewport.
func fit_ui(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.size = Vector2(1280, 720)
	control.scale = Vector2.ONE * 1.5

func _start() -> void:
	if _production_scene() and get_tree().current_scene.scene_file_path == MENU:
		_show_attract()

func _production_scene() -> bool:
	var scene := get_tree().current_scene
	return enabled and scene != null and scene.scene_file_path in [MENU, GAME]

func _build() -> void:
	_overlay = Control.new()
	add_child(_overlay)
	fit_ui(_overlay)
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://assets/ui/menu_background.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://tutorial/credits_background.gdshader")
	background.material = material
	_overlay.add_child(background)
	var particles := Control.new()
	particles.set_script(load("res://tutorial/credits_particles.gd"))
	particles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(particles)
	var column := VBoxContainer.new()
	column.position = Vector2(140, 180)
	column.size = Vector2(1000, 390)
	column.add_theme_constant_override("separation", 28)
	_overlay.add_child(column)
	var title := _label(column, "REQUIEM", 86)
	title.add_theme_font_override("font", load("res://assets/fonts/cormorant_garamond/CormorantGaramond.ttf"))
	_label(column, "HOLDING YOUR BREATH", 25)
	_tip = _label(column, TIPS[0], 27)
	_invitation = _label(column, "PRESS ANY BUTTON TO BEGIN", 32)
	_label(column, "R / SELECT  ·  RESTART DEMO", 21)
	_overlay.hide()
	_warning = _label(self, "", 32)
	_warning.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_warning.position = Vector2(380, 1005)
	_warning.size = Vector2(1160, 45)
	_warning.add_theme_color_override("font_outline_color", Color.BLACK)
	_warning.add_theme_constant_override("outline_size", 8)
	_warning.hide()

func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("eee9d9"))
	parent.add_child(label)
	return label

func _meaningful_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton or event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) > 0.35
	if event is InputEventMouseMotion:
		return event.relative.length() >= 3.0
	return false

func _input(event: InputEvent) -> void:
	if not _production_scene():
		return
	if not _meaningful_input(event):
		return
	idle_seconds = 0.0
	_warning.hide()
	if event is InputEventKey and event.keycode == KEY_F11:
		Preferences.set_fullscreen(not Preferences.fullscreen)
		get_viewport().set_input_as_handled()
		return
	if attracting:
		# Motion wakes the timer, but only an intentional press dismisses the invitation.
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			dismiss_attract()
		get_viewport().set_input_as_handled()
		return
	var reset: bool = event is InputEventKey and (event.physical_keycode == KEY_R or event.keycode == KEY_R)
	reset = reset or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_BACK)
	if reset and get_tree().current_scene.scene_file_path == GAME:
		fast_reset()
		get_viewport().set_input_as_handled()

func fast_reset() -> void:
	if transitioning or not _production_scene():
		return
	transitioning = true
	_restart.call_deferred()

func _restart() -> void:
	idle_seconds = 0.0
	get_tree().paused = false
	var result := get_tree().reload_current_scene()
	if result == OK:
		await get_tree().scene_changed
	transitioning = false

func enter_attract() -> void:
	if transitioning or attracting or not _production_scene():
		return
	transitioning = true
	_return_to_menu.call_deferred()

func _return_to_menu() -> void:
	get_tree().paused = false
	var result := get_tree().change_scene_to_file(MENU)
	if result == OK:
		await get_tree().scene_changed
	transitioning = false
	_show_attract()

func _show_attract() -> void:
	attracting = true
	idle_seconds = 0.0
	_clock = 0.0
	_overlay.show()
	_overlay.modulate.a = 0.0
	create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.5)
	_warning.hide()
	var focus := get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()

func dismiss_attract() -> void:
	attracting = false
	idle_seconds = 0.0
	_overlay.hide()
	_warning.hide()
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == MENU:
		var play := scene.get_node_or_null("%Play")
		if play:
			play.grab_focus()

func _process(delta: float) -> void:
	if not _production_scene() or transitioning:
		return
	if attracting:
		_clock += delta
		_invitation.modulate.a = 0.72 + sin(_clock * 1.8) * 0.22
		_tip.text = TIPS[int(_clock / 6.0) % TIPS.size()]
		return
	if LoadingScreen._active or LoadingScreen._closing:
		idle_seconds = 0.0
		return
	if Input.is_anything_pressed():
		idle_seconds = 0.0
	else:
		idle_seconds += delta
	_warning.visible = idle_seconds >= 50.0
	_warning.text = "Returning to title in %d s · Press any button to stay" % ceili(IDLE_SECONDS - idle_seconds)
	if idle_seconds >= IDLE_SECONDS:
		enter_attract()
