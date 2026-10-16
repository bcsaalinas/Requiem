extends Node2D
## Presentation-only camera experiment. Gameplay never depends on this rig.

@export_range(1.0, 3.0) var exploration_zoom := 1.65
@export_range(1.0, 3.0) var hallway_zoom := 1.80
@export_range(1.0, 3.0) var reveal_zoom := 1.85
@export_range(1.0, 3.0) var altar_zoom := 1.90

@onready var camera: Camera2D = $Camera2D
@onready var host: PhantomCameraHost = $Camera2D/PhantomCameraHost
@onready var exploration: PhantomCamera2D = $Exploration
@onready var hallway: PhantomCamera2D = $Hallway
@onready var reveal: PhantomCamera2D = $WindowReveal
@onready var altar: PhantomCamera2D = $Altar
@onready var reset: PhantomCamera2D = $Reset
@onready var impact: PhantomCameraNoiseEmitter2D = $Impact

var player: CharacterBody2D
var shots: Array[PhantomCamera2D] = []
var active_shot := "Exploration"
var region := Rect2()
var _hallway_door := 0.0
var _hallway_weight := 0.0
var _reveal_active := false
var _altar_active := false


func setup(actor: CharacterBody2D, world: Node2D) -> void:
	player = actor
	shots.assign([exploration, hallway, reveal, altar, reset])
	for shot in [exploration, hallway, reset]:
		shot.set_follow_target(player)
	reveal.set_follow_targets([player, world.props["window"]])
	altar.set_follow_targets([player, world.props["friend"]])


func apply_region(bounds: Rect2) -> void:
	region = bounds
	# Noise uses Camera2D.offset, which can pass native limits. Reserve a small inset.
	var safe_bounds := bounds.grow(-4.0)
	var viewport_size := get_viewport_rect().size
	var minimum_zoom := maxf(viewport_size.x / safe_bounds.size.x,
		viewport_size.y / safe_bounds.size.y)
	var nominal_zooms := [exploration_zoom, hallway_zoom, reveal_zoom, altar_zoom, exploration_zoom]
	for index in range(shots.size()):
		var shot := shots[index]
		shot.set_limit_left(int(safe_bounds.position.x))
		shot.set_limit_top(int(safe_bounds.position.y))
		shot.set_limit_right(int(safe_bounds.end.x))
		shot.set_limit_bottom(int(safe_bounds.end.y))
		var desired_zoom := maxf(minimum_zoom, nominal_zooms[index])
		if shot.auto_zoom:
			shot.auto_zoom_min = maxf(minimum_zoom, exploration_zoom)
			shot.auto_zoom_max = maxf(shot.auto_zoom_min, desired_zoom)
		else:
			shot.zoom = Vector2.ONE * desired_zoom


func enter_region(bounds: Rect2) -> void:
	_reveal_active = false
	_altar_active = false
	_hallway_door = 0.0
	_hallway_weight = 0.0
	hallway.follow_offset = Vector2.ZERO
	apply_region(bounds)
	snap_to_player()


func snap_to_player() -> void:
	if not is_instance_valid(player): return
	impact.stop(false)
	camera.offset = Vector2.ZERO
	# A zero-duration reset shot interrupts any previous tween before a teleport.
	_select(reset, true)
	reset.teleport_position()
	host.process(0.0)
	# Recenter Framed mode before reactivating its dead zone.
	exploration.follow_mode = PhantomCamera2D.FollowMode.SIMPLE
	exploration.teleport_position()
	exploration.follow_mode = PhantomCamera2D.FollowMode.FRAMED
	_select(exploration, true)
	host.process(0.0)
	camera.reset_physics_interpolation()
	camera.force_update_scroll()


func set_hallway_door(door_x: float) -> void:
	_hallway_door = door_x
	_choose_gameplay_shot()


func start_reveal() -> void:
	_reveal_active = true
	reveal.teleport_position()
	_select(reveal)
	impact.emit()


func finish_reveal() -> void:
	_reveal_active = false
	_choose_gameplay_shot()


func start_altar() -> void:
	_altar_active = true
	altar.teleport_position()
	_select(altar)


func finish_altar() -> void:
	_altar_active = false
	_choose_gameplay_shot()


func stop_effects() -> void:
	_reveal_active = false
	_altar_active = false
	_hallway_door = 0.0
	impact.stop(false)
	camera.offset = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player): return
	var target_weight := 1.0 if _hallway_door != 0.0 else 0.0
	_hallway_weight = move_toward(_hallway_weight, target_weight, delta * 4.0)
	if _hallway_door != 0.0:
		var toward_door := Vector2(_hallway_door, 276.0) - player.global_position
		hallway.follow_offset = toward_door.limit_length(65.0) * 0.65 * _hallway_weight
	else:
		hallway.follow_offset = hallway.follow_offset.move_toward(Vector2.ZERO, delta * 180.0)


func _choose_gameplay_shot() -> void:
	if _altar_active:
		_select(altar)
	elif _reveal_active:
		_select(reveal)
	elif _hallway_door != 0.0:
		_select(hallway)
	else:
		_select(exploration)


func _select(shot: PhantomCamera2D, instant := false) -> void:
	if active_shot == String(shot.name) and not instant: return
	var duration := shot.tween_resource.duration
	if instant: shot.tween_resource.duration = 0.0
	# Raise the requested shot before demoting the previous shot to avoid an interim winner.
	shot.priority = 100
	for other in shots:
		if other != shot: other.priority = 0
	active_shot = String(shot.name)
	if instant:
		host.process(0.0)
		shot.tween_resource.duration = duration
