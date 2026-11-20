extends Node2D
## Generador de Paredes Coloniales para Planta Baja (70 x 56 u, 1 u = 32 px)
## Distribución de múltiples habitaciones reales interconectadas (sin pasillos de laberinto artificial)

@onready var walls: TileMapLayer = $Walls
const TUTORIAL_ARCHITECTURE := preload("res://assets/art/tiles/tileset_architecture.tres")

func _ready() -> void:
	_build_walls()
	_build_tutorial_floor()

func _build_tutorial_floor() -> void:
	# Use the tutorial's own 80 px architectural tiles at the same 0.4 art scale
	# as the house, for a 32 px grid matching this map's walls and room layout.
	var old_floor := get_node_or_null("Floor") as CanvasItem
	if old_floor != null: old_floor.hide()
	var floor_layer := TileMapLayer.new()
	floor_layer.name = "TutorialArtFloor"
	floor_layer.tile_set = TUTORIAL_ARCHITECTURE
	floor_layer.scale = Vector2(0.4, 0.4)
	floor_layer.z_index = -10
	floor_layer.light_mask = 17
	add_child(floor_layer)
	move_child(floor_layer, 0)
	for y in range(2, 53):
		for x in range(2, 69):
			var tile_index := posmod(x * 7 + y * 11, 4)
			floor_layer.set_cell(Vector2i(x, y), 0, Vector2i(tile_index, 0))

func _build_walls() -> void:
	if walls == null:
		return
	walls.clear()

	# --- 1. Muros Perimetrales Exteriores (x = 2..68, y = 2..54) ---
	_h_wall_interior(2, 68, 2)
	_h_wall_south(2, 68, 52, [34, 35])
	_v_wall(2, 2, 54)
	_v_wall(68, 2, 54)

	# --- 2. Gran Zaguán (Sur-Centro, x = 22..50, y = 40..52) ---
	_v_wall(22, 43, 52, [47, 48])
	_v_wall(50, 43, 52, [47, 48])
	var arch_zaguan: Array[int] = [33, 34, 35, 36]
	_h_wall_interior(22, 50, 40, arch_zaguan)

	# --- 3. Ala Oeste: Gran Comedor, Cava, Antecomedor, Cocina Antigua (ALTAR 2), Troje y Cámara del Altar 3 ---
	# Muro Norte del Gran Comedor (y = 40..42)
	_h_wall_interior(2, 22, 40, [8, 9, 17, 18])
	# División entre Cava de Vinos (x=2..13) y Antecomedor (x=13..22)
	_v_wall(13, 31, 40, [35, 36])
	# Muro Este del Ala Oeste hacia el Patio con Fuente (x = 22)
	_v_wall(22, 18, 40, [22, 23, 34, 35])
	# Muro Sur de Cocina Antigua y Alacena (y = 28..30)
	_h_wall_interior(2, 22, 28, [8, 9, 17, 18])
	# División entre Cocina Antigua (x=2..15) y Alacena (x=15..22)
	_v_wall(15, 19, 28, [22, 23])
	# Muro Norte de Cocina hacia Cámara del Altar 3 y Sacristía Oeste (y = 16..18)
	_h_wall_interior(2, 26, 16, [8, 9, 18, 19])
	# División entre Troje/Bodega Superior (y=2..8) y Cámara del Altar 3 (y=8..16)
	_h_wall_interior(2, 15, 8, [8, 9])
	# División vertical entre Troje/Altar 3 (x=2..15) y Sacristía Oeste (x=15..26)
	_v_wall(15, 2, 16, [5, 6, 13, 14])

	# --- 4. Ala Norte: Capilla Colonial (ALTAR 4) y Biblioteca ---
	_v_wall(26, 2, 16, [8, 9])
	_v_wall(42, 2, 16, [8, 9])
	_v_wall(56, 2, 16, [8, 9])
	# Muro Sur de Capilla y Biblioteca hacia el Patio (y = 16..18)
	_h_wall_interior(26, 56, 16, [33, 34, 48, 49])

	# --- 5. Ala Este: Gran Salón de Baile, Sala de Música, Escaleras y Salón Sur ---
	# Muro Oeste inferior del Salón de Baile (x = 56, y = 16..24)
	_v_wall(56, 16, 24, [20, 21])
	# Muro Oeste hacia el Patio (x = 50, y = 18..40)
	_v_wall(50, 18, 40, [20, 21, 29, 30, 37, 38])
	# Muro entre Salón de Baile y Sala de Música (y = 24..26)
	_h_wall_interior(50, 68, 24, [53, 54, 61, 62])
	# Muro entre Sala de Música y Escaleras (y = 33..35)
	_h_wall_interior(50, 68, 33, [55, 56])
	# Muro entre Escaleras y Salón Sur (y = 40..42)
	_h_wall_interior(50, 68, 40, [55, 56])

	# --- 6. Columnas de Cantera del Patio Central ---
	_pillar(25, 21)
	_pillar(45, 21)
	_pillar(25, 36)
	_pillar(45, 36)


func _h_wall_interior(x1: int, x2: int, y: int, openings: Array[int] = []) -> void:
	for x in range(min(x1, x2), max(x1, x2) + 1):
		if x in openings:
			continue
		walls.set_cell(Vector2i(x, y), 0, Vector2i((x % 4) + 4, 0))
		walls.set_cell(Vector2i(x, y + 1), 0, Vector2i(x % 8, 1))
		walls.set_cell(Vector2i(x, y + 2), 0, Vector2i(x % 8, 2))


func _h_wall_south(x1: int, x2: int, y: int, openings: Array[int] = []) -> void:
	for x in range(min(x1, x2), max(x1, x2) + 1):
		if x in openings:
			continue
		walls.set_cell(Vector2i(x, y), 0, Vector2i((x % 4) + 4, 0))
		walls.set_cell(Vector2i(x, y + 1), 0, Vector2i(x % 8, 3))
		walls.set_cell(Vector2i(x, y + 2), 0, Vector2i(x % 8, 4))


func _v_wall(x: int, y1: int, y2: int, openings: Array[int] = []) -> void:
	for y in range(min(y1, y2), max(y1, y2) + 1):
		if y in openings:
			continue
		walls.set_cell(Vector2i(x, y), 0, Vector2i(y % 8, 2))


func _pillar(x: int, y: int) -> void:
	walls.set_cell(Vector2i(x, y), 0, Vector2i(4, 0))
	walls.set_cell(Vector2i(x + 1, y), 0, Vector2i(5, 0))
	walls.set_cell(Vector2i(x, y + 1), 0, Vector2i(4, 2))
	walls.set_cell(Vector2i(x + 1, y + 1), 0, Vector2i(5, 2))
