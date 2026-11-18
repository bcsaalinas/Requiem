extends Control
## Subjective feedback only: the vignette is screen-space; breath puffs are
## world-space sprites that light like anything else.

var feedback: Node
var _edge: ColorRect
var _armed_cue := &""
var _warning_age := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	LegacyUi.fit_root(self)
	_edge = ColorRect.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := ShaderMaterial.new()
	style.shader = preload("res://player/breath_vignette.gdshader")
	_edge.material = style
	add_child(_edge)
	move_child(_edge, 0)


func _process(delta: float) -> void:
	var strength: float = feedback.effects_strength if feedback.enabled else 0.0
	var locked: bool = feedback.breath.is_locked
	var shock := maxf(0.0, 1.0 - feedback.cue_age / 0.65) if feedback.cue == &"gasp" else 0.0
	var recovery: float = (1.0 - feedback.recovery_fraction) if locked else 0.0
	var edge_alpha: float = feedback.hold_focus * 0.055 \
		+ feedback.strain * (0.035 + feedback.pulse * 0.045) + shock * 0.08 + recovery * 0.035
	_edge.material.set_shader_parameter("strength", minf(edge_alpha, 0.17) * strength)
	_edge.material.set_shader_parameter("tension", maxf(feedback.strain, shock))
	visible = feedback.enabled and not GameState.is_dead and feedback.player.can_process()

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
