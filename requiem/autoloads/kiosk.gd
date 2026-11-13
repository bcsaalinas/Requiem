extends Node
## Show-floor behaviour: the build looks after itself between visitors.
##
## R / Select drops a run straight back to the title. Sixty seconds without input hands the screen
## to attract mode, and any input there wakes the title again. Only the production scenes are
## watched, so the Test Lab, the captures and the regression rigs behave exactly as before.

const TITLE_SCENE := "res://tutorial/main_menu.tscn"
const GAME_SCENE := "res://tutorial/tutorial.tscn"
const ATTRACT_SCENE := "res://tutorial/attract_mode.tscn"
## Stick drift and a nudged desk are not a visitor.
const AXIS_DEADZONE := 0.35
const MOUSE_DEADZONE_PX := 3.0

## Seconds without input before attract mode takes over.
@export var idle_seconds: float = 60.0

var _idle_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Heard before any node, so keys the game marks as handled still count as a visitor.
	get_window().window_input.connect(_on_window_input)


func _process(delta: float) -> void:
	# The poll covers a held key: walking into a wall for a minute is still someone playing.
	if not _can_idle() or Input.is_anything_pressed():
		_idle_time = 0.0
		return
	_idle_time += delta
	if _idle_time >= idle_seconds:
		_idle_time = 0.0
		get_tree().change_scene_to_file(ATTRACT_SCENE)


## True for the run a visitor is actually playing; rigs built on the tutorial keep their own R.
func owns_reset(scene: Node) -> bool:
	return scene == get_tree().current_scene and scene.scene_file_path == GAME_SCENE and not scene.test_mode


func go_to_title() -> void:
	_idle_time = 0.0
	get_tree().change_scene_to_file(TITLE_SCENE)


## The booth never shows a window; rigs and captures ask to keep theirs.
func enter_fullscreen() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and not (args.has("--windowed") or args.has("--record") or args.has("--background")):
		get_window().mode = Window.MODE_FULLSCREEN


func _on_window_input(event: InputEvent) -> void:
	if not _is_visitor(event):
		return
	_idle_time = 0.0
	var scene := get_tree().current_scene
	if scene == null or LoadingScreen._root.visible:
		return
	if scene.scene_file_path == ATTRACT_SCENE:
		go_to_title()
	elif event.is_action_pressed("fast_reset") and owns_reset(scene):
		go_to_title()


func _can_idle() -> bool:
	var scene := get_tree().current_scene
	if scene == null or LoadingScreen._root.visible:
		return false
	return scene.scene_file_path == TITLE_SCENE or owns_reset(scene)


func _is_visitor(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		return event.relative.length() >= MOUSE_DEADZONE_PX
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) >= AXIS_DEADZONE
	return event.is_pressed()
