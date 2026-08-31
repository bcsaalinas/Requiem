extends PointLight2D

# Flashlight
#
# Luz direccional que el jugador sostiene, apuntando al mouse. La textura
# (prop_radius_0.png) ya viene como un cono con la punta en el borde
# IZQUIERDO de la imagen — pero Godot centra la textura sobre el nodo por
# default, asi que sin corregir nada el cono queda mitad adentro del
# jugador y mitad flotando al lado, y al rotar gira alrededor de un punto
# que no es el jugador.
#
# `offset` recorre la textura para que esa punta quede exactamente sobre
# el origen del nodo. Con eso arreglado, rotar el nodo SI hace que el cono
# pivotee desde el jugador, como una linterna de verdad.
#
# UNIDADES: ver docs/UNITS.md. Este script no convierte nada, solo apunta;
# el alcance real ya lo definen texture + texture_scale puestos a mano en
# el nodo desde el Inspector.

## Si esta en false, el cono se queda fijo en la rotacion actual del nodo.
## Util para probar el offset sin que el mouse lo este moviendo.
@export var follow_mouse: bool = true


func _ready() -> void:
	_recenter_offset()


func _process(_delta: float) -> void:
	if not follow_mouse:
		return

	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 1.0:
		rotation = to_mouse.angle()


## Recalcula el offset para que la punta del cono (borde izquierdo de la
## textura) quede pegada al origen del nodo. Se calcula del tamano real de
## la textura, asi que sigue funcionando si cambias la textura o el
## texture_scale desde el Inspector, sin tener que retocar este numero.
func _recenter_offset() -> void:
	if texture == null:
		return
	offset = Vector2(texture.get_width() * 0.5 * texture_scale, 0.0)
