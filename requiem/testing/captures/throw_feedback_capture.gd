extends Node
## Run with a rendered viewport; --write-movie may record the same real-input take.
## Review output belongs outside tracked assets, under user://test-results/throw/.
const CaptureOutput := preload("res://testing/tools/capture_output.gd")
var studio: Node2D


func frames(count: int) -> void:
	for index in range(count): await get_tree().physics_frame
	await get_tree().process_frame


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(CaptureOutput.path("throw/%s.png" % label))
	if error != OK: push_error("Could not save throw capture: " + label)


func aim_at(offset: Vector2) -> void:
	studio.player.get_node("PlayerAim").set_target(studio.player.global_position + offset)


func press_throw() -> void:
	Input.action_press("throw")
	await frames(1)
	Input.action_release("throw")


func capture_release(label: String) -> void:
	# Physics-frame waits can resume before this frame's mechanic update. The
	# accepted release signal is the source of truth for the labeled still.
	if studio.thrower.is_throwing:
		await studio.thrower.object_released
	await get_tree().process_frame
	await capture(label)


func _ready() -> void:
	studio = preload("res://testing/experiments/throw_studio.tscn").instantiate()
	add_child(studio)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	# Keep evidence dimensions stable if the desktop resizes the native window.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await frames(15)
	studio.set_studio_area(1)
	studio.set_equipment_mode(2)
	aim_at(Vector2(240, -80))
	studio.hud.subtitle.text = "THROW · Prepare, release, settle"
	await frames(65)
	await capture("01-ready-flashlight-on")
	await press_throw()
	await frames(10)
	await capture("02-anticipation")
	await frames(14)
	await capture("03-forward-swing")
	await capture_release("04-release")
	await frames(12)
	await capture("05-follow-through")
	await frames(60)
	await capture("06-settled")

	studio.set_equipment_mode(0)
	aim_at(Vector2(-230, -70))
	studio.hud.subtitle.text = "Empty hands · same throw, same timing"
	await frames(35)
	await press_throw()
	await frames(16)
	await capture("07-empty-hand-windup")
	await capture_release("08-empty-hand-release")
	await frames(70)

	studio.set_studio_area(0)
	studio.set_equipment_mode(1)
	aim_at(Vector2(290, 15))
	studio.hud.subtitle.text = "Move quietly · throw with the flashlight off"
	Input.action_press("hold_breath")
	Input.action_press("move_right")
	await frames(35)
	await press_throw()
	await frames(18)
	await capture("09-moving-held-breath-windup")
	await capture_release("10-moving-flashlight-off-release")
	await frames(35)
	Input.action_release("move_right")
	Input.action_release("hold_breath")
	await frames(80)
	await capture("11-return-to-breath-and-idle")
	for action_name in ["throw", "hold_breath", "move_right"]:
		Input.action_release(action_name)
	studio.queue_free()
	await frames(4)
	get_tree().quit()
