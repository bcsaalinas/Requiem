extends Node
## The house voice: the house makes its own quiet, ambiguous sounds, so that she feels unsafe
## when she is safe, and never while she is in real danger.
##
## Three families:
##   settle   frequent, very quiet wood and pipe sounds (assets/audio/house/settle);
##   effects  a knock, a door creak, something falling, a chair dragged: rare, far apart;
##   nothing  now and then, instead of an effect, the ambience thins for a few seconds.
##
## Every sound comes from a room she is not in, on the World bus, quietly, with a soft start.
## None may play unless the entity is unaware, out of earshot of the room (outside ring 2), no
## awareness cue has sounded lately, and she is not praying; effects are also kept far apart
## and never repeat. gate() says in words why it is silent at any moment.
##
## One loud thing she does may be answered by a single knock a second later (answer()).
##
## A level says where its rooms are with enter() and leaves with leave(); while it tells its
## own part of the story it sets story_holds, and may use play() and spot_away() for it.
##
## It never plays a file of the entity, never the "behind the wall" drag, and never makes a
## noise the entity can hear. Every number is in audio/sound_settings.tres (House).

const SETTLE := "house/settle"
const EFFECTS := "house/effects"
## Name of the request made to MixDirector while the ambience thins.
const NOTHING_MIX := &"house_nothing"
const GROUP := &"house_voice"
## Files the house never plays: anything of the entity.
const ENTITY_FILES := "res://assets/audio/entity/"
## And, from the moment an entity is out in the world, the dragging behind the wall: by then
## that sound would be a lie about where it is.
const BEHIND_WALL := "behind_wall"
const HISTORY := 12

## Something sounded: family is &"settle", &"effect", &"answer" or &"story" (a level's own).
signal sounded(family: StringName, stream: AudioStream, at: Vector2, level_db: float, caption: String)
## The ambience thinned instead of an effect.
signal thinned()

## While true the level is telling its own part: the house voice keeps quiet by itself.
var story_holds := false
## The last sounds it made by itself, newest last: { family, file, at, level_db, gate }.
## `gate` is what gate() said as it played: always "" unless something is wrong.
var history: Array[Dictionary] = []
## How many of its own sounds played while its gates were closed. Must stay 0.
var violations := 0

## room name -> Array[Vector2] of places a sound can come from (world px).
var _rooms := {}
var _current_room := Callable()
var _listener: Node2D
var _effect_wait := 0.0
var _settle_wait := 0.0
var _open_wait := 0.0
var _answer_wait := -1.0
var _since_answer := INF
var _since_cue := INF
var _nothing_left := -1.0
var _was_open := false
var _last_effect := ""
var _last_spot := Vector2.INF


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Dread.cue_played.connect(func(_moment: StringName) -> void: _since_cue = 0.0)


## A level's house: its rooms and the places in them a sound can come from (world px), a
## callable that names the room she is in ("" when unknown), and whoever is listening.
func enter(rooms: Dictionary, current_room: Callable, listener: Node2D) -> void:
	var settings := SoundSettings.current()
	_rooms = rooms.duplicate(true)
	_current_room = current_room
	_listener = listener
	_effect_wait = randf_range(settings.house_effect_gap.x, settings.house_effect_gap.y)
	_settle_wait = randf_range(settings.house_settle_gap.x, settings.house_settle_gap.y)
	_open_wait = 0.0
	_answer_wait = -1.0
	_since_answer = INF
	_was_open = false


## She left the house: everything it was sounding stops.
func leave() -> void:
	_rooms.clear()
	_current_room = Callable()
	_listener = null
	_answer_wait = -1.0
	story_holds = false
	_end_nothing(0.0)
	for voice in get_children():
		voice.queue_free()


func in_a_house() -> bool:
	return not _rooms.is_empty()


## Why the house is keeping quiet right now, in words ("" when it may speak).
func gate() -> String:
	var settings := SoundSettings.current()
	if not in_a_house():
		return "no house here"
	if story_holds:
		return "the level is telling its own part"
	if GameState.is_dead:
		return "she is dead"
	if Dread.awareness > Dread.Awareness.PAUSED:
		return "it is alert (%s)" % String(Dread.Awareness.keys()[Dread.awareness]).to_lower()
	var ring: int = Acoustics.nearest_ring()
	if ring >= 2:
		return "it is near (ring %d)" % ring
	if _since_cue < settings.house_after_cue:
		return "an awareness cue played %.0f s ago (%.0f s of quiet first)" % [_since_cue, settings.house_after_cue]
	if GameState.is_praying:
		return "she is praying"
	return ""


## The same, for the rare effects: they also wait their turn.
func effect_gate() -> String:
	var held := gate()
	if held != "":
		return held
	if _open_wait > 0.0:
		return "it only just became safe (%.0f s more)" % _open_wait
	if _effect_wait > 0.0:
		return "the next effect is %.0f s away (they are kept far apart)" % _effect_wait
	return ""


## One line for a read-out.
func status() -> String:
	var held := effect_gate()
	return "silent: %s" % held if gate() != "" else ("settling · %s" % held if held != "" else "may speak")


## Brings the next effect forward to now (auditioning). The gates still apply.
func hurry() -> void:
	_effect_wait = 0.0
	_open_wait = 0.0


## A place in a room she is not in (and not the place used last). Vector2.INF with no house.
func spot_away() -> Vector2:
	var here := String(_current_room.call()) if _current_room.is_valid() else ""
	var far: float = Units.to_px(SoundSettings.current().house_min_distance_u)
	var choices: Array[Vector2] = []
	for room: String in _rooms:
		if room == here:
			continue
		for spot: Vector2 in _rooms[room]:
			# With no room known, distance decides: never right beside her.
			if here == "" and _listener != null and spot.distance_to(_listener.global_position) < far:
				continue
			if spot != _last_spot:
				choices.append(spot)
	if choices.is_empty():
		return Vector2.INF
	_last_spot = choices[randi() % choices.size()]
	return _last_spot


## How loud a file may play so that it is no louder than the house is allowed to be, in dB
## (0 or less): `lufs` is how loud the file itself is.
static func level_for(lufs: float) -> float:
	return minf(0.0, SoundSettings.current().house_max_lufs - lufs)


## Plays one sound of the house from a place, on World, with a soft start. Returns the player
## (it frees itself when done), or null for a file this voice refuses. `parent`: the node that
## owns the sound (a level, for its own story); left out, the house voice keeps it.
func play(stream: AudioStream, at: Vector2, level_db: float, pitch := 1.0, parent: Node = null) -> AudioStreamPlayer2D:
	if stream == null or not allowed(stream):
		return null
	var settings := SoundSettings.current()
	var voice := AudioStreamPlayer2D.new()
	voice.bus = AudioBus.WORLD
	voice.stream = stream
	voice.pitch_scale = pitch
	voice.volume_db = level_db + settings.house_attack_from_db
	voice.add_to_group(GROUP)
	(parent if parent != null else self).add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	voice.play()
	# A soft start: never a hard edge out of the quiet.
	voice.create_tween().tween_property(voice, "volume_db", level_db, settings.house_attack)
	return voice


## False for a file the house may not play: any file of the entity, ever; and the dragging
## behind the wall once an entity is out in the world.
func allowed(stream: AudioStream) -> bool:
	if stream.resource_path.begins_with(ENTITY_FILES):
		return false
	return not (stream.resource_path.contains(BEHIND_WALL) and Dread.entity_about())


## Something she did was loud: the house may answer with a single knock, a second later.
## Returns true if an answer is on its way.
func answer() -> bool:
	if gate() != "" or _answer_wait >= 0.0 or _since_answer < SoundSettings.current().house_answer_gap:
		return false
	_answer_wait = SoundSettings.current().house_answer_delay
	return true


## Every effect the house can make: { file, lufs, caption }. The ones the tutorial always
## used (sound_settings.tres), then whatever is in assets/audio/house/effects.
func effects() -> Array[Dictionary]:
	var settings := SoundSettings.current()
	var found: Array[Dictionary] = []
	for entry: Dictionary in settings.house_effects:
		found.append(entry)
	for stream in SoundLibrary.files(EFFECTS):
		found.append({"file": stream.resource_path, "lufs": settings.house_set_lufs, "caption": settings.house_effect_caption})
	return found


func _process(delta: float) -> void:
	_since_cue += delta
	_since_answer += delta
	if _nothing_left >= 0.0:
		_nothing_left -= delta
		if _nothing_left < 0.0 or gate() != "":
			_end_nothing(SoundSettings.current().house_nothing_fade)
	if not in_a_house():
		return
	var settings := SoundSettings.current()
	var open := gate() == ""
	if open and not _was_open:
		# It has only just become safe: the house does not speak the moment the danger turns away.
		_open_wait = randf_range(settings.house_gate_settle.x, settings.house_gate_settle.y)
	_was_open = open
	if _answer_wait >= 0.0:
		_answer_wait -= delta
		if _answer_wait < 0.0:
			_answer_wait = -1.0
			if open:
				_knock()
	if not open:
		return
	_open_wait = maxf(_open_wait - delta, 0.0)
	_effect_wait = maxf(_effect_wait - delta, 0.0)
	_settle_wait -= delta
	if _settle_wait <= 0.0:
		_settle_wait = randf_range(settings.house_settle_gap.x, settings.house_settle_gap.y)
		_settle()
	if _effect_wait <= 0.0 and _open_wait <= 0.0:
		_effect_wait = randf_range(settings.house_effect_gap.x, settings.house_effect_gap.y)
		if randi() % maxi(settings.house_nothing_one_in, 1) == 0:
			_nothing()
		else:
			_effect()


## A small sound of the house itself. Silent while the folder is empty.
func _settle() -> void:
	var stream := SoundLibrary.pick(SETTLE) if not SoundLibrary.files(SETTLE).is_empty() else null
	var at := spot_away()
	if stream == null or at == Vector2.INF:
		return
	var settings := SoundSettings.current()
	var level: float = level_for(settings.house_set_lufs) + settings.house_settle_db
	_sound(&"settle", stream, at, level, "")


## One of the rare effects, never the one before.
func _effect() -> void:
	var choices := effects().filter(func(entry: Dictionary) -> bool: return entry.file != _last_effect)
	if choices.is_empty():
		return
	_play_entry(&"effect", choices[randi() % choices.size()])


## The answer: one knock from another room.
func _knock() -> void:
	var settings := SoundSettings.current()
	for entry: Dictionary in settings.house_effects:
		if entry.file == settings.house_knock:
			_since_answer = 0.0
			_play_entry(&"answer", entry)
			return


func _play_entry(family: StringName, entry: Dictionary) -> void:
	var at := spot_away()
	var stream := load(entry.file) as AudioStream if ResourceLoader.exists(entry.file) else null
	if stream == null or at == Vector2.INF:
		return
	_last_effect = entry.file
	_sound(family, stream, at, level_for(float(entry.lufs)), String(entry.get("caption", "")))


func _sound(family: StringName, stream: AudioStream, at: Vector2, level_db: float, caption: String) -> void:
	var held := gate()
	var variation: float = SoundSettings.current().set_pitch_range
	if play(stream, at, level_db, randf_range(1.0 - variation, 1.0 + variation)) == null:
		return
	if held != "":
		violations += 1
		push_error("[HouseVoice] %s played while its gates were closed: %s" % [stream.resource_path, held])
	history.append({"family": family, "file": stream.resource_path, "at": at, "level_db": level_db, "gate": held})
	if history.size() > HISTORY:
		history.pop_front()
	sounded.emit(family, stream, at, level_db, caption)


## Nothing: the ambience thins for a few seconds and returns.
func _nothing() -> void:
	var settings := SoundSettings.current()
	_nothing_left = settings.house_nothing_time
	# Below wherever the mood of the house already has the ambience, so it is always heard to go.
	var level: float = settings.house_nothing_db + settings.threat_world_db * MixDirector.recede()
	MixDirector.duck(NOTHING_MIX, MixDirector.Priority.HOUSE, {AudioBus.AMBIENCE: level}, settings.house_nothing_fade)
	history.append({"family": &"nothing", "file": "", "at": Vector2.INF, "level_db": level, "gate": gate()})
	if history.size() > HISTORY:
		history.pop_front()
	thinned.emit()


func _end_nothing(fade: float) -> void:
	_nothing_left = -1.0
	MixDirector.release(NOTHING_MIX, fade)
