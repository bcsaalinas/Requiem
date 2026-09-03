extends Node

# GameState (Autoload)
#
# Maneja si el jugador murio o no. Otros scripts (Player, Entity)
# consultan GameState.is_dead para saber si deben congelarse.

signal player_died

var is_dead: bool = false
## True mientras el jugador esta rezando en un altar. player.gd lo lee para
## enraizarlo: la spec pide que rezar deje al jugador sin poder moverse.
var is_praying: bool = false


func kill_player() -> void:
	if is_dead:
		return
	is_dead = true
	player_died.emit()


func reset() -> void:
	is_dead = false
	is_praying = false
