extends CharacterBody2D

# Player
#
# Movimiento base del jugador. Todo lo visual (Sprite2D, CollisionShape2D,
# Camera2D) vive en player.tscn como nodos REALES, ya no se crea por codigo:
# asi se puede tunear desde el inspector sin tocar el script.
#
# UNIDADES: 1 u = 64 px = un tile = el ancho del jugador (ver docs/UNITS.md).
# Las velocidades se exportan en u/s y se convierten a px/s al usarse, para
# que si algun dia cambia la escala solo haya que tocar PX_PER_UNIT.

const PX_PER_UNIT: float = 64.0

@export_group("Velocidad (u/s)")
## Caminando, en unidades por segundo (1 u = el ancho del jugador).
@export var walk_speed_u: float = 3.0
## Corriendo (Shift), en unidades por segundo.
@export var sprint_speed_u: float = 5.0

@export_group("Inercia")
## 0 = nunca arranca, 1 = arranque instantaneo.
@export_range(0.01, 1.0) var acceleration: float = 0.1
## 0 = nunca frena, 1 = frenado en seco.
@export_range(0.01, 1.0) var friction: float = 0.15

@export_group("Hold Breath")
## Si esta activo, aguantar la respiracion congela el movimiento.
## OJO: la spec solo pide que silencie el ruido, no que te inmovilice.
## Queda expuesto para poder probar las dos versiones. Ver docs/GAME_DESIGN.md.
@export var freeze_while_holding_breath: bool = true

@onready var hold_breath: Node = get_node_or_null("HoldBreath")


func _ready() -> void:
	# La Entity usa is_in_group("player") para saber a quien atrapa.
	add_to_group("player")


func _physics_process(_delta: float) -> void:
	if GameState.is_dead:
		_brake()
		return

	# Bloqueo por gasp forzado (pulmon a 0): la spec pide 2s sin poder moverse.
	if hold_breath != null and hold_breath.is_locked:
		_brake()
		return

	if freeze_while_holding_breath and Input.is_action_pressed("hold_breath"):
		_brake()
		return

	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
	input_dir = input_dir.normalized()

	var sprinting := Input.is_physical_key_pressed(KEY_SHIFT)
	var target_speed := (sprint_speed_u if sprinting else walk_speed_u) * PX_PER_UNIT

	if input_dir != Vector2.ZERO:
		velocity = velocity.lerp(input_dir * target_speed, acceleration)
	else:
		velocity = velocity.lerp(Vector2.ZERO, friction)

	move_and_slide()


func _brake() -> void:
	velocity = velocity.lerp(Vector2.ZERO, friction)
	move_and_slide()


## Velocidad actual en unidades por segundo. Util para debug / otros scripts.
func get_speed_u() -> float:
	return velocity.length() / PX_PER_UNIT
