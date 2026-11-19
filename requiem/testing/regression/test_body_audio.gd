extends Node2D
## Viv's body and her listening (headless).
## Her breath clips are her own sets, on Body, with the noise they make unchanged, and no take
## plays twice running. Her breathing: calm or nervous by what the entity knows, quiet; panting
## only while she sprints past the exertion warning (the HUD's number too), louder as she tires,
## with a short tail; it stops while she holds her breath. Holding her
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
var radii: Array[float] = []
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
	NoiseManager.noise_emitted.connect(_on_noise)
	check_settings()
	check_scene()
	await set_up_alone()
	await check_breathing()
	await check_listening()
	await check_masking()
	await check_one_heartbeat()
	await check_no_repeat()
	player.queue_free()
	await frames(3)
	check(is_zero_approx(Acoustics.focus) and is_zero_approx(Acoustics.mask_db) and not MixDirector.is_active(BodyAudio.LISTEN),
		"When she leaves, nothing of her listening is left behind")
	await check_in_the_house()
	print("[Body audio tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func _on_noise(_at: Vector2, radius: float, _source: int, _duration: float) -> void:
	noises += 1
	radii.append(radius)


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
	for set_id in BodyAudio.LOOPS:
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
		and not loop(BodyAudio.NERVOUS).playing and not loop(BodyAudio.PANT).playing, "With nothing after her she breathes calmly")
	check(near(loop(BodyAudio.CALM).volume_db, SoundLibrary.gain_db(BodyAudio.CALM) + float(settings.viv_breath_db[BodyAudio.CALM]), 0.1)
		and loop(BodyAudio.CALM).volume_db <= 0.0, "At the level of its file plus its trim, never turned up (%.1f dB)" % loop(BodyAudio.CALM).volume_db)
	check(float(settings.viv_breath_db[BodyAudio.CALM]) <= -12.0 and float(settings.viv_breath_db[BodyAudio.NERVOUS]) <= -8.0
		and not settings.viv_breath_db.has(BodyAudio.PANT), "Calm is at least 12 dB under its file, nervous at least 8 dB; the panting has its own level")
	check(settings.viv_pant_db.x <= settings.viv_pant_db.y and settings.viv_pant_db.y <= 0.0
		and near(settings.viv_pant_in, 2.0, 0.001) and near(settings.viv_pant_tail, 2.5, 0.001),
		"The panting goes from %.0f dB at the warning to %.0f dB before the gasp, never turned up; in over 2 s, a 2.5 s tail" % [settings.viv_pant_db.x, settings.viv_pant_db.y])
	check(near(breath.exertion_warn_percent, 65.0, 0.001) and near(body.warning_percent(), breath.exertion_warn_percent, 0.001),
		"Her panting starts at the player's one exertion warning (65 %)")
	var hold_source := FileAccess.get_file_as_string("res://player/hold_breath.gd")
	check(hold_source.count("exertion_warn_percent") == 1, "Nothing about the mechanic reads the warning: it is only declared in HoldBreath")
	# What each moment asks for.
	var wanted := {Dread.Awareness.UNAWARE: BodyAudio.CALM, Dread.Awareness.PAUSED: BodyAudio.CALM, Dread.Awareness.HEARD: BodyAudio.NERVOUS,
		Dread.Awareness.SEARCHING: BodyAudio.NERVOUS, Dread.Awareness.HUNTING: BodyAudio.NERVOUS}
	var before: int = Dread.awareness
	var right := true
	for awareness: int in wanted:
		Dread.awareness = awareness
		right = right and body.wanted_mood() == wanted[awareness]
	Dread.awareness = before
	check(right, "Calm while it is unaware or paused, nervous once it has heard something, searches or hunts")
	# Nervous, with a stand-in that searches and then hunts.
	var hunter := Hunter.new()
	hunter.current_state = EntityAudio.SEARCH
	add_child(hunter)
	hunter.set_physics_process(false)
	Dread.watch(hunter)
	await seconds(settings.viv_breath_crossfade + 0.3)
	check(body.mood == BodyAudio.NERVOUS and loop(BodyAudio.NERVOUS).playing and not loop(BodyAudio.CALM).playing
		and near(loop(BodyAudio.NERVOUS).volume_db, SoundLibrary.gain_db(BodyAudio.NERVOUS) + float(settings.viv_breath_db[BodyAudio.NERVOUS]), 0.1)
		and loop(BodyAudio.NERVOUS).volume_db <= 0.0, "While it searches she breathes nervously, at its file plus its trim (%.1f dB)" % loop(BodyAudio.NERVOUS).volume_db)
	hunter.current_state = EntityAudio.HUNT
	await seconds(1.0)
	check(Dread.awareness == Dread.Awareness.HUNTING and body.mood == BodyAudio.NERVOUS and is_zero_approx(body.pant)
		and not loop(BodyAudio.PANT).playing, "While it hunts, still nervous: no panting while she is not tired")
	hunter.queue_free()
	await seconds(settings.viv_breath_crossfade + 0.3)
	check(body.mood == BodyAudio.CALM and near(body.weights[BodyAudio.CALM], 1.0, 0.001), "Calm again once it is gone")
	# Sprinting from rested: nothing yet.
	breath.exertion_percent = 0.0
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.is_sprinting = true
	await seconds(3.0)
	check(breath.exertion_percent > 10.0 and breath.exertion_percent < breath.exertion_warn_percent and is_zero_approx(body.pant)
		and not loop(BodyAudio.PANT).playing and near(body.weights[BodyAudio.CALM], 1.0, 0.001) and loop(BodyAudio.CALM).playing,
		"Three seconds of sprinting from rested (%.0f %%): no panting, her calm breathing in full" % breath.exertion_percent)
	# Just past the warning: the panting comes in gently.
	var warning: float = breath.exertion_warn_percent
	await hold_exertion(warning + 0.5, settings.viv_pant_in * 0.5)
	var total: float = body.weights[BodyAudio.CALM] + body.weights[BodyAudio.NERVOUS] + body.weights[BodyAudio.PANT]
	check(body.pant > 0.3 and body.pant < 0.7 and loop(BodyAudio.CALM).playing and loop(BodyAudio.PANT).playing and near(total, 1.0, 0.001),
		"Just past the warning the panting comes in: halfway both are heard (%.2f) and they add up to 1" % body.pant)
	await hold_exertion(warning + 0.5, settings.viv_pant_in * 0.5 + 0.3)
	check(near(body.pant, 1.0, 0.001) and not loop(BodyAudio.CALM).playing and is_zero_approx(body.weights[BodyAudio.CALM])
		and near(loop(BodyAudio.PANT).volume_db, SoundLibrary.gain_db(BodyAudio.PANT) + settings.viv_pant_db.x, 0.2) and loop(BodyAudio.PANT).volume_db <= 0.0,
		"After %.0f s only the panting is up, at its quiet level (%.1f dB)" % [settings.viv_pant_in, loop(BodyAudio.PANT).volume_db])
	# It builds with how tired she is.
	var rising := true
	var last := -INF
	var percent := warning + 0.5
	while percent < 99.9:
		breath.exertion_percent = percent
		rising = rising and body.trim_db(BodyAudio.PANT) >= last - 0.0001
		last = body.trim_db(BodyAudio.PANT)
		percent += 0.5
	breath.exertion_percent = 82.5
	var halfway: float = body.trim_db(BodyAudio.PANT)
	breath.exertion_percent = 99.0
	var at_99: float = body.trim_db(BodyAudio.PANT)
	check(rising and near(halfway, (settings.viv_pant_db.x + settings.viv_pant_db.y) * 0.5, 0.01) and near(at_99, settings.viv_pant_db.y, 0.3),
		"The panting builds and never falls as she tires: %.1f dB at 82.5 %%, %.1f dB at 99 %%" % [halfway, at_99])
	await hold_exertion(95.0, 0.2)
	check(near(loop(BodyAudio.PANT).volume_db, SoundLibrary.gain_db(BodyAudio.PANT) + body.trim_db(BodyAudio.PANT), 0.2)
		and loop(BodyAudio.PANT).volume_db > SoundLibrary.gain_db(BodyAudio.PANT) + settings.viv_pant_db.x + 3.0 and loop(BodyAudio.PANT).volume_db <= 0.0,
		"Near the gasp it is louder (%.1f dB), still never turned up" % loop(BodyAudio.PANT).volume_db)
	# The tail.
	player.is_sprinting = false
	await hold_exertion(80.0, settings.viv_pant_tail * 0.4)
	check(body.pant > 0.3 and loop(BodyAudio.PANT).playing, "She stops sprinting, still tired: the panting does not stop at once (%.2f)" % body.pant)
	await hold_exertion(80.0, settings.viv_pant_tail * 0.6 + 0.3)
	check(is_zero_approx(body.pant) and not loop(BodyAudio.PANT).playing and near(body.weights[BodyAudio.CALM], 1.0, 0.001) and loop(BodyAudio.CALM).playing,
		"After a %.1f s tail it is gone and her calm breathing is back" % settings.viv_pant_tail)
	check(noises == 0, "Her breathing makes no noise the entity can hear")
	# Walking while tired: no panting. Sprinting again while tired: straight back.
	player.velocity = Vector2(Units.to_px(player.walk_speed_u), 0.0)
	await hold_exertion(80.0, settings.viv_pant_in + 0.3)
	check(is_zero_approx(body.pant) and not loop(BodyAudio.PANT).playing, "Walking with her exertion high, she does not pant")
	player.is_sprinting = true
	player.velocity = Vector2(Units.to_px(player.sprint_speed_u), 0.0)
	await hold_exertion(80.0, settings.viv_pant_in + 0.2)
	check(near(body.pant, 1.0, 0.001) and loop(BodyAudio.PANT).playing, "Sprinting again while still tired, the panting is back within %.0f s" % settings.viv_pant_in)
	player.is_sprinting = false
	player.velocity = Vector2.ZERO
	await hold_exertion(75.0, settings.viv_pant_tail + 0.3)
	# Holding her breath past the warning: no panting, her breathing closed.
	player.set_physics_process(true)
	Input.action_press("hold_breath")
	await hold_exertion(75.0, settings.viv_pant_in + 0.3)
	check(breath.is_holding and is_zero_approx(body.pant) and not loop(BodyAudio.PANT).playing and body.open <= 0.001
		and loop(BodyAudio.CALM).volume_db <= BodyAudio.SILENT_DB, "Holding her breath past the warning: no panting, and her breathing closed as before")
	Input.action_release("hold_breath")
	await frames(2)
	for tick in 400:
		if not breath.is_sounding(): break
		await frames(1)
	breath.exertion_percent = 0.0
	breath.lung_percent = 100.0
	await seconds(settings.viv_breath_return + 0.3)
	# The forced gasp at 100 % while she sprints.
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.is_sprinting = true
	await hold_exertion(90.0, settings.viv_pant_in + 0.3)
	check(near(body.pant, 1.0, 0.001), "Sprinting at 90 %, she pants")
	noises = 0
	radii.clear()
	gasps = 0
	for tick in 600:
		await frames(1)
		if gasps > 0: break
	check(gasps == 1 and noises == 1 and near(radii[0] if not radii.is_empty() else 0.0, Units.to_px(breath.forced_gasp_radius_u), 0.01)
		and is_zero_approx(breath.exertion_percent) and breath.is_locked,
		"At 100 %% the forced gasp: one gasp, one noise of %.0f u, her exertion back to 0" % breath.forced_gasp_radius_u)
	var pant_db: float = loop(BodyAudio.PANT).volume_db
	var never_up := true
	var closed_under := true
	var elapsed := 0.0
	while elapsed < settings.viv_pant_tail + 1.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		never_up = never_up and loop(BodyAudio.PANT).volume_db <= pant_db + 0.001
		pant_db = loop(BodyAudio.PANT).volume_db
		if elapsed > settings.viv_breath_hold_fade + 0.05 and breath.is_sounding():
			closed_under = closed_under and body.open <= 0.001
	check(closed_under and breath._audio_player.stream != null, "Her breathing is closed under the gasp clip")
	check(never_up and is_zero_approx(body.pant) and not loop(BodyAudio.PANT).playing and not body.is_tired(),
		"After the gasp the panting only fades, at its quietest, and does not come back while she is not tired")
	player.is_sprinting = false
	player.set_physics_process(true)
	for tick in 400:
		if not breath.is_sounding(): break
		await frames(1)
	breath.exertion_percent = 0.0
	await seconds(settings.viv_breath_return + 0.3)
	check(near(body.open, 1.0, 0.001) and near(body.weights[BodyAudio.CALM], 1.0, 0.001) and loop(BodyAudio.CALM).playing,
		"Then her calm breathing returns: she has settled")
	# The one number.
	breath.exertion_warn_percent = 40.0
	player.set_physics_process(false)
	player.is_sprinting = true
	await hold_exertion(39.5, settings.viv_pant_in)
	var not_yet := is_zero_approx(body.pant)
	await hold_exertion(41.0, settings.viv_pant_in + 0.3)
	check(not_yet and near(body.pant, 1.0, 0.001) and near(body.trim_db(BodyAudio.PANT), settings.viv_pant_db.x, 0.3),
		"With the warning moved to 40 %, the panting starts just past 40 % (and enters quietly)")
	breath.exertion_warn_percent = 65.0
	player.is_sprinting = false
	await hold_exertion(0.0, settings.viv_pant_tail + 0.3)
	player.set_physics_process(true)
	await frames(2)
	GameState.is_dead = true
	await seconds(settings.viv_breath_hold_fade + 0.2)
	check(body.mood == "" and loop(BodyAudio.CALM).volume_db <= BodyAudio.SILENT_DB and loop(BodyAudio.PANT).volume_db <= BodyAudio.SILENT_DB,
		"Dead, she does not breathe")
	GameState.reset()
	await seconds(settings.viv_breath_return + 0.3)


## Keeps her exertion where it is for `time` seconds (it would rise or fall by itself), set
## before her BodyAudio reads it each frame.
func hold_exertion(percent: float, time: float) -> void:
	var elapsed := 0.0
	breath.exertion_percent = percent
	while elapsed < time:
		await get_tree().process_frame
		breath.exertion_percent = percent
		elapsed += get_process_delta_time()


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
			hunted = her_body.mood == BodyAudio.NERVOUS and is_zero_approx(her_body.pant)
			break
	check(hunted, "When it hunts, still nervous, and no panting while she is not tired")
	await check_hud_warning(game, her_body)
	game.queue_free()
	await frames(3)


## The HUD's exertion bar pulses past the same one number that starts her panting.
func check_hud_warning(game: Node2D, her_body: BodyAudio) -> void:
	var vitals: Node = game.hud.get_node("Screen/Vitals")
	var her_breath: Node = game.player.get_node("HoldBreath")
	var warning: float = her_breath.exertion_warn_percent
	check(not (&"exertion_warn" in vitals) and near(her_body.warning_percent(), warning, 0.001),
		"The HUD has no warning of its own: it and her panting read HoldBreath's (%.0f %%)" % warning)
	var at_warning := await exertion_pulses(her_breath, vitals, warning)
	var past_warning := await exertion_pulses(her_breath, vitals, warning + 2.0)
	check(not at_warning and past_warning, "The HUD's exertion bar is still at the warning and pulses just past it")
	her_breath.exertion_warn_percent = 40.0
	var at_new := await exertion_pulses(her_breath, vitals, 40.0)
	var past_new := await exertion_pulses(her_breath, vitals, 42.0)
	check(not at_new and past_new and near(her_body.warning_percent(), 40.0, 0.001),
		"Moving the one number to 40 %% moves the HUD's warning and her panting together")
	her_breath.exertion_warn_percent = warning
	her_breath.exertion_percent = 0.0


## Holds her exertion at `percent` for a second: true if the HUD's exertion bar pulsed.
func exertion_pulses(her_breath: Node, vitals: Node, percent: float) -> bool:
	var bar: ProgressBar = vitals.get_node("Exertion/Meter")
	var lowest := 1.0
	var elapsed := 0.0
	her_breath.exertion_percent = percent
	await get_tree().process_frame
	while elapsed < 1.0:
		her_breath.exertion_percent = percent
		await get_tree().process_frame
		lowest = minf(lowest, bar.modulate.a)
		elapsed += get_process_delta_time()
	return lowest < 0.98


## No take of hers plays twice running: SoundLibrary.pick_from, and the real users of it.
func check_no_repeat() -> void:
	var three: Array = [AudioStreamWAV.new(), AudioStreamWAV.new(), AudioStreamWAV.new()]
	var two: Array = [AudioStreamWAV.new(), AudioStreamWAV.new()]
	var one: Array = [AudioStreamWAV.new()]
	var fine := true
	for list: Array in [two, three]:
		var seen := {}
		var last: AudioStream = null
		for draw in 300:
			var clip := SoundLibrary.pick_from("test:%d" % list.size(), list)
			fine = fine and clip != last and list.has(clip)
			seen[clip] = true
			last = clip
		fine = fine and seen.size() == list.size()
	check(fine, "From two or three takes, never the same twice running, and every take is heard")
	var single := true
	for draw in 20:
		single = single and SoundLibrary.pick_from("test:one", one) == one[0]
	check(single and SoundLibrary.pick_from("test:none", []) == null, "One take always gives that take; none gives nothing")
	var apart := true
	var last_a: AudioStream = null
	var last_b: AudioStream = null
	for draw in 200:
		var a := SoundLibrary.pick_from("test:a", three)
		var b := SoundLibrary.pick_from("test:b", three)
		apart = apart and a != last_a and b != last_b
		last_a = a
		last_b = b
	check(apart, "Two lists remember their last take apart from each other")
	SoundLibrary.clear()
	check(not SoundLibrary._last_pick.has(SoundLibrary.LIST_KEY + "test:a"), "Clearing the library forgets them too")
	# Her breath in through the real player: 50 plays.
	var never_twice := true
	var previous: AudioStream = null
	for play in 50:
		breath._play_random_clip(breath.hold_clips)
		var stream: AudioStream = breath._audio_player.stream
		never_twice = never_twice and stream != previous and stream.resource_path.begins_with(SoundLibrary.ROOT + "viv/hold_in/")
		previous = stream
	var alternates := true
	for play in 20:
		breath._play_random_clip(breath.exhale_clips)
		alternates = alternates and breath._audio_player.stream != previous
		previous = breath._audio_player.stream
	breath._audio_player.stop()
	check(never_twice and alternates, "Fifty breaths in and twenty breaths out: never the same take twice running")
	for path in ["res://player/hold_breath.gd", "res://player/throw.gd", "res://player/flashlight.gd", "res://altar/body_altar.gd"]:
		var source := FileAccess.get_file_as_string(path)
		check(source.contains("SoundLibrary.pick_from(") and not source.contains("[randi() %"), "%s chooses its takes with the no-repeat rule" % path.get_file())
	await frames(2)
