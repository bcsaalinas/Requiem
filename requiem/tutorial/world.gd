@tool
extends Node2D
## The five tutorial zones side by side (REGIONS). Each zone is an instanced scene in
## tutorial/zones/ with its own Walls (TileMapLayer), Doors, Props, Rooms (cover visibility),
## Markers and lights. This script only indexes them for the story script and changes story lighting.
const Art := preload("res://tutorial/art.gd")
const REGIONS := {
	"bedroom": Rect2(0, 0, 960, 640),
	"hallway": Rect2(1600, 0, 960, 640),
	"forest": Rect2(3200, 0, 1440, 800),
	"house": Rect2(5200, 0, 1280, 960),
	"loop": Rect2(7200, 0, 960, 640),
}

var props: Dictionary = {}
var interactables: Dictionary = {}
var landmarks: Dictionary = {}
var scene_nodes: Array[Node] = []
var zones: Dictionary = {}
var window_body: StaticBody2D
var navigation_regions: Array[NavigationRegion2D] = []

func _ready() -> void:
	for zone in get_children():
		zones[String(zone.name).to_lower()] = zone
		_index(zone)
	if landmarks.has("SideLight"):
		# Story code and the camera-test rig still address the sidelight as a prop.
		props["window"] = landmarks["SideLight"]
		window_body = landmarks["SideLight"].get_node("Body")
	for id in ["ForestNavigation", "HouseNavigation", "LoopNavigation"]:
		if landmarks.has(id):
			navigation_regions.append(landmarks[id])

## Walks a zone without entering instanced props/doors (their internals are not story nodes).
func _index(node: Node) -> void:
	for child in node.get_children():
		scene_nodes.append(child)
		if not landmarks.has(String(child.name)):
			landmarks[String(child.name)] = child
		if child.get_script() == Art:
			props[String(child.name)] = child
		if child.has_meta("interaction_id"):
			var id: String = child.get_meta("interaction_id")
			interactables[id] = {
				"position": (child as Node2D).global_position + child.get_meta("interaction_offset", Vector2.ZERO),
				"label": child.get_meta("interaction_label"),
				"node": child,
			}
		if child.scene_file_path.is_empty():
			_index(child)

## Global position of a Marker2D placed in a zone scene's Markers node.
func marker(zone: String, id: String) -> Vector2:
	var node := zones[zone].get_node_or_null("Markers/" + id) as Node2D
	return node.global_position if node != null else REGIONS[zone].get_center()

## The zone's RoomVisibility (null for zones without rooms).
func rooms(zone: String) -> RoomVisibility:
	return zones[zone].get_node_or_null("Rooms") as RoomVisibility

func nodes_in(zone: String, container: String) -> Array[Node]:
	var parent: Node = zones[zone].get_node_or_null(container)
	return parent.get_children() if parent != null else []

## A temporary story light (the window reveal).
func lamp(at: Vector2, color := Color("efc98e"), scale_value := 2.0, strength := 1.0) -> PointLight2D:
	var light := PointLight2D.new()
	light.position = at
	light.texture = preload("res://assets/lighting/lamp_pool.tres")
	light.texture_scale = scale_value
	light.color = color
	light.energy = strength
	# Layer 1 is the scenery, layer 3 the entity: every real light reveals her.
	light.range_item_cull_mask = 5
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 1.5
	add_child(light)
	return light

func set_house_danger(danger: bool) -> void:
	for id in ["VestibuleLight", "AltarLeftLight", "AltarRightLight"]:
		if not landmarks.has(id):
			continue
		var light := landmarks[id] as PointLight2D
		light.energy = 0.12 if danger else float(light.get_meta("rest_energy"))
		light.color = Color("71889b") if danger else light.get_meta("rest_color")
	# The kitchen candle stays lit: the recovery light survives the attack.
	for id in ["altar_candle_left", "altar_candle_right", "vestibule_candle"]:
		if props.has(id):
			props[id].extinguished = danger
			props[id].queue_redraw()
