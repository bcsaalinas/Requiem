extends Node
## The Director (headless): it chooses the entity's patrol markers by where Viv is, and that
## is all it does. It prefers the next room to hers, never sends it at her, backs it off once
## it has pressed her long enough, brings it back after a quiet stretch, and never tells it
## anything. Checked in the real house, then switched on by the Hacienda.

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var director: EntityDirector
var listens := 0
var states := 0
## Viv stands in the kitchen. The route, by walking distance from her through the doorways:
## marker 1 beside her (the no-go), 2 and 3 in the next room (the band, 8 to 16 u), and
## 4, 5 and 6 two rooms away (far, 20 u or more).
var viv := Vector2.ZERO
var route: Array[Vector2] = []
const BESIDE := 0
const BAND := [1, 2]
const FAR := [3, 4, 5]


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func _ready() -> void:
	await set_up()
	check_drift_in()
	check_no_go()
	check_pressure_and_back_off()
	check_quiet_limit()
	await check_redirect()
	await check_stops_mid_way()
	check_it_never_tells()
	await check_zones()
	game.queue_free()
	await frames(3)
	print("[Entity director tests] %d/%d passed" % [checks - failures.size(), checks])
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)


func set_up() -> void:
	GameState.reset()
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	director = entity.director
	check(director != null and director.get_parent() == entity, "The entity has its Director")
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	check(not director.enabled and not entity.is_directed() and is_zero_approx(entity.patrol_stop_chance),
		"In the first house the Director is off and it never stops mid-way")
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	entity.listen_started.connect(func() -> void: listens += 1)
	entity.state_changed.connect(func(_from: int, _to: int) -> void: states += 1)
	viv = game.world.marker("house", "Patrol3")
	route = [viv + Vector2.RIGHT * Units.to_px(2.0), game.world.marker("house", "Patrol5"), game.world.marker("house", "Patrol2"),
		game.world.marker("house", "Patrol1"), game.world.marker("house", "Patrol4"), game.world.marker("house", "EntitySpawn")]
	game.player.global_position = viv
	director.enabled = true
	director.reset()


func walk_u(index: int) -> float:
	return director._walk_u(route[index], viv)


func chosen(counts: Array[int], indices: Array) -> int:
	var total := 0
	for index: int in indices:
		total += counts[index]
	return total


## How often each marker is chosen over `turns` choices that start from marker `from`.
func tally(from: int, turns := 400) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(route.size())
	counts.fill(0)
	for turn in turns:
		counts[director.pick(route, from)] += 1
	return counts


func check_drift_in() -> void:
	var walks: Array = range(route.size()).map(func(index: int) -> float: return snappedf(walk_u(index), 0.1))
	check(Units.to_u(route[BESIDE].distance_to(viv)) < director.no_go_u, "Marker 1 is beside her, inside the no-go")
	check(BAND.all(func(index: int) -> bool: return walk_u(index) >= director.near_band_u.x and walk_u(index) <= director.near_band_u.y),
		"Markers 2 and 3 are in the next room: 8 to 16 u from her through the doorway (%s)" % [walks])
	check(FAR.all(func(index: int) -> bool: return walk_u(index) >= director.far_u),
		"Markers 4, 5 and 6 are two rooms away: 20 u or more by foot (%s)" % [walks])
	# Either side of the kitchen wall, 3.75 u apart in a straight line.
	var doorway: Vector2 = (game.world.interactables["kitchen_door"]["node"] as Door).get_noise_origin()
	var round_the_wall: float = director._walk_u(doorway + Vector2(-60, -212), doorway + Vector2(60, -212))
	check(round_the_wall > 3.75 * 2.0, "Distance is by foot, through the doorways: 3.75 u through a wall is %.1f u to walk" % round_the_wall)
	var counts := tally(5)
	var in_band := chosen(counts, BAND)
	check(in_band >= 300, "From far away, 3 choices in 4 or more are a marker of the band, 8 to 16 u from her (%d of 400: %s)" % [in_band, counts])
	check(counts[1] > 40 and counts[2] > 40, "And not always the same one (%s)" % [counts])
	check(counts[5] == 0, "It is never handed the marker it already stands at")
	check(director.last_pick.mode == "drift in" and int(director.last_pick.index) < route.size(), "The choice says why it was made (%s)" % [director.last_pick])
	var again := true
	var last := 5
	for turn in 200:
		var next := director.pick(route, last)
		again = again and next != last
		last = next
	check(again, "Walking the route for 200 legs, never the same marker twice in a row")


func check_no_go() -> void:
	var counts := tally(5, 600)
	check(counts[0] == 0, "A marker within %.0f u of Viv is never chosen (the one 2 u from her: %d of 600)" % [director.no_go_u, counts[0]])
	# Even when it is the only way to be in the band.
	var close: Array[Vector2] = [viv + Vector2.RIGHT * Units.to_px(3.0), route[4], route[5]]
	var sent_at_her := 0
	for turn in 200:
		sent_at_her += int(director.pick(close, 2) == 0)
	check(sent_at_her == 0, "Not even when every other marker is far outside the band")
	# With nothing else to choose from, it gets the one furthest from her.
	var crowded: Array[Vector2] = [viv + Vector2.RIGHT * Units.to_px(1.0), viv + Vector2.RIGHT * Units.to_px(4.0), viv + Vector2.RIGHT * Units.to_px(2.0)]
	check(director.pick(crowded, 0) == 1, "If every marker is inside the no-go, it is sent to the one furthest from her")


func check_pressure_and_back_off() -> void:
	director.reset()
	var events: Array[String] = []
	var on_back := func() -> void: events.append("back off")
	var on_return := func() -> void: events.append("returned")
	director.backed_off.connect(on_back)
	director.returned.connect(on_return)
	# Far from her and unaware: nothing builds.
	for tick in 600:
		director.advance(0.1, 0.0, 30.0, true)
	check(is_zero_approx(director.pressure) and not director.is_backing_off(), "A minute far from her builds no pressure")
	# Beside her.
	var seconds := 0.0
	while not director.is_backing_off() and seconds < 60.0:
		director.advance(0.1, 1.0, 3.0, true)
		seconds += 0.1
	check(absf(seconds - director.pressure_fill_time) < 0.3 and events == ["back off"],
		"%.0f s on top of her fill the pressure, and it backs off (%.1f s)" % [director.pressure_fill_time, seconds])
	check(director.backing_off >= director.back_off_range.x and director.backing_off <= director.back_off_range.y,
		"For %.0f to %.0f s of patrol (%.1f s)" % [director.back_off_range.x, director.back_off_range.y, director.backing_off])
	# While it backs off, the far markers.
	var counts := tally(0)
	check(chosen(counts, FAR) == 400 and FAR.all(func(index: int) -> bool: return counts[index] > 40),
		"While it backs off it is sent to the markers %.0f u or more from her (%s)" % [director.far_u, counts])
	check(director.last_pick.mode == "back off", "And the choice says so")
	# A hunt does not use the back-off up: only patrol does.
	var left := director.backing_off
	for tick in 300:
		director.advance(0.1, 1.0, 3.0, false)
	check(is_equal_approx(director.backing_off, left), "Time it spends hunting or searching is not time away: the back-off waits")
	seconds = 0.0
	while director.is_backing_off() and seconds < 60.0:
		director.advance(0.1, 0.0, 25.0, true)
		seconds += 0.1
	check(not director.is_backing_off() and absf(seconds - left) < 0.3 and events == ["back off", "returned"],
		"After that time on patrol it comes back")
	check(is_equal_approx(director.pressure, director.pressure_after_back_off), "With the pressure starting again at %.1f" % director.pressure_after_back_off)
	check(chosen(tally(5), BAND) >= 250, "And it drifts in again")
	# What counts as close: what she hears of it, what it knows, or a little for hovering unheard.
	check(is_equal_approx(director.closeness(0.8, 0.0, 6.0), 0.8) and is_equal_approx(director.closeness(0.0, 0.7, 30.0), 0.7),
		"How near it sounds and how alert it is both press her, whichever is more")
	check(is_equal_approx(director.closeness(0.0, 0.0, 12.0), director.near_pressure) and director.near_pressure > 0.0 and director.near_pressure < 0.5,
		"Circling her unheard within %.0f u still counts a little (%.2f)" % [director.quiet_range_u, director.near_pressure])
	check(is_zero_approx(director.closeness(0.0, 0.0, 30.0)), "Far away and unaware counts for nothing")
	# Half as close fills half as fast; an empty house drains it.
	director.reset()
	for tick in 250:
		director.advance(0.1, 0.5, 8.0, true)
	check(absf(director.pressure - 0.5) < 0.02, "A room away it fills more slowly (%.2f after 25 s at half)" % director.pressure)
	for tick in 300:
		director.advance(0.1, 0.0, 25.0, true)
	check(is_zero_approx(director.pressure), "And an empty stretch drains it again")
	director.backed_off.disconnect(on_back)
	director.returned.disconnect(on_return)


func check_quiet_limit() -> void:
	director.reset()
	director.jitter_u = 40.0          # so much randomness that the band means nothing
	var loose := tally(5)
	check(chosen(loose, FAR) > 20, "(with this much randomness it wanders off: %s)" % [loose])
	check(not director.is_quiet_too_long(), "It has not been away long yet")
	for tick in int(director.quiet_limit_range.y * 10.0) + 5:
		director.advance(0.1, 0.0, 25.0, true)
	check(director.is_quiet_too_long(), "After %.0f s further than %.0f u from her it has been away too long" % [director.quiet_limit_range.y, director.quiet_range_u])
	var counts := tally(5)
	check(chosen(counts, BAND) == 400 and director.last_pick.mode == "quiet limit",
		"Then the next marker is one of the band, whatever the randomness (%s)" % [counts])
	check(counts[0] == 0, "Still never the one beside her")
	director.advance(0.1, 0.0, 12.0, true)
	check(not director.is_quiet_too_long() and is_zero_approx(director.quiet_for), "Once it has been near her the count starts over")
	director.jitter_u = 4.0


## When a back-off begins on patrol, the marker it was walking to is dropped at once.
func check_redirect() -> void:
	director.reset()
	entity.reset_encounter(route[5], route)
	entity.show()
	entity.active = true
	entity.revisit_chance = 0.0
	entity.route_index = 2                     # walking toward a marker of the band
	entity._patrol_wait = 999.0
	await frames(2)
	director.reset()                           # reset_encounter() did; the frames in between ticked it
	listens = 0
	states = 0
	director.pressure = 0.999
	director.advance(0.5, 1.0, 3.0, true)
	check(director.is_backing_off() and FAR.has(entity.route_index), "The back-off turns it round at once: now marker %d, far from her" % (entity.route_index + 1))
	check(listens == 0 and states == 0 and entity.get_state_name() == "PATROL", "Without a click or a change of state: it is still only patrolling")
	# Not while it is doing anything else.
	entity.route_index = 2
	entity._change_state(entity.State.SEARCH)
	entity.redirect_patrol()
	check(entity.route_index == 2, "It is never redirected while it searches")
	entity.reset_encounter(route[5], route)
	entity.revisit_chance = 0.35


func check_stops_mid_way() -> void:
	entity.reset_encounter(route[5], route)
	entity.show()
	entity.active = true
	entity.route_index = 0
	entity._patrol_wait = 0.0
	entity.patrol_stop_chance = 0.0
	listens = 0
	var stopped := 0
	for tick in 120:
		await frames(1)
		stopped += int(entity._patrol_wait > 0.0)
	check(stopped == 0 and entity.velocity.length() > 1.0, "With no chance of it, it never stops between two markers")
	entity.patrol_stop_chance = 1000.0
	await frames(3)
	check(entity._patrol_wait > 0.0 and entity._patrol_wait <= entity.patrol_stop_range.y and is_zero_approx(entity.velocity.length()),
		"With the chance, it stops mid-way for %.1f to %.1f s" % [entity.patrol_stop_range.x, entity.patrol_stop_range.y])
	check(listens == 0 and entity.get_state_name() == "PATROL" and not entity.is_listening(), "In silence: no click, it heard nothing")
	entity.reset_encounter(route[5], route)


## The contract: it reads where Viv is and hands back a marker. Nothing else.
func check_it_never_tells() -> void:
	entity.reset_encounter(route[5], route)
	entity.show()
	entity.active = true
	var before: Vector2 = entity.last_heard_position
	listens = 0
	states = 0
	for turn in 500:
		var index := director.pick(route, turn % route.size())
		if index < 0 or index >= route.size():
			check(false, "A choice is always an index into the route (%d)" % index)
			break
		director.advance(0.1, randf(), randf_range(0.0, 40.0), true)
	check(entity.last_heard_position == before and listens == 0 and states == 0 and entity.last_judgement.is_empty()
		and entity.last_heard_source == -1, "500 choices and 50 s of pressure later the entity has heard nothing and knows nothing new")
	# And it has no way to: nothing in the script names anything the entity knows or does about a sound.
	var source := FileAccess.get_file_as_string("res://entities/entity_director.gd")
	var code := ""
	for line in source.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	var forbidden: Array[String] = []
	for word: String in ["last_heard", "check_target", "_start_hunt", "_start_investigate", "_begin_listen", "notice(", "emit_noise", "_react", "_judge", "_inbox", "global_position ="]:
		if code.contains(word):
			forbidden.append(word)
	check(source.length() > 1000 and forbidden.is_empty(), "The Director's code touches nothing the entity knows or does about a sound (%s)" % [forbidden])
	entity.reset_encounter(route[5], route)
	entity.active = false
	entity.hide()


## The Hacienda switches it on, with the stops mid-way; the first house switches it off again.
func check_zones() -> void:
	director.enabled = false
	game.enter_zone("mansion_ground", Vector2.INF, false)
	await frames(4)
	check(director.enabled and entity.patrol_stop_chance > 0.0 and entity.is_directed(),
		"In the Hacienda the Director is on and it stops mid-way now and then (%.2f per second)" % entity.patrol_stop_chance)
	check(is_zero_approx(director.pressure) and not director.is_backing_off(), "Arriving there starts with no pressure")
	var points: Array[Vector2] = entity.route
	var at: Vector2 = game.player.global_position
	var too_close := 0
	for turn in 300:
		var index := director.pick(points, turn % points.size())
		too_close += int(Units.to_u(points[index].distance_to(at)) < director.no_go_u)
	var escape := points.any(func(point: Vector2) -> bool: return Units.to_u(point.distance_to(at)) >= director.no_go_u)
	check(points.size() >= 4 and (too_close == 0 or not escape), "On its real route there, 300 choices never send it within %.0f u of where she stands" % director.no_go_u)
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	check(not director.enabled and is_zero_approx(entity.patrol_stop_chance), "Back in the first house both are off again")
