extends SceneTree
# Opens a scene, lets it run, and saves a screenshot. Needs a display (xvfb-run on a server).
# Run: xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --script res://tests/shot.gd -- frames=120 out=/tmp/shot.png t=300 at=nest

var _frames := 0
var _node
var _args := {"scene": "res://scene/colony.tscn", "frames": "120", "out": "user://shot.png"}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_node = load(_args["scene"]).instantiate()
	root.add_child(_node)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1 and _node.has_method("debug_setup"):
		_node.debug_setup(_args)            # e.g. t=300 zoom=1.5 at=nest ph=0.0 (see scene/colony.gd)
	if _frames == int(_args["frames"]):
		var img = root.get_texture().get_image()
		img.save_png(_args["out"])
		print("saved ", _args["out"], " ", img.get_size())
		quit()
	return false
