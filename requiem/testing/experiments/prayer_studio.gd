extends "res://testing/experiments/breath_studio.gd"
## Safe review of the shared player and the real twelve-second altar ritual.
## Presets reset starting conditions; only BodyAltar can accept or advance prayer.

const AltarScene := preload("res://altar/altar.tscn")
const ALTAR_POSITION := Vector2(420, 350)
const FACING_NAMES := ["East", "South-east", "South", "South-west", "West", "North-west", "North", "North-east"]

var altar: Node
var heading_selector: OptionButton
var selected_heading := 6
var ritual_completed := false
var _altar_root: Node2D


func _ready() -> void:
	super._ready()
	entity.active = false
	entity.hide()
	thrower.available = false
	flashlight.click_clips.assign([sound("switch")])
	_update_equipment_label()
	hud.subtitle.text = "Hold E near the altar. Release at any point to return naturally."


func _build_studio_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PrayerStudioOverlay"
	layer.layer = 30
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(20, 16)
	panel.add_theme_constant_override("separation", 5)
	layer.add_child(panel)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	panel.add_child(heading)
	heading.add_child(_label("PRAYER STUDIO · SAFE SANDBOX", 16))
	studio_status = _label("", 14)
	heading.add_child(studio_status)
	panel.add_child(_label("Hold E pray · Space hold breath · WASD move · F light · R reset · Esc pause · F1 Test Lab", 13))
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	panel.add_child(controls)
	_studio_button(controls, "Reset ritual", func(): reset_studio_prayer())
	_studio_button(controls, "Low air · 25%", func(): reset_studio_prayer(25.0))
	equipment_button = _studio_button(controls, "", func():
		set_equipment_mode((get_equipment_mode() + 1) % 3))
	equipment_button.tooltip_text = "Cycle through no flashlight, flashlight off, and flashlight on."
	heading_selector = OptionButton.new()
	heading_selector.focus_mode = Control.FOCUS_NONE
	for facing in FACING_NAMES:
		heading_selector.add_item("Face " + facing)
	heading_selector.select(selected_heading)
	heading_selector.item_selected.connect(set_studio_heading)
	controls.add_child(heading_selector)


func set_effects_enabled(show_effects: bool) -> void:
	player.get_node("BreathFeedback").effects_strength = 1.0 if show_effects else 0.0


func get_equipment_mode() -> int:
	return 0 if not has_flashlight else (2 if flashlight.is_on else 1)


func set_equipment_mode(mode: int) -> void:
	set_equipped(mode > 0)
	flashlight.is_on = mode == 2
	flashlight._refresh_light()
	_update_equipment_label()


func _update_equipment_label() -> void:
	if is_instance_valid(equipment_button):
		equipment_button.text = ["Flashlight: absent", "Flashlight: off", "Flashlight: on"][get_equipment_mode()]


func set_studio_area(_index: int) -> void:
	# The open rug has room for all eight views and retains production lighting.
	enter_zone("bedroom", ALTAR_POSITION + Vector2(0, 66), false)
	reset_studio_prayer()


func set_studio_heading(index: int) -> void:
	selected_heading = posmod(index, 8)
	heading_selector.select(selected_heading)
	reset_studio_prayer()


func reset_studio_prayer(lung := 100.0) -> void:
	for action_name in ["pray", "throw", "hold_breath", "sprint", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action_name)
	if is_instance_valid(altar):
		altar._cancelar_rezo()
	if is_instance_valid(_altar_root):
		remove_child(_altar_root)
		_altar_root.queue_free()
	GameState.reset()
	ritual_completed = false
	thrower.clear_pending()
	thrower.available = false
	reset_studio_breath(lung, 0.0)
	player.velocity = Vector2.ZERO
	player.get_node("FootstepNoise").footstep_timer = 0.0
	var feedback := player.get_node_or_null("PrayerFeedback")
	if feedback != null:
		feedback.reset_feedback()
	_spawn_altar()
	var direction := Vector2.from_angle(selected_heading * PI / 4.0)
	player.global_position = ALTAR_POSITION - direction * 66.0
	# Drive the shared gait selector once to establish the preset facing, then
	# settle it normally. This also supports headings before flashlight pickup.
	var appearance := player.get_node("Appearance")
	appearance.set_actor_gait(0.0, true, direction, false, 0.0)
	player.get_node("PlayerMotion").reset_pose()
	player.get_node("PlayerAim").reset_pose()
	player.get_node("PlayerAim").set_target(ALTAR_POSITION)
	player.get_node("Camera2D").reset_smoothing()


func _spawn_altar() -> void:
	_altar_root = AltarScene.instantiate()
	_altar_root.name = "StudioAltar"
	_altar_root.position = ALTAR_POSITION
	add_child(_altar_root)
	altar = _altar_root.get_node("BodyAltar")
	# Skin the real altar sprite with the existing production atlas. Its own
	# pulse tint, collision, proximity, progress, audio and completion stay live.
	var texture := AtlasTexture.new()
	texture.atlas = Art.SPRITES
	texture.region = Art.CELLS["altar"]
	var sprite: Sprite2D = altar.get_node("Sprite2D")
	sprite.texture = texture
	sprite.scale = Vector2(80.0 / 282.0, 72.0 / 269.0)
	sprite.position = Vector2(0, -12)
	sprite.modulate = Color(0.84, 0.80, 0.70)
	sprite.self_modulate = Color.WHITE
	sprite.light_mask = 2
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = preload("res://tutorial/materials.gd").scenery_material()
	altar._color_base = sprite.modulate
	var label: Label = altar.get_node("Label")
	label.text = "Hold E · pray"
	label.position = Vector2(-48, -60)
	label.size = Vector2(96, 18)
	label.add_theme_font_size_override("font_size", 10)
	var progress: ProgressBar = altar.get_node("ProgressBar")
	progress.position = Vector2(-35, 28)
	progress.size = Vector2(70, 6)
	progress.hide()
	altar.pray_clips.assign([sound("prayer")])
	altar.pray_volume_db = -13.0


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(studio_status): return
	if not is_instance_valid(altar) and is_instance_valid(_altar_root):
		ritual_completed = true
	var feedback := player.get_node_or_null("PrayerFeedback")
	var phase: String = String(feedback.phase) if feedback != null else "idle"
	var action: String = String(player.get_node("ActionState").get_action())
	var elapsed: float = altar.tiempo_interaccion if is_instance_valid(altar) else (12.0 if ritual_completed else 0.0)
	var duration: float = altar.pray_duration if is_instance_valid(altar) else 12.0
	studio_status.text = "%s · %.1f / %.0f s · %s · Air %d%%" % [
		"Complete" if ritual_completed else phase.capitalize(), elapsed, duration, action, roundi(breath.lung_percent)]
	_update_equipment_label()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_R and not _paused:
			reset_studio_prayer()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F1 and not get_parent().has_method("show_menu"):
			get_tree().paused = false
			get_tree().change_scene_to_file.call_deferred("res://testing/test_lab.tscn")
			get_viewport().set_input_as_handled()
			return
	super._input(event)


func _on_rock_landed(_at: Vector2) -> void:
	pass
