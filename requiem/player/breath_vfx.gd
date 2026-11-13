extends Control
## Subjective feedback only: short paired arcs and cold-night vapor are not world-space noise radii.

var feedback: Node
var _edge: ColorRect
var _puffs: Array[Dictionary] = []
var _last_cue: StringName = &""
var _last_cue_age := 999.0
var _pant_timer := 0.0
var _heartbeat_clock := 0.0


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


func _process(delta: float) -> void:
	if feedback == null:
		return
	var strength: float = feedback.effects_strength if feedback.enabled else 0.0
	var locked: bool = feedback.breath.is_locked
	var shock := maxf(0.0, 1.0 - feedback.cue_age / 0.65) if feedback.cue == &"gasp" else 0.0
	var recovery: float = (1.0 - feedback.recovery_fraction) if locked else 0.0
	var edge_alpha: float = feedback.hold_focus * 0.055 \
		+ feedback.strain * (0.035 + feedback.pulse * 0.045) + shock * 0.08 + recovery * 0.035
	_edge.material.set_shader_parameter("strength", minf(edge_alpha, 0.17) * strength)
	_edge.material.set_shader_parameter("tension", maxf(feedback.strain, shock))

	var active: bool = bool(feedback.enabled) and not GameState.is_dead and feedback.player.can_process()
	visible = active
	if not active:
		if not feedback.enabled or GameState.is_dead:
			_puffs.clear()
			_last_cue = &""
			_pant_timer = 0.0
		return

	_heartbeat_clock += delta
	_detect_breath_puffs(delta)
	_tick_puffs(delta)
	queue_redraw()


func _detect_breath_puffs(delta: float) -> void:
	var cue: StringName = feedback.cue
	var age: float = feedback.cue_age
	var is_new_cue := cue != &"" and (cue != _last_cue or age < _last_cue_age)
	_last_cue = cue
	_last_cue_age = age

	if is_new_cue and feedback.effects_strength > 0.0:
		match cue:
			&"release":
				_spawn_vapor_burst(3, 18.0, 34.0, 0.72, Color("d8e3de"), 0.28)
			&"release_loud":
				_spawn_vapor_burst(6, 28.0, 56.0, 0.85, Color("ead6c5"), 0.42)
			&"gasp":
				_spawn_vapor_burst(9, 40.0, 82.0, 0.95, Color("f0cbb4"), 0.55)

	var breath: Node = feedback.breath
	if not breath.is_holding and not breath.is_locked and breath.exertion_percent >= 55.0:
		var interval := lerpf(0.90, 0.44, clampf((breath.exertion_percent - 55.0) / 45.0, 0.0, 1.0))
		_pant_timer += delta
		if _pant_timer >= interval:
			_pant_timer = 0.0
			_spawn_vapor_burst(2, 16.0, 28.0, 0.58, Color("d4ded8"), 0.24)
	else:
		_pant_timer = 0.0


func _spawn_vapor_burst(count: int, min_speed: float, max_speed: float, lifetime: float, color: Color, base_alpha: float) -> void:
	if feedback.appearance == null or feedback.player == null:
		return
	var facing: float = float(feedback.appearance.global_rotation)
	var aim: Node = feedback.player.get_node_or_null("PlayerAim")
	if aim != null and "aim_angle" in aim:
		facing = float(aim.aim_angle)
	var origin: Vector2 = feedback.appearance.global_position + Vector2.from_angle(facing) * 10.0
	for i in count:
		var spread := randf_range(-0.52, 0.52)
		var speed := randf_range(min_speed, max_speed)
		_puffs.append({
			"pos": origin + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)),
			"vel": Vector2.from_angle(facing + spread) * speed + Vector2(0.0, randf_range(-10.0, -3.0)),
			"age": 0.0,
			"life": lifetime * randf_range(0.85, 1.2),
			"radius": randf_range(3.5, 6.8),
			"color": color,
			"alpha": base_alpha * feedback.effects_strength,
		})


func _tick_puffs(delta: float) -> void:
	for i in range(_puffs.size() - 1, -1, -1):
		var puff := _puffs[i]
		puff.age += delta
		if puff.age >= puff.life:
			_puffs.remove_at(i)
			continue
		puff.pos += puff.vel * delta
		puff.vel = puff.vel.lerp(Vector2(0.0, -8.0), delta * 2.8)


func _draw() -> void:
	if feedback == null or not feedback.enabled:
		return
	_draw_edge_throb()
	_draw_vapor_puffs()
	_draw_character_arcs()


func _draw_edge_throb() -> void:
	var strain: float = feedback.strain
	var shock := maxf(0.0, 1.0 - feedback.cue_age / 0.65) if feedback.cue == &"gasp" else 0.0
	var intensity: float = maxf(maxf(0.0, (strain - 0.25) / 0.75), shock) * float(feedback.effects_strength)
	if intensity <= 0.01:
		return
	var pulse: float = 0.55 + 0.45 * float(feedback.pulse)
	var alpha := clampf(intensity * pulse * 0.26, 0.0, 0.28)
	var border_col := Color(0.84, 0.28, 0.23, alpha)
	var vp := get_viewport_rect().size
	var strip := lerpf(4.0, 14.0, intensity)
	draw_rect(Rect2(0.0, 0.0, vp.x, strip), border_col, true)
	draw_rect(Rect2(0.0, vp.y - strip, vp.x, strip), border_col, true)
	draw_rect(Rect2(0.0, strip, strip, vp.y - strip * 2.0), border_col, true)
	draw_rect(Rect2(vp.x - strip, strip, strip, vp.y - strip * 2.0), border_col, true)


func _draw_vapor_puffs() -> void:
	if _puffs.is_empty():
		return
	var canvas_xform := feedback.get_viewport().get_canvas_transform()
	if not canvas_xform.origin.is_finite():
		return
	var zoom_scale := clampf(canvas_xform.get_scale().x, 1.0, 2.2)
	for puff in _puffs:
		var t := clampf(float(puff.age) / float(puff.life), 0.0, 1.0)
		var screen_pos: Vector2 = canvas_xform * Vector2(puff.pos)
		var r: float = float(puff.radius) * lerpf(0.75, 2.35, ease(t, 0.55)) * zoom_scale
		if not screen_pos.is_finite() or not is_finite(r) or r <= 0.1:
			continue
		var a: float = float(puff.alpha) * (1.0 - t) * (1.0 - t)
		var col: Color = puff.color
		col.a = a
		draw_circle(screen_pos, r, col)


func _draw_character_arcs() -> void:
	var breath: Node = feedback.breath
	var xform: Transform2D = feedback.appearance.get_global_transform_with_canvas()
	var at: Vector2 = xform.origin
	if not at.is_finite():
		return
	var raw_scale := xform.get_scale().x
	var scale_factor := clampf(raw_scale if is_finite(raw_scale) else 1.0, 1.0, 2.2)

	# 1) Live curved twin lung brackets while holding breath.
	if breath.is_holding:
		var lung_frac := clampf(breath.lung_percent / 100.0, 0.0, 1.0)
		var quiet_frac := clampf(breath.quiet_exhale_lung_threshold / 100.0, 0.0, 1.0)
		var arc_r: float = (30.0 - float(feedback.pulse) * (1.8 if float(feedback.strain) > 0.3 else 0.4)) * scale_factor
		var span := 0.56
		var fill_col := Color("b7d8d2")
		if breath.lung_percent <= breath.quiet_exhale_lung_threshold or breath.exertion_percent >= 80.0:
			fill_col = Color("d64f42").lerp(Color("f2b0a0"), feedback.pulse * 0.45)
		elif breath.lung_percent <= 38.0:
			fill_col = Color("e2a45b")
		var alpha: float = (0.68 + float(feedback.pulse) * 0.24) * float(feedback.effects_strength)
		var track_col := Color(0.05, 0.06, 0.07, 0.62 * feedback.effects_strength)
		var danger_col := Color(0.84, 0.31, 0.26, 0.45 * feedback.effects_strength)
		fill_col.a = alpha

		for side in [0.0, PI]:
			var bottom_a: float = side + span
			var top_a: float = side - span
			if side > 1.0:
				# Left flank sweeps bottom (+PI - span) up to top (+PI + span) or symmetric vertical fill.
				bottom_a = side - span
				top_a = side + span
			# Dark backdrop arc
			draw_arc(at, arc_r, side - span, side + span, 14, track_col, 4.5, true)
			# Danger bottom 20% zone highlight
			var crit_end := lerpf(bottom_a, top_a, quiet_frac)
			draw_arc(at, arc_r, minf(bottom_a, crit_end), maxf(bottom_a, crit_end), 6, danger_col, 3.0, true)
			# Active lung level fill from bottom up
			if lung_frac > 0.01:
				var fill_end := lerpf(bottom_a, top_a, lung_frac)
				draw_arc(at, arc_r, minf(bottom_a, fill_end), maxf(bottom_a, fill_end), 12, fill_col, 2.2, true)
			# Crisp 20% threshold tick mark
			var tick_dir := Vector2.from_angle(crit_end)
			draw_line(at + tick_dir * (arc_r - 3.5), at + tick_dir * (arc_r + 3.5), Color(0.95, 0.90, 0.80, 0.85 * feedback.effects_strength), 1.4, true)

	# 2) Forced recovery progress arc around character while winded/locked.
	if breath.is_locked:
		var rec_r := 26.0 * scale_factor
		var frac := clampf(feedback.recovery_fraction, 0.0, 1.0)
		var start_a := -PI * 0.5
		draw_arc(at, rec_r, 0.0, TAU, 24, Color(0.05, 0.06, 0.07, 0.55 * feedback.effects_strength), 4.0, true)
		draw_arc(at, rec_r, start_a, start_a + TAU * frac, 20, Color(0.84, 0.34, 0.28, 0.85 * feedback.effects_strength), 2.2, true)

	# 3) Event cues (inhale contraction / exhale & gasp ripples).
	var duration := 0.42 if feedback.cue == &"inhale" else 0.60
	var progress: float = clampf(feedback.cue_age / duration, 0.0, 1.0)
	var event_active: bool = progress < 1.0 and feedback.cue != &""
	var warning_active: bool = breath.is_holding and feedback.strain > 0.12
	if not event_active and not warning_active:
		return
	var radius := lerpf(43.0, 33.0, ease(progress, 0.55)) if feedback.cue == &"inhale" else lerpf(33.0, 48.0, progress)
	radius *= scale_factor
	var color := Color("c6cfbe")
	if feedback.cue in [&"gasp", &"release_loud"]:
		color = Color("d66b56")
	var opacity: float = sin(pow(progress, 0.65) * PI) * 0.55 * feedback.effects_strength
	if not event_active:
		radius = (36.0 - feedback.pulse * 1.8) * scale_factor
		color = Color("d66b56")
		opacity = feedback.strain * (0.14 + feedback.pulse * 0.25) * feedback.effects_strength
	color.a = opacity
	if not is_finite(radius) or radius <= 0.5 or opacity <= 0.001:
		return
	for side in [0.0, PI]:
		var from_angle: float = side - 0.28
		var to_angle: float = side + 0.28
		var shadow := Color(0.03, 0.04, 0.035, opacity * 0.7)
		draw_arc(at, radius, from_angle, to_angle, 12, shadow, 3.2, true)
		draw_arc(at, radius, from_angle, to_angle, 12, color, 1.2, true)
