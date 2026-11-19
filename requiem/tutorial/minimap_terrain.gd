extends Control
const ZOOM := 0.27
const INK := Color("b5ad94")
const GOLD := Color("c4a778")
var atlas: Node
var _walls: Dictionary = {}

func project_point(world_point: Vector2) -> Vector2:
	return size * 0.5 + (world_point - atlas.game.player.global_position) * ZOOM

func _known(world_point: Vector2) -> bool:
	return atlas.known(world_point - atlas.REGIONS[atlas.game.zone].position, atlas.game.zone)

func _draw() -> void:
	if not is_instance_valid(atlas.game): return
	var zone: String = atlas.game.zone
	var region: Rect2 = atlas.REGIONS[zone]
	var zone_node: Node2D = atlas.game.world.zones[zone]
	draw_rect(Rect2(Vector2.ZERO, size), Color("111c19"))
	# Discovery tint and survey lines scroll in world space, never in screen space.
	for cell in atlas.explored.get(zone, {}):
		var rect := Rect2(Vector2(cell) * atlas.CELL, Vector2.ONE * atlas.CELL).intersection(Rect2(Vector2.ZERO, region.size))
		if not rect.has_area(): continue
		var screen := Rect2(project_point(region.position + rect.position), rect.size * ZOOM)
		if not screen.intersects(Rect2(Vector2.ZERO, size)): continue
		draw_rect(screen, Color(0.43, 0.48, 0.35, 0.09))
		draw_rect(screen, Color(0.5, 0.55, 0.4, 0.05), false, 0.5)
	if not _walls.has(zone): _cache_walls(zone_node, zone)
	for polygon in _walls[zone]:
		var center := Vector2.ZERO
		for point in polygon: center += point
		center /= polygon.size()
		if not _known(center): continue
		var screen_center := project_point(center)
		if not Rect2(Vector2(-24, -24), size + Vector2(48, 48)).has_point(screen_center): continue
		var points := PackedVector2Array()
		for point in polygon: points.append(project_point(point))
		draw_colored_polygon(points, Color(0.63, 0.62, 0.48, 0.5))
	if zone == "forest": _draw_trees(zone_node)
	var doors := zone_node.get_node_or_null("Doors")
	if doors != null:
		for door in doors.get_children():
			if door is Node2D and _known(door.global_position):
				draw_circle(project_point(door.global_position), 3, GOLD, false, 1, true)
	# The trail exit is an interaction marker, not a physical door.
	for id in ["forest_exit", "house_back"]:
		var item: Dictionary = atlas.game.world.interactables.get(id, {})
		if not item.is_empty() and zone_node.is_ancestor_of(item.node) and _known(item.node.global_position):
			draw_circle(project_point(item.node.global_position), 3, GOLD, false, 1, true)
	# Soft inner vignette, drawn before the marker so the player always reads clearly.
	for i in range(6):
		draw_rect(Rect2(Vector2.ONE * i, size - Vector2.ONE * i * 2), Color(0.02, 0.04, 0.03, 0.13 * (1.0 - float(i) / 6)), false, 2)
	var centre := size * 0.5
	draw_circle(centre, 10, Color(0.78, 0.68, 0.45, 0.12), true, -1, true)
	draw_circle(centre, 8, Color(0.78, 0.68, 0.45, 0.5), false, 1, true)
	var angle: float = atlas.game.player.get_node("PlayerAim").body_angle
	var arrow := PackedVector2Array()
	for point in [Vector2(6, 0), Vector2(-4, -3.5), Vector2(-2, 0), Vector2(-4, 3.5)]:
		arrow.append(centre + point.rotated(angle))
	draw_colored_polygon(arrow, Color("f5e4b8"))

func _cache_walls(zone_node: Node2D, zone: String) -> void:
	var polygons: Array[PackedVector2Array] = []
	var walls := zone_node.get_node_or_null("Walls") as TileMapLayer
	if walls != null:
		for cell in walls.get_used_cells():
			var data := walls.get_cell_tile_data(cell)
			if data == null: continue
			for i in data.get_collision_polygons_count(0):
				var polygon := PackedVector2Array()
				for point in data.get_collision_polygon_points(0, i):
					polygon.append(walls.to_global(walls.map_to_local(cell) + point))
				if polygon.size() >= 3: polygons.append(polygon)
	_walls[zone] = polygons

func _draw_trees(zone: Node2D) -> void:
	var props := zone.get_node_or_null("Props")
	if props == null: return
	for prop in props.get_children():
		if not prop is Node2D or not ("tree" in prop.name.to_lower() or "spruce" in prop.name.to_lower()): continue
		if not _known(prop.global_position): continue
		var point := project_point(prop.global_position)
		if not Rect2(Vector2.ZERO, size).grow(6).has_point(point): continue
		for tier in 2:
			var tip := point + Vector2(0, -5 + tier * 3)
			var spread := 2.5 + tier
			draw_polyline(PackedVector2Array([tip + Vector2(-spread, 4), tip, tip + Vector2(spread, 4)]), Color("6f7d65"), 1, true)
