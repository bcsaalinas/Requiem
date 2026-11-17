extends Node
## Drives the player's CharacterSprite from the existing mechanics. It reads ActionState, the breath,
## throw and prayer feedback phases and the flashlight, and changes none of their clocks, costs or noise.
## Priority (ActionState.get_action): death > pray > forced gasp > throw > pick up > hold breath > movement.

const DIRECTIONS := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const TURN_DEGREES := 240.0
const SPRINT_TURN_DEGREES := 540.0
const FOLLOW_AIM_TURN_DEGREES := 720.0
const SHUFFLE_ANGLE := deg_to_rad(45.0)
const HYSTERESIS := 10.0
const SIDE_STEP_ENTER := 60.0
const REVERSE_ENTER := 120.0
const REVERSE_RATE := 0.75
const CALM_BELOW := 40.0
const TIRED_BELOW := 72.0
const AFRAID_PRESSURE := 0.5
const WINDUP_SECONDS := 0.5
const MAX_HEAD_DEGREES := 70.0
const BEAD_SECONDS := 3.0

@onready var player: CharacterBody2D = get_parent()
@onready var appearance: Node2D = player.get_node("Appearance")
@onready var actions: Node = player.get_node("ActionState")
@onready var aim: Node = player.get_node("PlayerAim")
@onready var flashlight: PointLight2D = player.get_node("flashlight")
@onready var thrower: Node = player.get_node("Throw")
@onready var breath: Node = player.get_node("HoldBreath")
@onready var breath_feedback: Node = player.get_node_or_null("BreathFeedback")
@onready var prayer_feedback: Node = player.get_node_or_null("PrayerFeedback")
@onready var footsteps: Node = player.get_node_or_null("FootstepNoise")

var facing := PI / 2.0
var _rig: CharacterSprite
var _carry := "none"
var _mood := "calm"
var _leg_zone := 0
var _shuffling := false
var _was_action: StringName = &"idle"
var _sequence: Array[String] = []
var _sequence_options := {}
var _frozen := false
var _arm_sequence: Array[Dictionary] = []
var _hold_phase := ""
var _last_prayer_phase: StringName = &"idle"
var _prayer_exit_clip := ""
var _bead_pending := false
var _bead_active := false
var _last_quarter := 0
var _beam_offset := 0.0
var _written_facing: StringName = &"s"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 35
	_rig = appearance.rig
	_rig.clip_finished.connect(_on_clip_finished)
	GameState.state_reset.connect(reset)
	GameState.player_died.connect(play_death)
	thrower.throw_releasing.connect(_on_throw_releasing)
	thrower.throw_cancelled.connect(_on_throw_cancelled)
	Preferences.turn_mode_changed.connect(_apply_turn_mode)
	_apply_turn_mode()
	reset()


func reset() -> void:
	_frozen = false
	_sequence.clear()
	_arm_sequence.clear()
	_shuffling = false
	_hold_phase = ""
	_carry = _carry_state()
	_rig.set_facing(facing)


func _apply_turn_mode() -> void:
	_rig.steps_mode = Preferences.turn_mode == Preferences.TURN_STEPS
	_rig.set_facing(facing)


## The pickup visual hook: plays on every interaction or pickup, over the current legs.
func play_pickup() -> void:
	if not _frozen:
		_start_sequence(["pick_up"])


## Plays on the ranger's catch and the parents' second hear; holds its last frame.
func play_caught() -> void:
	_freeze_with("caught")


func play_death() -> void:
	if not _frozen:
		_freeze_with("death")


func _freeze_with(base: String) -> void:
	_frozen = true
	_sequence.clear()
	_sequence.append(base)
	_sequence_options = {}
	_play_upper_arm(base, {})
	_rig.play(&"lower", "girl_stand_lower")
	_rig.stop(&"head")


func _physics_process(delta: float) -> void:
	if _frozen:
		return
	var action: StringName = actions.get_action()
	_update_facing(delta, action)
	_update_carry()
	_update_head()
	var disabled := action == &"disabled"
	if disabled:
		action = &"idle"
	_present(action)
	_follow_sprint_arm(delta, action)
	if disabled:
		_lower_standing()
	_was_action = action
	var lower: String = _rig.clip_name(&"lower")
	var state := "sprint" if lower == "girl_sprint_lower" else ("idle" if lower == "girl_stand_lower" or lower == "" else "walk")
	appearance.actor_animation = StringName("%s_%s" % [state, appearance.actor_facing])
	appearance.actor_frame = _rig.frame_of(&"lower")


## While sprinting the beam follows the swinging arm's flashlight tip at half strength, smoothed.
func _follow_sprint_arm(delta: float, action: StringName) -> void:
	var wanted := 0.0
	if action == &"sprint" and actions.has_flashlight and _rig.has_anchor("flashlight_tip"):
		wanted = clampf(angle_difference(aim.aim_angle, _rig.flashlight_angle_global()) * 0.5, -deg_to_rad(3.0), deg_to_rad(3.0))
	_beam_offset = move_toward(_beam_offset, wanted, deg_to_rad(30.0) * delta)
	if not is_zero_approx(_beam_offset):
		flashlight.global_rotation = aim.aim_angle + _beam_offset


func _carry_state() -> String:
	if not actions.has_flashlight:
		return "none"
	return "on" if flashlight.is_on else "off"


func _update_carry() -> void:
	var now := _carry_state()
	if now == _carry:
		return
	if _carry == "off" and now == "on":
		_arm_sequence = [{"clip": "girl_arm_right_equip", "reverse": false}, {"clip": "girl_arm_right_click", "reverse": false}]
		_start_arm_sequence()
	elif _carry == "on" and now == "off":
		_arm_sequence = [{"clip": "girl_arm_right_click", "reverse": false}, {"clip": "girl_arm_right_equip", "reverse": true}]
		_start_arm_sequence()
	_carry = now


func _start_arm_sequence() -> void:
	if _arm_sequence.is_empty():
		return
	var step: Dictionary = _arm_sequence[0]
	_rig.play(&"arm_right", step["clip"], {"reverse": step["reverse"], "loop": false, "hold_last": true, "restart": true})


func _update_facing(delta: float, action: StringName) -> void:
	if appearance.actor_facing != _written_facing:
		facing = float(maxi(DIRECTIONS.find(String(appearance.actor_facing)), 0)) * PI / 4.0
	var target := facing
	var turn := TURN_DEGREES
	var moving: bool = player.velocity.length() > 5.0
	match action:
		&"throw", &"prayer":
			target = aim.body_angle
			turn = FOLLOW_AIM_TURN_DEGREES
		&"dead", &"forced_gasp":
			pass
		&"sprint":
			if moving:
				target = player.velocity.angle()
			turn = SPRINT_TURN_DEGREES
		_:
			if actions.has_flashlight:
				target = aim.body_angle
				turn = FOLLOW_AIM_TURN_DEGREES
			elif moving:
				target = player.velocity.angle()
	var difference := absf(angle_difference(facing, target))
	if not moving and action in [&"idle", &"walk"]:
		if difference > SHUFFLE_ANGLE:
			_shuffling = true
		elif difference < deg_to_rad(2.0):
			_shuffling = false
	else:
		_shuffling = false
	facing = rotate_toward(facing, target, deg_to_rad(turn) * delta)
	_rig.set_facing(facing)
	_written_facing = StringName(DIRECTIONS[posmod(roundi(facing / (PI / 4.0)), 8)])
	appearance.actor_facing = _written_facing


func _update_head() -> void:
	var look: float = aim.aim_angle if actions.has_flashlight else facing
	_rig.set_head_turn(clampf(rad_to_deg(angle_difference(facing, look)), -MAX_HEAD_DEGREES, MAX_HEAD_DEGREES))


func _present(action: StringName) -> void:
	var praying: bool = prayer_feedback != null and prayer_feedback.phase != &"idle"
	if praying and action == &"forced_gasp":
		_sequence.clear()
		_play_upper_arm("breath_forced_gasp", {})
		_rig.play(&"lower", "girl_pray_loop_lower")
		_rig.stop(&"head")
		return
	if praying:
		_present_prayer(action)
		return
	_last_prayer_phase = &"idle"
	_prayer_exit_clip = ""
	if action == &"forced_gasp":
		_sequence.clear()
		_play_upper_arm("breath_forced_gasp", {})
		_lower_standing()
		_hold_phase = ""
		return
	if action == &"throw":
		_sequence.clear()
		var windup_rate: float = float(CharacterClips.get_clip("girl_throw_windup_upper").get("loop_ms", 500.0)) / (WINDUP_SECONDS * 1000.0)
		_play_upper_arm("throw_windup", {"loop": false, "hold_last": true, "rate": windup_rate})
		_present_legs(action)
		return
	if not _sequence.is_empty():
		_play_upper_arm(_sequence[0], _sequence_options)
		_present_legs(action)
		return
	if action == &"hold_breath":
		_present_hold()
		_present_legs(action)
		return
	if _hold_phase != "":
		_hold_phase = ""
		_start_sequence(["breath_let_go"])
		return
	if action == &"sprint":
		_rig.play(&"upper", "girl_sprint_upper")
		_arm_base("sprint", {})
		_present_legs(action)
		return
	var moving := action == &"walk" or _shuffling
	if moving:
		_rig.play(&"upper", "girl_walk_upper", {"rate": 0.0})
		_arm_base("walk", {"rate": 0.0})
	else:
		_present_idle()
	_present_legs(action)


func _present_idle() -> void:
	var exertion: float = breath.exertion_percent
	var wanted := "calm" if exertion < CALM_BELOW else ("tired" if exertion < TIRED_BELOW else "exhausted")
	var on_idle: bool = String(_rig.clip_name(&"upper")).begins_with("girl_idle_")
	if wanted != _mood and (not on_idle or _rig.frame_of(&"upper") == 0):
		_mood = wanted
	_rig.play(&"upper", "girl_idle_%s_upper" % _mood)
	_arm_base("idle_" + _mood, {})


func _present_hold() -> void:
	var phase := "hold_in" if _hold_phase == "" else _hold_phase
	if _hold_phase == "":
		_hold_phase = "hold_in"
	var strained: bool = breath_feedback != null and breath_feedback.phase == &"strain"
	if _hold_phase == "hold_loop" and strained:
		_hold_phase = "strain"
	elif _hold_phase == "strain" and not strained:
		_hold_phase = "hold_loop"
	phase = _hold_phase
	_play_upper_arm("breath_" + phase, {"loop": phase != "hold_in"})


func _present_prayer(_action: StringName) -> void:
	var phase: StringName = prayer_feedback.phase if prayer_feedback != null else &"loop"
	if phase == &"exit":
		_bead_active = false
		_bead_pending = false
		_last_quarter = 0
		if _prayer_exit_clip == "":
			_prayer_exit_clip = "pray_abort" if _last_prayer_phase == &"entry" else "pray_finish"
		_play_upper_arm(_prayer_exit_clip, {"loop": false})
		_rig.play(&"lower", "girl_%s_lower" % _prayer_exit_clip)
		_rig.stop(&"head")
		return
	_last_prayer_phase = phase
	_prayer_exit_clip = ""
	_rig.stop(&"head")
	if phase == &"entry":
		_play_upper_arm("pray_kneel", {"loop": false, "hold_last": true})
		_rig.play(&"lower", "girl_pray_kneel_lower", {"loop": false, "hold_last": true})
	else:
		var mood := "afraid" if _afraid() else "calm"
		_update_bead(mood)
		if _bead_active:
			_play_upper_arm("pray_bead_step", {"loop": false, "hold_last": true})
		else:
			_play_upper_arm("pray_loop_" + mood, {})
		_rig.play(&"lower", "girl_pray_loop_lower")


## Bead steps follow the altar's progress quarters and only start from pray_loop_calm frame 0.
func _update_bead(mood: String) -> void:
	var source: Node = GameState.prayer_source
	if is_instance_valid(source):
		var quarter := int(source.get_prayer_elapsed() / BEAD_SECONDS)
		if quarter > _last_quarter:
			_bead_pending = true
		_last_quarter = quarter
	if _bead_pending and not _bead_active and mood == "calm" \
			and _rig.clip_name(&"upper") == "girl_pray_loop_calm_upper" and _rig.frame_of(&"upper") == 0:
		_bead_active = true
		_bead_pending = false


func _afraid() -> bool:
	var entity := get_tree().get_first_node_in_group("entity")
	if entity != null and entity.get("current_state") != null and entity.current_state == entity.State.HUNT:
		return true
	var scene := get_tree().current_scene
	return scene != null and float(scene.get("threat_pressure") if scene.get("threat_pressure") != null else 0.0) > AFRAID_PRESSURE


func _present_legs(action: StringName) -> void:
	var speed_u: float = player.get_speed_u()
	var moving_threshold: float = footsteps.moving_threshold_u if footsteps != null else 0.1
	var moving := speed_u > moving_threshold
	if action == &"sprint":
		var sprint := CharacterClips.get_clip("girl_sprint_lower")
		_rig.play(&"lower", "girl_sprint_lower", {"rate": _speed_rate(speed_u, sprint)})
		_rig.play(&"head", "girl_sprint_head", {"rate": 0.0})
		_lock_frames_to_lower([&"upper", &"arm_right", &"head"])
		_rig.set_mirror(false)
		return
	_rig.stop(&"head")
	if not moving:
		if _shuffling:
			_rig.play(&"lower", "girl_walk_lower")
			_lock_frames_to_lower([&"upper", &"arm_right"])
		else:
			_lower_standing()
		return
	var relative := rad_to_deg(absf(angle_difference(player.velocity.angle(), facing)))
	_update_leg_zone(relative)
	var sneaking := action == &"hold_breath"
	var clip_name := "girl_sneak_lower" if sneaking else "girl_walk_lower"
	var side := rad_to_deg(angle_difference(facing, player.velocity.angle())) < 0.0
	match _leg_zone:
		1:
			clip_name = "girl_side_step_lower"
		_:
			pass
	var clip := CharacterClips.get_clip(clip_name)
	var rate := _speed_rate(speed_u, clip)
	var reverse := _leg_zone == 2
	if reverse:
		rate *= REVERSE_RATE
	_rig.play(&"lower", clip_name, {"rate": rate, "reverse": reverse})
	_rig.set_mirror(_leg_zone == 1 and side)
	_lock_frames_to_lower([&"upper", &"arm_right"] if _sequence.is_empty() and action != &"hold_breath" else [])


func _update_leg_zone(relative: float) -> void:
	match _leg_zone:
		0:
			if relative > SIDE_STEP_ENTER + HYSTERESIS:
				_leg_zone = 1
		1:
			if relative < SIDE_STEP_ENTER - HYSTERESIS:
				_leg_zone = 0
			elif relative > REVERSE_ENTER + HYSTERESIS:
				_leg_zone = 2
		2:
			if relative < REVERSE_ENTER - HYSTERESIS:
				_leg_zone = 1


func _speed_rate(speed_u: float, clip: Dictionary) -> float:
	var authored: float = clip.get("speed_u_s", 0.0)
	return clampf(speed_u / authored, 0.25, 2.5) if authored > 0.0 else 1.0


func _lower_standing() -> void:
	_rig.play(&"lower", "girl_stand_lower")
	_rig.set_mirror(false)
	_rig.stop(&"head")


func _lock_frames_to_lower(parts: Array) -> void:
	var frame: int = _rig.frame_of(&"lower")
	for part: StringName in parts:
		if part == &"arm_right" and not _arm_sequence.is_empty():
			continue
		_rig.set_rate(part, 0.0)
		_rig.set_frame(part, frame)


func _play_upper_arm(base: String, options: Dictionary) -> void:
	_rig.play(&"upper", "girl_%s_upper" % base, options)
	_arm_base(base, options)


func _arm_base(base: String, options: Dictionary) -> void:
	if _arm_sequence.is_empty():
		_rig.play(&"arm_right", "girl_%s_arm_right_%s" % [base, _carry], options)


func _start_sequence(bases: Array[String], options := {}) -> void:
	_sequence.assign(bases)
	_sequence_options = options
	_play_upper_arm(_sequence[0], _sequence_options.merged({"loop": false, "restart": true}))


func _on_clip_finished(part: StringName, clip: StringName) -> void:
	if part == &"upper" and clip == &"girl_pray_bead_step_upper":
		_bead_active = false
	if part == &"arm_right" and not _arm_sequence.is_empty():
		_arm_sequence.pop_front()
		_start_arm_sequence()
		return
	if part != &"upper" or _sequence.is_empty() or _frozen:
		return
	if clip != StringName("girl_%s_upper" % _sequence[0]):
		return
	_sequence.pop_front()
	if not _sequence.is_empty():
		_play_upper_arm(_sequence[0], _sequence_options.merged({"loop": false, "restart": true}))


## The release pose is sampled at the projectile frame at the gameplay release moment, then recovers.
func _on_throw_releasing() -> void:
	if _frozen:
		return
	var release := CharacterClips.get_clip("girl_throw_release_upper")
	_sequence.assign(["throw_release", "throw_recover"])
	_sequence_options = {}
	_play_upper_arm("throw_release", {"loop": false, "restart": true, "frame": maxi(release.get("projectile_frame", 0), 0)})


func _on_throw_cancelled() -> void:
	_sequence.clear()
