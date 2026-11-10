extends Node
## Attract mode: the real game plays itself behind the title while nobody is at the booth.
##
## It loads the production tutorial with its story asleep and walks her through three short shots
## on the same input actions a visitor presses, so the rig, the light and the entity are the real
## thing and none of their code knows it is being filmed. Kiosk owns the way out: any input wakes
## the title, so this scene only has to play and to leave the input map clean behind it.

const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "sprint", "hold_breath"]
## Each shot is one walk. route: world px, starting where she stands. time: seconds on screen.
## hold: the stretch of x where she holds her breath. sprint: she runs it. entity: the house after
## the attack, and the second at which a noise calls the entity to her.
const SHOTS := [
	{"zone": "hallway", "route": [Vector2(1704, 368), Vector2(2452, 368)], "time": 10.0, "hold": Vector2(1860, 2200)},
	{"zone": "forest", "route": [Vector2(3350, 540), Vector2(3575, 540), Vector2(3575, 352), Vector2(4030, 352),
		Vector2(4030, 540), Vector2(4460, 540)], "time": 9.5, "sprint": true},
	{"zone": "house", "route": [Vector2(5800, 320), Vector2(5850, 480), Vector2(6060, 480)], "time": 9.0, "entity": 4.8},
]
const FADE_TIME := 0.9
const ARRIVE_PX := 20.0
const LOOK_AHEAD_PX := 240.0
const LINE_TIME := 4.0

var game: Node2D

var _veil: ColorRect
var _line: Label
var _prompt: Label
var _shot: Dictionary = {}
var _shot_index := -1
var _shot_clock := 0.0
var _waypoint := 0
var _heading := 0.0
var _closing := false
var _entity_called := false
var _clock := 0.0
var _line_index := 0


func _ready() -> void:
	_build_overlay()
	ResourceLoader.load_threaded_request(Kiosk.GAME_SCENE)


func _exit_tree() -> void:
	# action_press outlives the scene: a held move_right would walk the next visitor into a wall.
	for action in ACTIONS:
		Input.action_release(action)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = preload("res://ui/requiem_theme.tres")
	layer.add_child(root)

	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color.BLACK
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_veil)

	var title := UIPalette.label("REQUIEM", 78, UIPalette.BONE)
	title.position = Vector2(112, 56)
	root.add_child(title)

	_line = UIPalette.label(LoadingScreen.lines[0], UIPalette.BODY_SIZE, UIPalette.SUBTITLE)
	_line.position = Vector2(116, 164)
	root.add_child(_line)

	_prompt = UIPalette.label("PRESS ANY BUTTON", 30, UIPalette.CANDLE)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -92
	_prompt.offset_bottom = -44
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_prompt)


func _process(delta: float) -> void:
	_clock += delta
	_prompt.modulate.a = 0.8 + 0.2 * sin(_clock * TAU * 0.4)
	_rotate_line()
	if game == null:
		_poll_load()
		return
	_shot_clock += delta
	if _shot_clock >= _shot.time - FADE_TIME and not _closing:
		_closing = true
		var tween := create_tween()
		tween.tween_property(_veil, "color:a", 1.0, FADE_TIME)
		tween.tween_callback(_next_shot)


func _rotate_line() -> void:
	var index := int(_clock / LINE_TIME) % LoadingScreen.lines.size()
	if index != _line_index:
		_line_index = index
		_line.text = LoadingScreen.lines[index]


func _poll_load() -> void:
	var status := ResourceLoader.load_threaded_get_status(Kiosk.GAME_SCENE)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_start_game(ResourceLoader.load_threaded_get(Kiosk.GAME_SCENE))
	elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		push_error("[AttractMode] Failed to load %s" % Kiosk.GAME_SCENE)
		Kiosk.go_to_title()


func _start_game(packed: PackedScene) -> void:
	game = packed.instantiate()
	# test_mode is the tutorial's own quiet start: no dialogue, no window changes, no story audio.
	game.test_mode = true
	add_child(game)
	game.set_process_input(false)
	# The same switch that freezes the story while a reset plays: no cues, no parents, no capture.
	game.resetting = true
	game.hud.hide()
	game.has_flashlight = true
	game.flashlight.set_process(true)
	# The entity comes through this door, so it has to be open before she arrives.
	game.world.interactables["altar_door"]["node"].snap(true)
	_next_shot()


func _next_shot() -> void:
	_shot_index = (_shot_index + 1) % SHOTS.size()
	_shot = SHOTS[_shot_index]
	_shot_clock = 0.0
	_waypoint = 1
	_closing = false
	_entity_called = false
	_steer(Vector2.ZERO)
	game.attack_finished = _shot.has("entity")
	game.enter_zone(_shot.zone, _shot.route[0], false)
	game.ambience.play()
	game.breath.lung_percent = 100.0
	game.breath.exertion_percent = 0.0
	game.flashlight.battery_percent = 100.0
	game.flashlight.is_on = true
	game.flashlight._refresh_light()
	if _shot.has("entity"):
		game.entity.active = true
	_heading = (_shot.route[1] - _shot.route[0]).angle()
	var tween := create_tween()
	tween.tween_property(_veil, "color:a", 0.0, FADE_TIME)


func _physics_process(_delta: float) -> void:
	if game == null:
		return
	var player: CharacterBody2D = game.player
	var at := player.global_position
	while _waypoint < _shot.route.size() and at.distance_to(_shot.route[_waypoint]) < ARRIVE_PX:
		_waypoint += 1
	var direction := Vector2.ZERO
	if _waypoint < _shot.route.size():
		direction = at.direction_to(_shot.route[_waypoint])
		_heading = direction.angle()
	_steer(direction)
	_set_action("sprint", _shot.has("sprint") and direction != Vector2.ZERO)
	var hold: Vector2 = _shot.get("hold", Vector2.ZERO)
	_set_action("hold_breath", at.x > hold.x and at.x < hold.y)
	if _shot.has("entity") and not _entity_called and _shot_clock >= _shot.entity:
		_entity_called = true
		NoiseManager.emit_noise(at, 640.0, NoiseManager.SourceType.ENVIRONMENT)
	# Sweeping the beam keeps her alive; on the last shot it finds what is coming for her.
	var look := at + Vector2.from_angle(_heading + sin(_clock * 1.1) * 0.35) * LOOK_AHEAD_PX
	if _entity_called:
		look = game.entity.global_position
	player.get_node("PlayerAim").set_target(look)


func _steer(direction: Vector2) -> void:
	_set_axis("move_right", direction.x)
	_set_axis("move_left", -direction.x)
	_set_axis("move_down", direction.y)
	_set_axis("move_up", -direction.y)


func _set_axis(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _set_action(action: String, pressed: bool) -> void:
	_set_axis(action, 1.0 if pressed else 0.0)
