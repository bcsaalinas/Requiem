@tool
extends Node2D
## Room composition lives in world.tscn; this script indexes interactions and changes story lighting.
const Materials := preload("res://tutorial/materials.gd")
const Art := preload("res://tutorial/art.gd")
const REGIONS := {
	"bedroom": Rect2(0, 0, 960, 640),
	"hallway": Rect2(1600, 0, 960, 640),
	"forest": Rect2(3200, 0, 1440, 800),
	"house": Rect2(5200, 0, 1280, 960),
	"loop": Rect2(7200, 0, 960, 640),
}

@export_category("Floor")
@export var floor_details: Array[Dictionary] = []
var props: Dictionary = {}
var interactables: Dictionary = {}
var landmarks: Dictionary = {}
var scene_nodes: Array[Node] = []
var window_body: StaticBody2D
var navigation_regions: Array[NavigationRegion2D] = []

func _ready() -> void:
	material = Materials.scenery_material(true)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for room in get_children():
		for child in room.get_children():
			scene_nodes.append(child)
			landmarks[String(child.name)] = child
			if child.get_script() == Art:
				props[String(child.name)] = child
			if child.has_meta("interaction_id"):
				var id: String = child.get_meta("interaction_id")
				interactables[id] = {
					"position": child.position + child.get_meta("interaction_offset", Vector2.ZERO),
					"label": child.get_meta("interaction_label"),
					"node": child,
				}
	props["entry_collision"] = landmarks["EntryCollision"]
	window_body = landmarks["WindowCollision"]
	for id in ["ForestNavigation", "HouseNavigation", "LoopNavigation"]:
		navigation_regions.append(landmarks[id])
	for id in ["parent_door_a", "parent_door_b"]:
		props[id].listening = true
	queue_redraw()

## Glass fragments are spawned only after a real window impact.
func prop(id: String, kind: String, at: Vector2, size := Vector2(48,48)) -> Node2D:
	var node := Art.new()
	node.name = id
	node.kind = kind
	node.dimensions = size
	node.position = at
	add_child(node)
	props[id] = node
	return node

func lamp(at: Vector2, color := Color("efc98e"), scale_value := 2.0, strength := 1.0) -> PointLight2D:
	var light := PointLight2D.new()
	light.position = at
	light.texture = preload("res://assets/Textures/light_texture.png")
	light.texture_scale = scale_value
	light.color = color
	light.energy = strength
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 1.5
	add_child(light)
	preload("res://tutorial/prop_light.gd").attach(light)
	return light

func _draw() -> void:
	for zone in REGIONS:
		var r: Rect2 = REGIONS[zone]
		Materials.paint(self,r,1 if zone == "forest" else 0,256,Color(.88,.88,.81))
	for detail in floor_details:
		if detail.has("path"):
			var a: Vector2 = detail["from"]
			var b: Vector2 = detail["to"]
			var trail := Rect2(a.min(b)-Vector2(47,47),(b-a).abs()+Vector2(94,94))
			# Soft irregular verges keep the trail distinct from the surrounding loam.
			draw_line(a,b,Color(.28,.28,.17,.35),108,true)
			Materials.paint(self,trail,3,256,Color(.85,.82,.72))

func set_house_danger(danger: bool) -> void:
	for id in ["VestibuleLight", "AltarLeftLight", "AltarRightLight"]:
		var light := landmarks[id] as PointLight2D
		light.energy = 0.12 if danger else float(light.get_meta("rest_energy"))
		light.color = Color("71889b") if danger else light.get_meta("rest_color")
	for id in ["candle_(985_0, 280_0)", "candle_(1090_0, 280_0)", "candle_(510_0, 618_0)"]:
		props[id].extinguished = danger
		props[id].queue_redraw()

