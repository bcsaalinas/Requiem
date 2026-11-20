@tool
extends EditorPlugin

# Godot MCP Bridge — EditorPlugin entry point.
#
# Wires together three pieces:
#   1. McpDebugger (EditorDebuggerPlugin) — the engine's official extension
#      point for the built-in debug protocol. Registers the "mcp:" capture
#      namespace so we can talk to the running game without an autoload that
#      the user has to install (zero project intrusion).
#   2. McpBridge (Node) — a local TCP server on 127.0.0.1:<port> that the
#      external TypeScript MCP server connects to. <port> is resolved by
#      _resolve_bridge_port (env GODOT_MCP_BRIDGE_PORT > ProjectSettings
#      godot_mcp/bridge_port > DEFAULT_BRIDGE_PORT) so several editors with
#      this plugin can run side-by-side on different ports.
#   3. ErrorCollector (Node) — buffers runtime errors for get_runtime_errors.
#
# Also SELF-REGISTERS the game-side autoload (McpRuntime -> mcp_runtime.gd)
# on _enter_tree and removes it on _exit_tree. This means enabling the plugin
# is the ONLY setup step — no manual project.godot edit, no separate autoload/
# directory to copy. (The autoload is needed only for runtime-side tools like
# screenshot; the editor-side tools — errors/scene_tree/inspect — work without
# it. But registering it unconditionally keeps setup trivial.)
#
# Lifecycle: _enter_tree creates all three + registers autoload;
# _exit_tree tears all down + unregisters autoload.

const McpDebugger = preload("res://addons/godot-mcp/mcp_debugger.gd")
const McpBridge = preload("res://addons/godot-mcp/mcp_bridge.gd")
const ErrorCollector = preload("res://addons/godot-mcp/error_collector.gd")
const McpAssets = preload("res://addons/godot-mcp/mcp_assets.gd")
const OutputCollector = preload("res://addons/godot-mcp/output_collector.gd")

const DEFAULT_BRIDGE_PORT := 6510  # fallback; overridden by _resolve_bridge_port
# The game-side autoload we manage. Path is inside our addon dir so the whole
# plugin ships as a single addons/godot-mcp/ folder.
const _AUTOLOAD_NAME := "McpRuntime"
const _AUTOLOAD_PATH := "res://addons/godot-mcp/mcp_runtime.gd"
const McpLog = preload("res://addons/godot-mcp/mcp_log.gd")  # shared VERBOSE switch + McpLog.log() (see mcp_log.gd)

# Untyped on purpose: McpDebugger extends EditorDebuggerPlugin (a RefCounted,
# NOT a Node), while McpBridge and ErrorCollector are Nodes — they reference
# each other across scripts, so typing them would force circular preloads.
# Duck-typing is fine.
var _debugger  # McpDebugger (mcp_debugger.gd)
var _bridge  # McpBridge (mcp_bridge.gd)
var _collector  # ErrorCollector (error_collector.gd)
var _assets  # McpAssets (mcp_assets.gd) — editor-time asset queries (mode ③)
var _output_collector  # OutputCollector (output_collector.gd) — print/console-log source for get_console_output

# True only when WE registered the autoload (this session) OR it was already
# pointing at our path (a previous session). Used so _exit_tree cleans up only
# our own autoload and never clobbers a user's same-named autoload.
var _owns_autoload := false


func _enter_tree() -> void:
	_debugger = McpDebugger.new()
	add_debugger_plugin(_debugger)

	_bridge = McpBridge.new()
	_bridge.debugger = _debugger
	_debugger.bridge = _bridge
	_bridge.port = _resolve_bridge_port()
	add_child(_bridge)
	_bridge.start()

	# ErrorCollector polls the editor's Output panel for runtime errors and
	# exposes them to the bridge (-> get_runtime_errors tool).
	_collector = ErrorCollector.new()
	add_child(_collector)
	_bridge.collector = _collector
	_debugger.collector = _collector  # so McpDebugger can push structured errors

	# McpAssets — editor-time project asset queries (list_assets etc., mode ③).
	# Like the collector, the bridge calls it directly (no game round-trip), so
	# these tools work without Play.
	_assets = McpAssets.new()
	add_child(_assets)
	_bridge.assets = _assets

	# OutputCollector — print/console-log source for get_console_output. Like
	# ErrorCollector, fed by McpDebugger._on_debug_data (the "output" message).
	_output_collector = OutputCollector.new()
	add_child(_output_collector)
	_debugger.output_collector = _output_collector
	_bridge.output_collector = _output_collector

	_register_autoload()


func _exit_tree() -> void:
	_unregister_autoload()
	if _bridge:
		_bridge.collector = null
		_bridge.assets = null
		_bridge.stop()
		_bridge.queue_free()
		_bridge = null
	if _collector:
		_collector.queue_free()
		_collector = null
	if _assets:
		_assets.queue_free()
		_assets = null
	if _output_collector:
		_output_collector.queue_free()
		_output_collector = null
	if _debugger:
		remove_debugger_plugin(_debugger)
		_debugger = null


# Register the game-side autoload (the mcp: capture handler) so enabling this
# plugin is the only setup step. Idempotent: if it's already at our path (e.g.
# after an editor restart, we registered it last session) we just claim it for
# cleanup. We never overwrite an autoload of the same name pointing elsewhere —
# that's the user's, leave it alone with a warning.
func _register_autoload() -> void:
	var key := "autoload/" + _AUTOLOAD_NAME
	var existing := String(ProjectSettings.get_setting(key, ""))
	var wanted := "*" + _AUTOLOAD_PATH
	if existing == wanted:
		_owns_autoload = true  # ours from a prior session — claim for cleanup
		return
	if existing != "":
		push_warning("[godot-mcp] autoload '%s' already set to %s (not our path); leaving it untouched" % [_AUTOLOAD_NAME, existing])
		return
	ProjectSettings.set_setting(key, wanted)
	ProjectSettings.save()
	_owns_autoload = true
	McpLog.log("[godot-mcp] registered autoload %s -> %s" % [_AUTOLOAD_NAME, _AUTOLOAD_PATH])


# Remove the autoload we registered. Only acts if _owns_autoload (so disabling
# the plugin cleans up after itself, but we never delete an autoload we didn't
# create / claim).
func _unregister_autoload() -> void:
	if not _owns_autoload:
		return
	ProjectSettings.clear("autoload/" + _AUTOLOAD_NAME)
	ProjectSettings.save()
	_owns_autoload = false
	McpLog.log("[godot-mcp] unregistered autoload %s" % _AUTOLOAD_NAME)


# Resolve the bridge TCP port (highest priority wins):
#   1. env GODOT_MCP_BRIDGE_PORT — one-shot override, symmetric with the TS
#      server (server.ts reads the same env to know which port to dial).
#   2. ProjectSettings godot_mcp/bridge_port — per-project, persists in
#      project.godot. This is how multiple editors with this plugin run
#      side-by-side: give each project a different port (e.g. this dev project
#      6511, a real game project the default 6510).
#   3. DEFAULT_BRIDGE_PORT.
# Any out-of-range / malformed value falls back to the default rather than
# leaving the bridge unable to listen.
func _resolve_bridge_port() -> int:
	var env := OS.get_environment("GODOT_MCP_BRIDGE_PORT")
	if env.is_valid_int():
		var p := int(env)
		if p >= 1 and p <= 65535:
			return p
	var cfg = ProjectSettings.get_setting("godot_mcp/bridge_port", DEFAULT_BRIDGE_PORT)
	# @tool safety: get_setting returns a Variant; guard the type explicitly
	# (pitfalls #11 — untyped returns can silently misbehave).
	if typeof(cfg) == TYPE_INT and cfg >= 1 and cfg <= 65535:
		return cfg
	return DEFAULT_BRIDGE_PORT
