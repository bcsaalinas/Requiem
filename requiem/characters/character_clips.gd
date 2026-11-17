class_name CharacterClips
extends RefCounted
## Cached loader for the character sheets exported by art-lab: one JSON next to each PNG.
## Clip names are the sheet's file stem (for example "girl_walk_lower"). A path such as
## "../player/girl_stand_lower.png" (as NPC sheets write it) resolves to its stem too.

const DIRECTORY := "res://assets/art/player/"

static var _cache := {}


static func stem(name: String) -> String:
	return name.get_file().get_basename().split(" ")[0]


## Returns {name, texture, hframes, frames, loop_ms, loop, sound_frames, projectile_frame, action_frame,
## hold_last_frame, lower, raw}; empty when the sheet does not exist.
static func get_clip(name: String) -> Dictionary:
	var key := stem(name)
	if _cache.has(key):
		return _cache[key]
	var json_path := DIRECTORY + key + ".json"
	var result := {}
	if FileAccess.file_exists(json_path):
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		var sheet: Dictionary = raw["sheet"]
		var frames: Array[Dictionary] = []
		for entry: Dictionary in raw.get("frames", []):
			frames.append({
				"ms": float(entry.get("ms", 100)),
				"anchors": entry.get("anchors", {}),
				"head_offset": _vector(entry.get("head_offset", [0, 0])),
				"upper_offset": _vector(entry.get("upper_offset", [0, 0])),
				"label": entry.get("label", ""),
			})
		result = {
			"name": key,
			"texture": load(DIRECTORY + String(sheet["file"])),
			"hframes": int(sheet["hframes"]),
			"frames": frames,
			"loop_ms": _number(raw.get("loop_ms"), 0.0),
			"loop": bool(raw.get("loop", true)),
			"sound_frames": PackedInt32Array(Array(raw.get("sound_frames", []), TYPE_INT, "", null)),
			"projectile_frame": int(raw.get("projectile_frame", -1)),
			"action_frame": int(raw.get("action_frame", -1)),
			"hold_last_frame": bool(raw.get("hold_last_frame", false)),
			"lower": stem(String(raw["lower"])) if raw.has("lower") and String(raw["lower"]) != "" else "",
			"speed_u_s": _number(raw.get("speed_u_s"), 0.0),
			"raw": raw,
		}
	_cache[key] = result
	return result


static func _number(value: Variant, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback


static func _vector(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
