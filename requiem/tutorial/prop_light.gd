extends PointLight2D
## Raised prop faces receive wall shadows, while ground receivers also see furniture shadows.
## Following the actual source preserves flashlight aim, battery flicker and story lighting.
var source: PointLight2D

static func attach(light: PointLight2D) -> void:
	light.range_item_cull_mask = 1
	light.shadow_item_cull_mask = 3
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 1.5
	if light.has_node("PropLight"): return
	var companion := new()
	companion.name = "PropLight"
	light.add_child(companion,false,Node.INTERNAL_MODE_BACK)

func _ready() -> void:
	source = get_parent() as PointLight2D
	process_priority = 1
	range_item_cull_mask = 2
	shadow_item_cull_mask = 1
	_sync()

func _process(_delta: float) -> void:
	_sync()

func _sync() -> void:
	enabled = source.enabled
	texture = source.texture
	offset = source.offset
	texture_scale = source.texture_scale
	color = source.color
	energy = source.energy
	shadow_enabled = source.shadow_enabled
	shadow_filter = source.shadow_filter
	shadow_filter_smooth = source.shadow_filter_smooth
	shadow_color = source.shadow_color
