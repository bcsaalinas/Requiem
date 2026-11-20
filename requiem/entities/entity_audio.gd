class_name EntityAudio
extends Node2D
## Everything the entity sounds like, played from where it really is.
##
## Its body: every sound the animations call for (SpriteRig.cue) plays on its exact frame.
## Its breath and the drag of its shroud are loops that follow what it is doing.
## Each sound is a set of variations (SoundLibrary); a small pool of players lets steps overlap
## without cutting each other off. Nothing here makes noise the entity can hear.
##
## What it knows (Channel A) is heard from far away, and never falls silent with distance:
##   it heard something  - everything it was sounding stops dead, then the voice and the neck
##                         click together, one scrape, and silence until the scream;
##   it is hunting       - the inhale, then the scream and the stomp, with the music and the
##                         house ducked under them;
##   it lost the trail   - a groan, then one sniff;
##   it gave up          - a long breath out.
##
## Where it is (Channel B: its breath, talking, claws, drag and sniffing) only carries about a
## room. These sounds follow the way sound really travels to Viv (Acoustics): in the same room
## every one is heard, sharp and exactly placed; a room away they are quieter, dulled, vaguely
## placed, and some of them are lost on the way; further off there is nothing. What it knows
## (Channel A) is never dulled, thinned out or cut off like this.
## Behind a wall they come from the doorway the sound really travels through, not straight
## through the wall: they play from a holder (Heard) placed in the direction of that opening, at
## the distance the entity really is. What it knows is always heard from where it stands.
##
## Its calm breathing is quiet and comes and goes: a spell of breathing, then a rest, so it is
## never a steady rattle under everything (it breathes on without rests before it is shown,
## once it has heard something, and while Viv holds her breath to listen).
## While it knows nothing, its position sounds right beside her are held down a little
## (position_calm_near_db, gone where ring 2 ends), so nothing it does calm is a sudden jump in a
## silent house. Once it has heard something they are at their full level. Channel A never is.
##
## Its idle voice says it is alive and unaware: a mumbled phrase now and then while it walks its
## patrol, trailing off when it pauses. While it searches the voice is lower and rarer, and it
## sniffs in short runs as it scuttles. It never speaks while it listens, screams or hunts.
##
## Behind a switch (entity_knocks_enabled, off by default) it knocks on a door now and then:
## once in a patrol pause next to a door, at most once every two minutes, only while Viv hears
## it across her room or a room away (never on top of her). The knock is its own set
## (entity/knock, never the house's knock) on its own voice, played from where it stands, on the
## Entity bus. It is only a sound: nothing hears it and nothing it does changes.

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
const HEARD_VOICE := "entity/heard_voice"
const NECK_CLICK := "entity/neck_click"
const INHALE := "entity/inhale"
const SCREAM := "entity/scream"
const FOOT_SLAM := "entity/foot_slam"
const LOST := "entity/lost"
const SNIFF := "entity/sniff"
## The bite that ends a catch: played once, when the catch folds over her (the rig's
## hide_player moment, 0.74 s in), after the grab the animation cues itself.
const KILL := "entity/kill"
const STAND_DOWN := "entity/stand_down"
const MUMBLE := "entity/mumble"
const EXHALE := "entity/exhale"
## Its knock on a door. Every knock file comes from this folder, never the house's knock.
const KNOCK := "entity/knock"
const KNOCK_FOLDER := SoundLibrary.ROOT + KNOCK + "/"
## Its voice (the rest of Channel B is its body). A room away its voice gets through more often.
const VOICE_SETS: Array[String] = [MUMBLE, SNIFF, EXHALE]
const SILENT_DB := -60.0
## What a player is set to when nothing of it may be heard.
const GONE_DB := -80.0
## EntityAI.State, as state_changed reports it.
const PATROL := 0
## The check: it barely heard something and comes to look. It sounds like a search.
const INVESTIGATE := 1
const SEARCH := 2
const HUNT := 3
## Every player does its own falling off with distance; this switches the engine's off.
const NO_ENGINE_FALLOFF_PX := 1000000.0
const AWARENESS_VOICES := 6
## Name of the request made to MixDirector under the scream.
const SCREAM_DUCK := &"entity_scream"
## The hunt-start animation screams this long after its inhale.
const SCREAM_AFTER_INHALE := 0.2

## A sound started: which set, on which player. For the debug read-out and the tests.
signal played(set_id: String, voice: AudioStreamPlayer2D)
## An awareness cue started. moment: heard, heard_again, inhale, scream, foot_slam, lost,
## lost_sniff, stand_down. level_db: how far under its full level it reaches the listener.
signal awareness_played(moment: StringName, set_id: String, stream: AudioStream, level_db: float)
## A position sound was lost on the way to Viv (a gap, or it is too far to hear at all).
signal lost_on_the_way(set_id: String)

var entity: CharacterBody2D
var rig: Node
## On: it breathes even while it is not shown yet (the tutorial's unseen arrival). Once it is
## shown it always breathes, except while it listens, screams or catches.
var breathes_unseen := false
## How many times each set has played, and the last one (debug read-out, tests).
var plays := {}
var last_set := ""
## How its position sounds reach Viv right now: the way its sound travels (u), gliding between
## measurements, and what follows from it (debug read-out, tests).
var heard_u := 0.0
var heard_clarity := 1.0
var heard_ring := 3
## How many position sounds of each set were lost on the way, and the last one.
var gaps := {}
var last_gap := ""
## dB every position sound loses on the way right now, and how exactly it is placed (0..1).
var _reach_db := 0.0
var _panning := 1.0
## How calm it is for its position sounds (1 = it knows nothing, 0 = it has heard something),
## gliding over position_calm_fade, and what that holds its sounds down by right now (dB).
var _calm := 1.0
var _calm_known := false
var _calm_trim_db := 0.0
## Its calm breathing's rhythm: resting or in a spell, how far the rest holds it down (dB), how
## long this spell or rest still lasts, and whether something keeps it breathing right now.
var _breath_resting := false
var _breath_rest_db := 0.0
var _breath_left := 0.0
var _breath_held := false
## Where its position sounds (Channel B) play from: the entity itself, or behind a wall the
## direction of the opening its sound comes through (Acoustics), at the entity's own distance.
var heard: Node2D
## 0..1: after where it comes from jumped (another doorway, or into view), the placing comes
## back from dead centre to its full amount. What is placed is _panning times this.
var heard_settle := 1.0
## Where Heard is meant to be, relative to the ears, last frame (for telling a jump).
var _heard_target := Vector2.ZERO
var _heard_known := false
var _reach_known := false
## True once this catch has sounded its kill.
var _killed := false
var _voices: Array[AudioStreamPlayer2D] = []
var _next_voice := 0
var _breath: AudioStreamPlayer2D
var _drag: AudioStreamPlayer2D
## The same loops once more on the dulled bus: the two crossfade with clarity.
var _breath_far: AudioStreamPlayer2D
var _drag_far: AudioStreamPlayer2D
var _unknown_cues := {}
var _was_shown := false
## The last awareness cue: { moment, set, stream, level_db, at } (debug read-out, tests).
var last_awareness := {}
var _aware: Array[AudioStreamPlayer2D] = []
var _next_aware := 0
var _clock := 0.0
## Counts down to playing the heard-you cue without the animation's head snap (-1: not waiting).
var _heard_wait := -1.0
var _scraped := false
## Counts down to playing the scream without the animation (-1: not waiting).
var _scream_wait := -1.0
var _last_scream := -INF
var _duck_left := -1.0
var _sniff_wait := -1.0
var _exhale_covered_until := -INF
var _listener: Node2D
## The last idle phrase: { stream, pitch, state } (debug read-out, tests).
var last_talk := {}
var _talk: AudioStreamPlayer2D
## Seconds until the next phrase may start.
var _talk_wait := 0.0
## While a phrase trails off: dB it loses per second (0: it is not trailing off).
var _talk_fade := 0.0
var _still_for := 0.0
## Seconds until the next run of sniffs (-1: none planned).
var _sniff_run_wait := -1.0
var _sniffs_left := 0
var _sniff_pace := 0.0
var _sniff_next := 0.0
## Its knock: its own voice, here on the entity (not under Heard), so it is heard from where it
## stands, also through a wall.
var _knock: AudioStreamPlayer2D
## The last knock: { stream, door, at, level_db, ring, clock } (debug read-out, tests).
var last_knock := {}
var _last_knock := -INF
## Seconds it has been calm (unaware, on its patrol), and seconds it has stood still in this pause.
var _calm_for := 0.0
var _paused_for := 0.0
## This pause: whether the door next to it was looked for, that door (null: none), and whether
## it knocked.
var _knock_looked := false
var _knock_door: Door = null
var _knocked := false


func _ready() -> void:
	entity = get_parent() as CharacterBody2D
	# Channel B plays from Heard, which is placed on its own (top_level) and need not be where
	# the entity stands. Channel A stays here, on the entity.
	heard = Node2D.new()
	heard.name = "Heard"
	heard.top_level = true
	add_child(heard)
	heard.global_position = entity.global_position
	for index in SoundSettings.current().entity_voices:
		_voices.append(_player("Voice%d" % index, heard))
	_breath = _player("Breath", heard)
	_drag = _player("Drag", heard)
	_breath_far = _player("BreathFar", heard)
	_drag_far = _player("DragFar", heard)
	_breath_far.bus = AudioBus.ENTITY_FAR
	_drag_far.bus = AudioBus.ENTITY_FAR
	_talk = _player("Talk", heard)
	_talk_wait = _between(SoundSettings.current().talk_interval_patrol)
	_start_breath_spell()
	for index in AWARENESS_VOICES:
		_aware.append(_player("Awareness%d" % index))
	_knock = _player("Knock")
	rig = entity.get_node_or_null("SpriteRig")
	if rig != null and rig.has_signal(&"cue"):
		rig.connect(&"cue", play_cue)
	if rig != null and rig.has_signal(&"hide_player"):
		rig.connect(&"hide_player", _on_hide_player)
	if entity.has_signal(&"state_changed"):
		entity.connect(&"state_changed", _on_state_changed)
	if entity.has_signal(&"listen_started"):
		entity.connect(&"listen_started", _on_listen_started)
	if entity.has_signal(&"stood_down"):
		entity.connect(&"stood_down", _on_stood_down)
	# The mood of the house follows what this entity knows (audio/dread.gd).
	Dread.watch(entity, self)
	# How far its sound travels to Viv is measured a few times per second (audio/acoustics.gd).
	Acoustics.watch(entity, self)


func _player(player_name: String, holder: Node = self) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.name = player_name
	player.bus = AudioBus.ENTITY
	# The engine only knows the straight line. Levels are set here, from the way sound travels.
	player.max_distance = NO_ENGINE_FALLOFF_PX
	player.attenuation = 1.0
	holder.add_child(player)
	return player


## Plays the sound an animation frame calls for. Unknown names warn once and stay silent.
## The cues that say what it knows go out on Channel A.
func play_cue(cue_name: String) -> AudioStreamPlayer2D:
	if SILENT_CUES.has(cue_name):
		return null
	match cue_name:
		"neck_click":
			if _is(&"is_listening"):
				if _heard_wait >= 0.0:
					return _play_heard()
				# It turned its head to a second sound: the click again, never a second voice.
				return play_awareness(&"heard_again", NECK_CLICK, _heard_reach())
		"claw_scrape":
			if _is(&"is_listening"):
				if _scraped:
					return null     # one scrape, then silence until the scream
				_scraped = true
		"inhale":
			_duck_for_scream()
			return play_awareness(&"inhale", INHALE, _scream_reach())
		"scream":
			return _play_scream()
		"foot_slam":
			return play_awareness(&"foot_slam", FOOT_SLAM, _scream_reach())
		"launch_step":
			_release_scream_duck()
		"exhale":
			if _clock < _exhale_covered_until:
				return null         # the breath out of standing down is this same breath
	if not CUE_SETS.has(cue_name):
		if not _unknown_cues.has(cue_name):
			_unknown_cues[cue_name] = true
			push_warning("[EntityAudio] animation cue '%s' has no sound set" % cue_name)
		return null
	return play_set(CUE_SETS[cue_name], float(SoundSettings.current().cue_gain_db.get(cue_name, 0.0)))


## Plays one variation of a set from the entity's position, as a position sound (Channel B):
## a room away it may be lost on the way, and further off it always is. Returns the player, or
## null when the set is empty or the sound did not get through.
func play_set(set_id: String, extra_db := 0.0, pitch := 1.0) -> AudioStreamPlayer2D:
	var stream := SoundLibrary.stream(set_id)
	if stream == null:
		return null
	if is_catching() and heard_u > 0.0:
		_reach_known = false         # it has her: heard from her side at once, with no glide
		_tick_reach(0.0)
	if not _gets_through(set_id):
		return null
	var voice := _free_voice()
	voice.stream = stream
	voice.bus = _one_shot_bus()
	voice.set_meta(&"level", SoundLibrary.gain_db(set_id) + extra_db)
	voice.volume_db = _heard_db(float(voice.get_meta(&"level")))
	voice.panning_strength = placing()
	voice.pitch_scale = pitch
	voice.play()
	plays[set_id] = int(plays.get(set_id, 0)) + 1
	last_set = set_id
	played.emit(set_id, voice)
	return voice


## The catch has folded over her: the kill sound, once per catch (reset() arms it again).
func _on_hide_player() -> void:
	if _killed or not is_catching() or GameState.is_dead:
		return
	_killed = true
	play_set(KILL)


## The tutorial's switch for the time before it is shown: on, it can already be heard breathing.
func set_breathing(on: bool) -> void:
	breathes_unseen = on


## Cuts everything it is sounding, at once.
func stop_all() -> void:
	for voice in _voices + _aware:
		voice.stop()
	for loop in [_breath, _drag, _breath_far, _drag_far]:
		loop.stop()
	_talk.stop()
	_knock.stop()
	_talk_fade = 0.0
	_sniff_wait = -1.0
	_sniffs_left = 0


## Back to silence, with nothing pending (an encounter was reset).
func reset() -> void:
	stop_all()
	_killed = false
	_reach_known = false         # it was moved by hand: no glide from where it was
	_calm_known = false
	_start_breath_spell()
	_heard_wait = -1.0
	_scream_wait = -1.0
	_exhale_covered_until = -INF
	_sniff_run_wait = -1.0
	_talk_wait = _between(SoundSettings.current().talk_interval_patrol)
	_end_pause(true)           # a new encounter: no knock in its first moments
	if _duck_left >= 0.0:
		_duck_left = -1.0
		MixDirector.release(SCREAM_DUCK)


## Plays an awareness cue: one variation of a set (never the one played last), from the entity,
## at a level that falls with distance down to a floor and no further. reach is
## [full level out to (u), drop per u beyond (dB), floor (dB)].
func play_awareness(moment: StringName, set_id: String, reach: Array, extra_db := 0.0) -> AudioStreamPlayer2D:
	var stream := SoundLibrary.pick(set_id)
	if stream == null:
		return null
	var voice := _aware[_next_aware]
	for offset in _aware.size():
		var candidate := _aware[(_next_aware + offset) % _aware.size()]
		if not candidate.playing:
			voice = candidate
			break
	_next_aware = (_aware.find(voice) + 1) % _aware.size()
	var variation: float = SoundSettings.current().set_pitch_range
	voice.stream = stream
	voice.pitch_scale = randf_range(1.0 - variation, 1.0 + variation)
	voice.set_meta(&"base", SoundLibrary.gain_db(set_id) + extra_db)
	voice.set_meta(&"reach", reach)
	voice.set_meta(&"moment", moment)
	voice.set_meta(&"fade", 0.0)
	var level := reach_db(listener_distance_u(), reach)
	voice.volume_db = float(voice.get_meta(&"base")) + level
	voice.play()
	plays[set_id] = int(plays.get(set_id, 0)) + 1
	last_awareness = {"moment": moment, "set": set_id, "stream": stream, "level_db": level, "at": _clock}
	awareness_played.emit(moment, set_id, stream, level)
	return voice


## How far under its full level an awareness cue arrives at a distance: nothing lost out to
## reach[0] u, then reach[1] dB per u, never below reach[2].
static func reach_db(distance_u: float, reach: Array) -> float:
	return maxf(float(reach[2]), -maxf(0.0, distance_u - float(reach[0])) * float(reach[1]))


## Straight distance from the entity to Viv, in units (0 when there is nobody listening).
## What it knows (Channel A) falls off along this line; walls do not hold it back.
func listener_distance_u() -> float:
	if not is_instance_valid(_listener):
		_listener = get_tree().get_first_node_in_group(&"player") as Node2D
	return Units.to_u(entity.global_position.distance_to(_listener.global_position)) if _listener != null else 0.0


func _heard_reach() -> Array:
	var settings := SoundSettings.current()
	return [settings.heard_full_u, settings.heard_fall_db_per_u, settings.heard_floor_db]


func _scream_reach() -> Array:
	var settings := SoundSettings.current()
	return [settings.scream_full_u, settings.scream_fall_db_per_u, settings.scream_floor_db]


func _far_reach() -> Array:
	var settings := SoundSettings.current()
	return [settings.far_full_u, settings.far_fall_db_per_u, settings.far_floor_db]


## It froze to listen: everything it was sounding stops dead. The voice and the click follow
## on the animation's head snap, or after heard_click_wait without it.
func _on_listen_started() -> void:
	stop_all()
	_scraped = false
	_heard_wait = SoundSettings.current().heard_click_wait


## The heard-you cue: the voice and the neck click, always together.
func _play_heard() -> AudioStreamPlayer2D:
	_heard_wait = -1.0
	play_awareness(&"heard", NECK_CLICK, _heard_reach())
	return play_awareness(&"heard", HEARD_VOICE, _heard_reach(), SoundSettings.current().heard_voice_gain_db)


func _on_state_changed(previous: int, current: int) -> void:
	var settings := SoundSettings.current()
	if current == HUNT and previous != HUNT:
		# The animation screams 0.2 s after its inhale. With no animation running, the scream
		# still comes: no scream, no hunt.
		var animated: bool = rig != null and rig.is_visible_in_tree() and rig.is_processing()
		_scream_wait = settings.scream_cue_wait + SCREAM_AFTER_INHALE if animated else 0.0
	# A check sounds like a search: the lower, rarer talk and the sniffing. The "lost you"
	# groan stays the hunt's alone.
	var searching := current == SEARCH or current == INVESTIGATE
	if not searching:
		_sniff_wait = -1.0
		_sniff_run_wait = -1.0
		_sniffs_left = 0
	elif previous != SEARCH and previous != INVESTIGATE:
		_talk_wait = _between(settings.talk_interval_search)
		_sniff_run_wait = _between(settings.sniff_run_interval)
	if previous == HUNT and current == SEARCH:
		play_awareness(&"lost", LOST, _far_reach())
		_sniff_wait = settings.lost_then_sniff
		_sniff_run_wait = settings.lost_then_sniff + _between(settings.sniff_run_first)
	if previous == SEARCH and current == PATROL and not entity.has_signal(&"stood_down"):
		_on_stood_down()


func _play_scream() -> AudioStreamPlayer2D:
	var settings := SoundSettings.current()
	_scream_wait = -1.0
	var again := _clock - _last_scream < settings.scream_repeat_window
	_last_scream = _clock
	return play_awareness(&"scream", SCREAM, _scream_reach(), settings.scream_gain_db + (settings.scream_repeat_db if again else 0.0))


## Music, Ambience and World step down under the scream, from the inhale to the launch.
func _duck_for_scream() -> void:
	var settings := SoundSettings.current()
	MixDirector.duck(SCREAM_DUCK, MixDirector.Priority.SCREAM, {AudioBus.MUSIC: settings.scream_duck_db,
		AudioBus.AMBIENCE: settings.scream_duck_db, AudioBus.WORLD: settings.scream_duck_db}, settings.scream_duck_attack, self)
	_duck_left = settings.scream_duck_longest


func _release_scream_duck() -> void:
	if _duck_left >= 0.0:
		_duck_left = -1.0
		MixDirector.release(SCREAM_DUCK, SoundSettings.current().scream_duck_release)


## It gave up the search: one long breath out. A groan still sounding fades under it.
func _on_stood_down() -> void:
	var settings := SoundSettings.current()
	for voice in _aware:
		if voice.playing and voice.get_meta(&"moment", &"") in [&"lost", &"lost_sniff"]:
			voice.set_meta(&"fade", -SILENT_DB / maxf(settings.awareness_fade, 0.001))
	_sniff_wait = -1.0
	_exhale_covered_until = _clock + settings.stand_down_covers_exhale
	play_awareness(&"stand_down", STAND_DOWN, _far_reach())
	_talk_wait = _between(settings.talk_after_stand_down)       # then its idle talking resumes


func _tick_awareness(delta: float) -> void:
	_clock += delta
	if _heard_wait >= 0.0:
		_heard_wait -= delta
		if _heard_wait < 0.0:
			_play_heard()
	if _scream_wait >= 0.0:
		_scream_wait -= delta
		if _scream_wait < 0.0:
			if _duck_left < 0.0:
				_duck_for_scream()
			_play_scream()
			play_awareness(&"foot_slam", FOOT_SLAM, _scream_reach())
	if _duck_left >= 0.0:
		_duck_left -= delta
		if _duck_left < 0.0:
			_duck_left = 0.0
			_release_scream_duck()
	if _sniff_wait >= 0.0:
		_sniff_wait -= delta
		if _sniff_wait < 0.0:
			play_awareness(&"lost_sniff", SNIFF, _far_reach())
	var distance := listener_distance_u()
	for voice in _aware:
		if not voice.playing:
			continue
		var base := float(voice.get_meta(&"base")) - float(voice.get_meta(&"fade", 0.0)) * delta
		if float(voice.get_meta(&"fade", 0.0)) > 0.0:
			voice.set_meta(&"base", base)
			if base <= SILENT_DB:
				voice.stop()
				continue
		voice.volume_db = base + reach_db(distance, voice.get_meta(&"reach"))


## The set its breath loop is playing right now ("" when it is not breathing).
func breath_set() -> String:
	return _loop_set(_breath) if _breath.playing else ""


## True while the drag loop of its shroud is playing.
func is_dragging() -> bool:
	return _drag.playing


## True while it plays the catch: it has her.
func is_catching() -> bool:
	return rig != null and rig.get(&"mode") == "catch"


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


func _exit_tree() -> void:
	MixDirector.release(SCREAM_DUCK)
	Dread.report_presence(self, 0.0)
	Acoustics.unwatch(entity)


## It was put somewhere by hand (a reset, a test): it is heard from there at once, with no
## glide from where it was.
func placed() -> void:
	Acoustics.remeasure(entity)
	_reach_known = false
	_calm_known = false
	_start_breath_spell()
	_tick_reach(0.0)


## True while anything of it can be heard: it is shown, or it breathes before it is shown.
func is_audible() -> bool:
	return entity != null and entity.is_inside_tree() and (entity.is_visible_in_tree() or breathes_unseen)


## How much quieter a position sound is after travelling `acoustic_u` (0 = full level), when
## ring 1 ends at `limit_u`. From there on it is gone.
static func position_db(acoustic_u: float, limit_u: float) -> float:
	var settings := SoundSettings.current()
	if acoustic_u >= limit_u:
		return GONE_DB
	var along := clampf(inverse_lerp(settings.position_full_u, limit_u, acoustic_u), 0.0, 1.0)
	var level: float = settings.position_edge_db * pow(along, settings.position_falloff)
	var fade_from: float = limit_u - settings.position_fade_u
	if acoustic_u > fade_from:
		level = lerpf(level, SILENT_DB, inverse_lerp(fade_from, limit_u, acoustic_u))
	return level


## How much a position sound is held down because it is calm (`calm`, 0..1) and near, when
## ring 1 ends at `limit_u`: the whole of position_calm_near_db out to position_full_u,
## shrinking evenly to nothing where ring 2 ends (ring_near_u). While she listens ring 1 reaches
## further and that end moves out with it, so the distance curve under it keeps falling at
## least as fast and nearer is never quieter. Further off, and once it has heard something, 0.
static func calm_near_db(acoustic_u: float, limit_u: float, calm: float) -> float:
	var settings := SoundSettings.current()
	var gone_u: float = settings.ring_near_u * maxf(limit_u / settings.ring_somewhere_u, 1.0)
	var near := 1.0 - clampf(inverse_lerp(settings.position_full_u, gone_u, acoustic_u), 0.0, 1.0)
	return settings.position_calm_near_db * clampf(calm, 0.0, 1.0) * near


## What its position sounds are held down by right now because it is calm and near (dB, 0 or
## less; debug read-outs, tests).
func calm_trim_db() -> float:
	return _calm_trim_db


## What every position sound loses on the way to Viv right now, all told (dB; GONE_DB when
## nothing of it reaches her): distance, the calm trim and her own steps (debug read-outs).
func position_level_db() -> float:
	return _reach_db


## Calm glides towards 1 while it knows nothing (unaware, or standing still on its patrol) and
## towards 0 once it has heard something, over position_calm_fade. Put somewhere by hand (a
## reset, a test), it is set at once.
func _tick_calm(delta: float) -> void:
	var settings := SoundSettings.current()
	var calm_now := 1.0 if Dread.awareness_of(entity, self) <= Dread.Awareness.PAUSED else 0.0
	if not _calm_known or settings.position_calm_fade <= 0.0:
		_calm = calm_now
		_calm_known = true
	else:
		_calm = move_toward(_calm, calm_now, delta / settings.position_calm_fade)


## How exactly a position sound is placed after travelling `acoustic_u`: exact in rings 3 and
## 2, weakening across ring 1.
static func position_panning(acoustic_u: float, limit_u: float) -> float:
	var settings := SoundSettings.current()
	if acoustic_u <= settings.ring_near_u or limit_u <= settings.ring_near_u:
		return 1.0
	return lerpf(1.0, settings.far_panning, clampf(inverse_lerp(settings.ring_near_u, limit_u, acoustic_u), 0.0, 1.0))


## The chance that a single position sound gets through after travelling `acoustic_u`: always
## in rings 3 and 2, never beyond ring 1, and in between a chance that falls with clarity.
static func chance_through(acoustic_u: float, limit_u: float, voice: bool) -> float:
	var settings := SoundSettings.current()
	if acoustic_u >= limit_u:
		return 0.0
	if acoustic_u < settings.ring_near_u:
		return 1.0
	var span: Vector2 = settings.gap_chance_voice if voice else settings.gap_chance_body
	return lerpf(span.y, span.x, clampf(inverse_lerp(settings.ring_near_u, limit_u, acoustic_u), 0.0, 1.0))


## Where ring 1 ends for Viv right now, in units: further while she holds her breath to listen.
func reach_limit_u() -> float:
	var settings := SoundSettings.current()
	return settings.ring_somewhere_u * lerpf(1.0, settings.listen_reach_factor, Acoustics.focus)


## How much of a far-off position sound Viv's own movement covers right now, in dB (0 or
## less). Only in ring 1; it sets in over the first stretch of the ring, so there is no step.
func masked_db() -> float:
	var settings := SoundSettings.current()
	return Acoustics.mask_db * clampf(inverse_lerp(settings.ring_near_u, settings.ring_near_u + settings.mask_blend_u, heard_u), 0.0, 1.0)


## Rolls whether one position sound reaches Viv. One that does not is counted, never played.
func _gets_through(set_id: String) -> bool:
	var chance := chance_through(heard_u, reach_limit_u(), VOICE_SETS.has(set_id))
	# While she holds her breath to listen, fewer of them are lost (never beyond ring 1).
	if chance > 0.0:
		chance = 1.0 - (1.0 - chance) * lerpf(1.0, SoundSettings.current().listen_gap_factor, Acoustics.focus)
	if chance >= 1.0 or randf() < chance:
		return true
	gaps[set_id] = int(gaps.get(set_id, 0)) + 1
	last_gap = set_id
	lost_on_the_way.emit(set_id)
	return false


## A single sound plays on whichever bus is closer to what is left of its detail.
func _one_shot_bus() -> StringName:
	return AudioBus.ENTITY if heard_clarity >= SoundSettings.current().far_below_clarity else AudioBus.ENTITY_FAR


## The level of a position sound at Viv's ears, from the level it has next to her.
func _heard_db(level: float) -> float:
	return maxf(level + _reach_db, GONE_DB) if _reach_db > GONE_DB else GONE_DB


## Follows the way its sound travels to Viv (measured by Acoustics a few times per second,
## gliding in between), and reports how near it is to the mood of the house.
func _tick_reach(delta: float) -> void:
	var settings := SoundSettings.current()
	var listening: bool = Acoustics.listener() != null
	var audible := is_audible()
	# Put somewhere by hand, just heard again, or it has her: placed at once, with no glide and
	# no moment of vagueness.
	if not _reach_known or not audible:
		_heard_known = false
	# With nobody to hear it, it sounds as if she stood right here.
	var target := 0.0
	if listening:
		var reading := Acoustics.reading(entity)
		# Until it has been measured (it only just appeared), the straight line.
		target = reading.acoustic_u if reading.valid else listener_distance_u()
	# It has her: nothing is between them, whatever was measured last.
	if is_catching():
		target = 0.0
	if not audible:
		_reach_known = false
	elif not _reach_known or settings.position_smooth <= 0.0:
		heard_u = target
		_reach_known = true
	else:
		heard_u = lerpf(heard_u, target, 1.0 - exp(-delta / settings.position_smooth))
	var limit := reach_limit_u()
	heard_ring = 0 if heard_u >= limit else Acoustics.ring_for(heard_u)
	heard_clarity = Acoustics.clarity_for(heard_u)
	_tick_calm(delta)
	_calm_trim_db = calm_near_db(heard_u, limit, _calm)
	_reach_db = position_db(heard_u, limit)
	if _reach_db > GONE_DB:
		_reach_db += _calm_trim_db + masked_db()
	_panning = position_panning(heard_u, limit)
	Dread.report_presence(self, heard_clarity if audible and listening and not GameState.is_dead else 0.0)
	_place_heard(delta)


## How exactly its position sounds are placed right now (0 = dead centre, 1 = exact): the
## weakening with distance, times the moment of vagueness after a jump.
func placing() -> float:
	return _panning * heard_settle


## Where its position sounds come from, as far as direction goes (Heard): the entity itself,
## unless a wall is in the way and the sound comes round through an opening. Then Heard lies in
## the direction of that opening, at the distance the entity really is: Godot pans a 2D sound by
## how far it is to the side of the ears (relative to the screen width), so this keeps the
## amount of panning and changes only the side. Small changes glide; a jump (another opening,
## or it stepped into view) is not swept across the wall: Heard goes there at once and the
## placing goes vague for a moment.
func _place_heard(delta: float) -> void:
	var settings := SoundSettings.current()
	var at := entity.global_position
	var ears := Acoustics.listener()
	var reading := Acoustics.reading(entity)
	var through: bool = settings.doorway_panning and ears != null and reading.valid and reading.through_opening \
		and not is_catching()
	var target := Vector2.ZERO
	if ears != null:
		target = at - ears.global_position
		if through:
			target = (reading.heard_from - ears.global_position).normalized() * target.length()
	if not _heard_known:
		heard_settle = 1.0
	elif _heard_target.distance_to(target) > Units.to_px(settings.doorway_switch_u):
		heard_settle = 0.0
	else:
		heard_settle = minf(1.0, heard_settle + delta / settings.doorway_settle)
	if not through or ears == null:
		heard.global_position = at       # nothing in the way: exactly where it is, every frame
	elif not _heard_known or heard_settle == 0.0:
		heard.global_position = ears.global_position + target
	else:
		# Glides relative to the ears, so Viv walking does not drag it behind her.
		var offset := heard.global_position - ears.global_position
		heard.global_position = ears.global_position + offset.lerp(target, 1.0 - exp(-delta / settings.doorway_glide))
	_heard_target = target
	_heard_known = true


## Sets what reaches Viv of every position sound that is playing: level, blur and placing.
func _apply_reach() -> void:
	for voice in _voices:
		if voice.playing:
			voice.volume_db = _heard_db(float(voice.get_meta(&"level", SILENT_DB)))
			voice.panning_strength = placing()
	if _talk.playing:
		_talk.volume_db = _heard_db(float(_talk.get_meta(&"level", SILENT_DB)))
		_talk.panning_strength = placing()
	# The knock is heard from where it stands: weakened with distance, never moved to a doorway.
	if _knock.playing:
		_knock.volume_db = _heard_db(float(_knock.get_meta(&"level", SILENT_DB)))
		_knock.panning_strength = _panning
	# Loops: the near and the far player share the level, crossfaded by clarity (equal power).
	var near_db := linear_to_db(maxf(sqrt(heard_clarity), 0.0001))
	var far_db := linear_to_db(maxf(sqrt(1.0 - heard_clarity), 0.0001))
	for pair: Array in [[_breath, _breath_far], [_drag, _drag_far]]:
		var level := float(pair[0].get_meta(&"level", SILENT_DB))
		# Its calm breathing comes and goes (spells and rests); the loop runs on underneath.
		if pair[0] == _breath and _loop_set(_breath) == BREATH_CALM:
			level += _breath_rest_db
		pair[0].volume_db = _heard_db(level + near_db)
		pair[1].volume_db = _heard_db(level + far_db)
		pair[0].panning_strength = placing()
		pair[1].panning_strength = placing()


func _process(delta: float) -> void:
	var settings := SoundSettings.current()
	_tick_reach(delta)
	_tick_awareness(delta)
	var dead: bool = GameState.is_dead
	var shown := entity.is_visible_in_tree()
	if shown:
		breathes_unseen = false
	elif _was_shown:
		stop_all()
	_was_shown = shown
	# It holds its breath while it listens and while it screams: the silence is the tell.
	# The catch has its own sounds, and nothing under them.
	var reacting: bool = _is(&"is_listening") or _is(&"is_screaming") or is_catching()
	var breathes: bool = not dead and (shown or breathes_unseen)
	var wanted_breath := BREATH_HUNT if _state() == "HUNT" else BREATH_CALM
	_drive_loop(_breath, _breath_far, wanted_breath if breathes and not reacting else "", delta, reacting)
	_tick_breath_rhythm(delta, shown)
	# The shroud drags while it moves.
	var active: bool = entity.get(&"active") != false
	var moving: bool = shown and active and not dead and not reacting \
		and entity.velocity.length() > Units.to_px(settings.moving_speed_u)
	_drive_loop(_drag, _drag_far, DRAG if moving else "", delta, reacting)
	_tick_voice(delta, _state(), moving, reacting or dead or not shown or not active)
	if dead and _knock.playing:
		_knock.stop()
	_tick_knock(delta)
	_apply_reach()


## Its calm breathing comes and goes: a spell of breathing (breath_calm_spell), then it sinks
## away over breath_calm_fade and rests (breath_calm_rest), then it comes back over the same
## fade. The loop is never stopped for a rest, only held down, so each spell enters the take at
## a different point. It breathes without rests while it is not shown yet (the tutorial's unseen
## arrival), once it has heard something (near an encounter she must be able to follow it),
## while Viv holds her breath to listen (breath_found_by_listening) and when the rest is (0, 0).
## When any of those ends, a fresh spell begins.
func _tick_breath_rhythm(delta: float, shown: bool) -> void:
	var settings := SoundSettings.current()
	var unseen := breathes_unseen and not shown
	var alert := Dread.awareness_of(entity, self) > Dread.Awareness.PAUSED
	var listening := settings.breath_found_by_listening and Acoustics.focus > 0.0
	var never_rests := settings.breath_calm_rest.y <= 0.0
	var glide := delta * -SILENT_DB / maxf(settings.breath_calm_fade, 0.001)
	if unseen or alert or listening or never_rests:
		_breath_resting = false
		_breath_held = true
		# Listening brings a resting breath in over the fade; otherwise it is simply there.
		_breath_rest_db = move_toward(_breath_rest_db, 0.0, glide) if listening and not (unseen or alert) else 0.0
		return
	if _breath_held:
		_breath_held = false
		_start_breath_spell(false)      # a fresh spell; a level still coming in goes on gliding
	_breath_left -= delta
	if _breath_left <= 0.0:
		_breath_resting = not _breath_resting
		_breath_left = _between(settings.breath_calm_rest if _breath_resting else settings.breath_calm_spell)
	_breath_rest_db = move_toward(_breath_rest_db, SILENT_DB if _breath_resting else 0.0, glide)


## A spell of calm breathing starts now; `at_once`: at its full level at once (it was put
## somewhere by hand, or an encounter was reset), otherwise from where its fade has it.
func _start_breath_spell(at_once := true) -> void:
	_breath_resting = false
	if at_once:
		_breath_rest_db = 0.0
	_breath_left = _between(SoundSettings.current().breath_calm_spell)


## True while its calm breathing rests (sinking away, or away).
func breath_resting() -> bool:
	return _breath_resting


## How far its calm breathing is held down by its rhythm right now (0 in a spell, down to
## SILENT_DB in a rest), and how long this spell or rest still lasts (debug read-outs, tests).
func breath_rest_db() -> float:
	return _breath_rest_db


func breath_left() -> float:
	return _breath_left


## True while something keeps its calm breathing going with no rests (not shown yet, it has
## heard something, she holds her breath to listen, or rests are off).
func breath_held() -> bool:
	return _breath_held


## The idle voice. `silent`: it is listening, screaming, catching, hidden, inactive or dead.
func _tick_voice(delta: float, state: String, moving: bool, silent: bool) -> void:
	var settings := SoundSettings.current()
	if _talk.playing and _talk_fade > 0.0:
		_talk.set_meta(&"level", float(_talk.get_meta(&"level", SILENT_DB)) - _talk_fade * delta)
		if float(_talk.get_meta(&"level")) <= SILENT_DB:
			_talk.stop()
	if silent or state == "HUNT":
		return
	var searching := state == "SEARCH" or state == "INVESTIGATE"
	_still_for = 0.0 if moving else _still_for + delta
	_talk_wait -= delta
	if _talk.playing:
		# A patrol pause: the talk trails off. A fade, never the hard cut of listening.
		if not searching and _talk_fade == 0.0 and _still_for >= settings.talk_pause_grace:
			_talk_fade = -SILENT_DB / maxf(settings.talk_pause_fade, 0.001)
	elif _talk_wait <= 0.0 and (moving or searching):
		_say(searching)
	if not searching:
		return
	# Sniffing as it scuttles: short runs at a steady pace.
	if _sniffs_left > 0:
		_sniff_next -= delta
		if _sniff_next <= 0.0:
			play_set(SNIFF)
			_sniffs_left -= 1
			_sniff_next += _sniff_pace
	elif _sniff_run_wait >= 0.0:
		_sniff_run_wait -= delta
		if _sniff_run_wait <= 0.0 and moving and _sniff_wait < 0.0:
			_sniffs_left = randi_range(settings.sniff_run_count.x, settings.sniff_run_count.y)
			_sniff_pace = _between(settings.sniff_run_pace)
			_sniff_next = 0.0
			_sniff_run_wait = _between(settings.sniff_run_interval)


## Its knock on a door, behind the switch (entity_knocks_enabled). It knocks once in a patrol
## pause, when all of this holds: it is unaware and on its patrol, has been calm for
## entity_knock_first and has stood still for entity_knock_still; the middle of a doorway is
## within entity_knock_door_u; Viv hears it across her room or a room away (ring 2 or 1: never on
## top of her, and not when nobody would hear it); its last knock was entity_knock_gap ago; and
## the knock set has a file. It reads what the entity is doing and changes none of it.
func _tick_knock(delta: float) -> void:
	var settings := SoundSettings.current()
	if not settings.entity_knocks_enabled:
		_end_pause(true)          # switched on later, it is calm only from then on
		return
	var awareness := Dread.awareness_of(entity, self)
	var calm := awareness <= Dread.Awareness.PAUSED and _state() == "PATROL"
	_calm_for = _calm_for + delta if calm else 0.0
	if not calm or awareness != Dread.Awareness.PAUSED or not is_audible() or GameState.is_dead:
		_end_pause()
		return
	_paused_for += delta
	if _knocked or _paused_for < settings.entity_knock_still or _calm_for < settings.entity_knock_first \
			or _clock - _last_knock < settings.entity_knock_gap or heard_ring < 1 or heard_ring > 2 \
			or not SoundLibrary.has_set(KNOCK):
		return
	if not _knock_looked:
		_knock_looked = true
		_knock_door = _door_near()
	if is_instance_valid(_knock_door):
		_play_knock(_knock_door)


## A pause is over (it moved, or it is no longer calm). `encounter`: everything starts over,
## also the time it has been calm.
func _end_pause(encounter := false) -> void:
	_paused_for = 0.0
	_knock_looked = false
	_knock_door = null
	_knocked = false
	if encounter:
		_calm_for = 0.0


## The door whose doorway is nearest to it, within entity_knock_door_u (null: none). Looked up
## once per pause.
func _door_near() -> Door:
	var reach := Units.to_px(SoundSettings.current().entity_knock_door_u)
	var nearest: Door = null
	for node in get_tree().root.find_children("*", "Door", true, false):
		var door := node as Door
		if door == null or not door.is_visible_in_tree():
			continue
		var distance := door.get_noise_origin().distance_to(entity.global_position)
		if distance <= reach:
			reach = distance
			nearest = door
	return nearest


## One knock on `door`: a file of the knock set, from where it stands, on the Entity bus, at the
## set's level plus entity_knock_db, less what a sound of where it is loses on the way to Viv.
func _play_knock(door: Door) -> AudioStreamPlayer2D:
	var settings := SoundSettings.current()
	_knocked = true
	var stream := SoundLibrary.pick(KNOCK)
	# Never the house's knock, nor any file from outside its own folder.
	if stream == null or not stream.resource_path.begins_with(KNOCK_FOLDER):
		push_warning("[EntityAudio] a knock must come from %s, not %s" % [KNOCK_FOLDER, stream.resource_path if stream != null else "nothing"])
		return null
	_last_knock = _clock
	var variation: float = settings.set_pitch_range
	_knock.stream = stream
	_knock.bus = AudioBus.ENTITY
	_knock.pitch_scale = randf_range(1.0 - variation, 1.0 + variation)
	_knock.set_meta(&"level", SoundLibrary.gain_db(KNOCK) + settings.entity_knock_db)
	_knock.volume_db = _heard_db(float(_knock.get_meta(&"level")))
	_knock.panning_strength = _panning
	_knock.play()
	plays[KNOCK] = int(plays.get(KNOCK, 0)) + 1
	last_set = KNOCK
	last_knock = {"stream": stream, "door": door, "at": _knock.global_position, "level_db": _knock.volume_db,
		"ring": heard_ring, "clock": _clock}
	played.emit(KNOCK, _knock)
	return _knock


## One mumbled phrase, never the one said last. Searching, it is lower and slower.
func _say(searching: bool) -> void:
	var settings := SoundSettings.current()
	var interval := _between(settings.talk_interval_search if searching else settings.talk_interval_patrol)
	var stream := SoundLibrary.pick(MUMBLE)
	if stream == null or not _gets_through(MUMBLE):
		# Nothing to say, or the phrase was lost on the way to Viv: the next one waits its turn.
		_talk_wait = interval
		return
	var wander: float = settings.set_pitch_range * (0.5 if searching else 1.0)
	_talk.stream = stream
	_talk.pitch_scale = (settings.talk_pitch_search if searching else 1.0) * randf_range(1.0 - wander, 1.0 + wander)
	_talk.bus = _one_shot_bus()
	_talk.set_meta(&"level", SoundLibrary.gain_db(MUMBLE) + randf_range(-settings.set_volume_range_db, settings.set_volume_range_db))
	_talk.volume_db = _heard_db(float(_talk.get_meta(&"level")))
	_talk.panning_strength = placing()
	_talk_fade = 0.0
	_talk.play()
	# The next phrase waits its interval, and at least a breath after this one has ended.
	_talk_wait = maxf(interval, stream.get_length() / _talk.pitch_scale + settings.talk_min_gap)
	plays[MUMBLE] = int(plays.get(MUMBLE, 0)) + 1
	last_talk = {"stream": stream, "pitch": _talk.pitch_scale, "state": "SEARCH" if searching else "PATROL"}
	played.emit(MUMBLE, _talk)


func _between(span: Vector2) -> float:
	return randf_range(span.x, span.y)


## Fades a loop toward the set it should be playing ("" = silence). A change of set waits for
## the old one to fade out; `at_once` stops it with no fade. `far` is its twin on the dulled
## bus: it plays the same take in step. The level kept here is the one next to Viv; what
## reaches her is set in _apply_reach().
func _drive_loop(player: AudioStreamPlayer2D, far: AudioStreamPlayer2D, set_id: String, delta: float, at_once := false) -> void:
	var step := delta * -SILENT_DB / maxf(SoundSettings.current().loop_fade, 0.001)
	var level := float(player.get_meta(&"level", SILENT_DB))
	if player.playing and _loop_set(player) != set_id:
		level = SILENT_DB if at_once else move_toward(level, SILENT_DB, step)
		player.set_meta(&"level", level)
		if level > SILENT_DB:
			return
		player.stop()
		far.stop()
	if set_id == "":
		return
	if not player.playing:
		player.set_meta(&"set", set_id)
		if SoundLibrary.stream(set_id) == null:       # empty set: silent, warned once
			return
		var variations := SoundLibrary.files(set_id)
		player.stream = variations[randi() % variations.size()]       # loops: one take, going round
		far.stream = player.stream
		level = SILENT_DB
		player.volume_db = GONE_DB
		far.volume_db = GONE_DB
		player.play()
		far.play()
	player.set_meta(&"level", move_toward(level, SoundLibrary.gain_db(set_id), step))


func _loop_set(player: AudioStreamPlayer2D) -> String:
	return String(player.get_meta(&"set", ""))


func _is(method: StringName) -> bool:
	return entity.has_method(method) and bool(entity.call(method))


func _state() -> String:
	return String(entity.call(&"get_state_name")) if entity.has_method(&"get_state_name") else ""
