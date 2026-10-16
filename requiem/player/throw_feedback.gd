extends Node
## The mechanic owns windup/release/cooldown. This node only selects its poses.

const FOLLOW_THROUGH_SECONDS := 0.32

@export var enabled := true
@onready var player: CharacterBody2D = get_parent()
@onready var thrower: Node = player.get_node("Throw")
@onready var actions: Node = player.get_node("ActionState")
@onready var appearance: Node2D = player.get_node("Appearance")
@onready var aim: Node = player.get_node("PlayerAim")

var phase: StringName = &"idle"
var pose_phase := 0.0
var _previous_position := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 16
	thrower.throw_started.connect(_on_started)
	thrower.throw_releasing.connect(_on_releasing)
	thrower.object_released.connect(_on_released)
	thrower.throw_cancelled.connect(reset_feedback)
	thrower.presentation_reset.connect(reset_feedback)
	reset_feedback()


func reset_feedback() -> void:
	phase = &"idle"
	pose_phase = 0.0
	_previous_position = player.global_position
	appearance.set_throw_pose(&"idle", 0.0)


func _can_present() -> bool:
	return enabled and actions.get_action() not in [&"dead", &"disabled", &"forced_gasp", &"prayer"]


func _physics_process(_delta: float) -> void:
	var teleported := player.global_position.distance_to(_previous_position) > Units.to_px(3.0)
	_previous_position = player.global_position
	if not _can_present() or teleported:
		reset_feedback()
		return
	if thrower.is_throwing:
		phase = &"windup"
		pose_phase = thrower.get_windup_phase()
	elif phase == &"follow_through":
		var duration: float = minf(FOLLOW_THROUGH_SECONDS, thrower.get_release_cooldown())
		pose_phase = clampf(thrower.get_cooldown_elapsed() / maxf(duration, 0.001), 0.0, 1.0)
		if pose_phase >= 1.0 or duration <= 0.0:
			reset_feedback()
	else:
		reset_feedback()
	appearance.set_throw_pose(phase, pose_phase, thrower.get_pending_kind())


func _on_started() -> void:
	if not _can_present(): return
	phase = &"windup"
	pose_phase = 0.0
	_previous_position = player.global_position
	appearance.set_throw_pose(phase, pose_phase, thrower.get_pending_kind())


func _on_releasing() -> void:
	if not _can_present(): return
	# Release runs before normal pose processing. Sample the actual release
	# frame now, never the previous physics tick's wrist/hand socket.
	phase = &"follow_through"
	pose_phase = 0.0
	appearance.set_throw_pose(phase, pose_phase, thrower.get_pending_kind())
	aim._apply_pose()


func _on_released() -> void:
	if not _can_present(): return
	phase = &"follow_through"
	pose_phase = 0.0
	appearance.set_throw_pose(phase, pose_phase, thrower.get_pending_kind())
