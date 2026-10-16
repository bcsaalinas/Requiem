extends Node
## Walk/held poses follow FootstepNoise. Sprint follows actual distance with a
## shorter authored stride; gameplay hearing/audio keep their existing clock.

const SprintAnchors := preload("res://player/art/girl_rig_v2/sprint_layer_anchors.gd")

@export var enabled := true
@export_group("Body feedback (u)")
@export_range(0.0, 0.2) var walk_lift_u := 0.065
@export_range(0.0, 0.2) var sway_u := 0.035
@export_range(0.0, 0.2) var lean_u := 0.045
@export_group("Movement tiers")
@export_range(0.0, 1.0) var held_multiplier := 0.40
@export_range(1.0, 3.0) var sprint_multiplier := 1.50
@export_group("Settling")
@export_range(0.01, 0.5) var settle_time := 0.10
@export var teleport_reset_distance_u := 3.0

@onready var player: CharacterBody2D = get_parent()
@onready var appearance: Node2D = player.get_node("Appearance")
@onready var footsteps: Node = player.get_node("FootstepNoise")
@onready var breath: Node = player.get_node_or_null("HoldBreath")
@onready var actions: Node = player.get_node_or_null("ActionState")

var mode := "Idle"
var gait_phase := 0.0
var _previous_position := Vector2.ZERO
var _previous_timer := 0.0
var _foot_side := 1.0
var _pose := Vector2.ZERO
var _sprint_clock := 0.0


func _ready() -> void:
	# Settle even when dialogue disables the player; pause still freezes this node.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 10
	reset_pose()


func set_enabled(value: bool) -> void:
	enabled = value
	reset_pose()


func reset_pose() -> void:
	_previous_position = player.global_position
	_previous_timer = footsteps.footstep_timer
	_foot_side = 1.0
	gait_phase = 0.0
	_pose = Vector2.ZERO
	_sprint_clock = 0.0
	mode = "Idle"
	appearance.reset_actor_gait()
	_apply_pose(false, Vector2.ZERO, 0.0)


func _physics_process(delta: float) -> void:
	var displacement := player.global_position - _previous_position
	_previous_position = player.global_position
	if not enabled or displacement.length() > Units.to_px(teleport_reset_distance_u):
		reset_pose()
		return

	var locked := not player.can_process() or GameState.is_dead or GameState.is_praying
	if breath != null: locked = locked or breath.is_locked
	if actions != null: locked = not actions.can_move()
	var moving := not locked and displacement.length() > Units.to_px(footsteps.moving_threshold_u) * delta
	var target := Vector2.ZERO
	mode = "Idle"
	if moving:
		var held: bool = footsteps._is_holding_breath()
		var sprint: bool = not held and player.get_speed_u() >= footsteps.sprint_threshold_u
		mode = "Held breath" if held else ("Sprint" if sprint else "Walk")
		var strength := held_multiplier if held else (sprint_multiplier if sprint else 1.0)
		var interval: float = footsteps.held_footstep_interval if held else footsteps.footstep_interval
		var timer: float = footsteps.footstep_timer
		if timer < _previous_timer: _foot_side *= -1.0
		_previous_timer = timer
		gait_phase = clampf(timer / interval, 0.0, 1.0)
		# Both ends plant at the existing footfall; the middle transfers weight.
		var arc := sin(gait_phase * PI)
		target.y = -Units.to_px(walk_lift_u) * arc * strength
		target.x = Units.to_px(sway_u) * arc * _foot_side * strength
		target.x += Units.to_px(lean_u) * displacement.normalized().x * strength
	else:
		_previous_timer = footsteps.footstep_timer
		gait_phase = 0.0
		_foot_side = 1.0

	var blend := 1.0 - exp(-delta / settle_time)
	_pose.x = lerpf(_pose.x, target.x, blend)
	# Do not delay the vertical phase: each gameplay footfall must plant the body.
	_pose.y = target.y if moving else lerpf(_pose.y, 0.0, blend)
	if _pose.length_squared() < 0.0001: _pose = Vector2.ZERO
	_apply_pose(moving, displacement, delta)


func _apply_pose(moving: bool, direction: Vector2, delta: float) -> void:
	appearance.actor_motion_offset = _pose
	appearance.actor_is_moving = enabled and moving
	var half_cycle := 0.0 if _foot_side > 0.0 else 1.0
	var cycle := (half_cycle + gait_phase) * 0.5
	if enabled and moving and mode == "Sprint":
		_sprint_clock = fposmod(_sprint_clock + direction.length() / SprintAnchors.STRIDE_DISTANCE, 1.0)
		cycle = _sprint_clock
	appearance.set_actor_gait(cycle, enabled and moving,
		direction, mode == "Sprint", delta)
	appearance.queue_redraw()
