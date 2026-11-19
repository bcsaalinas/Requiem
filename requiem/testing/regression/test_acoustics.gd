extends Node
## Acoustics (headless): how far the entity's sound travels to Viv in the real house.
## Through a doorway it is the straight line; behind a wall it is mostly the walking path, so
## an entity two units away through the wall is a room away by ear. Measured a few times per
## second, never every frame, and nothing here makes noise.

## The house: three rooms in a row (kitchen, vestibule, altar room), divided by two walls with
## one doorway each. Positions are relative to the house zone, in pixels.
## Either side of the kitchen/vestibule wall, far above its doorway: 2 u apart.
const KITCHEN_BY_WALL := Vector2(368, 176)
const VESTIBULE_BY_WALL := Vector2(432, 176)
## Either side of the kitchen table, in the same room.
const KITCHEN_WEST := Vector2(176, 256)
const KITCHEN_EAST := Vector2(368, 256)
## The same room, nothing between them.
const VESTIBULE_A := Vector2(520, 400)
const VESTIBULE_B := Vector2(680, 400)

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var settings: SoundSettings
var house := Vector2.ZERO
var noises := 0
var measurements := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func _ready() -> void:
	settings = SoundSettings.current()
	check_settings()
	check_rings()
	await set_up()
	await check_house()
	await check_opening()
	await check_cache()
	check(noises == 0, "Measuring made no noise the entity could hear (%d)" % noises)
	game.queue_free()
	await frames(3)
	print("[Acoustics tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func check_settings() -> void:
	check(settings.ring_on_top_u == 4.0 and settings.ring_near_u == 9.0 and settings.ring_somewhere_u == 18.0,
		"The rings end at 4, 9 and 18 units")
	check(settings.ring_on_top_u < settings.ring_near_u and settings.ring_near_u < settings.ring_somewhere_u,
		"Each ring is wider than the one inside it")
	check(settings.acoustics_rate == 5.0, "The entity is measured 5 times per second")
	check(is_equal_approx(settings.acoustics_path_weight, 0.7), "Behind a wall the sound follows the path for 0.7 of the way")
	check(settings.acoustics_wall_mask == 1, "Walls are on physics layer 1")
	var source := FileAccess.get_file_as_string("res://audio/acoustics.gd")
	check(not source.contains("NoiseManager") and not source.contains("volume_db") and not source.contains(".play("),
		"Acoustics only measures: no noise, no sound, no mix")
	check(not source.contains("func _process("), "It does not work every frame")


func check_rings() -> void:
	check(Acoustics.ring_for(0.0) == 3 and Acoustics.ring_for(3.9) == 3, "Under 4 u is ring 3, on top of you")
	check(Acoustics.ring_for(4.0) == 2 and Acoustics.ring_for(8.9) == 2, "Under 9 u is ring 2, near")
	check(Acoustics.ring_for(9.0) == 1 and Acoustics.ring_for(17.9) == 1, "Under 18 u is ring 1, somewhere")
	check(Acoustics.ring_for(18.0) == 0 and Acoustics.ring_for(400.0) == 0, "Beyond that is ring 0, gone")
	check(Acoustics.clarity_for(0.0) == 1.0 and Acoustics.clarity_for(settings.clarity_full_u) == 1.0,
		"Up close every detail is heard")
	var half: float = Acoustics.clarity_for((settings.clarity_full_u + settings.ring_somewhere_u) * 0.5)
	check(is_equal_approx(half, 0.5), "Clarity falls evenly with distance (%.2f halfway)" % half)
	check(Acoustics.clarity_for(settings.ring_somewhere_u) == 0.0 and Acoustics.clarity_for(99.0) == 0.0,
		"Where ring 1 ends nothing of it is left")
	var steady := true
	var last := 1.0
	for step in range(0, 60):
		var clarity: float = Acoustics.clarity_for(step * 0.5)
		steady = steady and clarity <= last and clarity >= 0.0 and clarity <= 1.0
		last = clarity
	check(steady, "Clarity never rises with distance and stays between 0 and 1")
	var nothing := Acoustics.reading(null)
	check(not nothing.valid and nothing.ring == 0 and nothing.clarity == 0.0, "With nothing to measure the reading is ring 0")


func set_up() -> void:
	GameState.reset()
	NoiseManager.noise_emitted.connect(func(_at: Vector2, _radius: float, _source: int, _duration: float) -> void: noises += 1)
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	house = game.world.zones["house"].global_position
	# Nobody moves or makes a sound here: both are placed by hand.
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	var route: Array[Vector2] = [house + VESTIBULE_A]
	entity.reset_encounter(house + VESTIBULE_A, route)
	entity.show()
	entity.set_physics_process(false)
	Acoustics.measured.connect(func(emitter: Node2D, _reading: AcousticReading) -> void:
		if emitter == entity: measurements += 1)
	noises = 0


## Puts the entity and Viv in place and measures at once.
func place(entity_at: Vector2, viv_at: Vector2) -> AcousticReading:
	entity.global_position = house + entity_at
	game.player.global_position = house + viv_at
	# Moved bodies reach the physics space on the next physics frame.
	await frames(2)
	return Acoustics.measure(entity)


func check_house() -> void:
	check(Acoustics.listener() != null and Acoustics.listener().global_position.distance_to(game.player.global_position) < 1.0,
		"Sound is heard from where Viv stands")
	# The same room.
	var open := await place(VESTIBULE_A, VESTIBULE_B)
	check(open.valid and not open.blocked and is_equal_approx(open.straight_u, 5.0), "In the same room nothing is in the way (%.1f u)" % open.straight_u)
	check(is_equal_approx(open.acoustic_u, open.straight_u) and open.ring == 2 and open.clarity > 0.9,
		"So its sound travels the straight line: ring 2, near")
	check(open.path_u >= open.straight_u - 0.01 and open.path_u < open.straight_u + 1.0, "The walking path is about as long (%.1f u)" % open.path_u)
	# The kitchen table is furniture, not a wall.
	var table := await place(KITCHEN_WEST, KITCHEN_EAST)
	check(not table.blocked and is_equal_approx(table.acoustic_u, table.straight_u), "Furniture between them is not a wall")
	# Close through the wall, far by the doorway.
	var wall := await place(KITCHEN_BY_WALL, VESTIBULE_BY_WALL)
	check(wall.blocked and is_equal_approx(wall.straight_u, 2.0), "Two units apart, with the wall between them")
	check(wall.path_u > 12.0, "The way round, through the doorway, is far (%.1f u)" % wall.path_u)
	var expected: float = lerpf(wall.straight_u, wall.path_u, settings.acoustics_path_weight)
	check(is_equal_approx(wall.acoustic_u, expected), "Its sound travels 0.7 of the way along the path (%.1f u)" % wall.acoustic_u)
	check(Acoustics.ring_for(wall.straight_u) == 3 and wall.ring == 1 and wall.clarity < 0.6,
		"On top of her in a straight line, it is only somewhere by ear (ring %d, clarity %.2f)" % [wall.ring, wall.clarity])
	var mirrored := await place(VESTIBULE_BY_WALL, KITCHEN_BY_WALL)
	check(mirrored.blocked and absf(mirrored.acoustic_u - wall.acoustic_u) < 0.5, "The same from the other side")
	# Standing in the doorway line: the wall no longer blocks.
	var doorway := await place(Vector2(360, 480), Vector2(520, 480))
	check(not doorway.blocked and doorway.ring == 2, "Through the open doorway it is near again (%.1f u)" % doorway.acoustic_u)
	# A room and a half away, and the far end of the house.
	var away := await place(game.world.marker("house", "Patrol1") - house, game.world.marker("house", "Patrol5") - house)
	check(away.ring == 1 and away.clarity < 0.3, "From the altar room to the vestibule it is somewhere (%.1f u)" % away.acoustic_u)
	var far := await place(game.world.marker("house", "Patrol4") - house, game.world.marker("house", "Patrol3") - house)
	check(far.ring == 0 and far.clarity == 0.0 and far.blocked, "From one end of the house to the other it is gone (%.1f u)" % far.acoustic_u)
	# Outside the walkable floor (the porch): still measured, the steps to the floor count.
	var porch := await place(KITCHEN_BY_WALL, game.world.marker("house", "SpawnFromForest") - house)
	check(porch.valid and porch.blocked and porch.acoustic_u > porch.straight_u, "From the porch the front wall is in the way (%.1f u for %.1f)" % [porch.acoustic_u, porch.straight_u])
	# Hidden: nothing to hear.
	entity.hide()
	var hidden := Acoustics.measure(entity)
	check(not hidden.valid and hidden.ring == 0, "An entity that is not shown is ring 0")
	entity.show()


## Behind a wall its sound comes round through an opening: where it is heard from, as far as
## direction goes, is the first point of the walking path (counting from Viv) she can see.
func check_opening() -> void:
	check(settings.doorway_panning and is_equal_approx(settings.doorway_min_u, 0.75), "Behind a wall it is heard from the doorway (points under 0.75 u from her give no direction)")
	var open := await place(VESTIBULE_A, VESTIBULE_B)
	check(not open.through_opening and open.heard_from == open.emitter_at, "With nothing in the way it is heard from where it is")
	for pair: Array in [[KITCHEN_BY_WALL, VESTIBULE_BY_WALL], [VESTIBULE_BY_WALL, KITCHEN_BY_WALL]]:
		var wall := await place(pair[0], pair[1])
		var space: World2D = entity.get_world_2d()
		var nearest: float = Units.to_px(settings.doorway_min_u)
		check(wall.blocked and wall.through_opening and wall.path.has(wall.heard_from),
			"Through the wall it is heard from a point of the walking path (%s, path %s)" % [wall.heard_from - house, wall.path])
		check(not Acoustics._wall_between(wall.heard_from, wall.listener_at, space, []) and wall.heard_from.distance_to(wall.listener_at) >= nearest
			and wall.heard_from.distance_to(wall.emitter_at) > nearest,
			"A point she has a clear line to, not under her feet and not where it stands (%.1f u from her)" % Units.to_u(wall.heard_from.distance_to(wall.listener_at)))
		var first := true
		for index in range(wall.path.size() - 1, wall.path.find(wall.heard_from), -1):
			var point: Vector2 = wall.path[index]
			first = first and (point.distance_to(wall.listener_at) < nearest or Acoustics._wall_between(point, wall.listener_at, space, []))
		check(first, "It is the first such point counting from her")
		print("[Acoustics tests] opening for %s -> %s: %s, path %s" % [pair[0], pair[1], wall.heard_from - house, Array(wall.path).map(func(p: Vector2) -> Vector2: return p - house)])
	# A made-up case: a wall in the way and no path at all.
	var lost := Acoustics.measure_between(house + KITCHEN_BY_WALL, house + VESTIBULE_BY_WALL, entity.get_world_2d(), RID())
	check(lost.blocked and lost.path.is_empty() and not lost.through_opening and lost.heard_from == lost.emitter_at,
		"With no way round, it is heard from where it is")
	# Furniture is not a wall: no opening needed.
	var table := await place(KITCHEN_WEST, KITCHEN_EAST)
	check(not table.through_opening and table.heard_from == table.emitter_at, "Across the table it is heard from where it is")


func check_cache() -> void:
	await place(VESTIBULE_A, VESTIBULE_B)
	await seconds(0.3)
	var held := Acoustics.reading(entity)
	check(held.valid and held.ring == 2 and not held.blocked, "The entity reports itself: its last measurement is kept")
	measurements = 0
	var same := true
	for tick in 120:
		await get_tree().physics_frame
		# Between two measurements the kept reading is the same object: nothing is recomputed.
		if measurements == 0:
			same = same and Acoustics.reading(entity) == held
	check(measurements >= 8 and measurements <= 12, "It is measured 5 times per second, not every frame (%d in 2 s)" % measurements)
	check(same, "Between measurements the same reading is handed out")
	# The reading follows the entity as it moves through the wall line.
	entity.global_position = house + KITCHEN_BY_WALL
	game.player.global_position = house + VESTIBULE_BY_WALL
	await seconds(0.5)
	var moved := Acoustics.reading(entity)
	check(moved.blocked and moved.ring == 1, "And the kept reading follows it within a moment (ring %d)" % moved.ring)
	check(Acoustics.nearest_ring() == 1, "The nearest ring is the entity's")
	entity.hide()
	await seconds(0.5)
	check(Acoustics.reading(entity).ring == 0 and Acoustics.nearest_ring() == 0, "Hidden, it is gone by ear")
	entity.show()
