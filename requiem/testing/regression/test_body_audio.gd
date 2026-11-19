extends Node2D
## Viv's body and her listening (headless).
## Her breath clips are her own sets, on Body, with the noise they make unchanged. Her
## breathing loop follows the situation and stops while she holds her breath. Holding her
## breath makes the house soft and the entity a little louder, further-reaching and less
## broken up; walking and sprinting cover its far-off sounds. She has one heart: the hunt and
## running out of air both play through it, never two at once (test_heart covers the rest).
## None of it makes noise, and none of it ever dulls the entity.

const KITCHEN_BY_WALL := Vector2(368, 176)
const VESTIBULE_BY_WALL := Vector2(432, 176)        # 2 u apart, the wall between: ring 1
const VESTIBULE_A := Vector2(520, 400)
const VESTIBULE_B := Vector2(680, 400)              # 5 u apart, same room: ring 2
const STEP := "entity/claws_walk"
const TRIES := 400

## A stand-in entity that hunts: Dread reads what it knows from its current_state.
class Hunter extends CharacterBody2D:
	var current_state := EntityAudio.HUNT
	var active := true

var failures: Array[String] = []
var checks := 0
var settings: SoundSettings
var player: CharacterBody2D
var breath: Node
var body: BodyAudio
var noises := 0
var gasps := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame


func seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func near(a: float, b: float, tolerance := 0.05) -> bool:
	return absf(a - b) <= tolerance


func _ready() -> void:
	settings = SoundSettings.current()
	GameState.reset()
	Input.action_release("hold_breath")
	NoiseManager.noise_emitted.connect(func(_at: Vector2, _radius: float, _source: int, _duration: float) -> void: noises += 1)
	check_settings()
	check_scene()
	await set_up_alone()
	await check_breathing()
	await check_listening()
	await check_masking()
	await check_one_heartbeat()
	player.queue_free()
	await frames(3)
	check(is_zero_approx(Acoustics.focus) and is_zero_approx(Acoustics.mask_db) and not MixDirector.is_active(BodyAudio.LISTEN),
		"When she leaves, nothing of her listening is left behind")
	await check_in_the_house()
	print("[Body audio tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func check_settings() -> void:
	check(settings.mask_walk_db == -6.0 and settings.mask_sprint_db == -12.0, "Walking covers 6 dB of what is far off, sprinting 12 dB")
	check(near(settings.mask_off_time, 1.0, 0.3), "About a second of standing still lifts it")
	check(settings.listen_cutoff_hz == 2500.0 and near(settings.listen_in, 0.3, 0.001) and near(settings.listen_out, 0.5, 0.001),
		"Holding her breath softens the house to 2500 Hz over 0.3 s, and it returns over 0.5 s")
	check(near(settings.listen_reach_factor, 1.3, 0.001) and near(settings.listen_gap_factor, 0.5, 0.001) and settings.listen_entity_db == 2.0,
		"Listening: ring 1 reaches 1.3 times further, half the gaps, the entity 2 dB up")
	check(settings.viv_breath_crossfade == 1.5, "Her breathing changes over 1.5 s")
	check(settings.listen_cutoff_hz > settings.strain_shut_hz, "Running out of air dulls the house further than listening does")
	check(MixDirector.Priority.SCREAM > MixDirector.Priority.LISTEN and MixDirector.Priority.BREATH > MixDirector.Priority.LISTEN
		and MixDirector.Priority.LISTEN > MixDirector.Priority.PRAYER, "The scream outranks her listening, and her listening outranks prayer")
	for path in ["res://player/body_audio.gd", "res://player/breath_strain_audio.gd", "res://player/heart_audio.gd"]:
		var source := FileAccess.get_file_as_string(path)
		check(not source.contains("NoiseManager") and not source.contains("AudioServer"), "%s makes no noise and touches no bus" % path.get_file())
	for set_id in BodyAudio.MOODS:
		check(SoundLibrary.files(set_id).size() >= 1, "%s has a file" % set_id)


## The player scene as it is saved: the four breath exports are the four sets.
func check_scene() -> void:
	var saved: Node = (load("res://player/player.tscn") as PackedScene).instantiate()
	var saved_breath: Node = saved.get_node("HoldBreath")
	var wanted := {"hold_clips": "viv/hold_in", "exhale_clips": "viv/exhale", "gasp_clips": "viv/gasp", "forced_gasp_clips": "viv/forced_gasp"}
	for property: String in wanted:
		var clips: Array = saved_breath.get(property)
		var folder: String = SoundLibrary.ROOT + wanted[property] + "/"
		check(clips.size() == SoundLibrary.files(wanted[property]).size() and clips.size() >= 1 and clips.all(func(clip: AudioStream) -> bool:
			return clip != null and clip.resource_path.begins_with(folder)), "%s is the whole of %s (%d files)" % [property, wanted[property], clips.size()])
	check(saved_breath.quiet_exhale_radius_u == 1.0 and saved_breath.gasp_radius_u == 5.0 and saved_breath.forced_gasp_radius_u == 7.0
		and saved_breath.forced_lock_duration == 2.0, "Every noise radius of her breath is what it was: 1, 5 and 7 u")
	check(saved.get_node_or_null("BodyAudio") is BodyAudio, "The player has a BodyAudio child")
	saved.free()


func set_up_alone() -> void:
	player = preload("res://player/player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	breath = player.get_node("HoldBreath")
	body = player.get_node("BodyAudio")
	breath.forced_gasp_started.connect(func(_reason: StringName, _duration: float) -> void: gasps += 1)
	await frames(3)
	check(breath._audio_player.bus == AudioBus.BODY and body.get_children().size() == 4 and body.get_children().all(func(loop: Node) -> bool:
		return loop is AudioStreamPlayer and loop.bus == AudioBus.BODY) and body.heart.get_parent() == body,
		"Her breath clips, her three breathing loops and her heart play on Body")


func loop(set_id: String) -> AudioStreamPlayer:
	return body._loops[set_id]


func check_breathing() -> void:
	await seconds(settings.viv_breath_crossfade + 0.3)
	check(body.mood == BodyAudio.CALM and near(body.weights[BodyAudio.CALM], 1.0, 0.001) and loop(BodyAudio.CALM).playing
		and not loop(BodyAudio.NERVOUS).playing and not loop(BodyAudio.PANIC).playing, "With nothing after her she breathes calmly")
	check(near(loop(BodyAudio.CALM).volume_db, SoundLibrary.gain_db(BodyAudio.CALM) + float(settings.viv_breath_db[BodyAudio.CALM]), 0.1)
		and loop(BodyAudio.CALM).volume_db <= 0.0, "At the level of its file, never turned up (%.1f dB)" % loop(BodyAudio.CALM).volume_db)
	# What each moment asks for.
	var wanted := {Dread.Awareness.UNAWARE: BodyAudio.CALM, Dread.Awareness.PAUSED: BodyAudio.CALM, Dread.Awareness.HEARD: BodyAudio.NERVOUS,
		Dread.Awareness.SEARCHING: BodyAudio.NERVOUS, Dread.Awareness.HUNTING: BodyAudio.PANIC}
	var before: int = Dread.awareness
	var right := true
	for awareness: int in wanted:
		Dread.awareness = awareness
		right = right and body.wanted_mood() == wanted[awareness]
	Dread.awareness = before
	check(right, "Calm while it is unaware, nervous once it has heard something or searches, panicked while it hunts")
	# Sprinting.
	player.set_physics_process(false)
	player.is_sprinting = true
	await seconds(settings.viv_breath_crossfade * 0.5)
	check(body.mood == BodyAudio.PANIC and loop(BodyAudio.CALM).playing and loop(BodyAudio.PANIC).playing
		and body.weights[BodyAudio.CALM] > 0.2 and body.weights[BodyAudio.CALM] < 0.8 and body.weights[BodyAudio.PANIC] > 0.2,
		"Sprinting, her breathing crosses over to panic: halfway, both are heard")
	await seconds(settings.viv_breath_crossfade * 0.5 + 0.3)
	check(not loop(BodyAudio.CALM).playing and near(body.weights[BodyAudio.PANIC], 1.0, 0.001), "After 1.5 s only the panic is left")
	player.is_sprinting = false
	player.set_physics_process(true)
	await seconds(settings.viv_breath_crossfade + 0.3)
	check(body.mood == BodyAudio.CALM and not loop(BodyAudio.PANIC).playing, "And back to calm once she stops")
	check(noises == 0, "Her breathing makes no noise the entity can hear")
	GameState.is_dead = true
	await seconds(settings.viv_breath_hold_fade + 0.2)
	check(body.mood == "" and loop(BodyAudio.CALM).volume_db <= BodyAudio.SILENT_DB, "Dead, she does not breathe")
	GameState.reset()
	await seconds(settings.viv_breath_return + 0.3)


func cutoffs() -> Array:
	return BodyAudio.SOFTENED.map(func(bus_name: StringName) -> float: return MixDirector.cutoff_hz(bus_name))


func check_listening() -> void:
	check(is_zero_approx(body.listen) and cutoffs().all(func(hz: float) -> bool: return near(hz, settings.open_hz, 1.0)), "Breathing, the house is open")
	noises = 0
	Input.action_press("hold_breath")
	await frames(2)
	check(breath.is_holding, "She holds her breath")
	await seconds(settings.listen_in * 0.5)
	var halfway: Array = cutoffs()
	check(body.listen > 0.2 and body.listen < 0.9 and halfway.all(func(hz: float) -> bool: return hz < settings.open_hz - 100.0 and hz > settings.listen_cutoff_hz + 100.0),
		"The house starts to go soft at once, not in a step (%.0f Hz halfway)" % halfway[0])
	await seconds(settings.listen_in * 0.5 + maxf(settings.viv_breath_hold_fade, 0.1) + 0.15)
	check(near(body.listen, 1.0, 0.001) and near(Acoustics.focus, 1.0, 0.001) and cutoffs().all(func(hz: float) -> bool: return near(hz, settings.listen_cutoff_hz, 5.0)),
		"After 0.3 s Music, Ambience and World are low-passed to 2500 Hz")
	check(near(MixDirector.gain_db(AudioBus.ENTITY), settings.listen_entity_db, 0.01) and near(MixDirector.gain_db(AudioBus.ENTITY_FAR), settings.listen_entity_db, 0.01)
		and MixDirector.muffle_filter(AudioBus.ENTITY) == null and MixDirector.muffle_filter(AudioBus.ENTITY_FAR) == null,
		"The entity comes up 2 dB and is never dulled")
	check(body.open <= 0.001 and loop(BodyAudio.CALM).volume_db <= BodyAudio.SILENT_DB, "And her own breathing has stopped")
	check(noises == 0, "Listening makes no noise")
	# Let go early.
	Input.action_release("hold_breath")
	await frames(2)
	await seconds(settings.listen_out * 0.5)
	check(body.listen > 0.1 and body.listen < 0.8 and MixDirector.cutoff_hz(AudioBus.WORLD) > settings.listen_cutoff_hz + 100.0,
		"Letting go, the house comes back over half a second (%.2f halfway)" % body.listen)
	await seconds(settings.listen_out * 0.5 + 0.2)
	check(is_zero_approx(body.listen) and is_zero_approx(Acoustics.focus) and cutoffs().all(func(hz: float) -> bool: return near(hz, settings.open_hz, 1.0))
		and is_zero_approx(MixDirector.gain_db(AudioBus.ENTITY)) and not MixDirector.is_active(BodyAudio.LISTEN) and not MixDirector.is_active(BodyAudio.LISTEN_FOCUS),
		"And is fully open again")
	check(breath.is_sounding() and breath._audio_player.stream.resource_path.begins_with(SoundLibrary.ROOT + "viv/exhale/") and body.open <= 0.001,
		"Her breath out is one of her own, with no breathing loop under it")
	for tick in 400:
		if not breath.is_sounding(): break
		await frames(1)
	await seconds(settings.viv_breath_return + 0.2)
	check(near(body.open, 1.0, 0.001) and loop(BodyAudio.CALM).volume_db > BodyAudio.SILENT_DB, "Then she breathes again")
	# Out of air: it snaps back.
	breath.lung_percent = 100.0
	Input.action_press("hold_breath")
	await seconds(settings.listen_in + 0.2)
	check(near(body.listen, 1.0, 0.001), "Holding again, she listens again")
	gasps = 0
	breath.lung_percent = 0.5
	var snapped := false
	for tick in 30:
		await frames(1)
		if gasps > 0:
			snapped = is_zero_approx(body.listen) and is_zero_approx(Acoustics.focus) and near(MixDirector.cutoff_hz(AudioBus.WORLD), settings.open_hz, 1.0)
			break
	check(gasps == 1 and snapped, "A forced gasp snaps the house back at once")
	Input.action_release("hold_breath")
	await seconds(breath.forced_lock_duration + 0.2)
	breath.lung_percent = 100.0
	breath.exertion_percent = 0.0


func check_masking() -> void:
	player.set_physics_process(false)
	check(is_zero_approx(body.mask_db) and is_zero_approx(Acoustics.mask_db), "Standing still, nothing is covered")
	player.velocity = Vector2(Units.to_px(player.walk_speed_u), 0.0)
	await seconds(settings.mask_on_time + 0.2)
	check(near(body.mask_db, settings.mask_walk_db, 0.01) and near(Acoustics.mask_db, settings.mask_walk_db, 0.01), "Walking covers 6 dB of what is far off")
	player.is_sprinting = true
	player.velocity = Vector2(Units.to_px(player.sprint_speed_u), 0.0)
	await seconds(settings.mask_on_time + 0.2)
	check(near(body.mask_db, settings.mask_sprint_db, 0.01), "Sprinting covers 12 dB")
	player.is_sprinting = false
	player.velocity = Vector2.ZERO
	await seconds(settings.mask_off_time * 0.4)
	check(body.mask_db < -3.0 and body.mask_db > settings.mask_sprint_db, "Stopping does not give it back at once (%.1f dB)" % body.mask_db)
	await seconds(settings.mask_off_time * 0.6 + 0.2)
	check(is_zero_approx(body.mask_db) and is_zero_approx(Acoustics.mask_db), "About a second of standing still does")
	player.set_physics_process(true)
	await frames(2)


## Her heart in a hunt and running out of air: one voice, louder and faster as the air runs out.
func check_one_heartbeat() -> void:
	var feedback: Node = player.get_node("BreathFeedback")
	var strain: Node = feedback.strain_audio
	var heart: Node = body.heart
	check(strain.get_node_or_null("Heart") == null and MusicDirector.get_node_or_null("ThreatHeartbeat") == null,
		"Running out of air and the music have no heartbeat of their own any more")
	# A stand-in that hunts: Dread reads it like any entity.
	var hunter := Hunter.new()
	add_child(hunter)
	hunter.set_physics_process(false)
	Dread.watch(hunter)
	await seconds(settings.threat_lag.y + settings.threat_rise_time + settings.heart_rise_time + 0.3)
	check(heart.playing and heart.bus == AudioBus.BODY and heart.reason == &"threat" and heart.level_db() > -30.0,
		"In a hunt her heart is heard, on Body (%.1f dB)" % heart.level_db())
	var alone: float = heart.level_db()
	var alone_pitch: float = heart.pitch_scale
	feedback.enabled = true
	breath.lung_percent = 24.0
	Input.action_press("hold_breath")
	for tick in 150:
		await frames(1)
		if breath.lung_percent < 12.0: breath.lung_percent = 12.0
	check(strain.level > 0.6 and heart.reason == &"strain" and heart.playing and heart.level_db() > alone + 3.0 and heart.pitch_scale > alone_pitch,
		"Running out of air makes the same heart louder and faster (%.2f: %.1f dB, speed %.2f)" % [strain.level, heart.level_db(), heart.pitch_scale])
	check(MixDirector.cutoff_hz(AudioBus.MUSIC) < settings.listen_cutoff_hz - 100.0 and near(MixDirector.cutoff_hz(AudioBus.WORLD), settings.listen_cutoff_hz, 5.0),
		"Running out of air takes the soft house further on Music and Ambience (%.0f Hz), never back up" % MixDirector.cutoff_hz(AudioBus.MUSIC))
	breath.lung_percent = 60.0
	Input.action_release("hold_breath")
	await seconds(1.0 + settings.listen_out)
	check(strain.level <= 0.01 and heart.reason == &"threat" and heart.playing and near(heart.level_db(), alone, 0.5),
		"Breathing again, it is back at the hunt's level (%.1f dB)" % heart.level_db())
	hunter.current_state = EntityAudio.PATROL
	hunter.velocity = Vector2(Units.to_px(2.0), 0.0)
	var hunting: float = heart.get(&"amount")
	await seconds(settings.threat_lag.y + 2.0)
	check(heart.playing and float(heart.get(&"amount")) < hunting - 0.05, "After the hunt it calms as the threat falls (%.2f)" % heart.get(&"amount"))
	hunter.queue_free()
	GameState.reset()
	await frames(3)
	check(not heart.playing, "And a new attempt starts with it silent")
	breath.lung_percent = 100.0
	breath.exertion_percent = 0.0
	for tick in 400:
		if not breath.is_sounding(): break
		await frames(1)


## With the entity in the house: what her listening and her moving do to what she hears of it.
func check_in_the_house() -> void:
	GameState.reset()
	var game: Node2D = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	var entity: CharacterBody2D = game.entity
	var audio: EntityAudio = entity.audio
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	var house: Vector2 = game.world.zones["house"].global_position
	var viv: CharacterBody2D = game.player
	var her_body: BodyAudio = viv.get_node("BodyAudio")
	viv.set_physics_process(false)
	var route: Array[Vector2] = [house + VESTIBULE_A]
	entity.reset_encounter(house + KITCHEN_BY_WALL, route)
	entity.show()
	entity.set_physics_process(false)
	viv.global_position = house + VESTIBULE_BY_WALL
	await frames(2)
	audio.placed()
	await frames(1)
	check(audio.heard_ring == 1 and is_zero_approx(audio.masked_db()), "It is a room away, and she stands still (%.1f u)" % audio.heard_u)
	var limit: float = settings.ring_somewhere_u
	# Standing still: the plain share of its steps.
	var plain := 0
	for index in TRIES:
		if audio.play_set(STEP) != null: plain += 1
	var step: AudioStreamPlayer2D = null
	while step == null: step = audio.play_set(STEP)
	var still_db: float = step.volume_db
	var cue_still: float = audio._play_heard().volume_db
	# Walking: 6 dB less of what is far off; what it knows is untouched.
	viv.velocity = Vector2(Units.to_px(viv.walk_speed_u), 0.0)
	await seconds(settings.mask_on_time + 0.2)
	step = null
	while step == null: step = audio.play_set(STEP)
	check(near(audio.masked_db(), settings.mask_walk_db, 0.05) and near(step.volume_db, still_db + settings.mask_walk_db, 0.3),
		"While she walks its far-off steps are 6 dB quieter (%.1f against %.1f dB)" % [step.volume_db, still_db])
	check(near(audio._play_heard().volume_db, cue_still, 0.01) and step.bus != AudioBus.MUSIC, "The heard-you cue is not covered by her walking")
	viv.is_sprinting = true
	viv.velocity = Vector2(Units.to_px(viv.sprint_speed_u), 0.0)
	await seconds(settings.mask_on_time + 0.2)
	step = null
	while step == null: step = audio.play_set(STEP)
	check(near(step.volume_db, still_db + settings.mask_sprint_db, 0.3), "And 12 dB quieter while she sprints (%.1f dB)" % step.volume_db)
	viv.is_sprinting = false
	viv.velocity = Vector2.ZERO
	await seconds(settings.mask_off_time + 0.3)
	check(is_zero_approx(audio.masked_db()), "A second after she stops they are back")
	# In the same room nothing is covered.
	entity.global_position = house + VESTIBULE_A
	viv.global_position = house + VESTIBULE_B
	await frames(2)
	audio.placed()
	viv.velocity = Vector2(Units.to_px(viv.walk_speed_u), 0.0)
	await seconds(settings.mask_on_time + 0.2)
	check(audio.heard_ring == 2 and near(Acoustics.mask_db, settings.mask_walk_db, 0.05) and is_zero_approx(audio.masked_db()),
		"In the same room her walking covers nothing of it")
	viv.velocity = Vector2.ZERO
	# Holding her breath to listen.
	entity.global_position = house + KITCHEN_BY_WALL
	viv.global_position = house + VESTIBULE_BY_WALL
	await frames(2)
	audio.placed()
	await seconds(settings.mask_off_time + 0.3)
	audio.stop_all()
	Input.action_press("hold_breath")
	await seconds(settings.listen_in + 0.3)
	check(viv.get_node("HoldBreath").is_holding and near(her_body.listen, 1.0, 0.001) and near(audio.reach_limit_u(), limit * settings.listen_reach_factor, 0.01),
		"Holding her breath, ring 1 reaches 1.3 times further (%.1f u)" % audio.reach_limit_u())
	var beyond: float = (limit + audio.reach_limit_u()) * 0.5
	check(EntityAudio.position_db(beyond, limit) <= EntityAudio.GONE_DB and EntityAudio.position_db(beyond, audio.reach_limit_u()) > EntityAudio.SILENT_DB
		and EntityAudio.chance_through(beyond, audio.reach_limit_u(), false) > 0.0,
		"What was just out of earshot (%.1f u) can now be heard" % beyond)
	var listening := 0
	for index in TRIES:
		if audio.play_set(STEP) != null: listening += 1
	var expected: float = 1.0 - (1.0 - EntityAudio.chance_through(audio.heard_u, audio.reach_limit_u(), false)) * settings.listen_gap_factor
	check(listening > plain and near(float(listening) / TRIES, expected, 0.1),
		"Fewer of its steps are lost: %d in %d against %d standing still (about %.2f expected)" % [listening, TRIES, plain, expected])
	step = null
	while step == null: step = audio.play_set(STEP)
	check(step.volume_db > still_db and near(MixDirector.gain_db(AudioBus.ENTITY_FAR), settings.listen_entity_db, 0.01) and step.panning_strength > settings.far_panning,
		"And what gets through is louder and better placed (%.1f against %.1f dB)" % [step.volume_db, still_db])
	check(near(MixDirector.cutoff_hz(AudioBus.WORLD), settings.listen_cutoff_hz, 5.0) and MixDirector.muffle_filter(AudioBus.ENTITY) == null,
		"While the house is soft, the entity is not")
	Input.action_release("hold_breath")
	await seconds(settings.listen_out + 0.3)
	check(near(audio.reach_limit_u(), limit, 0.01) and is_zero_approx(MixDirector.gain_db(AudioBus.ENTITY)), "Breathing again, it is as before")
	# Her breathing follows what it knows.
	audio.stop_all()
	entity.active = true
	entity.set_physics_process(true)
	entity._on_noise_emitted(viv.global_position, Units.to_px(60.0), NoiseManager.SourceType.ENVIRONMENT, 0.0)
	await frames(4)
	check(Dread.awareness == Dread.Awareness.HEARD and her_body.mood == BodyAudio.NERVOUS, "When it hears something, her breathing turns nervous")
	var hunted := false
	for tick in 240:
		await frames(1)
		if Dread.awareness == Dread.Awareness.HUNTING:
			await frames(2)
			hunted = her_body.mood == BodyAudio.PANIC
			break
	check(hunted, "When it hunts, panicked")
	game.queue_free()
	await frames(3)
