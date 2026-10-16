extends CanvasLayer

# GameOverUi (Autoload)
#
# Cuando GameState avisa que el jugador murio, instancia la pantalla de game
# over (ui/game_over.tscn), que ofrece reintentar o volver al menu.

const GAME_OVER_SCENE := preload("res://ui/game_over.tscn")
const DEATH_STINGER_PATH := "res://assets/audio/534218__thesoundfxguy_yt__piano-jump-scare-stinger.wav"

var screen: Control
var _audio_player: AudioStreamPlayer


func _ready() -> void:
	layer = 100
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)

	GameState.player_died.connect(_on_player_died)
	GameState.state_reset.connect(_reset)


func _on_player_died() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
	screen = GAME_OVER_SCENE.instantiate()
	add_child(screen)
	play_death_stinger()


func _exit_tree() -> void:
	_reset()


func _reset() -> void:
	if is_instance_valid(screen):
		screen.queue_free()
		screen = null
	_audio_player.stop()
	_audio_player.stream = null


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
