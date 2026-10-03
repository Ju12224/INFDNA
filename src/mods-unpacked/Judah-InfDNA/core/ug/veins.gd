extends Reference
# The deep earth, an underground module (core/underground.gd; drawn by content/colony/ug/veins_view.gd). Four kinds:
#   vein   a thin winding band of quartz (pale, glassy) or iron-stained rock (rust) crossing the strata at an angle; more of
#          them deeper. Stamped as harder ground, never as stone: a quartz vein digs like shale, an iron vein like red clay, so
#          a vein is a slow band the diggers chew through, not a wall (and the terrain shader, which paints strata by depth,
#          needs no new material). The view draws the band itself.
#   geode  a hollow in the limestone or shale lined with crystals: amber, violet when deep or near the Void. The hollow is open
#          (front plane) inside a hard rind. The first time the colony breaks in it pays, once: +1 mutagen, or food when the
#          colony already holds three.
#   crack  hairline fissures in the deep floor where the Void shows through. Draw only: they brighten with the Monstrosity
#          meter, flash with each tremor, and after the collapse widen and climb toward the pit (sim.void_x).
#   mulch  bark chips and twig bits in the humus just under the turf. Draw only (art in content/art/mulch/ replaces the
#          procedural chips when it exists, see the view).
# Every feature is a pure function of the world seed and its block of columns (grid._ih), and one dictionary instance per
# feature is handed out (MEMO), so the view's cached geometry on it and on_carve's invalidation always meet.

const VEIN_B = 32            # vein candidates per block of columns
const VEIN_K = 3
const VEIN_STEPS = 96        # longest vein path (1-cell steps); the anchor is its middle
const VEIN_REACH = 52        # how far a vein can reach from its anchor column
const GEODE_B = 40
const GEODE_REACH = 8
const CRACK_B = 20
const CRACK_REACH = 50       # crack + its rising rift
const MULCH_B = 16

const MEMO = "infdna_ug_veins"         # Engine meta: {"gid": grid instance, "d": {feature id: dict or false}}
const STATE = "infdna_ug_veins"        # sim meta: {"open": {geode id: true}}
const GEODE_FOOD = 45.0


# ------------------------------------------------------------------ features
static func features(grid, xa: int, xb: int) -> Array:
	var out := []
	var memo = _memo(grid)
	for bx in range(_blk(xa - VEIN_REACH, VEIN_B), _blk(xb + VEIN_REACH, VEIN_B) + 1):
		for k in VEIN_K:
			_take(out, _lookup(memo, grid, "v", bx, k), xa, xb)
	for bx in range(_blk(xa - GEODE_REACH, GEODE_B), _blk(xb + GEODE_REACH, GEODE_B) + 1):
		_take(out, _lookup(memo, grid, "g", bx, 0), xa, xb)
	for bx in range(_blk(xa - CRACK_REACH, CRACK_B), _blk(xb + CRACK_REACH, CRACK_B) + 1):
		_take(out, _lookup(memo, grid, "c", bx, 0), xa, xb)
	for bx in range(_blk(xa, MULCH_B), _blk(xb, MULCH_B) + 1):
		_take(out, _lookup(memo, grid, "m", bx, 0), xa, xb)
	return out


static func _blk(x: int, b: int) -> int:
	return int(floor(float(x) / b))


static func _take(out: Array, f, xa: int, xb: int) -> void:
	if f is Dictionary and int(f["x1"]) >= xa and int(f["x0"]) <= xb:
		out.append(f)


static func _memo(grid) -> Dictionary:
	var gid = grid.get_instance_id()
	var m = Engine.get_meta(MEMO) if Engine.has_meta(MEMO) else null
	if m == null or m["gid"] != gid or m["d"].size() > 40000:
		m = {"gid": gid, "d": {}}
		Engine.set_meta(MEMO, m)
	return m["d"]


static func _lookup(memo: Dictionary, grid, kind: String, bx: int, k: int):
	var id = "%s%d:%d" % [kind, bx, k]
	if memo.has(id):
		return memo[id]
	var f = null
	match kind:
		"v":
			f = _make_vein(grid, bx, k)
		"g":
			f = _make_geode(grid, bx)
		"c":
			f = _make_crack(grid, bx)
		"m":
			f = _make_mulch(grid, bx)
	if f == null:
		memo[id] = false
		return false
	f["id"] = id
	memo[id] = f
	return f


# Rows below the original ground at (x, y), with the per-column seam wave (what strata_at measures).
static func _depth(grid, x: int, y: float) -> float:
	return y - grid.base_y(x) + grid.strata_off(x)


static func _in_nest(grid, x: float, y: float, pad: float) -> bool:
	return abs(x - grid._nest_x) < 20.0 + pad and y < grid._nest_y + 12.0 + pad


# A vein point may sit here: below the humus top, above the floor, outside the nest.
static func _vein_ok(grid, p: Vector2) -> bool:
	var x = int(floor(p.x))
	return p.y >= grid.base_y(x) + 5.0 and p.y <= grid.H - 4.5 and not _in_nest(grid, p.x, p.y, 1.5)


static func _make_vein(grid, bx: int, k: int):
	var u = grid._ih(bx, k, 7102)
	var d = 14.0 + 140.0 * sqrt(u)                       # rows below the ground: the deep end is favoured...
	var p = 0.14 + 0.5 * clamp((d - 14.0) / 140.0, 0.0, 1.0)
	if grid._ih(bx, k, 7101) >= p:                        # ...and more candidates survive there
		return null
	var ax = bx * VEIN_B + grid._ih(bx, k, 7103) * VEIN_B
	var ay = grid.base_y(int(floor(ax))) + d - grid.strata_off(int(floor(ax)))
	var anchor = Vector2(ax, ay)
	if not _vein_ok(grid, anchor):
		return null
	var quartz = grid._ih(bx, k, 7104) > clamp(0.8 - d / 130.0, 0.2, 0.7)   # iron staining is a shallow thing
	var n = 24 + int(grid._ih(bx, k, 7105) * (VEIN_STEPS - 24))
	var steep = grid._ih(bx, k, 7106) < 0.22
	var side = 1.0 if grid._ih(bx, k, 7107) < 0.5 else -1.0
	var a0 = side * (0.95 + 0.4 * grid._ih(bx, k, 7108)) if steep else (grid._ih(bx, k, 7108) - 0.5) * 0.9
	var a1 = 0.22 + 0.4 * grid._ih(bx, k, 7109)
	var f1 = 0.05 + 0.08 * grid._ih(bx, k, 7110)
	var p1 = grid._ih(bx, k, 7111) * TAU
	var a2 = 0.08 + 0.22 * grid._ih(bx, k, 7112)
	var f2 = 0.2 + 0.25 * grid._ih(bx, k, 7113)
	var p2 = grid._ih(bx, k, 7114) * TAU
	var wid = (0.75 + 0.9 * grid._ih(bx, k, 7115)) if quartz else (0.6 + 0.7 * grid._ih(bx, k, 7115))
	var p3 = grid._ih(bx, k, 7116) * TAU
	# walk out from the anchor both ways, stopping where the band would leave the deep ground
	var fwd := [anchor]
	var q = anchor
	for i in range(1, n / 2):
		var a = a0 + a1 * sin(i * f1 + p1) + a2 * sin(i * f2 + p2)
		q += Vector2(cos(a), sin(a))
		if not _vein_ok(grid, q):
			break
		fwd.append(q)
	var back := []
	q = anchor
	for i in range(1, n / 2):
		var a = a0 + a1 * sin(-i * f1 + p1) + a2 * sin(-i * f2 + p2)
		q -= Vector2(cos(a), sin(a))
		if not _vein_ok(grid, q):
			break
		back.append(q)
	back.invert()
	var path = back + fwd
	if path.size() < 10:
		return null
	var pts := PoolVector2Array()
	var ws := PoolRealArray()
	var m = path.size()
	var lo = Vector2(1e9, 1e9)
	var hi = Vector2(-1e9, -1e9)
	for i in m:
		var taper = clamp(min(i, m - 1 - i) / 7.0, 0.18, 1.0)
		var w = wid * taper * (0.78 + 0.32 * sin(i * 0.23 + p3))
		pts.append(path[i])
		ws.append(w)
		lo = Vector2(min(lo.x, path[i].x), min(lo.y, path[i].y))
		hi = Vector2(max(hi.x, path[i].x), max(hi.y, path[i].y))
	return {"kind": "vein", "x0": int(floor(lo.x)) - 1, "x1": int(ceil(hi.x)) + 1, "y0": int(floor(lo.y)) - 1, "y1": int(ceil(hi.y)) + 1,
		"y": int(ay), "pts": pts, "w": ws, "q": quartz, "d": d, "seed": grid._ih(bx, k, 7117)}


static func _make_geode(grid, bx: int):
	if grid._ih(bx, 0, 7201) >= 0.5:
		return null
	var cx = bx * GEODE_B + 5.0 + grid._ih(bx, 0, 7202) * (GEODE_B - 10)
	var ix = int(floor(cx))
	var d = 92.0 + grid._ih(bx, 0, 7203) * 56.0             # limestone and shale
	var rx = 2.1 + grid._ih(bx, 0, 7204) * 1.5
	var ry = min(rx, 1.6 + grid._ih(bx, 0, 7205) * 1.0)
	var cy = min(grid.base_y(ix) + d - grid.strata_off(ix), grid.H - 6.0 - ry)
	var dd = _depth(grid, ix, cy)
	if dd < 86.0 or _in_nest(grid, cx, cy, rx + 2.0):
		return null
	return {"kind": "geode", "x0": int(floor(cx - rx)) - 2, "x1": int(ceil(cx + rx)) + 2, "y0": int(floor(cy - ry)) - 2, "y1": int(ceil(cy + ry)) + 2,
		"y": int(cy), "cx": cx, "cy": cy, "rx": rx, "ry": ry, "d": dd, "v": smoothstep(118.0, 134.0, dd), "seed": grid._ih(bx, 0, 7206)}


static func _make_crack(grid, bx: int):
	if grid._ih(bx, 0, 7301) >= 0.72:
		return null
	var x = bx * CRACK_B + 2.0 + grid._ih(bx, 0, 7302) * (CRACK_B - 4)
	var y = grid.H - 4.0 - grid._ih(bx, 0, 7303) * 7.0
	if _depth(grid, int(floor(x)), y) < 104.0:
		return null
	# the main fissure climbs from the floor, jagging left and right of straight up
	var main := [Vector2(x, y)]
	var th = (grid._ih(bx, 0, 7304) - 0.5) * 0.9
	var n = 9 + int(grid._ih(bx, 0, 7305) * 18)
	var p = Vector2(x, y)
	var heads := [th]
	for i in n:
		th = th * 0.8 + (grid._ih(bx, i, 7306) - 0.5) * 1.1
		p += Vector2(sin(th), -cos(th)) * (0.9 + 0.5 * grid._ih(bx, i, 7307))
		main.append(p)
		heads.append(th)
	var segs := PoolVector2Array()
	for i in range(1, main.size()):
		segs.append(main[i - 1])
		segs.append(main[i])
	# a few side branches
	var nb = 1 + int(grid._ih(bx, 0, 7308) * 3)
	for b in nb:
		var s = 2 + int(grid._ih(bx, b, 7309) * max(1, main.size() - 5))
		var q = main[min(s, main.size() - 1)]
		var bt = heads[min(s, heads.size() - 1)] + (1.0 if grid._ih(bx, b, 7310) < 0.5 else -1.0) * (0.6 + 0.5 * grid._ih(bx, b, 7311))
		var bl = 3 + int(grid._ih(bx, b, 7312) * 7)
		for j in bl:
			bt += (grid._ih(bx, b * 16 + j, 7313) - 0.5) * 0.7
			var q2 = q + Vector2(sin(bt), -cos(bt)) * 0.9
			segs.append(q)
			segs.append(q2)
			q = q2
	# the rift: where the fissure goes on climbing toward the surface once the Void breaks through (drawn only then)
	var rift := PoolVector2Array()
	var r = main[main.size() - 1]
	var rt = heads[heads.size() - 1] * 0.5
	var x_home = r.x
	rift.append(r)
	for i in 160:
		rt = rt * 0.82 + (grid._ih(bx, i, 7314) - 0.5) * 0.6 - (r.x - x_home) * 0.01
		r += Vector2(sin(rt), -cos(rt)) * 1.5
		rift.append(r)
		if r.y < grid.base_y(int(floor(r.x))) + 12.0:
			break
	var lo = Vector2(1e9, 1e9)
	var hi = Vector2(-1e9, -1e9)
	for v in segs:
		lo = Vector2(min(lo.x, v.x), min(lo.y, v.y))
		hi = Vector2(max(hi.x, v.x), max(hi.y, v.y))
	var by0 = int(floor(lo.y)) - 1
	for v in rift:
		lo = Vector2(min(lo.x, v.x), min(lo.y, v.y))
		hi = Vector2(max(hi.x, v.x), max(hi.y, v.y))
	return {"kind": "crack", "x0": int(floor(lo.x)) - 1, "x1": int(ceil(hi.x)) + 1, "y0": int(floor(lo.y)) - 1, "y1": int(ceil(hi.y)) + 1,
		"y": int(y), "by0": by0, "rx": x, "ry": y, "segs": segs, "rift": rift, "ph": grid._ih(bx, 0, 7315) * TAU}


static func _make_mulch(grid, bx: int):
	var x0 = bx * MULCH_B
	var top = 1 << 20
	var bot = -(1 << 20)
	for x in range(x0, x0 + MULCH_B):
		top = min(top, grid.base_y(x))
		bot = max(bot, grid.base_y(x))
	return {"kind": "mulch", "x0": x0, "x1": x0 + MULCH_B - 1, "y0": top - 1, "y1": bot + 7, "y": top}


# ------------------------------------------------------------------ stamp
static func stamp(grid, f: Dictionary, xa: int, xb: int) -> void:
	match f["kind"]:
		"vein":
			_stamp_vein(grid, f, xa, xb)
		"geode":
			_stamp_geode(grid, f, xa, xb)


# The cells a structure may write: in the new columns, below the turf, above the floor, outside the nest.
static func _writable(grid, x: int, y: int, xa: int, xb: int) -> bool:
	if x < xa or x > xb or not grid.inb(x, y):
		return false
	if y < grid.surf_y(x) + 3 or y >= grid.H - 3:
		return false
	return not (abs(x - grid._nest_x) < 20 and y < grid._nest_y + 12)


# Harden one untouched cell (both planes solid, original ground) to `m` if it digs faster than that.
static func _harden(grid, x: int, y: int, m: int) -> void:
	var j = y * grid.W + (x - grid.ox)
	if grid.solid[j] != 1 or grid.solid[grid.WH + j] != 1 or grid.under[j] != 1:
		return
	var cur = grid.mat[j]
	if cur == grid.M_STONE or cur == grid.M_FOSSIL or cur == grid.M_BED:
		return
	if grid.DIG_RATE[cur] > grid.DIG_RATE[m]:
		grid.mat[j] = m


static func _stamp_vein(grid, f: Dictionary, xa: int, xb: int) -> void:
	if int(f["x1"]) < xa or int(f["x0"]) > xb:
		return
	var m = grid.M_SHALE if f["q"] else grid.M_RED
	var pts: PoolVector2Array = f["pts"]
	var ws: PoolRealArray = f["w"]
	for i in pts.size():
		var p = pts[i]
		var r = max(0.5, ws[i] * 0.5)
		for y in range(int(floor(p.y - r)), int(ceil(p.y + r)) + 1):
			for x in range(int(floor(p.x - r)), int(ceil(p.x + r)) + 1):
				var dx = x + 0.5 - p.x
				var dy = y + 0.5 - p.y
				if dx * dx + dy * dy <= r * r and _writable(grid, x, y, xa, xb):
					_harden(grid, x, y, m)


static func _stamp_geode(grid, f: Dictionary, xa: int, xb: int) -> void:
	var cx = f["cx"]
	var cy = f["cy"]
	var rx = f["rx"]
	var ry = f["ry"]
	for y in range(int(f["y0"]), int(f["y1"]) + 1):
		for x in range(int(f["x0"]), int(f["x1"]) + 1):
			if not _writable(grid, x, y, xa, xb):
				continue
			var ex = (x + 0.5 - cx) / rx
			var ey = (y + 0.5 - cy) / ry
			var e = ex * ex + ey * ey
			var j = y * grid.W + (x - grid.ox)
			if e <= 1.0:
				# the hollow: open in the front plane (the face the camera sees), a pocket the colony can break into
				if grid.under[j] == 1 and grid.solid[j] == 1:
					grid.solid[j] = 0
					grid.mat[j] = grid.strata_at(x, y)
			else:
				var ox2 = (x + 0.5 - cx) / (rx + 1.2)
				var oy2 = (y + 0.5 - cy) / (ry + 1.2)
				if ox2 * ox2 + oy2 * oy2 <= 1.0:
					_harden(grid, x, y, grid.M_SHALE)      # the rind: slow to break through


# ------------------------------------------------------------------ the colony digs
static func on_carve(sim, x: int, y: int, z: int, f: Dictionary) -> void:
	# whatever the view cached for this structure was cut against the old tunnels
	f.erase("_m")
	f.erase("_c")
	if f["kind"] == "geode" and z == 0 and not is_open(sim, f) and _reaches_hollow(sim.grid, f, x, y):
		_open_geode(sim, f)


# Does the open space around the dug cell now run into the hollow? (a little flood through open front-plane cells)
static func _reaches_hollow(g, f: Dictionary, x: int, y: int) -> bool:
	if g.is_solid(x, y, 0):
		return false
	var seen := {Vector2(x, y): true}
	var todo := [Vector2(x, y)]
	while not todo.empty():
		var c = todo.pop_back()
		var ex = (c.x + 0.5 - f["cx"]) / f["rx"]
		var ey = (c.y + 0.5 - f["cy"]) / f["ry"]
		if ex * ex + ey * ey <= 1.0:
			return true
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var n = c + d
			if not seen.has(n) and abs(n.x - x) <= 3 and abs(n.y - y) <= 3 and not g.is_solid(int(n.x), int(n.y), 0):
				seen[n] = true
				todo.append(n)
	return false


# A pocket the colony reached some other way (a borer, a sibling structure): any of its cells on the way home.
static func step(sim, _dt: float, feats: Array) -> void:
	var g = sim.grid
	if g.dist_home.size() != g.PLANES * g.WH:
		return
	for f in feats:
		if f["kind"] != "geode" or is_open(sim, f):
			continue
		var cx = int(floor(f["cx"]))
		var cy = int(floor(f["cy"]))
		var hit = false
		for dy in range(-1, 2):
			for dx in range(-int(f["rx"]), int(f["rx"]) + 1):
				if g.field(g.dist_home, cx + dx, cy + dy, 0) >= 0:
					hit = true
		if hit:
			_open_geode(sim, f)


static func _state(sim) -> Dictionary:
	if not sim.has_meta(STATE):
		sim.set_meta(STATE, {"open": {}})
	return sim.get_meta(STATE)


static func is_open(sim, f: Dictionary) -> bool:
	return _state(sim)["open"].has(f["id"])


# 0 amber .. 1 violet: deep shale geodes are violet, and after the collapse so is every geode near the pit.
static func violet(sim, f: Dictionary) -> float:
	var v = f["v"]
	if sim.arc_stage == 3:
		v = max(v, 1.0 - clamp(abs(f["cx"] - sim.void_x) / 180.0, 0.0, 1.0))
	return v


static func _open_geode(sim, f: Dictionary) -> void:
	_state(sim)["open"][f["id"]] = true
	var g = sim.grid
	var vi = violet(sim, f) > 0.5
	var col = Color("#c08cff") if vi else Color("#ffc163")
	var what = "violet" if vi else "amber"
	var where = g.MAT_NAMES[g.strata_at(int(floor(f["cx"])), int(floor(f["cy"])))]
	var gain = ""
	if sim.mutagen < 3:
		sim.mutagen += 1
		gain = "+1 mutagen"
	else:
		sim.food += GEODE_FOOD
		sim.ledger["other_in"] += GEODE_FOOD
		gain = "+%d food" % int(GEODE_FOOD)
	var pos = g.center(int(floor(f["cx"])), int(floor(f["cy"])))
	sim.fx.append({"kind": "ring", "pos": pos, "t": 0.0, "color": col})
	sim.fx.append({"kind": "text", "pos": pos + Vector2(0, -26), "t": 0.0, "text": "GEODE", "color": col})
	sim.toasts.append({"text": "The diggers broke into a geode deep in the %s: a hollow lined with %s crystals. %s." % [where, what, gain], "t": 7.0})
	sim._sfx("legendary")
