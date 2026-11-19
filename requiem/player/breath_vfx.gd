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
