# Centralized verbose logging for the godot-mcp addon.
#
# Startup/connection logs (session ready, sniffer connected, bridge listening,
# autoload registered, mcp peer connect/disconnect, breakpoint sync…) are handy
# while developing the plugin but are noise for game devs who just enable it.
# Every addon script calls McpLog.log() instead of print(), so this single
# VERBOSE switch gates them all — flip it to true here and every log across
# plugin.gd / mcp_bridge.gd / mcp_debugger.gd / mcp_runtime.gd lights up.
#
# Why a shared script and not a const+func per file? GDScript is single-
# inheritance: each addon script already `extends` a different engine class
# (EditorPlugin / Node / EditorDebuggerPlugin), so they can't share a common
# logger base class. A preloaded script with a static method is the idiomatic
# way to share one const + behavior across them, with nothing to desync.

const VERBOSE := false


static func log(msg) -> void:
	if VERBOSE:
		print(msg)
