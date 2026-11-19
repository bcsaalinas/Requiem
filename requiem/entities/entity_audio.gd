class_name EntityAudio
extends Node2D
## Everything the entity sounds like, played from where it really is.
##
## Its body: every sound the animations call for (SpriteRig.cue) plays on its exact frame.
## Its breath and the drag of its shroud are loops that follow what it is doing.
## Each sound is a set of variations (SoundLibrary); a small pool of players lets steps overlap
## without cutting each other off. Nothing here makes noise the entity can hear.

## Animation cue -> sound set. Every cue name in the entity-lab JSON files is here or in
## SILENT_CUES (the regression test checks it).
const CUE_SETS := {
	"neck_click": "entity/neck_click",
	"claw_scrape": "entity/claw_scrape",
	"exhale": "entity/exhale",
	"inhale": "entity/inhale",
	"scream": "entity/scream",
	"foot_slam": "entity/foot_slam",
	"pat_tap": "entity/pat_tap",
	"catch_grab": "entity/catch_grab",
	"cloth_fall": "entity/cloth_fall",
	"sob_stops": "entity/sob_stops",
	"footstep_left": "entity/claws_walk",
	"footstep_right": "entity/claws_walk",
	"footstep_right_hard": "entity/claws_run",
	"launch_step": "entity/claws_run",
	"scuttle_step_left": "entity/claws_scuttle",
	"scuttle_step_right": "entity/claws_scuttle",
	"claw_grope": "entity/claw_scrape",
	"claw_tick": "entity/pat_tap",
}
## Cues that are drawn but make no sound.
const SILENT_CUES: Array[String] = ["ear_flick"]
const BREATH_CALM := "entity/breath_calm"
const BREATH_HUNT := "entity/breath_hunt"
const DRAG := "entity/drag"
const SILENT_DB := -60.0

## A sound started: which set, on which player. For the debug read-out and the tests.
signal played(set_id: String, voice: AudioStreamPlayer2D)

var entity: CharacterBody2D
var rig: Node
## On: it breathes even while it is not shown yet (the tutorial's unseen arrival). Once it is
## shown it always breathes, except while it listens, screams or catches.
var breathes_unseen := false
## How many times each set has played, and the last one (debug read-out, tests).
var plays := {}
var last_set := ""
var _voices: Array[AudioStreamPlayer2D] = []
var _next_voice := 0
var _breath: AudioStreamPlayer2D
var _drag: AudioStreamPlayer2D
var _unknown_cues := {}
var _was_shown := false


func _ready() -> void:
	entity = get_parent() as CharacterBody2D
	for index in SoundSettings.current().entity_voices:
		_voices.append(_player("Voice%d" % index))
	_breath = _player("Breath")
	_drag = _player("Drag")
	rig = entity.get_node_or_null("SpriteRig")
	if rig != null and rig.has_signal(&"cue"):
		rig.connect(&"cue", play_cue)


func _player(player_name: String) -> AudioStreamPlayer2D:
	var settings := SoundSettings.current()
	var player := AudioStreamPlayer2D.new()
	player.name = player_name
	player.bus = AudioBus.ENTITY
	player.max_distance = Units.to_px(settings.entity_reach_u)
	player.attenuation = settings.entity_falloff
	add_child(player)
	return player


## Plays the sound an animation frame calls for. Unknown names warn once and stay silent.
func play_cue(cue_name: String) -> AudioStreamPlayer2D:
	if SILENT_CUES.has(cue_name):
		return null
	if not CUE_SETS.has(cue_name):
		if not _unknown_cues.has(cue_name):
			_unknown_cues[cue_name] = true
			push_warning("[EntityAudio] animation cue '%s' has no sound set" % cue_name)
		return null
	return play_set(CUE_SETS[cue_name], float(SoundSettings.current().cue_gain_db.get(cue_name, 0.0)))


## Plays one variation of a set from the entity's position. Returns the player, or null when
## the set is empty.
func play_set(set_id: String, extra_db := 0.0, pitch := 1.0) -> AudioStreamPlayer2D:
	var stream := SoundLibrary.stream(set_id)
	if stream == null:
		return null
	var voice := _free_voice()
	voice.stream = stream
	voice.volume_db = SoundLibrary.gain_db(set_id) + extra_db
	voice.pitch_scale = pitch
	voice.play()
	plays[set_id] = int(plays.get(set_id, 0)) + 1
	last_set = set_id
	played.emit(set_id, voice)
	return voice


## The tutorial's switch for the time before it is shown: on, it can already be heard breathing.
func set_breathing(on: bool) -> void:
	breathes_unseen = on


## Cuts everything it is sounding (a reset, a zone change).
func stop_all() -> void:
	for voice in _voices:
		voice.stop()
	_breath.stop()
	_drag.stop()


## The set its breath loop is playing right now ("" when it is not breathing).
func breath_set() -> String:
	return _loop_set(_breath) if _breath.playing else ""


## True while the drag loop of its shroud is playing.
func is_dragging() -> bool:
	return _drag.playing


## A player that is not busy; when all are, the one that started longest ago.
func _free_voice() -> AudioStreamPlayer2D:
	for offset in _voices.size():
		var voice := _voices[(_next_voice + offset) % _voices.size()]
		if not voice.playing:
			_next_voice = (_next_voice + offset + 1) % _voices.size()
			return voice
	var oldest := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return oldest


func _process(delta: float) -> void:
	var settings := SoundSettings.current()
	var dead: bool = GameState.is_dead
	var shown := entity.is_visible_in_tree()
	if shown:
		breathes_unseen = false
	elif _was_shown:
		stop_all()
	_was_shown = shown
	# It holds its breath while it listens and while it screams: the silence is the tell.
	# The catch has its own sounds, and nothing under them.
	var reacting: bool = _is(&"is_listening") or _is(&"is_screaming") or (rig != null and rig.get(&"mode") == "catch")
	var breathes: bool = not dead and (shown or breathes_unseen)
	var wanted_breath := BREATH_HUNT if _state() == "HUNT" else BREATH_CALM
	_drive_loop(_breath, wanted_breath if breathes and not reacting else "", delta, reacting)
	# The shroud drags while it moves.
	var active: bool = entity.get(&"active") != false
	var moving: bool = shown and active and not dead and not reacting \
		and entity.velocity.length() > Units.to_px(settings.moving_speed_u)
	_drive_loop(_drag, DRAG if moving else "", delta, reacting)


## Fades a loop toward the set it should be playing ("" = silence). A change of set waits for
## the old one to fade out; `at_once` stops it with no fade.
func _drive_loop(player: AudioStreamPlayer2D, set_id: String, delta: float, at_once := false) -> void:
	var step := delta * -SILENT_DB / maxf(SoundSettings.current().loop_fade, 0.001)
	if player.playing and _loop_set(player) != set_id:
		player.volume_db = SILENT_DB if at_once else move_toward(player.volume_db, SILENT_DB, step)
		if player.volume_db > SILENT_DB:
			return
		player.stop()
	if set_id == "":
		return
	if not player.playing:
		player.set_meta(&"set", set_id)
		if SoundLibrary.stream(set_id) == null:       # empty set: silent, warned once
			return
		var variations := SoundLibrary.files(set_id)
		player.stream = variations[randi() % variations.size()]       # loops: one take, going round
		player.volume_db = SILENT_DB
		player.play()
	player.volume_db = move_toward(player.volume_db, SoundLibrary.gain_db(set_id), step)


func _loop_set(player: AudioStreamPlayer2D) -> String:
	return String(player.get_meta(&"set", ""))


func _is(method: StringName) -> bool:
	return entity.has_method(method) and bool(entity.call(method))


func _state() -> String:
	return String(entity.call(&"get_state_name")) if entity.has_method(&"get_state_name") else ""
