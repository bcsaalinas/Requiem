extends StaticBody2D

var jugador_cerca: bool = false
var tiempo_interaccion: float = 0.0
const TIEMPO_REQUERIDO: float = 7.0 # Los 7 segundos requeridos

# Conecta directamente a los nodos que arrastraste al panel
@onready var label_texto = $Label
@onready var barra_progreso = $ProgressBar

# --- Agregado: sonido y ruido de rezo ---
@export var pray_clips: Array[AudioStream] = []
@export var pray_noise_radius: float = 340.0       # equivalente al radio de 6 unidades de la spec
@export var pray_noise_interval: float = 0.5       # cada cuanto avisa a NoiseManager mientras reza
@export var pray_volume_db: float = -4.0

var jugador_ref: CharacterBody2D = null
var _estaba_rezando: bool = false
var _timer_ruido: float = 0.0
var _audio_player: AudioStreamPlayer2D


func _ready() -> void:
	_audio_player = AudioStreamPlayer2D.new()
	add_child(_audio_player)


func _process(delta):
	# Si el jugador está cerca y mantiene presionada la accion "pray" (E por defecto; se define en project.godot)
	if jugador_cerca and Input.is_action_pressed("pray"):
		label_texto.hide()
		barra_progreso.show()

		# --- Agregado: si apenas empieza a rezar, sonido + primer aviso de ruido ---
		if not _estaba_rezando:
			_estaba_rezando = true
			_timer_ruido = 0.0
			_reproducir_sonido_rezo()
			_avisar_ruido()
		# --- Agregado: si el audio ya termino pero sigues rezando, se repite (loop manual) ---
		elif not _audio_player.playing:
			_reproducir_sonido_rezo()

		# --- Agregado: avisar a la entidad periodicamente mientras reza ---
		_timer_ruido += delta
		if _timer_ruido >= pray_noise_interval:
			_timer_ruido = 0.0
			_avisar_ruido()

		# Sumamos el tiempo que ha pasado en este frame (delta)
		tiempo_interaccion += delta

		# Calculamos el porcentaje para la barra (0 a 100)
		barra_progreso.value = (tiempo_interaccion / TIEMPO_REQUERIDO) * 100

		# Si llegamos a los 7 segundos
		if tiempo_interaccion >= TIEMPO_REQUERIDO:
			_interaccion_completada()

	else:
		# Si suelta la tecla o se aleja, se reinicia todo
		tiempo_interaccion = 0.0
		barra_progreso.value = 0
		barra_progreso.hide()
		_estaba_rezando = false  # Para que vuelva a sonar la proxima vez

		# --- Agregado: corta el sonido en el instante que sueltas F o te alejas ---
		if _audio_player.playing:
			_audio_player.stop()

		if jugador_cerca:
			label_texto.show()


func _interaccion_completada():
	print("¡Interacción de 7 segundos completada!")
	# Aquí puedes hacer que la caja desaparezca, te dé un objeto, etc.
	queue_free() # Esto destruye la cajsa temporalmente para probar


func _on_area_2d_body_entered(body: Node2D) -> void:
		if body is CharacterBody2D:
			jugador_cerca = true
			jugador_ref = body  # Agregado: guardamos referencia para saber su posicion
			label_texto.show()


func _on_area_2d_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		jugador_cerca = false
		jugador_ref = null
		label_texto.hide()
		barra_progreso.hide()
		tiempo_interaccion = 0.0


# --- Agregado: helpers de sonido y ruido ---
func _reproducir_sonido_rezo() -> void:
	if pray_clips.is_empty():
		return
	_audio_player.global_position = global_position
	_audio_player.volume_db = pray_volume_db
	_audio_player.stream = pray_clips[randi() % pray_clips.size()]
	_audio_player.play()


func _avisar_ruido() -> void:
	var posicion := jugador_ref.global_position if jugador_ref != null else global_position
	NoiseManager.emit_noise(posicion, pray_noise_radius, NoiseManager.SourceType.PRAY)
