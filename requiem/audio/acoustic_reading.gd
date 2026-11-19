class_name AcousticReading
extends RefCounted
## One measurement of how an emitter's sound reaches Viv (audio/acoustics.gd makes them).

## False when there was nothing to measure: no listener, or the emitter is not in the scene or
## not shown. Such a reading is ring 0, clarity 0.
var valid := false
## Straight-line distance, in units.
var straight_u := 0.0
## A wall is on the straight line.
var blocked := false
## Length of the walking path between them (through the doorways), in units. -1: no path.
var path_u := -1.0
## How far the sound really travels: the straight line when nothing blocks it, otherwise
## mostly the walking path.
var acoustic_u := 0.0
## 1 = every detail is heard, 0 = nothing of it is left.
var clarity := 0.0
## 3 on top of you, 2 near, 1 somewhere, 0 gone.
var ring := 0
## Where the listener stood and where the emitter was, in world pixels.
var listener_at := Vector2.ZERO
var emitter_at := Vector2.ZERO
## The walking path that was measured, from the emitter to the listener (empty: none).
var path := PackedVector2Array()


func ring_name() -> String:
	return ["gone", "somewhere", "near", "on top of you"][clampi(ring, 0, 3)]
