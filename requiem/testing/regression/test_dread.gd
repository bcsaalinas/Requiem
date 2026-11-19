extends Node
## Threat (headless): the music and the world follow what the entity knows, never where it is.
## One whole encounter is played in the house and listened to from the mix: the mood rising
## and falling, the music cutting out when it hears something, coming in with the scream,
## thinning while it searches, and returning slowly after it gives up. Then the catch: no
## stinger, and silence on the game over screen.

const STINGERS := ["dread_stinger_01", "jump_scare_02", "riser_02"]
const SKIPPED_FOLDERS := ["res://addons", "res://testing", "res://.godot", "res://builds", "res://.local-development", "res://tools"]
## Scripts that decide the music and the mood. None of them may read where anything is.
const BLIND_SCRIPTS := ["res://autoloads/music_director.gd", "res://audio/dread.gd"]

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
var settings: SoundSettings
var home := Vector2.ZERO
## Music state changes since the last clear(): { from, to, time }.
var music: Array[Dictionary] = []
## Awareness changes since the last clear(): { from, to, time }.
var aware: Array[Dictionary] = []
## Awareness cues passed on by Dread since the last clear(): { moment, time }.
var cues: Array[Dictionary] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _ready() -> void:
	settings = SoundSettings.current()
	check_settings()
	check_sources()
	await set_up()
	await check_unaware()
	await check_encounter()
	await check_catch()
	check_holds()
	game.queue_free()
	await frames(3)
	print("[Threat tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
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
	MusicDirector.music_state_changed.connect(func(from: int, to: int) -> void: music.append({"from": from, "to": to, "time": now()}))
	Dread.awareness_changed.connect(func(from: int, to: int) -> void: aware.append({"from": from, "to": to, "time": now()}))
	Dread.cue_played.connect(func(moment: StringName) -> void: cues.append({"moment": moment, "time": now()}))


## Puts the entity back at `at`, shown, active and unaware; standing still unless `walking`.
func arm(at: Vector2, walking := false) -> void:
	var route: Array[Vector2] = [game.world.marker("house", "Patrol3"), game.world.marker("house", "Patrol2")]
	entity.reset_encounter(at, route)
	entity.show()
	entity.active = true
	entity._patrol_wait = 0.0 if walking else 999.0
	await frames(3)
	clear()


func clear() -> void:
	music.clear()
	aware.clear()
	cues.clear()


func cue(moment: StringName) -> Dictionary:
	for event in cues:
		if event.moment == moment: return event
	return {}


func changed_to(log: Array[Dictionary], to: int) -> Dictionary:
	for change in log:
		if change.to == to: return change
	return {}


## Waits until `condition` is true, for `limit` seconds at most.
func until(condition: Callable, limit: float) -> bool:
	var deadline := now() + limit
	while now() < deadline:
		if condition.call(): return true
		await get_tree().physics_frame
	return condition.call()


## The music players that can be heard right now.
func sounding() -> Array:
	var found := []
	for bank in MusicDirector._banks:
		for player: AudioStreamPlayer in bank:
			if player.playing and player.volume_db > MusicDirector.SILENT_DB: found.append(player)
	return found


## The player of a state's track, when it is playing.
func track(state: int) -> AudioStreamPlayer:
	var streams: Array[AudioStream] = MusicDirector._streams_for(state)
	for player: AudioStreamPlayer in sounding():
		if streams.has(player.stream): return player
	return null


func gain(bus_name: StringName) -> float:
	return MixDirector.gain_db(bus_name)


func near(value: float, wanted: float, tolerance := 0.05) -> bool:
	return absf(value - wanted) <= tolerance


func check_settings() -> void:
	check(get_node_or_null("/root/Dread") != null and ProjectSettings.has_setting("autoload/Dread"), "Dread is an autoload")
	check(is_zero_approx(settings.threat_unaware) and near(settings.threat_paused, 0.1) and near(settings.threat_heard, 0.6)
		and near(settings.threat_searching, 0.7) and near(settings.threat_hunting, 1.0),
		"Threat is 0 unaware, 0.1 on a patrol pause, 0.6 heard, 0.7 searching, 1 hunting")
	check(near(Dread.threat_for(Dread.Awareness.UNAWARE), settings.threat_unaware) and near(Dread.threat_for(Dread.Awareness.PAUSED), settings.threat_paused)
		and near(Dread.threat_for(Dread.Awareness.HEARD), settings.threat_heard) and near(Dread.threat_for(Dread.Awareness.SEARCHING), settings.threat_searching)
		and near(Dread.threat_for(Dread.Awareness.HUNTING), settings.threat_hunting) and near(Dread.threat_for(Dread.Awareness.CAUGHT), settings.threat_hunting),
		"Dread reads those values from the settings")
	check(settings.threat_rise_time * 4.0 <= settings.threat_fall_time and settings.threat_lag.x > 0.0 and settings.threat_lag.y <= 1.0,
		"It rises quickly, falls slowly, and lags a little")
	check(near(settings.threat_world_db, -10.0) and near(settings.threat_body_db, 3.0), "At full threat the world is 10 dB down and Viv's body 3 dB up")
	var explore := MusicDirector.MusicState.EXPLORE
	var search := MusicDirector.MusicState.SEARCH
	check(near(MusicDirector.fade_for(explore, MusicDirector.MusicState.HEARD), 0.1, 0.001), "Hearing something cuts the music in 0.1 s")
	var stand_down: float = MusicDirector.fade_for(search, explore)
	check(stand_down >= 6.0 and stand_down <= 8.0 and settings.music_fade_stand_down == Vector2(6.0, 8.0), "After it gives up the drone returns over 6 to 8 s (%.1f s)" % stand_down)
	var times := [MusicDirector.fade_for(explore, MusicDirector.MusicState.HEARD), MusicDirector.fade_for(MusicDirector.MusicState.HEARD, MusicDirector.MusicState.HUNT),
		MusicDirector.fade_for(MusicDirector.MusicState.HUNT, search), stand_down, MusicDirector.fade_for(MusicDirector.MusicState.MENU, explore)]
	var different := {}
	for time: float in times: different[snappedf(time, 0.001) if time < 6.0 else 6.0] = true
	check(different.size() == times.size() and near(MusicDirector.fade_for(MusicDirector.MusicState.MENU, explore), settings.music_fade, 0.001),
		"Each change of the music has its own fade time (%s)" % [times])
	check(settings.music_search_db <= -10.0, "While it searches the thin tone plays well under the other music (%.0f dB)" % settings.music_search_db)


## No stinger is used anywhere, and the scripts that decide the music and the mood cannot
## know where the entity is.
func check_sources() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	var folders := ["res://"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			var path := folder.path_join(sub)
			if not SKIPPED_FOLDERS.has(path): folders.append(path)
		for file in DirAccess.get_files_at(folder):
			if not (file.ends_with(".gd") or file.ends_with(".tscn") or file.ends_with(".tres")): continue
			scanned += 1
			var text := FileAccess.get_file_as_string(folder.path_join(file))
			for stinger: String in STINGERS:
				if text.contains(stinger): offenders.append("%s uses %s" % [folder.path_join(file), stinger])
	check(scanned > 100, "The scripts, scenes and resources of the game were scanned (%d files)" % scanned)
	check(offenders.is_empty(), "No stinger is used: %s" % [offenders])
	var reads := RegEx.create_from_string("distance|global_position|\\.position\\b|listener")
	var peeking: Array[String] = []
	for path: String in BLIND_SCRIPTS:
		var number := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			if reads.search(line.get_slice("#", 0)) != null: peeking.append("%s:%d" % [path, number])
	check(peeking.is_empty(), "The music and the mood never read a position or a distance: %s" % [peeking])
	check(GameOverUi.find_children("*", "AudioStreamPlayer", true, false).is_empty() and not GameOverUi.has_method(&"play_death_stinger"),
		"The game over screen has no sound of its own")


## Unaware, the entity can walk right past Viv or be across the house: nothing changes.
func check_unaware() -> void:
	await arm(home, true)
	await seconds(0.8)
	check(audio != null and Dread._watched.has(entity.get_instance_id()), "The entity reports itself to Dread")
	check(Dread.awareness == Dread.Awareness.UNAWARE and is_zero_approx(Dread.threat) and MusicDirector.current_state == MusicDirector.MusicState.EXPLORE,
		"Walking its patrol unaware: no threat, exploration music")
	check(track(MusicDirector.MusicState.EXPLORE) != null, "The exploration drone is playing")
	clear()
	for distance_u: float in [1.5, 40.0, 6.0]:
		game.player.global_position = entity.global_position + Vector2.LEFT * Units.to_px(distance_u)
		await seconds(0.4)
	check(music.is_empty() and aware.is_empty() and is_zero_approx(Dread.threat),
		"Right beside Viv or across the house, an unaware entity changes neither the music nor the threat")
	# How near it is (presence) moves the world a little by itself: test_rings covers that.
	check(near(gain(AudioBus.AMBIENCE), settings.threat_world_db * MixDirector.recede()) and near(gain(AudioBus.WORLD), settings.threat_world_db * MixDirector.recede())
		and MixDirector.recede() <= settings.presence_world_share, "With no threat the world only recedes as far as its nearness takes it (%.2f)" % MixDirector.recede())
	# A patrol pause: a little threat, no change of music.
	entity._patrol_wait = 999.0
	await seconds(settings.threat_lag.y + settings.threat_rise_time + 0.3)
	check(Dread.awareness == Dread.Awareness.PAUSED and near(Dread.threat, settings.threat_paused, 0.001), "When it pauses, threat is %.1f (%.2f)" % [settings.threat_paused, Dread.threat])
	# The stronger of threat and nearness decides how far the world recedes.
	var receded: float = MixDirector.recede()
	check(receded >= settings.threat_paused and near(gain(AudioBus.AMBIENCE), settings.threat_world_db * receded) and near(gain(AudioBus.WORLD), settings.threat_world_db * receded)
		and near(gain(AudioBus.BODY), settings.threat_body_db * receded) and music.is_empty(),
		"The world dips by a dB or more (%.1f dB), and the music does not react" % gain(AudioBus.AMBIENCE))


## Roam, heard, scream, hunt, lost, search, gave up.
func check_encounter() -> void:
	entity.listen_time_range = Vector2(1.2, 1.2)
	entity.hunt_persistence = 4.0
	entity.search_duration = 5.0
	await arm(home)
	await seconds(settings.threat_lag.y + 0.3)
	clear()
	var explore := MusicDirector.MusicState.EXPLORE
	var heard_state := MusicDirector.MusicState.HEARD
	var hunt := MusicDirector.MusicState.HUNT
	var search := MusicDirector.MusicState.SEARCH
	game.player.global_position = home + Vector2.LEFT * Units.to_px(14.0)
	var spot: Vector2 = game.world.marker("house", "Patrol2")
	# It hears something.
	var heard_at := now()
	NoiseManager.emit_noise(spot, Units.to_px(40.0), NoiseManager.SourceType.ENVIRONMENT)
	check(entity.is_listening(), "It hears the sound that starts the encounter")
	await until(func() -> bool: return MusicDirector.current_state == heard_state, 0.5)
	var cut := changed_to(music, heard_state)
	check(Dread.awareness == Dread.Awareness.HEARD and not cut.is_empty() and cut.time - heard_at < 0.1,
		"The moment it listens, the music starts to go (%.3f s)" % ((cut.time - heard_at) if not cut.is_empty() else -1.0))
	await seconds(settings.music_fade_heard + 0.08)
	check(sounding().is_empty() and not MusicDirector._riser.playing, "%.1f s later there is no music at all" % settings.music_fade_heard)
	var most := 0.0
	var pulled_back := 0.0
	while entity.is_listening():
		most = maxf(most, Dread.threat)
		pulled_back = gain(AudioBus.AMBIENCE)
		await get_tree().physics_frame
	check(near(most, settings.threat_heard, 0.001), "While it listens, threat climbs to %.1f and no further (%.2f)" % [settings.threat_heard, most])
	check(near(pulled_back, settings.threat_world_db * settings.threat_heard), "And the world has pulled back with it (%.1f dB)" % pulled_back)
	# The scream.
	await until(func() -> bool: return not cue(&"scream").is_empty(), 2.0)
	await frames(2)
	var scream := cue(&"scream")
	var began := changed_to(music, hunt)
	var knew := changed_to(aware, Dread.Awareness.HUNTING)
	check(not scream.is_empty() and not began.is_empty() and absf(began.time - scream.time) < 0.05,
		"The hunt music starts with the scream (%.3f s apart)" % ((began.time - scream.time) if not began.is_empty() and not scream.is_empty() else -1.0))
	check(not knew.is_empty() and not scream.is_empty() and knew.time <= scream.time and scream.time - knew.time > 0.1
		and music.map(func(change: Dictionary) -> int: return change.to) == [heard_state, hunt],
		"Not before it: from the heard-you cue to the scream there is silence, also while it breathes in")
	check(MusicDirector._riser.playing and near(MusicDirector._riser.volume_db, settings.music_riser_db) and MusicDirector._riser.bus == AudioBus.MUSIC
		and MusicDirector.RISER_PATH.contains("pitch_riser_01"), "The rising tone starts with it, on the Music bus")
	check(track(hunt) != null and track(explore) == null, "The hunt drone is playing; the exploration drone is not")
	# The hunt: full threat, the scream's duck released into it.
	check(await until(func() -> bool: return not MixDirector.is_active(EntityAudio.SCREAM_DUCK), 3.0), "It launches into the hunt")
	check(near(Dread.threat, settings.threat_hunting, 0.001), "Hunting, threat is at %.1f" % settings.threat_hunting)
	await seconds(settings.scream_duck_release / 3.0)
	var returning: float = gain(AudioBus.WORLD)
	check(returning < settings.threat_world_db - 1.0 and returning > settings.scream_duck_db,
		"After the scream the world comes back slowly to where the mood holds it, not at once (%.1f dB)" % returning)
	await seconds(settings.scream_duck_release * 2.0 / 3.0 + 0.2)
	check(near(gain(AudioBus.AMBIENCE), settings.threat_world_db) and near(gain(AudioBus.WORLD), settings.threat_world_db),
		"While it hunts Ambience and World are %.0f dB down" % -settings.threat_world_db)
	check(near(gain(AudioBus.BODY), settings.threat_body_db), "Viv's body is %.0f dB up: she hears herself" % settings.threat_body_db)
	check(is_zero_approx(gain(AudioBus.MUSIC)) and is_zero_approx(gain(AudioBus.ENTITY)) and is_zero_approx(gain(AudioBus.ENTITY_FAR)),
		"The mood moves neither the music nor the entity")
	# It loses the trail.
	check(await until(func() -> bool: return Dread.awareness == Dread.Awareness.SEARCHING, 6.0), "It loses the trail")
	await frames(2)
	var lost := cue(&"lost")
	var thinned := changed_to(music, search)
	check(not lost.is_empty() and not thinned.is_empty() and absf(thinned.time - lost.time) < 0.1, "The music thins as it groans")
	var searching_since := now()
	await seconds(1.0)
	check(Dread.threat > settings.threat_searching + 0.15, "Threat falls slowly (%.2f a second after the hunt)" % Dread.threat)
	await seconds(settings.music_fade_search - 1.0 + 0.2)
	var tone := track(search)
	check(tone != null and near(tone.volume_db, settings.music_search_db) and track(hunt) == null and sounding().size() == 1,
		"While it searches there is almost no music: one thin tone, %.0f dB down" % -settings.music_search_db)
	await seconds(maxf(0.0, searching_since + 0.3 * settings.threat_fall_time + settings.threat_lag.y + 0.3 - now()))
	check(near(Dread.threat, settings.threat_searching, 0.001), "Searching, threat settles at %.1f (%.2f)" % [settings.threat_searching, Dread.threat])
	# It gives up.
	check(await until(func() -> bool: return not cue(&"stand_down").is_empty(), 6.0), "It gives up")
	await frames(2)
	var gave_up := cue(&"stand_down")
	var back := changed_to(music, explore)
	check(not gave_up.is_empty() and not back.is_empty() and absf(back.time - gave_up.time) < 0.1, "The exploration drone starts to return as it breathes out")
	var drone := track(explore)
	var length: float = MusicDirector._fades[drone].length if drone != null and MusicDirector._fades.has(drone) else -1.0
	check(length >= 6.0 and length <= 8.0, "Over 6 to 8 s (%.1f s)" % length)
	await seconds(2.0)
	check(drone != null and drone.playing and drone.volume_db > -45.0 and drone.volume_db < -12.0,
		"Two seconds in it can be heard and is still far from full (%.1f dB)" % (drone.volume_db if drone != null else 0.0))
	check(track(search) != null, "The thin tone is still on its way out")
	check(Dread.threat < settings.threat_searching and Dread.threat > 0.35 and gain(AudioBus.AMBIENCE) < -3.0,
		"The world is still coming back (threat %.2f, Ambience %.1f dB)" % [Dread.threat, gain(AudioBus.AMBIENCE)])
	await seconds(length - 2.0 + 0.3)
	check(drone != null and drone.playing and is_zero_approx(drone.volume_db) and track(search) == null, "Then the drone is back in full and the tone is gone")
	await seconds(maxf(0.0, gave_up.time + settings.threat_searching * settings.threat_fall_time + settings.threat_lag.y + 0.4 - now()))
	check(Dread.threat <= settings.threat_paused + 0.001 and near(gain(AudioBus.AMBIENCE), settings.threat_world_db * MixDirector.recede())
		and MixDirector.recede() <= maxf(settings.threat_paused, settings.presence_world_share) + 0.001,
		"And the house is back, but for how near it still is (threat %.2f, Ambience %.1f dB)" % [Dread.threat, gain(AudioBus.AMBIENCE)])
	var rise: float = knew.time - heard_at + settings.threat_rise_time
	check(rise < settings.threat_searching * settings.threat_fall_time, "The mood rose in about %.1f s and took %.0f s to fall" % [rise, settings.threat_searching * settings.threat_fall_time])
	check(music.map(func(change: Dictionary) -> int: return change.to) == [heard_state, hunt, search, explore],
		"The music of the whole encounter: silence, hunt, thin tone, exploration")
	entity.listen_time_range = Vector2(0.7, 1.2)


## The catch: no stinger, the music gone under the catch, and silence on the game over screen.
func check_catch() -> void:
	await arm(home, true)
	await seconds(0.5)
	clear()
	game.player.global_position = entity.global_position + Vector2(24, 0)
	var caught_at := now()
	game._begin_game_over()
	await until(func() -> bool: return MusicDirector.current_state == MusicDirector.MusicState.DEATH, 0.5)
	check(not changed_to(aware, Dread.Awareness.CAUGHT).is_empty() and MusicDirector.current_state == MusicDirector.MusicState.DEATH
		and now() - caught_at < 0.2, "The catch takes the music away")
	await seconds(settings.music_fade_catch + 0.1)
	check(sounding().is_empty(), "%.1f s later there is none" % settings.music_fade_catch)
	check(int(audio.plays.get("entity/catch_grab", 0)) >= 1, "The catch is carried by the entity's own sounds")
	await until(func() -> bool: return GameState.is_dead, 1.0)
	check(GameState.is_dead and GameOverUi.screen != null, "The game over screen is up")
	check(near(MixDirector.target_db(AudioBus.MUSIC), settings.death_duck_db) and near(MixDirector.target_db(AudioBus.AMBIENCE), settings.death_duck_db)
		and near(MixDirector.target_db(AudioBus.WORLD), settings.death_duck_db), "On it Music, Ambience and World go silent")
	check(is_zero_approx(MixDirector.target_db(AudioBus.ENTITY)) and is_zero_approx(MixDirector.target_db(AudioBus.ENTITY_FAR)),
		"What the entity is still sounding rings out")
	await seconds(settings.death_fade + 0.2)
	check(near(gain(AudioBus.AMBIENCE), settings.death_duck_db) and near(gain(AudioBus.WORLD), settings.death_duck_db) and sounding().is_empty()
		and GameOverUi.find_children("*", "AudioStreamPlayer", true, false).is_empty(), "And nothing plays on the screen")
	# Trying again starts clean.
	game.restore_checkpoint()
	await frames(4)
	check(not GameState.is_dead and is_zero_approx(Dread.threat) and Dread.awareness == Dread.Awareness.UNAWARE
		and MusicDirector.current_state == MusicDirector.MusicState.EXPLORE and not MixDirector.is_active(MixDirector.THREAT_MIX),
		"A new attempt starts with no mood left over, and the exploration music")
	await seconds(settings.death_release + 0.2)
	check(is_zero_approx(gain(AudioBus.AMBIENCE)) and is_zero_approx(gain(AudioBus.WORLD)) and is_zero_approx(gain(AudioBus.MUSIC)), "The house is back")


## Prayer and the menu keep their music whatever the entity knows.
func check_holds() -> void:
	var states := MusicDirector.MusicState
	MusicDirector._on_prayer_started(self)
	MusicDirector._on_awareness_changed(Dread.Awareness.UNAWARE, Dread.Awareness.SEARCHING)
	check(MusicDirector.current_state == states.PRAYER, "During a prayer its music holds")
	MusicDirector._on_prayer_ended(self, false)
	check(MusicDirector.current_state == states.SEARCH, "And gives way to what the entity knows when it ends")
	MusicDirector._on_awareness_changed(Dread.Awareness.SEARCHING, Dread.Awareness.UNAWARE)
	check(MusicDirector.current_state == states.EXPLORE, "Back to exploration")
	MusicDirector.bind_gameplay(null, null)
	MusicDirector.set_music_state(states.MENU)
	MusicDirector._on_awareness_changed(Dread.Awareness.UNAWARE, Dread.Awareness.HEARD)
	MusicDirector._on_cue_played(&"scream")
	check(MusicDirector.current_state == states.MENU, "Outside play (the menu) the music does not follow the entity")
	MusicDirector.bind_gameplay(entity, game.breath)
	check(MusicDirector.current_state == states.EXPLORE, "Starting play brings the exploration music")
