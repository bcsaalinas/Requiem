extends Node
"""Adaptive music routing. Empty optional catalogs are intentional until authored music exists."""
## During play the music follows what the entity knows (Dread.awareness), never where it is:
##   it heard something  - the music is gone at once, and stays gone until the scream;
##   the scream          - the hunt music and a rising tone start with it, not before;
##   it lost the trail   - almost nothing: one thin tone;
##   it gave up          - the exploration drone comes back slowly;
##   it caught her       - silence.
## Each of those changes has its own fade time (audio/sound_settings.tres, "Music").

## HEARD has no track: it is the silence between the heard-you cue and the scream.
enum MusicState { MENU, EXPLORE, INVESTIGATE, SEARCH, HUNT, PRAYER, DEATH, HEARD }

signal music_state_changed(previous: int, current: int)

const STATE_NAMES := ["MENU", "EXPLORE", "INVESTIGATE", "SEARCH", "HUNT", "PRAYER", "DEATH", "HEARD"]
## Name of the request this script makes to MixDirector while Viv holds her breath.
const BREATH_DUCK := &"breath_hold_music"
const KIT_TRACKS := {
	"MENU": "res://assets/audio/menumusic.mp3",
	"EXPLORE": "res://assets/audio/horror-jam-kit/WAV/Drone/drone_tension_02.wav",
	"INVESTIGATE": "res://assets/audio/horror-jam-kit/WAV/Drone/drone_tension_03.wav",
	"SEARCH": "res://assets/audio/horror-jam-kit 3/OGG/Tonal/high_tension_tone_01.ogg",
	"HUNT": "res://assets/audio/horror-jam-kit 3/OGG/Drone/drone_tension_03.ogg",
	"PRAYER": "res://assets/audio/horror-jam-kit 3/OGG/Tonal/eerie_music_box_02.ogg",
}
const HEARTBEAT_PATH := "res://assets/audio/horror-jam-kit 3/OGG/Body/heartbeat_01.ogg"
## The rising tone that starts with the scream, once per hunt.
const RISER_PATH := "res://assets/audio/horror-jam-kit 3/OGG/Riser/pitch_riser_01.ogg"
## A track this far down is silent, and is stopped.
const SILENT_DB := -60.0

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
## player -> { from, to, time, length }: levels on their way somewhere.
var _fades := {}
var _bound_entity: Node
var _bound_breath: Node
var _prayer_source: Node
## The state the entity's awareness asks for; it applies whenever prayer or death do not hold the music.
var _entity_music_state: int = MusicState.EXPLORE
## Counts down from the start of a hunt to starting its music without a scream (-1: not waiting).
var _hunt_wait := -1.0
## True from the game over screen until the next attempt: nothing moves the music meanwhile.
var _dead := false
var _heartbeat: AudioStreamPlayer
var _heartbeat_base_db := -80.0
var _riser: AudioStreamPlayer

func _ready() -> void:
	_ensure_buses()
	for bank_index in 2:
		var bank: Array[AudioStreamPlayer] = []
		for voice_index in 4:
			var player := AudioStreamPlayer.new()
			player.bus = AudioBus.MUSIC
			player.volume_db = SILENT_DB
			player.finished.connect(_on_track_finished.bind(player))
			add_child(player)
			bank.append(player)
			_player_bank[player.get_instance_id()] = bank_index
		_banks.append(bank)
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.name = "ThreatHeartbeat"
	_heartbeat.bus = AudioBus.BODY
	_heartbeat.volume_db = -80.0
	if ResourceLoader.exists(HEARTBEAT_PATH):
		_heartbeat.stream = load(HEARTBEAT_PATH)
		_heartbeat.finished.connect(_on_heartbeat_finished)
	add_child(_heartbeat)
	_riser = AudioStreamPlayer.new()
	_riser.name = "HuntRiser"
	_riser.bus = AudioBus.MUSIC
	if ResourceLoader.exists(RISER_PATH):
		_riser.stream = load(RISER_PATH)
	add_child(_riser)
	set_music_state(MusicState.MENU)
	GameState.prayer_started.connect(_on_prayer_started)
	GameState.prayer_ended.connect(_on_prayer_ended)
	GameState.player_died.connect(_on_player_died)
	GameState.state_reset.connect(_on_game_reset)
	Dread.awareness_changed.connect(_on_awareness_changed)
	Dread.cue_played.connect(_on_cue_played)

## The bus layout has one owner: MixDirector (audio/mix_director.gd).
func _ensure_buses() -> void:
	MixDirector.ensure_buses()

## Changes the music. `seconds` is how long the change takes; left out, the fade that belongs
## to this change is used (fade_for).
func set_music_state(state: int, seconds := -1.0) -> void:
	if state < 0 or state >= STATE_NAMES.size():
		return
	if state == current_state:
		return
	var previous := current_state
	current_state = state
	if seconds < 0.0:
		seconds = fade_for(previous, state)
	music_state_changed.emit(previous, current_state)
	_crossfade_to(_streams_for(state), state, seconds)
	if state != MusicState.HUNT and _riser.playing:
		_fade(_riser, SILENT_DB, seconds)
	_set_threat_heartbeat()

## How long the change from one state to another takes (audio/sound_settings.tres, "Music").
func fade_for(previous: int, current: int) -> float:
	var settings := SoundSettings.current()
	match current:
		MusicState.HEARD: return settings.music_fade_heard
		MusicState.HUNT: return settings.music_fade_hunt
		MusicState.SEARCH: return settings.music_fade_search
		MusicState.DEATH: return settings.music_fade_catch
		MusicState.EXPLORE:
			if previous == MusicState.SEARCH:
				return randf_range(settings.music_fade_stand_down.x, settings.music_fade_stand_down.y)
	return settings.music_fade

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

## Brings in the tracks of a state and takes out whatever else is playing, over `seconds`.
## A state with no tracks is silence.
func _crossfade_to(streams: Array[AudioStream], state: int, seconds: float) -> void:
	_active_state = state
	var current: Array = _banks[_active_bank]
	var other: Array = _banks[1 - _active_bank]
	if streams.is_empty():
		for player: AudioStreamPlayer in current + other:
			if player.playing: _fade(player, SILENT_DB, seconds)
		return
	if _bank_matches(current, streams):
		# Already playing, perhaps on its way out: it comes (back) up, and nothing restarts.
		for index in streams.size():
			_fade(current[index], _stem_target_db(state, index), seconds)
		for player: AudioStreamPlayer in other:
			if player.playing: _fade(player, SILENT_DB, seconds)
		return
	for player: AudioStreamPlayer in other:
		_fades.erase(player)
		player.stop()
		player.stream = null
	for index in mini(streams.size(), other.size()):
		var player: AudioStreamPlayer = other[index]
		player.stream = streams[index]
		player.volume_db = SILENT_DB
		player.play()
		_fade(player, _stem_target_db(state, index), seconds)
	for player: AudioStreamPlayer in current:
		if player.playing: _fade(player, SILENT_DB, seconds)
	_active_bank = 1 - _active_bank

func _bank_matches(bank: Array, streams: Array[AudioStream]) -> bool:
	if streams.size() > bank.size(): return false
	for index in streams.size():
		var player: AudioStreamPlayer = bank[index]
		if not player.playing or player.stream != streams[index]: return false
	return true

## Moves a player's level to `to_db` over `seconds`; a player that reaches silence is stopped.
## A new fade replaces the one before it, so two changes never pull on the same track.
func _fade(player: AudioStreamPlayer, to_db: float, seconds: float) -> void:
	if seconds <= 0.0:
		_fades.erase(player)
		player.volume_db = to_db
		if to_db <= SILENT_DB: player.stop()
		return
	_fades[player] = {"from": player.volume_db, "to": to_db, "time": 0.0, "length": seconds}

func _process(delta: float) -> void:
	if _hunt_wait >= 0.0:
		_hunt_wait -= delta
		if _hunt_wait < 0.0:
			_begin_hunt_music()
	for player: AudioStreamPlayer in _fades.keys():
		var fade: Dictionary = _fades[player]
		fade.time += delta
		var t := clampf(fade.time / fade.length, 0.0, 1.0)
		# Coming in, a track rises quickly at first and then settles; going out is the mirror.
		# A long fade is then heard along its whole length, not only at one end of it.
		var shaped := 1.0 - (1.0 - t) * (1.0 - t) if fade.to > fade.from else t * t
		player.volume_db = lerpf(fade.from, fade.to, shaped)
		if t >= 1.0:
			_fades.erase(player)
			if fade.to <= SILENT_DB: player.stop()

## The music steps back while she holds her breath. The Music bus is MixDirector's to move;
## the threat heartbeat is this script's own player, so it follows here.
func set_breath_held(held: bool) -> void:
	if breath_held == held:
		return
	breath_held = held
	var settings := SoundSettings.current()
	if held:
		MixDirector.duck(BREATH_DUCK, MixDirector.Priority.BREATH, {AudioBus.MUSIC: settings.breath_duck_db}, settings.breath_duck_fade)
	else:
		MixDirector.release(BREATH_DUCK, settings.breath_duck_fade)
	if is_instance_valid(_heartbeat) and _heartbeat.playing:
		var heartbeat_target := _heartbeat_base_db + (settings.breath_duck_db if held else 0.0)
		create_tween().tween_property(_heartbeat, "volume_db", heartbeat_target, settings.breath_duck_fade)

## Called by gameplay when the tutorial hides/deactivates its entity for a zone transition.
func clear_entity_threat() -> void:
	_entity_music_state = MusicState.EXPLORE
	_hunt_wait = -1.0
	_heartbeat.stop()
	if current_state != MusicState.PRAYER and not _dead:
		set_music_state(MusicState.EXPLORE)

## Change vertical layer balance without restarting the loop. Values are linear gains.
func set_stem_mix(state: int, gains: Array[float], fade_time := 0.5) -> void:
	if state < 0 or state >= STATE_NAMES.size(): return
	music_stem_gains[StringName(STATE_NAMES[state])] = gains.duplicate()
	if state != _active_state: return
	var players: Array = _banks[_active_bank]
	for index in mini(players.size(), gains.size()):
		var player: AudioStreamPlayer = players[index]
		if player.playing:
			_fade(player, _stem_target_db(state, index), maxf(0.01, fade_time))

func _stem_target_db(state: int, layer: int) -> float:
	var key := StringName(STATE_NAMES[state])
	var gains: Array = music_stem_gains.get(key, music_stem_gains.get(STATE_NAMES[state], []))
	var gain := float(gains[layer]) if layer < gains.size() else 1.0
	if gain <= 0.0001: return SILENT_DB
	# While it searches there is almost no music: the thin tone plays well under the others.
	return linear_to_db(gain) + (SoundSettings.current().music_search_db if state == MusicState.SEARCH else 0.0)

## Gameplay starts (or, with null, ends): from here the music follows what the entity knows,
## and steps back while Viv holds her breath.
func bind_gameplay(entity: Node, breath: Node) -> void:
	if is_instance_valid(_bound_breath):
		for pair in [[&"hold_started", &"_on_hold_started"], [&"breath_released", &"_on_breath_released"], [&"hold_cancelled", &"_on_hold_cancelled"], [&"forced_gasp_started", &"_on_forced_gasp"]]:
			var sig: StringName = pair[0]
			var cb := Callable(self, String(pair[1]))
			if _bound_breath.has_signal(sig) and _bound_breath.is_connected(sig, cb): _bound_breath.disconnect(sig, cb)
	_bound_entity = entity
	_bound_breath = breath
	_hunt_wait = -1.0
	if not is_instance_valid(breath):
		set_breath_held(false)
	if is_instance_valid(entity):
		# An entity with no EntityAudio is followed too (one that has it has reported itself).
		Dread.watch(entity as Node2D)
		_on_awareness_changed(Dread.Awareness.UNAWARE, Dread.awareness_of(entity as Node2D))
	if is_instance_valid(breath):
		if breath.has_signal("hold_started"): breath.connect(&"hold_started", Callable(self, "_on_hold_started"))
		if breath.has_signal("breath_released"): breath.connect(&"breath_released", Callable(self, "_on_breath_released"))
		if breath.has_signal("hold_cancelled"): breath.connect(&"hold_cancelled", Callable(self, "_on_hold_cancelled"))
		if breath.has_signal("forced_gasp_started"): breath.connect(&"forced_gasp_started", Callable(self, "_on_forced_gasp"))

## What the entity knows changed. Only during play: the menu has its own music.
func _on_awareness_changed(_previous: int, current: int) -> void:
	if not is_instance_valid(_bound_entity):
		return
	_hunt_wait = -1.0
	match current:
		Dread.Awareness.HEARD:
			_follow(MusicState.HEARD)
		Dread.Awareness.HUNTING:
			# The hunt music starts with the scream, never before it. Until then: nothing.
			_follow(MusicState.HEARD)
			_hunt_wait = SoundSettings.current().music_hunt_latest
		Dread.Awareness.SEARCHING:
			_follow(MusicState.SEARCH)
		Dread.Awareness.CAUGHT:
			_follow(MusicState.DEATH)
		_:
			_follow(MusicState.EXPLORE)

func _on_cue_played(moment: StringName) -> void:
	if moment == &"scream" and _hunt_wait >= 0.0:
		_begin_hunt_music()

## The scream: the hunt music and the rising tone start together.
func _begin_hunt_music() -> void:
	_hunt_wait = -1.0
	_follow(MusicState.HUNT)
	if current_state == MusicState.HUNT and _riser.stream != null:
		_fades.erase(_riser)
		_riser.volume_db = SoundSettings.current().music_riser_db
		_riser.play()

## Takes the state the entity's awareness asks for, unless prayer or death hold the music.
func _follow(state: int) -> void:
	_entity_music_state = state
	if current_state == MusicState.PRAYER or _dead:
		return
	set_music_state(state)

## Viv's heart under a search and a hunt. It follows the music, so it starts with the scream too.
func _set_threat_heartbeat() -> void:
	if not is_instance_valid(_heartbeat) or _heartbeat.stream == null: return
	if current_state == MusicState.HUNT:
		_heartbeat_base_db = -13.0
	elif current_state == MusicState.SEARCH:
		_heartbeat_base_db = -20.0
	else:
		_heartbeat_base_db = -80.0
	if _heartbeat_base_db <= -80.0:
		_heartbeat.stop()
	else:
		_heartbeat.volume_db = _heartbeat_base_db + (SoundSettings.current().breath_duck_db if breath_held else 0.0)
		if not _heartbeat.playing: _heartbeat.play()

func _on_heartbeat_finished() -> void:
	if current_state in [MusicState.SEARCH, MusicState.HUNT]: _heartbeat.play()

func _on_hold_started() -> void: set_breath_held(true)
func _on_breath_released(_quiet: bool, _lung: float) -> void: set_breath_held(false)
func _on_hold_cancelled() -> void: set_breath_held(false)
func _on_forced_gasp(_reason: StringName, _duration: float) -> void: set_breath_held(false)

func _on_prayer_started(source: Node) -> void:
	_prayer_source = source
	set_music_state(MusicState.PRAYER)
func _on_prayer_ended(source: Node, _immediate: bool) -> void:
	if source == _prayer_source:
		_prayer_source = null
		set_music_state(_entity_music_state)
func _on_player_died() -> void:
	_dead = true
	_hunt_wait = -1.0
	set_music_state(MusicState.DEATH)
func _on_game_reset() -> void:
	_dead = false
	_hunt_wait = -1.0
	_entity_music_state = MusicState.EXPLORE
	set_breath_held(false)
	_prayer_source = null
	set_music_state(MusicState.EXPLORE)

## A track that reaches its end starts again: while it is the music of the moment, and also
## while it is still fading out (a long fade never ends in a cut because the file ran out).
func _on_track_finished(player: AudioStreamPlayer) -> void:
	if player.stream == null:
		return
	if int(_player_bank.get(player.get_instance_id(), -1)) == _active_bank or _fades.has(player):
		player.play()
