extends Node
## What running out of air sounds like, so the meter is not needed to know it: her own heart,
## louder and faster; a thin high tone that grows in her ears; and the world outside her head
## going dull. All of it follows BreathFeedback.strain (0 = air to spare, 1 = none left) and
## falls away the moment she breathes. It adds nothing a listener in the world can hear.

const HEARTBEAT := preload("res://assets/audio/horror-jam-kit 2/WAV/Body/heartbeat_01.wav")
const TONE := preload("res://assets/audio/horror-jam-kit 2/WAV/Tonal/high_tension_tone_01.wav")
## Strain below this is silent; the heart comes in first, the tone only when it is urgent.
const HEART_FROM := 0.1
const TONE_FROM := 0.45
const HEART_DB := Vector2(-22.0, -3.0)
const HEART_PITCH := Vector2(0.95, 1.45)
const TONE_DB := Vector2(-30.0, -11.0)
## The world goes dull while she strains: these buses, from open down to strain_shut_hz with no
## air left (audio/sound_settings.tres). MixDirector owns the buses; this script only asks.
const MUFFLED_BUSES: Array[StringName] = [AudioBus.MUSIC, AudioBus.AMBIENCE]
const MUFFLE := &"breath_strain"
const SILENT_DB := -60.0
## The node whose `level` says the heartbeat of running out of air is sounding: the threat
## heartbeat (MusicDirector) gives way to it, so the two never sound together.
const HEART_GROUP := &"strain_heart"

var feedback: Node
## 0..1: how much of the strain mix is up right now (for the tests and for tuning).
var level := 0.0
var _heart: AudioStreamPlayer
var _tone: AudioStreamPlayer
## The low-passes MixDirector drives on MUFFLED_BUSES. Read here (and by the tests), never set.
var _filters: Array[AudioEffectLowPassFilter] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(HEART_GROUP)
	_heart = _voice("Heart", HEARTBEAT)
	_tone = _voice("Tone", TONE)
	for bus_name in MUFFLED_BUSES:
		_filters.append(MixDirector.muffle_filter(bus_name))


func _voice(voice_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.name = voice_name
	voice.stream = stream
	voice.bus = AudioBus.BODY
	voice.volume_db = SILENT_DB
	add_child(voice)
	# The clips are not imported as loops: start them again for as long as they are wanted.
	voice.finished.connect(func() -> void:
		if level > 0.0: voice.play())
	return voice


func _exit_tree() -> void:
	MixDirector.release(MUFFLE)


func _process(delta: float) -> void:
	var holding: bool = feedback.enabled and feedback.breath.is_holding and not GameState.is_dead
	var strain: float = feedback.strain * feedback.effects_strength if holding else 0.0
	var target := smoothstep(HEART_FROM, 1.0, strain)
	# It builds with the strain and lets go quickly: the first breath out is the relief.
	level = move_toward(level, target, delta * (1.5 if target > level else 4.0))
	var urgent := smoothstep(TONE_FROM, 1.0, strain) * level
	_drive(_heart, level, lerpf(HEART_DB.x, HEART_DB.y, level))
	_heart.pitch_scale = lerpf(HEART_PITCH.x, HEART_PITCH.y, level)
	_drive(_tone, urgent, lerpf(TONE_DB.x, TONE_DB.y, urgent))
	if level <= 0.0:
		MixDirector.release(MUFFLE)
		return
	var settings := SoundSettings.current()
	# Holding her breath has already made the house soft (player/body_audio.gd): running out
	# of air takes it further from there, never back up.
	var cutoff := minf(settings.open_hz * pow(settings.strain_shut_hz / settings.open_hz, level), BodyAudio.listen_hz(Acoustics.focus))
	var cutoffs := {}
	for bus_name in MUFFLED_BUSES: cutoffs[bus_name] = cutoff
	MixDirector.muffle(MUFFLE, MixDirector.Priority.BREATH, cutoffs)


func _drive(voice: AudioStreamPlayer, amount: float, volume_db: float) -> void:
	if amount <= 0.001:
		if voice.playing: voice.stop()
		voice.volume_db = SILENT_DB
		return
	voice.volume_db = volume_db
	if not voice.playing: voice.play()
