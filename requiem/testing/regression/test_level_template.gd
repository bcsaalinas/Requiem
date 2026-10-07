extends Node

# Pruebas del sistema de niveles por tiles.
#
# Arma una noche a partir de level_template.tscn pintando celdas por codigo
# (igual que lo haria el editor) y revisa que el resto funcione SIN tocar
# ningun script: suelo y camara ajustados al mapa, malla navegable recortada
# por muros y altares, puertas conectadas, y que un altar completado se borre
# de la capa Props.
#
# Correr: godot --headless res://testing/regression/test_level_template.tscn

const TEMPLATE: PackedScene = preload("res://level/level_template.tscn")
const W: int = 24
const H: int = 16

var checks: int = 0
var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame


func _ready() -> void:
	var level: Node2D = TEMPLATE.instantiate()
	var walls: TileMapLayer = level.get_node("Map")
	var props: TileMapLayer = level.get_node("Props")
	_paint_house(walls, props)
	level.get_node("Player").position = Vector2(5, 12) * Units.TILE_PX
	level.get_node("Entity").position = Vector2(17, 12) * Units.TILE_PX
	add_child(level)

	var nav: NavigationRegion2D = level.get_node("NavigationRegion2D")
	await nav.bake_finished
	# El servidor de navegacion sincroniza el mapa unos frames despues.
	await frames(6)

	_check_fitting(level)
	_check_navigation(level)
	await _check_patrol(level)
	await _check_altar_completion(level)

	level.queue_free()
	await frames(3)
	print("[Level tests] ", checks - failures.size(), "/", checks, " passed")
	get_tree().quit(0 if failures.is_empty() else 1)


## Casa de 24x16 tiles: un muro vertical con puerta de 2 tiles y, en el cuarto
## derecho, un muro horizontal con puerta de 1 tile. Un altar arriba a la derecha.
func _paint_house(walls: TileMapLayer, props: TileMapLayer) -> void:
	var cells: Array[Vector2i] = []
	for x in range(W):
		cells.append_array([Vector2i(x, 0), Vector2i(x, H - 1)])
	for y in range(H):
		cells.append_array([Vector2i(0, y), Vector2i(W - 1, y)])
	for y in range(1, H - 1):
		if y < 6 or y > 7:
			cells.append(Vector2i(10, y))
	for x in range(11, W - 1):
		if x != 17:
			cells.append(Vector2i(x, 9))
	for c in cells:
		walls.set_cell(c, 0, Vector2i.ZERO)
	props.set_cell(Vector2i(19, 4), 0, Vector2i.ZERO, 0)


func _check_fitting(level: Node2D) -> void:
	var expected := Rect2(-128, -128, W * 32 + 256, H * 32 + 256)
	var floor_rect: ColorRect = level.get_node("Floor")
	check(Rect2(floor_rect.position, floor_rect.size).is_equal_approx(expected), "Floor is fitted to the painted map plus 4 u")
	var cam: Camera2D = level.get_node("Player/Camera2D")
	var limits := Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top)
	check(limits.is_equal_approx(expected), "Camera limits follow the painted map")


func _check_navigation(level: Node2D) -> void:
	var walls: TileMapLayer = level.get_node("Map")
	var props: TileMapLayer = level.get_node("Props")
	var nav_map: RID = (level.get_node("NavigationRegion2D") as NavigationRegion2D).get_navigation_map()

	var wall := walls.map_to_local(Vector2i(10, 12))
	check(NavigationServer2D.map_get_closest_point(nav_map, wall).distance_to(wall) > 15.0, "Painted walls are carved out of the nav mesh")
	var altar := props.get_child(0) as Node2D
	check(altar != null and altar.global_scale == Vector2.ONE, "Altar is instanced from the Props layer at scale 1")
	check(NavigationServer2D.map_get_closest_point(nav_map, altar.global_position).distance_to(altar.global_position) > 15.0, "Painted altars are carved out of the nav mesh")

	var spawn := walls.map_to_local(Vector2i(5, 12))
	var altar_room := walls.map_to_local(Vector2i(19, 6))
	var lower_room := walls.map_to_local(Vector2i(17, 12))
	var path := NavigationServer2D.map_get_path(nav_map, spawn, altar_room, true)
	check(path.size() > 1 and path[path.size() - 1].distance_to(altar_room) < 1.0, "A 2-tile doorway connects the rooms")
	path = NavigationServer2D.map_get_path(nav_map, altar_room, lower_room, true)
	check(path.size() > 1 and path[path.size() - 1].distance_to(lower_room) < 1.0, "A 1-tile doorway still connects the rooms")


func _check_patrol(level: Node2D) -> void:
	var entity: CharacterBody2D = level.get_node("Entity")
	var start := entity.global_position
	var moved := 0.0
	for i in range(240):
		await get_tree().physics_frame
		moved = maxf(moved, entity.global_position.distance_to(start))
	check(entity.get_state_name() == "PATROL" and moved > Units.TILE_PX, "Template entity patrols the baked mesh")
	# Lejos y quieta, para que no interrumpa el rezo.
	entity.process_mode = Node.PROCESS_MODE_DISABLED
	entity.global_position = Vector2(-1000, -1000)


func _check_altar_completion(level: Node2D) -> void:
	var props: TileMapLayer = level.get_node("Props")
	var player: CharacterBody2D = level.get_node("Player")
	var altar := props.get_child(0) as Node2D
	var cell := props.local_to_map(altar.position)
	player.global_position = altar.global_position + Vector2(0, 60)
	await frames(4)

	Engine.time_scale = 6.0
	Input.action_press("pray")
	await get_tree().create_timer(12.5).timeout
	Input.action_release("pray")
	Engine.time_scale = 1.0
	await frames(3)
	check(props.get_cell_source_id(cell) == -1, "A completed altar erases its Props cell")
	check(not GameState.is_praying, "Completing the altar releases the player")

	# Si la capa se reconstruye, el altar no debe volver.
	props.enabled = false
	props.update_internals()
	props.enabled = true
	props.update_internals()
	await frames(3)
	check(props.get_child_count() == 0, "A completed altar does not come back when the layer refreshes")
