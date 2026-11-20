extends Node
## Where it is, by ear (headless): the rings applied to the entity's position sounds.
## In the same room every one of them is heard, sharp and exactly placed. A room away they
## are quieter, dulled, vaguely placed, and some are lost on the way. Further off there is
## nothing. What it knows (heard-you, scream) is never dulled, thinned out or cut off.
## How near it is also reaches the mood of the house (presence), late and smoothly: the
## world recedes a little, and the music ignores it.
## Behind a wall its position sounds come from the doorway the sound really travels through, at
## the distance the entity really is; what it knows is still heard from where it stands.

## Positions relative to the house zone, in pixels (see test_acoustics.gd for the rooms).
const VESTIBULE_A := Vector2(520, 400)
const VESTIBULE_NEXT := Vector2(552, 400)           # 1 u from A: on top of her
const VESTIBULE_B := Vector2(680, 400)              # 5 u from A, same room: near
const KITCHEN_BY_WALL := Vector2(368, 176)
const VESTIBULE_BY_WALL := Vector2(432, 176)        # 2 u apart, the wall between: somewhere
const ALTAR_BY_WALL := Vector2(848, 176)           # the altar room, reached through the other doorway
const BODY := "entity/claws_walk"
const TRIES := 400
## A made-up pair of rooms far from the house, one above the other: a wall across, with a
## doorway at its left end. The entity stands to Viv's right behind the wall; the doorway is to
## her left. (In the house every wall runs north-south, so a doorway is always on the entity's
## side of her.) Positions are relative to the arena, in pixels.
const ARENA := Vector2(-20000, -20000)
const ARENA_SIZE := Vector2(640, 640)
const ARENA_WALL_Y := 300.0
const ARENA_WALL_HALF := 10.0
const ARENA_DOOR := Vector2(160, 240)               # the doorway runs from x to x
const ARENA_AGENT_RADIUS := 8.0
const ARENA_VIV := Vector2(300, 330)
const ARENA_ENTITY := Vector2(460, 270)
## How far off the line to the opening Heard may lie (degrees), and how many dB the doorway's
## side of the Entity bus must be louder.
const ANGLE_TOLERANCE := 3.0
const SIDE_DB := 0.5

var failures: Array[String] = []
var checks := 0
var game: Node2D
var entity: CharacterBody2D
var audio: EntityAudio
var settings: SoundSettings
var house := Vector2.ZERO
var noises := 0
var lost := 0
var music_changes := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func seconds(time: float) -> void:
	await get_tree().create_timer(time).timeout


func near(a: float, b: float, tolerance := 0.05) -> bool:
	return absf(a - b) <= tolerance


func _ready() -> void:
	settings = SoundSettings.current()
	check_settings()
	check_curves()
	await set_up()
	await check_same_room()
	await check_a_room_away()
	await check_doorway()
	await check_doorway_steady()
	await check_far_away()
	await check_glide()
	await check_presence()
	await check_calm_trim()
	check(noises == 0, "None of it made a noise the entity could hear (%d)" % noises)
	game.queue_free()
	await frames(3)
	print("[Ring tests] %d/%d passed" % [checks - failures.size(), checks])
	await seconds(0.25)
	get_tree().quit(0 if failures.is_empty() else 1)


func check_settings() -> void:
	check(settings.gap_chance_body == Vector2(0.3, 0.7), "A room away a body sound gets through 3 to 7 times in 10")
	check(settings.gap_chance_voice.x > settings.gap_chance_body.x and settings.gap_chance_voice.y > settings.gap_chance_body.y
		and settings.gap_chance_voice.y <= 1.0, "Its voice gets through more often than its body")
	check(near(settings.far_panning, 0.35), "A room away it is placed about a third as exactly (%.2f)" % settings.far_panning)
	check(settings.presence_lag == Vector2(0.5, 2.0), "How near it is reaches the mood 0.5 to 2 s late")
	check(settings.position_edge_db < 0.0 and settings.position_full_u < settings.ring_on_top_u, "Its position sounds lose level with distance")
	var source := FileAccess.get_file_as_string("res://entities/entity_audio.gd")
	check(not source.contains("NoiseManager"), "The entity's sounds never make noise it could hear itself")
	check(not source.contains("entity_reach_u") and not source.contains("AudioServer"), "It sets no bus levels and uses no straight-line reach")
	var settings_source := FileAccess.get_file_as_string("res://audio/sound_settings.gd")
	check(not settings_source.contains("entity_reach_u") and not settings_source.contains("entity_falloff"), "The old straight-line reach settings are gone")


## The three curves, with nothing playing.
func check_curves() -> void:
	var limit: float = settings.ring_somewhere_u
	check(is_zero_approx(EntityAudio.position_db(0.0, limit)) and is_zero_approx(EntityAudio.position_db(settings.position_full_u, limit)),
		"Right beside her nothing is lost")
	var falling := true
	var last := 0.0
	for step in range(0, 80):
		var level: float = EntityAudio.position_db(step * 0.25, limit)
		falling = falling and level <= last + 0.0001
		last = level
	check(falling, "Further away is never louder")
	check(EntityAudio.position_db(settings.ring_near_u, limit) < -3.0 and EntityAudio.position_db(settings.ring_near_u, limit) > settings.position_edge_db,
		"Where the room ends it is clearly quieter, and still heard (%.1f dB)" % EntityAudio.position_db(settings.ring_near_u, limit))
	check(EntityAudio.position_db(limit - 0.01, limit) < EntityAudio.SILENT_DB + 1.0 and EntityAudio.position_db(limit, limit) <= EntityAudio.GONE_DB
		and EntityAudio.position_db(400.0, limit) <= EntityAudio.GONE_DB, "It fades to nothing where ring 1 ends, with no step")
	check(EntityAudio.position_panning(0.0, limit) == 1.0 and EntityAudio.position_panning(settings.ring_near_u, limit) == 1.0,
		"In rings 3 and 2 it is placed exactly")
	check(near(EntityAudio.position_panning(limit, limit), settings.far_panning, 0.001)
		and EntityAudio.position_panning((settings.ring_near_u + limit) * 0.5, limit) < 1.0
		and EntityAudio.position_panning((settings.ring_near_u + limit) * 0.5, limit) > settings.far_panning,
		"Across ring 1 its direction grows vague, never wrong")
	check(EntityAudio.chance_through(0.0, limit, false) == 1.0 and EntityAudio.chance_through(settings.ring_near_u - 0.01, limit, false) == 1.0
		and EntityAudio.chance_through(settings.ring_near_u - 0.01, limit, true) == 1.0, "In rings 3 and 2 nothing is lost on the way")
	var steady := true
	for step in range(0, 36):
		var at: float = settings.ring_near_u + step * 0.25
		var body: float = EntityAudio.chance_through(at, limit, false)
		var voice: float = EntityAudio.chance_through(at, limit, true)
		steady = steady and body >= settings.gap_chance_body.x - 0.001 and body <= settings.gap_chance_body.y + 0.001 and voice > body
	check(steady, "Anywhere in ring 1 a body sound has a 0.3 to 0.7 chance, and a voice sound a better one")
	check(EntityAudio.chance_through(limit, limit, false) == 0.0 and EntityAudio.chance_through(limit, limit, true) == 0.0,
		"Beyond ring 1 nothing gets through")


func set_up() -> void:
	GameState.reset()
	NoiseManager.noise_emitted.connect(func(_at: Vector2, _radius: float, _source: int, _duration: float) -> void: noises += 1)
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	add_child(game)
	await frames(5)
	game.dialogue.clear()
	entity = game.entity
	audio = entity.audio
	game.attack_finished = true
	game.enter_zone("house", Vector2.INF, false)
	await frames(3)
	house = game.world.zones["house"].global_position
	# Nobody moves or makes a sound here: both are placed by hand, and it stands breathing.
	game.player.process_mode = Node.PROCESS_MODE_DISABLED
	var route: Array[Vector2] = [house + VESTIBULE_A]
	entity.reset_encounter(house + VESTIBULE_A, route)
	entity.show()
	entity.set_physics_process(false)
	audio.lost_on_the_way.connect(func(_set_id: String) -> void: lost += 1)
	MusicDirector.music_state_changed.connect(func(_from: int, _to: int) -> void: music_changes += 1)
	noises = 0


## Puts the entity and Viv in place; it is heard from there at once.
func place(entity_at: Vector2, viv_at: Vector2) -> void:
	await place_at(house + entity_at, house + viv_at)


## The same in world pixels.
func place_at(entity_at: Vector2, viv_at: Vector2) -> void:
	entity.global_position = entity_at
	game.player.global_position = viv_at
	await frames(2)       # moved bodies reach the physics space on the next physics frame
	audio.placed()
	await frames(1)


func ears() -> Vector2:
	return Acoustics.listener().global_position


## Angle in degrees between two directions.
func angle_between(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(absf(a.angle_to(b)))


## What the Entity bus's left and right meters read at their loudest over `time` seconds.
func meters(time: float) -> Vector2:
	var bus := AudioServer.get_bus_index(AudioBus.ENTITY)
	var loudest := Vector2(-200.0, -200.0)
	var clock := 0.0
	while clock < time:
		await get_tree().process_frame
		clock += get_process_delta_time()
		loudest.x = maxf(loudest.x, AudioServer.get_bus_peak_volume_left_db(bus, 0))
		loudest.y = maxf(loudest.y, AudioServer.get_bus_peak_volume_right_db(bus, 0))
	return loudest


## Plays one set `count` times; returns how many got through.
func play_many(set_id: String, count: int) -> int:
	var through := 0
	for index in count:
		if audio.play_set(set_id) != null:
			through += 1
	return through


func check_same_room() -> void:
	# Near: five units away, nothing between them.
	await place(VESTIBULE_A, VESTIBULE_B)
	check(audio.heard_ring == 2 and audio.heard_clarity > 0.9 and near(audio.heard_u, 5.0, 0.2),
		"Across the room it is near: ring %d, %.1f u" % [audio.heard_ring, audio.heard_u])
	check(audio.heard.global_position == entity.global_position and audio.heard_settle == 1.0 and not Acoustics.reading(entity).through_opening,
		"In the same room its position sounds come from exactly where it is")
	lost = 0
	check(play_many(BODY, 100) == 100 and play_many(EntityAudio.SNIFF, 100) == 100 and lost == 0 and audio.gaps.is_empty(),
		"In the same room every sound it makes is heard")
	var voice := audio.play_set(BODY)
	var limit: float = audio.reach_limit_u()
	check(voice != null and voice.bus == AudioBus.ENTITY and voice.panning_strength == 1.0, "Sharp, and placed exactly")
	# Calm (it stands still on its patrol), so the calm trim is part of it (check_calm_trim).
	check(voice != null and near(voice.volume_db, SoundLibrary.gain_db(BODY) + EntityAudio.position_db(audio.heard_u, limit)
		+ EntityAudio.calm_near_db(audio.heard_u, limit, 1.0))
		and voice.volume_db < SoundLibrary.gain_db(BODY) and voice.max_distance >= EntityAudio.NO_ENGINE_FALLOFF_PX,
		"A little under its full level, set from the way its sound travels (%.1f dB)" % (voice.volume_db if voice != null else 0.0))
	await seconds(settings.loop_fade + 0.3)
	check(audio.breath_set() == EntityAudio.BREATH_CALM and audio._breath_far.playing and audio._breath_far.stream == audio._breath.stream
		and audio._breath_far.bus == AudioBus.ENTITY_FAR and audio._breath.bus == AudioBus.ENTITY,
		"Its breath plays twice, once sharp and once dulled, the same take")
	check(audio._breath.volume_db > audio._breath_far.volume_db + 6.0, "Near, the sharp one carries it (%.1f against %.1f dB)" % [audio._breath.volume_db, audio._breath_far.volume_db])
	var near_breath: float = audio._breath.volume_db
	# On top of her.
	await place(VESTIBULE_A, VESTIBULE_NEXT)
	voice = audio.play_set(BODY)
	check(audio.heard_ring == 3 and audio.heard_clarity == 1.0 and voice != null
		and near(voice.volume_db, SoundLibrary.gain_db(BODY) + settings.position_calm_near_db),
		"Right beside her, calm, it is at its full level less the calm trim (%.1f dB)" % settings.position_calm_near_db)
	await frames(3)
	check(audio._breath_far.volume_db <= EntityAudio.GONE_DB
		and near(audio._breath.volume_db, SoundLibrary.gain_db(EntityAudio.BREATH_CALM) + settings.position_calm_near_db, 0.1)
		and audio._breath.volume_db > near_breath, "And nothing of it is dulled")
	audio.stop_all()


func check_a_room_away() -> void:
	await place(KITCHEN_BY_WALL, VESTIBULE_BY_WALL)
	var limit: float = audio.reach_limit_u()
	check(audio.heard_ring == 1 and audio.heard_clarity < settings.far_below_clarity and audio.listener_distance_u() < settings.ring_on_top_u,
		"Two units away through the wall it is somewhere: ring %d, %.1f u by ear" % [audio.heard_ring, audio.heard_u])
	# Gaps.
	lost = 0
	audio.gaps.clear()
	var played_before := int(audio.plays.get(BODY, 0))
	var body := play_many(BODY, TRIES)
	var expected_body: float = EntityAudio.chance_through(audio.heard_u, limit, false)
	var body_share := float(body) / TRIES
	check(body_share >= settings.gap_chance_body.x and body_share <= settings.gap_chance_body.y and near(body_share, expected_body, 0.1),
		"Of its steps, %d in %d got through (about %.2f expected)" % [body, TRIES, expected_body])
	check(int(audio.gaps.get(BODY, 0)) == TRIES - body and lost == TRIES - body and int(audio.plays.get(BODY, 0)) - played_before == body,
		"A sound lost on the way is counted as lost, never as played")
	var sniffs := play_many(EntityAudio.SNIFF, TRIES)
	var expected_voice: float = EntityAudio.chance_through(audio.heard_u, limit, true)
	check(sniffs > body and near(float(sniffs) / TRIES, expected_voice, 0.1),
		"Its sniffing gets through more often: %d in %d (about %.2f expected)" % [sniffs, TRIES, expected_voice])
	var said_before := int(audio.plays.get(EntityAudio.MUMBLE, 0))
	var lost_before := int(audio.gaps.get(EntityAudio.MUMBLE, 0))
	for index in TRIES:
		audio._say(false)
	var said := int(audio.plays.get(EntityAudio.MUMBLE, 0)) - said_before
	check(said + int(audio.gaps.get(EntityAudio.MUMBLE, 0)) - lost_before == TRIES and said > body and said < TRIES,
		"So does its talking: %d phrases in %d" % [said, TRIES])
	check(audio._talk.bus == AudioBus.ENTITY_FAR and audio._talk.panning_strength < 1.0, "And what is heard of it is dulled and vague")
	# What does get through.
	var voice: AudioStreamPlayer2D = null
	while voice == null:
		voice = audio.play_set(BODY)
	check(voice.bus == AudioBus.ENTITY_FAR, "A step that gets through is dulled (the far bus)")
	check(voice.panning_strength < 1.0 and voice.panning_strength > settings.far_panning
		and near(voice.panning_strength, EntityAudio.position_panning(audio.heard_u, limit), 0.001),
		"It comes from over there, not from a point (placed %.2f)" % voice.panning_strength)
	check(voice.volume_db < SoundLibrary.gain_db(BODY) + EntityAudio.position_db(settings.ring_near_u, limit) and voice.volume_db > EntityAudio.SILENT_DB,
		"Quieter than anywhere in the room, and still heard (%.1f dB)" % voice.volume_db)
	await seconds(settings.loop_fade + 0.3)
	check(audio._breath.playing and audio._breath_far.volume_db > audio._breath.volume_db and audio._breath_far.volume_db > EntityAudio.SILENT_DB,
		"Its breath is mostly the dulled one now (%.1f against %.1f dB)" % [audio._breath_far.volume_db, audio._breath.volume_db])
	# What it knows is not thinned out, dulled or made vague.
	var cues := 0
	var plain := true
	for index in 60:
		var cue := audio._play_heard()
		if cue != null:
			cues += 1
			plain = plain and cue.bus == AudioBus.ENTITY and cue.panning_strength == 1.0
	check(cues == 60 and plain, "The heard-you cue is never lost on the way, dulled or made vague")
	# Where it comes from: the doorway, at the distance it really is.
	var reading := Acoustics.reading(entity)
	var offset: Vector2 = audio.heard.global_position - ears()
	var to_entity: Vector2 = entity.global_position - ears()
	check(reading.through_opening and angle_between(offset, reading.heard_from - ears()) < ANGLE_TOLERANCE
		and near(offset.length(), to_entity.length(), 1.0) and angle_between(offset, to_entity) > 20.0,
		"Its steps come from the doorway (%.0f degrees off it), not through the wall (%.0f degrees from it), at its own distance"
			% [angle_between(offset, reading.heard_from - ears()), angle_between(offset, to_entity)])
	check(audio._aware.all(func(player: AudioStreamPlayer2D) -> bool: return player.global_position == entity.global_position),
		"What it knows is still heard from where it stands")
	audio.stop_all()


## Two rooms, one above the other, joined by a doorway at the left end of the wall.
func build_arena() -> Node2D:
	var arena := Node2D.new()
	arena.name = "DoorwayArena"
	game.add_child(arena)
	arena.global_position = ARENA
	var top := ARENA_WALL_Y - ARENA_WALL_HALF
	var bottom := ARENA_WALL_Y + ARENA_WALL_HALF
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_traversable_outline(PackedVector2Array([Vector2.ZERO, Vector2(ARENA_SIZE.x, 0.0), ARENA_SIZE, Vector2(0.0, ARENA_SIZE.y)]))
	for span: Vector2 in [Vector2(0.0, ARENA_DOOR.x), Vector2(ARENA_DOOR.y, ARENA_SIZE.x)]:
		var wall := StaticBody2D.new()
		wall.collision_layer = settings.acoustics_wall_mask
		wall.add_to_group(Acoustics.WALL_GROUP)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(span.y - span.x, bottom - top)
		shape.shape = rect
		wall.add_child(shape)
		arena.add_child(wall)
		wall.position = Vector2((span.x + span.y) * 0.5, ARENA_WALL_Y)
		source.add_obstruction_outline(PackedVector2Array([Vector2(span.x, top), Vector2(span.y, top), Vector2(span.y, bottom), Vector2(span.x, bottom)]))
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = ARENA_AGENT_RADIUS
	NavigationServer2D.bake_from_source_geometry_data(polygon, source)
	var region := NavigationRegion2D.new()
	region.navigation_polygon = polygon
	arena.add_child(region)
	return arena


## The entity behind the wall to Viv's right, the doorway to her left: its position sounds come
## from her left. Loudness and blur do not care where they come from.
func check_doorway() -> void:
	var arena := build_arena()
	await frames(3)
	await place_at(ARENA + ARENA_ENTITY, ARENA + ARENA_VIV)
	var reading := Acoustics.reading(entity)
	var offset: Vector2 = audio.heard.global_position - ears()
	var to_entity: Vector2 = entity.global_position - ears()
	print("[Ring tests] arena: heard from %s, path %s, heard at %s, %.1f u" % [reading.heard_from - ARENA, Array(reading.path).map(func(p: Vector2) -> Vector2: return p - ARENA), offset, audio.heard_u])
	check(reading.blocked and reading.through_opening and reading.heard_from.x < ears().x and entity.global_position.x > ears().x,
		"Made-up rooms: it stands to her right behind the wall, the doorway is to her left (%s)" % (reading.heard_from - ARENA))
	check(angle_between(offset, reading.heard_from - ears()) < ANGLE_TOLERANCE and near(offset.length(), to_entity.length(), 1.0)
		and audio.heard.global_position.x < ears().x - Units.to_px(1.0),
		"So its sounds are placed to her left, toward the doorway, at its own distance (%s from her)" % offset)
	check(audio._aware.all(func(player: AudioStreamPlayer2D) -> bool: return player.global_position == entity.global_position),
		"What it knows stays where it stands")
	# Loudness and blur are the same with the doorway placing off.
	await frames(3)
	var on := [audio.heard_u, audio._reach_db, audio.heard_clarity, audio.heard_ring]
	settings.doorway_panning = false
	await frames(3)
	var off := [audio.heard_u, audio._reach_db, audio.heard_clarity, audio.heard_ring]
	check(on == off, "Where it comes from changes nothing of how loud or how dulled it is (%s, %s)" % [on, off])
	check(audio.heard.global_position == entity.global_position, "Switched off, it is heard from where it stands, even behind the wall")
	# The meters: with a position sound playing, the Entity bus is louder on the doorway's side.
	await seconds(settings.loop_fade + 0.3)
	var straight := await meters(1.0)
	settings.doorway_panning = true
	await seconds(settings.doorway_settle + 0.2)
	var doorway := await meters(1.0)
	print("[Ring tests] arena meters: straight %s, doorway %s" % [straight, doorway])
	check(audio._breath.playing and doorway.x > -60.0 and doorway.x > doorway.y + SIDE_DB,
		"Its breath comes from the left, the doorway's side (left %.1f, right %.1f dB)" % [doorway.x, doorway.y])
	check(straight.y > straight.x + SIDE_DB, "Through the wall it would have come from the right (left %.1f, right %.1f dB)" % [straight.x, straight.y])
	audio.stop_all()
	arena.queue_free()
	await frames(2)


## Behind the wall it stays put while Viv walks along it; a jump to another doorway is not swept
## across the wall: the placing goes to the centre and comes back.
func check_doorway_steady() -> void:
	await place(KITCHEN_BY_WALL, VESTIBULE_BY_WALL)
	var biggest := 0.0
	var previous: Vector2 = audio.heard.global_position
	var steps := 48
	for step in steps:
		game.player.global_position += Vector2(0.0, 2.0)
		await get_tree().physics_frame
		var moved: float = audio.heard.global_position.distance_to(previous)
		if audio.heard_settle >= 1.0:
			biggest = maxf(biggest, moved)
		previous = audio.heard.global_position
	check(Acoustics.reading(entity).through_opening and biggest < Units.to_px(0.5),
		"Walking %.0f u along the wall, where it comes from never jumps (at most %.1f px a frame)" % [Units.to_u(steps * 2.0), biggest])
	# She stops: it glides the last bit, then holds still.
	await seconds(settings.doorway_glide * 6.0 + 0.3)
	var still := audio.heard.global_position
	var drift := 0.0
	for tick in 60:
		await get_tree().physics_frame
		drift = maxf(drift, audio.heard.global_position.distance_to(still))
	check(drift < 1.0 and audio.heard_settle == 1.0, "Standing still, it does not drift or flicker (%.2f px)" % drift)
	# Another room, through the other doorway, without telling its voice.
	entity.global_position = house + ALTAR_BY_WALL
	var centre := false
	var swept := false
	var clock := 0.0
	previous = audio.heard.global_position
	while clock < 1.0:
		await get_tree().process_frame
		clock += get_process_delta_time()
		centre = centre or (audio.heard_settle == 0.0 and audio.placing() == 0.0)
		var moved: float = audio.heard.global_position.distance_to(previous)
		swept = swept or (moved > Units.to_px(0.5) and audio.heard_settle > 0.0)
		previous = audio.heard.global_position
	var reading := Acoustics.reading(entity)
	print("[Ring tests] other doorway: heard from %s" % (reading.heard_from - house))
	check(reading.through_opening and reading.heard_from.x > house.x + ALTAR_BY_WALL.x - Units.to_px(4.0) and centre and not swept,
		"Behind the other wall it jumps to the other doorway with no sweep, vague for a moment")
	check(audio.heard_settle == 1.0 and audio.placing() == audio._panning, "And %.1f s later it is placed as before" % settings.doorway_settle)
	audio.stop_all()


func check_far_away() -> void:
	await place(game.world.marker("house", "Patrol4") - house, game.world.marker("house", "Patrol3") - house)
	check(audio.heard_ring == 0 and audio.heard_clarity == 0.0, "From one end of the house to the other it is gone (%.1f u)" % audio.heard_u)
	lost = 0
	var said_before := int(audio.plays.get(EntityAudio.MUMBLE, 0))
	for index in 50:
		audio._say(false)
	check(play_many(BODY, 100) == 0 and play_many(EntityAudio.SNIFF, 100) == 0 and int(audio.plays.get(EntityAudio.MUMBLE, 0)) == said_before and lost == 250,
		"Nothing it does there is heard: no step, no sniff, no talking")
	await seconds(settings.loop_fade + 0.3)
	check(audio.breath_set() == EntityAudio.BREATH_CALM and audio._breath.volume_db <= EntityAudio.GONE_DB and audio._breath_far.volume_db <= EntityAudio.GONE_DB,
		"It still breathes, and none of it arrives")
	# What it knows still reaches her.
	var heard := audio._play_heard()
	check(heard != null and heard.playing and heard.bus == AudioBus.ENTITY
		and heard.volume_db >= SoundLibrary.gain_db(EntityAudio.HEARD_VOICE) + settings.heard_voice_gain_db + settings.heard_floor_db - 0.01
		and settings.heard_floor_db >= settings.audible_db,
		"Yet the heard-you cue still reaches her (%.1f dB)" % (heard.volume_db if heard != null else 0.0))
	var scream := audio.play_awareness(&"scream", EntityAudio.SCREAM, audio._scream_reach(), settings.scream_gain_db)
	check(scream != null and scream.playing and scream.bus == AudioBus.ENTITY
		and scream.volume_db >= SoundLibrary.gain_db(EntityAudio.SCREAM) + settings.scream_gain_db + settings.scream_floor_db - 0.01
		and settings.scream_floor_db >= settings.audible_db,
		"And so does the scream (%.1f dB)" % (scream.volume_db if scream != null else 0.0))
	audio.stop_all()


## Between two measurements what she hears glides; it never jumps.
func check_glide() -> void:
	await place(VESTIBULE_A, VESTIBULE_B)
	var from: float = audio.heard_u
	# It walks behind the wall (moved here in one go, without telling its voice).
	entity.global_position = house + KITCHEN_BY_WALL
	game.player.global_position = house + VESTIBULE_BY_WALL
	await frames(2)
	var to: float = Acoustics.remeasure(entity).acoustic_u
	await frames(2)
	check(to > from + 4.0 and absf(audio.heard_u - from) < (to - from) * 0.5, "A change in how far it sounds is not heard at once (%.1f of %.1f to %.1f u)" % [audio.heard_u, from, to])
	await seconds(settings.position_smooth * 6.0 + 0.3)
	check(near(audio.heard_u, Acoustics.reading(entity).acoustic_u, 0.3), "It glides there in a moment (%.1f u)" % audio.heard_u)


## How near it is reaches the mood late and smoothly, moves the world a little, and never the music.
func check_presence() -> void:
	var settle: float = settings.presence_lag.y + settings.presence_time + 0.4
	await place(game.world.marker("house", "Patrol4") - house, game.world.marker("house", "Patrol3") - house)
	await seconds(settle)
	check(is_zero_approx(Dread.presence) and not MixDirector.is_active(MixDirector.THREAT_MIX) and is_zero_approx(MixDirector.gain_db(AudioBus.AMBIENCE)),
		"With it far away there is no presence and the house is at its own level")
	music_changes = 0
	await place(VESTIBULE_A, VESTIBULE_B)
	var clarity: float = audio.heard_clarity
	check(near(Dread.reported_presence(), clarity, 0.001) and Dread.presence < clarity * 0.5, "Near again, it reports how near; the mood does not jump (%.2f)" % Dread.presence)
	var started := -1.0
	var arrived := -1.0
	var biggest_step := 0.0
	var waits: Array[float] = []
	var previous: float = Dread.presence
	var previous_wait: float = Dread._presence_wait
	var clock := 0.0
	while clock < 8.0:
		await get_tree().process_frame
		var delta: float = get_process_delta_time()
		clock += delta
		biggest_step = maxf(biggest_step, absf(Dread.presence - previous))
		if started < 0.0 and Dread.presence > previous: started = clock
		if arrived < 0.0 and near(Dread.presence, clarity, 0.001): arrived = clock
		if Dread._presence_wait > previous_wait: waits.append(Dread._presence_wait)
		previous = Dread.presence
		previous_wait = Dread._presence_wait
	check(started >= 0.0 and started <= settings.presence_lag.y + 0.1, "It starts to be felt within %.0f s (%.2f s)" % [settings.presence_lag.y, started])
	check(arrived - started >= clarity * settings.presence_time - 0.15 and biggest_step < 0.1,
		"And grows over about %.1f s, with no jump (%.2f s)" % [settings.presence_time, arrived - started])
	check(waits.size() >= 3 and waits.all(func(wait: float) -> bool: return wait >= settings.presence_lag.x - 0.05 and wait <= settings.presence_lag.y),
		"The mood looks at where it is every 0.5 to 2 s, not every frame (%d looks in 8 s)" % waits.size())
	var share: float = clarity * settings.presence_world_share
	check(near(Dread.presence, clarity, 0.001) and near(MixDirector.recede(), share, 0.001) and is_zero_approx(Dread.threat),
		"Unaware and near: presence %.2f, no threat, the world recedes %.2f" % [Dread.presence, MixDirector.recede()])
	check(near(MixDirector.gain_db(AudioBus.AMBIENCE), settings.threat_world_db * share) and near(MixDirector.gain_db(AudioBus.WORLD), settings.threat_world_db * share)
		and near(MixDirector.gain_db(AudioBus.BODY), settings.threat_body_db * share) and is_zero_approx(MixDirector.gain_db(AudioBus.ENTITY)),
		"The house goes down %.1f dB and Viv's body comes up %.1f dB; the entity is untouched" % [-settings.threat_world_db * share, settings.threat_body_db * share])
	check(music_changes == 0 and MusicDirector.current_state == MusicDirector.MusicState.EXPLORE and Dread.awareness == Dread.Awareness.UNAWARE,
		"The music does not react to how near it is")
	entity.hide()
	await frames(2)
	check(not audio.is_audible() and is_zero_approx(Dread.reported_presence()), "Hidden, it reports nothing")
	await seconds(settle)
	check(is_zero_approx(Dread.presence) and not MixDirector.is_active(MixDirector.THREAT_MIX) and is_zero_approx(MixDirector.gain_db(AudioBus.WORLD)),
		"And the house comes back")
	entity.show()


## While it knows nothing its position sounds beside her are held down a little; once it has
## heard something they are at their full level. Nearer is never quieter. Channel A is untouched.
func check_calm_trim() -> void:
	var trim: float = settings.position_calm_near_db
	check(trim < 0.0 and trim >= -7.5 and near(settings.position_calm_fade, 1.0), "The calm trim is on: %.1f dB, coming and going over %.1f s" % [trim, settings.position_calm_fade])
	var hearing := settings.ring_somewhere_u
	var listening := settings.ring_somewhere_u * settings.listen_reach_factor
	check(near(EntityAudio.calm_near_db(0.0, hearing, 1.0), trim, 0.001) and near(EntityAudio.calm_near_db(settings.position_full_u, hearing, 1.0), trim, 0.001),
		"Calm and right beside her, the whole trim")
	check(is_zero_approx(EntityAudio.calm_near_db(settings.ring_near_u, hearing, 1.0)) and is_zero_approx(EntityAudio.calm_near_db(settings.ring_near_u + 3.0, hearing, 1.0))
		and is_zero_approx(EntityAudio.calm_near_db(settings.ring_somewhere_u - 1.0, hearing, 1.0)),
		"Gone where ring 2 ends, and nothing a room away")
	check(is_zero_approx(EntityAudio.calm_near_db(settings.ring_near_u * settings.listen_reach_factor, listening, 1.0))
		and EntityAudio.calm_near_db(settings.ring_near_u, listening, 1.0) < 0.0,
		"While she holds her breath that edge moves out with ring 1 (to %.1f u)" % (settings.ring_near_u * settings.listen_reach_factor))
	check(is_zero_approx(EntityAudio.calm_near_db(1.0, hearing, 0.0)) and near(EntityAudio.calm_near_db(1.0, hearing, 0.5), trim * 0.5, 0.001),
		"Once it has heard something, none of it")
	for limit: float in [hearing, listening]:
		var falling := true
		var last := 0.0
		for step in range(0, int(limit * 20.0)):
			var at := step * 0.05
			var level: float = EntityAudio.position_db(at, limit) + EntityAudio.calm_near_db(at, limit, 1.0)
			falling = falling and level <= last + 0.0001
			last = level
		check(falling, "Calm, nearer is never quieter (ring 1 ending at %.1f u): %.1f dB at %.0f u, %.1f dB at %.0f u" % [limit,
			EntityAudio.position_db(settings.position_full_u, limit) + EntityAudio.calm_near_db(settings.position_full_u, limit, 1.0), settings.position_full_u,
			EntityAudio.position_db(settings.ring_near_u, limit), settings.ring_near_u])
	# In the house: right beside her, calm.
	await place(VESTIBULE_A, VESTIBULE_NEXT)
	check(Dread.awareness_of(entity, audio) <= Dread.Awareness.PAUSED and near(audio.calm_trim_db(), trim, 0.001) and near(audio.position_level_db(), trim, 0.001),
		"Calm beside her, its position sounds are held down by the trim (%.1f dB)" % audio.position_level_db())
	var voice := audio.play_set(BODY)
	check(voice != null and near(voice.volume_db, SoundLibrary.gain_db(BODY) + trim), "A step plays at its level less the trim (%.1f dB)" % (voice.volume_db if voice != null else 0.0))
	var calm_heard := audio._play_heard()
	var calm_heard_db: float = calm_heard.volume_db if calm_heard != null else 0.0
	audio.stop_all()
	# It has heard something (searching): at once at its full level, as before.
	entity.current_state = EntityAudio.SEARCH
	audio.placed()
	voice = audio.play_set(BODY)
	check(Dread.awareness_of(entity, audio) == Dread.Awareness.SEARCHING and is_zero_approx(audio.calm_trim_db())
		and voice != null and near(voice.volume_db, SoundLibrary.gain_db(BODY)),
		"Right beside her, once it has heard something, it is at its full level")
	var alert_heard := audio._play_heard()
	check(calm_heard != null and alert_heard != null and near(alert_heard.volume_db, calm_heard_db, 0.001)
		and near(alert_heard.volume_db, float(alert_heard.get_meta(&"base")) + EntityAudio.reach_db(audio.listener_distance_u(), audio._heard_reach()), 0.001),
		"What it knows is never trimmed: the heard-you cue is as loud calm or not (%.1f dB)" % calm_heard_db)
	audio.stop_all()
	# Calm again: the trim comes back over the fade, never in one step.
	entity.current_state = EntityAudio.PATROL
	await seconds(settings.position_calm_fade * 0.5)
	var halfway: float = audio.calm_trim_db()
	check(halfway < -0.5 and halfway > trim + 0.5, "Calm again, the trim comes back gradually (%.1f dB halfway)" % halfway)
	await seconds(settings.position_calm_fade * 0.5 + 0.3)
	check(near(audio.calm_trim_db(), trim, 0.001), "And is whole after %.1f s" % settings.position_calm_fade)
	# And it goes the same way.
	entity.current_state = EntityAudio.SEARCH
	await seconds(settings.position_calm_fade * 0.5)
	halfway = audio.calm_trim_db()
	check(halfway < -0.5 and halfway > trim + 0.5, "Alert, it goes gradually too (%.1f dB halfway)" % halfway)
	entity.current_state = EntityAudio.PATROL
	audio.placed()
	audio.stop_all()
