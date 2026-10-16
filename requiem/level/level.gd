extends Node2D

# Level (raiz de cada noche)
#
# Ajusta el suelo (Floor, un ColorRect) y los limites de la camara del jugador
# al rectangulo realmente pintado en la capa de muros. Asi una noche nueva,
# heredada de level_template.tscn, funciona sin dimensionar nada a mano: antes
# el suelo se estiraba a ojo y la camara se quedaba con los limites que traiga
# player.tscn.
# Supone un hijo "Map"; "Floor", "Props" y "Player/Camera2D" son opcionales.

## Margen del suelo y de la camara alrededor del mapa, en unidades.
@export var floor_margin_u: float = 4.0
## Night templates start equipped; the tutorial teaches a separate pickup.
@export var starts_with_flashlight := true

@onready var _walls: TileMapLayer = get_node_or_null("Map")
@onready var _props: TileMapLayer = get_node_or_null("Props")
@onready var _floor: ColorRect = get_node_or_null("Floor")
@onready var _camera: Camera2D = get_node_or_null("Player/Camera2D")


func _ready() -> void:
	var actions := get_node_or_null("Player/ActionState")
	if actions != null: actions.has_flashlight = starts_with_flashlight
	if _walls == null or _walls.tile_set == null:
		push_warning("[Level] Falta la capa de muros \"Map\"")
		return
	_check_grid(_walls)
	_check_grid(_props)
	if _walls.get_used_cells().is_empty():
		return

	var bounds: Rect2 = _map_bounds()
	if _floor != null:
		_floor.position = bounds.position
		_floor.size = bounds.size
	if _camera != null:
		# Los limites de Camera2D van en coordenadas globales.
		var global_bounds: Rect2 = get_global_transform() * bounds
		_camera.limit_left = floori(global_bounds.position.x)
		_camera.limit_top = floori(global_bounds.position.y)
		_camera.limit_right = ceili(global_bounds.end.x)
		_camera.limit_bottom = ceili(global_bounds.end.y)
		_camera.reset_smoothing()


## Rectangulo usado por los muros + margen, en el espacio local de este nodo.
func _map_bounds() -> Rect2:
	var cell: Vector2 = Vector2(_walls.tile_set.tile_size)
	var used: Rect2i = _walls.get_used_rect()

	# map_to_local devuelve el CENTRO de la celda; restamos media celda para
	# quedarnos con su esquina superior izquierda.
	var top_left: Vector2 = _walls.map_to_local(used.position) - cell * 0.5
	var rect := Rect2(top_left, Vector2(used.size) * cell).grow(Units.to_px(floor_margin_u))

	var a: Vector2 = to_local(_walls.to_global(rect.position))
	var b: Vector2 = to_local(_walls.to_global(rect.end))
	return Rect2(a, b - a).abs()


## Un TileSet de otro tamano rompe la regla 1 tile = 1 u: las distancias del
## mapa dejarian de cuadrar con los radios de ruido. Se avisa en vez de callar.
func _check_grid(layer: TileMapLayer) -> void:
	if layer == null or layer.tile_set == null:
		return
	if layer.tile_set.tile_size != Vector2i(Units.TILE_PX, Units.TILE_PX):
		push_warning("[Level] %s usa tiles de %s px; la cuadricula del juego es de %d px (1 u)"
				% [layer.name, layer.tile_set.tile_size, Units.TILE_PX])
