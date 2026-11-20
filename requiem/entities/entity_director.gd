class_name EntityDirector
extends Node
## The Director: a hint-only hand on the entity's patrol (child "Director" of an entity).
##
## It knows where Viv is. The entity does not, and the Director never tells it. It does ONE
## thing: when the entity asks which patrol marker to walk to next, the Director chooses.
##
##   DRIFT IN   Normally it prefers markers whose walking distance to Viv is inside
##              near_band_u (the next room, not her room), with some randomness: the entity
##              keeps passing through her part of the house without ever being sent at her.
##   NO-GO      Never a marker within no_go_u of Viv.
##   PRESSURE   Rises while the entity is near her (Dread.presence: how near it sounds) or
##              alert (Dread.threat); about pressure_fill_time of closeness fills it. Circling
##              her unheard, behind walls, still counts a little (near_pressure). Full: it
##              BACKS OFF, and for back_off_range seconds of patrol the markers far from her
##              are preferred. Then pressure starts again at pressure_after_back_off.
##   QUIET      If it has not been within quiet_range_u of her for quiet_limit_range
##              seconds, the next marker is the best one of the band, with no randomness:
##              no dead stretches.
##
## What it never does (the fairness contract): it never changes what the entity hears, never
## touches where the entity thinks a sound was, never makes it listen, check or hunt, and
## never returns anything but an index into the route it was handed.

## Pressure filled: it is being sent away for a while.
signal backed_off
## The back-off is over: it drifts in again.
signal returned

## Below this much closeness (0..1) pressure falls instead of rising.
const CLOSE_FLOOR := 0.05

## Off: the entity picks its patrol markers at random, as in the first house.
@export var enabled := true

@export_group("Drift in")
## Walking distance to Viv (u) of the markers it prefers: the next room, not her room.
@export var near_band_u := Vector2(8.0, 16.0)
## Never a marker this close to Viv, in a straight line.
@export_range(0.0, 20.0, 0.5, "suffix:u") var no_go_u := 5.0
## Randomness of a choice: a marker this far outside the band can still win.
@export_range(0.0, 20.0, 0.5, "suffix:u") var jitter_u := 4.0

@export_group("Pressure")
## Seconds of full closeness that fill the pressure.
@export_range(1.0, 120.0, 1.0, "suffix:s") var pressure_fill_time := 25.0
## Closeness (0..1) counted while it is within quiet_range_u of her and she cannot hear it:
## it hovers in her part of the house behind walls. At 0.25 that alone fills the pressure in
## four times pressure_fill_time, so it never circles her for ever (0: only what she hears counts).
@export_range(0.0, 1.0, 0.05) var near_pressure := 0.25
## Seconds an empty house takes to drain a full pressure.
@export_range(1.0, 300.0, 1.0, "suffix:s") var pressure_fall_time := 60.0
## Random range (s) of patrol it spends away once the pressure is full.
@export var back_off_range := Vector2(20.0, 35.0)
## While it backs off, markers at least this far from Viv (walking) are preferred.
@export_range(0.0, 60.0, 1.0, "suffix:u") var far_u := 20.0
## Where the pressure starts again after a back-off.
@export_range(0.0, 1.0, 0.05) var pressure_after_back_off := 0.3

@export_group("Quiet limit")
## "Near Viv" for the quiet limit, in a straight line.
@export_range(0.0, 60.0, 1.0, "suffix:u") var quiet_range_u := 18.0
## Random range (s) it may stay further away than that before it is brought back.
@export var quiet_limit_range := Vector2(45.0, 70.0)

## 0..1. Full: it backs off.
var pressure := 0.0
## Seconds of patrol left of the current back-off (0: not backing off).
var backing_off := 0.0
## Seconds since it was last within quiet_range_u of Viv.
var quiet_for := 0.0
## The last choice, for the F3 overlay and the tests: { index, walk_u, mode }.
var last_pick := {}
var _quiet_limit := 0.0


func _ready() -> void:
	reset()


## A new attempt starts with no pressure and a fresh quiet limit.
func reset() -> void:
	pressure = 0.0
	backing_off = 0.0
	quiet_for = 0.0
	last_pick = {}
	_roll_quiet_limit()


func _physics_process(delta: float) -> void:
	var entity := get_parent() as Node2D
	var viv := _viv()
	if not enabled or entity == null or viv == null or GameState.is_dead \
			or entity.get(&"active") == false or not entity.is_visible_in_tree():
		return
	var alert: float = Dread.threat if Dread.awareness >= Dread.Awareness.HEARD else 0.0
	var on_patrol: bool = String(entity.call(&"get_state_name")) == "PATROL" \
		and not (entity.has_method(&"is_listening") and bool(entity.call(&"is_listening")))
	var distance_u := Units.to_u(entity.global_position.distance_to(viv.global_position))
	advance(delta, closeness(Dread.presence, alert, distance_u), distance_u, on_patrol)


## How much it is pressing her right now (0..1): how near it sounds, how alert it is, or, when
## neither, the little that being in her part of the house counts for.
func closeness(presence: float, alert: float, distance_u: float) -> float:
	return clampf(maxf(maxf(presence, alert), near_pressure if distance_u <= quiet_range_u else 0.0), 0.0, 1.0)


## One step of the pressure and the quiet limit.
## `closeness`: 0..1, how near or how alert it is. `distance_u`: straight distance to Viv.
## `on_patrol`: a back-off only counts down while it is really patrolling.
func advance(delta: float, closeness: float, distance_u: float, on_patrol: bool) -> void:
	if backing_off > 0.0:
		if on_patrol:
			backing_off -= delta
			if backing_off <= 0.0:
				backing_off = 0.0
				pressure = pressure_after_back_off
				returned.emit()
	elif closeness > CLOSE_FLOOR:
		pressure = minf(pressure + closeness * delta / maxf(pressure_fill_time, 0.001), 1.0)
		if pressure >= 1.0:
			_begin_back_off()
	else:
		pressure = maxf(pressure - delta / maxf(pressure_fall_time, 0.001), 0.0)
	if distance_u <= quiet_range_u:
		if quiet_for > 0.0:
			_roll_quiet_limit()
		quiet_for = 0.0
	else:
		quiet_for += delta


func is_backing_off() -> bool:
	return backing_off > 0.0


## True when it has been away from Viv for longer than this stretch's limit.
func is_quiet_too_long() -> bool:
	return quiet_for >= _quiet_limit


## Index of the next patrol marker. Reads where Viv is; only ever returns a marker of `route`,
## never `from_index` again, never one within no_go_u of her (unless every other one is).
func pick(route: Array[Vector2], from_index: int) -> int:
	if route.size() < 2:
		return from_index
	var viv := _viv()
	if viv == null:
		return _any_other(route.size(), from_index)
	var at := viv.global_position
	var far := is_backing_off()
	var forced := not far and is_quiet_too_long()
	var best := -1
	var best_score := -INF
	var best_walk := 0.0
	var farthest := -1
	var farthest_walk := -1.0
	for index in route.size():
		if index == from_index:
			continue
		var walk := _walk_u(route[index], at)
		if walk > farthest_walk:
			farthest = index
			farthest_walk = walk
		if Units.to_u(route[index].distance_to(at)) < no_go_u:
			continue
		# 0 for a marker that is where it should be, less the further it is from that.
		var score: float = -maxf(far_u - walk, 0.0) if far \
			else -(maxf(near_band_u.x - walk, 0.0) + maxf(walk - near_band_u.y, 0.0))
		score += randf() * (0.01 if forced else jitter_u)
		if score > best_score:
			best = index
			best_score = score
			best_walk = walk
	if best < 0:
		# Every other marker is inside the no-go: the one furthest from her.
		best = farthest
		best_walk = farthest_walk
	last_pick = {"index": best, "walk_u": best_walk, "mode": "back off" if far else ("quiet limit" if forced else "drift in")}
	return best


## One line for the F3 overlay.
func status() -> String:
	if not enabled:
		return "off"
	var text := "pressure %.2f" % pressure
	if is_backing_off():
		text += ", backing off %.0f s" % backing_off
	elif is_quiet_too_long():
		text += ", quiet too long (%.0f s)" % quiet_for
	if not last_pick.is_empty():
		text += ", last marker %d (%.0f u from her by foot, %s)" % [int(last_pick.index) + 1, float(last_pick.walk_u), last_pick.mode]
	return text


func _begin_back_off() -> void:
	backing_off = randf_range(minf(back_off_range.x, back_off_range.y), maxf(back_off_range.x, back_off_range.y))
	backed_off.emit()
	# The marker it is walking to now was chosen to bring it near: it gets a new one.
	var entity := get_parent()
	if entity != null and entity.has_method(&"redirect_patrol"):
		entity.call(&"redirect_patrol")


func _roll_quiet_limit() -> void:
	_quiet_limit = randf_range(minf(quiet_limit_range.x, quiet_limit_range.y), maxf(quiet_limit_range.x, quiet_limit_range.y))


func _viv() -> Node2D:
	return get_tree().get_first_node_in_group(&"player") as Node2D if is_inside_tree() else null


func _any_other(count: int, from_index: int) -> int:
	var index := randi() % count
	return index if index != from_index else (index + 1) % count


## Walking distance between two points, through the doorways (the straight line with no path).
func _walk_u(from: Vector2, to: Vector2) -> float:
	var straight := Units.to_u(from.distance_to(to))
	var agent := get_parent().get_node_or_null("NavigationAgent2D") as NavigationAgent2D if get_parent() != null else null
	if agent == null:
		return straight
	var map := agent.get_navigation_map()
	if not map.is_valid():
		return straight
	var path := NavigationServer2D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return straight
	var length := from.distance_to(path[0]) + path[path.size() - 1].distance_to(to)
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return maxf(Units.to_u(length), straight)
