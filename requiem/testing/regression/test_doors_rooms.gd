extends Node
## Doors, room covers and the new noise rules (headless).
var failures: Array[String] = []
var checks := 0
var noises: Array[Dictionary] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame

func _ready() -> void:
	NoiseManager.noise_emitted.connect(func(at: Vector2, radius: float, source: int, _duration: float):
		noises.append({"at": at, "radius": radius, "source": source}))
	await check_tap_walking()
	var game: Node2D = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	await check_doors(game)
	await check_rooms(game)
	check_parent_hearing(game)
	game.queue_free()
	await frames(3)
	print("[Door and room tests] ",checks-failures.size(),"/",checks," passed")
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

## Tapping the movement keys must not slip past a listener without a footfall.
func check_tap_walking() -> void:
	var player: CharacterBody2D = preload("res://player/player.tscn").instantiate()
	add_child(player)
	player.get_node("Camera2D").enabled = false
	player.get_node("FootstepNoise").walk_clips.clear()
	await frames(3)
	noises.clear()
	for tap in range(4):
		Input.action_press("move_right")
		await frames(9)
		Input.action_release("move_right")
		await frames(20)
	var steps := noises.filter(func(n): return n.source == NoiseManager.SourceType.FOOTSTEP)
	check(steps.size() >= 3, "Four short taps make footfall noise (got %d)" % steps.size())
	check(steps.all(func(n): return is_equal_approx(n.radius, 96.0)), "Tapped footfalls keep the walking radius")
	noises.clear()
	await frames(45)
	check(noises.is_empty(), "Standing still makes no noise")
	# Letting the breath go as she stops keeps the held stretch quiet (found in play-testing).
	Input.action_press("hold_breath")
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	Input.action_release("hold_breath")
	await frames(40)
	check(noises.any(func(n): return n.source == NoiseManager.SourceType.CROUCH)
		and not noises.any(func(n): return n.source in [NoiseManager.SourceType.FOOTSTEP, NoiseManager.SourceType.SPRINT]),
		"Releasing the breath while stopping plants a held step, not a full footfall")
	player.queue_free()
	await frames(2)

func check_doors(game: Node2D) -> void:
	var door: Door = game.world.interactables["kitchen_door"]["node"]
	var blocker: CollisionShape2D = door.get_node("Blocker/Shape")
	var occluder: LightOccluder2D = door.get_node("Occluder")
	check(not door.is_open and not blocker.disabled and occluder.visible, "A closed door blocks bodies and light")
	noises.clear()
	check(door.open(), "An unlocked door opens")
	await frames(2)
	check(door.is_open and blocker.disabled and not occluder.visible, "Opening frees the doorway for bodies and light at once")
	check(noises.size() == 1 and noises[0].source == NoiseManager.SourceType.DOOR and is_equal_approx(noises[0].radius, 80.0),
		"Opening a door creaks at 2.5 u")
	noises.clear()
	door.close(true)
	await frames(2)
	check(not door.is_open and not blocker.disabled and occluder.visible, "Closing restores blocker and occluder together")
	check(noises.size() == 1 and is_equal_approx(noises[0].radius, 32.0), "Easing a door shut while holding breath creaks at 1 u")
	var front: Door = game.world.interactables["front_door"]["node"]
	check(front.locked and not front.open(), "A locked door refuses to open")
	# The entity pushes doors open when it reaches them.
	var walker := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(20, 20)
	walker.add_child(shape)
	walker.add_to_group("entity")
	walker.collision_mask = 0
	game.world.add_child(walker)
	walker.global_position = door.get_noise_origin() + Vector2(-60, 0)
	await frames(3)
	walker.global_position = door.get_noise_origin() + Vector2(-26, 0)
	await frames(4)
	check(door.is_open, "The entity opens a closed door it walks into")
	check(not door.close(), "A door cannot shut on a body standing in its doorway")
	walker.queue_free()
	await frames(3)
	door.snap(false)

## Interiors stay hidden from outside until the player enters or an open door joins the rooms.
func check_rooms(game: Node2D) -> void:
	game.enter_zone("house")
	var rooms: RoomVisibility = game.world.rooms("house")
	var vestibule: Room = rooms.get_node("Vestibule")
	var kitchen: Room = rooms.get_node("Kitchen")
	var front: Door = game.world.interactables["front_door"]["node"]
	check(rooms.current != null and rooms.current.name == "Porch", "The player starts on the porch")
	check(not vestibule.revealed and not kitchen.revealed, "From outside, the closed house shows no interior")
	front.snap(true)
	check(vestibule.revealed and not kitchen.revealed, "Opening the front door reveals only the room behind it")
	front.snap(false)
	check(not vestibule.revealed, "Shutting the door hides the room again")
	rooms.sync_to(vestibule.get_node("Shape").to_global(Vector2(600, 400)))
	check(vestibule.revealed and not kitchen.revealed, "Inside the vestibule the closed kitchen stays hidden")
	var kitchen_door: Door = game.world.interactables["kitchen_door"]["node"]
	kitchen_door.snap(true)
	check(kitchen.revealed, "An open inner door reveals the next room")
	kitchen_door.snap(false)
	check(not kitchen.revealed, "Closing the inner door hides it again")

## Parents hear a sound when its ring reaches the door's bottom edge.
func check_parent_hearing(game: Node2D) -> void:
	var listener: ParentListener = game._parent_listeners()[0]
	var far_side := listener.global_position + Vector2(40, 84)
	check(listener.hears(far_side, 96.0), "Walking along the far side of the corridor reaches the door")
	check(not listener.hears(far_side, 32.0), "Held footsteps on the far side do not")
	check(not listener.hears(listener.global_position + Vector2(140, 48), 96.0), "Footsteps well past the door are not heard")
