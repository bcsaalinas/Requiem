extends Node2D
## Throw presentation follows accepted mechanics, including the actual release.
## Live input covers integration; explicit timer steps check gameplay parity.

const RigLayers := preload("res://player/character_rig_layers.gd")
const GRIP_LENS := Vector2(16, 34)
const DIRECTIONS := [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

var checks := 0
var completed_scenarios := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var noises: Array[Dictionary] = []
var player: CharacterBody2D
var thrower: Node
var feedback: Node
var breath: Node
var breath_feedback: Node
var appearance: Node2D
var aim: Node
var action: Node
var flashlight: PointLight2D
var motion: Node
var _tutorial_inventory := true
var _pose_samples := 0
var _boot_drift := 0.0
var _lens_error := 0.0
var _wrist_bend := 0.0
var _watch_rearward_legs := false
var _rearward_leg_reach := 0.0
var _rearward_hip_distance := 0.0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame
		if _watch_rearward_legs:
			var lower: Dictionary = appearance.get_actor_lower_pose()
			for side in ["left", "right"]:
				var leg: Dictionary = lower.pose.metadata[side]
				var leg_transform: Transform2D = appearance.get_actor_leg_transform(side)
				var hip: Vector2 = appearance.to_global(leg_transform * leg.hip)
				var ankle: Vector2 = appearance.to_global(leg_transform * leg.ankle)
				_rearward_leg_reach = maxf(_rearward_leg_reach, hip.distance_to(ankle))
				_rearward_hip_distance = maxf(_rearward_hip_distance, hip.distance_to(appearance.global_position))


func release_inputs() -> void:
	for input_action in ["move_left", "move_right", "move_up", "move_down", "sprint", "hold_breath", "throw", "pray"]:
		Input.action_release(input_action)


func observe(event: StringName) -> void:
	events.append({"event": event, "phase": feedback.phase, "pose_phase": feedback.pose_phase,
		"hand": appearance.to_global(appearance.get_actor_throw_hand_position()),
		"region": appearance._rig_pose.upper_region, "flight_count": thrower._in_flight.size()})


func event_count(event: StringName) -> int:
	var count := 0
	for item in events:
		if item.event == event:
			count += 1
	return count


func create_player(tutorial_inventory: bool) -> void:
	_tutorial_inventory = tutorial_inventory
	player = preload("res://player/player.tscn").instantiate()
	if not tutorial_inventory:
		var tutorial_throw := player.get_node("Throw")
		player.remove_child(tutorial_throw)
		tutorial_throw.free()
		var shared_throw := Node.new()
		shared_throw.name = "Throw"
		shared_throw.set_script(preload("res://player/throw.gd"))
		player.add_child(shared_throw)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.get_node("Camera2D").enabled = false
	thrower = player.get_node("Throw")
	feedback = player.get_node("ThrowFeedback")
	breath = player.get_node("HoldBreath")
	breath_feedback = player.get_node("BreathFeedback")
	appearance = player.get_node("Appearance")
	aim = player.get_node("PlayerAim")
	action = player.get_node("ActionState")
	flashlight = player.get_node("flashlight")
	motion = player.get_node("PlayerMotion")
	for clips in [breath.hold_clips, breath.exhale_clips, breath.gasp_clips, breath.forced_gasp_clips,
		breath.exertion_clips, flashlight.click_clips, thrower.piedra_clips, thrower.despertador_clips,
		player.get_node("FootstepNoise").walk_clips, player.get_node("FootstepNoise").sprint_clips]:
		clips.clear()
	thrower.throw_started.connect(func(): observe(&"start"))
	thrower.object_released.connect(func(): observe(&"release"))
	thrower.throw_cancelled.connect(func(): observe(&"cancel"))


func reset_scenario() -> void:
	release_inputs()
	get_tree().paused = false
	GameState.reset()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.velocity = Vector2.ZERO
	player.is_sprinting = false
	thrower.set_physics_process(true)
	feedback.set_physics_process(true)
	thrower.clear_pending()
	thrower.selected = 0
	thrower.reset_charges()
	if _tutorial_inventory:
		thrower.available = true
		thrower.rocks = 3
	feedback.enabled = true
	feedback.reset_feedback()
	breath.cancel_holding()
	breath.is_locked = false
	breath._lock_timer = 0.0
	breath.reset_input_latch()
	breath.lung_percent = 100.0
	breath.exertion_percent = 0.0
	breath_feedback.reset_feedback()
	action.has_flashlight = true
	flashlight.is_on = true
	flashlight.battery_percent = 100.0
	appearance.actor_facing = &"s"
	motion.reset_pose()
	aim.reset_pose()
	aim.set_target(player.global_position + Vector2.DOWN * 2048.0)
	await frames(3)
	events.clear()
	noises.clear()


func _ready() -> void:
	GameState.reset()
	release_inputs()
	NoiseManager.noise_emitted.connect(func(at: Vector2, radius: float, source: int, _duration: float):
		noises.append({"at": at, "radius": radius, "source": source}))
	create_player(true)
	await check_start_release_and_cooldown()
	await check_interruptions()
	await check_pause_and_reset()
	await check_breath_and_locomotion()
	await check_unarmed_rearward_throw()
	await check_transformed_parent_release()
	await check_throw_shapes()
	await check_wall_release()
	thrower.clear_pending()
	player.queue_free()
	await frames(3)
	create_player(false)
	await check_shared_inventory_and_parity()
	check(completed_scenarios == 9, "Every throw integration scenario reaches its final assertions")
	check(_boot_drift < 0.001, "All throw upper poses leave the existing planted boots fixed (%.5f px)" % _boot_drift)
	check(_lens_error <= 0.51, "Every equipped throw pose keeps the beam at its painted lens (%.5f px)" % _lens_error)
	check(_wrist_bend <= 15.01, "Throw overlays preserve the existing wrist limit (%.5f degrees)" % _wrist_bend)
	release_inputs()
	thrower.clear_pending()
	player.queue_free()
	await frames(3)
	GameState.reset()
	print("[Throw feedback tests] %d/%d passed; %d pose samples" % [checks - failures.size(), checks, _pose_samples])
	get_tree().quit(0 if failures.is_empty() else 1)


func check_start_release_and_cooldown() -> void:
	await reset_scenario()
	check(is_equal_approx(thrower.windup_time, 0.5) and is_equal_approx(thrower.cooldown_time, 1.0),
		"The established half-second windup and one-second cooldown remain unchanged")
	Input.action_press("throw")
	await frames(2)
	Input.action_release("throw")
	check(event_count(&"start") == 1 and thrower.rocks == 2 and feedback.phase == &"windup",
		"Accepted Q input spends exactly one collected rock and begins the authored anticipation")
	check(appearance._rig_pose.upper_texture == RigLayers.THROW_ATLAS
		and is_equal_approx(feedback.pose_phase, thrower.get_windup_phase()),
		"The playable character's throw pose reads normalized progress from the actual windup timer")
	var committed_landing: Vector2 = thrower._pending_landing
	aim.set_target(player.global_position + Vector2.UP * 2048.0)
	thrower._start_throw()
	await frames(3)
	check(event_count(&"start") == 1 and thrower.rocks == 2 and thrower._pending_landing == committed_landing,
		"A denied repeated start cannot replay anticipation, spend another rock or redirect the committed landing")
	thrower.set_physics_process(false)
	feedback.set_physics_process(false)
	thrower._windup_timer = 0.001
	thrower._tick_timers(0.001)
	check(event_count(&"release") == 1 and thrower._in_flight.size() == 1 and not thrower.is_throwing,
		"The real windup completion creates exactly one projectile and accepted release event")
	var released: Dictionary = events[-1]
	var flight: Dictionary = thrower._in_flight[0]
	check(released.event == &"release" and released.phase == &"follow_through"
		and is_zero_approx(released.pose_phase) and released.flight_count == 1,
		"Release observers see the exact release pose synchronously with the newly spawned projectile")
	check(flight.from.distance_to(released.hand) < 0.001
		and flight.from.distance_to(player.global_position) > 1.0 and flight.to == committed_landing,
		"The projectile leaves the animated throwing hand and keeps its originally committed landing")
	thrower._release_object()
	check(event_count(&"release") == 1 and thrower._in_flight.size() == 1,
		"An already consumed windup cannot release a duplicate projectile")
	thrower._tick_timers(0.16)
	feedback._physics_process(0.16)
	check(feedback.phase == &"follow_through" and feedback.pose_phase > 0.0 and not thrower.can_throw(),
		"The arm visibly follows through during the existing cooldown")
	thrower._tick_timers(0.17)
	feedback._physics_process(0.17)
	check(feedback.phase == &"idle" and not thrower.can_throw() and is_equal_approx(thrower._cooldown_timer, 0.67),
		"Follow-through settles within 0.32 seconds without shortening the remaining cooldown")
	thrower._tick_flight(0.34)
	check(noises.is_empty() and thrower._in_flight.size() == 1, "Anticipation, release and flight add no premature hearing event")
	thrower._tick_flight(0.02)
	check(noises.size() == 1 and noises[0].at == committed_landing
		and is_equal_approx(noises[0].radius, Units.to_px(8.0)) and noises[0].source == NoiseManager.SourceType.THROW,
		"The rock retains its one existing eight-unit impact noise at the committed landing")
	thrower._start_throw()
	check(event_count(&"start") == 1 and thrower.rocks == 2, "Cooldown rejection cannot restart the pose or spend inventory")
	thrower._tick_timers(0.67)
	check(thrower.can_throw(), "The original cooldown releases throwing at exactly one second")
	thrower.rocks = 0
	thrower._start_throw()
	check(event_count(&"start") == 1 and feedback.phase == &"idle", "Empty tutorial inventory cannot play a false throw animation")
	completed_scenarios += 1


func check_interruptions() -> void:
	for blocker in [&"prayer", &"gasp", &"death", &"dialogue"]:
		await reset_scenario()
		thrower._start_throw()
		await frames(5)
		match blocker:
			&"prayer": GameState.is_praying = true
			&"gasp": breath._forced_gasp(breath.exertion_clips)
			&"death": GameState.kill_player()
			&"dialogue": player.process_mode = Node.PROCESS_MODE_DISABLED
		await frames(40)
		check(not thrower.is_throwing and feedback.phase == &"idle" and appearance._throw_track == &"idle",
			"%s removes both pending throw and its presentation" % blocker)
		check(event_count(&"cancel") == 1 and event_count(&"release") == 0
			and thrower._in_flight.is_empty() and thrower.rocks == 2,
			"%s cancels once, never releases late and preserves the spent rock" % blocker)
		thrower._start_throw()
		check(event_count(&"start") == 1 and thrower.rocks == 2,
			"%s rejects new throws without false animation or another inventory cost" % blocker)
	for blocker in [&"prayer", &"gasp", &"death", &"dialogue"]:
		await reset_scenario()
		thrower._start_throw()
		thrower._windup_timer = 0.001
		await frames(2)
		check(feedback.phase == &"follow_through", "The %s interruption fixture reaches released follow-through" % blocker)
		match blocker:
			&"prayer": GameState.is_praying = true
			&"gasp": breath._forced_gasp(breath.exertion_clips)
			&"death": GameState.kill_player()
			&"dialogue": player.process_mode = Node.PROCESS_MODE_DISABLED
		await frames(2)
		check(feedback.phase == &"idle" and appearance._throw_track == &"idle"
			and event_count(&"release") == 1 and event_count(&"cancel") == 0,
			"%s clears released follow-through without a false pending cancellation or another projectile" % blocker)
	completed_scenarios += 1


func check_pause_and_reset() -> void:
	await reset_scenario()
	thrower._start_throw()
	await frames(8)
	var before := [thrower._windup_timer, feedback.phase, feedback.pose_phase, events.size()]
	get_tree().paused = true
	await frames(8)
	check(before == [thrower._windup_timer, feedback.phase, feedback.pose_phase, events.size()],
		"Pause freezes anticipation and its actual windup without releasing the projectile")
	get_tree().paused = false
	thrower._windup_timer = 0.001
	await frames(2)
	check(feedback.phase == &"follow_through" and event_count(&"release") == 1,
		"Unpausing permits the existing windup to release exactly once")
	before = [thrower._cooldown_timer, feedback.phase, feedback.pose_phase, thrower._in_flight[0].t]
	get_tree().paused = true
	await frames(8)
	check(before == [thrower._cooldown_timer, feedback.phase, feedback.pose_phase, thrower._in_flight[0].t],
		"Pause freezes follow-through, flight and cooldown together")
	get_tree().paused = false
	thrower.clear_pending()
	check(feedback.phase == &"idle" and appearance._throw_track == &"idle"
		and thrower._in_flight.is_empty() and is_zero_approx(thrower._cooldown_timer),
		"Checkpoint-style clear resets a released follow-through and removes its pending flight")
	await frames(40)
	check(event_count(&"release") == 1 and event_count(&"cancel") == 0 and noises.is_empty(),
		"Resetting an already released throw adds no false cancellation, late impact or repeated release")
	thrower._start_throw()
	await frames(4)
	thrower.clear_pending()
	await frames(40)
	check(feedback.phase == &"idle" and event_count(&"cancel") == 1 and event_count(&"release") == 1,
		"Resetting during anticipation also clears its pose and prevents a late release")
	await reset_scenario()
	thrower._start_throw()
	await frames(4)
	thrower._windup_timer = 0.001
	player.global_position += Vector2.RIGHT * Units.to_px(4.0)
	await frames(2)
	check(event_count(&"cancel") == 1 and event_count(&"release") == 0 and not thrower.is_throwing
		and thrower._in_flight.is_empty() and feedback.phase == &"idle" and thrower.rocks == 2,
		"Teleporting just before release cancels before the timer fires, clears anticipation and preserves the spent rock")
	await frames(40)
	check(event_count(&"cancel") == 1 and event_count(&"release") == 0 and noises.is_empty()
		and thrower._in_flight.is_empty() and feedback.phase == &"idle" and appearance._throw_track == &"idle",
		"A teleported windup stays cancelled without a late projectile, impact or replayed pose")
	await reset_scenario()
	thrower._start_throw()
	thrower._windup_timer = 0.001
	await frames(2)
	var original_landing: Vector2 = thrower._in_flight[0].to
	player.global_position += Vector2.RIGHT * Units.to_px(4.0)
	await frames(2)
	check(feedback.phase == &"idle" and appearance._throw_track == &"idle" and event_count(&"cancel") == 0
		and event_count(&"release") == 1 and thrower._in_flight.size() == 1 and thrower._in_flight[0].to == original_landing,
		"Teleporting after release clears follow-through without falsely cancelling or redirecting the existing world projectile")
	await frames(40)
	check(event_count(&"release") == 1 and event_count(&"cancel") == 0 and thrower._in_flight.is_empty()
		and noises.size() == 1 and noises[0].at == original_landing and feedback.phase == &"idle" and thrower.rocks == 2,
		"The already released projectile lands once at its old target while the teleported player's throw pose stays reset")
	completed_scenarios += 1


func check_breath_and_locomotion() -> void:
	await reset_scenario()
	Input.action_press("hold_breath")
	await frames(18)
	var lung_before: float = breath.lung_percent
	thrower._start_throw()
	await frames(4)
	check(breath.is_holding and breath_feedback.phase == &"hold" and feedback.phase == &"windup"
		and appearance._rig_pose.upper_texture == RigLayers.THROW_ATLAS and breath.lung_percent < lung_before,
		"Throw takes the upper-body pose while held breath continues its actual resource costs underneath")
	await frames(52)
	check(feedback.phase == &"idle" and breath.is_holding and breath_feedback.phase == &"hold"
		and appearance._rig_pose.upper_texture == RigLayers.BREATH_ATLAS,
		"The continuing breath pose returns naturally after the throw settles")
	await reset_scenario()
	Input.action_press("move_right")
	Input.action_press("sprint")
	await frames(35)
	var start: Vector2 = player.global_position
	thrower._start_throw()
	await frames(12)
	check(feedback.phase == &"windup" and player.global_position.x > start.x + 20.0
		and absf(player.get_speed_u() - player.sprint_speed_u) < 0.05
		and String(appearance.actor_animation).begins_with("sprint_"),
		"Throw anticipation retains real sprint travel and the established lower-body locomotion")
	completed_scenarios += 1


func check_unarmed_rearward_throw() -> void:
	await reset_scenario()
	action.has_flashlight = false
	# The gait intentionally retains its previous facing across reset. Establish
	# the rearward fixture through actual movement, as an unequipped player does.
	Input.action_press("move_down")
	await frames(12)
	Input.action_release("move_down")
	await frames(30)
	aim.set_target(player.global_position + Vector2.UP * 2048.0)
	await frames(3)
	check(absf(angle_difference(aim.body_angle, PI / 2.0)) < 0.01,
		"The unarmed fixture starts facing south while its new throw target is directly behind it")
	_watch_rearward_legs = true
	thrower._start_throw()
	var landing: Vector2 = thrower._pending_landing
	await frames(4)
	aim.set_target(player.global_position + Vector2.RIGHT * 2048.0)
	await frames(24)
	check(thrower.is_throwing and absf(angle_difference(aim.body_angle, -PI / 2.0)) < deg_to_rad(3.0)
		and thrower._pending_landing == landing and not appearance.actor_equipped,
		"An unarmed rearward throw turns to its committed target before release despite a changed cursor")
	await frames(28)
	check(feedback.phase == &"idle" and event_count(&"release") == 1
		and absf(angle_difference(aim.body_angle, -PI / 2.0)) < deg_to_rad(3.0),
		"Finishing an unarmed throw retains its new resting heading without snapping to the old facing")
	var before: float = aim.body_angle
	Input.action_press("move_right")
	await frames(1)
	check(absf(angle_difference(before, aim.body_angle))
		<= deg_to_rad(aim.body_turn_speed_degrees) / float(Engine.physics_ticks_per_second) + 0.002,
		"Resuming movement after an unarmed throw gathers toward travel at the existing body turn rate")
	await frames(55)
	check(absf(angle_difference(aim.body_angle, 0.0)) < deg_to_rad(3.0) and player.velocity.x > 95.0,
		"An unarmed character returns to ordinary movement-facing after the throw")
	_watch_rearward_legs = false
	check(_rearward_leg_reach <= 30.01 and _rearward_hip_distance <= 21.0,
		"The real rearward pivot and return to travel retain established leg reach and hip attachment (%.3f / %.3f px)"
		% [_rearward_leg_reach, _rearward_hip_distance])
	completed_scenarios += 1


func check_transformed_parent_release() -> void:
	await reset_scenario()
	var previous_transform: Transform2D = transform
	transform = Transform2D(deg_to_rad(17.0), Vector2(70.0, -45.0))
	thrower._start_throw()
	thrower._windup_timer = 0.001
	thrower._tick_timers(0.001)
	var flight: Dictionary = thrower._in_flight[0]
	var hand: Vector2 = appearance.to_global(appearance.get_actor_throw_hand_position())
	check(flight.from.distance_to(hand) < 0.001 and flight.node.global_position.distance_to(hand) < 0.001,
		"A translated and rotated level spawns the projectile at the visible hand in world coordinates")
	check(flight.node.get_parent() == self,
		"Released projectiles belong to the level so subsequent character motion cannot drag them along")
	thrower.clear_pending()
	transform = previous_transform
	completed_scenarios += 1


func check_throw_shapes() -> void:
	await reset_scenario()
	var track_coverage := {}
	for equipment in range(3):
		action.has_flashlight = equipment > 0
		flashlight.is_on = equipment == 2
		flashlight._refresh_light()
		for heading in range(8):
			appearance.actor_facing = DIRECTIONS[heading]
			aim.reset_pose()
			var boots := {"left": appearance.get_actor_boot_position("left"), "right": appearance.get_actor_boot_position("right")}
			var lower: Dictionary = appearance.get_actor_lower_pose().duplicate(true)
			for arm_step in (range(-2, 3) if equipment > 0 else [0]):
				aim._arm_step = arm_step
				aim.aim_angle = heading * PI / 4.0 + arm_step * PI / 8.0 + (deg_to_rad(15.0) if equipment > 0 else 0.0)
				for track in RigLayers.THROW_ANCHORS.TRACKS:
					var count: int = RigLayers.THROW_ANCHORS.TRACKS[track].count
					for frame in range(count):
						appearance.set_throw_pose(StringName(track), frame / float(maxi(count - 1, 1)), 0)
						aim._apply_pose()
						_pose_samples += 1
						for side in ["left", "right"]:
							_boot_drift = maxf(_boot_drift, appearance.get_actor_boot_position(side).distance_to(boots[side]))
						if equipment > 0:
							var grip: Transform2D = appearance.get_actor_grip_transform()
							_lens_error = maxf(_lens_error, appearance.to_global(grip * GRIP_LENS).distance_to(aim.get_beam_global_position()))
							var grip_heading: float = (appearance.global_transform * grip).basis_xform(Vector2.DOWN).angle()
							var forearm_heading: float = appearance.global_rotation + appearance._rig_rotation + appearance._rig_pose.flashlight_angle
							_wrist_bend = maxf(_wrist_bend, absf(rad_to_deg(angle_difference(forearm_heading, grip_heading))))
						track_coverage["%d:%d:%s" % [equipment, heading, track]] = true
			check(appearance.get_actor_lower_pose() == lower, "Throw poses preserve the existing lower-pose data for equipment %d heading %d" % [equipment, heading])
		check(appearance.actor_equipped == (equipment > 0) and flashlight.is_on == (equipment == 2),
			"Throw tracks retain absent, unlit and lit flashlight ownership state %d" % equipment)
	check(track_coverage.size() == 3 * 8 * 2 and _pose_samples == 8 * 11 * RigLayers.THROW_ANCHORS.FRAMES_PER_MODE,
		"Both authored tracks cover all eight headings and every arm aim with absent, unlit and lit flashlight variants")
	check(appearance._rig_pose.upper_texture == RigLayers.THROW_ATLAS,
		"The exhaustive pose sweep renders the authored throw atlas")
	completed_scenarios += 1


func check_wall_release() -> void:
	await reset_scenario()
	thrower._start_throw()
	thrower.set_physics_process(false)
	feedback.set_physics_process(false)
	appearance.set_throw_pose(&"follow_through", 0.0, 0)
	aim._apply_pose()
	var socket_offset: Vector2 = appearance.to_global(appearance.get_actor_throw_hand_position()) - player.global_position
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(2.0, 80.0)
	shape.shape = rectangle
	wall.position = player.global_position + socket_offset * 0.75
	wall.rotation = socket_offset.angle()
	wall.add_child(shape)
	add_child(wall)
	await frames(3)
	thrower._windup_timer = 0.001
	thrower._tick_timers(0.001)
	var origin: Vector2 = thrower._in_flight[0].from
	var query := PhysicsRayQueryParameters2D.create(player.global_position, origin, thrower.wall_mask, [player.get_rid()])
	check(origin.distance_to(player.global_position) < socket_offset.length()
		and player.get_world_2d().direct_space_state.intersect_ray(query).is_empty(),
		"A hand protruding through a nearby wall releases its projectile on the player's side")
	wall.queue_free()
	await frames(3)
	completed_scenarios += 1


func mechanic_sample(presentation_enabled: bool) -> Dictionary:
	thrower.clear_pending()
	thrower.reset_charges()
	thrower.selected = 1
	feedback.enabled = presentation_enabled
	feedback.reset_feedback()
	events.clear()
	noises.clear()
	thrower._start_throw()
	var spent: int = thrower.alarms_left
	for step in range(150):
		thrower._tick_timers(1.0 / 60.0)
		thrower._tick_flight(1.0 / 60.0)
		thrower._tick_ringing(1.0 / 60.0)
		feedback._physics_process(1.0 / 60.0)
	return {"alarms": spent, "starts": event_count(&"start"), "releases": event_count(&"release"),
		"cooldown": thrower._cooldown_timer, "can_throw": thrower.can_throw(),
		"flight_count": thrower._in_flight.size(), "ringing": thrower._ringing.duplicate(true), "noises": noises.duplicate(true)}


func check_shared_inventory_and_parity() -> void:
	await reset_scenario()
	thrower.set_physics_process(false)
	feedback.set_physics_process(false)
	var active := mechanic_sample(true)
	var disabled := mechanic_sample(false)
	check(active == disabled, "Enabling throw presentation preserves shared alarm inventory, flight timing, cooldown and every ringing noise")
	check(active.alarms == 1 and active.starts == 1 and active.releases == 1 and active.can_throw
		and active.flight_count == 0 and active.ringing.size() == 1 and active.noises.size() == 4,
		"The shared alarm spends one charge and retains its impact plus half-second repeated ringing")
	thrower.clear_pending()
	events.clear()
	thrower.alarms_left = 0
	thrower._start_throw()
	check(events.is_empty() and not thrower.is_throwing, "An empty shared alarm cannot start a throw or its feedback")
	thrower.selected = 0
	thrower._start_throw()
	check(thrower.is_throwing and event_count(&"start") == 1,
		"The shared mechanic still provides unlimited stones independently of empty alarms")
	completed_scenarios += 1
