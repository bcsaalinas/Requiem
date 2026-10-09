extends CanvasLayer

# GameOverUI (Autoload)
#
# Muestra el texto de "moriste" cuando GameState avisa que el
# jugador murio, y permite reiniciar el nivel con la tecla R.
#
# El stinger de muerte se carga por RUTA, no con preload(): esto es un
# autoload sin escena propia (no hay Inspector donde arrastrar el archivo), y
# preload() de un archivo que todavia no existe rompe la carga del proyecto
# entero. Con ResourceLoader.exists() el sonido queda mudo hasta que el
# archivo aparezca en esa ruta exacta; no hace falta tocar el codigo despues.
const DEATH_STINGER_PATH := "res://assets/audio/534218__thesoundfxguy_yt__piano-jump-scare-stinger.wav"

var label: Label
var _audio_player: AudioStreamPlayer


func _ready() -> void:
	layer = 100
	label = Label.new()
	label.text = ""
	label.add_theme_font_size_override("font_size", 42)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 0.2, 0.2)
	add_child(label)

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

	GameState.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	label.text = "MORISTE\nLa entidad te atrapo\n\nPresiona R para reintentar"
	play_death_stinger()


## Publico a proposito: el tutorial NUNCA llama GameState.kill_player() (su
## captura usa su propio Entity.caught -> request_reset(), que resetea al
## checkpoint en vez de "matar" de verdad), asi que player_died jamas se
## dispara ahi. tutorial.gd llama esto directo desde _caught() para que la
## captura siga sonando igual sin duplicar la logica de carga del stinger.
func play_death_stinger() -> void:
	if not ResourceLoader.exists(DEATH_STINGER_PATH):
		return
	_audio_player.stream = load(DEATH_STINGER_PATH)
	_audio_player.play()


func _unhandled_input(event: InputEvent) -> void:
	if GameState.is_dead and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		GameState.reset()
		label.text = ""
		get_tree().reload_current_scene()
