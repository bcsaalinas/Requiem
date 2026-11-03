@tool
class_name WallWindow
extends Node2D
## A window set into an east-west wall, two tiles wide. It blocks movement like the wall around it
## but lets light through its glass: only the frame posts occlude. The origin is the floor line
## below the wall face, like Door, so both y-sort with the wall.

signal broken_changed(is_broken: bool)

const INTACT := preload("res://assets/level/window.png")
const BROKEN := preload("res://assets/level/window_broken.png")

## Exterior windows show the clapboard face; interior ones show wallpaper.
@export var exterior := false:
	set(value):
		exterior = value
		_refresh()
@export var broken := false:
	set(value):
		var changed := value != broken
		broken = value
		_refresh()
		if changed and is_inside_tree() and not Engine.is_editor_hint():
			broken_changed.emit(broken)


func _ready() -> void:
	_refresh()


## Windows can be interaction targets (the tutorial's latch); brighten the frame when focused.
func set_focused(value: bool) -> void:
	var glass := get_node_or_null("Glass") as CanvasItem
	if glass != null:
		glass.modulate = Color(1.3, 1.22, 1.08) if value else Color.WHITE


func _refresh() -> void:
	if not is_inside_tree():
		return
	var face := get_node_or_null("WallFace") as Sprite2D
	if face != null and face.texture is AtlasTexture:
		(face.texture as AtlasTexture).region = Rect2(0, 96, 64, 64) if exterior else Rect2(0, 32, 64, 64)
	var glass := get_node_or_null("Glass") as Sprite2D
	if glass != null:
		glass.texture = BROKEN if broken else INTACT
	var shards := get_node_or_null("Shards") as CanvasItem
	if shards != null:
		shards.visible = broken
