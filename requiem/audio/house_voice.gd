extends Node
## The house voice: the house makes its own quiet, ambiguous sounds, so that she feels unsafe
## when she is safe, and never while she is in real danger.
##
## Three families:
##   settle   frequent, very quiet wood and pipe sounds (assets/audio/house/settle);
##   effects  a knock, a door creak, something falling, a chair dragged: rare, far apart;
##   nothing  now and then, instead of an effect, the ambience thins for a few seconds.
##
## The knock is its signature: most effects (house_knock_share) are a knock, picked from
## knocks() (house_knock and assets/audio/house/knock), at the loudest a house sound may be
## (knock_level_for()), reported as &"knock". Never the same knock file twice running when
## there are several; with one file, never three effects in a row that are that file.
##
## Every sound comes from a room she is not in, on the World bus, quietly, with a soft start.
## None may play unless the entity is unaware, out of earshot of the room (outside ring 2), no
## awareness cue has sounded lately, and she is not praying; effects are also kept far apart
## and never repeat. gate() says in words why it is silent at any moment.
##
## One loud thing she does may be answered by a single knock a second later (answer()). If she
## keeps being loud, each answer comes a little closer (never from her room) and may be a little
## louder, up to house_escalate_steps; a quiet minute puts it back.
##
## The aftermath: after one of the rare effects, a door the level gave it, in a room she is not
## in, may later be found ajar, with a creak she hears. The door is only drawn a little open:
## it stays shut for bodies, light and the entity, and the entity does not hear the creak. Once
## per run (begin_run()).
##
## A level says where its rooms are with enter() and leaves with leave(); while it tells its
## own part of the story it sets story_holds, and may use play() and spot_away() for it.
##
## It never plays a file of the entity, never the "behind the wall" drag, and never makes a
## noise the entity can hear. Every number is in audio/sound_settings.tres (House).

const SETTLE := "house/settle"
const EFFECTS := "house/effects"
## The house's own knocks, besides house_knock: any file dropped here is a knock.
const KNOCK := "house/knock"
## With a single knock file, at most this many effects in a row may be that file.
const KNOCKS_IN_A_ROW := 2
## Name of the request made to MixDirector while the ambience thins.
const NOTHING_MIX := &"house_nothing"
const GROUP := &"house_voice"
## Files the house never plays: anything of the entity.
const ENTITY_FILES := "res://assets/audio/entity/"
## And, from the moment an entity is out in the world, the dragging behind the wall: by then
## that sound would be a lie about where it is.
const BEHIND_WALL := "behind_wall"
const HISTORY := 12

## Something sounded: family is &"settle", &"effect", &"knock" (an effect that is a knock),
## &"answer", &"aftermath" (a door found ajar) or &"story" (a level's own).
signal sounded(family: StringName, stream: AudioStream, at: Vector2, level_db: float, caption: String)
## The ambience thinned instead of an effect.
signal thinned()
## A door was found ajar (the aftermath of an effect). Its leaf only: it is still shut.
signal door_left_ajar(door: Door)

## While true the level is telling its own part: the house voice keeps quiet by itself.
var story_holds := false
## The last sounds it made by itself, newest last: { family, file, at, level_db, gate }.
## `gate` is what gate() said as it played: always "" unless something is wrong.
var history: Array[Dictionary] = []
## How many of its own sounds played while its gates were closed. Must stay 0.
var violations := 0
## How much closer the answer has come: 0 (as far as any house sound) to house_escalate_steps.
var answer_step := 0
## True once a door was left ajar in this run (a retry after death does not clear it).
var ajar_done := false

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
## The knock file played last as an effect, and how many effects in a row were that file.
var _last_knock := ""
var _knocks_running := 0
## The other effect (not a knock) played last.
var _last_other := ""
## True when the next effect is to be a knock (auditioning: hurry_knock()).
var _knock_next := false
var _last_spot := Vector2.INF
## Seconds since she last did something loud (since answer() was last called, answered or not).
var _since_loud := INF
## Seconds since the last answer that was accepted.
var _since_accepted := INF
## True when the answer on its way raised the step.
var _answer_raised := false
## How far from her the last answer came (px); INF when forgotten.
var _answer_distance := INF
## The doors the level gave: any may be left ajar after an effect.
var _doors: Array[Door] = []
## Seconds until a door may be found ajar (-1: nothing pending), and where the effect sounded.
var _ajar_wait := -1.0
var _ajar_from := Vector2.INF
## The swing the house last drew on the door it is leaving ajar (NAN: it is drawing none).
var _ajar_leaf := NAN


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Dread.cue_played.connect(func(_moment: StringName) -> void: _since_cue = 0.0)
	GameState.state_reset.connect(_on_state_reset)


## A level's house: its rooms and the places in them a sound can come from (world px), a
## callable that names the room she is in ("" when unknown), whoever is listening, and the
## doors that may be found ajar (none: no door ever is).
func enter(rooms: Dictionary, current_room: Callable, listener: Node2D, doors: Array = []) -> void:
	var settings := SoundSettings.current()
	_rooms = rooms.duplicate(true)
	_current_room = current_room
	_listener = listener
	_doors.clear()
	for door in doors:
		if door is Door:
			_doors.append(door)
	_ajar_wait = -1.0
	_reset_escalation()
	_effect_wait = randf_range(settings.house_effect_gap.x, settings.house_effect_gap.y)
	_settle_wait = randf_range(settings.house_settle_gap.x, settings.house_settle_gap.y)
	_open_wait = 0.0
	_answer_wait = -1.0
	_since_answer = INF
	_was_open = false
	_knock_next = false


## She left the house: everything it was sounding stops.
func leave() -> void:
	_rooms.clear()
	_current_room = Callable()
	_listener = null
	_doors.clear()
	_ajar_wait = -1.0
	_reset_escalation()
	_answer_wait = -1.0
	_knock_next = false
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


## A new run of the game: a door may be left ajar again. Not called on a retry after death.
func begin_run() -> void:
	ajar_done = false
	_ajar_wait = -1.0


## One line for a read-out.
func status() -> String:
	var held := effect_gate()
	var line := "silent: %s" % held if gate() != "" else ("settling · %s" % held if held != "" else "may speak")
	if in_a_house() and gate() == "":
		line += " · " + knock_text()
	if answer_step > 0:
		var settings := SoundSettings.current()
		line += " · answers: step %d of %d (quiet resets it in %.0f s)" % [answer_step, settings.house_escalate_steps,
			maxf(settings.house_escalate_reset - _since_loud, 0.0)]
	return line


## Brings the next effect forward to now (auditioning). The gates still apply.
func hurry() -> void:
	_effect_wait = 0.0
	_open_wait = 0.0


## Brings a knock forward to now (auditioning): the next effect is a knock, not a "nothing" and
## not another effect, unless that would be the same single knock file three times in a row.
## The gates still apply.
func hurry_knock() -> void:
	_knock_next = true
	hurry()


## What the next effect can be, in words, for a read-out.
func knock_text() -> String:
	var settings := SoundSettings.current()
	var count := knocks().size()
	var files := "%d knock file%s" % [count, "" if count == 1 else "s"]
	if count == 0:
		return "no knock file"
	if settings.house_knock_share <= 0.0 and not _knock_next:
		return "knocks: one effect among the others, %s" % files
	if count == 1 and _knocks_running >= KNOCKS_IN_A_ROW:
		return "next effect not a knock (%d knocks in a row), %s" % [_knocks_running, files]
	if _knock_next:
		return "next effect a knock, %s" % files
	return "knocks %.0f%% of effects, %s" % [settings.house_knock_share * 100.0, files]


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


## How loud a knock file plays (dB): brought to the loudest the house may be (house_max_lufs),
## turned down if it is louder, and turned up if it is quieter, but by no more than
## house_knock_max_gain_db. `lufs` is how loud the file itself is.
static func knock_level_for(lufs: float) -> float:
	var settings := SoundSettings.current()
	return minf(settings.house_max_lufs - lufs, settings.house_knock_max_gain_db)


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
## Returns true if an answer is on its way. Asked again soon after an answer, the next one
## comes closer; every call, answered or not, restarts the quiet that puts it back.
func answer() -> bool:
	var settings := SoundSettings.current()
	_settle_quiet()
	_since_loud = 0.0
	if gate() != "" or _answer_wait >= 0.0 or _since_answer < settings.house_answer_gap:
		return false
	_answer_raised = _since_accepted < settings.house_escalate_window and answer_step < settings.house_escalate_steps
	if _answer_raised:
		answer_step += 1
	_since_accepted = 0.0
	_answer_wait = settings.house_answer_delay
	return true


## The loudest the answer may be at its step (LUFS): house_max_lufs at step 0, rising
## evenly to house_escalate_max_lufs at the top step.
func answer_cap() -> float:
	var settings := SoundSettings.current()
	var steps := maxi(settings.house_escalate_steps, 1)
	return lerpf(settings.house_max_lufs, settings.house_escalate_max_lufs, clampf(float(answer_step) / steps, 0.0, 1.0))


## How loud the answering file may play (dB, 0 or less): turned down to answer_cap(), never up.
func answer_level_for(lufs: float) -> float:
	return minf(0.0, answer_cap() - lufs)


## Where the next answer may come from: places in rooms she is not in (with no room known,
## not right beside her), never nearer than house_answer_min_u.
func answer_places() -> Array[Vector2]:
	var settings := SoundSettings.current()
	var here := String(_current_room.call()) if _current_room.is_valid() else ""
	var far: float = Units.to_px(settings.house_min_distance_u)
	var least: float = Units.to_px(settings.house_answer_min_u)
	var places: Array[Vector2] = []
	for room: String in _rooms:
		if room == here:
			continue
		for spot: Vector2 in _rooms[room]:
			if is_instance_valid(_listener):
				var distance := spot.distance_to(_listener.global_position)
				if distance < least or (here == "" and distance < far):
					continue
			places.append(spot)
	return places


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


## Every knock the house can make: { file, lufs, caption }. house_knock (its entry in
## house_effects: its measured loudness and caption), then whatever is in assets/audio/house/knock.
func knocks() -> Array[Dictionary]:
	var settings := SoundSettings.current()
	var found: Array[Dictionary] = []
	for entry: Dictionary in settings.house_effects:
		if entry.file == settings.house_knock:
			found.append(entry)
			break
	for stream in SoundLibrary.files(KNOCK):
		found.append({"file": stream.resource_path, "lufs": settings.house_set_lufs, "caption": settings.house_knock_caption})
	return found


## The next effect: { entry, family } (family &"knock" or &"effect"), or {} for none. It does
## not play it or remember it (_remember_effect() does, once it has sounded).
## With house_knock_share 0, one of effects(), never the one before, as before there were knocks.
## Otherwise a knock with that chance (never the same file twice running; with one file, not a
## third time in a row), else one of the other effects (never the other one before).
func pick_effect() -> Dictionary:
	var settings := SoundSettings.current()
	var share := clampf(settings.house_knock_share, 0.0, 1.0)
	if share <= 0.0 and not _knock_next:
		var choices := effects().filter(func(entry: Dictionary) -> bool: return entry.file != _last_effect)
		return {} if choices.is_empty() else {"entry": choices[randi() % choices.size()], "family": &"effect"}
	var all_knocks := knocks()
	var knock_files := all_knocks.map(func(entry: Dictionary) -> String: return entry.file)
	var knock_choices: Array = all_knocks
	if all_knocks.size() >= 2:
		knock_choices = all_knocks.filter(func(entry: Dictionary) -> bool: return entry.file != _last_knock)
	elif all_knocks.size() == 1 and _knocks_running >= KNOCKS_IN_A_ROW:
		knock_choices = []
	if not knock_choices.is_empty() and (_knock_next or randf() < share):
		return {"entry": knock_choices[randi() % knock_choices.size()], "family": &"knock"}
	var others := effects().filter(func(entry: Dictionary) -> bool: return not knock_files.has(entry.file))
	var fresh := others.filter(func(entry: Dictionary) -> bool: return entry.file != _last_other)
	# With a single other effect, it may follow itself (knocks come between).
	var pool: Array = fresh if not fresh.is_empty() else others
	return {} if pool.is_empty() else {"entry": pool[randi() % pool.size()], "family": &"effect"}


## An effect sounded: the knock rules and "never the one before" go by it.
func _remember_effect(entry: Dictionary, family: StringName) -> void:
	_last_effect = entry.file
	if family == &"knock":
		_knocks_running = _knocks_running + 1 if entry.file == _last_knock else 1
		_last_knock = entry.file
	else:
		_knocks_running = 0
		_last_other = entry.file


func _process(delta: float) -> void:
	_since_cue += delta
	_since_answer += delta
	_since_loud += delta
	_since_accepted += delta
	_settle_quiet()
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
	if _ajar_wait >= 0.0:
		_ajar_wait -= delta
		if _ajar_wait < 0.0:
			_ajar_wait = -1.0
			# Not while it is alert or near: then this attempt is dropped (a later effect may try).
			if open:
				_leave_ajar()
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
		if randi() % maxi(settings.house_nothing_one_in, 1) == 0 and not _knock_next:
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


## One of the rare effects (most often a knock): pick_effect().
func _effect() -> void:
	var picked := pick_effect()
	_knock_next = false
	if picked.is_empty():
		return
	var entry: Dictionary = picked.entry
	var family: StringName = picked.family
	var level := knock_level_for(float(entry.lufs)) if family == &"knock" else NAN
	if _play_entry(family, entry, Vector2.INF, level):
		_remember_effect(entry, family)


## The answer: one knock from another room, closer each step.
func _knock() -> void:
	var settings := SoundSettings.current()
	for entry: Dictionary in settings.house_effects:
		if entry.file == settings.house_knock:
			_since_answer = 0.0
			var at := _answer_spot()
			if _play_entry(&"answer", entry, at, answer_level_for(float(entry.lufs))) and is_instance_valid(_listener):
				_answer_distance = at.distance_to(_listener.global_position)
			return


## Where this answer comes from. At step 0 (or with nothing remembered) any allowed place, not
## the one used last; when this answer raised the step, the farthest place that is nearer to
## her than the last answer was (the nearest, if none is nearer); otherwise the place about
## as far as the last answer. Vector2.INF with nowhere allowed.
func _answer_spot() -> Vector2:
	var places := answer_places()
	if places.is_empty():
		return Vector2.INF
	if answer_step == 0 or _answer_distance == INF or not is_instance_valid(_listener):
		var fresh := places.filter(func(spot: Vector2) -> bool: return spot != _last_spot)
		var pool: Array = fresh if not fresh.is_empty() else places
		_last_spot = pool[randi() % pool.size()]
		return _last_spot
	var ears := _listener.global_position
	var chosen := Vector2.INF
	var best := INF
	for spot in places:
		var distance := spot.distance_to(ears)
		var score := absf(distance - _answer_distance)
		if _answer_raised:
			# Nearer than the last: the farthest of those (a little closer, not a jump).
			score = _answer_distance - distance if distance < _answer_distance else INF
		if score < best:
			best = score
			chosen = spot
	if chosen == Vector2.INF:
		# Nothing nearer is allowed: the nearest allowed place.
		for spot in places:
			if chosen == Vector2.INF or spot.distance_to(ears) < chosen.distance_to(ears):
				chosen = spot
	_last_spot = chosen
	return chosen


## Plays one entry of house_effects from `at` (a place away from her when left out), at
## `level_db` (turned down to house_max_lufs when left out). Returns true if it sounded.
func _play_entry(family: StringName, entry: Dictionary, at := Vector2.INF, level_db := NAN) -> bool:
	if at == Vector2.INF and family != &"answer":
		at = spot_away()
	var stream := load(entry.file) as AudioStream if ResourceLoader.exists(entry.file) else null
	if stream == null or at == Vector2.INF:
		return false
	_last_effect = entry.file
	var level := level_for(float(entry.lufs)) if is_nan(level_db) else level_db
	if not _sound(family, stream, at, level, String(entry.get("caption", ""))):
		return false
	if family == &"effect" or family == &"knock":
		_after_effect(at)
	return true


func _sound(family: StringName, stream: AudioStream, at: Vector2, level_db: float, caption: String) -> bool:
	var held := gate()
	var variation: float = SoundSettings.current().set_pitch_range
	if play(stream, at, level_db, randf_range(1.0 - variation, 1.0 + variation)) == null:
		return false
	if held != "":
		violations += 1
		push_error("[HouseVoice] %s played while its gates were closed: %s" % [stream.resource_path, held])
	history.append({"family": family, "file": stream.resource_path, "at": at, "level_db": level_db, "gate": held})
	if history.size() > HISTORY:
		history.pop_front()
	sounded.emit(family, stream, at, level_db, caption)
	return true


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


## A quiet minute (nothing loud from her) puts the answer back where it started.
func _settle_quiet() -> void:
	if _since_loud >= SoundSettings.current().house_escalate_reset:
		_reset_escalation()


func _reset_escalation() -> void:
	answer_step = 0
	_answer_raised = false
	_answer_distance = INF
	_since_accepted = INF
	_since_loud = INF


## Death and a retry: the answer starts again from afar, and any door still to be left ajar is
## not. Whether one was left ajar this run is kept.
func _on_state_reset() -> void:
	_reset_escalation()
	_ajar_wait = -1.0


## After an effect: maybe, a while later, a door is found ajar (at most once per run).
func _after_effect(at: Vector2) -> void:
	var settings := SoundSettings.current()
	if not settings.house_ajar or ajar_done or _ajar_wait >= 0.0 or _doors.is_empty():
		return
	if randf() >= settings.house_ajar_chance:
		return
	_ajar_wait = randf_range(settings.house_ajar_delay.x, settings.house_ajar_delay.y)
	_ajar_from = at


## The doors that may be left ajar now: shut and at rest, not locked, nobody in the doorway,
## far from her and behind a wall; nearest to `from` (where the effect sounded) first.
func ajar_candidates(from := Vector2.INF) -> Array[Door]:
	var found: Array[Door] = []
	if not is_instance_valid(_listener):
		return found
	var settings := SoundSettings.current()
	var ears := _listener.global_position
	var least: float = Units.to_px(settings.house_ajar_min_u)
	var skipped: Array[RID] = []
	for body: Node in [_listener, _listener.get_parent()]:
		if body is CollisionObject2D:
			skipped.append((body as CollisionObject2D).get_rid())
	for door in _doors:
		if not is_instance_valid(door) or not door.is_inside_tree():
			continue
		if door.is_open or not is_zero_approx(door.swing) or door.locked or door.is_doorway_occupied():
			continue
		var at := door.get_noise_origin()
		if at.distance_to(ears) < least:
			continue
		# She must not see it happen: a wall between them (the acoustics' own wall ray).
		if not Acoustics._wall_between(at, ears, door.get_world_2d(), skipped):
			continue
		found.append(door)
	if from != Vector2.INF:
		found.sort_custom(func(a: Door, b: Door) -> bool: return a.get_noise_origin().distance_to(from) < b.get_noise_origin().distance_to(from))
	return found


## The aftermath: the door nearest the effect is drawn a little open, with a creak she hears.
## Only the leaf moves: the door is still shut (is_open, its blocker, its light occluders and
## the way the entity walks are untouched), it sends no signal, its own player stays silent,
## and the creak is a house sound the entity cannot hear.
func _leave_ajar() -> void:
	var settings := SoundSettings.current()
	var doors := ajar_candidates(_ajar_from)
	if doors.is_empty():
		return
	var door: Door = doors[0]
	var creak := _creak_for(door)
	var stream: AudioStream = creak.stream
	var at := door.get_noise_origin()
	if stream == null or not _sound(&"aftermath", stream, at, level_for(float(creak.lufs)), settings.house_ajar_caption):
		return
	ajar_done = true
	var target: float = settings.house_ajar_swing
	# The leaf moves while the creak sounds, and stops if anything else moves the door meanwhile.
	_ajar_leaf = door.swing
	create_tween().tween_method(_draw_ajar.bind(door), 0.0, target, stream.get_length())
	door_left_ajar.emit(door)


## One step of the leaf drawn ajar. It stops for good once the door is really opened, put
## back (a checkpoint) or gone.
func _draw_ajar(value: float, door: Object) -> void:
	if is_nan(_ajar_leaf) or not is_instance_valid(door) or (door as Door).is_open or not is_equal_approx((door as Door).swing, _ajar_leaf):
		_ajar_leaf = NAN
		return
	(door as Door).swing = value
	_ajar_leaf = value


## The creak for a door and how loud its file is: the door's own when its loudness is known
## (it is house_ajar_creak or one of house_effects), otherwise house_ajar_creak.
## { stream, lufs }; stream is null for a file the house may not play.
func _creak_for(door: Door) -> Dictionary:
	var settings := SoundSettings.current()
	var own: AudioStream = door.creak
	if own != null and allowed(own):
		if own.resource_path == settings.house_ajar_creak:
			return {"stream": own, "lufs": settings.house_ajar_creak_lufs}
		for entry: Dictionary in settings.house_effects:
			if entry.file == own.resource_path:
				return {"stream": own, "lufs": float(entry.lufs)}
	var fallback := load(settings.house_ajar_creak) as AudioStream if ResourceLoader.exists(settings.house_ajar_creak) else null
	return {"stream": fallback if fallback != null and allowed(fallback) else null, "lufs": settings.house_ajar_creak_lufs}
