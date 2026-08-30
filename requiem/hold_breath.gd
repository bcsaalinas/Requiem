extends Node

# HoldBreath (mecanica "Hold Breath" de la spec de Requiem)
#
# Se pone como hijo del Player, junto con FootstepNoise. Usa la
# accion de input "hold_breath" (tecla recomendada: Espacio).
# Tambien muestra una barra de pulmon en pantalla (como la del
# altar), visible solo mientras se mantiene la respiracion.

@export_group("Pulmon")
@export var drain_rate_percent: float = 20.0
@export var refill_rate_percent: float = 10.0

@export_group("Ruido al soltar (px)")
@export var quiet_exhale_radius: float = 60.0
@export var gasp_radius: float = 300.0
@export var forced_gasp_radius: float = 420.0
@export var forced_lock_duration: float = 2.0

@export_group("Audio")
@export var hold_clips: Array[AudioStream] = []
@export var exhale_clips: Array[AudioStream] = []
@export var gasp_clips: Array[AudioStream] = []
@export var forced_gasp_clips: Array[AudioStream] = []
@export var volume_db: float = -4.0

var lung_percent: float = 100.0
var is_holding: bool = false
var is_locked: bool = false
var _lock_timer: float = 0.0
var _audio_player: AudioStreamPlayer2D

@onready var player: Node2D = get_parent()

# --- Agregado: barra visual de pulmon ---
var _bar_layer: CanvasLayer
var _bar: ProgressBar


func _ready() -> void:
	_audio_player = AudioStreamPlayer2D.new()
	add_child(_audio_player)

	_bar_layer = CanvasLayer.new()
	add_child(_bar_layer)

	_bar = ProgressBar.new()
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.value = 100
	_bar.size = Vector2(220, 24)
	_bar.position = Vector2(20, 20)
	_bar.show_percentage = false
	_bar.visible = false
	_bar_layer.add_child(_bar)


func _physics_process(delta: float) -> void:
	if is_locked:
		_lock_timer -= delta
		if _lock_timer <= 0.0:
			is_locked = false
		_update_bar()
		return

	var wants_to_hold := Input.is_action_pressed("hold_breath")

	if wants_to_hold and lung_percent > 0.0:
		_continue_holding(delta)
	else:
		if is_holding:
			_release_breath()
		_refill_lung(delta)

	_update_bar()


func _update_bar() -> void:
	_bar.value = lung_percent
	_bar.visible = is_holding or is_locked


func _continue_holding(delta: float) -> void:
	if not is_holding:
		is_holding = true
		_play_random_clip(hold_clips)
	elif not _audio_player.playing:
		_play_random_clip(hold_clips)

	lung_percent -= drain_rate_percent * delta

	if lung_percent <= 0.0:
		lung_percent = 0.0
		_forced_gasp()


func _refill_lung(delta: float) -> void:
	lung_percent = min(100.0, lung_percent + refill_rate_percent * delta)


func _release_breath() -> void:
	is_holding = false
	_audio_player.stop()

	if lung_percent > 20.0:
		_emit_breath(quiet_exhale_radius, exhale_clips)
	else:
		_emit_breath(gasp_radius, gasp_clips)


func _forced_gasp() -> void:
	is_holding = false
	is_locked = true
	_lock_timer = forced_lock_duration
	_audio_player.stop()
	_emit_breath(forced_gasp_radius, forced_gasp_clips)


func _emit_breath(radius: float, clips: Array[AudioStream]) -> void:
	NoiseManager.emit_noise(player.global_position, radius, NoiseManager.SourceType.BREATH)
	_play_random_clip(clips)


func _play_random_clip(clips: Array[AudioStream]) -> void:
	if clips.is_empty():
		return

	_audio_player.global_position = player.global_position
	_audio_player.volume_db = volume_db
	_audio_player.stream = clips[randi() % clips.size()]
	_audio_player.play()


func get_lung_percent() -> float:
	return lung_percent
