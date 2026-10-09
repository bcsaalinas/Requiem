extends Node

# AmbienceManager (Autoload)
#
# Las zonas de ambiente (AmbienceZone, ver scripts/ambience_zone.gd) avisan
# aqui cuando el jugador entra o sale. Este maneja una PILA de zonas activas
# en vez de un simple "zona actual": la de mas arriba (la ultima en la que
# entraste, mientras sigan todas superpuestas) es la que suena. Al salir de
# una, vuelve sola a la que queda debajo. Asi funcionan zonas anidadas sin
# que el nivel tenga que coordinarlas a mano: ej. "casa" por fuera y
# "sotano" por dentro, saliendo del sotano vuelve solo al ambiente de casa.
#
# Dos AudioStreamPlayer (no 2D: el ambiente es un lavado sobre toda la
# escena, no algo que tenga sentido paneado por posicion) turnados para
# poder cruzar (crossfade) de uno al otro sin cortar en seco.

const DEFAULT_FADE_TIME: float = 2.5
const SILENT_DB: float = -80.0

var _stack: Array = []

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer

var _fading: bool = false
var _fade_timer: float = 0.0
var _fade_duration: float = DEFAULT_FADE_TIME
var _fade_from_db: float = SILENT_DB
var _fade_to_db: float = SILENT_DB
var _outgoing: AudioStreamPlayer
var _incoming: AudioStreamPlayer


func _ready() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_b = AudioStreamPlayer.new()
	add_child(_player_a)
	add_child(_player_b)
	_active_player = _player_a


func _process(delta: float) -> void:
	if not _fading:
		return

	_fade_timer += delta
	var t := clampf(_fade_timer / _fade_duration, 0.0, 1.0)

	_incoming.volume_db = lerpf(SILENT_DB, _fade_to_db, t)
	if _outgoing != _incoming:
		_outgoing.volume_db = lerpf(_fade_from_db, SILENT_DB, t)

	if t >= 1.0:
		_fading = false
		if _outgoing != _incoming:
			_outgoing.stop()


## Llamado por AmbienceZone al entrar el jugador. Si la zona ya esta en la
## pila (reentrada rara) no hace nada.
func enter_zone(zone: Node) -> void:
	if _stack.has(zone):
		return
	_stack.append(zone)
	_apply_top()


## Llamado por AmbienceZone al salir el jugador (o al salir de escena, ver
## _exit_tree() de AmbienceZone: una zona nunca debe quedar fantasma en la
## pila si se destruye mientras el jugador seguia dentro).
func exit_zone(zone: Node) -> void:
	_stack.erase(zone)
	_apply_top()


func _apply_top() -> void:
	if _stack.is_empty():
		_crossfade_to(null, 0.0, DEFAULT_FADE_TIME)
		return

	var top: Node = _stack[-1]
	_crossfade_to(top.ambient_stream, top.volume_db, top.fade_time)


func _crossfade_to(stream: AudioStream, volume_db: float, fade_time: float) -> void:
	var incoming := _player_b if _active_player == _player_a else _player_a

	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	if stream != null:
		incoming.play()

	_outgoing = _active_player
	_incoming = incoming
	_active_player = incoming

	_fading = true
	_fade_timer = 0.0
	_fade_duration = maxf(fade_time, 0.01)
	_fade_from_db = _outgoing.volume_db if _outgoing.playing else SILENT_DB
	_fade_to_db = volume_db
