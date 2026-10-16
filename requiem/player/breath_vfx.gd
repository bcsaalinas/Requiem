extends Control
## Subjective feedback only: short paired arcs are not world-space noise radii.

var feedback: Node
var _edge: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge = ColorRect.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := ShaderMaterial.new()
	style.shader = preload("res://player/breath_vignette.gdshader")
	_edge.material = style
	add_child(_edge)
	move_child(_edge, 0)


func _process(_delta: float) -> void:
	var strength: float = feedback.effects_strength if feedback.enabled else 0.0
	var locked: bool = feedback.breath.is_locked
	var shock := maxf(0.0, 1.0 - feedback.cue_age / 0.65) if feedback.cue == &"gasp" else 0.0
	var recovery: float = (1.0 - feedback.recovery_fraction) if locked else 0.0
	var edge_alpha: float = feedback.hold_focus * 0.055 \
		+ feedback.strain * (0.035 + feedback.pulse * 0.045) + shock * 0.08 + recovery * 0.035
	_edge.material.set_shader_parameter("strength", minf(edge_alpha, 0.17) * strength)
	_edge.material.set_shader_parameter("tension", maxf(feedback.strain, shock))
	visible = feedback.enabled and not GameState.is_dead and feedback.player.can_process()
	queue_redraw()


func _draw() -> void:
	if feedback == null or not feedback.enabled: return
	var duration := 0.42 if feedback.cue == &"inhale" else 0.60
	var progress: float = clampf(feedback.cue_age / duration, 0.0, 1.0)
	var event_active: bool = progress < 1.0 and feedback.cue != &""
	var warning_active: bool = feedback.breath.is_holding and feedback.strain > 0.12
	if not event_active and not warning_active: return
	var at: Vector2 = feedback.appearance.get_global_transform_with_canvas().origin
	# Screen-space width remains restrained at any gameplay camera zoom.
	var scale_factor: float = feedback.appearance.get_global_transform_with_canvas().get_scale().x
	var radius := lerpf(43.0, 33.0, ease(progress, 0.55)) if feedback.cue == &"inhale" else lerpf(33.0, 45.0, progress)
	radius *= clampf(scale_factor, 1.0, 2.2)
	var color := Color("c6cfbe")
	if feedback.cue in [&"gasp", &"release_loud"]: color = Color("c4997d")
	var opacity: float = sin(pow(progress, 0.65) * PI) * 0.48 * feedback.effects_strength
	if not event_active:
		# Reuse the same restrained marks for pressure near the character, so
		# reading low air never requires looking away to the corner meter.
		radius = (34.0 - feedback.pulse * 1.6) * clampf(scale_factor, 1.0, 2.2)
		color = Color("c4997d")
		opacity = feedback.strain * (0.12 + feedback.pulse * 0.22) * feedback.effects_strength
	color.a = opacity
	for side in [0.0, PI]:
		var from_angle: float = side - 0.24
		var to_angle: float = side + 0.24
		var shadow := Color(0.03, 0.04, 0.035, opacity * 0.7)
		draw_arc(at, radius, from_angle, to_angle, 12, shadow, 3.0, true)
		draw_arc(at, radius, from_angle, to_angle, 12, color, 1.0, true)
