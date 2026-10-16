extends "res://level/level.gd"
## Paint before children enter the tree so navigation sees the complete fixture.

func _enter_tree() -> void:
	GameState.reset()
	# The current player scene carries the tutorial's finite-rock adapter.
	# This station deliberately exercises the full shared throwable mechanic.
	get_node("Player/Throw").set_script(preload("res://player/throw.gd"))
	var walls: TileMapLayer = get_node("Map")
	for x in range(28):
		walls.set_cell(Vector2i(x, 0), 0, Vector2i.ZERO)
		walls.set_cell(Vector2i(x, 19), 0, Vector2i.ZERO)
	for y in range(1, 19):
		walls.set_cell(Vector2i(0, y), 0, Vector2i.ZERO)
		walls.set_cell(Vector2i(27, y), 0, Vector2i.ZERO)
		if y < 9 or y > 11:
			walls.set_cell(Vector2i(14, y), 0, Vector2i.ZERO)
	get_node("Props").set_cell(Vector2i(7, 4), 0, Vector2i.ZERO, 0)
	get_node("Player").position = Vector2(7, 13) * Units.TILE_PX
	get_node("Entity").position = Vector2(23, 6) * Units.TILE_PX


func _exit_tree() -> void:
	GameState.reset()
