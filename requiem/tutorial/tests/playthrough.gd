extends Node
## Scripted QA playthrough: real movement/collisions and interactions; fixed mouse aim fixture.
## Run with -- --record to keep audio and save stage screenshots.
var game: Node2D
var recording:=false
var failed:=false

func _ready() -> void:
	recording=OS.get_cmdline_user_args().has("--record")
	if OS.get_cmdline_user_args().has("--background"):
		get_window().mode=Window.MODE_MINIMIZED
	game=preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode=not recording
	add_child(game)
	await wait(1)
	await dialogue()
	await move(Vector2(620,258))
	game.interact("flashlight")
	await wait(1)
	await move(Vector2(718,258))
	game.interact("battery")
	await capture("01-bedroom")
	await wait(1)
	await move(Vector2(830,460))
	game.interact("bedroom_exit")
	await wait(1)
	await move(Vector2(1830,340))
	await move(Vector2(2040,340),true)
	await move(Vector2(2110,340))
	await move(Vector2(2110,485))
	await capture("02-hallway")
	await wait(6)
	await move(Vector2(2110,340))
	await move(Vector2(2210,340))
	await move(Vector2(2420,340),true)
	await move(Vector2(2450,340))
	game.interact("hall_exit")
	await wait(2)
	# Save flashlight power while following the moonlit trail.
	game.flashlight.is_on=false
	game.flashlight._refresh_light()
	await move(Vector2(3580,540))
	await move(Vector2(3580,415))
	await move(Vector2(3580,350),true)
	await move(Vector2(3730,350),true)
	await move(Vector2(3730,450),true)
	Input.action_release("hold_breath")
	await wait(6)
	await move(Vector2(3860,450))
	game.interact("forest_rocks")
	game.interact("forest_battery")
	await capture("03-forest")
	await wait(2)
	await move(Vector2(4000,500))
	await move(Vector2(4030,540))
	await move(Vector2(4460,540))
	game.interact("forest_exit")
	await wait(2)
	await move(Vector2(5737,765))
	game.interact("front_door")
	await wait(3)
	await move(Vector2(5870,800))
	game.interact("window")
	await wait(2)
	# The native OS pointer is not deterministic in a movie/headless run.
	# Physics verifies the same target used by a player aiming at the window.
	var query:=PhysicsRayQueryParameters2D.create(game.player.position,Vector2(5870,608),1)
	query.exclude=[game.player.get_rid()]
	var hit: Dictionary=game.player.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider!=game.world.window_body:
		abort("Window aim is obstructed")
		return
	game.thrower._start_throw()
	game.thrower._pending_landing=hit.position+Vector2(0,4)
	await wait(1.3)
	await capture("04-window")
	await wait(3)
	await move(Vector2(5870,765))
	game.interact("window")
	await wait(1)
	await move(Vector2(5737,765))
	game.interact("front_door")
	await move(Vector2(5820,620))
	await move(Vector2(6000,620))
	await move(Vector2(6230,620))
	await move(Vector2(6230,455))
	await capture("05-altar")
	game.interact("friend")
	await dialogue()
	await wait(4.0)
	await capture("06-aftermath")
	await move(Vector2(6240,650))
	await move(Vector2(6160,650))
	await move(Vector2(5900,650),true)
	await move(Vector2(5780,640))
	game.interact("front_door")
	await wait(2)
	await move(Vector2(7510,365))
	await move(Vector2(7700,365),true)
	await move(Vector2(7700,490),true)
	Input.action_release("hold_breath")
	await wait(6)
	await move(Vector2(7700,370))
	await move(Vector2(7920,370),true)
	await move(Vector2(8025,340))
	game.interact("loop_end")
	await capture("07-impossible-room")
	await wait(5)
	if not game.complete:
		abort("Final interaction did not complete the tutorial")
		return
	print("[Playthrough] PASS — all five spaces traversed using player movement")
	game.queue_free()
	await wait(.1)
	get_tree().quit(0)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func dialogue() -> void:
	while not game.dialogue.is_empty():
		await wait(3.2 if recording else .1)
		game.advance_dialogue()

func move(target: Vector2, held:=false) -> void:
	if failed: return
	var expected_zone: String=game.zone
	var elapsed:=0.0
	if held: Input.action_press("hold_breath")
	else: Input.action_release("hold_breath")
	while game.player.position.distance_to(target)>6:
		if game.resetting or game.zone!=expected_zone:
			abort("Caught on route to %s from %s"%[target,game.player.position])
			return
		var direction: Vector2=(target-game.player.position).normalized()
		for pair in [["move_right",direction.x],["move_left",-direction.x],["move_down",direction.y],["move_up",-direction.y]]:
			if pair[1]>.15: Input.action_press(pair[0],pair[1])
			else: Input.action_release(pair[0])
		await get_tree().physics_frame
		elapsed+=1.0/60.0
		if elapsed>25:
			abort("Blocked on route to %s at %s"%[target,game.player.position])
			return
	for action in ["move_right","move_left","move_down","move_up"]: Input.action_release(action)
	# Holding stays active between consecutive held waypoints; release only on recovery.
	await get_tree().physics_frame

func capture(id: String) -> void:
	if not recording: return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/organic-tutorial/screenshots/"+id+".png")

func abort(message: String) -> void:
	failed=true
	push_error("[Playthrough] "+message)
	get_tree().quit(1)
