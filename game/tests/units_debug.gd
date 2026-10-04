extends SceneTree
# Throwaway: a seeded screenshot plus a dump of the ants in view, and an overlay of the grid's solid cells (o=1).

var _frames := 0
var _node
var _args := {"frames": "60", "out": "user://units.png", "seed": "7"}


class Overlay extends Node2D:
	var colony
	var units

	func _process(_d):
		queue_redraw()

	func _draw():
		var g = colony.grid
		var vr = colony.view_rect(0)
		var C = 6.0
		for y in range(int(vr.position.y / C), int(vr.end.y / C) + 1):
			for x in range(int(vr.position.x / C), int(vr.end.x / C) + 1):
				if g.is_solid(x, y, 0):
					draw_rect(Rect2(x * C, y * C, C, C), Color(0, 1, 0, 0.25), false, 0.4)
				elif g.can_walk(x, y, 1) and g.is_solid(x, y, 0) == false:
					pass
		for a in colony.sim.ants:
			var p = colony.sim.ant_pos(a)
			if vr.has_point(p):
				var n = Vector2(-sin(a.rot), cos(a.rot))
				draw_line(p, p + n * 3.0, Color(1, 0, 0), 0.6)
				draw_circle(p + n * 3.0, 0.7, Color(1, 1, 0))


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	seed(int(_args["seed"]))
	_node = load("res://scene/colony.tscn").instantiate()
	root.add_child(_node)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_node.debug_setup(_args)
		if _args.get("o", "0") == "1":
			var o = Overlay.new()
			o.colony = _node
			o.z_index = 100
			_node.add_child(o)
	if _frames == int(_args["frames"]):
		var img = root.get_texture().get_image()
		img.save_png(_args["out"])
		var vr = _node.view_rect(300)
		var cam = _node.cam.position
		var z = _node.zoom()
		var size = root.get_visible_rect().size
		for a in _node.sim.ants:
			var p = _node.sim.ant_pos(a)
			if vr.has_point(p) and (a.carry > 0.0 or _args.get("all", "0") == "1"):
				var sp = (p - cam) * z + size * 0.5
				var uv = _node.views["units"]
				var st = uv._state.get(a.id, Vector3(-9, -9, -9))
				print("   state ", st)
				print("ant %d c%d z%d->%d (%d,%d)->(%d,%d) t=%.2f rot=%.2f f=%d carry=%.1f wings=%d screen=(%d,%d) under=%s" % [a.id, a.caste, a.z, a.tz,
					a.x, a.y, a.tx, a.ty, a.t, a.rot, a.facing, a.carry, a.ph["wings"], sp.x, sp.y, _node.grid.is_under(a.x, a.y)])
		print("saved ", _args["out"])
		quit()
	return false
