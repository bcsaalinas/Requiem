extends CanvasLayer

# GameOverUI (Autoload)
#
# Muestra el texto de "moriste" cuando GameState avisa que el
# jugador murio, y permite reiniciar el nivel con la tecla R.

var label: Label


func _ready() -> void:
	layer = 100
	label = Label.new()
	label.text = ""
	label.add_theme_font_size_override("font_size", 42)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 0.2, 0.2)
	add_child(label)

	GameState.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	label.text = "MORISTE\nLa entidad te atrapo\n\nPresiona R para reintentar"


func _unhandled_input(event: InputEvent) -> void:
	if GameState.is_dead and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		GameState.reset()
		label.text = ""
		get_tree().reload_current_scene()
