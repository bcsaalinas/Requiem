@tool
extends EditorDebuggerPlugin

# McpDebugger — the editor side of the mcp: capture namespace, the runtime
# error sniffer, the scene-tree fetcher, and the node inspector.
#
# Four jobs:
#   1. mcp: capture — forward in-game "mcp:<kind>" messages to McpBridge
#      (ping/pong and future custom tools). Same as the original POC.
#   2. Runtime errors — ScriptEditorDebugger.debug_data sees the hardcoded
#      "error" message; structured OutputError payload -> ErrorCollector.
#   3. Scene tree — send stock "scene:request_scene_tree"; game replies
#      "scene:scene_tree" (via debug_data) -> parsed nested tree.
#   4. Node inspect — send stock "scene:inspect_objects" with an object id;
#      game replies "scene:inspect_objects" (via debug_data) -> parsed props.
#
# Why a session tab? EditorDebuggerSession exposes no reference to its
# ScriptEditorDebugger, but add_session_tab() parents our Control under the
# debugger's TabContainer — two get_parent() hops reach the ScriptEditorDebugger
# (add_debugger_tab does tabs->add_child; 4.7.1 source
# script_editor_debugger.cpp:2082). The tab occupies one slot in the Debugger
# panel; we name it "MCP" and put a short label in it.
#
# debug_data(msg, data) is emitted for every inbound message BEFORE hardcoded
# routing (script_editor_debugger.cpp:984), so it sees "error",
# "scene:scene_tree", and "scene:inspect_objects" alike — all hardcoded,
# unprefixed messages that _capture can never reach.

const McpWire = preload("res://addons/godot-mcp/mcp_wire.gd")
const McpLog = preload("res://addons/godot-mcp/mcp_log.gd")  # shared VERBOSE switch + McpLog.log() (see mcp_log.gd)

var bridge  # McpBridge (mcp_bridge.gd), set by plugin.gd. Untyped (cross-script ref).
var collector  # ErrorCollector (error_collector.gd), set by plugin.gd.
var output_collector  # OutputCollector (output_collector.gd), set by plugin.gd. print/console-log source.

var _active_session_id: int = -1
var _wire := McpWire.new()  # pure wire-format parsing (see mcp_wire.gd)
# Recorded breakpoints [{file:String, line:int}]. Array (not Dictionary) on
# purpose: @tool Dictionary iteration is unreliable (pitfalls #13). Replayed to
# every new game session in _setup_session so stop+re-Play doesn't lose them.
var _breakpoints: Array = []


func _has_capture(capture: String) -> bool:
	return capture == "mcp"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if not message.begins_with("mcp:"):
		return false
	var kind := message.substr(4)  # strip "mcp:" prefix
	if bridge:
		bridge.on_game_message(kind, data, session_id)
	return true


func _setup_session(session_id: int) -> void:
	_active_session_id = session_id
	McpLog.log("[godot-mcp] debug session ready: id=%d" % session_id)
	_connect_error_sniffer(session_id)
	_replay_breakpoints(session_id)


# Add an MCP tab to this session's debugger and connect its `debug_data` signal
# so we receive every inbound debug message.
func _connect_error_sniffer(session_id: int) -> void:
	var session := get_session(session_id)
	if session == null:
		return
	var tab := Control.new()
	tab.name = "MCP"
	var label := Label.new()
	label.text = "Godot MCP Bridge — error sniffer + scene tree + inspector active."
	label.position = Vector2(10, 10)
	tab.add_child(label)
	session.add_session_tab(tab)

	# add_session_tab parents `tab` under the debugger's TabContainer, so two
	# hops up is the ScriptEditorDebugger instance that emits debug_data.
	var sed: Object = tab.get_parent()
	if sed != null:
		sed = sed.get_parent()
	if sed == null:
		push_warning("[godot-mcp] could not reach ScriptEditorDebugger from session tab")
		return
	if not sed.has_signal("debug_data"):
		push_warning("[godot-mcp] no debug_data signal on debugger node (class=%s)" % sed.get_class())
		return
	if not sed.is_connected("debug_data", _on_debug_data):
		sed.connect("debug_data", _on_debug_data)
	# "started" fires when a game connects to this debugger (Play), right after
	# set_pid (script_editor_debugger.cpp:436) — BEFORE the game's main loop / _ready.
	# _setup_session only runs once (editor startup / plugin register, NOT per Play),
	# so "started" is the reliable per-Play hook to replay recorded breakpoints to
	# each fresh game process. Without it, set_breakpoint before Play is lost (the
	# new subprocess never receives it) and _ready runs straight through.
	if sed.has_signal("started") and not sed.is_connected("started", _on_debugger_started):
		sed.connect("started", _on_debugger_started)
	McpLog.log("[godot-mcp] debug_data sniffer connected (session %d, sed=%s)" % [session_id, sed.get_class()])


# ScriptEditorDebugger.debug_data(msg, data) — fires for every inbound message.
# We act on "error", "scene:scene_tree", "scene:inspect_objects"; everything else
# is ignored (the built-in handlers still process it normally).
func _on_debug_data(msg: String, data: Array) -> void:
	match msg:
		"error":
			if collector != null:
				collector.push_error_data(data)
		"output":
			# print() / print_rich() / printerr() — the console log stream (NOT
			# push_error, that's "error" above). data = [PackedStringArray strings,
			# PackedInt32Array types], parallel; OutputCollector splits per-index.
			# Distinct from get_runtime_errors: type=1 here is printerr, not push_error.
			if output_collector != null:
				output_collector.push_output_data(data)
		"scene:scene_tree":
			if bridge != null:
				bridge.on_scene_tree(parse_scene_tree(data))
		"scene:inspect_objects":
			if bridge != null:
				bridge.on_inspect_objects(parse_inspect_objects(data))
		"remote_selection_invalidated":
			# SceneDebugger._send_object_ids emits this (NOT "scene:inspect_objects")
			# when a requested object id is invalid/freed — data[0] is the list of
			# bad ids. Forward it so the bridge can fail the pending inspect_node /
			# set_node_property call immediately, instead of hanging until the 10s
			# _check_timeouts.
			if bridge != null:
				bridge.on_invalid_selection(data)
		"debug_enter":
			# Game hit a breakpoint / paused. data = [can_continue, error,
			# has_frames, thread_id]. Bridge tracks paused state and resolves a
			# pending wait_for_breakpoint / step_* / break_execution.
			if bridge != null:
				bridge.on_debug_enter(data)
		"debug_exit":
			# Game resumed (after continue/step moved on). Bridge clears paused
			# state and resolves a pending continue_execution.
			if bridge != null:
				bridge.on_debug_exit(data)
		"stack_dump":
			# Reply to get_stack_dump — also auto-requested by the editor on every
			# debug_enter (script_editor_debugger.cpp:354); harmless when no request
			# is pending (bridge ignores ownerless dumps). data[0] = field total.
			if bridge != null:
				bridge.on_stack_dump(parse_stack_dump(data))
		"stack_frame_vars":
			# Header of one frame's variables: data[0] = total var count.
			if bridge != null:
				bridge.on_stack_frame_vars(data)
		"stack_frame_var":
			# One variable (local/member/global) of the current frame; sent N
			# times after stack_frame_vars. Bridge accumulates, resolves when full.
			if bridge != null:
				bridge.on_stack_frame_var(parse_stack_frame_var(data))
		"evaluation_return":
			# Reply to evaluate — a single ScriptStackVariable (scope=3).
			if bridge != null:
				bridge.on_evaluation_return(parse_stack_frame_var(data))


# Called by McpBridge to push a command into the running game (mcp: namespace).
func send_to_game(kind: String, data: Array) -> bool:
	var session := _get_live_session()
	if session == null:
		return false
	session.send_message("mcp:" + kind, data)
	return true


# Send a stock (un-prefixed) debug command to the running game — used by the
# breakpoint tools. Unlike send_to_game (adds "mcp:") and request_scene_tree
# (adds "scene:"), breakpoint commands carry NO prefix: the keys are exactly
# "breakpoint" / "get_stack_dump" / "get_stack_frame_vars" / "step" / "next" /
# "out" / "continue" / "break" / "evaluate". send_message defaults the thread to
# MAIN_ID (script_editor_debugger.h:290) — correct for single-threaded games.
func send_debug_command(key: String, data: Array) -> bool:
	var session := _get_live_session()
	if session == null:
		return false
	session.send_message(key, data)
	return true


# Set or remove a breakpoint. The "breakpoint" command is fire-and-forget (no
# reply), so we record it in _breakpoints and replay on every new game session
# (_setup_session) — otherwise stopping & re-Playing loses it. file must be a
# res:// path; payload order is [file, line, enabled] (file FIRST — easy to flip).
func set_breakpoint(file: String, line: int, enabled: bool) -> Dictionary:
	var applied_now := false
	var session := _get_live_session()
	if session != null:
		session.send_message("breakpoint", [file, line, enabled])
		applied_now = true
	# Record/clear regardless of session liveness, so the next session replays it.
	var found := -1
	for i in range(_breakpoints.size()):
		var bp: Dictionary = _breakpoints[i]
		if String(bp.get("file", "")) == file and int(bp.get("line", 0)) == line:
			found = i
			break
	if enabled:
		if found < 0:
			_breakpoints.append({"file": file, "line": line})
	else:
		if found >= 0:
			_breakpoints.remove_at(found)
	return {
		"file": file,
		"line": line,
		"enabled": enabled,
		"applied_now": applied_now,
		"note": ("" if applied_now else "no live session; will apply on next Play"),
	}


func clear_breakpoints() -> Dictionary:
	var session := _get_live_session()
	for bp in _breakpoints:
		if session != null:
			session.send_message("breakpoint", [String(bp.get("file", "")), int(bp.get("line", 0)), false])
	var n := _breakpoints.size()
	_breakpoints.clear()
	return {"cleared": n, "applied_now": session != null}


# Replay every recorded breakpoint to a freshly-started game session (called at
# the end of _setup_session). Uses get_session() directly rather than
# _get_live_session() — the session may not report is_active() yet right after
# it is created.
func _replay_breakpoints(session_id: int) -> void:
	if _breakpoints.is_empty():
		return
	var session := get_session(session_id)
	if session == null:
		return
	for bp in _breakpoints:
		session.send_message("breakpoint", [String(bp.get("file", "")), int(bp.get("line", 0)), true])
	McpLog.log("[godot-mcp] replayed %d breakpoint(s) to new session" % _breakpoints.size())


# ScriptEditorDebugger "started" signal — fires when a game connects (Play), right
# after set_pid. In 4.7.1 this did NOT fire reliably on Play, so the bridge also
# edge-detects session-active transitions (sync_breakpoints_to_game) as the
# reliable sync. This handler is kept + logged to confirm whether it fires.
func _on_debugger_started() -> void:
	McpLog.log("[godot-mcp] started signal fired (breakpoints=%d)" % _breakpoints.size())
	if not _breakpoints.is_empty():
		_replay_breakpoints(_active_session_id)


# Sync all recorded breakpoints to the currently-live game session. Called by
# McpBridge when it detects the session just became active (Play). _setup_session
# only fires at editor startup (NOT per Play in 4.7.1), so the bridge edge-detects
# the inactive→active transition and calls this to replay breakpoints to each
# fresh game process.
func sync_breakpoints_to_game() -> void:
	if _breakpoints.is_empty():
		return
	var session := _get_live_session()
	if session == null:
		return
	for bp in _breakpoints:
		session.send_message("breakpoint", [String(bp.get("file", "")), int(bp.get("line", 0)), true])
	McpLog.log("[godot-mcp] synced %d breakpoint(s) to live game session" % _breakpoints.size())


# Ask the running game for its scene tree. The game's built-in SceneDebugger
# replies with "scene:scene_tree" (received in _on_debug_data).
func request_scene_tree() -> bool:
	var session := _get_live_session()
	if session == null:
		return false
	session.send_message("scene:request_scene_tree", [])
	return true


# Ask the running game for one node's runtime properties. The game replies with
# "scene:inspect_objects" (received in _on_debug_data). update_selection=false
# so the reply is a pure query (not "remote_objects_selected", which would
# mutate the editor's selection).
func request_inspect(object_id: int) -> bool:
	var session := _get_live_session()
	if session == null:
		return false
	session.send_message("scene:inspect_objects", [[object_id], false])
	return true


# Set a node property (fire-and-forget), then immediately re-request its
# properties so the bridge can verify the new value landed. The set is the
# stock "scene:set_object_property" message (scene_debugger.cpp:631, 287) — it
# has NO reply and silently no-ops on a missing object/property, so we pair it
# with an inspect_objects request whose reply the bridge matches back to the
# pending set_node_property call (see mcp_bridge.gd::on_inspect_objects).
func request_set_property(object_id: int, prop: String, value: Variant) -> bool:
	var session := _get_live_session()
	if session == null:
		return false
	session.send_message("scene:set_object_property", [object_id, prop, value])
	session.send_message("scene:inspect_objects", [[object_id], false])
	return true


# --- wire parsing (delegated to McpWire; see mcp_wire.gd) ---
# parse_scene_tree / parse_inspect_objects forward to _wire. The actual parsing
# lives in mcp_wire.gd (extends RefCounted) — extracted because this script
# extends EditorDebuggerPlugin, which Godot won't instantiate outside the editor
# ("Class 'EditorDebuggerPlugin' can only be instantiated by editor").
func parse_scene_tree(arr: Array) -> Dictionary:
	return _wire.parse_scene_tree(arr)


func parse_inspect_objects(data: Array) -> Array:
	return _wire.parse_inspect_objects(data)


func parse_stack_dump(arr: Array) -> Array:
	return _wire.parse_stack_dump(arr)


func parse_stack_frame_var(arr: Array) -> Dictionary:
	return _wire.parse_stack_frame_var(arr)


func has_active_session() -> bool:
	return _get_live_session() != null


# 当前真正活跃的 session(game stop 后 peer 断开 → is_active()==false,被过滤掉)。
# 不缓存"是否活跃"——每次现查 session.is_active()(peer 是否还连着,Godot 官方
# 判定),所以无需监听 session.stopped 信号、无残留。和竞品 is_playing_scene()
# 现查同思路(拉模式优于推模式)。
func _get_live_session() -> EditorDebuggerSession:
	if _active_session_id < 0:
		return null
	var session := get_session(_active_session_id)
	if session == null:
		return null
	if not session.is_active():
		return null
	return session
