class_name SoundLibrary
extends RefCounted
## Sound sets. A set is one folder under res://assets/audio/ (for example "entity/claws_walk");
## every file in it is a variation of the same sound. Asking for a set gives one stream that
## plays a different variation each time, never the same one twice in a row, at a slightly
## different pitch and level (audio/sound_settings.tres).
##
## Adding or removing files in a folder changes the set; no code names a file.
## A missing or empty set is silent: it gives null and warns once.

const ROOT := "res://assets/audio/"
const TYPES: Array[String] = ["wav", "ogg", "mp3"]

static var _sets := {}
static var _files := {}
static var _warned := {}


## The variations of a set, in file-name order. Empty when the folder is missing or empty.
static func files(set_id: String) -> Array[AudioStream]:
	if _files.has(set_id):
		return _files[set_id]
	var found: Array[AudioStream] = []
	var folder := ROOT + set_id
	var names := Array(ResourceLoader.list_directory(folder))
	names.sort()
	for file: String in names:
		if TYPES.has(file.get_extension().to_lower()):
			var stream := load(folder.path_join(file)) as AudioStream
			if stream != null:
				found.append(stream)
	_files[set_id] = found
	return found


## The set as one stream (null, with one warning, when it has no files).
static func stream(set_id: String) -> AudioStreamRandomizer:
	if not _sets.has(set_id):
		var variations := files(set_id)
		var settings := SoundSettings.current()
		var randomizer: AudioStreamRandomizer = null
		if not variations.is_empty():
			randomizer = AudioStreamRandomizer.new()
			randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
			randomizer.random_pitch = 1.0 + settings.set_pitch_range
			randomizer.random_volume_offset_db = settings.set_volume_range_db
			for variation in variations:
				randomizer.add_stream(-1, variation)
		_sets[set_id] = randomizer
	if _sets[set_id] == null and not _warned.has(set_id):
		_warned[set_id] = true
		push_warning("[SoundLibrary] sound set '%s' has no files (%s%s): it stays silent" % [set_id, ROOT, set_id])
	return _sets[set_id]


static func has_set(set_id: String) -> bool:
	return _sets[set_id] != null if _sets.has(set_id) else not files(set_id).is_empty()


## What the game adds to a set at playback, in dB (set_gain_db in sound_settings.tres).
static func gain_db(set_id: String) -> float:
	return float(SoundSettings.current().set_gain_db.get(set_id, 0.0))


## Forgets every set, so folders are read again (tests, and after files change).
static func clear() -> void:
	_sets.clear()
	_files.clear()
	_warned.clear()
