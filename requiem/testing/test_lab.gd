extends Node
## Development entry only. Production scenes never depend on this launcher.

const TUTORIAL := "res://tutorial/tutorial.tscn"
const COMPARISON := "res://testing/experiments/phantom_tutorial.tscn"
const SANDBOX := "res://testing/experiments/mechanics_sandbox.tscn"
const NoiseOverlay := preload("res://testing/tools/noise_debug.gd")

var active_scene: Node
var active_path := ""
var menu: Control
var toolbar: HBoxContainer
var noise: Node
var switching := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	noise = NoiseOverlay.new()
	noise.enabled = false
	add_child(noise)
	noise._legend_layer.hide()
	noise.set_process_unhandled_input(false)
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	menu = PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(menu)
	var center := CenterContainer.new()
	menu.add_child(center)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	choices.custom_minimum_size.x = 640
	center.add_child(choices)
	var title := Label.new()
	title.text = "REQUIEM · TEST LAB"
	title.add_theme_font_size_override("font_size", 30)
	choices.add_child(title)
	var description := Label.new()
	description.text = "One workspace for feature checks. F5 still runs the playable tutorial.\nF1 returns here · F3 toggles emitted-noise visualization during a test."
	choices.add_child(description)
	add_button(choices, "Play tutorial · full story and pickup flow", func(): launch(TUTORIAL))
	add_button(choices, "Character and camera · C / V comparisons, 1–5 areas", func(): launch(COMPARISON))
	add_button(choices, "Mechanics sandbox · breath, throwing, prayer and hearing", func(): launch(SANDBOX))
	var help := Label.new()
	help.text = "Automated checks and capture tools: testing/README.md\nResults are written to user://test-results/, never to game assets.\nA noise ring shows an emitted event; it does not prove an enemy heard it."
	choices.add_child(help)
	toolbar = HBoxContainer.new()
	toolbar.position = Vector2(20, 116)
	layer.add_child(toolbar)
	add_button(toolbar, "F1 · Test Lab", show_menu)
	add_button(toolbar, "Restart test", restart)
	toolbar.hide()
	choices.get_child(2).grab_focus()


func add_button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)


func launch(path: String) -> void:
	if switching:
		return
	switching = true
	await clear_scene()
	active_path = path
	active_scene = load(path).instantiate()
	# Child gameplay must pause normally even though the lab stays responsive.
	active_scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(active_scene)
	menu.hide()
	toolbar.show()
	noise.set_process_unhandled_input(true)
	switching = false


func clear_scene() -> void:
	get_tree().paused = false
	for action in InputMap.get_actions():
		Input.action_release(action)
	if is_instance_valid(active_scene):
		active_scene.queue_free()
		await get_tree().process_frame
	active_scene = null
	GameState.reset()
	GameOverUi.label.text = ""
	noise.enabled = false
	noise._noises.clear()
	noise._legend_layer.hide()
	noise.set_process_unhandled_input(false)
	noise._redraw()


func show_menu() -> void:
	if switching:
		return
	switching = true
	await clear_scene()
	menu.show()
	toolbar.hide()
	switching = false


func restart() -> void:
	if active_path != "":
		launch(active_path)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		show_menu.call_deferred()
	elif event.keycode == KEY_R and GameState.is_dead:
		get_viewport().set_input_as_handled()
		restart.call_deferred()
