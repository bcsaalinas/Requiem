class_name ParentListener
extends Node2D
## A parent awake behind a closed door. Any noise whose reach touches the bottom edge of the door is
## heard. Placed on the door's floor line.
## The cue lives in the world: the glow is a real light behind the leaf that leaves through the slit
## under the door, and child LightOccluder2Ds cast the shadows on the corridor floor. LeftFoot and
## RightFoot shift about while the parent is calm and close together and stop while they stir or
## listen; a single Drag shadow (the loop) drags along the slit and stops while it listens.

## Half the width of the listening door edge, in px.
@export var half_width := 30.0
## The light under the door.
@export var glow: PointLight2D
@export var danger_color := Color(1.0, 0.4, 0.22)

## 0..1 after a warning: the shadows stop while the parent listens.
var alert := 0.0
## 0..1, how close the player's next step is to reaching this door (set by the tutorial).
var danger := 0.0
## `danger` eased, so the feet settle instead of snapping.
var stir := 0.0
var _clock := 0.0
var _drag_clock := 0.0
var _glow_energy := 0.0
var _glow_color := Color.WHITE

@onready var _left_foot := get_node_or_null("LeftFoot") as Node2D
@onready var _right_foot := get_node_or_null("RightFoot") as Node2D
@onready var _drag := get_node_or_null("Drag") as Node2D


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
	var tension := maxf(alert, stir)
	var shift := sin(_clock * 0.65) * 8.0 * (1.0 - tension)
	if _left_foot != null:
		_left_foot.position.x = snappedf(lerpf(-12.0, -5.0, tension) + shift, Units.ART_SCALE)
	if _right_foot != null:
		_right_foot.position.x = snappedf(lerpf(10.0, 5.0, tension) + shift, Units.ART_SCALE)
	if _drag != null:
		if tension <= 0.0:
			_drag_clock += delta
		_drag.position.x = snappedf(sin(_drag_clock * 0.3) * 20.0, Units.ART_SCALE)
