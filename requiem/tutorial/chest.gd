extends Node2D
## A trunk seen from straight above (level/props/chest.tscn with this script on the instance).
## It opens once: the latch clicks and the lid knocks, quietly on a held breath
## like a door, and `opened` hands over what it holds. The prop does not know what the loot means;
## the story script that listens does.
##
## Finding it: a closed trunk carries the same cold star as the pickups, on its hasp, so it can
## be found in a black room. Close enough to open, it gets the pickup outline.

signal opened(loot: String)

const CLOSED := preload("res://assets/art/props/deco_chest.png")
const OPEN := preload("res://assets/art/props/deco_chest_open.png")
const CHEST_OPEN_SOUND := preload("res://tutorial/assets/audio/chest_latch_and_lid.wav")
const OUTLINE_SHADER := preload("res://tutorial/pickup_outline.gdshader")
const HintBeacon := preload("res://tutorial/hint_beacon.gd")
## The hasp, from the node's origin (the trunk's front floor line).
const HASP := Vector2(0.0, -8.0)

@export_enum("empty", "battery", "stones", "note", "key") var loot := "empty"
## What the note says (loot "note").
@export_multiline var note_text := ""
@export_group("Noise")
## How far the lid is heard, in units; on a held breath it is eased open.
@export var noise_radius_u := 3.0
@export var quiet_noise_radius_u := 1.0

var is_open := false
var focused := false
var content_taken := false
var _content: Sprite2D

var _outline: Sprite2D
var _beacon: Sprite2D
var _audio: AudioStreamPlayer2D
@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	_outline = Sprite2D.new()
	_outline.name = "Outline"
	_outline.centered = false
	_outline.texture = CLOSED
	_outline.region_enabled = true
	_outline.region_rect = Rect2(Vector2(-1.0, -1.0), CLOSED.get_size() + Vector2(2.0, 2.0))
	_outline.scale = _sprite.scale
	_outline.position = _sprite.position - Vector2.ONE * _sprite.scale
	_outline.visible = false
	_outline.material = ShaderMaterial.new()
	_outline.material.shader = OUTLINE_SHADER
	add_child(_outline)
	_beacon = HintBeacon.new()
	_beacon.name = "Beacon"
	_beacon.position = HASP
	_beacon.z_index = 1
	_beacon.period = 3.1
	add_child(_beacon)
	_audio = AudioStreamPlayer2D.new()
	_audio.name = "Audio"
	_audio.bus = &"SFX"
	_audio.position = Vector2(0.0, -20.0)
	add_child(_audio)
	_content = Sprite2D.new()
	_content.position = Vector2(0, -17)
	_content.scale = Vector2.ONE * 0.3
	var icons := {"battery": "battery", "stones": "pebble_a", "note": "note", "key": "key"}
	if icons.has(loot):
		_content.texture = load("res://assets/art/items/item_%s.png" % icons[loot])
	add_child(_content)
	_refresh()


## Swings the lid back. False when it was open already.
func open(quiet := false) -> bool:
	if is_open:
		return false
	is_open = true
	_refresh()
	# The lid lands on its hinges: one small jolt, no squash (the art is one flat plate).
	var rest := _sprite.position
	var tween := create_tween()
	tween.tween_property(_sprite, "position", rest + Vector2(0.0, -1.2), 0.05)
	tween.tween_property(_sprite, "position", rest, 0.09)
	_audio.stream = CHEST_OPEN_SOUND
	_audio.volume_db = -8.0 if quiet else -1.0
	_audio.play()
	var radius_u := quiet_noise_radius_u if quiet else noise_radius_u
	if radius_u > 0.0:
		NoiseManager.emit_noise(get_loot_origin(), radius_u * Units.PX_PER_UNIT, NoiseManager.SourceType.DOOR)
	opened.emit(loot)
	return true


## Where the loot comes out: the middle of the trunk.
func get_loot_origin() -> Vector2:
	return to_global(Vector2(0.0, -20.0))

func take_content() -> void:
	content_taken = true
	_refresh()


func set_focused(value: bool) -> void:
	focused = value
	_refresh()


func _refresh() -> void:
	if _sprite == null:
		return
	_sprite.texture = OPEN if is_open else CLOSED
	_content.visible = is_open and not content_taken
	_outline.visible = focused and not is_open
	# Only trunks that can be opened here call for attention.
	_beacon.shining = not is_open and has_meta("interaction_id")
