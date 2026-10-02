extends Reference
# The inside of the nest, layered: between the rear wall and the front dirt (so it only shows where the
# tunnels are open) hang roots, dirt drips, pebbles, crumbs and glowing fungus, and light falls down
# the shafts from the entrances. Built once per 32-column chunk into a cached mesh (mesh_kit.gd) from the
# open cells that have a ceiling or a floor, and rebuilt (throttled) when the tunnels change.

const MK = preload("res://mods-unpacked/Judah-InfDNA/content/colony/mesh_kit.gd")

const INK = Color("#15121a")
const CH = 32
const MAX_ROWS = 175

var sim
var g
var _chunks := {}            # chunk index -> {mesh, t}
var _vis := []
var _t := 0.0
var _open_ver := -999
var _stale := false
var _lo := 0
var _hi := 0
var _range_t := 0.0


func _init(sim_) -> void:
	sim = sim_
	g = sim_.grid


func prepare(cols: Array, t: float) -> void:
	_t = t
	_range_t -= 0.016
	if _range_t <= 0.0:
		_range_t = 1.0
		_lo = int(g.entrance.x) - 70
		_hi = int(g.entrance.x) + 70
		for en in g.entrances:
			_lo = min(_lo, int(en.x) - 45)
			_hi = max(_hi, int(en.x) + 45)
		for c in sim.planner.chambers:
			_lo = min(_lo, int(c["center"].x - c["rx"]) - 25)
			_hi = max(_hi, int(c["center"].x + c["rx"]) + 25)
		if abs(g.open_under - _open_ver) >= 6:
			_open_ver = g.open_under
			_stale = true
	var c_lo = int(floor(float(max(cols[0], _lo)) / CH))
	var c_hi = int(floor(float(min(cols[1], _hi)) / CH))
	var budget = 6 if _chunks.empty() else 1
	_vis = []
	for ci in range(c_lo, c_hi + 1):
		var ch = _chunks.get(ci)
		if ch == null or (_stale and t - ch["t"] > 3.0):
			if budget > 0:
				budget -= 1
				ch = _build(ci)
				_chunks[ci] = ch
		if ch != null and ch["mesh"] != null:
			_vis.append(ch["mesh"])
	if _stale:
		var all_fresh = true
		for ci2 in range(c_lo, c_hi + 1):
			var c2 = _chunks.get(ci2)
			if c2 == null or t - c2["t"] > 3.0:
				all_fresh = false
		if all_fresh:
			_stale = false


func draw(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_shafts(ci)
	for m in _vis:
		ci.draw_mesh(m, null)


# Daylight falling down each shaft, leaning with the sun.
func _shafts(ci: CanvasItem) -> void:
	var C = g.CELL
	for en in g.entrances:
		var x = (en.x + 0.5) * C
		var y = g.surf_y(int(en.x)) * C
		var wob = sin(_t * 0.4 + x * 0.01) * 6.0
		var warm = Color(1.0, 0.93, 0.7, 0.2)
		var none = Color(1.0, 0.93, 0.7, 0.0)
		ci.draw_polygon(PoolVector2Array([Vector2(x - 16, y), Vector2(x + 16, y), Vector2(x - 50 + wob, y + 380), Vector2(x - 190 + wob, y + 380)]),
			PoolColorArray([warm, warm, none, none]))


func _build(ci: int) -> Dictionary:
	var mk = MK.new()
	var C = g.CELL
	var W = g.W
	var ox = g.ox
	var solid = g.solid
	var under = g.under
	var c0 = ci * CH
	for x in range(c0, c0 + CH):
		if x < ox + 2 or x >= ox + W - 2:
			continue
		var sy = g.surf_y(x)
		for y in range(sy + 2, min(sy + MAX_ROWS, g.H - 2)):
			var j = y * W + (x - ox)
			if solid[j] != 0 or under[j] == 0:
				continue
			var up = solid[j - W]
			var dn = solid[j + W]
			if up == 0 and dn == 0:
				continue
			var h = MK.hash1(x * 7.31 + y * 3.17)
			var sd = x * 1.7 + y * 0.9
			var shade = 1.0 - 0.45 * clamp(float(y - sy) / 150.0, 0.0, 1.0)
			if up != 0:
				if h < 0.075:
					_root(mk, (x + 0.2 + 0.6 * MK.hash1(sd)) * C, y * C, sd, shade)
				elif h < 0.1:
					var dx = (x + 0.5) * C
					var dl = 6.0 + 8.0 * MK.hash1(sd + 2.0)
					mk.tri(Vector2(dx - 3.5, y * C), Vector2(dx + 3.5, y * C), Vector2(dx + (MK.hash1(sd) - 0.5) * 2.0, y * C + dl), Color(0.3 * shade + 0.1, 0.2 * shade + 0.07, 0.12 * shade + 0.04))
			if dn != 0:
				var fy = (y + 1) * C
				var fx = (x + 0.15 + 0.7 * MK.hash1(sd + 4.0)) * C
				if h < 0.04:
					var rr = 2.4 + 3.4 * MK.hash1(sd + 5.0)
					mk.ellipse_ink(Vector2(fx, fy - rr * 0.5), rr, rr * 0.65, Color(0.52 * shade + 0.1, 0.5 * shade + 0.08, 0.46 * shade + 0.08), 1.2, 9)
				elif h < 0.062:
					_fungus(mk, fx, fy, sd, shade)
				elif h < 0.085:
					for k in 3:
						mk.ellipse(Vector2(fx + (k - 1) * 3.2, fy - 1.0), 1.6, 1.1, Color(0.36 * shade + 0.1, 0.25 * shade + 0.07, 0.15 * shade + 0.05), 6)
	return {"mesh": mk.build(), "t": _t}


func _root(mk, x0: float, y0: float, sd: float, shade: float) -> void:
	var n = 5
	var ln = 8.0 + 22.0 * MK.hash1(sd + 1.0)
	var pts := PoolVector2Array()
	var wid := PoolRealArray()
	var wink := PoolRealArray()
	var side = (MK.hash1(sd + 3.0) - 0.5) * 8.0
	for i in n:
		var t = float(i) / (n - 1)
		pts.append(Vector2(x0 + sin(t * 3.0 + sd) * 2.5 * t + side * t * t, y0 + ln * t))
		wid.append(3.2 * (1.0 - t) + 0.9)
		wink.append(3.2 * (1.0 - t) + 3.2)
	var rc = Color(0.34 * shade + 0.06, 0.22 * shade + 0.04, 0.12 * shade + 0.03)
	mk.ribbon(pts, wink, INK)
	mk.ribbon(pts, wid, rc, rc.lightened(0.18))
	if MK.hash1(sd + 6.0) > 0.45:
		var p2 = pts[2]
		var tp := PoolVector2Array([p2, p2 + Vector2(side * 0.5 + 4.0, 4.0), p2 + Vector2(side * 0.8 + 8.0, 9.0)])
		mk.ribbon(tp, PoolRealArray([1.8, 1.3, 0.8]), rc)


func _fungus(mk, fx: float, fy: float, sd: float, shade: float) -> void:
	var cols = [Color("#7fe9d0"), Color("#ffcf6a"), Color("#b9a0ff")]
	var gc = cols[int(MK.hash1(sd + 7.0) * 2.99)]
	var n = 1 + int(MK.hash1(sd + 8.0) * 2.99)
	for i in n:
		var px = fx + (i - (n - 1) * 0.5) * 6.0
		var hh = 5.0 + 6.0 * MK.hash1(sd + i * 3.0)
		var cr = 3.0 + 2.6 * MK.hash1(sd + i * 5.0)
		mk.ellipse(Vector2(px, fy - hh), cr * 4.4, cr * 3.4, Color(gc.r, gc.g, gc.b, 0.07), 12)
		mk.ellipse(Vector2(px, fy - hh), cr * 2.4, cr * 1.9, Color(gc.r, gc.g, gc.b, 0.14), 12)
		mk.quad(Vector2(px - 1.1, fy), Vector2(px + 1.1, fy), Vector2(px + 0.8, fy - hh), Vector2(px - 0.8, fy - hh), Color(0.9 * shade + 0.1, 0.88 * shade + 0.1, 0.8 * shade + 0.1))
		mk.ellipse_ink(Vector2(px, fy - hh), cr, cr * 0.62, gc, 1.2, 10)
		mk.ellipse(Vector2(px - cr * 0.25, fy - hh - cr * 0.2), cr * 0.35, cr * 0.2, Color(1, 1, 1, 0.55), 6)
