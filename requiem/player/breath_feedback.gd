extends Node
## Presentation follows accepted mechanic events. It never owns air, noise or locks.

const BreathVfx := preload("res://player/breath_vfx.gd")
const INHALE_SECONDS := 0.20
const RELEASE_SECONDS := 0.46
const LATE_RELEASE_SECONDS := 0.55
const GASP_SECONDS := 0.28

@export var enabled := true
@export_range(0.0, 1.0) var effects_strength := 1.0

@onready var player: CharacterBody2D = get_parent()
@onready var breath: Node = player.get_node("HoldBreath")
@onready var appearance: Node2D = player.get_node("Appearance")

var phase: StringName = &"idle"
var phase_name := "Relaxed"
var pose_phase := 0.0
var hold_focus := 0.0
var strain := 0.0
var lung_pressure := 0.0
var exertion_pressure := 0.0
var pulse := 0.0
var cue: StringName = &""
var cue_age := 10.0
var recovery_fraction := 0.0
var _elapsed := 0.0
var _pulse_clock := 0.0
var _forced_duration := 0.0
var _was_locked := false
var _previous_position := Vector2.ZERO
var _vfx: Control
var _layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Updated after displacement/gait, before aim resolves the animated hand socket.
	process_physics_priority = 15
	breath.hold_started.connect(_on_hold_started)
	breath.breath_released.connect(_on_released)
	breath.forced_gasp_started.connect(_on_forced_gasp)
	breath.hold_cancelled.connect(_on_cancelled)
	_layer = CanvasLayer.new()
	_layer.name = "BreathEffects"
	_layer.layer = 15
	add_child(_layer)
	_vfx = BreathVfx.new()
	_vfx.feedback = self
	_layer.add_child(_vfx)
	reset_feedback()


func reset_feedback() -> void:
	phase = &"idle"
	phase_name = "Relaxed"
	pose_phase = 0.0
	hold_focus = 0.0
	strain = 0.0
	lung_pressure = 0.0
	exertion_pressure = 0.0
	pulse = 0.0
	_elapsed = 0.0
	_pulse_clock = 0.0
	_forced_duration = 0.0
	_was_locked = false
	cue = &""
	cue_age = 10.0
	recovery_fraction = 0.0
	_previous_position = player.global_position
	appearance.set_breath_pose(&"idle", 0.0)


func _physics_process(delta: float) -> void:
	var teleported := player.global_position.distance_to(_previous_position) > Units.to_px(3.0)
	_previous_position = player.global_position
	if not enabled or GameState.is_dead or not player.can_process() or teleported:
		reset_feedback()
		return
	_elapsed += delta
	cue_age += delta
	# These warnings are normalized to real resources, never a parallel hold timer.
	lung_pressure = 1.0 - smoothstep(5.0, 45.0, breath.lung_percent) if breath.is_holding else 0.0
	exertion_pressure = smoothstep(72.0, 100.0, breath.exertion_percent)
	var target_strain := maxf(lung_pressure, exertion_pressure)
	strain = lerpf(strain, target_strain, 1.0 - exp(-delta * 12.0))
	hold_focus = lerpf(hold_focus, 1.0 if breath.is_holding else 0.0,
		1.0 - exp(-delta * (15.0 if breath.is_holding else 5.5)))
	_pulse_clock = fposmod(_pulse_clock + delta * TAU * lerpf(0.8, 1.55, strain), TAU)
	pulse = (1.0 - cos(_pulse_clock)) * 0.5
	if breath.is_locked:
		# Recovery stays visible even though the mechanic clears exertion on gasp.
		if not _was_locked:
			# Resuming dialogue continues the existing recovery, never a second gasp.
			_forced_duration = maxf(breath.forced_lock_duration, 0.001)
		var remaining: float = breath.get_recovery_remaining()
		var elapsed := maxf(0.0, _forced_duration - remaining)
		recovery_fraction = clampf(elapsed / _forced_duration, 0.0, 1.0)
		phase = &"gasp" if elapsed < GASP_SECONDS else &"recovery"
		pose_phase = elapsed / GASP_SECONDS if phase == &"gasp" else \
			clampf((elapsed - GASP_SECONDS) / maxf(_forced_duration - GASP_SECONDS, 0.001), 0.0, 1.0)
	elif breath.is_holding:
		if phase == &"inhale" and _elapsed < INHALE_SECONDS:
			pose_phase = _elapsed / INHALE_SECONDS
		else:
			phase = &"strain" if lung_pressure > 0.12 or exertion_pressure > 0.12 else &"hold"
			pose_phase = _pulse_clock / TAU if phase == &"strain" else 0.0
	elif phase in [&"release", &"release_loud"]:
		var duration := RELEASE_SECONDS if phase == &"release" else LATE_RELEASE_SECONDS
		pose_phase = clampf(_elapsed / duration, 0.0, 1.0)
		if _elapsed >= duration:
			phase = &"idle"
			pose_phase = 0.0
	else:
		phase = &"idle"
		pose_phase = 0.0
	_was_locked = breath.is_locked
	_update_label()
	appearance.set_breath_pose(phase, pose_phase)


func _update_label() -> void:
	match phase:
		&"inhale": phase_name = "Holding breath"
		&"hold": phase_name = "Holding breath"
		&"strain": phase_name = "Straining"
		&"release": phase_name = "Controlled exhale"
		&"release_loud": phase_name = "Loud exhale"
		&"gasp": phase_name = "Forced gasp"
		&"recovery": phase_name = "Recovering"
		_: phase_name = "Release Space" if breath.needs_release else "Relaxed"


func _on_hold_started() -> void:
	phase = &"inhale"
	_elapsed = 0.0
	_pulse_clock = 0.0
	cue = &"inhale"
	cue_age = 0.0


func _on_released(is_quiet: bool, _lung_at_release: float) -> void:
	phase = &"release" if is_quiet else &"release_loud"
	_elapsed = 0.0
	cue = phase
	cue_age = 0.0


func _on_forced_gasp(_reason: StringName, duration: float) -> void:
	phase = &"gasp"
	_elapsed = 0.0
	_forced_duration = maxf(duration, 0.001)
	_was_locked = true
	cue = &"gasp"
	cue_age = 0.0


func _on_cancelled() -> void:
	# An interruption is not a deliberate exhale and has no reward/ripple.
	reset_feedback()


func get_meter_color(exertion := false) -> Color:
	var normal := Color("ceac78") if exertion else Color("c3c4aa")
	if not enabled or GameState.is_dead or not player.can_process(): return normal
	var pressure := exertion_pressure if exertion else lung_pressure
	var warning := Color("cf9474")
	var amount := pressure * (0.45 + pulse * 0.35)
	if breath.is_locked: amount = maxf(amount, 0.55 * (1.0 - recovery_fraction))
	var color := normal.lerp(warning, amount)
	if not exertion and cue in [&"inhale", &"release"]:
		color = color.lerp(Color("e7e4c8"), maxf(0.0, 1.0 - cue_age / 0.46) * 0.8)
	return color


func get_meter_caption() -> String:
	if not enabled or GameState.is_dead or not player.can_process(): return "BREATH"
	if breath.is_locked: return "RECOVERING"
	if breath.needs_release: return "RELEASE SPACE"
	if breath.is_holding: return "LOW AIR" if lung_pressure > 0.64 else "HOLDING"
	if phase == &"release": return "EXHALE"
	if phase == &"release_loud": return "LOUD EXHALE"
	return "BREATH"
