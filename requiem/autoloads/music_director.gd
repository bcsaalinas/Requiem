extends Node
"""Adaptive music routing. Empty optional catalogs are intentional until authored music exists."""

enum MusicState { MENU, EXPLORE, INVESTIGATE, SEARCH, HUNT, PRAYER, DEATH }

signal music_state_changed(previous: int, current: int)

const STATE_NAMES := ["MENU", "EXPLORE", "INVESTIGATE", "SEARCH", "HUNT", "PRAYER", "DEATH"]
const CROSSFADE_SECONDS := 1.4
const BREATH_DUCK_DB := -5.0
const KIT_TRACKS := {
	"MENU": "res://assets/audio/menumusic.mp3",
	"EXPLORE": "res://assets/audio/horror-jam-kit/WAV/Drone/drone_tension_02.wav",
	"INVESTIGATE": "res://assets/audio/horror-jam-kit/WAV/Drone/drone_tension_03.wav",
	"SEARCH": "res://assets/audio/horror-jam-kit 3/OGG/Tonal/high_tension_tone_01.ogg",
	"HUNT": "res://assets/audio/horror-jam-kit 3/OGG/Drone/drone_tension_03.ogg",
	"PRAYER": "res://assets/audio/horror-jam-kit 3/OGG/Tonal/eerie_music_box_02.ogg",
}
const HEARTBEAT_PATH := "res://assets/audio/horror-jam-kit 3/OGG/Body/heartbeat_01.ogg"

## Assign authored looping music here when available. Missing resources are safely ignored.
@export var music_tracks: Dictionary = {}
## Optional synchronized layers per state. If present, the base track is replaced
## by these stems and all layers start together for vertical remixing.
@export var music_stems: Dictionary = {}
## Optional per-state linear stem gains (0..1), one entry per stem.
@export var music_stem_gains: Dictionary = {}

var current_state: int = -1
var breath_held := false
var _banks: Array = []
var _active_bank := 0
var _active_state := MusicState.MENU
var _player_bank: Dictionary = {}
var _generation := 0
var _bound_entity: Node
var _bound_breath: Node
var _prayer_source: Node
var _entity_music_state: int = MusicState.EXPLORE
var _heartbeat: AudioStreamPlayer
var _heartbeat_base_db := -80.0

func _ready() -> void:
	_ensure_buses()
	for bank_index in 2:
		var bank: Array[AudioStreamPlayer] = []
		for voice_index in 4:
			var player := AudioStreamPlayer.new()
			player.bus = "Music"
			player.volume_db = -80.0
			player.finished.connect(_on_track_finished.bind(player))
			add_child(player)
			bank.append(player)
			_player_bank[player.get_instance_id()] = bank_index
		_banks.append(bank)
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.name = "ThreatHeartbeat"
	_heartbeat.bus = "SFX"
	_heartbeat.volume_db = -80.0
	if ResourceLoader.exists(HEARTBEAT_PATH):
		_heartbeat.stream = load(HEARTBEAT_PATH)
		_heartbeat.finished.connect(_on_heartbeat_finished)
	add_child(_heartbeat)
	set_music_state(MusicState.MENU)
	GameState.prayer_started.connect(_on_prayer_started)
	GameState.prayer_ended.connect(_on_prayer_ended)
	GameState.player_died.connect(_on_player_died)
	GameState.state_reset.connect(_on_game_reset)

func _ensure_buses() -> void:
	for bus_name in ["Music", "Ambience", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func set_music_state(state: int) -> void:
	if state < 0 or state >= STATE_NAMES.size():
		return
	if state == current_state:
		return
	var previous := current_state
	current_state = state
	music_state_changed.emit(previous, current_state)
	_crossfade_to(_streams_for(state), state)

func _streams_for(state: int) -> Array[AudioStream]:
	var key := StringName(STATE_NAMES[state])
	var raw_stems = music_stems.get(key, music_stems.get(STATE_NAMES[state], []))
	var streams: Array[AudioStream] = []
	if raw_stems is Array:
		for item in raw_stems:
			if item is AudioStream:
				streams.append(item)
	if not streams.is_empty():
		return streams
	var stream: AudioStream = music_tracks.get(key, music_tracks.get(STATE_NAMES[state], null))
	if stream != null:
		streams.append(stream)
		return streams
	var path := "res://assets/audio/music/%s.ogg" % STATE_NAMES[state].to_lower()
	if ResourceLoader.exists(path):
		streams.append(load(path) as AudioStream)
	elif KIT_TRACKS.has(STATE_NAMES[state]) and ResourceLoader.exists(KIT_TRACKS[STATE_NAMES[state]]):
		streams.append(load(KIT_TRACKS[STATE_NAMES[state]]) as AudioStream)
	return streams

func _crossfade_to(streams: Array[AudioStream], state: int) -> void:
	_active_state = state
	var outgoing: Array = _banks[_active_bank]
	if not streams.is_empty() and _bank_matches(outgoing, streams):
		return
	_generation += 1
	var generation := _generation
	var incoming_index := 1 - _active_bank
	var incoming: Array = _banks[incoming_index]
	if streams.is_empty():
		var fade_out := create_tween().set_parallel(true)
		var had_audio := false
		for player in outgoing:
			if player.playing:
				had_audio = true
				fade_out.tween_property(player, "volume_db", -80.0, CROSSFADE_SECONDS)
		if had_audio:
			fade_out.finished.connect(func():
				if generation == _generation:
					for player in outgoing: player.stop())
		return
	for player in incoming:
		player.stop()
		player.stream = null
	for i in mini(streams.size(), incoming.size()):
		var player: AudioStreamPlayer = incoming[i]
		player.stream = streams[i]
		player.volume_db = -80.0
		player.play()
	_active_bank = incoming_index
	var fade := create_tween().set_parallel(true)
	for i in streams.size():
		fade.tween_property(incoming[i], "volume_db", _stem_target_db(state, i), CROSSFADE_SECONDS)
	for player in outgoing:
		if player.playing:
			fade.tween_property(player, "volume_db", -80.0, CROSSFADE_SECONDS)
	fade.finished.connect(func():
		if generation == _generation:
			for player in outgoing: player.stop())

func _bank_matches(bank: Array, streams: Array[AudioStream]) -> bool:
	if streams.size() > bank.size(): return false
	for index in streams.size():
		var player: AudioStreamPlayer = bank[index]
		if not player.playing or player.stream != streams[index]: return false
	return true

func _effective_music_db() -> float:
	return BREATH_DUCK_DB if breath_held else 0.0

func set_breath_held(held: bool) -> void:
	if breath_held == held:
		return
	breath_held = held
	var tween := create_tween().set_parallel(true)
	for index in _banks[_active_bank].size():
		var player: AudioStreamPlayer = _banks[_active_bank][index]
		if player.playing:
			tween.tween_property(player, "volume_db", _stem_target_db(_active_state, index), 0.18)
	if is_instance_valid(_heartbeat) and _heartbeat.playing:
		var heartbeat_target := _heartbeat_base_db + (BREATH_DUCK_DB if held else 0.0)
		tween.tween_property(_heartbeat, "volume_db", heartbeat_target, 0.18)

## Called by gameplay when the tutorial hides/deactivates its entity for a zone transition.
func clear_entity_threat() -> void:
	_entity_music_state = MusicState.EXPLORE
	_heartbeat.stop()
	if current_state not in [MusicState.PRAYER, MusicState.DEATH]:
		set_music_state(MusicState.EXPLORE)

## Change vertical layer balance without restarting the loop. Values are linear gains.
func set_stem_mix(state: int, gains: Array[float], fade_time := 0.5) -> void:
	if state < 0 or state >= STATE_NAMES.size(): return
	music_stem_gains[StringName(STATE_NAMES[state])] = gains.duplicate()
	if state != _active_state: return
	var tween := create_tween().set_parallel(true)
	var players: Array = _banks[_active_bank]
	for index in mini(players.size(), gains.size()):
		var player: AudioStreamPlayer = players[index]
		if player.playing:
			tween.tween_property(player, "volume_db", _stem_target_db(state, index), maxf(0.01, fade_time))

func _stem_target_db(state: int, layer: int) -> float:
	var key := StringName(STATE_NAMES[state])
	var gains: Array = music_stem_gains.get(key, music_stem_gains.get(STATE_NAMES[state], []))
	var gain := float(gains[layer]) if layer < gains.size() else 1.0
	if gain <= 0.0001: return -80.0
	return _effective_music_db() + linear_to_db(gain)

func bind_gameplay(entity: Node, breath: Node) -> void:
	if is_instance_valid(_bound_entity) and _bound_entity.has_signal("state_changed"):
		var old_cb := Callable(self, "_on_entity_state_changed")
		if _bound_entity.is_connected(&"state_changed", old_cb): _bound_entity.disconnect(&"state_changed", old_cb)
	if is_instance_valid(_bound_breath):
		for pair in [[&"hold_started", &"_on_hold_started"], [&"breath_released", &"_on_breath_released"], [&"hold_cancelled", &"_on_hold_cancelled"], [&"forced_gasp_started", &"_on_forced_gasp"]]:
			var sig: StringName = pair[0]
			var cb := Callable(self, String(pair[1]))
			if _bound_breath.has_signal(sig) and _bound_breath.is_connected(sig, cb): _bound_breath.disconnect(sig, cb)
	_bound_entity = entity
	_bound_breath = breath
	if is_instance_valid(entity) and entity.has_signal("state_changed"):
		entity.connect(&"state_changed", Callable(self, "_on_entity_state_changed"))
		_on_entity_state_changed(-1, int(entity.get("current_state")))
	if is_instance_valid(breath):
		if breath.has_signal("hold_started"): breath.connect(&"hold_started", Callable(self, "_on_hold_started"))
		if breath.has_signal("breath_released"): breath.connect(&"breath_released", Callable(self, "_on_breath_released"))
		if breath.has_signal("hold_cancelled"): breath.connect(&"hold_cancelled", Callable(self, "_on_hold_cancelled"))
		if breath.has_signal("forced_gasp_started"): breath.connect(&"forced_gasp_started", Callable(self, "_on_forced_gasp"))

func _on_entity_state_changed(_previous: int, new_state: int) -> void:
	_entity_music_state = _music_state_for_entity(new_state)
	_set_threat_heartbeat(new_state)
	if current_state in [MusicState.PRAYER, MusicState.DEATH]: return
	set_music_state(_entity_music_state)

func _set_threat_heartbeat(entity_state: int) -> void:
	if not is_instance_valid(_heartbeat) or _heartbeat.stream == null: return
	if current_state in [MusicState.PRAYER, MusicState.DEATH]:
		_heartbeat.stop()
		return
	if entity_state == 3:
		_heartbeat_base_db = -13.0
	elif entity_state == 2:
		_heartbeat_base_db = -20.0
	else:
		_heartbeat_base_db = -80.0
	if _heartbeat_base_db <= -80.0:
		_heartbeat.stop()
	else:
		_heartbeat.volume_db = _heartbeat_base_db + (BREATH_DUCK_DB if breath_held else 0.0)
		if not _heartbeat.playing: _heartbeat.play()

func _on_heartbeat_finished() -> void:
	if current_state in [MusicState.SEARCH, MusicState.HUNT]: _heartbeat.play()

func _music_state_for_entity(new_state: int) -> int:
	match new_state:
		0: return MusicState.EXPLORE # PATROL
		1: return MusicState.INVESTIGATE
		2: return MusicState.SEARCH
		3: return MusicState.HUNT
	return MusicState.EXPLORE

func _on_hold_started() -> void: set_breath_held(true)
func _on_breath_released(_quiet: bool, _lung: float) -> void: set_breath_held(false)
func _on_hold_cancelled() -> void: set_breath_held(false)
func _on_forced_gasp(_reason: StringName, _duration: float) -> void: set_breath_held(false)

func _on_prayer_started(source: Node) -> void:
	_prayer_source = source
	_heartbeat.stop()
	set_music_state(MusicState.PRAYER)
func _on_prayer_ended(source: Node, _immediate: bool) -> void:
	if source == _prayer_source:
		_prayer_source = null
		set_music_state(_entity_music_state)
		_set_threat_heartbeat(2 if _entity_music_state == MusicState.SEARCH else (3 if _entity_music_state == MusicState.HUNT else 0))
func _on_player_died() -> void:
	_heartbeat.stop()
	set_music_state(MusicState.DEATH)
func _on_game_reset() -> void:
	set_breath_held(false)
	_prayer_source = null
	_heartbeat.stop()
	set_music_state(MusicState.EXPLORE)

func _on_track_finished(player: AudioStreamPlayer) -> void:
	if int(_player_bank.get(player.get_instance_id(), -1)) == _active_bank and player.stream != null:
		player.play()
