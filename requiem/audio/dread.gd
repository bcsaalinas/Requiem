extends Node
## The mood of the house: how much danger Viv is in, as far as the entity knows.
##
## `awareness` is what the entity knows right now (with several entities, the most alert one).
## `threat` is the same thing as one number from 0 to 1 for the mix to follow. It rises
## quickly, falls slowly and lags a little behind the facts, so it feels like a mood and not
## like a switch.
##
## Both only say what it knows. Neither reads how far away it is: a quiet house never gives
## its position away.
##
## `presence` is a second mood: how near its sound is, whatever it knows (1 = on top of her,
## 0 = gone). This script does not work it out. Each entity's own sound reports it
## (EntityAudio, from Acoustics), and here it only arrives late and moves slowly, so it is a
## feeling in the room and never a bearing. The music does not follow it.
##
## Entities report themselves here (EntityAudio does it for every entity that has one).
## Nothing in this script makes a sound, and nothing in it makes noise the entity can hear.

## What the entity knows, from least to most alert.
##   UNAWARE    walking its patrol (or not there at all)
##   PAUSED     standing still on its patrol
##   HEARD      it heard something and stands listening
##   SEARCHING  it lost the trail and looks for it
##   HUNTING    it knows, from the moment it stops listening (the scream) on
##   CAUGHT     it has her: the catch, and the game over screen after it
enum Awareness { UNAWARE, PAUSED, HEARD, SEARCHING, HUNTING, CAUGHT }

const AWARENESS_NAMES := ["UNAWARE", "PAUSED", "HEARD", "SEARCHING", "HUNTING", "CAUGHT"]

## What it knows changed. Sent at once, with no lag: the music cuts on this.
signal awareness_changed(previous: int, current: int)
## The mood moved (0..1). Sent every frame while it is moving.
signal threat_changed(value: float)
## One of its awareness cues just played: heard, heard_again, inhale, scream, foot_slam,
## lost, lost_sniff, stand_down (EntityAudio.awareness_played).
signal cue_played(moment: StringName)
## The second mood moved (0..1). Sent every frame while it is moving.
signal presence_changed(value: float)

var awareness: int = Awareness.UNAWARE
var threat := 0.0
## instance id -> { entity: WeakRef, audio: WeakRef or null }
var _watched := {}
var _target := 0.0
var _lag := 0.0
var _settle := false
var presence := 0.0
## instance id -> { source: WeakRef, value: float }: what each entity's sound last reported.
var _reports := {}
var _presence_goal := 0.0
var _presence_wait := 0.0


func _ready() -> void:
	GameState.state_reset.connect(_on_state_reset)


## Starts following an entity. `audio` is its EntityAudio, when it has one: its awareness cues
## are passed on (cue_played), and it knows when the entity is catching. Asking twice is fine.
func watch(entity: Node2D, audio: Node = null) -> void:
	if entity == null:
		return
	var id := entity.get_instance_id()
	if not _watched.has(id):
		_watched[id] = {"entity": weakref(entity), "audio": null}
	if audio != null and _watched[id].audio == null:
		_watched[id].audio = weakref(audio)
		if audio.has_signal(&"awareness_played"):
			audio.connect(&"awareness_played", _on_awareness_played)


## What one entity knows right now.
func awareness_of(entity: Node2D, audio: Node = null) -> int:
	# An entity that is not shown knows nothing, whatever state it was left in.
	if not entity.is_inside_tree() or not entity.is_visible_in_tree():
		return Awareness.UNAWARE
	if audio != null and audio.has_method(&"is_catching") and audio.call(&"is_catching"):
		return Awareness.CAUGHT
	if entity.has_method(&"is_listening") and entity.call(&"is_listening"):
		return Awareness.HEARD
	match int(entity.get(&"current_state")):
		EntityAudio.HUNT:
			return Awareness.HUNTING
		EntityAudio.SEARCH:
			return Awareness.SEARCHING
	# On patrol. (INVESTIGATE is never entered; if it were, it would count as patrol too.)
	var standing: bool = entity.get(&"active") != false and entity is CharacterBody2D \
		and (entity as CharacterBody2D).velocity.length() <= Units.to_px(SoundSettings.current().moving_speed_u)
	return Awareness.PAUSED if standing else Awareness.UNAWARE


## An entity's sound says how near it is to Viv's ears right now (0..1). The strongest report
## counts. Report 0 when it can no longer be heard.
func report_presence(source: Object, value: float) -> void:
	if source == null:
		return
	var id := source.get_instance_id()
	if not _reports.has(id):
		_reports[id] = {"source": weakref(source), "value": 0.0}
	_reports[id].value = clampf(value, 0.0, 1.0)


## The strongest report right now, with no lag (for tests and read-outs).
func reported_presence() -> float:
	var strongest := 0.0
	for id in _reports.keys():
		if (_reports[id].source as WeakRef).get_ref() == null:
			_reports.erase(id)
			continue
		strongest = maxf(strongest, _reports[id].value)
	return strongest


## The threat value each awareness stands for (audio/sound_settings.tres).
func threat_for(level: int) -> float:
	var settings := SoundSettings.current()
	match level:
		Awareness.PAUSED: return settings.threat_paused
		Awareness.HEARD: return settings.threat_heard
		Awareness.SEARCHING: return settings.threat_searching
		Awareness.HUNTING, Awareness.CAUGHT: return settings.threat_hunting
	return settings.threat_unaware


func awareness_name() -> String:
	return AWARENESS_NAMES[awareness]


func _process(delta: float) -> void:
	var settings := SoundSettings.current()
	_tick_presence(delta, settings)
	var now := _read()
	if now != awareness:
		var previous := awareness
		awareness = now
		_target = threat_for(now)
		if now == Awareness.HEARD:
			# Hearing something never calms the mood (it may have been searching already).
			_target = maxf(_target, threat)
		_lag = randf_range(settings.threat_lag.x, settings.threat_lag.y)
		awareness_changed.emit(previous, now)
	if _settle:
		# A new attempt starts clean: no mood left over from the last one.
		_settle = false
		_lag = 0.0
		_target = threat_for(awareness)
		if threat != _target:
			threat = _target
			threat_changed.emit(threat)
		return
	if _lag > 0.0:
		_lag -= delta
		return
	if threat == _target:
		return
	var time: float = settings.threat_rise_time if _target > threat else settings.threat_fall_time
	threat = move_toward(threat, _target, delta / maxf(time, 0.001))
	threat_changed.emit(threat)


## Presence looks at the reports only now and then (the lag), and then drifts to what it saw.
func _tick_presence(delta: float, settings: SoundSettings) -> void:
	_presence_wait -= delta
	if _settle:
		# A new attempt starts clean.
		_presence_wait = 0.0
		_presence_goal = reported_presence()
		if presence != _presence_goal:
			presence = _presence_goal
			presence_changed.emit(presence)
	if _presence_wait <= 0.0:
		_presence_goal = reported_presence()
		_presence_wait = randf_range(settings.presence_lag.x, settings.presence_lag.y)
	if presence != _presence_goal:
		presence = move_toward(presence, _presence_goal, delta / maxf(settings.presence_time, 0.001))
		presence_changed.emit(presence)


## The most alert thing any watched entity knows.
func _read() -> int:
	if GameState.is_dead:
		return Awareness.CAUGHT
	var most: int = Awareness.UNAWARE
	for id in _watched.keys():
		var entity := (_watched[id].entity as WeakRef).get_ref() as Node2D
		if entity == null:
			_watched.erase(id)
			continue
		var audio: Node = (_watched[id].audio as WeakRef).get_ref() if _watched[id].audio != null else null
		most = maxi(most, awareness_of(entity, audio))
	return most


func _on_awareness_played(moment: StringName, _set_id: String, _stream: AudioStream, _level_db: float) -> void:
	cue_played.emit(moment)


func _on_state_reset() -> void:
	_settle = true
