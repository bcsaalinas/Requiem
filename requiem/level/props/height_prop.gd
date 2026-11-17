extends Node2D
## A tall prop seen from above: the base sits at floor level and the top shifts
## with the camera like the wall tops, so the piece reads as having height.

@export var height_factor := 0.006

@onready var _base: Sprite2D = $Base
@onready var _top: Sprite2D = $Top
var _top_base := Vector2.ZERO


func _ready() -> void:
	var snap := (global_position / Units.ART_SCALE).round() * Units.ART_SCALE - global_position
	_base.position += snap
	_top.position += snap
	_top_base = _top.position


func _process(_delta: float) -> void:
	_top.position = _top_base + HeightShift.offset_for(to_global(_top_base), height_factor)
