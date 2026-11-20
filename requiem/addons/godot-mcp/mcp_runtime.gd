extends Node

# In-game runtime for the "mcp:" capture namespace.
#
# Registers a message capture with the engine debugger so the editor-side
# EditorDebuggerPlugin (addons/godot-mcp/mcp_debugger.gd) can talk to the
# running game over Godot's built-in debug protocol. This is "approach B"
# — used for the custom mcp:* protocol (ping/pong and
# screenshot). The built-in scene:* messages (scene tree, inspect objects)
# and the error stream need NO autoload at all.
#
# This script lives under addons/godot-mcp/ but is NOT loaded by the editor
# plugin — it is registered as a project autoload (name "McpRuntime") by
# plugin.gd::_register_autoload on _enter_tree, so the user only has to enable
# the plugin (no manual project.godot edit, no separate autoload/ dir).
#
# IMPORTANT: capture callbacks receive the message WITHOUT the "mcp:" prefix.
# The RemoteDebugger strips it (core/debugger/remote_debugger.cpp:680-686).
# So a message sent as "mcp:ping" arrives here as "ping".

const _SHOT_MAX_WIDTH := 1024
const _SHOT_JPEG_QUALITY := 0.85
const _TEMP_KEEP := 20  # rolling window: keep the N most recent mcp_* temp files
const McpLog = preload("res://addons/godot-mcp/mcp_log.gd")  # shared VERBOSE switch + McpLog.log() (see mcp_log.gd)


func _ready() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.register_message_capture("mcp", _capture)
		McpLog.log("[mcp-runtime] registered mcp: capture")
	else:
		# Game not launched under the debugger (e.g. exported build):
		# the debugger singleton is absent, nothing to register.
		McpLog.log("[mcp-runtime] debugger inactive — mcp capture not registered")


func _capture(message: String, data: Array) -> bool:
	# `message` already has the "mcp:" prefix stripped here.
	match message:
		"ping":
			# data == [call_id, echo_message]; echo them back as pong.
			if data.size() >= 2:
				var call_id: int = int(data[0])
				var echo: String = str(data[1])
				EngineDebugger.send_message("mcp:pong", [call_id, "pong: " + echo])
				return true
		"screenshot":
			# data == [call_id]; capture viewport -> JPEG file -> reply path.
			if data.size() >= 1:
				_take_screenshot(int(data[0]))
				return true
		"call":
			# data == [call_id, object_id, method, args_array]; invoke a method
			# on the runtime object and reply with its return value.
			if data.size() >= 4:
				_do_call(int(data[0]), int(data[1]), str(data[2]), data[3])
				return true
		"eval":
			# data == [call_id, code, object_id]; evaluate a GDScript expression
			# (Expression class — single expression only) with optional object as
			# base context, reply with its value. See _do_eval for the limits.
			if data.size() >= 3:
				_do_eval(int(data[0]), str(data[1]), int(data[2]))
				return true
		"simulate_input":
			# data == [call_id, event_dict]; build an InputEvent from event_dict
			# (type: key/mouse_button/action) and feed it via Input.parse_input_event
			# so the game's _input/_unhandled_input handlers fire. Single event per
			# call (pressed defaults true); a tap = two calls (press then release).
			if data.size() >= 2:
				_do_simulate_input(int(data[0]), data[1])
				return true
		_:
			pass
	return false


# Capture the current viewport to a JPEG under user:// and reply with its
# absolute path. Downscaled to ~_SHOT_MAX_WIDTH wide to keep the payload sane.
# The file is intentionally left in place (not cleaned here): a human can
# inspect it later when an AI's visual reasoning seems off. Cleanup is a
# separate policy (e.g. rolling by count/time).
func _take_screenshot(call_id: int) -> void:
	var viewport := get_viewport()
	if viewport == null:
		_reply(call_id, "", "no viewport")
		return
	var img: Image = viewport.get_texture().get_image()
	if img == null:
		_reply(call_id, "", "viewport texture unavailable (rendering not ready?)")
		return
	if img.get_width() > _SHOT_MAX_WIDTH:
		var ratio := float(_SHOT_MAX_WIDTH) / float(img.get_width())
		img.resize(_SHOT_MAX_WIDTH, maxi(1, int(img.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	var rel_path := "user://mcp_shot_%d.jpg" % call_id
	var err := img.save_jpg(rel_path, _SHOT_JPEG_QUALITY)
	if err != OK:
		_reply(call_id, "", "save_jpg failed (err=%d)" % err)
		return
	_prune_temp("mcp_shot_", ".jpg")
	_reply(call_id, ProjectSettings.globalize_path(rel_path), "")


# Reply to the editor: [call_id, absolute_path, error_message]. An empty path
# or a non-empty error signals failure.
func _reply(call_id: int, abs_path: String, error_msg: String) -> void:
	EngineDebugger.send_message("mcp:screenshot_result", [call_id, abs_path, error_msg])


# Rolling cleanup: keep only the N most recent user://mcp_<prefix>*<ext> files,
# delete the oldest. Prevents screenshots from accumulating unbounded across
# sessions. Called after each screenshot is written.
func _prune_temp(prefix: String, ext: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var files: Array = []  # [name, mtime] pairs (Array indexed, not Dict)
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with(prefix) and fname.ends_with(ext):
			files.append([fname, FileAccess.get_modified_time("user://" + fname)])
		fname = dir.get_next()
	dir.list_dir_end()
	if files.size() <= _TEMP_KEEP:
		return
	# bubble sort by mtime ascending (oldest first)
	var i := 0
	while i < files.size():
		var j := i + 1
		while j < files.size():
			if files[j][1] < files[i][1]:
				var tmp = files[i]
				files[i] = files[j]
				files[j] = tmp
			j += 1
		i += 1
	var to_delete := files.size() - _TEMP_KEEP
	var k := 0
	while k < to_delete:
		dir.remove(files[k][0])
		k += 1


# Call a method on a runtime object by id and reply with its return value.
# has_method is checked first so a bad method name surfaces as an explicit
# error reply (not just a push_error the AI would only see via
# get_runtime_errors). The return value is serialized (primitives as-is,
# compounds via var_to_str) so it survives the debug protocol + JSON bridge
# unchanged — same rule as mcp_debugger._variant_to_jsonable, mirrored here on
# the game side.
func _do_call(call_id: int, object_id: int, method: String, args: Array) -> void:
	var obj: Object = instance_from_id(object_id)
	if obj == null:
		# Bogus or stale id — point the AI back at get_scene_tree instead of
		# leaving it to guess. (instance_from_id's own C++ "slot >= slot_max"
		# push_error is Godot's defense against a corrupted id and can't be
		# avoided from GDScript; the actionable signal lives in this reply.)
		_reply_call(call_id, null, "no live object for id %d — invalid or freed; call get_scene_tree for a fresh id" % object_id)
		return
	if not obj.has_method(method):
		_reply_call(call_id, null, "%s has no method '%s'" % [obj.get_class(), method])
		return
	var ret: Variant = null
	if args.is_empty():
		ret = obj.call(method)
	else:
		ret = obj.callv(method, args)
	_reply_call(call_id, _serialize_ret(ret), "")


func _serialize_ret(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		_:
			return var_to_str(v)


# Reply with [call_id, return_value, error_message]. A non-empty error signals
# failure (object freed / unknown method). return_value is already JSON-friendly.
func _reply_call(call_id: int, ret: Variant, error_msg: String) -> void:
	EngineDebugger.send_message("mcp:call_result", [call_id, ret, error_msg])


# Evaluate a GDScript single expression (Expression class) and reply with its
# value. Expression is a PURE expression evaluator — no statements (var/if/for),
# no assignment, no multiline (see core/math/expression.cpp). Its
# builtin function white-list is clean (math/random/utility — no load/FileAccess/
# DirAccess/ResourceLoader/HTTP; those are GDScript-only utility funcs Expression
# can't see), so the expression itself has no file/network/resource access. The
# real power/risk is the CALL node: base.foo() or bare foo() resolves to
# base.<foo>, so a Node base can queue_free()/get_tree().quit()/get_node(...).
# That "mutate game state" risk is accepted (AI responsible + bridge timeout);
# we deliberately do NOT offer multiline GDScript eval (that adds file/network/
# shell). object_id (non-zero) is the base; bare identifiers/methods resolve to
# it (position == base.position).
func _do_eval(call_id: int, code: String, object_id: int) -> void:
	var base: Object = null
	if object_id != 0:
		base = instance_from_id(object_id)
		if base == null:
			_reply_eval(call_id, null, "no live object for id %d — invalid or freed; call get_scene_tree for a fresh id" % object_id)
			return
	var expr := Expression.new()
	var parse_err: int = expr.parse(code)
	if parse_err != OK:
		_reply_eval(call_id, null, "parse error: %s" % expr.get_error_text())
		return
	var ret: Variant = expr.execute([], base, true)  # show_error=true
	if expr.has_execute_failed():
		_reply_eval(call_id, null, "execute error: %s" % expr.get_error_text())
		return
	_reply_eval(call_id, _serialize_ret(ret), "")


# Reply with [call_id, return_value, error_message] (same shape as _reply_call,
# but on the mcp:eval_result channel). return_value is JSON-friendly via
# _serialize_ret.
func _reply_eval(call_id: int, ret: Variant, error_msg: String) -> void:
	EngineDebugger.send_message("mcp:eval_result", [call_id, ret, error_msg])


# Inject a synthetic InputEvent into the running game's input system. event_dict
# arrives as a Variant Dictionary; type selects the event class:
#   key          — InputEventKey (keycode/physical_keycode, pressed, shift/ctrl/alt)
#   mouse_button — InputEventMouseButton (button_index, pressed, position)
#   action       — Input.action_press/release (flips is_action_pressed directly;
#                  does NOT fire _input handlers — use key for that)
# Vector2 fields arrive as "Vector2(x, y)" strings (var_to_str convention) and
# are decoded via str_to_var. Single event per call; a key tap = press + release
# (two calls). Replies mcp:simulate_input_result with [call_id, kind, err].
func _do_simulate_input(call_id: int, event_dict: Variant) -> void:
	var d: Dictionary = Dictionary(event_dict)
	var etype: String = String(d.get("type", ""))
	match etype:
		"key":
			var k := InputEventKey.new()
			var pkc: int = int(d.get("physical_keycode", 0))
			var kc: int = int(d.get("keycode", 0))
			if pkc != 0:
				k.physical_keycode = pkc
			elif kc != 0:
				k.keycode = kc
			else:
				_reply_simulate_input(call_id, "", "key event requires keycode or physical_keycode")
				return
			k.pressed = bool(d.get("pressed", true))
			k.echo = false
			k.shift_pressed = bool(d.get("shift", false))
			k.ctrl_pressed = bool(d.get("ctrl", false))
			k.alt_pressed = bool(d.get("alt", false))
			Input.parse_input_event(k)
			_reply_simulate_input(call_id, "key", "")
		"mouse_button":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button_index", MOUSE_BUTTON_LEFT))
			m.pressed = bool(d.get("pressed", true))
			var pos: Variant = d.get("position", "Vector2(0, 0)")
			if typeof(pos) == TYPE_STRING:
				pos = str_to_var(String(pos))
			m.position = pos
			m.global_position = pos
			Input.parse_input_event(m)
			_reply_simulate_input(call_id, "mouse_button", "")
		"action":
			var aname := String(d.get("action", ""))
			if aname.is_empty():
				_reply_simulate_input(call_id, "", "action event requires 'action' name")
				return
			# action_press/release flips Input.is_action_pressed directly; it does
			# NOT generate an InputEvent, so _input/_unhandled_input won't fire.
			if bool(d.get("pressed", true)):
				Input.action_press(aname, float(d.get("strength", 1.0)))
			else:
				Input.action_release(aname)
			_reply_simulate_input(call_id, "action", "")
		_:
			_reply_simulate_input(call_id, "", "unknown input type: %s (expected key/mouse_button/action)" % etype)


func _reply_simulate_input(call_id: int, kind_injected: String, error_msg: String) -> void:
	EngineDebugger.send_message("mcp:simulate_input_result", [call_id, kind_injected, error_msg])
