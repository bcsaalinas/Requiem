extends Control
## Pantalla de game over: se instancia desde el autoload GameOverUi cuando el
## jugador muere. Ofrece reintentar el nivel o volver al menu.


func _on_restart_pressed() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("retry_from_game_over"):
		scene.retry_from_game_over()
		return
	GameState.reset()
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://tutorial/main_menu.tscn")