extends Node2D
## A tree seen from straight above: the trunk on the ground, the canopy over everyone who walks under it.

@onready var _trunk: Sprite2D = $Trunk
@onready var _canopy: Sprite2D = $Canopy
var _canopy_base := Vector2.ZERO


func _ready() -> void:
	var snap := (global_position / Units.ART_SCALE).round() * Units.ART_SCALE - global_position
	_trunk.position += snap
	_canopy.position += snap
	_canopy_base = _canopy.position


func _process(_delta: float) -> void:
	_canopy.position = _canopy_base + HeightShift.offset_for(to_global(_canopy_base))
