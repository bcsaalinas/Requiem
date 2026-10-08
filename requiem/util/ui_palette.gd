class_name UIPalette
extends RefCounted

# UIPalette (fuente UNICA de verdad del look de la interfaz)
#
# Mismo patron que Units: class_name con constantes y funciones estaticas, NO
# autoload. Se usa desde cualquier script sin registrar nada, funciona en
# scripts @tool, y se puede usar dentro de otra `const`.
#
# Los colores salen de hud.tscn tal como se autorizaron ahi. La razon de
# centralizarlos es la misma que la de Units: cada pantalla nueva que invente
# su propio gris acaba desalineada con las que ya se entregaron.

# --- Superficies ---
const PANEL := Color(0.035, 0.042, 0.039, 0.97)
const PANEL_SOLID := Color(0.035, 0.042, 0.039, 1.0)
const TRACK := Color(0.1, 0.14, 0.14, 0.8)
## 0e161b, el clear color del renderer.
const VOID := Color(0.055, 0.086, 0.106)

# --- Signos vitales ---
const BONE := Color(0.7647059, 0.76862746, 0.6666667)      # breath
const AMBER := Color(0.80784315, 0.6745098, 0.47058824)    # exertion
const ASH := Color(0.65882355, 0.6784314, 0.60784316)      # battery
const ALARM := Color(0.78, 0.33, 0.27)                     # umbral cruzado

# --- Texto ---
const TEXT := Color(0.8666667, 0.827451, 0.7254902)
const TEXT_DIM := Color(0.72156864, 0.7294118, 0.6901961)
const CANDLE := Color(0.95686275, 0.85882354, 0.61960787)
const SUBTITLE := Color(0.9411765, 0.9137255, 0.8509804)
const SHADOW := Color(0, 0, 0, 0.95)

# --- Medidas ---
const METER_SIZE := Vector2(110, 5)
const CAPTION_SIZE := 10
const BODY_SIZE := 18
const TITLE_SIZE := 24


static func flat(color: Color, margin := 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	if margin > 0.0:
		box.content_margin_left = margin
		box.content_margin_right = margin
		box.content_margin_top = margin * 0.8
		box.content_margin_bottom = margin * 0.8
	return box


## Toda etiqueta del juego lleva la misma sombra; sin ella el texto desaparece
## sobre un piso iluminado.
static func label(text: String, size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", SHADOW)
	node.add_theme_constant_override("shadow_offset_x", 1)
	node.add_theme_constant_override("shadow_offset_y", 2)
	return node


static func meter(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = METER_SIZE
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", flat(TRACK))
	bar.add_theme_stylebox_override("fill", flat(fill))
	return bar
