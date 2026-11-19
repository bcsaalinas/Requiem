extends Node2D

func _ready() -> void:
	# This isolated suite does not exercise menu music; release its autostarted stream.
	MusicDirector.set_process(false)
	for player in MusicDirector.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
	GameState.is_dead = false
	var entity = load("res://tutorial/tutorial_entity.tscn").instantiate()
	add_child(entity)
	entity.set_physics_process(false)
	entity.sprite_rig.set_process(false)
	assert(not entity._breath_player.playing, "Inactive monster must be silent")
	entity.set_breathing(true)
	assert(entity._breath_player.playing, "Story breathing must work before activation")
	entity.active = true
	entity.set_breathing(false)
	entity.notice(Vector2(100, 100))
	assert(entity.is_listening() and not entity._breath_player.playing)
	entity._listening = 0.0
	entity._start_hunt()
	assert(entity.is_screaming() and not entity._breath_player.playing)
	assert(entity._stinger_player.stream == entity.hunt_stinger_clips[0])
	var playback: float = entity._stinger_player.get_playback_position()
	entity._start_hunt()
	assert(entity._stinger_player.get_playback_position() >= playback)
	entity._scream_left = 0.0
	entity._resume_breathing()
	assert(entity._breath_player.playing and entity._breath_player.pitch_scale > 1.1)
	entity._change_state(entity.State.SEARCH)
	assert(entity._stinger_player.stream == entity.search_cue_clips[0])
	assert(is_equal_approx(entity._breath_player.pitch_scale, 1.06))
	entity._change_state(entity.State.PATROL)
	assert(is_equal_approx(entity._breath_player.pitch_scale, 0.94))
	entity.play_catch(Vector2.ZERO)
	assert(not entity._breath_player.playing)
	assert(entity._stinger_player.stream == entity.catch_clips[0])
	assert(is_equal_approx(entity._stinger_player.pitch_scale, 1.0))
	assert(not entity._devour_player.playing, "Eating must wait for the animation")
	entity.sprite_rig._tick_catch(739.0)
	assert(not entity._devour_player.playing, "No crunch before player is pulled under")
	entity.sprite_rig._tick_catch(1.0)
	assert(entity._devour_player.playing, "Crunch starts on the 740ms hide-player event")
	assert(entity._devour_player.bus == "SFX")
	assert(entity.devour_clip.get_length() + 0.74 < entity.catch_screen_delay)
	var devour_position: float = entity._devour_player.get_playback_position()
	entity.sprite_rig.hide_player.emit()
	assert(entity._devour_player.get_playback_position() >= devour_position, "Duplicate cue must not restart")
	assert(entity.breath_volume_db == -6.0 and entity.stinger_volume_db == 2.0)
	var points: Array[Vector2] = [Vector2.ZERO]
	entity.reset_encounter(Vector2.ZERO, points)
	assert(not entity._breath_player.playing and not entity._stinger_player.playing)
	assert(not entity._devour_player.playing and not entity._devour_started, "Retry cancels and rearms the eating cue")
	entity.play_catch(Vector2.ZERO)
	entity.sprite_rig._tick_catch(740.0)
	assert(entity._devour_player.playing, "Eating cue works again after retry")
	entity.reset_encounter(Vector2.ZERO, points)
	assert(entity._drag.bus == "SFX" and entity._feel_player.bus == "SFX")
	entity.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[Entity audio tests] 1/1 passed: transitions, silence, capture and reset")
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
