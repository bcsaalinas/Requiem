extends Node2D
## Safety net behind the level. The zones are floating rooms over void, so "under the geometry" here
## means just past each region's edge: a frame of Area2D strips around every World.REGIONS rect.
## Nothing reaches them in normal play. A player who clips out is put back at the last checkpoint.
const World := preload("res://tutorial/world.gd")
## Gap between the region's edge and its strips, so doorways on the edge never touch one.
const MARGIN := 64.0
const THICKNESS := 200.0

func _ready() -> void:
	for id in World.REGIONS:
		var region: Rect2 = World.REGIONS[id]
		var outer := region.grow(MARGIN + THICKNESS)
		_add_strip(Rect2(outer.position, Vector2(outer.size.x, THICKNESS)))
		_add_strip(Rect2(outer.position.x, outer.end.y - THICKNESS, outer.size.x, THICKNESS))
		_add_strip(Rect2(outer.position, Vector2(THICKNESS, outer.size.y)))
		_add_strip(Rect2(outer.end.x - THICKNESS, outer.position.y, THICKNESS, outer.size.y))

func _add_strip(rect: Rect2) -> void:
	var area := Area2D.new()
	area.monitorable = false
	area.position = rect.get_center()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = rect.size
	area.add_child(shape)
	area.body_entered.connect(_on_body_entered)
	add_child(area)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		owner.request_reset("Back to the last safe place.")
