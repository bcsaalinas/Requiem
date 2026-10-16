@tool
extends Node

# McpAssets — editor-time project asset queries (mode ③: no game round-trip).
#
# The bridge calls these methods directly (same pattern as ErrorCollector /
# collector_status / list_tools): the call stays entirely in the editor process,
# results return over the local TCP bridge, and the debug protocol / running
# game are never involved. So these tools work WITHOUT Play.
#
# Data source: EditorInterface.get_resource_filesystem() — Godot's in-memory
# cache of the project's res:// tree. Scanning hundreds to
# thousands of files is millisecond-scale.

# List res:// resources, optionally filtered by type and/or path substring
# (case-insensitive). Returns [{path, type, uid}].
#
# type_filter matches the resource's imported type name as a substring, so
# "texture" catches CompressedTexture2D / ImageTexture / AtlasTexture, "audio"
# catches AudioStreamOggVorbis / AudioStreamWAV, etc. AI doesn't need to know
# the exact class names.
const _TEMP_KEEP := 20  # rolling window: keep the N most recent mcp_* temp files
var _img_counter := 0  # monotonic id for get_image_png temp files


# Read a texture at a res:// path, downscale, save as PNG under user://, return
# its absolute path. The TS server reads the file and base64->image content
# (same pattern as screenshot). Mode ③: editor-time, no game round-trip.
# @tool hardening: typed casts (Texture2D/Image), no enum-returning methods
# (get_format etc. — see pitfalls #11/#12).
func get_image_png(path: String, max_size: int) -> Dictionary:
	var res = load(path)
	if res == null:
		return {"error": "could not load resource: %s" % path}
	var tex: Texture2D = res
	if tex == null:
		return {"error": "not a Texture2D: %s (got %s)" % [path, str(res.get_class())]}
	var img: Image = tex.get_image()
	if img == null:
		return {"error": "no image (compressed/GPU-only texture? get_image() returned null)"}
	if img.get_width() > max_size:
		var ratio := float(max_size) / float(img.get_width())
		img.resize(max_size, maxi(1, int(img.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	_img_counter += 1
	var rel := "user://mcp_img_%d.png" % _img_counter
	var err := img.save_png(rel)
	if err != OK:
		return {"error": "save_png failed (err=%d)" % err}
	_prune_temp("mcp_img_", ".png")
	return {"path": ProjectSettings.globalize_path(rel)}


# Slice a sprite sheet PNG into a SpriteFrames resource (.tres). Mode 'auto'
# detects frame bounds via transparent-gap projection (no cols/rows needed);
# 'grid' uses uniform cols×rows. Each row → one animation. Returns {path,
# animations, frames_per_anim, frame_size}. Mode ③, editor-time.
# @tool hardening: typed Image/SpriteFrames/ImageTexture, no enum returns.
func slice_sprite_sheet(path: String, mode: String, cols: int, rows: int, fps: float, out_path: String, atlas_path: String) -> Dictionary:
	if out_path.length() == 0:
		out_path = path + ".frames.tres"
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return {"error": "could not load source PNG: %s" % path}
	if mode == "atlas":
		# ASE-style atlas JSON: frameTags give animation NAMES + exact frame
		# coords (no empty frames, unlike uniform grid). Closes ASE -> Godot.
		return _slice_atlas(img, atlas_path, fps, out_path)
	var col_bounds: Array = []
	var row_bounds: Array = []
	if mode == "grid":
		if cols < 1 or rows < 1:
			return {"error": "grid mode needs cols>=1 and rows>=1"}
		col_bounds = _grid_bounds(img.get_width(), cols)
		row_bounds = _grid_bounds(img.get_height(), rows)
	else:
		var counts: Dictionary = _detect_counts(img)
		var cc := int(counts["cols"])
		var rc := int(counts["rows"])
		if cc < 1 or rc < 1:
			return {"error": "no frames detected (fully transparent image?)"}
		col_bounds = _grid_bounds(img.get_width(), cc)
		row_bounds = _grid_bounds(img.get_height(), rc)
	if col_bounds.is_empty() or row_bounds.is_empty():
		return {"error": "no frames detected (fully transparent, or no transparent gaps between frames?)"}
	var frames := SpriteFrames.new()
	var anim_names: Array = []
	if row_bounds.size() == 1:
		anim_names = ["default"]  # SpriteFrames.new() already has "default"
		frames.set_animation_speed("default", fps)
	else:
		frames.remove_animation("default")
		for ri in range(row_bounds.size()):
			var anim_name := "anim_%d" % ri
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, fps)
			anim_names.append(anim_name)
	for ri in range(row_bounds.size()):
		var anim := String(anim_names[ri])
		for ci in range(col_bounds.size()):
			var rect := Rect2(
				float(col_bounds[ci][0]), float(row_bounds[ri][0]),
				float(col_bounds[ci][1] - col_bounds[ci][0]),
				float(row_bounds[ri][1] - row_bounds[ri][0]))
			var sub: Image = img.get_region(rect)
			frames.add_frame(anim, ImageTexture.create_from_image(sub), 1.0)
	var err := ResourceSaver.save(frames, out_path)
	if err != OK:
		return {"error": "ResourceSaver.save failed (err=%d)" % err}
	return {
		"path": out_path,
		"animations": anim_names,
		"frames_per_anim": col_bounds.size(),
		"frame_size": [col_bounds[0][1] - col_bounds[0][0], row_bounds[0][1] - row_bounds[0][0]],
	}


# ASE-style atlas mode: read a JSON atlas (ASE spritesheet_export output),
# use meta.frameTags for animation NAMES + each frame's EXACT {x,y,w,h} from
# the `frames` array. from/to are global indices INTO that array, so we read
# the precise coords per frame directly — a true atlas slice, robust to tags
# of differing frame counts (e.g. walk=6, attack=4, roll=5 in one sheet).
# Closes ASE -> Godot: ASE tags become Godot SpriteFrames animation names.
# @tool hardening: `frames` is an Array (indexing is safe — proven in _walk);
# per-frame coords via Dictionary.get() single-key (safe per pitfalls #13,
# which only trips values()/keys()/[]indexing, NOT get()).
func _slice_atlas(img: Image, atlas_path: String, fps: float, out_path: String) -> Dictionary:
	if atlas_path.length() == 0:
		return {"error": "atlas mode needs atlas_path (JSON from ASE export)"}
	var abs_path := ProjectSettings.globalize_path(atlas_path)
	var f = FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return {"error": "could not open atlas: %s (abs=%s)" % [atlas_path, abs_path]}
	var txt = f.get_as_text()
	f.close()
	var atlas = JSON.parse_string(txt)
	if typeof(atlas) != TYPE_DICTIONARY:
		return {"error": "parse failed type=%d txt_len=%d" % [typeof(atlas), txt.length()]}
	var frame_tags: Array = atlas.get("meta", {}).get("frameTags", [])
	var frames_arr: Array = atlas.get("frames", [])
	if frame_tags.is_empty():
		return {"error": "atlas JSON has no frameTags"}
	if frames_arr.is_empty():
		return {"error": "atlas JSON has no frames"}
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var anim_names: Array = []
	var frame_size := [0, 0]
	var ti := 0
	while ti < frame_tags.size():
		var tag = frame_tags[ti]
		var anim_name := String(tag.get("name", ""))
		var from := int(tag.get("from", 0))
		var to := int(tag.get("to", -1))
		if anim_name.length() > 0 and to >= from:
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, fps)
			anim_names.append(anim_name)
			var idx := from
			while idx <= to:
				# from/to are global indices into the frames array; clamp so a
				# malformed tag (to >= frames_arr.size()) can't read OOB.
				if idx < 0 or idx >= frames_arr.size():
					break
				var fd = frames_arr[idx]
				var fr: Dictionary = fd.get("frame", {})
				var fx := int(fr.get("x", 0))
				var fy := int(fr.get("y", 0))
				var fwf := int(fr.get("w", 0))
				var fhf := int(fr.get("h", 0))
				if frame_size[0] == 0 and fwf > 0:
					frame_size = [fwf, fhf]
				var rect := Rect2(float(fx), float(fy), float(fwf), float(fhf))
				var sub: Image = img.get_region(rect)
				frames.add_frame(anim_name, ImageTexture.create_from_image(sub), 1.0)
				idx += 1
		ti += 1
	if anim_names.is_empty():
		return {"error": "atlas JSON has no frameTags"}
	var err := ResourceSaver.save(frames, out_path)
	if err != OK:
		return {"error": "ResourceSaver.save failed (err=%d)" % err}
	return {
		"path": out_path,
		"animations": anim_names,
		"frames_per_anim": -1,  # per-tag (atlas knows exact counts); see animations
		"frame_size": frame_size,
	}


# Describe a SpriteFrames resource: animations + frame_count + fps + loop_mode
# + frame_size per animation. Pairs with slice_sprite_sheet (verify the slice)
# and any hand-authored SpriteFrames. Mode ③, editor-time.
# @tool hardening: typed SpriteFrames/Texture2D, while loop (not for over the
# PackedStringArray). loop_mode via int(get_animation_loop_mode()) — enum→int
# is safe per pitfalls #11 (only String/StringName returns trip; int is fine).
func describe_sprite(path: String) -> Dictionary:
	# CACHE_MODE_IGNORE: slice_sprite_sheet may have JUST overwritten this .tres
	# in the same editor session; plain load() would return the stale cached
	# version. Force a fresh read from disk.
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		return {"error": "could not load resource: %s" % path}
	var frames: SpriteFrames = res
	if frames == null:
		return {"error": "not a SpriteFrames: %s (got %s)" % [path, str(res.get_class())]}
	var names = frames.get_animation_names()  # PackedStringArray
	var anims: Array = []
	var i := 0
	while i < names.size():
		var anim := str(names[i])
		var fc := frames.get_frame_count(anim)
		var fps := frames.get_animation_speed(anim)
		var frame_size := [0, 0]
		if fc > 0:
			var tex: Texture2D = frames.get_frame_texture(anim, 0)
			if tex != null:
				frame_size = [tex.get_width(), tex.get_height()]
		var lm := int(frames.get_animation_loop_mode(anim))
		var loop_mode_str := "none" if lm == 0 else ("linear" if lm == 1 else ("pingpong" if lm == 2 else "unknown"))
		anims.append({"name": anim, "fps": fps, "frame_count": fc, "loop_mode": loop_mode_str, "frame_size": frame_size})
		i += 1
	return {"animations": anims}


# Refresh the editor's project filesystem (mode ③). Call this AFTER writing/
# modifying files on disk under res:// so the editor picks them up: new files
# get discovered + imported + assigned a uid://; modified .png get re-imported;
# modified .tres/.tscn get their cached version refreshed in place (scan
# triggers reload_from_file on mtime change). The main "resync disk -> editor"
# action; covers most cases EXCEPT reloading an already-open scene (use
# reload_scene for that). scan is threaded (non-blocking) — may not be finished
# when this returns, so a follow-up list_assets may need a moment.
# @tool hardening: scan/scan_sources return void (no String/enum return risk).
func refresh_filesystem(mode: String) -> Dictionary:
	var fs = EditorInterface.get_resource_filesystem()
	if mode == "changes":
		fs.scan_sources()
	else:
		fs.scan()
	return {"status": "scan started", "mode": mode}


# Reload an already-open scene from disk (mode ③). This is the ONE case
# refresh_filesystem can't handle: scan only refreshes the PackedScene CACHE,
# not the live Node-tree instance open in the editor. reload_scene_from_path
# uses CACHE_MODE_REPLACE + replace_state internally, so it reads the new
# version directly — no need to refresh_filesystem first. If the scene isn't
# open, just opens it. Discards unsaved edits to that scene (expected: the AI
# changed the file on disk).
func reload_scene(path: String) -> Dictionary:
	if path in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(path)
		return {"action": "reloaded", "path": path}
	EditorInterface.open_scene_from_path(path)
	return {"action": "opened", "path": path}


# Force the editor to re-read a single resource from disk (mode ③). A lighter,
# targeted alternative to refresh_filesystem when only one .tres/.res changed.
# load with CACHE_MODE_REPLACE reads the new version and copy_from's it into
# the cached Ref (same mechanism reload_scene uses internally), so existing
# references see the new content. For .png/.wav CONTENT changes use
# refresh_filesystem (this does not re-run the importer — see pitfalls #15).
func reload_resource(path: String) -> Dictionary:
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if res == null:
		return {"error": "could not load resource: %s" % path}
	return {"action": "reloaded", "path": path, "type": str(res.get_class())}


# Reload an editor plugin (mode ③) — equivalent to toggling it off then on in
# Project Settings -> Plugins. Use after editing the plugin's .gd code so the
# new code takes effect. name defaults to "godot-mcp".
# DEADLOCK TRAP: reloading THIS plugin via set_plugin_enabled(false) immediately
# runs _exit_tree -> frees mcp_assets + bridge, so the following (true) line
# never executes (the call stack is torn down). Fix: call_deferred on the editor
# singleton EditorInterface — deferred calls survive the plugin's destruction
# and run after this frame. Reloading godot-mcp itself drops the MCP connection
# (bridge is rebuilt) -> the AI must /mcp reconnect afterward.
func reload_plugin(name: String) -> Dictionary:
	var pname := name if name.length() > 0 else "godot-mcp"
	EditorInterface.call_deferred("set_plugin_enabled", pname, false)
	EditorInterface.call_deferred("set_plugin_enabled", pname, true)
	return {
		"status": "reload scheduled",
		"plugin": pname,
		"note": "reloading this plugin drops the MCP connection -> /mcp reconnect required",
	}


# Describe an audio stream's metadata: length / mono + format-specific (WAV:
# mix_rate / stereo / format / loop). Mode ③, editor-time.
# @tool hardening: typed AudioStreamWAV cast, int() wraps on enum returns
# (format/loop_mode). Ogg/MP3 don't bind mix_rate/stereo/format getters
# those fields are WAV-only.
func describe_audio(path: String) -> Dictionary:
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		return {"error": "could not load resource: %s" % path}
	var stream = res
	var cls := str(res.get_class())
	var info := {
		"path": path,
		"class": cls,
		"length": float(stream.get_length()),
		"monophonic": bool(stream.is_monophonic()),
	}
	if cls == "AudioStreamWAV":
		var wav: AudioStreamWAV = res
		info["mix_rate"] = int(wav.get_mix_rate())
		info["stereo"] = bool(wav.is_stereo())
		info["format"] = _wav_format_name(int(wav.get_format()))
		var lm := int(wav.get_loop_mode())
		info["loop_mode"] = "none" if lm == 0 else ("forward" if lm == 1 else ("pingpong" if lm == 2 else "unknown"))
		if lm != 0:
			info["loop_begin"] = int(wav.get_loop_begin())
			info["loop_end"] = int(wav.get_loop_end())
	return info


# AudioStreamWAV format enum → name. Numeric match (avoids @tool enum-constant
# fuss); order per audio_stream_wav.h: FORMAT_8_BITS=0/16_BITS=1/IMA_ADPCM=2/QOA=3.
func _wav_format_name(f: int) -> String:
	match f:
		0: return "8_bits"
		1: return "16_bits"
		2: return "ima_adpcm"
		3: return "qoa"
		_: return "unknown(%d)" % f


# Get audio PCM as a downsampled waveform PNG (AI can SEE the waveform via
# Vision, like get_image_png). Mixes the full stream via instantiate_playback +
# mix_audio (the universal PCM path — works for WAV/Ogg/MP3),
# downsamples to a min/max envelope, draws a waveform image, saves PNG under
# user://, returns path + stats. Mode ③, editor-time.
# @tool hardening: typed AudioStreamPlayback/Image/PackedVector2Array, while
# loops, float()/int() wraps on numeric returns.
func get_audio_pcm(path: String, width: int) -> Dictionary:
	var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		return {"error": "could not load resource: %s" % path}
	var stream = res
	var length: float = float(stream.get_length())
	if length <= 0.0:
		return {"error": "stream has no finite length (infinite/unknown) — can't mix"}
	var pb: AudioStreamPlayback = stream.instantiate_playback()
	if pb == null:
		return {"error": "could not instantiate playback"}
	pb.start(0.0)
	var mix_rate := int(AudioServer.get_mix_rate())
	var frames := int(length * float(mix_rate))
	var data: PackedVector2Array = pb.mix_audio(1.0, frames)
	var w := width if width > 0 else 800
	if w > 2000:
		w = 2000
	var env := _pcm_envelope(data, w)
	var img: Image = Image.create(w, 200, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.12, 1.0))
	var mid := 100
	var col := Color(0.3, 0.9, 0.4, 1.0)
	var xi := 0
	while xi < w:
		var lo: float = float(env[xi * 2])
		var hi: float = float(env[xi * 2 + 1])
		var y_top: int = mid - int(hi * float(mid))
		var y_bot: int = mid - int(lo * float(mid))
		if y_top > y_bot:
			var t := y_top
			y_top = y_bot
			y_bot = t
		var yi := y_top
		while yi <= y_bot:
			if yi >= 0 and yi < 200:
				img.set_pixel(xi, yi, col)
			yi += 1
		xi += 1
	_img_counter += 1
	var rel := "user://mcp_audio_%d.png" % _img_counter
	var err := img.save_png(rel)
	if err != OK:
		return {"error": "save_png failed (err=%d)" % err}
	_prune_temp("mcp_audio_", ".png")
	return {
		"path": ProjectSettings.globalize_path(rel),
		"source": path,
		"length": length,
		"frames": frames,
		"mix_rate": mix_rate,
		"sample_count": data.size(),
		"width": w,
	}


# Downsample PCM (PackedVector2Array of stereo frames) to w min/max pairs (each
# 0..1 amplitude). Left channel only (mono envelope suffices for visualization).
func _pcm_envelope(data: PackedVector2Array, w: int) -> Array:
	var env: Array = []
	env.resize(w * 2)
	var n := data.size()
	var ci := 0
	while ci < w:
		var lo := 1.0
		var hi := 0.0
		if n > 0:
			var chunk := n / w
			if chunk < 1:
				chunk = 1
			var s := ci * chunk
			var e := s + chunk
			if e > n:
				e = n
			var si := s
			while si < e:
				var v: float = abs(float(data[si].x))
				if v < lo:
					lo = v
				if v > hi:
					hi = v
				si += 1
		env[ci * 2] = lo
		env[ci * 2 + 1] = hi
		ci += 1
	return env


# Rolling cleanup: keep only the N most recent user://mcp_<prefix>*<ext> files,
# delete the oldest. Called after each temp file is written (get_image_png /
# get_audio_pcm) so temp files never accumulate unbounded.
# @tool hardening: typed DirAccess, Array of [name, mtime] (not Dict — pitfalls #13).
func _prune_temp(prefix: String, ext: String) -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return
	var files: Array = []  # [name, mtime] pairs (Array indexed, not Dict)
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with(prefix) and fname.ends_with(ext):
			files.append([fname, int(dir.get_modified_time(fname))])
		fname = dir.get_next()
	dir.list_dir_end()
	if files.size() <= _TEMP_KEEP:
		return
	# bubble sort by mtime ascending (oldest first)
	var i := 0
	while i < files.size():
		var j := i + 1
		while j < files.size():
			if int(files[j][1]) < int(files[i][1]):
				var tmp = files[i]
				files[i] = files[j]
				files[j] = tmp
			j += 1
		i += 1
	var to_delete := files.size() - _TEMP_KEEP
	var k := 0
	while k < to_delete:
		dir.remove(String(files[k][0]))
		k += 1


# Clean ALL user://mcp_* temp files (screenshots + image PNGs + audio waveforms).
# Returns {deleted, deleted_count, kept}. The on-demand counterpart to the
# automatic _prune_temp rolling window. Mode ③, editor-time.
func clean_temp() -> Dictionary:
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return {"error": "could not open user://"}
	var deleted: Array = []
	var kept: Array = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("mcp_") and (fname.ends_with(".jpg") or fname.ends_with(".png")):
			if dir.remove(fname) == OK:
				deleted.append(fname)
			else:
				kept.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return {"deleted": deleted, "deleted_count": deleted.size(), "kept": kept}


# Launch the game (Play). Starts a fresh game SUBPROCESS (OS::create_instance,
# editor_run.cpp:182) that reads .gd from disk — so new code takes effect with
# NO build step (GDScript has no build; the subprocess always reads the latest
# files). If a game is already running, stop it first: the running process has
# the old code in memory, only a new subprocess picks up .gd changes.
# Mode ③, editor-time. mode: "main" (default) / "current" / "custom".
# ⚠️ subprocess takes ~1s to connect its debugger session — caller should
# ping_game to confirm before eval/screenshot/get_console_output.
func play_scene(mode: String, scene_path: String) -> Dictionary:
	var was_playing := EditorInterface.is_playing_scene()
	# CRASH TRAP (pitfalls #22): EditorInterface.stop_playing_scene / play_*
	# mutate the editor's SceneTree (hide bottom panel, close floating Window,
	# remove embedded process). Calling them SYNCHRONOUSLY from bridge._process
	# frees nodes while the main loop is iterating → use-after-free → editor
	# SIGSEGV (whole editor process dies). Same trap class as reload_plugin
	# (line 274). Fix: call_deferred — runs after this frame, outside the
	# _process iteration. Deferred queue is FIFO, so stop runs before play.
	if was_playing:
		EditorInterface.call_deferred("stop_playing_scene")
	match mode:
		"current":
			EditorInterface.call_deferred("play_current_scene")
		"custom":
			if scene_path.length() == 0:
				return {"error": "mode='custom' requires scene_path"}
			EditorInterface.call_deferred("play_custom_scene", scene_path)
		_:
			# "main" (default); unknown modes fall back to main scene.
			EditorInterface.call_deferred("play_main_scene")
	return {
		"status": "playing",
		"mode": "current" if mode == "current" else ("custom" if mode == "custom" else "main"),
		"scene_path": scene_path if mode == "custom" else "",
		"was_restarted": was_playing,
		"note": "game subprocess launched; takes ~1s to connect debugger — ping_game to confirm before eval/screenshot/get_console_output",
	}


# Stop the running game (kills the subprocess via OS::kill). No-op if not playing.
func stop_scene() -> Dictionary:
	var was_playing := EditorInterface.is_playing_scene()
	# CRASH TRAP (pitfalls #22): see play_scene above — must call_deferred, else
	# editor SIGSEGV from SceneTree mutation during bridge._process iteration.
	if was_playing:
		EditorInterface.call_deferred("stop_playing_scene")
	return {"status": "stopping_scheduled" if was_playing else "not_playing", "was_playing": was_playing, "note": "stop deferred to next frame; poll get_play_status to confirm (~1 frame)" if was_playing else ""}


# Query game play status.
func get_play_status() -> Dictionary:
	return {
		"is_playing": EditorInterface.is_playing_scene(),
		"scene_path": EditorInterface.get_playing_scene(),
	}


# Uniform grid bounds: [[0,step],[step,2step],...]. Last frame may be shorter
# if size isn't evenly divisible — acceptable for MVP.
func _grid_bounds(size: int, count: int) -> Array:
	var step := int(size / count)
	var bounds: Array = []
	var i := 0
	while i < count:
		bounds.append([i * step, (i + 1) * step])
		i += 1
	return bounds


# Detect frame COUNTS via transparent-gap projection: for each row/column, is
# there any non-transparent pixel? Count continuous non-transparent runs = frame
# count (cols) / animation row count (rows). The caller then slices a UNIFORM
# grid from these counts — better for SpriteFrames than tight per-frame bounds
# (which give non-uniform frame sizes that look bad as animation frames).
func _detect_counts(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var row_has: Array = []
	var col_has: Array = []
	var y := 0
	while y < h:
		var has := false
		var x := 0
		while x < w:
			if img.get_pixel(x, y).a > 0.01:
				has = true
				break
			x += 1
		row_has.append(has)
		y += 1
	var xi := 0
	while xi < w:
		var hasc := false
		var yi := 0
		while yi < h:
			if img.get_pixel(xi, yi).a > 0.01:
				hasc = true
				break
			yi += 1
		col_has.append(hasc)
		xi += 1
	return {"rows": _count_runs(row_has), "cols": _count_runs(col_has)}


# Count continuous runs of true in a bool array.
func _count_runs(arr: Array) -> int:
	var count := 0
	var i := 0
	while i < arr.size():
		if bool(arr[i]):
			count += 1
			while i < arr.size() and bool(arr[i]):
				i += 1
		else:
			i += 1
	return count


func list_assets(type_filter: String, path_filter: String) -> Array:
	var fs = EditorInterface.get_resource_filesystem()
	var root = fs.get_filesystem()  # EditorFileSystemDirectory at res://
	var out: Array = []
	_walk(root, type_filter.to_lower(), path_filter.to_lower(), out)
	return out


# Find which scenes/resources reference a given resource (reverse dependency
# lookup). Scans all res:// files via EditorFileSystem, calls
# ResourceLoader.get_dependencies on each, returns owners referencing target.
# Mode ③, editor-time. @tool hardening: typed EditorFileSystemDirectory, while
# loops (not for over PackedStringArray), str() wraps on string returns.
# Answer "where is this asset used?" before delete/rename, or trace deps.
func find_references(target_path: String) -> Dictionary:
	var target_norm := _normalize_res_path(target_path)
	var fs = EditorInterface.get_resource_filesystem()
	var root = fs.get_filesystem()
	var owners: Array = []
	_find_refs_walk(root, target_norm, owners)
	return {"target": target_path, "referenced_by": owners, "count": owners.size()}


func _find_refs_walk(d, target: String, owners: Array) -> void:
	var dir: EditorFileSystemDirectory = d
	var fc: int = dir.get_file_count()
	var i: int = 0
	while i < fc:
		var p := str(dir.get_file_path(i))
		# get_dependencies works on any res:// path (returns [] for assets with
		# no deps, e.g. imported .png). PackedStringArray indexed via while loop.
		var deps: PackedStringArray = ResourceLoader.get_dependencies(p)
		var di: int = 0
		while di < deps.size():
			if _normalize_res_path(str(deps[di])) == target:
				owners.append(p)
				break  # one reference per owner is enough
			di += 1
		i += 1
	var sc: int = dir.get_subdir_count()
	var j: int = 0
	while j < sc:
		_find_refs_walk(dir.get_subdir(j), target, owners)
		j += 1


# Normalize a resource path for matching: uid:// -> res:// (via ResourceUID),
# so a dep stored as uid matches a target given as res:// path.
func _normalize_res_path(p: String) -> String:
	var s := p
	if s.begins_with("uid://"):
		s = ResourceUID.uid_to_path(s)
	return s


func _walk(d, tf: String, pf: String, out: Array) -> void:
	var dir: EditorFileSystemDirectory = d
	var fc: int = dir.get_file_count()
	var i: int = 0
	while i < fc:
		var p := str(dir.get_file_path(i))
		var t := str(dir.get_file_type(i))
		var type_ok := tf.length() == 0 or t.to_lower().find(tf) != -1
		var path_ok := pf.length() == 0 or p.to_lower().find(pf) != -1
		if type_ok and path_ok:
			# uid via ResourceUID.path_to_uid (static, GDScript-bound) — NOT
			# dir.get_file_uid, which exists in C++ but was never bound to GDScript
			# (ClassDB binds get_file_count/path/type but NOT get_file_uid). That
			# missing binding is why every earlier attempt silently failed.
			var uid_text := ResourceUID.path_to_uid(p)
			out.append({"path": p, "type": t, "uid": uid_text})
		i += 1
	var sc: int = dir.get_subdir_count()
	var j: int = 0
	while j < sc:
		_walk(dir.get_subdir(j), tf, pf, out)
		j += 1
