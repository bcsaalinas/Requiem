extends Node2D
## Showcase guidance (tutorial/showcase.gd): marigold petals on the floor from her to the next thing
## to do, the same petals the forest trail taught her to follow. The path is the walkable one (the
## navigation map), laid from the goal back towards her so petals already on the floor stay where
## they are as she walks. Faint and unshaded: readable in the dark Hacienda, never a beam of light.

const PETALS := [
	preload("res://assets/art/ritual/ritual_petals_a.png"),
	preload("res://assets/art/ritual/ritual_petals_b.png"),
	preload("res://assets/art/ritual/ritual_petals_c.png"),
]
## Distance between petals along the path (px).
const SPACING := 40.0
## No petals this close to her (px), so the trail starts in front of her feet.
const CLEAR_NEAR := 30.0
## At most this many petals (about 1.4 rooms of trail ahead of her).
const MAX_PETALS := 36
## Seconds between path updates.
const REFRESH := 0.6

var player: Node2D
## Global position the petals lead to; Vector2.INF hides them.
var target := Vector2.INF:
	set(value):
		if value != target:
			target = value
			_refresh_left = 0.0
var _petals: Array[Dictionary] = []
var _refresh_left := 0.0


func _ready() -> void:
	z_index = -8
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unlit


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH
	_petals.clear()
	if visible and target != Vector2.INF and is_instance_valid(player):
		_lay(NavigationServer2D.map_get_path(get_world_2d().navigation_map, player.global_position, target, true))
	queue_redraw()


func _lay(path: PackedVector2Array) -> void:
	if path.size() < 2:
		return
	# Walk from the goal back to her, dropping a petal every SPACING px of path.
	var from_goal := 0.0
	var next_drop := SPACING * 0.5
	var laid: Array[Dictionary] = []
	for index in range(path.size() - 1, 0, -1):
		var a := path[index]
		var b := path[index - 1]
		var length := a.distance_to(b)
		while next_drop <= from_goal + length:
			var at := a.lerp(b, (next_drop - from_goal) / maxf(length, 0.001))
			laid.append({"at": at, "seed": absi(hash(Vector2i(at.round())))})
			next_drop += SPACING
		from_goal += length
	# Keep the ones in front of her: the last laid are the nearest to her.
	var kept: Array[Dictionary] = []
	for petal: Dictionary in laid:
		if petal["at"].distance_to(player.global_position) >= CLEAR_NEAR:
			kept.append(petal)
	_petals = kept.slice(maxi(0, kept.size() - MAX_PETALS))


func _draw() -> void:
	var count := _petals.size()
	for index in count:
		var petal: Dictionary = _petals[index]
		var seed: int = petal["seed"]
		var texture: Texture2D = PETALS[seed % PETALS.size()]
		var size := texture.get_size() * Units.ART_SCALE
		# Nearest petals are clearest; the far end of the trail fades into the dark.
		var nearness := float(index + 1) / float(count)
		var shade := Color(0.78, 0.66, 0.55, 0.25 + 0.5 * nearness)
		draw_set_transform(to_local(petal["at"]), float(seed % 628) * 0.01, Vector2.ONE)
		draw_texture_rect(texture, Rect2(-size * 0.5, size), false, shade)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
