extends Node
## Fairness (headless): the player always knows what the entity knows.
## If it hears a sound, the heard-you cue plays and reaches Viv wherever she stands. A hunt
## never begins without its scream. Losing the trail and giving up each have their own cue.

const RADIUS_PROPERTIES := ["walk_noise_radius_u", "sprint_noise_radius_u", "held_noise_radius_u",
	"quiet_exhale_radius_u", "gasp_radius_u", "forced_gasp_radius_u", "impact_noise_radius_u",
	"click_noise_radius_u", "pray_noise_radius_u", "pulse_radius_u", "noise_radius_u", "quiet_noise_radius_u"]

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
var settings: SoundSettings
var home := Vector2.ZERO
## Awareness cues since the last clear(): { moment, set, stream, level, volume, time }.
var events: Array[Dictionary] = []
## Body sounds (Channel B) since the last clear(): { set, time }.
var body: Array[Dictionary] = []
## State changes since the last clear(): { from, to, time }.
var states: Array[Dictionary] = []
var listens := 0
var stand_downs := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	settings = SoundSettings.current()
	await set_up()
	check_reach()
	await check_detections()
	await check_second_sound()
	await check_without_animation()
	await check_encounter()
	check_screams_never_repeat()
	game.queue_free()
	await frames(3)
	print("[Awareness tests] %d/%d passed" % [checks - failures.size(), checks])
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)


func set_up() -> void:
	GameState.reset()
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	audio = entity.audio
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	home = game.world.marker("house", "Patrol1")
	game.player.process_mode = Node.PROCESS_MODE_DISABLED      # she makes no sound of her own here
	entity.get_node("CollisionShape2D").disabled = false
	audio.awareness_played.connect(func(moment: StringName, set_id: String, stream: AudioStream, level: float) -> void:
		var voice: AudioStreamPlayer2D = audio._aware.filter(func(v: AudioStreamPlayer2D) -> bool: return v.playing and v.stream == stream)[0]
		events.append({"moment": moment, "set": set_id, "stream": stream, "level": level, "volume": voice.volume_db,
			"base": float(voice.get_meta(&"base")), "time": now()}))
	audio.played.connect(func(set_id: String, _voice: AudioStreamPlayer2D) -> void: body.append({"set": set_id, "time": now()}))
	entity.state_changed.connect(func(from: int, to: int) -> void: states.append({"from": from, "to": to, "time": now()}))
	entity.listen_started.connect(func() -> void: listens += 1)
	entity.stood_down.connect(func() -> void: stand_downs += 1)


## Puts the entity back at `at`, shown, active and unaware; standing still unless `walking`.
func arm(at: Vector2, walking := false) -> void:
	var route: Array[Vector2] = [game.world.marker("house", "Patrol2"), game.world.marker("house", "Patrol3")]
	entity.reset_encounter(at, route)
	entity.show()
	entity.active = true
	entity._patrol_wait = 0.0 if walking else 999.0
	await frames(3)
	clear()


func clear() -> void:
	events.clear()
	body.clear()
	states.clear()
	listens = 0
	stand_downs = 0


func moments(moment: StringName) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event.moment == moment)


## The largest noise radius anything Viv does can emit, read from the real nodes.
func largest_player_noise_u() -> float:
	var largest := 0.0
	var roots: Array[Node] = [game, preload("res://altar/altar.tscn").instantiate()]
	for root in roots:
		for node in [root] + root.find_children("*", "", true, false):
			for property in RADIUS_PROPERTIES:
				if property in node:
					largest = maxf(largest, float(node.get(property)))
	roots[1].free()
	return largest


func check_reach() -> void:
	var largest := largest_player_noise_u()
	check(is_equal_approx(largest, 8.0), "The largest noise Viv can make is 8 u (found %.1f u)" % largest)
	# Its faintest hearing: the entity scene's own ears (the Hacienda's), not the gentler house's.
	var ears: CharacterBody2D = preload("res://tutorial/tutorial_entity.tscn").instantiate()
	var needed: float = largest * maxf(ears.faint_gain, entity.faint_gain)
	ears.free()
	check(settings.heard_full_u >= needed, "The heard-you cue is at full level out to %.1f u; detections can come from %.1f u" % [settings.heard_full_u, needed])
	check(settings.heard_floor_db >= settings.audible_db and settings.scream_floor_db >= settings.audible_db
		and settings.far_floor_db >= settings.audible_db, "No awareness cue can fall below what counts as audible, at any distance")
	var heard := [settings.heard_full_u, settings.heard_fall_db_per_u, settings.heard_floor_db]
	check(is_zero_approx(EntityAudio.reach_db(0.0, heard)) and is_zero_approx(EntityAudio.reach_db(settings.heard_full_u, heard))
		and EntityAudio.reach_db(settings.heard_full_u + 4.0, heard) < 0.0 and is_equal_approx(EntityAudio.reach_db(10000.0, heard), settings.heard_floor_db),
		"Its level is full up close, falls with distance, and stops falling at its floor")
	check(audio._aware.all(func(voice: AudioStreamPlayer2D) -> bool:
		return voice.max_distance >= EntityAudio.NO_ENGINE_FALLOFF_PX and voice.bus == AudioBus.ENTITY),
		"Awareness cues play on the Entity bus, which is never muffled, and the engine never fades them out by distance")


## It detects noises from several distances and positions; every time, the cue reaches Viv.
func check_detections() -> void:
	var cases := [
		# [what, Viv's distance from it (u), noise radius (u), noise lands at Viv (true) or next to it (false), it is already searching, it is walking]
		["a walking step beside it", 2.0, 3.0, true, false, false],
		["a sprint step at the edge of its calm hearing", 7.4, 6.0, true, false, false],
		["a forced gasp while it searches, at the edge of its sharp hearing", 11.0, 7.0, true, true, false],
		["a stone thrown next to it from 10 u", 10.0, 8.0, false, false, false],
		["an alarm clock next to it, Viv 16 u away", 16.0, 8.0, false, false, false],
		["an alarm clock next to it, Viv 24 u away", 24.0, 8.0, false, false, true],
		["an alarm clock next to it, Viv across the house", 38.0, 8.0, false, false, false],
		["a prayer pulse while it walks its patrol", 9.5, 8.0, true, false, true],
	]
	var directions := [Vector2.RIGHT, Vector2.DOWN, Vector2(-1, 1).normalized(), Vector2.LEFT, Vector2(1, -1).normalized(), Vector2.UP]
	var number := 0
	for case in cases:
		var direction: Vector2 = directions[number % directions.size()]
		number += 1
		await arm(home, case[5])
		if case[5]:
			await frames(40)            # let it get going
			clear()
		if case[4]:
			entity._change_state(entity.State.SEARCH)
			entity._search_queue.clear()
			entity._search_queue.append(entity.global_position)
			entity._feel_left = 30.0
			await frames(2)
			clear()
		var viv: Vector2 = entity.global_position + direction * Units.to_px(case[1])
		game.player.global_position = viv
		var at: Vector2 = viv if case[3] else entity.global_position + direction * 20.0
		NoiseManager.emit_noise(at, Units.to_px(case[2]), NoiseManager.SourceType.THROW)
		check(entity.is_listening() and listens == 1, "It hears %s" % case[0])
		check(audio.breath_set() == "" and not audio.is_dragging() and audio._voices.all(func(voice: AudioStreamPlayer2D) -> bool: return not voice.playing),
			"%s: everything it was sounding stops dead" % case[0])
		for tick in range(40):
			await frames(1)
			if moments(&"heard").size() >= 2: break
		var heard := moments(&"heard")
		var sets: Array = heard.map(func(event: Dictionary) -> String: return event.set)
		check(heard.size() == 2 and sets.has(EntityAudio.HEARD_VOICE) and sets.has(EntityAudio.NECK_CLICK)
			and absf(heard[0].time - heard[1].time) < 0.02, "%s: the voice and the neck click play, together" % case[0])
		check(heard.size() == 2 and heard.all(func(event: Dictionary) -> bool:
			return event.level >= settings.audible_db and event.volume >= settings.audible_db),
			"%s: both reach Viv %.1f u away (%s dB)" % [case[0], case[1], heard.map(func(event: Dictionary) -> float: return snappedf(event.volume, 0.1))])
		check(case[1] > settings.heard_full_u or heard.all(func(event: Dictionary) -> bool: return is_zero_approx(event.level)),
			"%s: within %.0f u the cue is at full level" % [case[0], settings.heard_full_u])
	# A sound it does not hear makes no cue: the cue only ever means "it heard".
	await arm(home)
	game.player.global_position = home + Vector2.RIGHT * Units.to_px(5.0)
	# A held-breath step 5 u away: outside even its faintest hearing (1 u x faint_gain).
	check(Units.to_px(1.0) * entity.faint_gain < Units.to_px(5.0), "A held-breath step is not heard from 5 u (it carries %.1f u at most)" % entity.faint_gain)
	NoiseManager.emit_noise(game.player.global_position, Units.to_px(1.0), NoiseManager.SourceType.CROUCH)
	await frames(30)
	check(not entity.is_listening() and events.is_empty() and listens == 0, "A step it cannot hear makes no cue")
	# The walking step that used to go unheard there is barely heard now: the click, and no scream.
	NoiseManager.emit_noise(game.player.global_position, Units.to_px(3.0), NoiseManager.SourceType.FOOTSTEP)
	await frames(30)
	check(entity.is_listening() and listens == 1 and entity.listen_outcome_name() == "INVESTIGATE" and moments(&"heard").size() == 2
		and moments(&"scream").is_empty(), "A walking step from 5 u is barely heard: the cue plays, and it is on its way to a check, not a hunt")
	var voice_db: float = SoundLibrary.gain_db(EntityAudio.HEARD_VOICE) + settings.heard_voice_gain_db
	check(voice_db > SoundLibrary.gain_db("entity/mumble") and SoundLibrary.gain_db(EntityAudio.NECK_CLICK) >= 4.0,
		"The heard-you voice plays above any idle talking, and the click is brought up to it")


## A second sound while it listens: the head snaps again, the voice does not speak again.
func check_second_sound() -> void:
	await arm(home)
	entity.listen_time_range = Vector2(1.2, 1.2)
	game.player.global_position = home + Vector2.DOWN * Units.to_px(6.0)
	var facing := Vector2.from_angle(entity.sprite_rig.heading)
	NoiseManager.emit_noise(home + facing * 40.0, Units.to_px(8.0), NoiseManager.SourceType.THROW)
	await get_tree().create_timer(0.45).timeout
	var aim_before: String = entity.sprite_rig.aim
	NoiseManager.emit_noise(home + facing.orthogonal() * 40.0, Units.to_px(8.0), NoiseManager.SourceType.THROW)
	await get_tree().create_timer(0.3).timeout
	check(entity.sprite_rig.aim != aim_before, "A sound from its side while it listens turns its head again")
	var voices := events.filter(func(event: Dictionary) -> bool: return event.set == EntityAudio.HEARD_VOICE)
	check(listens == 1 and voices.size() == 1, "A second sound while it listens does not make it speak again")
	check(moments(&"heard_again").size() >= 1 and moments(&"heard_again").all(func(event: Dictionary) -> bool:
		return event.set == EntityAudio.NECK_CLICK and event.level >= settings.audible_db), "Its head snaps to the new sound, and that click is heard")
	check(body.filter(func(sound: Dictionary) -> bool: return sound.set == "entity/claw_scrape").size() <= 1,
		"One scrape at most, however often it turns")
	entity.listen_time_range = Vector2(0.7, 1.2)


## With no animation running, nothing is lost: the cue and the scream still play.
func check_without_animation() -> void:
	await arm(home)
	entity.sprite_rig.set_process(false)
	game.player.global_position = home + Vector2.LEFT * Units.to_px(20.0)
	NoiseManager.emit_noise(home + Vector2.LEFT * 30.0, Units.to_px(8.0), NoiseManager.SourceType.THROW)
	var start := now()
	for tick in range(60):
		await frames(1)
		if moments(&"heard").size() >= 2: break
	var heard := moments(&"heard")
	check(heard.size() == 2 and heard[0].time - start >= settings.heard_click_wait - 0.05 and heard[0].time - start < settings.heard_click_wait + 0.2
		and heard.all(func(event: Dictionary) -> bool: return event.level >= settings.audible_db),
		"Without the head snap, the heard-you cue plays anyway after %.2f s" % settings.heard_click_wait)
	for tick in range(120):
		await frames(1)
		if not states.is_empty(): break
	await frames(2)
	check(not states.is_empty() and states[0].to == entity.State.HUNT and moments(&"scream").size() == 1
		and moments(&"scream")[0].time - states[0].time < 0.1 and moments(&"scream")[0].level >= settings.audible_db,
		"Without the hunt-start animation the scream still comes: no scream, no hunt")
	check(is_equal_approx(MixDirector.target_db(AudioBus.MUSIC), settings.scream_duck_db), "And the mix still ducks for it")
	entity.sprite_rig.set_process(true)
	await arm(home)
	check(not MixDirector.is_active(EntityAudio.SCREAM_DUCK), "Resetting the encounter lets the duck go")


## One whole encounter: heard, scream, hunt, lost, search, gave up. Then a second one.
func check_encounter() -> void:
	entity.hunt_linger = 1.5
	entity.search_duration_range = Vector2(3.6, 3.6)
	await arm(home)
	audio._last_scream = -INF       # the screams of the checks above are not part of this encounter
	var spot: Vector2 = game.world.marker("house", "Patrol2")
	game.player.global_position = home + Vector2.LEFT * Units.to_px(14.0)
	NoiseManager.emit_noise(spot, Units.to_px(40.0), NoiseManager.SourceType.ENVIRONMENT)
	check(entity.is_listening(), "It hears the sound that starts the encounter")
	# Up to the launch.
	var ducked := {}
	var body_untouched := true
	for tick in range(400):
		await frames(1)
		if not moments(&"scream").is_empty() and ducked.is_empty() and now() - moments(&"scream")[0].time > 0.4:
			for bus_name in [AudioBus.MUSIC, AudioBus.AMBIENCE, AudioBus.WORLD]:
				ducked[bus_name] = MixDirector.gain_db(bus_name)
			# The mood of the house brings Viv's body forward (Step 6); nothing ever lowers it.
			body_untouched = is_zero_approx(MixDirector.gain_db(AudioBus.ENTITY)) and is_zero_approx(MixDirector.gain_db(AudioBus.ENTITY_FAR)) \
				and MixDirector.gain_db(AudioBus.BODY) >= 0.0
		if body.any(func(sound: Dictionary) -> bool: return sound.set == "entity/claws_run"): break
	var heard := moments(&"heard")
	var inhale := moments(&"inhale")
	var scream := moments(&"scream")
	var slam := moments(&"foot_slam")
	check(heard.size() == 2 and inhale.size() == 1 and scream.size() == 1 and slam.size() == 1,
		"Heard-you, then the inhale, the scream and the stomp, once each")
	if heard.size() < 2 or inhale.size() != 1 or scream.size() != 1 or slam.size() != 1:
		return
	# The scream is the only sound of the sequence above -16 LUFS (the inhale sits at -16).
	var warning: float = scream[0].time - heard[0].time
	check(warning >= 0.7, "The heard-you cue comes %.2f s before the scream: at least 0.7 s of warning" % warning)
	check(inhale[0].time - heard[0].time >= 0.5, "And the silence after the cue lasts (%.2f s to the inhale)" % (inhale[0].time - heard[0].time))
	var between := body.filter(func(sound: Dictionary) -> bool: return sound.time > heard[0].time and sound.time < inhale[0].time)
	var between_sets: Array = between.map(func(sound: Dictionary) -> String: return sound.set)
	check(between.size() <= 1 and between_sets.all(func(set_id: String) -> bool: return set_id == "entity/claw_scrape")
		and events.filter(func(event: Dictionary) -> bool: return event.time > heard[0].time and event.time < inhale[0].time).is_empty(),
		"Between the cue and the scream: one scrape, then silence (heard %s)" % [between_sets])
	var gap: float = scream[0].time - inhale[0].time
	check(gap > 0.12 and gap < 0.32 and absf(slam[0].time - scream[0].time) < 0.05, "The scream and the stomp land together, 0.2 s after the inhale (%.2f s)" % gap)
	var hunt_started: Array = states.filter(func(change: Dictionary) -> bool: return change.to == entity.State.HUNT)
	check(hunt_started.size() == 1 and scream[0].time - hunt_started[0].time < 0.4 and scream[0].level >= settings.audible_db
		and inhale[0].level >= settings.audible_db, "The hunt starts with its scream, heard from where Viv stands")
	check(is_equal_approx(scream[0].base, SoundLibrary.gain_db(EntityAudio.SCREAM) + settings.scream_gain_db), "The scream plays 3 dB up")
	check(ducked.size() == 3 and ducked.values().all(func(gain: float) -> bool: return is_equal_approx(gain, settings.scream_duck_db)) and body_untouched,
		"Under the scream Music, Ambience and World are 14 dB down; the entity is not touched and Viv's body is never lowered (%s)" % [ducked])
	check(not MixDirector.is_active(EntityAudio.SCREAM_DUCK), "The duck lets go when it launches")
	await get_tree().create_timer(settings.scream_duck_release + 0.2).timeout
	# The music is back in full; the world comes back to where the mood of the house holds it.
	check(is_zero_approx(MixDirector.gain_db(AudioBus.MUSIC))
		and absf(MixDirector.gain_db(AudioBus.WORLD) - settings.threat_world_db * Dread.threat) < 0.05,
		"And the duck is over %.1f s later (World %.1f dB, threat %.2f)" % [settings.scream_duck_release, MixDirector.gain_db(AudioBus.WORLD), Dread.threat])
	# A new sound during the hunt moves the target; it does not scream again.
	if entity.get_state_name() == "HUNT":
		NoiseManager.emit_noise(game.world.marker("house", "Patrol3"), Units.to_px(40.0), NoiseManager.SourceType.ENVIRONMENT)
		await frames(20)
	check(moments(&"scream").size() == 1 and moments(&"heard").size() == 2 and listens == 1, "A new sound during the hunt brings no second scream and no second cue")
	# The trail goes cold.
	for tick in range(900):
		await frames(1)
		if not moments(&"lost_sniff").is_empty() or entity.get_state_name() == "PATROL": break
	var lost := moments(&"lost")
	var sniff := moments(&"lost_sniff")
	var searching: Array = states.filter(func(change: Dictionary) -> bool: return change.from == entity.State.HUNT and change.to == entity.State.SEARCH)
	check(searching.size() == 1 and lost.size() == 1 and absf(lost[0].time - searching[0].time) < 0.1 and lost[0].level >= settings.audible_db,
		"When it loses the trail it groans, and Viv hears it")
	check(sniff.size() == 1 and lost.size() == 1 and sniff[0].set == EntityAudio.SNIFF and absf(sniff[0].time - lost[0].time - settings.lost_then_sniff) < 0.2,
		"Then one sniff, %.1f s later" % settings.lost_then_sniff)
	# It gives up.
	for tick in range(900):
		await frames(1)
		if entity.get_state_name() == "PATROL": break
	await frames(2)
	var gave_up := moments(&"stand_down")
	check(entity.get_state_name() == "PATROL" and stand_downs == 1 and gave_up.size() == 1 and gave_up[0].set == EntityAudio.STAND_DOWN
		and gave_up[0].level >= settings.audible_db, "Giving up has its own sound, heard from where Viv stands")
	check(gave_up.size() == 1 and lost.size() == 1 and gave_up[0].stream != lost[0].stream and EntityAudio.STAND_DOWN != EntityAudio.LOST
		and SoundLibrary.files(EntityAudio.STAND_DOWN).all(func(stream: AudioStream) -> bool: return not SoundLibrary.files(EntityAudio.LOST).has(stream)),
		"It is not the sound of losing the trail")
	var given_up_at: float = gave_up[0].time if gave_up.size() == 1 else now()
	await get_tree().create_timer(1.2).timeout
	check(moments(&"lost_sniff").size() == 1 and moments(&"stand_down").size() == 1
		and body.filter(func(sound: Dictionary) -> bool: return sound.set == "entity/exhale" and sound.time >= given_up_at).is_empty(),
		"One breath out, not two; no sniff after it has given up")
	# A second encounter, inside 20 s of the first scream.
	var first_scream: Dictionary = scream[0]
	clear()
	entity._patrol_wait = 999.0
	NoiseManager.emit_noise(entity.global_position + Vector2(30, 0), Units.to_px(8.0), NoiseManager.SourceType.THROW)
	for tick in range(400):
		await frames(1)
		if not moments(&"scream").is_empty(): break
	var second := moments(&"scream")
	check(second.size() == 1 and moments(&"heard").size() == 2, "The second encounter has its cue and its scream too")
	if second.size() == 1:
		check(second[0].time - first_scream.time < settings.scream_repeat_window
			and is_equal_approx(second[0].base, first_scream.base + settings.scream_repeat_db), "A scream within 20 s of the last one is 4 dB quieter")
		check(second[0].stream != first_scream.stream, "And it is not the same scream")
	await arm(home)


func check_screams_never_repeat() -> void:
	var last: AudioStream = null
	var repeats := 0
	var seen := {}
	for index in 60:
		var stream := SoundLibrary.pick(EntityAudio.SCREAM)
		repeats += int(stream == last)
		seen[stream] = true
		last = stream
	check(repeats == 0 and seen.size() == SoundLibrary.files(EntityAudio.SCREAM).size() and seen.size() >= 3,
		"Sixty screams in a row: never the same file twice running, and every file is used")
