extends SceneTree
# A live filmstrip of one ant in the nest: runs a colony to t sim seconds, finds an ant in the wanted spot, then films the real game
# (sim stepping as in play) and saves 8 crops of it, `every` frames apart, side by side in one png (4 x 2).
#   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --resolution 1920x1057 --fixed-fps 30 \
#     --script res://tests/ants_film.gd -- t=600 zoom=2.5 follow=flat every=3 out=/tmp/film.png
# follow = flat | corner | slope | shaft | ceiling | floor | crowd | any (see _wanted); at=nest|surface|x,y; seed= repeats a colony.
# Prints, per saved frame, the ant's drawn cell, gait, tilt and body length (units_view.debug_frames) next to its sim state.

var _args := {"scene": "res://scene/colony.tscn", "t": "600", "zoom": "2.5", "at": "nest", "ph": "0.45", "follow": "flat", "every": "3", "out": "/tmp/film.png", "n": "8", "start": "10"}
var _node
var _uv
var _frames := 0
var _stamp := 0
var _ant := -1
var _crops := []
var _notes := []
var _last_p := Vector2.ZERO


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	seed(int(_args.get("seed", "7")))               # the colony's seed comes from randi(): the same seed gives the same colony
	_node = load(_args["scene"]).instantiate()
	root.add_child(_node)


# Is this ant what we are looking for? (cells; rot 0 = standing on a floor, PI = on a roof)
func _wanted(a, kind: String) -> bool:
	var g = _node.grid
	if not g.is_under(a.x, a.y) or not g.is_under(a.tx, a.ty) or a.dig_timer > 0.0 or a.z != a.tz:
		return false
	var moving: bool = a.tx != a.x or a.ty != a.y
	match kind:
		"flat":
			return moving and a.ty == a.y and abs(a.rot) < 0.06 and abs(a.trot) < 0.06
		"slope":
			return moving and abs(a.rot) > 0.25 and abs(a.rot) < 1.2
		"shaft":
			return moving and a.tx == a.x and abs(abs(a.rot) - PI * 0.5) < 0.5
		"ceiling":
			return moving and abs(a.rot) > 2.4
		"corner":
			return moving and abs(wrapf(a.trot - a.rot, -PI, PI)) > 0.5
		"floor":
			return not moving and abs(a.rot) < 0.06 and a.task == 0
		"any":
			return moving
	return false


func _find() -> int:
	var kind: String = _args["follow"]
	if kind == "crowd":
		var best := 0
		var best_id := -1
		var cnt := {}
		for a in _node.sim.ants:
			if _node.grid.is_under(a.x, a.y):
				var k = Vector2i(a.x / 3, a.y / 3)
				cnt[k] = cnt.get(k, 0) + 1
				if cnt[k] > best:
					best = cnt[k]
					best_id = a.id
		return best_id
	for step in 400:
		var pool := []
		for a in _node.sim.ants:
			if _wanted(a, kind):
				pool.append(a)
		if not pool.is_empty():
			return pool[int(_args.get("pick", "0")) % pool.size()].id
		for i in 5:
			_node.sim.step(0.1)
	return -1


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_node.debug_setup(_args)
		_uv = _node.views["units"]
		_uv.debug_on = true
		_ant = _find()
		print("following ant ", _ant, " (", _args["follow"], ")")
		return false
	if _ant < 0:
		quit()
		return true
	if _uv.debug_stamp == _stamp:
		return false
	_stamp = _uv.debug_stamp
	var df: Dictionary = _uv.debug_frames
	var a = null
	for u in _node.sim.ants:
		if u.id == _ant:
			a = u
			break
	if a == null:
		print("ant ", _ant, " is gone")
		_finish()
		return true
	var wp := Vector2.ZERO
	if df.has(_ant):
		wp = Vector2(df[_ant][8], df[_ant][9])
	else:
		wp = Vector2((a.x + 0.5) * 6.0, (a.y + 0.5) * 6.0)
	_last_p = wp
	_node.cam.position = _node.cam.position.lerp(wp, 0.5)
	var every: int = int(_args["every"])
	var start: int = int(_args["start"])
	if _frames >= start and (_frames - start) % every == 0 and _crops.size() < int(_args["n"]):
		_grab(a, df)
	if _crops.size() >= int(_args["n"]):
		_finish()
		return true
	return false


func _screen_of(wp: Vector2) -> Vector2:
	var cam: Camera2D = _node.cam
	return (wp - cam.get_screen_center_position()) * cam.zoom + root.get_visible_rect().size * 0.5


func _grab(a, df: Dictionary) -> void:
	var img: Image = root.get_texture().get_image()
	var sc = Vector2(img.get_size()) / root.get_visible_rect().size
	var sp: Vector2 = _screen_of(_last_p) * sc
	var w := 340
	var h := 250
	var x = clampi(int(sp.x) - w / 2, 0, img.get_width() - w)
	var y = clampi(int(sp.y) - h / 2, 0, img.get_height() - h)
	_crops.append(img.get_region(Rect2i(x, y, w, h)))
	var r = df.get(_ant, [])
	var note = "f%d cell %s moved %.2f gait %.2f | sim rot %.2f trot %.2f t %.2f xy %d,%d->%d,%d z%d task %d" % [_frames, str(r[1]) if r.size() > 1 else "-", r[3] if r.size() > 3 else 0.0, r[5] if r.size() > 5 else 0.0, a.rot, a.trot, a.t, a.x, a.y, a.tx, a.ty, a.z, a.task]
	if r.size() > 13:
		note += " | drawn rot %.2f len %.1f" % [r[13], r[14]]
	_notes.append(note)


func _finish() -> void:
	if not _crops.is_empty():
		var w: int = _crops[0].get_width()
		var h: int = _crops[0].get_height()
		var sheet = Image.create(w * 4, h * 2, false, Image.FORMAT_RGBA8)
		for i in _crops.size():
			sheet.blit_rect(_crops[i], Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
		sheet.save_png(_args["out"])
		print("saved ", _args["out"])
	for n in _notes:
		print(n)
	quit()
