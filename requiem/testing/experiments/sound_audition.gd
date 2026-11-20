extends "res://tutorial/tutorial.gd"
## Sound audition: the real house, the real entity, the real mix. Development only.
##
## Two things to listen to:
## - every sound set, one variation at a time (the list on the right; a click plays the next
##   variation of that set, "Play every set once" goes down the whole list);
## - a whole encounter: key 1 makes the entity hear a sound where Viv stands, and from there
##   it plays out by itself with its real timings: it listens, screams, hunts (5 s), loses the
##   trail, searches (5 s) and gives up. Keys 2 and 3 skip the waits, key 4 is the catch.
## N turns the entity's knocking on and off for this session (entity_knocks_enabled; saves nothing).
##
## The line at the top reads out what the music and the mix are doing meanwhile, and the box
## under the sound sets how far its sound travels to Viv (the ring, and whether a wall is in the way).
## While "Viv is safe" is on, the entity cannot hear her and cannot catch her, so she can stand
## next to it or walk away from it and listen from anywhere.

const SET_FAMILIES := ["entity", "viv"]
## Where Viv starts: the middle of the house, a room away from the entity's first patrol point.
const VIV_START_MARKER := "Patrol5"
## How long a looping set (breathing, the drag) is played before it is faded out.
const LOOP_SECONDS := 5.0
const LOOP_FADE := 0.3
## Silence between two sets when the whole list is played.
const LIST_GAP := 0.4
## Radius of the sound key 1 makes: large enough to be heard wherever the entity is.
const HEARD_RADIUS_U := 60.0
## The catch is played from this far away from Viv.
const CATCH_REACH := 28.0
## Padding above and below the text of a sound-set button: as little as reads well, so that
## every set and the read-out under them fit on screen (31 sets, 16 rows, today).
const SET_BUTTON_PAD := 1.0

## On: the entity cannot hear Viv's own noises and cannot catch her.
var safe := true
var studio_status: Label
var mix_status: Label
var house_status: Label
var where_status: Label
var safe_button: Button
var set_buttons := {}
var sets: Array[String] = []
var _entity_voice: AudioStreamPlayer2D
var _viv_voice: AudioStreamPlayer
## Sets still to play when the whole list was asked for, and the wait before the next one.
var _list: Array[String] = []
var _list_wait := 0.0
var _playing_set := ""
var _built := false


func _ready() -> void:
	test_mode = true
	start_zone = "house"
	# The tutorial's automated mode silences Viv's own clips. Here they are part of the mix.
	var walk_audio: Array[AudioStream] = player.get_node("FootstepNoise").walk_clips.duplicate()
	var hold_audio: Array[AudioStream] = player.get_node("HoldBreath").hold_clips.duplicate()
	var exertion_audio: Array[AudioStream] = player.get_node("HoldBreath").exertion_clips.duplicate()
	super._ready()
	player.get_node("FootstepNoise").walk_clips.assign(walk_audio)
	breath.hold_clips.assign(hold_audio)
	breath.exertion_clips.assign(exertion_audio)
	thrower.available = false
	friend_met = true
	has_flashlight = true
	flashlight.battery_percent = 100.0
	flashlight.is_on = true
	flashlight.set_process(true)
	flashlight.set_process_unhandled_input(true)
	flashlight._refresh_light()
	_entity_voice = AudioStreamPlayer2D.new()
	_entity_voice.name = "AuditionVoice"
	_entity_voice.bus = AudioBus.ENTITY
	# Auditioning a set plays it as it is, at any distance: this is a listening booth.
	_entity_voice.max_distance = EntityAudio.NO_ENGINE_FALLOFF_PX
	_entity_voice.attenuation = 1.0
	entity.add_child(_entity_voice)
	_viv_voice = AudioStreamPlayer.new()
	_viv_voice.name = "AuditionVoice"
	_viv_voice.bus = AudioBus.BODY
	player.add_child(_viv_voice)
	for family: String in SET_FAMILIES:
		var folders := Array(DirAccess.get_directories_at(SoundLibrary.ROOT + family))
		folders.sort()
		for folder: String in folders:
			sets.append("%s/%s" % [family, folder])
	_build_controls()
	_built = true
	enter_zone("house", world.marker("house", VIV_START_MARKER))
	set_safe(true)


## Every way into the house here ends the same: after the attack, the entity on its patrol,
## the house ambience on (the tutorial's automated mode leaves it off).
func enter_zone(next_zone: String, spawn := Vector2.INF, save := true, arrival_door := "") -> void:
	attack_finished = true
	super.enter_zone(next_zone, spawn, save, arrival_door)
	AmbienceManager.set_track(load(ZONE_AMBIENCE_PATHS[zone]) as AudioStream, ZONE_AMBIENCE_VOLUME_DB[zone], 1.0)
	if zone != "house":
		return
	var points: Array[Vector2] = []
	for index in range(1, 7):
		points.append(world.marker("house", "Patrol%d" % index))
	entity.reset_encounter(points[0], points)
	entity.get_node("CollisionShape2D").set_deferred("disabled", false)
	entity.show()
	entity.active = true
	entity.set_breathing(true)
	if _built:
		set_safe(safe)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SoundAuditionOverlay"
	layer.layer = 30
	LegacyUi.fit_layer(layer)
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(20, 4)
	panel.add_theme_constant_override("separation", 1)
	layer.add_child(panel)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	panel.add_child(heading)
	heading.add_child(_label("SOUND AUDITION", 16))
	studio_status = _label("", 14)
	heading.add_child(studio_status)
	mix_status = _label("", 13)
	panel.add_child(mix_status)
	house_status = _label("", 12)
	panel.add_child(house_status)
	panel.add_child(_label("WASD move · Space hold breath · F light · E doors · N its knocking · J a house knock · Esc pause · F1 Test Lab", 12))
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	panel.add_child(controls)
	_button(controls, "1 · It hears a sound", make_it_hear).tooltip_text = \
		"A sound lands where Viv stands. The whole encounter follows by itself: listen, scream, hunt, lost, search, gave up."
	_button(controls, "2 · Lose the trail now", lose_trail).tooltip_text = "While it hunts: skip to the moment it loses the trail."
	_button(controls, "3 · Give up now", give_up).tooltip_text = "While it searches: skip to the moment it gives up."
	_button(controls, "4 · Catch", audition_catch).tooltip_text = "The catch and the game over screen. R starts over."
	_button(controls, "R · Start over", reset_audition)
	_button(controls, "H · House effect", house_hurry).tooltip_text = \
		"Brings the house's next effect forward. Its gates still apply: nothing plays while the entity is alert or near."
	_button(controls, "K · House answers", house_answer).tooltip_text = \
		"As if Viv had slammed a trunk lid: one knock from another room about a second later, if it is safe."
	_button(controls, "M · Drone", turn_drone).tooltip_text = \
		"The exploration drone comes and goes on its own clock (40 to 90 s each way). This turns it now."
	safe_button = _button(controls, "", func() -> void: set_safe(not safe))
	safe_button.tooltip_text = "On: the entity cannot hear Viv's own noises and cannot catch her."
	# The sound sets, down the right edge: just under the controls, packed tight so that every
	# set and the read-out under them stay on screen.
	var list := VBoxContainer.new()
	list.position = Vector2(PixelDisplay.UI_CANVAS.x - 330.0, 118.0)
	list.add_theme_constant_override("separation", 2)
	layer.add_child(list)
	list.add_child(_label("SOUND SETS · a click plays the next variation", 12))
	_button(list, "0 · Play every set once", play_every_set)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 1)
	list.add_child(grid)
	for set_id: String in sets:
		var button := _button(grid, "%s (%d)" % [set_id.replace("/", " · "), SoundLibrary.files(set_id).size()], play_set_once.bind(set_id))
		button.add_theme_font_size_override("font_size", 11)
		button.custom_minimum_size = Vector2(160, 0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_tighten(button)
		set_buttons[set_id] = button
	# How far its sound travels to Viv, under the list.
	list.add_child(_label("WHERE IT IS, BY EAR", 12))
	where_status = _label("", 12)
	where_status.add_theme_constant_override("line_spacing", 0)
	list.add_child(where_status)


## Less padding above and below a button's text (its look is otherwise the theme's).
func _tighten(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var box := button.get_theme_stylebox(state)
		if box == null:
			continue
		box = box.duplicate() as StyleBox
		box.content_margin_top = SET_BUTTON_PAD
		box.content_margin_bottom = SET_BUTTON_PAD
		button.add_theme_stylebox_override(state, box)


## N. The entity's knocking on and off, for this session only (the settings file is not saved).
func toggle_knocks() -> void:
	var settings := SoundSettings.current()
	settings.entity_knocks_enabled = not settings.entity_knocks_enabled


func knocks_text() -> String:
	var voice: EntityAudio = entity.audio
	if not SoundSettings.current().entity_knocks_enabled:
		return "knocks: off"
	if voice == null or voice.last_knock.is_empty():
		return "knocks: on (none yet)" if SoundLibrary.has_set(EntityAudio.KNOCK) else "knocks: on (no file)"
	return "knocks: on (last %.0f s ago)" % (voice._clock - float(voice.last_knock.clock))


func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("dfd9be"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	# Space and the number keys must always reach the game, even after a click.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Safe: the entity is deaf to the noises of the game (only key 1 reaches it) and its touch
## does nothing. Off: it hears Viv and catches her, as in the game.
func set_safe(on: bool) -> void:
	safe = on
	var hears := Callable(entity, "_on_noise_emitted")
	if on and NoiseManager.noise_emitted.is_connected(hears):
		NoiseManager.noise_emitted.disconnect(hears)
	elif not on and not NoiseManager.noise_emitted.is_connected(hears):
		NoiseManager.noise_emitted.connect(hears)
	safe_button.text = "T · Viv is safe: on" if on else "T · Viv is safe: OFF"


## Key 1. The entity hears a sound at Viv's feet, exactly as if she had made it.
func make_it_hear() -> void:
	if resetting or not entity.active:
		return
	entity._on_noise_emitted(player.global_position, Units.to_px(HEARD_RADIUS_U), NoiseManager.SourceType.ENVIRONMENT, 0.0)


## Key 2. Only while it hunts (not while it still stands screaming).
func lose_trail() -> void:
	if entity.active and entity.get_state_name() == "HUNT" and not entity.is_screaming():
		entity._begin_search()


## Key 3. Only while it searches.
func give_up() -> void:
	if entity.active and entity.get_state_name() == "SEARCH" and not entity.is_listening():
		entity._change_state(entity.State.PATROL)


## Key 4. The real catch, from next to Viv, and the game over screen after it.
func audition_catch() -> void:
	if resetting or not entity.active:
		return
	if entity.global_position.distance_to(player.global_position) > CATCH_REACH:
		entity.global_position = player.global_position + Vector2(CATCH_REACH, 0)
		if entity.audio != null:
			entity.audio.placed()       # it was moved by hand: it is heard from here at once
	# The automated mode skips the wait before the game over screen; here the catch plays out.
	test_mode = false
	_begin_game_over()
	test_mode = true


## R. Back to the start: Viv in the middle of the house, the entity on its patrol, unaware.
func reset_audition() -> void:
	_list.clear()
	_stop_voices()
	for action_name in ["hold_breath", "sprint", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action_name)
	restore_checkpoint()


func retry_from_game_over() -> void:
	reset_audition()


## Plays one variation of a set (the next one, never the one before). Entity sets play from
## where the entity is, on its bus; Viv's play on Body. Returns how long it will sound.
func play_set_once(set_id: String) -> float:
	# A folder still waiting for its files (her steps by surface) is not a fault: no warning.
	var stream: AudioStream = null if SoundLibrary.files(set_id).is_empty() else SoundLibrary.pick(set_id)
	if stream == null:
		_playing_set = "%s is empty" % set_id
		return 0.0
	var voice: Node = _entity_voice if set_id.begins_with("entity/") else _viv_voice
	var looping: bool = (stream is AudioStreamOggVorbis and stream.loop) or (stream is AudioStreamMP3 and stream.loop) \
		or (stream is AudioStreamWAV and stream.loop_mode != AudioStreamWAV.LOOP_DISABLED)
	var length: float = LOOP_SECONDS if looping else stream.get_length()
	_stop_voices()
	voice.stream = stream
	voice.volume_db = SoundLibrary.gain_db(set_id)
	voice.play()
	_playing_set = "%s · %s%s" % [set_id, stream.resource_path.get_file(), " (loop)" if looping else ""]
	if looping:
		var fade := create_tween()
		fade.tween_interval(LOOP_SECONDS - LOOP_FADE)
		fade.tween_property(voice, "volume_db", -60.0, LOOP_FADE)
		fade.tween_callback(voice.stop)
		voice.set_meta(&"fade", fade)
	return length


## Key 0. Every set, once, in order.
func play_every_set() -> void:
	_list.assign(sets)
	_list_wait = 0.0


func _stop_voices() -> void:
	for voice: Node in [_entity_voice, _viv_voice]:
		if voice.has_meta(&"fade"):
			var fade: Tween = voice.get_meta(&"fade")
			if fade != null and fade.is_valid():
				fade.kill()
			voice.remove_meta(&"fade")
		voice.stop()


## How its sound reaches Viv right now (audio/acoustics.gd, measured 5 times per second).
func where_text() -> String:
	var heard: AcousticReading = Acoustics.reading(entity)
	if not heard.valid:
		return "ring 0 · gone (nothing to hear)"
	var text := "ring %d · %s\nits sound travels %.1f u · clarity %.2f\nstraight line %.1f u · walking path %s\nwall in the way: %s" % [
		heard.ring, heard.ring_name(), heard.acoustic_u, heard.clarity, heard.straight_u,
		"%.1f u" % heard.path_u if heard.path_u >= 0.0 else "none", "yes" if heard.blocked else "no"]
	# What that does to its position sounds (breath, talking, claws, drag, sniffing).
	var voice: EntityAudio = entity.audio
	if voice == null:
		return text
	var lost := 0
	for set_id: String in voice.gaps:
		lost += int(voice.gaps[set_id])
	# What is really applied: distance, the calm trim beside her and her own steps.
	var level: float = voice.position_level_db()
	var her_body := player.get_node_or_null("BodyAudio") as BodyAudio
	var her := "" if her_body == null else "\nViv: %s · listening %.2f · her steps cover %.0f dB" % [
		her_body.mood.get_file() if her_body.mood != "" else "no breathing", her_body.listen, -voice.masked_db()]
	# Its own line, only while she pants: on the line above it would not fit the column.
	if her_body != null and her_body.pant > 0.0:
		her += "\nViv: panting %d%% (she is tired)" % roundi(her_body.pant * 100.0)
	return text + "\nposition sounds: %s\nplaced %d%% · lost on the way %d · %s\npresence %.2f · the house recedes %.2f%s" % [
		"silent" if level <= EntityAudio.GONE_DB else "%.1f dB%s · %d%% dulled" % [level,
			" (calm %.1f)" % voice.calm_trim_db() if voice.calm_trim_db() < -0.05 else "", roundi((1.0 - voice.heard_clarity) * 100.0)],
		roundi(EntityAudio.position_panning(voice.heard_u, voice.reach_limit_u()) * 100.0), lost, breath_text(voice), Dread.presence, MixDirector.recede(), her]


## Its breath in a few words: none, its hunting breath, or its calm breathing in a spell
## ("breath on 5 s": 5 s of this spell left), kept going with no rests ("breath on, held": it
## has heard something, or she holds her breath) or resting ("breath rests 12 s").
func breath_text(voice: EntityAudio) -> String:
	var set_id := voice.breath_set()
	if set_id == "":
		return "no breath"
	if set_id != EntityAudio.BREATH_CALM:
		return "breath hunt"
	if voice.breath_held():
		return "breath on, held"
	if voice.breath_resting():
		return "breath rests %.0f s" % voice.breath_left()
	return "breath on %.0f s" % voice.breath_left()


## H. The house's next effect is due now (if its gates are open).
func house_hurry() -> void:
	HouseVoice.hurry()


## J. The house's next effect is a knock, due now (if its gates are open).
func house_knock() -> void:
	HouseVoice.hurry_knock()


## M. The exploration drone turns now instead of on its own clock: in if it is away, away if it is in.
func turn_drone() -> void:
	MusicDirector.turn_drone(not MusicDirector.drone_in)


## The music of the moment; during exploration, also where the drone is on its own clock.
func music_text() -> String:
	var state: String = MusicDirector.STATE_NAMES[MusicDirector.current_state]
	if MusicDirector.current_state != MusicDirector.MusicState.EXPLORE:
		return state
	return "%s (%s %.0f s)" % [state, "drone in, goes in" if MusicDirector.drone_in else "no drone, back in", MusicDirector.drone_wait]


## K. Viv did something loud: the house may answer with one knock.
func house_answer() -> void:
	HouseVoice.answer()


## What the house voice is doing and why, and the last thing it did.
func house_text() -> String:
	var last := "nothing yet"
	if not HouseVoice.history.is_empty():
		var entry: Dictionary = HouseVoice.history.back()
		last = String(entry.family) + ("" if entry.file == "" else " · " + String(entry.file).get_file())
	return "House voice: %s · last: %s" % [HouseVoice.status(), last]


## What the entity is doing, in the words of the design.
func phase() -> String:
	if not entity.active or not entity.visible:
		return "CAUGHT" if GameState.is_dead or (entity.audio != null and entity.audio.is_catching()) else "inactive"
	if entity.is_listening():
		return "LISTEN"
	if entity.is_screaming():
		return "HUNT START (scream)"
	var state: String = entity.get_state_name()
	if state == "PATROL" and Dread.awareness == Dread.Awareness.PAUSED:
		return "PATROL (pause)"
	return state


func _process(delta: float) -> void:
	super._process(delta)
	if not _built:
		return
	flashlight.battery_percent = 100.0
	if not _list.is_empty():
		_list_wait -= delta
		if _list_wait <= 0.0:
			_list_wait = play_set_once(_list.pop_front()) + LIST_GAP
	var cue: String = String(entity.audio.last_awareness.get("moment", "none")) if entity.audio != null else "none"
	studio_status.text = "It: %s · last cue: %s · %s%s" % [phase(), cue, knocks_text(), "" if _playing_set == "" else " · set: " + _playing_set]
	where_status.text = where_text()
	house_status.text = house_text()
	mix_status.text = "threat %.2f (%s) · music %s · Ambience %+.1f dB · World %+.1f dB · Body %+.1f dB · Music bus %+.1f dB" % [
		Dread.threat, Dread.awareness_name(), music_text(),
		MixDirector.gain_db(AudioBus.AMBIENCE), MixDirector.gain_db(AudioBus.WORLD), MixDirector.gain_db(AudioBus.BODY), MixDirector.gain_db(AudioBus.MUSIC)]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not _paused:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var handled := true
		match key:
			KEY_1: make_it_hear()
			KEY_2: lose_trail()
			KEY_3: give_up()
			KEY_4: audition_catch()
			KEY_0: play_every_set()
			KEY_H: house_hurry()
			KEY_J: house_knock()
			KEY_K: house_answer()
			KEY_M: turn_drone()
			KEY_N: toggle_knocks()
			KEY_T: set_safe(not safe)
			KEY_R: reset_audition()
			KEY_F1:
				if get_parent().has_method("show_menu"):
					handled = false
				else:
					get_tree().paused = false
					get_tree().change_scene_to_file.call_deferred("res://testing/test_lab.tscn")
			_: handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	super._input(event)


## No story here: the house makes no noises of its own, only doors can be used, and no door
## leads out.
func in_unease() -> bool:
	return false


func interaction_available(id: String) -> bool:
	return world.interactables[id]["node"] is Door and id not in ZONE_DOORS


func _zone_door_active(_id: String) -> bool:
	return false


func _caught() -> void:
	if not safe:
		super._caught()


func restore_checkpoint(bedroom := false) -> void:
	super.restore_checkpoint(bedroom)
	thrower.available = false


func _on_rock_landed(_at: Vector2) -> void:
	pass
