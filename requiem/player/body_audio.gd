class_name BodyAudio
extends Node
## Viv's body, and the way she listens. A child of the Player called "BodyAudio".
##
## Her breathing: one quiet loop on the Body bus that says how she is. Calm while nothing is
## after her, nervous once it has heard something or is searching, panicked while it hunts or
## while she sprints. The three crossfade slowly, and it stops while she holds her breath.
##
## Her listening. Moving costs information: while she walks, the entity's far-off sounds (ring
## 1) are quieter, and quieter still while she sprints; a second after she stands still they
## are back. Holding her breath is also listening: the house goes soft (a gentle low-pass on
## Music, Ambience and World, before running out of air dulls it further), the entity stays
## sharp and comes up a little, its far-off sounds carry further and fewer of them are lost.
##
## Nothing here makes a noise the entity can hear, and nothing here ever dulls the entity.
## Every number is in audio/sound_settings.tres.

const CALM := "viv/calm"
const NERVOUS := "viv/nervous"
const PANIC := "viv/panic"
const MOODS: Array[String] = [CALM, NERVOUS, PANIC]
## Names of the requests made to MixDirector while she listens.
const LISTEN := &"listen"
const LISTEN_FOCUS := &"listen_focus"
const SOFTENED: Array[StringName] = [AudioBus.MUSIC, AudioBus.AMBIENCE, AudioBus.WORLD]
const SILENT_DB := -60.0

## The breathing she is heading for ("" = none: she holds her breath, or she is dead).
var mood := ""
## 0..1 per breathing loop: how much of each is up right now.
var weights := {CALM: 0.0, NERVOUS: 0.0, PANIC: 0.0}
## 0..1: 0 while her breathing is held back (holding her breath, and the breath out after it).
var open := 1.0
## 0..1: how hard she is listening (holding her breath).
var listen := 0.0
## dB (0 or less): how much her own movement covers the entity's far-off sounds.
var mask_db := 0.0

var _loops := {}

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var breath: Node = get_parent().get_node_or_null("HoldBreath")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for set_id in MOODS:
		var loop := AudioStreamPlayer.new()
		loop.name = set_id.get_file().capitalize()
		loop.bus = AudioBus.BODY
		loop.volume_db = SILENT_DB
		add_child(loop)
		# The files are not imported as loops: go round for as long as this breathing is up.
		loop.finished.connect(func() -> void:
			if weights[set_id] > 0.0: loop.play())
		_loops[set_id] = loop
	if breath != null:
		breath.forced_gasp_started.connect(_on_forced_gasp)


func _exit_tree() -> void:
	Acoustics.focus = 0.0
	Acoustics.mask_db = 0.0
	MixDirector.release(LISTEN)
	MixDirector.release(LISTEN_FOCUS)


## The soft low-pass of listening, in Hz, for an amount of listening (0 = open, 1 = full).
## Cutoffs move in octaves, so the change sounds even.
static func listen_hz(amount: float) -> float:
	var settings := SoundSettings.current()
	return settings.open_hz * pow(settings.listen_cutoff_hz / settings.open_hz, clampf(amount, 0.0, 1.0))


## The breathing that fits this moment.
func wanted_mood() -> String:
	if GameState.is_dead or player == null:
		return ""
	if Dread.awareness >= Dread.Awareness.HUNTING or player.get(&"is_sprinting") == true:
		return PANIC
	if Dread.awareness in [Dread.Awareness.HEARD, Dread.Awareness.SEARCHING]:
		return NERVOUS
	return CALM


## The level one of her breathing loops plays at right now, in dB (for tests and read-outs).
func level_db(set_id: String) -> float:
	var settings := SoundSettings.current()
	var amount: float = sqrt(float(weights[set_id])) * open
	if amount <= 0.0:
		return SILENT_DB
	return maxf(SoundLibrary.gain_db(set_id) + float(settings.viv_breath_db.get(set_id, 0.0)) + linear_to_db(amount), SILENT_DB)


func _process(delta: float) -> void:
	var settings := SoundSettings.current()
	_tick_breathing(delta, settings)
	_tick_mask(delta, settings)
	_tick_listening(delta, settings)


func _tick_breathing(delta: float, settings: SoundSettings) -> void:
	mood = wanted_mood()
	# She holds her breath, or is letting it out: no breathing under it.
	var held: bool = breath != null and (breath.is_holding or breath.is_sounding())
	if held or mood == "":
		open = move_toward(open, 0.0, delta / maxf(settings.viv_breath_hold_fade, 0.001))
	else:
		open = move_toward(open, 1.0, delta / maxf(settings.viv_breath_return, 0.001))
	for set_id in MOODS:
		var loop: AudioStreamPlayer = _loops[set_id]
		weights[set_id] = move_toward(float(weights[set_id]), 1.0 if set_id == mood else 0.0, delta / maxf(settings.viv_breath_crossfade, 0.001))
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
	var cutoffs := {}
	for bus_name in SOFTENED:
		cutoffs[bus_name] = listen_hz(listen)
	MixDirector.muffle(LISTEN, MixDirector.Priority.LISTEN, cutoffs)
	var forward: float = settings.listen_entity_db * listen
	MixDirector.focus(LISTEN_FOCUS, MixDirector.Priority.LISTEN, {AudioBus.ENTITY: forward, AudioBus.ENTITY_FAR: forward})


## Out of air: the gasp takes everything back at once.
func _on_forced_gasp(_reason: StringName, _duration: float) -> void:
	listen = 0.0
	_apply_listening()
