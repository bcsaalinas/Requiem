@tool
extends Node

# McpBridge — local TCP hub between the TypeScript MCP server and the running game.
#
# Protocol: newline-delimited JSON (one object per line) over a single TCP
# connection on 127.0.0.1:<port>. Default 6510 (avoids Godot's debug port 6007
# and the 6505/9090 used by other Godot-MCP projects).
#
# Messages server -> bridge:
#   {"type":"call","id":<int>,"tool":"<name>","args":{...}}
# Messages bridge -> server:
#   {"type":"result","id":<int>,"result":<any>} | {"type":"result","id":<int>,"error":"..."}
#   {"type":"event","event":"<kind>","data":[...]}   (asynchronous, reserved)
#
# Request/response correlation:
#   - mcp: tools (ping, screenshot): call id embedded in payload ([call_id, ...]).
#   - scene_tree / inspect_node: game reply carries no id, matched by tool name.
#   - get_runtime_errors: pull from the collector, no round-trip.

var debugger  # McpDebugger (mcp_debugger.gd), set by plugin.gd. Untyped: it's an EditorDebuggerPlugin (RefCounted), not a Node.
var collector  # ErrorCollector (error_collector.gd), set by plugin.gd. Untyped cross-script ref.
var assets  # McpAssets (mcp_assets.gd), set by plugin.gd. Editor-time asset queries (mode ③: no game round-trip). Untyped cross-script ref.
var output_collector  # OutputCollector (output_collector.gd), set by plugin.gd. print/console-log source. Untyped cross-script ref.
var port: int = 6510

const _POLL_INTERVAL := 0.03  # seconds
const _CALL_TIMEOUT_MS := 10000  # screenshot includes viewport grab + JPEG encode; give it room
const _EVAL_TIMEOUT_MS := 30000  # expression eval (esp. with method calls) can be slower than a single call
const _BREAKPOINT_WAIT_MS := 60000  # wait_for_breakpoint: a breakpoint may take long to hit, or never
const _STEP_WAIT_MS := 15000  # step_*/break: usually quick, but a return/end may mean no next debug_enter
const _DEBUG_CMD_MS := 10000  # get_stack_dump / get_frame_vars / continue / evaluate while paused (fast replies)
const McpLog = preload("res://addons/godot-mcp/mcp_log.gd")  # shared VERBOSE switch + McpLog.log() (see mcp_log.gd)

var _server := TCPServer.new()
var _peer: StreamPeerTCP = null
var _recv := PackedByteArray()
var _poll_accum: float = 0.0

# call_id -> {"time": int, "tool": String}
# Breakpoint entries add "wait_for": <event key> (debug_enter/debug_exit/
# stack_dump/stack_frame_vars/evaluation_return) so ownerless replies (which
# carry no call_id) are matched by event type, and "vars"/"expected" for the
# multi-message stack_frame_var accumulation.
var _pending: Dictionary = {}

# Debug-pause state, derived from debug_enter/debug_exit (we don't rely on
# session.is_breaked()'s multi-thread semantics). Reset on session death in
# _cleanup_dead_debug_state (stop_scene sends no debug_exit).
var _debug_paused := false
var _last_debug_enter := {}  # cached hit, for immediate resolve when already paused
var _dbg_session_active := false  # edge-detect inactive→active to sync breakpoints on Play


func start() -> void:
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_error("[godot-mcp] bridge: failed to listen on 127.0.0.1:%d (err=%d)" % [port, err])
		return
	McpLog.log("[godot-mcp] bridge listening on 127.0.0.1:%d" % port)


func stop() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	_server.stop()


func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < _POLL_INTERVAL:
		return
	_poll_accum = 0.0

	# Accept at most one client (the TypeScript MCP server). A NEW connection
	# always takes over the current one: `/mcp reconnect` restarts server.ts,
	# and its old socket can linger as a zombie peer (StreamPeerTCP.get_status()
	# doesn't surface a silent close promptly), which would otherwise keep
	# `_peer != null` and block the fresh connection in the listen backlog
	# forever — every bridge call then times out (see pitfalls #21). MCP is
	# single-client, so the new connection always wins.
	if _server.is_connection_available():
		if _peer != null:
			McpLog.log("[godot-mcp] mcp server reconnecting — dropping previous peer")
			_peer.disconnect_from_host()
			_peer = null
			_pending.clear()  # drop in-flight game calls from the dead client
			_recv.clear()
		_peer = _server.take_connection()
		_recv.clear()
		McpLog.log("[godot-mcp] mcp server connected")

	if _peer == null:
		return

	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		McpLog.log("[godot-mcp] mcp server disconnected")
		_peer = null
		return

	# Drain available bytes.
	var avail := _peer.get_available_bytes()
	if avail > 0:
		var got := _peer.get_data(avail)
		if got[0] == OK and got[1].size() > 0:
			_recv.append_array(got[1])

	# Process complete lines.
	while true:
		var nl := _recv.find(0x0A)  # '\n'
		if nl == -1:
			break
		var line_bytes: PackedByteArray = _recv.slice(0, nl)
		_recv = _recv.slice(nl + 1)
		var line := line_bytes.get_string_from_utf8().strip_edges()
		if not line.is_empty():
			_handle_line(line)

	# Guard against unbounded buffer growth on malformed input.
	if _recv.size() > 1_000_000:
		_recv.clear()

	# Edge-detect session inactive→active (Play): replay recorded breakpoints to
	# the new game process. _setup_session only fires at editor startup (NOT per
	# Play in 4.7.1), and the sed "started" signal proved unreliable on Play, so
	# this poll is the reliable per-Play breakpoint sync.
	var now_active: bool = debugger != null and debugger.has_active_session()
	if now_active and not _dbg_session_active:
		debugger.sync_breakpoints_to_game()
	_dbg_session_active = now_active
	_cleanup_dead_debug_state()
	_check_timeouts()


func _handle_line(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_send_json({"type": "error", "error": "invalid json line"})
		return
	var msg: Dictionary = parsed
	match String(msg.get("type", "")):
		"call":
			_handle_call(msg)
		"ping":
			# Lightweight liveness check that doesn't touch the game.
			_send_json({"type": "result", "id": int(msg.get("id", 0)), "result": {"alive": true}})
		_:
			_send_json({"type": "error", "error": "unknown message type: %s" % msg.get("type", "")})


func _handle_call(msg: Dictionary) -> void:
	var call_id: int = int(msg.get("id", 0))
	var tool: String = String(msg.get("tool", ""))
	var args: Dictionary = msg.get("args", {}) if typeof(msg.get("args")) == TYPE_DICTIONARY else {}

	match tool:
		"ping_game":
			if debugger == null or not debugger.has_active_session():
				_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
				return
			var payload := str(args.get("message", "hello"))
			_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": tool}
			# Send [call_id, message]; the in-game runtime echoes them back.
			var ok: bool = debugger.send_to_game("ping", [call_id, payload])
			if not ok:
				_pending.erase(call_id)
				_send_json({"type": "result", "id": call_id, "error": "failed to send mcp:ping to game"})
		"get_runtime_errors":
			_handle_get_runtime_errors(call_id, args)
		"get_console_output":
			_handle_get_console_output(call_id, args)
		"clean_temp":
			# Mode ③ — on-demand cleanup of user://mcp_* temp files.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				_send_json({"type": "result", "id": call_id, "result": assets.clean_temp()})
		"play_scene":
			# Mode ③ — launch game subprocess (EditorInterface.play_*). If already
			# running, stop first so the new subprocess picks up .gd changes.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var ps_mode := String(args.get("mode", "main"))
				var ps_path := String(args.get("scene_path", ""))
				_send_json({"type": "result", "id": call_id, "result": assets.play_scene(ps_mode, ps_path)})
		"stop_scene":
			# Mode ③ — kill the game subprocess.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				_send_json({"type": "result", "id": call_id, "result": assets.stop_scene()})
		"get_play_status":
			# Mode ③ — query game play status.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				_send_json({"type": "result", "id": call_id, "result": assets.get_play_status()})
		"get_scene_tree":
			_handle_get_scene_tree(call_id)
		"inspect_node":
			_handle_inspect_node(call_id, args)
		"set_node_property":
			_handle_set_node_property(call_id, args)
		"call_node_method":
			_handle_call_node_method(call_id, args)
		"eval":
			_handle_eval(call_id, args)
		"simulate_input":
			_handle_simulate_input(call_id, args)
		"screenshot":
			_handle_screenshot(call_id)
		"set_breakpoint":
			_handle_set_breakpoint(call_id, args)
		"remove_breakpoint":
			_handle_remove_breakpoint(call_id, args)
		"clear_breakpoints":
			_handle_clear_breakpoints(call_id)
		"wait_for_breakpoint":
			_handle_wait_for_breakpoint(call_id, args)
		"get_stack_dump":
			_handle_get_stack_dump(call_id)
		"get_stack_frame_vars":
			_handle_get_stack_frame_vars(call_id, args)
		"continue_execution":
			_handle_continue(call_id)
		"step_into":
			_handle_step(call_id, "step")
		"step_over":
			_handle_step(call_id, "next")
		"step_out":
			_handle_step(call_id, "out")
		"evaluate_debug":
			_handle_evaluate_debug(call_id, args)
		"break_execution":
			_handle_break(call_id)
		"collector_status":
			if collector == null:
				_send_json({"type": "result", "id": call_id, "result": {"error": "collector not available"}})
			else:
				_send_json({"type": "result", "id": call_id, "result": collector.get_status()})
		"get_project_root":
			# Mode ③ — project absolute path. server.ts uses this to resolve res://
			# paths for get_diagnostics WITHOUT inferring from its install location
			# (which breaks under `npm i -g`); makes a global bin viable.
			_send_json({"type": "result", "id": call_id, "result": {"project_root": ProjectSettings.globalize_path("res://")}})
		"list_assets":
			# Mode ③ — editor-time, no game round-trip. Bridge calls McpAssets
			# directly (like collector above), never touching the debug protocol.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var tf := String(args.get("type_filter", ""))
				var pf := String(args.get("path_filter", ""))
				_send_json({"type": "result", "id": call_id, "result": {"assets": assets.list_assets(tf, pf)}})
		"get_image_png":
			# Mode ③ — editor-time texture read. Same local-execution pattern as
			# list_assets; returns {path} or {error} for the TS server to read.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var img_path := String(args.get("path", ""))
				var img_max := int(args.get("max_size", 1024))
				_send_json({"type": "result", "id": call_id, "result": assets.get_image_png(img_path, img_max)})
		"slice_sprite_sheet":
			# Mode ③ — slice a sprite sheet PNG into a SpriteFrames resource.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var ss_path := String(args.get("path", ""))
				var ss_mode := String(args.get("mode", "auto"))
				var ss_cols := int(args.get("cols", 0))
				var ss_rows := int(args.get("rows", 0))
				var ss_fps := float(args.get("fps", 12))
				var ss_out := String(args.get("out_path", ""))
				var ss_atlas := String(args.get("atlas_path", ""))
				_send_json({"type": "result", "id": call_id, "result": assets.slice_sprite_sheet(ss_path, ss_mode, ss_cols, ss_rows, ss_fps, ss_out, ss_atlas)})
		"describe_sprite":
			# Mode ③ — describe a SpriteFrames resource (verify slice / inspect
			# hand-authored frames). Editor-time, no game round-trip.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var ds_path := String(args.get("path", ""))
				_send_json({"type": "result", "id": call_id, "result": assets.describe_sprite(ds_path)})
		"refresh_filesystem":
			# Mode ③ — rescan project filesystem (new/modified files -> import + refresh).
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var rf_mode := String(args.get("mode", "full"))
				_send_json({"type": "result", "id": call_id, "result": assets.refresh_filesystem(rf_mode)})
		"reload_scene":
			# Mode ③ — reload an already-open scene from disk (the case scan can't handle).
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var rs_path := String(args.get("path", ""))
				_send_json({"type": "result", "id": call_id, "result": assets.reload_scene(rs_path)})
		"reload_resource":
			# Mode ③ — force re-read of a single .tres/.res from disk.
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var rr_path := String(args.get("path", ""))
				_send_json({"type": "result", "id": call_id, "result": assets.reload_resource(rr_path)})
		"reload_plugin":
			# Mode ③ — reload an editor plugin (set_plugin_enabled via call_deferred).
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var rp_name := String(args.get("name", ""))
				_send_json({"type": "result", "id": call_id, "result": assets.reload_plugin(rp_name)})
		"find_references":
			# Mode ③ — reverse dependency lookup (which scenes/resources reference target).
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var fr_target := String(args.get("target", ""))
				_send_json({"type": "result", "id": call_id, "result": assets.find_references(fr_target)})
		"describe_audio":
			# Mode ③ — audio stream metadata (length/mono + WAV format/loop).
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var da_path := String(args.get("path", ""))
				_send_json({"type": "result", "id": call_id, "result": assets.describe_audio(da_path)})
		"get_audio_pcm":
			# Mode ③ — audio PCM as downsampled waveform PNG (Vision).
			if assets == null:
				_send_json({"type": "result", "id": call_id, "error": "assets module not available"})
			else:
				var ga_path := String(args.get("path", ""))
				var ga_width := int(args.get("width", 800))
				_send_json({"type": "result", "id": call_id, "result": assets.get_audio_pcm(ga_path, ga_width)})
		"list_tools":
			_send_json({"type": "result", "id": call_id, "result": {"tools": ["ping_game", "get_runtime_errors", "get_scene_tree", "inspect_node", "set_node_property", "call_node_method", "screenshot", "collector_status", "list_assets", "get_image_png", "slice_sprite_sheet", "describe_sprite", "refresh_filesystem", "reload_scene", "reload_resource", "reload_plugin", "find_references", "describe_audio", "get_audio_pcm", "get_console_output", "eval", "simulate_input", "clean_temp", "play_scene", "stop_scene", "get_play_status", "get_diagnostics", "set_breakpoint", "remove_breakpoint", "clear_breakpoints", "wait_for_breakpoint", "get_stack_dump", "get_stack_frame_vars", "continue_execution", "step_into", "step_over", "step_out", "evaluate_debug", "break_execution", "list_tools"]}})
		_:
			_send_json({"type": "result", "id": call_id, "error": "unknown tool: %s" % tool})


func _handle_get_runtime_errors(call_id: int, args: Dictionary) -> void:
	if collector == null:
		_send_json({"type": "result", "id": call_id, "result": {"errors": [], "count": 0, "note": "error collector not available"}})
		return
	var include_warnings := bool(args.get("include_warnings", false))
	var clear := bool(args.get("clear", true))
	var errs: Array = collector.take(include_warnings, clear)
	_send_json({"type": "result", "id": call_id, "result": {"errors": errs, "count": errs.size()}})


func _handle_get_console_output(call_id: int, args: Dictionary) -> void:
	if output_collector == null:
		_send_json({"type": "result", "id": call_id, "result": {"lines": [], "count": 0, "note": "output collector not available"}})
		return
	var types_var: Variant = args.get("types", [])
	var types_arr: Array = types_var if typeof(types_var) == TYPE_ARRAY else []
	var clear := bool(args.get("clear", true))
	var lines: Array = output_collector.take(types_arr, clear)
	_send_json({"type": "result", "id": call_id, "result": {"lines": lines, "count": lines.size()}})


func _handle_get_scene_tree(call_id: int) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "get_scene_tree"}
	var ok: bool = debugger.request_scene_tree()
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to request scene tree from game"})


func _handle_inspect_node(call_id: int, args: Dictionary) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	var object_id: int = int(args.get("object_id", 0))
	if object_id == 0:
		_send_json({"type": "result", "id": call_id, "error": "object_id required (get it from get_scene_tree)"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "inspect_node", "object_id": object_id}
	var ok: bool = debugger.request_inspect(object_id)
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to request inspect_objects from game"})


func _handle_set_node_property(call_id: int, args: Dictionary) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	var object_id: int = int(args.get("object_id", 0))
	if object_id == 0:
		_send_json({"type": "result", "id": call_id, "error": "object_id required (get it from get_scene_tree)"})
		return
	var prop: String = String(args.get("property", ""))
	if prop.is_empty():
		_send_json({"type": "result", "id": call_id, "error": "property name required"})
		return
	if not args.has("value"):
		_send_json({"type": "result", "id": call_id, "error": "value required"})
		return
	# scene:set_object_property is fire-and-forget (no reply, silent on a bad
	# object/property). We convert the AI's JSON value to a Godot Variant, then
	# rely on debugger.request_set_property to fire a paired scene:inspect_objects
	# request whose reply on_inspect_objects matches back here to verify.
	var value: Variant = _jsonable_to_variant(args.get("value"))
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "set_node_property", "object_id": object_id, "property": prop, "sent_value": value}
	var ok2: bool = debugger.request_set_property(object_id, prop, value)
	if not ok2:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send scene:set_object_property to game"})


func _handle_call_node_method(call_id: int, args: Dictionary) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	var object_id: int = int(args.get("object_id", 0))
	if object_id == 0:
		_send_json({"type": "result", "id": call_id, "error": "object_id required (get it from get_scene_tree)"})
		return
	var method: String = String(args.get("method", ""))
	if method.is_empty():
		_send_json({"type": "result", "id": call_id, "error": "method name required"})
		return
	var raw_args: Variant = args.get("args", [])
	if typeof(raw_args) != TYPE_ARRAY:
		raw_args = []
	# Convert each JSON arg to a Godot Variant (same rule as set_node_property's
	# value): compounds via str_to_var, primitives as-is. The game side calls
	# obj.callv(method, call_args) and replies mcp:call_result.
	var call_args: Array = []
	for a in raw_args:
		call_args.append(_jsonable_to_variant(a))
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "call_node_method"}
	var ok3: bool = debugger.send_to_game("call", [call_id, object_id, method, call_args])
	if not ok3:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send mcp:call to game"})


func _handle_eval(call_id: int, args: Dictionary) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	var code: String = String(args.get("code", ""))
	if code.is_empty():
		_send_json({"type": "result", "id": call_id, "error": "code required (a GDScript expression)"})
		return
	var object_id: int = int(args.get("object_id", 0))
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "eval"}
	# Send [call_id, code, object_id]; the in-game runtime evaluates the
	# expression (Expression class — single expression) with object_id as base,
	# replies mcp:eval_result with [call_id, ret, err].
	var ok: bool = debugger.send_to_game("eval", [call_id, code, object_id])
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send mcp:eval to game"})


func _handle_simulate_input(call_id: int, args: Dictionary) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	var event: Dictionary = Dictionary(args.get("event", {}))
	if event.is_empty():
		_send_json({"type": "result", "id": call_id, "error": "event required (a dict with type + fields: key/mouse_button/action)"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "simulate_input"}
	# Send [call_id, event_dict]; the in-game runtime builds the InputEvent and
	# feeds it via Input.parse_input_event, replies mcp:simulate_input_result
	# with [call_id, kind_injected, err].
	var sok: bool = debugger.send_to_game("simulate_input", [call_id, event])
	if not sok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send mcp:simulate_input to game"})


func _handle_screenshot(call_id: int) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "screenshot"}
	# The game (autoload/mcp_runtime.gd) captures the viewport, saves a JPEG,
	# and replies mcp:screenshot_result with [call_id, abs_path, error_msg].
	var ok: bool = debugger.send_to_game("screenshot", [call_id])
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send mcp:screenshot to game"})


# Invoked by McpDebugger._capture when the running game sends "mcp:<kind>".
func on_game_message(kind: String, data: Array, session_id: int) -> void:
	match kind:
		"pong":
			if data.size() >= 2:
				var call_id: int = int(data[0])
				var message: String = str(data[1])
				if _pending.has(call_id):
					_pending.erase(call_id)
					_send_json({"type": "result", "id": call_id, "result": {"pong": message, "session_id": session_id}})
					return
			# Unsolicited pong — forward as event.
			_send_json({"type": "event", "event": "pong", "data": data})
		"screenshot_result":
			# data == [call_id, abs_path, error_msg]. Match the pending screenshot
			# call; resolve with the path on success, or surface the error.
			if data.size() >= 3:
				var call_id: int = int(data[0])
				var path: String = str(data[1])
				var err_msg: String = str(data[2])
				if _pending.has(call_id):
					_pending.erase(call_id)
					if err_msg.length() > 0:
						_send_json({"type": "result", "id": call_id, "error": err_msg})
					else:
						_send_json({"type": "result", "id": call_id, "result": {"path": path}})
					return
			_send_json({"type": "event", "event": "screenshot_result", "data": data})
		"call_result":
			# data == [call_id, return_value, error_msg]. return_value is already
			# JSON-friendly (the game side serialized compounds via var_to_str).
			if data.size() >= 3:
				var call_id: int = int(data[0])
				if _pending.has(call_id):
					_pending.erase(call_id)
					var c_err: String = str(data[2])
					if c_err.length() > 0:
						_send_json({"type": "result", "id": call_id, "error": c_err})
					else:
						_send_json({"type": "result", "id": call_id, "result": {"return_value": data[1]}})
					return
			_send_json({"type": "event", "event": "call_result", "data": data})
		"eval_result":
			# data == [call_id, return_value, error_msg] — same shape as call_result.
			if data.size() >= 3:
				var call_id: int = int(data[0])
				if _pending.has(call_id):
					_pending.erase(call_id)
					var e_err: String = str(data[2])
					if e_err.length() > 0:
						_send_json({"type": "result", "id": call_id, "error": e_err})
					else:
						_send_json({"type": "result", "id": call_id, "result": {"return_value": data[1]}})
					return
			_send_json({"type": "event", "event": "eval_result", "data": data})
		"simulate_input_result":
			# data == [call_id, kind_injected, error_msg].
			if data.size() >= 3:
				var call_id: int = int(data[0])
				if _pending.has(call_id):
					_pending.erase(call_id)
					var si_err: String = str(data[2])
					if si_err.length() > 0:
						_send_json({"type": "result", "id": call_id, "error": si_err})
					else:
						_send_json({"type": "result", "id": call_id, "result": {"injected": str(data[1])}})
					return
			_send_json({"type": "event", "event": "simulate_input_result", "data": data})
		_:
			_send_json({"type": "event", "event": kind, "data": data})


# Invoked by McpDebugger._on_debug_data when a "scene:scene_tree" response
# arrives. The reply carries no call id, so we match it to the pending
# get_scene_tree call by tool name.
func on_scene_tree(tree: Dictionary) -> void:
	var match_id := -1
	for id in _pending:
		if String(_pending[id].get("tool", "")) == "get_scene_tree":
			match_id = int(id)
			break
	if match_id >= 0:
		_pending.erase(match_id)
		_send_json({"type": "result", "id": match_id, "result": {"tree": tree}})


# Invoked by McpDebugger._on_debug_data when a "scene:inspect_objects" response
# arrives. The reply carries no call id, so we match it by tool name. Two tools
# ride on this reply: inspect_node (plain query) and set_node_property (whose
# request_set_property fires a set then an inspect_objects to verify the write).
func on_inspect_objects(objects: Array) -> void:
	var match_id := -1
	var tool := ""
	for id in _pending:
		var t := String(_pending[id].get("tool", ""))
		if t == "inspect_node" or t == "set_node_property":
			match_id = int(id)
			tool = t
			break
	if match_id < 0:
		return
	var entry: Dictionary = _pending[match_id]
	_pending.erase(match_id)
	if tool == "inspect_node":
		_send_json({"type": "result", "id": match_id, "result": {"objects": objects}})
		return
	# set_node_property: pull the target property's readback value to verify.
	var object_id: int = int(entry.get("object_id", 0))
	var prop: String = String(entry.get("property", ""))
	var sent_value: Variant = entry.get("sent_value", null)
	var new_value: Variant = null
	var found := false
	for obj in objects:
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		if int(obj.get("id", 0)) != object_id:
			continue
		for p in obj.get("properties", []):
			if typeof(p) == TYPE_DICTIONARY and String(p.get("name", "")) == prop:
				new_value = p.get("value", null)
				found = true
				break
		break
	var applied := found and _values_equal(new_value, sent_value)
	_send_json({"type": "result", "id": match_id, "result": {
		"object_id": object_id,
		"property": prop,
		"new_value": new_value,
		"applied": applied,
		"note": ("" if found else "property not found in readback"),
	}})


# Called via McpDebugger._on_debug_data when "remote_selection_invalidated"
# arrives — Godot's SceneDebugger emits that (instead of "scene:inspect_objects")
# when a requested object id is invalid/freed; data[0] is the list of bad ids.
# Without this, the pending inspect_node / set_node_property call would hang
# until the 10s _check_timeouts. We resolve it now with the same "bad id"
# guidance as call_node_method, pointing the AI at get_scene_tree.
func on_invalid_selection(data: Array) -> void:
	var bad_ids := {}
	if data.size() >= 1 and typeof(data[0]) == TYPE_ARRAY:
		for bid in data[0]:
			bad_ids[int(bid)] = true
	var match_id := -1
	var object_id := 0
	for id in _pending:
		var t := String(_pending[id].get("tool", ""))
		if t == "inspect_node" or t == "set_node_property":
			var pid := int(_pending[id].get("object_id", 0))
			# Match the pending whose id is in the bad list; if we couldn't parse
			# the list, fall back to the first matching pending (single-pending is
			# the common case — MCP tool calls are usually serial).
			if bad_ids.is_empty() or bad_ids.has(pid):
				match_id = int(id)
				object_id = pid
				break
	if match_id >= 0:
		_pending.erase(match_id)
		_send_json({"type": "result", "id": match_id, "error":
			"no live object for id %d — invalid or freed; call get_scene_tree for a fresh id" % object_id})


# Inverse of mcp_debugger._variant_to_jsonable: turn the JSON value the AI sent
# into the Godot Variant that scene:set_object_property expects. Numbers/bools/
# null pass through; strings are run through str_to_var so compound values that
# inspect_node showed as "Vector2(180, 240)" round-trip back into real Vector2.
# A bare string that doesn't parse into a compound stays a literal string.
func _jsonable_to_variant(v: Variant) -> Variant:
	if typeof(v) == TYPE_STRING:
		var parsed: Variant = str_to_var(v)
		if parsed != null and typeof(parsed) != TYPE_STRING:
			return parsed
		return v
	return v


# Mirror of mcp_debugger._variant_to_jsonable, used to normalize the value we
# sent so it compares cleanly against the readback (which arrived already
# JSON-friendly). Primitives as-is, compounds as their var_to_str string.
func _to_jsonable(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		_:
			return var_to_str(v)


func _values_equal(readback: Variant, sent: Variant) -> bool:
	return _to_jsonable(sent) == readback


func _check_timeouts() -> void:
	var now := Time.get_ticks_msec()
	var expired: Array = []
	for id in _pending:
		var tool_name := String(_pending[id].get("tool", ""))
		if now - int(_pending[id].get("time", now)) > _limit_for_tool(tool_name):
			expired.append(id)
	for id in expired:
		var p: Dictionary = _pending[id]
		_pending.erase(id)
		# A stalled frame-vars stream returns the partial set gathered so far
		# rather than a bare timeout — more useful than an empty-handed failure.
		if String(p.get("tool", "")) == "get_stack_frame_vars" and int(p.get("expected", -1)) >= 0:
			_emit_frame_vars(int(id), p)
		else:
			_send_json({"type": "result", "id": id, "error": "timeout waiting for game response"})


func _send_json(obj: Dictionary) -> void:
	if _peer == null:
		return
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var data := (JSON.stringify(obj) + "\n").to_utf8_buffer()
	_peer.put_data(data)


# ============================================================
# Breakpoint debugging (mode ① — all via McpDebugger._on_debug_data)
# ============================================================
# Stock, unprefixed debug messages with NO call_id in their replies, so we match
# them to pending tool calls by the "wait_for" event key (one in flight per event
# type). State machine: continue→debug_exit, step→next debug_enter (intermediate
# debug_exit ignored), wait/break→debug_enter. See the plan for full rationale.


# Per-tool timeout limit (called by _check_timeouts).
func _limit_for_tool(tool_name: String) -> int:
	match tool_name:
		"eval":
			return _EVAL_TIMEOUT_MS
		"wait_for_breakpoint":
			return _BREAKPOINT_WAIT_MS
		"step", "break_execution":
			return _STEP_WAIT_MS
		"get_stack_dump", "get_stack_frame_vars", "continue_execution", "evaluate_debug":
			return _DEBUG_CMD_MS
		_:
			return _CALL_TIMEOUT_MS


# stop_scene kills the game subprocess but sends NO debug_exit, so _debug_paused
# would linger and any pending debug tool would hang to its own timeout. When the
# session is gone, drop debug state and fail in-flight breakpoint calls promptly.
func _cleanup_dead_debug_state() -> void:
	if not _debug_paused:
		return
	if debugger != null and debugger.has_active_session():
		return
	_debug_paused = false
	_last_debug_enter = {}
	var dead: Array = []
	for id in _pending:
		if String(_pending[id].get("wait_for", "")) != "":
			dead.append(int(id))
	for id in dead:
		_pending.erase(id)
		_send_json({"type": "result", "id": id, "error": "game session ended while paused"})


# --- breakpoint tools: handlers (called from _handle_call) ---

func _handle_set_breakpoint(call_id: int, args: Dictionary) -> void:
	if debugger == null:
		_send_json({"type": "result", "id": call_id, "error": "debugger not available"})
		return
	var file := String(args.get("file", ""))
	var line := int(args.get("line", 0))
	if file.is_empty() or line < 1:
		_send_json({"type": "result", "id": call_id, "error": "file (res:// path) and line (>=1) required"})
		return
	_send_json({"type": "result", "id": call_id, "result": debugger.set_breakpoint(file, line, true)})


func _handle_remove_breakpoint(call_id: int, args: Dictionary) -> void:
	if debugger == null:
		_send_json({"type": "result", "id": call_id, "error": "debugger not available"})
		return
	var file := String(args.get("file", ""))
	var line := int(args.get("line", 0))
	if file.is_empty() or line < 1:
		_send_json({"type": "result", "id": call_id, "error": "file (res:// path) and line (>=1) required"})
		return
	_send_json({"type": "result", "id": call_id, "result": debugger.set_breakpoint(file, line, false)})


func _handle_clear_breakpoints(call_id: int) -> void:
	if debugger == null:
		_send_json({"type": "result", "id": call_id, "error": "debugger not available"})
		return
	_send_json({"type": "result", "id": call_id, "result": debugger.clear_breakpoints()})


# Wait for the game to hit a breakpoint. No command is sent — the game pushes
# debug_enter when it pauses. If already paused, resolve immediately from cache.
func _handle_wait_for_breakpoint(call_id: int, _args: Dictionary) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	if _debug_paused and not _last_debug_enter.is_empty():
		_send_json({"type": "result", "id": call_id, "result": _last_debug_enter})
		return
	# debug_enter is a global event with no call_id — at most ONE debug_enter
	# waiter (wait/step/break) in flight, else they can't be told apart.
	if _has_waitfor_pending("debug_enter"):
		_send_json({"type": "result", "id": call_id, "error": "a debug_enter wait is already in flight (wait_for_breakpoint/step/break); resolve it first"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "wait_for_breakpoint", "wait_for": "debug_enter"}


func _handle_get_stack_dump(call_id: int) -> void:
	if not _require_paused(call_id):
		return
	if _has_waitfor_pending("stack_dump"):
		_send_json({"type": "result", "id": call_id, "error": "a get_stack_dump request is already in flight; resolve it first"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "get_stack_dump", "wait_for": "stack_dump"}
	var ok: bool = debugger.send_debug_command("get_stack_dump", [])
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send get_stack_dump to game"})


# Single-flight: stack_frame_var is an id-less stream; two concurrent requests
# would interleave their variables. Vars accumulate in the pending entry.
func _handle_get_stack_frame_vars(call_id: int, args: Dictionary) -> void:
	if not _require_paused(call_id):
		return
	if _has_pending_tool("get_stack_frame_vars"):
		_send_json({"type": "result", "id": call_id, "error": "a stack-frame-vars request is already in flight; resolve it first"})
		return
	var frame := int(args.get("frame", 0))
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "get_stack_frame_vars", "wait_for": "stack_frame_vars", "frame": frame, "expected": -1, "vars": []}
	var ok: bool = debugger.send_debug_command("get_stack_frame_vars", [frame])
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send get_stack_frame_vars to game"})


# continue: the paused loop breaks and the game sends debug_exit (then runs free
# until the NEXT breakpoint). Resolve on debug_exit — NOT debug_enter, which may
# never come.
func _handle_continue(call_id: int) -> void:
	if not _require_paused(call_id):
		return
	if _has_waitfor_pending("debug_exit"):
		_send_json({"type": "result", "id": call_id, "error": "a debug_exit wait is already in flight; resolve it first"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "continue_execution", "wait_for": "debug_exit"}
	var ok: bool = debugger.send_debug_command("continue", [])
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send continue to game"})


# step into/over/out: the loop breaks (debug_exit) then the game re-pauses at
# the next line (debug_enter). We wait for debug_enter; the intermediate
# debug_exit finds no debug_exit pending and is ignored — that's the point of
# the wait_for bucketing.
func _handle_step(call_id: int, key: String) -> void:
	if not _require_paused(call_id):
		return
	if _has_waitfor_pending("debug_enter"):
		_send_json({"type": "result", "id": call_id, "error": "a debug_enter wait is already in flight (wait_for_breakpoint/step/break); resolve it first"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "step", "wait_for": "debug_enter"}
	var ok: bool = debugger.send_debug_command(key, [])
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send %s to game" % key})


# break: pause a running (not-yet-paused) game. Same waiter as wait/step.
func _handle_break(call_id: int) -> void:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return
	if _debug_paused and not _last_debug_enter.is_empty():
		var r: Dictionary = _last_debug_enter.duplicate(true)
		r["already_paused"] = true
		_send_json({"type": "result", "id": call_id, "result": r})
		return
	if _has_waitfor_pending("debug_enter"):
		_send_json({"type": "result", "id": call_id, "error": "a debug_enter wait is already in flight (wait_for_breakpoint/step/break); resolve it first"})
		return
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "break_execution", "wait_for": "debug_enter"}
	var ok: bool = debugger.send_debug_command("break", [])
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send break to game"})


# Evaluate an expression in the paused frame's scope. Single-flight. Default
# frame=0 (stack top always has a script instance; deeper frames may not, which
# makes the game break the loop and drop the reply).
func _handle_evaluate_debug(call_id: int, args: Dictionary) -> void:
	if not _require_paused(call_id):
		return
	var expr := String(args.get("expression", ""))
	if expr.is_empty():
		_send_json({"type": "result", "id": call_id, "error": "expression required"})
		return
	if _has_pending_tool("evaluate_debug"):
		_send_json({"type": "result", "id": call_id, "error": "an evaluate_debug request is already in flight; resolve it first"})
		return
	var frame := int(args.get("frame", 0))
	_pending[call_id] = {"time": Time.get_ticks_msec(), "tool": "evaluate_debug", "wait_for": "evaluation_return"}
	var ok: bool = debugger.send_debug_command("evaluate", [expr, frame])
	if not ok:
		_pending.erase(call_id)
		_send_json({"type": "result", "id": call_id, "error": "failed to send evaluate to game"})


# --- breakpoint tools: game→editor callbacks (from McpDebugger._on_debug_data) ---

# debug_enter: data = [can_continue, error, has_frames, thread_id]
func on_debug_enter(data: Array) -> void:
	var info := {}
	if data.size() >= 4:
		info = {
			"paused": true,
			"can_continue": bool(data[0]),
			"error": str(data[1]),
			"has_frames": bool(data[2]),
			"thread_id": int(data[3]),
		}
	else:
		info = {"paused": true}
	_debug_paused = true
	_last_debug_enter = info
	# MVP is main-thread only; single-threaded games always pause on main, so we
	# resolve normally. (Multi-thread stepping can't be routed via send_message.)
	var match_id := _find_pending_by_waitfor("debug_enter")
	if match_id >= 0:
		_pending.erase(match_id)
		_send_json({"type": "result", "id": match_id, "result": info})


func on_debug_exit(_data: Array) -> void:
	_debug_paused = false
	# Only continue_execution waits for debug_exit. step's intermediate debug_exit
	# finds no debug_exit pending → silently ignored (the wait_for bucketing).
	var match_id := _find_pending_by_waitfor("debug_exit")
	if match_id >= 0:
		_pending.erase(match_id)
		_send_json({"type": "result", "id": match_id, "result": {"resumed": true}})


func on_stack_dump(frames: Array) -> void:
	# The editor auto-requests a stack_dump on every debug_enter
	# (script_editor_debugger.cpp:354); with no pending request we just drop it.
	var match_id := _find_pending_by_waitfor("stack_dump")
	if match_id >= 0:
		_pending.erase(match_id)
		_send_json({"type": "result", "id": match_id, "result": {"frames": frames, "count": frames.size()}})


# stack_frame_vars header: data[0] = total var count (locals+members+globals).
func on_stack_frame_vars(data: Array) -> void:
	var match_id := _find_pending_by_waitfor("stack_frame_vars")
	if match_id < 0:
		return
	var p: Dictionary = _pending[match_id]
	var total := int(data[0]) if data.size() >= 1 else 0
	p["expected"] = total
	if total == 0:
		_resolve_frame_vars(match_id)


# One variable of the current frame; arrives N times after the header.
func on_stack_frame_var(v: Dictionary) -> void:
	var match_id := _find_pending_by_waitfor("stack_frame_vars")
	if match_id < 0:
		return
	var p: Dictionary = _pending[match_id]
	(p["vars"] as Array).append(v)
	if int(p["expected"]) >= 0 and (p["vars"] as Array).size() >= int(p["expected"]):
		_resolve_frame_vars(match_id)


func on_evaluation_return(v: Dictionary) -> void:
	var match_id := _find_pending_by_waitfor("evaluation_return")
	if match_id >= 0:
		_pending.erase(match_id)
		_send_json({"type": "result", "id": match_id, "result": {
			"expression": v.get("name", ""),
			"value": v.get("value"),
			"type_hint": v.get("type_hint", ""),
			"truncated": bool(v.get("truncated", false)),
		}})


# --- helpers ---

func _find_pending_by_waitfor(wf: String) -> int:
	for id in _pending:
		if String(_pending[id].get("wait_for", "")) == wf:
			return int(id)
	return -1


func _has_waitfor_pending(wf: String) -> bool:
	return _find_pending_by_waitfor(wf) >= 0


func _has_pending_tool(t: String) -> bool:
	for id in _pending:
		if String(_pending[id].get("tool", "")) == t:
			return true
	return false


func _require_paused(call_id: int) -> bool:
	if debugger == null or not debugger.has_active_session():
		_send_json({"type": "result", "id": call_id, "error": "no active game session — run the game from the editor (Play) first"})
		return false
	if not _debug_paused:
		_send_json({"type": "result", "id": call_id, "error": "game is not paused at a breakpoint — call wait_for_breakpoint first (or set_breakpoint + Play + trigger it)"})
		return false
	return true


# Drain a completed frame-vars request: group by scope, emit with completeness.
func _resolve_frame_vars(match_id: int) -> void:
	var p: Dictionary = _pending[match_id]
	_pending.erase(match_id)
	_emit_frame_vars(match_id, p)


func _emit_frame_vars(id: int, p: Dictionary) -> void:
	var locals := []
	var members := []
	var globals := []
	var evals := []
	for v in p.get("vars", []):
		match int((v as Dictionary).get("scope", -1)):
			0:
				locals.append(v)
			1:
				members.append(v)
			2:
				globals.append(v)
			_:
				evals.append(v)
	var got := locals.size() + members.size() + globals.size() + evals.size()
	_send_json({"type": "result", "id": id, "result": {
		"frame": int(p.get("frame", 0)),
		"locals": locals,
		"members": members,
		"globals": globals,
		"expected": int(p.get("expected", -1)),
		"received": got,
		"complete": got >= int(p.get("expected", -1)),
	}})
