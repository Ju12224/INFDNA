extends SceneTree
# Wheel-zoom filmstrip: rolls the wheel at a mouse point (colony._zoom_at, one notch every `gap` frames) from stop to stop of `path` and
# saves a frame once the zoom has settled at each stop. Run with --fixed-fps 30 (and a display) so the eased zoom takes the time it does live.
# args: seed t at zoom ph mx my path (zoom stops, e.g. 2.5,1.6,1,0.6,0.3) k (notch size) gap settle out
# e.g. xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --resolution 1920x1057 --fixed-fps 30 \
#        --script res://tests/_film25.gd -- seed=5 t=900 at=surface zoom=2.5 mx=0.5 my=0.7 path=2.5,1.6,1,0.6,0.3 out=/tmp/film
var _f := 0
var _node
var _a := {"seed": "5", "t": "900", "at": "surface", "zoom": "2.5", "ph": "0.5", "mx": "0.5", "my": "0.7", "path": "2.5,1.6,1.0,0.6,0.3",
	"k": "1.18", "gap": "2", "settle": "24", "out": "/tmp/film"}
var _stops := []
var _i := 0
var _wait := 0


func _init() -> void:
	for x in OS.get_cmdline_user_args():
		var kv = x.split("=", true, 1)
		if kv.size() == 2:
			_a[kv[0]] = kv[1]
	seed(int(_a["seed"]))
	for s in str(_a["path"]).split(",", false):
		_stops.append(float(s))
	_node = load("res://scene/colony.tscn").instantiate()
	root.add_child(_node)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 1:
		_node.debug_setup(_a)
		for v in str(_a.get("hide", "")).split(",", false):
			if _node.views.has(v):
				_node.views[v].visible = false
	if _f < 6:
		return false
	var vs = _node.get_viewport_rect().size
	var mp = Vector2(float(_a["mx"]) * vs.x, float(_a["my"]) * vs.y)
	var goal: float = _stops[_i]
	var k = float(_a["k"])
	var z = _node._zoom_target
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img = root.get_texture().get_image()
			var path = "%s_%02d.png" % [_a["out"], _i]
			img.save_png(path)
			print("frame ", _i, " zoom ", snappedf(_node.zoom(), 0.01), " cam ", _node.cam.position.snapped(Vector2.ONE), " -> ", path)
			_i += 1
			if _i >= _stops.size():
				quit()
		return false
	if abs(log(z / goal)) > 0.5 * log(k) and _f % int(_a["gap"]) == 0:
		_node._zoom_at(mp, k if goal > z else 1.0 / k)        # a wheel notch
	elif abs(log(z / goal)) <= 0.5 * log(k):
		_wait = int(_a["settle"])
	return false
