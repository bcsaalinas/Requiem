extends Node
var game: Node2D
var old_captions := false
var failures: Array[String]=[]
var checks:=0

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame

func at_interaction(id: String, offset:=Vector2(0,45)) -> void:
	game.player.position=game.world.interactables[id]["position"]+offset
	game.player.velocity=Vector2.ZERO
	game.interact(id)

func _ready() -> void:
	game=preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode=true
	add_child(game)
	old_captions=Preferences.captions
	Preferences.captions=true
	await frames(5)
	var step_audio: Node = game.player.get_node("FootstepAudio")
	check(game.zone=="bedroom" and step_audio.surface==&"wood","In the bedroom Viv walks on wood")
	check(game.world.navigation_regions.size()==3,"Three bounded navigation regions exist")
	check(game.breath.drain_rate_percent==20.0 and game.breath.exertion_rise_rate_percent==6.0,"Existing breathing rates preserved")
	check(game.player.walk_speed_u==3.2 and game.player.hold_breath_speed_u==2.5,"Existing movement rates preserved")
	check(not game.thrower.can_throw(),"Rocks cannot be thrown before collection")
	at_interaction("bedroom_exit")
	check(game.zone=="bedroom","Missing equipment prevents leaving the bedroom")
	at_interaction("battery")
	check(game.batteries==1 and not game.has_flashlight,"Battery can be collected before the flashlight")
	at_interaction("flashlight")
	check(game.has_flashlight and game.flashlight.battery_percent>99,"Pickups equip and power flashlight")
	# A battery that ran dry in the bedroom must never lock the player in (tester bug).
	game.flashlight.battery_percent=0.0
	var bedroom_door: Door = game.world.interactables["bedroom_exit"]["node"]
	at_interaction("bedroom_exit",Vector2(-36,0))
	check(bedroom_door.is_open,"A collected but empty battery still lets the player open the bedroom door")
	await frames(4)
	check(game.zone=="hallway","Walking through the open bedroom door enters the hallway")
	check(step_audio.surface==&"wood","In the hallway she walks on wood")
	game.flashlight.battery_percent=100.0
	var door_a: ParentListener = game._parent_listeners()[0]
	game.player.position=door_a.global_position+Vector2(-150,48)
	game._tick_hallway(.01)
	check(game.hud.caption.text.contains("Chair scrapes"),"Approaching the first occupied door plays a listening cue")
	game._update_key_hint(.01)
	check(game.space_hint and game.hud.key_hint.text.contains("Hold breath"),"The first door cue puts the hold-breath key under her")
	check(game.hud.key_hint.visible,"The hold-breath key stays on screen in the hallway before any danger")
	# Teach before failing: a door stirs once a normal step could reach it and settles while she holds.
	game.player.position=door_a.global_position+Vector2(0,48)
	game._tick_hallway(.01)
	check(door_a.danger>0.9 and not game.hall_warned,"A parent door stirs when her next step could reach it, before anything is heard")
	game.breath.is_holding=true
	game._tick_hallway(.01)
	check(door_a.danger<0.5,"Holding her breath settles the door")
	game.breath.is_holding=false
	game.player.position=game.world.marker("hallway","SpawnFromBedroom")
	game._tick_hallway(.01)
	check(door_a.danger==0.0,"Doors stay calm while she stands in the light")
	var refuge: SafeLight = game.world.nodes_in("hallway","SafeLights")[0]
	game.player.position=refuge.global_position
	game.breath.lung_percent=40.0
	game._tick_hallway(.01)
	check(game.hall_refuge_cued,"Arriving out of breath inside the refuge light is recognised")
	game.breath.lung_percent=100.0
	NoiseManager.emit_noise(refuge.global_position+Vector2(0,-60),224,NoiseManager.SourceType.BREATH)
	check(not game.resetting and not game.hall_warned,"Even a forced gasp inside the refuge light never reaches the parents")
	# Hearing is "the ring reaches the door edge", so the far side of the corridor is no free path.
	var far_side := door_a.global_position+Vector2(0,80)
	NoiseManager.emit_noise(far_side,32,NoiseManager.SourceType.CROUCH)
	check(not game.hall_warned,"Held footsteps pass the door on the far side of the corridor")
	NoiseManager.emit_noise(far_side,96,NoiseManager.SourceType.FOOTSTEP)
	check(game.hall_warned and not game.resetting,"The first footstep a parent hears is a warning, not a failure")
	game._update_key_hint(.01)
	check(game.hall_hold_alert and game.hud.key_hint.text.contains("Hold breath"),"The warning asks for held breath under her")
	check(door_a.alert>0.9,"The door that heard her lights up")
	check(game.get_node_or_null("NoiseFx/Rings")==null,"No sound circles are drawn for the player's noises")
	check(not game.player.is_physics_processing(),"The warning freezes the player for a beat while breath input stays live")
	await get_tree().create_timer(1.3).timeout
	check(game.player.is_physics_processing(),"The player can move again after the warning beat")
	NoiseManager.emit_noise(far_side,96,NoiseManager.SourceType.FOOTSTEP)
	check(game.resetting,"Being heard again after the warning sends the player back")
	await frames(10)
	check(game.zone=="hallway" and game.has_flashlight and game.player.position.distance_to(game.world.marker("hallway","SpawnFromBedroom"))<1.0,
		"A parent catch restarts at the hallway entrance and keeps the equipment")
	check(game.breath.lung_percent==100 and not game.breath.is_locked,"Retry restores air and clears forced lock")
	# The restart landing is lit: a breath held there until it gives out cannot get her caught again.
	NoiseManager.emit_noise(game.world.marker("hallway","SpawnFromBedroom"),224,NoiseManager.SourceType.BREATH)
	check(not game.resetting,"A forced gasp at the hallway restart point stays inside its light")
	# Real physics movement through a complete first crossing using unchanged inputs.
	game.player.position=door_a.global_position+Vector2(-140,48)
	Input.action_press("hold_breath")
	Input.action_press("move_right")
	await frames(192)
	Input.action_release("move_right")
	Input.action_release("hold_breath")
	check(game.zone=="hallway" and not game.resetting and game.player.position.x>door_a.global_position.x+60,"Held movement physically traverses the first parent crossing")
	check(not game.space_hint and not game.hud.key_hint.visible,"Holding her breath past the doors retires the key hint")
	await frames(5)
	# Zone doors are real doors: E opens them, walking into the doorway goes through.
	var back_door: Door = game.world.interactables["hall_exit"]["node"]
	at_interaction("hall_exit",Vector2(-36,16))
	check(back_door.is_open,"The back door opens before the player can leave")
	game._tick_hallway(.01)
	check(game.hall_lesson_done and game.hud.key_hint.text=="","Past both doors the lesson ends and the key hint goes")
	await frames(4)
	check(game.zone=="forest" and game.stage=="sho","Walking through the open back door begins the forest stage")
	check(step_audio.surface==&"forest","In the forest she walks on the forest floor")
	check(not back_door.is_open,"The back door is shut behind the player")
	check(not game.entity.visible and not game.entity.active,"Forest uses indirect presence without an invisible active capture entity")
	NoiseManager.emit_noise(Vector2(3580,350),32,NoiseManager.SourceType.CROUCH)
	check(game.ambient_reply_cooldown==0,"Held movement does not provoke the distant forest response")
	NoiseManager.emit_noise(Vector2(3580,350),96,NoiseManager.SourceType.FOOTSTEP)
	check(game.ambient_reply_cooldown>0 and not game.resetting,"Audible footsteps receive an environmental answer without an unfair unseen capture")
	at_interaction("early_rocks")
	await frames(2)
	check(game.player.process_mode==Node.PROCESS_MODE_INHERIT and game.hud.key_hint.text.contains("Throw"),"First stones fill her pockets and put the throw key under her")
	var _r=game.world.zones["forest"].get_node("Ranger")
	check(not _r.chasing and not _r.investigating,"Picking up the first stones does not draw the ranger off his beat")
	game.advance_dialogue()
	check(game.player.process_mode==Node.PROCESS_MODE_INHERIT,"Continue leaves the player and camera free")
	at_interaction("forest_rocks")
	check(game.dialogue.is_empty(),"Later stones do not repeat the interruption")
	check(game.thrower.rocks==3,"Forest rock pile fills finite inventory")
	await complete_sound_lesson()
	game.entity.active=false
	game.encounter_grace=999
	at_interaction("forest_exit")
	check(game.zone=="house" and game.stage=="ten","House begins the turn")
	check(step_audio.surface==&"wood","In the house she walks on wood again")
	at_interaction("porch_rocks")
	at_interaction("front_door")
	check(not game.door_unlocked,"Front door initially stays locked")
	game._on_rock_landed(Vector2(5500,700))
	check(not game.window_broken,"Missing window does not unlock progression")
	game.player.position=Vector2(5870,800)
	game.player.get_node("Camera2D").reset_smoothing()
	await frames(30)
	# Supply the same explicit aim target used by the playable throw presentation,
	# then exercise inherited windup, flight, impact and finite inventory.
	var query:=PhysicsRayQueryParameters2D.create(game.player.position,Vector2(5870,608),1)
	query.exclude=[game.player.get_rid()]
	var hit: Dictionary=game.player.get_world_2d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider==game.world.window_body,"Window collider intercepts a rock thrown from the porch")
	game.player.get_node("PlayerAim").set_target(Vector2(5870,608))
	game.thrower._start_throw()
	check(game.thrower.rocks==2,"Beginning a real throw consumes one collected rock")
	await frames(70)
	check(game.window_broken,"Rock flight and impact break the sidelight")
	var side_light: WallWindow = game.world.interactables["window"]["node"]
	check(side_light.broken and side_light.get_node("Shards").visible,"Window impact breaks the glass and drops shards on the porch")
	check(not game.entity.visible,"Window impact keeps the entity unseen until the altar")
	await frames(150)
	check(game.sequence=="","Window reveal finishes without trapping interactions")
	var front_door: Door = game.world.interactables["front_door"]["node"]
	at_interaction("window",Vector2(0,60))
	await frames(3)
	check(game.door_unlocked and not front_door.locked and front_door.is_open,"Reaching through releases the latch and the front door swings in")
	# Walk in through the real doorway; the entrance must stay a door and shut behind the player.
	game.player.position=front_door.global_position+Vector2(0,26)
	Input.action_press("move_up")
	await frames(110)
	Input.action_release("move_up")
	await frames(30)
	check(game.player.position.y<front_door.global_position.y-96,"The unlocked front door permits entry on foot")
	check(front_door.visible and not front_door.is_open,"The entrance stays a visible door and shuts behind the player")
	# Trunks reward looking around; the one under the burning candle keeps shut for now.
	var key_trunk: Node2D = game.world.interactables["chest_vestibule"]["node"]
	at_interaction("chest_vestibule",Vector2(0,70))
	check(not key_trunk.is_open and not game.has_key,"The trunk under the burning candle does not open before the blackout")
	var spares_before: int = game.batteries
	at_interaction("chest_altar",Vector2(0,70))
	check(game.world.interactables["chest_altar"]["node"].is_open and game.batteries==spares_before+1,"A trunk opens and gives its battery")
	check(not game.interaction_available("chest_altar"),"An opened trunk offers nothing more")
	at_interaction("chest_altar_corner",Vector2(0,-50))
	check(game.world.interactables["chest_altar_corner"]["node"].is_open and game.batteries==spares_before+1,"Some trunks are empty")
	var altar_energy: float=game.world.landmarks["AltarLeftLight"].energy
	at_interaction("friend")
	check(not game.dialogue.is_empty(),"Friend dialogue precedes attack")
	var help_key:=InputEventKey.new()
	help_key.physical_keycode=KEY_H
	help_key.pressed=true
	game._input(help_key)
	check(get_tree().paused and PauseMenu.is_open and PauseMenu._root.visible,"Help pauses the tutorial")
	game._input(help_key)
	check(not get_tree().paused and game.player.process_mode==Node.PROCESS_MODE_DISABLED,"Closing help preserves the dialogue input lock")
	while not game.dialogue.is_empty(): game.advance_dialogue()
	# The last flame takes every light with it, hers included: Eli goes in total dark.
	var ring: PointLight2D = game.player.get_node("LocalLight")
	var lit_when_gone := false
	var dark_frames := 0
	for tick in range(520):
		await frames(1)
		if game.attack_finished: break
		if not game.world.props["friend"].visible:
			if game.flashlight.enabled or ring.enabled: lit_when_gone = lit_when_gone or dark_frames == 0
			else: dark_frames += 1
	check(not lit_when_gone and dark_frames>=int(game.BLACKOUT_SECONDS*60.0)-2,"The last candle puts out her flashlight and ring before Eli is gone, and holds the dark")
	check(ring.enabled and game.flashlight.is_on==(game.flashlight.battery_percent>0.0),"Her light comes back by itself once the dark has done its work")
	check(game.attack_finished and game.world.props["friend"].fallen and not game.world.props["friend"].visible,"Attack leaves friend hidden and fallen")
	check(game.player.process_mode!=Node.PROCESS_MODE_DISABLED,"Story releases player input")
	check(game.stage=="ketsu","Aftermath starts the integration stage")
	check(game.world.landmarks["AltarLeftLight"].energy<altar_energy and game.world.landmarks["HouseRecoveryLight"].energy>game.world.landmarks["AltarLeftLight"].energy,"Aftermath dims the dangerous altar while the recovery lamp stays bright")
	game.request_reset("test retry")
	await get_tree().create_timer(0.2).timeout
	for tick in range(400):
		if not game.resetting: break
		await frames(1)
	game.entity.active=false
	check(game.attack_finished and game.friend_met and game.world.props["friend"].fallen and not game.world.props["friend"].visible,"House retry preserves completed story (friend still hidden and fallen)")
	check(game.world.landmarks["AltarLeftLight"].energy<altar_energy,"House retry preserves the changed lighting")
	at_interaction("friend")
	check(game.dialogue.is_empty(),"Completed dialogue cannot replay")
	# After the blackout: the way out has shut itself, and the house is only sound.
	check(front_door.locked and not front_door.is_open,"The front door locks itself in the blackout")
	check(game.in_unease() and game.encounter_grace<=0.0 and not game.entity.visible and not game.entity.active,"Nothing is in the house yet: only its noises")
	at_interaction("front_door",Vector2(0,-55))
	await frames(2)
	check(game.zone=="house" and front_door.locked and game.interaction_label("front_door")=="Try the door","Without the key the front door only rattles")
	var heard_before: int = game.unease_count
	for tick in range(240):
		await frames(1)
		if game.unease_count>heard_before: break
	var house_origin: Vector2 = game.world.zones["house"].global_position
	var vestibule := Rect2(house_origin+Vector2(400,128),Vector2(416,512))
	check(game.unease_count>heard_before and game.unease_last==game.UNEASE_KNOCK,"The house answers a rattled door with a knock")
	check(not vestibule.has_point(game.unease_last_at),"House sounds come from a room she is not in")
	# Two more sounds, 5 to 9 s apart each: up to 18 s, so 20 s of waiting (15 s failed one run in five).
	for tick in range(1200):
		await frames(1)
		if game.unease_count>=heard_before+3: break
	check(game.unease_count>=heard_before+3 and not game.entity.visible and game.encounter_grace<=0.0,"The house keeps making sounds while she searches, and nothing appears")
	check(game.unease_last_at.distance_to(game.player.global_position)<=game.UNEASE_BEHIND_DISTANCE+1.0,"Every third sound is a board right behind her")
	# A page tells her where the key is; the key trunk starts the next stage.
	at_interaction("chest_kitchen",Vector2(0,-50))
	check(not game.dialogue.is_empty() and game.dialogue[0].contains("spare key"),"A trunk can hold a page that points to the key")
	while not game.dialogue.is_empty(): game.advance_dialogue()
	var candle_rest: Vector2 = game.world.props["vestibule_candle"].global_position
	at_interaction("chest_vestibule",Vector2(0,70))
	check(key_trunk.is_open and game.has_key and not game.in_unease(),"After the blackout the trunk gives up the key")
	check(game.in_presence() and game.encounter_grace>0.0 and not game.entity.visible,"Taking the key starts its own sounds, with nothing to see yet")
	await frames(30)
	check(game.world.props["vestibule_candle"].global_position.distance_to(candle_rest)>15.0 and game.key_noise_at!=Vector2.INF,"Lifting the lid tips the dead candle onto the floor")
	check(game.hud._slots.has("key") and game.hud._slots.key.visible,"The key shows in the inventory")
	at_interaction("front_door",Vector2(0,-55))
	await frames(2)
	check(game.zone=="house" and front_door.locked and not game.key_used,"While it is coming in, the front door is not a way out")
	# Run the heard phase out: it drags in from the door, breathes, and only then stands there.
	game.flashlight.is_on=false
	game.encounter_grace=0.05
	for tick in range(240):
		await frames(1)
		if game.entity.visible: break
	check(game.heard_step==game.PRESENCE_PATH.size(),"Its sounds walk the whole path in from the front door")
	check(game.entity.visible and game.entity.active and not game.in_presence(),"Only after its sounds does it appear")
	check(game.entity.global_position.distance_to(house_origin+game.PRESENCE_PATH[-1]["spot"])<48.0,"It stands up where it was last heard")
	game.entity.active=false
	game.flashlight.is_on=game.flashlight.battery_percent>0.0
	at_interaction("front_door",Vector2(0,-55))
	check(game.key_used and not front_door.locked and front_door.is_open,"With it inside, the key opens the front door")
	await frames(2)
	check(not game.hud._slots.key.visible,"A used key leaves the inventory")
	game.interact("front_door")
	await frames(4)
	check(game.zone=="loop","Return doorway leads to the impossible room")
	check(step_audio.surface==&"wood" and game.ZONE_SURFACE.size()==5,"In the last room she walks on wood: every zone has its surface")
	check(not game.entity.active,"Return visit preserves the aftermath")
	at_interaction("loop_end",Vector2(-45,0))
	check(game.complete and not game.entity.active,"Final doorway completes tutorial and stops encounter")
	game.queue_free()
	Preferences.captions=old_captions
	await frames(3)
	print("[Tutorial tests] ",checks-failures.size(),"/",checks," passed")
	# Let the audio mixer release stopped playbacks after scene teardown.
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func complete_sound_lesson() -> void:
	var ranger = game.world.zones["forest"].get_node("Ranger")
	var forest_origin: Vector2 = game.world.zones["forest"].global_position
	var beat: Node2D = game.world.zones["forest"].get_node("RangerBeat")
	var east_post: Vector2 = beat.get_child(beat.get_child_count()-1).global_position
	# His beat: from the lantern post down the trail to the east post and back, the same way every time.
	ranger.reset_patrol()
	ranger.active = true
	game.player.position = forest_origin + Vector2(700,400)
	var home: Vector2 = ranger.home
	await frames(30)
	check(ranger.global_position.distance_to(home)<2.0 and ranger.facing.x>0.5,"The beat starts at the lantern post, looking down the trail")
	var reached_east := false
	var returned := false
	var seen_waiting := false
	var beam_swept_her := false
	for tick in range(1800):
		await frames(1)
		seen_waiting = seen_waiting or ranger.chasing
		beam_swept_her = beam_swept_her or ranger.in_beam(game.player.global_position)
		if not reached_east: reached_east = ranger.global_position.distance_to(east_post)<40.0 and ranger.wait_left>0.0
		elif ranger.global_position.distance_to(home)<30.0 and ranger.wait_left>0.0:
			returned = true
			break
	check(reached_east,"The ranger walks his beat out to the east post and stops to look")
	check(returned,"The beat brings him back to the lantern post")
	check(not seen_waiting,"Standing still at the checkpoint spot through a whole beat is never spotted")
	check(beam_swept_her,"His turning beam does pass over the checkpoint spot, too briefly to be sure")
	ranger.chasing = true
	at_interaction("forest_exit")
	check(game.zone=="forest","The way on stays shut while the ranger is on her heels")
	ranger.active = false
	ranger.reset_patrol()
	# What his beam lights is what he sees: range, cone and a clear line. Each case is judged the
	# moment she is placed, so his sweeping torch cannot move between placing and looking. The
	# lantern beside his post hides a sliver of the trail at one end of the sweep, so wait for
	# the torch to come back to the middle first.
	for tick in range(300):
		await frames(1)
		if absf(rad_to_deg(ranger.beam_direction().angle_to(ranger.facing))) < 3.0: break
	var ahead: Vector2 = ranger.beam_direction()
	var beam_start: Vector2 = ranger.beam_origin()
	game.player.global_position = beam_start + ahead * (ranger.sight_range - 20.0)
	check(ranger.in_beam(game.player.global_position) and ranger.can_see_player(),"A player near the far end of the beam is seen")
	game.player.global_position = beam_start + ahead * (ranger.sight_range + 30.0)
	check(not ranger.can_see_player(),"Past the end of the beam she is not seen")
	game.player.global_position = beam_start + ahead.rotated(deg_to_rad(ranger.sight_half_angle + 8.0)) * 160.0
	check(not ranger.can_see_player(),"Beside the beam she is not seen, however close to its edge")
	game.player.global_position = beam_start + ahead.rotated(-deg_to_rad(ranger.sight_half_angle - 6.0)) * 160.0
	check(ranger.can_see_player(),"Inside the edge of the beam she is seen")
	game.player.global_position = ranger.global_position - ahead * 60.0
	check(not ranger.can_see_player(),"Player behind the ranger is outside his vision")
	ranger.facing = Vector2.DOWN
	ranger.get_node("Appearance").snap_to_facing()
	await frames(4)
	game.player.global_position = ranger.beam_origin() + ranger.beam_direction() * 110.0
	check(ranger.can_see_player(),"Ranger sees a player in front on a clear path")
	await frames(2)
	var blocker := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(60,12)
	shape.shape = rectangle
	blocker.add_child(shape)
	blocker.position = ranger.global_position.lerp(game.player.global_position,0.5)
	blocker.rotation = ranger.global_position.angle_to_point(game.player.global_position) + PI*0.5
	game.add_child(blocker)
	await frames(2)
	check(ranger.in_beam(game.player.global_position) and not ranger.can_see_player(),"Opaque collision geometry blocks the ranger's sight")
	blocker.queue_free()
	await frames(2)
	# A glimpse at the far end takes a moment to register; then he comes.
	game.player.global_position = ranger.beam_origin() + ranger.beam_direction() * (ranger.sight_range - 20.0)
	ranger.active = true
	await frames(6)
	check(not ranger.chasing and ranger.suspicion>0.0,"A glimpse at the end of the beam is not yet a sighting")
	await frames(40)
	check(ranger.chasing,"Staying in the beam starts pursuit")
	game.player.position = ranger.global_position + ranger.beam_direction() * 80.0
	await frames(2)
	check(ranger.chasing,"Seeing the player starts pursuit")
	game.player.position = ranger.home + Vector2(-500,0)
	var remembered: Vector2 = ranger.target
	await frames(4)
	check(ranger.target.is_equal_approx(remembered),"Losing sight preserves last seen position rather than tracking through cover")
	var recovery_impact: Vector2 = ranger.home + Vector2(0,120)
	NoiseManager.emit_noise(recovery_impact,256,NoiseManager.SourceType.THROW)
	check(not ranger.chasing and ranger.target.is_equal_approx(recovery_impact),"A heard stone interrupts pursuit once vision is broken")
	game.player.position = ranger.global_position + Vector2(2,0)
	await frames(20)
	check(not ranger.chasing and not ranger.distracted and not game.resetting,"Capture restores the forest checkpoint and resets the encounter")
	ranger.reset_patrol()
	ranger.active = true
	game.player.position = game.world.zones["forest"].global_position + Vector2(700,400)
	await frames(2)
	check(game.player.global_position.distance_to(game.world.zones["forest"].global_position+Vector2(700,400))<1.0,"Approach checkpoint places her at the clear throw spot")
	check(ranger.active and ranger.global_position.distance_to(ranger.home)<2.0,"The checkpoint leaves the ranger on his beat instead of jumping him back to his post")
	check(game.world.zones["forest"].get_node("ThrowTarget").visible,"Lit target marks where the first stone should land")
	check(game.checkpoint.position.is_equal_approx(game.player.position),"Checkpoint saves the safe throw position")
	game.advance_dialogue()
	await frames(2)
	game.player.get_node("PlayerAim").set_target(game.world.zones["forest"].global_position + Vector2(800,520))
	var impact: Vector2 = game.thrower._compute_landing()
	Input.action_press("throw")
	await frames(1)
	Input.action_release("throw")
	await frames(80)
	check(ranger.target.is_equal_approx(impact),"Q projectile impact reaches ranger through NoiseManager")
	for tick in range(900):
		if ranger.distracted: break
		await frames(1)
	check(ranger.distracted,"Ranger investigates the stone and opens the route")
	var destination: Vector2 = game.world.interactables["forest_exit"]["position"] + Vector2(-45,0)
	var route := NavigationServer2D.map_get_path(game.player.get_world_2d().navigation_map,game.player.global_position,destination,true)
	var next_point := 1
	for tick in range(700):
		if next_point >= route.size() or game.resetting or not game.dialogue.is_empty(): break
		var direction: Vector2 = route[next_point] - game.player.global_position
		if direction.length() < 16.0:
			next_point += 1
			continue
		for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
		if absf(direction.x)>6.0: Input.action_press("move_right" if direction.x>0 else "move_left")
		if absf(direction.y)>6.0: Input.action_press("move_down" if direction.y>0 else "move_up")
		await frames(1)
	for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
	check(game.player.global_position.distance_to(destination)<60.0 and not ranger.chasing and not game.resetting,"Player can walk the trail past the ranger while the stone has his attention")
	check(not game.entity.visible and not game.entity.active,"Entity is absent throughout the ranger encounter")
