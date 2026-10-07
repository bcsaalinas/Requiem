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
	at_interaction("bedroom_exit")
	check(game.zone=="hallway","Equipped player can enter hallway")
	game.player.position=Vector2(1770,340)
	game._tick_hallway(.01)
	check(game.hud.subtitle.text.contains("SPACE · Hold breath"),"First parent cue offers a brief breath prompt at the occupied door")
	game.player.position=Vector2(2110,485)
	game._tick_hallway(.01)
	check(game.hud.subtitle.text.contains("Rest here"),"Entering the refuge explains release and recovery")
	NoiseManager.emit_noise(game.player.position,224,NoiseManager.SourceType.BREATH)
	check(not game.resetting,"Full forced-gasp radius cannot reach either parent from the refuge center")
	game.player.position=Vector2(1930,340)
	NoiseManager.emit_noise(game.player.position,32,NoiseManager.SourceType.CROUCH)
	check(not game.resetting,"Existing held footsteps pass the parent listening zone")
	NoiseManager.emit_noise(game.player.position,96,NoiseManager.SourceType.FOOTSTEP)
	check(game.resetting,"Ordinary footsteps alert the parent")
	await frames(10)
	check(game.zone=="bedroom" and game.has_flashlight,"Parent reset returns to bedroom and retains equipment")
	check(game.breath.lung_percent==100 and not game.breath.is_locked,"Retry restores air and clears forced lock")
	at_interaction("bedroom_exit")
	# Real physics movement through a complete first exposure using unchanged inputs.
	game.player.position=Vector2(1830,340)
	Input.action_press("hold_breath")
	Input.action_press("move_right")
	await frames(145)
	Input.action_release("move_right")
	Input.action_release("hold_breath")
	check(game.zone=="hallway" and not game.resetting and game.player.position.x>2010,"Held movement physically traverses first parent crossing")
	await frames(5)
	at_interaction("hall_exit")
	check(game.zone=="forest" and game.stage=="sho","Forest begins the development stage")
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
	# Native mouse coordinates are unavailable in headless mode. Supply a physics-verified
	# aim fixture, then exercise the actual inherited windup, flight, impact and inventory.
	var query:=PhysicsRayQueryParameters2D.create(game.player.position,Vector2(5870,608),1)
	query.exclude=[game.player.get_rid()]
	var hit: Dictionary=game.player.get_world_2d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider==game.world.window_body,"Window collider intercepts a rock thrown from the porch")
	game.thrower._start_throw()
	game.thrower._pending_landing=hit.position+Vector2(0,4)
	check(game.thrower.rocks==2,"Beginning a real throw consumes one collected rock")
	await frames(70)
	check(game.window_broken,"Rock flight and impact break the sidelight")
	check(game.world.props.has("shards"),"Window impact creates the existing glass fragments")
	check(game.sequence=="reveal","Window impact starts the brief figure reveal")
	check(not game.world.window_body.get_child(1).visible,"Broken sidelight lets light through")
	await frames(150)
	check(game.sequence=="","Window reveal finishes without trapping interactions")
	at_interaction("window",Vector2(0,60))
	await frames(3)
	check(game.door_unlocked and not is_instance_valid(game.world.props["entry_collision"]),"Reaching through removes the front door collider")
	at_interaction("front_door",Vector2(0,60))
	check(game.player.position.y<680,"Unlocked front door permits entry")
	var altar_energy: float=game.world.landmarks["AltarLeftLight"].energy
	at_interaction("friend")
	check(not game.dialogue.is_empty(),"Friend dialogue precedes attack")
	var help_key:=InputEventKey.new()
	help_key.physical_keycode=KEY_H
	help_key.pressed=true
	game._input(help_key)
	check(get_tree().paused and game.hud.help_panel.visible,"Help pauses the tutorial")
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
	check(game.zone=="loop","Return doorway leads to the impossible room")
	check(not game.entity.visible and not game.entity.active,"Impossible room keeps the presence indirect")
	at_interaction("loop_end",Vector2(-45,0))
	check(game.complete and not game.entity.active,"Final doorway completes tutorial and stops encounter")
	game.queue_free()
	await frames(3)
	print("[Tutorial tests] ",checks-failures.size(),"/",checks," passed")
	get_tree().quit(0 if failures.is_empty() else 1)
