extends Node
## Praying, as she hears it: a state of its own. A child of BodyAudio called "Prayer".
##
## How far she is into that state is one number, `depth` (0 = not at all, 1 = deep in the
## prayer). It sinks in slowly while she prays (prayer_in, slower than holding her breath) and
## comes back over prayer_return once the prayer is over, completed or let go: a prayer let go
## early has less to come back from, so it is back sooner. When the prayer is cut (she dies, a
## new attempt, a teleport) it comes back over prayer_cut.
##
## What follows `depth`:
##   - Music, Ambience and World are low-passed, down to prayer_cutoff_hz (one request to
##     MixDirector, priority PRAYER). Holding her breath outranks it: while she holds, her
##     listening decides, and prayer takes it back once she breathes again.
##   - Her calm and nervous breathing slow down (BodyAudio reads `depth`).
##   - Her heart beats, quietly and steadily (player/heart_audio.gd reads `depth`).
##   - A tone from the set house/prayer_tone rises with her progress, if that folder has a
##     file. Empty, it stays silent and nothing is reported.
##   - Her voice: at an altar that says she prays aloud (its `prayer_spoken` is true: the
##     Hacienda's altars), one file from the set viv/prayer_voice plays for as long as she
##     prays, on the sound-effects bus like the tone: never dulled, never ducked. This is the only place that voice is played. Altars without the
##     switch (the body altar of the lab and the tutorial) stay wordless.
##
## Nothing here makes a noise the entity can hear (the altar's own noise is the altar's, and
## that is what gives her away), and nothing here ever dulls the entity or Viv's body: only
## the three buses above are asked for, and nothing else in the mix is touched. Every number
## is in audio/sound_settings.tres ("Viv: prayer").

## The name of the request made to MixDirector while she prays.
const PRAYER := &"prayer"
## The set of the prayer tone (a folder under assets/audio/).
const TONE := "house/prayer_tone"
## The buses that sink with the prayer.
const DULLED: Array[StringName] = [AudioBus.MUSIC, AudioBus.AMBIENCE, AudioBus.WORLD]
## The tone is not part of the house (it is never low-passed with it) and follows the player's
## sound-effects slider. SFX is that slider's own bus, and nothing in the mix ducks it.
const TONE_BUS := AudioBus.SFX
## The set of her spoken prayer (a folder under assets/audio/). It plays where the tone does.
const VOICE := "viv/prayer_voice"
const VOICE_BUS := TONE_BUS
const SILENT_DB := -60.0
const PERCENT := 100.0

## 0..1: how far she is into the prayer state right now.
var depth := 0.0
## 0..1: how far the prayer got (seconds prayed / the prayer's length). Held while the world
## comes back; 0 once it is back.
var progress := 0.0
## The tone's voice (silent while the folder is empty).
var tone: AudioStreamPlayer
## Her spoken prayer (silent at altars that do not ask for it, and while the folder is empty).
var voice: AudioStreamPlayer
## How many times her spoken prayer has started (for read-outs and checks).
var voice_starts := 0

## True while the world comes back over prayer_cut instead of prayer_return.
var _cut := false
## 1 while she prays aloud; falls to 0 over prayer_voice_fade once she stops.
var _voice_amount := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	tone = AudioStreamPlayer.new()
	tone.name = "Tone"
	tone.bus = TONE_BUS
	tone.volume_db = SILENT_DB
	add_child(tone)
	# The files are not imported as loops: go round for as long as the prayer lasts.
	tone.finished.connect(func() -> void:
		if depth > 0.0: _start_tone())
	voice = AudioStreamPlayer.new()
	voice.name = "Voice"
	voice.bus = VOICE_BUS
	voice.volume_db = SILENT_DB
	add_child(voice)
	# The prayer can outlast the recording: it goes round for as long as she prays.
	voice.finished.connect(func() -> void:
		if speaking(): voice.play())
	GameState.prayer_started.connect(_on_prayer_started)
	GameState.prayer_ended.connect(_on_prayer_ended)
	GameState.state_reset.connect(_on_state_reset)


func _exit_tree() -> void:
	MixDirector.release(PRAYER)


## The low-pass of prayer, in Hz, for a depth (0 = open, 1 = prayer_cutoff_hz). Cutoffs move
## in octaves, so the change sounds even (the same rule as BodyAudio.listen_hz()).
static func prayer_hz(amount: float) -> float:
	var settings := SoundSettings.current()
	return settings.open_hz * pow(settings.prayer_cutoff_hz / settings.open_hz, clampf(amount, 0.0, 1.0))


## The level of the tone right now, in dB (SILENT_DB while it is silent).
func tone_db() -> float:
	if depth <= 0.0:
		return SILENT_DB
	var settings := SoundSettings.current()
	var db := SoundLibrary.gain_db(TONE) + lerpf(settings.prayer_tone_db.x, settings.prayer_tone_db.y, progress) \
		+ linear_to_db(depth)
	return maxf(db, SILENT_DB)


## True when the tone's folder has a file.
func has_tone() -> bool:
	return not SoundLibrary.files(TONE).is_empty()


## True while she prays aloud: she is praying, alive, and the altar asks for her voice.
func speaking() -> bool:
	var altar: Node = GameState.prayer_source
	return GameState.is_praying and not GameState.is_dead and is_instance_valid(altar) \
		and altar.get(&"prayer_spoken") == true


## The level of her spoken prayer right now, in dB (SILENT_DB while it is silent).
func voice_db() -> float:
	if _voice_amount <= 0.0:
		return SILENT_DB
	return maxf(SoundLibrary.gain_db(VOICE) + linear_to_db(_voice_amount), SILENT_DB)


## One plain line for read-outs: "praying · world dulled 62% · tone: no file", and, at an altar
## where she prays aloud, " · aloud -6.0 dB" after it.
func status() -> String:
	var state := "praying" if GameState.is_praying else ("coming back" if depth > 0.0 else "not praying")
	var heard := "tone: no file"
	if has_tone():
		heard = "tone %.1f dB" % tone_db() if tone.playing else "tone: silent"
	var line := "%s · world dulled %d%% · %s" % [state, roundi(depth * PERCENT), heard]
	return line + " · aloud %.1f dB" % voice_db() if voice.playing else line


func _process(delta: float) -> void:
	var settings := SoundSettings.current()
	var praying := GameState.is_praying and not GameState.is_dead
	_tick_voice(delta, settings)
	if praying:
		_cut = false
		depth = move_toward(depth, 1.0, delta / maxf(settings.prayer_in, 0.001))
		progress = _prayer_progress()
	else:
		if GameState.is_dead:
			_cut = true
		var time: float = settings.prayer_cut if _cut else settings.prayer_return
		depth = move_toward(depth, 0.0, delta / maxf(time, 0.001))
	if depth <= 0.0:
		depth = 0.0
		progress = 0.0
		_cut = false
		MixDirector.release(PRAYER)
		_silence_tone()
		return
	var cutoffs := {}
	for bus_name in DULLED:
		cutoffs[bus_name] = prayer_hz(depth)
	MixDirector.muffle(PRAYER, MixDirector.Priority.PRAYER, cutoffs)
	_tick_tone()


## Seconds prayed / the prayer's length, read from the altar she prays at.
func _prayer_progress() -> float:
	var altar: Node = GameState.prayer_source
	if not is_instance_valid(altar) or not altar.has_method("get_prayer_elapsed"):
		return progress
	var duration: Variant = altar.get(&"pray_duration")
	var length := float(duration) if duration != null else 0.0
	if length <= 0.0:
		return progress
	return clampf(float(altar.call("get_prayer_elapsed")) / length, 0.0, 1.0)


## Her spoken prayer: it starts with the prayer, fades when she lets go, and is cut at once
## when the prayer is cut.
func _tick_voice(delta: float, settings: SoundSettings) -> void:
	if speaking():
		_voice_amount = 1.0
		if not voice.playing:
			voice.stream = SoundLibrary.pick(VOICE)
			if voice.stream == null:
				_voice_amount = 0.0
				return
			voice.volume_db = voice_db()
			voice.play()
			voice_starts += 1
	elif _voice_amount > 0.0:
		var fade: float = 0.0 if _cut or GameState.is_dead else settings.prayer_voice_fade
		_voice_amount = 0.0 if fade <= 0.0 else move_toward(_voice_amount, 0.0, delta / fade)
	if voice.playing:
		if _voice_amount <= 0.0:
			voice.stop()
		voice.volume_db = voice_db()


func _tick_tone() -> void:
	if not has_tone():
		_silence_tone()
		return
	tone.volume_db = tone_db()
	if not tone.playing:
		_start_tone()


func _start_tone() -> void:
	if not has_tone():
		return
	tone.stream = SoundLibrary.pick(TONE)
	tone.volume_db = tone_db()
	if tone.stream != null:
		tone.play()


func _silence_tone() -> void:
	if tone.playing:
		tone.stop()
	tone.volume_db = SILENT_DB


func _on_prayer_started(_altar: Node) -> void:
	_cut = false


## A prayer completed or let go comes back slowly; one cut short (death, a new attempt, a
## teleport) comes back at once.
func _on_prayer_ended(_altar: Node, immediate: bool) -> void:
	_cut = immediate


func _on_state_reset() -> void:
	_cut = true
	_voice_amount = 0.0
	if voice.playing:
		voice.stop()
