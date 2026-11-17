extends SceneTree
## Bakes the architecture art into the five tutorial zone scenes. Run it from the repo root with the
## zone scenes closed in the editor, and re-run it whenever a zone layout changes:
##
##   Godot --headless --path requiem --script res://level/art/zone_art_baker.gd
##
## It is deterministic (a fixed random seed per zone) and idempotent (it replaces its own nodes).
## The old `Walls` TileMapLayer keeps all collision, light occlusion and navigation: only its pixels
## are hidden. Per zone it adds ArtFloor, ArtWallBase, ArtWallInnerFace, ArtWallTops (hidden, drawn
## by ArtWallTopsShifted) and removes the old Floor, PorchDeck, Ground and trail Line2Ds.
##
## Rules:
## - Visible floor is every cell of the old floor sprites that is not a wall, a window gap, void
##   (forest column 0) or inside a ParentRoom shape (those rooms stay covered).
## - A collision cell is drawn as wall when it is 8-adjacent to visible floor, or when it lies in a
##   straight run of collision cells between two drawn wall cells (filler: base and a plain top).
##   Every other collision cell stays black void.
## - Window gaps are walls for this purpose; each drawn gap cell gets the window top.
## - Pieces are picked by matching the 8-neighbour floor mask against the nine wall pieces under all
##   eight tile transforms. Godot composes a tile transform as transpose first, then the flips.

const TILESET_PATH := "res://assets/art/tiles/tileset_architecture.tres"
const LEAF_B_PATH := "res://assets/art/props/door_leaf_b_closed.png"
const ZONES := ["bedroom", "hallway", "forest", "house", "loop"]
const OLD_NODES := ["Floor", "PorchDeck", "Ground", "TrailVerge", "Trail"]
const ART_NODES := ["ArtFloor", "ArtWallBase", "ArtWallInnerFace", "ArtWallTops", "ArtWallTopsShifted"]
const CELL := Units.TILE_PX
const COLUMNS := 9

const N := 1
const E := 2
const S := 4
const W := 8
const NE := 16
const SE := 32
const SW := 64
const NW := 128
const ALL_BITS := [N, E, S, W, NE, SE, SW, NW]
const DIRECTIONS := {
	N: Vector2i(0, -1), E: Vector2i(1, 0), S: Vector2i(0, 1), W: Vector2i(-1, 0),
	NE: Vector2i(1, -1), SE: Vector2i(1, 1), SW: Vector2i(-1, 1), NW: Vector2i(-1, -1),
}

## straight, outer_corner, inner_corner, inner_corner_room, t_junction, t_junction_room, end_cap,
## cross, straight_two_sided: the floor each piece is drawn facing.
const PIECE_MASKS := [S, SE, S | E, S | E | NW, SW | SE, N | SW | SE, W | S | E, NE | SE | SW | NW, N | S]
const PIECE_NAMES := ["straight", "outer_corner", "inner_corner", "inner_corner_room", "t_junction",
	"t_junction_room", "end_cap", "cross", "straight_two_sided"]

const BASE_FIRST := 33
const FACE_FIRST := 42
const TOP_FIRST := 51
const STRAIGHT_TOPS := [51, 60, 61, 62, 63]
const WINDOW_TOP := 64
const WINDOW_CRACKED_TOP := 66
const FLOOR_LIGHT_MASK := 1 | 16
const FLOOR_FIRST := {"wood": 0, "pasta": 4, "cement": 8, "patio": 12, "bath": 16, "forest": 20, "trail": 24}
const TRAIL_PIECES := {"edge": 28, "edge_b": 29, "corner_outer": 30, "corner_inner": 31, "diagonal": 32}
## Corners (NW, NE, SW, SE) that are trail, as drawn.
const TRAIL_PIECE_CORNERS := {"edge": NW | NE, "edge_b": NW | NE, "corner_outer": NW, "corner_inner": NW | NE | SW, "diagonal": NW | SE}
const TRAIL_CENTRE := {"edge": 1, "edge_b": 1, "corner_outer": 0, "corner_inner": 1, "diagonal": 1}
const FOREST_TERRAIN := 0
const TRAIL_TERRAIN := 1
const TRAIL_POLYLINE := [Vector2(40, 540), Vector2(316, 540), Vector2(380, 476), Vector2(380, 414),
	Vector2(444, 350), Vector2(766, 350), Vector2(830, 414), Vector2(830, 476), Vector2(894, 540),
	Vector2(1440, 540)]
const TRAIL_RADIUS := 45.0

const HOUSE_FLOORS := {"Kitchen": "cement", "Vestibule": "pasta", "AltarRoom": "wood", "Porch": "patio"}

var _tile_set: TileSet
var _atlas: TileSetAtlasSource
var _matches: Array[Dictionary] = []
var _unmatched: Array[String] = []
var _filler := 0


func _initialize() -> void:
	_tile_set = load(TILESET_PATH)
	_ensure_terrains()
	_atlas = _tile_set.get_source(0)
	_build_match_table()
	for zone: String in ZONES:
		_bake_zone(zone)
	print("Unmatched wall masks: ", _unmatched.size())
	for line in _unmatched:
		print("  ", line)
	print("Filler wall cells: ", _filler)
	quit()


# --- Atlas helpers ----------------------------------------------------------

static func coords(index: int) -> Vector2i:
	return Vector2i(index % COLUMNS, floori(index / float(COLUMNS)))


static func transform_mask(mask: int, alternative: int) -> int:
	var result := mask
	if alternative & 4:
		result = _remap(result, {N: W, W: N, S: E, E: S, NE: SW, SW: NE})
	if alternative & 1:
		result = _remap(result, {E: W, W: E, NE: NW, NW: NE, SE: SW, SW: SE})
	if alternative & 2:
		result = _remap(result, {N: S, S: N, NE: SE, SE: NE, NW: SW, SW: NW})
	return result


static func _remap(mask: int, mapping: Dictionary) -> int:
	var result := 0
	for bit: int in ALL_BITS:
		if mask & bit:
			result |= int(mapping.get(bit, bit))
	return result


## Clears a diagonal bit when either orthogonal neighbour beside it is floor.
static func normalise(mask: int) -> int:
	var result := mask
	if mask & (N | E):
		result &= ~NE
	if mask & (S | E):
		result &= ~SE
	if mask & (S | W):
		result &= ~SW
	if mask & (N | W):
		result &= ~NW
	return result


func _build_match_table() -> void:
	for alternative in 8:
		for piece in PIECE_MASKS.size():
			_matches.append({
				"mask": normalise(transform_mask(PIECE_MASKS[piece], alternative)),
				"piece": piece,
				"alternative": alternative,
			})


func _match(mask: int) -> Dictionary:
	for entry in _matches:
		if entry["mask"] == mask:
			return entry
	var best: Dictionary = _matches[0]
	var best_distance := 99
	for entry in _matches:
		var difference: int = entry["mask"] ^ mask
		var distance := 0
		for bit: int in ALL_BITS:
			if difference & bit:
				distance += 1
		if distance < best_distance:
			best_distance = distance
			best = entry
	return best


func _weight(index: int) -> float:
	return _atlas.get_tile_data(coords(index), 0).probability


func _pick(rng: RandomNumberGenerator, indices: Array) -> int:
	var total := 0.0
	for index: int in indices:
		total += _weight(index)
	var roll := rng.randf() * total
	for index: int in indices:
		roll -= _weight(index)
		if roll <= 0.0:
			return index
	return indices[indices.size() - 1]


func _alternative_for(index: int, alternative: int) -> int:
	return alternative if _atlas.has_alternative_tile(coords(index), alternative) else 0


# --- Terrain set ------------------------------------------------------------

func _ensure_terrains() -> void:
	if _tile_set.get_terrain_sets_count() == 0:
		_tile_set.add_terrain_set()
	_tile_set.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	while _tile_set.get_terrains_count(0) < 2:
		_tile_set.add_terrain(0)
	_tile_set.set_terrain_name(0, FOREST_TERRAIN, "forest")
	_tile_set.set_terrain_color(0, FOREST_TERRAIN, Color(0.25, 0.3, 0.2))
	_tile_set.set_terrain_name(0, TRAIL_TERRAIN, "trail")
	_tile_set.set_terrain_color(0, TRAIL_TERRAIN, Color(0.5, 0.42, 0.32))
	var atlas: TileSetAtlasSource = _tile_set.get_source(0)
	for tile_index in atlas.get_tiles_count():
		var tile_coords := atlas.get_tile_id(tile_index)
		for alternative_index in atlas.get_alternative_tiles_count(tile_coords):
			atlas.get_tile_data(tile_coords, atlas.get_alternative_tile_id(tile_coords, alternative_index)).terrain_set = -1
	for variant in 4:
		_set_terrain_tile(atlas, FLOOR_FIRST["forest"] + variant, 0, 0, FOREST_TERRAIN)
		_set_terrain_tile(atlas, FLOOR_FIRST["trail"] + variant, 0, 0, TRAIL_TERRAIN)
	for piece: String in TRAIL_PIECES:
		for alternative in 8:
			var corners := transform_mask(TRAIL_PIECE_CORNERS[piece], alternative)
			_set_terrain_tile(atlas, TRAIL_PIECES[piece], alternative, corners, TRAIL_CENTRE[piece], true)
	ResourceSaver.save(_tile_set, TILESET_PATH)


func _set_terrain_tile(atlas: TileSetAtlasSource, index: int, alternative: int, trail_corners: int, centre: int, mixed := false) -> void:
	var tile_coords := coords(index)
	if not atlas.has_alternative_tile(tile_coords, alternative):
		return
	var data := atlas.get_tile_data(tile_coords, alternative)
	data.terrain_set = 0
	data.terrain = centre
	var bits := {
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: NW,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: NE,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: SW,
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: SE,
	}
	for neighbour: int in bits:
		var is_trail := (trail_corners & int(bits[neighbour])) != 0 if mixed else centre == TRAIL_TERRAIN
		data.set_terrain_peering_bit(neighbour, TRAIL_TERRAIN if is_trail else FOREST_TERRAIN)


# --- Zone baking ------------------------------------------------------------

func _bake_zone(zone: String) -> void:
	var packed: PackedScene = load("res://tutorial/zones/%s.tscn" % zone)
	var zone_root := packed.instantiate()
	var floor_rects := _floor_rects(zone_root, zone)
	for node_name: String in OLD_NODES + ART_NODES:
		var old := zone_root.get_node_or_null(node_name)
		if old != null:
			zone_root.remove_child(old)
			old.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = ("zone_art_" + zone).hash()
	seed(rng.seed)

	var walls := zone_root.get_node("Walls") as TileMapLayer
	var collision := {}
	for cell in walls.get_used_cells():
		collision[cell] = true
	var windows := _windows(zone_root)
	var gap_cells := {}
	for entry in windows:
		for cell: Vector2i in entry["gap"]:
			gap_cells[cell] = true
			collision[cell] = true

	var rooms := _rooms(zone_root)
	var floor_cells := {}
	for rect in floor_rects:
		for y in range(floori(rect.position.y / CELL), ceili(rect.end.y / CELL)):
			for x in range(floori(rect.position.x / CELL), ceili(rect.end.x / CELL)):
				var cell := Vector2i(x, y)
				if collision.has(cell) or _is_void(zone, cell, rooms):
					continue
				floor_cells[cell] = true

	floor_cells = _reachable(zone_root, floor_cells, rooms)

	var drawn := {}
	for cell: Vector2i in collision:
		for bit: int in ALL_BITS:
			if floor_cells.has(cell + DIRECTIONS[bit]):
				drawn[cell] = true
				break
	var filler := {}
	for cell: Vector2i in collision:
		if not drawn.has(cell) and (_runs_between_drawn(cell, Vector2i.DOWN, collision, drawn) or _runs_between_drawn(cell, Vector2i.RIGHT, collision, drawn)):
			filler[cell] = true

	var floor_layer := _layer(zone_root, "ArtFloor", -10)
	floor_layer.light_mask = FLOOR_LIGHT_MASK
	var base_layer := _layer(zone_root, "ArtWallBase", 0)
	var face_layer := _layer(zone_root, "ArtWallInnerFace", 0)
	var tops_layer := _layer(zone_root, "ArtWallTops", 2)
	tops_layer.visible = false

	_paint_floor(zone, floor_layer, floor_cells, rooms, rng)

	var window_tops := {}
	for entry in windows:
		var top_index := WINDOW_CRACKED_TOP if entry["exterior"] else WINDOW_TOP
		var room_side := -1 if floor_cells.has(entry["gap"][0] + Vector2i(0, -1)) else 1
		var origin: Vector2i = entry["origin"]
		var outer_row := origin.y - 1 if room_side == -1 else origin.y - 3
		var art_cells := PackedVector2Array()
		for cell: Vector2i in entry["gap"]:
			if drawn.has(cell) and (not entry["exterior"] or cell.y == outer_row):
				window_tops[cell] = top_index
				art_cells.append(Vector2(cell))
		var window_node: Node = entry["node"]
		window_node.set_meta("art_cells", art_cells)
		window_node.set("room_side", room_side)

	for cell in _sorted(drawn.keys() + filler.keys()):
		var mask := 0
		for bit: int in ALL_BITS:
			if floor_cells.has(cell + DIRECTIONS[bit]):
				mask |= bit
		mask = normalise(mask)
		var is_filler := filler.has(cell)
		if is_filler or mask == 0:
			_filler += 1
			base_layer.set_cell(cell, 0, coords(BASE_FIRST))
			var plain_top: int = window_tops.get(cell, _pick(rng, STRAIGHT_TOPS))
			tops_layer.set_cell(cell, 0, coords(plain_top))
			continue
		var entry := _match(mask)
		if entry["mask"] != mask:
			_unmatched.append("%s %s mask=%s used=%s alt %d" % [zone, cell, _mask_text(mask), PIECE_NAMES[entry["piece"]], entry["alternative"]])
		var piece: int = entry["piece"]
		var alternative: int = entry["alternative"]
		base_layer.set_cell(cell, 0, coords(BASE_FIRST + piece), _alternative_for(BASE_FIRST + piece, alternative))
		face_layer.set_cell(cell, 0, coords(FACE_FIRST + piece), _alternative_for(FACE_FIRST + piece, alternative))
		if window_tops.has(cell):
			tops_layer.set_cell(cell, 0, coords(window_tops[cell]))
		else:
			var top_index := _pick(rng, STRAIGHT_TOPS) if piece == 0 else TOP_FIRST + piece
			tops_layer.set_cell(cell, 0, coords(top_index), _alternative_for(top_index, alternative))

	var shifted := HeightShiftedTiles.new()
	shifted.name = "ArtWallTopsShifted"
	shifted.z_index = 41
	shifted.scale = Vector2.ONE * Units.ART_SCALE
	zone_root.add_child(shifted)
	shifted.source = tops_layer

	walls.self_modulate = Color(1, 1, 1, 0)
	_adjust_doors(zone_root, zone)

	for node_name: String in ART_NODES:
		_own(zone_root.get_node(node_name), zone_root)
	var result := PackedScene.new()
	result.pack(zone_root)
	var path := "res://tutorial/zones/%s.tscn" % zone
	var scene_uid := ResourceLoader.get_resource_uid(path)
	var error := ResourceSaver.save(result, path)
	_restore_uids(path, scene_uid)
	print("Baked %s: floor %d, walls %d, filler %d (save %s)" % [zone, floor_cells.size(), drawn.size(), filler.size(), error_string(error)])
	zone_root.free()


## Keeps only the floor connected to a marker or a room, so floor sprite area outside the building
## (and beyond its walls) stays void.
func _reachable(zone_root: Node, floor_cells: Dictionary, rooms: Dictionary) -> Dictionary:
	var seeds: Array[Vector2i] = []
	var markers := zone_root.get_node_or_null("Markers")
	if markers != null:
		for marker in markers.get_children():
			seeds.append(Vector2i((marker as Node2D).position / CELL))
	for cell: Vector2i in floor_cells:
		var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
		for room_name: String in rooms:
			if not room_name.begins_with("ParentRoom") and Geometry2D.is_point_in_polygon(centre, rooms[room_name]):
				seeds.append(cell)
				break
	var reached := {}
	var queue: Array[Vector2i] = []
	for seed_cell in seeds:
		if floor_cells.has(seed_cell) and not reached.has(seed_cell):
			reached[seed_cell] = true
			queue.append(seed_cell)
	if queue.is_empty():
		return floor_cells
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if floor_cells.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	return reached


## Saving from a script drops the uid attributes; put them back so references stay stable.
func _restore_uids(path: String, scene_uid: int) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var matcher := RegEx.create_from_string('path="([^"]+)"')
	for index in lines.size():
		var line := lines[index]
		if index == 0 and line.begins_with("[gd_scene") and not "uid=" in line and scene_uid != ResourceUID.INVALID_ID:
			lines[index] = line.replace("]", ' uid="%s"]' % ResourceUID.id_to_text(scene_uid))
		elif line.begins_with("[ext_resource") and not "uid=" in line:
			var found := matcher.search(line)
			var uid := ResourceLoader.get_resource_uid(found.get_string(1)) if found != null else ResourceUID.INVALID_ID
			if uid != ResourceUID.INVALID_ID:
				lines[index] = line.replace(" path=", ' uid="%s" path=' % ResourceUID.id_to_text(uid))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines))


func _layer(zone_root: Node, node_name: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = node_name
	layer.tile_set = _tile_set
	layer.z_index = z
	layer.scale = Vector2.ONE * Units.ART_SCALE
	zone_root.add_child(layer)
	return layer


func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_own(child, owner_node)


func _sorted(cells: Array) -> Array:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return cells


func _mask_text(mask: int) -> String:
	var names := {N: "N", E: "E", S: "S", W: "W", NE: "NE", SE: "SE", SW: "SW", NW: "NW"}
	var parts: Array[String] = []
	for bit: int in ALL_BITS:
		if mask & bit:
			parts.append(names[bit])
	return "+".join(parts) if not parts.is_empty() else "none"


func _runs_between_drawn(cell: Vector2i, axis: Vector2i, collision: Dictionary, drawn: Dictionary) -> bool:
	return _finds_drawn(cell, axis, collision, drawn) and _finds_drawn(cell, -axis, collision, drawn)


func _finds_drawn(cell: Vector2i, step: Vector2i, collision: Dictionary, drawn: Dictionary) -> bool:
	var probe := cell + step
	while collision.has(probe):
		if drawn.has(probe):
			return true
		probe += step
	return false


# --- Zone data --------------------------------------------------------------

## The old floor sprites are removed by the bake, so their rects are kept as zone metadata and
## re-used when the baker runs again.
func _floor_rects(zone_root: Node, _zone: String) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for node_name: String in ["Floor", "PorchDeck", "Ground"]:
		var sprite := zone_root.get_node_or_null(node_name) as Sprite2D
		if sprite == null:
			continue
		rects.append(Rect2(sprite.position, sprite.region_rect.size * sprite.scale))
	if rects.is_empty() and zone_root.has_meta("art_floor_rects"):
		rects.assign(zone_root.get_meta("art_floor_rects"))
	if rects.is_empty():
		push_error("%s has no floor sprites and no art_floor_rects metadata" % zone_root.name)
	zone_root.set_meta("art_floor_rects", rects)
	return rects


func _rooms(zone_root: Node) -> Dictionary:
	var rooms := {}
	var holder := zone_root.get_node_or_null("Rooms")
	if holder == null:
		return rooms
	for area in holder.get_children():
		var shape := area.get_node_or_null("Shape") as CollisionPolygon2D
		if shape == null:
			continue
		var to_zone: Transform2D = holder.transform * area.transform * shape.transform
		var points := PackedVector2Array()
		for point in shape.polygon:
			points.append(to_zone * point)
		rooms[String(area.name)] = points
	return rooms


func _is_void(zone: String, cell: Vector2i, rooms: Dictionary) -> bool:
	if zone == "forest" and cell.x == 0:
		return true
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
	for room_name: String in rooms:
		if room_name.begins_with("ParentRoom") and Geometry2D.is_point_in_polygon(centre, rooms[room_name]):
			return true
	return false


func _windows(zone_root: Node) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var doors := zone_root.get_node_or_null("Doors")
	if doors == null:
		return found
	for node in doors.get_children():
		if not node.scene_file_path.ends_with("window.tscn"):
			continue
		var origin := Vector2i(Vector2(node.position) / CELL)
		var gap: Array[Vector2i] = []
		for row in [origin.y - 3, origin.y - 2, origin.y - 1]:
			gap.append(Vector2i(origin.x - 1, row))
			gap.append(Vector2i(origin.x, row))
		found.append({"node": node, "gap": gap, "exterior": node.get("exterior"), "origin": origin})
	return found


func _paint_floor(zone: String, layer: TileMapLayer, floor_cells: Dictionary, rooms: Dictionary, rng: RandomNumberGenerator) -> void:
	var cells := _sorted(floor_cells.keys())
	if zone == "forest":
		_paint_forest(layer, cells, rng)
		return
	for cell: Vector2i in cells:
		var group := _floor_group(zone, cell, rooms)
		var first: int = FLOOR_FIRST[group]
		layer.set_cell(cell, 0, coords(_pick(rng, [first, first + 1, first + 2, first + 3])))


func _floor_group(zone: String, cell: Vector2i, rooms: Dictionary) -> String:
	if zone != "house":
		return "wood"
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
	var nearest := ""
	var nearest_distance := INF
	for room_name: String in HOUSE_FLOORS:
		var points: PackedVector2Array = rooms.get(room_name, PackedVector2Array())
		if points.is_empty():
			continue
		if Geometry2D.is_point_in_polygon(centre, points):
			return HOUSE_FLOORS[room_name]
		for index in points.size():
			var closest := Geometry2D.get_closest_point_to_segment(centre, points[index], points[(index + 1) % points.size()])
			if closest.distance_to(centre) < nearest_distance:
				nearest_distance = closest.distance_to(centre)
				nearest = room_name
	return HOUSE_FLOORS.get(nearest, "wood")


## Corner grounds, as Match Corners reads them: a cell corner is trail when it lies within the trail
## radius of the old Trail Line2D polyline. Each cell takes a tile or alternative whose four corner
## grounds match exactly (weighted random among equals), so neighbouring cells always agree.
func _paint_forest(layer: TileMapLayer, cells: Array, rng: RandomNumberGenerator) -> void:
	var candidates := {}
	var piece_names := {}
	for variant in 4:
		_add_candidate(candidates, FLOOR_FIRST["forest"] + variant, 0, 0)
		_add_candidate(candidates, FLOOR_FIRST["trail"] + variant, 0, NW | NE | SW | SE)
		piece_names[FLOOR_FIRST["forest"] + variant] = "forest"
		piece_names[FLOOR_FIRST["trail"] + variant] = "trail"
	for piece: String in TRAIL_PIECES:
		piece_names[TRAIL_PIECES[piece]] = piece
		for alternative in 8:
			if _atlas.has_alternative_tile(coords(TRAIL_PIECES[piece]), alternative):
				_add_candidate(candidates, TRAIL_PIECES[piece], alternative, transform_mask(TRAIL_PIECE_CORNERS[piece], alternative))
	var chosen := {}
	var counts := {}
	for cell: Vector2i in cells:
		var mask := 0
		for corner in [[NW, Vector2i(0, 0)], [NE, Vector2i(1, 0)], [SW, Vector2i(0, 1)], [SE, Vector2i(1, 1)]]:
			if _distance_to_trail(Vector2(cell + corner[1]) * CELL) <= TRAIL_RADIUS:
				mask |= corner[0]
		var pick := _pick_candidate(rng, candidates[mask])
		if mask == 0 or mask == (NW | NE | SW | SE):
			for _attempt in 8:
				if not (_same_pick(chosen.get(cell + Vector2i.LEFT, {}), pick) or _same_pick(chosen.get(cell + Vector2i.UP, {}), pick)):
					break
				pick = _pick_candidate(rng, candidates[mask])
		chosen[cell] = {"mask": mask, "index": pick["index"], "alternative": pick["alternative"]}
		layer.set_cell(cell, 0, coords(pick["index"]), pick["alternative"])
		counts[piece_names[pick["index"]]] = counts.get(piece_names[pick["index"]], 0) + 1
	var mismatches := 0
	for cell: Vector2i in chosen:
		var mask: int = chosen[cell]["mask"]
		var right := cell + Vector2i.RIGHT
		var below := cell + Vector2i.DOWN
		if chosen.has(right):
			var other: int = chosen[right]["mask"]
			mismatches += int(bool(mask & NE) != bool(other & NW)) + int(bool(mask & SE) != bool(other & SW))
		if chosen.has(below):
			var other: int = chosen[below]["mask"]
			mismatches += int(bool(mask & SW) != bool(other & NW)) + int(bool(mask & SE) != bool(other & NE))
	print("Forest trail pieces: ", counts, " corner mismatches: ", mismatches)


func _same_pick(neighbour: Dictionary, pick: Dictionary) -> bool:
	return not neighbour.is_empty() and neighbour["index"] == pick["index"] and neighbour["alternative"] == pick["alternative"]


func _add_candidate(candidates: Dictionary, index: int, alternative: int, mask: int) -> void:
	if not candidates.has(mask):
		candidates[mask] = []
	candidates[mask].append({"index": index, "alternative": alternative, "weight": _atlas.get_tile_data(coords(index), alternative).probability})


func _pick_candidate(rng: RandomNumberGenerator, options: Array) -> Dictionary:
	var total := 0.0
	for option: Dictionary in options:
		total += option["weight"]
	var roll := rng.randf() * total
	for option: Dictionary in options:
		roll -= option["weight"]
		if roll <= 0.0:
			return option
	return options[options.size() - 1]


func _distance_to_trail(point: Vector2) -> float:
	var best := INF
	for index in TRAIL_POLYLINE.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(point, TRAIL_POLYLINE[index], TRAIL_POLYLINE[index + 1])
		best = minf(best, closest.distance_to(point))
	return best


func _adjust_doors(zone_root: Node, zone: String) -> void:
	var doors := zone_root.get_node_or_null("Doors")
	if doors == null:
		return
	if zone == "hallway" or zone == "loop":
		for door_name in ["ParentDoorA", "ParentDoorB"]:
			var door := doors.get_node(door_name)
			door.set("swing_side", -1)
			door.set("leaf_texture", load(LEAF_B_PATH))
	if zone == "house":
		doors.get_node("FrontDoor").set("swing_side", -1)
