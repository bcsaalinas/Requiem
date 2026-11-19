extends Node
## Jump-scare audit (development only, never exported).
##
## Watches the Master bus and keeps a log of every sudden rise in level: more than
## audit_jump_db (18 dB) within audit_jump_window (100 ms). The scream is the one sound that
## is meant to do that, so it is counted and left out of the log. Every other rise is logged
## with what explains it:
##   her own action        she made a noise or pressed something in that instant, or the rise
##                         is on her own bus (Body: her steps and breath; UI: her clicks);
##   it heard her          the heard-you cue itself, which only ever answers a noise;
##   warned                the heard-you cue came 0.7 s or more before, and the encounter is on
##                         (or has only just ended: the stand-down's own sound);
##   UNEXPLAINED           none of those: this is what a jump scare looks like.
## It also logs any sound of the house voice that played while its gates were closed.
##
## It only listens: it changes no sound and makes no noise. Numbers: audio/sound_settings.tres
## ("Checks: the jump-scare audit").

## Moments of the entity's awareness that are the heard-you cue.
const HEARD_MOMENTS: Array[StringName] = [&"heard", &"heard_again"]
const SCREAM := &"scream"
const UNEXPLAINED := "UNEXPLAINED"
## Buses that only ever carry what she does herself.
const HER_OWN: Array[StringName] = [AudioBus.BODY, AudioBus.UI]
## The list keeps this many entries (the newest).
const KEPT := 200

## A rise was logged: { time, from_db, to_db, jump_db, bus, cause, explained, sound, sound_ago }.
## `bus` is the bus that was loudest as it rose ("" when a test fed the reading); `sound` is
## the last sound somebody told it about with note_sound(), `sound_ago` how long before the rise.
signal jumped(entry: Dictionary)
## A house sound played while its gates were closed: { time, family, file, reason }.
signal house_breached(entry: Dictionary)

## Every rise that was not the scream, newest last.
var rises: Array[Dictionary] = []
## House sounds that played while the house voice's gates were closed. Must stay empty.
var house_breaches: Array[Dictionary] = []
## Rises that were the scream (counted, not logged).
var screams := 0
## How many meter readings were taken, and the loudest of them (dB, peak on Master).
var readings := 0
var loudest_db := -INF
## Prints every logged rise; off, only the unexplained ones and the house's are printed.
var verbose := false

## The meter readings of the last window: { time, level }.
var _recent: Array[Dictionary] = []
var _cue_at := {}
var _heard_at := -INF
var _noise_at := -INF
var _press_at := -INF
var _alert_at := -INF
var _sound := ""
var _sound_at := -INF
var _rose_at := -INF
var _master := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_master = AudioServer.get_bus_index(AudioBus.MASTER)
	Dread.cue_played.connect(_on_cue_played)
	NoiseManager.noise_emitted.connect(func(_at: Vector2, _radius: float, _source: int, _duration: float) -> void: _noise_at = now())
	HouseVoice.sounded.connect(_on_house_sounded)


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		_press_at = now()


func _process(_delta: float) -> void:
	if Dread.awareness >= Dread.Awareness.HEARD:
		_alert_at = now()
	sample(now(), _peak(_master), loudest_bus())


## The peak of a bus right now, in dB.
func _peak(bus: int) -> float:
	return maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))


## The bus that is loudest right now: where a rise on Master comes from.
func loudest_bus() -> StringName:
	var loudest := &""
	var level := -INF
	for bus_name in AudioBus.ALL:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus >= 0 and _peak(bus) > level:
			level = _peak(bus)
			loudest = bus_name
	return loudest


## One reading of the Master meter (dB, peak) at `time`, and the bus that is loudest then.
## Called every frame; a test may call it with readings of its own.
func sample(time: float, level_db: float, bus: StringName = &"") -> void:
	var settings := SoundSettings.current()
	readings += 1
	loudest_db = maxf(loudest_db, level_db)
	# Quieter than the floor counts as the floor: a rise out of silence is measured from there.
	var level := maxf(level_db, settings.audit_floor_db)
	while not _recent.is_empty() and time - float(_recent[0].time) > settings.audit_jump_window:
		_recent.pop_front()
	var lowest := level
	for reading in _recent:
		lowest = minf(lowest, float(reading.level))
	if level - lowest > settings.audit_jump_db:
		# One rise is logged once: the meter flickers while a sound starts, so a second rise
		# within the same window is still the same sound.
		if time - _rose_at > settings.audit_jump_window:
			_rose(time, lowest, level, bus)
		_rose_at = time
		_recent.clear()
	_recent.append({"time": time, "level": level})


## What explains a rise at `time` on `bus` ("" for the scream, UNEXPLAINED for nothing).
func cause_at(time: float, bus: StringName = &"") -> String:
	var settings := SoundSettings.current()
	if time - float(_cue_at.get(SCREAM, -INF)) <= settings.audit_scream_time:
		return ""
	if time - maxf(_noise_at, _press_at) <= settings.audit_own_action:
		return "her own action"
	if HER_OWN.has(bus):
		return "her own action (%s bus)" % bus
	var since_heard := time - _heard_at
	if since_heard >= 0.0 and since_heard < settings.audit_warning:
		# While it listens it makes no other sound: this is the heard-you cue itself.
		return "it heard her (the heard-you cue)"
	if since_heard >= settings.audit_warning and time - _alert_at <= settings.audit_aftermath:
		return "warned %.1f s before" % since_heard
	return UNEXPLAINED


## Whoever knows what just played (the audio read-out does) says so here, so that a logged
## rise can name the sound it most likely was. Changes nothing about what is logged.
func note_sound(sound: String, time: float = now()) -> void:
	_sound = sound
	_sound_at = time


func unexplained() -> Array[Dictionary]:
	return rises.filter(func(entry: Dictionary) -> bool: return not entry.explained)


## One line for a read-out.
func summary() -> String:
	var last := "none yet"
	if not rises.is_empty():
		last = "+%.0f dB (%s%s)" % [rises.back().jump_db, rises.back().cause, "" if rises.back().sound == "" else ", after " + rises.back().sound]
	return "%d sudden rises, %d unexplained, %d house sounds while gated · last: %s" % [rises.size(), unexplained().size(), house_breaches.size(), last]


## Forgets everything it has seen.
func clear() -> void:
	rises.clear()
	house_breaches.clear()
	screams = 0
	readings = 0
	loudest_db = -INF
	_recent.clear()
	_cue_at.clear()
	_heard_at = -INF
	_noise_at = -INF
	_press_at = -INF
	_alert_at = -INF
	_sound = ""
	_sound_at = -INF
	_rose_at = -INF


func _rose(time: float, from_db: float, to_db: float, bus: StringName) -> void:
	var cause := cause_at(time, bus)
	if cause == "":
		screams += 1
		return
	var entry := {"time": time, "from_db": from_db, "to_db": to_db, "jump_db": to_db - from_db, "bus": bus, "cause": cause, "explained": cause != UNEXPLAINED,
		"sound": _sound, "sound_ago": time - _sound_at}
	rises.append(entry)
	if rises.size() > KEPT:
		rises.pop_front()
	if verbose or not entry.explained:
		print("[JumpAudit] +%.0f dB within %.0f ms on Master (%.0f to %.0f dB)%s%s · %s" % [
			entry.jump_db, SoundSettings.current().audit_jump_window * 1000.0, from_db, to_db, "" if bus == &"" else ", loudest bus " + bus,
			"" if _sound == "" else ", last sound %s %.1f s before" % [_sound, entry.sound_ago], cause])
	jumped.emit(entry)


func _on_cue_played(moment: StringName) -> void:
	_cue_at[moment] = now()
	if HEARD_MOMENTS.has(moment):
		_heard_at = now()
		_alert_at = now()


func _on_house_sounded(family: StringName, stream: AudioStream, _at: Vector2, _level_db: float, _caption: String) -> void:
	var reason := HouseVoice.gate()
	if reason == "" or family == &"story":
		return
	var entry := {"time": now(), "family": family, "file": stream.resource_path if stream != null else "", "reason": reason}
	house_breaches.append(entry)
	print("[JumpAudit] the house played %s (%s) while its gates were closed: %s" % [String(entry.file).get_file(), family, reason])
	house_breached.emit(entry)
