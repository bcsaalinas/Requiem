extends Node

# GameState (Autoload)
#
# Maneja si el jugador murio o no. Otros scripts (Player, Entity)
# consultan GameState.is_dead para saber si deben congelarse.

signal player_died
signal state_reset
signal prayer_started(altar: Node)
signal prayer_ended(altar: Node, immediate: bool)
signal altar_completed(altar: Node)
signal all_altars_completed

var is_dead: bool = false
## True mientras el jugador esta rezando en un altar. player.gd lo lee para
## enraizarlo: la spec pide que rezar deje al jugador sin poder moverse.
var is_praying: bool = false
## The accepted altar owns the ritual clock; presentation reads this source.
var prayer_source: Node = null

## Contador oficial de progreso para los 7 altares de la hacienda.
var altars_completed: int = 0
var total_altars: int = 7


func begin_prayer(altar: Node) -> bool:
	if is_dead or not is_instance_valid(altar):
		return false
	if altar.has_method("can_begin_prayer") and not altar.can_begin_prayer():
		return false
	if is_instance_valid(prayer_source):
		return prayer_source == altar and is_praying
	prayer_source = altar
	is_praying = true
	prayer_started.emit(altar)
	return true


func end_prayer(altar: Node, immediate := false) -> void:
	if not is_instance_valid(altar) or prayer_source != altar:
		return
	prayer_source = null
	is_praying = false
	prayer_ended.emit(altar, immediate)


func _cancel_active_prayer() -> void:
	var source := prayer_source
	if is_instance_valid(source):
		if source.has_method("cancel_prayer"):
			source.cancel_prayer(true)
		# Also support lightweight sources used by isolated scenes.
		if prayer_source == source:
			end_prayer(source, true)
	prayer_source = null
	is_praying = false


func kill_player() -> void:
	if is_dead:
		return
	is_dead = true
	_cancel_active_prayer()
	player_died.emit()


func register_altar_prayed(altar: Node) -> void:
	altars_completed += 1
	altar_completed.emit(altar)
	if altars_completed >= total_altars:
		all_altars_completed.emit()


## A retry: she is alive again. What she has already done (the altars she prayed at) stays.
func reset() -> void:
	_cancel_active_prayer()
	is_dead = false
	state_reset.emit()


## A new game: the Hacienda's altars are unlit again.
func reset_progress() -> void:
	altars_completed = 0
