@tool
extends Sprite2D
## Plays a delivered vfx sheet: flat frames at art scale, JSON timings, no
## tweened scale/alpha/rotation. Lit like any other sprite.

@export var sheet: Texture2D
@export var frame_count := 1
@export var frame_ms: Array[int] = []
@export var anchor := Vector2.ZERO
@export var loops := false

var _age := 0.0
var _playing := false


func _ready() -> void:
	if sheet != null: play(sheet, frame_count, frame_ms, anchor, loops)


func play(texture: Texture2D, frames: int, timings: Array[int], sheet_anchor: Vector2, looping := false) -> void:
	frame_ms = timings
	loops = looping
	self.texture = texture
	vframes = 1
	hframes = frames
	centered = false
	offset = -sheet_anchor * Units.ART_SCALE
	scale = Vector2(Units.ART_SCALE, Units.ART_SCALE)
	frame = 0
	_age = 0.0
	_playing = true
	visible = true


func _process(delta: float) -> void:
	if not _playing or frame_ms.is_empty(): return
	_age += delta
	var t := _age
	var total := 0.0
	for ms in frame_ms: total += ms / 1000.0
	if loops:
		t = fmod(t, total)
	elif t >= total:
		_playing = false
		queue_free()
		return
	var acc := 0.0
	for i in frame_ms.size():
		acc += frame_ms[i] / 1000.0
		if t < acc:
			frame = i
			return
