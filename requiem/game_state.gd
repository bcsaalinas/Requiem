extends Node

# GameState (Autoload)
#
# Maneja si el jugador murio o no. Otros scripts (Player, Entity)
# consultan GameState.is_dead para saber si deben congelarse.

signal player_died

var is_dead: bool = false


func kill_player() -> void:
	if is_dead:
		return
	is_dead = true
	player_died.emit()


func reset() -> void:
	is_dead = false
