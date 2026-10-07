extends Node2D
## Exercise equipped aiming and action interruptions through the playable player.
## Explicit world targets keep mouse-dependent behavior reproducible headlessly.

var checks := 0
var completed_scenarios := 0
var failures: Array[String] = []
var noises: Array[Dictionary] = []
var player: CharacterBody2D
var action: Node
var aim: Node
var appearance: Node2D
var breath: Node
var thrower: Node
var flashlight: PointLight2D


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame


func release_inputs() -> void:
	for input_action in ["move_left", "move_right", "move_up", "move_down", "sprint", "hold_breath", "throw", "pray"]:
		Input.action_release(input_action)


func angle_near(actual: float, expected: float, tolerance_degrees := 3.0) -> bool:
	return absf(angle_difference(actual, expected)) <= deg_to_rad(tolerance_degrees)


func point_aim(direction: Vector2, distance := 2048.0) -> void:
	aim.set_target(player.global_position + direction.normalized() * distance)


func _ready() -> void:
	GameState.reset()
	release_inputs()
	NoiseManager.noise_emitted.connect(func(at: Vector2, radius: float, source: int, _duration: float):
		noises.append({"at": at, "radius": radius, "source": source}))
	player = preload("res://player/player.tscn").instantiate()
	# This runner remains active to unpause; gameplay must still obey tree pause.
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	action = player.get_node("ActionState")
	aim = player.get_node("PlayerAim")
	appearance = player.get_node("Appearance")
	breath = player.get_node("HoldBreath")
	thrower = player.get_node("Throw")
	flashlight = player.get_node("flashlight")
	player.get_node("FootstepNoise").walk_clips.clear()
	player.get_node("FootstepNoise").sprint_clips.clear()
	breath.hold_clips.clear()
	breath.exertion_clips.clear()
	flashlight.click_clips.clear()
	await frames(3)
	await check_equipped_aim()
	await check_action_interruptions()
	release_inputs()
	player.queue_free()
	await frames(3)
	GameState.reset()
	await check_tutorial_equipment()
	GameState.reset()
	await check_night_equipment()
	# Godot may resume a caller after a runtime error aborts an awaited coroutine.
	check(completed_scenarios == 4, "Every integration scenario reached its final assertions")
	print("[Player action tests] %d/%d passed" % [checks - failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func check_equipped_aim() -> void:
	check(not action.has_flashlight and not appearance.actor_equipped,
		"A new player has no visible flashlight before pickup")
	point_aim(Vector2.RIGHT)
	Input.action_press("move_down")
	await frames(45)
	check(appearance.actor_facing == &"s",
		"Without equipment, mouse aim does not replace movement-facing selection")
	Input.action_release("move_down")
	await frames(45)
	var collision_transform: Transform2D = player.get_node("CollisionShape2D").transform
	var local_light_transform: Transform2D = player.get_node("LocalLight").transform
	action.has_flashlight = true
	point_aim(Vector2.RIGHT)
	await frames(90)
	check(appearance.actor_rig_enabled and appearance.actor_equipped,
		"Equipment enables the coherent layered player and visible torch")
	check(angle_near(aim.body_angle, 0.0, aim.turn_threshold_degrees + 1.0)
		and angle_near(aim.aim_angle, 0.0),
		"Stationary cursor aim brings the torso around and points the torch east")
	check(aim.has_valid_target, "A distant world aim target is accepted")
	check(player.get_node("CollisionShape2D").transform == collision_transform
		and player.get_node("LocalLight").transform == local_light_transform,
		"Turning the rig does not rotate its collision or ambient player light")
	check(player.global_position.distance_to(aim.get_hand_global_position()) > 1.0,
		"The hand anchor is attached away from the player's center")
	check(aim.get_hand_global_position().distance_to(aim.get_muzzle_global_position()) > 1.0,
		"The flashlight muzzle extends beyond the held grip")
	check(aim.get_muzzle_global_position().distance_to(aim.get_beam_global_position()) < 0.01
		and flashlight.global_position.distance_to(aim.get_beam_global_position()) < 0.01,
		"In clear space the live beam originates at the visible flashlight muzzle")
	check(angle_near(flashlight.global_rotation, aim.aim_angle, 0.1),
		"The beam and visible torch use the same aim direction")
	flashlight._apply_beam_length()
	var local_tip: Vector2 = (flashlight.beam_tip_pixels - flashlight.texture.get_size() * 0.5) \
		* flashlight.texture_scale + flashlight.offset
	check(local_tip.length() < 0.001,
		"The inset painted cone tip maps to the torch muzzle rather than behind its hand")
	await check_wall_clipping()

	var before_deadzone: float = aim.aim_angle
	var body_before_deadzone: float = aim.body_angle
	for direction in [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN]:
		aim.set_target(player.global_position + direction * Units.to_px(aim.cursor_deadzone_u * 0.25))
		await frames(2)
	check(angle_near(aim.aim_angle, before_deadzone, 0.1)
		and angle_near(aim.body_angle, body_before_deadzone, 0.1),
		"Cursor jitter inside the player deadzone cannot flip the torch or body")

	point_aim(Vector2.LEFT)
	var body_before_turn: float = aim.body_angle
	var beam_before_turn: float = aim.aim_angle
	await frames(1)
	var physics_delta := 1.0 / float(Engine.physics_ticks_per_second)
	check(absf(angle_difference(body_before_turn, aim.body_angle))
		<= deg_to_rad(aim.body_turn_speed_degrees) * physics_delta + 0.002,
		"A cursor reversal cannot turn the torso faster than its physical response limit")
	check(absf(angle_difference(beam_before_turn, aim.aim_angle))
		<= deg_to_rad(aim.aim_turn_speed_degrees) * physics_delta + 0.002,
		"A cursor reversal cannot snap the torch through an unrestricted half turn")
	await frames(90)
	check(angle_near(aim.aim_angle, PI)
		and angle_near(aim.body_angle, PI, aim.turn_threshold_degrees + 1.0),
		"A sustained reversed target eventually turns body and light toward it")

	point_aim(Vector2.DOWN)
	await frames(90)
	aim.set_target(player.global_position + Vector2(-34.2020143, 93.9692621))
	await frames(45)
	var settled_hand: Vector2 = aim.get_hand_global_position()
	var settled_angle: float = aim.aim_angle
	var settled_region: Rect2 = appearance._rig_pose.upper_region
	var hand_drift := 0.0
	var angle_drift := 0.0
	var stable_region := true
	for sample in range(90):
		await frames(1)
		hand_drift = maxf(hand_drift, settled_hand.distance_to(aim.get_hand_global_position()))
		angle_drift = maxf(angle_drift, absf(angle_difference(settled_angle, aim.aim_angle)))
		stable_region = stable_region and appearance._rig_pose.upper_region == settled_region
	check(stable_region and hand_drift < 0.01 and angle_drift < deg_to_rad(0.1),
		"A stationary target near an arm-pose boundary cannot oscillate its hand or beam")

	point_aim(Vector2.RIGHT)
	await frames(90)
	var start_position: Vector2 = player.global_position
	Input.action_press("move_left")
	await frames(60)
	check(player.global_position.x < start_position.x - 50.0
		and absf(player.get_speed_u() - player.walk_speed_u) < 0.02,
		"Aiming behind movement allows backward travel at the unchanged walk speed")
	check(angle_near(aim.aim_angle, 0.0, 5.0),
		"Backward movement keeps the light aimed at the selected target")
	check(not noises.is_empty() and noises[-1].radius == 96.0,
		"Equipped directional movement preserves the existing footstep hearing cost")
	Input.action_release("move_left")
	Input.action_press("move_down")
	await frames(60)
	check(player.velocity.y > 95.0 and angle_near(aim.aim_angle, 0.0, 8.0),
		"Strafing moves perpendicular to the independently aimed torch")
	Input.action_press("sprint")
	await frames(60)
	check(absf(player.get_speed_u() - player.sprint_speed_u) < 0.02
		and action.get_action() == &"sprint",
		"Equipped sprint preserves its speed and shared action identity")
	check(noises[-1].radius == 192.0,
		"Equipped sprint preserves its louder hearing cost")
	release_inputs()
	await frames(60)
	check(action.get_action() == &"idle", "Stopping equipped motion returns to shared idle")
	completed_scenarios += 1


func check_wall_clipping() -> void:
	var socket_offset: Vector2 = aim.get_muzzle_global_position() - player.global_position
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(2.0, 80.0)
	shape.shape = rectangle
	wall.position = player.global_position + socket_offset * 0.85
	wall.rotation = socket_offset.angle()
	wall.add_child(shape)
	add_child(wall)
	await frames(4)
	var clipped_origin: Vector2 = aim.get_beam_global_position()
	check(aim.beam_obstructed and clipped_origin.distance_to(player.global_position)
		< aim.get_muzzle_global_position().distance_to(player.global_position),
		"A nearby wall keeps the protruding torch's light source on the player's side")
	var query := PhysicsRayQueryParameters2D.create(player.global_position, clipped_origin, 1, [player.get_rid()])
	check(player.get_world_2d().direct_space_state.intersect_ray(query).is_empty(),
		"The clipped beam origin cannot remain beyond the wall")
	wall.queue_free()
	await frames(4)
	check(not aim.beam_obstructed and aim.get_beam_global_position().distance_to(aim.get_muzzle_global_position()) < 0.01,
		"Removing the obstruction returns the light source to its moving visual socket")


func check_action_interruptions() -> void:
	point_aim(Vector2.RIGHT)
	await frames(90)
	thrower.rocks = 3
	thrower._start_throw()
	check(action.get_action() == &"throw" and action.can_move() and not action.can_aim(),
		"Throw preparation retains movement while committing the current aim")
	var throw_angle: float = aim.aim_angle
	point_aim(Vector2.UP)
	await frames(4)
	check(angle_near(aim.aim_angle, throw_angle, 0.1),
		"Changing the cursor during throw windup does not redirect its committed pose")
	GameState.is_praying = true
	await frames(2)
	check(action.get_action() == &"prayer" and not action.can_move() and not action.can_aim(),
		"Prayer takes priority over movement and aim")
	check(not thrower.is_throwing and thrower.rocks == 2 and thrower._in_flight.is_empty(),
		"Prayer cancels pending release without creating a projectile or refunding the rock")
	var prayer_angle: float = aim.aim_angle
	Input.action_press("move_right")
	Input.action_press("hold_breath")
	var prayer_position: Vector2 = player.global_position
	var lung_before_prayer: float = breath.lung_percent
	await frames(12)
	check(player.global_position.distance_to(prayer_position) < 0.01
		and angle_near(aim.aim_angle, prayer_angle, 0.1),
		"Prayer ignores movement and cursor changes while stationary")
	check(breath.lung_percent < lung_before_prayer and action.get_action() == &"prayer",
		"Prayer preserves existing breath costs while retaining action priority")
	release_inputs()
	GameState.is_praying = false
	await frames(3)

	breath._forced_gasp(breath.exertion_clips)
	point_aim(Vector2.LEFT)
	var gasp_angle: float = aim.aim_angle
	var gasp_position: Vector2 = player.global_position
	Input.action_press("move_right")
	await frames(12)
	check(action.get_action() == &"forced_gasp" and not action.can_throw(),
		"Forced gasp is the shared recovery action and blocks throwing")
	check(player.global_position.distance_to(gasp_position) < 0.01
		and angle_near(aim.aim_angle, gasp_angle, 0.1),
		"Forced gasp locks movement and aiming for its recovery window")
	release_inputs()
	await frames(125)
	check(not breath.is_locked and action.can_move() and action.can_aim(),
		"Completing the existing gasp recovery releases movement and aim")

	Input.action_press("hold_breath")
	await frames(4)
	check(action.get_action() == &"hold_breath", "Actual held breath is exposed to presentation")
	var pause_angle: float = aim.aim_angle
	var pause_lung: float = breath.lung_percent
	var pause_position: Vector2 = player.global_position
	get_tree().paused = true
	point_aim(Vector2.DOWN)
	await frames(8)
	check(angle_near(aim.aim_angle, pause_angle, 0.1)
		and is_equal_approx(breath.lung_percent, pause_lung)
		and player.global_position == pause_position,
		"Pause freezes aim, breathing resources, and physical motion together")
	get_tree().paused = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var dialogue_angle: float = aim.aim_angle
	var noises_before_dialogue := noises.size()
	await frames(6)
	check(action.get_action() == &"disabled" and not breath.is_holding,
		"Dialogue disables character actions and silently interrupts held breath")
	check(noises.size() == noises_before_dialogue and angle_near(aim.aim_angle, dialogue_angle, 0.1),
		"Dialogue interruption cannot emit an exhale or keep tracking the cursor")
	release_inputs()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	await frames(6)
	check(action.can_move() and action.can_aim(), "Closing dialogue releases the shared action policy")

	thrower.clear_pending()
	thrower._start_throw()
	Input.action_press("hold_breath")
	await frames(2)
	GameState.kill_player()
	var dead_lung: float = breath.lung_percent
	var dead_exertion: float = breath.exertion_percent
	var dead_angle: float = aim.aim_angle
	var noises_before_death := noises.size()
	point_aim(Vector2.RIGHT)
	await frames(40)
	check(action.get_action() == &"dead" and not action.can_move() and not action.can_aim(),
		"Death takes priority over every character action")
	check(not thrower.is_throwing and thrower._in_flight.is_empty() and thrower.rocks == 1,
		"Death interrupts pending throw release and keeps spent inventory spent")
	check(is_equal_approx(breath.lung_percent, dead_lung)
		and is_equal_approx(breath.exertion_percent, dead_exertion)
		and noises.size() == noises_before_death,
		"Death freezes lung and exertion and suppresses further breath noise")
	check(angle_near(aim.aim_angle, dead_angle, 0.1), "Death freezes the visible aiming direction")
	completed_scenarios += 1


func check_tutorial_equipment() -> void:
	var game: Node2D = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await frames(5)
	var state: Node = game.player.get_node("ActionState")
	var visual: Node2D = game.player.get_node("Appearance")
	var player_aim: Node = game.player.get_node("PlayerAim")
	check(not game.has_flashlight and not state.has_flashlight and not visual.actor_equipped,
		"The tutorial starts with consistent inventory and an empty flashlight hand")
	game.player.position = game.world.interactables["battery"]["position"] + Vector2(0, 45)
	game.interact("battery")
	game.player.position = game.world.interactables["flashlight"]["position"] + Vector2(0, 45)
	game.interact("flashlight")
	player_aim.set_target(game.player.global_position + Vector2(400, 0))
	await frames(5)
	check(game.has_flashlight and state.has_flashlight and visual.actor_equipped and game.flashlight.is_on,
		"Real flashlight pickup equips the same prop and uses the previously collected battery")
	game.flashlight.toggle()
	await frames(2)
	check(visual.actor_equipped and not game.flashlight.enabled,
		"Switching off removes emitted light while leaving the owned torch in hand")
	game.flashlight.battery_percent = 0.0
	game.flashlight.toggle()
	await frames(2)
	check(visual.actor_equipped and not game.flashlight.is_on,
		"An empty battery prevents lighting without making the physical torch disappear")
	game.batteries = 1
	game.insert_battery()
	await frames(2)
	check(game.batteries == 0 and game.flashlight.is_on and visual.actor_equipped,
		"Battery replacement restores the existing equipped torch")
	game.save_checkpoint()
	game.flashlight.follow_mouse = false
	player_aim.set_target(game.player.global_position + Vector2(400, 0))
	game.thrower.rocks = 2
	game.thrower._start_throw()
	game.breath._forced_gasp(game.breath.exertion_clips)
	game.request_reset("")
	await frames(12)
	check(not game.resetting and state.has_flashlight and visual.actor_equipped,
		"Checkpoint restoration retains flashlight ownership and visible equipment")
	check(not game.breath.is_locked and not game.thrower.is_throwing
		and game.thrower._in_flight.is_empty() and state.can_aim(),
		"Checkpoint restoration clears recovery and pending actions without a late projectile")
	check(game.breath.lung_percent == 100.0 and game.breath.exertion_percent == 0.0,
		"Checkpoint restoration restores the established breathing resources")
	check(not player_aim.has_valid_target,
		"Checkpoint restoration clears an obsolete injected aim target")
	game.queue_free()
	await frames(3)
	completed_scenarios += 1


func check_night_equipment() -> void:
	var level: Node2D = preload("res://level/level_template.tscn").instantiate()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level)
	await frames(3)
	var night_player: CharacterBody2D = level.get_node("Player")
	var state: Node = night_player.get_node("ActionState")
	var visual: Node2D = night_player.get_node("Appearance")
	var light: PointLight2D = night_player.get_node("flashlight")
	check(state.has_flashlight and visual.actor_equipped,
		"A standalone night template grants its starting flashlight without the tutorial pickup")
	var toggle_event := InputEventAction.new()
	toggle_event.action = "candle_toggle"
	toggle_event.pressed = true
	light._unhandled_input(toggle_event)
	await frames(2)
	check(light.is_on and light.enabled,
		"The existing flashlight toggle works immediately in the equipped night template")
	level.queue_free()
	await frames(3)
	completed_scenarios += 1
