class_name Units
extends RefCounted

# Units (fuente UNICA de verdad de la escala del juego)
#
# 1 u = 32 px = el ancho del jugador.
#
# Antes cada script (player, entity_ai, hold_breath, flashlight, footstep_noise,
# throw, body_altar, noise_debug) declaraba su propio `const PX_PER_UNIT = 32.0`.
# Si algun dia cambia la escala habia que acordarse de 8 archivos, y el altar ya
# se equivoco una vez (340 px creyendo que 1 u = 64 px). Ahora vive aqui.
#
# Es un class_name con constantes y funciones estaticas, NO un autoload:
#   - se puede usar desde cualquier script sin registrar nada en Project Settings
#   - tambien funciona en scripts @tool (el editor), que es donde se arman niveles
#   - se puede usar dentro de otra `const` (un autoload no, porque no existe
#     todavia cuando el script se compila)

## Pixeles por unidad de juego.
const PX_PER_UNIT: float = 32.0

# --- Cuadricula del nivel -----------------------------------------------------
# Las capas de tiles (muros "Map" y props "Props") usan celdas de 32 px, asi
# que 1 tile = 1 u: un pasillo de 3 tiles mide 3 u, igual que los radios de
# ruido. Es una constante aparte de PX_PER_UNIT a proposito: es el tamano del
# arte de los tiles, y no debe cambiar solo porque cambie la escala.

## Lado de una celda de las capas de tiles, en pixeles.
const TILE_PX: int = 32


static func to_px(units: float) -> float:
	return units * PX_PER_UNIT


static func to_u(pixels: float) -> float:
	return pixels / PX_PER_UNIT


static func vec_to_px(v_units: Vector2) -> Vector2:
	return v_units * PX_PER_UNIT


static func vec_to_u(v_pixels: Vector2) -> Vector2:
	return v_pixels / PX_PER_UNIT
