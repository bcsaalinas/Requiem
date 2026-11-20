extends Node
## Showcase build (tutorial/showcase.gd): night one in the Hacienda as the booth plays it.
var game: Node2D
var failures: Array[String] = []
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func frames(count: int) -> void:
	for i in range(count): await get_tree().physics_frame


func _ready() -> void:
	game = preload("res://tutorial/tutorial.tscn").instantiate()
	game.test_mode = true
	game.force_showcase = true
	game.start_zone = "mansion_ground"
	add_child(game)
	await frames(5)
	while not game.dialogue.is_empty():
		game.advance_dialogue()
	await frames(2)

	check(game.showcase and TranslationServer.get_locale().begins_with("es"), "The showcase plays in Spanish")
	check(GameState.total_altars == 3, "Night one asks for three altars")
	var lit := ["altar_2", "altar_3", "altar_5", "altar_6"].all(func(id: String) -> bool: return game.mansion_story.completed(id))
	var dark := ["altar_1", "altar_4", "altar_7"].all(func(id: String) -> bool: return not game.mansion_story.completed(id))
	check(lit and dark, "Rosa's altars are already lit; the three showcase altars are dark")
	check(not game.world.interactables.has("hearth_reminder") and game.world.interactables.has("fountain_dedication"),
		"Only the showcase notes are in the house")
	check(game.world.interactables.has("fountain_marigold")
		and game.world.interactables["fountain_marigold"]["node"].position.distance_to(Vector2(2000, 950)) < 1.0,
		"The marigold lies in its fixed showcase room")

	# The objective line and the petals point at the first thing to do.
	# Physics can catch up several steps in one frame headless: wait for a drawn frame too.
	await get_tree().process_frame
	await get_tree().process_frame
	check(game.hud.objective.visible and game.hud.objective.text == "Lee la dedicatoria.", "The objective reads the dedication first (%s)" % game.hud.objective.text)
	check(game.guide_petals.target.distance_to(game.world.interactables["fountain_dedication"]["position"]) < 1.0,
		"The petals lead to the dedication")
	check(game.translate_label("Take marigold") == "Tomar la flor de cempasúchil", "Prompts are translated in two parts")

	# The chapel opens after the fountain, not after the chapel's own altar.
	var chapel: Door = game.world.interactables["door_chapel"]["node"]
	check(chapel.locked, "The chapel is bolted before the fountain is prayed at")
	var fountain: Node = game.world.interactables["altar_1"]["node"]
	fountain.light_without_prayer()
	game.mansion_story.on_altar_completed(fountain)
	check(not chapel.locked, "Praying at the fountain unbolts the chapel")

	# Breath: one forced gasp is soft.
	check(game.breath.soft_gasps == 1, "The first forced gasp is a soft one")

	# A catch is a near miss the first time: she is shoved free and it walks away, deaf for a moment.
	game.mansion_grace = 0.01
	await frames(3)
	game.entity.global_position = game.player.global_position + Vector2(10, 0)
	game._caught()
	check(not game.resetting and not GameState.is_dead, "The first catch is a near miss, not a death")
	check(game.entity.is_resting(), "After a near miss the creature rests")
	var state_before: String = game.entity.get_state_name()
	NoiseManager.emit_noise(game.entity.global_position, 200, NoiseManager.SourceType.SPRINT)
	await frames(1)
	check(game.entity.get_state_name() == state_before and not game.entity.is_listening(), "For a moment it hears nothing at all")
	game._caught()
	check(game.resetting, "A second catch soon after is a death")

	TranslationServer.set_locale("en")
	print("[Showcase tests] %d/%d passed" % [checks - failures.size(), checks])
	for failure in failures: print("FAIL: " + failure)
	get_tree().quit(1 if failures.size() > 0 else 0)
