extends NavigationRegion2D

# NavSetup
#
# Genera la malla navegable por codigo. IMPORTANTE: por default,
# NavigationPolygon solo detecta colisiones dentro de los HIJOS del
# propio NavigationRegion2D. Como el TileMapLayer "Map" es hermano
# (no hijo), usamos el modo de "grupo" para que si lo detecte sin
# tener que reacomodar el arbol de nodos.

func _ready() -> void:
	var poly := NavigationPolygon.new()

	var outline := PackedVector2Array([
		Vector2(-2000, -1500),
		Vector2(2000, -1500),
		Vector2(2000, 1500),
		Vector2(-2000, 1500),
	])
	poly.add_outline(outline)

	poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	poly.source_geometry_group_name = "nav_obstacles"

	# Metemos el Map (hermano de este nodo) al grupo automaticamente,
	# sin que haya que hacerlo a mano en el editor
	var map_node = get_node_or_null("../Map")
	if map_node:
		map_node.add_to_group("nav_obstacles")
		print("[NavSetup] Map agregado al grupo nav_obstacles")
	else:
		print("[NavSetup] ADVERTENCIA: no encontre el nodo Map en ../Map")

	navigation_polygon = poly
	call_deferred("bake_navigation_polygon")
	
