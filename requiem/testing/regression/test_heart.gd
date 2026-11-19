extends Node2D
## Viv's heart (headless): one heartbeat, three reasons.
## It follows the highest of running out of air, what the entity knows (threat) and how near it
## is (presence). An unaware entity near her raises a quiet heartbeat; a far one, or a pause on
## its patrol, raises none. Searching is louder than near, a hunt louder still, no air left the
## loudest, and never above its cap. It comes in from silence and moves smoothly, steps back
## while she holds her breath, stops when she dies and on a new attempt. There is exactly one
## heartbeat voice in the game, and it never makes a noise the entity can hear.

const HEART_FILE := "heartbeat"
const HeartAudio := preload("res://player/heart_audio.gd")

## A stand-in entity: Dread reads what it knows from these few members only.
class FakeEntity extends CharacterBody2D:
	var current_state := EntityAudio.PATROL
	var active := true
	var listening := false
	func is_listening() -> bool:
		return listening

var failures: Array[String] = []
var checks := 0
var settings: SoundSettings
var player: CharacterBody2D
var breath: Node
var body: BodyAudio
var heart: HeartAudio
var entity: FakeEntity
var noises := 0
## Breath releases and gasps of her own during the suite: the only noise she may make.
var own_breath := 0


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
	await set_up()
	await check_silent()
	check_one_voice("With her standing alone")
	await check_presence()
	await check_far_and_paused()
	var heard_db: float = await settle_on(Dread.Awareness.HEARD)
	var search_db: float = await settle_on(Dread.Awareness.SEARCHING)
	var hunt_db: float = await settle_on(Dread.Awareness.HUNTING)
	check(near(hunt_db, -13.0, 1.0) and heart.bus == AudioBus.BODY,
		"In a hunt her heart is where the hunt heartbeat always was: about -13 dB on Body (%.1f dB)" % hunt_db)
	check(presence_db < heard_db and heard_db < search_db and search_db < hunt_db,
		"Near (%.1f) < it heard something (%.1f) < it searches (%.1f) < it hunts (%.1f dB)" % [presence_db, heard_db, search_db, hunt_db])
	await check_listening(hunt_db)
	await check_strain(hunt_db)
	await check_calming()
	await check_rise()
	await check_dead_and_reset()
	check(noises <= own_breath, "Her heart made no noise the entity can hear (%d noises, %d of her own breath)" % [noises, own_breath])
	# Leave nothing behind.
	Input.action_release("hold_breath")
	Dread.report_presence(self, 0.0)
	entity.queue_free()
	player.queue_free()
	GameState.reset()
	await frames(3)
	print("[Heart tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func check_settings() -> void:
	check(settings.heart_db == Vector2(-30.0, -3.0) and settings.heart_db.y <= 0.0, "Her heart goes from -30 dB to its cap, -3 dB")
	check(near(settings.heart_rise_time, 0.65, 0.001) and near(settings.heart_fall_time, 0.25, 0.001), "It builds over 0.65 s and lets go over 0.25 s")
	check(settings.heart_threat_from > settings.threat_paused, "A pause on its patrol (threat %.1f) is below where the heart starts" % settings.threat_paused)
	check(settings.heart_presence.y < settings.heart_threat.x + 0.1 and settings.heart_strain.y == 1.0,
		"Near by ear stays quiet; only running out of air reaches the cap")
	var source := FileAccess.get_file_as_string("res://player/heart_audio.gd")
	check(not source.contains("NoiseManager") and not source.contains("AudioServer") and not source.contains("global_position"),
		"heart_audio.gd makes no noise, touches no bus and never reads where anything is")


func set_up() -> void:
	player = preload("res://player/player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	breath = player.get_node("HoldBreath")
	body = player.get_node("BodyAudio")
	heart = body.heart as HeartAudio
	breath.breath_released.connect(func(_quiet: bool, _lung: float) -> void: own_breath += 1)
	breath.forced_gasp_started.connect(func(_reason: StringName, _duration: float) -> void: own_breath += 1)
	entity = FakeEntity.new()
	entity.velocity = Vector2(Units.to_px(2.0), 0.0)   # walking its patrol: unaware
	add_child(entity)
	entity.set_physics_process(false)
	Dread.watch(entity)
	await frames(3)
	check(heart != null and heart.name == "Heart" and heart.get_parent() == body and heart.get_class() == "AudioStreamPlayer",
		"Her heart is one voice under BodyAudio, not placed anywhere")


## Every AudioStreamPlayer in the game whose sound is a heartbeat.
func heartbeat_voices() -> Array[Node]:
	var found: Array[Node] = []
	for node in get_tree().root.find_children("*", "", true, false):
		var stream: Variant = node.get(&"stream") if (node is AudioStreamPlayer or node is AudioStreamPlayer2D) else null
		if stream is AudioStream and (stream as AudioStream).resource_path.contains(HEART_FILE):
			found.append(node)
	return found


func check_one_voice(when: String) -> void:
	var voices := heartbeat_voices()
	var strain: Node = player.get_node("BreathFeedback").strain_audio
	var in_music := MusicDirector.find_children("*", "", true, false).any(func(node: Node) -> bool:
		return node.get(&"stream") is AudioStream and (node.get(&"stream") as AudioStream).resource_path.contains(HEART_FILE))
	check(voices.size() == 1 and voices[0] == heart and not in_music and strain.get_node_or_null("Heart") == null,
		"%s: exactly one heartbeat voice exists, hers (%d found)" % [when, voices.size()])


func check_silent() -> void:
	await seconds(0.5)
	check(is_zero_approx(Dread.threat) and is_zero_approx(Dread.presence) and is_zero_approx(heart.amount) and not heart.playing
		and heart.reason == &"" and heart.level_db() <= HeartAudio.SILENT_DB, "Nothing after her, nothing near: no heartbeat")


var presence_db := 0.0

## The "done when": an unaware entity near her raises a quiet heartbeat.
func check_presence() -> void:
	Dread.report_presence(self, 1.0)
	var first_audible := 0.0
	var biggest_step := 0.0
	var last := heart.level_db()
	var began := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - began) / 1000000.0 < settings.presence_lag.y + settings.presence_time + 1.0:
		await frames(1)
		var now: float = heart.level_db()
		if heart.playing and first_audible == 0.0:
			first_audible = now
		if last >= settings.heart_db.x and now >= settings.heart_db.x:
			biggest_step = maxf(biggest_step, absf(now - last))
		last = now
	presence_db = heart.level_db()
	check(Dread.awareness == Dread.Awareness.UNAWARE and is_zero_approx(Dread.threat) and near(Dread.presence, 1.0, 0.001),
		"The entity is on top of her and knows nothing (presence %.2f, threat %.2f)" % [Dread.presence, Dread.threat])
	check(heart.playing and heart.bus == AudioBus.BODY and heart.reason == &"presence" and near(heart.amount, settings.heart_presence.y, 0.001),
		"An unaware entity near her raises a quiet heartbeat, on Body, for presence (%.2f, %s)" % [heart.amount, heart.reason])
	var search_amount: float = HeartAudio.push(settings.threat_searching, settings.heart_threat_from, settings.heart_threat)
	check(presence_db <= HeartAudio.level_for(settings.heart_presence.y) + 0.01 and presence_db < HeartAudio.level_for(search_amount) - 3.0,
		"Quiet: %.1f dB, clearly under a search (%.1f dB)" % [presence_db, HeartAudio.level_for(search_amount)])
	check(first_audible < settings.heart_db.x - 3.0 and biggest_step < 2.0,
		"It comes in from silence (first heard at %.1f dB) and rises smoothly (at most %.2f dB a frame)" % [first_audible, biggest_step])


func check_far_and_paused() -> void:
	# Far off by ear: below where presence starts.
	Dread.report_presence(self, settings.heart_presence_from - 0.1)
	GameState.reset()   # presence goes straight to what is reported
	await seconds(settings.heart_fall_time + 0.3)
	check(near(Dread.presence, settings.heart_presence_from - 0.1, 0.001) and is_zero_approx(heart.amount) and not heart.playing,
		"An entity further off (presence %.2f) raises no heartbeat" % Dread.presence)
	Dread.report_presence(self, 0.0)
	entity.velocity = Vector2.ZERO
	GameState.reset()
	await seconds(settings.threat_lag.y + settings.threat_rise_time + 0.3)
	check(Dread.awareness == Dread.Awareness.PAUSED and near(Dread.threat, settings.threat_paused, 0.001) and is_zero_approx(heart.amount) and not heart.playing,
		"A pause on its patrol (threat %.2f) raises none" % Dread.threat)


## Makes the stand-in know `awareness`, waits for threat and the heart to settle, returns the level.
func settle_on(awareness: int) -> float:
	entity.listening = awareness == Dread.Awareness.HEARD
	entity.current_state = {Dread.Awareness.SEARCHING: EntityAudio.SEARCH, Dread.Awareness.HUNTING: EntityAudio.HUNT}.get(awareness, EntityAudio.PATROL)
	await seconds(settings.threat_lag.y + settings.threat_rise_time + settings.heart_rise_time + 0.2)
	var wanted: float = HeartAudio.push(Dread.threat_for(awareness), settings.heart_threat_from, settings.heart_threat)
	check(Dread.awareness == awareness and heart.playing and heart.reason == &"threat" and near(heart.amount, wanted, 0.001),
		"%s: her heart beats for the threat (%.2f, %s, %.1f dB)" % [Dread.AWARENESS_NAMES[awareness], heart.amount, heart.reason, heart.level_db()])
	return heart.level_db()


func check_listening(hunt_db: float) -> void:
	breath.lung_percent = 100.0
	breath.exertion_percent = 0.0
	Input.action_press("hold_breath")
	await seconds(settings.listen_in + 0.4)
	check(breath.is_holding and heart.reason == &"threat" and is_zero_approx(heart.strain_amount)
		and near(heart.level_db(), hunt_db + settings.breath_duck_db, 0.5),
		"Holding her breath steps it back by %.0f dB, as the music (%.1f against %.1f dB)" % [settings.breath_duck_db, heart.level_db(), hunt_db])
	Input.action_release("hold_breath")
	await seconds(settings.listen_out + settings.heart_rise_time + 0.2)
	check(near(heart.level_db(), hunt_db, 0.5), "Letting go brings it back (%.1f dB)" % heart.level_db())
	for tick in 400:
		if not breath.is_sounding(): break
		await frames(1)


func check_strain(hunt_db: float) -> void:
	var hunt_pitch: float = heart.pitch_scale
	breath.lung_percent = 24.0
	Input.action_press("hold_breath")
	var loudest := -80.0
	var doubled := 0
	for tick in 150:
		await frames(1)
		if breath.lung_percent < 12.0: breath.lung_percent = 12.0
		loudest = maxf(loudest, heart.level_db())
		if heartbeat_voices().size() != 1: doubled += 1
	check(heart.reason == &"strain" and heart.strain_amount > heart.threat_amount and heart.level_db() > hunt_db + 3.0 and heart.pitch_scale > hunt_pitch,
		"As her air runs out the same heart takes over, louder and faster (%.1f dB, speed %.2f against %.2f)" % [heart.level_db(), heart.pitch_scale, hunt_pitch])
	# No air left at all, in the middle of a hunt: still one voice, never above its cap.
	for tick in 120:
		await frames(1)
		if breath.lung_percent < 2.0: breath.lung_percent = 2.0
		loudest = maxf(loudest, heart.level_db())
		if heartbeat_voices().size() != 1: doubled += 1
	check(loudest <= settings.heart_db.y + 0.001 and loudest > hunt_db + 6.0,
		"With almost no air left during a hunt it is the loudest it gets, and never above %.0f dB (%.1f dB)" % [settings.heart_db.y, loudest])
	check(doubled == 0, "A hunt and no air at once: still one heartbeat, never two")
	check_one_voice("Hunted and out of air")
	breath.lung_percent = 60.0
	Input.action_release("hold_breath")
	await seconds(1.0)
	check(heart.reason == &"threat" and near(heart.level_db(), hunt_db, 0.5) and heart.playing,
		"Breathing again, it hands back to the hunt (%.1f dB)" % heart.level_db())
	for tick in 400:
		if not breath.is_sounding(): break
		await frames(1)
	breath.lung_percent = 100.0
	breath.exertion_percent = 0.0


## After a hunt, the heart calms down as the threat falls; it does not stop on the spot.
func check_calming() -> void:
	entity.current_state = EntityAudio.PATROL
	entity.velocity = Vector2(Units.to_px(2.0), 0.0)
	var before: float = heart.amount
	await seconds(settings.threat_lag.y + 2.0)
	check(Dread.awareness == Dread.Awareness.UNAWARE and heart.playing and heart.amount < before - 0.05 and heart.amount > 0.0,
		"Once it gives up, her heart calms down as the threat falls (%.2f, was %.2f)" % [heart.amount, before])
	GameState.reset()
	await frames(1)
	check(is_zero_approx(heart.amount) and not heart.playing, "A new attempt: silent at once")


## From silence straight into a hunt, it takes about heart_rise_time of the way up.
func check_rise() -> void:
	entity.current_state = EntityAudio.HUNT
	GameState.reset()   # threat goes straight to a hunt; the heart starts from silence
	var target: float = settings.heart_threat.y
	var began := Time.get_ticks_usec()
	var took := -1.0
	for tick in 600:
		await frames(1)
		if heart.amount >= target - 0.001:
			took = (Time.get_ticks_usec() - began) / 1000000.0
			break
	check(took > 0.0 and near(took, settings.heart_rise_time * target, 0.1),
		"From silence to a hunt takes %.2f s (about %.2f expected): it builds, it never jumps" % [took, settings.heart_rise_time * target])


func check_dead_and_reset() -> void:
	check(heart.playing, "Hunted, it beats")
	GameState.is_dead = true
	await seconds(settings.heart_fall_time + 0.2)
	check(is_zero_approx(heart.amount) and not heart.playing, "Dead: silent")
	GameState.reset()
	check(is_zero_approx(heart.amount) and not heart.playing, "And still silent the moment she tries again")
	await frames(1)
	check(heart.amount < 0.1, "If it is still hunting, the heart builds again from silence (%.2f)" % heart.amount)
	entity.current_state = EntityAudio.PATROL
	entity.velocity = Vector2(Units.to_px(2.0), 0.0)
	GameState.reset()
	await frames(2)
