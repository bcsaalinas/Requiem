extends Node
var game: Node2D
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
	await frames(5)
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
	game.flashlight.battery_percent=100.0
	var door_a: ParentListener = game._parent_listeners()[0]
	game.player.position=door_a.global_position+Vector2(-150,48)
	game._tick_hallway(.01)
	check(game.hud.subtitle.text.contains("chair scrapes"),"Approaching the first occupied door plays a listening cue")
	check(game.hud.subtitle.text.contains("Hold my breath"),"The first door cue tells her to hold her breath past the doors")
	check(game.hud.breath_hint.visible,"The hold-breath key stays on screen in the hallway before any danger")
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
	check(game.hud.subtitle.text.contains("Rest here"),"Arriving out of breath in the refuge explains release and recovery")
	game.breath.lung_percent=100.0
	NoiseManager.emit_noise(refuge.global_position+Vector2(0,-60),224,NoiseManager.SourceType.BREATH)
	check(not game.resetting and not game.hall_warned,"Even a forced gasp inside the refuge light never reaches the parents")
	# Hearing is "the ring reaches the door edge", so the far side of the corridor is no free path.
	var far_side := door_a.global_position+Vector2(0,80)
	NoiseManager.emit_noise(far_side,32,NoiseManager.SourceType.CROUCH)
	check(not game.hall_warned,"Held footsteps pass the door on the far side of the corridor")
	NoiseManager.emit_noise(far_side,96,NoiseManager.SourceType.FOOTSTEP)
	check(game.hall_warned and not game.resetting,"The first footstep a parent hears is a warning, not a failure")
	check(game.hud.alert.visible and game.hud.alert.get_node("Title").text.contains("SPACE"),"The warning puts HOLD SPACE in the middle of the screen")
	check(game.heard_flash._edges.size()==1,"The door edge that heard her flashes")
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
	check(game.hud.breath_hint.visible,"The key hint stays until both doors are behind her")
	await frames(5)
	# Zone doors are real doors: E opens them, walking into the doorway goes through.
	var back_door: Door = game.world.interactables["hall_exit"]["node"]
	at_interaction("hall_exit",Vector2(-36,16))
	check(back_door.is_open,"The back door opens before the player can leave")
	game._tick_hallway(.01)
	check(game.hall_lesson_done and not game.hud.breath_hint.visible,"Past both doors the lesson ends and the key hint goes")
	await frames(4)
	check(game.zone=="forest" and game.stage=="sho","Walking through the open back door begins the forest stage")
	check(not back_door.is_open,"The back door is shut behind the player")
	check(not game.entity.visible and not game.entity.active,"Forest uses indirect presence without an invisible active capture entity")
	NoiseManager.emit_noise(Vector2(3580,350),32,NoiseManager.SourceType.CROUCH)
	check(game.ambient_reply_cooldown==0,"Held movement does not provoke the distant forest response")
	NoiseManager.emit_noise(Vector2(3580,350),96,NoiseManager.SourceType.FOOTSTEP)
	check(game.ambient_reply_cooldown>0 and not game.resetting,"Audible footsteps receive an environmental answer without an unfair unseen capture")
	at_interaction("forest_rocks")
	check(game.thrower.rocks==3,"Forest rock pile fills finite inventory")
	game.entity.active=false
	game.encounter_grace=999
	at_interaction("forest_exit")
	check(game.zone=="house" and game.stage=="ten","House begins the turn")
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
	check(game.sequence=="reveal","Window impact starts the brief figure reveal")
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
	await frames(230)
	check(game.attack_finished and game.world.props["friend"].fallen,"Attack leaves friend on ground")
	check(game.player.process_mode!=Node.PROCESS_MODE_DISABLED,"Story releases player input")
	check(game.stage=="ketsu","Aftermath starts the integration stage")
	check(game.world.landmarks["AltarLeftLight"].energy<altar_energy and game.world.landmarks["HouseRecoveryLight"].energy>game.world.landmarks["AltarLeftLight"].energy,"Aftermath dims the dangerous altar while the recovery lamp stays bright")
	game.request_reset("test retry")
	await frames(10)
	check(game.attack_finished and game.friend_met and game.world.props["friend"].fallen,"House retry preserves completed story")
	check(game.world.landmarks["AltarLeftLight"].energy<altar_energy,"House retry preserves the changed lighting")
	at_interaction("friend")
	check(game.dialogue.is_empty(),"Completed dialogue cannot replay")
	at_interaction("front_door",Vector2(0,-55))
	await frames(4)
	check(game.zone=="loop","Return doorway leads to the impossible room")
	check(not game.entity.visible and not game.entity.active,"Impossible room keeps the presence indirect")
	at_interaction("loop_end",Vector2(-45,0))
	check(game.complete and not game.entity.active,"Final doorway completes tutorial and stops encounter")
	game.queue_free()
	await frames(3)
	print("[Tutorial tests] ",checks-failures.size(),"/",checks," passed")
	# Let the audio mixer release stopped playbacks after scene teardown.
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
