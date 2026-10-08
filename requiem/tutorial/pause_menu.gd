extends CanvasLayer
## Beta pause menu. Replaces the static help panel with a navigable menu that
## keeps the game's tone: pausing a horror game normally kills the tension, so
## this one holds it — the world dims rather than disappearing, the audio ducks
## rather than stopping, and the title says the house is waiting.
##
## It does NOT own the pause. tutorial.gd::_toggle_pause() already saves and
## restores every child's process_mode and sets get_tree().paused; this menu
## just shows and hides, driven by set_open(). Standalone scenes that have no
## such owner can flip `owns_pause` instead.
##
## Keyboard, gamepad and mouse all work; focus is grabbed on open so no mouse
## is needed.

signal resume_pressed
signal quit_pressed

@export_group("Behaviour")
## Off by default: tutorial.gd owns the tree pause. Turn on for standalone use.
@export var owns_pause: bool = false
## Input action that toggles the menu. Empty disables self-toggling, which is
## what you want while tutorial.gd drives it.
@export var toggle_action: String = ""
@export var fade_time: float = 0.22

@export_group("Audio")
## Bus lowered while paused. Silence is this game's own vocabulary, so the
## pause borrows it instead of killing the mix dead.
@export var duck_bus_name: String = "Master"
@export var duck_db: float = -14.0

const CONTROLS := [
	["WASD / Arrows", "Move"],
	["Shift", "Sprint"],
	["Space", "Hold breath"],
	["E", "Interact · Pray"],
	["F", "Flashlight"],
	["B", "Replace battery"],
	["Q / Tab", "Throw · Switch"],
	["R", "Restart checkpoint"],
	["F11", "Fullscreen"],
]

var is_open: bool = false

var _root: Control
var _veil: ColorRect
var _panel: PanelContainer
var _pages: Dictionary = {}
var _duck_bus: int = -1
var _duck_base_db: float = 0.0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_duck_bus = AudioServer.get_bus_index(duck_bus_name)
	if _duck_bus >= 0:
		_duck_base_db = AudioServer.get_bus_volume_db(_duck_bus)
	_build()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action == "" or not InputMap.has_action(toggle_action):
		return
	if event.is_action_pressed(toggle_action):
		set_open(not is_open)
		get_viewport().set_input_as_handled()


# --- Construction ------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# A tint, not a blackout: the player still sees the room they are standing
	# in, drained of its light. Blacking out lets them step out of the game.
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color(UIPalette.VOID.r, UIPalette.VOID.g, UIPalette.VOID.b, 0.78)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_veil)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -290
	_panel.offset_right = 290
	_panel.offset_top = -210
	_panel.offset_bottom = 210
	_panel.add_theme_stylebox_override("panel", UIPalette.flat(UIPalette.PANEL, 30.0))
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_panel.add_child(column)

	var title := UIPalette.label("HOLDING YOUR BREATH", UIPalette.TITLE_SIZE, UIPalette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var sub := UIPalette.label("the house is waiting", UIPalette.CAPTION_SIZE, UIPalette.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)

	column.add_child(HSeparator.new())

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 250)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stack)

	_pages["main"] = _build_main()
	_pages["controls"] = _build_controls()
	_pages["audio"] = _build_audio()
	for key in _pages:
		var page: Control = _pages[key]
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(page)


func _build_main() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_menu_button("Resume", func():
		resume_pressed.emit()
		if owns_pause:
			set_open(false)
	))
	box.add_child(_menu_button("Controls", func(): _show_page("controls")))
	box.add_child(_menu_button("Audio", func(): _show_page("audio")))
	box.add_child(_menu_button("Quit to desktop", func():
		quit_pressed.emit()
		get_tree().quit()
	))
	return box


func _build_controls() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 7)
	for row in CONTROLS:
		var key := UIPalette.label(row[0], 15, UIPalette.CANDLE)
		key.custom_minimum_size.x = 180
		grid.add_child(key)
		grid.add_child(UIPalette.label(row[1], 15, UIPalette.TEXT_DIM))
	box.add_child(grid)

	box.add_child(HSeparator.new())
	box.add_child(UIPalette.label(
		"Stand still to recover exertion.\nRelease your breath before your air runs out.",
		13, UIPalette.TEXT_DIM
	))
	box.add_child(_menu_button("Back", func(): _show_page("main")))
	return box


## Builds one slider per bus that actually exists, so it shows Master today and
## picks up Ambience and SFX the moment those buses are created.
func _build_audio() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)

	for bus_name in ["Master", "Ambience", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			continue
		box.add_child(_volume_row(bus_name, index))

	box.add_child(HSeparator.new())
	box.add_child(_menu_button("Back", func(): _show_page("main")))
	return box


func _volume_row(bus_name: String, index: int) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(UIPalette.label(bus_name.to_upper(), UIPalette.CAPTION_SIZE, UIPalette.TEXT_DIM))

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(0, 18)
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(index))
	slider.value_changed.connect(func(v: float):
		# Silence is a real setting here, so the bottom of the slider mutes
		# rather than sitting at a very quiet -40 dB.
		AudioServer.set_bus_mute(index, v <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.0001)))
		if bus_name == duck_bus_name:
			_duck_base_db = linear_to_db(maxf(v, 0.0001))
	)
	row.add_child(slider)
	return row


func _menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", UIPalette.BODY_SIZE)
	button.add_theme_color_override("font_color", UIPalette.TEXT_DIM)
	button.add_theme_color_override("font_hover_color", UIPalette.CANDLE)
	button.add_theme_color_override("font_focus_color", UIPalette.CANDLE)
	button.add_theme_stylebox_override("normal", UIPalette.flat(Color(0, 0, 0, 0), 8.0))
	button.add_theme_stylebox_override("hover", UIPalette.flat(UIPalette.TRACK, 8.0))
	button.add_theme_stylebox_override("focus", UIPalette.flat(UIPalette.TRACK, 8.0))
	button.add_theme_stylebox_override("pressed", UIPalette.flat(UIPalette.TRACK, 8.0))
	button.pressed.connect(action)
	return button


# --- State -------------------------------------------------------------

## Single entry point. tutorial.gd calls this from _toggle_pause().
func set_open(open: bool) -> void:
	if open == is_open:
		return
	is_open = open

	if open:
		_show_page("main")
		_root.visible = true
		_root.modulate.a = 0.0

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_root, "modulate:a", 1.0 if open else 0.0, fade_time)
	if not open:
		tween.tween_callback(func(): _root.visible = false)

	if _duck_bus >= 0:
		AudioServer.set_bus_volume_db(
			_duck_bus, _duck_base_db + duck_db if open else _duck_base_db
		)

	if owns_pause:
		get_tree().paused = open


func _show_page(key: String) -> void:
	for name in _pages:
		(_pages[name] as Control).visible = name == key

	# Focus the first button on the open page so pad and keyboard work without
	# the player having to touch the mouse first.
	await get_tree().process_frame
	var page: Control = _pages.get(key)
	if page == null:
		return
	for child in page.get_children():
		if child is Button:
			(child as Button).grab_focus()
			return
