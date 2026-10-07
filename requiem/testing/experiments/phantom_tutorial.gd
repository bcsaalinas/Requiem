extends "res://tutorial/tutorial.gd"
## Separate playable comparison scene; the shipping tutorial remains the baseline.

@onready var camera_rig: Node2D = $CameraRig
@onready var camera_status: Label = $CameraTestOverlay/Status
var using_native_camera := false
var _camera_started := false


func _ready() -> void:
	# Comparison must also work while dialogue disables the rest of the player.
	player.get_node("Camera2D").process_mode = Node.PROCESS_MODE_PAUSABLE
	camera_rig.setup(player, world)
	super._ready()
	# The addon host initializes after one frame. Keep the baseline camera for that frame.
	await get_tree().process_frame
	_camera_started = true
	set_native_camera(false)


func _frame_camera() -> void:
	# The two cameras keep independent state for an immediate A/B comparison.
	super._frame_camera()
	if is_instance_valid(camera_rig):
		camera_rig.apply_region(World.REGIONS[zone])


func enter_zone(next_zone: String, spawn := Vector2.INF, save := true) -> void:
	super.enter_zone(next_zone, spawn, save)
	if is_instance_valid(camera_rig): camera_rig.enter_region(World.REGIONS[zone])


func _tick_hallway(delta: float) -> void:
	super._tick_hallway(delta)
	var door_x := 1930.0 if player.position.x < 2110.0 else 2310.0
	# The refuge and its recovery cue retain exploration framing.
	var near_door := absf(player.position.x - door_x) < 165.0 and player.position.y < 418.0
	camera_rig.set_hallway_door(door_x if near_door else 0.0)


func _on_rock_landed(at: Vector2) -> void:
	var already_broken := window_broken
	super._on_rock_landed(at)
	if not already_broken and window_broken: camera_rig.start_reveal()


func show_dialogue(lines: Array[String], done := Callable()) -> void:
	super.show_dialogue(lines, done)
	if zone == "house" and friend_met and not attack_finished: camera_rig.start_altar()


func _begin_attack() -> void:
	super._begin_attack()
	camera_rig.start_altar()


func _tick_sequence(delta: float) -> void:
	var previous_sequence := sequence
	var previous_step := sequence_step
	super._tick_sequence(delta)
	if previous_sequence == "reveal" and sequence == "": camera_rig.finish_reveal()
	if previous_sequence == "attack":
		if previous_step == 0 and sequence_step >= 1: camera_rig.impact.emit()
		if sequence == "": camera_rig.finish_altar()


func request_reset(message: String, bedroom := false) -> void:
	if not resetting: camera_rig.stop_effects()
	super.request_reset(message, bedroom)


func interact(id: String) -> void:
	var previous_position := player.position
	super.interact(id)
	# The front door also teleports within the house without entering another region.
	if id == "front_door" and player.position.distance_to(previous_position) > 100.0:
		camera_rig.snap_to_player()


func set_native_camera(enabled: bool) -> void:
	using_native_camera = enabled
	var native_camera := player.get_node("Camera2D") as Camera2D
	_frame_camera()
	if enabled:
		camera_rig.camera.enabled = false
		native_camera.enabled = true
		native_camera.make_current()
		native_camera.reset_smoothing()
		_refresh_native_camera.call_deferred()
	else:
		native_camera.enabled = false
		camera_rig.camera.enabled = true
		camera_rig.camera.make_current()
		camera_rig.snap_to_player()
		# Restore the current story composition when comparing during a scene.
		if sequence == "attack" or (zone == "house" and friend_met and not dialogue.is_empty()):
			camera_rig.start_altar()
		elif sequence == "reveal": camera_rig.start_reveal()


func _refresh_native_camera() -> void:
	# A previously disabled Camera2D needs a tick to refresh its follow target.
	await get_tree().process_frame
	if using_native_camera:
		var native_camera := player.get_node("Camera2D") as Camera2D
		native_camera.reset_smoothing()
		native_camera.force_update_scroll()


func jump_to_zone(index: int) -> void:
	var zones := ["bedroom", "hallway", "forest", "house", "loop"]
	if _paused or resetting or sequence != "": return
	dialogue.clear()
	dialogue_done = Callable()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	hud.subtitle.text = ""
	hud.prompt.text = ""
	has_flashlight = true
	flashlight.battery_percent = 100.0
	flashlight.is_on = true
	flashlight.set_process(true)
	flashlight.set_process_unhandled_input(true)
	flashlight._refresh_light()
	batteries = maxi(batteries, 2)
	thrower.rocks = maxi(thrower.rocks, 3)
	enter_zone(zones[index])


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and _camera_started and not _paused:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_C:
			set_native_camera(not using_native_camera)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_V:
			var motion := player.get_node("PlayerMotion")
			motion.set_enabled(not motion.enabled)
			get_viewport().set_input_as_handled()
			return
		if key >= KEY_1 and key <= KEY_5:
			jump_to_zone(key - KEY_1)
			get_viewport().set_input_as_handled()
			return
	super._input(event)


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(camera_rig): return
	var mode: String = "Original" if using_native_camera else "Phantom · " + camera_rig.active_shot
	var motion := player.get_node("PlayerMotion")
	var body_mode: String = motion.mode if motion.enabled else "Still"
	camera_status.text = "ALPHA FEEL TEST · %s\nC: camera · V: animation (%s)\n1–5: bedroom / hall / forest / house / loop" % [mode, body_mode]
