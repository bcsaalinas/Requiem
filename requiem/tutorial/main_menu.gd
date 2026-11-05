extends Control
## Main menu — the first thing the game shows.
##
## Layout, key art and styling are authored in main_menu.tscn with ui/requiem_theme.tres.
## This script switches pages, fills the data-driven rows (controls list, one slider per audio
## bus), flickers the candle and hands Play to the loading screen, which owns the threaded load.
##
## Visual rule: the room is dark and still. The candle on the altar and the thin rule under the
## title are the only things that move, on the same flicker idiom as a dying flashlight.

const CONTROLS := [
	["WASD / Arrows", "Move"],
	["Shift", "Sprint"],
	["Space", "Hold breath"],
	["E", "Interact · Doors · Pray"],
	["F", "Flashlight"],
	["B", "Swap battery"],
	["Q / Tab", "Throw · Switch"],
	["R / Select", "Restart demo"],
	["F11", "Fullscreen"],
]
## Where the candle flame sits in the key art (UV of menu_background.png), and the
## size of its glow in art pixels. The art is drawn "covered", so the glow follows it.
const CANDLE_UV := Vector2(0.8156, 0.5444)
const GLOW_SIZE := 240.0

@export_group("Flow")
## Scene handed to LoadingScreen when the player picks Play.
@export var game_scene: String = "res://tutorial/tutorial.tscn"
@export var fade_in: float = 1.1

@export_group("Presentation")
## Optional room tone.
@export var ambience: AudioStream

@export_multiline var team_credits: String = preload("res://tutorial/credits_data.gd").TEAM
@export_multiline var resource_credits: String = ""

const CREDITS_SCENE := preload("res://tutorial/credits.tscn")
var _credits: Control
var _credits_transition := false

var _current_page := "main"
var _last_focus: Dictionary = {}
var _starting := false
var _fullscreen: CheckButton
var _pages: Dictionary = {}
var _clock := 0.0
var _flicker_target := 1.0
var _flicker := 1.0
var _next_flicker := 0.0
var _rng := RandomNumberGenerator.new()

@onready var _rule: CanvasItem = %Rule
@onready var _glow: CanvasItem = %CandleGlow


func _ready() -> void:
	Exhibit.configure_display()
	$Column.scale = Vector2.ONE * 1.5
	$Column.offset_left = 168
	$Column.offset_right = 608
	$Column.offset_top = -405
	$Column.offset_bottom = 135
	_rng.randomize()
	_pages = {"main": %MainPage, "controls": %ControlsPage, "audio": %AudioPage}
	%Play.pressed.connect(_start_game)
	%SettingsButton.pressed.connect(_show_page.bind("settings"))
	%CreditsButton.pressed.connect(_open_credits)
	%Quit.pressed.connect(_show_page.bind("quit"))
	%ControlsBack.pressed.connect(_show_page.bind("settings"))
	%AudioBack.pressed.connect(_show_page.bind("settings"))
	_build_extra_pages()
	LoadingScreen.failed.connect(_load_failed)
	_build_controls()
	_build_audio()
	_show_page("main")
	%Background.resized.connect(_place_glow)
	_place_glow.call_deferred()

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


func _build_controls() -> void:
	var grid: GridContainer = %ControlsGrid
	for row in CONTROLS:
		var key := Label.new()
		key.text = row[0]
		key.theme_type_variation = &"KeyLabel"
		key.custom_minimum_size.x = 170
		grid.add_child(key)
		var action := Label.new()
		action.text = row[1]
		action.theme_type_variation = &"CaptionLabel"
		grid.add_child(action)


## One slider per bus that exists, same as the pause menu: Master today,
## Ambience and SFX the moment those buses are created.
func _build_audio() -> void:
	var page: Control = %AudioPage
	var index := 0
	for bus_name in ["Master", "Ambience", "SFX"]:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		var row := VBoxContainer.new()
		var caption := Label.new()
		caption.text = bus_name.to_upper()
		caption.theme_type_variation = &"CaptionLabel"
		row.add_child(caption)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.custom_minimum_size = Vector2(320, 18)
		slider.value = 0.0 if AudioServer.is_bus_mute(bus) else db_to_linear(AudioServer.get_bus_volume_db(bus))
		slider.value_changed.connect(func(v: float):
			Preferences.set_volume(bus_name, v))
		row.add_child(slider)
		page.add_child(row)
		page.move_child(row, index)
		index += 1


func _show_page(key: String) -> void:
	if _credits_transition or is_instance_valid(_credits):
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _pages.has(_current_page) and _pages[_current_page].is_ancestor_of(focused):
		_last_focus[_current_page] = focused
	_current_page = key
	for page_name in _pages:
		(_pages[page_name] as Control).visible = page_name == key
	await get_tree().process_frame
	if not is_inside_tree() or _current_page != key or _starting:
		return
	if key == "quit":
		_pages[key].get_child(1).grab_focus()
	elif _last_focus.has(key) and is_instance_valid(_last_focus[key]):
		_last_focus[key].grab_focus()
	else:
		_focus_first(_pages[key])


func _focus_first(node: Node) -> bool:
	if node is Control and node.focus_mode == Control.FOCUS_ALL:
		node.grab_focus()
		return true
	for child in node.get_children():
		if _focus_first(child):
			return true
	return false


func _page(key: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	%MainPage.get_parent().add_child(page)
	_pages[key] = page
	return page


func _button(page: Control, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(220, 40)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	page.add_child(button)
	button.pressed.connect(action)
	return button


func _caption(page: Control, caption: String) -> void:
	var label := Label.new()
	label.text = caption
	label.theme_type_variation = &"CaptionLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(label)


func _build_extra_pages() -> void:
	var settings := _page("settings")
	_caption(settings, "SETTINGS")
	_button(settings, "Audio", _show_page.bind("audio"))
	_button(settings, "Controls", _show_page.bind("controls"))
	_button(settings, "Display", _show_page.bind("display"))
	_button(settings, "Back", _show_page.bind("main"))

	var display := _page("display")
	_caption(display, "DISPLAY")
	_fullscreen = CheckButton.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.button_pressed = Preferences.fullscreen
	_fullscreen.toggled.connect(Preferences.set_fullscreen)
	display.add_child(_fullscreen)
	_button(display, "Back", _show_page.bind("settings"))

	var quit := _page("quit")
	_caption(quit, "Quit Requiem?")
	_button(quit, "Cancel", _show_page.bind("main"))
	_button(quit, "Quit to desktop", func(): get_tree().quit())

	var error_page := _page("error")
	_caption(error_page, "The game could not be loaded. Please try again.")
	_button(error_page, "Retry", _start_game)
	_button(error_page, "Back to Menu", _show_page.bind("main"))


func _unhandled_input(event: InputEvent) -> void:
	if _starting or is_instance_valid(_credits) or _credits_transition:
		return
	if event.is_action_pressed("ui_cancel"):
		var destination := "main"
		if _current_page == "main":
			destination = "quit"
		elif _current_page in ["audio", "controls", "display"]:
			destination = "settings"
		_show_page(destination)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		Preferences.set_fullscreen(not Preferences.fullscreen)
		_fullscreen.set_pressed_no_signal(Preferences.fullscreen)
		get_viewport().set_input_as_handled()


func _load_failed() -> void:
	_starting = false
	_show_page("error")


## Keeps the glow on the painted candle at any window aspect (same maths as KEEP_ASPECT_COVERED).
func _place_glow() -> void:
	var background: TextureRect = %Background
	var art := background.texture.get_size()
	var cover := maxf(background.size.x / art.x, background.size.y / art.y)
	var origin := (background.size - art * cover) * 0.5
	_glow.size = Vector2.ONE * GLOW_SIZE * cover
	_glow.pivot_offset = _glow.size * 0.5
	_glow.position = origin + CANDLE_UV * art * cover - _glow.size * 0.5


## Hands off to the loading screen, which owns the threaded load and the swap.
func _start_game() -> void:
	if _starting or _credits_transition or is_instance_valid(_credits):
		return
	_starting = true
	for page in _pages.values():
		(page as Control).visible = false
	LoadingScreen.show_for(game_scene)


## Irregular candle flicker: a new target every 90–260 ms, eased toward rather
## than snapped to, so it reads as a flame and not as a broken element.
func _process(delta: float) -> void:
	_clock += delta
	_next_flicker -= delta
	if _next_flicker <= 0.0:
		_next_flicker = _rng.randf_range(0.09, 0.26)
		_flicker_target = _rng.randf_range(0.72, 1.0)
	_flicker = lerpf(_flicker, _flicker_target, clampf(delta * 9.0, 0.0, 1.0))
	_rule.modulate.a = _flicker
	_glow.modulate.a = 0.55 + 0.45 * _flicker
	_glow.scale = Vector2.ONE * (0.97 + 0.05 * _flicker)


func _open_credits() -> void:
	if _starting or _credits_transition or is_instance_valid(_credits):
		return
	_credits_transition = true
	%CreditsButton.release_focus()
	$Column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := create_tween()
	fade.tween_property($Column, "modulate:a", 0.0, 0.25)
	await fade.finished
	$Column.hide()
	_credits = CREDITS_SCENE.instantiate()
	_credits.team_credits = team_credits
	_credits.resource_credits = resource_credits
	_credits.back_requested.connect(_close_credits)
	add_child(_credits)
	_credits_transition = false


func _close_credits() -> void:
	_credits.queue_free()
	_credits = null
	$Column.show()
	$Column.mouse_filter = Control.MOUSE_FILTER_STOP
	var fade := create_tween()
	fade.tween_property($Column, "modulate:a", 1.0, 0.3)
	%CreditsButton.grab_focus()
