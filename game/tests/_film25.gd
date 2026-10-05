extends SceneTree
# filmstrip: wheel-zoom in at a mouse point; saves a frame every `every` frames. args: seed t at zoom mx my notches every n out
var _f := 0
var _node
var _a := {"frames": "1", "seed": "5", "t": "1500", "at": "surface", "zoom": "2.5", "ph": "0.5", "mx": "0.5", "my": "0.4", "notches": "6", "every": "3", "n": "8", "out": "/tmp/film", "gap": "2", "start": "4", "k": "1.18"}
func _init() -> void:
	for x in OS.get_cmdline_user_args():
		var kv = x.split("=", true, 1)
		if kv.size() == 2:
			_a[kv[0]] = kv[1]
	seed(int(_a["seed"]))
	_node = load("res://scene/colony.tscn").instantiate()
	root.add_child(_node)
func _process(_d: float) -> bool:
	_f += 1
	if _f == 1:
		print("DBG before setup cam ", _node.cam.position, " entrance ", _node.grid.entrance, " ground_y ", _node.ground_y())
		_node.debug_setup(_a)
		for v in str(_a.get("hide", "")).split(",", false):
			if _node.views.has(v):
				_node.views[v].visible = false
		print("DBG after setup cam ", _node.cam.position, " time ", _node.sim.time, " collapsed ", _node.sim.collapsed, " entrance ", _node.grid.entrance, " center ", _node.grid.center(int(_node.grid.entrance.x), int(_node.grid.entrance.y)), " ents ", _node.grid.entrances.size())
	if _f <= 5:
		print("DBG f", _f, " cam ", _node.cam.position, " zoom ", _node.zoom(), " focus ", _node.focus, " frame_t ", _node._frame_t, " dolly ", _node.Band.dolly)
	var vs = _node.get_viewport_rect().size
	var mp = Vector2(float(_a["mx"]) * vs.x, float(_a["my"]) * vs.y)
	var st = int(_a["start"])
	var gap = int(_a["gap"])
	for i in int(_a["notches"]):
		if _f == st + i * gap:
			_node._zoom_at(mp, float(_a["k"]))
			if i == 0:
				var w = _node._screen_to_world(mp)
				print("DBG mouse world ", w, " ground ", _node.views["surface"].ground_y(w.x), " lane_under ", _node.lane_under(mp), " target ", _node.focus_target, " meadow ", _node.focus_meadow, " vs ", vs)
	var k = int(_a["every"])
	var idx = (_f - st) / k
	if _f >= st and (_f - st) % k == 0 and idx < int(_a["n"]):
		var img = root.get_texture().get_image()
		img.save_png("%s_%d.png" % [_a["out"], idx])
		print("frame ", idx, " zoom ", snappedf(_node.zoom(), 0.01), " focus ", snappedf(_node.focus, 0.1), " cam ", _node.cam.position.snapped(Vector2.ONE))
	if idx >= int(_a["n"]):
		quit()
	return false
