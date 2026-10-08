extends Node
## Repeatable real-input review. Movie Maker and images stay outside game assets.
const CaptureOutput := preload("res://testing/tools/capture_output.gd")
var studio: Node2D


func frames(count: int) -> void:
	for index in range(count): await get_tree().physics_frame
	await get_tree().process_frame


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(CaptureOutput.path("breath/%s.png" % label))


func _ready() -> void:
	studio = preload("res://testing/experiments/breath_studio.tscn").instantiate()
	add_child(studio)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	# Deterministic render size even when a tiling desktop resizes the window.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await frames(15)
	studio.player.get_node("PlayerAim").set_target(studio.player.position + Vector2(280, -200))
	studio.hud.subtitle.text = "HOLD BREATH · Animation & feedback"
	await frames(60)
	await capture("01-relaxed")
	studio.hud.subtitle.text = "Hold · a short inhale, then stillness"
	Input.action_press("hold_breath")
	await frames(8)
	await capture("02-inhale")
	await frames(84)
	await capture("03-holding")
	studio.hud.subtitle.text = "Release early · a controlled exhale"
	Input.action_release("hold_breath")
	await frames(12)
	await capture("04-controlled-release")
	await frames(65)
	studio.reset_studio_breath(25.0, 0.0)
	studio.hud.subtitle.text = "Low air · tension grows with the remaining breath"
	Input.action_press("hold_breath")
	await frames(35)
	await capture("05-strain")
	await frames(44)
	studio.hud.subtitle.text = "Forced gasp · two seconds to recover"
	await capture("06-gasp")
	await frames(55)
	await capture("07-recovery")
	await frames(90)
	studio.hud.subtitle.text = "Release Space to take the next breath"
	await capture("08-rearm")
	await frames(50)
	Input.action_release("hold_breath")
	studio.reset_studio_breath()
	studio.hud.subtitle.text = "Walk quietly · keep the grip and footsteps grounded"
	Input.action_press("hold_breath")
	Input.action_press("move_right")
	await frames(85)
	await capture("09-held-walk")
	Input.action_release("move_right")
	Input.action_release("hold_breath")
	await frames(55)
	studio.set_studio_area(1)
	studio.set_equipped(false)
	studio.hud.subtitle.text = "The same feedback works before flashlight pickup"
	Input.action_press("hold_breath")
	await frames(75)
	await capture("10-unequipped")
	Input.action_release("hold_breath")
	await frames(40)
	studio.queue_free()
	await frames(4)
	get_tree().quit()
