extends Node2D
## Showcase feedback drawn in the world (tutorial/showcase.gd): the one rule of the game made
## visible without words. It hears you, so:
## - every sound she makes ripples out on the floor as far as it carries (the radius the creature
##   hears it at), faint for a step, wide for a run, a gasp or a door,
## - her air is a thin ring around her while she holds her breath or gets it back,
## - while the creature is listening or hunting, a small mark shows where a stone would land.
## Drawn unshaded so it reads in the dark, and quiet enough to stay out of the way.

const UIPalette := preload("res://util/ui_palette.gd")
## Sounds that come from her or from what she does.
const HER_SOURCES := [
	NoiseManager.SourceType.FOOTSTEP, NoiseManager.SourceType.SPRINT, NoiseManager.SourceType.CROUCH,
	NoiseManager.SourceType.BREATH, NoiseManager.SourceType.PRAY, NoiseManager.SourceType.THROW,
	NoiseManager.SourceType.DOOR, NoiseManager.SourceType.FLASHLIGHT,
]
## Seconds a ripple takes to spread out and fade.
const RIPPLE_TIME := 0.8
## Peak opacity of a ripple.
const RIPPLE_ALPHA := 0.22
## Ripples further than this from her (px) are someone else's (a door it opens) and not drawn,
## except a stone's landing, which is always hers.
const RIPPLE_NEAR := 48.0
## Radius (px) of the air ring around her.
const AIR_RADIUS := 15.0

var player: CharacterBody2D
var breath: Node
var thrower: Node
var entity: Node
## Off while dialogue, death or a story sequence holds the game.
var shown := true

var _ripples: Array[Dictionary] = []
var _clock := 0.0


func _ready() -> void:
	z_index = 60
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unlit
	NoiseManager.noise_emitted.connect(_on_noise)


func _on_noise(at: Vector2, radius: float, source: int, _duration: float) -> void:
	if not shown or not is_instance_valid(player) or not (source in HER_SOURCES):
		return
	if source != NoiseManager.SourceType.THROW and at.distance_to(player.global_position) > RIPPLE_NEAR:
		return
	_ripples.append({"at": at, "radius": radius, "age": 0.0})
	if _ripples.size() > 24:
		_ripples.pop_front()


func _process(delta: float) -> void:
	_clock += delta
	for ripple in _ripples:
		ripple["age"] += delta
	_ripples = _ripples.filter(func(ripple: Dictionary) -> bool: return ripple["age"] < RIPPLE_TIME)
	queue_redraw()


func _draw() -> void:
	if not shown or not is_instance_valid(player):
		return
	for ripple in _ripples:
		var t: float = ripple["age"] / RIPPLE_TIME
		var radius: float = ripple["radius"] * (0.25 + 0.75 * ease(t, 0.4))
		var color := UIPalette.BONE
		color.a = RIPPLE_ALPHA * (1.0 - t)
		draw_arc(to_local(ripple["at"]), radius, 0.0, TAU, maxi(24, int(radius * 0.5)), color, 1.0, false)
	_draw_air()
	_draw_stone_mark()


func _draw_air() -> void:
	if breath == null:
		return
	var air: float = breath.lung_percent
	if not breath.is_holding and air >= 99.5:
		return
	var center := to_local(player.global_position + Vector2(0, -6))
	var color := UIPalette.BREATH_HOLD if breath.is_holding else UIPalette.BONE
	if air <= 45.0:
		color = UIPalette.BREATH_WARN
	if air <= 20.0:
		color = UIPalette.BREATH_CRIT.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_clock * TAU * 3.0)))
	var track := Color(0, 0, 0, 0.35)
	draw_arc(center, AIR_RADIUS, 0.0, TAU, 40, track, 2.0, false)
	var sweep := TAU * clampf(air / 100.0, 0.0, 1.0)
	color.a = 0.8 if breath.is_holding else 0.45
	if sweep > 0.01:
		draw_arc(center, AIR_RADIUS, -PI * 0.5, -PI * 0.5 + sweep, 40, color, 2.0, false)


func _draw_stone_mark() -> void:
	if thrower == null or entity == null or thrower.rocks <= 0 or not thrower.available:
		return
	var alert: bool = entity.active and (entity.is_listening() or entity.get_state_name() in ["HUNT", "SEARCH"])
	if not alert and not thrower.is_throwing:
		return
	var at := to_local(thrower.predict_landing())
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * 1.5)
	var color := UIPalette.CANDLE
	color.a = 0.35 + 0.3 * pulse
	draw_arc(at, 5.0, 0.0, TAU, 16, color, 1.0, false)
	draw_line(at + Vector2(-2, 0), at + Vector2(2, 0), color, 1.0)
	draw_line(at + Vector2(0, -2), at + Vector2(0, 2), color, 1.0)


func clear() -> void:
	_ripples.clear()
	queue_redraw()
