extends Reference
# Tree roots (an underground module, see core/underground.gd). Every tree on the meadow (core/world_features.gd) grows a root system
# down into the soil under its trunk: a few thick main roots (laterals that spread out under the turf, sinkers that go straight down),
# each branching into thinner and thinner roots, deeper and wider for bigger trees. Each kind of tree has its own habit: oaks a broad
# heart, the spruce a shallow plate, the acacia one deep tap root, the grove three small crowns, the stump a dead, greying system.
# Besides, everywhere along the meadow a fringe of grass and shrub rootlets hangs just under the turf (drawn only).
#
# In the sim: the thick parts of a root dig slowly (they are stamped as shale, the parts a little thinner as limestone, so a digger
# takes three times as long through an old main root as through humus). When the colony digs into a big living root it taps it: sap
# trickles into the larder now and then, about a food a minute for a main root and a little less for a branch, never more than three
# a minute from all the tapped roots together (the colony earns 10-30 a minute on its own). The first tap is announced.
#
# The trees come from the sim's seed_base, which the grid does not hold, and the grid stamps its first columns while it is built inside
# the sim's _init, before anyone could tell it. So until the grid knows the seed, features() returns only the rootlets, and the first
# step() binds the roots: it records the seed on the grid, drops the stale cached feature lists and stamps the sim range there and then.
# From then on new columns are stamped as they are generated, like every other module. (A grid with a `world_seed` property is used
# directly and needs no binding.)

const WF = preload("res://mods-unpacked/Judah-InfDNA/core/world_features.gd")
const UG = preload("res://mods-unpacked/Judah-InfDNA/core/underground.gd")
const Seasons = preload("res://mods-unpacked/Judah-InfDNA/core/seasons.gd")

const REACH_MAX = 110        # columns: no root system reaches further than this from its trunk
const FRINGE = 64            # columns per rootlet feature
const RMIN = 0.06            # cells: the thinnest root tip (radius)
const MED_R = 0.45           # cells: a root this thick (radius) digs like limestone
const HARD_R = 1.0           # cells: ... and this thick like shale
const BIG_R = 0.75           # cells: a root this thick can be tapped for sap
const MAX_STRANDS = 260
const SAP_MAIN = 1.0         # food a minute from a tapped main root
const SAP_BRANCH = 0.6       # ... from a tapped branch
const SAP_MAX = 3.0          # food a minute from all tapped roots together
const SAP_SEASON = [1.3, 1.0, 0.85, 0.7]   # spring sap rises; in winter it runs slow (the tree lives on its stores)
const TOAST = "The diggers reached a root: sap trickles into the nest"

# The tree pictures (content/art/art_manifest.json: width / height, where the trunk meets the ground as a share of the picture's width)
# and how tall ground_view draws each kind (hmul), so a root crown sits under the trunk that is drawn. Then the habit, how deep and how
# wide it roots compared with an oak of its size, and whether it is alive.
#    name:      [aspect,  foot0,  foot1,  hmul, habit,   depth, spread, alive]
const SPEC = {
	"oak1": [0.8317, 0.3271, 0.7346, 0.88, "heart", 1.0, 1.0, true],
	"oak2": [0.9681, 0.4188, 0.6822, 0.88, "heart", 1.0, 1.0, true],
	"mossoak": [1.3806, 0.3805, 0.7643, 0.55, "heart", 1.25, 0.85, true],
	"acacia": [1.7413, 0.2065, 0.8967, 0.4, "tap", 2.2, 0.8, true],
	"grove": [1.2542, 0.0, 0.9892, 0.5, "grove", 1.2, 0.75, true],
	"spruce": [0.6391, 0.066, 0.8522, 0.95, "plate", 0.45, 1.05, true],
	"stump": [0.9665, 0.0081, 0.7291, 0.38, "heart", 1.3, 1.1, false],
}


# ---------------------------------------------------------------- features
static func features(grid, xa: int, xb: int) -> Array:
	var out := []
	for k in range(int(floor(float(xa) / FRINGE)), int(floor(float(xb) / FRINGE)) + 1):
		out.append(_fringe(grid, k))
	var ws = world_seed(grid)
	if ws == null:
		return out
	var memo = _memo(grid)
	for t in WF.in_range(int(ws), xa - REACH_MAX, xb + REACH_MAX, grid._nest_x):
		if t["kind"] != "tree":
			continue
		var f = memo.get(t["id"])
		if f == null:
			f = _system(grid, t)
			memo[t["id"]] = f
		if f.empty() or int(f["x1"]) < xa or int(f["x0"]) > xb:
			continue
		out.append(f)
	return out


# The seed the meadow's trees grow from, or null while the grid does not know it yet.
static func world_seed(grid):
	var v = grid.get("world_seed")
	if v != null:
		return int(v)
	if grid.has_meta("roots_ws"):
		return int(grid.get_meta("roots_ws"))
	return null


# Root systems already grown for this world, by tree id (a pure function of the seed, kept so a tree that spans several chunks grows once).
static func _memo(grid) -> Dictionary:
	if not grid.has_meta("roots_memo"):
		grid.set_meta("roots_memo", {})
	var m: Dictionary = grid.get_meta("roots_memo")
	if m.size() > 300:
		m.clear()
	return m


# The rootlet fringe of one 64-column stretch: the view grows the tufts from the column hashes; the sim does nothing with it.
static func _fringe(grid, k: int) -> Dictionary:
	var x0 = k * FRINGE
	var lo = 1 << 20
	var hi = -(1 << 20)
	for x in range(x0, x0 + FRINGE, 8):
		var b = grid.base_y(x)
		lo = min(lo, b)
		hi = max(hi, b)
	return {"kind": "rootlets", "x0": x0, "x1": x0 + FRINGE - 1, "y0": lo - 2, "y1": hi + 6, "k": k}


# The kind of tree ground_view draws for a feature seed (the same hash and thresholds as ground_view._tree_sprite).
static func tree_name(sd: float) -> String:
	var r = fmod(abs(sin((sd + 99.0) * 12.9898) * 43758.5453), 1.0)
	if r < 0.30:
		return "oak1"
	if r < 0.58:
		return "oak2"
	if r < 0.68:
		return "mossoak"
	if r < 0.76:
		return "acacia"
	if r < 0.82:
		return "grove"
	if r < 0.93:
		return "spruce"
	if r < 0.97:
		return "stump"
	return "log"


# ---------------------------------------------------------------- growing a root system
# Everything in cells (x right, y down), as floats. A strand is {"p": points, "r": radii, "lvl": 0 main / 1 branch / 2.. fine, "up": parent}.
static func _system(grid, t: Dictionary) -> Dictionary:
	var sd: float = t["seed"]
	var tid = int(t["id"])
	var name = tree_name(sd)
	if not SPEC.has(name):
		return {}                  # a fallen log has no roots in the ground
	var sp = SPEC[name]
	var C = grid.CELL
	var sc = 0.62 + 0.38 * float(t["lane"])
	var hs = float(t["h"]) * sc * float(sp[3])           # drawn height of the tree, px
	var wpx = hs * float(sp[0])                           # drawn width, px
	var bx = float(t["x"]) + 0.5
	var cx = bx + 0.75 * wpx * ((sp[1] + sp[2]) * 0.5 - 0.5) / C
	var footw = wpx * (sp[2] - sp[1]) / C
	var sz = clamp(hs / 1000.0, 0.25, 1.6)
	var reach = clamp(wpx * 0.45 / C * float(sp[6]), 12.0, REACH_MAX - 12.0)
	var S = {"g": grid, "tid": tid, "strands": [], "q": [], "nx": grid._nest_x, "ny": grid._nest_y, "H": grid.H,
		"stones": _stone_cells(grid, int(cx - reach) - 4, int(cx + reach) + 4), "lvmax": 3 if sz > 0.7 else 2}
	var habit: String = sp[4]
	if habit == "grove":
		for k in 3:
			var gx = cx + (k - 1) * footw * 0.3 + (grid._ih(tid, 900 + k, 1) - 0.5) * 3.0
			_crown(S, gx, sz * 0.6, footw * 0.1, reach * 0.55, hs * 0.6, "heart", float(sp[5]), 300 + k * 40)
	else:
		_crown(S, cx, sz, footw * 0.28, reach, hs, habit, float(sp[5]), 0)
	_grow_all(S)
	var strands: Array = S["strands"]
	if strands.empty():
		return {}
	var x0 = 1e9
	var x1 = -1e9
	var y0 = 1e9
	var y1 = -1e9
	for s in strands:
		var p: PoolVector2Array = s["p"]
		var r: PoolRealArray = s["r"]
		for i in p.size():
			x0 = min(x0, p[i].x - r[i])
			x1 = max(x1, p[i].x + r[i])
			y0 = min(y0, p[i].y - r[i])
			y1 = max(y1, p[i].y + r[i])
	return {"kind": "tree", "id": tid, "y": tid, "name": name, "alive": bool(sp[7]), "cx": cx, "sz": sz,
		"x0": int(floor(x0)) - 1, "x1": int(ceil(x1)) + 1, "y0": int(floor(y0)) - 1, "y1": int(ceil(y1)) + 1, "strands": strands}


# One root crown: laterals out to both sides under the turf (inner ones steeper), sinkers down from under the trunk.
static func _crown(S: Dictionary, cx: float, sz: float, cw: float, reach: float, hs: float, habit: String, depth_k: float, salt: int) -> void:
	var g = S["g"]
	var tid: int = S["tid"]
	cw = clamp(cw, 1.5, 13.0)
	var depth = clamp(hs * 0.03 * depth_k, 7.0, 50.0)
	var r0 = clamp(0.75 + sz * 1.6, 0.8, 3.0)
	var top = float(g.base_y(int(floor(cx))))
	var nl = 2
	if habit == "plate" or g._ih(tid, salt + 1, 2) < sz * 0.8:
		nl = 3
	for side in [-1, 1]:
		for k in nl:
			var u = (k + 0.5) / nl
			var hk = salt + 10 + k * 2 + (0 if side < 0 else 1) * 7
			var sx = cx + side * cw * (0.1 + 0.8 * u)
			var down = lerp(0.95, 0.2, u) + (g._ih(tid, hk, 3) - 0.5) * 0.3
			if habit == "plate":
				down = lerp(0.55, 0.1, u) + (g._ih(tid, hk, 3) - 0.5) * 0.15
			var a = down if side > 0 else PI - down
			var ln = reach * (0.5 + 0.5 * u) * (0.8 + 0.4 * g._ih(tid, hk, 4))
			var r = r0 * (1.0 - 0.3 * u) * (0.85 + 0.3 * g._ih(tid, hk, 5))
			var dmax = depth * (0.55 if habit != "plate" else 0.8)
			S["q"].append([Vector2(sx, top + 0.5 + r * 0.5), a, ln, r, 0, 0.012, dmax, -1])
	var ns = 1 + (1 if sz > 0.9 and habit != "plate" else 0)
	for k in ns:
		var hk2 = salt + 30 + k
		var sx2 = cx + (g._ih(tid, hk2, 1) - 0.5) * cw * 0.8
		var a2 = PI * 0.5 + (g._ih(tid, hk2, 2) - 0.5) * 0.7
		var ln2 = depth * (0.8 + 0.25 * g._ih(tid, hk2, 3))
		var r2 = r0 * (0.8 if habit != "tap" else 1.05)
		if habit == "plate":
			ln2 *= 0.7
			r2 *= 0.6
		S["q"].append([Vector2(sx2, top + 0.6 + r2 * 0.4), a2, ln2, r2, 0, 0.09, depth * 1.1, -1])


# Grow the queue breadth first, so every parent comes before its branches (the view draws them in this order).
static func _grow_all(S: Dictionary) -> void:
	var q: Array = S["q"]
	var head = 0
	while head < q.size() and S["strands"].size() < MAX_STRANDS:
		var job = q[head]
		head += 1
		_grow(S, job)


static func _grow(S: Dictionary, job: Array) -> void:
	var g = S["g"]
	var tid: int = S["tid"]
	var sid: int = S["strands"].size()
	var p: Vector2 = job[0]
	var a: float = job[1]
	var ln: float = job[2]
	var r0: float = job[3]
	var lvl: int = job[4]
	var grav: float = job[5]
	var dmax: float = job[6]
	var stp = 1.25 if lvl == 0 else (1.0 if lvl == 1 else 0.8)
	var n = max(2, int(ceil(ln / stp)))
	var pts := PoolVector2Array()
	var rs := PoolRealArray()
	var curl = (g._ih(tid, sid, 11) - 0.5) * 0.06
	var wob = 0.2 if lvl == 0 else 0.34
	var flip = 1.0 if g._ih(tid, sid, 12) < 0.5 else -1.0
	for i in n + 1:
		var tt = float(i) / n
		var r = max(RMIN, r0 * pow(1.0 - 0.86 * tt, 1.25))
		pts.append(p)
		rs.append(r)
		if i == n:
			break
		a += curl + (g._ih(tid, sid * 97 + i, 13) - 0.5) * wob
		var dep = p.y - float(g.base_y(int(floor(p.x))))
		a = _turn(a, PI * 0.5, grav * (0.4 + tt))
		if dep < 1.4 + r:
			a = _turn(a, PI * 0.5, 0.35)                       # never up into the turf
		if dep > dmax:
			a = _turn(a, 0.0 if cos(a) >= 0.0 else PI, 0.3)    # level off at its depth
		var np = p + Vector2(cos(a), sin(a)) * stp
		if _blocked(S, np, r):
			var found = false
			for k in [0.6, -0.6, 1.2, -1.2]:
				var a2 = a + k * flip
				var np2 = p + Vector2(cos(a2), sin(a2)) * stp
				if not _blocked(S, np2, r):
					a = a2
					np = np2
					found = true
					break
			if not found:
				break                                      # a stone or the nest in the way: the root ends here
		p = np
	if pts.size() < 2:
		return
	S["strands"].append({"p": pts, "r": rs, "lvl": lvl, "up": job[7]})
	# branches: more and longer on the thick roots, thinner as they go
	if lvl >= int(S["lvmax"]):
		return
	var nb = [3 + int(g._ih(tid, sid, 20) * 3.0), 2 + int(g._ih(tid, sid, 20) * 2.6), 1 + int(g._ih(tid, sid, 20) * 2.6)][min(lvl, 2)]
	var m = pts.size() - 1
	for b in nb:
		var u = 0.1 + 0.8 * (b + 0.25 + 0.5 * g._ih(tid, sid * 7 + b, 21)) / nb
		var i = int(u * m)
		var d = pts[min(i + 1, m)] - pts[max(i - 1, 0)]
		var da = atan2(d.y, d.x)
		var side = 1.0 if (b + sid) % 2 == 0 else -1.0
		var ca = da + side * (0.45 + 0.6 * g._ih(tid, sid * 7 + b, 22))
		if sin(ca) < -0.2:
			ca = da - side * (0.45 + 0.6 * g._ih(tid, sid * 7 + b, 22))
		var cl = ln * (1.0 - u) * (0.45 + 0.4 * g._ih(tid, sid * 7 + b, 23)) + 1.5
		var cr = rs[i] * (0.42 + 0.2 * g._ih(tid, sid * 7 + b, 24))
		if cr < 0.07 or cl < 2.5:
			continue
		S["q"].append([pts[i], ca, cl, cr, lvl + 1, 0.03 + 0.025 * lvl, dmax * 1.15 + 3.0, sid])


static func _turn(a: float, to: float, k: float) -> float:
	return a + wrapf(to - a, -PI, PI) * clamp(k, 0.0, 1.0)


# The nest area, stones and the world floor stop a root (the contract keeps the nest untouched; a root never grows through a stone).
static func _blocked(S: Dictionary, p: Vector2, r: float) -> bool:
	var m = r + 2.0
	if abs(p.x - float(S["nx"])) < 20.0 + m and p.y < float(S["ny"]) + 12.0 + m:
		return true
	if p.y > float(S["H"]) - 8.0:
		return true
	var st: Dictionary = S["stones"]
	if st.has(int(floor(p.x)) * 1024 + int(floor(p.y))):
		return true
	return false


static func _stone_cells(grid, xa: int, xb: int) -> Dictionary:
	var out := {}
	for s in grid.stones_in(xa, xb):
		if s[1] > grid.base_y(int(s[0])) + 70:
			continue
		for y in range(int(s[1] - s[3]) - 1, int(s[1] + s[3]) + 2):
			for x in range(int(s[0] - s[2]) - 1, int(s[0] + s[2]) + 2):
				var dx = (x + 0.5 - s[0]) / (s[2] + 0.6)
				var dy = (y + 0.5 - s[1]) / (s[3] + 0.6)
				if dx * dx + dy * dy <= 1.0:
					out[x * 1024 + y] = true
	return out


# ---------------------------------------------------------------- cells
# The cells a root system makes hard, packed: key x * 1024 + y -> value int(radius * 100) << 12 | strand << 2 | class (1 limestone,
# 2 shale). Kept in the feature, so the stamp, the taps and the view all read one list.
static func cells(f: Dictionary) -> Dictionary:
	if f.has("_hard"):
		return f["_hard"]
	var hard := {}
	var strands: Array = f["strands"]
	for si in strands.size():
		var s = strands[si]
		var p: PoolVector2Array = s["p"]
		var r: PoolRealArray = s["r"]
		if r[0] < MED_R:
			continue
		for i in p.size() - 1:
			if r[i] < MED_R:
				break
			var seg = p[i + 1] - p[i]
			var m = max(1, int(ceil(seg.length() / max(0.5, r[i] * 0.8))))
			for j in m:
				var k = float(j) / m
				var q = p[i] + seg * k
				var rq = lerp(r[i], r[i + 1], k)
				if rq < MED_R:
					continue
				var cls = 2 if rq >= HARD_R else 1
				var rr = rq + 0.25
				var v = int(rq * 100.0) * 4096 + si * 4 + cls
				for cy in range(int(floor(q.y - rr)), int(floor(q.y + rr)) + 1):
					var dy = cy + 0.5 - q.y
					for cx in range(int(floor(q.x - rr)), int(floor(q.x + rr)) + 1):
						var dx = cx + 0.5 - q.x
						if dx * dx + dy * dy > rr * rr:
							continue
						var key = cx * 1024 + cy
						var old = hard.get(key, 0)
						if (v >> 12) > (old >> 12):
							hard[key] = v
	f["_hard"] = hard
	return hard


# ---------------------------------------------------------------- stamp
# Thick root cells dig like shale, the thinner ones like limestone. Only plain soil is changed (stones, fossils and whatever a sibling
# module set down stay), and only solid ground in both planes, outside the nest area and away from the surface rows.
static func stamp(grid, f: Dictionary, xa: int, xb: int) -> void:
	if f.get("kind", "") != "tree":
		return
	var hard = cells(f)
	var mat: PoolByteArray = grid.mat
	var sol: PoolByteArray = grid.solid
	var und: PoolByteArray = grid.under
	var W: int = grid.W
	var WH: int = grid.WH
	var ox: int = grid.ox
	var nx: int = grid._nest_x
	var ny: int = grid._nest_y
	var changed = false
	for key in hard:
		var y = key & 1023
		var x = key >> 10
		if x < xa or x > xb or x < ox or x >= ox + W or y < 0 or y >= grid.H - 3:
			continue
		if y < grid.surf_y(x) + 3 or (abs(x - nx) < 20 and y < ny + 12):
			continue
		var j = y * W + (x - ox)
		if sol[j] != 1 or sol[WH + j] != 1 or und[j] != 1:
			continue
		var m0 = mat[j]
		if m0 != grid.M_HUMUS and m0 != grid.M_CLAY and m0 != grid.M_SAND and m0 != grid.M_RED:
			continue
		mat[j] = grid.M_SHALE if (hard[key] & 3) == 2 else grid.M_LIME
		changed = true
	if changed:
		grid.mat = mat


# ---------------------------------------------------------------- the sim
# Bind the roots to the grid (see the header): once per world, on the sim's first step.
static func bind(sim) -> void:
	var g = sim.grid
	if world_seed(g) != null:
		return
	g.set_meta("roots_ws", int(sim.seed_base))
	var reg = UG.get_reg()
	var pre = "roots:%d:" % g._seed
	for k in reg._cache.keys():
		if str(k).begins_with(pre):
			reg._cache.erase(k)
	var l = g.sim_l()
	var r = g.sim_r()
	for f in reg.features("roots", g, l, r):
		stamp(g, f, l, r)
	refresh_view(sim)


static func _meta(o, key: String, def):
	if not o.has_meta(key):
		o.set_meta(key, def)
	return o.get_meta(key)


# The view keeps a weak reference to the canvas it draws on, so a root cut while the camera stands still is redrawn at once.
static func refresh_view(sim) -> void:
	if sim.has_meta("roots_ci"):
		var c = sim.get_meta("roots_ci").get_ref()
		if c != null:
			c.update()


# Tapped roots: "tree id:strand" -> food a minute.
static func tapped(sim) -> Dictionary:
	return _meta(sim, "roots_tapped", {})


static func _tap(sim, f: Dictionary, si: int, quiet: bool = false) -> void:
	var tp = tapped(sim)
	var key = "%d:%d" % [int(f["id"]), si]
	if tp.has(key):
		return
	tp[key] = SAP_MAIN if int(f["strands"][si]["lvl"]) == 0 else SAP_BRANCH
	if not sim.has_meta("roots_toast"):
		sim.set_meta("roots_toast", true)
		if not quiet:
			sim.toasts.append({"text": TOAST, "t": 7.0})


static func on_carve(sim, x: int, y: int, z: int, f: Dictionary) -> void:
	if f.get("kind", "") != "tree":
		return
	var g = sim.grid
	var hard = cells(f)
	var hit = false
	var best = -1
	var best_r = 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var v = hard.get((x + dx) * 1024 + (y + dy), 0)
			if v == 0 or g.is_solid(x + dx, y + dy, z):
				continue
			hit = true
			if f["alive"] and (v >> 12) >= int(BIG_R * 100.0) and (v >> 12) > best_r:
				best_r = v >> 12
				best = (v >> 2) & 1023
	if best >= 0:
		_tap(sim, f, best)
	if hit or _near_line(f, x, y):
		var ver = _meta(sim, "roots_ver", {})
		ver[f["id"]] = int(ver.get(f["id"], 0)) + 1
		refresh_view(sim)


# Is a thin root (one that is not stamped) close to the dug cell? Then the view has a cut to show.
static func _near_line(f: Dictionary, x: int, y: int) -> bool:
	var c = Vector2(x + 0.5, y + 0.5)
	for s in f["strands"]:
		var p: PoolVector2Array = s["p"]
		var n = p.size()
		if n == 0:
			continue
		# cheap reject on the strand's ends and middle
		var mid = p[n / 2]
		if c.distance_squared_to(mid) > pow(n * 1.3 + 3.0, 2):
			continue
		for i in range(0, n, 2):
			if c.distance_squared_to(p[i]) < 6.25:
				return true
	return false


# Twice a second: the tapped roots bleed a little sap into the larder (whole food at a time, now and then), and one tree a step is
# checked for big roots the colony's tunnels opened some other way (an outpost shaft).
static func step(sim, dt: float, feats: Array) -> void:
	bind(sim)
	var g = sim.grid
	var trees := []
	for f in feats:
		if f.get("kind", "") == "tree" and f["alive"]:
			trees.append(f)
	if not trees.empty():
		var ti = int(_meta(sim, "roots_scan", 0)) % trees.size()
		sim.set_meta("roots_scan", ti + 1)
		_scan(sim, trees[ti])
	var tp = tapped(sim)
	if tp.empty():
		return
	var rate = 0.0
	for v in tp.values():
		rate += float(v)
	rate = min(rate, SAP_MAX) * SAP_SEASON[Seasons.index(sim.time)]
	var acc = float(_meta(sim, "roots_sap", 0.0)) + rate / 60.0 * dt
	if sim.food >= sim.food_cap:
		acc = min(acc, 1.0)                 # a full larder: the sap runs to waste
	while acc >= 1.0:
		acc -= 1.0
		sim.food += 1.0
		sim.ledger["other_in"] += 1.0
		sim.set_meta("roots_food", float(_meta(sim, "roots_food", 0.0)) + 1.0)
	sim.set_meta("roots_sap", acc)


static func _scan(sim, f: Dictionary) -> void:
	var g = sim.grid
	var hard = cells(f)
	var sol: PoolByteArray = g.solid
	var W: int = g.W
	var WH: int = g.WH
	var ox: int = g.ox
	var big = int(BIG_R * 100.0)
	for key in hard:
		var v = hard[key]
		if (v >> 12) < big:
			continue
		var y = key & 1023
		var x = key >> 10
		if x < ox or x >= ox + W:
			continue
		var j = y * W + (x - ox)
		for z in 2:
			if sol[z * WH + j] != 0 or not _reached(g, x, y, z):
				continue
			var si = (v >> 2) & 1023
			if not tapped(sim).has("%d:%d" % [int(f["id"]), si]):
				_tap(sim, f, si)


# An open cell the colony can walk to (a cavern a sibling module left open is not a tunnel of the colony's).
static func _reached(g, x: int, y: int, z: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if g.field(g.dist_home, x + dx, y + dy, z) >= 0:
				return true
	return false
