@tool
extends Node

# ErrorCollector — the runtime-error source for get_runtime_errors.
#
# HOW ERRORS GET HERE (the hard-won path):
#   GDScript runtime errors (null access, push_error, SCRIPT ERROR) travel from
#   the game as a debug wire message keyed "error" — NO capture prefix. The
#   editor's ScriptEditorDebugger._parse_message emits a `debug_data(msg, data)`
#   signal for EVERY inbound message on its first line — including "error" —
#   BEFORE routing to the hardcoded _msg_error handler. McpDebugger connects to
#   that signal (via a session tab -> two get_parent() hops -> the
#   ScriptEditorDebugger) and forwards the structured payload here.
#
#   Why not the editor "Output" panel? Because print() goes to Output (via the
#   "output" message), but errors go to the Debugger panel (via "error"). They
#   are separate streams — an earlier version polled Output and saw zero errors.
#
#   Why not EditorDebuggerPlugin._capture? "error" is a hardcoded, unprefixed
#   message; _capture only sees "<capture>:<msg>" messages lacking a hardcoded
#   handler. Unsolvable at the capture layer — a Godot architectural limit,
#   confirmed against 4.7.1 source (script_editor_debugger.cpp:983-997, 1022).
#
# Wire format of the "error" message data (DebuggerMarshalls::OutputError,
# core/debugger/debugger_marshalls.cpp:101-149):
#   [0..3] hr, min, sec, msec
#   [4]  source_file (res://...)
#   [5]  source_func
#   [6]  source_line
#   [7]  error        (condition string, e.g. "Invalid access to property...")
#   [8]  error_descr  (custom description / push_error text; often "" for native errors)
#   [9]  warning      (bool)
#   [10] stack_elems  (= frame_count * 3)
#   [11..] per frame, 3 each: file, func, line

const _BUFFER_CAP := 200

var _errors: Array = []   # ring buffer of structured error dicts
var _seq := 0             # monotonic id assigned to each newly-seen error


# Called by McpDebugger._on_debug_data when an "error" message arrives.
# Parses the OutputError wire array into a structured dict and buffers it.
# Defensive: a malformed array must never crash the signal callback.
func push_error_data(data: Array) -> void:
	if data.size() < 11:
		return
	var is_warning: bool = bool(data[9])
	var stack_elems: int = int(data[10])
	var backtrace: Array = []
	var idx: int = 11
	var frame_count: int = stack_elems / 3
	for _i in range(frame_count):
		if idx + 2 >= data.size():
			break
		backtrace.append({
			"file": String(data[idx]),
			"function": String(data[idx + 1]),
			"line": int(data[idx + 2]),
		})
		idx += 3

	var error_cond: String = String(data[7])
	var error_descr: String = String(data[8])
	# error_descr is the user-facing message when present (push_error text or
	# GDScript exception detail); otherwise fall back to the condition string.
	var message: String = error_descr if error_descr.length() > 0 else error_cond

	_seq += 1
	_errors.append({
		"seq": _seq,
		"level": "warning" if is_warning else "error",
		"message": message,
		"condition": error_cond,
		"function": String(data[5]),
		"file": String(data[4]),
		"line": int(data[6]),
		"time": "%d:%02d:%02d:%03d" % [int(data[0]), int(data[1]), int(data[2]), int(data[3])],
		"backtrace": backtrace,
	})

	while _errors.size() > _BUFFER_CAP:
		_errors.pop_front()


# --- API used by McpBridge ---

# Returns buffered errors. By default filters out warnings and drains the
# buffer (so the next call only sees errors emitted after this one).
func take(include_warnings: bool = false, clear: bool = true) -> Array:
	var out: Array = []
	for e in _errors:
		if not include_warnings and String(e["level"]) == "warning":
			continue
		out.append(e)
	if clear:
		_errors.clear()
	return out


func count() -> int:
	return _errors.size()


# Diagnostic snapshot — exposed via the bridge's collector_status tool.
func get_status() -> Dictionary:
	var last: Dictionary = _errors[_errors.size() - 1] if _errors.size() > 0 else {}
	return {
		"capture": "debug_data signal (ScriptEditorDebugger)",
		"buffered_errors": _errors.size(),
		"last_error": last,
	}
