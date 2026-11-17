extends Node2D
## Small ground puffs from actual sprint foot plants. This never emits gameplay
## noise and owns no footstep clock: Aim has already resolved both support feet.

const MAX_PUFFS := 24
const TELEPORT_DISTANCE_U := 3.0
const DUST_TEXTURE := preload("res://assets/art/vfx/vfx_sprint_dust.png")
## One-shot strip timings in ms (vfx_sprint_dust.json): 60, 160, 120, 100.
const FRAME_MS: Array[int] = [60, 160, 120, 100]
## Frame-space point that lands on the planted boot's toe (the sheet's anchor).
const ANCHOR := Vector2(24, 44)
const FRAME_SIZE := Vector2(48, 48)

@export var enabled := true
@export_range(0.0, 1.0) var effects_strength := 1.0

@onready var player: CharacterBody2D = get_parent()
@onready var appearance: Node2D = player.get_node("Appearance")
@onready var motion: Node = player.get_node("PlayerMotion")
@onready var actions: Node = player.get_node_or_null("ActionState")
@onready var footsteps: Node = player.get_node_or_null("FootstepNoise")
@onready var breath: Node = player.get_node_or_null("HoldBreath")

## World-fixed one-shot sprites: each dictionary has sprite, age, lifetime.
var particles: Array[Dictionary] = []
## Lifetime count is intentionally retained by clear_dust for diagnostics.
var emitted_puffs := 0

var _previous_position := Vector2.ZERO
var _previous_contacts := {"left": false, "right": false}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 25
	z_index = 0
	# Store and render world-space positions independently of the player parent.
	set_as_top_level(true)
	global_transform = Transform2D.IDENTITY
	GameState.state_reset.connect(clear_dust)
	GameState.player_died.connect(clear_dust)
	clear_dust()


func clear_dust() -> void:
	for puff in particles:
		puff["sprite"].queue_free()
	particles.clear()
	_previous_position = player.global_position
	_remember_contacts(appearance.get_actor_lower_pose().get("contacts", {}))


func reset() -> void:
	clear_dust()


func _physics_process(delta: float) -> void:
	var displacement := player.global_position - _previous_position
	_previous_position = player.global_position
	if not enabled or effects_strength <= 0.0 or GameState.is_dead \
			or not player.can_process() \
			or displacement.length() > Units.to_px(TELEPORT_DISTANCE_U):
		clear_dust()
		return

	_age_puffs(maxf(delta, 0.0))
	var lower: Dictionary = appearance.get_actor_lower_pose()
	var contacts: Dictionary = lower.get("contacts", {})
	var boots: Dictionary = lower.get("boots", {})
	var threshold_u: float = footsteps.moving_threshold_u if footsteps != null else 0.1
	var moving := delta > 0.0 and displacement.length() > Units.to_px(threshold_u) * delta
	var allowed: bool = not GameState.is_praying and (breath == null or not breath.is_locked)
	if actions != null:
		allowed = actions.can_move()
	if moving and allowed and motion.enabled and motion.mode == "Sprint":
		for side in ["left", "right"]:
			if bool(contacts.get(side, false)) and not bool(_previous_contacts[side]) \
					and boots.has(side):
				_emit_plant(Vector2(boots[side]), displacement.normalized(), side)
	_remember_contacts(contacts)


func _remember_contacts(contacts: Dictionary) -> void:
	for side in ["left", "right"]:
		_previous_contacts[side] = bool(contacts.get(side, false))


func _emit_plant(at: Vector2, travel: Vector2, side: String) -> void:
	if particles.size() >= MAX_PUFFS:
		var oldest: Dictionary = particles.pop_front()
		oldest["sprite"].queue_free()
	var sprite := Sprite2D.new()
	sprite.texture = DUST_TEXTURE
	sprite.hframes = 4
	sprite.offset = FRAME_SIZE * 0.5 - ANCHOR
	sprite.scale = Vector2.ONE * Units.ART_SCALE
	# The sheet is drawn travelling down the screen: rotate in quarter turns to
	# the run direction, never a free angle, and flip for the right boot.
	var quarter := int(roundf(travel.angle() / (PI * 0.5))) - 1
	sprite.rotation = quarter * PI * 0.5
	sprite.flip_h = side == "right"
	sprite.position = at
	add_child(sprite)
	var lifetime := 0.0
	for ms in FRAME_MS:
		lifetime += ms / 1000.0
	particles.append({"sprite": sprite, "age": 0.0, "lifetime": lifetime})
	emitted_puffs += 1


func _age_puffs(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var puff: Dictionary = particles[index]
		puff["age"] = float(puff["age"]) + delta
		if float(puff["age"]) >= float(puff["lifetime"]):
			puff["sprite"].queue_free()
			particles.remove_at(index)
			continue
		var elapsed := float(puff["age"]) * 1000.0
		var frame := 0
		var at_ms := 0.0
		for ms in FRAME_MS:
			if elapsed < at_ms + ms: break
			at_ms += ms
			frame += 1
		puff["sprite"].frame = mini(frame, 3)
