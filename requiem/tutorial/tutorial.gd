extends Node2D
## Tutorial orchestration. Existing player mechanics remain untouched.
signal stage_changed(stage: String)
signal tutorial_completed
const World := preload("res://tutorial/world.gd")
const Art := preload("res://tutorial/art.gd")
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
@onready var ambience: AudioStreamPlayer = $AmbientAudio
@onready var prayer_audio: AudioStreamPlayer2D = $PrayerAudio
var zone := "bedroom"
var stage := "ki"
var has_flashlight := false
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
var loop_hold_seen := false
var _old_debug := true
var _old_debug_legend := true
var _paused := false
var _paused_modes: Dictionary = {}
var _sounds: Dictionary = {}

func _enter_tree() -> void:
	GameState.reset()

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var args := OS.get_cmdline_user_args()
	if not test_mode and DisplayServer.get_name() != "headless" and not (args.has("--windowed") or args.has("--record") or args.has("--background")):
		get_window().mode = Window.MODE_FULLSCREEN
	get_viewport().size_changed.connect(_frame_camera)
	RenderingServer.set_default_clear_color(Color("0e161b"))
	_old_debug=NoiseDebug.enabled
	_old_debug_legend=NoiseDebug._legend_layer.visible
	NoiseDebug.enabled=false
	NoiseDebug._legend_layer.hide()
	NoiseDebug._redraw()
	thrower=player.get_node("Throw")
	breath=player.get_node("HoldBreath")
	player.get_node("Sprite2D").hide()
	breath._bar_layer.hide()
	thrower._bar_layer.hide()
	thrower.rock_landed.connect(_on_rock_landed)
	preload("res://tutorial/prop_light.gd").attach(player.get_node("LocalLight"))
	flashlight=player.get_node("flashlight")
	flashlight.battery_percent=0.0
	flashlight._update_bar()
	preload("res://tutorial/prop_light.gd").attach(flashlight)
	flashlight._bar_layer.hide()
	flashlight.set_process(false)
	flashlight.set_process_unhandled_input(false)
	entity.caught.connect(_caught)
	hud.resume_requested.connect(_toggle_pause)
	hud.fullscreen_requested.connect(_toggle_fullscreen)
	ambience.finished.connect(func(): ambience.play())
	prayer_audio.stream=sound("prayer")
	prayer_audio.finished.connect(func():
		if zone=="house" and not attack_finished: prayer_audio.play())
	flashlight.click_clips.assign([sound("switch")])
	thrower.piedra_clips.assign([sound("rock")])
	if test_mode:
		player.get_node("FootstepNoise").walk_clips.clear()
		breath.hold_clips.clear()
		breath.exertion_clips.clear()
		thrower.piedra_clips.clear()
		flashlight.click_clips.clear()
	NoiseManager.noise_emitted.connect(_on_noise)
	enter_zone(start_zone)
	if not test_mode:
		show_dialogue([
			"ELI: I'm at my aunt's old house. Follow the yellow trail marks. Bring a light.",
			"ELI: And be quiet leaving. Your parents are still awake."
		])
		play_sound("phone",player.position)

func _exit_tree() -> void:
	if is_instance_valid(NoiseDebug):
		NoiseDebug.enabled=_old_debug
		NoiseDebug._legend_layer.visible=_old_debug_legend
		NoiseDebug._redraw()
	get_tree().paused=false
	for audio in get_tree().get_nodes_in_group("tutorial_audio"):
		audio.stop()
		audio.stream=null
	_sounds.clear()
	GameState.reset()

func sound(id: String) -> AudioStream:
	if not _sounds.has(id): _sounds[id]=load("res://tutorial/assets/audio/%s.wav"%id)
	return _sounds[id]

func play_sound(id: String, at: Vector2, volume := -8.0) -> void:
	if test_mode: return
	var audio:=AudioStreamPlayer2D.new()
	audio.position=at
	audio.stream=sound(id)
	audio.volume_db=volume
	add_child(audio)
	audio.add_to_group("tutorial_audio")
	audio.finished.connect(audio.queue_free)
	audio.play()

func enter_zone(next_zone: String, spawn := Vector2.INF, save := true) -> void:
	zone=next_zone
	ambient_reply_cooldown=0
	world.set_house_danger(attack_finished)
	var origin: Vector2=World.REGIONS[zone].position
	var starts:={"bedroom":Vector2(340,440),"hallway":Vector2(110,340),"forest":Vector2(150,540),"house":Vector2(530,850),"loop":Vector2(130,330)}
	player.position=origin+starts[zone] if spawn==Vector2.INF else spawn
	player.velocity=Vector2.ZERO
	_frame_camera()
	player.get_node("Camera2D").reset_smoothing()
	var stage_for_zone:={"bedroom":"ki","hallway":"ki","forest":"sho","house":"ketsu" if attack_finished else "ten","loop":"ketsu"}
	stage=stage_for_zone[zone]
	stage_changed.emit(stage)
	ambience.stream=sound("forest" if zone=="forest" else "room")
	if not test_mode: ambience.play()
	prayer_audio.stop()
	if zone=="house" and not attack_finished and not test_mode: prayer_audio.play()
	_configure_entity()
	if zone == "hallway":
		hall_door_cues.clear()
		hall_refuge_cued=false
		hall_audio_clock=0
	if save: save_checkpoint()

func _configure_entity() -> void:
	entity.hide()
	entity.active=false
	encounter_grace=0.0
	# The opening forest and impossible room suggest a presence through spatial sound.
	# No invisible active monster: the physical threat exists only after the altar attack.
	if zone == "house" and attack_finished:
		var points: Array[Vector2] = [Vector2(6030,330),Vector2(6080,360),Vector2(6080,500)]
		entity.reset_encounter(Vector2(6030,330),points)
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
		play_sound("behind_wall",Vector2(7675,210),-5)
		say("[Slow dragging on the other side of the wall.]",5)
	if zone=="loop" and breath.is_holding: loop_hold_seen=true
	if zone=="house" and door_unlocked and not attack_finished and player.position.y<660 and checkpoint.get("position",Vector2.ZERO).y>704:
		save_checkpoint()
	_find_interaction()

func _tick_hallway(delta: float) -> void:
	hall_audio_clock -= delta
	var x := player.position.x
	for index in range(2):
		var door_x := 1930.0 if index == 0 else 2310.0
		if absf(x-door_x)<190 and not hall_door_cues.has(index):
			hall_door_cues[index]=true
			hall_cued=true
			say("[Chair scrapes behind the door]\nSPACE · Hold breath" if index==0 else "[Movement behind the door]",6)
			play_sound("chair_scrape",Vector2(door_x,276),-3)
			hall_audio_clock=4.0
	if hall_audio_clock<=0:
		var door_x := 1930.0 if x<2110 else 2310.0
		play_sound("parent_rustle",Vector2(door_x,276),-7)
		hall_audio_clock=6.5
	if Rect2(2038,418,144,128).has_point(player.position) and not hall_refuge_cued:
		hall_refuge_cued=true
		say("Release your breath. Rest here.",6)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if key==KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if key in [KEY_H,KEY_ESCAPE]:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused: return
	if key==KEY_R and not resetting:
		request_reset("Back to the last safe place.")
		get_viewport().set_input_as_handled()
		return
	if key==KEY_B and dialogue.is_empty() and not resetting:
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
			if not has_flashlight or (flashlight.battery_percent<=0 and batteries==0):
				say("I need a light before I go.")
				return
			if flashlight.battery_percent<=0: insert_battery()
			enter_zone("hallway")
			play_sound("door",player.position)
		"hall_back": enter_zone("bedroom",Vector2(820,460))
		"hall_exit":
			enter_zone("forest")
			say("The yellow marks. Eli went this way.",5)
		"forest_back": enter_zone("hallway",Vector2(2450,340))
		"forest_rocks","porch_rocks":
			if thrower.rocks>=3:
				say("Rocks full")
			else:
				thrower.rocks+=3
				play_sound("pickup",player.position)
				say("Rocks +3",5)
		"forest_exit": enter_zone("house")
		"house_back":
			if attack_finished: say("The path has disappeared into the dark.")
			else: enter_zone("forest",Vector2(4460,540))
		"window":
			if window_broken:
				door_unlocked=true
				world.props["entry_collision"].queue_free()
				world.props["front_door"].hide()
				play_sound("door",player.position)
				say("[Latch clicks]",5)
				# Re-bake the house after the door collision leaves the tree.
				_rebake_house.call_deferred()
			else: say("The latch is behind the glass.\nQ · Throw rock",6)
		"front_door":
			if not door_unlocked:
				say("Locked. The latch is beside the window.",5)
				play_sound("door",player.position)
			elif attack_finished:
				enter_zone("loop")
				play_sound("impossible",player.position)
				say("This should be outside.",6)
			else:
				player.position=Vector2(5737,620) if player.position.y>680 else Vector2(5737,755)
				player.velocity=Vector2.ZERO
				if player.position.y<680: save_checkpoint()
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
				say("There has to be another way out.",9)
				play_sound("impossible",player.position,-14)

func collect(id: String) -> void:
	collected[id]=true
	world.interactables[id]["node"].hide()
	play_sound("pickup",player.position)

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
	say("Battery replaced")

func _rebake_house() -> void:
	await get_tree().process_frame
	world.navigation_regions[1].bake_navigation_polygon(false)

func _on_rock_landed(at: Vector2) -> void:
	if zone!="house" or window_broken: return
	if at.distance_to(Vector2(5870,692))>59: return
	window_broken=true
	world.props["window"].broken=true
	world.window_body.get_child(1).visible=false
	world.props["window"].queue_redraw()
	world.prop("shards","glass",Vector2(5870,720))
	play_sound("glass",at,-3)
	NoiseManager.emit_noise(at,256,NoiseManager.SourceType.ENVIRONMENT)
	world.props["reveal"].position=Vector2(5878,640)
	world.props["reveal"].modulate=Color(.65,.65,.65,.65)
	world.props["reveal"].show()
	play_sound("presence",Vector2(5870,640))
	sequence="reveal"
	sequence_time=0
	world.lamp(Vector2(5870,642),Color("a9b9a7"),.8,.45).name="RevealLight"
	say("[Glass shatters]",4)

func _begin_attack() -> void:
	sequence="attack"
	sequence_time=0
	sequence_step=0
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.velocity=Vector2.ZERO
	thrower.available=false
	play_sound("presence",Vector2(6230,170))
	say("[Scraping behind the wall]",3)

func _tick_sequence(delta: float) -> void:
	sequence_time+=delta
	if sequence=="reveal":
		if sequence_time>=1.15:
			world.props["reveal"].hide()
			var light:=world.get_node_or_null("RevealLight")
			if light!=null: light.queue_free()
			sequence=""
			say("",6)
		return
	if sequence!="attack": return
	if sequence_time>=2.3 and sequence_step==0:
		sequence_step=1
		play_sound("thud",Vector2(6240,365),-2)
		NoiseManager.emit_noise(Vector2(6240,365),256,NoiseManager.SourceType.ENVIRONMENT)
		hud.shade.color=Color(0,0,0,.96)
		world.props["friend"].hide()
		say("[A gasp. A heavy impact.]",3)
	if sequence_time>=3.6 and sequence_step==1:
		sequence_step=2
		world.props["friend"].fallen=true
		world.props["friend"].position=Vector2(6240,392)
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
			var listeners := [Vector2(3630,285),Vector2(4010,285)] if zone=="forest" else [Vector2(7640,278),Vector2(7850,278)]
			for listener in listeners:
				if at.distance_to(listener)<=radius:
					play_sound("branch" if zone=="forest" else "behind_wall",listener,-4)
					say("[Branches shift nearby]" if zone=="forest" else "[The dragging stops]",4)
					ambient_reply_cooldown=6.0
					break
	if zone!="hallway" or resetting or not dialogue.is_empty(): return
	# Parent listens to player actions only; ambience never becomes a failure signal.
	if source not in [NoiseManager.SourceType.FOOTSTEP,NoiseManager.SourceType.SPRINT,NoiseManager.SourceType.CROUCH,NoiseManager.SourceType.BREATH,NoiseManager.SourceType.THROW]: return
	for ear in [Vector2(1930,276),Vector2(2310,276)]:
		if at.distance_to(ear)<=radius:
			parent_failures+=1
			request_reset("PARENT: Back to your room. Now.",true)
			return

func _caught() -> void:
	if not resetting and dialogue.is_empty() and sequence=="": request_reset("")

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
	world.props["reveal"].hide()
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
	player.get_node("FootstepNoise").footstep_timer=0
	player.get_node("FootstepNoise")._audio_player.stop()
	player.velocity=Vector2.ZERO
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
	if bedroom: enter_zone("bedroom",Vector2(760,425),false)
	else: enter_zone(checkpoint.get("zone","bedroom"),checkpoint.get("position",Vector2(340,440)),false)
	if bedroom: say("",6)

func _frame_camera() -> void:
	if not is_instance_valid(player): return
	var camera := player.get_node("Camera2D") as Camera2D
	var region: Rect2 = World.REGIONS[zone]
	var viewport_size := get_viewport_rect().size
	var zoom := maxf(1.65,maxf(viewport_size.x/region.size.x,viewport_size.y/region.size.y))
	camera.zoom = Vector2.ONE*zoom
	camera.limit_left = int(region.position.x)
	camera.limit_top = int(region.position.y)
	camera.limit_right = int(region.end.x)
	camera.limit_bottom = int(region.end.y)
	camera.force_update_scroll()

func _toggle_fullscreen() -> void:
	get_window().mode = Window.MODE_WINDOWED if get_window().mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_FULLSCREEN

func _toggle_pause() -> void:
	_paused = not _paused
	hud.help_panel.visible = _paused
	process_mode = Node.PROCESS_MODE_ALWAYS if _paused else Node.PROCESS_MODE_INHERIT
	for child in get_children():
		if _paused:
			_paused_modes[child] = child.process_mode
			if child.process_mode != Node.PROCESS_MODE_DISABLED: child.process_mode = Node.PROCESS_MODE_PAUSABLE
		else:
			child.process_mode = _paused_modes.get(child,Node.PROCESS_MODE_INHERIT)
	if not _paused: _paused_modes.clear()
	get_tree().paused = _paused
