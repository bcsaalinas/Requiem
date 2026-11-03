extends RefCounted
## Shared scenery grade (saturation, contrast, gain) for the painted prop atlas.
static func scenery_material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = preload("res://tutorial/scenery.gdshader")
	return result
