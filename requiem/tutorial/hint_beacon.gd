extends Sprite2D
## The cold star that says "this one": the same twinkle the pickups carry, for things that are
## not picked up (a window to break, a chest to open). Unshaded, so it reads in a black room
## without lighting anything. It only marks the spot; it never explains what to do there.

const STAR := preload("res://assets/art/vfx/vfx_glint.png")
## Small star, large star, small star, then dark for the rest of the period.
const STAR_MS := [90.0, 170.0, 120.0]
const STAR_FRAMES := [1, 0, 1]

## Seconds between twinkles.
@export var period := 2.4
## Off: the star is hidden and keeps its place in the cycle.
@export var shining := true

var _clock := 0.0


func _init() -> void:
	texture = STAR
	hframes = 2
	scale = Vector2.ONE * Units.ART_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unlit


func _ready() -> void:
	# Staggered by where it stands, so two stars in one room never blink together.
	_clock = fposmod(global_position.x * 0.137 + global_position.y * 0.071, period)


func _process(delta: float) -> void:
	_clock = fposmod(_clock + delta, period)
	visible = false
	if not shining:
		return
	var time_ms := _clock * 1000.0
	for index in STAR_MS.size():
		if time_ms < STAR_MS[index]:
			visible = true
			frame = STAR_FRAMES[index]
			return
		time_ms -= STAR_MS[index]
