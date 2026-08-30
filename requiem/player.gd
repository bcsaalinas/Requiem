extends CharacterBody2D

# Velocidades reducidas para simular cautela y tensión
var base_speed: float = 96.0
var sprint_speed: float = 165.0

# Variables de inercia para darle "peso" al personaje
var aceleracion: float = 0.1
var friccion: float = 0.15

func _ready():
	# 1. Gráficos del jugador
	var sprite = Sprite2D.new()
	var greybox_texture = PlaceholderTexture2D.new()
	greybox_texture.size = Vector2(32, 32)
	sprite.texture = greybox_texture
	sprite.modulate = Color(0.4, 0.7, 1.0)
	add_child(sprite)

	# 2. Colisión del jugador
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(26, 26)
	collision.shape = shape
	add_child(collision)
	
	# 3. Cámara de terror
	var camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0 # Más bajo = la cámara tarda más en seguirte (desorientación)
	camera.zoom = Vector2(1.5, 1.5) # Zoom muy cerrado para generar claustrofobia
	add_child(camera)
	camera.make_current()

func _physics_process(_delta):
	var input_dir = Vector2.ZERO

	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1

	input_dir = input_dir.normalized()
	
	var target_speed = base_speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		target_speed = sprint_speed

	# Lógica de inercia y peso (reemplaza el arranque instantáneo)
	var target_velocity = input_dir * target_speed
	
	if input_dir != Vector2.ZERO:
		# Arranca poco a poco
		velocity = velocity.lerp(target_velocity, aceleracion)
	else:
		# Frena resbalando ligeramente, no en seco
		velocity = velocity.lerp(Vector2.ZERO, friccion)

	move_and_slide()
