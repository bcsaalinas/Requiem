extends Node
## Exercise presentation transitions against the real breath/action mechanics.
## A minimal player keeps resource and hearing assertions deterministic.

var checks := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var noises: Array[float] = []
var footstep_noises: Array[Dictionary] = []
var player: CharacterBody2D
var breath: Node
var footsteps: Node


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func observe(event: StringName, details: Dictionary = {}) -> void:
	details.merge({"event": event, "holding": breath.is_holding,
		"locked": breath.is_locked, "lung": breath.lung_percent,
		"recovery": breath.get_recovery_remaining()})
	events.append(details)


func reset_scenario() -> void:
	for input_action in ["hold_breath", "sprint", "move_right"]:
		Input.action_release(input_action)
	GameState.reset()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.is_sprinting = false
	player.velocity = Vector2.ZERO
	breath.cancel_holding()
	breath.is_locked = false
	breath._lock_timer = 0.0
	breath.reset_input_latch()
	breath.lung_percent = 100.0
	breath.exertion_percent = 0.0
	events.clear()
	noises.clear()
	footstep_noises.clear()


func _ready() -> void:
	GameState.reset()
	player = CharacterBody2D.new()
	player.set_script(preload("res://player/player.gd"))
	var action := Node.new()
	action.name = "ActionState"
	action.set_script(preload("res://player/action_state.gd"))
	player.add_child(action)
	breath = Node.new()
	breath.name = "HoldBreath"
	breath.set_script(preload("res://player/hold_breath.gd"))
	player.add_child(breath)
	footsteps = Node.new()
	footsteps.name = "FootstepNoise"
	footsteps.set_script(preload("res://player/footstep_noise.gd"))
	player.add_child(footsteps)
	add_child(player)
	# Step only the real mechanic explicitly, with known deltas.
	action.set_physics_process(false)
	breath.set_physics_process(false)
	player.set_physics_process(false)
	footsteps.set_physics_process(false)
	breath.hold_started.connect(func(): observe(&"start"))
	breath.breath_released.connect(func(quiet: bool, lung: float):
		observe(&"release", {"quiet": quiet, "released_lung": lung}))
	breath.forced_gasp_started.connect(func(reason: StringName, duration: float):
		observe(&"gasp", {"reason": reason, "duration": duration}))
	breath.hold_cancelled.connect(func(): observe(&"cancel"))
	NoiseManager.noise_emitted.connect(func(_at: Vector2, radius: float, source: int, _duration: float):
		if source == NoiseManager.SourceType.BREATH:
			noises.append(radius)
		else:
			footstep_noises.append({"radius": radius, "source": source}))
	check_deliberate_release()
	check_forced_recovery()
	check_release_to_rearm()
	check_lung_gasp_audio()
	check_interruptions()
	reset_scenario()
	player.queue_free()
	await get_tree().process_frame
	print("[Breath event tests] %d/%d passed" % [checks - failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func check_deliberate_release() -> void:
	reset_scenario()
	Input.action_press("hold_breath")
	breath._physics_process(0.5)
	check(events.size() == 1 and events[0].event == &"start" and events[0].holding,
		"Hold starts once and observers already see an active held breath")
	check(is_equal_approx(breath.lung_percent, 90.0) and is_equal_approx(breath.exertion_percent, 3.0),
		"Starting hold retains the existing lung and exertion rates")
	breath._physics_process(0.5)
	check(events.size() == 1 and noises.is_empty(), "Sustaining hold emits neither repeated starts nor hearing events")
	Input.action_release("hold_breath")
	breath._physics_process(0.5)
	check(events.size() == 2 and events[1].event == &"release" and events[1].quiet
		and not events[1].holding and is_equal_approx(events[1].released_lung, 80.0),
		"Quiet release reports the actual pre-refill lung value after clearing held state")
	check(noises.size() == 1 and is_equal_approx(noises[0], Units.to_px(1.0)),
		"A deliberate quiet release preserves its single 1-unit hearing event")
	check(is_equal_approx(breath.lung_percent, 85.0) and is_equal_approx(breath.exertion_percent, 4.0),
		"Release keeps lung refill and stationary exertion recovery unchanged")
	breath._release_breath()
	breath._physics_process(0.5)
	check(events.size() == 2 and noises.size() == 1,
		"Released and repeated release calls cannot replay a release or its hearing event")
	reset_scenario()
	breath.lung_percent = 20.0
	Input.action_press("hold_breath")
	breath._physics_process(0.0)
	Input.action_release("hold_breath")
	breath._physics_process(0.0)
	check(events.size() == 2 and not events[1].quiet and is_equal_approx(events[1].released_lung, 20.0),
		"Exactly 20 percent lung produces the existing loud deliberate release")
	check(noises.size() == 1 and is_equal_approx(noises[0], Units.to_px(5.0)) and not breath.is_locked,
		"Low-lung voluntary release keeps its 5-unit noise and does not add a forced lock")


func check_forced_recovery() -> void:
	reset_scenario()
	breath.lung_percent = 1.0
	breath.exertion_percent = 99.9
	Input.action_press("hold_breath")
	breath._physics_process(0.1)
	check(events.size() == 2 and events[0].event == &"start" and events[1].event == &"gasp"
		and events[1].reason == &"lung", "Lung depletion has one forced transition and retains priority over exertion")
	check(not events[1].holding and events[1].locked and events[1].lung == 0.0
		and is_equal_approx(events[1].recovery, 2.0) and is_equal_approx(events[1].duration, 2.0),
		"Forced gasp observers receive the completed lock state and its real duration")
	check(breath.exertion_percent == 0.0 and noises.size() == 1
		and is_equal_approx(noises[0], Units.to_px(7.0)),
		"Forced gasp preserves one 7-unit hearing event and resets exertion")
	breath._forced_gasp(breath.exertion_clips)
	breath._release_breath()
	breath._physics_process(0.75)
	check(events.size() == 2 and noises.size() == 1 and is_equal_approx(breath.get_recovery_remaining(), 1.25),
		"Held input, duplicate gasp and release during recovery add no phantom exhale")
	check(breath.lung_percent == 0.0 and breath.exertion_percent == 0.0,
		"The existing recovery lock still freezes both resources")
	Input.action_release("hold_breath")
	breath._physics_process(1.5)
	check(not breath.is_locked and breath.get_recovery_remaining() == 0.0,
		"Recovery remaining clamps at zero when the existing lock finishes")
	breath._physics_process(0.5)
	check(events.size() == 2 and noises.size() == 1 and is_equal_approx(breath.lung_percent, 5.0),
		"Post-lock refill does not manufacture a release event")
	reset_scenario()
	player.is_sprinting = true
	breath.exertion_percent = 99.5
	breath._physics_process(0.1)
	check(events.size() == 1 and events[0].event == &"gasp" and events[0].reason == &"exertion",
		"Sprint exhaustion reports its own reason even without a held breath")
	check(breath.is_locked and breath.lung_percent == 100.0 and breath.exertion_percent == 0.0,
		"Sprint exhaustion preserves the full lung and shared forced recovery behavior")


func check_interruptions() -> void:
	reset_scenario()
	Input.action_press("hold_breath")
	breath._physics_process(0.1)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	breath._physics_process(0.1)
	breath.cancel_holding()
	check(events.size() == 2 and events[1].event == &"cancel" and not events[1].holding,
		"Disabled input cancels one actual hold and repeated cancellation stays silent")
	check(noises.is_empty() and is_equal_approx(breath.lung_percent, 98.0),
		"Dialogue interruption adds neither exhale noise nor resource changes")
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	breath._physics_process(0.1)
	check(events.size() == 3 and events[2].event == &"start",
		"Resuming held input after an interruption starts a new real hold")
	GameState.is_dead = true
	breath._physics_process(0.1)
	breath._forced_gasp(breath.exertion_clips)
	breath._physics_process(0.1)
	check(events.size() == 4 and events[3].event == &"cancel" and not breath.is_locked
		and noises.is_empty(), "Death interrupts once without a release, forced gasp or hearing event")


func check_release_to_rearm() -> void:
	reset_scenario()
	breath.lung_percent = 1.0
	Input.action_press("hold_breath")
	breath._physics_process(0.1)
	check(breath.needs_release, "A forced gasp requires release before another held breath")
	Input.action_release("hold_breath")
	breath._physics_process(0.1)
	check(breath.needs_release, "Releasing during the lock cannot rearm early")
	Input.action_press("hold_breath")
	breath._physics_process(2.0)
	for step in range(60):
		breath._physics_process(1.0 / 60.0)
	check(breath.needs_release and not breath.is_holding and not breath.is_locked
		and is_equal_approx(breath.lung_percent, 10.0) and events.size() == 2 and noises.size() == 1,
		"Holding Space through recovery refills normally without chained forced gasps")
	var action: Node = player.get_node("ActionState")
	check(not action.is_hold_requested() and action.can_move(),
		"The latched request does not give movement a false held-breath state")
	Input.action_press("move_right")
	for step in range(100):
		player._physics_process(1.0 / 60.0)
	check(absf(player.get_speed_u() - player.walk_speed_u) < 0.01 and not player.is_sprinting,
		"Latched Space permits normal walking rather than held-breath speed")
	footsteps._do_footstep(player.get_speed_u())
	check(footstep_noises.size() == 1 and footstep_noises[0].source == NoiseManager.SourceType.FOOTSTEP
		and is_equal_approx(footstep_noises[0].radius, Units.to_px(3.0)),
		"Latched Space grants no quieter held-footstep benefit")
	Input.action_press("sprint")
	for step in range(100):
		player._physics_process(1.0 / 60.0)
	check(absf(player.get_speed_u() - player.sprint_speed_u) < 0.01 and player.is_sprinting,
		"Latched Space also permits normal sprint speed")
	footsteps._do_footstep(player.get_speed_u())
	check(footstep_noises.size() == 2 and footstep_noises[1].source == NoiseManager.SourceType.SPRINT
		and is_equal_approx(footstep_noises[1].radius, Units.to_px(6.0)),
		"Sprinting after forced recovery retains its full hearing cost")
	Input.action_release("hold_breath")
	breath._physics_process(0.1)
	check(not breath.needs_release and not breath.is_holding and is_equal_approx(breath.lung_percent, 11.0),
		"Release after recovery rearms while preserving the current refill")
	Input.action_press("hold_breath")
	breath._physics_process(0.1)
	check(breath.is_holding and events.size() == 3 and events[2].event == &"start"
		and is_equal_approx(breath.lung_percent, 9.0), "A fresh press after release begins a real held breath")
	reset_scenario()
	player.is_sprinting = true
	breath.exertion_percent = 99.5
	breath._physics_process(0.1)
	Input.action_press("hold_breath")
	breath._physics_process(2.1)
	breath._physics_process(0.1)
	check(breath.needs_release and not breath.is_holding and not breath.is_locked
		and events.size() == 1, "An exertion gasp uses the same release-to-rearm rule")
	breath.reset_input_latch()
	check(not breath.needs_release, "An explicit level reset can clear the temporary input latch")


func check_lung_gasp_audio() -> void:
	reset_scenario()
	var lung_clip := AudioStreamGenerator.new()
	var exertion_clip := AudioStreamGenerator.new()
	breath.forced_gasp_clips.append(lung_clip)
	breath.exertion_clips.append(exertion_clip)
	breath.lung_percent = 1.0
	Input.action_press("hold_breath")
	breath._physics_process(0.1)
	check(breath._audio_player.stream == lung_clip, "Lung depletion uses its configured forced-gasp audio")
	reset_scenario()
	breath.forced_gasp_clips.clear()
	breath.lung_percent = 1.0
	Input.action_press("hold_breath")
	breath._physics_process(0.1)
	check(breath._audio_player.stream == exertion_clip,
		"An unconfigured lung gasp preserves the previous exertion-audio fallback")
	breath.exertion_clips.clear()
