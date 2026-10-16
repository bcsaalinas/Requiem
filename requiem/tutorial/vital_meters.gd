extends HBoxContainer
## Beta vitals: the bars stop being readouts and start behaving like the organs
## they stand for. Attach to Screen/Vitals in hud.tscn — it drives the three
## Meter children already in the scene, nothing is renamed or moved.
##
## Division of labour: tutorial.gd already writes hud.breath/effort/battery
## every frame, so this script never touches `value`. It owns presentation only
## — colour, beat, jitter — and reads the numbers back off the bars.
##
## State comes from ActionState.get_action(), per its own header: "presentation
## reads this derived priority instead of maintaining another state."
##
## The meters never auto-hide. Our Yomawari benchmark takeaway was to keep
## breath on screen at all times so the tension never switches off.

@export_group("Sources")
## Player node. Left empty, it is found through the "player" group.
@export var player_path: NodePath

@export_group("Breath")
## Below this, the bar beats instead of sitting still.
@export var breath_warn: float = 35.0
## Below this, the beat bleeds toward alarm.
@export var breath_critical: float = 20.0
## Beats per second as the lung empties.
@export var beat_rate_max: float = 3.4

@export_group("Exertion")
## Above this, the bar starts pulsing and the row jitters.
@export var exertion_warn: float = 65.0
## Above this, amber bleeds toward alarm.
@export var exertion_critical: float = 85.0

@export_group("Feel")
## Peak horizontal jitter, in pixels, at full alarm.
@export var jitter: float = 1.6
## How fast a bar's colour moves toward its target.
@export var colour_speed: float = 7.0
## Idle sway so the HUD breathes when nothing is happening.
@export var idle_sway: float = 0.1

var _breath_bar: ProgressBar
var _exertion_bar: ProgressBar
var _breath_caption: Label
var _exertion_caption: Label

var _breath_fill: StyleBoxFlat
var _exertion_fill: StyleBoxFlat
var _breath_track: StyleBoxFlat

var _player: Node
var _actions: Node

var _clock: float = 0.0
var _beat_phase: float = 0.0
var _was_gasping: bool = false
var _home: Vector2


func _ready() -> void:
	_breath_bar = get_node_or_null("Breath/Meter")
	_exertion_bar = get_node_or_null("Exertion/Meter")
	_breath_caption = get_node_or_null("Breath/Caption")
	_exertion_caption = get_node_or_null("Exertion/Caption")

	# Each bar needs its own stylebox instance. hud.tscn authors the three bars
	# against shared resources, so tinting breath would tint exertion too.
	_breath_fill = UIPalette.flat(UIPalette.BONE)
	_exertion_fill = UIPalette.flat(UIPalette.AMBER)
	_breath_track = UIPalette.flat(UIPalette.TRACK)

	if _breath_bar:
		_breath_bar.add_theme_stylebox_override("fill", _breath_fill)
		_breath_bar.add_theme_stylebox_override("background", _breath_track)
	if _exertion_bar:
		_exertion_bar.add_theme_stylebox_override("fill", _exertion_fill)

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


func _process(delta: float) -> void:
	if _player == null:
		_resolve_player()
		return

	_clock += delta
	var action: StringName = _actions.get_action() if _actions != null else &"idle"

	_drive_breath(delta, action)
	_drive_exertion(delta, action)
	_check_gasp(action)


## The breath bar beats, and the rate rises as the lung empties — the player
## sees the gasp coming in the corner of their eye before any number means
## anything.
##
## While the breath is actually held the bar goes completely still: no beat, no
## idle sway. The HUD stops breathing when the player does. That stillness is
## the only moment in the game where nothing on screen moves, which is exactly
## what the mechanic is worth.
func _drive_breath(delta: float, action: StringName) -> void:
	if _breath_bar == null:
		return

	var lung: float = _breath_bar.value
	var held: bool = action == &"hold_breath"

	var urgency: float = 0.0
	if lung < breath_warn:
		urgency = clampf((breath_warn - lung) / maxf(breath_warn, 0.001), 0.0, 1.0)

	var target := UIPalette.BONE
	if lung < breath_critical:
		target = UIPalette.BONE.lerp(UIPalette.ALARM, urgency)

	if held:
		# Held: the track darkens, as if under pressure, and everything freezes.
		_beat_phase = 0.0
		_breath_bar.scale.y = 1.0
		_breath_bar.modulate.a = 1.0
		_breath_track.bg_color = _breath_track.bg_color.lerp(
			UIPalette.TRACK.darkened(0.35), clampf(colour_speed * delta, 0.0, 1.0)
		)
		if _breath_caption:
			_breath_caption.modulate.a = lerpf(_breath_caption.modulate.a, 0.65, delta * 6.0)
	else:
		_breath_track.bg_color = _breath_track.bg_color.lerp(
			UIPalette.TRACK, clampf(colour_speed * delta, 0.0, 1.0)
		)
		if urgency > 0.0:
			_beat_phase += delta * lerpf(0.8, beat_rate_max, urgency) * TAU
			# Sharp attack, slow release — a pulse, not a sine wave.
			var beat: float = pow(maxf(sin(_beat_phase), 0.0), 3.0)
			_breath_bar.modulate.a = lerpf(0.75, 1.0, beat)
			_breath_bar.scale.y = 1.0 + beat * urgency * 0.9
			if _breath_caption:
				_breath_caption.modulate.a = lerpf(0.55, 1.0, beat)
		else:
			_beat_phase = 0.0
			_breath_bar.modulate.a = 1.0
			_breath_bar.scale.y = 1.0 + sin(_clock * 1.1) * idle_sway
			if _breath_caption:
				_breath_caption.modulate.a = 1.0

	_breath_fill.bg_color = _breath_fill.bg_color.lerp(target, clampf(colour_speed * delta, 0.0, 1.0))


## Exertion runs the other way: it fills, and the closer it gets to the forced
## gasp the more it refuses to sit still.
func _drive_exertion(delta: float, action: StringName) -> void:
	if _exertion_bar == null:
		return

	var effort: float = _exertion_bar.value
	var urgency: float = 0.0
	if effort > exertion_warn:
		var span: float = maxf(100.0 - exertion_warn, 0.001)
		urgency = clampf((effort - exertion_warn) / span, 0.0, 1.0)

	var target := UIPalette.AMBER
	if effort > exertion_critical:
		target = UIPalette.AMBER.lerp(UIPalette.ALARM, urgency)

	if urgency > 0.0:
		var rate: float = lerpf(5.0, 13.0, urgency)
		# Sprinting is what put the player here, so it reads louder than the
		# same exertion reached by holding the breath.
		if action == &"sprint":
			rate *= 1.25
		var pulse: float = (sin(_clock * rate) + 1.0) * 0.5
		_exertion_bar.modulate.a = lerpf(0.72, 1.0, pulse)
		position = _home + Vector2(randf_range(-jitter, jitter) * urgency, 0.0)
		if _exertion_caption:
			_exertion_caption.modulate.a = lerpf(0.6, 1.0, pulse)
	else:
		_exertion_bar.modulate.a = 1.0
		position = position.lerp(_home, clampf(delta * 10.0, 0.0, 1.0))
		if _exertion_caption:
			_exertion_caption.modulate.a = 1.0

	_exertion_fill.bg_color = _exertion_fill.bg_color.lerp(target, clampf(colour_speed * delta, 0.0, 1.0))


## The forced gasp is the one moment both meters agree. One frame of agreement
## reads as a system failure rather than as two bars doing their own thing.
func _check_gasp(action: StringName) -> void:
	var gasping: bool = action == &"forced_gasp"
	if gasping and not _was_gasping:
		for bar in [_breath_bar, _exertion_bar]:
			if bar == null:
				continue
			bar.modulate = Color(1.6, 1.4, 1.3)
			var tween := create_tween()
			tween.tween_property(bar, "modulate", Color.WHITE, 0.45)
	_was_gasping = gasping
