extends Node
## A continuous control response selects sparse body/arm poses. The wrist and
## beam share one heading and socket; this controller never advances the gait.

@export_range(30.0, 720.0) var body_turn_speed_degrees := 240.0
@export_range(30.0, 1080.0) var aim_turn_speed_degrees := 540.0
@export_range(15.0, 45.0) var turn_threshold_degrees := 30.0
@export var cursor_deadzone_u := 0.75

const LegPose := preload("res://player/leg_pose.gd")
const RigLayers := preload("res://player/character_rig_layers.gd")

const DIRECTIONS := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const POSE_STEP := PI / 4.0
const WRIST_REACH := deg_to_rad(15.0)

@onready var player: CharacterBody2D = get_parent()
@onready var actions: Node = player.get_node("ActionState")
@onready var appearance: Node2D = player.get_node("Appearance")
@onready var flashlight: PointLight2D = player.get_node("flashlight")
@onready var thrower: Node = player.get_node("Throw")
@onready var throw_feedback: Node = player.get_node_or_null("ThrowFeedback")
@onready var prayer_feedback: Node = player.get_node_or_null("PrayerFeedback")

var body_angle := PI / 2.0
var pose_body_angle := PI / 2.0
var aim_angle := PI / 2.0
var has_valid_target := false
var beam_obstructed := false
var _target := Vector2.INF
var _previous_position := Vector2.ZERO
var _travel_angle := PI / 2.0
var _turning := false
var _arm_angle := PI / 2.0
var _arm_step := 0
var _wrist_correction := 0.0
var _unarmed_action_facing := false
var _legs := LegPose.new()
var _leg_layers := RigLayers.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 20
	reset_pose()


## Optional world target for a controller, replay, or deterministic test.
func set_target(world_position: Vector2) -> void:
	_target = world_position


func clear_target() -> void:
	_target = Vector2.INF


func get_target_position() -> Vector2:
	return _target if _target.is_finite() else player.get_global_mouse_position()


func reset_pose() -> void:
	_previous_position = player.global_position
	var index := DIRECTIONS.find(String(appearance.actor_facing))
	body_angle = float(maxi(index, 0)) * POSE_STEP
	pose_body_angle = body_angle
	aim_angle = body_angle
	_arm_angle = body_angle
	_arm_step = 0
	_wrist_correction = 0.0
	_travel_angle = body_angle
	_turning = false
	_unarmed_action_facing = false
	has_valid_target = false
	clear_target()
	_legs.reset(body_angle)
	_update_lower_pose(0.0)
	_apply_pose()


func _physics_process(delta: float) -> void:
	var displacement := player.global_position - _previous_position
	_previous_position = player.global_position
	if displacement.length() > Units.to_px(3.0):
		reset_pose()
		return
	if appearance.actor_is_moving and not displacement.is_zero_approx():
		_travel_angle = displacement.angle()
	if actions.has_flashlight:
		_unarmed_action_facing = false
	var prayer_target: Vector2 = prayer_feedback.get_facing_target() if prayer_feedback != null else Vector2.INF
	if prayer_target.is_finite() and prayer_target.distance_to(player.global_position) > 1.0:
		_unarmed_action_facing = not actions.has_flashlight
		_update_aim((prayer_target - player.global_position).angle(), prayer_target, delta)
	elif thrower.is_throwing and actions.can_throw():
		# Face the accepted direction, including before flashlight pickup. A new
		# cursor target cannot redirect this throw. Use the existing turn/feet
		# response, with enough turn time to reach even a rearward release.
		var desired: float = thrower.get_committed_angle()
		_unarmed_action_facing = not actions.has_flashlight
		var turn_window: float = maxf(thrower._windup_timer - 0.12, delta)
		var turn_rate := maxf(deg_to_rad(body_turn_speed_degrees), absf(angle_difference(body_angle, desired)) / turn_window)
		_update_aim(desired, player.global_position + Vector2.from_angle(desired) * 2048.0, delta, turn_rate)
	elif not actions.has_flashlight and _unarmed_action_facing:
		# Retain the new heading at rest; gather back toward travel smoothly
		# when walking resumes instead of snapping to an old idle view.
		var following: bool = (throw_feedback != null and throw_feedback.phase == &"follow_through") \
			or (prayer_feedback != null and prayer_feedback.phase == &"exit")
		if not following and appearance.actor_is_moving and actions.can_move():
			_update_aim(_travel_angle, player.global_position + Vector2.from_angle(_travel_angle) * 2048.0, delta)
			if absf(angle_difference(body_angle, _travel_angle)) < deg_to_rad(2.0):
				_unarmed_action_facing = false
	elif not actions.has_flashlight:
		var index := DIRECTIONS.find(String(appearance.actor_facing))
		body_angle = float(maxi(index, 0)) * POSE_STEP
		pose_body_angle = body_angle
		aim_angle = body_angle
		_arm_angle = body_angle
		_arm_step = 0
		_wrist_correction = 0.0
		_turning = false
		has_valid_target = false
	elif actions.can_aim() and (flashlight.follow_mouse or _target.is_finite()):
		var target := get_target_position()
		var to_target := target - player.global_position
		has_valid_target = to_target.length() >= Units.to_px(cursor_deadzone_u)
		if has_valid_target:
			_update_aim(to_target.angle(), target, delta)
	_update_lower_pose(delta)
	_apply_pose()


func _update_aim(desired: float, target: Vector2, delta: float, turn_rate := -1.0) -> void:
	var difference := angle_difference(body_angle, desired)
	if absf(difference) > deg_to_rad(turn_threshold_degrees):
		_turning = true
	if _turning:
		body_angle = rotate_toward(body_angle, desired, (turn_rate if turn_rate >= 0.0 else deg_to_rad(body_turn_speed_degrees)) * delta)
		if absf(angle_difference(body_angle, desired)) < deg_to_rad(2.0):
			_turning = false
	# Hysteresis prevents a cursor on a sector boundary from chattering the feet.
	if absf(angle_difference(pose_body_angle, body_angle)) > POSE_STEP * 0.5 + deg_to_rad(4.0):
		pose_body_angle = roundf(body_angle / POSE_STEP) * POSE_STEP
	# Select the arm from root-to-cursor direction, never the previous hand.
	# Feeding a moving socket back into pose selection can oscillate forever at
	# a sector boundary even when the mouse is completely stationary.
	var desired_arm := pose_body_angle + clampf(angle_difference(pose_body_angle,desired),-PI/4.0,PI/4.0)
	_arm_angle = rotate_toward(_arm_angle,desired_arm,deg_to_rad(aim_turn_speed_degrees)*delta)
	var relative_arm := angle_difference(pose_body_angle,_arm_angle)
	if absf(relative_arm - _arm_step*PI/8.0) > PI/16.0 + deg_to_rad(3.0):
		_arm_step = clampi(roundi(relative_arm/(PI/8.0)),-2,2)
	_update_actor_pose()
	var from_hand := target - get_hand_global_position()
	var hand_target_angle := from_hand.angle() if from_hand.length_squared() > 1.0 else desired
	# Arm and torch share the same turn response, including the chosen arc on
	# a reversal. Only a small parallax correction belongs to the wrist: a near
	# cursor must not fold the hand sideways to aim behind its own grip.
	var correction := clampf(angle_difference(desired, hand_target_angle), -WRIST_REACH, WRIST_REACH)
	_wrist_correction = move_toward(_wrist_correction, correction, deg_to_rad(aim_turn_speed_degrees) * delta)
	var forearm_heading := pose_body_angle + _arm_step * PI / 8.0
	aim_angle = forearm_heading + clampf(angle_difference(forearm_heading,
		_arm_angle + _wrist_correction), -WRIST_REACH, WRIST_REACH)


func _apply_pose() -> void:
	_update_actor_pose()
	var muzzle := get_muzzle_global_position()
	var origin := muzzle
	beam_obstructed = false
	# The hand may extend beyond the collision footprint. Keep the light source
	# on the player's side of a wall instead of leaking through that wall.
	if player.is_inside_tree() and player.get_world_2d() != null:
		var query := PhysicsRayQueryParameters2D.create(player.global_position, muzzle, player.collision_mask, [player.get_rid()])
		var hit := player.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			origin = hit.position + (player.global_position - muzzle).normalized() * 1.5
			beam_obstructed = true
	flashlight.global_position = origin
	flashlight.global_rotation = aim_angle


func _update_actor_pose() -> void:
	var relative := _travel_angle - (pose_body_angle - PI / 2.0)
	var direction: String = DIRECTIONS[posmod(roundi(relative / POSE_STEP), 8)]
	appearance.set_actor_pose(pose_body_angle, aim_angle, direction, actions.has_flashlight, _arm_step)


func get_hand_global_position() -> Vector2:
	return appearance.to_global(appearance.get_actor_hand_position())


func get_muzzle_global_position() -> Vector2:
	return appearance.to_global(appearance.get_actor_muzzle_position())


func get_beam_global_position() -> Vector2:
	return flashlight.global_position


func _update_lower_pose(delta: float) -> void:
	var state := String(appearance.actor_animation).get_slice("_", 0)
	var lower := _legs.advance(delta, state, appearance.actor_frame, appearance.actor_is_moving,
		_travel_angle, pose_body_angle, appearance.global_position, appearance.actor_ground_offset,
		appearance.actor_frame_scale, _leg_layers)
	appearance.set_actor_lower_pose(lower)
