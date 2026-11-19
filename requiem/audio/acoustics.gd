extends Node
## How far a sound really travels to Viv: through doorways, not through walls.
##
## For an emitter (the entity) and the listener (Viv's ears) it measures the straight line,
## whether a wall is on it, and the walking path between them. From those it works out the
## acoustic distance, a clarity from 0 to 1, and a ring:
##   3  on top of you      2  near (the same room, or the next doorway)
##   1  somewhere (about a room away)                  0  gone
##
## Entities report themselves with watch() (EntityAudio does it). Each one is measured a few
## times per second, never every frame; reading() returns the last measurement.
##
## Nothing here makes a sound, changes the mix, or makes noise the entity can hear. It only
## measures. Every threshold is in audio/sound_settings.tres (Acoustics).

## Furniture and bodies share the walls' physics layer. They are looked past, up to this many
## of them on one line, so that only a wall counts as a wall.
const LOOKED_PAST := 6
## Group for anything that is not a tile layer and should still stop sound like a wall.
const WALL_GROUP := &"sound_wall"

## A watched emitter was measured again.
signal measured(emitter: Node2D, reading: AcousticReading)

## instance id -> { emitter: WeakRef, voice: WeakRef or null, reading: AcousticReading, wait: float }
var _watched := {}
var _listener_override: WeakRef


## Starts measuring an emitter. Asking twice is fine. `voice` is the node that makes its
## sounds, when it can say whether it can be heard at all (is_audible(): the tutorial's
## entity breathes before it is shown). Without one, an emitter is heard while it is shown.
func watch(emitter: Node2D, voice: Node = null) -> void:
	if emitter == null or _watched.has(emitter.get_instance_id()):
		return
	# Emitters take turns: two of them are never measured in the same frame.
	var turn: float = float(_watched.size() % 4) * 0.25 / maxf(SoundSettings.current().acoustics_rate, 1.0)
	_watched[emitter.get_instance_id()] = {"emitter": weakref(emitter), "voice": weakref(voice) if voice != null else null,
		"reading": AcousticReading.new(), "wait": turn}


func unwatch(emitter: Node2D) -> void:
	if emitter != null:
		_watched.erase(emitter.get_instance_id())


## The last measurement of a watched emitter (never null; not valid until it was measured).
func reading(emitter: Node2D) -> AcousticReading:
	if emitter == null or not _watched.has(emitter.get_instance_id()):
		return AcousticReading.new()
	return _watched[emitter.get_instance_id()].reading


## Measures a watched emitter again right now (it was just moved by hand) and keeps the result.
func remeasure(emitter: Node2D) -> AcousticReading:
	if emitter == null or not _watched.has(emitter.get_instance_id()):
		return AcousticReading.new()
	var entry: Dictionary = _watched[emitter.get_instance_id()]
	entry.reading = measure(emitter)
	measured.emit(emitter, entry.reading)
	return entry.reading


## Whether an emitter can be heard at all: its voice says so, else it has to be shown.
func is_audible(emitter: Node2D) -> bool:
	if emitter == null or not emitter.is_inside_tree():
		return false
	var entry: Dictionary = _watched.get(emitter.get_instance_id(), {})
	var voice: Node = (entry.voice as WeakRef).get_ref() if entry.get("voice") != null else null
	if voice != null and voice.has_method(&"is_audible"):
		return bool(voice.call(&"is_audible"))
	return emitter.is_visible_in_tree()


## The ring of the nearest watched emitter (0 with none): how close anything is, by ear.
func nearest_ring() -> int:
	var nearest := 0
	for id in _watched:
		nearest = maxi(nearest, (_watched[id].reading as AcousticReading).ring)
	return nearest


## Where sounds are heard from: Viv's ears (the current AudioListener2D), else the player.
func listener() -> Node2D:
	if _listener_override != null and _listener_override.get_ref() != null:
		return _listener_override.get_ref()
	var ears := get_viewport().get_audio_listener_2d()
	if ears != null and ears.is_inside_tree():
		return ears
	return get_tree().get_first_node_in_group(&"player") as Node2D


## For tests and tools: hear from another node (null: back to Viv).
func set_listener(node: Node2D) -> void:
	_listener_override = weakref(node) if node != null else null


func ring_for(acoustic_u: float) -> int:
	var settings := SoundSettings.current()
	if acoustic_u < settings.ring_on_top_u: return 3
	if acoustic_u < settings.ring_near_u: return 2
	if acoustic_u < settings.ring_somewhere_u: return 1
	return 0


func clarity_for(acoustic_u: float) -> float:
	var settings := SoundSettings.current()
	if settings.ring_somewhere_u <= settings.clarity_full_u:
		return 1.0 if acoustic_u < settings.ring_somewhere_u else 0.0
	return clampf(inverse_lerp(settings.ring_somewhere_u, settings.clarity_full_u, acoustic_u), 0.0, 1.0)


## Measures one emitter now. Call it from _physics_process (it casts a ray); for anything that
## is watched, use reading() instead.
func measure(emitter: Node2D) -> AcousticReading:
	var result := AcousticReading.new()
	var ears := listener()
	if emitter == null or ears == null or not is_audible(emitter):
		return result
	var skipped: Array[RID] = []
	for body: Node in [emitter, ears, ears.get_parent()]:
		if body is CollisionObject2D:
			skipped.append((body as CollisionObject2D).get_rid())
	var agent := emitter.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	var map: RID = agent.get_navigation_map() if agent != null else emitter.get_world_2d().navigation_map
	return measure_between(emitter.global_position, ears.global_position, emitter.get_world_2d(), map, skipped)


## The same measurement between two points of a world. `skipped`: bodies the line passes
## through freely (the emitter and the listener themselves).
func measure_between(from: Vector2, to: Vector2, world: World2D, map: RID, skipped: Array[RID] = []) -> AcousticReading:
	var settings := SoundSettings.current()
	var result := AcousticReading.new()
	result.valid = true
	result.emitter_at = from
	result.listener_at = to
	result.straight_u = Units.to_u(from.distance_to(to))
	result.blocked = _wall_between(from, to, world, skipped)
	result.acoustic_u = result.straight_u
	result.path = NavigationServer2D.map_get_path(map, from, to, true) if map.is_valid() else PackedVector2Array()
	if result.path.size() >= 2:
		# The path starts and ends on the walkable floor: the steps to and from it count too.
		var length := from.distance_to(result.path[0]) + result.path[result.path.size() - 1].distance_to(to)
		for index in range(1, result.path.size()):
			length += result.path[index - 1].distance_to(result.path[index])
		# A path is never shorter than the straight line.
		result.path_u = maxf(Units.to_u(length), result.straight_u)
	if result.blocked:
		if result.path_u >= 0.0:
			result.acoustic_u = lerpf(result.straight_u, result.path_u, settings.acoustics_path_weight)
		else:
			result.acoustic_u = result.straight_u * settings.acoustics_no_path_factor
	result.clarity = clarity_for(result.acoustic_u)
	result.ring = ring_for(result.acoustic_u)
	return result


## One ray on the wall layer. Furniture and bodies on that layer are looked past.
func _wall_between(from: Vector2, to: Vector2, world: World2D, skipped: Array[RID]) -> bool:
	if from.is_equal_approx(to):
		return false
	var query := PhysicsRayQueryParameters2D.create(from, to, SoundSettings.current().acoustics_wall_mask)
	query.collide_with_areas = false
	query.hit_from_inside = false
	var exclude: Array[RID] = skipped.duplicate()
	for attempt in LOOKED_PAST:
		query.exclude = exclude
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit.collider
		if collider is TileMapLayer or (collider is Node and (collider as Node).is_in_group(WALL_GROUP)):
			return true
		exclude.append(hit.rid)
	# Nothing but furniture as far as it was worth looking: not a wall.
	return false


func _physics_process(delta: float) -> void:
	var interval: float = 1.0 / maxf(SoundSettings.current().acoustics_rate, 1.0)
	for id in _watched.keys():
		var entry: Dictionary = _watched[id]
		var emitter := (entry.emitter as WeakRef).get_ref() as Node2D
		if emitter == null:
			_watched.erase(id)
			continue
		entry.wait -= delta
		if entry.wait > 0.0:
			continue
		entry.wait += interval
		if entry.wait <= 0.0:
			entry.wait = interval
		entry.reading = measure(emitter)
		measured.emit(emitter, entry.reading)
