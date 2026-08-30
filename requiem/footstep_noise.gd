extends Node

# FootstepNoise
#
# Componente independiente: NO modifica el script de movimiento del
# companero (player.gd). Solo lee la velocidad del CharacterBody2D
# padre (Player) para saber si esta caminando o corriendo, reproduce
# el audio real correspondiente, y avisa a NoiseManager para que la
# entidad pueda reaccionar.

@export_group("Deteccion de movimiento")
@export var moving_threshold: float = 5.0
@export var sprint_speed_threshold: float = 150.0

@export_group("Ruido de pasos (px)")
@export var footstep_interval: float = 0.45
@export var walk_noise_radius: float = 170.0
@export var sprint_noise_radius: float = 400.0

@export_group("Audio")
@export var walk_clips: Array[AudioStream] = []
@export var sprint_clips: Array[AudioStream] = []
@export var volume_db: float = -6.0
@export_range(0.0, 0.3) var pitch_variation: float = 0.08
@export var stop_sound_when_still: bool = true  # corta el audio en cuanto te detienes, sin importar cuanto dure el archivo

var footstep_timer: float = 0.0
var _audio_player: AudioStreamPlayer2D

@onready var player: CharacterBody2D = get_parent()


func _ready() -> void:
	_audio_player = AudioStreamPlayer2D.new()
	add_child(_audio_player)


func _physics_process(delta: float) -> void:
	var speed := player.velocity.length()
	var is_moving := speed > moving_threshold

	if not is_moving:
		footstep_timer = 0.0
		if stop_sound_when_still and _audio_player.playing:
			_audio_player.stop()
		return

	footstep_timer += delta
	if footstep_timer < footstep_interval:
		return

	footstep_timer = 0.0
	_do_footstep(speed)


func _do_footstep(speed: float) -> void:
	var is_sprint := speed >= sprint_speed_threshold
	var radius := sprint_noise_radius if is_sprint else walk_noise_radius
	var source_type: int = NoiseManager.SourceType.SPRINT if is_sprint else NoiseManager.SourceType.FOOTSTEP

	NoiseManager.emit_noise(player.global_position, radius, source_type)
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
