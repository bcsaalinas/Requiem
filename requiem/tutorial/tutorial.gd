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
}
## Sounds the player makes; the parents and the forest only react to these.
const PLAYER_SOUNDS := [NoiseManager.SourceType.FOOTSTEP, NoiseManager.SourceType.SPRINT,
	NoiseManager.SourceType.CROUCH, NoiseManager.SourceType.BREATH, NoiseManager.SourceType.THROW,
	NoiseManager.SourceType.DOOR]
## Seconds a warned parent keeps listening before settling again.
const PARENT_LISTEN_TIME := 3.5
## A parent door starts to stir when her next step falls short of it by less than this fraction of
## the step's reach (walking 3 u: 72 px; held 1 u: 24 px), so holding the breath visibly settles it.
const HALL_STIR_MARGIN := 0.75
## Doors that lead to another zone when the player walks through the open doorway.
const ZONE_DOORS := ["bedroom_exit", "hall_back", "hall_exit", "forest_back", "front_door"]
@export_category("Entry")
@export_enum("bedroom", "hallway", "forest", "house", "loop") var start_zone: String = "bedroom"
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
var friend_home := Vector2.ZERO
var _paused := false
var _paused_modes: Dictionary = {}
var _sounds: Dictionary = {}

func _enter_tree() -> void:
	GameState.reset()

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if not test_mode: Kiosk.enter_fullscreen()
	get_viewport().size_changed.connect(_frame_camera)
	# Beyond the walls is void: black, like the unlit rooms.
	RenderingServer.set_default_clear_color(Color.BLACK)
	thrower=player.get_node("Throw")
	breath=player.get_node("HoldBreath")
	player.get_node("Sprite2D").hide()
	breath._bar_layer.hide()
	thrower._bar_layer.hide()
	thrower.rock_landed.connect(_on_rock_landed)
	MusicDirector.bind_gameplay(entity, breath)
	flashlight=player.get_node("flashlight")
	has_flashlight=false
	flashlight.battery_percent=0.0
	flashlight._update_bar()
	flashlight._bar_layer.hide()
	flashlight.set_process(false)
	flashlight.set_process_unhandled_input(false)
	entity.caught.connect(_caught)
	hud.resume_requested.connect(_toggle_pause)
	hud.fullscreen_requested.connect(_toggle_fullscreen)
	PauseMenu.resume_pressed.connect(_toggle_pause)
	prayer_audio.stream=sound("prayer")
	prayer_audio.bus="SFX"
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
	for id in ZONE_DOORS:
		var door := world.interactables[id]["node"] as Door
		door.get_node("Doorway").body_entered.connect(_on_zone_doorway.bind(id))
		# Opening a door the player already stands in also counts as walking through.
		door.opened.connect(func(): _on_zone_doorway(player,id))
	friend_home=world.props["friend"].global_position
	prayer_audio.global_position=friend_home
	enter_zone(start_zone)
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
	if not _sounds.has(id): _sounds[id]=load("res://tutorial/assets/audio/%s.wav"%id)
	return _sounds[id]

func play_sound(id: String, at: Vector2, volume := -8.0) -> void:
	if test_mode: return
	var audio:=AudioStreamPlayer2D.new()
	audio.position=at
	audio.bus="SFX"
	audio.stream=sound(id)
	audio.volume_db=volume
	add_child(audio)
	audio.add_to_group("tutorial_audio")
	audio.finished.connect(audio.queue_free)
	audio.play()

## Moves the player into a zone. `arrival_door` (an interaction id) starts open behind the
## player and swings shut once they step away from it.
func enter_zone(next_zone: String, spawn := Vector2.INF, save := true, arrival_door := "") -> void:
	zone=next_zone
	ambient_reply_cooldown=0
	world.set_house_danger(attack_finished)
	var start_markers:={"bedroom":"SpawnStart","hallway":"SpawnFromBedroom","forest":"SpawnFromHome","house":"SpawnFromForest","loop":"SpawnFromHouse"}
	if spawn==Vector2.INF:
		spawn=world.marker(zone,start_markers[zone])
	player.position=spawn
	player.velocity=Vector2.ZERO
	player.get_node("FootstepNoise").reset_steps()
	heard_flash.clear()
	var rooms: RoomVisibility = world.rooms(zone)
	if rooms != null:
		rooms.sync_to(player.position)
	if arrival_door != "":
		_close_behind(world.interactables[arrival_door]["node"])
	player.get_node("PlayerMotion").reset_pose()
	player.get_node("PlayerAim").reset_pose()
	_frame_camera()
	player.get_node("Camera2D").reset_smoothing()
	var stage_for_zone:={"bedroom":"ki","hallway":"ki","forest":"sho","house":"ketsu" if attack_finished else "ten","loop":"ketsu"}
	stage=stage_for_zone[zone]
	stage_changed.emit(stage)
	var zone_stream := load(ZONE_AMBIENCE_PATHS[zone]) as AudioStream
	AmbienceManager.set_track(zone_stream if not test_mode else null,
		ZONE_AMBIENCE_VOLUME_DB[zone], 2.0)
	prayer_audio.stop()
	if zone=="house" and not attack_finished and not test_mode: prayer_audio.play()
	_configure_entity()
	hud.set_breath_hint(false)
	if zone == "hallway":
		hall_door_cues.clear()
		hall_stirred.clear()
		hall_refuge_cued=false
		hall_audio_clock=0
	if save: save_checkpoint()

func _configure_entity() -> void:
	entity.hide()
	entity.active=false
	MusicDirector.clear_entity_threat()
	encounter_grace=0.0
	# The opening forest and impossible room suggest a presence through spatial sound.
	# No invisible active monster: the physical threat exists only after the altar attack.
	if zone == "house" and attack_finished:
		var points: Array[Vector2] = []
		for index in range(1,7):
			points.append(world.marker("house","Patrol%d" % index))
		entity.reset_encounter(world.marker("house","EntitySpawn"),points)
		entity.show()
		encounter_grace=5.0

func _process(delta: float) -> void:
	if _paused: return
	ambient_reply_cooldown=maxf(0,ambient_reply_cooldown-delta)
	if subtitle_time>0:
		subtitle_time-=delta
		if subtitle_time<=0 and dialogue.is_empty(): hud.subtitle.text=""
	if banner_time>0:
		banner_time-=delta
		if banner_time<=0: hud.banner.text=""
	hud.breath.value=breath.lung_percent
	hud.effort.value=breath.exertion_percent
	hud.update_breath_feedback(player.get_node("BreathFeedback"))
	hud.battery.value=flashlight.battery_percent
	hud.update_inventory(has_flashlight,batteries,thrower.rocks)
	if not dialogue.is_empty(): hud.place_prompt(Vector2.ZERO,true)
	if not dialogue.is_empty() or resetting: return
	if sequence!="": _tick_sequence(delta)
	if encounter_grace>0:
		encounter_grace-=delta
		if encounter_grace<=0 and not complete and entity.visible: entity.active=true
	if zone=="hallway": _tick_hallway(delta)
	if zone=="forest" and not forest_cued and player.position.x>3500:
		forest_cued=true
		say("[A branch snaps beyond the marked path. Nothing moves.]",5)
		play_sound("branch",Vector2(3630,215),-4)
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
			else:
				say("[A chair scrapes behind the door]" if index==0 else "[Movement behind the door]",4)
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
		prop_node.set_focused(id==nearest)
	hud.prompt.text="" if nearest=="" else "E  ·  "+interaction_label(nearest)
	if nearest!="": hud.place_prompt(get_canvas_transform()*world.interactables[nearest]["position"])

func interaction_available(id: String) -> bool:
	if collected.has(id): return false
	if id=="flashlight" and has_flashlight: return false
	if id=="friend": return zone=="house" and not friend_met
	if id=="altar_pray": return false # The friend demonstrates prayer in this introduction.
	if id=="window" and door_unlocked: return false
	return true

func interaction_label(id: String) -> String:
	if id=="window" and window_broken: return "Release latch"
	if id=="front_door" and door_unlocked: return "Open door"
	var node: Node = world.interactables[id]["node"]
	if node is Door and node.is_open and id in ZONE_DOORS and _zone_door_active(id): return "Go through"
	if node is Door and (node.is_open or node.locked): return node.interaction_label()
	return world.interactables[id]["label"]

func interact(id: String) -> void:
	if not interaction_available(id): return
	# Distance validation is shared by normal input and tests; no remote interactions.
	if player.position.distance_to(world.interactables[id]["position"])>85: return
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
		"battery","forest_battery","porch_battery","house_battery":
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
		"forest_rocks","porch_rocks":
			if thrower.rocks>=3:
				say("Rocks full")
			else:
				thrower.rocks+=3
				play_sound("pickup",player.position)
				_animate_rocks(world.interactables[id]["node"].global_position)
				say("Rocks +3",5)
		"forest_exit": enter_zone("house")
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
			if not door_unlocked:
				say("Locked. The latch is beside the window.",5)
				play_sound("door",player.position)
			elif attack_finished and front_door.is_open:
				_go_through(id)
			else:
				_use_door(front_door)
		"kitchen_door","altar_door":
			_use_door(world.interactables[id]["node"])
		"friend":
			friend_met=true
			show_dialogue([
				"ELI: My aunt said we had to come here and pray at the altars. It keeps something here.",
				"ELI: Wait. Do you hear that?"
			],_begin_attack)
		"loop_back": say("It won't open.")
		"loop_end":
			if not complete:
				complete=true
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
		say("No spare battery")
		return
	if flashlight.battery_percent>85:
		say("Battery is full")
		return
	batteries-=1
	flashlight.battery_percent=100
	flashlight.is_on=true
	flashlight._refresh_light()
	play_sound("switch",player.position)
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
	var reveal: Node2D = world.landmarks["reveal"]
	reveal.modulate=Color(.65,.65,.65,.65)
	reveal.z_index=45
	reveal.show()
	play_sound("presence",reveal.global_position)
	sequence="reveal"
	sequence_time=0
	var reveal_light: PointLight2D = world.lamp(reveal.global_position+Vector2(0,30),Color("a9b9a7"),.8,.45)
	reveal_light.name="RevealLight"
	# The figure is light-only on layer 4: only this light ever shows it.
	reveal_light.range_item_cull_mask |= 8
	say("[Glass shatters]",4)

## The screen closes in as the hunting entity comes near. Only while it hunts: then its breathing
## is already loud, so the vignette never gives away a silent patrol behind a wall.
func _update_threat_presentation() -> void:
	var hunting_house: bool = zone=="house" and entity.active and entity.visible \
		and entity.get_state_name()=="HUNT"
	var pressure := 0.0
	if hunting_house:
		var distance := entity.global_position.distance_to(player.global_position)
		pressure = 1.0-smoothstep(2.0*Units.PX_PER_UNIT,10.0*Units.PX_PER_UNIT,distance)
	threat_pressure = lerpf(threat_pressure,pressure,0.08)
	(film.material as ShaderMaterial).set_shader_parameter("pressure",threat_pressure)

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
			world.landmarks["reveal"].hide()
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
			say("This should be outside.",6)
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
	world.landmarks["reveal"].hide()
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
	world.landmarks["reveal"].hide()
	var reveal_light:=world.get_node_or_null("RevealLight")
	if reveal_light!=null: reveal_light.queue_free()
	hud.shade.color=Color(0,0,0,.82)
	say(message,4)
	play_sound("parent" if bedroom else "presence",player.position)
	_restore_after_delay(bedroom)

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
