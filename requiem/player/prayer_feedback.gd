extends Node
## The altar owns acceptance, progress and completion. Only the short visual
## exit has its own clock; entry and the sustained pose read the real ritual.

const ENTRY_SECONDS := 0.42
const LOOP_SECONDS := 2.0
const EXIT_SECONDS := 0.38

@export var enabled := true
@onready var player: CharacterBody2D = get_parent()
@onready var actions: Node = player.get_node("ActionState")
@onready var appearance: Node2D = player.get_node("Appearance")

var phase: StringName = &"idle"
var pose_phase := 0.0
var _source: Node = null
var _entry_offset := 0.0
var _facing_target := Vector2.INF
var _previous_position := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 17
	GameState.prayer_started.connect(_on_started)
	GameState.prayer_ended.connect(_on_ended)
	GameState.state_reset.connect(reset_feedback)
	reset_feedback()


func reset_feedback() -> void:
	_source = null
	_entry_offset = 0.0
	_facing_target = Vector2.INF
	_previous_position = player.global_position
	_clear_pose()


func _clear_pose() -> void:
	phase = &"idle"
	pose_phase = 0.0
	appearance.set_prayer_pose(phase, pose_phase)
	appearance.set_prayer_lower_pose(phase, pose_phase)


func _present_pose() -> void:
	# A gasp moves the upper body without making the kneeling legs stand up.
	appearance.set_prayer_lower_pose(phase, pose_phase)
	appearance.set_prayer_pose(&"idle" if actions.get_action() == &"forced_gasp" else phase, pose_phase)


func get_facing_target() -> Vector2:
	return _facing_target if enabled and is_instance_valid(_source) \
		and GameState.is_praying and actions.get_action() == &"prayer" else Vector2.INF


func _physics_process(delta: float) -> void:
	var teleported := player.global_position.distance_to(_previous_position) > Units.to_px(3.0)
	_previous_position = player.global_position
	if teleported:
		if is_instance_valid(_source):
			_source.cancel_prayer(true)
		reset_feedback()
		return
	var action: StringName = actions.get_action()
	if action in [&"dead", &"disabled"]:
		reset_feedback()
		return
	if not enabled:
		_clear_pose()
		return
	if is_instance_valid(GameState.prayer_source) and GameState.is_praying:
		if _source != GameState.prayer_source:
			_on_started(GameState.prayer_source)
		var elapsed: float = _source.get_prayer_elapsed() + _entry_offset
		if elapsed < ENTRY_SECONDS:
			phase = &"entry"
			pose_phase = clampf(elapsed / ENTRY_SECONDS, 0.0, 1.0)
		else:
			phase = &"loop"
			pose_phase = fposmod(elapsed - ENTRY_SECONDS, LOOP_SECONDS) / LOOP_SECONDS
	elif phase == &"exit" and action != &"throw":
		pose_phase = minf(1.0, pose_phase + delta / EXIT_SECONDS)
		if pose_phase >= 1.0:
			reset_feedback()
	else:
		reset_feedback()
	_present_pose()


func _on_started(altar: Node) -> void:
	# An interrupted exit can turn around from the same authored pose.
	_entry_offset = (1.0 - pose_phase) * ENTRY_SECONDS if phase == &"exit" else 0.0
	_source = altar
	_previous_position = player.global_position
	_facing_target = altar.get_prayer_target()
	if not enabled or actions.get_action() in [&"dead", &"disabled"]:
		return
	phase = &"entry"
	pose_phase = _entry_offset / ENTRY_SECONDS
	_present_pose()


func _on_ended(altar: Node, immediate: bool) -> void:
	if altar != _source:
		return
	_source = null
	_facing_target = Vector2.INF
	if immediate or not enabled or phase == &"idle" \
			or actions.get_action() in [&"dead", &"disabled"]:
		reset_feedback()
		return
	pose_phase = 1.0 - pose_phase if phase == &"entry" else 0.0
	phase = &"exit"
	_present_pose()
