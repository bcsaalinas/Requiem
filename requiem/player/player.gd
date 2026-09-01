extends CharacterBody2D

# Player
#
# Movimiento base del jugador. Todo lo visual (Sprite2D, CollisionShape2D,
# Camera2D) vive en player.tscn como nodos REALES, ya no se crea por codigo:
# asi se puede tunear desde el inspector sin tocar el script.
#
# UNIDADES: 1 u = 32 px = un tile = el ancho del jugador.
# Las velocidades se exportan en u/s y se convierten a px/s al usarse, para
# que si algun dia cambia la escala solo haya que tocar PX_PER_UNIT.
#
# VELOCIDAD: tres niveles, elegidos en este orden de prioridad cada frame:
#   1. Aguantando la respiracion -> hold_breath_speed_u (lento y silencioso).
#      Tiene prioridad sobre el sprint: Shift + aguantar = este nivel, NO sprint.
#   2. Esprintando (Shift + te estas moviendo + NO aguantas) -> sprint_speed_u.
#   3. Normal -> walk_speed_u.

const PX_PER_UNIT: float = 32.0

@export_group("Velocidad (u/s)")
## Caminando, en unidades por segundo (1 u = el ancho del jugador).
@export var walk_speed_u: float = 3.2
## Corriendo (Shift), en unidades por segundo.
@export var sprint_speed_u: float = 5.4
## Aguantando la respiracion: mas lento que caminar. Gana al sprint.
@export var hold_breath_speed_u: float = 2.5

@export_group("Inercia")
## 0 = nunca arranca, 1 = arranque instantaneo.
@export_range(0.01, 1.0) var acceleration: float = 0.1
## 0 = nunca frena, 1 = frenado en seco.
@export_range(0.01, 1.0) var friction: float = 0.15

## True SOLO cuando de verdad estas esprintando: Shift + hay input de movimiento
## + no estas aguantando la respiracion. HoldBreath.gd lo lee para subir el
## medidor de agotamiento. Se recalcula cada frame de fisica.
var is_sprinting: bool = false

@onready var hold_breath: Node = get_node_or_null("HoldBreath")


func _ready() -> void:
	# La Entity usa is_in_group("player") para saber a quien atrapa.
	add_to_group("player")


func _physics_process(_delta: float) -> void:
	if GameState.is_dead:
		is_sprinting = false
		_brake()
		return

	# Bloqueo por gasp forzado (pulmon a 0 o agotamiento a 100): la spec pide
	# 2s sin poder moverse. Es independiente de los niveles de velocidad.
	if hold_breath != null and hold_breath.is_locked:
		is_sprinting = false
		_brake()
		return

	# Acciones del InputMap (definidas en project.godot), no teclas fisicas
	# sueltas: asi el jugador puede reasignar controles y funciona igual con mando.
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var holding_breath := Input.is_action_pressed("hold_breath")

	# is_sprinting se calcula DESPUES de input_dir a proposito: necesita saber
	# si de verdad te estas moviendo. Aguantar la respiracion lo cancela.
	is_sprinting = Input.is_action_pressed("sprint") and input_dir != Vector2.ZERO and not holding_breath

	# Prioridad: aguantar respiracion > sprint > caminar.
	var target_speed_u := walk_speed_u
	if holding_breath:
		target_speed_u = hold_breath_speed_u
	elif is_sprinting:
		target_speed_u = sprint_speed_u
	var target_speed := target_speed_u * PX_PER_UNIT

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
