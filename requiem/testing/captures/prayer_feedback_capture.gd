extends Node
## Rendered evidence uses actual E/Space inputs and the real altar clock.
## Pass -- --capture-dir=/absolute/path; the default is local, ignored output.

var studio: Node2D
var capture_dir := ""
var evidence: Array[Dictionary] = []
var failures: Array[String] = []


func frames(count: int) -> void:
	for index in range(count): await get_tree().physics_frame
	await get_tree().process_frame


func _prepare_output() -> void:
	capture_dir = ProjectSettings.globalize_path("res://.local-development/prayer-review")
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size()):
		var argument: String = arguments[index]
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
		elif argument == "--capture-dir" and index + 1 < arguments.size():
			capture_dir = arguments[index + 1]
	if not capture_dir.is_absolute_path():
		capture_dir = ProjectSettings.globalize_path("res://").path_join(capture_dir)
	var error := DirAccess.make_dir_recursive_absolute(capture_dir)
	if error != OK:
		failures.append("Cannot create capture directory: " + capture_dir)


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))
	if error != OK:
		failures.append("Could not save prayer capture: " + label)
	var feedback: Node = studio.player.get_node("PrayerFeedback")
	evidence.append({"label": label, "phase": String(feedback.phase),
		"pose_phase": feedback.pose_phase, "action": String(studio.player.get_node("ActionState").get_action()),
		"is_praying": GameState.is_praying, "equipment_mode": studio.get_equipment_mode(),
		"ritual_elapsed": studio.altar.tiempo_interaccion if is_instance_valid(studio.altar) else 12.0,
		"lung_percent": studio.breath.lung_percent, "forced_gasp": studio.breath.is_locked,
		"completed": studio.ritual_completed})


func require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _ready() -> void:
	_prepare_output()
	studio = preload("res://testing/experiments/prayer_studio.tscn").instantiate()
	add_child(studio)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await frames(20)
	studio.set_equipment_mode(2)
	studio.hud.subtitle.text = "PRAYER · Begin, bow, return"
	await capture("01-ready")
	Input.action_press("pray")
	await frames(6)
	require(GameState.is_praying, "E near the real altar must start prayer.")
	await capture("02-partial-entry")
	Input.action_release("pray")
	await frames(2)
	await capture("03-early-release")
	await frames(24)
	await capture("04-early-release-settled")

	studio.set_equipment_mode(0)
	studio.set_studio_heading(2)
	await frames(8)
	studio.hud.subtitle.text = "Empty hands · a quiet sustained prayer"
	Input.action_press("pray")
	await frames(40)
	await capture("05-empty-hands-loop")
	Input.action_release("pray")
	await frames(8)
	await capture("06-loop-release")
	await frames(24)

	studio.set_equipment_mode(1)
	studio.set_studio_heading(0)
	studio.reset_studio_prayer(25.0)
	await frames(5)
	studio.hud.subtitle.text = "Flashlight off · prayer continues through a forced gasp"
	Input.action_press("pray")
	Input.action_press("hold_breath")
	await frames(40)
	await capture("07-prayer-with-held-breath")
	for index in range(120):
		if studio.breath.is_locked: break
		await frames(1)
	require(studio.breath.is_locked and GameState.is_praying,
		"Low air must force a gasp while the accepted ritual continues.")
	await capture("08-forced-gasp")
	await frames(125)
	Input.action_release("hold_breath")
	await frames(22)
	require(GameState.is_praying and not studio.breath.is_locked,
		"The real ritual must remain active after gasp recovery.")
	await capture("09-prayer-resumed")
	Input.action_release("pray")
	await frames(24)

	studio.set_equipment_mode(2)
	studio.set_studio_heading(6)
	await frames(8)
	studio.hud.subtitle.text = "A complete ritual · the real twelve-second hold"
	Input.action_press("pray")
	await frames(150)
	await capture("10-normal-ritual-pulse")
	for index in range(720):
		if not is_instance_valid(studio.altar): break
		await frames(1)
	Input.action_release("pray")
	await frames(24)
	require(studio.ritual_completed and not GameState.is_praying,
		"Twelve seconds must complete the real altar and release the player.")
	await capture("11-complete-and-settled")
	var output := FileAccess.open(capture_dir.path_join("prayer_capture_evidence.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"frames": evidence, "failures": failures}, "\t") + "\n")
	for action_name in ["pray", "hold_breath"]:
		Input.action_release(action_name)
	studio.queue_free()
	await frames(4)
	get_tree().quit(0 if failures.is_empty() else 1)
