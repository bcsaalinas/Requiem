extends Node2D
## Small ground puffs from actual sprint foot plants. This never emits gameplay
## noise and owns no footstep clock: Aim has already resolved both support feet.

const MAX_PUFFS := 24
const DUST_COLOR := Color(0.61, 0.59, 0.52)
const TELEPORT_DISTANCE_U := 3.0

@export var enabled := true
@export_range(0.0, 1.0) var effects_strength := 1.0

@onready var player: CharacterBody2D = get_parent()
@onready var appearance: Node2D = player.get_node("Appearance")
@onready var motion: Node = player.get_node("PlayerMotion")
@onready var actions: Node = player.get_node_or_null("ActionState")
@onready var footsteps: Node = player.get_node_or_null("FootstepNoise")
@onready var breath: Node = player.get_node_or_null("HoldBreath")

## Positions and velocities are world pixels, so a turn cannot drag old dust.
## Each dictionary has position, velocity, age, lifetime, radius, opacity, foot.
var particles: Array[Dictionary] = []
## Lifetime count is intentionally retained by clear_dust for diagnostics.
var emitted_puffs := 0

var _previous_position := Vector2.ZERO
var _previous_contacts := {"left": false, "right": false}
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 25
	z_index = 0
	# Store and render world-space positions independently of the player parent.
	set_as_top_level(true)
	global_transform = Transform2D.IDENTITY
	_random.seed = 197905
	GameState.state_reset.connect(clear_dust)
	GameState.player_died.connect(clear_dust)
	clear_dust()


func clear_dust() -> void:
	particles.clear()
	_previous_position = player.global_position
	_remember_contacts(appearance.get_actor_lower_pose().get("contacts", {}))
	queue_redraw()


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
	queue_redraw()


func _remember_contacts(contacts: Dictionary) -> void:
	for side in ["left", "right"]:
		_previous_contacts[side] = bool(contacts.get(side, false))


func _emit_plant(at: Vector2, travel: Vector2, side: String) -> void:
	var lateral := travel.orthogonal()
	# Three tiny soft shapes read as a foot scuff without outlining the boot.
	for index in range(3):
		if particles.size() >= MAX_PUFFS:
			particles.pop_front()
		var spread := float(index - 1) * 1.7 + _random.randf_range(-0.45, 0.45)
		particles.append({
			"position": at - travel * _random.randf_range(4.5, 6.0) + lateral * spread,
			"velocity": -travel * _random.randf_range(14.0, 24.0) + lateral * spread * 2.0,
			"age": 0.0,
			"lifetime": _random.randf_range(0.32, 0.44),
			"radius": _random.randf_range(3.2, 4.5),
			"opacity": _random.randf_range(0.27, 0.32),
			"foot": side,
		})
		emitted_puffs += 1


func _age_puffs(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var puff: Dictionary = particles[index]
		puff.age = float(puff.age) + delta
		if float(puff.age) >= float(puff.lifetime):
			particles.remove_at(index)
			continue
		puff.position = Vector2(puff.position) + Vector2(puff.velocity) * delta
		puff.velocity = Vector2(puff.velocity) * exp(-4.0 * delta)


func _draw() -> void:
	if not enabled:
		return
	var strength := clampf(effects_strength, 0.0, 1.0)
	for puff in particles:
		var age: float = puff.age
		var progress := clampf(age / float(puff.lifetime), 0.0, 1.0)
		# A forward plant begins below the coat. Hold the short scuff until the
		# body clears that contact, then fade within the same brief lifetime.
		var fade := 1.0 - clampf((age - 0.18) / (float(puff.lifetime) - 0.18), 0.0, 1.0)
		var opacity := float(puff.opacity) * strength \
			* minf(age / 0.025, 1.0) * fade
		var radius := float(puff.radius) * lerpf(0.75, 1.4, progress)
		var at: Vector2 = puff.position
		# Nested translucent fills soften the edge without additive light/glow.
		for layer in range(3):
			var color := DUST_COLOR
			color.a = opacity * [0.18, 0.30, 0.56][layer]
			draw_circle(at, radius * [1.0, 0.76, 0.48][layer], color, true, -1.0, true)
