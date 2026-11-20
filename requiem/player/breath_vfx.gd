extends Control
## Subjective feedback only. The tunnel is drawn over the finished world image (it never changes
## what the lights reveal); breath effects are world-space sprites, drawn unlit so they always read.
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
const DARKNESS_HELD := 0.85
const DARKNESS_STRAINED := 0.97
const DRAIN_HELD := 0.6

var feedback: Node
var _edge: ColorRect
var _armed_cue := &""
var _leak_age := 0.0
var _last_beat := 0.0
var _beats := 0
var _following: Array[Sprite2D] = []
var _unlit := CanvasItemMaterial.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
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
	# The dark at the rim deepens with the strain, and beats with her pulse once it is urgent.
	material.set_shader_parameter("darkness", lerpf(DARKNESS_HELD, DARKNESS_STRAINED, feedback.strain))
	material.set_shader_parameter("drain", lerpf(DRAIN_HELD, 1.0, feedback.strain))
	material.set_shader_parameter("focus", _focus_uv())
	visible = feedback.enabled and not GameState.is_dead and feedback.player.can_process()
	_edge.visible = amount * strength > 0.001

	_follow_head()
	_tick_breath_effects(delta)
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


## One effect per moment of the breath, each from a delivered sheet:
## in (hold starts): air drawn to her mouth; strain (air running short): tension marks and sweat
## on every heartbeat, then air leaking from her lips; out (release, late release, forced gasp):
## one puff, a fan of three, or a burst followed by panting while she recovers.
func _tick_breath_effects(delta: float) -> void:
	if feedback.cue != _armed_cue:
		_armed_cue = feedback.cue
		match feedback.cue:
			&"inhale": _spawn(&"in", IN_TEXTURE, IN_MS, IN_ANCHOR, 0.0, MOUTH_FORWARD, true)
			&"release": _spawn_puff()
			&"release_loud": _burst(LOUD_FAN, 0.05)
			&"gasp": _burst(GASP_FAN, 0.0)
	var beat: float = feedback.beat_phase
	var new_beat := beat < _last_beat
	_last_beat = beat
	if feedback.breath.is_holding and feedback.strain > STRAIN_MARKS_FROM:
		_leak_age += delta
		if new_beat:
			_beats += 1
			# Every other beat at first, every beat (both sides) once it is urgent.
			var urgent: bool = feedback.strain > STRAIN_URGENT
			if urgent or _beats % 2 == 0:
				_spawn(&"strain", STRAIN_TEXTURE, STRAIN_MS, STRAIN_ANCHOR, 0.0, 0.0, true, _beats % 4 < 2)
			if urgent:
				_spawn(&"strain", STRAIN_TEXTURE, STRAIN_MS, STRAIN_ANCHOR, 0.0, 0.0, true, _beats % 4 >= 2)
			if feedback.strain > STRAIN_LEAK_FROM and _leak_age > lerpf(1.6, 0.7, feedback.strain):
				_leak_age = 0.0
				_spawn_puff(&"leak")
	else:
		_leak_age = 0.0
		_beats = 0
	# Recovering from a forced gasp she pants: a puff on every heartbeat until her air is back.
	if feedback.breath.is_locked and new_beat and feedback.cue_age > 0.3:
		_spawn_puff(&"pant")


func _burst(fan: Array, stagger: float) -> void:
	for index in fan.size():
		if stagger <= 0.0 or index == 0:
			_spawn_puff(&"out", deg_to_rad(fan[index]))
		else:
			get_tree().create_timer(stagger * index).timeout.connect(_spawn_puff.bind(&"out", deg_to_rad(fan[index])))


func _spawn_puff(kind := &"out", turn := 0.0) -> void:
	_spawn(kind, BREATH_TEXTURE, FRAME_MS, ANCHOR, turn, MOUTH_FORWARD, false)


## `turn` swings the effect off her facing; `forward` is art px from the head centre toward the
## face. `follow` keeps it on her head as she moves (air she breathes out is left behind instead).
func _spawn(kind: StringName, texture: Texture2D, timings: Array[int], anchor: Vector2, turn := 0.0,
		forward := 0.0, follow := false, mirrored := false) -> void:
	if feedback.effects_strength <= 0.0 or not is_instance_valid(feedback.appearance.rig): return
	var fx := VfxSheet.new()
	feedback.player.get_parent().add_child(fx)
	fx.set_as_top_level(true)
	fx.z_index = 42
	# Her breath is feedback for the player, like the pickup stars: drawn unlit and pale, or the
	# slate of the sheets vanishes in exactly the dark rooms where she holds her breath.
	fx.material = _unlit
	fx.modulate = BREATH_TINT
	fx.add_to_group(&"breath_vfx")
	fx.set_meta(&"kind", kind)
	fx.set_meta(&"turn", turn)
	fx.set_meta(&"forward", forward)
	fx.play(texture, timings.size(), timings, anchor)
	# These turn with her head, so the sheet's anchor has to sit exactly on the node: Sprite2D
	# offsets are in texture pixels (VfxSheet scales its anchor down, which only suits unturned art).
	fx.offset = -anchor
	if mirrored:
		fx.scale.x = -fx.scale.x
	_place(fx)
	if follow: _following.append(fx)


func _place(fx: Sprite2D) -> void:
	var rig: Node2D = feedback.appearance.rig
	var head: Vector2 = rig.anchor_global("head_center") if rig.has_anchor("head_center") else rig.global_position
	# The art faces south: the rig's rotation carries "down the sheet" onto her facing.
	var heading: float = rig.global_rotation
	var turned: float = heading + float(fx.get_meta(&"turn"))
	fx.global_rotation = turned
	fx.global_position = head + Vector2.DOWN.rotated(turned) * float(fx.get_meta(&"forward")) * Units.ART_SCALE


func _follow_head() -> void:
	for index in range(_following.size() - 1, -1, -1):
		var fx: Sprite2D = _following[index]
		if not is_instance_valid(fx) or fx.is_queued_for_deletion():
			_following.remove_at(index)
		else:
			_place(fx)


const BREATH_TEXTURE := preload("res://assets/art/vfx/vfx_breath_puff.png")
## vfx_breath_puff.json: 90, 130, 120, 100 ms; anchor at 16,6 of a 32x32 frame.
const FRAME_MS: Array[int] = [90, 130, 120, 100]
const ANCHOR := Vector2(16, 6)
## vfx_breath_in.json (stand-in art): 4 x 70 ms; anchor (the mouth) at 24,8 of a 48x48 frame.
const IN_TEXTURE := preload("res://assets/art/vfx/vfx_breath_in.png")
const IN_MS: Array[int] = [70, 70, 70, 70]
const IN_ANCHOR := Vector2(24, 8)
## vfx_breath_strain.json (stand-in art): 80, 100, 120 ms; anchor (head centre) at 32,32 of 64x64.
const STRAIN_TEXTURE := preload("res://assets/art/vfx/vfx_breath_strain.png")
const STRAIN_MS: Array[int] = [80, 100, 120]
const STRAIN_ANCHOR := Vector2(32, 32)
const VfxSheet := preload("res://level/vfx_sheet.gd")
## Art px from the head centre to her lips.
const MOUTH_FORWARD := 25.0
## The sheets are painted in dark slate for lit air; unlit they are lifted to a cold pale grey.
const BREATH_TINT := Color(2.0, 2.1, 2.25, 0.92)
## Strain (0..1) at which the marks start, come on every beat, and air starts to leak.
const STRAIN_MARKS_FROM := 0.12
const STRAIN_URGENT := 0.6
const STRAIN_LEAK_FROM := 0.4
## Degrees off her facing for each puff of a late release and of a forced gasp.
const LOUD_FAN := [0.0, -42.0, 42.0]
const GASP_FAN := [0.0, -26.0, 26.0, -52.0, 52.0]


## Her position in the world image, as UV.
func _focus_uv() -> Vector2:
	var view: SubViewport = PixelDisplay.world_view
	var at: Vector2 = view.canvas_transform * feedback.player.global_position
	return at / Vector2(view.size)
