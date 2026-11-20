class_name BodyAudio
extends Node
## Viv's body, and the way she listens. A child of the Player called "BodyAudio".
##
## Her breathing: one quiet loop on the Body bus, with two kinds of meaning. Her mood says what
## the entity knows: calm while it is unaware or paused, nervous once it has heard something,
## searches or hunts (the two crossfade slowly). Her panting says she is physically tired: it
## comes in gently while she sprints with the exertion meter past its warning (the same number
## that makes the HUD's bar pulse), grows louder as the meter nears the forced gasp, and has a
## short tail once she stops sprinting. Panting takes the place of her mood breathing, it is not
## laid on top. All of it stops while she holds her breath or one of her breath clips sounds.
##
## Her listening. Moving costs information: while she walks, the entity's far-off sounds (ring
## 1) are quieter, and quieter still while she sprints; a second after she stands still they
## are back. Holding her breath is also listening: the house goes soft (a gentle low-pass on
## Music, Ambience and World, before running out of air dulls it further), the entity stays
## sharp and comes up a little, its far-off sounds carry further and fewer of them are lost.
##
## Her heart: the one heartbeat in the game, a child called "Heart" (player/heart_audio.gd).
## It follows the highest of running out of air, what the entity knows, how near it is and
## whether she prays.
##
## Her prayer: a child called "Prayer" (player/prayer_audio.gd). While she prays the house sinks
## slowly into a low-pass, her calm and nervous breathing slow down (a little lower too: the
## only way to slow a loop without new files), her heart beats quietly, and the world comes
## back once the prayer is over. Holding her breath while she prays outranks it: her listening
## starts from where the prayer has the house and goes back there, so nothing jumps.
##
## Nothing here makes a noise the entity can hear, and nothing here ever dulls the entity.
## Every number is in audio/sound_settings.tres.

const CALM := "viv/calm"
const NERVOUS := "viv/nervous"
## Her panting: she is physically tired. (The set keeps its folder name, viv/panic.)
const PANT := "viv/panic"
## The two moods: what the entity knows.
const MOODS: Array[String] = [CALM, NERVOUS]
## Every breathing loop she has.
const LOOPS: Array[String] = [CALM, NERVOUS, PANT]
## The exertion meter is full here: the forced gasp.
const EXERTION_FULL := 100.0
## Names of the requests made to MixDirector while she listens.
const LISTEN := &"listen"
const LISTEN_FOCUS := &"listen_focus"
const SOFTENED: Array[StringName] = [AudioBus.MUSIC, AudioBus.AMBIENCE, AudioBus.WORLD]
const SILENT_DB := -60.0
const HeartAudio := preload("res://player/heart_audio.gd")
const PrayerAudio := preload("res://player/prayer_audio.gd")

## The mood breathing she is heading for ("" = none: she is dead).
var mood := ""
## 0..1 per breathing loop: how much of each is up right now (they add up to 1 while she breathes).
var weights := {CALM: 0.0, NERVOUS: 0.0, PANT: 0.0}
## 0..1: how much of her breathing is panting (the rest is her mood breathing).
var pant := 0.0
## 0..1: 0 while her breathing is held back (holding her breath, and the breath out after it).
var open := 1.0
## 0..1: how hard she is listening (holding her breath).
var listen := 0.0
## dB (0 or less): how much her own movement covers the entity's far-off sounds.
var mask_db := 0.0
## Her heart (player/heart_audio.gd): its `amount`, `reason` and `level_db()` say how it beats.
var heart: AudioStreamPlayer
## Her prayer (player/prayer_audio.gd): its `depth` says how far she is into the prayer state.
var prayer: Node

var _loops := {}
## 0..1 per mood: the slow crossfade between calm and nervous, before the panting takes its share.
var _moods := {CALM: 0.0, NERVOUS: 0.0}

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var breath: Node = get_parent().get_node_or_null("HoldBreath")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for set_id in LOOPS:
		var loop := AudioStreamPlayer.new()
		loop.name = set_id.get_file().capitalize()
		loop.bus = AudioBus.BODY
		loop.volume_db = SILENT_DB
		add_child(loop)
		# The files are not imported as loops: go round for as long as this breathing is up.
		loop.finished.connect(func() -> void:
			if weights[set_id] > 0.0: loop.play())
		_loops[set_id] = loop
	heart = HeartAudio.new()
	heart.name = "Heart"
	heart.set(&"body", self)
	add_child(heart)
	prayer = PrayerAudio.new()
	prayer.name = "Prayer"
	add_child(prayer)
	if breath != null:
		breath.forced_gasp_started.connect(_on_forced_gasp)


func _exit_tree() -> void:
	Acoustics.focus = 0.0
	Acoustics.mask_db = 0.0
	MixDirector.release(LISTEN)
	MixDirector.release(LISTEN_FOCUS)


## The soft low-pass of listening, in Hz, for an amount of listening (0 = where the house is
## without it, 1 = full). `from` is where the house is without it: open, or where her prayer
## has it. Cutoffs move in octaves, so the change sounds even.
static func listen_hz(amount: float, from := -1.0) -> float:
	var settings := SoundSettings.current()
	var rest: float = settings.open_hz if from <= 0.0 else from
	return rest * pow(settings.listen_cutoff_hz / rest, clampf(amount, 0.0, 1.0))


## 0..1: how far she is into the prayer state (0 without a prayer node).
func prayer_depth() -> float:
	return float(prayer.get(&"depth")) if is_instance_valid(prayer) else 0.0


## The mood breathing that fits what the entity knows: calm, or nervous once it has heard
## something, searches or hunts.
func wanted_mood() -> String:
	if GameState.is_dead or player == null:
		return ""
	if Dread.awareness >= Dread.Awareness.HEARD:
		return NERVOUS
	return CALM


## The exertion % past which she pants and the HUD warns (HoldBreath.exertion_warn_percent).
func warning_percent() -> float:
	return float(breath.exertion_warn_percent) if breath != null else EXERTION_FULL


## How tired she is past the warning: 0 at the warning, 1 at the forced gasp.
func effort() -> float:
	var warning := warning_percent()
	if breath == null or warning >= EXERTION_FULL:
		return 0.0
	return clampf(inverse_lerp(warning, EXERTION_FULL, float(breath.exertion_percent)), 0.0, 1.0)


## True while she should be panting: sprinting, with the exertion meter past its warning.
func is_tired() -> bool:
	return breath != null and mood != "" and player.get(&"is_sprinting") == true \
		and float(breath.exertion_percent) > warning_percent()


## What is added to one of her loops, in dB: her mood's trim, or the panting's for how tired she is.
func trim_db(set_id: String) -> float:
	var settings := SoundSettings.current()
	if set_id == PANT:
		return lerpf(settings.viv_pant_db.x, settings.viv_pant_db.y, effort())
	return float(settings.viv_breath_db.get(set_id, 0.0))


## The level one of her breathing loops plays at right now, in dB (for tests and read-outs).
func level_db(set_id: String) -> float:
	var amount: float = sqrt(float(weights[set_id])) * open
	if amount <= 0.0:
		return SILENT_DB
	return maxf(SoundLibrary.gain_db(set_id) + trim_db(set_id) + linear_to_db(amount), SILENT_DB)


func _process(delta: float) -> void:
	var settings := SoundSettings.current()
	_tick_breathing(delta, settings)
	_tick_mask(delta, settings)
	_tick_listening(delta, settings)


## The take heard most clearly during a mood crossfade. Its playback cursor drives Viv's art.
func leading_breath_loop() -> AudioStreamPlayer:
	var loudest: AudioStreamPlayer
	var level := SILENT_DB
	for set_id in LOOPS:
		var voice: AudioStreamPlayer = _loops[set_id]
		if voice.playing and voice.stream != null and voice.volume_db > level:
			level = voice.volume_db
			loudest = voice
	return loudest


func _tick_breathing(delta: float, settings: SoundSettings) -> void:
	mood = wanted_mood()
	# She holds her breath, or is letting it out: no breathing under it.
	var held: bool = breath != null and (breath.is_holding or breath.is_sounding())
	if held or mood == "":
		open = move_toward(open, 0.0, delta / maxf(settings.viv_breath_hold_fade, 0.001))
	else:
		open = move_toward(open, 1.0, delta / maxf(settings.viv_breath_return, 0.001))
	# Her mood: calm and nervous crossfade slowly between themselves.
	for set_id in MOODS:
		_moods[set_id] = move_toward(float(_moods[set_id]), 1.0 if set_id == mood else 0.0, delta / maxf(settings.viv_breath_crossfade, 0.001))
	# Her panting: in gently once she is tired, out over a short tail once she is not.
	if is_tired():
		pant = move_toward(pant, 1.0, delta / maxf(settings.viv_pant_in, 0.001))
	else:
		pant = move_toward(pant, 0.0, delta / maxf(settings.viv_pant_tail, 0.001))
	# The panting takes its share from her mood breathing.
	for set_id in MOODS:
		weights[set_id] = float(_moods[set_id]) * (1.0 - pant)
	weights[PANT] = pant
	# Praying, her mood breathing slows (her panting never plays then: she cannot sprint).
	var slowed := lerpf(1.0, settings.viv_breath_prayer_pitch, prayer_depth())
	for set_id in MOODS:
		(_loops[set_id] as AudioStreamPlayer).pitch_scale = slowed
	for set_id in LOOPS:
		var loop: AudioStreamPlayer = _loops[set_id]
		if weights[set_id] <= 0.0:
			if loop.playing: loop.stop()
			loop.volume_db = SILENT_DB
			continue
		loop.volume_db = level_db(set_id)
		if not loop.playing:
			loop.stream = SoundLibrary.pick(set_id)
			if loop.stream != null:
				loop.play()


## Moving costs information: her own steps cover what is far off.
func _tick_mask(delta: float, settings: SoundSettings) -> void:
	var moving: bool = player != null and not GameState.is_dead \
		and player.velocity.length() > Units.to_px(settings.mask_moving_speed_u)
	var target := 0.0
	if moving:
		target = settings.mask_sprint_db if player.get(&"is_sprinting") == true else settings.mask_walk_db
	var span: float = absf(settings.mask_sprint_db)
	if target < mask_db:
		mask_db = move_toward(mask_db, target, delta * span / maxf(settings.mask_on_time, 0.001))
	else:
		mask_db = move_toward(mask_db, target, delta * span / maxf(settings.mask_off_time, 0.001))
	Acoustics.mask_db = mask_db


## Holding her breath is listening: the house goes soft, the entity comes forward.
func _tick_listening(delta: float, settings: SoundSettings) -> void:
	var holding: bool = breath != null and breath.is_holding and not GameState.is_dead
	if holding:
		listen = move_toward(listen, 1.0, delta / maxf(settings.listen_in, 0.001))
	else:
		listen = move_toward(listen, 0.0, delta / maxf(settings.listen_out, 0.001))
	_apply_listening()


func _apply_listening() -> void:
	Acoustics.focus = listen
	if listen <= 0.0:
		MixDirector.release(LISTEN)
		MixDirector.release(LISTEN_FOCUS)
		return
	var settings := SoundSettings.current()
	# She may hold her breath while she prays: listening starts from where the prayer has the
	# house, so it never jumps open, and hands it back there.
	var rest := settings.open_hz
	if prayer_depth() > 0.0:
		rest = float(PrayerAudio.prayer_hz(prayer_depth()))
	var cutoffs := {}
	for bus_name in SOFTENED:
		cutoffs[bus_name] = listen_hz(listen, rest)
	MixDirector.muffle(LISTEN, MixDirector.Priority.LISTEN, cutoffs)
	var forward: float = settings.listen_entity_db * listen
	MixDirector.focus(LISTEN_FOCUS, MixDirector.Priority.LISTEN, {AudioBus.ENTITY: forward, AudioBus.ENTITY_FAR: forward})


## Out of air: the gasp takes everything back at once.
func _on_forced_gasp(_reason: StringName, _duration: float) -> void:
	listen = 0.0
	_apply_listening()
