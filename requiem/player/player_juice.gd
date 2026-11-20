class_name PlayerJuice
extends Node
## Subtle player action game-feel ("juice"), simple walking dust particles,
## and atmospheric entity proximity/focus suspense (gentle camera tremor, organic
## light dimming/fluttering, and eerie tension vignette).
##
## Clean, subtle, and non-intrusive: no sound circles or hud bars.

const PX_PER_UNIT: float = 32.0

@export_group("Action Juice")
@export var walk_step_shake_px: float = 0.28
@export var sprint_step_shake_px: float = 0.85
@export var throw_impact_shake_px: float = 1.6
@export var gasp_shake_px: float = 1.9
@export var pray_pulse_shake_px: float = 1.1
@export var pant_exertion_threshold: float = 68.0
@export var pant_interval_sec: float = 1.25
@export var pant_noise_radius_u: float = 1.5

@export_group("Entity Suspense & Focus (Subtle)")
@export var proximity_start_u: float = 12.5
@export var proximity_close_u: float = 2.4
@export var proximity_shake_px: float = 0.45
@export var focus_shake_px: float = 1.65
@export var scream_shake_px: float = 2.7
@export var proximity_light_dim: float = 0.12
@export var focus_light_dim: float = 0.28
@export var light_affect_radius_px: float = 480.0

@export_group("Particles")
@export var max_particles: int = 64

var _player: CharacterBody2D
var _camera: Camera2D
var _breath: Node
var _thrower: Node
var _flashlight: PointLight2D
var _local_light: PointLight2D
var _actions: Node
var _footstep_audio: Node
var _aim: Node

var _world_layer: CanvasLayer
var _world_canvas: _WorldJuiceCanvas
var _screen_layer: CanvasLayer
var _screen_canvas: _ScreenJuiceCanvas

var _particles: Array[Dictionary] = []
var _beam_motes: Array[Dictionary] = []
var _throw_trail: Array[Vector2] = []
var _throw_target: Vector2 = Vector2.ZERO
var _has_throw_target: bool = false

var _clock: float = 0.0
var _pant_timer: float = 0.0
var _prayer_aura_timer: float = 0.0
var _action_trauma: float = 0.0
var _step_kick: Vector2 = Vector2.ZERO
var _walk_step_cooldown: float = 0.0

var _entity: Node2D = null
var _connected_entity: Node2D = null
var _was_entity_focused: bool = false
var _was_entity_screaming: bool = false
var _entity_proximity: float = 0.0
var _entity_focus: float = 0.0
var _focus_spike: float = 0.0
var _entity_dir: Vector2 = Vector2.UP
var _heartbeat_phase: float = 0.0

var _base_flashlight_energy: float = 1.0
var _base_local_energy: float = 0.6
var _tracked_lights: Dictionary = {} # instance_id -> { "light": PointLight2D, "base_energy": float }
var _light_scan_clock: float = 0.0

var _pant_player: AudioStreamPlayer2D
var _pant_clip: AudioStream


class _WorldJuiceCanvas extends Node2D:
	var owner_juice: PlayerJuice

	func _draw() -> void:
		if owner_juice != null:
			owner_juice._draw_world(self)


class _ScreenJuiceCanvas extends Control:
	var owner_juice: PlayerJuice

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if owner_juice != null:
			owner_juice._draw_screen(self)


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	if _player == null:
		set_process(false)
		return

	_camera = _player.get_node_or_null("Camera2D") as Camera2D
	_breath = _player.get_node_or_null("HoldBreath")
	_thrower = _player.get_node_or_null("Throw")
	_flashlight = _player.get_node_or_null("flashlight") as PointLight2D
	_local_light = _player.get_node_or_null("LocalLight") as PointLight2D
	_actions = _player.get_node_or_null("ActionState")
	_footstep_audio = _player.get_node_or_null("FootstepAudio")
	_aim = _player.get_node_or_null("PlayerAim")

	if _flashlight != null:
		_base_flashlight_energy = _flashlight.energy
		if _flashlight.has_signal("toggle_rejected"):
			_flashlight.toggle_rejected.connect(_on_flashlight_rejected)
	if _local_light != null:
		_base_local_energy = _local_light.energy

	if _footstep_audio != null and _footstep_audio.has_signal("step_played"):
		_footstep_audio.step_played.connect(_on_step_played)

	if NoiseManager != null:
		NoiseManager.noise_emitted.connect(_on_noise_emitted)

	_pant_clip = load("res://assets/audio/horror-jam-kit 2/WAV/Body/breath_texture_01.wav")
	_pant_player = AudioStreamPlayer2D.new()
	_pant_player.name = "PantAudio"
	_pant_player.bus = &"SFX"
	_pant_player.volume_db = -11.5
	_player.add_child.call_deferred(_pant_player)

	# Floating dust motes inside the active flashlight cone
	for i in range(14):
		_beam_motes.append({
			"dist": randf_range(28.0, 270.0),
			"angle": randf_range(-0.32, 0.32),
			"phase": randf_range(0.0, TAU),
			"speed": randf_range(0.7, 1.6),
			"size": randf_range(0.9, 1.8),
		})

	_world_layer = CanvasLayer.new()
	_world_layer.name = "PlayerWorldJuiceLayer"
	_world_layer.layer = 2
	_world_layer.follow_viewport_enabled = true
	_world_canvas = _WorldJuiceCanvas.new()
	_world_canvas.name = "WorldJuiceCanvas"
	_world_canvas.owner_juice = self
	_world_layer.add_child(_world_canvas)
	add_child(_world_layer)

	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "PlayerScreenJuiceLayer"
	_screen_layer.layer = 9
	_screen_canvas = _ScreenJuiceCanvas.new()
	_screen_canvas.name = "ScreenJuiceCanvas"
	_screen_canvas.owner_juice = self
	_screen_layer.add_child(_screen_canvas)
	add_child(_screen_layer)


func _exit_tree() -> void:
	_restore_all_lights()
	if _camera != null:
		_camera.offset = Vector2.ZERO


func _is_test_mode() -> bool:
	var n: Node = _player
	while n != null:
		if "test_mode" in n and bool(n.get("test_mode")):
			return true
		n = n.get_parent()
	return false


func _is_gameplay_active() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _is_test_mode():
		return false
	if _camera == null or not _camera.enabled:
		return false
	return true


func get_entity_proximity() -> float:
	return _entity_proximity


func get_entity_focus() -> float:
	return _entity_focus


func _process(delta: float) -> void:
	if _player == null:
		return

	_clock += delta
	var active_gameplay := _is_gameplay_active()

	_action_trauma = maxf(0.0, _action_trauma - delta * 3.0)
	_focus_spike = maxf(0.0, _focus_spike - delta * 2.2)
	_step_kick = _step_kick.lerp(Vector2.ZERO, clampf(delta * 14.0, 0.0, 1.0))

	_tick_particles(delta)
	_tick_throw_trail()
	_tick_prayer_aura(delta)

	if active_gameplay:
		_tick_walk_particles_continuous(delta)
		_tick_panting_noise(delta)
		_tick_entity_suspense(delta)
		_apply_camera_juice(delta)
		_apply_light_juice(delta)
	else:
		_entity_proximity = 0.0
		_entity_focus = 0.0
		if _camera != null and _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO
		_restore_all_lights()

	if _world_canvas != null:
		_world_canvas.queue_redraw()
	if _screen_canvas != null:
		_screen_canvas.queue_redraw()


func _tick_walk_particles_continuous(delta: float) -> void:
	if _player.velocity.length_squared() > 1600.0: # speed > ~40 px/s
		_walk_step_cooldown -= delta
		if _walk_step_cooldown <= 0.0:
			var sprinting := _player.velocity.length() > 130.0
			_walk_step_cooldown = 0.22 if sprinting else 0.32
			var move_dir := _player.velocity.normalized()
			var foot_offset := Vector2(randf_range(-4.0, 4.0), randf_range(6.0, 10.0))
			_spawn_walk_particle(_player.global_position + foot_offset, -move_dir, sprinting)
	else:
		_walk_step_cooldown = 0.05


func _tick_panting_noise(delta: float) -> void:
	if _breath == null or _player.process_mode == Node.PROCESS_MODE_DISABLED:
		_pant_timer = 0.0
		return
	var exertion: float = float(_breath.exertion_percent)
	var holding: bool = bool(_breath.is_holding) or Input.is_action_pressed("hold_breath")
	var locked: bool = bool(_breath.is_locked)
	if exertion >= pant_exertion_threshold and not holding and not locked:
		var intensity := clampf((exertion - pant_exertion_threshold) / (100.0 - pant_exertion_threshold), 0.0, 1.0)
		_pant_timer += delta * lerpf(0.85, 1.35, intensity)
		if _pant_timer >= pant_interval_sec:
			_pant_timer = 0.0
			var radius_px := (pant_noise_radius_u + intensity * 0.5) * PX_PER_UNIT
			NoiseManager.emit_noise(_player.global_position, radius_px, NoiseManager.SourceType.BREATH)
			if _pant_player != null and _pant_clip != null and not _pant_player.playing:
				_pant_player.stream = _pant_clip
				_pant_player.pitch_scale = randf_range(0.96, 1.06)
				_pant_player.volume_db = lerpf(-13.0, -8.0, intensity)
				_pant_player.play()
	else:
		_pant_timer = maxf(0.0, _pant_timer - delta * 1.5)


func _tick_prayer_aura(delta: float) -> void:
	if _actions == null or not _actions.has_method("get_action"):
		return
	if _actions.get_action() == &"pray":
		_prayer_aura_timer += delta
		if _prayer_aura_timer >= 0.12:
			_prayer_aura_timer = 0.0
			var angle := randf_range(0.0, TAU)
			var dist := randf_range(6.0, 22.0)
			_spawn_particle(
				_player.global_position + Vector2.from_angle(angle) * dist,
				Vector2(randf_range(-6.0, 6.0), randf_range(-28.0, -12.0)),
				UIPalette.CANDLE,
				randf_range(0.35, 0.65),
				randf_range(1.2, 2.2)
			)
	else:
		_prayer_aura_timer = 0.0


func _tick_throw_trail() -> void:
	if _thrower != null and "_in_flight" in _thrower:
		var flights: Array = _thrower._in_flight
		if not flights.is_empty():
			var item: Dictionary = flights.back()
			var node: Node2D = item.get("node") as Node2D
			_throw_target = item.get("to", Vector2.ZERO)
			_has_throw_target = true
			if node != null and is_instance_valid(node):
				var pos := node.global_position
				if _throw_trail.is_empty() or _throw_trail.back().distance_to(pos) > 4.0:
					_throw_trail.append(pos)
					if _throw_trail.size() > 10:
						_throw_trail.pop_front()
			return
	_has_throw_target = false
	if not _throw_trail.is_empty():
		_throw_trail.clear()


func _resolve_entity() -> Node2D:
	if _entity != null and is_instance_valid(_entity):
		return _entity
	var parent := _player.get_parent()
	if parent != null:
		var sibling := parent.get_node_or_null("Entity") as Node2D
		if sibling != null:
			_entity = sibling
	if _entity == null:
		var group_nodes := get_tree().get_nodes_in_group("entity")
		if not group_nodes.is_empty() and group_nodes[0] is Node2D:
			_entity = group_nodes[0] as Node2D
	if _entity != null and _entity != _connected_entity:
		_connected_entity = _entity
		if _entity.has_signal("heard_noise") and not _entity.is_connected("heard_noise", _on_entity_heard_noise):
			_entity.connect("heard_noise", _on_entity_heard_noise)
	return _entity


func _on_entity_heard_noise(_at: Vector2, _source: int) -> void:
	if not _is_gameplay_active():
		return
	_focus_spike = 0.7
	_action_trauma = maxf(_action_trauma, 0.4)


func _tick_entity_suspense(delta: float) -> void:
	var ent := _resolve_entity()
	var is_active := false
	if ent != null and is_instance_valid(ent) and ent.visible:
		is_active = true
		if "active" in ent and not bool(ent.get("active")):
			is_active = false
		if ent.process_mode == Node.PROCESS_MODE_DISABLED:
			is_active = false

	if not is_active:
		_entity_proximity = move_toward(_entity_proximity, 0.0, delta * 2.0)
		_entity_focus = move_toward(_entity_focus, 0.0, delta * 2.0)
		_was_entity_focused = false
		_was_entity_screaming = false
		return

	var to_ent := ent.global_position - _player.global_position
	var dist_px := to_ent.length()
	var dist_u := dist_px / PX_PER_UNIT
	if dist_px > 0.001:
		_entity_dir = to_ent / dist_px

	var prox_target := 1.0 - smoothstep(proximity_close_u, proximity_start_u, dist_u)
	_entity_proximity = lerpf(_entity_proximity, prox_target, clampf(delta * 4.0, 0.0, 1.0))

	var state_name := "PATROL"
	if ent.has_method("get_state_name"):
		state_name = String(ent.call("get_state_name"))
	var listening := ent.has_method("is_listening") and bool(ent.call("is_listening"))
	var screaming := ent.has_method("is_screaming") and bool(ent.call("is_screaming"))

	var focus_target := 0.0
	if screaming or state_name == "HUNT":
		focus_target = 1.0
	elif listening:
		focus_target = 0.7
	elif state_name == "SEARCH":
		focus_target = 0.5 * clampf(1.1 - dist_u / 16.0, 0.2, 1.0)

	var now_focused := focus_target >= 0.5
	if now_focused and not _was_entity_focused:
		_focus_spike = 0.8
		_action_trauma = maxf(_action_trauma, 0.45)
	if screaming and not _was_entity_screaming:
		_focus_spike = 1.0
		_action_trauma = maxf(_action_trauma, 0.65)
	_was_entity_focused = now_focused
	_was_entity_screaming = screaming

	_entity_focus = lerpf(_entity_focus, focus_target, clampf(delta * (5.0 if focus_target > _entity_focus else 2.0), 0.0, 1.0))

	var heart_rate := lerpf(1.0, 2.8, maxf(_entity_proximity, _entity_focus))
	_heartbeat_phase = fposmod(_heartbeat_phase + delta * heart_rate * TAU, TAU)


func _apply_camera_juice(_delta: float) -> void:
	if _camera == null or not _camera.enabled:
		return

	var offset := _step_kick

	# Subtle action trauma shake
	if _action_trauma > 0.001:
		var mag := _action_trauma * 1.3
		offset += Vector2(
			sin(_clock * 34.0) * mag,
			cos(_clock * 28.0) * mag
		)

	# Entity proximity gentle suspense tremor
	if _entity_proximity > 0.01 or _entity_focus > 0.01:
		var lub := pow(maxf(sin(_heartbeat_phase), 0.0), 3.0)
		var prox_mag := _entity_proximity * proximity_shake_px
		offset += Vector2(
			sin(_clock * 6.0) * prox_mag * 0.5,
			cos(_clock * 5.0) * prox_mag * 0.5 + lub * prox_mag * 0.5
		)

		# Entity focus subtle suspense shake (tense and atmospheric, not disorienting)
		var focus_intensity := clampf(_entity_focus * (0.35 + 0.65 * maxf(_entity_proximity, 0.25)) + _focus_spike * 0.35, 0.0, 1.0)
		if focus_intensity > 0.01:
			var screaming := _entity != null and is_instance_valid(_entity) and _entity.has_method("is_screaming") and bool(_entity.call("is_screaming"))
			var max_shake := scream_shake_px if screaming else focus_shake_px
			var shake_amt := focus_intensity * max_shake
			var jitter := Vector2(
				sin(_clock * 41.0) * 0.5 + randf_range(-0.3, 0.3),
				cos(_clock * 37.0) * 0.5 + randf_range(-0.3, 0.3)
			) * shake_amt
			offset += jitter

	_camera.offset = offset


func _apply_light_juice(delta: float) -> void:
	var threat := maxf(_entity_proximity * 0.65, _entity_focus)

	# Subtle, organic light dip and flutter when entity is near/focusing
	var flicker_wave := 1.0
	if threat > 0.02:
		var n1 := sin(_clock * 16.0) * cos(_clock * 11.0)
		var dim_amount := lerpf(proximity_light_dim * _entity_proximity, focus_light_dim, _entity_focus)
		flicker_wave = 1.0 - dim_amount
		# Soft, subtle flutter
		var flutter := (0.5 + 0.5 * n1) * (0.06 * _entity_proximity + 0.16 * _entity_focus)
		flicker_wave *= (1.0 - flutter)

	if _flashlight != null:
		if _flashlight.enabled:
			_flashlight.energy = clampf(_base_flashlight_energy * flicker_wave, 0.25, 1.25)
		else:
			_flashlight.energy = _base_flashlight_energy

	if _local_light != null:
		_local_light.energy = clampf(_base_local_energy * lerpf(1.0, flicker_wave, 0.6), 0.15, 1.0)

	# Nearby world lights dim & flutter subtly when entity is near
	_light_scan_clock -= delta
	if threat > 0.03:
		if _light_scan_clock <= 0.0:
			_light_scan_clock = 0.4
			_scan_nearby_world_lights()
		_modulate_world_lights(flicker_wave, threat)
	elif not _tracked_lights.is_empty():
		_restore_world_lights()


func _scan_nearby_world_lights() -> void:
	var root := _player.get_parent()
	if root == null:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == _player:
			continue
		if node is PointLight2D:
			var light := node as PointLight2D
			if light.visible and light.enabled:
				var d_player := light.global_position.distance_to(_player.global_position)
				var d_ent := 9999.0
				if _entity != null and is_instance_valid(_entity):
					d_ent = light.global_position.distance_to(_entity.global_position)
				if minf(d_player, d_ent) <= light_affect_radius_px:
					var id := light.get_instance_id()
					if not _tracked_lights.has(id):
						_tracked_lights[id] = {
							"light": light,
							"base_energy": light.energy,
						}
		for child in node.get_children():
			stack.append(child)


func _modulate_world_lights(global_flicker: float, threat: float) -> void:
	var stale: Array[int] = []
	for id in _tracked_lights:
		var entry: Dictionary = _tracked_lights[id]
		var light: PointLight2D = entry["light"]
		if light == null or not is_instance_valid(light):
			stale.append(id)
			continue
		var base_e: float = float(entry["base_energy"])
		var d_player := light.global_position.distance_to(_player.global_position)
		var d_ent := d_player
		if _entity != null and is_instance_valid(_entity):
			d_ent = minf(d_player, light.global_position.distance_to(_entity.global_position))
		var dist_factor := 1.0 - smoothstep(60.0, light_affect_radius_px, d_ent)
		if dist_factor <= 0.01:
			light.energy = base_e
			stale.append(id)
			continue
		var phase := float(id % 97) * 0.37
		var local_flutter := 1.0 - (0.5 + 0.5 * sin(_clock * 19.0 + phase)) * 0.12 * _entity_focus * dist_factor
		var mult := lerpf(1.0, global_flicker * local_flutter, clampf(dist_factor * (0.35 + 0.45 * threat), 0.0, 1.0))
		light.energy = maxf(0.1, base_e * mult)
	for id in stale:
		_tracked_lights.erase(id)


func _restore_world_lights() -> void:
	for id in _tracked_lights:
		var entry: Dictionary = _tracked_lights[id]
		var light: PointLight2D = entry["light"]
		if light != null and is_instance_valid(light):
			light.energy = float(entry["base_energy"])
	_tracked_lights.clear()


func _restore_all_lights() -> void:
	if _flashlight != null and is_instance_valid(_flashlight):
		_flashlight.energy = _base_flashlight_energy
	if _local_light != null and is_instance_valid(_local_light):
		_local_light.energy = _base_local_energy
	_restore_world_lights()


func _on_step_played(side: String, at: Vector2, mode: String, _clip: AudioStream, _pitch: float, _gain_db: float) -> void:
	if not _is_gameplay_active():
		return
	var move_dir := _player.velocity.normalized() if _player.velocity.length_squared() > 1.0 else Vector2.DOWN
	var side_sign := -1.0 if side.to_lower() == "left" else 1.0
	var perp := Vector2(-move_dir.y, move_dir.x) * side_sign

	if mode == &"sprint":
		_step_kick = perp * sprint_step_shake_px + move_dir * (sprint_step_shake_px * 0.45)
		_action_trauma = maxf(_action_trauma, 0.16)
		# Sprint dust particles
		for i in range(4):
			var vel := (-move_dir + perp * randf_range(-0.5, 0.5)).normalized() * randf_range(16.0, 36.0)
			_spawn_particle(at + Vector2(randf_range(-2, 2), randf_range(-2, 2)), vel, Color(0.72, 0.69, 0.63, 0.55), randf_range(0.24, 0.4), randf_range(1.4, 2.4))
	elif mode == &"walk":
		_step_kick = perp * walk_step_shake_px
		# Simple, subtle walk dust particles at footstep
		_spawn_walk_step_particles(at, move_dir, perp)
	elif mode == &"hold_breath":
		_step_kick = perp * (walk_step_shake_px * 0.3)
		# Very faint stealth dust
		var vel := -move_dir * randf_range(3.0, 8.0)
		_spawn_particle(at, vel, Color(0.66, 0.69, 0.68, 0.25), 0.2, 1.1)


func _spawn_walk_step_particles(foot_pos: Vector2, move_dir: Vector2, perp: Vector2) -> void:
	for i in range(3):
		var spread := (-move_dir + perp * randf_range(-0.4, 0.4)).normalized()
		var speed := randf_range(5.0, 15.0)
		var dust_pos := foot_pos + Vector2(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5))
		var dust_color := Color(0.72, 0.70, 0.65, randf_range(0.35, 0.5))
		_spawn_particle(dust_pos, spread * speed, dust_color, randf_range(0.22, 0.36), randf_range(1.1, 2.0))


func _spawn_walk_particle(pos: Vector2, drift_dir: Vector2, sprinting: bool) -> void:
	var vel := drift_dir.rotated(randf_range(-0.4, 0.4)) * randf_range(6.0, 18.0 if sprinting else 12.0)
	var col := Color(0.70, 0.68, 0.64, 0.4 if sprinting else 0.3)
	_spawn_particle(pos, vel, col, 0.28, 1.6 if sprinting else 1.2)


func _on_flashlight_rejected() -> void:
	if not _is_gameplay_active():
		return
	_action_trauma = maxf(_action_trauma, 0.15)
	# Clicking a dead flashlight still makes a mechanical click noise (1.5 u)
	NoiseManager.emit_noise(_player.global_position, 1.5 * PX_PER_UNIT, NoiseManager.SourceType.FLASHLIGHT)


func _on_noise_emitted(at: Vector2, _radius_px: float, source_type: int, _duration: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dist_to_player := at.distance_to(_player.global_position)
	if dist_to_player > 540.0:
		return

	# Subtle physical trauma shake & tactile impact particles (NO sound circles drawn)
	if source_type == NoiseManager.SourceType.THROW:
		var atten := 1.0 - smoothstep(24.0, 360.0, dist_to_player)
		_action_trauma = maxf(_action_trauma, 0.38 * maxf(atten, 0.25))
		for i in range(8):
			var vel := Vector2.from_angle(randf_range(0.0, TAU)) * randf_range(18.0, 55.0)
			_spawn_particle(at, vel, Color(0.78, 0.75, 0.68, 0.6), randf_range(0.24, 0.42), randf_range(1.3, 2.2))
	elif source_type == NoiseManager.SourceType.PRAY:
		_action_trauma = maxf(_action_trauma, 0.22)
		for i in range(5):
			var vel := Vector2(randf_range(-16.0, 16.0), randf_range(-38.0, -14.0))
			_spawn_particle(at, vel, UIPalette.CANDLE, randf_range(0.3, 0.55), randf_range(1.2, 2.2))
	elif source_type == NoiseManager.SourceType.BREATH:
		_action_trauma = maxf(_action_trauma, 0.28)
	elif source_type == NoiseManager.SourceType.DOOR:
		_action_trauma = maxf(_action_trauma, 0.12)


func _spawn_particle(pos: Vector2, vel: Vector2, color: Color, lifetime: float, size: float) -> void:
	if _particles.size() >= max_particles:
		_particles.pop_front()
	_particles.append({
		"pos": pos,
		"vel": vel,
		"color": color,
		"age": 0.0,
		"lifetime": lifetime,
		"size": size,
	})


func _tick_particles(delta: float) -> void:
	var i := _particles.size() - 1
	while i >= 0:
		var p: Dictionary = _particles[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["lifetime"]):
			_particles.remove_at(i)
		else:
			var vel: Vector2 = p["vel"]
			p["pos"] = (p["pos"] as Vector2) + vel * delta
			p["vel"] = vel.lerp(Vector2.ZERO, clampf(delta * 4.5, 0.0, 1.0))
		i -= 1


func _get_flashlight_muzzle_pos() -> Vector2:
	if _aim != null and _aim.has_method("get_beam_global_position"):
		return _aim.call("get_beam_global_position")
	if _flashlight != null:
		return _flashlight.global_position
	return _player.global_position


func _get_flashlight_dir() -> Vector2:
	if _aim != null and _aim.has_method("get_aim_direction"):
		return _aim.call("get_aim_direction")
	if _flashlight != null:
		return Vector2.RIGHT.rotated(_flashlight.global_rotation)
	return Vector2.RIGHT


func _draw_world(canvas: Node2D) -> void:
	if not _is_gameplay_active():
		return

	# 1. Subtle dust motes inside active flashlight cone
	if _flashlight != null and _flashlight.enabled:
		var muzzle := _get_flashlight_muzzle_pos()
		var dir := _get_flashlight_dir()
		var base_rot := dir.angle()
		for mote in _beam_motes:
			var dist: float = float(mote["dist"])
			var ang: float = float(mote["angle"]) + sin(_clock * float(mote["speed"]) + float(mote["phase"])) * 0.05
			var m_pos := muzzle + Vector2.from_angle(base_rot + ang) * dist
			var alpha := (0.12 + 0.08 * sin(_clock * 2.1 + float(mote["phase"]))) * (1.0 - dist / 300.0)
			canvas.draw_circle(m_pos, float(mote["size"]), Color(1.0, 0.94, 0.8, maxf(0.0, alpha)))

	# 2. Subtle throw trajectory line
	if _throw_trail.size() >= 2:
		for idx in range(1, _throw_trail.size()):
			var frac := float(idx) / float(_throw_trail.size())
			var t_col := Color(UIPalette.CANDLE.r, UIPalette.CANDLE.g, UIPalette.CANDLE.b, frac * 0.4)
			canvas.draw_line(_throw_trail[idx - 1], _throw_trail[idx], t_col, lerpf(1.0, 2.4, frac), true)
		if _has_throw_target:
			var ret_r := 8.0 + 2.0 * sin(_clock * 12.0)
			canvas.draw_arc(_throw_target, ret_r, 0.0, TAU, 18, Color(UIPalette.CANDLE.r, UIPalette.CANDLE.g, UIPalette.CANDLE.b, 0.35), 1.2, true)

	# 3. Simple particles (walk dust, sprint motes, prayer embers, impact fragments)
	for p in _particles:
		var prog := clampf(float(p["age"]) / maxf(float(p["lifetime"]), 0.001), 0.0, 1.0)
		var col: Color = p["color"]
		col.a *= (1.0 - prog) * 0.85
		var sz := float(p["size"]) * (1.0 - prog * 0.35)
		canvas.draw_circle(p["pos"] as Vector2, maxf(0.5, sz), col)


func _draw_screen(canvas: Control) -> void:
	if not _is_gameplay_active():
		return
	var threat := maxf(_entity_proximity, _entity_focus)
	if threat <= 0.04 and _focus_spike <= 0.04:
		return

	var vp := canvas.size
	if vp.x <= 4.0 or vp.y <= 4.0:
		return

	var lub := pow(maxf(sin(_heartbeat_phase), 0.0), 3.0)

	# Subtle, soft edge vignette pulse for atmospheric dread
	var intensity := clampf(threat * 0.4 + lub * threat * 0.18 + _focus_spike * 0.3, 0.0, 0.8)
	var edge_col := Color(0.12, 0.02, 0.02, intensity * (0.15 if _entity_focus > 0.2 else 0.07))
	var band := lerpf(18.0, 44.0, intensity)
	canvas.draw_rect(Rect2(0, 0, vp.x, band), edge_col)
	canvas.draw_rect(Rect2(0, vp.y - band, vp.x, band), edge_col)
	canvas.draw_rect(Rect2(0, 0, band, vp.y), edge_col)
	canvas.draw_rect(Rect2(vp.x - band, 0, band, vp.y), edge_col)
