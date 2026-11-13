extends Node2D
## Generador de Paredes Coloniales para Planta Alta (70 x 56 u, 1 u = 32 px)
## Distribución de múltiples habitaciones reales interconectadas alrededor de la Galería del Patio

@onready var walls: TileMapLayer = $Walls

func _ready() -> void:
	_build_walls()

func _build_walls() -> void:
	if walls == null:
		return
	walls.clear()

	# --- 1. Muros Perimetrales Exteriores (x = 2..68, y = 2..54) ---
	_h_wall_interior(2, 68, 2)
	_h_wall_south(2, 68, 52)
	_v_wall(2, 2, 54)
	_v_wall(68, 2, 54)

	# --- 2. Barandal de la Balcony Galería alrededor del Vacío Central (x = 27..44, y = 22..34) ---
	_railing_v(27, 22, 34)
	_railing_v(44, 22, 34)
	_railing_h(27, 44, 22)
	_railing_h(27, 44, 34)
	_pillar(27, 22)
	_pillar(43, 22)
	_pillar(27, 33)
	_pillar(43, 33)

	# --- 3. Ala Norte: Anexo NO, Despacho Privado, Cámara Ancestros (ALTAR 5), Alcoba del Patrón y Closets ---
	_h_wall_interior(2, 68, 16, [8, 9, 20, 21, 34, 35, 48, 49, 61, 62])
	_v_wall(14, 2, 16, [9, 10])
	_v_wall(28, 2, 16, [9, 10])
	_v_wall(42, 2, 16, [9, 10])
	_v_wall(56, 2, 16, [9, 10])

	# --- 4. Ala Oeste: Cuarto de Huéspedes 1, Cuarto de Huéspedes 2 y Salón de Té / Antesala ---
	_v_wall(22, 18, 40, [21, 22, 30, 31, 37, 38])
	_h_wall_interior(2, 22, 25, [11, 12])
	_h_wall_interior(2, 22, 33, [11, 12])

	# --- 5. Ala Este: Estudio Prohibido (ALTAR 6), Galería de Cuadros y Escaleras ---
	_v_wall(50, 18, 40, [21, 22, 29, 30, 37, 38])
	_h_wall_interior(50, 68, 25, [58, 59])
	_h_wall_interior(50, 68, 33, [55, 56])

	# --- 6. Ala Sur: Cuarto Huéspedes 3, Guardarropa, Tapanco/Costura (ALTAR 7), Blancos y Cuarto Huéspedes 4 ---
	_h_wall_interior(2, 68, 40, [11, 12, 26, 27, 35, 36, 44, 45, 55, 56])
	_v_wall(24, 43, 52, [47, 48])
	_v_wall(30, 43, 52, [47, 48])
	_v_wall(42, 43, 52, [47, 48])
	_v_wall(48, 43, 52, [47, 48])


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


func _railing_h(x1: int, x2: int, y: int, openings: Array[int] = []) -> void:
	for x in range(min(x1, x2), max(x1, x2) + 1):
		if x in openings:
			continue
		walls.set_cell(Vector2i(x, y), 0, Vector2i(x % 8, 2))


func _railing_v(x: int, y1: int, y2: int, openings: Array[int] = []) -> void:
	for y in range(min(y1, y2), max(y1, y2) + 1):
		if y in openings:
			continue
		walls.set_cell(Vector2i(x, y), 0, Vector2i(y % 8, 2))


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
