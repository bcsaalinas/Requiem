extends Node

# FootstepNoise
#
# Componente independiente: NO modifica player.gd. Lee la velocidad del
# CharacterBody2D padre para saber si esta caminando o corriendo y avisa
# a NoiseManager. FootstepAudio reproduce los sonidos al plantar cada pie.
#
# TRES niveles de paso, no dos. Ademas de caminar y esprintar, lee el nodo
# hermano "HoldBreath": mientras aguantas la respiracion pisas MUCHO mas
# despacio y mas suave (1 u en vez de 3 u). NO es silencio total: a bocajarro
# la entidad te sigue oyendo, y con las orejas paradas (HUNT/SEARCH multiplica
# por 1.6) ese paso vale 1.6 u. Aguantar la respiracion compra sigilo, no
# invisibilidad.
#
# UNIDADES: 1 u = 32 px. Radios y umbrales se exportan en
# unidades; la conversion a px pasa aqui adentro.
# Estos radios NO estan fijados por la spec, se pueden tunear libremente.

const PX_PER_UNIT: float = Units.PX_PER_UNIT

@export_group("Deteccion de movimiento (u/s)")
## Debajo de esto se considera quieto.
@export var moving_threshold_u: float = 0.1
## A partir de esto cuenta como sprint y no como caminata.
@export var sprint_threshold_u: float = 4.0

@export_group("Ruido de pasos (u)")
@export var footstep_interval: float = 0.45
## Radio del paso caminando, en unidades.
@export var walk_noise_radius_u: float = 3.0
## Radio del paso corriendo, en unidades.
@export var sprint_noise_radius_u: float = 6.0
## Radio del paso aguantando la respiracion. Mismo valor que la exhalacion
## suave (1 u): aguantar la respiracion te convierte en algo de 1 u.
@export var held_noise_radius_u: float = 1.0
## Aguantando la respiracion pisas mas espaciado. Es lo que hace que SUENE a
## paso medido y no a caminata normal en bajito.
@export var held_footstep_interval: float = 0.7

## Stopping plants the moving foot: if the player moved at least this long since the last
## footfall, the stop itself is a footfall. The time keeps adding up across short stops, so
## tapping the movement keys cannot slip past a listener without a sound (tester bug: tap-walking).
@export var settle_step_min_time: float = 0.08

@export_group("Audio bank (played by FootstepAudio)")
@export var walk_clips: Array[AudioStream] = []
@export var sprint_clips: Array[AudioStream] = []
@export var volume_db: float = -6.0
@export_range(0.0, 0.3) var pitch_variation: float = 0.035

var footstep_timer: float = 0.0
## Movement time not yet covered by a footfall noise. Unlike footstep_timer (which drives the gait
## animation and restarts at every stop) it survives stops until a footfall is emitted.
var unvoiced_time: float = 0.0
## Breath state her current steps belong to (see _physics_process).
var _moving_held := false
var _last_speed_u := 0.0

@onready var player: CharacterBody2D = get_parent()
## Nodo hermano. Puede no existir (por eso el get_node_or_null): el componente
## tiene que seguir funcionando en una escena sin mecanica de respiracion.
@onready var hold_breath: Node = player.get_node_or_null("HoldBreath")


## True solo si de verdad se esta aguantando la respiracion (no basta con la
## tecla: durante el bloqueo por gasp forzado ya no cuenta).
func _is_holding_breath() -> bool:
	return hold_breath != null and hold_breath.is_holding


func _physics_process(delta: float) -> void:
	var speed_u := player.velocity.length() / PX_PER_UNIT
	var is_moving := speed_u > moving_threshold_u

	if not is_moving:
		if unvoiced_time >= settle_step_min_time:
			_emit_step(_last_speed_u, _moving_held)
		footstep_timer = 0.0
		return

	# Holding counts at once; letting go counts only while she keeps walking. Releasing the breath
	# as she slows to a stop must not turn the held stretch into a full footfall.
	var holding := _is_holding_breath()
	if holding or speed_u >= _last_speed_u - 0.01:
		_moving_held = holding
	_last_speed_u = speed_u
	var interval := held_footstep_interval if _moving_held else footstep_interval

	footstep_timer += delta
	unvoiced_time += delta
	if footstep_timer < interval:
		return

	footstep_timer = 0.0
	_emit_step(speed_u, _moving_held)


## Forgets pending steps (teleports, checkpoint restores).
func reset_steps() -> void:
	footstep_timer = 0.0
	unvoiced_time = 0.0


func _do_footstep(speed_u: float) -> void:
	_emit_step(speed_u, _is_holding_breath())


## Prioridad identica a la de player.gd: aguantar > esprintar > caminar.
## Aguantar gana siempre, y como hold_breath_speed_u (2.5) esta por debajo de
## sprint_threshold_u (4.0), nunca se puede esprintar en silencio.
func _emit_step(speed_u: float, held: bool) -> void:
	unvoiced_time = 0.0
	if held:
		NoiseManager.emit_noise(player.global_position, held_noise_radius_u * PX_PER_UNIT, NoiseManager.SourceType.CROUCH)
		return

	var is_sprint := speed_u >= sprint_threshold_u
	var radius_u := sprint_noise_radius_u if is_sprint else walk_noise_radius_u
	var source_type: int = NoiseManager.SourceType.SPRINT if is_sprint else NoiseManager.SourceType.FOOTSTEP

	NoiseManager.emit_noise(player.global_position, radius_u * PX_PER_UNIT, source_type)
