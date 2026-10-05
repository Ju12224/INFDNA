extends SceneTree
# Filmstrip of the Tunnel Borer (scene/creatures_view.gd _draw_worm): runs the colony live and saves a picture every `every` sim seconds with
# the camera on the worm. Needs a display. Run with a fixed frame rate so the sim steps are the same on a slow machine:
#   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --resolution 1920x1057 --fixed-fps 30 \
#     --script res://tests/worm_film.gd -- out=/tmp/worm zoom=2.5 n=10 every=2 speed=3 mode=live
#   mode   live = a real borer from the meadow, down the hole and through the soil toward the queen; path = a borer driven along a
#          bent tunnel (right, down, back left, up a shaft, right again) carved in the soil, so every kind of corner shows
#   n, every   frames, and sim seconds between them;  speed  sim speed (the head crawls this much faster; path mode scales it likewise)
#   crop   half width,half height of the middle of the screen kept in the contact sheet (it is made by tests/worm_sheet.py)
var _node
var _f := 0
var _a := {"out": "/tmp/worm", "zoom": "2.5", "n": "10", "every": "2.0", "speed": "3", "mode": "live", "warm": "5"}
var _e = null
var _path := []
var _s := 0.0
var _vt := 0.0
var _next := 0.0
var _saved := 0


func _init() -> void:
	for x in OS.get_cmdline_user_args():
		var kv = x.split("=", true, 1)
		if kv.size() == 2:
			_a[kv[0]] = kv[1]
	seed(7)
	_node = load("res://scene/colony.tscn").instantiate()
	root.add_child(_node)


func _process(_d: float) -> bool:
	_f += 1
	var sim = _node.sim
	var g = sim.grid
	if _f == 1:
		_node.debug_setup({"zoom": _a["zoom"], "frames": "1"})
		sim.enemies.clear()
		_node.speed = float(_a["speed"])
		if _a["mode"] == "live":
			sim._spawn_enemy("borer", 1, 0)
			_e = sim.enemies.back()
			_e.max_hp = 1e9
			_e.hp = 1e9
		else:
			_make_path()
			_node.speed = 0.0
		var ph0 = sim.phenotype(sim.ants[0].genome) if not sim.ants.is_empty() else {}
		print("ant len px ", _node.views["creatures"]._ant_len(float(ph0.get("size", 74.0))), " size ", ph0.get("size"))
		print("zoom ", _node.zoom(), " ants ", sim.ants.size(), " entrance ", g.entrance, " surf_y ", g.surf_y(int(g.entrance.x)))
	if _e == null or not sim.enemies.has(_e):
		if _f > 2:
			print("borer gone at frame ", _f)
			quit()
		return false
	if _a["mode"] == "path":
		_drive()
	elif _f > 1:
		pass
	_vt += (1.0 / 30.0) * float(_a["speed"])
	var view = _node.views["creatures"]
	var p = sim.enemy_pos(_e)
	var mid = p
	var w = view._worm.get(_e.id)
	if w != null and w["tr"].size() > 14:
		mid = (p + w["tr"][w["tr"].size() - 14]) * 0.5
	_node.cam.position = mid
	if _f >= int(_a["warm"]) and _vt >= _next:
		_next += float(_a["every"])
		var img = root.get_texture().get_image()
		var fn = "%s_%02d.png" % [_a["out"], _saved]
		img.save_png(fn)
		_saved += 1
		print("saved ", fn, " t=", snappedf(_vt, 0.1), " head ", p, " state ", _e.state)
		if _saved >= int(_a["n"]):
			quit()
	return false


func _make_path() -> void:
	var sim = _node.sim
	var g = sim.grid
	var ex = int(g.entrance.x) + 14
	var cur = Vector2i(ex, g.surf_y(ex) + 12)
	var legs = [Vector2i(22, 0), Vector2i(10, 10), Vector2i(0, 12), Vector2i(-24, 0), Vector2i(-8, -8), Vector2i(0, -10), Vector2i(20, 0), Vector2i(6, 6), Vector2i(0, 8), Vector2i(-14, 0)]
	_path = [cur]
	for leg in legs:
		var tgt = cur + leg
		while cur != tgt:
			cur += Vector2i(signi(tgt.x - cur.x), signi(tgt.y - cur.y))
			_path.append(cur)
	for c in _path:
		g._carve_raw(c.x, c.y, 1.35, true, 0, true)
	sim._spawn_enemy("borer", 1, ex)
	_e = sim.enemies.back()
	_e.max_hp = 1e9
	_e.hp = 1e9
	_e.state = 3
	_e.facing = 1
	_e.lane = 1.0
	_e.x = _path[0].x
	_e.y = _path[0].y
	_e.tx = _e.x
	_e.ty = _e.y
	_e.t = 0.0
	_e.stun_t = 0.0
	print("path cells ", _path.size())


func _drive() -> void:
	_s += (1.0 / 30.0) * float(_a["speed"]) * 2.24
	var i = int(_s)
	if i >= _path.size() - 1:
		quit()
		return
	var c = _path[i]
	var n = _path[i + 1]
	_e.x = c.x
	_e.y = c.y
	_e.tx = n.x
	_e.ty = n.y
	_e.t = _s - i
	if n.x != c.x:
		_e.facing = 1 if n.x > c.x else -1
