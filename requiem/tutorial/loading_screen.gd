extends CanvasLayer
## Beta loading screen. Builds itself in code, like every other HUD piece.
##
## Two ideas carry it. The indicator is a breath, not a spinner: it fills on an
## inhale curve, holds, then releases faster than it filled, so the player is
## breathing with the game before the game starts. And the loading beat is the
## only place the game speaks in its own voice, so it carries the moodboard
## lines rather than a tip list.
##
## Layer 90: above the HUD (20) and the pause menu (60), below GameOverUi (100).
##
## Usage:
##   LoadingScreen.show_for("res://tutorial/tutorial.tscn")   # threaded swap
##   LoadingScreen.begin()  ...  LoadingScreen.finish()       # manual bracket

signal finished

@export_group("Timing")
## Floor on how long the screen stays up. Without it a fast load flashes.
@export var minimum_time: float = 2.2
@export var fade_in: float = 0.35
@export var fade_out: float = 0.8

@export_group("Breath")
## Seconds for one full inhale.
@export var inhale_time: float = 2.6
## Seconds held at the top before the bar releases.
@export var hold_time: float = 0.9

@export_group("Voice")
@export var lines: Array[String] = [
	"LISTEN OR DIE",
	"EVERY BREATH BETRAYS YOU",
	"PRAYER WON'T SAVE YOU. SURVIVING IT WILL.",
	"IT CANNOT SEE YOU. IT HAS NEVER SEEN ANYTHING.",
	"THE DARK IS NOT THE THREAT. YOU ARE.",
]
@export var line_interval: float = 3.4

var _root: Control
var _line: Label
var _hint: Label
var _bar: ProgressBar
var _fill: StyleBoxFlat

var _active: bool = false
var _elapsed: float = 0.0
var _breath_clock: float = 0.0
var _line_clock: float = 0.0
var _line_index: int = 0
var _target_path: String = ""
var _ready_to_leave: bool = false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = UIPalette.PANEL_SOLID
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(veil)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 26)
	column.offset_left = -300
	column.offset_right = 300
	column.offset_top = -90
	column.offset_bottom = 90
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	_line = UIPalette.label(lines[0] if not lines.is_empty() else "", 21, UIPalette.SUBTITLE)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_line)

	# Wider and thinner than a vitals meter: it reads as a horizon, not as a
	# resource the player owns.
	var holder := CenterContainer.new()
	column.add_child(holder)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(300, 3)
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_fill = UIPalette.flat(UIPalette.BONE)
	_bar.add_theme_stylebox_override("background", UIPalette.flat(UIPalette.TRACK))
	_bar.add_theme_stylebox_override("fill", _fill)
	holder.add_child(_bar)

	_hint = UIPalette.label("breathe in", UIPalette.CAPTION_SIZE, UIPalette.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)


## Loads a scene in the background and swaps to it once the breath settles.
func show_for(scene_path: String) -> void:
	_target_path = scene_path
	ResourceLoader.load_threaded_request(scene_path)
	begin()


## Opens the screen without owning the load. Call finish() when ready.
func begin() -> void:
	if _active:
		return
	_active = true
	_elapsed = 0.0
	_breath_clock = 0.0
	_line_clock = 0.0
	_line_index = 0
	_ready_to_leave = false
	if not lines.is_empty():
		_line.text = lines[0]

	_root.visible = true
	_root.modulate.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_root, "modulate:a", 1.0, fade_in)


## Marks the work done. The screen still waits out minimum_time.
func finish() -> void:
	_ready_to_leave = true


func _process(delta: float) -> void:
	if not _active:
		return

	_elapsed += delta
	_drive_breath(delta)
	_rotate_line(delta)

	if _target_path != "":
		_poll_load()

	if _ready_to_leave and _elapsed >= minimum_time:
		_close()


func _poll_load() -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_target_path, progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_ready_to_leave = true
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		push_error("[LoadingScreen] Failed to load %s" % _target_path)
		_ready_to_leave = true


## Inhale, hold, release — the rhythm the player will be managing all game.
## Deliberately not tied to load progress: a bar that stalls at 80% tells the
## player the game is broken, a bar that breathes tells them to wait.
func _drive_breath(delta: float) -> void:
	var cycle: float = inhale_time + hold_time + inhale_time * 0.8
	_breath_clock = fmod(_breath_clock + delta, cycle)

	var value: float
	if _breath_clock < inhale_time:
		var t: float = _breath_clock / inhale_time
		value = ease(t, 0.45)              # fast start, slow top — a real inhale
		_hint.text = "breathe in"
	elif _breath_clock < inhale_time + hold_time:
		value = 1.0
		_hint.text = "hold"
	else:
		var t: float = (_breath_clock - inhale_time - hold_time) / (inhale_time * 0.8)
		value = 1.0 - ease(t, 2.2)         # the release is quicker than the fill
		_hint.text = "release"

	_bar.value = value
	_fill.bg_color = UIPalette.BONE.lerp(UIPalette.CANDLE, value * 0.45)
	_hint.modulate.a = lerpf(0.4, 0.9, value)


func _rotate_line(delta: float) -> void:
	if lines.size() < 2:
		return
	_line_clock += delta
	if _line_clock < line_interval:
		return
	_line_clock = 0.0
	_line_index = (_line_index + 1) % lines.size()

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_line, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): _line.text = lines[_line_index])
	tween.tween_property(_line, "modulate:a", 1.0, 0.6)


func _close() -> void:
	_active = false

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_root, "modulate:a", 0.0, fade_out)
	tween.tween_callback(func():
		_root.visible = false
		if _target_path != "":
			var packed: PackedScene = ResourceLoader.load_threaded_get(_target_path)
			_target_path = ""
			if packed:
				get_tree().change_scene_to_packed(packed)
		finished.emit()
	)
