extends HBoxContainer
## Beta vitals: each bar behaves like the organ or tool it stands for, with
## framed cards, vector icons, threshold markers, trailing drain and clear states.
##
## Division of labour: tutorial.gd writes hud.breath/effort/battery every frame,
## so this script never mutates `ProgressBar.value`. It owns all visual styling
## — colour, card chrome, icons, pulses, ghost trails and jitter.

@export_group("Sources")
@export var player_path: NodePath

@export_group("Breath")
## Looks only: the breath bar turns amber under this much air.
@export var breath_warn: float = 45.0
# The red mark on the breath bar is the mechanic's own line: HoldBreath.quiet_exhale_lung_threshold,
# under which letting go is a gasp the entity hears. Read from her when the meters find her.
var breath_critical: float = 20.0
@export var beat_rate_max: float = 3.4

@export_group("Exertion")
# The bar starts pulsing and the row jitters above the player's HoldBreath.exertion_warn_percent
# (one number, shared with her panting), read from her every frame: the meters keep no copy.
# The tick on the exertion bar stands on that same number.
## Looks only: the exertion bar turns red past this. The mechanic has two lines, the warning
## above and the forced gasp at 100; this is just how late the red comes between them.
@export var exertion_critical: float = 80.0

@export_group("Feel")
@export var jitter: float = 2.0
@export var colour_speed: float = 8.0
@export var idle_sway: float = 0.08

var _breath_box: VBoxContainer
var _exertion_box: VBoxContainer
var _battery_box: VBoxContainer

var _breath_bar: ProgressBar
var _exertion_bar: ProgressBar
var _battery_bar: ProgressBar

var _breath_caption: Label
var _exertion_caption: Label
var _battery_caption: Label

var _breath_fill: StyleBoxFlat
var _exertion_fill: StyleBoxFlat
var _battery_fill: StyleBoxFlat
var _breath_track: StyleBoxFlat
var _exertion_track: StyleBoxFlat
var _battery_track: StyleBoxFlat

var _breath_overlay: Control
var _exertion_overlay: Control
var _battery_overlay: Control

var _player: Node
var _actions: Node
var _breath_node: Node
var _feedback: Node
var _flashlight: PointLight2D

var _clock: float = 0.0
var _beat_phase: float = 0.0
var _exertion_beat: float = 0.0
var _was_gasping: bool = false
var _was_holding: bool = false
var _was_flashlight_on: bool = false
var _prev_battery: float = -1.0
var _home: Vector2

var _breath_ghost: float = 100.0
var _exertion_ghost: float = 0.0
var _battery_ghost: float = 100.0

var _breath_flash: float = 0.0
var _exertion_flash: float = 0.0
var _battery_flash: float = 0.0
var _gasp_shake: float = 0.0

var _spares: int = 0
var _is_resting: bool = false
var _font: Font


class MeterOverlay extends Control:
	var kind: StringName = &"breath"
	var meter: ProgressBar
	var ghost_value: float = 0.0
	var threshold: float = 20.0
	var recovery_fraction: float = -1.0
	var urgency: float = 0.0
	var is_holding: bool = false
	var is_on: bool = false

	func _init(p_kind: StringName, p_meter: ProgressBar) -> void:
		kind = p_kind
		meter = p_meter
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if meter == null or size.x <= 2.0 or size.y <= 2.0:
			return
		var w := size.x
		var h := size.y
		var val_frac := clampf(meter.value / 100.0, 0.0, 1.0)
		var ghost_frac := clampf(ghost_value / 100.0, 0.0, 1.0)

		# Danger zone backdrop
		if kind == &"breath":
			var crit_w := w * (threshold / 100.0)
			var zone := UIPalette.DANGER_ZONE
			zone.a = lerpf(0.24, 0.52, urgency if is_holding else 0.0)
			draw_rect(Rect2(0, 0, crit_w, h), zone)
		elif kind == &"exertion":
			var crit_x := w * (threshold / 100.0)
			var zone := UIPalette.DANGER_ZONE
			zone.a = lerpf(0.22, 0.52, urgency)
			draw_rect(Rect2(crit_x, 0, w - crit_x, h), zone)
		elif kind == &"battery":
			var low_w := w * (threshold / 100.0)
			var zone := UIPalette.DANGER_ZONE
			zone.a = 0.22 if meter.value > threshold else 0.45
			draw_rect(Rect2(0, 0, low_w, h), zone)

		# Trailing ghost fill for sudden drops / refills
		if kind == &"breath" or kind == &"battery":
			if ghost_frac > val_frac + 0.005:
				var x0 := val_frac * w
				var gw := (ghost_frac - val_frac) * w
				draw_rect(Rect2(x0, 1.0, gw, h - 2.0), UIPalette.GHOST_TRAIL)
		elif kind == &"exertion":
			if ghost_frac < val_frac - 0.005:
				var x0 := ghost_frac * w
				var gw := (val_frac - ghost_frac) * w
				draw_rect(Rect2(x0, 1.0, gw, h - 2.0), UIPalette.GHOST_TRAIL)

		# Forced recovery countdown bar across the Breath track
		if kind == &"breath" and recovery_fraction >= 0.0:
			var rec_w := w * clampf(recovery_fraction, 0.0, 1.0)
			draw_rect(Rect2(0, h - 3.0, rec_w, 3.0), UIPalette.CANDLE)

		# Threshold ticks / battery cell dividers
		if kind == &"breath":
			var tx := roundf(w * (threshold / 100.0))
			draw_line(Vector2(tx, -1.0), Vector2(tx, h + 1.0), Color(0.95, 0.55, 0.48, 0.92), 2.0)
			draw_line(Vector2(roundf(w * 0.5), 2.0), Vector2(roundf(w * 0.5), h - 2.0), Color(0.9, 0.9, 0.85, 0.22), 1.0)
		elif kind == &"exertion":
			var tx := roundf(w * (threshold / 100.0))
			draw_line(Vector2(tx, -1.0), Vector2(tx, h + 1.0), Color(0.95, 0.55, 0.48, 0.92), 2.0)
			draw_line(Vector2(roundf(w * 0.5), 2.0), Vector2(roundf(w * 0.5), h - 2.0), Color(0.9, 0.9, 0.85, 0.22), 1.0)
		elif kind == &"battery":
			for frac in [0.25, 0.5, 0.75]:
				var cx := roundf(w * frac)
				draw_line(Vector2(cx, 0.0), Vector2(cx, h), Color(0.03, 0.035, 0.03, 0.9), 2.0)

		# Subtle top highlight + crisp outer hairline
		if val_frac > 0.02:
			draw_line(Vector2(1.0, 1.0), Vector2(maxf(2.0, val_frac * w - 1.0), 1.0), Color(1, 1, 1, 0.18), 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.85, 0.78, 0.16), false, 1.0)


func _ready() -> void:
	_breath_box = get_node_or_null("Breath")
	_exertion_box = get_node_or_null("Exertion")
	_battery_box = get_node_or_null("Battery")

	_breath_bar = get_node_or_null("Breath/Meter")
	_exertion_bar = get_node_or_null("Exertion/Meter")
	_battery_bar = get_node_or_null("Battery/Meter")

	_breath_caption = get_node_or_null("Breath/Caption")
	_exertion_caption = get_node_or_null("Exertion/Caption")
	_battery_caption = get_node_or_null("Battery/Caption")

	_font = ThemeDB.fallback_font
	if _breath_caption:
		_font = _breath_caption.get_theme_font("font")

	_breath_fill = UIPalette.flat(UIPalette.BONE)
	_exertion_fill = UIPalette.flat(UIPalette.AMBER)
	_battery_fill = UIPalette.flat(UIPalette.BATTERY_ON)
	_breath_track = UIPalette.flat(UIPalette.TRACK)
	_exertion_track = UIPalette.flat(UIPalette.TRACK)
	_battery_track = UIPalette.flat(UIPalette.TRACK)

	if _breath_bar:
		_breath_bar.add_theme_stylebox_override("fill", _breath_fill)
		_breath_bar.add_theme_stylebox_override("background", _breath_track)
		_breath_overlay = MeterOverlay.new(&"breath", _breath_bar)
		_breath_bar.add_child(_breath_overlay)
	if _exertion_bar:
		_exertion_bar.add_theme_stylebox_override("fill", _exertion_fill)
		_exertion_bar.add_theme_stylebox_override("background", _exertion_track)
		_exertion_overlay = MeterOverlay.new(&"exertion", _exertion_bar)
		_exertion_overlay.threshold = exertion_critical
		_exertion_bar.add_child(_exertion_overlay)
	if _battery_bar:
		_battery_bar.add_theme_stylebox_override("fill", _battery_fill)
		_battery_bar.add_theme_stylebox_override("background", _battery_track)
		_battery_overlay = MeterOverlay.new(&"battery", _battery_bar)
		_battery_overlay.threshold = 25.0
		_battery_bar.add_child(_battery_overlay)

	# Indent captions slightly so vector icons sit cleanly inside each card header.
	var indent := StyleBoxEmpty.new()
	indent.content_margin_left = 24.0
	for cap in [_breath_caption, _exertion_caption, _battery_caption]:
		if cap != null:
			cap.add_theme_stylebox_override("normal", indent)

	_home = position
	_resolve_player()


func _resolve_player() -> void:
	if player_path != NodePath():
		_player = get_node_or_null(player_path)
	if _player == null:
		var found := get_tree().get_nodes_in_group("player")
		if not found.is_empty():
			_player = found[0]
	if _player != null:
		_actions = _player.get_node_or_null("ActionState")
		var hold_breath: Node = _player.get_node_or_null("HoldBreath")
		if hold_breath != null:
			breath_critical = hold_breath.quiet_exhale_lung_threshold
			breath_warn = maxf(breath_warn, breath_critical)
			if _breath_overlay != null:
				_breath_overlay.threshold = breath_critical
		_breath_node = _player.get_node_or_null("HoldBreath")
		_feedback = _player.get_node_or_null("BreathFeedback")
		_flashlight = _player.get_node_or_null("flashlight")
		if _flashlight != null and _battery_overlay != null:
			_battery_overlay.threshold = _flashlight.low_battery_threshold


## The exertion % past which the bar warns: the player's own number, read live. With no
## HoldBreath there is no exertion to warn about.
func _warn_at() -> float:
	return float(_breath_node.exertion_warn_percent) if _breath_node != null and is_instance_valid(_breath_node) else INF


func set_equipment_context(spares: int) -> void:
	_spares = spares


func _process(delta: float) -> void:
	if _player == null:
		_resolve_player()
		return

	_clock += delta
	var action: StringName = _actions.get_action() if _actions != null else &"idle"

	_breath_flash = maxf(0.0, _breath_flash - delta * 2.8)
	_exertion_flash = maxf(0.0, _exertion_flash - delta * 2.8)
	_battery_flash = maxf(0.0, _battery_flash - delta * 2.8)
	_gasp_shake = maxf(0.0, _gasp_shake - delta * 3.0)

	_drive_breath(delta, action)
	_drive_exertion(delta, action)
	_drive_battery(delta)
	_check_gasp(action)
	queue_redraw()


func _drive_breath(delta: float, action: StringName) -> void:
	if _breath_bar == null:
		return

	var lung: float = _breath_bar.value
	var held: bool = action == &"hold_breath"
	var locked: bool = action == &"forced_gasp"

	if held and not _was_holding:
		_breath_flash = 0.75
	elif not held and _was_holding:
		_breath_flash = maxf(_breath_flash, 0.45)
	_was_holding = held

	_breath_ghost = lerpf(_breath_ghost, lung, clampf(delta * (2.5 if lung < _breath_ghost else 10.0), 0.0, 1.0))

	var urgency: float = 0.0
	if lung < breath_warn:
		urgency = clampf((breath_warn - lung) / maxf(breath_warn, 0.001), 0.0, 1.0)
	var crit_urgency: float = 0.0
	if lung <= breath_critical:
		crit_urgency = clampf((breath_critical - lung) / maxf(breath_critical, 0.001), 0.0, 1.0)

	var target := UIPalette.BREATH_HOLD if held else UIPalette.BONE
	if held and lung < breath_warn:
		target = UIPalette.BREATH_HOLD.lerp(UIPalette.BREATH_WARN, smoothstep(breath_warn, breath_critical, lung))
	if lung <= breath_critical and (held or locked):
		target = target.lerp(UIPalette.BREATH_CRIT, 0.55 + 0.45 * crit_urgency)
	elif locked:
		target = UIPalette.BREATH_CRIT.lerp(UIPalette.BONE, _feedback.recovery_fraction if _feedback != null else 0.0)

	if _breath_caption and _feedback != null and _feedback.has_method("get_meter_caption"):
		_breath_caption.text = _feedback.get_meter_caption()
		var cap_color := UIPalette.BREATH_HOLD if held and lung >= breath_warn else UIPalette.BONE
		if held and lung < breath_warn:
			cap_color = cap_color.lerp(UIPalette.BREATH_CRIT if lung <= breath_critical else UIPalette.BREATH_WARN, urgency)
		elif _breath_node != null and _breath_node.needs_release:
			cap_color = UIPalette.CANDLE
		elif locked:
			cap_color = UIPalette.BREATH_CRIT.lerp(UIPalette.CANDLE, 0.4)
		_breath_caption.add_theme_color_override("font_color", cap_color)

	_breath_bar.pivot_offset = _breath_bar.size * 0.5
	if held:
		_breath_track.bg_color = _breath_track.bg_color.lerp(
			UIPalette.TRACK.darkened(0.45), clampf(colour_speed * delta, 0.0, 1.0)
		)
		if urgency > 0.0:
			_beat_phase += delta * lerpf(1.1, beat_rate_max, urgency) * TAU
			var beat: float = pow(maxf(sin(_beat_phase), 0.0), 3.0)
			_breath_bar.modulate.a = lerpf(0.82, 1.0, beat)
			_breath_bar.scale.y = 1.0 + beat * urgency * 0.45
			if _breath_caption:
				_breath_caption.modulate.a = lerpf(0.75, 1.0, beat)
		else:
			# Stillness while safely held: the HUD holds its breath with the player.
			_beat_phase = 0.0
			_breath_bar.scale.y = 1.0
			_breath_bar.modulate.a = 1.0
			if _breath_caption:
				_breath_caption.modulate.a = 0.95
	else:
		_breath_track.bg_color = _breath_track.bg_color.lerp(
			UIPalette.TRACK, clampf(colour_speed * delta, 0.0, 1.0)
		)
		if urgency > 0.0:
			_beat_phase += delta * lerpf(0.8, beat_rate_max, urgency) * TAU
			var beat: float = pow(maxf(sin(_beat_phase), 0.0), 3.0)
			_breath_bar.modulate.a = lerpf(0.78, 1.0, beat)
			_breath_bar.scale.y = 1.0 + beat * urgency * 0.35
			if _breath_caption:
				_breath_caption.modulate.a = lerpf(0.65, 1.0, beat)
		else:
			_beat_phase = 0.0
			_breath_bar.modulate.a = 1.0
			_breath_bar.scale.y = 1.0 + sin(_clock * 1.1) * idle_sway
			if _breath_caption:
				_breath_caption.modulate.a = 1.0

	if _breath_flash > 0.0:
		target = target.lerp(Color(1.0, 0.97, 0.88), _breath_flash * 0.65)
	_breath_fill.bg_color = _breath_fill.bg_color.lerp(target, clampf(colour_speed * delta, 0.0, 1.0))

	if _breath_overlay != null:
		_breath_overlay.ghost_value = _breath_ghost
		_breath_overlay.urgency = urgency
		_breath_overlay.is_holding = held
		_breath_overlay.recovery_fraction = _feedback.recovery_fraction if (locked and _feedback != null) else -1.0
		_breath_overlay.queue_redraw()


func _drive_exertion(delta: float, action: StringName) -> void:
	if _exertion_bar == null:
		return

	var effort: float = _exertion_bar.value
	_exertion_ghost = lerpf(_exertion_ghost, effort, clampf(delta * (3.0 if effort > _exertion_ghost else 8.0), 0.0, 1.0))

	var speed_u: float = _player.get_speed_u() if (_player != null and _player.has_method("get_speed_u")) else 0.0
	var calm_u: float = _breath_node.calm_speed_threshold_u if _breath_node != null else 0.1
	_is_resting = effort > 0.5 and action in [&"idle", &"walk"] and speed_u <= calm_u

	var urgency: float = 0.0
	var exertion_warn := _warn_at()
	if _exertion_overlay != null:
		_exertion_overlay.threshold = minf(exertion_warn, 100.0)
	if effort > exertion_warn:
		var span: float = maxf(100.0 - exertion_warn, 0.001)
		urgency = clampf((effort - exertion_warn) / span, 0.0, 1.0)

	var target := UIPalette.AMBER
	if _is_resting:
		target = UIPalette.AMBER.lerp(UIPalette.EXERTION_REST, 0.45)
	elif effort > exertion_critical:
		target = UIPalette.AMBER.lerp(UIPalette.EXERTION_HOT, urgency)

	var rate := lerpf(1.2, 3.8, clampf(effort / 100.0, 0.0, 1.0))
	if action == &"sprint":
		rate *= 1.35
	_exertion_beat = fposmod(_exertion_beat + delta * rate * TAU, TAU)

	_exertion_bar.pivot_offset = _exertion_bar.size * 0.5
	if urgency > 0.0:
		var pulse: float = (sin(_exertion_beat) + 1.0) * 0.5
		_exertion_bar.modulate.a = lerpf(0.76, 1.0, pulse)
		_exertion_bar.scale.y = 1.0 + pulse * urgency * 0.25
		position.x = _home.x + randf_range(-jitter, jitter) * urgency + randf_range(-3.0, 3.0) * _gasp_shake
		if _exertion_caption:
			_exertion_caption.modulate.a = lerpf(0.68, 1.0, pulse)
	else:
		_exertion_bar.modulate.a = 1.0
		_exertion_bar.scale.y = 1.0
		var shake_x := randf_range(-3.0, 3.0) * _gasp_shake
		position.x = lerpf(position.x, _home.x + shake_x, clampf(delta * 12.0, 0.0, 1.0))
		if _exertion_caption:
			_exertion_caption.modulate.a = 1.0

	if _exertion_caption:
		var cap_color := UIPalette.EXERTION_REST if _is_resting else UIPalette.AMBER
		if effort >= exertion_critical:
			cap_color = UIPalette.EXERTION_HOT
		_exertion_caption.add_theme_color_override("font_color", cap_color)

	if _exertion_flash > 0.0:
		target = target.lerp(Color(1.0, 0.9, 0.8), _exertion_flash * 0.7)
	_exertion_fill.bg_color = _exertion_fill.bg_color.lerp(target, clampf(colour_speed * delta, 0.0, 1.0))

	if _exertion_overlay != null:
		_exertion_overlay.ghost_value = _exertion_ghost
		_exertion_overlay.urgency = urgency
		_exertion_overlay.queue_redraw()


func _drive_battery(delta: float) -> void:
	if _battery_bar == null or _battery_box == null or not _battery_box.visible:
		return

	var charge: float = _battery_bar.value
	if _prev_battery >= 0.0 and charge - _prev_battery > 20.0:
		_battery_flash = 1.0
	_prev_battery = charge

	var is_on: bool = _flashlight != null and _flashlight.is_on and charge > 0.0
	if is_on != _was_flashlight_on:
		_battery_flash = maxf(_battery_flash, 0.7)
	_was_flashlight_on = is_on

	_battery_ghost = lerpf(_battery_ghost, charge, clampf(delta * 3.5, 0.0, 1.0))

	var low_thresh: float = _flashlight.low_battery_threshold if _flashlight != null else 25.0
	var is_low := charge > 0.0 and charge <= low_thresh
	var target := UIPalette.BATTERY_ON if is_on else UIPalette.BATTERY_OFF
	if charge <= 0.0:
		target = UIPalette.BREATH_CRIT
	elif is_low:
		var flicker := 0.5 + 0.5 * sin(_clock * 11.0)
		target = UIPalette.BATTERY_LOW.lerp(UIPalette.BATTERY_ON, flicker * 0.35 if is_on else 0.0)

	if _battery_flash > 0.0:
		target = target.lerp(Color.WHITE, _battery_flash * 0.65)
	_battery_fill.bg_color = _battery_fill.bg_color.lerp(target, clampf(colour_speed * delta, 0.0, 1.0))

	if _battery_caption:
		var cap_color := UIPalette.BATTERY_ON if is_on else UIPalette.TEXT_DIM
		if charge <= 0.0:
			cap_color = UIPalette.BREATH_CRIT
		elif is_low:
			cap_color = UIPalette.BATTERY_LOW
		_battery_caption.add_theme_color_override("font_color", cap_color)

	if _battery_overlay != null:
		_battery_overlay.ghost_value = _battery_ghost
		_battery_overlay.is_on = is_on
		_battery_overlay.urgency = 1.0 if is_low or charge <= 0.0 else 0.0
		_battery_overlay.queue_redraw()


func _check_gasp(action: StringName) -> void:
	var gasping: bool = action == &"forced_gasp"
	if gasping and not _was_gasping:
		_breath_flash = 1.0
		_exertion_flash = 1.0
		_gasp_shake = 1.0
		for bar in [_breath_bar, _exertion_bar]:
			if bar == null:
				continue
			bar.modulate = Color(1.6, 1.3, 1.2)
			var tween := create_tween()
			tween.tween_property(bar, "modulate", Color.WHITE, 0.45)
	_was_gasping = gasping


func _draw() -> void:
	var action: StringName = _actions.get_action() if _actions != null else &"idle"
	_draw_breath_card(action)
	_draw_exertion_card(action)
	_draw_battery_card()


func _draw_card_box(box: Control, border: Color, glow_alpha: float) -> Rect2:
	var rect := Rect2(box.position - Vector2(10, 6), box.size + Vector2(20, 12))
	if glow_alpha > 0.01:
		var glow_col := border
		glow_col.a = glow_alpha * 0.25
		draw_rect(rect.grow(3.0), glow_col)
	draw_rect(rect, UIPalette.CARD_BG)
	draw_rect(rect, border, false, 1.5 if glow_alpha > 0.2 else 1.0)
	return rect


func _draw_badge(rect: Rect2, label_text: String, color: Color, align_y: float) -> void:
	if _font == null or label_text.is_empty():
		return
	var font_size := 13
	var text_size := _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(6, 2)
	var badge_rect := Rect2(
		Vector2(rect.end.x - 8.0 - text_size.x - pad.x * 2.0, align_y - text_size.y * 0.5 - pad.y + 1.0),
		Vector2(text_size.x + pad.x * 2.0, text_size.y + pad.y)
	)
	var bg := Color(color.r, color.g, color.b, 0.16)
	var bd := Color(color.r, color.g, color.b, 0.65)
	draw_rect(badge_rect, bg)
	draw_rect(badge_rect, bd, false, 1.0)
	draw_string(_font, Vector2(badge_rect.position.x + pad.x, badge_rect.end.y - pad.y - 2.0),
		label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_breath_card(action: StringName) -> void:
	if _breath_box == null or not _breath_box.visible:
		return
	var lung := _breath_bar.value if _breath_bar else 100.0
	var held := action == &"hold_breath"
	var locked := action == &"forced_gasp"
	var needs_rel: bool = _breath_node != null and _breath_node.needs_release

	var border := UIPalette.CARD_BORDER
	var glow := 0.0
	var badge := "[SPACE]"
	var badge_col := UIPalette.TEXT_DIM

	if locked:
		border = UIPalette.BREATH_CRIT
		glow = 0.65
		badge = "LOCKED"
		badge_col = UIPalette.BREATH_CRIT
	elif needs_rel:
		var blink := 0.5 + 0.5 * sin(_clock * 10.0)
		border = UIPalette.CANDLE.lerp(UIPalette.BREATH_CRIT, blink * 0.4)
		glow = 0.45 + 0.35 * blink
		badge = "REL"
		badge_col = UIPalette.CANDLE
	elif held:
		if lung <= breath_critical:
			var beat := pow(maxf(sin(_beat_phase), 0.0), 2.0)
			border = UIPalette.BREATH_CRIT
			glow = 0.5 + 0.5 * beat
			badge = "GASP!"
			badge_col = UIPalette.BREATH_CRIT
		elif lung < breath_warn:
			border = UIPalette.BREATH_WARN
			glow = 0.45
			badge = "LOW"
			badge_col = UIPalette.BREATH_WARN
		else:
			border = UIPalette.BREATH_HOLD
			glow = 0.45
			badge = "HELD"
			badge_col = UIPalette.BREATH_HOLD
	elif lung < 99.0:
		border = UIPalette.BONE.darkened(0.25)
		badge = "REFILL"
		badge_col = UIPalette.BONE

	border = border.lerp(Color.WHITE, _breath_flash * 0.6)
	var rect := _draw_card_box(_breath_box, border, glow + _breath_flash)
	var icon_center := _breath_box.position + Vector2(9.0, 13.0)
	_draw_lung_icon(icon_center, border if (held or locked or lung < breath_warn) else UIPalette.BONE, held, locked, lung)
	_draw_badge(rect, badge, badge_col, icon_center.y)


func _draw_lung_icon(center: Vector2, color: Color, held: bool, locked: bool, lung: float) -> void:
	var scale_pulse := 1.0 + (0.0 if held else sin(_clock * 1.1) * 0.05)
	if held and lung < breath_warn:
		scale_pulse = 1.0 + pow(maxf(sin(_beat_phase), 0.0), 3.0) * 0.18
	elif locked:
		scale_pulse = 1.0 + sin(_clock * 12.0) * 0.08
	var fill_col := Color(color.r, color.g, color.b, clampf(lung / 100.0, 0.25, 0.9))
	# Trachea stem
	draw_line(center + Vector2(0, -7) * scale_pulse, center + Vector2(0, -1), color, 1.6)
	draw_line(center + Vector2(0, -2), center + Vector2(-3.5, 0), color, 1.3)
	draw_line(center + Vector2(0, -2), center + Vector2(3.5, 0), color, 1.3)
	# Left & right lung lobes
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array([
			center + Vector2(side * 1.6, -2.5) * scale_pulse,
			center + Vector2(side * 6.5, -1.0) * scale_pulse,
			center + Vector2(side * 7.2, 5.0) * scale_pulse,
			center + Vector2(side * 2.0, 6.5) * scale_pulse,
		])
		draw_colored_polygon(pts, fill_col)
		pts.append(pts[0])
		draw_polyline(pts, color, 1.2, true)


func _draw_exertion_card(action: StringName) -> void:
	if _exertion_box == null or not _exertion_box.visible:
		return
	var effort := _exertion_bar.value if _exertion_bar else 0.0
	var border := UIPalette.CARD_BORDER
	var glow := 0.0
	var badge := ""
	var badge_col := UIPalette.TEXT_DIM

	if action == &"forced_gasp":
		border = UIPalette.EXERTION_HOT
		glow = 0.7
		badge = "GASP"
		badge_col = UIPalette.EXERTION_HOT
	elif effort >= maxf(exertion_critical, _warn_at()):
		var pulse := 0.5 + 0.5 * sin(_exertion_beat)
		border = UIPalette.EXERTION_HOT
		glow = 0.45 + 0.45 * pulse
		badge = "LIMIT!"
		badge_col = UIPalette.EXERTION_HOT
	elif effort >= _warn_at():
		border = UIPalette.AMBER
		glow = 0.35
		badge = "STRAIN"
		badge_col = UIPalette.AMBER
	elif _is_resting:
		border = UIPalette.EXERTION_REST
		glow = 0.25
		badge = "REST"
		badge_col = UIPalette.EXERTION_REST
	elif action == &"sprint":
		border = UIPalette.AMBER
		glow = 0.25
		badge = "SPRINT"
		badge_col = UIPalette.AMBER
	elif effort > 0.5:
		badge = "TIRED"
		badge_col = UIPalette.AMBER.darkened(0.15)

	border = border.lerp(Color.WHITE, _exertion_flash * 0.6)
	var rect := _draw_card_box(_exertion_box, border, glow + _exertion_flash)
	var icon_center := _exertion_box.position + Vector2(9.0, 13.0)
	_draw_exertion_icon(icon_center, badge_col if not badge.is_empty() else UIPalette.AMBER, effort)
	_draw_badge(rect, badge, badge_col, icon_center.y)


func _draw_exertion_icon(center: Vector2, color: Color, effort: float) -> void:
	var beat := pow(maxf(sin(_exertion_beat), 0.0), 3.0) if effort > 5.0 else 0.0
	var amp := lerpf(2.5, 6.2, clampf(effort / 100.0, 0.0, 1.0)) * (1.0 + beat * 0.35)
	var pts := PackedVector2Array([
		center + Vector2(-8, 1),
		center + Vector2(-4.5, 1),
		center + Vector2(-2.5, -amp),
		center + Vector2(0.5, amp * 0.7),
		center + Vector2(3.0, -amp * 0.55),
		center + Vector2(5.0, 1),
		center + Vector2(8.0, 1),
	])
	draw_polyline(pts, color, 1.6, true)


func _draw_battery_card() -> void:
	if _battery_box == null or not _battery_box.visible:
		return
	var charge := _battery_bar.value if _battery_bar else 0.0
	var is_on: bool = _flashlight != null and bool(_flashlight.is_on) and charge > 0.0
	var low_thresh: float = _flashlight.low_battery_threshold if _flashlight != null else 25.0

	var border := UIPalette.BATTERY_ON if is_on else UIPalette.CARD_BORDER
	var glow := 0.32 if is_on else 0.0
	var badge := "ON" if is_on else "OFF"
	var badge_col := UIPalette.BATTERY_ON if is_on else UIPalette.TEXT_DIM

	if charge <= 0.0:
		var blink := 0.5 + 0.5 * sin(_clock * 9.0)
		border = UIPalette.BREATH_CRIT
		glow = 0.35 + 0.35 * blink
		badge = "SWAP [B]" if _spares > 0 else "DEAD"
		badge_col = UIPalette.CANDLE if _spares > 0 else UIPalette.BREATH_CRIT
	elif charge <= low_thresh:
		var blink := 0.5 + 0.5 * sin(_clock * 8.0)
		border = UIPalette.BATTERY_LOW
		glow = 0.25 + 0.35 * blink
		badge = "SWAP [B]" if _spares > 0 else "LOW"
		badge_col = UIPalette.CANDLE if _spares > 0 else UIPalette.BATTERY_LOW

	border = border.lerp(Color.WHITE, _battery_flash * 0.65)
	var rect := _draw_card_box(_battery_box, border, glow + _battery_flash)
	var icon_center := _battery_box.position + Vector2(9.0, 13.0)
	_draw_battery_icon(icon_center, badge_col, charge, is_on)
	_draw_badge(rect, badge, badge_col, icon_center.y)


func _draw_battery_icon(center: Vector2, color: Color, charge: float, is_on: bool) -> void:
	var body := Rect2(center + Vector2(-7, -4.5), Vector2(12, 9))
	draw_rect(body, color, false, 1.3)
	draw_rect(Rect2(center + Vector2(5, -2), Vector2(2.2, 4)), color)
	var fill_w := 9.0 * clampf(charge / 100.0, 0.0, 1.0)
	if fill_w > 0.5:
		draw_rect(Rect2(center + Vector2(-5.5, -3), Vector2(fill_w, 6)), color)
	if is_on:
		for angle in [-0.35, 0.0, 0.35]:
			var dir := Vector2.RIGHT.rotated(angle)
			draw_line(center + Vector2(8.5, 0) + dir * 1.0, center + Vector2(8.5, 0) + dir * 3.8, UIPalette.CANDLE, 1.2)
	elif charge > 0.0:
		draw_line(center + Vector2(-6, 6), center + Vector2(6, -6), Color(0.5, 0.52, 0.48, 0.8), 1.3)
