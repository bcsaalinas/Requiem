extends Control
## Automatic cinematic roll. Labels recede gently toward the top, without a video file.
signal back_requested
const DATA := preload("res://tutorial/credits_data.gd")
const SERIF := preload("res://assets/fonts/cormorant_garamond/CormorantGaramond.ttf")
const IVORY := Color(0.89, 0.88, 0.81)
const MUTED := Color(0.66, 0.69, 0.67)
@export_multiline var team_credits: String = DATA.TEAM
@export_multiline var resource_credits: String = ""
@export var transition_time := 0.45
@export_range(15.0, 80.0) var scroll_speed := 38.0

var back_button: Button
var licenses_button: Button
var _licenses: RichTextLabel
var _footer: VBoxContainer
var _roll: Control
var _rows: Array[Dictionary] = []
var _content_height := 0.0
var _travel := 0.0
var _elapsed := 0.0
var _closing := false
var _hover_tweens: Dictionary = {}

func _ready() -> void:
	Exhibit.fit_ui(self)
	_build()
	resized.connect(_resize_layout)
	_resize_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, transition_time)
	back_button.grab_focus.call_deferred()

func _row(caption: String, font_size: int = 30, color: Color = IVORY, gap: float = 12.0) -> void:
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", SERIF)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size.x = 760
	_roll.add_child(label)
	var height := label.get_minimum_size().y
	_rows.append({"label": label, "offset": _content_height})
	_content_height += height + gap

func _build() -> void:
	_roll = Control.new()
	_roll.clip_contents = true
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roll)
	_row("REQUIEM", 64, IVORY, 0)
	_row("Holding Your Breath", 28, MUTED, 24)
	_row("—  ◇  —", 24, MUTED, 55)
	_row("DEVELOPMENT TEAM", 24, MUTED, 36)
	for entry in team_credits.split("\n\n", false):
		var lines := entry.split("\n", false)
		_row(lines[0], 36, IVORY, 4)
		for i in range(1, lines.size()):
			_row(lines[i], 25, MUTED, 38)
	_content_height += 65
	_row("SOUND & ATMOSPHERE", 28, IVORY, 38)
	for entry in DATA.AUDIO:
		_row(entry[0], 32, IVORY, 4)
		_row(entry[1], 23, MUTED, 34)
	_content_height += 65
	_row("ENGINE & TOOLS", 28, IVORY, 38)
	_row("Godot Engine", 36, IVORY, 4)
	_row("Godot contributors · MIT License", 24, MUTED, 40)
	_row("Phantom Camera", 34, IVORY, 4)
	_row("Marcus Skov · MIT License", 24, MUTED, 40)
	_row("Cormorant Garamond", 34, IVORY, 4)
	_row("The Cormorant Project Authors · SIL Open Font License 1.1", 23, MUTED, 50)
	if not resource_credits.strip_edges().is_empty():
		_row(resource_credits, 26, MUTED, 50)
	_content_height += 60
	_row("Thank you for playing", 40, IVORY, 30)
	_row("REQUIEM", 54, IVORY, 20)

	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 2)
	add_child(_footer)
	back_button = _button(_footer, "BACK")
	back_button.pressed.connect(request_back)
	licenses_button = _button(_footer, "LICENSES")
	licenses_button.add_theme_font_size_override("font_size", 15)
	licenses_button.custom_minimum_size.y = 24
	_licenses = RichTextLabel.new()
	_licenses.visible = false
	_licenses.add_theme_color_override("default_color", IVORY)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.025, 0.03, 0.03, 0.98)
	panel.content_margin_left = 22
	panel.content_margin_right = 22
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	_licenses.add_theme_stylebox_override("normal", panel)
	_licenses.text = "GODOT ENGINE\n" + Engine.get_license_text()
	_licenses.text += "\n\nPHANTOM CAMERA — Marcus Skov\n" + DATA.PHANTOM_LICENSE
	_licenses.text += "\n\nCORMORANT GARAMOND\n" + DATA.FONT_LICENSE
	add_child(_licenses)
	licenses_button.pressed.connect(func():
		_licenses.visible = not _licenses.visible
		licenses_button.text = "RESUME CREDITS" if _licenses.visible else "LICENSES")

func _button(parent: Node, caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 40
	button.add_theme_font_override("font", SERIF)
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_focus_color", IVORY)
	button.add_theme_color_override("font_hover_color", IVORY)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	parent.add_child(button)
	var ornament := Label.new()
	ornament.text = "◇                                          ◇"
	ornament.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ornament.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ornament.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ornament.add_theme_color_override("font_color", IVORY)
	ornament.modulate.a = 0.0
	button.add_child(ornament)
	var update := func():
		if _hover_tweens.has(button):
			_hover_tweens[button].kill()
		var tween := create_tween()
		_hover_tweens[button] = tween
		tween.tween_property(ornament, "modulate:a", 0.75 if button.has_focus() or button.is_hovered() else 0.0, 0.18)
	button.mouse_entered.connect(update)
	button.mouse_exited.connect(update)
	button.focus_entered.connect(update)
	button.focus_exited.connect(update)
	return button

func _resize_layout() -> void:
	_roll.position = Vector2(0, 20)
	_roll.size = Vector2(size.x, maxf(180, size.y - 130))
	_footer.position = Vector2((size.x - 300) * 0.5, size.y - 95)
	_footer.size = Vector2(300, 72)
	var width := minf(800, size.x - 48)
	_licenses.position = Vector2((size.x - width) * 0.5, 35)
	_licenses.size = Vector2(width, maxf(120, size.y - 150))
	_position_rows()

func _position_rows() -> void:
	var height := _roll.size.y
	for row in _rows:
		var label: Label = row.label
		var y: float = height * 0.72 + row.offset - _travel
		var depth := clampf(y / height, 0.0, 1.0)
		var perspective := (0.62 + depth * 0.38) * minf(1.0, (size.x - 48) / 760.0)
		label.scale = Vector2.ONE * perspective
		label.position = Vector2((size.x - 760 * perspective) * 0.5, y)
		label.modulate.a = smoothstep(0.0, 0.20, depth) * (1.0 - smoothstep(0.9, 1.0, depth))
		label.visible = y > -label.size.y and y < height

func request_back() -> void:
	if _closing:
		return
	_closing = true
	back_button.disabled = true
	licenses_button.disabled = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, transition_time)
	await fade.finished
	if back_requested.get_connections().is_empty():
		get_tree().change_scene_to_file("res://tutorial/main_menu.tscn")
	else:
		back_requested.emit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		request_back()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _closing or _licenses.visible:
		return
	_elapsed += delta
	if _elapsed > 1.2:
		_travel += scroll_speed * delta
	_position_rows()
	if _travel > _content_height + _roll.size.y * 0.72 + 100:
		request_back()
