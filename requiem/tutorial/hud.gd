extends CanvasLayer
## Equipment, vital signs and contextual interaction feedback.
signal resume_requested
signal fullscreen_requested

@onready var root: Control = $Screen
@onready var prompt: Label = $Screen/InteractionPrompt
@onready var subtitle: Label = $Screen/Subtitle
@onready var breath: ProgressBar = $Screen/Vitals/Breath/Meter
@onready var effort: ProgressBar = $Screen/Vitals/Exertion/Meter
@onready var battery: ProgressBar = $Screen/Vitals/Battery/Meter
@onready var banner: Label = $Screen/Banner
@onready var shade: ColorRect = $Screen/StoryFade
@onready var help_panel: PanelContainer = $Screen/PauseMenu
@onready var inventory: HBoxContainer = $Screen/Inventory
var _slots: Dictionary = {}
var _counts: Dictionary = {}
var _breath_fill: StyleBoxFlat
var _effort_fill: StyleBoxFlat

func _ready() -> void:
	# Each HUD owns these styles; warning pulses cannot leak into other scenes.
	_breath_fill = breath.get_theme_stylebox("fill").duplicate()
	_effort_fill = effort.get_theme_stylebox("fill").duplicate()
	breath.add_theme_stylebox_override("fill", _breath_fill)
	effort.add_theme_stylebox_override("fill", _effort_fill)
	for kind in ["flashlight", "battery", "rocks"]:
		var slot := inventory.get_node(String(kind).capitalize())
		_slots[kind] = slot
		_counts[kind] = slot.get_node("Count")

func update_breath_feedback(feedback: Node) -> void:
	_breath_fill.bg_color = feedback.get_meter_color()
	_effort_fill.bg_color = feedback.get_meter_color(true)
	var caption: Label = $Screen/Vitals/Breath/Caption
	caption.text = feedback.get_meter_caption()
	caption.modulate = Color.WHITE.lerp(Color("f2c3a3"), feedback.lung_pressure * feedback.pulse * 0.35)

func _on_resume_pressed() -> void:
	resume_requested.emit()

func _on_fullscreen_pressed() -> void:
	fullscreen_requested.emit()

func update_inventory(equipped: bool, spares: int, rocks: int) -> void:
	_slots.flashlight.visible = equipped
	_slots.battery.visible = equipped or spares > 0
	_slots.rocks.visible = _slots.rocks.visible or rocks > 0
	_counts.battery.text = str(spares)
	_counts.rocks.text = str(rocks)
	battery.get_parent().visible = equipped

func place_prompt(at: Vector2, in_dialogue := false) -> void:
	var viewport_size := root.size
	if in_dialogue:
		prompt.position = Vector2((viewport_size.x-prompt.size.x)*.5,viewport_size.y-69)
	else:
		prompt.position = Vector2(
			clampf(at.x-prompt.size.x*.5,24,viewport_size.x-prompt.size.x-24),
			clampf(at.y+34,78,viewport_size.y-215))
