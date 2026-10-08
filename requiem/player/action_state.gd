extends Node
## Shared action policy. Mechanics retain their own clocks, costs and effects;
## presentation reads this derived priority instead of maintaining another state.

@export var has_flashlight := false

@onready var player: CharacterBody2D = get_parent()
@onready var breath: Node = player.get_node_or_null("HoldBreath")
@onready var thrower: Node = player.get_node_or_null("Throw")
@onready var footsteps: Node = player.get_node_or_null("FootstepNoise")


func _ready() -> void:
	# Observe dialogue disabling the parent. A real tree pause still freezes us.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -20
	GameState.player_died.connect(interrupt_actions)


func _physics_process(_delta: float) -> void:
	if not can_throw() and thrower != null:
		thrower.cancel_windup()
	# A gasp already released the breath; do not cut its recovery sound short.
	if (GameState.is_dead or not player.can_process()) and breath != null:
		breath.cancel_holding()
	if not can_move():
		player.is_sprinting = false


func get_action() -> StringName:
	if GameState.is_dead:
		return &"dead"
	if not _player_is_active():
		return &"disabled"
	if breath != null and breath.is_locked:
		return &"forced_gasp"
	if GameState.is_praying:
		return &"prayer"
	if thrower != null and thrower.is_throwing:
		return &"throw"
	if is_holding_breath():
		return &"hold_breath"
	if player.is_sprinting:
		return &"sprint"
	var threshold_u: float = footsteps.moving_threshold_u if footsteps != null else 0.1
	return &"walk" if player.get_speed_u() > threshold_u else &"idle"


func can_move() -> bool:
	return not GameState.is_dead and _player_is_active() and not GameState.is_praying \
		and (breath == null or not breath.is_locked)


func can_aim() -> bool:
	return can_move() and (thrower == null or not thrower.is_throwing)


## Only shared blockers. Throw owns inventory, windup and cooldown eligibility.
func can_throw() -> bool:
	return can_move()


func can_hold_breath() -> bool:
	# Prayer roots movement but retains the existing breathing/resource behavior.
	return not GameState.is_dead and _player_is_active() \
		and (breath == null or not breath.is_locked)


func is_hold_requested() -> bool:
	return can_hold_breath() and (breath == null or not breath.needs_release) \
		and Input.is_action_pressed("hold_breath")


func is_holding_breath() -> bool:
	return can_hold_breath() and breath != null and breath.is_holding


func _player_is_active() -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and player.can_process()


## Used for an explicit interruption as well as death. Already released objects
## and spent inventory remain owned by Throw; an interruption never refunds them.
func interrupt_actions() -> void:
	if is_instance_valid(player):
		player.is_sprinting = false
	if thrower != null:
		thrower.cancel_windup()
	if breath != null:
		breath.cancel_holding()
