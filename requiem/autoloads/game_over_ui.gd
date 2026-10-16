extends CanvasLayer

# GameOverUi (Autoload)
#
# Cuando GameState avisa que el jugador murio, instancia la pantalla de game
# over (ui/game_over.tscn), que ofrece reintentar o volver al menu.

const GAME_OVER_SCENE := preload("res://ui/game_over.tscn")

var screen: Control


func _ready() -> void:
	layer = 100
	GameState.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
	screen = GAME_OVER_SCENE.instantiate()
	add_child(screen)