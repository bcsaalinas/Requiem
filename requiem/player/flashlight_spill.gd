extends PointLight2D
## The share of the flashlight beam that passes over low furniture.
##
## The beam (the parent PointLight2D) casts furniture shadows; this copy of it
## does not. Behind a desk or a bed the floor keeps `share` of the beam, so low
## furniture leaves a partial shadow instead of a black hole that runs to the end
## of the cone. Walls, doors and tall props (wardrobes) are on the occluder bits
## both lights cast, so they still block the whole beam.
##
## Occluder bits: furniture footprints use bit 4 (value 8), which only the beam's
## shadow mask includes (11 = walls 1 + 2 + furniture 8). Tall furniture also sets
## bit 1, like walls, so this spill and ordinary lamps stop at it too. Lamps leave
## bit 4 out: a lamp standing on a desk must not throw the desk's shadow.
##
## The parent keeps its `energy` (flashlight.gd and PlayerJuice drive it); the
## split lives in the colours, so lit floor is exactly as bright as one light.

## Fraction of the beam that is not stopped by low furniture.
@export_range(0.0, 1.0) var share := 0.45

@onready var beam: PointLight2D = get_parent()


func _ready() -> void:
	# Run after every script that writes the beam's energy this frame.
	process_priority = 100
	texture = beam.texture
	range_item_cull_mask = beam.range_item_cull_mask
	shadow_enabled = beam.shadow_enabled
	shadow_filter = beam.shadow_filter
	blend_mode = beam.blend_mode
	beam.color = Color(1.0 - share, 1.0 - share, 1.0 - share)
	color = Color(share, share, share)
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	enabled = beam.enabled
	energy = beam.energy
	texture_scale = beam.texture_scale
	offset = beam.offset
