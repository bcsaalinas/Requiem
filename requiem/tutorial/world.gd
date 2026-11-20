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
	"mansion_ground": Rect2(8800, 0, 2304, 1856),
	"mansion_upper": Rect2(11600, 0, 2304, 1856),
}

const FriendVisual := preload("res://tutorial/friend_visual.gd")
const ATTACK_CANDLES := ["RouteVeladora0", "RouteVeladora1", "vestibule_candle", "RouteVeladora2", "altar_candle_left", "altar_candle_right", "RouteVeladora3"]
const HOUSE_CANDLE_LIGHTS := {"vestibule_candle": "VestibuleLight", "altar_candle_left": "AltarLeftLight", "altar_candle_right": "AltarLeftLight"}
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
		if child.get_script() == Art or child.get_script() == FriendVisual:
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

func set_candle_out(candle_id: String, out: bool) -> void:
	if props.has(candle_id):
		props[candle_id].extinguished = out
		props[candle_id].queue_redraw()
	var light: PointLight2D = null
	var resolved_out := out
	if HOUSE_CANDLE_LIGHTS.has(candle_id):
		light = landmarks.get(HOUSE_CANDLE_LIGHTS[candle_id]) as PointLight2D
		if candle_id.begins_with("altar_candle"):
			resolved_out = _altar_lights_out()
	elif props.has(candle_id):
		light = props[candle_id].get_node_or_null("WarmPool") as PointLight2D
	if light != null:
		light.energy = 0.0 if resolved_out else float(light.get_meta("rest_energy"))
		light.color = Color("71889b") if resolved_out else Color(light.get_meta("rest_color"))
	if candle_id == "vestibule_candle":
		zones["house"].get_node("Lights/WindowSpill").visible = not out

## The altar jars share one light: it stays on while either jar is lit.
func _altar_lights_out() -> bool:
	var left = props.get("altar_candle_left")
	var right = props.get("altar_candle_right")
	return (left == null or left.extinguished) and (right == null or right.extinguished)

func set_house_danger(danger: bool) -> void:
	# The kitchen candle stays lit: the recovery light survives the attack.
	for id in ATTACK_CANDLES:
		set_candle_out(id, danger)
	# The petals leading away from the porch are gone once the house has turned.
	if landmarks.has("PorchPetals"):
		landmarks["PorchPetals"].visible = not danger
