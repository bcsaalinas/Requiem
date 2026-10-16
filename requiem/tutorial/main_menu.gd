extends Control
## Main menu — the first thing the game shows.
##
## It exists so the loading screen has something to load *from*. A loading
## screen that runs before any input is just a delay; after a click on Play it
## becomes a transition, and the breath it animates reads as the player's own.
##
## Visual rule: the menu is still and almost entirely dark. One warm element —
## a thin candle-coloured rule under the title — flickers on the same idiom as
## the flashlight at low battery. It is the only light in the room, and it is
## the only thing that moves.
##
## Set as Main Scene in Project Settings. Replaces boot.tscn.

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

@export_group("Flow")
## Scene handed to LoadingScreen when the player picks Play.
@export var game_scene: String = "res://tutorial/tutorial.tscn"
@export var fade_in: float = 1.1

@export_group("Presentation")
@export var title_text: String = "REQUIEM"
@export var tagline: String = "a blind thing is listening"
@export var title_size: int = 64
## Optional room tone. Drop res://tutorial/assets/audio/room.wav here.
@export var ambience: AudioStream

var _pages: Dictionary = {}
var _candle: ColorRect
var _clock: float = 0.0
var _flicker_target: float = 1.0
var _flicker: float = 1.0
var _next_flicker: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_show_page("main")

	if ambience != null:
		var player := AudioStreamPlayer.new()
		player.stream = ambience
		player.volume_db = -20.0
		player.finished.connect(player.play)
		add_child(player)
		player.play()

	# Fade up from black slowly. The game opens by letting your eyes adjust.
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_in)


func _build() -> void:
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = UIPalette.PANEL_SOLID
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.offset_left = -300
	column.offset_right = 300
	column.offset_top = -230
	column.offset_bottom = 230
	add_child(column)

	var title := UIPalette.label(title_text, title_size, UIPalette.BONE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(title)

	# The one warm element. Everything else in the menu is bone and ash.
	var candle_holder := CenterContainer.new()
	column.add_child(candle_holder)
	_candle = ColorRect.new()
	_candle.custom_minimum_size = Vector2(190, 1)
	_candle.color = UIPalette.CANDLE
	_candle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	candle_holder.add_child(_candle)

	var sub := UIPalette.label(tagline, UIPalette.CAPTION_SIZE, UIPalette.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 34)
	column.add_child(spacer)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 260)
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
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_menu_button("Play", _start_game))
	box.add_child(_menu_button("Controls", func(): _show_page("controls")))
	box.add_child(_menu_button("Audio", func(): _show_page("audio")))
	box.add_child(_menu_button("Quit", func(): get_tree().quit()))
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


## One slider per bus that exists, same as the pause menu: Master today,
## Ambience and SFX the moment those buses are created.
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
		AudioServer.set_bus_mute(index, v <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.0001)))
	)
	row.add_child(slider)
	return row


func _menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
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


func _show_page(key: String) -> void:
	for name in _pages:
		(_pages[name] as Control).visible = name == key

	await get_tree().process_frame
	var page: Control = _pages.get(key)
	if page == null:
		return
	for child in page.get_children():
		if child is Button:
			(child as Button).grab_focus()
			return


## Hands off to the loading screen, which owns the threaded load and the swap.
func _start_game() -> void:
	for page in _pages.values():
		(page as Control).visible = false
	LoadingScreen.show_for(game_scene)


## Irregular candle flicker: a new target every 90–260 ms, eased toward rather
## than snapped to, so it reads as a flame and not as a broken element.
func _process(delta: float) -> void:
	if _candle == null:
		return

	_clock += delta
	_next_flicker -= delta
	if _next_flicker <= 0.0:
		_next_flicker = _rng.randf_range(0.09, 0.26)
		_flicker_target = _rng.randf_range(0.72, 1.0)

	_flicker = lerpf(_flicker, _flicker_target, clampf(delta * 9.0, 0.0, 1.0))
	_candle.modulate.a = _flicker
	# A very slow breath on the width, far below conscious notice.
	_candle.custom_minimum_size.x = 190.0 + sin(_clock * 0.6) * 6.0
