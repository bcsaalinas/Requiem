extends AudioListener2D
## Viv's ears. Positional sound is heard from where she stands, not from the centre of the
## screen: near the edge of a zone the camera stops, and the two can be 12 u apart, enough for
## a sound on her right to play on the left.


func _ready() -> void:
	make_current()
