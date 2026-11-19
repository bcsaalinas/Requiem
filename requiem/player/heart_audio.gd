extends AudioStreamPlayer
## Viv's heart: the only heartbeat in the game. A child of BodyAudio called "Heart", and itself
## the voice (not positional, on the Body bus).
##
## How hard it beats is one number, `amount` (0 = silent, 1 = as hard as it ever beats). Three
## reasons can push it up, each only as far as its own range in audio/sound_settings.tres
## ("Viv: her heart"), and the heart follows the highest of them:
##   strain    she holds her breath and is running out of air (BreathStrainAudio.level);
##   threat    what the entity knows (Dread.threat): it heard something, it searches, it hunts;
##   presence  an entity is near by ear, in any state, also unaware (Dread.presence). It lags
##             and drifts on purpose, so it is a feeling and never a direction.
## While she holds her breath she is listening, so the threat and presence heart steps back as
## the music does (breath_duck_db). Running out of air is never stepped back.
##
## The level and the speed both follow `amount`. It rises and falls smoothly, never above its
## cap, and comes in from silence, so it never starts with a step. Dead: it stops; a new
## attempt starts with it silent.
##
## It adds nothing a listener in the world can hear, and it never dulls the entity.

const HEARTBEAT := preload("res://assets/audio/horror-jam-kit 2/WAV/Body/heartbeat_01.wav")
const SILENT_DB := -60.0
const STRAIN := &"strain"
const THREAT := &"threat"
const PRESENCE := &"presence"

## The BodyAudio this heart belongs to (her listening, and the player).
var body: Node
## 0..1: how hard it beats right now.
var amount := 0.0
## Which reason is winning right now: &"strain", &"threat", &"presence", or &"" when none is.
var reason := &""
## 0..1: how far each reason pushes right now (for the tests and the read-outs).
var strain_amount := 0.0
var threat_amount := 0.0
var presence_amount := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	stream = HEARTBEAT
	bus = AudioBus.BODY
	volume_db = SILENT_DB
	# The file is not imported as a loop: start it again for as long as the heart beats.
	finished.connect(func() -> void:
		if amount > 0.0: play())
	GameState.state_reset.connect(_on_state_reset)


## The level it plays at right now, in dB (SILENT_DB while it is silent).
func level_db() -> float:
	return level_for(amount)


## The level for an amount: from heart_db.x to heart_db.y (the cap), fading in from silence
## over the first heart_edge of the amount.
static func level_for(value: float) -> float:
	var settings := SoundSettings.current()
	if value <= 0.0:
		return SILENT_DB
	var db := lerpf(settings.heart_db.x, settings.heart_db.y, clampf(value, 0.0, 1.0))
	if value < settings.heart_edge:
		db += linear_to_db(value / settings.heart_edge)
	return clampf(db, SILENT_DB, settings.heart_db.y)


## How far one reason's input pushes the heart: nothing at or below `from`, then from
## range.x up to range.y as the input goes from `from` to 1.
static func push(value: float, from: float, range: Vector2) -> float:
	if value <= from:
		return 0.0
	return lerpf(range.x, range.y, inverse_lerp(from, 1.0, minf(value, 1.0)))


func _process(delta: float) -> void:
	var settings := SoundSettings.current()
	var target := _target(settings)
	var time: float = settings.heart_rise_time if target > amount else settings.heart_fall_time
	amount = move_toward(amount, target, delta / maxf(time, 0.001))
	if amount <= 0.0:
		reason = &""
		_silence()
		return
	volume_db = level_db()
	pitch_scale = lerpf(settings.heart_pitch.x, settings.heart_pitch.y, amount)
	if not playing:
		play()


## The highest of the three reasons, with the threat and presence heart stepped back while
## she listens.
func _target(settings: SoundSettings) -> float:
	if GameState.is_dead:
		strain_amount = 0.0
		threat_amount = 0.0
		presence_amount = 0.0
		return 0.0
	var level := _strain_level()
	strain_amount = lerpf(settings.heart_strain.x, settings.heart_strain.y, level) if level > 0.0 else 0.0
	threat_amount = push(Dread.threat, settings.heart_threat_from, settings.heart_threat)
	presence_amount = push(Dread.presence, settings.heart_presence_from, settings.heart_presence)
	var outside := maxf(threat_amount, presence_amount)
	var listening: float = float(body.get(&"listen")) if body != null else 0.0
	# Listening steps it back by breath_duck_db, on the heart's own dB scale.
	var step := listening * absf(settings.breath_duck_db) / maxf(settings.heart_db.y - settings.heart_db.x, 0.001)
	outside = maxf(outside - step, 0.0)
	if strain_amount <= 0.0 and outside <= 0.0:
		return 0.0
	if strain_amount >= outside:
		reason = STRAIN
		return strain_amount
	reason = THREAT if threat_amount >= presence_amount else PRESENCE
	return outside


## How short of air she is, as the strain sound already has it (0 while she breathes).
func _strain_level() -> float:
	var player: Node = body.get(&"player") if body != null else null
	var feedback: Node = player.get_node_or_null("BreathFeedback") if player != null else null
	var strain_audio: Variant = feedback.get(&"strain_audio") if feedback != null else null
	if strain_audio == null:
		return 0.0
	return float((strain_audio as Node).get(&"level"))


func _silence() -> void:
	if playing:
		stop()
	volume_db = SILENT_DB


func _on_state_reset() -> void:
	amount = 0.0
	reason = &""
	strain_amount = 0.0
	threat_amount = 0.0
	presence_amount = 0.0
	_silence()
