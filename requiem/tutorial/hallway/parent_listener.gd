class_name ParentListener
extends Node2D
## A parent awake behind a closed door. Any noise whose reach touches the bottom edge of the door is
## heard. Placed on the door's floor line.
## Draws the diegetic cue: warm light under the door and two feet shadows shifting behind it. As the
## player comes close enough to be heard, the parent stirs: the feet stop and the light under the
## door brightens and turns toward red, so the danger reads before anything is heard.

## Half the width of the listening door edge, in px.
@export var half_width := 30.0
@export var light_color := Color(0.95, 0.72, 0.42)
@export var feet_color := Color("0d0b09")
## The light under the door. It follows the parent's state (stirring, listening).
@export var glow: PointLight2D
@export var danger_color := Color(1.0, 0.4, 0.22)

## 0..1 after a warning: the feet stop and the light brightens while the parent listens.
var alert := 0.0
## 0..1, how close the player's next step is to reaching this door (set by the tutorial).
var danger := 0.0
## `danger` eased, so the light swells and settles instead of snapping.
var stir := 0.0
var _clock := 0.0
var _glow_energy := 0.0
var _glow_color := Color.WHITE


func _ready() -> void:
	if glow != null:
		_glow_energy = glow.energy
		_glow_color = glow.color


## True when a noise of `radius` px made at `point` (global) reaches this door.
func hears(point: Vector2, radius: float) -> bool:
	return distance_to_edge(point) <= radius


func distance_to_edge(point: Vector2) -> float:
	var local := to_local(point)
	return local.distance_to(Vector2(clampf(local.x, -half_width, half_width), 0.0))


func listen() -> void:
	alert = 1.0


func _process(delta: float) -> void:
	_clock += delta
	alert = maxf(0.0, alert - delta * 0.35)
	stir = move_toward(stir, danger, delta * 2.5)
	if glow != null:
		glow.energy = _glow_energy * (1.0 + 1.1 * stir + 1.2 * alert)
		glow.color = _glow_color.lerp(danger_color, maxf(stir * 0.75, alert))
	queue_redraw()


func _draw() -> void:
	var tension := maxf(alert, stir)
	var strip := light_color.lerp(danger_color, tension * 0.75)
	strip.a = 0.5 + 0.45 * tension
	draw_rect(Rect2(-half_width, -3.0, half_width * 2.0, 3.0), strip)
	# Feet keep shifting while the parent is calm and freeze while they stir or listen.
	var shift := sin(_clock * 0.65) * 8.0 * (1.0 - tension)
	for x in [-12.0, 10.0]:
		draw_rect(Rect2(x + shift - 4.0, -4.0, 8.0, 4.0), feet_color)
