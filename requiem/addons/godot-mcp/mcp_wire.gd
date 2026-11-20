extends RefCounted

# McpWire — pure parsing of Godot's debug wire formats, extracted from
# McpDebugger into a plain RefCounted.
#
# WHY THIS FILE EXISTS: McpDebugger extends EditorDebuggerPlugin, and Godot
# refuses to instantiate that class outside the editor
# ("Class 'EditorDebuggerPlugin' can only be instantiated by editor"). Any
# logic attached to McpDebugger is therefore unreachable outside the editor
# lifecycle. Moving the wire parsing here (RefCounted — instantiable anywhere)
# decouples it from that lifecycle and gives a single home for the formats most
# likely to drift across Godot versions: SceneDebuggerTree / SceneDebuggerObject
# / OutputError.
#
# McpDebugger holds a _wire instance and forwards parse_scene_tree /
# parse_inspect_objects here.

var _st_idx := 0  # cursor while parsing a scene:scene_tree payload


# --- scene:scene_tree parsing ---
# Wire format (SceneDebuggerTree::serialize, scene_debugger_object.cpp:329):
# a flat depth-first list, 6 elements per node:
#   [child_count:int, name:String, type:String, id:int(ObjectID),
#    scene_file_path:String, view_flags:int]
func parse_scene_tree(arr: Array) -> Dictionary:
	if arr.size() < 6:
		return {}
	_st_idx = 0
	var root := _read_tree_node(arr)
	root["children"] = _read_tree_children(arr, int(root["child_count"]))
	root.erase("child_count")
	return root


func _read_tree_node(arr: Array) -> Dictionary:
	var i := _st_idx
	_st_idx = i + 6
	var view_flags := int(arr[i + 5])
	return {
		"child_count": int(arr[i]),
		"name": String(arr[i + 1]),
		"type": String(arr[i + 2]),
		"id": int(arr[i + 3]),
		"scene_file_path": String(arr[i + 4]),
		# view_flags bits (scene_debugger_object.h:72-76): 2=has_visible_method,
		# 4=visible, 8=visible_in_tree. Node and Window-root have no is_visible,
		# so their flags stay 0 — only treat visible_in_tree as meaningful when
		# has_visible_method is set (see server.ts renderTree).
		"has_visible_method": (view_flags & 2) != 0,
		"visible": (view_flags & 4) != 0,
		"visible_in_tree": (view_flags & 8) != 0,
	}


func _read_tree_children(arr: Array, count: int) -> Array:
	var children := []
	for _i in range(count):
		var child := _read_tree_node(arr)
		child["children"] = _read_tree_children(arr, int(child["child_count"]))
		child.erase("child_count")
		children.append(child)
	return children


# --- scene:inspect_objects parsing ---
# Wire format (SceneDebuggerObject::serialize, scene_debugger_object.cpp:189):
# data = Array of objects, each = [id:int, class_name:String, props:Array].
# Each prop = [name:String, type:int(Variant::Type), hint:int, hint_string:String,
#              usage:int, value:Variant]. We keep name + a JSON-friendly value.
func parse_inspect_objects(data: Array) -> Array:
	var objects := []
	for obj_arr in data:
		if typeof(obj_arr) != TYPE_ARRAY or obj_arr.size() < 3:
			continue
		var props_in: Array = obj_arr[2]
		var props_out := []
		for prop in props_in:
			if typeof(prop) != TYPE_ARRAY or prop.size() < 6:
				continue
			# prop = [name, type, hint, hint_string, usage, value]. Skip the
			# inspector's category/group/subgroup headers (usage flags) — they
			# aren't real properties and render as "<Group> = null".
			var usage := int(prop[4])
			if (usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP)) != 0:
				continue
			props_out.append({
				"name": String(prop[0]),
				"type": int(prop[1]),
				"value": _variant_to_jsonable(prop[5]),
			})
		objects.append({
			"id": int(obj_arr[0]),
			"class_name": String(obj_arr[1]),
			"properties": props_out,
		})
	return objects


# --- breakpoint debugging: stack_dump parsing ---
# Wire format (ScriptStackDump::serialize, debugger_marshalls.cpp:38-46):
# data = [field_total_count:int, file1, line1, func1, file2, line2, func2, ...]
# WARNING: the FIRST element is the total field count (frames × 3), NOT the
# frame count — frame_count = field_total / 3. frame 0 = top of stack (the
# function currently paused). Cross-version guard: stop a frame short if its
# trio would read past the end of the array.
func parse_stack_dump(arr: Array) -> Array:
	var frames := []
	if arr.size() < 1:
		return frames
	var n_frames := int(arr[0]) / 3
	var idx := 1
	for i in range(n_frames):
		if idx + 2 >= arr.size():
			break
		frames.append({
			"file": String(arr[idx]),
			"line": int(arr[idx + 1]),
			"function": String(arr[idx + 2]),
			"frame_level": i,  # 0 = top of stack
		})
		idx += 3
	return frames


# --- breakpoint debugging: stack_frame_var parsing ---
# Wire format (ScriptStackVariable::serialize, debugger_marshalls.cpp:65-88):
# data = [name:String, scope_type:int, variant_type:int, value:Variant, type_hint:String]
# scope_type: 0=local, 1=member, 2=global, 3=evaluate. The "evaluate" reply
# (evaluation_return) is itself a single ScriptStackVariable with scope=3, so
# this parser is reused for it.
# value arrives already decoded by the debug protocol into a Variant. Two cases
# silently replace value with nil (debugger_marshalls.cpp:69-83): a null Object
# reference, OR any value larger than 1 MiB (max_size = 1<<20). We can't tell
# those apart from a genuine nil, so `truncated` flags "variant_type says non-NIL
# but value is null" — i.e. the value was dropped, see it as possibly incomplete.
func parse_stack_frame_var(arr: Array) -> Dictionary:
	if arr.size() < 5:
		return {}
	var variant_type := int(arr[2])
	var raw_value: Variant = arr[3]
	return {
		"name": String(arr[0]),
		"scope": int(arr[1]),
		"variant_type": variant_type,
		"value": _variant_to_jsonable(raw_value),
		"type_hint": String(arr[4]),
		"truncated": (raw_value == null and variant_type != TYPE_NIL),
	}


# Convert a runtime Variant into something JSON-serializable for the bridge.
# Primitives pass through; compound/engine types (Vector2, Color, Node refs, ...)
# become their var_to_str form (e.g. "Vector2(100, 200)") so the AI still sees
# type + value. Without this, JSON.stringify would choke on non-JSON Variants.
# Underscore-prefixed but accessed from outside this file (GDScript has no private).
func _variant_to_jsonable(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		_:
			return var_to_str(v)
