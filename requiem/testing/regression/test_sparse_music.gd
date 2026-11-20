extends Node
## Sparse music (headless): during exploration the drone comes and goes by itself.
## It stays a while, leaves a while, and nothing about the entity moves that clock: so whether
## there is music tells the player nothing. What the entity knows still wins every time: the
## silence when it hears, the hunt music with the scream, the thin tone, and the drone coming
## back when it gives up.

var failures: Array[String] = []
var checks := 0
var settings: SoundSettings
var game: Node2D
var entity: CharacterBody2D
var home := Vector2.ZERO
## Every time the drone turned: { coming_in, time }.
var turns: Array[Dictionary] = []
var music: Array[Dictionary] = []
var cues: Array[StringName] = []
var kept := {}


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


func near(value: float, wanted: float, tolerance := 0.05) -> bool:
	return absf(value - wanted) <= tolerance


## Waits until `condition` is true, for `limit` seconds at most.
func until(condition: Callable, limit: float) -> bool:
	var deadline := now() + limit
	while now() < deadline:
		if condition.call(): return true
		await get_tree().process_frame
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


func _ready() -> void:
	settings = SoundSettings.current()
	check_settings()
	await set_up()
	await check_opening()
	await check_cycle()
	await check_entity_means_nothing()
	await check_awareness_wins()
	await check_other_music()
	for key: String in kept:
		settings.set(key, kept[key])
	game.queue_free()
	await frames(3)
	print("[Sparse music tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func check_settings() -> void:
	check(settings.music_drone_stay == Vector2(40.0, 90.0) and settings.music_drone_away == Vector2(40.0, 90.0),
		"The drone stays 40 to 90 s and is away 40 to 90 s")
	check(settings.music_drone_fade_in >= 4.0 and settings.music_drone_fade_out >= 4.0
		and settings.music_drone_fade_in + settings.music_drone_fade_out < settings.music_drone_away.x,
		"It comes and goes slowly (%.0f s in, %.0f s out), and is truly gone for most of its time away" % [settings.music_drone_fade_in, settings.music_drone_fade_out])
	# The clock of the drone never asks anything about the entity.
	var source := FileAccess.get_file_as_string("res://autoloads/music_director.gd")
	var clock := source.substr(source.find("func _tick_drone"))
	clock = clock.substr(0, clock.find("\nfunc ", 1))
	check(clock.length() > 40 and not clock.contains("Dread") and not clock.contains("_bound_entity") and not clock.contains("Acoustics")
		and not clock.contains("_entity_music_state"), "The clock of the drone never asks about the entity")


func set_up() -> void:
	MusicDirector.drone_turned.connect(func(coming_in: bool) -> void: turns.append({"coming_in": coming_in, "time": now()}))
	MusicDirector.music_state_changed.connect(func(from: int, to: int) -> void: music.append({"from": from, "to": to, "time": now()}))
	Dread.cue_played.connect(func(moment: StringName) -> void: cues.append(moment))
	GameState.reset()
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	home = game.world.marker("house", "Patrol4")
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.global_position = game.world.zones["house"].global_position + Vector2(520, 400)
	await arm()


## Puts the entity at the far end of the house, shown, active, unaware and standing still.
func arm() -> void:
	var route: Array[Vector2] = [home]
	entity.reset_encounter(home, route)
	entity.show()
	entity.active = true
	entity._patrol_wait = 999.0
	await frames(3)
	entity.audio.placed()
	await frames(2)


## Shortens the drone's times so that its coming and going can be watched.
func shorten(stay: Vector2, away: Vector2, fade: float) -> void:
	for key: String in ["music_drone_stay", "music_drone_away", "music_drone_fade_in", "music_drone_fade_out"]:
		if not kept.has(key): kept[key] = settings.get(key)
	settings.music_drone_stay = stay
	settings.music_drone_away = away
	settings.music_drone_fade_in = fade
	settings.music_drone_fade_out = fade


func check_opening() -> void:
	var explore := MusicDirector.MusicState.EXPLORE
	check(MusicDirector.current_state == explore and MusicDirector.drone_in and track(explore) != null,
		"A new attempt opens with the drone, as it always did")
	check(MusicDirector.drone_wait >= settings.music_drone_stay.x - 2.0 and MusicDirector.drone_wait <= settings.music_drone_stay.y,
		"And it will stay 40 to 90 s before it first goes (%.0f s)" % MusicDirector.drone_wait)
	var before := MusicDirector.drone_wait
	await seconds(0.5)
	check(near(before - MusicDirector.drone_wait, 0.5, 0.15), "Its clock runs by itself")


## Stay, go, stay, go: each for its own random time, with no music at all while it is away.
func check_cycle() -> void:
	var explore := MusicDirector.MusicState.EXPLORE
	shorten(Vector2(0.9, 1.4), Vector2(0.9, 1.4), 0.25)
	turns.clear()
	music.clear()
	MusicDirector.turn_drone(true)
	check(turns.size() == 1 and turns[0].coming_in and MusicDirector.drone_in, "The drone can be told to come in (the audition key)")
	var silences := 0
	var presences := 0
	var deadline := now() + 7.5
	var last_turn := 0
	while now() < deadline:
		await get_tree().process_frame
		if turns.size() == last_turn + 1 and now() - turns.back().time > settings.music_drone_fade_out + 0.2:
			last_turn = turns.size()
			if turns.back().coming_in:
				var drone := track(explore)
				presences += int(drone != null and is_zero_approx(drone.volume_db))
			else:
				silences += int(sounding().is_empty())
	var alternates := true
	var in_range := true
	var lengths := {}
	for index in range(1, turns.size()):
		alternates = alternates and turns[index].coming_in != turns[index - 1].coming_in
		var length: float = turns[index].time - turns[index - 1].time
		lengths[snappedf(length, 0.01)] = true
		in_range = in_range and length >= 0.9 - 0.05 and length <= 1.4 + 0.15
	check(turns.size() >= 5 and alternates, "Left alone it goes and comes back, again and again (%d turns in 7.5 s)" % turns.size())
	check(in_range and lengths.size() >= 3, "Each stay and each absence lasts its own random time inside the range (%s)" % [lengths.keys()])
	var times_in := turns.filter(func(turn: Dictionary) -> bool: return turn.coming_in).size() - 1
	var times_out := turns.size() - 1 - times_in
	check(silences >= maxi(times_out - 1, 1), "While it is away there is no music at all (%d of %d absences)" % [silences, times_out])
	check(presences >= maxi(times_in - 1, 1), "While it is there it is at its full level (%d of %d stays)" % [presences, times_in])
	check(music.is_empty() and MusicDirector.current_state == explore, "All of that is still exploration: the state of the music never changed")
	# It goes slowly: halfway through its fade it is neither full nor gone.
	shorten(Vector2(5.0, 5.0), Vector2(5.0, 5.0), 1.0)
	MusicDirector.turn_drone(true)
	await seconds(1.2)
	MusicDirector.turn_drone(false)
	await seconds(0.5)
	var leaving := track(explore)
	check(leaving != null and leaving.volume_db < -3.0 and leaving.volume_db > MusicDirector.SILENT_DB + 5.0, "Going, it fades: halfway it is neither full nor gone (%.1f dB)" % (leaving.volume_db if leaving != null else 0.0))
	MusicDirector.turn_drone(true)
	await seconds(0.3)
	var back := track(explore)
	check(back == leaving and back != null and back.playing, "Called back while it is still going, the same drone rises again: nothing restarts")


## The entity near or far, walking or still: the drone's clock does not notice.
func check_entity_means_nothing() -> void:
	var explore := MusicDirector.MusicState.EXPLORE
	shorten(Vector2(1.0, 1.0), Vector2(1.0, 1.0), 0.2)
	MusicDirector.turn_drone(true)
	turns.clear()
	music.clear()
	# It walks up to her and stands in the same room, unaware.
	entity.global_position = game.player.global_position + Vector2.RIGHT * Units.to_px(3.0)
	await frames(2)
	entity.audio.placed()
	await seconds(0.3)
	check(Acoustics.nearest_ring() >= 2 and Dread.awareness <= Dread.Awareness.PAUSED and turns.is_empty() and MusicDirector.drone_in and track(explore) != null,
		"It comes right up to her, unaware: the drone does not move")
	await seconds(4.4)
	var steady := turns.size() >= 4
	for index in range(1, turns.size()):
		steady = steady and near(turns[index].time - turns[index - 1].time, 1.0, 0.12)
	check(steady and music.is_empty(), "With it beside her the drone keeps exactly its own time (%d turns)" % turns.size())
	check(Dread.presence > 0.3, "Though the house itself knows it is near (presence %.2f)" % Dread.presence)
	# And gone again, just after the drone has left.
	var seen := turns.size()
	await until(func() -> bool: return turns.size() > seen and not MusicDirector.drone_in, 3.0)
	var count := turns.size()
	entity.global_position = home
	await frames(2)
	entity.audio.placed()
	await seconds(0.3)
	check(turns.size() == count and not MusicDirector.drone_in, "It leaves: the drone does not come back for that either")


## What the entity knows always wins over the drone's own clock.
func check_awareness_wins() -> void:
	var explore := MusicDirector.MusicState.EXPLORE
	shorten(Vector2(30.0, 30.0), Vector2(30.0, 30.0), 0.2)
	MusicDirector.turn_drone(false)
	await seconds(0.5)
	check(sounding().is_empty() and not MusicDirector.drone_in, "The drone is away, and will be for a while")
	music.clear()
	cues.clear()
	entity.listen_time_range = Vector2(0.8, 0.8)
	entity.hunt_persistence = 1.5
	entity.search_duration = 3.0
	entity._patrol_wait = 999.0
	NoiseManager.emit_noise(entity.global_position + Vector2.LEFT * Units.to_px(3.0), Units.to_px(40.0), NoiseManager.SourceType.ENVIRONMENT)
	check(await until(func() -> bool: return MusicDirector.current_state == MusicDirector.MusicState.HEARD, 0.5), "It hears something: the music goes to its silence")
	check(await until(func() -> bool: return MusicDirector.current_state == MusicDirector.MusicState.HUNT, 3.0) and cues.has(&"scream"),
		"With the scream the hunt music starts, drone away or not")
	await seconds(settings.music_fade_hunt + 0.2)
	var hunt := track(MusicDirector.MusicState.HUNT)
	check(hunt != null and is_equal_approx(hunt.volume_db, settings.music_hunt_db) and hunt.stream.resource_path == "res://assets/audio/music/hunt.wav",
		"The chase music (music/hunt.wav), at its level (%.1f dB)" % settings.music_hunt_db)
	# The drone's clock turns during the hunt: nothing is heard of it.
	MusicDirector.turn_drone(true)
	await seconds(0.4)
	check(MusicDirector.current_state == MusicDirector.MusicState.HUNT and track(explore) == null and hunt.playing and is_equal_approx(hunt.volume_db, settings.music_hunt_db),
		"The drone's own clock turning during a hunt changes nothing that is heard")
	MusicDirector.turn_drone(false)
	await seconds(0.4)
	check(track(MusicDirector.MusicState.HUNT) == hunt and is_equal_approx(hunt.volume_db, settings.music_hunt_db), "Nor does it take the hunt music away")
	check(await until(func() -> bool: return MusicDirector.current_state == MusicDirector.MusicState.SEARCH, 6.0), "It loses the trail: the thin tone")
	check(await until(func() -> bool: return cues.has(&"stand_down"), 8.0), "It gives up")
	await frames(2)
	var drone := track(explore)
	var length: float = MusicDirector._fades[drone].length if drone != null and MusicDirector._fades.has(drone) else -1.0
	check(MusicDirector.current_state == explore and MusicDirector.drone_in and length >= settings.music_fade_stand_down.x and length <= settings.music_fade_stand_down.y,
		"The drone was away, and it comes back all the same as the entity breathes out, over 6 to 8 s (%.1f s)" % length)
	check(near(MusicDirector.drone_wait, 30.0, 0.5), "And from there it stays its own time again (%.0f s)" % MusicDirector.drone_wait)
	check(music.map(func(change: Dictionary) -> int: return change.to) == [MusicDirector.MusicState.HEARD, MusicDirector.MusicState.HUNT, MusicDirector.MusicState.SEARCH, explore],
		"The music of the whole encounter is what it was: silence, hunt, thin tone, exploration")
	entity.listen_time_range = Vector2(0.7, 1.2)
	entity.hunt_persistence = 5.0
	entity.search_duration = 5.0


## Prayer and the menu have their own music; a new attempt opens with the drone.
func check_other_music() -> void:
	var explore := MusicDirector.MusicState.EXPLORE
	await arm()
	shorten(Vector2(30.0, 30.0), Vector2(30.0, 30.0), 0.2)
	MusicDirector.turn_drone(false)
	await seconds(0.5)
	MusicDirector._on_prayer_started(self)      # the music's side of a prayer only: Viv herself is left alone
	await seconds(0.3)
	check(MusicDirector.current_state == MusicDirector.MusicState.PRAYER and track(MusicDirector.MusicState.PRAYER) != null, "Prayer has its music whether the drone is there or not")
	MusicDirector._on_prayer_ended(self, false)
	await seconds(settings.music_fade + 0.3)
	check(MusicDirector.current_state == explore and not MusicDirector.drone_in and sounding().is_empty(),
		"After the prayer the drone is where its own clock has it: still away")
	# An encounter that ends without a search (it is taken out of the house mid-hunt).
	MusicDirector.set_music_state(MusicDirector.MusicState.HUNT, 0.0)
	MusicDirector.turn_drone(false)
	MusicDirector.clear_entity_threat()
	await frames(3)
	check(MusicDirector.current_state == explore and MusicDirector.drone_in and track(explore) != null,
		"However an encounter ends, the drone comes back after it")
	MusicDirector.set_music_state(MusicDirector.MusicState.MENU, 0.0)
	MusicDirector.turn_drone(false)
	await seconds(0.4)
	check(track(MusicDirector.MusicState.MENU) != null, "The menu's music is not the drone's to take away")
	GameState.reset()
	await frames(3)
	check(MusicDirector.current_state == explore and MusicDirector.drone_in and track(explore) != null and near(MusicDirector.drone_wait, 30.0, 0.5),
		"A new attempt opens with the drone")
