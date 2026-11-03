@tool
class_name Door
extends Node2D
## A doorway cut into the wall TileMapLayer. The leaf, the movement blocker and the light
## occluder always change together: a closed door stops bodies, light and (with Room covers) sight.
##
## FRONT doors sit in an east-west wall: an upright leaf in the wall face plus its top edge in the
## dark wall band. SIDE doors sit in a north-south wall: a plank seen from above that swings 90 deg.
## The node origin is the floor line of the doorway (bottom of the face for FRONT, south end of the
## gap for SIDE), so the door y-sorts like the wall it belongs to.

signal opened
signal closed

enum Style { FRONT, SIDE }

@export var style := Style.FRONT:
	set(value):
		style = value
		_apply_swing()
@export var start_open := false
@export var locked := false:
	set(value):
		locked = value
		_update_light()
## Seconds the leaf takes to swing open or shut.
@export_range(0.05, 2.0, 0.05) var swing_time := 0.35
## SIDE doors only: 1 swings the leaf toward +x (east), -1 toward -x (west).
@export_range(-1, 1, 2) var swing_side := 1:
	set(value):
		swing_side = value
		_apply_swing()
## 0 = shut, 1 = fully open. Animated by open()/close(); editable to preview in the editor.
@export_range(0.0, 1.0, 0.01) var swing := 0.0:
	set(value):
		swing = value
		_apply_swing()

@export_group("Noise")
## Radius of the creak heard by listeners (entity, parents), in units (1 u = 32 px).
@export var noise_radius_u := 2.5
## Radius when the door is eased open or shut while the player holds their breath.
@export var quiet_noise_radius_u := 1.0
@export var creak: AudioStream

## Bodies in this group push a closed, unlocked door open when they reach it (the entity).
@export var opened_by_group: StringName = &"entity"

@export_group("Light")
## Energy of the small warm lights at the doorway (children of Glow), so doors read in the dark.
@export var light_energy := 0.75:
	set(value):
		light_energy = value
		_update_light()
## Energy while the door is locked: still visible, but it does not invite.
@export var locked_light_energy := 0.35:
	set(value):
		locked_light_energy = value
		_update_light()
## Light multiplier while the door is the focused interaction.
@export var focused_light_boost := 1.6

@export_group("Interaction")
@export var open_label := "Open door"
@export var close_label := "Close door"
@export var locked_label := "Locked"

var is_open := false
var focused := false
var _tween: Tween


func _ready() -> void:
	if start_open:
		is_open = true
		swing = 1.0
	_sync_blockers()
	_apply_swing()
	_update_light()
	var doorway := get_node_or_null("Doorway") as Area2D
	if doorway != null and not Engine.is_editor_hint():
		doorway.body_entered.connect(_on_doorway_body_entered)


func _on_doorway_body_entered(body: Node2D) -> void:
	if opened_by_group != &"" and body.is_in_group(opened_by_group) and body.is_visible_in_tree():
		open()


## Opens the door. Returns false when it is locked or already open.
func open(quiet := false, silent := false) -> bool:
	if locked or is_open:
		return false
	is_open = true
	_sync_blockers()
	_animate(1.0)
	if not silent:
		_make_noise(quiet)
	opened.emit()
	return true


## Shuts the door unless a body stands in the doorway. Returns false when it cannot shut.
func close(quiet := false, silent := false) -> bool:
	if not is_open or is_doorway_occupied():
		return false
	is_open = false
	_animate(0.0)
	_sync_blockers()
	if not silent:
		_make_noise(quiet)
	closed.emit()
	return true


func toggle(quiet := false) -> bool:
	return close(quiet) if is_open else open(quiet)


## Sets the state at once, without sound (arrivals through a door, checkpoint restores).
func snap(open_state: bool) -> void:
	if _tween != null:
		_tween.kill()
	is_open = open_state
	swing = 1.0 if open_state else 0.0
	_sync_blockers()
	if open_state:
		opened.emit()
	else:
		closed.emit()


func is_doorway_occupied() -> bool:
	var doorway := get_node_or_null("Doorway") as Area2D
	return doorway != null and doorway.monitoring and doorway.has_overlapping_bodies()


func interaction_label() -> String:
	if locked:
		return locked_label
	return close_label if is_open else open_label


## Doors take part in the tutorial interaction highlight like the other props.
func set_focused(value: bool) -> void:
	focused = value
	var frame := get_node_or_null("Frame") as CanvasItem
	if frame != null:
		frame.modulate = Color(1.5, 1.4, 1.2) if value else Color.WHITE
	_update_light()


func _update_light() -> void:
	var glow := get_node_or_null("Glow")
	if glow == null:
		return
	var energy := locked_light_energy if locked else light_energy
	if focused:
		energy *= focused_light_boost
	for light in glow.get_children():
		if light is PointLight2D:
			light.energy = energy


func _animate(target: float) -> void:
	if _tween != null:
		_tween.kill()
	if not is_inside_tree() or swing_time <= 0.0:
		swing = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "swing", target, swing_time * absf(target - swing)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if target > swing else Tween.EASE_IN)


## Blocker and occluder follow the logical state at once, so light and bodies never pass a shut door.
func _sync_blockers() -> void:
	var shape := get_node_or_null("Blocker/Shape") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", is_open)
	var occluder := get_node_or_null("Occluder") as LightOccluder2D
	if occluder != null:
		occluder.visible = not is_open


func _apply_swing() -> void:
	if not is_inside_tree():
		return
	var hinge := get_node_or_null("Hinge") as Node2D
	if style == Style.FRONT:
		# Seen from the front, a leaf turning away from the viewer narrows toward its hinge.
		if hinge != null:
			hinge.scale.x = lerpf(1.0, 0.16, swing)
			hinge.modulate = Color.WHITE.lerp(Color(0.42, 0.42, 0.42), swing)
		var top := get_node_or_null("TopHinge") as Node2D
		if top != null:
			top.rotation = lerpf(0.0, PI * 0.5, swing)
	elif hinge != null:
		hinge.rotation = lerpf(0.0, -swing_side * PI * 0.5, swing)


func _make_noise(quiet: bool) -> void:
	var audio := get_node_or_null("Audio") as AudioStreamPlayer2D
	if audio != null and creak != null:
		audio.stream = creak
		audio.volume_db = -14.0 if quiet else -6.0
		audio.pitch_scale = randf_range(0.92, 1.05)
		audio.play()
	if Engine.is_editor_hint():
		return
	var radius_u := quiet_noise_radius_u if quiet else noise_radius_u
	if radius_u > 0.0:
		NoiseManager.emit_noise(get_noise_origin(), radius_u * Units.PX_PER_UNIT, NoiseManager.SourceType.DOOR)


## Centre of the doorway gap in global coordinates.
func get_noise_origin() -> Vector2:
	return to_global(Vector2(0.0, -48.0) if style == Style.FRONT else Vector2(0.0, -32.0))
