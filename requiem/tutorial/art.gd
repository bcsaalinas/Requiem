@tool
extends Node2D
## Original textured sprites; their visual height is independent of collision footprints.
@export var kind: String = "crate"
@export var dimensions: Vector2 = Vector2(48, 48)
@export var tint: Color = Color("82755a")
@export_group("Actor animation")
## Optional skin. Other atlas actors keep the original procedural presentation.
@export var actor_frames: SpriteFrames
@export var actor_rig_enabled := false
@export var actor_frame_scale := 58.0 / 203.0
@export var actor_frame_pivot := Vector2(128, 243)
@export var actor_ground_offset := Vector2(0, 20)
@export var actor_shadow_offset := Vector2(2, 17)
@export var actor_shadow_radius := Vector2(14.28, 8)
@export_group("Actor readability")
@export_range(0.0, 1.0) var actor_value_floor := 0.18
@export_range(0.0, 1.0) var actor_value_range := 0.72
@export_range(0.0, 1.0) var actor_rim_strength := 0.45
const CharacterAnimation := preload("res://player/character_animation.gd")
const RigLayers := preload("res://player/character_rig_layers.gd")
const ThrowableVisual := preload("res://player/throwable_visual.gd")
const Materials := preload("res://tutorial/materials.gd")
const DETAILS := preload("res://tutorial/assets/art/details_atlas.png")
const DETAIL_REGIONS := {
 "flashlight":Rect2(.025,.08,.205,.35), "battery":Rect2(.325,.09,.10,.34),
 "phone":Rect2(.545,.09,.175,.37), "rocks":Rect2(.788,.115,.177,.315),
 "window":Rect2(.075,.50,.10,.445), "broken":Rect2(.326,.50,.10,.445),
 "marker":Rect2(.55,.50,.18,.455), "candle":Rect2(.787,.54,.19,.37),
}
const SPRITES := preload("res://tutorial/assets/art/props_atlas.png")
const CELLS := {
 "bed": Rect2(95,0,190,317), "desk": Rect2(366,20,250,283),
 "shelf": Rect2(694,0,205,316), "chair": Rect2(1005,46,207,264),
 "tree": Rect2(0,322,320,318), "spruce": Rect2(340,322,265,318),
 "altar": Rect2(666,370,282,269), "crate": Rect2(994,416,260,209),
 "door": Rect2(63,670,242,258), "lantern": Rect2(446,669,91,264),
 "rug": Rect2(694,641,206,306), "coats": Rect2(1005,674,234,254),
 "actor": Rect2(94,950,186,237), "friend": Rect2(375,975,215,240),
 "fallen": Rect2(638,1020,318,181), "entity": Rect2(996,946,252,322),
}
var focused := false
var threat_pressure := 0.0
var focal_sprite: Sprite2D
var rim_sprite: Sprite2D
var listening := false
var fallen := false
var broken := false
var extinguished := false
var clock := 0.0
## Painted body pose; contact shadows and the physical player stay fixed.
var actor_motion_offset := Vector2.ZERO
var actor_is_moving := false
var actor_animation: StringName = &"idle_s"
var actor_frame := 0
var actor_facing: StringName = &"s"
var actor_cycle_phase := 0.0
var _actor_player := CharacterAnimation.new()
var _rig_layers: RefCounted
var actor_equipped := false
var _rig_pose: Dictionary = {}
var _rig_rotation := 0.0
var _wrist_angle := PI / 2.0
var _lower_sprite: Sprite2D
var _lower_rim: Sprite2D
var _right_leg_sprite: Sprite2D
var _right_leg_rim: Sprite2D
var _lower_pose: Dictionary = {}
var _torch_sprite: Sprite2D
var _torch_rim: Sprite2D
var _breath_track: StringName = &"idle"
var _breath_phase := 0.0
var _throw_track: StringName = &"idle"
var _throw_phase := 0.0
var _throw_kind := -1
var _throw_prop: Node2D
var _prayer_track: StringName = &"idle"
var _prayer_phase := 0.0
var _prayer_lower_track: StringName = &"idle"
var _prayer_lower_phase := 0.0

func _ready() -> void:
	reset_actor_gait()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 0 if kind == "rug" else 1
	light_mask = 1 if kind in ["actor","friend","entity","wall","rug","glass"] else 2
	material = Materials.scenery_material()
	if kind == "tree":
		material.set_shader_parameter("gain",.70)
		material.set_shader_parameter("saturation",.12)
	if kind == "rug":
		material.set_shader_parameter("saturation",.08)
		material.set_shader_parameter("contrast",.38)
		material.set_shader_parameter("gain",.56)
		material.set_shader_parameter("detail_radius",3.0)
	if kind in ["actor","friend","entity","flashlight","battery","phone","rocks","marker","window","door"]:
		focal_sprite = Sprite2D.new()
		focal_sprite.name = "ReadabilitySprite"
		focal_sprite.light_mask = light_mask
		focal_sprite.centered = false
		focal_sprite.region_enabled = true
		var focal_material := ShaderMaterial.new()
		focal_material.shader = preload("res://tutorial/focal_sprite.gdshader")
		focal_sprite.material = focal_material
		# Rendering helpers must not become duplicate authored nodes when the world is saved.
		add_child(focal_sprite,false,Node.INTERNAL_MODE_BACK)
		rim_sprite = Sprite2D.new()
		rim_sprite.name = "ReadabilityContour"
		rim_sprite.centered = false
		rim_sprite.region_enabled = true
		var rim_material := ShaderMaterial.new()
		rim_material.shader = preload("res://tutorial/readability_rim.gdshader")
		rim_sprite.material = rim_material
		add_child(rim_sprite,false,Node.INTERNAL_MODE_BACK)
		if kind == "actor" and actor_rig_enabled:
			_lower_sprite = _new_rig_layer("LeftLeg",false)
			_lower_rim = _new_rig_layer("LeftLegContour",true)
			_right_leg_sprite = _new_rig_layer("RightLeg",false)
			_right_leg_rim = _new_rig_layer("RightLegContour",true)
			# Keep the complete actor at one world depth; only sibling order
			# determines which articulated layer covers the other.
			move_child(_lower_sprite,0)
			move_child(_lower_rim,1)
			move_child(_right_leg_sprite,2)
			move_child(_right_leg_rim,3)
			_torch_sprite = _new_rig_layer("Equipment",false)
			_torch_rim = _new_rig_layer("EquipmentContour",true)
			_throw_prop = ThrowableVisual.new()
			_throw_prop.name = "HeldThrowable"
			_throw_prop.visible = false
			add_child(_throw_prop, false, Node.INTERNAL_MODE_BACK)

func _process(delta: float) -> void:
	clock += delta
	if kind in ["actor", "friend", "entity", "candle", "phone", "altar"] or listening:
		queue_redraw()

func _draw() -> void:
	var r := Rect2(-dimensions / 2, dimensions)
	if DETAIL_REGIONS.has(kind):
		_draw_detail()
		return
	if CELLS.has(kind):
		_draw_sprite()
		return
	match kind:
		"wall":
			Materials.paint(self,r,2,160,Color(.46,.47,.43))
			var face := Rect2(r.position.x,r.end.y-minf(30,r.size.y),r.size.x,minf(30,r.size.y))
			Materials.paint(self,face,0,220,Color(.34,.31,.28))
			draw_line(Vector2(r.position.x,face.position.y),Vector2(r.end.x,face.position.y),Color("736857"),2)
			draw_line(Vector2(r.position.x,r.end.y-2),Vector2(r.end.x,r.end.y-2),Color("151612"),4)
		"glass":
			for i in range(11):
				var p := Vector2(sin(i*7.0)*28, cos(i*5.0)*16)
				draw_line(p, p+Vector2(5,-4), Color("9aaca6"), 2)

func paint_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(32): points.append(center + Vector2(cos(i*TAU/32), sin(i*TAU/32))*radius)
	draw_colored_polygon(points, color)

func _draw_sprite() -> void:
	if kind == "actor" and actor_frames != null:
		_draw_animated_actor()
		return
	var id := "fallen" if kind == "friend" and fallen else kind
	if kind == "tree" and int(position.x) % 3 == 0: id = "spruce"
	var region: Rect2 = CELLS[id]
	region = region.intersection(Rect2(Vector2.ZERO,SPRITES.get_size()))
	var size := dimensions
	var bottom := dimensions.y * .5
	match kind:
		"actor": size = Vector2(42,58); bottom = 20
		"friend":
			size = Vector2(48,58) if not fallen else Vector2(73,42)
			bottom = 22
		"entity": size = Vector2(45,92); bottom = 24
		"tree": size = Vector2(155,185); bottom = 30
		"bed": size = Vector2(dimensions.x,dimensions.y)
		"desk": size = Vector2(dimensions.x, maxf(90,dimensions.x*.72))
		"shelf": size = Vector2(dimensions.x,maxf(135,dimensions.y))
		"coats": size = Vector2(116,95); bottom = 12
		"chair": size = Vector2(75,96); bottom = 32
		"crate": size = Vector2(dimensions.x,dimensions.y*1.2)
		"altar": size = Vector2(148,128); bottom = 38
		"door":
			size = Vector2(maxf(48,dimensions.x),98)
			bottom = dimensions.y*.5
		"lantern": size = Vector2(19,55); bottom = 12
	# Contact shadows ground props without changing their physical footprints.
	if kind != "rug":
		paint_ellipse(Vector2(2,bottom-3),Vector2(size.x*.34,8),Color(0,0,0,.08))
		paint_ellipse(Vector2(2,bottom-3),Vector2(size.x*.27,5),Color(0,0,0,.14))
	var offset := Vector2(-size.x*.5,bottom-size.y)
	if kind == "actor":
		offset += actor_motion_offset
		if not actor_is_moving: offset.y += sin(clock*2.0)*.6
	var albedo := Color(1.15,1.12,1.07) if kind != "entity" else Color(.42,.45,.46,.75)
	var painted_offset := offset if kind == "actor" else offset.floor()
	paint_sprite(SPRITES,Rect2(painted_offset,size),region,albedo)
	if listening:
		# A cold line below the occupied door, interrupted by two shifting feet.
		var y := bottom + 3
		draw_line(Vector2(-30,y),Vector2(30,y),Color("a6b4ad"),3)
		var shift := sin(clock*.65)*8
		for x in [-12.0,10.0]:
			draw_rect(Rect2(x+shift-4,y-2,8,6),Color("141712"))

func reset_actor_gait() -> void:
	_actor_player.reset(actor_frames)
	_sync_actor_frame()

func set_actor_gait(cycle_phase: float, moving: bool, direction := Vector2.ZERO,
		sprint := false, delta := 0.0) -> void:
	_actor_player.advance(actor_frames, delta, moving, direction, cycle_phase, sprint)
	_sync_actor_frame()

func _sync_actor_frame() -> void:
	actor_animation = _actor_player.animation
	actor_frame = _actor_player.frame
	actor_facing = _actor_player.facing
	actor_cycle_phase = _actor_player.phase
	queue_redraw()

func _draw_animated_actor() -> void:
	if actor_rig_enabled:
		_draw_rig_actor()
		return
	if not actor_frames.has_animation(actor_animation): return
	if actor_frame >= actor_frames.get_frame_count(actor_animation): return
	var texture := actor_frames.get_frame_texture(actor_animation, actor_frame)
	if texture == null: return
	var atlas := texture as AtlasTexture
	var region := atlas.region if atlas != null else Rect2(Vector2.ZERO, texture.get_size())
	# Keep the existing contact point, collision footprint and shadow stationary.
	paint_ellipse(actor_shadow_offset,actor_shadow_radius,Color(0,0,0,.08))
	paint_ellipse(actor_shadow_offset,actor_shadow_radius*Vector2(.794,.625),Color(0,0,0,.14))
	var offset := actor_ground_offset - actor_frame_pivot * actor_frame_scale
	var target := Rect2(offset,region.size * actor_frame_scale)
	# The frames already contain weight transfer: never add the legacy whole-body bob.
	paint_sprite(atlas.atlas if atlas != null else texture,target,region)


func set_actor_pose(body_angle: float, wrist_angle: float, relative_direction: String, equipped: bool, arm_step := 99) -> void:
	if _rig_layers == null: _rig_layers = RigLayers.new()
	actor_equipped = equipped
	_rig_rotation = body_angle - PI / 2.0
	_wrist_angle = wrist_angle
	var aim_step := clampi(roundi(angle_difference(body_angle,wrist_angle)/(PI/8.0)),-2,2) if arm_step == 99 else clampi(arm_step,-2,2)
	var state := String(actor_animation).get_slice("_",0)
	_rig_pose = _rig_layers.get_pose(state,actor_frame,relative_direction,aim_step,equipped)
	if _breath_track != &"idle":
		_rig_pose = _rig_layers.get_breath_pose(String(_breath_track), _breath_phase, aim_step, equipped)
	if _throw_track != &"idle":
		_rig_pose = _rig_layers.get_throw_pose(String(_throw_track), _throw_phase, aim_step, equipped)
	if _prayer_track != &"idle":
		_rig_pose = _rig_layers.get_prayer_pose(String(_prayer_track), _prayer_phase, aim_step, equipped)
	queue_redraw()


func set_breath_pose(track: StringName, phase: float) -> void:
	_breath_track = track
	_breath_phase = clampf(phase, 0.0, 1.0)
	# PlayerAim applies this with the current body/arm heading later this tick.
	queue_redraw()


func set_throw_pose(track: StringName, phase: float, kind_id := -1) -> void:
	_throw_track = track
	_throw_phase = clampf(phase, 0.0, 1.0)
	_throw_kind = kind_id
	queue_redraw()


func get_actor_throw_hand_position() -> Vector2:
	if not _rig_pose.has("throw_hand"): return actor_ground_offset
	return actor_ground_offset + ((_rig_pose.throw_hand - actor_frame_pivot) * actor_frame_scale).rotated(_rig_rotation)


func set_prayer_pose(track: StringName, phase: float) -> void:
	_prayer_track = track
	_prayer_phase = clampf(phase, 0.0, 1.0)
	queue_redraw()


func set_prayer_lower_pose(track: StringName, phase: float) -> void:
	_prayer_lower_track = track
	_prayer_lower_phase = clampf(phase, 0.0, 1.0)
	queue_redraw()


func get_actor_hand_position() -> Vector2:
	if _rig_pose.is_empty(): return Vector2.ZERO
	return actor_ground_offset + ((_rig_pose.right_hand - actor_frame_pivot) * actor_frame_scale).rotated(_rig_rotation)


func get_actor_muzzle_position() -> Vector2:
	return get_actor_grip_transform() * RigLayers.ANCHORS.GRIP_MUZZLE


## Maps actual grip texture pixels into Appearance coordinates. Both rendering
## and beam placement use this transform, including its registered wrist pivot.
func get_actor_grip_transform() -> Transform2D:
	var pose := Transform2D(_wrist_angle - PI / 2.0, Vector2.ZERO).scaled(Vector2.ONE * actor_frame_scale)
	pose.origin = get_actor_hand_position() - pose.basis_xform(RigLayers.ANCHORS.GRIP_WRIST)
	return pose


func set_actor_lower_pose(pose: Dictionary) -> void:
	_lower_pose = pose
	queue_redraw()


func get_actor_lower_pose() -> Dictionary:
	if _prayer_lower_track != &"idle" and _rig_layers != null:
		var prayer: Dictionary = _rig_layers.get_prayer_lower_pose(String(_prayer_lower_track), _prayer_lower_phase)
		var weight: float = prayer.metadata.kneel_weight
		# At standing endpoints the original support contacts remain authoritative.
		if weight > 0.0:
			var rotations := {}
			var offsets := {}
			for side in ["left", "right"]:
				var from_heading: float = _lower_pose.get("rotations", {}).get(side, _lower_pose.get("heading", _rig_rotation + PI / 2.0))
				rotations[side] = lerp_angle(from_heading, _rig_rotation + PI / 2.0, weight)
				offsets[side] = Vector2(_lower_pose.get("offsets", {}).get(side, Vector2.ZERO)) * (1.0 - weight)
			return {"pose": prayer, "heading": _rig_rotation + PI / 2.0,
				"offsets": offsets, "rotations": rotations, "kneeling": true}
	return _lower_pose


func get_actor_leg_transform(side: String) -> Transform2D:
	var lower := get_actor_lower_pose()
	var heading: float = lower.get("heading", _rig_rotation + PI / 2.0)
	var offsets: Dictionary = lower.get("offsets", {})
	var rotations: Dictionary = lower.get("rotations", {})
	heading = float(rotations.get(side, heading))
	var pose := Transform2D(heading - PI / 2.0, Vector2.ZERO).scaled(Vector2.ONE * actor_frame_scale)
	pose.origin = actor_ground_offset + Vector2(offsets.get(side, Vector2.ZERO)) - pose.basis_xform(actor_frame_pivot)
	return pose


func get_actor_boot_position(side: String) -> Vector2:
	var lower := get_actor_lower_pose()
	if lower.is_empty(): return actor_ground_offset
	return get_actor_leg_transform(side) * Vector2(lower.pose.metadata[side].boot)


func _new_rig_layer(layer_name: String, contour: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = layer_name
	sprite.centered = false
	sprite.region_enabled = true
	sprite.light_mask = light_mask
	var style := ShaderMaterial.new()
	style.shader = preload("res://tutorial/readability_rim.gdshader") if contour else preload("res://tutorial/focal_sprite.gdshader")
	sprite.material = style
	add_child(sprite,false,Node.INTERNAL_MODE_BACK)
	return sprite


func _draw_rig_actor() -> void:
	if not is_instance_valid(_lower_sprite): return
	if _rig_pose.is_empty(): set_actor_pose(PI/2.0,PI/2.0,"s",false)
	paint_ellipse(actor_shadow_offset,actor_shadow_radius,Color(0,0,0,.08))
	paint_ellipse(actor_shadow_offset,actor_shadow_radius*Vector2(.794,.625),Color(0,0,0,.14))
	var offset := actor_ground_offset + (-actor_frame_pivot*actor_frame_scale).rotated(_rig_rotation)
	var lower: Dictionary = get_actor_lower_pose().get("pose", _rig_layers.get_lower_pose("idle", 0, "s"))
	for side in ["left", "right"]:
		var transform_at_leg := get_actor_leg_transform(side)
		var sprite := _lower_sprite if side == "left" else _right_leg_sprite
		var rim := _lower_rim if side == "left" else _right_leg_rim
		_pose_layer(sprite, rim, lower[side + "_texture"], lower.region, transform_at_leg.origin, transform_at_leg.get_rotation())
	_pose_layer(focal_sprite,rim_sprite,_rig_pose.upper_texture,_rig_pose.upper_region,offset,_rig_rotation)
	_torch_sprite.visible = actor_equipped
	_torch_rim.visible = actor_equipped
	if actor_equipped:
		var transform_at_hand := get_actor_grip_transform()
		var texture: Texture2D = _rig_pose.flashlight_texture
		_pose_layer(_torch_sprite,_torch_rim,texture,Rect2(Vector2.ZERO,texture.get_size()),transform_at_hand.origin,transform_at_hand.get_rotation(),texture.get_size()*actor_frame_scale)
	_throw_prop.visible = _throw_track == &"windup" and _throw_kind >= 0
	if _throw_prop.visible:
		_throw_prop.kind = _throw_kind
		_throw_prop.color = Color(1.0, .85, .35) if _throw_kind == 1 else Color(.85, .85, .8)
		_throw_prop.position = get_actor_throw_hand_position()
		_throw_prop.rotation = _rig_rotation


func _pose_layer(sprite: Sprite2D, contour: Sprite2D, texture: Texture2D, region: Rect2,
		at: Vector2, angle: float, size := Vector2.ZERO) -> void:
	if size == Vector2.ZERO: size = region.size * actor_frame_scale
	var ratio := region.size/size
	sprite.texture = texture
	sprite.region_rect = region.grow_individual(ratio.x*2,ratio.y*2,ratio.x*2,ratio.y*2)
	sprite.position = at - Vector2(2,2).rotated(angle)
	sprite.rotation = angle
	sprite.scale = size/region.size
	var style := sprite.material as ShaderMaterial
	style.set_shader_parameter("atlas_texture",texture)
	style.set_shader_parameter("atlas_bounds",Vector4(region.position.x/texture.get_width(),region.position.y/texture.get_height(),region.end.x/texture.get_width(),region.end.y/texture.get_height()))
	style.set_shader_parameter("edge_step",ratio/texture.get_size())
	style.set_shader_parameter("accent",Color("bedbd5"))
	style.set_shader_parameter("value_floor",actor_value_floor)
	style.set_shader_parameter("value_range",actor_value_range)
	style.set_shader_parameter("rim_strength",actor_rim_strength)
	style.set_shader_parameter("color_mix",.18)
	contour.texture = texture
	contour.region_rect = sprite.region_rect
	contour.transform = sprite.transform
	for parameter in ["atlas_texture","atlas_bounds","edge_step","accent","rim_strength"]:
		contour.material.set_shader_parameter(parameter,style.get_shader_parameter(parameter))

func _draw_detail() -> void:
	var key := "broken" if kind == "window" and broken else kind
	var region: Rect2 = DETAIL_REGIONS[key]
	region.position *= DETAILS.get_size()
	region.size *= DETAILS.get_size()
	var size := Vector2(32,32)
	match kind:
		"flashlight": size=Vector2(36,30)
		"battery": size=Vector2(14,25)
		"phone": size=Vector2(24,28)
		"rocks": size=Vector2(41,32)
		"window": size=Vector2(42,91)
		"marker": size=Vector2(40,55)
		"candle": size=Vector2(25,27)
	var bottom := 12.0
	if kind == "window": bottom=dimensions.y*.5
	if kind == "candle" and extinguished:
		region.position.y += region.size.y*.27
		region.size.y *= .73
		size.y *= .73
	paint_sprite(DETAILS,Rect2(Vector2(-size.x*.5,bottom-size.y),size),region)

func set_focused(value: bool) -> void:
	if focused == value: return
	focused = value
	queue_redraw()

func set_threat_pressure(value: float) -> void:
	if is_equal_approx(value,threat_pressure): return
	threat_pressure = value
	queue_redraw()

func paint_sprite(atlas: Texture2D, target: Rect2, source: Rect2, albedo := Color.WHITE) -> void:
	var emphasized := is_instance_valid(focal_sprite) and (kind != "door" or focused) and (kind != "entity" or threat_pressure>.01)
	if is_instance_valid(focal_sprite):
		focal_sprite.visible=emphasized
		rim_sprite.visible=emphasized
	if not emphasized:
		draw_texture_rect_region(atlas,target,source,albedo)
		return
	# Pad the draw quad for a one-pixel rim and a dark separating edge.
	var ratio := source.size/target.size
	var padded := source.grow_individual(ratio.x*2,ratio.y*2,ratio.x*2,ratio.y*2)
	focal_sprite.texture=atlas
	focal_sprite.region_rect=padded
	focal_sprite.position=target.position-Vector2(2,2)
	focal_sprite.scale=target.size/source.size
	var style := focal_sprite.material as ShaderMaterial
	style.set_shader_parameter("atlas_texture",atlas)
	style.set_shader_parameter("atlas_bounds",Vector4(source.position.x/atlas.get_width(),source.position.y/atlas.get_height(),source.end.x/atlas.get_width(),source.end.y/atlas.get_height()))
	style.set_shader_parameter("edge_step",ratio/atlas.get_size())
	var accent := Color("e1b967")
	var floor_value := .17
	var value_range := .68
	var rim := .28 if not focused else .65
	if kind == "actor":
		accent=Color("bedbd5"); floor_value=actor_value_floor
		value_range=actor_value_range; rim=actor_rim_strength
	elif kind == "friend":
		accent=Color("baaea0"); floor_value=.12; value_range=.54; rim=.30
	elif kind == "marker":
		floor_value=.15; rim=.42
	elif kind in ["window","door"]:
		floor_value=.10 if not focused else .18; rim=.20 if not focused else .70
	elif kind == "entity":
		accent=Color("b99a96"); floor_value=.12+threat_pressure*.20
		value_range=.25; rim=threat_pressure*.62
	style.set_shader_parameter("accent",accent)
	style.set_shader_parameter("value_floor",floor_value)
	style.set_shader_parameter("value_range",value_range)
	style.set_shader_parameter("rim_strength",rim)
	style.set_shader_parameter("color_mix",.55 if kind in ["marker","battery","flashlight","rocks","phone"] else .18)

	# Reuse the same atlas crop for a subtle contour, never an unlit sprite body.
	rim_sprite.texture = focal_sprite.texture
	rim_sprite.region_rect = focal_sprite.region_rect
	rim_sprite.position = focal_sprite.position
	rim_sprite.scale = focal_sprite.scale
	for parameter in ["atlas_texture","atlas_bounds","edge_step","accent","rim_strength"]:
		rim_sprite.material.set_shader_parameter(parameter,style.get_shader_parameter(parameter))
