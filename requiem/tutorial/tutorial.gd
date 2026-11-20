extends Node2D
## Tutorial orchestration. Existing player mechanics remain untouched.
signal stage_changed(stage: String)
signal tutorial_completed
const World := preload("res://tutorial/world.gd")
const Art := preload("res://tutorial/art.gd")
const HintBeacon := preload("res://tutorial/hint_beacon.gd")
const Chest := preload("res://tutorial/chest.gd")
const KEY_ART := preload("res://assets/art/items/item_key.png")
const NOTE_ART := preload("res://assets/art/items/item_note.png")
const MansionStory := preload("res://tutorial/mansion_story.gd")
const ATTACK_CANDLE_STEP := 0.6
const ATTACK_LAST_PAUSE := 1.0
## Total dark after the last flame, long enough to doubt the light is coming back.
const BLACKOUT_SECONDS := 1.5
## Her light stutters back by itself: seconds after the dark at which it flips, starting with on.
const RELIGHT_STUTTER: Array[float] = [0.0, 0.07, 0.22, 0.27, 0.5]
## Control returns this long after the dark ends, with the light already steady.
const RELIGHT_SECONDS := 0.75
const HEARD_PHASE := 20.0
const HEARD_PHASE_RETRY := 8.0
const HEARD_BEAM_WAIT := 3.0
## After the blackout the house is only sound, in three stages. Unease: the house itself, from
## rooms she is not in, for as long as she searches. Presence (the heard phase above): the thing
## in it, from the moment she lifts the key out of its trunk. Then, at last, something to see.
const UNEASE_SOUNDS: Array[Dictionary] = [
	{"clip": "res://assets/audio/horror-jam-kit 2/WAV/Foley/creak_02.wav", "caption": "[A floorboard creaks]", "volume": -6.0},
	{"clip": "res://assets/audio/horror-jam-kit 2/WAV/Foley/door_knock_01.wav", "caption": "[Knocking, somewhere in the house]", "volume": -5.0},
	{"clip": "res://tutorial/assets/audio/chair_scrape.wav", "caption": "[A chair drags]", "volume": -7.0},
	{"clip": "res://assets/audio/horror-jam-kit 2/WAV/Foley/metal_scrape_01.wav", "caption": "[Metal scrapes]", "volume": -10.0},
	{"clip": "res://tutorial/assets/audio/behind_wall.wav", "caption": "[Something moves behind the wall]", "volume": -8.0},
	{"clip": "res://assets/audio/horror-jam-kit 2/WAV/Impact/deep_impact_02.wav", "caption": "[A heavy knock under the floor]", "volume": -9.0},
	{"clip": "res://assets/audio/horror-jam-kit 2/WAV/Tonal/eerie_music_box_02.wav", "caption": "[A music box, far off]", "volume": -15.0},
]
const UNEASE_CREAK := 0
const UNEASE_KNOCK := 1
## Places a sound can come from, per room (house px). Never the room she stands in.
const UNEASE_SPOTS := {
	"Kitchen": [Vector2(240,300), Vector2(150,560), Vector2(330,200)],
	"Vestibule": [Vector2(608,200), Vector2(470,330), Vector2(700,600)],
	"AltarRoom": [Vector2(1008,250), Vector2(1100,560), Vector2(880,330)],
}
## Seconds before the first sound, then the gap between sounds: wide at first, tight after a minute.
const UNEASE_FIRST := 3.5
const UNEASE_GAP := Vector2(5.0, 9.0)
const UNEASE_GAP_LATE := Vector2(2.5, 5.0)
const UNEASE_RAMP := 60.0
## Every third sound is a board right behind her, out of the beam.
const UNEASE_BEHIND_EVERY := 3
const UNEASE_BEHIND_DISTANCE := 120.0
## A trunk lid or a rattled door gets an answer from another room after this long.
const UNEASE_REPLY := 1.1
## Where its own sounds come from once she has the key: in at the front door and up the vestibule
## toward the trunk, so it stands between her and the way out (house px, heard-phase seconds).
const PRESENCE_PATH: Array[Dictionary] = [
	{"at": 3.0, "spot": Vector2(544,650), "caption": "[Something drags itself in by the front door]"},
	{"at": 8.0, "spot": Vector2(608,560), "caption": "[Dragging, closer]"},
	{"at": 13.0, "spot": Vector2(608,470), "caption": "[Wet breathing]", "breathing": true},
	{"at": 17.0, "spot": Vector2(660,380), "caption": "", "carried": true},
]
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
## What Viv walks on in each zone. Her steps take their sounds from the set of that surface
## (assets/audio/viv/steps_wood/, steps_forest/); see player/footstep_audio.gd.
const ZONE_SURFACE := {
	"bedroom": &"wood",
	"hallway": &"wood",
	"forest": &"forest",
	"house": &"wood",
	"loop": &"wood",
	"mansion_ground": &"wood",
	"mansion_upper": &"wood",
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
	"mansion_ground": 3.5,
	"mansion_upper": 3.5,
}
## Sounds the player makes; the parents and the forest only react to these.
const PLAYER_SOUNDS := [NoiseManager.SourceType.FOOTSTEP, NoiseManager.SourceType.SPRINT,
	NoiseManager.SourceType.CROUCH, NoiseManager.SourceType.BREATH, NoiseManager.SourceType.THROW,
	NoiseManager.SourceType.DOOR]
## Seconds a warned parent keeps listening before settling again.
const PARENT_LISTEN_TIME := 3.5
const PARENT_FILL_MASK := 128
const PARENT_FILL_ENERGY := 1.0
## A parent door starts to stir when her next step falls short of it by less than this fraction of
## the step's reach (walking 3 u: 72 px; held 1 u: 24 px), so holding the breath visibly settles it.
const HALL_STIR_MARGIN := 0.75
## Doors that lead to another zone when the player walks through the open doorway.
const ZONE_DOORS := ["bedroom_exit", "hall_back", "hall_exit", "forest_back", "front_door", "loop_end"]
## The Hacienda: the first night after the tutorial, on two floors joined by the stairs.
const MANSION_ZONES := ["mansion_ground", "mansion_upper"]
## Where its patrol starts on each floor, how many patrol points the floor has, and how long it
## waits before it starts to move once she arrives (seconds).
const MANSION_ENTITY := {
	"mansion_ground": {"spawn": "EntitySpawn", "points": 8, "grace": 6.0},
	"mansion_upper": {"spawn": "Patrol1", "points": 6, "grace": 4.0},
}
## The name the house voice knows a floor of the Hacienda by (it has no rooms of its own).
const HACIENDA_VOICE := "hacienda"
## Beyond the end of the forest trail she simply walks on to the house: this far past the last
## petals (px, along the trail) the forest hands over without a key press.
const FOREST_EXIT_REACH := 40.0
## ...and only on the trail itself: this far to either side of it (px).
const FOREST_EXIT_WIDTH := 110.0
const FieldMap := preload("res://tutorial/field_map.gd")
## The ground outside the house's south wall, porch included (house coordinates).
const HOUSE_EXTERIOR: Array[Vector2] = [Vector2(0, 744), Vector2(1280, 744), Vector2(1280, 960), Vector2(0, 960)]
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
## The always-visible minimap and what it has seen (tutorial/field_map.gd).
var field_map: Node
## Counts down after she arrives on a Hacienda floor; at zero the entity there starts to move.
var mansion_grace := 0.0
var mansion_story := MansionStory.new()
## 1 the moment it starts to hunt, easing back to 0: the screen's jolt (Atmosphere film).
var hunt_intro_effect := 0.0
var zone := "bedroom"
var stage := "ki"
var has_flashlight: bool:
	get:
		return is_instance_valid(player) and player.get_node("ActionState").has_flashlight
	set(value):
		if is_instance_valid(player): player.get_node("ActionState").has_flashlight = value
var batteries := 0
var window_broken := false
## She has been pointed at the side window (the locked door, or a look at the glass): from here
## the glass twinkles and the throw key shows while she stands on the porch with a stone.
var window_hinted := false
var window_beacon: Sprite2D
## A cold glint on the porch side of the sidelight once the door has pointed at it: in a dark
## porch a star alone was missed, so the glass itself catches light until the latch is open.
var window_glint: PointLight2D
const WINDOW_GLINT_ENERGY := Vector2(0.5, 1.7)
var door_unlocked := false
## The front door locks itself in the blackout; the key from the vestibule trunk opens it again.
var has_key := false
var key_used := false
var unease_time := 0.0
var unease_next := UNEASE_FIRST
var unease_count := 0
var unease_last := -1
## The next sound is an answer to something she just did (-1: none): which sound it is.
var unease_reply := -1
## Where the last house sound came from (for the tests and the review harness).
var unease_last_at := Vector2.INF
## Where the key's candle hit the floor: the noise the thing comes to look at.
var key_noise_at := Vector2.INF
var friend_met := false
var attack_finished := false
var relight_step := 0
var complete := false
var collected: Dictionary = {}
var checkpoint: Dictionary = {}
var dialogue: Array[String] = []
var dialogue_done: Callable
var subtitle_time := 0.0
var caption_time := 0.0
var space_hint := false
var flash_hint_time := 0.0
var sprint_hint_time := 0.0
var has_sprinted := false
var _sprint_seen := 0.0
var _sprint_hint_offered := false
var has_thrown := false
var prayer_captioned := false
var breathing_captioned := false
var entity_was_screaming := false
var banner_time := 0.0
var encounter_grace := 0.0
var heard_length := 0.0
var heard_step := 0
var heard_at := Vector2.INF
var heard_phase_seen := false
var arrival_place := Vector2.INF
var arrival_target := Vector2.ZERO
var arrival_wait := 0.0
var _beam_image: Image
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
var stone_hint_seen := false
var ranger_checkpoint_ready := false
var dead_light_time := 0.0
## Eased 0..1 closeness of the hunting entity (drives the Atmosphere vignette).
var threat_pressure := 0.0
var friend_home := Vector2.ZERO
var _paused := false
var _paused_modes: Dictionary = {}
var _sounds: Dictionary = {}


func _enter_tree() -> void:
	GameState.reset()
	GameState.reset_progress()
	PixelDisplay.attach_world_layer($Atmosphere)

func _ready() -> void:
	var atmosphere_film := $Atmosphere/Film as Control
	atmosphere_film.set_anchors_preset(Control.PRESET_TOP_LEFT)
	atmosphere_film.position = Vector2.ZERO
	atmosphere_film.size = Vector2(PixelDisplay.WORLD_SIZE)
	if not test_mode: Kiosk.enter_fullscreen()
	# Beyond the walls is void: black, like the unlit rooms.
	RenderingServer.set_default_clear_color(Color.BLACK)
	thrower=player.get_node("Throw")
	breath=player.get_node("HoldBreath")
	player.get_node("Sprite2D").hide()
	breath._bar_layer.hide()
	thrower.rock_landed.connect(_on_rock_landed)
	thrower.object_released.connect(func(): has_thrown=true)
	entity.state_changed.connect(_on_entity_state_changed)
	MusicDirector.bind_gameplay(entity, breath)
	flashlight=player.get_node("flashlight")
	has_flashlight=false
	flashlight.battery_percent=0.0
	flashlight._update_bar()
	flashlight._bar_layer.hide()
	flashlight.set_process(false)
	flashlight.set_process_unhandled_input(false)
	hud.low_battery_at = flashlight.low_battery_threshold
	flashlight.toggled.connect(func(_on: bool) -> void: hud.pulse_slot("flashlight"))
	flashlight.toggle_rejected.connect(func() -> void:
		if batteries <= 0: hud.reject_slot("flashlight"))
	mansion_story.setup(self)
	GameState.prayer_started.connect(_on_mansion_prayer_started)
	GameState.prayer_ended.connect(_on_mansion_prayer_ended)
	GameState.altar_completed.connect(_on_altar_prayed)
	GameState.all_altars_completed.connect(_on_all_altars_prayed)
	for stairs_id: String in ["stairs_to_upper", "stairs_to_ground"]:
		if world.interactables.has(stairs_id):
			var stairs := world.interactables[stairs_id]["node"] as Area2D
			if stairs != null: stairs.body_entered.connect(_on_stairs_entered.bind(stairs_id))
	entity.caught.connect(_caught)
	world.zones["forest"].get_node("Ranger").caught.connect(_on_ranger_caught)
	world.zones["forest"].get_node("Ranger").spotted.connect(_on_ranger_spotted)
	hud.resume_requested.connect(_toggle_pause)
	hud.fullscreen_requested.connect(_toggle_fullscreen)
	PauseMenu.resume_pressed.connect(_toggle_pause)
	prayer_audio.stream=sound("prayer")
	prayer_audio.bus=AudioBus.WORLD
	prayer_audio.finished.connect(func():
		if zone=="house" and not attack_finished: prayer_audio.play())
	flashlight.click_clips.assign([load("res://assets/audio/629008__realgtro__flashlight-click.wav")])
	thrower.piedra_clips.assign([sound("rock")])
	if test_mode:
		player.get_node("FootstepNoise").walk_clips.clear()
		breath.hold_clips.clear()
		breath.exertion_clips.clear()
		thrower.piedra_clips.clear()
		flashlight.click_clips.clear()
	NoiseManager.noise_emitted.connect(_on_noise)
	HouseVoice.sounded.connect(_on_house_sounded)
	var window_mullion: Node2D = world.zones["house"].get_node("Lights/WindowSpill/Mullion")
	(world.interactables["window"]["node"] as WallWindow).broken_changed.connect(func(is_broken: bool): window_mullion.visible = not is_broken)
	window_beacon = HintBeacon.new()
	window_beacon.name = "HintBeacon"
	window_beacon.position = Vector2(0,-48)
	window_beacon.z_as_relative = false
	window_beacon.z_index = 48
	window_beacon.period = 1.6
	window_beacon.shining = false
	world.interactables["window"]["node"].add_child(window_beacon)
	window_glint = world.lamp(world.to_local(world.interactables["window"]["node"].global_position+Vector2(0,-36)),Color("9cc6ff"),0.8,0.0)
	window_glint.name = "WindowGlint"
	# It sits on the glass, inside the wall's own shadow caster: unshadowed, or the wall eats it.
	window_glint.shadow_enabled = false
	for room in world.rooms("house").get_rooms():
		room.player_entered.connect(func(_room): _sync_roof())
		room.player_exited.connect(func(_room): _sync_roof())
	for id in world.interactables:
		var chest: Node = world.interactables[id]["node"]
		if chest.get_script() == Chest: chest.opened.connect(_on_chest_opened.bind(id))
	for id in ZONE_DOORS:
		var door := world.interactables[id]["node"] as Door
		door.get_node("Doorway").body_entered.connect(_on_zone_doorway.bind(id))
		# Opening a door the player already stands in also counts as walking through.
		door.opened.connect(func(): _on_zone_doorway(player,id))
	friend_home=world.props["friend"].global_position
	prayer_audio.global_position=friend_home
	# A new game (a retry after death is not): the house may leave a door ajar once again.
	HouseVoice.begin_run()
	field_map = FieldMap.new()
	field_map.name = "FieldMap"
	add_child(field_map)
	enter_zone(start_zone)
	field_map.bind_game(self)
	if not test_mode:
		show_dialogue([
			"ELI: I'm at my aunt's old house. Follow the petals. Bring a light.",
			"ELI: And be quiet leaving. Your parents are still awake."
		])
		play_sound("phone",player.position)
		caption("[Phone buzzes]")

func _exit_tree() -> void:
	HouseVoice.leave()
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
	if not _sounds.has(id): _sounds[id]=load("res://tutorial/assets/audio/%s.wav"%id)
	return _sounds[id]

func play_sound(id: String, at: Vector2, volume := -8.0) -> AudioStreamPlayer2D:
	if test_mode: return null
	var audio:=AudioStreamPlayer2D.new()
	audio.position=at
	audio.bus=AudioBus.WORLD
	audio.stream=sound(id)
	audio.volume_db=volume
	add_child(audio)
	audio.add_to_group("tutorial_audio")
	audio.finished.connect(audio.queue_free)
	audio.play()
	return audio

## Moves the player into a zone. `arrival_door` (an interaction id) starts open behind the
## player and swings shut once they step away from it.
func enter_zone(next_zone: String, spawn := Vector2.INF, save := true, arrival_door := "") -> void:
	zone=next_zone
	ambient_reply_cooldown=0
	world.set_house_danger(attack_finished)
	var start_markers:={"bedroom":"SpawnStart","hallway":"SpawnFromBedroom","forest":"SpawnFromHome","house":"SpawnFromForest","loop":"SpawnFromHouse",
		"mansion_ground":"SpawnEntrance","mansion_upper":"SpawnFromStairs"}
	if spawn==Vector2.INF:
		spawn=world.marker(zone,start_markers[zone])
	player.position=spawn
	player.velocity=Vector2.ZERO
	player.get_node("FootstepNoise").reset_steps()
	player.get_node("FootstepAudio").surface = ZONE_SURFACE[zone]
	heard_flash.clear()
	var rooms: RoomVisibility = world.rooms(zone)
	if rooms != null:
		rooms.sync_to(player.position)
	_sync_roof()
	if arrival_door != "":
		_close_behind(world.interactables[arrival_door]["node"])
	player.get_node("PlayerMotion").reset_pose()
	player.get_node("PlayerAim").reset_pose()
	_frame_camera()
	var stage_for_zone:={"bedroom":"ki","hallway":"ki","forest":"sho","house":"ketsu" if attack_finished else "ten","loop":"ketsu",
		"mansion_ground":"ketsu","mansion_upper":"ketsu"}
	stage=stage_for_zone[zone]
	stage_changed.emit(stage)
	var zone_stream := load(ZONE_AMBIENCE_PATHS[zone]) as AudioStream
	AmbienceManager.set_track(zone_stream if not test_mode else null,
		ZONE_AMBIENCE_VOLUME_DB[zone], 2.0)
	prayer_audio.stop()
	if zone=="house" and not attack_finished and not test_mode:
		prayer_audio.play()
		if not prayer_captioned:
			prayer_captioned=true
			caption("[Low praying]")
	_configure_entity()
	_enter_house_voice()
	_sync_altar_door_glow()
	# The minimap changes sheet with her, at once (not on its next sample).
	if field_map != null and field_map.sheet != null:
		field_map.selected = zone
		field_map.record_position()
	hud.show_altars_tracker(zone in MANSION_ZONES)
	if zone in MANSION_ZONES:
		hud.set_altars_count(GameState.altars_completed, GameState.total_altars)
	world.zones["forest"].get_node("Ranger").active = zone == "forest"
	if zone == "forest":
		world.zones["forest"].get_node("Ranger").reset_patrol()
		ranger_checkpoint_ready = false
		world.zones["forest"].get_node("ThrowTarget").hide()
		if save and not _sprint_hint_offered:
			sprint_hint_time = 8.0
			_sprint_hint_offered = true
	if zone == "hallway":
		hall_door_cues.clear()
		hall_stirred.clear()
		hall_refuge_cued=false
		hall_audio_clock=0
	if save: save_checkpoint()

func _configure_entity() -> void:
	entity.revisit_chance = 0.35
	entity.hide()
	entity.active=false
	# Its unseen breathing belongs to the heard phase that switched it on: never to the next zone.
	entity.set_breathing(false)
	MusicDirector.clear_entity_threat()
	encounter_grace=0.0
	mansion_grace=0.0
	arrival_place=Vector2.INF
	world.props["friend"].visible = not attack_finished
	# The opening forest and impossible room suggest a presence through spatial sound.
	# No invisible active monster: the physical threat exists only after the altar attack.
	if zone == "house" and attack_finished and not complete:
		var points: Array[Vector2] = []
		for index in range(1,7):
			points.append(world.marker("house","Patrol%d" % index))
		entity.reset_encounter(world.marker("house","EntityArrive"),points)
		entity.get_node("CollisionShape2D").set_deferred("disabled",true)
		heard_step=0
		heard_at=Vector2.INF
		unease_time=0.0
		unease_next=UNEASE_FIRST
		unease_reply=-1
		# With the key already in her pocket (a retry) it is on its way at once.
		if has_key: _begin_presence()
	elif zone in MANSION_ZONES:
		# In the Hacienda it is there from the start: it stands where its patrol begins and
		# starts to walk it a few seconds after she arrives.
		var floor_plan: Dictionary = MANSION_ENTITY[zone]
		var mansion_points: Array[Vector2] = []
		for index in range(1, int(floor_plan["points"]) + 1):
			mansion_points.append(world.marker(zone, "Patrol%d" % index))
		entity.reset_encounter(world.marker(zone, String(floor_plan["spawn"])), mansion_points)
		entity.get_node("CollisionShape2D").set_deferred("disabled", false)
		entity.show()
		mansion_grace = float(floor_plan["grace"])

## Its own sounds start: the heard phase, which ends with it standing in the house.
func _begin_presence() -> void:
	encounter_grace=HEARD_PHASE_RETRY if heard_phase_seen else HEARD_PHASE
	heard_length=encounter_grace
	heard_phase_seen=true
	heard_step=0
	heard_at=Vector2.INF

## True while the house is only making its own noises: after the blackout, before the key.
func in_unease() -> bool:
	return zone=="house" and attack_finished and not has_key and not complete and not resetting

## True while the thing is heard and not yet seen (from the key until it stands in the house).
func in_presence() -> bool:
	return zone=="house" and (encounter_grace>0 or arrival_place!=Vector2.INF)

## One sound of the house, from a place. The house voice (audio/house_voice.gd) plays it: on
## World, with a soft start, and never a file the house may not use.
func _play_stream(stream: AudioStream, at: Vector2, volume: float) -> void:
	if test_mode or stream == null: return
	var audio := HouseVoice.play(stream,at,volume,randf_range(0.92,1.06),self)
	if audio != null: audio.add_to_group("tutorial_audio")

## The house voice speaks in the house and in the Hacienda: tell it where its rooms are. In the
## house, before the key and while the thing arrives, this script tells the story itself (the
## unease and the presence below) and the house voice keeps out of it; after that the house is
## its own. The Hacienda is its own from the first step: it has no rooms to name, so its sounds
## come from the places of the entity's patrol on this floor, never from right beside her
## (house_min_distance_u), and only while the entity is far and calm (the house voice's gates).
func _enter_house_voice() -> void:
	if zone in MANSION_ZONES:
		var places: Array[Vector2] = []
		for index in range(1, int(MANSION_ENTITY[zone]["points"]) + 1):
			places.append(world.marker(zone, "Patrol%d" % index))
		HouseVoice.enter({HACIENDA_VOICE: places}, func() -> String: return "", player)
		HouseVoice.story_holds = false
		return
	if zone!="house":
		HouseVoice.leave()
		return
	var house: Vector2=world.zones["house"].global_position
	var rooms := {}
	for room: String in UNEASE_SPOTS:
		rooms[room]=UNEASE_SPOTS[room].map(func(spot: Vector2) -> Vector2: return house+spot)
	# Its doors too: after one of its effects, one of them may be found ajar.
	var doors: Array[Door]=[]
	for node in world.zones["house"].get_node("Doors").get_children():
		if node is Door: doors.append(node)
	HouseVoice.enter(rooms,_room_name,player,doors)
	HouseVoice.story_holds=house_story()

## The room of the house she is in ("" when she is in none of them).
func _room_name() -> String:
	var rooms: RoomVisibility = world.rooms("house")
	return String(rooms.current.name) if rooms != null and rooms.current != null else ""

## True while this script is telling the house's part of the story itself.
func house_story() -> bool:
	return zone=="house" and (not attack_finished or in_unease() or in_presence() or resetting or complete)

func _on_house_sounded(family: StringName, _stream: AudioStream, _at: Vector2, _level: float, text: String) -> void:
	if family!=&"story" and text!="": caption(text)

## The house, heard and never seen. Sounds come from rooms she is not in, a little oftener as
## the search goes on; now and then a board gives right behind her, where the beam is not.
## Nothing here can hurt her: it only tells her she is not alone before anything proves it.
func _tick_unease(delta: float) -> void:
	unease_time+=delta
	if unease_time<unease_next: return
	var sound := unease_reply
	var behind := sound<0 and unease_count%UNEASE_BEHIND_EVERY==UNEASE_BEHIND_EVERY-1
	if sound<0:
		sound=UNEASE_CREAK if behind else randi()%UNEASE_SOUNDS.size()
		if sound==unease_last and not behind: sound=(sound+1)%UNEASE_SOUNDS.size()
	var at := _unease_spot(behind)
	unease_reply=-1
	unease_last=sound
	unease_last_at=at
	unease_count+=1
	var entry: Dictionary = UNEASE_SOUNDS[sound]
	_play_stream(load(entry["clip"]) as AudioStream,at,entry["volume"])
	caption("[A board creaks right behind you]" if behind else entry["caption"])
	var pace := clampf(unease_time/UNEASE_RAMP,0.0,1.0)
	var gap := UNEASE_GAP.lerp(UNEASE_GAP_LATE,pace)
	unease_next=unease_time+randf_range(gap.x,gap.y)

## A spot in a room she is not in; or, for the close one, just behind her back.
func _unease_spot(behind: bool) -> Vector2:
	var house: Vector2=world.zones["house"].global_position
	if behind:
		var facing := Vector2.from_angle(flashlight.global_rotation) if flashlight.enabled else Vector2.DOWN
		return player.global_position-facing*UNEASE_BEHIND_DISTANCE
	# A room she is not in, and not the place used last: the house voice knows the rooms.
	var away := HouseVoice.spot_away()
	return away if away!=Vector2.INF else house+UNEASE_SPOTS["Vestibule"][0]

## Something she did was loud enough to be answered: the next sound comes soon, and is a knock.
func _house_answers() -> void:
	if not in_unease():
		# Later, with the thing in the house, the house answers by itself, if it is safe to.
		HouseVoice.answer()
		return
	unease_reply=UNEASE_KNOCK
	unease_next=minf(unease_next,unease_time+UNEASE_REPLY)

func _process(delta: float) -> void:
	if _paused: return
	if zone == "forest":
		world.interactables["ranger"]["position"] = world.zones["forest"].get_node("Ranger").global_position
	ambient_reply_cooldown=maxf(0,ambient_reply_cooldown-delta)
	if subtitle_time>0:
		subtitle_time-=delta
		if subtitle_time<=0 and dialogue.is_empty(): hud.subtitle.text=""
	if caption_time>0:
		caption_time-=delta
		if caption_time<=0: hud.caption.text=""
	var screaming: bool = entity.is_screaming()
	if screaming and not entity_was_screaming: caption("[A deep scream]")
	entity_was_screaming = screaming

	hud.breath.value=breath.lung_percent
	hud.effort.value=breath.exertion_percent
	hud.update_breath_feedback(player.get_node("BreathFeedback"))
	hud.battery.value=flashlight.battery_percent
	hud.update_inventory(has_flashlight,batteries,thrower.rocks)
	hud.set_key(has_key and not key_used)
	hud.update_equipment_state(flashlight.is_on, flashlight.battery_percent, batteries, thrower.rocks, thrower.get_cooldown_fraction())
	hunt_intro_effect = move_toward(hunt_intro_effect, 0.0, delta * 1.5)
	if not dialogue.is_empty(): hud.place_prompt(Vector2.ZERO,true)
	HouseVoice.story_holds=house_story()
	if not dialogue.is_empty() or resetting: return
	if zone == "forest":
		_tick_ranger_checkpoint()
		if not dialogue.is_empty(): return
	if sequence!="": _tick_sequence(delta)
	if encounter_grace>0: _tick_heard_phase(delta)
	elif in_unease(): _tick_unease(delta)
	if arrival_place!=Vector2.INF: _tick_arrival(delta)
	if mansion_grace > 0.0:
		mansion_grace -= delta
		if mansion_grace <= 0.0 and zone in MANSION_ZONES and not complete and entity.visible:
			entity.active = true
	if zone=="hallway": _tick_hallway(delta)
	if zone == "forest" and _past_forest_exit():
		_leave_forest()
		return
	if zone=="forest" and not forest_cued and player.position.x>3500:
		forest_cued=true
		caption("[Branch snaps]")
		play_sound("branch",Vector2(3630,215),-4)
	if zone=="loop" and not loop_cued and player.position.x>7460:
		loop_cued=true
		play_sound("behind_wall",_wall_listeners()[0]+Vector2(0,-60),-5)
		caption("[Dragging behind the wall]")
	if zone=="loop" and breath.is_holding: loop_hold_seen=true
	if zone=="house" and door_unlocked and not attack_finished and player.position.y<660 and checkpoint.get("position",Vector2.ZERO).y>704:
		save_checkpoint()
	if zone=="house": _shut_front_door_behind()
	window_beacon.shining = zone=="house" and window_hinted and not door_unlocked
	var glint_pulse: float = 0.5+0.5*sin(Time.get_ticks_msec()*0.0035)
	window_glint.energy = move_toward(window_glint.energy,
		lerpf(WINDOW_GLINT_ENERGY.x,WINDOW_GLINT_ENERGY.y,glint_pulse) if window_beacon.shining else 0.0,delta*4.0)
	window_glint.visible = window_glint.energy>0.0
	_update_threat_presentation()
	_tick_battery(delta)
	_find_interaction()
	_update_key_hint(delta)

func _update_key_hint(delta: float) -> void:
	flash_hint_time=maxf(0.0,flash_hint_time-delta)
	if dialogue.is_empty(): sprint_hint_time=maxf(0.0,sprint_hint_time-delta)
	if player.is_sprinting:
		_sprint_seen += delta
		if _sprint_seen >= 0.3: has_sprinted = true
	if breath.is_holding: space_hint=false
	var text := ""
	if space_hint and zone=="hallway": text="SPACE · Hold breath"
	elif has_flashlight and batteries>0 and flashlight.battery_percent<=flashlight.low_battery_threshold: text="B · Battery"
	elif _window_throw_ready(): text="Q · Throw at the window"
	elif thrower.rocks>0 and not has_thrown: text="Q · Throw"
	elif zone=="forest" and not has_sprinted and sprint_hint_time>0: text="SHIFT · Sprint"
	elif flash_hint_time>0: text="F · Light"
	hud.show_key_hint(text, PixelDisplay.world_to_ui(player.global_position))

## On the porch, pointed at the window, a stone in hand, the glass still whole.
func _window_throw_ready() -> bool:
	return zone=="house" and window_hinted and not window_broken and thrower.rocks>0 \
		and player.position.y>world.interactables["window"]["node"].global_position.y

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
				caption("[Chair scrapes behind the door]")
				space_hint=true
			else:
				caption("[Chair scrapes behind the door]" if index==0 else "[Movement behind the door]")
			play_sound("chair_scrape",door.global_position+Vector2(0,-40),-3)
			hall_audio_clock=4.0
	if hall_audio_clock<=0 and nearest_door != null:
		play_sound("parent_rustle",nearest_door.global_position+Vector2(0,-40),-7)
		caption("[Rustling behind the door]")
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
			caption("[Rustling behind the door]")
			hall_audio_clock=maxf(hall_audio_clock,4.0)
		elif door.danger < 0.2:
			hall_stirred.erase(index)
	if not hall_lesson_done and not listeners.is_empty() and player.position.x > listeners.back().global_position.x+90:
		hall_lesson_done=true
	if hall_hold_alert and breath.is_holding:
		hall_hold_alert=false
		hud.dismiss_alert()
	# Only explain the refuge when it matters: arriving out of breath or still holding it.
	if in_light and not hall_refuge_cued and (breath.is_holding or breath.lung_percent < 80.0):
		hall_refuge_cued=true
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

func _nearest_wall_listener(point: Vector2) -> ParentListener:
	var nearest_listener: ParentListener = null
	for node in world.nodes_in("loop","Listeners"):
		if node is ParentListener and (nearest_listener == null \
				or node.global_position.distance_to(point) < nearest_listener.global_position.distance_to(point)):
			nearest_listener = node
	return nearest_listener

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
		request_reset("")
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
	hud.prompt.text="E"
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

func caption(text: String, seconds := 3.0) -> void:
	if not Preferences.captions:
		return
	hud.caption.text = text
	caption_time = seconds

func _find_interaction() -> void:
	nearest=""
	var distance:=85.0
	for id in world.interactables:
		if not interaction_available(id): continue
		var d := _interaction_distance(id)
		if d<distance:
			distance=d
			nearest=id
	for id in world.interactables:
		var prop_node: Node2D=world.interactables[id]["node"]
		if prop_node.has_method("set_focused"):
			prop_node.set_focused(id==nearest)
	hud.prompt.text="" if nearest=="" else (interaction_label(nearest) if _prompt_without_key(nearest) else "E · "+interaction_label(nearest))
	if nearest!="":
		var target: Node2D = world.interactables[nearest]["node"]
		# Anything she takes carries its prompt right above it; the key hint keeps the space under her.
		var drawn_pickup: bool = target.has_method("is_pickup") and target.is_pickup()
		var chest_loot := mansion_story.chest_displays.get(nearest) as Sprite2D
		var pickup: bool = drawn_pickup or interaction_label(nearest).begins_with("Take")
		var anchor: Vector2 = target.get_prompt_anchor() if drawn_pickup else world.interactables[nearest]["position"]
		if chest_loot != null and chest_loot.visible:
			anchor = chest_loot.global_position
		hud.place_prompt(PixelDisplay.world_to_ui(anchor),false,pickup)

func _prompt_without_key(id: String) -> bool:
	var node: Node = world.interactables[id]["node"]
	return id=="loop_back" or (mansion_story.label(id).is_empty() and node is Door and node.locked and not (id=="front_door" and door_unlocked))

func _interaction_distance(id: String) -> float:
	var entry: Dictionary = world.interactables[id]
	var distance := player.global_position.distance_to(entry["position"])
	# The prompt is drawn above the leaf. Use the doorway too so both sides can reach the lock.
	if id == "front_door" or not mansion_story.key_for_door(id).is_empty():
		var door: Door = entry["node"]
		distance = minf(distance, player.global_position.distance_to(door.global_position))
	return distance

func interaction_available(id: String) -> bool:
	if collected.has(id): return false
	if id.begins_with("altar_") and world.interactables[id]["node"].get(&"is_completed") == true: return false
	if id=="flashlight" and has_flashlight: return false
	if id=="friend": return zone=="house" and not friend_met
	if id=="altar_pray": return false # The friend demonstrates prayer in this introduction.
	if id=="window" and door_unlocked: return false
	return true

func interaction_label(id: String) -> String:
	var story_label := mansion_story.label(id)
	if not story_label.is_empty(): return story_label
	if id == "stairs_to_upper" and not mansion_story.completed("altar_4"):
		return "Check the stair gate"
	if id=="window" and window_broken: return "Reach in for the latch"
	if id=="front_door" and attack_finished and not key_used: return "Unlock front door" if has_key else "Try the door"
	if id=="front_door" and door_unlocked: return "Open"
	var node: Node = world.interactables[id]["node"]
	if node is Door and node.is_open and id in ZONE_DOORS and _zone_door_active(id): return "Go"
	if node is Door and (node.is_open or node.locked): return node.interaction_label()
	return world.interactables[id]["label"]

func interact(id: String) -> void:
	if not interaction_available(id): return
	# Distance validation is shared by normal input and tests; no remote interactions.
	if _interaction_distance(id) > 85.0: return
	var target: Node = world.interactables[id]["node"]
	if zone in MANSION_ZONES and mansion_story.interact(id): return
	_player_visual("play_pickup")
	if target.get_script() == Chest:
		_open_chest(id,target)
		return
	if zone in MANSION_ZONES and _interact_mansion(id, target): return
	match id:
		"abuela_note":
			show_dialogue(["My dear, I left the flashlight beside this note. Remember to turn it off when you do not need it. — Abuela"] )
		"phone":
			world.interactables["phone"]["node"].screen_lit = false
			show_dialogue(["ELI: I'm at my aunt's old house. Follow the petals. Bring a light.",
				"ELI: And be quiet leaving. Your parents are still awake."])
		"flashlight":
			has_flashlight=true
			collect(id)
			flashlight.set_process(true)
			flashlight.set_process_unhandled_input(true)
			if batteries>0: insert_battery()
			flash_hint_time=3.0
		"battery","forest_battery","porch_battery","house_battery":
			batteries+=1
			collect(id)
			if has_flashlight and flashlight.battery_percent<=0: insert_battery()
		"bedroom_exit":
			var exit_door: Door = world.interactables[id]["node"]
			if exit_door.is_open:
				_go_through(id)
				return
			# Gate on what was collected, not on the charge left: an empty battery must never
			# lock the player in the bedroom (bug: dead battery prevents leaving).
			if not has_flashlight:
				say("Not without a light.")
				return
			if not collected.has("battery"):
				say("It needs a battery.")
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
		"early_rocks","forest_rocks","porch_rocks":
			if thrower.rocks<3:
				thrower.rocks=mini(3,thrower.rocks+3)
				play_sound("pickup",player.position)
				_animate_rocks(world.interactables[id]["node"].global_position)
			stone_hint_seen = true
		"forest_exit": _leave_forest()
		"ranger":
			say("RANGER: This trail is closed tonight. Head back home.", 5.0)
		"house_back":
			if attack_finished: say("The path is gone.")
			else: enter_zone("forest",world.marker("forest","SpawnFromHouse"))
		"window":
			if window_broken:
				# Reaching through the broken glass releases the latch; the door stays a real door.
				door_unlocked=true
				var front_door: Door = world.interactables["front_door"]["node"]
				front_door.locked=false
				front_door.open()
				(world.interactables["window"]["node"] as WallWindow).unlatched=true
				caption("[Latch clicks]")
			else:
				window_hinted=true
				if thrower.rocks>0: say("The latch is right behind the glass. A stone would break it.",6)
				else: say("The latch is right behind the glass. I need something to throw.",6)
		"front_door":
			var front_door: Door = world.interactables[id]["node"]
			if not door_unlocked:
				# The door itself points at the way in: players read "locked" as a dead end.
				window_hinted=true
				if window_broken: say("Locked. I can reach the latch through the broken window.",6)
				else: say("Locked. The latch is on the inside, by that window.",6)
				play_sound("door",player.position)
				caption("[Door rattles]")
			elif attack_finished and not has_key:
				say("It won't open. It has locked itself... there must be a key in this house.",6)
				play_sound("door",player.position)
				caption("[Door rattles]")
				_house_answers()
			elif attack_finished and in_presence():
				# It is coming in through this door: she has to let it pass before she can use it.
				say("This is the right key. Hide until it passes, then unlock the front door.",6)
			elif attack_finished and not key_used:
				key_used=true
				front_door.locked=false
				play_sound("switch",player.position)
				caption("[Key turns]")
				front_door.open(breath.is_holding)
			elif attack_finished and front_door.is_open:
				_go_through(id)
			else:
				_use_door(front_door)
		"kitchen_door","altar_door":
			_use_door(world.interactables[id]["node"])
		"friend":
			friend_met=true
			world.props["friend"].face_and_stand(player.global_position)
			prayer_audio.stop()
			show_dialogue([
				"ELI: My aunt said we have to pray at the altars. It keeps something here.",
				"ELI: Wait. Do you hear that?"
			],_begin_attack)
		"loop_back": pass
		"loop_end":
			# The last door of the impossible hallway: beyond it is the Hacienda.
			var last_door: Door = world.interactables[id]["node"]
			if last_door.is_open: _go_through(id)
			else: _use_door(last_door)

## Trunks: a lid, a creak that can be heard, and something inside (or nothing).
func _open_chest(id: String, chest: Node2D) -> void:
	if id=="chest_vestibule" and not attack_finished:
		say("Not while the candle is burning on it.",5)
		return
	collected[id]=true
	chest.open(breath.is_holding)

func _on_chest_opened(loot: String, id: String) -> void:
	if MansionStory.CHESTS.has(id): return
	var chest: Node2D = world.interactables[id]["node"]
	var from: Vector2 = chest.get_loot_origin()
	match loot:
		"battery":
			batteries+=1
			_pop_loot(from,Art.ITEMS["battery"],"battery")
			if has_flashlight and flashlight.battery_percent<=0: insert_battery()
		"stones":
			thrower.rocks=mini(3,thrower.rocks+3)
			stone_hint_seen=true
			play_sound("pickup",player.position)
			_animate_rocks(from)
		"note":
			_pop_loot(from,NOTE_ART,"")
			show_dialogue([chest.note_text])
		"key":
			has_key=true
			_pop_loot(from,KEY_ART,"key")
			say("The key to the front door. Get out once the way is clear.",7)
			_key_candle_falls()
		_:
			say("Empty.",3)
			caption("[Hollow wood]")
	_house_answers()

## What a trunk gives rises out of it, hangs for a beat so it can be read in the dark (it is
## drawn unlit, like the pickup stars), then goes to her hands and its inventory slot pops.
func _pop_loot(from: Vector2, texture: Texture2D, slot: String) -> void:
	play_sound("pickup",player.position)
	var item := Sprite2D.new()
	item.texture = texture
	item.scale = Vector2.ONE * Units.ART_SCALE
	item.z_index = 44
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	item.material = unlit
	world.add_child(item)
	item.global_position = from
	var tween := item.create_tween()
	tween.tween_property(item,"global_position",from+Vector2(0,-16),0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.4)
	tween.tween_property(item,"global_position",player.global_position+Vector2(0,-12),0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(item,"scale",Vector2.ONE*Units.ART_SCALE*0.4,0.22)
	tween.tween_callback(item.queue_free)
	if slot != "": tween.tween_callback(hud.pulse_slot.bind(slot))

## The key trunk sits under the vestibule candle. Lifting the lid tips the dead jar onto the
## boards: the loudest thing she does in this house, and what the thing in it comes to look at.
func _key_candle_falls() -> void:
	var candle: Node2D = world.props["vestibule_candle"]
	var rest := candle.global_position
	key_noise_at = rest+Vector2(22,16)
	var tween := candle.create_tween()
	tween.tween_property(candle,"global_position",rest.lerp(key_noise_at,0.5)+Vector2(0,-8),0.12)
	tween.tween_property(candle,"global_position",key_noise_at,0.14).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(candle,"rotation",PI*0.5,0.26)
	tween.tween_callback(func():
		play_sound("thud",key_noise_at,-6)
		caption("[The candle jar hits the floor]")
		NoiseManager.emit_noise(key_noise_at,256,NoiseManager.SourceType.ENVIRONMENT))
	save_checkpoint()
	_begin_presence()

func collect(id: String) -> void:
	collected[id]=true
	_player_visual("play_pickup")
	var item: Node2D = world.interactables[id]["node"]
	play_sound("pickup",player.position)
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
		var pebble := Sprite2D.new()
		pebble.texture = load("res://assets/art/items/item_pebble_%s.png" % ["a","b","c"][index])
		pebble.scale = Vector2.ONE * Units.ART_SCALE
		pebble.z_index = 44
		world.add_child(pebble)
		var start := pile+Vector2(randf_range(-10,10),randf_range(-6,4))
		pebble.global_position = start
		var tween := pebble.create_tween()
		tween.tween_interval(index*0.08)
		tween.tween_property(pebble,"global_position",start.lerp(hands,0.5)+Vector2(0,-22),0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(pebble,"global_position",hands,0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(pebble.queue_free)
	hud.pulse_slot("rocks")

func insert_battery() -> void:
	if not has_flashlight:
		return
	if batteries<=0:
		play_sound("switch",player.position)
		hud.pulse_slot("battery")
		return
	if flashlight.battery_percent>85:
		return
	batteries-=1
	flashlight.battery_percent=100
	flashlight.is_on=true
	flashlight._refresh_light()
	play_sound("battery_insert",player.position,SoundSettings.current().battery_insert_db)
	hud.pulse_slot("battery")
	low_battery_hinted=false

## Bug fix (battery changing was not intuitive): a hint appears only when the light fades and a
## spare exists, and a dead light is swapped automatically after a beat if the player has a spare.
func _tick_battery(delta: float) -> void:
	if not has_flashlight or resetting or not dialogue.is_empty(): return
	var charge: float = flashlight.battery_percent
	if charge>0.0 and charge<=flashlight.low_battery_threshold and batteries>0 and not low_battery_hinted:
		low_battery_hinted=true
	if charge<=0.0 and batteries>0:
		dead_light_time+=delta
		if dead_light_time>=1.2:
			insert_battery()
			caption("[Battery clicks in]")
	else:
		dead_light_time=0.0

func _on_rock_landed(at: Vector2) -> void:
	if zone!="house" or window_broken: return
	var side_light: WallWindow = world.interactables["window"]["node"]
	var miss := at.distance_to(side_light.global_position+Vector2(0,-48))
	if miss>59:
		# A stone that lands near the glass says so: the idea was right, the aim was off.
		if window_hinted and miss<170: say("Missed the glass.",3)
		return
	window_broken=true
	window_hinted=true
	say("That did it. Now I can reach the latch.",6)
	side_light.broken=true
	play_sound("glass",at,-3)
	NoiseManager.emit_noise(at,256,NoiseManager.SourceType.ENVIRONMENT)
	play_sound("presence", side_light.global_position)
	caption("[Glass shatters]")
	get_tree().create_timer(1.5,false).timeout.connect(func(): caption("[Something moves inside]"))

## The screen closes in as the hunting entity comes near. Only while it hunts: then its breathing
## is already loud, so the vignette never gives away a silent patrol behind a wall.
func _update_threat_presentation() -> void:
	var hunting_house: bool = (zone=="house" or zone in MANSION_ZONES) and entity.active and entity.visible \
		and entity.get_state_name()=="HUNT"
	var pressure := 0.0
	if hunting_house:
		var distance := entity.global_position.distance_to(player.global_position)
		pressure = 1.0-smoothstep(2.0*Units.PX_PER_UNIT,10.0*Units.PX_PER_UNIT,distance)
	threat_pressure = lerpf(threat_pressure,pressure,0.08)
	(film.material as ShaderMaterial).set_shader_parameter("pressure",threat_pressure)
	(film.material as ShaderMaterial).set_shader_parameter("hunt_intro",hunt_intro_effect)

## The moment it starts to hunt the screen jolts once (Atmosphere film, hunt_intro).
func _on_entity_state_changed(_previous: int, current: int) -> void:
	if entity.get_state_name() == "HUNT":
		hunt_intro_effect = 1.0

## Shown on the capture screen: the sound that gave the player away.
func game_over_cause() -> String:
	if entity.last_heard_source < 0: return "It found you in the dark."
	return "It heard you."

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
	world.props["friend"].kneel()
	if not test_mode: prayer_audio.play()
	var front_door: Door = world.interactables["front_door"]["node"]
	var scrape := play_sound("presence",front_door.global_position)
	if scrape != null:
		scrape.finished.disconnect(scrape.queue_free)
		scrape.finished.connect(scrape.play)
		var tween := scrape.create_tween()
		var previous := 0.0
		for index in World.ATTACK_CANDLES.size():
			tween.tween_property(scrape,"position",world.props[World.ATTACK_CANDLES[index]].global_position,_attack_candle_time(index)-previous)
			previous=_attack_candle_time(index)
		tween.tween_callback(scrape.queue_free)
	caption("[Something drags across the floor]")

func _sync_roof() -> void:
	var current: Room = world.rooms("house").current
	var roof_on := current == null or current.name == "Porch"
	for id in ["ArtRoof", "ArtRoofEaves", "ArtRoofEaveCorners"]:
		world.zones["house"].get_node(id).visible = roof_on
	# Once she is inside, the outside is gone: the porch and the ground around the house fall
	# dark, the way a room's cover hides a room she cannot see into.
	_exterior_cover().visible = not roof_on

## One black sheet over everything outside the house's walls (house coordinates), drawn like
## the rooms' covers. Built once, shown only while she stands in one of the house's rooms.
func _exterior_cover() -> Polygon2D:
	var house: Node2D = world.zones["house"]
	var cover := house.get_node_or_null("ExteriorCover") as Polygon2D
	if cover == null:
		cover = Polygon2D.new()
		cover.name = "ExteriorCover"
		cover.polygon = PackedVector2Array(HOUSE_EXTERIOR)
		cover.color = Color.BLACK
		cover.light_mask = 0
		cover.z_index = 40
		cover.visible = false
		house.add_child(cover)
	return cover

## The altar doorway's own lights stay dark for the quiet beat after the last
## flame; the doorway itself still answers the flashlight and other real light.
func _sync_altar_door_glow() -> void:
	var altar_door: Door = world.interactables["altar_door"]["node"]
	altar_door.decorative_glow_off = zone=="house" and attack_finished and encounter_grace>0.0

func _attack_candle_time(index: int) -> float:
	var last: int=World.ATTACK_CANDLES.size()-1
	return 0.9+ATTACK_CANDLE_STEP*mini(index,last-1)+(ATTACK_LAST_PAUSE if index==last else 0.0)

func _tick_heard_phase(delta: float) -> void:
	encounter_grace-=delta
	var elapsed: float=heard_length-encounter_grace
	var beat: float=heard_length/HEARD_PHASE
	var house: Vector2=world.zones["house"].global_position
	while heard_step<PRESENCE_PATH.size() and elapsed>=float(PRESENCE_PATH[heard_step]["at"])*beat:
		var step: Dictionary=PRESENCE_PATH[heard_step]
		heard_step+=1
		heard_at=house+step["spot"]
		if step.get("breathing",false):
			entity.global_position=heard_at
			entity.set_breathing(true)
			if not breathing_captioned:
				breathing_captioned=true
				caption(step["caption"])
		else:
			# Once it breathes, the breathing is what moves; before that each step is a drag.
			entity.global_position=heard_at
			if not step.get("carried",false): play_sound("presence",heard_at)
			if step["caption"]!="": caption(step["caption"])
	if encounter_grace<=0 and not complete:
		# It stands up where it was last heard and goes to look at what fell.
		var from: Vector2=heard_at if heard_at!=Vector2.INF else world.marker("house","EntityArrive")
		_arrive(from,key_noise_at if key_noise_at!=Vector2.INF else friend_home)

func _arrive(place: Vector2, target: Vector2) -> void:
	arrival_place=NavigationServer2D.map_get_closest_point(world.landmarks["HouseNavigation"].get_navigation_map(),place)
	arrival_target=target
	arrival_wait=HEARD_BEAM_WAIT

func _tick_arrival(delta: float) -> void:
	arrival_wait-=delta
	if arrival_wait>0 and _in_beam(arrival_place): return
	entity.global_position=arrival_place
	entity.get_node("CollisionShape2D").set_deferred("disabled",false)
	entity.show()
	entity.active=true
	entity.notice(arrival_target)
	arrival_place=Vector2.INF
	world.interactables["altar_door"]["node"].decorative_glow_off = false

func _in_beam(at: Vector2) -> bool:
	if not flashlight.enabled or flashlight.texture == null: return false
	if _beam_image == null: _beam_image=flashlight.texture.get_image()
	var local: Vector2=flashlight.global_transform.affine_inverse()*at
	var pixel: Vector2=(local-flashlight.offset)/flashlight.texture_scale+Vector2(_beam_image.get_size())*0.5
	if not Rect2(Vector2.ZERO,Vector2(_beam_image.get_size())).has_point(pixel): return false
	var texel: Color=_beam_image.get_pixelv(Vector2i(pixel))
	return texel.a*texel.v>0.05

func _tick_sequence(delta: float) -> void:
	sequence_time+=delta
	if sequence=="ending":
		if sequence_time>=4.0 and sequence_step==0:
			sequence_step=1
			hud.shade.color=Color.BLACK
			hud.subtitle.text=""
			hud.prompt.text=""
			player.process_mode=Node.PROCESS_MODE_DISABLED
			play_sound("behind_wall",player.position)
		if sequence_time>=6.0 and sequence_step==1:
			sequence_step=2
			hud.end_title.show()
		if sequence_time>=9.0 and sequence_step==2:
			sequence_step=3
			Kiosk.go_to_title.call_deferred()
		return
	if sequence!="attack": return
	var last_candle: int=World.ATTACK_CANDLES.size()-1
	var last_candle_time: float=_attack_candle_time(last_candle)
	if sequence_step<last_candle and sequence_time>=_attack_candle_time(sequence_step):
		world.set_candle_out(World.ATTACK_CANDLES[sequence_step],true)
		sequence_step+=1
		if sequence_step==last_candle:
			prayer_audio.stop()
			var friend_rig: CharacterSprite = world.props["friend"].rig
			friend_rig.set_rate(&"upper",0.0)
			friend_rig.set_rate(&"lower",0.0)
	if sequence_step==last_candle and sequence_time>=last_candle_time:
		sequence_step+=1
		world.set_candle_out(World.ATTACK_CANDLES[last_candle],true)
		world.interactables["altar_door"]["node"].decorative_glow_off = true
		# Every light dies with the last flame, hers included: Eli goes in the dark,
		# never out of a lit beam.
		_set_carried_light(false)
		relight_step=0
		world.props["friend"].hide()
		world.props["friend"].fallen=true
		play_sound("thud",friend_home,-2)
		NoiseManager.emit_noise(friend_home,256,NoiseManager.SourceType.ENVIRONMENT)
		caption("[A gasp. Something heavy falls.]")
	if sequence_step==last_candle+1:
		_tick_relight(sequence_time-last_candle_time-BLACKOUT_SECONDS)
	if sequence_step==last_candle+1 and sequence_time>=last_candle_time+BLACKOUT_SECONDS+RELIGHT_SECONDS:
		sequence_step+=1
		_set_carried_light(true)
		world.props["friend"].fallen=true
		prayer_audio.stop()
		attack_finished=true
		# The way out shuts with the lights: from here the house has to be searched.
		var way_out: Door = world.interactables["front_door"]["node"]
		way_out.snap(false)
		way_out.locked=true
		stage="ketsu"
		stage_changed.emit(stage)
		player.process_mode=Node.PROCESS_MODE_INHERIT
		thrower.available=true
		_configure_entity()
		save_checkpoint()
		say("Eli…?",6)
		sequence=""

## The flashlight and the step ring together: everything she carries that makes light.
## Coming back, the flashlight relights itself if it has charge; the ring always returns.
func _set_carried_light(lit: bool) -> void:
	player.get_node("LocalLight").enabled=lit
	if lit: flashlight.relight()
	else: flashlight.snuff()

func _tick_relight(since_dark: float) -> void:
	var flips := 0
	for at in RELIGHT_STUTTER:
		if since_dark>=at: flips+=1
	if flips==relight_step: return
	relight_step=flips
	_set_carried_light(flips%2==1)

func _on_noise(at: Vector2, radius: float, source: int, _duration: float) -> void:
	if encounter_grace>0 and zone=="house" and not resetting and source in PLAYER_SOUNDS:
		var front_door: Door = world.interactables["front_door"]["node"]
		var reach: Vector2=heard_at if heard_at!=Vector2.INF else front_door.global_position
		if at.distance_to(reach)<=radius:
			encounter_grace=0.0
			_arrive(reach,at)
	# The unseen passages answer audible player actions, without an invisible capture body.
	# This preserves a readable relationship between breath, footfalls and environmental response.
	if zone in ["forest","loop"] and not resetting and ambient_reply_cooldown<=0:
		if source in [NoiseManager.SourceType.FOOTSTEP,NoiseManager.SourceType.SPRINT,NoiseManager.SourceType.BREATH,NoiseManager.SourceType.THROW]:
			var listeners: Array = [world.marker("forest","ListenerA"),world.marker("forest","ListenerB")] if zone=="forest" else _wall_listeners()
			for listener in listeners:
				if at.distance_to(listener)<=radius:
					play_sound("branch" if zone=="forest" else "behind_wall",listener,-4)
					caption("[Branches shift]" if zone=="forest" else "[The dragging stops]")
					if zone=="loop": _nearest_wall_listener(listener).listen()
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
	listener.listen()
	if not hall_warned:
		hall_warned=true
		hall_listen_time=PARENT_LISTEN_TIME
		play_sound("parent_rustle",listener.global_position+Vector2(0,-40),-2)
		say("DAD: ...Hm? Someone up?",PARENT_LISTEN_TIME+2.5)
		# Held steps right by the door are the one sound Space cannot fix: ask for distance instead.
		hall_hold_alert = source != NoiseManager.SourceType.CROUCH
		space_hint=true
		# She freezes for a beat so the warning and the prompt land before another step can count.
		# Only movement stops: breath input stays live, so Space pressed now works at once.
		player.velocity=Vector2.ZERO
		player.get_node("FootstepNoise").reset_steps()
		player.set_physics_process(false)
		get_tree().create_timer(1.1).timeout.connect(func(): player.set_physics_process(true))
		return
	parent_failures+=1
	_parent_doorway_notice(listener)
	request_reset("DAD: Back to bed. Now.",true)

## On the second hear the parent leans out of the doorway toward her; the leaf swings open for the
## picture only (no blocker change) and everything is undone on the next reset.
func _parent_doorway_notice(listener: ParentListener) -> void:
	var doors: Node = world.zones["hallway"].get_node("Doors")
	var closest_door: Door = null
	for node in doors.get_children():
		if node is Door and node.name.begins_with("ParentDoor") \
				and (closest_door == null or node.global_position.distance_to(listener.global_position) < closest_door.global_position.distance_to(listener.global_position)):
			closest_door = node
	if closest_door == null: return
	var notice := CharacterSprite.new()
	notice.head_enabled = false
	notice.hide_head()
	notice.z_index = 1
	world.zones["hallway"].add_child(notice)
	var cut_x := 88.0
	notice.global_position = closest_door.global_position + Vector2(32.0 - (cut_x - 80.0) * Units.ART_SCALE, -48.0)
	notice.play(&"upper", "parent_doorway_notice", {"loop": false, "hold_last": true, "rate": 1.0})
	create_tween().tween_property(closest_door, "swing", 1.0, minf(closest_door.swing_time, 0.3))
	var blockers: Array[CanvasItem] = []
	for path in ["Occluder", "OccluderLeaf"]:
		var blocker := closest_door.get_node_or_null(path) as CanvasItem
		if blocker != null: blockers.append(blocker)
	var tab := world.zones["hallway"].get_node_or_null("Rooms/ParentRoom%s/DoorTab" % String(closest_door.name).trim_prefix("ParentDoor")) as CanvasItem
	if tab != null: blockers.append(tab)
	for path in ["LeftFoot", "RightFoot"]:
		var foot := listener.get_node_or_null(path) as CanvasItem
		if foot != null: blockers.append(foot)
	if listener.glow != null: blockers.append(listener.glow)
	for blocker in blockers: blocker.visible = false
	for layer in notice.get_children():
		if layer is CanvasItem: layer.light_mask = PARENT_FILL_MASK
	var fill := PointLight2D.new()
	fill.texture = preload("res://assets/art/lights/light_lamp_pool.png")
	fill.texture_scale = 0.4
	fill.color = Color("e9b77a")
	fill.energy = PARENT_FILL_ENERGY
	fill.range_item_cull_mask = PARENT_FILL_MASK
	world.zones["hallway"].add_child(fill)
	fill.global_position = notice.global_position
	var spill := PointLight2D.new()
	spill.texture = preload("res://assets/art/lights/light_door_spill.png")
	spill.texture_scale = 0.4
	spill.color = Color("e9b77a")
	spill.energy = 1.25
	world.zones["hallway"].add_child(spill)
	spill.global_position = closest_door.global_position + Vector2(0.0, 29.2)
	GameState.state_reset.connect(func():
		notice.queue_free()
		spill.queue_free()
		fill.queue_free()
		for blocker in blockers: blocker.visible = true
		closest_door.swing = 1.0 if closest_door.is_open else 0.0, CONNECT_ONE_SHOT)

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
			enter_zone("loop",Vector2.INF,true,"loop_back")
			play_sound("impossible",player.position)
			caption("[The house shifts]")
			say("This should be outside.",6)
		"bedroom_exit": enter_zone("hallway",Vector2.INF,true,"hall_back")
		"hall_back": enter_zone("bedroom",world.marker("bedroom","SpawnFromHallway"),true,"bedroom_exit")
		"hall_exit":
			enter_zone("forest",Vector2.INF,true,"forest_back")
		"forest_back": enter_zone("hallway",world.marker("hallway","SpawnFromForest"),true,"hall_exit")
		"loop_end":
			# Everything she carries (light, batteries, stones) stays with her: it is one game.
			tutorial_completed.emit()
			enter_zone("mansion_ground",world.marker("mansion_ground","SpawnEntrance"),true,"mansion_main_porton")
			play_sound("impossible",player.position)
			caption("[The house shifts]")
			show_dialogue([
				"VIV: This door was supposed to lead outside. The gate here is sealed.",
				"VIV: There's a light in the courtyard. I should see what's there.",
			])
	door.snap(false)

## Arriving through a door: it is open behind the player and swings shut once they step away.
func _close_behind(door: Door) -> void:
	door.snap(true)
	await get_tree().create_timer(0.6).timeout
	while is_instance_valid(door) and door.is_open and (door.is_doorway_occupied() or player.position.distance_to(door.get_noise_origin())<72.0):
		await get_tree().create_timer(0.2).timeout
	if is_instance_valid(door) and door.is_open: door.close(true)

func _caught() -> void:
	if resetting or not dialogue.is_empty() or sequence != "": return
	_begin_game_over()

# La entidad atrapo al jugador: congela la escena y muestra la pantalla de
# derrota (GameState.player_died -> GameOverUi instancia ui/game_over.tscn).
func _begin_game_over() -> void:
	resetting=true
	_player_visual("play_death")
	entity.active=false
	encounter_grace=0
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.velocity=Vector2.ZERO
	dialogue.clear()
	hud.dismiss_alert()
	dialogue_done=Callable()
	sequence=""
	# The catch plays first: the arms snap shut, the shroud folds over her, a beat of stillness.
	# Its own sounds carry the moment (EntityAudio: the grab, the cloth, the sob that stops).
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

## Visual-only hook into the player's animator (absent in studios that swap the rig).
func _player_visual(method: String) -> void:
	var animator := player.get_node_or_null("VivAnimator")
	if animator != null: animator.call(method)

func request_reset(message: String, bedroom := false) -> void:
	_player_visual("play_caught")
	if resetting: return
	resetting=true
	entity.active=false
	encounter_grace=0
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.velocity=Vector2.ZERO
	dialogue.clear()
	hud.dismiss_alert()
	dialogue_done=Callable()
	if sequence=="attack":
		# Retrying before the completed attack should permit the conversation again.
		friend_met=false
		world.props["friend"].show()
	sequence=""
	if not bedroom: hud.shade.color=Color(0,0,0,.82)
	say(message,4)
	play_sound("parent" if bedroom else "presence",player.position)
	_restore_after_delay(bedroom)

func _restore_after_delay(bedroom: bool) -> void:
	if bedroom and not test_mode:
		await get_tree().create_timer(.9).timeout
		hud.shade.color=Color.BLACK
		await get_tree().create_timer(.1).timeout
	else:
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
	player.get_node("LocalLight").enabled=true
	thrower.available=true
	player.process_mode=Node.PROCESS_MODE_INHERIT
	resetting=false
	hud.shade.color=Color(0,0,0,0)
	# A parent catch restarts at the hallway entrance, close to the lesson, with gear kept.
	if bedroom: enter_zone("hallway",world.marker("hallway","SpawnFromBedroom"),false)
	else: enter_zone(checkpoint.get("zone","bedroom"),checkpoint.get("position",Vector2(340,440)),false)
	if bedroom: space_hint=true

func _frame_camera() -> void:
	if not is_instance_valid(player): return
	var camera := player.get_node("Camera2D") as PixelCamera
	var region: Rect2 = World.REGIONS[zone]
	camera.limit_left = int(region.position.x)
	camera.limit_top = int(region.position.y)
	camera.limit_right = int(region.end.x)
	camera.limit_bottom = int(region.end.y)
	camera.snap_to_target()

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

func _on_ranger_spotted() -> void:
	if zone == "forest" and not resetting:
		say("RANGER: You there! Stop!", 3.0)
		if not has_sprinted: sprint_hint_time = 4.0

func _on_ranger_caught() -> void:
	if zone == "forest" and not resetting:
		request_reset("RANGER: Trail's closed. Go home.")

func _tick_ranger_checkpoint() -> void:
	var forest: Node2D = world.zones["forest"]
	var ranger = forest.get_node("Ranger")
	if ranger.distracted:
		forest.get_node("ThrowTarget").hide()
	if ranger_checkpoint_ready: return
	var setup: Vector2 = forest.global_position + Vector2(700,400)
	if player.global_position.distance_to(setup) > 55.0: return
	ranger_checkpoint_ready = true
	thrower.rocks = maxi(thrower.rocks,3)
	# This known clear spot makes every retry and the directional instruction consistent.
	player.global_position = setup
	player.velocity = Vector2.ZERO
	player.get_node("FootstepNoise").reset_steps()
	save_checkpoint()
	# He keeps walking his beat: putting him back at his post here would jump his light.
	ranger.active = true
	forest.get_node("ThrowTarget").show()

## The end of the forest trail: past the last petals she walks on to the house by herself.
func _past_forest_exit() -> bool:
	if resetting or not dialogue.is_empty() or not world.interactables.has("forest_exit"): return false
	var exit_at: Vector2 = world.interactables["forest_exit"]["position"]
	return player.global_position.x >= exit_at.x + FOREST_EXIT_REACH \
		and absf(player.global_position.y - exit_at.y) <= FOREST_EXIT_WIDTH

## Leaving the forest for the house, by walking on or with the prompt. Only a ranger on her
## heels shuts the way: a stone or good timing both get her here.
func _leave_forest() -> void:
	var ranger = world.zones["forest"].get_node("Ranger")
	if ranger.chasing:
		if subtitle_time <= 0.0: say("Not with him right behind me.", 4.0)
		return
	enter_zone("house")

## The Hacienda's own interactions. True when `id` was one of them.
func _interact_mansion(id: String, target: Node) -> bool:
	if id == "mansion_main_porton":
		var porton := target as Door
		if GameState.altars_completed < GameState.total_altars:
			say("Sealed from the outside. The seven altars have to be prayed at first.", 5.0)
			play_sound("door", player.position)
			caption("[The gate rattles]")
		elif not complete:
			complete = true
			entity.active = false
			mansion_grace = 0.0
			porton.locked = false
			porton.open(breath.is_holding)
			_begin_mansion_epilogue()
		return true
	if id.begins_with("stairs_to_"):
		_take_stairs(id)
		return true
	if id.begins_with("altar_"):
		return true      # the altar itself takes the held key (level/props/mansion_altar.gd)
	if target is Door:
		if target.locked:
			say(target.locked_label, 5.0)
		else:
			_use_door(target as Door)
		return true
	if id.begins_with("battery_"):
		batteries += 1
		collect(id)
		if has_flashlight and flashlight.battery_percent <= 0: insert_battery()
		return true
	if id.begins_with("rocks_"):
		if thrower.rocks < 3:
			thrower.rocks = mini(3, thrower.rocks + 3)
			play_sound("pickup", player.position)
			_animate_rocks(target.global_position)
		return true
	return false

## Stairs join the two floors: stepping onto them (or the prompt) takes her to the other one.
func _on_stairs_entered(body: Node2D, id: String) -> void:
	if body == player and not resetting and dialogue.is_empty():
		_take_stairs.call_deferred(id)

func _take_stairs(id: String) -> void:
	if resetting: return
	if id == "stairs_to_upper" and zone == "mansion_ground":
		if not mansion_story.completed("altar_4"):
			say("The stair gate is sealed. The chapel altar may open it.", 5.0)
			return
		enter_zone("mansion_upper", world.marker("mansion_upper", "SpawnFromStairs"))
	elif id == "stairs_to_ground" and zone == "mansion_upper":
		enter_zone("mansion_ground", world.marker("mansion_ground", "SpawnFromUpper"))
	else:
		return
	play_sound("door", player.position)
	caption("[Stairs creak]")

func _on_mansion_prayer_started(altar: Node) -> void:
	var id := String(altar.get_meta("interaction_id", ""))
	if MansionStory.ALTARS.has(id):
		say(MansionStory.ALTARS[id]["words"], altar.pray_duration)


func _on_mansion_prayer_ended(altar: Node, _immediate: bool) -> void:
	var id := String(altar.get_meta("interaction_id", ""))
	if MansionStory.ALTARS.has(id) and hud.subtitle.text == MansionStory.ALTARS[id]["words"]:
		say("")


func _on_altar_prayed(altar_node: Node) -> void:
	hud.set_altars_count(GameState.altars_completed, GameState.total_altars)
	play_sound("switch", player.position, 2.0)
	var response := mansion_story.on_altar_completed(altar_node)
	say("%s (%d / %d)" % [response, GameState.altars_completed, GameState.total_altars], 6.0)
	save_checkpoint()


func _begin_mansion_epilogue() -> void:
	var porch: Vector2 = world.marker("house", "SpawnFromForest")
	enter_zone("house", porch, false)
	var eli: Node2D = world.props["friend"]
	eli.global_position = porch + Vector2(92, -12)
	eli.fallen = false
	eli.show()
	eli.rig.set_rate(&"upper", 1.0)
	eli.rig.set_rate(&"lower", 1.0)
	eli.face_and_stand(player.global_position)
	show_dialogue([
		"VIV: I found what you wrote. Inés asked you to open the door.",
		"ELI: I heard her. I had the key, and I left.",
		"VIV: Come on. When we get home, you're going to tell them what happened.",
	], _finish_mansion_epilogue)


func _finish_mansion_epilogue() -> void:
	sequence = "ending"
	sequence_time = 0.0
	sequence_step = 0


func _on_all_altars_prayed() -> void:
	hud.set_altars_count(GameState.total_altars, GameState.total_altars)
	say("All seven altars are lit. The bolt on the main gate has opened.", 8.0)
	play_sound("impossible", player.position, 0.0)
	if world.interactables.has("mansion_main_porton"):
		var porton: Door = world.interactables["mansion_main_porton"]["node"]
		porton.locked = false
		porton.locked_label = ""
