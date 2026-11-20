extends TextureRect
## Plays the animated main-menu cover from its single atlas sheet.
##
## The cover is one 7680 x 3240 sheet: 8 columns x 6 rows of 960 x 540 frames, 90 ms each, a
## 4.32 s loop (export/ui/menu_cover.json in art-lab). This node shows one AtlasTexture at a
## time, so the TextureRect keeps owning the cover fit and the art is never resampled into a
## different frame size.
##
## The clock is absolute rather than frame-to-frame, so a dropped frame skips a drawing instead
## of slowing the loop down.

const SHEET := preload("res://assets/ui/menu_cover.png")
const FRAME_SIZE := Vector2i(960, 540)
const COLUMNS := 8
const FRAMES := 48
const FRAME_TIME := 0.09

var _frames: Array[AtlasTexture] = []
var _clock := 0.0
var _index := -1


func _ready() -> void:
	_frames.resize(FRAMES)
	for i in FRAMES:
		var frame := AtlasTexture.new()
		frame.atlas = SHEET
		frame.region = Rect2(
				Vector2(i % COLUMNS, i / COLUMNS) * Vector2(FRAME_SIZE), Vector2(FRAME_SIZE))
		_frames[i] = frame
	_show(0)


func _process(delta: float) -> void:
	_clock += delta
	_show(int(_clock / FRAME_TIME) % FRAMES)


func _show(index: int) -> void:
	if index == _index:
		return
	_index = index
	texture = _frames[index]
