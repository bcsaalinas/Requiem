class_name RoomVisibility
extends Node2D
## Lifts the cover of the room the player stands in and of every room joined to it by an open
## door; every other room stays hidden. Put all Rooms of a zone under this node.

## The room the player was last seen in (kept while they cross a doorway gap).
var current: Room
var _inside: Array[Room] = []


func _ready() -> void:
	for room in get_rooms():
		room.player_entered.connect(_on_player_entered)
		room.player_exited.connect(_on_player_exited)
		for door in room.doors:
			if door != null and not door.opened.is_connected(refresh):
				door.opened.connect(refresh)
				door.closed.connect(refresh)
	refresh(true)


func get_rooms() -> Array[Room]:
	var rooms: Array[Room] = []
	for child in get_children():
		if child is Room:
			rooms.append(child)
	return rooms


## Places the player without waiting for physics (zone entry, checkpoint restore).
func sync_to(point: Vector2) -> void:
	_inside.clear()
	current = room_at(point)
	if current != null:
		_inside.append(current)
	refresh(true)


## The room whose Shape contains `point` (global coordinates), or null.
func room_at(point: Vector2) -> Room:
	for room in get_rooms():
		var shape := room.get_node_or_null("Shape") as CollisionPolygon2D
		if shape != null and Geometry2D.is_point_in_polygon(shape.to_local(point), shape.polygon):
			return room
	return null


func refresh(instant := false) -> void:
	for room in get_rooms():
		room.set_revealed(is_open_to_player(room), instant)


func is_open_to_player(room: Room) -> bool:
	if room == current or _inside.has(room):
		return true
	for door in room.doors:
		if door != null and door.is_open and other_side(door, room) == current:
			return true
	return false


## The other room that lists `door`, or null when the door leads outside this zone's rooms.
func other_side(door: Door, room: Room) -> Room:
	for candidate in get_rooms():
		if candidate != room and candidate.doors.has(door):
			return candidate
	return null


func _on_player_entered(room: Room) -> void:
	if not _inside.has(room):
		_inside.append(room)
	current = room
	refresh()


func _on_player_exited(room: Room) -> void:
	_inside.erase(room)
	if current == room and not _inside.is_empty():
		current = _inside.back()
	refresh()
