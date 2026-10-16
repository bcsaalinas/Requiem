extends Node
## Real movement input produces every gait and dust sample. MovieMaker records
## the same sequence; PNGs and JSON retain the live state behind each caption.

var studio: Node2D
var capture_dir := ""
var evidence: Array[Dictionary] = []
var failures: Array[String] = []


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame


func require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _prepare_output() -> void:
	capture_dir = ProjectSettings.globalize_path("res://.local-development/sprint-review")
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
		failures.append("Could not save sprint capture: " + label)
	var motion: Node = studio.player.get_node("PlayerMotion")
	var dust: Node = studio.player.get_node("SprintDust")
	var appearance: Node = studio.player.get_node("Appearance")
	var lower: Dictionary = appearance.get_actor_lower_pose()
	var at: Vector2 = studio.player.global_position
	var sample := {"label": label, "mode": motion.mode,
		"animation": String(appearance.actor_animation), "frame": appearance.actor_frame,
		"speed_u": studio.player.get_speed_u(), "is_sprinting": studio.player.is_sprinting,
		"position": [at.x, at.y], "equipment_mode": studio.get_equipment_mode(),
		"area": studio.zone, "dust_count": dust.particles.size(), "emitted_puffs": dust.emitted_puffs,
		"dust_enabled": dust.enabled, "contacts": lower.get("contacts", {}),
		"leg_direction": lower.get("direction", ""), "heading": lower.get("heading", 0.0),
		"body_heading": studio.player.get_node("PlayerAim").pose_body_angle,
		"exertion_percent": studio.breath.exertion_percent}
	var boots: Dictionary = lower.get("boots", {})
	if boots.has("left") and boots.has("right"):
		sample["boot_separation"] = Vector2(boots.left).distance_to(boots.right)
	evidence.append(sample)


func capture_plant(label: String) -> void:
	var dust: Node = studio.player.get_node("SprintDust")
	var before: int = dust.emitted_puffs
	for index in range(45):
		await frames(1)
		if dust.emitted_puffs > before:
			break
	await frames(14)
	require(dust.emitted_puffs > before and not dust.particles.is_empty()
		and studio.player.get_node("PlayerMotion").mode == "Sprint",
		label + " must show a real sprint plant with visible live dust.")
	await capture(label)


func stop_moving() -> void:
	for action_name in ["sprint", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action_name)


func _ready() -> void:
	_prepare_output()
	studio = preload("res://testing/experiments/sprint_studio.tscn").instantiate()
	add_child(studio)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await frames(20)
	studio.hud.subtitle.text = "SPRINT · Walk into a quicker stride, then settle"
	studio.player.get_node("PlayerAim").set_target(Vector2(900, 440))
	Input.action_press("move_right")
	await frames(40)
	require(studio.player.get_node("PlayerMotion").mode == "Walk",
		"The baseline must be actual walking before sprint input.")
	await capture("01-walk-baseline")
	Input.action_press("sprint")
	await frames(35)
	await capture_plant("02-equipped-sprint-plant")
	await frames(22)
	stop_moving()
	await frames(40)
	require(studio.player.get_node("SprintDust").particles.is_empty(),
		"Stopped sprint dust must finish fading.")
	await capture("03-settled-after-sprint")

	studio.reset_studio_sprint()
	studio.set_equipment_mode(0)
	studio.hud.subtitle.text = "Empty hands · diagonal strides and a sharp reversal"
	Input.action_press("sprint")
	Input.action_press("move_up")
	Input.action_press("move_right")
	await frames(40)
	await capture_plant("04-unarmed-diagonal")
	Input.action_release("move_up")
	Input.action_release("move_right")
	Input.action_press("move_left")
	Input.action_press("move_down")
	await frames(35)
	await capture_plant("05-unarmed-reversed")
	stop_moving()
	await frames(25)

	studio.set_studio_area(2)
	studio.set_equipment_mode(1)
	studio.player.get_node("PlayerAim").set_target(Vector2(2820, 100))
	studio.hud.subtitle.text = "Flashlight off · run across and away from the aiming direction"
	Input.action_press("sprint")
	Input.action_press("move_right")
	Input.action_press("move_down")
	await frames(30)
	await capture_plant("06-light-off-opposite-aim")
	Input.action_release("move_down")
	await frames(25)
	await capture_plant("07-sideways-travel")
	studio.set_equipment_mode(2)
	studio.player.get_node("PlayerAim").set_target(Vector2(4420, 280))
	studio.hud.subtitle.text = "Flashlight on · the same stride and restrained ground dust"
	Input.action_press("move_up")
	await frames(25)
	await capture_plant("08-light-on-diagonal")
	stop_moving()
	await frames(40)
	await capture("09-forest-stop")

	studio.set_studio_area(0)
	studio.set_equipment_mode(2)
	studio.player.get_node("PlayerAim").set_target(Vector2(1200, 440))
	studio.hud.subtitle.text = "A real wall stops the stride and dust, even while Shift stays held"
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(220)
	var dust: Node = studio.player.get_node("SprintDust")
	var before: int = dust.emitted_puffs
	await frames(35)
	require(studio.player.get_speed_u() < 0.01 and dust.emitted_puffs == before
		and dust.particles.is_empty() and studio.player.get_node("PlayerMotion").mode == "Idle",
		"Holding sprint into the bedroom wall must produce no dust or moving gait.")
	await capture("10-blocked-wall-no-dust")
	stop_moving()
	studio.reset_studio_sprint()
	await frames(20)
	studio.hud.subtitle.text = "Ready for the next run"
	await capture("11-reset-clean")
	var output := FileAccess.open(capture_dir.path_join("sprint_capture_evidence.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"frames": evidence, "failures": failures}, "\t") + "\n")
	else:
		failures.append("Cannot save sprint evidence JSON.")
	studio.queue_free()
	await frames(4)
	get_tree().quit(0 if failures.is_empty() else 1)
