extends Node2D
## Exercises the actual tutorial HUD and Viv's sound-driven idle/walk visuals.
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	var game := preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(6)
	var player: CharacterBody2D = game.player
	var vitals: Node = game.hud.vitals
	var breath: Node = game.breath
	var body: BodyAudio = player.get_node("BodyAudio")
	var mist: Sprite2D = player.get_node("QuietBreath")
	var rig: CharacterSprite = player.get_node("Appearance").rig
	check(vitals.pose == vitals.Pose.READY, "Rested Viv stands upright")
	# Park the normal tutorial player on an unobstructed stretch of the forest.
	game.enter_zone("forest", game.world.marker("forest", "SpawnFromHome"), false)
	await frames(6)
	for moving in [false, true]:
		if moving:
			Input.action_press("move_right")
		var max_lift := 0.0
		var emitted := false
		var quiet := false
		var active_clip := false
		# Seek the playing calm take across inhalation, exhalation and the quiet tail.
		for at in [1.35, 1.85, 3.4]:
			var voice := body.leading_breath_loop()
			if voice == null:
				break
			voice.play(at)
			await frames(4)
			await get_tree().create_timer(0.0).timeout
			max_lift = maxf(max_lift, rig.breath_lift)
			if mist.visible:
				var mouth := rig.anchor_global("head_center") + Vector2.DOWN.rotated(rig.global_rotation) * 25.0 * Units.ART_SCALE
				emitted = mist.global_position.distance_to(mouth) < 3.0
			if at == 3.4:
				quiet = not mist.visible
			active_clip = rig.clip_name(&"upper").begins_with("girl_walk" if moving else "girl_idle")
		check(max_lift >= 2 and emitted and quiet and active_clip, "Audible inhale lifts Viv and exhale mists at her mouth (walking=%s, lift=%s, mist=%s, quiet=%s, clip=%s)" % [moving, max_lift, emitted, quiet, rig.clip_name(&"upper")])
	Input.action_press("sprint")
	await frames(3)
	check(vitals.pose == vitals.Pose.RUN, "A real sprint changes the icon")
	breath.exertion_percent = breath.exertion_warn_percent + 2.0
	await frames(3)
	check(vitals.pose == vitals.Pose.LABORED_RUN, "The shared panting threshold changes her stride")
	Input.action_release("sprint")
	await frames(4)
	check(vitals.pose == vitals.Pose.TIRED_WALK, "Walking while tired does not claim recovery")
	Input.action_release("move_right")
	await frames(30)
	check(vitals.pose == vitals.Pose.RECOVER, "Resting with fatigue shows recovery")
	Input.action_press("hold_breath")
	await frames(4)
	check(vitals.pose == vitals.Pose.BRACED and not mist.visible and is_zero_approx(rig.breath_lift),
		"Holding a strained breath suppresses the ordinary exhale and shoulder lift")
	breath.exertion_percent = 20.0
	await frames(2)
	check(vitals.pose == vitals.Pose.HOLD, "An easy held breath has its own posture")
	breath.exertion_percent = 99.99
	await frames(4)
	check(breath.is_locked and is_zero_approx(breath.exertion_percent) and vitals.pose == vitals.Pose.GASP,
		"The gasp posture survives the meter reset")
	Input.action_release("hold_breath")
	await get_tree().create_timer(breath.forced_lock_duration + 0.15).timeout
	check(not breath.is_locked and vitals.pose == vitals.Pose.READY, "The icon settles when control returns")
	print("[Pixel feedback] %d/%d passed" % [checks - failures, checks])
	get_tree().quit(1 if failures else 0)
