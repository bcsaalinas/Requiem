extends "res://entities/entity_ai.gd"
## Authored patrol route; hearing, search, hunt and speeds use the existing entity.
signal caught
var route: Array[Vector2] = []
var route_index := 0
var active := false
var appearance: Node2D

func _ready() -> void:
	super._ready()
	_sprite.hide()
	appearance = $Appearance
	color_by_state = false
	log_state_changes = false

func _physics_process(delta: float) -> void:
	_update_readability()
	if not active:
		velocity = Vector2.ZERO
		return
	super._physics_process(delta)

func _on_noise_emitted(at: Vector2, radius: float, source: int, duration: float) -> void:
	if active: super._on_noise_emitted(at, radius, source, duration)

func _tick_patrol(delta: float) -> void:
	if route.is_empty(): return
	if _patrol_wait > 0:
		_patrol_wait -= delta
		_halt()
		return
	nav_agent.target_position = route[route_index]
	_move_along_path(patrol_speed_u)
	if _reached(route[route_index]):
		route_index = (route_index + 1) % route.size()
		_patrol_wait = patrol_pause

func _on_catch_area_body_entered(body: Node2D) -> void:
	if active and body.is_in_group("player"): caught.emit()

func reset_encounter(at: Vector2, points: Array[Vector2]) -> void:
	global_position = at
	route = points
	route_index = 0
	velocity = Vector2.ZERO
	_recent_noises.clear()
	_search_queue.clear()
	_hunt_timer = 0.0
	_state_timer = 0.0
	_patrol_wait = 1.5
	current_state = State.PATROL
	active = false

func _update_readability() -> void:
	var pressure := 0.0
	var observer := get_tree().get_first_node_in_group("player") as Node2D
	if active and visible and is_instance_valid(observer):
		var distance := global_position.distance_to(observer.global_position)
		if distance<7.0*PX_PER_UNIT:
			var query := PhysicsRayQueryParameters2D.create(observer.global_position,global_position,1)
			query.exclude = [observer.get_rid(),get_rid()]
			if get_world_2d().direct_space_state.intersect_ray(query).is_empty():
				pressure=1.0-smoothstep(2.0*PX_PER_UNIT,7.0*PX_PER_UNIT,distance)
	appearance.set_threat_pressure(pressure)
