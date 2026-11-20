@tool
class_name Door
extends Node2D
## A doorway cut into the wall TileMapLayer. The leaf, the movement blocker and the light
## occluder always change together: a closed door stops bodies, light and (with Room covers) sight.
##
## Seen from above, both styles are the same door: a floor-level frame (the threshold) and a leaf at
## wall height that swings 90 degrees about its hinge. `style` is only the wall orientation: FRONT sits
## in an east-west wall, SIDE in a north-south wall. The node origin is the floor line of the
## doorway (bottom of the drawn wall row for FRONT, south end of the gap for SIDE).

signal opened
signal closed
## A body pushed it open (push_open): who, and whether it was slammed.
signal pushed(by: Node2D, slammed: bool)
## A body tried it and it is locked.
signal rattled(by: Node2D)

enum Style { FRONT, SIDE }
## What a body that walks into a closed door wants to do with it (its wants_door(door) answers):
## push it open, stand in front of it for now and push it later, or slam it.
enum Push { OPEN, WAIT, SLAM }

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
## FRONT: 1 swings the leaf toward +y (south), -1 toward -y (north). SIDE: 1 swings it east, -1 west.
@export_range(-1, 1, 2) var swing_side := 1:
	set(value):
		swing_side = value
		_apply_swing()
## 0 = shut, 1 = fully open. Animated by open()/close(); editable to preview in the editor.
@export_range(0.0, 1.0, 0.01) var swing := 0.0:
	set(value):
		swing = value
		_apply_swing()

@export var leaf_texture: Texture2D = preload("res://assets/art/props/door_leaf_closed.png"):
	set(value):
		leaf_texture = value
		_apply_swing()

@export_group("Noise")
## Radius of the creak heard by listeners (entity, parents), in units (1 u = 32 px).
@export var noise_radius_u := 2.5
## Radius when the door is eased open or shut while the player holds their breath.
@export var quiet_noise_radius_u := 1.0
@export var creak: AudioStream
## The door pushed open by a body, slammed open by one, and tried while locked. Each one empty:
## the creak stands in for it (lower and heavier, loud and short, a short strain).
@export var pushed_sound: AudioStream
@export var slam_sound: AudioStream
@export var locked_sound: AudioStream

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
@export var open_label := "Open"
@export var close_label := "Close"
@export var locked_label := "Locked"

## Every door of a running level is in this group.
const DOOR_GROUP := &"doors"
## A door pushed open by a body: the creak, lower and heavier, until it has its own sound.
const PUSHED_VOLUME_DB := -6.0
const PUSHED_PITCH := Vector2(0.72, 0.84)
## Slammed open (a hunt): louder, shorter, and the leaf swings in a fraction of its time.
const SLAM_VOLUME_DB := -3.0
const SLAM_PITCH := Vector2(1.3, 1.45)
const SLAM_SWING := 0.35
## Tried while locked: a short strain of the wood, until it has its own rattle.
const LOCKED_VOLUME_DB := -10.0
const LOCKED_PITCH := Vector2(1.5, 1.7)
const LOCKED_STRAIN := 0.4

## Leaf art: 160x34 px canvas drawn hinged on the left, swinging south; the pivot is the hinge-end
## corner of the swing face. The closed leaf sits 23 art px below the top of the frame.
const LEAF_CANVAS_Y := 23.0
const LEAF_WIDTH := 160.0
const PIVOT_Y_SOUTH := 27.0
const PIVOT_Y_NORTH := 7.0
const FRAME_SIZE := Vector2(64, 32)

var is_open := false
var focused := false
var _tween: Tween
var _hinge_base := Vector2.ZERO
var _leaf_body_pending := false
## 1 for an ordinary swing; less while a slam is being started.
var _swing_scale := 1.0
## Counts the door's sounds, so that a cut meant for one never stops the next.
var _sound_token := 0


func _ready() -> void:
	var door_audio := get_node_or_null("Audio") as AudioStreamPlayer2D
	if door_audio != null:
		door_audio.bus = AudioBus.WORLD
	if start_open:
		is_open = true
		swing = 1.0
	_sync_blockers()
	_apply_swing()
	_update_light()
	var doorway := get_node_or_null("Doorway") as Area2D
	if doorway != null and not Engine.is_editor_hint():
		doorway.body_entered.connect(_on_doorway_body_entered)
	if not Engine.is_editor_hint():
		# The entity finds doors here: a closed one on a sound's way muffles it, and a search
		# ends through one.
		add_to_group(DOOR_GROUP)


func _process(_delta: float) -> void:
	var assembly := get_node_or_null("Assembly") as Node2D
	var hinge := get_node_or_null("Assembly/Hinge") as Node2D
	if assembly == null or hinge == null or Engine.is_editor_hint():
		return
	var shift := HeightShift.offset_for(assembly.global_position)
	hinge.position = _hinge_base + shift.rotated(-assembly.global_rotation)
	if _leaf_body_pending:
		_update_leaf_body()


func _on_doorway_body_entered(body: Node2D) -> void:
	if opened_by_group != &"" and body.is_in_group(opened_by_group) and body.is_visible_in_tree():
		push_open(body)


## A body walked into it (the entity). Viv hears the door; nothing here is one of her noises,
## so no NoiseManager event is sent and the entity never hunts its own door.
## - Locked: it is tried (the rattle), and the body is told (door_refused(door)).
## - Otherwise the body is asked what it wants (wants_door(door) -> Push): it may stand in
##   front of the door first and call push_open() again later, or slam it.
## Returns true when the door opened.
func push_open(by: Node2D) -> bool:
	if is_open:
		return false
	if locked:
		_play_door_sound(locked_sound, LOCKED_VOLUME_DB, LOCKED_PITCH, 0.0 if locked_sound != null else LOCKED_STRAIN)
		rattled.emit(by)
		if by != null and by.has_method(&"door_refused"):
			by.call(&"door_refused", self)
		return false
	var push: int = Push.OPEN
	if by != null and by.has_method(&"wants_door"):
		push = int(by.call(&"wants_door", self))
	if push == Push.WAIT:
		return false
	var slammed := push == Push.SLAM
	_swing_scale = SLAM_SWING if slammed else 1.0
	open(false, true)
	_swing_scale = 1.0
	if slammed:
		_play_door_sound(slam_sound, SLAM_VOLUME_DB, SLAM_PITCH)
	else:
		_play_door_sound(pushed_sound, PUSHED_VOLUME_DB, PUSHED_PITCH)
	pushed.emit(by, slammed)
	return true


## Opens the door. Returns false when it is locked or already open.
func open(quiet := false, silent := false) -> bool:
	if locked or is_open:
		return false
	is_open = true
	_sync_blockers()
	_animate(1.0)
	if not silent:
		_make_noise(quiet)
	_spawn_hinge_dust()
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
	_spawn_hinge_dust()
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
	_update_light()


## Decorative doorway lights forced off (story beats); real lights still reach the door.
var decorative_glow_off := false:
	set(value):
		decorative_glow_off = value
		_update_light()


func _update_light() -> void:
	var glow := get_node_or_null("Glow")
	if glow == null:
		return
	var energy := 0.0 if decorative_glow_off else (locked_light_energy if locked else light_energy)
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
	_tween.tween_property(self, "swing", target, swing_time * _swing_scale * absf(target - swing)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if target > swing else Tween.EASE_IN)


## Blocker and occluder follow the logical state at once, so light and bodies never pass a shut door.
func _sync_blockers() -> void:
	var shape := get_node_or_null("Blocker/Shape") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", is_open)
	for occluder_name in ["Occluder", "OccluderLeaf"]:
		var occluder := get_node_or_null(occluder_name) as LightOccluder2D
		if occluder != null:
			# FRONT doors keep the y -80 line off: it stopped her beam 57 px
			# before the leaf; the jamb posts seal the sides now.
			occluder.visible = false if occluder_name == "Occluder" 				and style == Style.FRONT else not is_open
	_sync_leaf_body()


## The swung-open leaf gets its own Viv-only body once it lands; a shut door
## still relies on Blocker. Layer 2 reaches only her mask, so the entity, the
## ranger, pebbles and navigation never feel it.
func _sync_leaf_body() -> void:
	var shape := get_node_or_null("LeafBody/Shape") as CollisionShape2D
	if shape == null:
		return
	if not is_open:
		_leaf_body_pending = false
		shape.set_deferred("disabled", true)
	else:
		_leaf_body_pending = true


func _update_leaf_body() -> void:
	var shape := get_node_or_null("LeafBody/Shape") as CollisionShape2D
	var leaf := get_node_or_null("Assembly/Hinge/Leaf") as Sprite2D
	if shape == null or leaf == null:
		_leaf_body_pending = false
		return
	if not is_open or swing < 0.99:
		return
	var xf := global_transform.affine_inverse() * leaf.global_transform
	var points := PackedVector2Array([xf * Vector2.ZERO, xf * Vector2(LEAF_WIDTH, 0.0), \
		xf * Vector2(0.0, 34.0), xf * Vector2(LEAF_WIDTH, 34.0)])
	var aabb := Rect2(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		aabb = aabb.expand(points[i])
	shape.position = aabb.get_center()
	(shape.shape as RectangleShape2D).size = aabb.size
	# If she stands where the leaf lands, the body waits until she is clear
	# instead of shoving or trapping her.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = global_transform * Transform2D(0.0, shape.position)
	query.collision_mask = 1
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 8):
		if (hit["collider"] as Node).is_in_group("player"):
			return
	shape.set_deferred("disabled", false)
	_leaf_body_pending = false


func _apply_swing() -> void:
	if not is_inside_tree():
		return
	var assembly := get_node_or_null("Assembly") as Node2D
	var hinge := get_node_or_null("Assembly/Hinge") as Node2D
	var leaf := get_node_or_null("Assembly/Hinge/Leaf") as Sprite2D
	if assembly == null or hinge == null or leaf == null:
		return
	# In assembly space the leaf is drawn hinged on the left, swinging south. SIDE doors are hinged at
	# the north end, which is the right end once the assembly is turned; swing_side 1 is south in
	# assembly space for both styles (east for SIDE).
	var swings_south := swing_side == 1
	var hinge_right := style == Style.SIDE
	leaf.texture = leaf_texture
	leaf.flip_h = hinge_right
	leaf.flip_v = not swings_south
	var pivot := Vector2(LEAF_WIDTH if hinge_right else 0.0, PIVOT_Y_SOUTH if swings_south else PIVOT_Y_NORTH)
	leaf.position = -pivot * Units.ART_SCALE
	_hinge_base = -FRAME_SIZE * 0.5 + Vector2(pivot.x, LEAF_CANVAS_Y + pivot.y) * Units.ART_SCALE
	var open_angle := PI * 0.5 if swings_south != hinge_right else -PI * 0.5
	hinge.position = _hinge_base
	hinge.rotation = open_angle * swing


func _make_noise(quiet: bool) -> void:
	_play_creak(-14.0 if quiet else -6.0, Vector2(0.92, 1.05))
	if Engine.is_editor_hint():
		return
	var radius_u := quiet_noise_radius_u if quiet else noise_radius_u
	if radius_u > 0.0:
		NoiseManager.emit_noise(get_noise_origin(), radius_u * Units.PX_PER_UNIT, NoiseManager.SourceType.DOOR)


## The door's sound alone, for Viv's ears: nothing here is a noise the entity can hear.
func _play_creak(volume_db: float, pitch: Vector2) -> void:
	_play_door_sound(creak, volume_db, pitch)


## Plays `stream` (the creak when it is empty) from the doorway. `cut_after` > 0 stops it
## after that long: the creak cut short is what stands in for a rattle.
func _play_door_sound(stream: AudioStream, volume_db: float, pitch: Vector2, cut_after := 0.0) -> void:
	var audio := get_node_or_null("Audio") as AudioStreamPlayer2D
	var sound := stream if stream != null else creak
	if audio == null or sound == null:
		return
	audio.stream = sound
	audio.volume_db = volume_db
	audio.pitch_scale = randf_range(pitch.x, pitch.y)
	audio.play()
	_sound_token += 1
	if cut_after > 0.0 and is_inside_tree():
		var token := _sound_token
		get_tree().create_timer(cut_after).timeout.connect(func() -> void:
			if token == _sound_token and audio.playing: audio.stop())


## Centre of the doorway gap in global coordinates.
func get_noise_origin() -> Vector2:
	return to_global(Vector2(0.0, -48.0) if style == Style.FRONT else Vector2(0.0, -32.0))


## Burst of plaster/wood dust out of the hinge side on every swing (vfx_door_dust sheet).
func _spawn_hinge_dust() -> void:
	var hinge := get_node_or_null("Assembly/Hinge") as Node2D
	if hinge == null or Engine.is_editor_hint():
		return
	var dust := VfxSheet.new()
	get_parent().add_child(dust)
	dust.set_as_top_level(true)
	dust.global_position = hinge.global_position
	dust.z_index = 35
	dust.play(DUST_TEXTURE, 3, DUST_MS, DUST_ANCHOR)


const VfxSheet := preload("res://level/vfx_sheet.gd")
const DUST_TEXTURE := preload("res://assets/art/vfx/vfx_door_dust.png")
## vfx_door_dust.json: 90, 120, 130 ms; centred 80,24 of a 160x48 frame.
const DUST_MS: Array[int] = [90, 120, 130]
const DUST_ANCHOR := Vector2(80, 24)
