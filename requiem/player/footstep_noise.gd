extends Node

# FootstepNoise
#
# Componente independiente: NO modifica player.gd. Solo lee la velocidad del
# CharacterBody2D padre para saber si esta caminando o corriendo, reproduce el
# audio real, y avisa a NoiseManager para que la entidad pueda reaccionar.
#
# UNIDADES: 1 u = 32 px. Radios y umbrales se exportan en
# unidades; la conversion a px pasa aqui adentro.
# Estos radios NO estan fijados por la spec, se pueden tunear libremente.

const PX_PER_UNIT: float = 32.0

@export_group("Deteccion de movimiento (u/s)")
## Debajo de esto se considera quieto.
@export var moving_threshold_u: float = 0.1
## A partir de esto cuenta como sprint y no como caminata.
@export var sprint_threshold_u: float = 4.0

@export_group("Ruido de pasos (u)")
@export var footstep_interval: float = 0.45
## Radio del paso caminando, en unidades.
@export var walk_noise_radius_u: float = 3.0
## Radio del paso corriendo, en unidades.
@export var sprint_noise_radius_u: float = 6.0

@export_group("Audio")
@export var walk_clips: Array[AudioStream] = []
@export var sprint_clips: Array[AudioStream] = []
@export var volume_db: float = -6.0
@export_range(0.0, 0.3) var pitch_variation: float = 0.08
## Corta el audio en cuanto te detienes, sin importar cuanto dure el archivo.
@export var stop_sound_when_still: bool = true

var footstep_timer: float = 0.0
var _audio_player: AudioStreamPlayer2D

@onready var player: CharacterBody2D = get_parent()


func _ready() -> void:
	_audio_player = AudioStreamPlayer2D.new()
	add_child(_audio_player)


func _physics_process(delta: float) -> void:
	var speed_u := player.velocity.length() / PX_PER_UNIT
	var is_moving := speed_u > moving_threshold_u

	if not is_moving:
		footstep_timer = 0.0
		if stop_sound_when_still and _audio_player.playing:
			_audio_player.stop()
		return

	footstep_timer += delta
	if footstep_timer < footstep_interval:
		return

	footstep_timer = 0.0
	_do_footstep(speed_u)


func _do_footstep(speed_u: float) -> void:
	var is_sprint := speed_u >= sprint_threshold_u
	var radius_u := sprint_noise_radius_u if is_sprint else walk_noise_radius_u
	var source_type: int = NoiseManager.SourceType.SPRINT if is_sprint else NoiseManager.SourceType.FOOTSTEP

	NoiseManager.emit_noise(player.global_position, radius_u * PX_PER_UNIT, source_type)
	_play_random_clip(sprint_clips if is_sprint else walk_clips)


func _play_random_clip(clips: Array[AudioStream]) -> void:
	if clips.is_empty():
		return

	var clip: AudioStream = clips[randi() % clips.size()]
	_audio_player.global_position = player.global_position
	_audio_player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	_audio_player.volume_db = volume_db
	_audio_player.stream = clip
	_audio_player.play()
