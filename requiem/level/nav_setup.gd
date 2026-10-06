extends NavigationRegion2D

# NavSetup
#
# Genera la malla navegable por codigo, A PARTIR DEL MAPA, no de numeros fijos.
#
# Antes el contorno era un rectangulo cableado de (-2000,-1500) a (2000,1500).
# Si un nivel nuevo era mas grande se salia de la malla, y si era mas chico se
# horneaba navegacion sobre vacio. Ahora el contorno se calcula con el rectangulo
# realmente usado por la capa de muros (get_used_rect) mas un margen en unidades.
# Agregar o borrar tiles ya no obliga a tocar este archivo.
#
# IMPORTANTE: por default NavigationPolygon solo detecta colisiones dentro de
# los HIJOS del NavigationRegion2D. Las capas "Map" y "Props" son hermanas, asi
# que se usa el modo de "grupo" y se meten al grupo "nav_obstacles" solas.

## Capa con los muros (TileMapLayer).
@export var walls_path: NodePath = ^"../Map"
## Capa opcional de props con escenas (altares, etc.). Si no existe se ignora.
@export var props_path: NodePath = ^"../Props"
## Cuanto margen de navegacion se deja alrededor del mapa, en unidades.
@export var margin_u: float = 4.0
## Distancia minima entre el centro del agente y un muro o prop, en unidades.
## Es la misma que usan las regiones horneadas del tutorial (15 px). Con este
## valor una puerta de 1 tile (32 px) deja un paso de apenas 2 px en la malla:
## la entidad la cruza, pero rozando. Desde 0.5 u las puertas de 1 tile se
## cierran para la navegacion.
@export var agent_radius_u: float = 15.0 / Units.PX_PER_UNIT

const OBSTACLE_GROUP: StringName = &"nav_obstacles"


func _ready() -> void:
	var walls := get_node_or_null(walls_path) as TileMapLayer
	if walls == null or walls.tile_set == null:
		push_warning("[NavSetup] No encontre la capa de muros en %s" % walls_path)
		return
	if walls.get_used_cells().is_empty():
		push_warning("[NavSetup] La capa %s no tiene tiles pintados; no hay navegacion" % walls.name)
		return

	walls.add_to_group(OBSTACLE_GROUP)

	var props := get_node_or_null(props_path) as TileMapLayer
	if props != null:
		# Las escenas de un TileMapLayer se instancian en su actualizacion
		# interna. La forzamos para que sus colisiones ya existan al hornear.
		props.update_internals()
		props.add_to_group(OBSTACLE_GROUP)

	var poly := NavigationPolygon.new()
	poly.add_outline(_outline_from(walls))
	poly.agent_radius = Units.to_px(agent_radius_u)
	poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	poly.source_geometry_group_name = OBSTACLE_GROUP

	navigation_polygon = poly
	call_deferred("bake_navigation_polygon")


## Rectangulo usado por los muros + margen, convertido al espacio local de este
## nodo (por si algun dia el nivel no esta en el origen).
func _outline_from(walls: TileMapLayer) -> PackedVector2Array:
	var cell: Vector2 = Vector2(walls.tile_set.tile_size)
	var used: Rect2i = walls.get_used_rect()

	# map_to_local devuelve el CENTRO de la celda; restamos media celda para
	# quedarnos con su esquina superior izquierda.
	var top_left: Vector2 = walls.map_to_local(used.position) - cell * 0.5
	var size: Vector2 = Vector2(used.size) * cell

	var margin: float = Units.to_px(margin_u)
	top_left -= Vector2(margin, margin)
	size += Vector2(margin, margin) * 2.0

	var corners := PackedVector2Array([
		top_left,
		top_left + Vector2(size.x, 0.0),
		top_left + size,
		top_left + Vector2(0.0, size.y),
	])

	var outline := PackedVector2Array()
	for p in corners:
		outline.append(to_local(walls.to_global(p)))
	return outline
