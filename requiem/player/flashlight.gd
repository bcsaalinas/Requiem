extends PointLight2D

# Flashlight (linterna de mano del jugador)
#
# Es un PointLight2D con textura de cono (prop_radius_0.png): la punta del cono
# esta en el borde IZQUIERDO de la imagen y es la zona mas brillante; hacia el
# extremo opuesto la luz se apaga sola. Por eso el haz "decae con la distancia"
# de forma natural: es la propia textura, no hace falta shader.
#
# Este script se encarga de:
#   - Apuntar el cono hacia el cursor (rota el nodo; el pivote es su origen,
#     que gracias a `offset` cae justo sobre el jugador -> gira "desde la mano").
#   - Encender / apagar con la accion "candle_toggle" (F por defecto).
#   - Gastar bateria mientras esta encendida; al llegar a 0 se apaga sola y no
#     se puede volver a prender.
#   - Atenuar y hacer parpadear el haz cuando la bateria esta baja.
#   - Estrechar el cono mientras el jugador aguanta la respiracion (costo de
#     percepcion: el ancho pasa de 100% a 45%).
#
# UNIDADES: 1 u = 32 px. El alcance del haz se exporta en
# unidades y se traduce a texture_scale con el ancho real de la textura, asi
# que cambiar la textura no rompe la escala.
const PX_PER_UNIT: float = 32.0

@export_group("Haz")
## Largo del cono en unidades (1 u = el ancho del jugador).
@export var beam_length_u: float = 13.0
## Brillo del haz con la bateria llena.
@export var beam_energy: float = 1.0
## Si es false el cono se queda quieto en su rotacion actual (para depurar).
@export var follow_mouse: bool = true
## Empieza encendida al cargar el nivel.
@export var start_on: bool = false

@export_group("Costo de aguantar la respiracion")
## Mientras el jugador aguanta la respiracion, el cono se estrecha a esta
## fraccion de su ancho normal (spec: 100% -> 45%). SOLO afecta scale.y (ancho
## perpendicular); scale.x (alcance) no se toca, asi se lee como "apuntar mas
## fino", no como "linterna mas chica".
@export_range(0.1, 1.0) var held_cone_width_ratio: float = 0.45
## Velocidad del easing del ancho del cono (mas alto = mas rapido). ~8 deja un
## ritmo parecido a los lerp de aceleracion/friccion de player.gd: se asienta
## en menos de un segundo.
@export var cone_ease_speed: float = 8.0

@export_group("Bateria")
## Cuanta bateria (en %) se gasta por segundo.
@export var battery_drain_rate_percent: float = 1.5
## Si es true la bateria SOLO baja mientras la linterna esta encendida.
@export var drains_only_when_on: bool = true
## Debajo de este %, el haz se atenua de forma proporcional y parpadea.
@export_range(0.0, 100.0) var low_battery_threshold: float = 25.0
## Brillo minimo (fraccion de beam_energy) al que llega el haz con la bateria
## casi vacia, antes de apagarse del todo.
@export_range(0.0, 1.0) var low_battery_min_level: float = 0.3

@export_group("Audio")
@export var click_clips: Array[AudioStream] = []
@export var volume_db: float = -8.0

var battery_percent: float = 100.0
var is_on: bool = false

var _audio_player: AudioStreamPlayer2D
var _flicker: float = 1.0
## Ancho "100%" del cono: el scale.y con el que arranca el nodo (Inspector o 1).
var _full_cone_width: float = 1.0

# --- Barra de bateria en pantalla (mismo patron que HoldBreath) ---
var _bar_layer: CanvasLayer
var _battery_bar: ProgressBar


func _ready() -> void:
	_audio_player = AudioStreamPlayer2D.new()
	add_child(_audio_player)

	_bar_layer = CanvasLayer.new()
	add_child(_bar_layer)

	_battery_bar = ProgressBar.new()
	_battery_bar.min_value = 0
	_battery_bar.max_value = 100
	_battery_bar.value = 100
	_battery_bar.size = Vector2(220, 24)
	# Debajo de las barras de HoldBreath (y=20 pulmon, y=54 agotamiento).
	_battery_bar.position = Vector2(20, 88)
	_battery_bar.show_percentage = false
	_battery_bar.visible = false
	_bar_layer.add_child(_battery_bar)

	_apply_beam_length()
	_full_cone_width = scale.y
	is_on = start_on and battery_percent > 0.0
	_refresh_light()
	_update_bar()


func _process(delta: float) -> void:
	if GameState.is_dead:
		return

	if follow_mouse and is_on:
		_aim_at_mouse()

	_tick_cone_width(delta)
	_tick_battery(delta)
	_tick_flicker(delta)
	_refresh_light()
	_update_bar()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("candle_toggle"):
		toggle()


## Enciende / apaga. No hace nada si intentas encender sin bateria.
func toggle() -> void:
	if GameState.is_dead:
		return
	if not is_on and battery_percent <= 0.0:
		return
	is_on = not is_on
	_play_click()
	_refresh_light()
	_update_bar()


func _aim_at_mouse() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 1.0:
		rotation = to_mouse.angle()


## Estrecha el cono mientras se aguanta la respiracion y lo devuelve a su ancho
## normal al soltar, con easing (no salta). Solo cambia scale.y; scale.x queda
## intacto para que se lea como "haz mas fino", no como "linterna mas chica".
##
## Lee el input directo (no el nodo HoldBreath) para mantener la linterna
## desacoplada. Efecto lateral menor: si el jugador mantiene la tecla durante
## el bloqueo por gasp forzado, el cono sigue fino esos ~2s aunque ya no este
## "aguantando" de verdad. Aceptable.
func _tick_cone_width(delta: float) -> void:
	var held := Input.is_action_pressed("hold_breath")
	var target_y := _full_cone_width * (held_cone_width_ratio if held else 1.0)
	var eased_y := lerpf(scale.y, target_y, clampf(cone_ease_speed * delta, 0.0, 1.0))
	scale = Vector2(scale.x, eased_y)


func _tick_battery(delta: float) -> void:
	if drains_only_when_on and not is_on:
		return
	if battery_percent <= 0.0:
		return

	battery_percent = max(0.0, battery_percent - battery_drain_rate_percent * delta)

	if battery_percent <= 0.0 and is_on:
		is_on = false
		_play_click()


## Parpadeo pseudoaleatorio mientras la bateria agoniza. Fuera de ese rango
## el haz queda perfectamente estable (_flicker = 1.0).
func _tick_flicker(delta: float) -> void:
	var dying := is_on and battery_percent > 0.0 and battery_percent <= low_battery_threshold
	if dying:
		if randf() < 0.18:
			_flicker = randf_range(low_battery_min_level, 1.0)
		else:
			_flicker = lerpf(_flicker, 1.0, delta * 8.0)
	else:
		_flicker = 1.0


## Vuelca el estado actual (encendida + bateria + parpadeo) sobre la luz real.
func _refresh_light() -> void:
	enabled = is_on
	if not is_on:
		return

	var level := 1.0
	if battery_percent <= low_battery_threshold:
		var t := clampf(battery_percent / maxf(low_battery_threshold, 0.001), 0.0, 1.0)
		level = lerpf(low_battery_min_level, 1.0, t)

	energy = beam_energy * level * _flicker


## texture_scale a partir del largo deseado en unidades, y `offset` para que la
## punta del cono (borde izquierdo de la textura) quede sobre el origen del nodo.
func _apply_beam_length() -> void:
	if texture == null:
		return
	texture_scale = beam_length_u * PX_PER_UNIT / float(texture.get_width())
	offset = Vector2(texture.get_width() * 0.5 * texture_scale, 0.0)


func _play_click() -> void:
	if click_clips.is_empty():
		return
	_audio_player.volume_db = volume_db
	_audio_player.stream = click_clips[randi() % click_clips.size()]
	_audio_player.play()


func _update_bar() -> void:
	_battery_bar.value = battery_percent
	_battery_bar.visible = is_on or battery_percent < 100.0


func get_battery_percent() -> float:
	return battery_percent
