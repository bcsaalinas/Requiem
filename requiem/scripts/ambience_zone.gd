extends Area2D

# AmbienceZone
#
# Poligono o circulo de trigger: mientras el jugador esta DENTRO, esta zona
# es la candidata a sonar (ver autoloads/ambience_manager.gd, que maneja el
# crossfade real y la pila para zonas anidadas). No hace falta coordinar
# zonas vecinas entre si: cada una solo avisa "entre" / "sali".
#
# Requiere un CollisionShape2D hijo, igual que cualquier otra Area2D del
# proyecto (ver altar/body_altar.gd). Solo reacciona al nodo en el grupo
# "player" (lo agrega player.gd en su _ready()).
#
# ambient_stream se pone en Loop en el .import (clic derecho > Reimport,
# activar Loop): esto es una atmosfera de fondo larga, no un efecto suelto,
# asi que no usa el patron _play_random_clip() de los demas componentes.

@export var ambient_stream: AudioStream
@export var volume_db: float = -6.0
## Cuanto tarda el crossfade al entrar/salir de esta zona.
@export var fade_time: float = 2.5


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Si la zona se destruye (ej. queue_free de un nivel) mientras el jugador
## seguia dentro, no debe quedar fantasma en la pila del manager.
func _exit_tree() -> void:
	AmbienceManager.exit_zone(self)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		AmbienceManager.enter_zone(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		AmbienceManager.exit_zone(self)
