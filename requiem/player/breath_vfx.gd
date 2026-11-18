extends Control
## Subjective feedback only. The tunnel is drawn over the finished world image (it never changes
## what the lights reveal); breath puffs are world-space sprites that light like anything else.
##
## Holding her breath closes the view to a clear circle around her and drains its colour: silence
## costs sight. The circle tightens and throbs with her heartbeat as the air runs short, slams
## nearly shut on a forced gasp, and opens again as she recovers.

## Clear radius in screen heights: comfortable hold, air nearly gone, forced gasp.
const RADIUS_HELD := 0.34
const RADIUS_STRAINED := 0.22
const RADIUS_GASP := 0.11
const HEARTBEAT_SQUEEZE := 0.035
const SHOCK_SECONDS := 0.65

var feedback: Node
var _edge: ColorRect
var _armed_cue := &""
var _warning_age := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = Vector2(PixelDisplay.WORLD_SIZE)
	_edge = ColorRect.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := ShaderMaterial.new()
	style.shader = preload("res://player/breath_tunnel.gdshader")
	style.set_shader_parameter("aspect", float(PixelDisplay.WORLD_SIZE.x) / PixelDisplay.WORLD_SIZE.y)
	_edge.material = style
	add_child(_edge)
	move_child(_edge, 0)


func _process(delta: float) -> void:
	var strength: float = feedback.effects_strength if feedback.enabled else 0.0
	var locked: bool = feedback.breath.is_locked
	var shock := maxf(0.0, 1.0 - feedback.cue_age / SHOCK_SECONDS) if feedback.cue in [&"gasp", &"release_loud"] else 0.0
	if feedback.cue == &"release_loud": shock *= 0.5
	var recovery: float = (1.0 - feedback.recovery_fraction) if locked else 0.0
	var amount: float = maxf(feedback.hold_focus, maxf(shock, recovery * 0.85))
	var radius: float = lerpf(RADIUS_HELD, RADIUS_STRAINED, feedback.strain) \
		- HEARTBEAT_SQUEEZE * feedback.heartbeat * (0.25 + 0.75 * feedback.strain)
	radius = lerpf(radius, RADIUS_GASP, maxf(shock, recovery * 0.6))
	var material := _edge.material as ShaderMaterial
	material.set_shader_parameter("amount", amount * strength)
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("focus", _focus_uv())
	visible = feedback.enabled and not GameState.is_dead and feedback.player.can_process()
	_edge.visible = amount * strength > 0.001

	# Puffs are out-breaths only: release, loud release and forced gasp.
	if feedback.cue != _armed_cue:
		_armed_cue = feedback.cue
		if feedback.cue in [&"release", &"release_loud", &"gasp"]:
			_spawn_puff()
	if feedback.breath.is_holding and feedback.strain > 0.12:
		_warning_age += delta
		if feedback.pulse < 0.2 and _warning_age > 0.9:
			_warning_age = 0.0
			_spawn_puff()
	else:
		_warning_age = 0.0


func _spawn_puff() -> void:
	if feedback.effects_strength <= 0.0: return
	var rig: Node = feedback.appearance.rig
	var at: Vector2 = rig.anchor_global("head_center") if rig.has_anchor("head_center") \
		else feedback.appearance.get_global_transform_with_canvas().origin
	var puff := VfxSheet.new()
	feedback.player.get_parent().add_child(puff)
	puff.set_as_top_level(true)
	puff.global_position = at
	puff.z_index = 42
	puff.play(BREATH_TEXTURE, 4, FRAME_MS, ANCHOR)


const BREATH_TEXTURE := preload("res://assets/art/vfx/vfx_breath_puff.png")
## vfx_breath_puff.json: 90, 130, 120, 100 ms; anchor at 16,6 of a 32x32 frame.
const FRAME_MS: Array[int] = [90, 130, 120, 100]
const ANCHOR := Vector2(16, 6)
const VfxSheet := preload("res://level/vfx_sheet.gd")


## Her position in the world image, as UV.
func _focus_uv() -> Vector2:
	var view: SubViewport = PixelDisplay.world_view
	var at: Vector2 = view.canvas_transform * feedback.player.global_position
	return at / Vector2(view.size)
