extends Sprite2D
## Inhale and exhale landmarks in seconds within each shipped recording. Playback position
## follows prayer pitch, restarts and pauses. No separate visual breathing clock.
const CUES := {
	"viv_calm_01": [Vector2(0.10, 1.55), Vector2(4.65, 5.35)],
	"viv_nervous_01": [Vector2(0.22, 0.78), Vector2(1.27, 1.84), Vector2(2.32, 2.93),
		Vector2(3.47, 4.16), Vector2(4.81, 5.07), Vector2(5.68, 6.18), Vector2(6.84, 7.30)],
	"viv_panic_01": [Vector2(0.04, 0.27), Vector2(0.72, 0.96), Vector2(1.39, 1.65),
		Vector2(1.93, 2.15), Vector2(2.48, 2.72), Vector2(3.12, 3.44), Vector2(3.81, 4.06),
		Vector2(4.45, 4.72), Vector2(5.10, 5.34), Vector2(5.83, 6.02), Vector2(6.36, 6.64)]
}
@onready var body: BodyAudio = $"../BodyAudio"
@onready var breath: Node = $"../HoldBreath"
@onready var rig: CharacterSprite = $"../Appearance".rig
@onready var feedback: Node = $"../BreathFeedback"
var _lift := 0.0

func _ready() -> void:
	# Dialogue can disable the player mid-exhale. Clear the sprite on that frame.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture = preload("res://assets/art/vfx/viv_quiet_exhale.png")
	hframes = 5
	centered = false
	offset = Vector2(-7, 0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unlit
	z_index = 42
	process_priority = 5
	hide()

## x is chest lift. y runs from 0 to 1 on an exhale and is negative between exhales.
static func sample_pose(take: String, seconds: float) -> Vector2:
	var marks: Array = CUES.get(take, [])
	for index in marks.size():
		var mark: Vector2 = marks[index]
		if seconds < mark.x:
			break
		if seconds < mark.y:
			return Vector2(smoothstep(mark.x, mark.y, seconds), -1)
		var duration := clampf((mark.y - mark.x) * 1.35, 0.30, 1.18)
		if index + 1 < marks.size():
			duration = minf(duration, marks[index + 1].x - mark.y)
		var out_phase := (seconds - mark.y) / duration
		if out_phase < 1.0:
			return Vector2(1.0 - smoothstep(0.0, 1.0, out_phase), out_phase)
	return Vector2(0, -1)

func _process(delta: float) -> void:
	hide()
	var upper := rig.clip_name(&"upper")
	var ordinary := upper.begins_with("girl_idle_") or upper == "girl_walk_upper"
	if not ordinary or not feedback.enabled or feedback.effects_strength <= 0.0 \
			or GameState.is_dead or not body.player.can_process() or breath.is_holding or breath.is_locked or breath.is_sounding():
		_lift = 0.0
		rig.breath_lift = 0.0
		return
	var voice := body.leading_breath_loop()
	var shape := Vector2(0, -1)
	if voice != null:
		var take := voice.stream.resource_path.get_file().get_basename()
		var seconds := voice.get_playback_position() + AudioServer.get_time_since_last_mix() * voice.pitch_scale
		shape = sample_pose(take, seconds)
	var strength: float = body.open * feedback.effects_strength
	_lift = lerpf(_lift, shape.x * strength, 1.0 - exp(-delta * 20.0))
	rig.breath_lift = roundf(5.0 * _lift)
	if shape.y < 0.0 or strength < 0.05:
		return
	var forward := Vector2.DOWN.rotated(rig.global_rotation)
	global_position = rig.anchor_global("head_center") + forward * 25.0 * Units.ART_SCALE
	global_rotation = rig.global_rotation
	frame = mini(int(shape.y * hframes), hframes - 1)
	modulate.a = strength * (0.45 + 0.30 * sin(PI * shape.y))
	show()
