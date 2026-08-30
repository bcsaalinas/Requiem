extends StaticBody2D

var jugador_cerca: bool = false
var tiempo_interaccion: float = 0.0
const TIEMPO_REQUERIDO: float = 7.0 # Los 7 segundos requeridos

# Conecta directamente a los nodos que arrastraste al panel
@onready var label_texto = $Label
@onready var barra_progreso = $ProgressBar

func _process(delta):
	# Si el jugador está cerca y mantiene presionada la F
	if jugador_cerca and Input.is_physical_key_pressed(KEY_F):
		label_texto.hide()
		barra_progreso.show()
		
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
		
		if jugador_cerca:
			label_texto.show()


func _interaccion_completada():
	print("¡Interacción de 7 segundos completada!")
	# Aquí puedes hacer que la caja desaparezca, te dé un objeto, etc.
	queue_free() # Esto destruye la cajsa temporalmente para probar


func _on_area_2d_body_entered(body: Node2D) -> void:
		if body is CharacterBody2D: 
			jugador_cerca = true
			label_texto.show()


func _on_area_2d_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		jugador_cerca = false
		label_texto.hide()
		barra_progreso.hide()
		tiempo_interaccion = 0.0
