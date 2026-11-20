extends RefCounted

const SPRITES := preload("res://tutorial/offering_sprites.tres")
const NOTE := preload("res://assets/art/items/item_note.png")
const KEY := preload("res://assets/art/items/item_key.png")
const PETALS := preload("res://assets/art/ritual/ritual_petals_a.png")
const BURNER := preload("res://assets/art/ritual/ritual_copal_burner.png")
const BATTERY := preload("res://assets/art/items/item_battery.png")
const STONE := preload("res://assets/art/items/item_pebble_a.png")
const BEACON := preload("res://tutorial/hint_beacon.gd")
const Art := preload("res://tutorial/art.gd")
# The seven offering textures use the standard pickup beacon without separate glint sheets.
const GLINTS := {
	NOTE: preload("res://assets/art/items/item_note_glint.png"),
	BATTERY: preload("res://assets/art/items/item_battery_glint.png"),
	STONE: preload("res://assets/art/items/item_pebble_a_glint.png"),
}

const ALTARS := {
	"altar_1": {"item": "fountain_marigold", "clue": "fountain_dedication", "after": [], "words": "Inés, I leave you a marigold so your name is remembered."},
	"altar_2": {"item": "hearth_bread", "clue": "hearth_reminder", "after": ["altar_1"], "words": "For the bread you used to save for someone else."},
	"altar_3": {"item": "granary_thimble", "clue": "hearth_reminder", "after": ["altar_2"], "words": "For the hours you spent sewing, and what you hoped to make."},
	"altar_4": {"item": "chapel_rosary", "clue": "chapel_note", "after": ["altar_3"], "words": "Inés, may someone hear you this time."},
	"altar_5": {"item": "ancestors_portrait", "clue": "portrait_inscription", "after": ["altar_4"], "words": "For Rosa, who kept a place for you here."},
	"altar_6": {"item": "study_letter", "clue": "study_confession", "after": ["altar_4"], "words": "The door didn't close on its own. You deserved to be let out."},
	"altar_7": {"item": "tapanco_thread", "clue": "tapanco_note", "after": ["altar_5", "altar_6"], "words": "Inés, we remember who you were. Eli locked that door. It was never your fault."},
}

# Positions are local to each floor.
const NOTES := {
	"fountain_dedication": ["mansion_ground", Vector2(1048, 1104), "the dedication", "For Inés. She always asked us to leave a marigold when the fountain ran dry."],
	"hearth_reminder": ["mansion_ground", Vector2(400, 758), "the kitchen note", "Inés saved bread before she sat down to sew. Her thimble is in the granary chest. I left the spare key in the dining room trunk. — Rosa"],
	"chapel_note": ["mansion_ground", Vector2(1136, 352), "the chapel note", "Bring Inés's wooden rosary to the chapel altar and remember her hands at work."],
	"portrait_inscription": ["mansion_upper", Vector2(1056, 320), "the inscription", "Inés and her aunt Rosa, at the end of summer. Rosa wrote: You always had a place at my table."],
	"ancestors_letter": ["mansion_upper", Vector2(1248, 240), "Inés's letter", "Tía Rosa, when I finish this dress, I want to take it to the market myself. I marked the seams with my blue thread. — Inés"],
	"study_confession": ["mansion_upper", Vector2(1960, 736), "Eli's account", "I locked Inés in as a game. I heard her asking me to open it. I left with the key. I told everyone the door shut on its own. — Eli"],
	"tapanco_note": ["mansion_upper", Vector2(1080, 1504), "the sewing note", "The blue thread was her favorite. Say her name and tell the truth about the door. — Rosa"],
}

# Item names are also the pickup and placement prompt labels.
const ITEMS := {
	"fountain_marigold": ["marigold", "marigold", PETALS],
	"hearth_bread": ["plate of bread", "bread", BURNER],
	"granary_thimble": ["brass thimble", "thimble", BURNER],
	"chapel_rosary": ["wooden rosary", "rosary", KEY],
	"ancestors_portrait": ["family portrait", "portrait", NOTE],
	"study_letter": ["Eli's letter", "letter", NOTE],
	"tapanco_thread": ["blue thread", "thread", BURNER],
	"granary_key": ["granary key", "", KEY],
	"study_key": ["study key", "", KEY],
	"spare_battery_chapel": ["spare battery", "", BATTERY],
	"spare_battery_closet": ["spare battery", "", BATTERY],
	"spare_stones_ballroom": ["stones", "", STONE],
	"spare_stones_south_salon": ["stones", "", STONE],
}
# Each floor draws without replacement. Ground locations are reachable without
# either key. Upper locations are outside the Study and sewing room.
const GROUND_OFFERINGS := ["fountain_marigold", "hearth_bread", "chapel_rosary"]
const UPPER_OFFERINGS := ["ancestors_portrait", "study_letter", "tapanco_thread"]
const OFFERING_LABELS := {
	"fountain_marigold": "Marigold",
	"hearth_bread": "Bread",
	"granary_thimble": "Thimble",
	"chapel_rosary": "Rosary",
	"ancestors_portrait": "Portrait",
	"study_letter": "Letter",
	"tapanco_thread": "Thread",
}
const GROUND_SPOTS := [
	["the dining room west of the entrance", Vector2(256, 1552)],
	["the cellar between the dining room and the kitchen", Vector2(304, 1200)],
	["the music room east of the courtyard", Vector2(2000, 950)],
	["the ballroom in the northeast wing", Vector2(2064, 336)],
	["the library east of the chapel", Vector2(1552, 272)],
	["the hall of mirrors east of the entrance", Vector2(2016, 1552)],
]
const UPPER_SPOTS := [
	["the northwest guest room", Vector2(620, 730)],
	["the tea room at the south end of the west wing", Vector2(384, 1248)],
	["the picture gallery north of the stairs", Vector2(2096, 960)],
	["the middle guest room in the west wing", Vector2(336, 1056)],
	["the sitting room in the southwest wing", Vector2(488, 1512)],
	["the southeast bedroom", Vector2(1952, 1596)],
]
const GRANARY_CHEST_SPOTS := [Vector2(368, 224), Vector2(336, 168), Vector2(112, 196)]
const CHESTS := {
	"chest_dining_key": "granary_key",
	"chest_storage": "granary_thimble",
	"chest_gallery": "study_key",
	"chest_chapel": "spare_battery_chapel",
	"chest_closet": "spare_battery_closet",
	"chest_ballroom": "spare_stones_ballroom",
	"chest_south_salon": "spare_stones_south_salon",
}
const KEY_DESTINATIONS := {
	"granary_key": "Troje",
	"study_key": "Estudio",
}
const KEY_DIRECTIONS := {
	"granary_key": "The granary key opens the Troje. From the kitchen, head north past the granary altar.",
	"study_key": "The study key opens the Estudio. Look for its door on the north side of the picture gallery.",
}
const DOOR_LOCKS := {
	"door_altar3_troje": "granary_key",
	"door_troje_sacristia": "granary_key",
	"door_forbidden_balcony": "study_key",
	"door_forbidden_artgallery": "study_key",
	"door_closet_forbidden": "study_key",
	"door_chapel": "",
	"door_tapanco_north": "",
	"door_closet_tapanco": "",
	"door_tapanco_blancos": "",
}

var game
var read_notes: Dictionary = {}
var chest_displays: Dictionary = {}
var offering_locations: Dictionary = {}


func setup(owner_game: Node) -> void:
	game = owner_game
	for id: String in NOTES:
		var note: Array = NOTES[id]
		_add_prop(id, "Read " + note[2], note[0], note[1], NOTE)
	_scatter_offerings("mansion_ground", GROUND_OFFERINGS, GROUND_SPOTS)
	_scatter_offerings("mansion_upper", UPPER_OFFERINGS, UPPER_SPOTS)
	var granary_chest := _node("chest_storage")
	var chest_offset: Vector2 = game.world.interactables["chest_storage"]["position"] - granary_chest.global_position
	granary_chest.position = GRANARY_CHEST_SPOTS.pick_random()
	game.world.interactables["chest_storage"]["position"] = granary_chest.global_position + chest_offset
	for chest_id: String in CHESTS:
		var chest := _node(chest_id)
		var display := _sprite(_texture(CHESTS[chest_id]))
		chest.add_child(display)
		display.global_position = chest.get_loot_origin() + Vector2(0, -9)
		display.z_index = 44
		var unlit := CanvasItemMaterial.new()
		unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		display.material = unlit
		_add_beacon(display)
		display.hide()
		chest_displays[chest_id] = display
	for id: String in ALTARS:
		var altar = _node(id)
		var display := _sprite(_texture(ALTARS[id]["item"]))
		altar.add_child(display)
		display.position = Vector2(24, -28)
		display.hide()
		altar.configure_offering(display, _can_place_offering.bind(id))
	_sync_doors()


func _scatter_offerings(floor_id: String, ids: Array, spots: Array) -> void:
	var available := spots.duplicate()
	available.shuffle()
	for id: String in ids:
		var spot: Array = available.pop_back()
		offering_locations[id] = spot[0]
		_add_prop(id, "Take " + ITEMS[id][0], floor_id, spot[1], _texture(id))


func _node(id: String) -> Node2D:
	return game.world.interactables[id]["node"]


func _texture(id: String) -> Texture2D:
	var item: Array = ITEMS[id]
	if not String(item[1]).is_empty():
		var texture := SPRITES.get(item[1]) as Texture2D
		if texture != null:
			return texture
	return item[2]


## Chest loot and altar offerings: drawn at the same size as every pickup (Units.PICKUP_ART_SCALE).
func _sprite(texture: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * Units.PICKUP_ART_SCALE
	return sprite


## Notes and loose offerings are ordinary pickups: same size, glint, star and focus outline.
func _add_prop(id: String, label: String, floor_id: String, at: Vector2, texture: Texture2D) -> void:
	var prop := Art.new()
	prop.name = id
	prop.kind = "story_item"
	prop.item_texture = texture
	prop.item_glint = GLINTS.get(texture)
	game.world.zones[floor_id].get_node("Props").add_child(prop)
	prop.position = at
	game.world.interactables[id] = {"node": prop, "position": prop.global_position, "label": label}


func _add_beacon(sprite: Sprite2D) -> void:
	# The star keeps the size it has everywhere else, whatever the scale of the sprite it marks.
	var beacon := BEACON.new()
	beacon.scale = Vector2.ONE * Units.ART_SCALE / sprite.scale
	sprite.add_child(beacon)


func key_for_door(id: String) -> String:
	return DOOR_LOCKS.get(id, "")


func label(id: String) -> String:
	if CHESTS.has(id) and _node(id).is_open:
		return "Take " + ITEMS[CHESTS[id]][0]
	if ALTARS.has(id) and not _node(id).offering_placed:
		if _placement_blocker(id).is_empty():
			return "Place " + ITEMS[ALTARS[id]["item"]][0]
		return "Inspect the altar"
	var key := key_for_door(id)
	if not key.is_empty() and not _node(id).is_open:
		return ("Check " if _node(id).locked else "Open ") + KEY_DESTINATIONS[key]
	return ""


func interact(id: String) -> bool:
	if NOTES.has(id):
		read_notes[id] = true
		var text: String = NOTES[id][3]
		for altar: Dictionary in ALTARS.values():
			var item: String = altar["item"]
			if altar["clue"] == id and offering_locations.has(item) and not game.collected.has(item):
				text += "\nLook for the %s in %s." % [ITEMS[item][0], offering_locations[item]]
		game.say(text, 12.0)
		return true
	if ITEMS.has(id):
		_take_item(id)
		_node(id).hide()
		return true
	if CHESTS.has(id):
		var chest = _node(id)
		if not chest.is_open:
			chest.open(game.breath.is_holding)
			chest_displays[id].show()
			game.say("Inside: %s. Press E again to take it." % ITEMS[CHESTS[id]][0], 5.0)
		else:
			if _take_item(CHESTS[id]):
				chest_displays[id].hide()
				game.collected[id] = true
		return true
	if ALTARS.has(id):
		var altar = _node(id)
		if not altar.offering_placed:
			var blocker := _placement_blocker(id)
			if not blocker.is_empty():
				game.say(blocker, 5.0)
			else:
				altar.place_offering()
				game.hud.hide_offering(ALTARS[id]["item"])
				game.say("The offering is ready. Hold E to pray.")
		return true
	return false


func _take_item(id: String) -> bool:
	if id.begins_with("spare_stones_"):
		if game.thrower.rocks >= 3:
			game.say("I have enough stones. I can leave these here.")
			return false
		game.thrower.rocks = 3
		game.stone_hint_seen = true
	elif id.begins_with("spare_battery_"):
		game.batteries += 1
		game.hud.pulse_slot("battery")
		if game.has_flashlight and game.flashlight.battery_percent <= 0.0:
			game.insert_battery()
	game.collected[id] = true
	if OFFERING_LABELS.has(id):
		game.hud.show_offering(id, OFFERING_LABELS[id], _texture(id))
	game._player_visual("play_pickup")
	game.play_sound("pickup", game.player.global_position)
	game.say(KEY_DIRECTIONS.get(id, "Found " + ITEMS[id][0] + "."), 8.0)
	_sync_doors()
	return true


func _can_place_offering(id: String) -> bool:
	return _placement_blocker(id).is_empty()


func _placement_blocker(id: String) -> String:
	var altar: Dictionary = ALTARS[id]
	for prerequisite: String in altar["after"]:
		var previous = _node(prerequisite)
		if not previous.is_completed:
			return "I need to finish the " + previous.altar_name + " first."
	if not read_notes.has(altar["clue"]):
		return "I should read " + NOTES[altar["clue"]][2] + " before I leave anything."
	if not game.collected.has(altar["item"]):
		if offering_locations.has(altar["item"]):
			return "Look for the %s in %s." % [ITEMS[altar["item"]][0], offering_locations[altar["item"]]]
		return "I need to find the " + ITEMS[altar["item"]][0] + "."
	return ""


func completed(id: String) -> bool:
	return _node(id).is_completed


func _sync_doors() -> void:
	var upstairs_complete := completed("altar_5") and completed("altar_6")
	for id: String in DOOR_LOCKS:
		var door := _node(id) as Door
		var key: String = DOOR_LOCKS[id]
		if not key.is_empty():
			door.locked = not game.collected.has(key)
			door.locked_label = KEY_DESTINATIONS[key] + " is locked. It needs the " + ITEMS[key][0] + "."
		elif id == "door_chapel":
			door.locked = not completed("altar_4")
			door.locked_label = "The chapel bolt is sealed. There are other entrances."
			if door.locked and door.is_open:
				door.snap(false)
		else:
			door.locked = not upstairs_complete
			door.locked_label = "The sewing room opens after both upstairs dedications."


func on_altar_completed(altar: Node) -> String:
	_sync_doors()
	var seal := _node("mansion_main_porton").get_node("PrayerSeal") as Sprite2D
	if GameState.altars_completed >= GameState.total_altars:
		seal.frame = 2
	elif GameState.altars_completed >= 4:
		seal.frame = 1
	match String(altar.get_meta("interaction_id", "")):
		"altar_1":
			var fountain: AnimationPlayer = game.world.zones["mansion_ground"].get_node("PatioCentral/CanteraFountain/AnimationPlayer")
			fountain.play(&"running")
			game.world.landmarks["HearthRouteLight"].enabled = true
			return "A light came on by the kitchen door."
		"altar_2":
			return "Rosa left the granary key in the dining-room trunk."
		"altar_3":
			return "The chapel is next. I can reach it through the sacristy."
		"altar_4":
			game.world.landmarks["StairRouteLight"].enabled = true
			return "The chapel bolt opens. The way upstairs is clear."
		"altar_5", "altar_6":
			if completed("altar_5") and completed("altar_6"):
				return "The sewing-room bolt just opened."
	return "The offering is lit."
