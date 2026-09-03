extends StaticBody2D

# BodyAltar (el ritual de rezo)
#
# El jugador mantiene "pray" (E) pegado al altar durante pray_duration segundos
# seguidos. Mientras reza:
#
#   - Queda ENRAIZADO: GameState.is_praying bloquea el movimiento en player.gd.
#     Rezar es comprometerte, no algo que hagas de pasada.
#   - Emite ruido continuo de pray_noise_radius_u cada pray_noise_interval.
#   - A los pulse_at_time segundos suelta UN PULSO mas grande
#     (pulse_radius_u) que dura pulse_duration: el momento en el que el ritual
#     te delata de verdad.
#
# Soltar la tecla o alejarse reinicia el progreso a cero. No hay progreso
# parcial guardado: o aguantas los 12 s o no cuenta.
#
# UNIDADES: 1 u = 32 px, misma convencion que player.gd. Los radios se
# exportan en unidades; antes este script era el unico que usaba pixeles
# crudos y por eso tenia el radio mal (340 px se escribio creyendo 1 u = 64 px,
# o sea 5.3 u; con la convencion real eran 10.6 u, casi el doble de la spec).
const PX_PER_UNIT: float = 32.0

@export_group("Ritual")
## Cuanto hay que aguantar sin soltar, en segundos (spec: 12 s).
@export var pray_duration: float = 12.0

@export_group("Ruido (u)")
## Radio del ruido continuo mientras rezas (spec: 6 u).
@export var pray_noise_radius_u: float = 6.0
## Cada cuanto se le avisa a NoiseManager mientras dura el rezo.
@export var pray_noise_interval: float = 0.5

@export_group("Pulso")
## Segundo del ritual en el que se dispara el pulso (spec: t = 2 s).
@export var pulse_at_time: float = 2.0
## Radio del pulso (spec: 8 u).
@export var pulse_radius_u: float = 8.0
## Cuanto dura el pulso (spec: 1.5 s).
@export var pulse_duration: float = 1.5

@export_group("Audio")
@export var pray_clips: Array[AudioStream] = []
@export var pray_volume_db: float = -4.0

var jugador_cerca: bool = false
var tiempo_interaccion: float = 0.0

@onready var label_texto = $Label
@onready var barra_progreso = $ProgressBar
@onready var sprite = $Sprite2D

var jugador_ref: CharacterBody2D = null
var _estaba_rezando: bool = false
var _timer_ruido: float = 0.0
var _pulse_disparado: bool = false
var _pulse_restante: float = 0.0
var _audio_player: AudioStreamPlayer2D
var _color_base: Color


func _ready() -> void:
	_audio_player = AudioStreamPlayer2D.new()
	add_child(_audio_player)
	_color_base = sprite.modulate


func _process(delta):
	# Si el jugador murio a medio rezo hay que soltar la bandera, si no se
	# queda enraizado para siempre al reiniciar.
	if GameState.is_dead:
		if _estaba_rezando:
			_cancelar_rezo()
		return

	if jugador_cerca and Input.is_action_pressed("pray"):
		label_texto.hide()
		barra_progreso.show()

		if not _estaba_rezando:
			_estaba_rezando = true
			_timer_ruido = 0.0
			_pulse_disparado = false
			_pulse_restante = 0.0
			GameState.is_praying = true
			_reproducir_sonido_rezo()
			_avisar_ruido()
		elif not _audio_player.playing:
			_reproducir_sonido_rezo()

		tiempo_interaccion += delta
		_tick_pulso(delta)

		# El ruido periodico usa el radio del pulso mientras el pulso esta vivo.
		_timer_ruido += delta
		if _timer_ruido >= pray_noise_interval:
			_timer_ruido = 0.0
			_avisar_ruido()

		barra_progreso.value = (tiempo_interaccion / pray_duration) * 100

		if tiempo_interaccion >= pray_duration:
			_interaccion_completada()

	else:
		if _estaba_rezando:
			_cancelar_rezo()

		tiempo_interaccion = 0.0
		barra_progreso.value = 0
		barra_progreso.hide()

		if jugador_cerca:
			label_texto.show()


## Dispara el pulso una sola vez al cruzar pulse_at_time y lo mantiene vivo
## pulse_duration segundos. Mientras vive, _radio_actual() devuelve el radio
## grande, asi que el ruido periodico sale amplificado sin logica aparte.
func _tick_pulso(delta: float) -> void:
	if not _pulse_disparado and tiempo_interaccion >= pulse_at_time:
		_pulse_disparado = true
		_pulse_restante = pulse_duration
		_avisar_ruido()

	if _pulse_restante > 0.0:
		_pulse_restante = max(0.0, _pulse_restante - delta)

	_refrescar_color()


func _radio_actual_u() -> float:
	return pulse_radius_u if _pulse_restante > 0.0 else pray_noise_radius_u


## El altar se pone incandescente mientras dura el pulso. Es la unica lectura
## visual que tiene el jugador de "esto acaba de sonar el doble de fuerte".
func _refrescar_color() -> void:
	if sprite == null:
		return
	if _pulse_restante > 0.0:
		var t: float = _pulse_restante / max(pulse_duration, 0.001)
		sprite.modulate = _color_base.lerp(Color(1, 1, 1), t)
	else:
		sprite.modulate = _color_base


## Suelta el ritual sin completarlo: limpia el enraizado, el pulso y el audio.
func _cancelar_rezo() -> void:
	_estaba_rezando = false
	_pulse_disparado = false
	_pulse_restante = 0.0
	GameState.is_praying = false
	_refrescar_color()

	if _audio_player.playing:
		_audio_player.stop()


func _interaccion_completada():
	print("[Altar] Rezo completado (%.1f s)" % pray_duration)
	# OJO: hay que soltar la bandera ANTES del queue_free, si no el jugador se
	# queda enraizado para siempre porque ya no existe quien la baje.
	GameState.is_praying = false
	_estaba_rezando = false
	if _audio_player.playing:
		_audio_player.stop()
	queue_free()


func _on_area_2d_body_entered(body: Node2D) -> void:
		if body is CharacterBody2D:
			jugador_cerca = true
			jugador_ref = body
			label_texto.show()


func _on_area_2d_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		if _estaba_rezando:
			_cancelar_rezo()
		jugador_cerca = false
		jugador_ref = null
		label_texto.hide()
		barra_progreso.hide()
		tiempo_interaccion = 0.0


func _reproducir_sonido_rezo() -> void:
	if pray_clips.is_empty():
		return
	_audio_player.global_position = global_position
	_audio_player.volume_db = pray_volume_db
	_audio_player.stream = pray_clips[randi() % pray_clips.size()]
	_audio_player.play()


func _avisar_ruido() -> void:
	var posicion := jugador_ref.global_position if jugador_ref != null else global_position
	NoiseManager.emit_noise(posicion, _radio_actual_u() * PX_PER_UNIT, NoiseManager.SourceType.PRAY)
