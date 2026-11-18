extends CanvasLayer
## Equipment, vital signs and contextual interaction feedback.
signal resume_requested
signal fullscreen_requested

@onready var root: Control = $Screen
@onready var prompt: Label = $Screen/InteractionPrompt
@onready var subtitle: Label = $Screen/Subtitle
@onready var caption: Label = $Screen/Caption
@onready var breath: ProgressBar = $Screen/Vitals/Breath/Meter
@onready var effort: ProgressBar = $Screen/Vitals/Exertion/Meter
@onready var battery: ProgressBar = $Screen/Vitals/Battery/Meter
@onready var shade: ColorRect = $Screen/StoryFade
@onready var end_title: Label = $Screen/EndTitle
@onready var help_panel: PanelContainer = $Screen/PauseMenu
@onready var inventory: HBoxContainer = $Screen/Inventory
@onready var key_hint: Label = $Screen/KeyHint
@onready var alert: VBoxContainer = $Screen/Alert
var _slots: Dictionary = {}
var _counts: Dictionary = {}
var _alert_tween: Tween

func _ready() -> void:
	LegacyUi.fit_root(root)
	for kind in ["flashlight", "battery", "rocks"]:
		var slot := inventory.get_node(String(kind).capitalize())
		_slots[kind] = slot
		_counts[kind] = slot.get_node("Count")

func update_breath_feedback(_feedback: Node) -> void:
	pass


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

func show_key_hint(text: String, at: Vector2) -> void:
	key_hint.text = text
	key_hint.visible = text != ""
	if text == "":
		return
	at = LegacyUi.to_ui(at)
	key_hint.position = Vector2(at.x - key_hint.size.x * .5, at.y + 34)

func place_prompt(at: Vector2, in_dialogue := false) -> void:
	at = LegacyUi.to_ui(at)
	var viewport_size := root.size
	if in_dialogue:
		prompt.position = Vector2((viewport_size.x-prompt.size.x)*.5,viewport_size.y-69)
	else:
		prompt.position = Vector2(
			clampf(at.x-prompt.size.x*.5,24,viewport_size.x-prompt.size.x-24),
			clampf(at.y+34,78,viewport_size.y-215))
