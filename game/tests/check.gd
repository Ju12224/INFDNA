extends SceneTree
# Loads every script in the project and reports the ones that fail to compile.
# Run: godot --headless --path game --script res://tests/check.gd

func _init() -> void:
	var bad := 0
	var n := 0
	for p in _scripts("res://"):
		n += 1
		var s = load(p)
		if not (s is Script) or not s.can_instantiate():
			bad += 1
			print("FAIL ", p)
	print("checked %d scripts, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)


func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_scripts(dir.path_join(d)))
	return out
