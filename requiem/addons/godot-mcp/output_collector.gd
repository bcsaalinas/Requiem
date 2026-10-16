@tool
extends Node

# OutputCollector — the print/console-log source for get_console_output.
#
# print() / print_rich() / printerr() in the game travel as the "output" debug
# message (NOT "error" — that's push_error/push_warning, captured by
# ErrorCollector → get_runtime_errors). The two are SEPARATE streams; pitfalls #1.
#
# The "output" message's data is [PackedStringArray strings, PackedInt32Array
# types] — parallel arrays, each index one print entry. type: 0=LOG (print),
# 1=ERROR (printerr — NOT push_error!), 2=LOG_RICH (print_rich). The game batches
# one frame's prints into a single "output" wire message (flush_output,
# remote_debugger.cpp:206-241), so one message may carry many entries — we split
# per-index so the MCP tool's granularity matches actual print calls.
#
# Game-side throttling (32k chars/s, 2048 queued msgs, one wire msg/frame,
# remote_debugger.cpp / main.cpp:2290-2293) already bounds the flow. We just need
# a ring buffer to cap long-term memory.

const _BUFFER_CAP := 500

var _lines: Array = []  # ring buffer of {seq, text, type, type_name}
var _seq := 0


# Called by McpDebugger._on_debug_data when an "output" message arrives.
# Splits the parallel [strings, types] arrays into individual entries.
func push_output_data(data: Array) -> void:
	if data.size() < 2:
		return
	var strings: PackedStringArray = data[0]
	var types: PackedInt32Array = data[1]
	var n := strings.size()
	if types.size() < n:
		n = types.size()
	var i := 0
	while i < n:
		var t := int(types[i])
		_seq += 1
		_lines.append({
			"seq": _seq,
			"text": String(strings[i]),
			"type": t,
			"type_name": _type_name(t),
		})
		i += 1
	while _lines.size() > _BUFFER_CAP:
		_lines.pop_front()


func _type_name(t: int) -> String:
	match t:
		0: return "log"
		1: return "error"  # printerr — NOT push_error (different stream than get_runtime_errors)
		2: return "rich"
		_: return "unknown"


# Returns buffered lines, optionally filtered by type_name, draining by default.
# types (optional): ["log", "rich", "error"] — empty = all types.
func take(types: Array = [], clear: bool = true) -> Array:
	var filter := types.size() > 0
	var out: Array = []
	for line in _lines:
		var tn := String(line.get("type_name", ""))
		if not filter or types.has(tn):
			out.append(line)
		else:
			if clear:
				# filtered-out lines are still drained when clear=true (drain semantics)
				pass
	if clear:
		_lines.clear()
	return out


func count() -> int:
	return _lines.size()


# Diagnostic snapshot — exposed via the bridge if useful (mirrors error_collector).
func get_status() -> Dictionary:
	var last: Dictionary = _lines[_lines.size() - 1] if _lines.size() > 0 else {}
	return {
		"capture": "debug_data signal (output message)",
		"buffered_lines": _lines.size(),
		"cap": _BUFFER_CAP,
		"last_line": last,
	}
