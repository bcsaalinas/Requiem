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
@onready var breath_hint: HBoxContainer = $Screen/BreathHint
@onready var alert: VBoxContainer = $Screen/Alert
var _slots: Dictionary = {}
var _counts: Dictionary = {}
var _breath_fill: StyleBoxFlat
var _effort_fill: StyleBoxFlat
var _hint_clock := 0.0
var _alert_tween: Tween

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

## The hallway's standing lesson: the key next to the breath meter. `urgency` (0..1) rises as a
## parent door comes within earshot and makes the hint and the meter pulse; holding the breath
## settles both.
func set_breath_hint(shown: bool, holding := false, urgency := 0.0, delta := 0.0) -> void:
	var meter_box := breath.get_parent() as CanvasItem
	breath_hint.visible = shown
	if not shown:
		meter_box.modulate = Color.WHITE
		return
	_hint_clock += delta
	var pulse := 0.5 + 0.5 * sin(_hint_clock * TAU * 1.4)
	var glow := 0.0 if holding else (0.25 + 0.75 * urgency) * pulse
	(breath_hint.get_node("Text") as Label).text = "Quiet steps" if holding else "Hold breath"
	breath_hint.modulate = Color(1, 1, 1, 0.55) if holding else Color.WHITE.lerp(Color(1.45, 1.2, 1.0), glow)
	meter_box.modulate = Color.WHITE.lerp(Color(1.6, 1.4, 1.15), glow)

## A large centred call to action that fades out on its own (the first parent warning).
func flash_alert(title: String, detail: String, duration := 3.0) -> void:
	(alert.get_node("Title") as Label).text = title
	(alert.get_node("Detail") as Label).text = detail
	alert.modulate.a = 1.0
	alert.show()
	if _alert_tween != null:
		_alert_tween.kill()
	_alert_tween = create_tween()
	_alert_tween.tween_interval(duration)
	_alert_tween.tween_property(alert, "modulate:a", 0.0, 0.6)
	_alert_tween.tween_callback(alert.hide)

## Fades the alert early, once the player has done what it asked.
func dismiss_alert() -> void:
	if not alert.visible or (_alert_tween != null and _alert_tween.is_running() and alert.modulate.a < 1.0):
		return
	if _alert_tween != null:
		_alert_tween.kill()
	_alert_tween = create_tween()
	_alert_tween.tween_property(alert, "modulate:a", 0.0, 0.5)
	_alert_tween.tween_callback(alert.hide)

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

## A short pop of an inventory slot when something lands in it.
func pulse_slot(kind: String) -> void:
	var slot: Control = _slots.get(kind)
	if slot == null:
		return
	slot.pivot_offset = slot.size * 0.5
	var tween := slot.create_tween()
	tween.tween_property(slot, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_BACK)
	tween.tween_property(slot, "scale", Vector2.ONE, 0.25)

func place_prompt(at: Vector2, in_dialogue := false) -> void:
	var viewport_size := root.size
	if in_dialogue:
		prompt.position = Vector2((viewport_size.x-prompt.size.x)*.5,viewport_size.y-69)
	else:
		prompt.position = Vector2(
			clampf(at.x-prompt.size.x*.5,24,viewport_size.x-prompt.size.x-24),
			clampf(at.y+34,78,viewport_size.y-215))
