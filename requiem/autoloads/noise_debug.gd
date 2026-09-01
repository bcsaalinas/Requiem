extends Node

# NoiseDebug (Autoload)
#
# Visualizacion de debug de TODO ruido que pase por NoiseManager.
# Cada ruido se dibuja como un circulo en el mundo, en su posicion y radio
# reales, con una etiqueta que dice de que tipo es y cuanto mide EN UNIDADES.
# Sirve para ver a simple vista "que tan fuerte estoy sonando".
#
# No inventa nada: solo escucha la senal noise_emitted, igual que la Entity.
# Si un circulo aparece aqui, la entidad tambien lo oyo.
#
# OJO con la oscuridad: el dibujo NO va en el canvas principal, va en su propio
# CanvasLayer con follow_viewport_enabled. Asi sigue a la camara (y las
# coordenadas siguen siendo de mundo) pero el CanvasModulate del nivel no se lo
# come y los circulos siguen siendo legibles con las luces apagadas.
#
# UNIDADES: 1 u = 32 px. La etiqueta siempre reporta el radio
# en unidades, no en pixeles, para poder verificar la escala de un vistazo.
#
# F3 activa / desactiva la visualizacion.

const PX_PER_UNIT: float = 32.0


## Nodo interno que hace el dibujo. Vive dentro del CanvasLayer.
class NoiseCanvas extends Node2D:
	var debug: Node

	func _draw() -> void:
		if debug != null:
			debug._draw_noises(self)


@export_group("Tiempos")
## Cuanto tarda la onda en viajar del centro al borde.
@export var ring_travel_time: float = 0.35
## Cuanto dura el circulo en pantalla antes de desvanecerse del todo.
@export var fade_time: float = 1.2

@export_group("Dibujo")
@export var outline_width: float = 2.0
@export var fill_alpha: float = 0.07
@export var label_font_size: int = 16

@export_group("Consola")
## Imprime cada ruido en consola ademas de dibujarlo.
@export var log_to_console: bool = false

var enabled: bool = true

var _noises: Array = []
var _canvas_layer: CanvasLayer
var _canvas: NoiseCanvas
var _legend_layer: CanvasLayer
var _legend: Label


func _ready() -> void:
	# Capa de dibujo: sigue a la camara, pero fuera del canvas oscurecido.
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 50
	_canvas_layer.follow_viewport_enabled = true
	add_child(_canvas_layer)

	_canvas = NoiseCanvas.new()
	_canvas.debug = self
	_canvas_layer.add_child(_canvas)

	# Leyenda fija en pantalla.
	_legend_layer = CanvasLayer.new()
	_legend_layer.layer = 90
	add_child(_legend_layer)

	_legend = Label.new()
	_legend.position = Vector2(16, 16)
	_legend.add_theme_font_size_override("font_size", 14)
	_legend_layer.add_child(_legend)

	NoiseManager.noise_emitted.connect(_on_noise_emitted)
	_update_legend()


func _on_noise_emitted(noise_position: Vector2, radius: float, source_type: int, _duration: float) -> void:
	_noises.append({
		"position": noise_position,
		"radius": radius,
		"type": source_type,
		"age": 0.0,
	})
	if log_to_console:
		print("[NoiseDebug] %s  r=%.2f u (%.0f px)  pos=%s" % [
			_name_for(source_type), radius / PX_PER_UNIT, radius, str(noise_position)
		])
	_update_legend()
	_redraw()


func _process(delta: float) -> void:
	if _noises.is_empty():
		return

	for i in range(_noises.size() - 1, -1, -1):
		_noises[i]["age"] += delta
		if _noises[i]["age"] >= fade_time:
			_noises.remove_at(i)

	_update_legend()
	_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		enabled = not enabled
		_update_legend()
		_redraw()


func _redraw() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


## Llamado por NoiseCanvas._draw(). Recibe el Node2D sobre el que dibujar.
func _draw_noises(c: Node2D) -> void:
	if not enabled:
		return

	var font := ThemeDB.fallback_font

	for n in _noises:
		var age: float = n["age"]
		var radius: float = n["radius"]
		var center: Vector2 = n["position"]
		var col: Color = _color_for(n["type"])
		var life: float = clampf(1.0 - age / fade_time, 0.0, 1.0)

		# Relleno tenue de todo el alcance.
		c.draw_circle(center, radius, Color(col.r, col.g, col.b, fill_alpha * life))

		# Contorno en el radio REAL: esto es exactamente lo que puede oir la entidad.
		c.draw_arc(center, radius, 0.0, TAU, 64,
			Color(col.r, col.g, col.b, 0.9 * life), outline_width, true)

		# Onda que viaja del centro al borde. Solo para leer el evento a simple vista.
		var ring: float = clampf(age / ring_travel_time, 0.0, 1.0)
		if ring < 1.0:
			c.draw_arc(center, radius * ring, 0.0, TAU, 48,
				Color(col.r, col.g, col.b, (1.0 - ring) * life), 3.0, true)

		# Centro exacto: es el punto al que camina la entidad, no donde estas tu.
		c.draw_line(center - Vector2(6, 0), center + Vector2(6, 0), Color(col.r, col.g, col.b, life), 1.5)
		c.draw_line(center - Vector2(0, 6), center + Vector2(0, 6), Color(col.r, col.g, col.b, life), 1.5)

		# Etiqueta: tipo + radio EN UNIDADES.
		var label := "%s  %.2f u" % [_name_for(n["type"]), radius / PX_PER_UNIT]
		c.draw_string(font, center + Vector2(-radius, -radius - 6.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size,
			Color(col.r, col.g, col.b, life))


func _color_for(source_type: int) -> Color:
	match source_type:
		NoiseManager.SourceType.FOOTSTEP: return Color(0.55, 0.85, 1.0)
		NoiseManager.SourceType.SPRINT: return Color(1.0, 0.55, 0.2)
		NoiseManager.SourceType.CROUCH: return Color(0.4, 0.6, 0.8)
		NoiseManager.SourceType.BREATH: return Color(0.5, 1.0, 0.6)
		NoiseManager.SourceType.PRAY: return Color(0.85, 0.45, 1.0)
		NoiseManager.SourceType.THROW: return Color(1.0, 0.9, 0.3)
		NoiseManager.SourceType.CANDLE: return Color(1.0, 0.75, 0.4)
		_: return Color(0.8, 0.8, 0.8)


func _name_for(source_type: int) -> String:
	var keys := NoiseManager.SourceType.keys()
	if source_type >= 0 and source_type < keys.size():
		return String(keys[source_type])
	return "UNKNOWN"


func _update_legend() -> void:
	if _legend == null:
		return
	var state := "ON" if enabled else "OFF"
	_legend.text = "NOISE DEBUG [F3]: %s    1 u = %d px    activos: %d" % [
		state, int(PX_PER_UNIT), _noises.size()
	]
	_legend.modulate = Color(1, 1, 1, 0.85) if enabled else Color(1, 1, 1, 0.35)
