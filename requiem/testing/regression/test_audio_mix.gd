extends Node
## The bus layout and its single owner (headless).
## Buses and their effects, who may be muffled, request priorities and fades, the volume
## sliders, the breath duck, where Viv's sounds play, where she listens from, and a scan of the
## scripts for anything but MixDirector touching a bus.

## The only scripts that may change the audio server. Preferences and the pause menu own the
## player's volume sliders (bus volume and mute); MixDirector owns everything else.
const MIX_OWNER := "res://audio/mix_director.gd"
const VOLUME_OWNERS := ["res://autoloads/preferences.gd", "res://tutorial/pause_menu.gd"]
const SKIPPED_FOLDERS := ["res://addons", "res://testing", "res://.godot", "res://builds", "res://.local-development", "res://tools"]

var failures: Array[String] = []
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func _ready() -> void:
	var saved_path: String = Preferences.storage_path
	Preferences.storage_path = "user://requiem-mix-test-%s.cfg" % OS.get_process_id()
	Preferences.load_preferences()
	check_layout()
	check_muffle_rules()
	await check_priorities()
	await check_fades()
	check_volume_sliders()
	await check_breath_duck()
	await check_player()
	check_single_owner()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Preferences.storage_path))
	Preferences.storage_path = saved_path
	Preferences.load_preferences()
	print("[Audio mix tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func effects(bus_name: StringName) -> Array[AudioEffect]:
	var found: Array[AudioEffect] = []
	var bus := AudioServer.get_bus_index(bus_name)
	for slot in AudioServer.get_bus_effect_count(bus):
		found.append(AudioServer.get_bus_effect(bus, slot))
	return found


func has_effect(bus_name: StringName, effect_class: String, effect_name := "") -> bool:
	return effects(bus_name).any(func(effect: AudioEffect) -> bool:
		return effect.is_class(effect_class) and (effect_name == "" or effect.resource_name == effect_name))


func check_layout() -> void:
	var settings := SoundSettings.current()
	var names: Array[StringName] = []
	for index in AudioServer.bus_count:
		names.append(StringName(AudioServer.get_bus_name(index)))
	var expected: Array[StringName] = [AudioBus.MASTER]
	expected.append_array(AudioBus.ALL)
	check(names == expected, "The buses are Master, Music, Ambience, World, Body, UI, Entity, EntityFar, SFX (found %s)" % [names])
	check(AudioBus.ALL.all(func(bus_name: StringName) -> bool:
		return AudioServer.get_bus_send(AudioServer.get_bus_index(bus_name)) == AudioBus.MASTER),
		"Every bus plays into Master")
	var limiters := effects(AudioBus.MASTER).filter(func(effect: AudioEffect) -> bool: return effect is AudioEffectHardLimiter)
	check(limiters.size() == 1 and is_equal_approx(limiters[0].ceiling_db, settings.limiter_ceiling_db)
		and is_equal_approx(settings.limiter_ceiling_db, -1.0), "Master ends in one limiter with a -1 dB ceiling")
	check(has_effect(AudioBus.ENTITY, "AudioEffectReverb") and not has_effect(AudioBus.ENTITY, "AudioEffectLowPassFilter"),
		"The Entity bus has a reverb and no filter")
	var far_filters := effects(AudioBus.ENTITY_FAR).filter(func(effect: AudioEffect) -> bool: return effect is AudioEffectLowPassFilter)
	check(far_filters.size() == 1 and is_equal_approx(far_filters[0].cutoff_hz, settings.far_cutoff_hz)
		and has_effect(AudioBus.ENTITY_FAR, "AudioEffectReverb"), "The EntityFar bus is low-passed and has a reverb")
	var near_reverb: AudioEffectReverb = effects(AudioBus.ENTITY).filter(func(effect: AudioEffect) -> bool: return effect is AudioEffectReverb)[0]
	var far_reverb: AudioEffectReverb = effects(AudioBus.ENTITY_FAR).filter(func(effect: AudioEffect) -> bool: return effect is AudioEffectReverb)[0]
	check(far_reverb.wet > near_reverb.wet and near_reverb.wet <= 0.15, "The far reverb is a little wetter than the near one, which is small")
	check(AudioBus.MIXABLE.all(func(bus_name: StringName) -> bool: return has_effect(bus_name, "AudioEffectAmplify", MixDirector.GAIN_NAME))
		and not has_effect(AudioBus.MASTER, "AudioEffectAmplify") and not has_effect(AudioBus.UI, "AudioEffectAmplify"),
		"The mix has its own gain stage on every bus it may move, and none on Master or UI")


func check_muffle_rules() -> void:
	for bus_name in AudioBus.ALL:
		var muffled := has_effect(bus_name, "AudioEffectLowPassFilter", MixDirector.MUFFLE_NAME)
		check(muffled == AudioBus.MUFFLEABLE.has(bus_name), "%s %s be muffled" % [bus_name, "can" if AudioBus.MUFFLEABLE.has(bus_name) else "can never"])
	check(AudioBus.MUFFLEABLE == [AudioBus.MUSIC, AudioBus.AMBIENCE, AudioBus.WORLD], "Only Music, Ambience and World may be muffled")
	var accepted: bool = MixDirector.muffle(&"test_forbidden", MixDirector.Priority.SCREAM,
		{AudioBus.ENTITY: 500.0, AudioBus.ENTITY_FAR: 500.0, AudioBus.BODY: 500.0, AudioBus.WORLD: 500.0})
	check(not accepted and is_equal_approx(MixDirector.cutoff_hz(AudioBus.WORLD), 500.0)
		and MixDirector.muffle_filter(AudioBus.ENTITY) == null and MixDirector.muffle_filter(AudioBus.BODY) == null,
		"A muffle asked of the entity or of Viv's body is refused; the rest of the request still applies")
	var far_filter: AudioEffectLowPassFilter = effects(AudioBus.ENTITY_FAR).filter(func(effect: AudioEffect) -> bool: return effect is AudioEffectLowPassFilter)[0]
	check(is_equal_approx(far_filter.cutoff_hz, SoundSettings.current().far_cutoff_hz), "The EntityFar filter is not something a request can move")
	MixDirector.release(&"test_forbidden")
	check(is_equal_approx(MixDirector.cutoff_hz(AudioBus.WORLD), SoundSettings.current().open_hz), "Releasing a muffle opens the bus again")


func check_priorities() -> void:
	var volumes_before := bus_volumes()
	MixDirector.duck(&"test_threat", MixDirector.Priority.THREAT, {AudioBus.AMBIENCE: -10.0, AudioBus.WORLD: -10.0})
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), -10.0), "A request with no fade applies at once")
	MixDirector.duck(&"test_prayer", MixDirector.Priority.PRAYER, {AudioBus.AMBIENCE: -6.0})
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), -6.0) and is_equal_approx(MixDirector.gain_db(AudioBus.WORLD), -10.0),
		"Prayer outranks threat on the bus they share; the other bus keeps its request")
	MixDirector.duck(&"test_breath", MixDirector.Priority.BREATH, {AudioBus.AMBIENCE: -3.0})
	MixDirector.duck(&"test_scream", MixDirector.Priority.SCREAM, {AudioBus.AMBIENCE: -14.0})
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), -14.0), "The scream duck outranks everything")
	MixDirector.duck(&"test_threat", MixDirector.Priority.THREAT, {AudioBus.AMBIENCE: -20.0, AudioBus.WORLD: -10.0})
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), -14.0), "A lower request changing underneath does not move the bus")
	MixDirector.release(&"test_scream")
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), -3.0), "When the scream ends, hold-breath is next")
	MixDirector.release(&"test_breath")
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), -6.0), "Then prayer")
	MixDirector.release(&"test_prayer")
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), -20.0), "Then threat")
	MixDirector.release(&"test_threat")
	check(is_zero_approx(MixDirector.gain_db(AudioBus.AMBIENCE)) and is_zero_approx(MixDirector.gain_db(AudioBus.WORLD)),
		"With no request left the bus is back at rest")
	MixDirector.focus(&"test_focus", MixDirector.Priority.THREAT, {AudioBus.BODY: 3.0, AudioBus.MASTER: -40.0, AudioBus.UI: -40.0})
	check(is_equal_approx(MixDirector.gain_db(AudioBus.BODY), 3.0) and is_zero_approx(MixDirector.gain_db(AudioBus.MASTER)),
		"A bus can be brought forward; Master and UI are never moved")
	MixDirector.release(&"test_focus")
	check(bus_volumes() == volumes_before, "None of it moved a bus volume: those belong to the player's sliders")
	check(MixDirector.Priority.DEATH > MixDirector.Priority.SCREAM and MixDirector.Priority.SCREAM > MixDirector.Priority.BREATH
		and MixDirector.Priority.BREATH > MixDirector.Priority.PRAYER and MixDirector.Priority.PRAYER > MixDirector.Priority.THREAT,
		"The order is: death, the scream, hold-breath, prayer, threat")
	# A request dies with the node that made it.
	var holder := Node.new()
	add_child(holder)
	MixDirector.duck(&"test_orphan", MixDirector.Priority.THREAT, {AudioBus.MUSIC: -12.0}, 0.0, holder)
	holder.free()
	await seconds(SoundSettings.current().orphan_fade + 0.2)
	check(not MixDirector.is_active(&"test_orphan") and is_zero_approx(MixDirector.gain_db(AudioBus.MUSIC)),
		"A request is let go when the node that made it leaves")


func check_fades() -> void:
	MixDirector.duck(&"test_fade", MixDirector.Priority.SCREAM, {AudioBus.MUSIC: -14.0}, 0.4)
	await seconds(0.2)
	var halfway: float = MixDirector.gain_db(AudioBus.MUSIC)
	check(halfway < -3.0 and halfway > -11.0, "A duck fades in (%.1f dB halfway)" % halfway)
	await seconds(0.35)
	var gain: AudioEffectAmplify = effects(AudioBus.MUSIC).filter(func(effect: AudioEffect) -> bool: return effect.resource_name == MixDirector.GAIN_NAME)[0]
	check(is_equal_approx(MixDirector.gain_db(AudioBus.MUSIC), -14.0) and is_equal_approx(gain.volume_db, -14.0),
		"It arrives, and the bus effect carries the value")
	MixDirector.release(&"test_fade", 0.3)
	await seconds(0.15)
	check(MixDirector.gain_db(AudioBus.MUSIC) < -2.0 and MixDirector.gain_db(AudioBus.MUSIC) > -12.0, "The release fades too")
	await seconds(0.3)
	check(is_zero_approx(gain.volume_db), "And ends at rest")
	MixDirector.muffle(&"test_muffle_fade", MixDirector.Priority.BREATH, {AudioBus.WORLD: 2500.0}, 0.3)
	await seconds(0.15)
	var cutoff: float = MixDirector.cutoff_hz(AudioBus.WORLD)
	check(cutoff > 2500.0 and cutoff < SoundSettings.current().open_hz, "A muffle closes gradually (%.0f Hz halfway)" % cutoff)
	await seconds(0.3)
	check(is_equal_approx(MixDirector.muffle_filter(AudioBus.WORLD).cutoff_hz, 2500.0), "And settles on its cutoff")
	MixDirector.release(&"test_muffle_fade")
	# A fade in progress is not cut short by requests that keep changing underneath it or
	# after it: the mood of the house moves every frame.
	MixDirector.follow(&"test_mood", MixDirector.Priority.THREAT, {AudioBus.AMBIENCE: -6.0})
	MixDirector.duck(&"test_over", MixDirector.Priority.SCREAM, {AudioBus.AMBIENCE: -14.0}, 0.4)
	for step in 6:
		await get_tree().physics_frame
		MixDirector.follow(&"test_mood", MixDirector.Priority.THREAT, {AudioBus.AMBIENCE: -6.0 - step * 0.1})
	var attack: float = MixDirector.gain_db(AudioBus.AMBIENCE)
	check(attack < -6.0 and attack > -13.5, "A lower request that keeps changing does not cut short the fade above it (%.1f dB)" % attack)
	await seconds(0.45)
	MixDirector.release(&"test_over", 0.6)
	for step in 6:
		await get_tree().physics_frame
		MixDirector.follow(&"test_mood", MixDirector.Priority.THREAT, {AudioBus.AMBIENCE: -7.0 + step * 0.1})
		# Said twice in one frame, it still changes nothing.
		MixDirector.follow(&"test_mood", MixDirector.Priority.THREAT, {AudioBus.AMBIENCE: -7.0 + step * 0.1})
	var release_db: float = MixDirector.gain_db(AudioBus.AMBIENCE)
	check(release_db < -8.0 and release_db > -14.0, "Nor does it cut short the release that hands the bus back to it (%.1f dB)" % release_db)
	await seconds(0.65)
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), MixDirector.target_db(AudioBus.AMBIENCE))
		and is_equal_approx(MixDirector.target_db(AudioBus.AMBIENCE), -6.5), "And the bus ends on the value it asks for")
	MixDirector.follow(&"test_mood", MixDirector.Priority.THREAT, {AudioBus.AMBIENCE: -3.0})
	check(is_equal_approx(MixDirector.gain_db(AudioBus.AMBIENCE), -3.0), "With no fade in progress, a request moving its own value applies at once")
	MixDirector.release(&"test_mood")


func bus_volumes() -> Array:
	var volumes := []
	for index in AudioServer.bus_count:
		volumes.append([AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)])
	return volumes


func check_volume_sliders() -> void:
	Preferences.set_volume("SFX", 0.5)
	var half := linear_to_db(0.5)
	check(AudioBus.SFX_FAMILY.all(func(bus_name: StringName) -> bool:
		return is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus_name)), half)),
		"The SFX slider is the volume of SFX, World, Body, Entity and EntityFar together")
	check(is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioBus.MUSIC)))
		and is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioBus.UI))),
		"It leaves Music and UI alone")
	Preferences.set_volume("SFX", 0.0)
	check(AudioBus.SFX_FAMILY.all(func(bus_name: StringName) -> bool: return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus_name))),
		"Turning SFX all the way down silences the entity too")
	Preferences.set_volume("SFX", 0.25)
	Preferences.load_preferences()
	check(AudioBus.SFX_FAMILY.all(func(bus_name: StringName) -> bool:
		var index := AudioServer.get_bus_index(bus_name)
		return is_equal_approx(AudioServer.get_bus_volume_db(index), linear_to_db(0.25)) and not AudioServer.is_bus_mute(index)),
		"The saved SFX volume comes back on every bus of the family")
	Preferences.set_volume("SFX", 1.0)


func check_breath_duck() -> void:
	var settings := SoundSettings.current()
	check(is_equal_approx(settings.breath_duck_db, -5.0) and is_equal_approx(settings.breath_duck_fade, 0.18),
		"The breath duck keeps its level and speed: -5 dB over 0.18 s")
	MusicDirector.set_breath_held(true)
	await seconds(settings.breath_duck_fade + 0.1)
	check(is_equal_approx(MixDirector.gain_db(AudioBus.MUSIC), settings.breath_duck_db)
		and is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioBus.MUSIC))),
		"Holding breath drops the music through the mix, not through the bus volume")
	MusicDirector.set_breath_held(false)
	await seconds(settings.breath_duck_fade + 0.1)
	check(is_zero_approx(MixDirector.gain_db(AudioBus.MUSIC)), "Letting go brings it back")


func check_player() -> void:
	GameState.reset()
	var player: CharacterBody2D = preload("res://player/player.tscn").instantiate()
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ears := player.get_node_or_null("Ears") as AudioListener2D
	check(ears != null and ears.is_current() and ears.global_position.is_equal_approx(player.global_position),
		"Positional sound is heard from where Viv stands")
	player.global_position = Vector2(900, 400)
	check(ears != null and ears.global_position.is_equal_approx(player.global_position), "Her ears move with her, wherever the camera stops")
	var body_voices: Array = player.get_node("FootstepAudio").get_children()
	body_voices.append(player.get_node("HoldBreath")._audio_player)
	body_voices.append_array(player.get_node("BreathFeedback").strain_audio.get_children())
	body_voices.append(player.get_node("flashlight")._audio_player)
	check(body_voices.size() >= 7 and body_voices.all(func(voice: Node) -> bool: return voice.bus == AudioBus.BODY),
		"Her footsteps, breath, strain heartbeat and tone, and the flashlight click play on Body")
	check(MusicDirector._heartbeat.bus == AudioBus.BODY, "The threat heartbeat plays on Body")
	check(player.get_node("Throw")._audio_player.bus == AudioBus.WORLD, "What she throws lands on World")
	var strain: Node = player.get_node("BreathFeedback").strain_audio
	check(strain._filters.size() == 2 and strain._filters[0] == MixDirector.muffle_filter(AudioBus.MUSIC)
		and strain._filters[1] == MixDirector.muffle_filter(AudioBus.AMBIENCE),
		"Breath strain muffles Music and Ambience through the mix's own filters")
	player.queue_free()
	await get_tree().process_frame


## No script but MixDirector changes the mix; the volume sliders belong to Preferences and the
## pause menu, and to them alone.
func check_single_owner() -> void:
	var mix_calls := RegEx.create_from_string("AudioServer\\s*\\.\\s*(add_bus|remove_bus|move_bus|set_bus_(?!volume_db|mute)\\w+|add_bus_effect|remove_bus_effect|swap_bus_effects|set_bus_layout)|AudioEffect\\w+\\s*\\.\\s*new\\s*\\(|\\.\\s*cutoff_hz\\s*=[^=]")
	var volume_calls := RegEx.create_from_string("AudioServer\\s*\\.\\s*set_bus_(volume_db|volume_linear|mute)")
	var offenders: Array[String] = []
	var scanned := 0
	var folders := ["res://"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			var path := folder.path_join(sub)
			if not SKIPPED_FOLDERS.has(path):
				folders.append(path)
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".gd"):
				continue
			var path := folder.path_join(file)
			scanned += 1
			var number := 0
			for line in FileAccess.get_file_as_string(path).split("\n"):
				number += 1
				var code := line.get_slice("#", 0)
				if path != MIX_OWNER and mix_calls.search(code) != null:
					offenders.append("%s:%d changes the mix" % [path, number])
				if path not in VOLUME_OWNERS and volume_calls.search(code) != null:
					offenders.append("%s:%d sets a bus volume" % [path, number])
	check(scanned > 40, "The scripts of the game were scanned (%d files)" % scanned)
	check(offenders.is_empty(), "Only MixDirector changes the mix, only the settings menus set bus volumes: %s" % [offenders])
