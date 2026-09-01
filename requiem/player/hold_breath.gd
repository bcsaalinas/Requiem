extends Node

# HoldBreath (mecanica de respiracion / agotamiento de la spec de Requiem)
#
# Se pone como hijo del Player, en un nodo llamado EXACTAMENTE "HoldBreath"
# (player.gd lo busca con get_node_or_null("HoldBreath")). Usa la accion de
# input "hold_breath" (tecla recomendada: Espacio).
#
# Maneja DOS medidores independientes:
#
#   - Pulmon (lung_percent, 100 -> 0): se vacia mientras aguantas la
#     respiracion, se recupera cuando no. Llegar a 0 -> gasp forzado.
#
#   - Agotamiento (exertion_percent, 0 -> 100): sube si esprintas O si aguantas
#     la respiracion; SOLO baja mientras estas "en calma" (ni esprint, ni
#     aguantar, ni bloqueado). Nunca se resetea por soltar: solo baja poco a
#     poco. Llegar a 100 -> el mismo gasp forzado, y ademas se pone en 0.
#
# Los dos medidores comparten el mismo castigo (_forced_gasp): 2s de bloqueo de
# movimiento + ruido fuerte de 7 u.
#
# UNIDADES: 1 u = 32 px. Los radios se exportan en unidades.
const PX_PER_UNIT: float = 32.0

@export_group("Pulmon")
@export var drain_rate_percent: float = 20.0
@export var refill_rate_percent: float = 10.0

@export_group("Agotamiento")
## Sube mientras esprintas o aguantas la respiracion.
@export var exertion_rise_rate_percent: float = 6.0
## Baja solo mientras estas en calma (ni esprint, ni aguantar, ni bloqueado).
@export var exertion_decay_rate_percent: float = 4.0

@export_group("Ruido al soltar (u)")
@export var quiet_exhale_radius_u: float = 1.0
@export var gasp_radius_u: float = 5.0
@export var forced_gasp_radius_u: float = 7.0
@export var forced_lock_duration: float = 2.0

@export_group("Audio")
@export var hold_clips: Array[AudioStream] = []
@export var exhale_clips: Array[AudioStream] = []
@export var gasp_clips: Array[AudioStream] = []
@export var forced_gasp_clips: Array[AudioStream] = []
@export var volume_db: float = -4.0

var lung_percent: float = 100.0
var exertion_percent: float = 0.0
var is_holding: bool = false
var is_locked: bool = false
var _lock_timer: float = 0.0
var _audio_player: AudioStreamPlayer2D

@onready var player: Node2D = get_parent()

# --- Barras visuales: pulmon arriba, agotamiento justo debajo ---
var _bar_layer: CanvasLayer
var _lung_bar: ProgressBar
var _exertion_bar: ProgressBar


func _ready() -> void:
	_audio_player = AudioStreamPlayer2D.new()
	add_child(_audio_player)

	_bar_layer = CanvasLayer.new()
	add_child(_bar_layer)

	_lung_bar = _make_bar(Vector2(20, 20))
	_lung_bar.value = 100
	_bar_layer.add_child(_lung_bar)

	_exertion_bar = _make_bar(Vector2(20, 54))
	_exertion_bar.value = 0
	_bar_layer.add_child(_exertion_bar)


## Construye una barra con el mismo estilo que la barra original de pulmon.
func _make_bar(pos: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.size = Vector2(220, 24)
	bar.position = pos
	bar.show_percentage = false
	bar.visible = false
	return bar


func _physics_process(delta: float) -> void:
	if is_locked:
		_lock_timer -= delta
		if _lock_timer <= 0.0:
			is_locked = false
		_update_bars()
		return

	var wants_to_hold := Input.is_action_pressed("hold_breath")

	# --- Pulmon ---
	if wants_to_hold and lung_percent > 0.0:
		_continue_holding(delta)
	else:
		if is_holding:
			_release_breath()
		_refill_lung(delta)

	# _continue_holding pudo disparar el gasp forzado; si quedamos bloqueados
	# no seguimos tocando el agotamiento este frame.
	if is_locked:
		_update_bars()
		return

	# --- Agotamiento (independiente del pulmon) ---
	_tick_exertion(delta)

	_update_bars()


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


## Sube el agotamiento si hay esfuerzo (esprint del Player o aguantar aqui),
## lo baja si hay calma. Nunca se resetea al soltar: solo la calma lo baja.
func _tick_exertion(delta: float) -> void:
	# player.is_sprinting llega sin tipo (player es Node2D), lo forzamos a bool.
	var player_sprinting: bool = player.is_sprinting
	var exerting := player_sprinting or is_holding

	if exerting:
		exertion_percent = min(100.0, exertion_percent + exertion_rise_rate_percent * delta)
		if exertion_percent >= 100.0:
			_forced_gasp()
	else:
		exertion_percent = max(0.0, exertion_percent - exertion_decay_rate_percent * delta)


func _release_breath() -> void:
	is_holding = false
	_audio_player.stop()

	if lung_percent > 20.0:
		_emit_breath(quiet_exhale_radius_u, exhale_clips)
	else:
		_emit_breath(gasp_radius_u, gasp_clips)


## Castigo compartido: lo llaman TANTO el pulmon al llegar a 0 COMO el
## agotamiento al llegar a 100. Bloquea el movimiento forced_lock_duration
## segundos, suelta un ruido fuerte de 7 u, y deja el agotamiento en 0 para
## no encadenar bloqueos infinitos.
func _forced_gasp() -> void:
	if is_locked:
		return
	is_holding = false
	is_locked = true
	_lock_timer = forced_lock_duration
	exertion_percent = 0.0
	_audio_player.stop()
	_emit_breath(forced_gasp_radius_u, forced_gasp_clips)


func _emit_breath(radius_u: float, clips: Array[AudioStream]) -> void:
	NoiseManager.emit_noise(player.global_position, radius_u * PX_PER_UNIT, NoiseManager.SourceType.BREATH)
	_play_random_clip(clips)


func _play_random_clip(clips: Array[AudioStream]) -> void:
	if clips.is_empty():
		return

	_audio_player.global_position = player.global_position
	_audio_player.volume_db = volume_db
	_audio_player.stream = clips[randi() % clips.size()]
	_audio_player.play()


func _update_bars() -> void:
	_lung_bar.value = lung_percent
	_lung_bar.visible = is_holding or is_locked

	_exertion_bar.value = exertion_percent
	_exertion_bar.visible = exertion_percent > 0.0


func get_lung_percent() -> float:
	return lung_percent


func get_exertion_percent() -> float:
	return exertion_percent
