extends Node
## User preferences, shared by the main menu and pause menu.
signal display_mode_changed

const DISPLAY_FILL := "fill"
const DISPLAY_PIXEL_PERFECT := "pixel_perfect"

var config := ConfigFile.new()
var storage_path := "user://preferences.cfg"
var fullscreen := false
var display_mode := DISPLAY_FILL

func _ready() -> void:
	load_preferences()

func load_preferences() -> void:
	config = ConfigFile.new()
	config.load(storage_path)
	fullscreen = bool(config.get_value("display", "fullscreen", false))
	display_mode = str(config.get_value("display", "mode", DISPLAY_FILL))
	if display_mode != DISPLAY_PIXEL_PERFECT:
		display_mode = DISPLAY_FILL
	for index in AudioServer.bus_count:
		var bus_name := AudioServer.get_bus_name(index)
		var volume := clampf(float(config.get_value("audio", bus_name, 1.0)), 0.0, 1.0)
		_apply_volume(index, volume)
	apply_display()

func _apply_volume(index: int, volume: float) -> void:
	AudioServer.set_bus_mute(index, volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))

func set_volume(bus_name: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	volume = clampf(volume, 0.0, 1.0)
	_apply_volume(index, volume)
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
