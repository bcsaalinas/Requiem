extends RefCounted
## Evidence is local output, never an imported or versioned game resource.

static func path(relative_path: String) -> String:
	var destination := "user://test-results/" + relative_path
	var directory := destination if destination.ends_with("/") else destination.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK:
		push_error("Cannot create capture output directory: " + directory)
	return destination
