extends Control
## Pantalla de titulo / menu principal. Botones definidos visualmente en menu.tscn.


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://tutorial/tutorial.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()