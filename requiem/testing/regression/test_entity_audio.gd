extends Node
## The entity's body sounds (headless): every animation cue has a sound set, the sets exist,
## and in the house each cue plays once, on its frame, from the entity, on the Entity bus.

const ENTITY_ART := "res://tutorial/assets/art/entity"
const RIG_SCRIPT := "res://tutorial/entity_sprite_rig.gd"
## The cue names the animations are known to use (entity-lab clips).
const KNOWN_CUES := ["neck_click", "ear_flick", "claw_scrape", "exhale", "inhale", "scream", "foot_slam",
	"launch_step", "footstep_left", "footstep_right", "footstep_right_hard", "scuttle_step_left",
	"scuttle_step_right", "claw_grope", "pat_tap", "claw_tick", "catch_grab", "cloth_fall", "sob_stops"]

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
## Every cue the rig fired, with what played for it on that same call:
## { cue, set (the first sound, "" = none), sets (all of them), gain (dB before distance) }.
var heard: Array[Dictionary] = []
## Every sound EntityAudio started since the last cue: [set, gain].
var _started: Array = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func _ready() -> void:
	check_cue_map()
	check_sets()
	await check_in_the_house()
	print("[Entity audio tests] %d/%d passed" % [checks - failures.size(), checks])
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)


## Cue names in a clip file: the "name" of every entry of a "sounds" / "sound_frames" list.
func cues_in(value: Variant, found: Dictionary, under_sounds := false) -> void:
	if value is Dictionary:
		if under_sounds and value.has("name"):
			found[String(value["name"])] = true
		for key in value:
			cues_in(value[key], found, String(key) in ["sounds", "sound_frames"])
	elif value is Array:
		for item in value:
			cues_in(item, found, under_sounds)


func check_cue_map() -> void:
	var found := {}
	var files := 0
	for folder in DirAccess.get_directories_at(ENTITY_ART):
		for file in DirAccess.get_files_at(ENTITY_ART.path_join(folder)):
			if file.ends_with(".json"):
				files += 1
				cues_in(JSON.parse_string(FileAccess.get_file_as_string(ENTITY_ART.path_join(folder).path_join(file))), found)
	# Cue names written in the rig script itself (the exhale of a rise or a release).
	var in_script := RegEx.create_from_string("\"(\\w+)\" if n == 0 else \"\"|cue\\.emit\\(\"(\\w+)\"\\)")
	for hit in in_script.search_all(FileAccess.get_file_as_string(RIG_SCRIPT)):
		found[hit.get_string(1) if hit.get_string(1) != "" else hit.get_string(2)] = true
	check(files >= 9 and found.size() >= 19, "The entity-lab clips were read (%d files, %d cue names)" % [files, found.size()])
	var unmapped: Array = found.keys().filter(func(cue: String) -> bool:
		return not EntityAudio.CUE_SETS.has(cue) and not EntityAudio.SILENT_CUES.has(cue))
	check(unmapped.is_empty(), "Every cue name in the clips maps to a sound set or is listed as silent (unmapped: %s)" % [unmapped])
	check(KNOWN_CUES.all(func(cue: String) -> bool: return EntityAudio.CUE_SETS.has(cue) or EntityAudio.SILENT_CUES.has(cue))
		and KNOWN_CUES.all(func(cue: String) -> bool: return found.has(cue)), "The nineteen known cue names are all in the clips and all mapped")
	check(EntityAudio.SILENT_CUES == ["ear_flick"], "Only the ear flick is silent")
	var same_name := ["neck_click", "claw_scrape", "exhale", "inhale", "scream", "foot_slam", "pat_tap", "catch_grab", "cloth_fall", "sob_stops"]
	check(same_name.all(func(cue: String) -> bool: return EntityAudio.CUE_SETS[cue] == "entity/" + cue), "Cues named after a set play that set")
	check(EntityAudio.CUE_SETS["footstep_left"] == "entity/claws_walk" and EntityAudio.CUE_SETS["footstep_right"] == "entity/claws_walk"
		and EntityAudio.CUE_SETS["footstep_right_hard"] == "entity/claws_run" and EntityAudio.CUE_SETS["launch_step"] == "entity/claws_run"
		and EntityAudio.CUE_SETS["scuttle_step_left"] == "entity/claws_scuttle" and EntityAudio.CUE_SETS["scuttle_step_right"] == "entity/claws_scuttle"
		and EntityAudio.CUE_SETS["claw_grope"] == "entity/claw_scrape" and EntityAudio.CUE_SETS["claw_tick"] == "entity/pat_tap",
		"Steps play the walk, run and scuttle claws; the grope is a scrape and the tick a tap")
	var settings := SoundSettings.current()
	check(is_equal_approx(settings.cue_gain_db["claw_grope"], -4.0) and is_equal_approx(settings.cue_gain_db["claw_tick"], -8.0),
		"The grope plays 4 dB and the tick 8 dB under their set")


func check_sets() -> void:
	var settings := SoundSettings.current()
	var wanted := {}
	for cue in EntityAudio.CUE_SETS:
		wanted[EntityAudio.CUE_SETS[cue]] = true
	for loop in [EntityAudio.BREATH_CALM, EntityAudio.BREATH_HUNT, EntityAudio.DRAG]:
		wanted[loop] = true
	var empty: Array = wanted.keys().filter(func(set_id: String) -> bool: return SoundLibrary.files(set_id).is_empty())
	check(empty.is_empty(), "Every set the entity plays has files (empty: %s)" % [empty])
	var walk := SoundLibrary.stream("entity/claws_walk")
	check(walk != null and walk.streams_count == SoundLibrary.files("entity/claws_walk").size() and walk.streams_count >= 10
		and walk.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS,
		"A set is every file of its folder, played at random with no immediate repeat")
	check(is_equal_approx(walk.random_pitch, 1.06) and is_equal_approx(walk.random_volume_offset_db, 2.0)
		and is_equal_approx(settings.set_pitch_range, 0.06), "Each play varies in pitch (0.94 to 1.06) and level (2 dB either way)")
	check([EntityAudio.BREATH_CALM, EntityAudio.BREATH_HUNT, EntityAudio.DRAG].all(func(set_id: String) -> bool:
		return SoundLibrary.files(set_id).all(func(stream: AudioStream) -> bool: return stream is AudioStreamOggVorbis and stream.loop)),
		"The breath and drag sets are loops")
	check(SoundLibrary.gain_db("entity/neck_click") >= 4.0 and SoundLibrary.gain_db("entity/foot_slam") >= 3.0
		and SoundLibrary.gain_db("entity/pat_tap") >= 3.0 and SoundLibrary.gain_db("entity/cloth_fall") >= 6.0
		and is_zero_approx(SoundLibrary.gain_db("entity/heard_voice")),
		"Sets that sit under their loudness target are made up at playback, not squashed")
	# A missing set is silent, warns once, and never crashes.
	check(SoundLibrary.stream("entity/not_a_set") == null and not SoundLibrary.has_set("entity/not_a_set"), "A missing set gives no stream")
	SoundLibrary.stream("entity/not_a_set")
	check(SoundLibrary._warned.size() == 1, "It warns once, however often it is asked for")
	check(not ResourceLoader.exists("res://assets/audio/366137__dcsfx__monster-breathing.wav"), "The NonCommercial breathing file is gone")


func check_in_the_house() -> void:
	GameState.reset()
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	audio = entity.get_node_or_null("EntityAudio") as EntityAudio
	check(audio != null and entity.audio == audio and entity.sprite_rig.cue.is_connected(audio.play_cue),
		"The tutorial entity has an EntityAudio child listening to its animation cues")
	if audio == null:
		return
	var players: Array = audio.get_children()
	check(players.size() == SoundSettings.current().entity_voices + 3 + EntityAudio.AWARENESS_VOICES and players.all(func(player: Node) -> bool:
		return player is AudioStreamPlayer2D and player.bus == AudioBus.ENTITY), "A pool of players, plus breath, drag, voice and the awareness voices, all on the Entity bus")
	check(entity.breath_calm_clips.is_empty() and entity.breath_hunt_clips.is_empty() and entity.hunt_stinger_clips.is_empty()
		and entity.search_cue_clips.is_empty() and entity.investigate_cue_clips.is_empty() and entity.catch_clips.is_empty()
		and entity.drag_clip == null and entity.feel_clip == null,
		"The old clip slots are empty: no stinger, no search riser, no borrowed drag, nothing on INVESTIGATE")
	entity.sprite_rig.cue.disconnect(audio.play_cue)
	entity.sprite_rig.cue.connect(func(_cue: String) -> void: _started.clear())
	entity.sprite_rig.cue.connect(audio.play_cue)
	entity.sprite_rig.cue.connect(_on_cue)
	audio.played.connect(func(set_id: String, voice: AudioStreamPlayer2D) -> void: _started.append([set_id, voice.volume_db]))
	audio.awareness_played.connect(func(_moment: StringName, set_id: String, stream: AudioStream, _level: float) -> void:
		var voice: AudioStreamPlayer2D = audio._aware.filter(func(v: AudioStreamPlayer2D) -> bool: return v.playing and v.stream == stream)[0]
		_started.append([set_id, float(voice.get_meta(&"base"))]))
	for door in game.world.zones["house"].get_node("Doors").get_children():
		if door is Door:
			door.noise_radius_u = 0.0
			door.quiet_noise_radius_u = 0.0

	# Out in the house, patrolling, with Viv far away and silent.
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	var patrol: Vector2 = game.world.marker("house", "Patrol1")
	game.player.global_position = game.world.marker("house", "Patrol4")
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	entity.global_position = patrol
	entity.get_node("CollisionShape2D").disabled = false
	entity.show()
	entity.active = true
	entity._patrol_wait = 0.0
	check(not audio.is_dragging() and audio.breath_set() == "", "Hidden and still, it made no sound")
	var walked := false
	var dragged := false
	for tick in range(600):
		await frames(1)
		walked = walked or entity.velocity.length() > 4.0
		dragged = dragged or (audio.is_dragging() and entity.velocity.length() > 4.0)
		if count("footstep_left") + count("footstep_right") >= 4: break
	check(walked and count("footstep_left") >= 1 and count("footstep_right") >= 1, "On patrol the walk clip fires its footstep cues")
	check(all_played("footstep_left", "entity/claws_walk") and all_played("footstep_right", "entity/claws_walk"),
		"Each footstep plays a claw step on the very call that fired it")
	check(audio.breath_set() == EntityAudio.BREATH_CALM and dragged, "It breathes calmly, and its shroud drags while it moves")
	check(not entity._breath_player.playing and not entity._drag.playing and not entity._stinger_player.playing and not entity._feel_player.playing,
		"The old players stay silent: nothing sounds twice")
	check(audio._voices.any(func(voice: AudioStreamPlayer2D) -> bool: return voice.global_position.distance_to(entity.global_position) < 1.0),
		"Sounds come from where the entity is")

	# A noise: it freezes, its breath and drag stop at once, the head snaps.
	heard.clear()
	NoiseManager.emit_noise(entity.global_position + Vector2(40, 0), 96.0, NoiseManager.SourceType.FOOTSTEP)
	await frames(2)
	check(entity.is_listening() and audio.breath_set() == "" and not audio.is_dragging(), "While it listens it neither breathes nor drags")
	for tick in range(40):
		await frames(1)
		if count("neck_click") > 0 and count("claw_scrape") > 0: break
	check(all_played("neck_click", "entity/neck_click") and count("neck_click") >= 1, "The head snap plays the neck click")
	check(heard.any(func(entry: Dictionary) -> bool: return entry.cue == "neck_click" and entry.sets == ["entity/neck_click", "entity/heard_voice"]),
		"The first head snap carries the heard-you voice with it")
	check(heard.any(func(entry: Dictionary) -> bool: return entry.cue == "neck_click" and is_equal_approx(entry.gain, SoundLibrary.gain_db("entity/neck_click"))),
		"The neck click plays with its make-up gain")
	check(count("ear_flick") >= 1 and heard.all(func(entry: Dictionary) -> bool: return entry.cue != "ear_flick" or entry.set == ""),
		"The ear flick is seen, not heard")

	# The hunt starts: inhale, scream and stomp, then the launch.
	for tick in range(300):
		await frames(1)
		if count("launch_step") > 0: break
	check(all_played("inhale", "entity/inhale") and all_played("scream", "entity/scream") and all_played("foot_slam", "entity/foot_slam")
		and all_played("launch_step", "entity/claws_run") and count("inhale") == 1 and count("scream") == 1 and count("foot_slam") == 1,
		"The hunt start plays inhale, then scream and stomp, then the launch step, once each")
	var order: Array = heard.map(func(entry: Dictionary) -> String: return entry.cue)
	check(order.find("inhale") < order.find("scream") and order.find("scream") < order.find("launch_step"), "In that order")
	entity.last_heard_position = game.world.marker("house", "Patrol3")
	for tick in range(240):
		await frames(1)
		if count("footstep_right_hard") >= 2 and audio.breath_set() == EntityAudio.BREATH_HUNT: break
	check(all_played("footstep_right_hard", "entity/claws_run") and count("footstep_right_hard") >= 1, "In pursuit its hard steps are running claws")
	check(audio.breath_set() == EntityAudio.BREATH_HUNT, "While it hunts it breathes its hunting breath")

	# The trail goes cold: it scuttles, gropes, and feels the floor.
	heard.clear()
	entity._hunt_timer = entity.hunt_persistence
	entity.search_duration = 60.0
	for tick in range(900):
		await frames(1)
		if count("scuttle_step_left") + count("scuttle_step_right") >= 2 and count("claw_grope") >= 1 and count("claw_scrape") + count("pat_tap") >= 1: break
	check(entity.get_state_name() == "SEARCH" and all_played("scuttle_step_left", "entity/claws_scuttle") and all_played("scuttle_step_right", "entity/claws_scuttle")
		and count("scuttle_step_left") + count("scuttle_step_right") >= 2, "Searching, it scuttles on its claws")
	check(count("claw_grope") >= 1 and heard.all(func(entry: Dictionary) -> bool:
		return entry.cue != "claw_grope" or (entry.set == "entity/claw_scrape" and is_equal_approx(entry.gain, SoundLibrary.gain_db("entity/claw_scrape") - 4.0))),
		"The grope is a scrape, 4 dB down")
	check(count("claw_scrape") + count("pat_tap") >= 1 and all_played("claw_scrape", "entity/claw_scrape") and all_played("pat_tap", "entity/pat_tap"),
		"Feeling the floor scrapes and taps")
	check(entity.get_state_name() == "SEARCH" and not entity.is_listening() and audio.breath_set() == EntityAudio.BREATH_CALM,
		"Searching, its breath is calm again")

	# The catch.
	heard.clear()
	entity.play_catch(entity.global_position + Vector2(20, 0))
	for tick in range(200):
		await frames(1)
		if count("sob_stops") > 0: break
	check(all_played("catch_grab", "entity/catch_grab") and all_played("cloth_fall", "entity/cloth_fall") and all_played("sob_stops", "entity/sob_stops")
		and count("catch_grab") == 1 and count("cloth_fall") == 1 and count("sob_stops") == 1, "The catch plays the grab, the cloth and the sob that stops, once each")
	check(audio.breath_set() == "" and not audio.is_dragging(), "Under the catch there is no breath and no drag")
	check(heard.all(func(entry: Dictionary) -> bool:
		return entry.sets.all(func(set_id: String) -> bool: return entry.sets.count(set_id) == 1)), "No cue ever played the same sound twice")
	var route: Array[Vector2] = [patrol]
	entity.reset_encounter(patrol, route)
	await frames(2)
	check(audio._voices.all(func(voice: AudioStreamPlayer2D) -> bool: return not voice.playing) and not audio.is_dragging(),
		"Resetting the encounter cuts whatever it was sounding")
	entity.hide()
	await frames(2)
	check(audio.breath_set() == "" and not audio.is_dragging(), "Hidden again, it is silent")
	audio.set_breathing(true)
	await frames(2)
	check(audio.breath_set() == EntityAudio.BREATH_CALM, "The tutorial can let it be heard breathing before it is seen")
	audio.set_breathing(false)
	game.queue_free()
	await frames(3)


## Runs right after EntityAudio handled the same cue; _started was emptied right before it.
func _on_cue(cue_name: String) -> void:
	var sets: Array = _started.map(func(sound: Array) -> String: return sound[0])
	heard.append({"cue": cue_name, "set": sets[0] if not sets.is_empty() else "", "sets": sets,
		"gain": _started[0][1] if not _started.is_empty() else 0.0})
	_started.clear()


func count(cue_name: String) -> int:
	return heard.filter(func(entry: Dictionary) -> bool: return entry.cue == cue_name).size()


func all_played(cue_name: String, set_id: String) -> bool:
	return heard.all(func(entry: Dictionary) -> bool: return entry.cue != cue_name or entry.set == set_id)
