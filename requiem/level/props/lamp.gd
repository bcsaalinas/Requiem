@tool
extends Node2D
## A lamp prop. Its light is tuned per instance from the Inspector (energy, reach, colour)
## instead of editing the internal PointLight2D.

@export var lit := true:
	set(value):
		lit = value
		_apply()
@export_range(0.0, 4.0, 0.05) var energy := 1.1:
	set(value):
		energy = value
		_apply()
## Light radius as a multiple of the 256 px falloff texture (1.0 = 128 px reach).
@export_range(0.1, 6.0, 0.05) var reach := 1.3:
	set(value):
		reach = value
		_apply()
@export var color := Color("e8c088"):
	set(value):
		color = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	var light := get_node_or_null("Light") as PointLight2D
	if light == null:
		return
	light.enabled = lit
	light.energy = energy
	light.texture_scale = reach
	light.color = color
