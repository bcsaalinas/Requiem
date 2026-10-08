extends Node

var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://tutorial/tutorial.tscn", "F5 retains the playable tutorial")
	check(not ProjectSettings.has_setting("autoload/NoiseDebug"), "Production has no noise-debug autoload")
	var lab = preload("res://testing/test_lab.tscn").instantiate()
	add_child(lab)
	check(lab.menu.visible and not lab.toolbar.visible, "Lab opens at its launcher")
	await lab.launch(lab.TUTORIAL)
	await frames(8)
	check(lab.active_scene.zone == "bedroom" and not lab.active_scene.has_node("CameraTestOverlay"), "Normal tutorial has no comparison overlay")
	check(not lab.noise.enabled, "Noise overlay starts off")
	lab.active_scene._toggle_pause()
	check(get_tree().paused, "Tutorial can pause inside the lab")
	await lab.show_menu()
	check(not get_tree().paused and lab.active_scene == null and lab.menu.visible, "Returning from pause clears the scene and resumes the lab")
	await lab.launch(lab.COMPARISON)
	await frames(12)
	lab.active_scene.jump_to_zone(2)
	await frames(4)
	check(lab.active_scene.zone == "forest", "Comparison area shortcuts still work")
	check(get_viewport().get_camera_2d() == lab.active_scene.camera_rig.camera, "Comparison owns the active camera")
	await lab.launch(lab.SANDBOX)
	await frames(20)
	var sandbox = lab.active_scene
	check(sandbox.get_node("Map").get_used_cells().size() > 0 and sandbox.get_node("NavigationRegion2D").navigation_polygon != null, "Mechanics sandbox paints before navigation initializes")
	check(sandbox.get_node("Props").get_child_count() > 0, "Sandbox contains the real shared altar")
	check(sandbox.get_node("Player/ActionState").has_flashlight, "Sandbox starts equipped")
	check(sandbox.get_node("Player/Throw").get_script() == preload("res://player/throw.gd"), "Sandbox uses shared throwables instead of the tutorial inventory adapter")
	await check_breath_studio(lab)
	await check_throw_studio(lab)
	await check_prayer_studio(lab)
	await check_sprint_studio(lab)
	await lab.show_menu()
	check(not GameState.is_dead and not GameState.is_praying and GameOverUi.label.text == "", "Scenario exit clears shared death and prayer state")
	check(not lab.noise.enabled and not lab.noise.is_processing_unhandled_input(), "Debug keyboard handling is disabled in the menu")
	lab.queue_free()
	await frames(3)
	print("[Test Lab checks] %d/%d passed" % [checks - failures, checks])
	get_tree().quit(0 if failures == 0 else 1)


func check_breath_studio(lab: Node) -> void:
	await lab.launch(lab.BREATH_STUDIO)
	await frames(8)
	var studio: Node = lab.active_scene
	var breath: Node = studio.breath
	var feedback: Node = studio.player.get_node("BreathFeedback")
	var appearance: Node2D = studio.player.get_node("Appearance")
	check(studio.zone == "hallway" and studio.test_mode and not studio.entity.active
		and not studio.entity.visible, "Breath studio opens in the safe production hallway")
	check(studio.has_flashlight and appearance.actor_equipped and studio.flashlight.is_on,
		"Breath studio starts with visible equipped light")
	var studio_controls: Rect2 = studio.studio_status.get_parent().get_parent().get_global_rect()
	check(studio_controls.end.y <= lab.toolbar.position.y
		and get_viewport().get_visible_rect().encloses(studio_controls),
		"Breath studio controls fit the viewport above the lab return toolbar")
	check(studio.equipment_button.focus_mode == Control.FOCUS_NONE
		and studio.area_selector.focus_mode == Control.FOCUS_NONE
		and studio.effects_button.focus_mode == Control.FOCUS_NONE,
		"Studio controls leave Space available to the mechanic after clicking")

	studio.reset_studio_breath(25.0, 0.0)
	check(breath.lung_percent == 25.0 and breath.exertion_percent == 0.0,
		"Low-air preset changes actual breathing resources")
	Input.action_press("hold_breath")
	await frames(8)
	check(breath.is_holding and breath.lung_percent < 25.0 and feedback.cue == &"inhale"
		and feedback.phase == &"inhale", "Real hold input begins the low-air inhale feedback")
	await frames(78)
	check(breath.is_locked and feedback.phase in [&"gasp", &"recovery"]
		and feedback.cue == &"gasp", "Actual low-air depletion reaches visible forced recovery")
	check(studio.zone == "hallway" and not studio.resetting and studio.parent_failures == 0,
		"Loud breathing cannot trigger the tutorial's parental reset in the studio")
	studio.reset_studio_breath()
	check(not breath.is_locked and not breath.is_holding and not breath.needs_release
		and feedback.phase == &"idle" and feedback.cue == &"" and feedback.strain == 0.0,
		"Studio reset clears forced recovery, its input latch, and transient feedback")

	studio.set_equipped(false)
	await frames(3)
	check(not studio.has_flashlight and not appearance.actor_equipped and not studio.flashlight.enabled,
		"Equipment comparison removes both visible prop and emitted light")
	studio.set_studio_area(1)
	await frames(3)
	check(studio.zone == "bedroom" and studio.area_selector.selected == 1
		and breath.lung_percent == 100.0 and breath.exertion_percent == 0.0,
		"Lit-bedroom comparison resets real resources in the production room")
	studio.set_equipped(true)
	await frames(3)
	check(appearance.actor_equipped and studio.flashlight.enabled,
		"Equipment comparison restores the visible light and attachment")
	studio.set_studio_area(0)
	studio.reset_studio_breath(100.0, 90.0)
	check(studio.zone == "hallway" and breath.lung_percent == 100.0 and breath.exertion_percent == 90.0,
		"High-exertion preset is independent of lung depletion")
	Input.action_press("hold_breath")
	await frames(20)
	check(feedback.phase == &"strain" and feedback.exertion_pressure > 0.5
		and feedback.lung_pressure == 0.0 and studio.studio_status.text.contains("Straining"),
		"Real high-exertion holding shows strain and its readable studio status")
	var lung_before_effects_toggle: float = breath.lung_percent
	studio.effects_button.pressed.emit()
	await frames(3)
	check(feedback.effects_strength == 0.0 and studio.effects_button.text == "Effects: off"
		and feedback.enabled and feedback.phase == &"strain" and appearance._breath_track == &"strain"
		and breath.is_holding and breath.lung_percent < lung_before_effects_toggle,
		"Effects comparison disables VFX while the live breath animation and mechanic continue")
	studio.effects_button.pressed.emit()
	check(feedback.effects_strength == 1.0 and studio.effects_button.text == "Effects: on",
		"Effects comparison restores the visual feedback without resetting the breath")
	var paused_lung: float = breath.lung_percent
	var paused_pulse: float = feedback.pulse
	var paused_cue_age: float = feedback.cue_age
	studio._toggle_pause()
	await frames(5)
	check(get_tree().paused and breath.lung_percent == paused_lung
		and feedback.pulse == paused_pulse and feedback.cue_age == paused_cue_age,
		"Pausing the studio freezes breath resources and animation feedback together")
	await lab.show_menu()
	check(not get_tree().paused and lab.active_scene == null and lab.menu.visible
		and not Input.is_action_pressed("hold_breath"),
		"Returning from the paused studio clears its held input and pause state")


func check_throw_studio(lab: Node) -> void:
	await lab.launch(lab.THROW_STUDIO)
	await frames(8)
	var studio: Node = lab.active_scene
	var thrower: Node = studio.thrower
	var feedback: Node = studio.player.get_node("ThrowFeedback")
	var appearance: Node2D = studio.player.get_node("Appearance")
	check(studio.zone == "hallway" and studio.test_mode and not studio.entity.active
		and not studio.entity.visible and thrower.rocks == 3 and thrower.can_throw(),
		"Throw studio opens safely in the production hallway with three usable rocks")
	check(studio.equipment_button.focus_mode == Control.FOCUS_NONE
		and studio.area_selector.focus_mode == Control.FOCUS_NONE,
		"Throw studio controls leave gameplay keys available after clicking")
	var controls: Rect2 = studio.studio_status.get_parent().get_parent().get_global_rect()
	check(controls.end.y <= lab.toolbar.position.y and get_viewport().get_visible_rect().encloses(controls),
		"Throw studio controls fit the viewport above the lab return toolbar")
	studio.player.get_node("PlayerAim").set_target(studio.player.global_position + Vector2.DOWN * 200.0)
	Input.action_press("throw")
	await frames(2)
	Input.action_release("throw")
	check(thrower.rocks == 2 and thrower.is_throwing and feedback.phase == &"windup",
		"Real Q input spends one studio rock and starts the real throw anticipation")
	await frames(31)
	check(not thrower.is_throwing and thrower._in_flight.size() == 1
		and feedback.phase == &"follow_through" and thrower._cooldown_timer > 0.0 and not thrower.can_throw(),
		"The studio releases its projectile into authored follow-through and the existing cooldown")
	studio.reset_studio_throw()
	check(thrower.rocks == 3 and thrower.can_throw() and thrower._in_flight.is_empty()
		and feedback.phase == &"idle" and appearance._throw_track == &"idle",
		"Reset during follow-through clears the flight and pose, removes cooldown and refills three rocks")
	await frames(28)
	check(thrower._in_flight.is_empty() and not studio.resetting and studio.parent_failures == 0
		and studio.zone == "hallway" and not studio.entity.active,
		"A reset throw cannot produce a delayed flight or trigger a tutorial encounter")
	for mode in range(3):
		studio.set_equipment_mode(mode)
		await frames(3)
		check(studio.get_equipment_mode() == mode and studio.has_flashlight == (mode > 0)
			and appearance.actor_equipped == (mode > 0) and studio.flashlight.enabled == (mode == 2),
			"Throw studio equipment comparison correctly applies absent, off and on mode %d" % mode)
	Input.action_press("throw")
	await frames(2)
	studio.set_studio_area(1)
	await frames(3)
	check(studio.zone == "bedroom" and studio.area_selector.selected == 1
		and thrower.rocks == 3 and not thrower.is_throwing and thrower._in_flight.is_empty()
		and feedback.phase == &"idle" and not Input.is_action_pressed("throw"),
		"Changing to the lit bedroom cancels a pending throw, resets its presentation and refills inventory")
	studio.set_studio_area(0)
	Input.action_press("throw")
	Input.action_press("hold_breath")
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(4)
	var windup_before_pause: float = thrower._windup_timer
	var pose_before_pause: float = feedback.pose_phase
	studio._toggle_pause()
	await frames(5)
	check(get_tree().paused and thrower._windup_timer == windup_before_pause
		and feedback.pose_phase == pose_before_pause,
		"Pausing the throw studio freezes its real windup and presentation together")
	var return_key := InputEventKey.new()
	return_key.keycode = KEY_F1
	return_key.pressed = true
	lab._input(return_key)
	await frames(5)
	check(not get_tree().paused and lab.active_scene == null and lab.menu.visible
		and not Input.is_action_pressed("throw") and not Input.is_action_pressed("hold_breath")
		and not Input.is_action_pressed("sprint") and not Input.is_action_pressed("move_right"),
		"F1 returns from the paused throw studio without leaking pause, throw, breath or movement input")


func check_prayer_studio(lab: Node) -> void:
	await lab.launch(lab.PRAYER_STUDIO)
	await frames(8)
	var studio: Node = lab.active_scene
	var breath: Node = studio.breath
	var feedback: Node = studio.player.get_node("PrayerFeedback")
	var appearance: Node2D = studio.player.get_node("Appearance")
	var aim: Node = studio.player.get_node("PlayerAim")
	check(studio.zone == "bedroom" and studio.test_mode and not studio.entity.active
		and not studio.entity.visible and not studio.thrower.available,
		"Prayer studio opens in the safe production room without enemies or throw interference")
	check(is_instance_valid(studio.altar) and studio.altar.get_script() == preload("res://altar/body_altar.gd")
		and studio.altar.pray_duration == 12.0 and studio.altar.jugador_cerca,
		"Prayer studio places the shared player inside the real twelve-second altar's proximity area")
	check(studio.has_flashlight and appearance.actor_equipped and studio.flashlight.enabled,
		"Prayer studio begins with the shared equipped player and live flashlight")
	check(studio.equipment_button.focus_mode == Control.FOCUS_NONE
		and studio.heading_selector.focus_mode == Control.FOCUS_NONE,
		"Prayer studio controls leave E and Space available after clicking presets")
	var controls: Rect2 = studio.studio_status.get_parent().get_parent().get_global_rect()
	check(controls.end.y <= lab.toolbar.position.y and get_viewport().get_visible_rect().encloses(controls),
		"Prayer studio controls fit the viewport above the lab return toolbar")
	Input.action_press("pray")
	await frames(7)
	check(GameState.is_praying and GameState.prayer_source == studio.altar
		and studio.altar.tiempo_interaccion > 0.0 and feedback.phase == &"entry",
		"Real E input starts the owned altar clock and the shared prayer entry")
	var prayer_position: Vector2 = studio.player.global_position
	Input.action_press("move_right")
	await frames(24)
	check(studio.player.global_position.distance_to(prayer_position) < 0.01
		and feedback.phase == &"loop" and appearance._prayer_track == &"loop"
		and studio.studio_status.text.contains("Loop") and studio.studio_status.text.contains("prayer"),
		"Prayer roots the real player and reaches a sustained pose with truthful studio status")
	Input.action_release("move_right")
	Input.action_release("pray")
	await frames(3)
	check(not GameState.is_praying and GameState.prayer_source == null
		and studio.altar.tiempo_interaccion == 0.0 and feedback.phase == &"exit",
		"Releasing E cancels actual ritual progress and enters the authored prayer exit")
	await frames(24)
	check(feedback.phase == &"idle" and appearance._prayer_track == &"idle",
		"The studio returns the shared character to idle after prayer release")

	studio.reset_studio_prayer(25.0)
	check(breath.lung_percent == 25.0 and breath.exertion_percent == 0.0
		and not breath.is_locked and not breath.needs_release,
		"Prayer studio's low-air preset sets real resources and clears stale breath input")
	await frames(4)
	Input.action_press("pray")
	Input.action_press("hold_breath")
	await frames(84)
	check(breath.is_locked and GameState.is_praying and GameState.prayer_source == studio.altar
		and studio.altar.tiempo_interaccion > 1.0
		and studio.player.get_node("ActionState").get_action() == &"forced_gasp",
		"Actual low-air depletion gives forced gasp priority while the owned studio ritual keeps progressing")
	studio.reset_studio_prayer()
	check(not GameState.is_praying and GameState.prayer_source == null
		and not breath.is_locked and not breath.is_holding and not breath.needs_release
		and breath.lung_percent == 100.0 and breath.exertion_percent == 0.0
		and feedback.phase == &"idle" and not Input.is_action_pressed("pray")
		and not Input.is_action_pressed("hold_breath"),
		"Reset during gasp clears prayer ownership, resources, feedback and held keys")

	for heading in range(8):
		studio.set_studio_heading(heading)
		await frames(4)
		var expected := heading * PI / 4.0
		check(studio.heading_selector.selected == heading
			and studio.player.global_position.distance_to(studio.ALTAR_POSITION - Vector2.from_angle(expected) * 66.0) < 0.01
			and absf(angle_difference(aim.pose_body_angle, expected)) < 0.01
			and studio.altar.jugador_cerca and not GameState.is_praying,
			"Prayer heading preset %d repositions and faces the real player within altar range" % heading)
	for mode in range(3):
		studio.set_equipment_mode(mode)
		await frames(3)
		check(studio.get_equipment_mode() == mode and studio.has_flashlight == (mode > 0)
			and appearance.actor_equipped == (mode > 0) and studio.flashlight.enabled == (mode == 2),
			"Prayer studio equipment comparison correctly applies absent, off and on mode %d" % mode)
	studio.equipment_button.pressed.emit()
	await frames(3)
	check(studio.get_equipment_mode() == 0 and studio.equipment_button.text == "Flashlight: absent",
		"Prayer studio's equipment button cycles from on to absent without stealing gameplay input")
	studio.set_equipment_mode(2)
	studio.set_studio_heading(6)
	await frames(4)
	Input.action_press("pray")
	Input.action_press("hold_breath")
	await frames(12)
	var ritual_before_pause: float = studio.altar.tiempo_interaccion
	var pose_before_pause: float = feedback.pose_phase
	var lung_before_pause: float = breath.lung_percent
	studio._toggle_pause()
	await frames(5)
	check(get_tree().paused and studio.altar.tiempo_interaccion == ritual_before_pause
		and feedback.pose_phase == pose_before_pause and breath.lung_percent == lung_before_pause,
		"Pausing prayer studio freezes the altar clock, character animation and breathing resources together")
	var return_key := InputEventKey.new()
	return_key.keycode = KEY_F1
	return_key.pressed = true
	lab._input(return_key)
	await frames(5)
	check(not get_tree().paused and lab.active_scene == null and lab.menu.visible
		and not Input.is_action_pressed("pray") and not Input.is_action_pressed("hold_breath")
		and not GameState.is_praying and GameState.prayer_source == null,
		"F1 leaves paused prayer studio without leaking prayer ownership, held keys or pause state")


func check_sprint_studio(lab: Node) -> void:
	await lab.launch(lab.SPRINT_STUDIO)
	await frames(8)
	var studio: Node = lab.active_scene
	var motion: Node = studio.player.get_node("PlayerMotion")
	var dust: Node = studio.player.get_node("SprintDust")
	var appearance: Node = studio.player.get_node("Appearance")
	check(studio.zone == "bedroom" and studio.area_selector.selected == 0 and studio.test_mode
		and not studio.entity.active and not studio.entity.visible and not studio.thrower.available,
		"Sprint studio opens in the safe lit bedroom with production collision and no story encounters")
	check(studio.player.global_position.distance_to(Vector2(385, 440)) < 0.01
		and dust.enabled and dust.effects_strength == 1.0 and dust.particles.is_empty(),
		"Sprint studio starts on the open rug with enabled, empty ground dust")
	var controls: Rect2 = studio.studio_status.get_parent().get_parent().get_global_rect()
	check(controls.end.y <= lab.toolbar.position.y and get_viewport().get_visible_rect().encloses(controls),
		"Sprint studio controls fit above the lab return toolbar")
	check(studio.equipment_button.focus_mode == Control.FOCUS_NONE
		and studio.area_selector.focus_mode == Control.FOCUS_NONE
		and studio.effects_button.focus_mode == Control.FOCUS_NONE,
		"Sprint controls preserve movement, sprint and breath input after clicking")
	var start: Vector2 = studio.player.global_position
	var before: int = dust.emitted_puffs
	Input.action_press("move_right")
	await frames(32)
	check(motion.mode == "Walk" and studio.player.global_position.x > start.x + 30.0
		and dust.emitted_puffs == before and dust.particles.is_empty(),
		"Real walking moves through the studio without producing sprint dust")
	Input.action_press("sprint")
	await frames(35)
	check(motion.mode == "Sprint" and studio.player.is_sprinting and studio.player.get_speed_u() > 5.0
		and dust.emitted_puffs > before and studio.studio_status.text.contains("Sprint"),
		"Shift starts the actual sprint gait and planted-foot dust with truthful status")
	var effort_before_toggle: float = studio.breath.exertion_percent
	studio.effects_button.pressed.emit()
	before = dust.emitted_puffs
	await frames(20)
	check(not dust.enabled and dust.effects_strength == 0.0 and dust.particles.is_empty()
		and dust.emitted_puffs == before and motion.mode == "Sprint"
		and studio.breath.exertion_percent > effort_before_toggle and studio.effects_button.text == "Dust: off",
		"Dust comparison removes only visual puffs while real sprint movement and exertion continue")
	studio.effects_button.pressed.emit()
	await frames(25)
	check(dust.enabled and dust.effects_strength == 1.0 and dust.emitted_puffs > before
		and studio.effects_button.text == "Dust: on",
		"Re-enabling dust resumes emission on new actual foot contacts")
	Input.action_release("move_right")
	Input.action_release("sprint")
	await frames(45)
	check(motion.mode == "Idle" and dust.particles.is_empty(),
		"Normal sprint release settles the gait and naturally finishes remaining puffs")

	for mode in range(3):
		studio.set_equipment_mode(mode)
		await frames(3)
		check(studio.get_equipment_mode() == mode and studio.has_flashlight == (mode > 0)
			and appearance.actor_equipped == (mode > 0) and studio.flashlight.enabled == (mode == 2),
			"Sprint studio correctly presents absent, off and on equipment mode %d" % mode)
	studio.set_studio_area(1)
	await frames(4)
	check(studio.zone == "hallway" and studio.player.global_position.distance_to(Vector2(2100, 348)) < 0.01
		and studio.area_selector.selected == 1 and dust.particles.is_empty(),
		"Hallway comparison preserves production scenery and clears previous world-space dust")
	studio.set_studio_area(2)
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(35)
	check(studio.zone == "forest" and studio.player.global_position.x > 3845.0
		and motion.mode == "Sprint" and not studio.resetting and studio.parent_failures == 0
		and not studio.entity.active and studio.dialogue.is_empty(),
		"Forest path offers a real open run without tutorial story or enemy interruptions")
	studio.reset_studio_sprint()
	check(studio.player.global_position.distance_to(Vector2(3820, 430)) < 0.01
		and studio.player.velocity == Vector2.ZERO and not studio.player.is_sprinting
		and studio.breath.lung_percent == 100.0 and studio.breath.exertion_percent == 0.0
		and dust.particles.is_empty() and motion.mode == "Idle"
		and not Input.is_action_pressed("sprint") and not Input.is_action_pressed("move_right"),
		"Reset returns to the current run origin and clears real resources, input, gait and dust")

	studio.set_studio_area(0)
	studio.player.global_position = Vector2(896, 440)
	await frames(4)
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(45)
	before = dust.emitted_puffs
	var blocked_position: Vector2 = studio.player.global_position
	await frames(20)
	check(studio.player.global_position.distance_to(blocked_position) < 0.01
		and studio.player.get_speed_u() < 0.01 and motion.mode == "Idle"
		and dust.emitted_puffs == before and dust.particles.is_empty(),
		"The production bedroom wall stops gait and dust while sprint input remains held")

	studio.set_studio_area(2)
	Input.action_press("sprint")
	Input.action_press("move_right")
	await frames(38)
	var particles_before_pause: Array = dust.particles.duplicate(true)
	var position_before_pause: Vector2 = studio.player.global_position
	var effort_before_pause: float = studio.breath.exertion_percent
	studio._toggle_pause()
	await frames(5)
	check(get_tree().paused and studio.player.global_position == position_before_pause
		and studio.breath.exertion_percent == effort_before_pause and dust.particles == particles_before_pause,
		"Pausing sprint studio freezes movement, exertion and existing dust together")
	var return_key := InputEventKey.new()
	return_key.keycode = KEY_F1
	return_key.pressed = true
	lab._input(return_key)
	await frames(5)
	check(not get_tree().paused and lab.active_scene == null and lab.menu.visible
		and not Input.is_action_pressed("sprint") and not Input.is_action_pressed("move_right"),
		"F1 leaves paused sprint studio without leaking sprint, movement or pause state")
