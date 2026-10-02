extends SceneTree
# Compile-check every mod script (GDScript parse + resolve preloads). Prints FAIL lines; exit code 1 on failure.
func _walk(dir_path: String, out: Array) -> void:
	var d = Directory.new()
	if d.open(dir_path) != OK:
		return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		var full = dir_path.plus_file(n)
		if d.current_is_dir():
			_walk(full, out)
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()

func _init():
	var files := []
	_walk("res://mods-unpacked", files)
	files.sort()
	var bad = 0
	for f in files:
		var s = load(f)
		if s == null or not (s is GDScript) or not s.can_instance():
			print("FAIL ", f)
			bad += 1
		else:
			print("ok   ", f.get_file())
	print("COMPILE %d files, %d failed" % [files.size(), bad])
	quit(1 if bad > 0 else 0)
