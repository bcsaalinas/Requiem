extends Node2D
const CaptureOutput := preload("res://testing/tools/capture_output.gd")
## A short repeatable visual comparison; output stays outside the repository.

var game: Node2D


func frames(count: int) -> void:
	for index in range(count): await get_tree().physics_frame
	await get_tree().process_frame


func _ready() -> void:
	game = preload("res://testing/experiments/phantom_tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	get_window().mode = Window.MODE_FULLSCREEN
	await frames(15)
	var motion: Node = game.player.get_node("PlayerMotion")
	for feedback in [false, true]:
		motion.set_enabled(feedback)
		for gait in ["Walk", "Sprint", "Held breath"]:
			game.enter_zone("bedroom")
			game.player.get_node("FootstepNoise").footstep_timer = 0.0
			motion.reset_pose()
			await frames(8)
			Input.action_press("move_right")
			if gait == "Sprint": Input.action_press("sprint")
			if gait == "Held breath": Input.action_press("hold_breath")
			await frames(65)
			await RenderingServer.frame_post_draw
			var name := "%s-%s" % ["feedback" if feedback else "original", gait.to_lower().replace(" ", "-")]
			get_viewport().get_texture().get_image().save_png(CaptureOutput.path("movement/%s.png" % name))
			Input.action_release("move_right")
			Input.action_release("sprint")
			Input.action_release("hold_breath")
			await frames(35)
	game.queue_free()
	await frames(3)
	get_tree().quit()
