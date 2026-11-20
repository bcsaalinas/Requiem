extends CanvasLayer
## Equipment, vital signs and contextual interaction feedback.
signal resume_requested
signal fullscreen_requested

const UIPalette := preload("res://util/ui_palette.gd")
const ITEMS := preload("res://assets/art/hud/equipment_items.png")
const CHARGE_TRACK := preload("res://assets/art/hud/equipment_charge_track.png")
const CHARGE := preload("res://assets/art/hud/equipment_charge.png")
const ITEM_REGIONS := {"flashlight": Rect2(0, 0, 33, 18), "battery": Rect2(42, 0, 24, 24),
	"rocks": Rect2(68, 0, 28, 24), "key": Rect2(100, 0, 24, 24)}
const PICKUP_PROMPT_GAP := 12.0

@onready var root: Control = $Screen
@onready var prompt: Label = $Screen/InteractionPrompt
@onready var subtitle: Label = $Screen/Subtitle
## Compatibility alias used by tutorial regression and scripted caption callers.
@onready var caption: Label = $Screen/Caption
@onready var end_title: Label = $Screen/EndTitle
@onready var key_hint: Label = $Screen/KeyHint
@onready var breath: ProgressBar = $Screen/Vitals/Breath/Meter
@onready var effort: ProgressBar = $Screen/Vitals/Exertion/Meter
@onready var battery: ProgressBar = $Screen/Vitals/Battery/Meter
@onready var vitals: Node = $Screen/Vitals
@onready var banner: Label = $Screen/Banner
@onready var shade: ColorRect = $Screen/StoryFade
@onready var help_panel: PanelContainer = $Screen/PauseMenu
@onready var inventory: HBoxContainer = $Screen/Inventory
@onready var offering_inventory: HBoxContainer = $Screen/OfferingInventory
@onready var breath_hint: HBoxContainer = $Screen/BreathHint
@onready var alert: VBoxContainer = $Screen/Alert
@onready var altars_tracker: Control = $Screen/AltarsTracker
@onready var altars_count_label: Label = $Screen/AltarsTracker/VBox/Header/Count
@onready var altars_bar: ProgressBar = $Screen/AltarsTracker/VBox/Bar
var _slots: Dictionary = {}
var _counts: Dictionary = {}
var _offering_labels: Dictionary = {}
var _slot_rejects: Dictionary = {}
var _slot_base_x: Dictionary = {}
var _hint_clock := 0.0
var _hud_clock := 0.0
var _alert_tween: Tween
var _flashlight_on := false
var _battery_percent := 0.0
var _spare_batteries := 0
var _rocks_count := 0
var _throw_cooldown_frac := 0.0
## The battery % under which the flashlight is dying (the flashlight's own low_battery_threshold;
## the game sets it when it starts).
var low_battery_at := 25.0
var _inventory_overlay: Control

func _ready() -> void:
	LegacyUi.fit_root(root)
	for kind in ["flashlight", "battery", "rocks"]:
		var slot: Control = inventory.get_node(String(kind).capitalize())
		_set_item_icon(slot, kind)
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_slots[kind] = slot
		_counts[kind] = slot.get_node("Count")
		_slot_rejects[kind] = 0.0
		if kind == "flashlight":
			slot.draw.connect(_draw_charge.bind(slot))
	_inventory_overlay = Control.new()
	_inventory_overlay.name = "InventoryOverlay"
	_inventory_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_overlay.draw.connect(_draw_inventory_overlay)
	root.add_child(_inventory_overlay)
	root.move_child(_inventory_overlay, inventory.get_index() + 1)

func _process(delta: float) -> void:
	_hud_clock += delta
	var any_slot_visible := false
	for kind in _slots:
		var slot: Control = _slots[kind]
		var reject_t := float(_slot_rejects.get(kind, 0.0))
		if reject_t > 0.0:
			reject_t = maxf(0.0, reject_t - delta * 3.2)
			_slot_rejects[kind] = reject_t
			if not _slot_base_x.has(kind):
				_slot_base_x[kind] = slot.position.x
			slot.position.x = float(_slot_base_x[kind]) + sin(reject_t * TAU * 3.0) * 5.0 * reject_t
			if reject_t <= 0.0:
				slot.position.x = float(_slot_base_x[kind])
				_slot_base_x.erase(kind)
		if slot.visible:
			any_slot_visible = true
			slot.queue_redraw()
	if any_slot_visible and _inventory_overlay != null:
		_inventory_overlay.queue_redraw()

func update_breath_feedback(_feedback: Node) -> void:
	# VitalMeters owns reactive colors and captions; keep hook for compatibility.
	pass

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
	_spare_batteries = spares
	_rocks_count = rocks

	_refresh_slot_modulation()

## The key is a single story item, so add its slot only when it is first found.
func set_key(held: bool) -> void:
	if not _slots.has("key"):
		if not held:
			return
		var slot: Control = _slots.flashlight.duplicate(0)
		slot.name = "Key"
		_set_item_icon(slot, "key")
		inventory.add_child(slot)
		_slots["key"] = slot
	_slots["key"].visible = held

func show_offering(id: String, item_name: String, texture: Texture2D) -> void:
	if not _slots.has(id):
		var slot := _slots.flashlight.duplicate(0) as HBoxContainer
		slot.name = id
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.modulate = Color.WHITE
		slot.scale = Vector2.ONE
		(slot.get_node("Icon") as TextureRect).texture = texture
		_offering_labels[id] = item_name.to_upper()
		_slots[id] = slot
		offering_inventory.add_child(slot)
		slot.draw.connect(_draw_slot_card.bind(id))
	_slots[id].show()
	# Give the container a frame to position a slot before scaling it around its center.
	pulse_slot.call_deferred(id)

func hide_offering(id: String) -> void:
	if _offering_labels.has(id):
		_slots[id].hide()

func show_key_hint(message: String, window_position: Vector2) -> void:
	key_hint.text = message
	key_hint.visible = not message.is_empty()
	if message.is_empty():
		return
	key_hint.position = Vector2(window_position.x - key_hint.size.x * 0.5, window_position.y + 34.0)

## Rich per-frame equipment feedback: light power, swap prompt, empty dim, throw cooldown.
func update_equipment_state(flashlight_on: bool, battery_percent: float, spares: int, rocks: int, throw_cooldown_frac := 0.0) -> void:
	_flashlight_on = flashlight_on
	_battery_percent = battery_percent
	_spare_batteries = spares
	_rocks_count = rocks
	_throw_cooldown_frac = clampf(throw_cooldown_frac, 0.0, 1.0)
	_refresh_slot_modulation()

func _refresh_slot_modulation() -> void:
	var low_bat := _battery_percent <= low_battery_at
	var dead_bat := _battery_percent <= 0.0
	var flash_slot: Control = _slots.get("flashlight")
	if flash_slot != null:
		if dead_bat:
			flash_slot.modulate = Color(0.75, 0.52, 0.50, 0.85)
		elif _flashlight_on:
			flash_slot.modulate = Color(1.06, 1.04, 0.96, 1.0)
		else:
			flash_slot.modulate = Color(0.74, 0.76, 0.78, 0.88)
	var bat_slot: Control = _slots.get("battery")
	if bat_slot != null:
		var pulse := 0.5 + 0.5 * sin(_hud_clock * TAU * 2.2)
		if _spare_batteries <= 0:
			bat_slot.modulate = Color(0.55, 0.54, 0.54, 0.65)
		elif low_bat and _slots.flashlight.visible:
			bat_slot.modulate = Color(1.0, 0.96, 0.88).lerp(Color(1.22, 1.12, 0.86), pulse)
		else:
			bat_slot.modulate = Color.WHITE
	var rock_slot: Control = _slots.get("rocks")
	if rock_slot != null:
		if _rocks_count <= 0:
			rock_slot.modulate = Color(0.52, 0.52, 0.54, 0.62)
		elif _throw_cooldown_frac > 0.0:
			rock_slot.modulate = Color(0.76, 0.78, 0.82, 0.88)
		else:
			rock_slot.modulate = Color.WHITE

## A short pop of an inventory slot when something lands in it.
func pulse_slot(kind: String) -> void:
	var slot: Control = _slots.get(kind)
	if slot == null:
		return
	slot.pivot_offset = slot.size * 0.5
	var tween := slot.create_tween()
	tween.tween_property(slot, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_BACK)
	tween.tween_property(slot, "scale", Vector2.ONE, 0.25)

## Tactile rejection shake + crimson flash when an action cannot be performed.
func reject_slot(kind: String) -> void:
	if not _slots.has(kind):
		return
	_slot_rejects[kind] = 1.0
	var slot: Control = _slots[kind]
	slot.queue_redraw()

func _set_item_icon(slot: Control, kind: String) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = ITEMS
	atlas.region = ITEM_REGIONS[kind]
	var icon := slot.get_node("Icon") as TextureRect
	icon.texture = atlas
	icon.custom_minimum_size = atlas.region.size * 1.25
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.custom_minimum_size = Vector2.ZERO

func _draw_charge(slot: Control) -> void:
	var icon := slot.get_node("Icon") as Control
	var origin := Vector2(icon.position.x, slot.size.y - 5.0).round()
	var track := Rect2(2, 18, 29, 5)
	slot.draw_texture_rect_region(CHARGE_TRACK, Rect2(origin, track.size * 1.25), track)
	var cells := clampi(ceili(_battery_percent / 25.0), 0, 4)
	if cells > 0:
		var region := Rect2(2, 18, cells * 7, 5)
		slot.draw_texture_rect_region(CHARGE, Rect2(origin, region.size * 1.25), region)

func _draw_slot_card(kind: String) -> void:
	var slot: Control = _slots[kind]
	var font := slot.get_theme_font("font", "Label")
	slot.draw_string(font, Vector2(0, slot.size.y + 8), _offering_labels[kind],
		HORIZONTAL_ALIGNMENT_CENTER, slot.size.x, 12, UIPalette.TEXT)

func _draw_inventory_overlay() -> void:
	if _inventory_overlay == null:
		return
	var rock_slot: Control = _slots.get("rocks")
	if rock_slot != null and rock_slot.visible and _throw_cooldown_frac > 0.0:
		var slot_to_overlay := _inventory_overlay.get_global_transform().affine_inverse() * rock_slot.get_global_transform()
		var slot_rect := slot_to_overlay * Rect2(Vector2.ZERO, rock_slot.size)
		var fill_h := slot_rect.size.y * _throw_cooldown_frac
		var sweep := Rect2(slot_rect.position.x, slot_rect.end.y - fill_h, slot_rect.size.x, fill_h)
		_inventory_overlay.draw_rect(sweep, Color(0.04, 0.05, 0.06, 0.45), true)

func place_prompt(at: Vector2, in_dialogue := false, above := false) -> void:
	var viewport_size := PixelDisplay.UI_CANVAS
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if above and not in_dialogue else VERTICAL_ALIGNMENT_TOP
	if in_dialogue:
		prompt.position = Vector2((viewport_size.x-prompt.size.x)*.5,viewport_size.y-69)
	else:
		prompt.position = Vector2(
			clampf(at.x-prompt.size.x*.5,24,viewport_size.x-prompt.size.x-24),
			clampf(at.y-PICKUP_PROMPT_GAP-prompt.size.y if above else at.y+34,78,viewport_size.y-215))

func show_altars_tracker(shown: bool) -> void:
	if altars_tracker != null:
		altars_tracker.visible = shown

func set_altars_count(count: int, total: int = 7) -> void:
	if altars_tracker == null or altars_count_label == null or altars_bar == null:
		return
	altars_count_label.text = "%d / %d" % [count, total]
	altars_bar.max_value = float(total)
	var tw := create_tween()
	tw.tween_property(altars_bar, "value", float(count), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	altars_tracker.pivot_offset = altars_tracker.size * 0.5
	var pop := create_tween()
	pop.tween_property(altars_tracker, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_BACK)
	pop.tween_property(altars_tracker, "scale", Vector2.ONE, 0.22)
