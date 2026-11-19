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
	queue_redraw()


## The paired arcs make the breathing cost readable at the character, matching the HUD's live
## lung meter. They render in the fixed world viewport so they stay registered to her body.
func _draw() -> void:
	if feedback == null or not feedback.enabled or GameState.is_dead or not feedback.player.can_process():
		return
	_draw_character_arcs()


func _draw_character_arcs() -> void:
	var breath: Node = feedback.breath
	# This Control is drawn in PixelDisplay's world SubViewport. The ordinary
	# get_global_transform_with_canvas() uses the root window canvas (including
	# letterbox/output scaling), which puts the arcs far away from the player.
	# Map the player's world position through the same camera transform as _focus_uv.
	var view: SubViewport = PixelDisplay.world_view
	var transform: Transform2D = view.canvas_transform * feedback.appearance.global_transform
	var at: Vector2 = transform.origin
	if not at.is_finite():
		return
	var scale_factor: float = clampf(transform.get_scale().x, 1.0, 2.2)
	var effect_strength: float = feedback.effects_strength

	# Paired lung brackets drain with held breath and turn amber/red as air runs low.
	if breath.is_holding:
		var lung: float = clampf(breath.lung_percent / 100.0, 0.0, 1.0)
		var threshold: float = clampf(breath.quiet_exhale_lung_threshold / 100.0, 0.0, 1.0)
		var radius: float = (30.0 - feedback.pulse * (1.8 if feedback.strain > 0.3 else 0.4)) * scale_factor
		var fill := Color("b7d8d2")
		if breath.lung_percent <= breath.quiet_exhale_lung_threshold or breath.exertion_percent >= 80.0:
			fill = Color("d64f42").lerp(Color("f2b0a0"), feedback.pulse * 0.45)
		elif breath.lung_percent <= 38.0:
			fill = Color("e2a45b")
		fill.a = (0.68 + feedback.pulse * 0.24) * effect_strength
		for side_value in [0.0, PI]:
			var side: float = side_value
			var from_angle: float = side - 0.56
			var to_angle: float = side + 0.56
			var bottom: float = side + 0.56 if side == 0.0 else side - 0.56
			var top: float = side - 0.56 if side == 0.0 else side + 0.56
			draw_arc(at, radius, from_angle, to_angle, 14, Color(0.05, 0.06, 0.07, 0.62 * effect_strength), 4.5, true)
			var danger_end: float = lerpf(bottom, top, threshold)
			draw_arc(at, radius, minf(bottom, danger_end), maxf(bottom, danger_end), 6, Color(0.84, 0.31, 0.26, 0.45 * effect_strength), 3.0, true)
			if lung > 0.01:
				var fill_end := lerpf(bottom, top, lung)
				draw_arc(at, radius, minf(bottom, fill_end), maxf(bottom, fill_end), 12, fill, 2.2, true)
			var tick: Vector2 = Vector2.from_angle(danger_end)
			draw_line(at + tick * (radius - 3.5), at + tick * (radius + 3.5), Color(0.95, 0.90, 0.80, 0.85 * effect_strength), 1.4, true)

	# Recovery ring fills while the forced gasp lock wears off.
	if breath.is_locked:
		var recovery_radius := 26.0 * scale_factor
		var recovery := clampf(feedback.recovery_fraction, 0.0, 1.0)
		draw_arc(at, recovery_radius, 0.0, TAU, 24, Color(0.05, 0.06, 0.07, 0.55 * effect_strength), 4.0, true)
		draw_arc(at, recovery_radius, -PI * 0.5, -PI * 0.5 + TAU * recovery, 20, Color(0.84, 0.34, 0.28, 0.85 * effect_strength), 2.2, true)

	# A short paired pulse marks inhale, exhale, and the forced gasp.
	var duration := 0.42 if feedback.cue == &"inhale" else 0.60
	var progress := clampf(feedback.cue_age / duration, 0.0, 1.0)
	var event_active: bool = progress < 1.0 and feedback.cue != &""
	var warning_active: bool = breath.is_holding and feedback.strain > 0.12
	if not event_active and not warning_active:
		return
	var radius: float = lerpf(43.0, 33.0, ease(progress, 0.55)) if feedback.cue == &"inhale" else lerpf(33.0, 48.0, progress)
	radius *= scale_factor
	var color := Color("d66b56") if feedback.cue in [&"gasp", &"release_loud"] else Color("c6cfbe")
	var opacity := sin(pow(progress, 0.65) * PI) * 0.55 * effect_strength
	if not event_active:
		radius = (36.0 - feedback.pulse * 1.8) * scale_factor
		color = Color("d66b56")
		opacity = feedback.strain * (0.14 + feedback.pulse * 0.25) * effect_strength
	if not is_finite(radius) or opacity <= 0.001:
		return
	color.a = opacity
	for side in [0.0, PI]:
		draw_arc(at, radius, side - 0.28, side + 0.28, 12, Color(0.03, 0.04, 0.035, opacity * 0.7), 3.2, true)
		draw_arc(at, radius, side - 0.28, side + 0.28, 12, color, 1.2, true)


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
