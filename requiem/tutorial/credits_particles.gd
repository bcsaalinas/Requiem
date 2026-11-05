extends Control
## A bounded set of 30 motes; no textures, physics or particle simulation.
var _clock := 0.0
var _motes: Array[Vector4] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 9817
	for i in 30:
		_motes.append(Vector4(rng.randf(), rng.randf(), rng.randf_range(0.5, 1.6), rng.randf_range(0.004, 0.012)))

func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()

func _draw() -> void:
	for mote in _motes:
		var position := Vector2(fposmod(mote.x + sin(_clock * 0.07 + mote.y * 12.0) * 0.018, 1.0), fposmod(mote.y - _clock * mote.w, 1.0)) * size
		var alpha := 0.10 + 0.12 * (sin(_clock * 0.3 + mote.x * 20.0) * 0.5 + 0.5)
		draw_circle(position, mote.z, Color(0.87, 0.87, 0.80, alpha), true, -1, true)
