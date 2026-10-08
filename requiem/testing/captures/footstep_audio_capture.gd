extends Node
## MovieMaker includes actual engine-mixed audio. The opening comparison alone
## reenacts the previous long-clip restart; every later step is production code.

var studio: Node
var audio: Node
var legacy: AudioStreamPlayer
var legacy_mode := false
var stage := ""
var events: Array[Dictionary] = []
var failures: Array[String] = []
var output := "res://.local-development/footstep-review"


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame


func stop() -> void:
	for action in ["move_right", "move_left", "move_up", "move_down", "sprint", "hold_breath"]:
		Input.action_release(action)
	legacy.stop()


func caption(value: String) -> void:
	stage = value
	studio.hud.subtitle.text = value


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))


func _ready() -> void:
	output = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(output)
	studio = preload("res://testing/experiments/sprint_studio.tscn").instantiate()
	add_child(studio)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	# Isolate footstep sound for this comparison; the interactive station retains
	# its normal ambience and breath audio.
	studio.ambience.stop()
	studio.ambience.process_mode = Node.PROCESS_MODE_DISABLED
	studio.breath.hold_clips.clear()
	studio.breath.exertion_clips.clear()
	audio = studio.player.get_node("FootstepAudio")
	audio._random.seed = 1806
	audio.step_played.connect(func(side: String, at: Vector2, mode: String, clip: AudioStream, pitch: float, gain: float):
		events.append({"frame": Engine.get_physics_frames(), "stage": stage, "side": side,
			"position": [at.x, at.y], "mode": mode, "clip": clip.resource_path, "pitch": pitch, "gain_db": gain}))
	legacy = AudioStreamPlayer.new()
	legacy.stream = preload("res://assets/audio/freesound_community-concrete-footsteps-1-6265.mp3")
	legacy.volume_db = -6.0
	add_child(legacy)
	NoiseManager.noise_emitted.connect(func(_at: Vector2, _radius: float, source: int, _duration: float):
		if legacy_mode and source == NoiseManager.SourceType.FOOTSTEP: legacy.play())
	await frames(20)
	studio.player.get_node("PlayerAim").set_target(Vector2(1000, 440))
	studio.set_step_audio_enabled(false)
	legacy_mode = true
	caption("BEFORE · The long recording restarts on the hearing timer")
	Input.action_press("move_right")
	await frames(125)
	await shot("01-before")
	legacy_mode = false
	stop()
	await frames(25)
	studio.reset_studio_sprint()
	studio.ambience.stop()
	studio.set_step_audio_enabled(true)
	studio.player.get_node("PlayerAim").set_target(Vector2(1200, 440))
	caption("AFTER · Individual impacts follow each planted foot")
	Input.action_press("move_right")
	await frames(125)
	await shot("02-walk")
	caption("SPRINT · Quicker footfalls, firmer impacts, the same movement speed")
	Input.action_press("sprint")
	await frames(85)
	await shot("03-sprint")
	caption("TURN · Footsteps stay attached to actual ground contacts")
	Input.action_release("move_right")
	Input.action_press("move_left")
	Input.action_press("move_up")
	await frames(35)
	Input.action_release("move_up")
	await frames(30)
	await shot("04-turn")
	caption("HELD BREATH · Slower, softer steps while holding Space")
	Input.action_press("hold_breath")
	await frames(145)
	await shot("05-held")
	stop()
	await frames(40)
	caption("STOP · The last short impact finishes; no extra steps")
	var before: int = audio.played_steps
	await frames(45)
	if before != audio.played_steps: failures.append("Unexpected stationary steps")
	await shot("06-stop")
	studio.reset_studio_sprint()
	studio.ambience.stop()
	studio.player.get_node("PlayerAim").set_target(Vector2(1200, 440))
	caption("WALL · Movement input alone does not produce footstep sounds")
	Input.action_press("move_right")
	Input.action_press("sprint")
	await frames(220)
	before = audio.played_steps
	await frames(40)
	if before != audio.played_steps: failures.append("Unexpected wall steps")
	await shot("07-wall")
	stop()
	for mode in ["Walk", "Sprint", "Held breath"]:
		if events.filter(func(e): return e.mode == mode).size() < 3:
			failures.append("Missing recorded footfalls: " + mode)
	var file := FileAccess.open(output.path_join("footstep_capture_evidence.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"steps": events, "failures": failures}, "\t"))
	studio.queue_free()
	legacy.queue_free()
	await frames(5)
	for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
