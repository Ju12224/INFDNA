extends Reference
# Caverns (underground module, see core/underground.gd): natural hollows deep in the soil, seen side-on.
#   pocket - a small void in the sand (a few cells), or now and then in the limestone
#   cave   - a hollow 8-20 cells wide, in the limestone or (rarer, smaller) the sand
#   cavern - a wide limestone cavern (24-44 cells) with stalactites, often a pool and glow-worms on its ceiling
# A hollow is a star-shaped blob (a superellipse whose radius wobbles with a few hashed harmonics, the floor cut flat where silt
# settled), so the same function says which cells are open (stamp, on_carve) and gives the outline the view draws.
# Hollows are front-plane open cells, sealed by at least one cell of soil, so the colony sees them but cannot walk in until its
# digging breaks through. Nothing here is a hazard: the pools are drawn, ants walk the floor beneath them.
#
# Sim effects (kept small):
#   - Breaking in: on_carve notices a fresh tunnel touching an open cavern cell (step() also catches a breach made any other way,
#     from the home distance field) and announces it once. The carve already set grid.nav_dirty, and the open cells next to the
#     cavern walls are walkable under world_grid._walk_rule, so the next nav rebuild lets ants climb along its walls and floor.
#   - Cool air: every cave or cavern the colony has broken into slows the rot of surplus food (cave 8 %, cavern 15 %, at most 40 %):
#     step() hands back that share of what rotted (sim.rot_rate) since the last call. Pockets give nothing but space.
#   - Pools fill while it rains (sim.rain) and drain slowly; the level lives in the sim (meta "ug_caverns") and only the view uses it.
# State per run: sim meta "ug_caverns" = {"found": {id: true}, "pool": {id: level 0..1}, "cool": rot cut, "pockets": n}.

const SLOT = 56            # columns per generation slot: at most one cave or cavern per slot, and two sand pockets
const SALT = 7717          # keeps these hashes apart from the other modules'
const N8 = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]
const COOL = {"cave": 0.08, "cavern": 0.15}
const COOL_MAX = 0.4
const FILL = 0.025          # pool level per second at full rain (a heavy shower fills an empty pool in about 40 s)
const DRAIN = 0.0016        # pool level lost per second (a full pool takes about ten minutes to sink back)


# ---------------------------------------------------------------- generation
static func features(grid, xa: int, xb: int) -> Array:
	var out := []
	for s in range(int(floor(float(xa) / SLOT)) - 1, int(floor(float(xb) / SLOT)) + 2):
		for f in _slot(grid, s):
			if int(f["x1"]) >= xa and int(f["x0"]) <= xb:
				out.append(f)
	return out


static func _slot(grid, s: int) -> Array:
	var out := []
	var x0 = s * SLOT
	# one cave or cavern in the limestone (86..122 rows below the original ground), or a smaller cave up in the sand (31..56)
	var r = grid._ih(s, SALT, 1)
	var sand_cave = null
	if r < 0.5:
		var big = grid._ih(s, SALT, 2) < 0.45
		var kind = "cavern" if big else "cave"
		var w = (24.0 + 20.0 * grid._ih(s, SALT, 3)) if big else (8.0 + 12.0 * grid._ih(s, SALT, 3))
		var ry = (4.6 + 3.2 * grid._ih(s, SALT, 4)) if big else (2.4 + 2.2 * grid._ih(s, SALT, 4))
		var f = _make(grid, s, 0, kind, x0, x0 + SLOT - 1, w * 0.5, ry, 87.0, 124.0)
		if f != null:
			out.append(f)
	elif r < 0.64:
		var f2 = _make(grid, s, 0, "cave", x0, x0 + SLOT - 1, 4.0 + 3.0 * grid._ih(s, SALT, 3), 2.0 + 1.0 * grid._ih(s, SALT, 4), 32.5, 55.5)
		if f2 != null:
			out.append(f2)
			sand_cave = f2
	elif r < 0.8:
		var f3 = _make(grid, s, 0, "pocket", x0, x0 + SLOT - 1, 2.0 + 2.0 * grid._ih(s, SALT, 3), 1.2 + 0.9 * grid._ih(s, SALT, 4), 87.0, 121.0)
		if f3 != null:
			out.append(f3)
	# sand pockets: one chance in each half of the slot (not in a half that a sand cave already reaches into)
	for i in 2:
		if grid._ih(s, SALT + 10 + i, 0) < 0.36:
			var hx = x0 + i * (SLOT / 2)
			if sand_cave != null and int(sand_cave["x1"]) >= hx - 2 and int(sand_cave["x0"]) <= hx + SLOT / 2 + 1:
				continue
			var f4 = _make(grid, s, 1 + i, "pocket", hx, hx + SLOT / 2 - 1, 1.6 + 2.2 * grid._ih(s, SALT + 10 + i, 1), 1.0 + 0.9 * grid._ih(s, SALT + 10 + i, 2), 32.5, 55.0)
			if f4 != null:
				out.append(f4)
	return out


# A hollow of half-size rx x ry somewhere inside columns lo..hi, its outline between depths d_top and d_bot (rows below the original
# ground, before the strata wave). null when it does not fit (the land is too high or low there, or it would touch the nest).
static func _make(grid, s: int, i: int, kind: String, lo: int, hi: int, rx: float, ry: float, d_top: float, d_bot: float):
	var k = SALT + 100 + i * 37
	var big = kind == "cavern"
	var amp = [0.13, 0.08, 0.05, 0.03, 0.02] if big else ([0.11, 0.07, 0.05, 0.02, 0.0] if kind == "cave" else [0.12, 0.06, 0.0, 0.0, 0.0])
	var harm := []
	for h in amp.size():
		harm.append((grid._ih(s, k, 10 + h) - 0.5) * 2.0 * amp[h])
		harm.append(grid._ih(s, k, 20 + h) * TAU)
	var n = 2.0 if kind == "pocket" else (2.3 + 0.4 * grid._ih(s, k, 30) if kind == "cave" else 2.6 + 0.7 * grid._ih(s, k, 30))
	var pool = false
	if big:
		pool = grid._ih(s, k, 31) < 0.6
	elif kind == "cave" and d_top > 80.0:
		pool = grid._ih(s, k, 31) < 0.25
	var flr = 9.0 if pool else (0.5 + 0.25 * grid._ih(s, k, 32) if kind != "pocket" else 9.0)
	var f = {"kind": kind, "id": "%d.%d" % [s, i], "rx": rx, "ry": ry, "n": n, "h": harm, "floor": flr, "pool": pool, "cx": 0.0, "cy": 0.0}
	# extent of the outline around its centre
	var ext = _extent(f)
	var w0 = ext.position.x
	var w1 = ext.end.x
	var span = (hi - 2) - (lo + 2) - (w1 - w0)
	if span < 0.0:
		return null
	var cx = lo + 2 - w0 + span * grid._ih(s, k, 33)
	var cxi = int(cx)
	var bys = [grid.base_y(cxi - 10), grid.base_y(cxi), grid.base_y(cxi + 10)]
	bys.sort()
	var base = bys[1] - grid.strata_off(cxi)
	var top_d = d_top - ext.position.y
	var bot_d = d_bot - ext.end.y
	var d = top_d + max(0.0, bot_d - top_d) * grid._ih(s, k, 34)
	var cy = base + d
	f["cx"] = cx
	f["cy"] = cy
	f["x0"] = int(floor(cx + w0)) - 1
	f["x1"] = int(ceil(cx + w1)) + 1
	f["y0"] = int(floor(cy + ext.position.y)) - 1
	f["y1"] = int(ceil(cy + ext.end.y)) + 1
	f["y"] = int(cy)
	# keep well under the ground everywhere it spans, off the bottom rows, and out of the nest's starting area
	if f["y1"] > grid.H - 6:
		return null
	for x in [f["x0"], cxi, f["x1"]]:
		if f["y0"] < grid.base_y(x) + 18:
			return null
	if f["x1"] >= grid._nest_x - 22 and f["x0"] <= grid._nest_x + 22 and f["y0"] < grid._nest_y + 14:
		return null
	if pool:
		f["pool_d"] = min(ext.end.y * 0.7, 2.2 + 2.2 * grid._ih(s, k, 35))      # deepest water, cells
		f["lvl0"] = 0.35 + 0.5 * grid._ih(s, k, 36)
	f["glow"] = int((9.0 + 14.0 * grid._ih(s, k, 37)) if big else (3.0 + 6.0 * grid._ih(s, k, 37))) if kind != "pocket" and grid._ih(s, k, 38) < (0.85 if big else 0.5) else 0
	return f


# Radius multiplier of the outline at angle a (in the hollow's normalised space).
static func _rad(f: Dictionary, a: float) -> float:
	var h = f["h"]
	var r = 1.0
	for j in range(0, h.size(), 2):
		r += h[j] * sin((j / 2 + 2) * a + h[j + 1])
	return max(0.55, r)


static func _metric(f: Dictionary, dx: float, dy: float) -> float:
	var n = f["n"]
	if n == 2.0:
		return sqrt(dx * dx + dy * dy)
	return pow(pow(abs(dx), n) + pow(abs(dy), n), 1.0 / n)


# Is the point (in cell units: cell (x, y) has its centre at x + 0.5, y + 0.5) inside the hollow?
static func inside(f: Dictionary, px: float, py: float) -> bool:
	var dx = (px - f["cx"]) / f["rx"]
	var dy = (py - f["cy"]) / f["ry"]
	if dy >= f["floor"]:
		return false
	if abs(dx) > 1.45 or abs(dy) > 1.45:
		return false
	return _metric(f, dx, dy) < _rad(f, atan2(dy, dx))


# Outline point at angle a, relative to the centre (cell units).
static func outline_at(f: Dictionary, a: float) -> Vector2:
	var c = cos(a)
	var s = sin(a)
	var rho = _rad(f, a) / max(0.001, _metric(f, c, s))
	if s > 0.001:
		rho = min(rho, f["floor"] / s)
	return Vector2(c * rho * f["rx"], s * rho * f["ry"])


# The outline as points around the centre (cell units, absolute), `segs` of them.
static func outline(f: Dictionary, segs: int) -> PoolVector2Array:
	var pts := PoolVector2Array()
	var c = Vector2(f["cx"], f["cy"])
	for i in segs:
		pts.append(c + outline_at(f, TAU * i / segs))
	return pts


static func _extent(f: Dictionary) -> Rect2:
	var lo = Vector2(1e9, 1e9)
	var hi = Vector2(-1e9, -1e9)
	for i in 72:
		var p = outline_at(f, TAU * i / 72.0)
		lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
		hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
	return Rect2(lo, hi - lo)


# Topmost / bottom-most open cell of column x (-1 when the column misses the hollow).
static func top_cell(f: Dictionary, x: int) -> int:
	for y in range(int(f["y0"]), int(f["y1"]) + 1):
		if inside(f, x + 0.5, y + 0.5):
			return y
	return -1


static func bottom_cell(f: Dictionary, x: int) -> int:
	for y in range(int(f["y1"]), int(f["y0"]) - 1, -1):
		if inside(f, x + 0.5, y + 0.5):
			return y
	return -1


# ---------------------------------------------------------------- stamping
static func stamp(grid, f: Dictionary, xa: int, xb: int) -> void:
	var a = int(max(max(xa, int(f["x0"])), grid.ox))
	var b = int(min(min(xb, int(f["x1"])), grid.ox + grid.W - 1))
	if a > b:
		return
	var sol = grid.solid
	var mt = grid.mat
	var und = grid.under
	var W = grid.W
	var ox = grid.ox
	var nx = grid._nest_x
	var ny = grid._nest_y
	var y_lo = int(f["y0"])
	var y_hi = int(min(int(f["y1"]), grid.H - 4))
	var n := 0
	for x in range(a, b + 1):
		var top = grid.surf_y(x) + 6
		for y in range(max(y_lo, top), y_hi + 1):
			if abs(x - nx) < 20 and y < ny + 12:
				continue
			if not inside(f, x + 0.5, y + 0.5):
				continue
			var j = y * W + (x - ox)
			if und[j] == 1 and sol[j] == 1:
				sol[j] = 0
				mt[j] = grid.strata_at(x, y)     # a stone the hollow cut through is gone with it (no stone ghost on the open cell)
				n += 1
	if n > 0:
		grid.solid = sol
		grid.mat = mt
		# a chunk image cached before these columns joined the sim (its 2-column pad overlapped the old edge) must be repainted
		grid._touch(a, y_lo, b, y_hi)


# ---------------------------------------------------------------- the colony breaks in
static func state(sim) -> Dictionary:
	if sim.has_meta("ug_caverns"):
		return sim.get_meta("ug_caverns")
	var st = {"found": {}, "pool": {}, "cool": 0.0, "pockets": 0}
	sim.set_meta("ug_caverns", st)
	return st


static func found(sim, f: Dictionary) -> bool:
	return sim.has_meta("ug_caverns") and sim.get_meta("ug_caverns")["found"].has(f["id"])


static func pool_level(sim, f: Dictionary) -> float:
	if not f.get("pool", false):
		return 0.0
	if sim.has_meta("ug_caverns"):
		return sim.get_meta("ug_caverns")["pool"].get(f["id"], f["lvl0"])
	return f["lvl0"]


# A fresh tunnel (cells within 2.5 of the dug cell, open, outside the hollow) next to an open cell of the hollow: the colony is in.
static func on_carve(sim, x: int, y: int, z: int, f: Dictionary) -> void:
	if z != 0 or found(sim, f):
		return
	var g = sim.grid
	for yy in range(y - 3, y + 4):
		for xx in range(x - 3, x + 4):
			if (xx - x) * (xx - x) + (yy - y) * (yy - y) > 6.25 or g.is_solid(xx, yy, 0) or not g.is_under(xx, yy):
				continue
			if inside(f, xx + 0.5, yy + 0.5):
				continue
			for d in N8:
				var cx = xx + int(d.x)
				var cy = yy + int(d.y)
				if inside(f, cx + 0.5, cy + 0.5) and not g.is_solid(cx, cy, 0):
					_discover(sim, f, Vector2(cx, cy))
					return


static func _discover(sim, f: Dictionary, cell: Vector2) -> void:
	var st = state(sim)
	if st["found"].has(f["id"]):
		return
	st["found"][f["id"]] = true
	var g = sim.grid
	g.nav_dirty = true
	var pos = g.center(int(cell.x), int(cell.y))
	var kind = f["kind"]
	if kind == "pocket":
		st["pockets"] += 1
		sim.fx.append({"kind": "text", "pos": pos + Vector2(0, -20), "t": 0.0, "text": "HOLLOW", "color": Color("#c8d6dc")})
		if st["pockets"] == 1:
			sim.toasts.append({"text": "The diggers broke into a hollow in the soil: a little room for free.", "t": 5.0})
		return
	var before = st["cool"]
	st["cool"] = min(COOL_MAX, before + COOL[kind])
	var gain = int(round((st["cool"] - before) * 100.0))
	var extra = ""
	if f.get("glow", 0) > 0:
		extra += " Glow-worms light its ceiling."
	if f.get("pool", false):
		extra += " A pool lies on its floor."
	var cool_txt = (" Its cool air keeps the stores: surplus food rots %d%% slower (%d%% in all)." % [gain, int(round(st["cool"] * 100.0))]) if gain > 0 else ""
	var w = int(f["x1"]) - int(f["x0"]) - 1
	sim.toasts.append({"text": "The diggers broke into a %s, %d cells wide.%s%s" % [kind, w, extra, cool_txt], "t": 8.0})
	sim.banner = "Discovered: a %s" % kind
	sim.banner_t = 3.0
	sim.fx.append({"kind": "ring", "pos": pos, "t": 0.0, "color": Color("#9fe8ff")})
	sim.fx.append({"kind": "text", "pos": pos + Vector2(0, -34), "t": 0.0, "text": kind.to_upper(), "color": Color("#9fe8ff")})
	if sim.has_method("_sfx"):
		sim._sfx("repelled")


# ---------------------------------------------------------------- slow changes (about twice a second)
static func step(sim, dt: float, feats: Array) -> void:
	var st = state(sim)
	var g = sim.grid
	var rain = float(sim.rain)
	var nav_ok = not g.nav_dirty and g.dist_home.size() == g.PLANES * g.WH
	for f in feats:
		if f.get("pool", false):
			var lv = st["pool"].get(f["id"], f["lvl0"])
			lv = clamp(lv + (FILL * rain - DRAIN) * dt, 0.12, 1.0)
			st["pool"][f["id"]] = lv
		# a breach made any other way (a squad, a borer, a back-plane hole): the hollow's floor is now on the way home
		if nav_ok and not st["found"].has(f["id"]):
			var fx = int(floor(f["cx"]))
			var fy = f.get("_fy", -2)
			if fy == -2:
				fy = bottom_cell(f, fx)
				f["_fy"] = fy
			if fy >= 0 and g.field(g.dist_home, fx, fy, 0) >= 0 and not g.is_solid(fx, fy, 0):
				_discover(sim, f, Vector2(fx, fy))
	# cool air: hand back part of what rotted
	if st["cool"] > 0.0 and float(sim.rot_rate) > 0.0:
		var back = float(sim.rot_rate) * st["cool"] * dt
		sim.food += back
		sim.ledger["rot"] = max(0.0, sim.ledger["rot"] - back)
