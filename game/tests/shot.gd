extends SceneTree
# Opens a scene, lets it run, and saves a screenshot. Needs a display (xvfb-run on a server).
# Run: xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --script res://tests/shot.gd -- scene=res://main.tscn frames=120 out=/tmp/shot.png

var _frames := 0
var _args := {"scene": "res://main.tscn", "frames": "120", "out": "user://shot.png"}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	root.add_child(load(_args["scene"]).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == int(_args["frames"]):
		var img = root.get_texture().get_image()
		img.save_png(_args["out"])
		print("saved ", _args["out"], " ", img.get_size())
		quit()
	return false
