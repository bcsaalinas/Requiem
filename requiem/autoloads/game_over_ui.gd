extends CanvasLayer

# GameOverUi (Autoload)
#
# Cuando GameState avisa que el jugador murio, instancia la pantalla de game
# over (ui/game_over.tscn), que ofrece reintentar o volver al menu.
#
# The screen makes no sound of its own. The catch is carried by the entity's own sounds
# (entities/entity_audio.gd: the grab, the cloth, the sob that stops), and after them the house
# is silent (audio/mix_director.gd).

const GAME_OVER_SCENE := preload("res://ui/game_over.tscn")

var screen: Control


func _ready() -> void:
	layer = 100
	GameState.player_died.connect(_on_player_died)
	GameState.state_reset.connect(_reset)


func _on_player_died() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
	screen = GAME_OVER_SCENE.instantiate()
	LegacyUi.fit_root(screen)
	add_child(screen)


func _exit_tree() -> void:
	_reset()


func _reset() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
		screen = null
