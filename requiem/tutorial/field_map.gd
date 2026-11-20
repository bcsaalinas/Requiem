extends Node
## Local exploration memory for the always-visible, player-centred minimap.
const Sheet := preload("res://tutorial/minimap.gd")
const TITLES := {"bedroom": "The bedroom", "hallway": "The hallway", "forest": "The forest", "house": "The old house", "loop": "The return", "mansion_ground": "The mansion", "mansion_upper": "Upper floor"}
const REGIONS := preload("res://tutorial/world.gd").REGIONS
const CELL := 96.0
var game: Node
var sheet: Control
var selected := "bedroom"
var explored: Dictionary = {}
var _sample_left := 0.0

func bind_game(owner_game: Node) -> void:
	game = owner_game
	sheet = Sheet.new()
	sheet.atlas = self
	sheet.name = "Minimap"
	game.hud.root.add_child(sheet)
	game.hud.root.move_child(sheet, 0)
	record_position()

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	selected = game.zone
	sheet.visible = not game.complete and not game.resetting and not GameState.is_dead
	_sample_left -= delta
	if _sample_left <= 0.0:
		_sample_left = 0.15
		record_position()
	sheet.refresh()

func record_position() -> void:
	var zone: String = game.zone
	if not REGIONS.has(zone): return
	if not explored.has(zone):
		explored[zone] = {}
	var point: Vector2 = game.player.global_position - REGIONS[zone].position
	var cell := Vector2i(floori(point.x / CELL), floori(point.y / CELL))
	for x in range(-2, 3):
		for y in range(-2, 3):
			if Vector2(x, y).length() <= 2.3:
				var candidate := cell + Vector2i(x, y)
				if _room_visible((Vector2(candidate) + Vector2(0.5, 0.5)) * CELL, zone):
					explored[zone][candidate] = true

func known(point: Vector2, zone: String = selected) -> bool:
	return explored.get(zone, {}).has(Vector2i(floori(point.x / CELL), floori(point.y / CELL)))

func _room_visible(point: Vector2, zone: String) -> bool:
	var rooms: Node = game.world.zones[zone].get_node_or_null("Rooms")
	if rooms == null: return true
	for room in rooms.get_children():
		var shape := room.get_node_or_null("Shape") as CollisionPolygon2D
		if shape == null: continue
		var global: Vector2 = REGIONS[zone].position + point
		if Geometry2D.is_point_in_polygon(shape.to_local(global), shape.polygon):
			return room.revealed
	return true
