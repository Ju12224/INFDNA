extends SceneTree
# Opens a scene, lets it run, and saves a screenshot. Needs a display (xvfb-run on a server).
# Run: xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --script res://tests/shot.gd -- frames=120 out=/tmp/shot.png t=300 at=nest
# Opens the colony unless scene= says otherwise (scene=res://scene/title.tscn, run_end.tscn, lab.tscn); menu=1 opens the pause menu.

var _frames := 0
var _node
var _args := {"scene": "res://scene/colony.tscn", "frames": "120", "out": "user://shot.png"}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	if _args.has("queen"):
		load("res://scene/run.gd").queen_id = _args["queen"]     # queen=vampire: the queen the title screen shows picked
	if _args.has("seed"):
		seed(int(_args["seed"]))
	_node = load(_args["scene"]).instantiate()
	root.add_child(_node)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1 and _node.has_method("debug_setup"):
		_node.debug_setup(_args)
		for v in str(_args.get("hide", "")).split(",", false):
			if _node.views.has(v):
				_node.views[v].visible = false
		if _args.has("nocover"):
			_node.views["surface"]._cover.visible = false            # e.g. t=300 zoom=1.5 at=nest ph=0.0 (see scene/colony.gd)
	if _frames == 2 and _args.has("set") and "sim" in _node:
		for kv in str(_args["set"]).split(","):          # set=arc_stage:2,raid_n:12 - sim fields, to show the top bar's rarer states
			var p = kv.split(":")
			_node.sim.set(p[0], str_to_var(p[1]))
	if _frames == 2 and _args.has("menu") and "views" in _node and _node.views.has("hud"):
		_node.views["hud"]._open_menu()     # menu=1: the Esc pause menu over the colony
	if _frames == int(_args["frames"]):
		var img = root.get_texture().get_image()
		img.save_png(_args["out"])
		print("saved ", _args["out"], " ", img.get_size())
		quit()
	return false
