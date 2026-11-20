extends HBoxContainer
## The existing Meter nodes receive the tutorial's resource values. Only effort lives here.
const STRAP := preload("res://assets/art/hud/exertion_strap.png")
const FILL := preload("res://assets/art/hud/exertion_effort.png")
const POSES := preload("res://assets/art/hud/exertion_poses.png")
enum Pose { READY, RUN, LABORED_RUN, HOLD, BRACED, TIRED_WALK, RECOVER, GASP }
const ART_SCALE := 1.5

@onready var meter: ProgressBar = $Exertion/Meter
var pose := Pose.READY
var _beat := 0.0
var _player: CharacterBody2D
var _breath: Node

func _ready() -> void:
	meter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var empty := StyleBoxEmpty.new()
	meter.add_theme_stylebox_override("fill", empty)
	meter.add_theme_stylebox_override("background", empty)
	meter.draw.connect(_draw_meter)

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		_breath = _player.get_node_or_null("HoldBreath") if _player else null
	if not is_instance_valid(_breath):
		return
	var warned: bool = meter.value > _breath.exertion_warn_percent
	var resting: bool = _player.get_speed_u() <= _breath.calm_speed_threshold_u
	if _breath.is_locked:
		pose = Pose.GASP
	elif _breath.is_holding:
		pose = Pose.BRACED if warned else Pose.HOLD
	elif _player.is_sprinting:
		pose = Pose.LABORED_RUN if warned else Pose.RUN
	elif resting and meter.value > 0.0:
		pose = Pose.RECOVER
	elif warned:
		pose = Pose.TIRED_WALK
	else:
		pose = Pose.READY
	_beat = fmod(_beat + delta * lerpf(1.1, 2.2, meter.ratio), 1.0)
	meter.modulate.a = 0.88 + 0.12 * cos(_beat * TAU) if warned else 1.0
	meter.queue_redraw()

func _draw_meter() -> void:
	var rect := Rect2(Vector2.ZERO, STRAP.get_size() * ART_SCALE)
	meter.draw_texture_rect(STRAP, rect, false)
	var width := roundi(85.0 * meter.ratio)
	if width > 0:
		var region := Rect2(24, 7, width, 5)
		meter.draw_texture_rect_region(FILL, Rect2(region.position * ART_SCALE, region.size * ART_SCALE), region)
	var icon := Rect2(0, 0, 18 * ART_SCALE, 18 * ART_SCALE)
	meter.draw_texture_rect_region(POSES, icon, Rect2(int(pose) * 18, 0, 18, 18))
