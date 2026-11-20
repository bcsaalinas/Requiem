extends Node
## User preferences, shared by the main menu and pause menu.
signal display_mode_changed
signal turn_mode_changed
signal captions_changed

const TURN_FREE := "free"
const TURN_STEPS := "steps"

const DISPLAY_FILL := "fill"
const DISPLAY_PIXEL_PERFECT := "pixel_perfect"

var config := ConfigFile.new()
var storage_path := "user://preferences.cfg"
var fullscreen := false
var display_mode := DISPLAY_FILL
## Her body is drawn turning in 22.5° steps by default; "free" is the option.
var turn_mode := TURN_STEPS
var captions := false

func _ready() -> void:
	load_preferences()

func load_preferences() -> void:
	config = ConfigFile.new()
	config.load(storage_path)
	fullscreen = bool(config.get_value("display", "fullscreen", false))
	display_mode = str(config.get_value("display", "mode", DISPLAY_FILL))
	if display_mode != DISPLAY_PIXEL_PERFECT:
		display_mode = DISPLAY_FILL
	var stored_turn_mode := str(config.get_value("display", "turn_mode", TURN_STEPS))
	turn_mode = stored_turn_mode if stored_turn_mode in [TURN_FREE, TURN_STEPS] else TURN_STEPS
	captions = bool(config.get_value("display", "captions", false))
	apply_volumes()
	apply_display()

## Puts the saved volume sliders on the buses. The SFX slider is the volume of every
## sound-effect bus (AudioBus.SFX_FAMILY): World, Body, Entity and EntityFar follow it.
func apply_volumes() -> void:
	for index in AudioServer.bus_count:
		var bus_name := AudioServer.get_bus_name(index)
		var slider := String(AudioBus.SFX) if AudioBus.SFX_FAMILY.has(StringName(bus_name)) else bus_name
		var volume := clampf(float(config.get_value("audio", slider, 1.0)), 0.0, 1.0)
		_apply_volume(index, volume)

func _apply_volume(index: int, volume: float) -> void:
	AudioServer.set_bus_mute(index, volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))

func set_volume(bus_name: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	volume = clampf(volume, 0.0, 1.0)
	_apply_volume(index, volume)
	if bus_name == String(AudioBus.SFX):
		for family_bus in AudioBus.SFX_FAMILY:
			var family_index := AudioServer.get_bus_index(family_bus)
			if family_index >= 0:
				_apply_volume(family_index, volume)
	config.set_value("audio", bus_name, volume)
	_save()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_display()
	config.set_value("display", "fullscreen", enabled)
	_save()

func set_display_mode(mode: String) -> void:
	display_mode = mode
	config.set_value("display", "mode", mode)
	_save()
	display_mode_changed.emit()

func set_turn_mode(mode: String) -> void:
	turn_mode = mode
	config.set_value("display", "turn_mode", mode)
	_save()
	turn_mode_changed.emit()

func toggle_turn_mode() -> void:
	set_turn_mode(TURN_FREE if turn_mode == TURN_STEPS else TURN_STEPS)

func turn_caption() -> String:
	return "Turning · 22.5° steps" if turn_mode == TURN_STEPS else "Turning · Free"

func set_captions(value: bool) -> void:
	captions = value
	config.set_value("display", "captions", value)
	_save()
	captions_changed.emit()

func toggle_captions() -> void:
	set_captions(not captions)

func captions_caption() -> String:
	return "Sound captions · On" if captions else "Sound captions · Off"

func toggle_display_mode() -> void:
	set_display_mode(DISPLAY_FILL if display_mode == DISPLAY_PIXEL_PERFECT else DISPLAY_PIXEL_PERFECT)

func display_caption() -> String:
	return "Display · Pixel-perfect (borders)" if display_mode == DISPLAY_PIXEL_PERFECT else "Display · Fill screen"

func apply_display() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED

func _save() -> void:
	if config.save(storage_path) != OK:
		push_warning("Could not save preferences; changes apply to this session only.")
