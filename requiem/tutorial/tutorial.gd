extends Node2D
## Tutorial orchestration. Existing player mechanics remain untouched.
signal stage_changed(stage: String)
signal tutorial_completed
const World := preload("res://tutorial/world.gd")
const Art := preload("res://tutorial/art.gd")
## Pista de ambiente real por zona (reemplaza el placeholder corto
## room.wav/forest.wav de tutorial/assets/audio). bedroom es la unica que se
## queda tranquila; hallway usa viento (corriente de aire, inquieta antes de
## salir); house y loop comparten el sotano porque las dos son la etapa
## "ketsu" (climax) de stage_for_zone en enter_zone().
const ZONE_AMBIENCE_PATHS := {
	"bedroom": "res://assets/audio/407553__juane170058__room-tone-ambiance-in-empty-warehouse.wav",
	"hallway": "res://assets/audio/341839__ianstargem__spook-wind-ambience.wav",
	"forest": "res://assets/audio/320145__owlstorm__night-crickets-ambience-on-rural-property.wav",
	"house": "res://assets/audio/410746__simo170075__basement-ambience.wav",
	"loop": "res://assets/audio/410746__simo170075__basement-ambience.wav",
	"mansion_ground": "res://assets/audio/410746__simo170075__basement-ambience.wav",
	"mansion_upper": "res://assets/audio/410746__simo170075__basement-ambience.wav",
}
## Compensacion de volumen POR PISTA (no por zona: house/loop comparten
## archivo y compensacion). Cada archivo real trae un nivel de grabacion muy
## distinto -- el de bedroom es literalmente "room tone" de post-produccion
## (pensado para ser casi inaudible) y mide -68.5dB de mean_volume, contra
## -25/-28dB de los de viento y grillos. Sin esto, ambience.volume_db fijo en
## -18 (ver AmbientAudio en tutorial.tscn) deja a bedroom en silencio total.
## Los numeros compensan hasta emparejar el nivel percibido que ya tenia el
## room.wav/forest.wav viejo (-18dB de nodo + -30dB de archivo ~= -48dB), mas
## un +8dB parejo a las 4 para que el ambiente se note mas fuerte en general.
## +8dB es el limite comodo: bedroom es el mas ajustado de pico (-29.8dBFS de
## maximo en el archivo + 28dB de aca = -1.8dBFS), los otros tres sobran de
## margen.
const ZONE_AMBIENCE_VOLUME_DB := {
	"bedroom": 28.0,
	"hallway": -15.0,
	"forest": -11.5,
	"house": 3.5,
	"loop": 3.5,
	"mansion_ground": 2.0,
	"mansion_upper": 2.0,
}
## Sounds the player makes; the parents and the forest only react to these.
const PLAYER_SOUNDS := [NoiseManager.SourceType.FOOTSTEP, NoiseManager.SourceType.SPRINT,
	NoiseManager.SourceType.CROUCH, NoiseManager.SourceType.BREATH, NoiseManager.SourceType.THROW,
	NoiseManager.SourceType.DOOR]
const HEARD_PHASE := 20.0
const HEARD_PHASE_RETRY := 8.0
const HEARD_BEAM_WAIT := 3.0
const PRESENCE_PATH: Array[Dictionary] = [
	{"at": 3.0, "spot": Vector2(544, 650), "caption": "[Something drags itself in by the front door]"},
	{"at": 8.0, "spot": Vector2(608, 560), "caption": "[Dragging, closer]"},
	{"at": 13.0, "spot": Vector2(608, 470), "caption": "[Wet breathing]", "breathing": true},
	{"at": 17.0, "spot": Vector2(660, 380), "caption": "", "carried": true},
]
const UNEASE_SPOTS := {
	"Kitchen": [Vector2(240, 300), Vector2(150, 560), Vector2(330, 200)],
	"Vestibule": [Vector2(608, 200), Vector2(470, 330), Vector2(700, 600)],
	"AltarRoom": [Vector2(1008, 250), Vector2(1100, 560), Vector2(880, 330)],
}
const UNEASE_CUES := [
	["chair_scrape", "[A chair drags]", -7.0],
	["behind_wall", "[Something moves behind the wall]", -8.0],
	["presence", "[Something shifts in another room]", -10.0],
	["thud", "[A heavy knock under the floor]", -9.0],
	["door", "[A door moves somewhere in the house]", -10.0],
]
## Seconds a warned parent keeps listening before settling again.
const PARENT_LISTEN_TIME := 3.5
## A parent door starts to stir when her next step falls short of it by less than this fraction of
## the step's reach (walking 3 u: 72 px; held 1 u: 24 px), so holding the breath visibly settles it.
const HALL_STIR_MARGIN := 0.75
## Doors that lead to another zone when the player walks through the open doorway.
const ZONE_DOORS := ["bedroom_exit", "hall_back", "hall_exit", "forest_back", "front_door"]
@export_category("Entry")
@export_enum("bedroom", "hallway", "forest", "house", "loop", "mansion_ground", "mansion_upper") var start_zone: String = "bedroom"
@export_group("Validation")
@export var test_mode := false
@onready var world: Node2D = $TutorialWorld
@onready var hud: CanvasLayer = $HUD
@onready var player: CharacterBody2D = $Player
var breath: Node
var thrower: Node
var flashlight: PointLight2D
@onready var entity: CharacterBody2D = $Entity
@onready var prayer_audio: AudioStreamPlayer2D = $PrayerAudio
@onready var heard_flash: Node2D = $NoiseFx/HeardFlash
@onready var film: ColorRect = $Atmosphere/Film
var field_map: Node
@onready var ambient_modulate: CanvasModulate = $TutorialAmbient
var zone := "bedroom"
var stage := "ki"
var has_flashlight: bool:
	get:
		return is_instance_valid(player) and player.get_node("ActionState").has_flashlight
	set(value):
		if is_instance_valid(player): player.get_node("ActionState").has_flashlight = value
var batteries := 0
var window_broken := false
var door_unlocked := false
var has_key := false
var key_used := false
var key_noise_at := Vector2.INF
var heard_length := 0.0
var heard_step := 0
var heard_at := Vector2.INF
var heard_phase_seen := false
var arrival_place := Vector2.INF
var arrival_target := Vector2.ZERO
var arrival_wait := 0.0
var _beam_image: Image
var _caption_time := 0.0
var _unease_time := 0.0
var _unease_next := 3.5
var _unease_count := 0
var _unease_last := -1
var ranger_checkpoint_ready := false
var prayer_captioned := false
var breathing_captioned := false
var stone_hint_seen := false
var space_hint := false
var has_sprinted := false
var has_thrown := false
var sprint_hint_time := 0.0
var flash_hint_time := 0.0
var friend_met := false
var attack_finished := false
var complete := false
var collected: Dictionary = {}
var checkpoint: Dictionary = {}
var dialogue: Array[String] = []
var dialogue_done: Callable
var subtitle_time := 0.0
var banner_time := 0.0
var encounter_grace := 0.0
var resetting := false
var sequence := ""
var sequence_time := 0.0
var sequence_step := 0
var nearest := ""
var forest_cued := false
var hall_cued := false
var hall_door_cues: Dictionary = {}
var hall_refuge_cued := false
var hall_audio_clock := 0.0
var loop_cued := false
var ambient_reply_cooldown := 0.0
var parent_failures := 0
## The first time a parent hears the player is a warning, not a failure (safe first encounter).
var hall_warned := false
var hall_listen_time := 0.0
## The hold-breath lesson ends once she is past both parent doors; the key hint goes with it.
var hall_lesson_done := false
## Doors that already stirred audibly during this approach (index -> true).
var hall_stirred: Dictionary = {}
## The centred alert asks for Space; holding it clears the alert early.
var hall_hold_alert := false
var loop_hold_seen := false
## The house entrance shuts behind the player once, the first time they step inside.
var front_door_shut_behind := false
var low_battery_hinted := false
var dead_light_time := 0.0
## Eased 0..1 closeness of the hunting entity (drives the Atmosphere vignette).
var threat_pressure := 0.0
var hunt_intro_effect := 0.0
var friend_home := Vector2.ZERO
var _paused := false
var _paused_modes: Dictionary = {}
var _sounds: Dictionary = {}

func _enter_tree() -> void:
	GameState.reset()

func _ready() -> void:
	field_map = preload("res://tutorial/field_map.gd").new()
	field_map.name = "FieldMap"
	add_child(field_map)
	if not test_mode: Kiosk.enter_fullscreen()
	get_viewport().size_changed.connect(_frame_camera)
	# Beyond the walls is void: black, like the unlit rooms.
	RenderingServer.set_default_clear_color(Color.BLACK)
	thrower=player.get_node("Throw")
	breath=player.get_node("HoldBreath")
	player.get_node("Sprite2D").hide()
	breath._bar_layer.hide()
	thrower.rock_landed.connect(_on_rock_landed)
	thrower.object_released.connect(func(): has_thrown = true)
	entity.state_changed.connect(_on_entity_state_changed)
	MusicDirector.bind_gameplay(entity, breath)
	flashlight=player.get_node("flashlight")
	has_flashlight=false
	flashlight.battery_percent=0.0
	flashlight._update_bar()
	flashlight._bar_layer.hide()
	flashlight.set_process(false)
	flashlight.set_process_unhandled_input(false)
	flashlight.toggled.connect(func(_on: bool) -> void: hud.pulse_slot("flashlight"))
	flashlight.toggle_rejected.connect(func() -> void:
		if batteries <= 0:
			hud.reject_slot("flashlight"))
	entity.caught.connect(_caught)
	var ranger: Node = world.zones["forest"].get_node("Ranger")
	ranger.caught.connect(_on_ranger_caught)
	ranger.spotted.connect(_on_ranger_spotted)
	hud.resume_requested.connect(_toggle_pause)
	hud.fullscreen_requested.connect(_toggle_fullscreen)
	PauseMenu.resume_pressed.connect(_toggle_pause)
	prayer_audio.stream=sound("prayer")
	prayer_audio.bus="SFX"
	prayer_audio.finished.connect(func():
		if zone=="house" and not attack_finished: prayer_audio.play())
	flashlight.click_clips.assign([load("res://assets/audio/629008__realgtro__flashlight-click.wav")])
	thrower.piedra_clips.assign([sound("rock")])
	thrower.piedra_release_clips.assign([sound("stone_throw")])
	if test_mode:
		player.get_node("FootstepNoise").walk_clips.clear()
		breath.hold_clips.clear()
		breath.exhale_clips.clear()
		breath.exertion_clips.clear()
		thrower.piedra_clips.clear()
		thrower.piedra_release_clips.clear()
		flashlight.click_clips.clear()
	NoiseManager.noise_emitted.connect(_on_noise)
	GameState.altar_completed.connect(_on_altar_prayed)
	GameState.all_altars_completed.connect(_on_all_altars_prayed)
	for id in ZONE_DOORS:
		if world.interactables.has(id):
			var door_data = world.interactables[id]["node"]
			if door_data is Door:
				var door := door_data as Door
				var doorway = door.get_node_or_null("Doorway") as Area2D
				if doorway != null:
					doorway.body_entered.connect(_on_zone_doorway.bind(id))
				door.opened.connect(func(): _on_zone_doorway(player,id))
	if world.interactables.has("stairs_to_upper"):
		var stairs_up = world.interactables["stairs_to_upper"]["node"]
		if stairs_up is Area2D:
			stairs_up.body_entered.connect(func(body):
				if body == player and zone == "mansion_ground":
					interact("stairs_to_upper")
			)
	if world.interactables.has("stairs_to_ground"):
		var stairs_down = world.interactables["stairs_to_ground"]["node"]
		if stairs_down is Area2D:
			stairs_down.body_entered.connect(func(body):
				if body == player and zone == "mansion_upper":
					interact("stairs_to_ground")
			)
	friend_home=world.props["friend"].global_position
	prayer_audio.global_position=friend_home
	enter_zone(start_zone)
	field_map.bind_game(self)
	if not test_mode:
		show_dialogue([
			"ELI: I'm at my aunt's old house. Follow the yellow trail marks. Bring a light.",
			"ELI: And be quiet leaving. Your parents are still awake."
		])
		play_sound("phone",player.position)

func _exit_tree() -> void:
	PauseMenu.set_open(false)
	get_tree().paused=false
	for audio in get_tree().get_nodes_in_group("tutorial_audio"):
		audio.stop()
		audio.stream=null
	_sounds.clear()
	AmbienceManager.set_track(null, -80.0)
	MusicDirector.bind_gameplay(null, null)
	GameState.reset()

func sound(id: String) -> AudioStream:
	if id == "prayer":
		return preload("res://tutorial/assets/audio/prayer_female.mp3")
	if not _sounds.has(id): _sounds[id]=load("res://tutorial/assets/audio/%s.wav"%id)
	return _sounds[id]

func play_sound(id: String, at: Vector2, volume := -8.0) -> AudioStreamPlayer2D:
	if test_mode: return null
	var audio:=AudioStreamPlayer2D.new()
	audio.position=at
	audio.bus="SFX"
	audio.stream=sound(id)
	audio.volume_db=volume
	audio.pitch_scale=randf_range(0.92, 1.06)
	add_child(audio)
	audio.add_to_group("tutorial_audio")
	audio.finished.connect(audio.queue_free)
	audio.play()
	return audio

func _play_pickup_sound(at: Vector2) -> void:
	var variants := ["pickup_hand_1", "pickup_hand_2", "pickup_hand_3", "pickup_hand_4"]
	play_sound(variants.pick_random(), at, -7.0)

## Moves the player into a zone. `arrival_door` (an interaction id) starts open behind the
## player and swings shut once they step away from it.
func enter_zone(next_zone: String, spawn := Vector2.INF, save := true, arrival_door := "") -> void:
	zone=next_zone
	ambient_reply_cooldown=0
	world.set_house_danger(attack_finished)
	var start_markers:={
		"bedroom":"SpawnStart",
		"hallway":"SpawnFromBedroom",
		"forest":"SpawnFromHome",
		"house":"SpawnFromForest",
		"loop":"SpawnFromHouse",
		"mansion_ground":"SpawnEntrance",
		"mansion_upper":"SpawnFromStairs"
	}
	if spawn==Vector2.INF:
		spawn=world.marker(zone,start_markers.get(zone, "SpawnStart"))
	player.position=spawn
	player.velocity=Vector2.ZERO
	player.get_node("FootstepNoise").reset_steps()
	heard_flash.clear()
	var rooms: RoomVisibility = world.rooms(zone)
	if rooms != null:
		rooms.sync_to(player.position)
	if arrival_door != "" and world.interactables.has(arrival_door):
		_close_behind(world.interactables[arrival_door]["node"])
	player.get_node("PlayerMotion").reset_pose()
	player.get_node("PlayerAim").reset_pose()
	_frame_camera()
	player.get_node("Camera2D").reset_smoothing()
	var stage_for_zone:={
		"bedroom":"ki",
		"hallway":"ki",
		"forest":"sho",
		"house":"ketsu" if attack_finished else "ten",
		"loop":"ketsu",
		"mansion_ground":"ketsu",
		"mansion_upper":"ketsu"
	}
	stage=stage_for_zone.get(zone, "ketsu")
	stage_changed.emit(stage)
	if ZONE_AMBIENCE_PATHS.has(zone):
		var zone_stream := load(ZONE_AMBIENCE_PATHS[zone]) as AudioStream
		AmbienceManager.set_track(zone_stream if not test_mode else null,
			ZONE_AMBIENCE_VOLUME_DB.get(zone, 0.0), 2.0)
	prayer_audio.stop()
	if zone=="house" and not attack_finished and not test_mode:
		prayer_audio.play()
		if not prayer_captioned:
			prayer_captioned = true
			caption("[Low praying]")
	_configure_entity()
	hud.set_breath_hint(false)
	if ambient_modulate != null:
		# The new mansion follows the tutorial's near-black ambient level; local
		# lamps, the flashlight, and the breathing ring now reveal what is nearby.
		ambient_modulate.color = Color(0.019607844, 0.023529412, 0.03137255, 1.0)
	if zone in ["mansion_ground", "mansion_upper"]:
		hud.show_altars_tracker(true)
		hud.set_altars_count(GameState.altars_completed, 7)
	if zone == "hallway":
		hall_door_cues.clear()
		hall_stirred.clear()
		hall_refuge_cued=false
		hall_audio_clock=0
	if zone == "forest":
		ranger_checkpoint_ready = false
		world.zones["forest"].get_node("ThrowTarget").hide()
	if save: save_checkpoint()

func _configure_entity() -> void:
	entity.revisit_chance = 0.35
	entity.hide()
	entity.active=false
	# The forest ranger is a separate character from the house entity. Keep him
	# active only in his zone so thrown stones can reach his noise listener.
	var ranger_zone: Node = world.zones.get("forest") as Node
	if ranger_zone != null:
		var forest_ranger := ranger_zone.get_node_or_null("Ranger") as CharacterBody2D
		if forest_ranger != null:
			forest_ranger.active = zone == "forest"
			if zone == "forest":
				forest_ranger.reset_patrol()
	MusicDirector.clear_entity_threat()
	encounter_grace=0.0
	# The opening forest and impossible room suggest a presence through spatial sound.
	# No invisible active monster: the physical threat exists only after the altar attack.
	if zone == "house" and attack_finished:
		var points: Array[Vector2] = []
		for index in range(1,7):
			points.append(world.marker("house","Patrol%d" % index))
		# New-sounds encounter: let the house sound occupied before the entity is
		# visible. Once she takes the key, it enters from the front door and walks
		# toward the noise the key made.
		entity.reset_encounter(world.marker("house","EntityArrive"),points)
		entity.set_breathing(false)
		entity.get_node("CollisionShape2D").set_deferred("disabled", true)
		arrival_place = Vector2.INF
		heard_step = 0
		heard_at = Vector2.INF
		_unease_time = 0.0
		_unease_next = 3.5
		_unease_count = 0
		_unease_last = -1
		if has_key:
			_begin_presence()
	elif zone == "mansion_ground":
		var points: Array[Vector2] = []
		for index in range(1, 9):
			points.append(world.marker("mansion_ground", "Patrol%d" % index))
		entity.reset_encounter(world.marker("mansion_ground", "EntitySpawn"), points)
		entity.show()
		encounter_grace = 6.0
	elif zone == "mansion_upper":
		var points: Array[Vector2] = []
		for index in range(1, 7):
			points.append(world.marker("mansion_upper", "Patrol%d" % index))
		entity.reset_encounter(world.marker("mansion_upper", "Patrol1"), points)
		entity.show()
		encounter_grace = 4.0

func _process(delta: float) -> void:
	if _paused: return
	_update_house_roof()
	hunt_intro_effect = move_toward(hunt_intro_effect, 0.0, delta * 1.5)
	if zone == "forest":
		world.interactables["ranger"]["position"] = world.zones["forest"].get_node("Ranger").global_position
	ambient_reply_cooldown=maxf(0,ambient_reply_cooldown-delta)
	if subtitle_time>0:
		subtitle_time-=delta
		if subtitle_time<=0 and dialogue.is_empty(): hud.subtitle.text=""
	if banner_time>0:
		banner_time-=delta
		if banner_time<=0: hud.banner.text=""
	if _caption_time > 0.0:
		_caption_time -= delta
		if _caption_time <= 0.0: hud.caption.text = ""
	hud.breath.value=breath.lung_percent
	hud.effort.value=breath.exertion_percent
	hud.update_breath_feedback(player.get_node("BreathFeedback"))
	hud.battery.value=flashlight.battery_percent
	hud.update_inventory(has_flashlight,batteries,thrower.rocks)
	hud.set_key(has_key and not key_used)
	var throw_cooldown_frac := 0.0
	if "_cooldown_timer" in thrower and "_release_cooldown" in thrower:
		throw_cooldown_frac = clampf(thrower._cooldown_timer / maxf(thrower._release_cooldown, 0.001), 0.0, 1.0)
	hud.update_equipment_state(flashlight.is_on, flashlight.battery_percent, batteries, thrower.rocks, throw_cooldown_frac)
	_update_key_hint(delta)
	if not dialogue.is_empty(): hud.place_prompt(Vector2.ZERO,true)
	if not dialogue.is_empty() or resetting: return
	if sequence!="": _tick_sequence(delta)
	if zone == "house" and attack_finished:
		if not has_key: _tick_unease(delta)
		if heard_phase_seen:
			if encounter_grace > 0.0:
				_tick_heard_phase(delta)
			if arrival_place != Vector2.INF: _tick_arrival(delta)
	elif encounter_grace>0:
		encounter_grace-=delta
		if encounter_grace<=0 and not complete and entity.visible:
			entity.active=true
			# reset_encounter stops all loops; explicitly restart her breathing when
			# the mansion's quiet-entry grace period ends.
			entity.set_breathing(true)
	if zone=="hallway": _tick_hallway(delta)
	if zone=="forest" and not forest_cued and player.position.x>3500:
		forest_cued=true
		say("[A branch snaps beyond the marked path. Nothing moves.]",5)
		play_sound("branch",Vector2(3630,215),-4)
	if zone == "forest": _tick_ranger_checkpoint()
	if zone=="loop" and not loop_cued and player.position.x>7460:
		loop_cued=true
		play_sound("behind_wall",_wall_listeners()[0]+Vector2(0,-60),-5)
		say("[Slow dragging on the other side of the wall.]",5)
	if zone=="loop" and breath.is_holding: loop_hold_seen=true
	if zone=="house" and door_unlocked and not attack_finished and player.position.y<660 and checkpoint.get("position",Vector2.ZERO).y>704:
		save_checkpoint()
	if zone=="house": _shut_front_door_behind()
	_update_threat_presentation()
	_tick_battery(delta)
	_find_interaction()

func caption(message: String, duration := 4.0) -> void:
	hud.caption.text = message
	_caption_time = duration

func in_presence() -> bool:
	return zone == "house" and attack_finished and heard_phase_seen and (encounter_grace > 0.0 or arrival_place != Vector2.INF)

func in_unease() -> bool:
	return zone == "house" and attack_finished and not has_key and not complete and not resetting

func _begin_presence() -> void:
	var duration := HEARD_PHASE_RETRY if heard_phase_seen else HEARD_PHASE
	heard_phase_seen = true
	heard_step = 0
	heard_length = duration
	heard_at = Vector2.INF
	encounter_grace = duration
	breathing_captioned = false

func _tick_unease(delta: float) -> void:
	_unease_time += delta
	if _unease_time < _unease_next:
		return
	_unease_time = 0.0
	_unease_next = randf_range(5.0, 9.0)
	_unease_count += 1
	var cue: Array = UNEASE_CUES.pick_random()
	var rooms: RoomVisibility = world.rooms("house")
	var current_room := String(rooms.current.name) if rooms != null and rooms.current != null else ""
	var room_names: Array = UNEASE_SPOTS.keys().filter(func(name): return name != current_room)
	if room_names.is_empty(): room_names = UNEASE_SPOTS.keys()
	var spots: Array = UNEASE_SPOTS[room_names.pick_random()]
	var at: Vector2 = world.zones["house"].global_position + spots.pick_random()
	if _unease_count % 3 == 0:
		at = player.global_position + Vector2.RIGHT.rotated(player.global_rotation) * -120.0
	play_sound(String(cue[0]), at, float(cue[2]))
	caption(String(cue[1]), 3.0)

func _tick_heard_phase(delta: float) -> void:
	encounter_grace = maxf(0.0, encounter_grace - delta)
	var elapsed := heard_length - encounter_grace
	var beat_scale: float = heard_length / HEARD_PHASE
	while heard_step < PRESENCE_PATH.size() and elapsed >= float(PRESENCE_PATH[heard_step].at) * beat_scale:
		var step: Dictionary = PRESENCE_PATH[heard_step]
		var origin: Vector2 = world.zones["house"].global_position
		heard_at = origin + step.spot
		entity.global_position = heard_at
		if bool(step.get("breathing", false)):
			entity.set_breathing(true)
			if not breathing_captioned:
				breathing_captioned = true
				caption(String(step.caption), 4.0)
		if bool(step.get("carried", false)):
			play_sound("presence", heard_at, -3.0)
		elif not bool(step.get("breathing", false)):
			play_sound("presence", heard_at)
			if not String(step.caption).is_empty(): caption(String(step.caption), 4.0)
		heard_step += 1
	if encounter_grace <= 0.0 and arrival_place == Vector2.INF:
		var target := key_noise_at if key_noise_at != Vector2.INF else friend_home
		var from_position: Vector2 = heard_at if heard_at != Vector2.INF else world.marker("house", "EntityArrive")
		_arrive(from_position, target)

func _arrive(place: Vector2, target: Vector2) -> void:
	var navigation := world.landmarks.get("HouseNavigation") as NavigationRegion2D
	var map: RID = navigation.get_navigation_map() if navigation != null else RID()
	arrival_place = NavigationServer2D.map_get_closest_point(map, place) if map.is_valid() else place
	arrival_target = target
	arrival_wait = HEARD_BEAM_WAIT
	entity.global_position = arrival_place

func _in_beam(at: Vector2) -> bool:
	if flashlight == null or not flashlight.enabled or not flashlight.is_on or flashlight.texture == null:
		return false
	if _beam_image == null:
		var texture := flashlight.texture as Texture2D
		if texture == null: return false
		_beam_image = texture.get_image()
	if _beam_image == null: return false
	var local: Vector2 = flashlight.global_transform.affine_inverse() * at
	var pixel: Vector2 = (local - flashlight.offset) / flashlight.texture_scale + Vector2(_beam_image.get_size()) * 0.5
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= _beam_image.get_width() or pixel.y >= _beam_image.get_height(): return false
	var texel: Color = _beam_image.get_pixelv(Vector2i(pixel))
	return texel.a * texel.v > 0.05

func _tick_arrival(delta: float) -> void:
	arrival_wait -= delta
	if arrival_wait > 0.0 and _in_beam(arrival_place): return
	entity.global_position = arrival_place
	entity.get_node("CollisionShape2D").set_deferred("disabled", false)
	entity.show()
	entity.active = true
	entity.notice(arrival_target)
	arrival_place = Vector2.INF

func _update_key_hint(delta: float) -> void:
	sprint_hint_time = maxf(0.0, sprint_hint_time - delta)
	flash_hint_time = maxf(0.0, flash_hint_time - delta)
	var message := ""
	if space_hint and not breath.is_holding: message = "SPACE  ·  Hold breath"
	elif sprint_hint_time > 0.0: message = "SHIFT  ·  Sprint"
	elif flash_hint_time > 0.0: message = "F  ·  Flashlight"
	elif zone == "forest" and thrower.rocks > 0 and not has_thrown: message = "Q  ·  Throw rock"
	hud.show_key_hint(message, PixelDisplay.world_to_ui(player.global_position))

func _tick_hallway(delta: float) -> void:
	hall_audio_clock -= delta
	hall_listen_time = maxf(0.0, hall_listen_time - delta)
	var listeners := _parent_listeners()
	var nearest_door: ParentListener = null
	for index in range(listeners.size()):
		var door: ParentListener = listeners[index]
		var gap := absf(player.position.x - door.global_position.x)
		if nearest_door == null or gap < absf(player.position.x - nearest_door.global_position.x):
			nearest_door = door
		if gap < 190 and not hall_door_cues.has(index):
			hall_door_cues[index]=true
			hall_cued=true
			if index==0 and not hall_lesson_done:
				say("[A chair scrapes behind the door]\nThey're still up. Hold my breath past their doors.",5)
				caption("[Chair scrapes behind the door]", 5.0)
				space_hint = true
			else:
				say("[A chair scrapes behind the door]" if index==0 else "[Movement behind the door]",4)
				caption("[Chair scrapes behind the door]" if index==0 else "[Movement behind the door]", 4.0)
			play_sound("chair_scrape",door.global_position+Vector2(0,-40),-3)
			hall_audio_clock=4.0
	if hall_audio_clock<=0 and nearest_door != null:
		play_sound("parent_rustle",nearest_door.global_position+Vector2(0,-40),-7)
		hall_audio_clock=6.5
	# Teach before the danger: a door stirs once her next step could reach it and settles while she
	# holds her breath. The key stays next to the breath meter until both doors are behind her.
	var in_light := _safe_light_at(player.position) != null
	var step_radius := _next_step_radius()
	var urgency := 0.0
	for index in range(listeners.size()):
		var door: ParentListener = listeners[index]
		var reach := door.distance_to_edge(player.position)-step_radius
		door.danger = 0.0 if in_light else 1.0-smoothstep(0.0,HALL_STIR_MARGIN*step_radius,reach)
		urgency = maxf(urgency,door.danger)
		if door.danger >= 0.6 and not hall_stirred.has(index):
			hall_stirred[index]=true
			play_sound("parent_rustle",door.global_position+Vector2(0,-40),-4)
			hall_audio_clock=maxf(hall_audio_clock,4.0)
		elif door.danger < 0.2:
			hall_stirred.erase(index)
	if not hall_lesson_done and not listeners.is_empty() and player.position.x > listeners.back().global_position.x+90:
		hall_lesson_done=true
		space_hint = false
	hud.set_breath_hint(not hall_lesson_done,breath.is_holding,urgency,delta)
	if hall_hold_alert and breath.is_holding:
		hall_hold_alert=false
		hud.dismiss_alert()
	# Only explain the refuge when it matters: arriving out of breath or still holding it.
	if in_light and not hall_refuge_cued and (breath.is_holding or breath.lung_percent < 80.0):
		hall_refuge_cued=true
		say("Safe in the light. Let your breath go. Rest here.",5)
	elif not in_light and not breath.is_holding:
		hall_refuge_cued=false

## Reach of the step she would take now, in px: held, walking or running.
func _next_step_radius() -> float:
	var steps := player.get_node("FootstepNoise")
	if breath.is_holding: return steps.held_noise_radius_u*Units.PX_PER_UNIT
	if player.velocity.length() >= steps.sprint_threshold_u*Units.PX_PER_UNIT: return steps.sprint_noise_radius_u*Units.PX_PER_UNIT
	return steps.walk_noise_radius_u*Units.PX_PER_UNIT

func _parent_listeners() -> Array[ParentListener]:
	var listeners: Array[ParentListener] = []
	for node in world.nodes_in("hallway","Listeners"):
		if node is ParentListener: listeners.append(node)
	return listeners

## Where the impossible room answers back: the cold-lit doors of the loop corridor.
func _wall_listeners() -> Array:
	var points := []
	for node in world.nodes_in("loop","Listeners"):
		if node is ParentListener: points.append(node.global_position+Vector2(0,-40))
	return points

func _safe_light_at(point: Vector2) -> SafeLight:
	for node in world.nodes_in(zone,"SafeLights"):
		if node is SafeLight and node.contains(point): return node
	return null

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if key in [KEY_H,KEY_ESCAPE]:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused: return
	# In the shipping run R belongs to Kiosk: it drops the whole run back to the title.
	if key==KEY_R and not resetting and not Kiosk.owns_reset(self):
		request_reset("Back to the last safe place.")
		get_viewport().set_input_as_handled()
		return
	if event.is_action("swap_battery") and dialogue.is_empty() and not resetting:
		insert_battery()
		get_viewport().set_input_as_handled()
	# The light key on a dead flashlight swaps in a spare: what players try first.
	if event.is_action("candle_toggle") and has_flashlight and flashlight.battery_percent<=0 and batteries>0 \
			and dialogue.is_empty() and not resetting:
		insert_battery()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("throw") and hud.inventory.get_node("Rocks").visible and thrower.rocks<=0 \
			and dialogue.is_empty() and not resetting:
		hud.reject_slot("rocks")
		say("No rocks left")
	if event.is_action_pressed("sprint"):
		has_sprinted = true
		sprint_hint_time = 0.0
	if event.is_action_pressed("throw"):
		has_thrown = true
	if event.is_action_pressed("candle_toggle"):
		flash_hint_time = 0.0
	if key==KEY_E:
		if not dialogue.is_empty(): advance_dialogue()
		elif not resetting and sequence=="":
			_find_interaction()
			if nearest!="": interact(nearest)
		get_viewport().set_input_as_handled()

func show_dialogue(lines: Array[String], done := Callable()) -> void:
	dialogue.assign(lines)
	dialogue_done=done
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.velocity=Vector2.ZERO
	entity.active=false
	hud.subtitle.text=dialogue[0]
	hud.prompt.text="E  ·  Continue"
	hud.place_prompt(Vector2.ZERO,true)

func advance_dialogue() -> void:
	if dialogue.is_empty(): return
	dialogue.pop_front()
	if not dialogue.is_empty():
		hud.subtitle.text=dialogue[0]
		return
	player.process_mode=Node.PROCESS_MODE_INHERIT
	hud.subtitle.text=""
	hud.prompt.text=""
	if dialogue_done.is_valid():
		var callback:=dialogue_done
		dialogue_done=Callable()
		callback.call()

func say(message: String, duration := 4.0) -> void:
	hud.subtitle.text=message
	subtitle_time=duration

func _find_interaction() -> void:
	nearest=""
	var distance:=85.0
	for id in world.interactables:
		if not interaction_available(id): continue
		var at: Vector2=world.interactables[id]["position"]
		var d:=player.position.distance_to(at)
		if d<distance:
			distance=d
			nearest=id
	for id in world.interactables:
		var prop_node: Node2D=world.interactables[id]["node"]
		if prop_node.has_method("set_focused"):
			prop_node.set_focused(id==nearest)
	hud.prompt.text="" if nearest=="" else "E  ·  "+interaction_label(nearest)
	if nearest!="": hud.place_prompt(PixelDisplay.world_to_ui(world.interactables[nearest]["position"]))

## The exterior roof sits above room contents by design. Lift it while a room is occupied so the
## player, pickups and the new HUD prompts remain visible from the top-down camera.
func _update_house_roof() -> void:
	var rooms: RoomVisibility = world.rooms("house")
	var inside_house: bool = zone == "house" and rooms != null and rooms.current != null
	var house: Node = world.zones.get("house") as Node
	if house == null:
		return
	for node_name in ["ArtRoof", "ArtRoofEaves", "ArtRoofEaveCorners"]:
		var roof := house.get_node_or_null(node_name) as CanvasItem
		if roof != null:
			roof.visible = not inside_house

func interaction_available(id: String) -> bool:
	if collected.has(id): return false
	if id == "phone" and not bool(world.interactables["chest_bedroom"]["node"].get("is_open")): return false
	if id.begins_with("chest_"):
		if id == "chest_vestibule" and not attack_finished: return false
		var chest: Node = world.interactables[id]["node"]
	if id=="flashlight" and has_flashlight: return false
	if id=="friend": return zone=="house" and not friend_met
	if id=="altar_pray": return false # The friend demonstrates prayer in this introduction.
	if id=="window" and door_unlocked: return false
	return true

func interaction_label(id: String) -> String:
	if id.begins_with("chest_"):
		var chest: Node = world.interactables[id]["node"]
		if bool(chest.get("is_open")):
			return "Read" if String(chest.get("loot")) == "note" else "Take"
	if id=="window" and window_broken: return "Release latch"
	if id=="front_door" and attack_finished and has_key and not key_used: return "Unlock door"
	if id=="front_door" and door_unlocked: return "Open door"
	var node: Node = world.interactables[id]["node"]
	if node is Door:
		if node.is_open and id in ZONE_DOORS and _zone_door_active(id): return "Go through"
		return node.interaction_label()
	return world.interactables[id]["label"]

func interact(id: String) -> void:
	if not interaction_available(id): return
	# Distance validation is shared by normal input and tests; no remote interactions.
	if player.position.distance_to(world.interactables[id]["position"])>85: return
	var target_node: Node = world.interactables[id]["node"]
	if id.begins_with("chest_"):
		if id == "chest_vestibule" and not attack_finished: return
		if not target_node.has_method("open"):
			push_warning("Chest interaction '%s' has no open() method" % id)
			return
		if not bool(target_node.get("is_open")):
			target_node.call("open", breath.is_holding)
			if id == "chest_bedroom":
				world.interactables["phone"]["node"].show()
			if String(target_node.get("loot")) == "empty":
				collected[id] = true
				say("The chest is empty")
			return
		collected[id] = true
		target_node.call("take_content")
		match String(target_node.get("loot")):
			"battery":
				batteries += 1
				if has_flashlight and flashlight.battery_percent <= 0.0:
					insert_battery()
				else:
					say("Battery +1")
			"stones":
				if thrower.rocks < 3:
					thrower.rocks = mini(3, thrower.rocks + 3)
					say("Rocks +3")
				else:
					say("Rocks full")
			"key":
				has_key = true
				key_noise_at = target_node.global_position
				hud.set_key(true)
				hud.pulse_slot("key")
				say("Found a key")
				if zone == "house" and attack_finished:
					_begin_presence()
			"note":
				var note := String(target_node.get("note_text"))
				if not note.is_empty(): show_dialogue([note])
			"empty":
				say("The chest is empty")
		return
	if target_node is Door and not id in ZONE_DOORS and id != "mansion_main_porton" and id != "loop_end" and id != "loop_back":
		_use_door(target_node as Door)
		return
	if id.contains("battery"):
		batteries+=1
		collect(id)
		if has_flashlight and flashlight.battery_percent<=0: insert_battery()
		else: say("Battery +1")
		return
	if id.contains("rocks"):
		if thrower.rocks>=3:
			say("Rocks full")
		else:
			thrower.rocks+=3
			_play_pickup_sound(player.position)
			_animate_rocks(world.interactables[id]["node"].global_position)
			say("Rocks +3",5)
		return
	match id:
		"phone":
			show_dialogue(["ELI: Follow the yellow trail marks to my aunt's house. Bring your flashlight."])
		"flashlight":
			has_flashlight=true
			collect(id)
			flashlight.set_process(true)
			flashlight.set_process_unhandled_input(true)
			if batteries>0: insert_battery()
			else: say("Flashlight")
		"battery","forest_battery","porch_battery","house_battery", \
		"mansion_battery_zaguan","battery_library","battery_service","battery_kitchen", \
		"battery_ballroom","battery_study","battery_main_bedroom","battery_gallery":
			batteries+=1
			collect(id)
			if has_flashlight and flashlight.battery_percent<=0: insert_battery()
			else: say("Battery +1")
		"bedroom_exit":
			var exit_door: Door = world.interactables[id]["node"]
			if exit_door.is_open:
				_go_through(id)
				return
			# Gate on what was collected, not on the charge left: an empty battery must never
			# lock the player in the bedroom (bug: dead battery prevents leaving).
			if not has_flashlight:
				say("I need a light before I go.")
				return
			if not collected.has("battery"):
				say("The flashlight needs its battery.")
				return
			if flashlight.battery_percent<=0 and batteries>0: insert_battery()
			_use_door(exit_door)
		"hall_back","hall_exit":
			var door: Door = world.interactables[id]["node"]
			if door.is_open: _go_through(id)
			else: _use_door(door)
		"forest_back":
			var home_door: Door = world.interactables[id]["node"]
			if home_door.is_open: _go_through(id)
			else: _use_door(home_door)
		"forest_rocks","porch_rocks", \
		"mansion_rocks_zaguan","patio_rocks_sw","patio_rocks_ne","rocks_sotano", \
		"rocks_storage","rocks_chapel","rocks_kitchen","rocks_main_bedroom", \
		"rocks_sewing","rocks_living","rocks_balcony":
			if thrower.rocks>=3:
				say("Rocks full")
			else:
				thrower.rocks+=3
				_play_pickup_sound(player.position)
				_animate_rocks(world.interactables[id]["node"].global_position)
				say("Rocks +3",5)
		"forest_exit":
			var ranger = world.zones["forest"].get_node("Ranger")
			if ranger.chasing:
				say("Not with him right behind me.", 4.0)
				return
			enter_zone("house")
		"ranger": say("RANGER: This trail is closed tonight. Head back home.", 5.0)
		"house_back":
			if attack_finished: say("The path has disappeared into the dark.")
			else: enter_zone("forest",world.marker("forest","SpawnFromHouse"))
		"window":
			if window_broken:
				# Reaching through the broken glass releases the latch; the door stays a real door.
				door_unlocked=true
				var front_door: Door = world.interactables["front_door"]["node"]
				front_door.locked=false
				front_door.open()
				say("[Latch clicks. The door swings in.]",5)
			else: say("The latch is behind the glass.\nQ · Throw rock",6)
		"front_door":
			var front_door: Door = world.interactables[id]["node"]
			if attack_finished and has_key and not key_used:
				key_used=true
				door_unlocked=true
				front_door.locked=false
				hud.set_key(false)
				play_sound("door",player.position)
				say("The key turns in the lock.",4)
			if not door_unlocked:
				say("Locked. The latch is beside the window.",5)
				play_sound("door",player.position)
				if not test_mode:
					NoiseManager.emit_noise(front_door.get_noise_origin(), 2.0 * Units.PX_PER_UNIT, NoiseManager.SourceType.DOOR)
			elif attack_finished and front_door.is_open:
				_go_through(id)
			else:
				_use_door(front_door)
		"kitchen_door","altar_door", \
		"door_kitchen","door_library","door_storage","door_chapel","door_service_dorm","door_ballroom", \
		"door_study","door_main_bedroom","door_gallery","door_sewing","door_living","door_stairs":
			_use_door(world.interactables[id]["node"])
		"mansion_main_porton":
			if GameState.altars_completed >= GameState.total_altars:
				complete = true
				hud.end_title.show()
				entity.active = false
				encounter_grace = 0
				tutorial_completed.emit()
				(world.interactables[id]["node"] as Door).open(breath.is_holding)
				say("El sello se ha roto. Has consagrado los 7 altares y escapado de la Hacienda.", 8.0)
			else:
				say("El portón está sellado con un cerrojo pesado. Debes consagrar los 7 altares.", 5.0)
				play_sound("door", player.position)
				if not test_mode:
					NoiseManager.emit_noise((world.interactables[id]["node"] as Door).get_noise_origin(), 2.0 * Units.PX_PER_UNIT, NoiseManager.SourceType.DOOR)
		"stairs_to_upper":
			enter_zone("mansion_upper", world.marker("mansion_upper", "SpawnFromStairs"), true)
			play_sound("door", player.position)
			say("Subiendo a la planta alta...", 3.0)
		"stairs_to_ground":
			enter_zone("mansion_ground", world.marker("mansion_ground", "SpawnFromUpper"), true)
			play_sound("door", player.position)
			say("Bajando a la planta baja...", 3.0)
		"altar_1", "altar_2", "altar_3", "altar_4", "altar_5", "altar_6", "altar_7":
			say("Mantén presionada la tecla [E] durante 12 segundos para consagrar la ofrenda.", 4.5)
		"friend":
			friend_met=true
			show_dialogue([
				"ELI: My aunt said we had to come here and pray at the altars. It keeps something here.",
				"ELI: Wait. Do you hear that?"
			],_begin_attack)
		"loop_back":
			say("It won't open.")
			play_sound("door", player.position)
			if not test_mode:
				NoiseManager.emit_noise(world.interactables[id]["position"], 2.0 * Units.PX_PER_UNIT, NoiseManager.SourceType.DOOR)
		"loop_end":
			if not complete:
				complete=true
				hud.end_title.show()
				entity.active=false
				encounter_grace=0
				tutorial_completed.emit()
				# The last door opens onto more darkness.
				(world.interactables[id]["node"] as Door).open(breath.is_holding)
				say("There has to be another way out.",9)
				play_sound("impossible",player.position,-14)

func collect(id: String) -> void:
	collected[id]=true
	var item: Node2D = world.interactables[id]["node"]
	_play_pickup_sound(player.position)
	# The item flies into her hands and the inventory slot pops; her animation is untouched.
	var tween := item.create_tween()
	tween.tween_property(item,"global_position",player.global_position+Vector2(0,-12),0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(item,"scale",Vector2(0.4,0.4),0.25)
	tween.tween_callback(item.hide)
	hud.pulse_slot("flashlight" if id=="flashlight" else "battery")

## Three pebbles hop from the pile one after another and land in her hands. She stands right
## next to the pile, so the hop (not the distance) is what makes the pickup read.
func _animate_rocks(pile: Vector2) -> void:
	var hands := player.global_position+Vector2(0,-12)
	for index in range(3):
		var pebble := Polygon2D.new()
		pebble.polygon = PackedVector2Array([Vector2(-4,-2),Vector2(-1,-5),Vector2(4,-3),Vector2(5,2),Vector2(0,4),Vector2(-4,2)])
		pebble.color = Color(0.62,0.6,0.55)
		pebble.z_index = 5
		world.add_child(pebble)
		var start := pile+Vector2(randf_range(-10,10),randf_range(-6,4))
		pebble.global_position = start
		var tween := pebble.create_tween()
		tween.tween_interval(index*0.08)
		tween.tween_property(pebble,"global_position",start.lerp(hands,0.5)+Vector2(0,-22),0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(pebble,"global_position",hands,0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(pebble,"scale",Vector2(0.5,0.5),0.14)
		tween.tween_callback(pebble.queue_free)
	hud.pulse_slot("rocks")

func insert_battery() -> void:
	if not has_flashlight:
		say("Take the flashlight first.")
		return
	if batteries<=0:
		hud.reject_slot("battery")
		say("No spare battery")
		return
	if flashlight.battery_percent>85:
		hud.reject_slot("battery")
		say("Battery is full")
		return
	batteries-=1
	flashlight.battery_percent=100
	flashlight.is_on=true
	flashlight._refresh_light()
	play_sound("battery_insert",player.position,-5.0)
	if not test_mode and zone != "bedroom":
		NoiseManager.emit_noise(player.global_position, 1.5 * Units.PX_PER_UNIT, NoiseManager.SourceType.FLASHLIGHT)
	hud.pulse_slot("battery")
	say("Battery replaced")
	low_battery_hinted=false

## Bug fix (battery changing was not intuitive): a hint appears only when the light fades and a
## spare exists, and a dead light is swapped automatically after a beat if the player has a spare.
func _tick_battery(delta: float) -> void:
	if not has_flashlight or resetting or not dialogue.is_empty(): return
	var charge: float = flashlight.battery_percent
	if charge>0.0 and charge<=flashlight.low_battery_threshold and batteries>0 and not low_battery_hinted:
		low_battery_hinted=true
		say("The light is fading.\nB · Swap battery",5)
	if charge<=0.0 and batteries>0:
		dead_light_time+=delta
		if dead_light_time>=1.2:
			insert_battery()
			say("Her hands find a spare battery in the dark.",4)
	else:
		dead_light_time=0.0

func _on_rock_landed(at: Vector2) -> void:
	if zone!="house" or window_broken: return
	var side_light: WallWindow = world.interactables["window"]["node"]
	if at.distance_to(side_light.global_position+Vector2(0,-48))>59: return
	window_broken=true
	side_light.broken=true
	play_sound("glass",at,-3)
	NoiseManager.emit_noise(at,256,NoiseManager.SourceType.ENVIRONMENT)
	# The figure stands just behind the glass; it draws above the room cover for this one beat.
	var reveal := world.landmarks.get("Reveal", world.landmarks.get("reveal")) as Node2D
	var reveal_at := side_light.global_position + Vector2(0, -24)
	if reveal != null:
		reveal.modulate=Color(.65,.65,.65,.65)
		reveal.z_index=45
		reveal.show()
		reveal_at = reveal.global_position
	play_sound("presence",reveal_at)
	sequence="reveal"
	sequence_time=0
	var reveal_light: PointLight2D = world.lamp(reveal_at+Vector2(0,30),Color("a9b9a7"),.8,.45)
	reveal_light.name="RevealLight"
	# The figure is light-only on layer 4: only this light ever shows it.
	reveal_light.range_item_cull_mask |= 8
	say("[Glass shatters]",4)

## The screen closes in as the entity comes near, and intensifies sharply when it focuses/hunts.
func _update_threat_presentation() -> void:
	var pressure := 0.0
	var focus_target := 0.0
	if entity.active and entity.visible:
		var distance := entity.global_position.distance_to(player.global_position)
		var prox := 1.0 - smoothstep(2.0 * Units.PX_PER_UNIT, 14.0 * Units.PX_PER_UNIT, distance)
		var state_name: String = entity.get_state_name()
		var listening: bool = entity.has_method("is_listening") and entity.is_listening()
		var screaming: bool = entity.has_method("is_screaming") and entity.is_screaming()
		if state_name == "HUNT" or screaming:
			pressure = 1.0 - smoothstep(2.0 * Units.PX_PER_UNIT, 11.5 * Units.PX_PER_UNIT, distance)
			focus_target = clampf(0.45 + 0.55 * prox, 0.45, 1.0)
		elif listening:
			pressure = prox * 0.65
			focus_target = 0.65
		elif state_name == "SEARCH":
			pressure = prox * 0.55
			focus_target = prox * 0.5
		else:
			pressure = prox * 0.35
	threat_pressure = lerpf(threat_pressure, pressure, 0.08)
	var mat := film.material as ShaderMaterial
	mat.set_shader_parameter("pressure", threat_pressure)
	var cur_focus: float = float(mat.get_shader_parameter("focus")) if mat.get_shader_parameter("focus") != null else 0.0
	var next_focus := lerpf(cur_focus, focus_target, 0.12)
	mat.set_shader_parameter("focus", next_focus)
	mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin( float(Time.get_ticks_msec()) * 0.012 ))
	mat.set_shader_parameter("hunt_intro", hunt_intro_effect)

func _on_entity_state_changed(_previous: int, current: int) -> void:
	if current == 3:
		hunt_intro_effect = 1.0

## Shown on the capture screen: the sound that gave the player away.
func game_over_cause() -> String:
	if entity.last_heard_source < 0: return "It found you in the dark."
	return "It heard your %s." % _noise_name(entity.last_heard_source).replace(" right by the door","")

## Bug fix: the entrance stays a visible door and swings shut once the player is inside.
func _shut_front_door_behind() -> void:
	if front_door_shut_behind or not door_unlocked or attack_finished: return
	var front_door: Door = world.interactables["front_door"]["node"]
	var rooms: RoomVisibility = world.rooms("house")
	if front_door.is_open and rooms.current != null and rooms.current.name == "Vestibule" \
			and player.position.y < front_door.global_position.y-130 and not front_door.is_doorway_occupied():
		front_door_shut_behind=true
		front_door.close(true)
		save_checkpoint()

func _begin_attack() -> void:
	sequence="attack"
	sequence_time=0
	sequence_step=0
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.velocity=Vector2.ZERO
	thrower.available=false
	play_sound("presence",friend_home+Vector2(-10,-150))
	say("[Scraping behind the wall]",3)

func _tick_sequence(delta: float) -> void:
	sequence_time+=delta
	if sequence=="reveal":
		if sequence_time>=1.15:
			var reveal := world.landmarks.get("Reveal", world.landmarks.get("reveal")) as Node2D
			if reveal != null: reveal.hide()
			var light:=world.get_node_or_null("RevealLight")
			if light!=null: light.queue_free()
			sequence=""
			say("",6)
		return
	if sequence!="attack": return
	if sequence_time>=2.3 and sequence_step==0:
		sequence_step=1
		play_sound("thud",friend_home,-2)
		NoiseManager.emit_noise(friend_home,256,NoiseManager.SourceType.ENVIRONMENT)
		hud.shade.color=Color(0,0,0,.96)
		world.props["friend"].hide()
		say("[A gasp. A heavy impact.]",3)
	if sequence_time>=3.6 and sequence_step==1:
		sequence_step=2
		world.props["friend"].fallen=true
		world.props["friend"].global_position=friend_home+Vector2(0,27)
		world.props["friend"].show()
		hud.shade.color=Color(0,0,0,0)
		prayer_audio.stop()
		attack_finished=true
		world.set_house_danger(true)
		stage="ketsu"
		stage_changed.emit(stage)
		player.process_mode=Node.PROCESS_MODE_INHERIT
		thrower.available=true
		_configure_entity()
		save_checkpoint()
		say("Eli…?",6)
		sequence=""

func _on_noise(at: Vector2, radius: float, source: int, _duration: float) -> void:
	# The unseen passages answer audible player actions, without an invisible capture body.
	# This preserves a readable relationship between breath, footfalls and environmental response.
	if zone in ["forest","loop"] and not resetting and ambient_reply_cooldown<=0:
		if source in [NoiseManager.SourceType.FOOTSTEP,NoiseManager.SourceType.SPRINT,NoiseManager.SourceType.BREATH,NoiseManager.SourceType.THROW]:
			var listeners: Array = [world.marker("forest","ListenerA"),world.marker("forest","ListenerB")] if zone=="forest" else _wall_listeners()
			for listener in listeners:
				if at.distance_to(listener)<=radius:
					play_sound("branch" if zone=="forest" else "behind_wall",listener,-4)
					say("[Branches shift nearby]" if zone=="forest" else "[The dragging stops]",4)
					ambient_reply_cooldown=6.0
					break
	if zone!="hallway" or resetting or not dialogue.is_empty(): return
	# Parents listen to player actions only; ambience never becomes a failure signal.
	if source not in PLAYER_SOUNDS: return
	# Light means safety: nothing made inside a lit refuge reaches the doors.
	if _safe_light_at(at) != null: return
	for listener in _parent_listeners():
		if listener.hears(at,radius):
			_parent_heard(listener,at,source)
			return

## A parent heard the player: the door edge flashes red so the cause is visible.
## The first time is a warning that teaches Hold Breath; after that the player is sent back.
func _parent_heard(listener: ParentListener, at: Vector2, source: int) -> void:
	print("[Tutorial] parent heard ",NoiseManager.SourceType.keys()[source]," at ",at.round()," (warned before: ",hall_warned,")")
	heard_flash.flash(listener.to_global(Vector2(-listener.half_width,0)),listener.to_global(Vector2(listener.half_width,0)))
	listener.listen()
	if not hall_warned:
		hall_warned=true
		hall_listen_time=PARENT_LISTEN_TIME
		play_sound("parent_rustle",listener.global_position+Vector2(0,-40),-2)
		say("DAD: ...Hm? Someone up?",PARENT_LISTEN_TIME+2.5)
		# Held steps right by the door are the one sound Space cannot fix: ask for distance instead.
		hall_hold_alert = source != NoiseManager.SourceType.CROUCH
		if hall_hold_alert: hud.flash_alert("HOLD  SPACE","Hold your breath and your steps go quiet.",PARENT_LISTEN_TIME)
		else: hud.flash_alert("TOO CLOSE","Even held steps carry right by their door.",PARENT_LISTEN_TIME)
		# She freezes for a beat so the warning and the prompt land before another step can count.
		# Only movement stops: breath input stays live, so Space pressed now works at once.
		player.velocity=Vector2.ZERO
		player.get_node("FootstepNoise").reset_steps()
		player.set_physics_process(false)
		get_tree().create_timer(1.1).timeout.connect(func(): player.set_physics_process(true))
		return
	parent_failures+=1
	request_reset("DAD: Back to bed. Now.\nHe heard your %s through the door." % _noise_name(source),true)

func _on_ranger_spotted() -> void:
	if zone == "forest" and not resetting:
		say("RANGER: You there! Stop!", 3.0)
		if not has_sprinted: sprint_hint_time = 4.0

func _on_ranger_caught() -> void:
	if zone == "forest" and not resetting:
		request_reset("RANGER: Trail's closed. Go home.")

func _tick_ranger_checkpoint() -> void:
	var forest: Node2D = world.zones["forest"]
	var ranger: CharacterBody2D = forest.get_node("Ranger")
	if ranger.get("distracted"):
		forest.get_node("ThrowTarget").hide()
	if ranger_checkpoint_ready: return
	var setup: Vector2 = forest.global_position + Vector2(700, 400)
	if player.global_position.distance_to(setup) > 55.0: return
	ranger_checkpoint_ready = true
	thrower.rocks = maxi(thrower.rocks, 3)
	player.global_position = setup
	player.velocity = Vector2.ZERO
	player.get_node("FootstepNoise").reset_steps()
	save_checkpoint()
	ranger.active = true
	forest.get_node("ThrowTarget").show()

func _noise_name(source: int) -> String:
	match source:
		NoiseManager.SourceType.SPRINT: return "running"
		NoiseManager.SourceType.CROUCH: return "careful steps right by the door"
		NoiseManager.SourceType.BREATH: return "breath"
		NoiseManager.SourceType.THROW: return "throw"
		NoiseManager.SourceType.DOOR: return "door"
		NoiseManager.SourceType.FLASHLIGHT: return "flashlight"
	return "footsteps"

## Opens or shuts a door; holding your breath eases it quietly.
func _use_door(door: Door) -> void:
	if door.locked:
		say(door.locked_label,3)
		play_sound("door", door.get_noise_origin())
		if not test_mode:
			NoiseManager.emit_noise(door.get_noise_origin(), 2.0 * Units.PX_PER_UNIT, NoiseManager.SourceType.DOOR)
		return
	if door.is_open: door.close(breath.is_holding)
	else: door.open(breath.is_holding)

func _on_zone_doorway(body: Node2D, id: String) -> void:
	var door := world.interactables[id]["node"] as Door
	if body==player and not resetting and dialogue.is_empty() and door.is_open and _zone_door_active(id) \
			and (door.get_node("Doorway") as Area2D).overlaps_body(player):
		_go_through.call_deferred(id)

## The house entrance only leads elsewhere after the attack (into the impossible room).
func _zone_door_active(id: String) -> bool:
	return id!="front_door" or attack_finished

func _go_through(id: String) -> void:
	var door := world.interactables[id]["node"] as Door
	if resetting or not door.is_open or not _zone_door_active(id): return
	match id:
		"front_door":
			if test_mode:
				enter_zone("loop",Vector2.INF,true,"loop_back")
			else:
				enter_zone("mansion_ground", world.marker("mansion_ground", "SpawnEntrance"), true, "mansion_main_porton")
				play_sound("impossible", player.position)
				say("La salida hacia el patio desapareció... Has entrado al zaguán de la Hacienda. El portón se ha sellado.", 7.0)
		"bedroom_exit": enter_zone("hallway",Vector2.INF,true,"hall_back")
		"hall_back": enter_zone("bedroom",world.marker("bedroom","SpawnFromHallway"),true,"bedroom_exit")
		"hall_exit":
			enter_zone("forest",Vector2.INF,true,"forest_back")
			say("The yellow marks. Eli went this way.",5)
		"forest_back": enter_zone("hallway",world.marker("hallway","SpawnFromForest"),true,"hall_exit")
	door.snap(false)

## Arriving through a door: it is open behind the player and swings shut once they step away.
func _close_behind(door: Door) -> void:
	door.snap(true)
	await get_tree().create_timer(0.6).timeout
	while is_instance_valid(door) and door.is_open and (door.is_doorway_occupied() or player.position.distance_to(door.get_noise_origin())<72.0):
		await get_tree().create_timer(0.2).timeout
	if is_instance_valid(door) and door.is_open: door.close(true)

func _on_altar_prayed(altar_node: Node) -> void:
	hud.set_altars_count(GameState.altars_completed, GameState.total_altars)
	play_sound("switch", player.position, 2.0)
	var altar_name := "Ofrenda"
	if "altar_name" in altar_node:
		altar_name = altar_node.altar_name
	say("%s consagrada (%d / %d). La llama de cempasúchil arde." % [altar_name, GameState.altars_completed, GameState.total_altars], 5.0)

func _on_all_altars_prayed() -> void:
	hud.set_altars_count(GameState.total_altars, GameState.total_altars)
	say("¡Los 7 altares han sido consagrados! El cerrojo del portón principal se ha abierto.", 8.0)
	play_sound("impossible", player.position, 0.0)
	if world.interactables.has("mansion_main_porton"):
		var porton: Door = world.interactables["mansion_main_porton"]["node"]
		porton.locked = false
		porton.locked_label = ""

func _caught() -> void:
	if resetting or not dialogue.is_empty() or sequence != "": return
	_begin_game_over()

# La entidad atrapo al jugador: congela la escena y muestra la pantalla de
# derrota (GameState.player_died -> GameOverUi instancia ui/game_over.tscn).
func _begin_game_over() -> void:
	resetting=true
	entity.active=false
	encounter_grace=0
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.velocity=Vector2.ZERO
	dialogue.clear()
	dialogue_done=Callable()
	sequence=""
	_hide_window_reveal()
	var reveal_light:=world.get_node_or_null("RevealLight")
	if reveal_light!=null: reveal_light.queue_free()
	play_sound("presence",player.position)
	# The catch plays first: the arms snap shut, the shroud folds over her, a beat of stillness.
	entity.sprite_rig.hide_player.connect(_hide_caught_player,CONNECT_ONE_SHOT)
	entity.play_catch(player.global_position)
	get_tree().create_timer(entity.catch_screen_delay if not test_mode else .01,false).timeout.connect(_show_game_over,CONNECT_ONE_SHOT)

## The hands are under the cloth from here (catch.json hide_player).
func _hide_caught_player() -> void:
	if resetting: player.get_node("Appearance").hide()

func _show_game_over() -> void:
	if not resetting or GameState.is_dead: return
	hud.shade.color=Color(0,0,0,.82)
	GameState.kill_player()

# Lo invoca la pantalla de game over cuando el jugador pulsa "Reintentar":
# reanuda desde el ultimo checkpoint en lugar de narrar su captura.
func retry_from_game_over() -> void:
	if not resetting: return
	_restore_after_delay(false)

func save_checkpoint() -> void:
	checkpoint={"zone":zone,"position":player.position,"battery":flashlight.battery_percent,"batteries":batteries,"rocks":thrower.rocks}
	print("[Tutorial] checkpoint: ",zone," / ",stage)

func request_reset(message: String, bedroom := false) -> void:
	if resetting: return
	resetting=true
	entity.active=false
	encounter_grace=0
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.velocity=Vector2.ZERO
	dialogue.clear()
	dialogue_done=Callable()
	if sequence=="attack":
		# Retrying before the completed attack should permit the conversation again.
		friend_met=false
		world.props["friend"].show()
	sequence=""
	_hide_window_reveal()
	var reveal_light:=world.get_node_or_null("RevealLight")
	if reveal_light!=null: reveal_light.queue_free()
	hud.shade.color=Color(0,0,0,.82)
	say(message,4)
	play_sound("parent" if bedroom else "presence",player.position)
	_restore_after_delay(bedroom)

func _hide_window_reveal() -> void:
	var reveal := world.landmarks.get("Reveal", world.landmarks.get("reveal")) as Node2D
	if reveal != null: reveal.hide()

func _restore_after_delay(bedroom: bool) -> void:
	await get_tree().create_timer(.7 if not test_mode else .01).timeout
	restore_checkpoint(bedroom)

func restore_checkpoint(bedroom := false) -> void:
	thrower.clear_pending()
	breath._audio_player.stop()
	breath.is_holding=false
	breath.is_locked=false
	breath._lock_timer=0
	breath.lung_percent=100
	breath.exertion_percent=0
	breath.reset_input_latch()
	player.get_node("BreathFeedback").reset_feedback()
	player.get_node("FootstepNoise").footstep_timer=0
	player.get_node("FootstepAudio").reset_audio()
	player.velocity=Vector2.ZERO
	player.get_node("Appearance").show()
	if entity.sprite_rig.hide_player.is_connected(_hide_caught_player): entity.sprite_rig.hide_player.disconnect(_hide_caught_player)
	GameState.reset()
	flashlight.battery_percent=maxf(flashlight.battery_percent,float(checkpoint.get("battery",100)))
	batteries=maxi(batteries,int(checkpoint.get("batteries",0)))
	thrower.rocks=maxi(thrower.rocks,int(checkpoint.get("rocks",0)))
	if has_flashlight and flashlight.battery_percent>0: flashlight.is_on=true
	flashlight._refresh_light()
	thrower.available=true
	player.process_mode=Node.PROCESS_MODE_INHERIT
	resetting=false
	hud.shade.color=Color(0,0,0,0)
	# A parent catch restarts at the hallway entrance, close to the lesson, with gear kept.
	if bedroom: enter_zone("hallway",world.marker("hallway","SpawnFromBedroom"),false)
	else: enter_zone(checkpoint.get("zone","bedroom"),checkpoint.get("position",Vector2(340,440)),false)
	if bedroom: say("Hold SPACE before the doors. Breathe out in the light.",5)

func _frame_camera() -> void:
	if not is_instance_valid(player): return
	var camera := player.get_node("Camera2D") as Camera2D
	var region: Rect2 = World.REGIONS[zone]
	var viewport_size := get_viewport_rect().size
	var zoom := maxf(2.475,maxf(viewport_size.x/region.size.x,viewport_size.y/region.size.y))
	if zone in ["mansion_ground", "mansion_upper"]:
		zoom = 1.95
	camera.zoom = Vector2.ONE*zoom
	camera.limit_left = int(region.position.x)
	camera.limit_top = int(region.position.y)
	camera.limit_right = int(region.end.x)
	camera.limit_bottom = int(region.end.y)
	camera.force_update_scroll()

func _toggle_fullscreen() -> void:
	Preferences.set_fullscreen(not Preferences.fullscreen)

func _toggle_pause() -> void:
	_paused = not _paused
	PauseMenu.set_open(_paused)
	process_mode = Node.PROCESS_MODE_ALWAYS if _paused else Node.PROCESS_MODE_INHERIT
	for child in get_children():
		if _paused:
			_paused_modes[child] = child.process_mode
			if child.process_mode != Node.PROCESS_MODE_DISABLED: child.process_mode = Node.PROCESS_MODE_PAUSABLE
		else:
			child.process_mode = _paused_modes.get(child,Node.PROCESS_MODE_INHERIT)
	if not _paused: _paused_modes.clear()
	get_tree().paused = _paused
