extends Reference
# The ground the ants walk on: a deep band of turf with many walking lanes, scenery, and the natural
# landmarks (giant trees, boulders, cliffs with cave mouths). Everything static is built once into
# cached meshes (mesh_kit.gd) and redrawn with a few draw_mesh calls, so the cost stays flat however
# much scenery is on screen (the old per-frame loops cost 12-20 ms).
#
# Scenery is cut into LANE SLICES so ant_view can interleave it with the units: an ant in a back lane
# walks behind a flower, one in a front lane walks in front of it. Slice SLICES is the foreground,
# drawn over every unit. Lane 0 is the back of the band, lane 1 the front lip (the dirt outline).

const MK = preload("res://mods-unpacked/Judah-InfDNA/content/colony/mesh_kit.gd")
const WF = preload("res://mods-unpacked/Judah-InfDNA/core/world_features.gd")

const INK = Color("#15121a")
const DEPTH = 128.0          # thickness of the walkable band, px
const LANE_K = 0.9           # a unit at lane l stands (1 - l) * DEPTH * LANE_K above the front lip
const CH = 48                # columns per cached chunk
const SLICES = 14            # lane slices, plus one foreground slice
const STRIPS = 9             # visible lane rows in the turf

const GRASS_BACK = Color("#6c9e4c")
const GRASS_FRONT = Color("#9ccf55")
const MOUND_BACK = Color("#8a5a34")
const MOUND_FRONT = Color("#a8733f")
const HAZE = Color("#8fb8a0")
const GREENS = [Color("#4a7a2c"), Color("#659c38"), Color("#86bb4a"), Color("#a9d963")]
const BLADES = [Color("#5d8f34"), Color("#86bb4a"), Color("#b3df6e")]
const FLOWERS = [Color("#f5f0e6"), Color("#f7d046"), Color("#f08fb0"), Color("#9a7be0"), Color("#f08a3c")]
const CAPS = [Color("#d4493a"), Color("#e08a3c"), Color("#a8734a"), Color("#9a6fb0")]

var sim
var g
var world_seed := 0
var _t := 0.0
var _chunks := {}            # chunk index -> {band, shade, sl[], sy, oy, t}
var _stale := {}
var _vis := []               # [chunk index, chunk] for the chunks in view
var _fcache := {}            # feature id -> {mesh, shade, slice, x0, x1}
var _flist := []
var _flist_key := -999999
var _vis_f := []             # per slice: visible feature entries
var _vis_shade := []
var perf             # perf.gd (optional): scenery detail level


func _init(sim_) -> void:
	sim = sim_
	g = sim_.grid
	world_seed = sim_.seed_base
	for s in SLICES + 1:
		_vis_f.append([])


static func lane_y(sy: float, lane: float) -> float:
	return sy - (1.0 - lane) * DEPTH * LANE_K


# Perspective: back lanes are smaller. Past the front lip (lane > 1) things loom larger.
static func persp(lane: float) -> float:
	return 0.62 + 0.38 * lane if lane <= 1.0 else 1.0 + (lane - 1.0) * 1.8


static func slice_of(lane: float) -> int:
	return SLICES if lane > 1.0 else int(clamp(lane, 0.0, 0.9999) * SLICES)


static func hz(col: Color, lane: float) -> Color:
	return col.linear_interpolate(HAZE, (1.0 - clamp(lane, 0.0, 1.0)) * 0.3)


func _sm(x: int) -> float:
	var acc := 0.0
	for k in range(-2, 3):
		acc += g.surf_y(x + k)
	return acc / 5.0 * g.CELL


# Smoothed ground height (px) at a column, from the chunk cache when it is there.
func smooth_px(x: int) -> float:
	var ci = int(floor(float(x) / CH))
	var ch = _chunks.get(ci)
	if ch != null:
		return ch["sy"][x - ci * CH]
	return _sm(x)


static func _sy_at(sy: PoolRealArray, c0: int, px: float, C: float) -> float:
	var u = clamp(px / C - c0, 0.0, CH - 0.001)
	var i = int(u)
	return lerp(sy[i], sy[i + 1], u - i)


# ---------------------------------------------------------------- per frame
func prepare(cols: Array, t: float) -> void:
	_t = t
	if not g.surf_dirty.empty():
		for x in g.surf_dirty.keys():
			var ci = int(floor(float(x) / CH))
			_stale[ci] = true
			var m = ((x % CH) + CH) % CH
			if m < 3:
				_stale[ci - 1] = true
			elif m > CH - 4:
				_stale[ci + 1] = true
		g.surf_dirty.clear()
	var c_lo = int(floor(float(cols[0]) / CH))
	var c_hi = int(floor(float(cols[1]) / CH))
	var budget = 14 if _chunks.empty() else 3
	_vis = []
	for ci in range(c_lo, c_hi + 1):
		var ch = _chunks.get(ci)
		if ch == null or (_stale.has(ci) and t - ch["t"] > 0.6):
			if budget > 0:
				budget -= 1
				ch = _build_chunk(ci)
				_chunks[ci] = ch
				_stale.erase(ci)
		if ch != null:
			_vis.append([ci, ch])
	if _chunks.size() > 70:
		for ci in _chunks.keys():
			if ci < c_lo - 14 or ci > c_hi + 14:
				_chunks.erase(ci)
	_prepare_features(cols, budget)


func _prepare_features(cols: Array, chunk_budget: int) -> void:
	var key = int(floor(float(cols[0]) / (WF.SLOT * 0.5))) * 1000 + int(floor(float(cols[1]) / (WF.SLOT * 0.5)))
	if key != _flist_key:
		_flist_key = key
		_flist = WF.in_range(world_seed, cols[0] - 120, cols[1] + 120, int(g.entrance.x))
	for s in SLICES + 1:
		_vis_f[s] = []
	_vis_shade = []
	var C = g.CELL
	var px0 = cols[0] * C
	var px1 = cols[1] * C
	var budget = 2
	for f in _flist:
		var e = _fcache.get(f["id"])
		if e == null:
			if budget <= 0:
				continue
			budget -= 1
			e = _build_feature(f)
			_fcache[f["id"]] = e
		if e["x1"] < px0 or e["x0"] > px1:
			continue
		_vis_f[e["slice"]].append(e)
		if e["shade"] != null:
			_vis_shade.append(e)
	if _fcache.size() > 90:
		for id in _fcache.keys():
			var e2 = _fcache[id]
			if e2["x1"] < px0 - 6000.0 or e2["x0"] > px1 + 6000.0:
				_fcache.erase(id)


# Band, ground shadows: drawn first (under every unit).
func draw_ground(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for e in _vis:
		var ch = e[1]
		if ch["band"] != null:
			ci.draw_mesh(ch["band"], null)
	for e in _vis:
		var ch2 = e[1]
		if ch2["shade"] != null:
			ci.draw_mesh(ch2["shade"], null)
	for fe in _vis_shade:
		ci.draw_mesh(fe["shade"], null)


# One lane slice of scenery. A little wind shear sways the tufts and flowers.
func draw_slice(ci: CanvasItem, s: int) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var amp = 0.008 + 0.03 * float(s) / SLICES + (0.02 if s == SLICES else 0.0)
	var detail = perf.scenery if perf != null else 2
	var skip_decor = detail == 0 or (detail == 1 and s % 2 == 1 and s != SLICES)
	for e in _vis:
		if skip_decor:
			break
		var m = e[1]["sl"][s]
		if m == null:
			continue
		var sw = amp * sin(_t * 1.15 + e[0] * 1.7 + s * 0.45)
		ci.draw_mesh(m, null, null, Transform2D(Vector2(1, 0), Vector2(sw, 1), Vector2(-sw * e[1]["oy"], 0)))
	for fe in _vis_f[s]:
		ci.draw_mesh(fe["mesh"], null)


func visible_slices() -> Array:
	var out := []
	for s in SLICES + 1:
		var any = not _vis_f[s].empty()
		if not any:
			for e in _vis:
				if e[1]["sl"][s] != null:
					any = true
					break
		if any:
			out.append(s)
	return out


# ---------------------------------------------------------------- chunk build
func _build_chunk(ci: int) -> Dictionary:
	var c0 = ci * CH
	var sy := PoolRealArray()
	var mf := PoolRealArray()
	var raw := []
	for i in CH + 7:
		raw.append(clamp(float(g.mound_h(c0 - 3 + i)), 0.0, 1.0))
	for i in CH + 1:
		sy.append(_sm(c0 + i))
		var acc := 0.0
		for k in 7:
			acc += raw[i + k]
		mf.append(acc / 7.0)      # a wide blur: the bare mound fades into the turf instead of ending at a wall
	var band = MK.new()
	var shade = MK.new()
	var sl := []
	for s in SLICES + 1:
		sl.append(MK.new())
	_band(band, c0, sy, mf)
	_decor(sl, shade, band, c0, sy, mf)
	var outs := []
	for mk in sl:
		outs.append(mk.build())
	var oy := 0.0
	for i in CH + 1:
		oy += sy[i]
	return {"band": band.build(), "shade": shade.build(), "sl": outs, "sy": sy, "oy": oy / (CH + 1), "t": _t}


func _lane_col(lane: float, mfv: float, i: int, j: int) -> Color:
	var t = clamp(lane, 0.0, 1.0)
	var col = GRASS_BACK.linear_interpolate(GRASS_FRONT, t)
	var n = sin((i) * 0.11 + j * 1.7) * 0.022 + (0.018 if j % 2 == 0 else -0.018)
	col = col.lightened(n) if n > 0.0 else col.darkened(-n)
	if mfv > 0.0:
		col = col.linear_interpolate(MOUND_BACK.linear_interpolate(MOUND_FRONT, t), mfv)
	return col


func _band(mk, c0: int, sy: PoolRealArray, mf: PoolRealArray) -> void:
	var C = g.CELL
	for j in STRIPS:
		var la = -0.11 + 1.13 * float(j) / STRIPS
		var lb = -0.11 + 1.13 * float(j + 1) / STRIPS
		for i in CH:
			var xa = (c0 + i) * C
			var xb = xa + C
			mk.quad_c(Vector2(xa, lane_y(sy[i], la)), _lane_col(la, mf[i], c0 + i, j),
				Vector2(xb, lane_y(sy[i + 1], la)), _lane_col(la, mf[i + 1], c0 + i + 1, j),
				Vector2(xb, lane_y(sy[i + 1], lb)), _lane_col(lb, mf[i + 1], c0 + i + 1, j),
				Vector2(xa, lane_y(sy[i], lb)), _lane_col(lb, mf[i], c0 + i, j))
	# lighter and darker patches of turf, flat on the ground
	for i in range(0, CH, 3):
		var col = c0 + i
		var h = MK.hash1(col * 1.7)
		if h < 0.5 or mf[i] > 0.3:
			continue
		var lane = MK.hash1(col * 3.1)
		var p = Vector2(col * C, lane_y(sy[i], lane))
		var sz = (12.0 + 18.0 * MK.hash1(col * 5.3)) * persp(lane)
		mk.ellipse(p, sz, sz * 0.3, Color(1, 1, 1, 0.07) if h > 0.78 else Color(0.18, 0.33, 0.08, 0.11), 10)
	# front lip: a bright edge over a turf shadow
	var lip := PoolVector2Array()
	var wl := PoolRealArray()
	var lip2 := PoolVector2Array()
	for i in CH + 1:
		lip.append(Vector2((c0 + i) * C, sy[i] - 2.0))
		lip2.append(Vector2((c0 + i) * C, sy[i] + 2.5))
		wl.append(3.0)
	mk.ribbon(lip2, wl, Color(0.2, 0.36, 0.12, 0.85))
	mk.ribbon(lip, wl, Color("#c3e87a"))
	# spoil pellets on the mound, loose blades and leaf litter elsewhere
	for i in CH:
		var col2 = c0 + i
		for k in 3:
			var h1 = MK.hash1(col2 * 7.13 + k * 1.91)
			var lane1 = MK.hash1(col2 * 3.7 + k * 5.3)
			var p1 = Vector2(col2 * C + h1 * C, lane_y(sy[i], lane1))
			var ps = persp(lane1)
			if mf[i] > 0.3:
				mk.ellipse(p1, (1.3 + 1.7 * h1) * ps, (1.0 + 1.2 * h1) * ps, Color("#6b4426") if h1 > 0.55 else Color("#c9935c"), 6)
			elif mf[i] < 0.2:
				mk.blade(p1, (h1 - 0.5) * 5.0, (3.0 + 5.0 * h1) * ps, 1.7 * ps + 0.4, BLADES[0], BLADES[int(h1 * 2.99)])
		if mf[i] < 0.2 and MK.hash1(col2 * 2.37 + 4.0) > 0.86:
			var lane2 = MK.hash1(col2 * 8.1)
			var p2 = Vector2(col2 * C, lane_y(sy[i], lane2))
			var ps2 = persp(lane2)
			var lc = Color("#8a6a3a") if MK.hash1(col2 * 3.3) > 0.5 else Color("#6e5530")
			mk.ellipse(p2, 5.5 * ps2, 1.9 * ps2, hz(lc, lane2), 8, (MK.hash1(col2) - 0.5) * 0.9)


func _decor(sl: Array, shade, band, c0: int, sy: PoolRealArray, mf: PoolRealArray) -> void:
	var C = g.CELL
	var ents := []
	for en in g.entrances:
		ents.append(int(en.x))
	for i in range(0, CH, 4):
		var col = c0 + i
		var h0 = MK.hash1(col * 3.17 + 0.5)
		if h0 > 0.8 or mf[i] > 0.25:
			continue
		var near = false
		for ex in ents:
			if abs(col - ex) < 9:
				near = true
		if near:
			continue
		var lane = MK.hash1(col * 5.71 + 2.0)
		var px = (col + MK.hash1(col * 9.1)) * C
		var p = Vector2(px, lane_y(_sy_at(sy, c0, px, C), lane))
		var ps = persp(lane)
		var sd = col * 1.37 + 0.11
		var r = MK.hash1(col * 1.93 + 7.0)
		var mkr = sl[slice_of(lane)]
		if r < 0.36:
			_tuft(mkr, p, ps, sd, lane)
		elif r < 0.50:
			_flowers(mkr, p, ps, sd, lane)
		elif r < 0.58:
			_clover(band, p, ps, sd, lane)
		elif r < 0.68:
			_pebbles(mkr, shade, p, ps, sd, lane)
		elif r < 0.76:
			_mushroom(mkr, shade, p, ps, sd, lane)
		elif r < 0.87:
			_bush(mkr, shade, p, ps, sd, lane)
		else:
			_fern(mkr, p, ps, sd, lane)
	# foreground: tall grass in front of everything (units walk behind it)
	for i in range(0, CH, 10):
		var col2 = c0 + i
		if mf[i] > 0.25 or MK.hash1(col2 * 4.4 + 1.0) > 0.7:
			continue
		var lane2 = 1.03 + 0.12 * MK.hash1(col2 * 6.1)
		var px2 = (col2 + MK.hash1(col2 * 2.9)) * C
		var p2 = Vector2(px2, lane_y(_sy_at(sy, c0, px2, C), lane2))
		_tall(sl[SLICES], p2, persp(lane2), col2 * 2.11 + 0.3, lane2)


func _tuft(mk, p: Vector2, ps: float, sd: float, lane: float, big: float = 1.0) -> void:
	var n = 6 + int(MK.hash1(sd) * 5.0)
	for i in n:
		var h1 = MK.hash1(sd + i * 1.7)
		var h2 = MK.hash1(sd + i * 3.1 + 5.0)
		mk.blade(p + Vector2((h1 - 0.5) * 18.0 * ps * big, 0), (h2 - 0.5) * 16.0 * ps, (13.0 + 16.0 * h2) * ps * big,
			3.4 * ps, hz(GREENS[int(h1 * 1.99)], lane), hz(GREENS[2 + int(h2 * 1.99)], lane))


func _tall(mk, p: Vector2, ps: float, sd: float, lane: float) -> void:
	for i in 9:
		var h1 = MK.hash1(sd + i * 1.3)
		var h2 = MK.hash1(sd + i * 2.9 + 4.0)
		mk.blade(p + Vector2((h1 - 0.5) * 30.0 * ps, 0), (h2 - 0.5) * 26.0 * ps, (28.0 + 48.0 * h2) * ps, 3.8 * ps,
			Color("#3a6620"), GREENS[2 + int(h1 * 1.99)])


func _flowers(mk, p: Vector2, ps: float, sd: float, lane: float) -> void:
	var fc = FLOWERS[int(MK.hash1(sd + 9.0) * 4.99)]
	var n = 2 + int(MK.hash1(sd + 3.0) * 3.0)
	for i in n:
		var h1 = MK.hash1(sd + i * 2.3)
		var h2 = MK.hash1(sd + i * 4.7 + 1.0)
		var bx = (h1 - 0.5) * 22.0 * ps
		var ln = (16.0 + 18.0 * h2) * ps
		var lean = (h2 - 0.5) * 8.0 * ps
		mk.blade(p + Vector2(bx, 0), lean, ln, 1.8 * ps + 0.4, hz(Color("#46742a"), lane), hz(Color("#6aa23c"), lane))
		var head = p + Vector2(bx + lean, -ln)
		for k in 5:
			var a = TAU * k / 5.0 + sd
			mk.ellipse(head + Vector2(cos(a), sin(a)) * 3.6 * ps, 3.4 * ps, 2.4 * ps, hz(fc, lane), 8, a)
		mk.ellipse(head, 2.5 * ps, 2.5 * ps, hz(Color("#f2b632"), lane), 8)
	_tuft(mk, p, ps * 0.7, sd + 3.0, lane, 0.7)


func _clover(mk, p: Vector2, ps: float, sd: float, lane: float) -> void:
	for i in 7:
		var h1 = MK.hash1(sd + i * 1.9)
		var h2 = MK.hash1(sd + i * 3.7 + 2.0)
		mk.ellipse(p + Vector2((h1 - 0.5) * 30.0 * ps, (h2 - 0.5) * 5.0 * ps), 4.4 * ps, 1.8 * ps, hz(Color("#4f8f33") if h1 > 0.5 else Color("#5fa03a"), lane), 8, (h2 - 0.5) * 0.6)
	for k in 2:
		mk.ellipse(p + Vector2((MK.hash1(sd + k * 8.0) - 0.5) * 24.0 * ps, -1.5 * ps), 1.6 * ps, 1.0 * ps, hz(Color("#f5f0e6"), lane), 6)


func _pebbles(mk, sh, p: Vector2, ps: float, sd: float, lane: float) -> void:
	var n = 2 + int(MK.hash1(sd) * 3.0)
	for i in n:
		var h1 = MK.hash1(sd + i * 2.1)
		var rx = (3.5 + 6.5 * h1) * ps
		var ry = rx * 0.64
		var q = p + Vector2((MK.hash1(sd + i * 5.3) - 0.5) * 26.0 * ps, 0)
		var gc = Color("#9a9a96") if h1 > 0.5 else Color("#8d8372")
		mk.ellipse_ink(q + Vector2(0, -ry * 0.5), rx, ry, hz(gc, lane), 1.5 * ps + 0.5, 9)
		mk.ellipse(q + Vector2(rx * 0.25, -ry * 0.9), rx * 0.4, ry * 0.3, hz(gc.lightened(0.3), lane), 6)
		sh.shadow(q + Vector2(-rx * 0.3, 1.0), rx * 1.2, ry * 0.5, Color(0.08, 0.12, 0.05, 0.18), 2)


func _mushroom(mk, sh, p: Vector2, ps: float, sd: float, lane: float) -> void:
	var cap = CAPS[int(MK.hash1(sd + 2.0) * 3.99)]
	var n = 1 + int(MK.hash1(sd) * 2.99)
	for i in n:
		var h1 = MK.hash1(sd + i * 2.7)
		var h2 = MK.hash1(sd + i * 4.1 + 3.0)
		var base = p + Vector2((h1 - 0.5) * 18.0 * ps, 0)
		var hh = (10.0 + 14.0 * h2) * ps
		var cr = (7.0 + 8.0 * h2) * ps
		mk.quad(base + Vector2(-3.2 * ps - 1.2, 0), base + Vector2(3.2 * ps + 1.2, 0), base + Vector2(2.6 * ps + 1.2, -hh), base + Vector2(-2.6 * ps - 1.2, -hh), INK)
		mk.quad(base + Vector2(-2.6 * ps, 0), base + Vector2(2.6 * ps, 0), base + Vector2(2.0 * ps, -hh), base + Vector2(-2.0 * ps, -hh), hz(Color("#efe6d2"), lane))
		mk.ellipse_ink(base + Vector2(0, -hh), cr, cr * 0.62, hz(cap, lane), 1.8, 12)
		for k in 3:
			mk.ellipse(base + Vector2((k - 1) * cr * 0.5, -hh - cr * (0.2 + 0.1 * (k % 2))), 1.4 * ps, 1.0 * ps, Color(1, 1, 1, 0.9), 6)
		sh.shadow(base + Vector2(-cr * 0.3, 1.5), cr * 1.1, cr * 0.26, Color(0.08, 0.12, 0.05, 0.2), 2)


func _bush(mk, sh, p: Vector2, ps: float, sd: float, lane: float) -> void:
	var n = 5 + int(MK.hash1(sd) * 4.0)
	var sz = (18.0 + 14.0 * MK.hash1(sd + 1.0)) * ps
	var dark = hz(Color("#35632a"), lane)
	var mid = hz(Color("#4b8a36"), lane)
	var lite = hz(Color("#72b04a"), lane)
	for i in n:
		var u = float(i) / (n - 1)
		var q = p + Vector2((u - 0.5) * sz * 2.2 + (MK.hash1(sd + i) - 0.5) * 6.0 * ps, -sz * (0.5 + 0.3 * sin(i * 1.3 + sd)))
		mk.blob_ink(q, sz * (0.65 + 0.3 * MK.hash1(sd + i * 2.0)), sz * 0.6, sd + i, 0.12, dark, 2.2 * ps + 0.6, 10)
	for i in n:
		var u2 = float(i) / (n - 1)
		var q2 = p + Vector2((u2 - 0.5) * sz * 2.1 + sz * 0.06, -sz * (0.58 + 0.3 * sin(i * 1.3 + sd)) - sz * 0.05)
		mk.blob(q2, sz * 0.55, sz * 0.48, sd + i * 1.7, 0.12, mid, 10)
	for i in n / 2 + 1:
		var q3 = p + Vector2((float(i) / max(1, n / 2) - 0.5) * sz * 1.6 + sz * 0.14, -sz * 0.85 - sz * 0.3 * sin(i * 2.1 + sd))
		mk.blob(q3, sz * 0.3, sz * 0.26, sd + i * 2.3, 0.1, lite, 8)
	if MK.hash1(sd + 5.0) > 0.6:
		for i in 5:
			mk.ellipse(p + Vector2((MK.hash1(sd + i * 3.0) - 0.5) * sz * 1.8, -sz * (0.5 + 0.5 * MK.hash1(sd + i * 7.0))), 2.2 * ps, 2.2 * ps, Color("#d9413a"), 6)
	sh.shadow(p + Vector2(-sz * 0.5, 2.0), sz * 1.7, sz * 0.3, Color(0.06, 0.1, 0.04, 0.2), 3)


func _fern(mk, p: Vector2, ps: float, sd: float, lane: float) -> void:
	for i in 6:
		var h1 = MK.hash1(sd + i * 1.7)
		var sgn = -1.0 if i % 2 == 0 else 1.0
		mk.blade(p + Vector2(sgn * 2.0 * ps, 0), sgn * (16.0 + 18.0 * h1) * ps, (26.0 + 22.0 * h1) * ps, 4.4 * ps,
			hz(Color("#3f7a2a"), lane), hz(Color("#7cbc4c"), lane))


# ---------------------------------------------------------------- landmarks
func _build_feature(f: Dictionary) -> Dictionary:
	match f["kind"]:
		"tree":
			return _tree(f)
		"cliff":
			return _cliff(f)
	return _boulder(f)


func _base_point(f: Dictionary) -> Vector2:
	return Vector2((f["x"] + 0.5) * g.CELL, lane_y(_sm(f["x"]), f["lane"]) + 4.0)


func _tree(f: Dictionary) -> Dictionary:
	var mk = MK.new()
	var sh = MK.new()
	var lane: float = f["lane"]
	var sc = persp(lane)
	var w: float = f["w"] * sc
	var h: float = f["h"] * sc
	var sd: float = f["seed"]
	var b = _base_point(f)
	var bark = hz(Color("#6a4b32"), lane)
	var bark_d = bark.darkened(0.42)
	var bark_m = bark.darkened(0.18)
	var bark_l = bark.lightened(0.24)
	var bark_h = bark.lightened(0.42)
	var n = 22
	var top_y = h * 0.6
	var lean = (MK.hash1(sd + 3.0) - 0.5) * w * 1.6
	var pts := PoolVector2Array()
	var wid := PoolRealArray()
	var wink := PoolRealArray()
	for i in n + 1:
		var t = float(i) / n
		pts.append(b + Vector2(lean * t * t + sin(t * 3.4 + sd) * w * 0.12 * t + sin(t * 9.0 + sd * 2.0) * w * 0.025, -top_y * t))
		var ww = w * (1.0 - 0.3 * t) + w * 0.9 * pow(1.0 - t, 5.0)
		wid.append(ww)
		wink.append(ww + 12.0)
	# roots splay out and grip the ground
	for k in 6:
		var sgn = -1.0 if k % 2 == 0 else 1.0
		var rl = w * (0.6 + 0.6 * MK.hash1(sd + k * 3.3))
		var rp := PoolVector2Array()
		var rw := PoolRealArray()
		var rwi := PoolRealArray()
		for j in 7:
			var u = float(j) / 6.0
			rp.append(b + Vector2(sgn * (w * 0.18 + rl * u), -w * 0.55 * pow(1.0 - u, 2.2) + 4.0 * u + (k % 3) * 1.5))
			rw.append(w * 0.46 * pow(1.0 - u, 0.8) + 4.0)
			rwi.append(w * 0.46 * pow(1.0 - u, 0.8) + 11.0)
		mk.ribbon(rp, rwi, INK)
		mk.ribbon(rp, rw, bark_m, bark_d)
	mk.ribbon(pts, wink, INK)
	# the trunk in five vertical bands, shaded left to right (the sun is on the right)
	var band_cols = [bark_d, bark_m, bark, bark_l, bark_h]
	for bi in 5:
		var u0 = -0.5 + float(bi) / 5.0
		var u1 = u0 + 0.2
		for i in n:
			var n0 = Vector2(1, 0)
			var a0 = pts[i] + n0 * wid[i] * u0
			var a1 = pts[i] + n0 * wid[i] * u1
			var c0 = pts[i + 1] + n0 * wid[i + 1] * u0
			var c1 = pts[i + 1] + n0 * wid[i + 1] * u1
			mk.quad(a0, a1, c1, c0, band_cols[bi])
	# bark: grooves, ridges, knots and a little moss on the shaded base
	for k in 9:
		var pg := PoolVector2Array()
		var wg := PoolRealArray()
		var off = (k / 8.0 - 0.5) * 0.86
		var t0 = 0.02 + 0.3 * MK.hash1(sd + k * 1.7)
		var t1 = min(1.0, t0 + 0.4 + 0.5 * MK.hash1(sd + k * 2.9))
		for i in range(int(t0 * n), int(t1 * n) + 1):
			var t2 = float(i) / n
			pg.append(pts[i] + Vector2(wid[i] * off + sin(t2 * 11.0 + k * 1.7) * 3.0, 0))
			wg.append(3.0 + 1.5 * (1.0 - t2))
		if pg.size() > 1:
			mk.ribbon(pg, wg, Color(0.1, 0.07, 0.05, 0.45))
	for k in 16:
		var ti = int((0.05 + 0.85 * MK.hash1(sd + k * 4.1)) * n)
		var u = (MK.hash1(sd + k * 6.3) - 0.5) * 0.7
		var kp = pts[ti] + Vector2(wid[ti] * u, 0)
		if k % 4 == 0:
			mk.ellipse_ink(kp, wid[ti] * 0.06 + 4.0, wid[ti] * 0.09 + 6.0, bark_d, 2.0, 9)
		else:
			var rr := PoolVector2Array([kp + Vector2(-wid[ti] * 0.1, 2), kp + Vector2(0, -1.5), kp + Vector2(wid[ti] * 0.1, 2)])
			mk.ribbon(rr, PoolRealArray([2.5, 3.2, 2.5]), Color(0.1, 0.07, 0.05, 0.4))
	mk.blob(b + Vector2(-w * 0.28, -w * 0.5), w * 0.22, w * 0.4, sd + 6.0, 0.18, hz(Color("#5b8f3a"), lane), 10)
	mk.blob(b + Vector2(-w * 0.12, -w * 1.1), w * 0.12, w * 0.2, sd + 7.0, 0.2, hz(Color("#6aa23c"), lane), 8)
	# branches: thick, curving up into the crown, each with a twig or two
	var ends := []
	for k in 7:
		var t0 = 0.4 + 0.08 * k
		var idx = int(t0 * n)
		var dir = 1.0 if k % 2 == 0 else -1.0
		var ln = h * (0.13 + 0.14 * MK.hash1(sd + k * 5.0))
		var ang = -PI * 0.5 + dir * (0.5 + 0.55 * MK.hash1(sd + k * 7.0))
		var bp := PoolVector2Array()
		var bw := PoolRealArray()
		var bwi := PoolRealArray()
		for j in 7:
			var u2 = float(j) / 6.0
			var bend = sin(u2 * 2.6 + k) * ln * 0.07
			bp.append(pts[idx] + Vector2(cos(ang), sin(ang)) * ln * u2 + Vector2(dir * ln * 0.12 * u2 + bend, -ln * 0.28 * u2 * u2))
			bw.append(wid[idx] * 0.52 * pow(1.0 - u2, 0.9) + 5.0)
			bwi.append(wid[idx] * 0.52 * pow(1.0 - u2, 0.9) + 12.0)
		mk.ribbon(bp, bwi, INK)
		mk.ribbon(bp, bw, bark_m, bark_d)
		mk.ribbon(bp, PoolRealArray([bw[0] * 0.3, bw[1] * 0.3, bw[2] * 0.3, bw[3] * 0.3, bw[4] * 0.3, bw[5] * 0.3, bw[6] * 0.3]), Color(bark_h.r, bark_h.g, bark_h.b, 0.4))
		ends.append(bp[6])
		for q in 2:
			var sp = bp[3 + q]
			var sa = ang + (0.7 if q == 0 else -0.8) * dir
			var tp := PoolVector2Array()
			var tw := PoolRealArray()
			var twi := PoolRealArray()
			for j in 4:
				var u3 = float(j) / 3.0
				tp.append(sp + Vector2(cos(sa), sin(sa)) * ln * 0.34 * u3 + Vector2(0, -ln * 0.06 * u3))
				tw.append(bw[3] * 0.5 * (1.0 - u3) + 3.0)
				twi.append(bw[3] * 0.5 * (1.0 - u3) + 9.0)
			mk.ribbon(tp, twi, INK)
			mk.ribbon(tp, tw, bark_m, bark_d)
			ends.append(tp[3])
	# crown: a wide canopy of many round leaf clusters, dark under, light on top (sun upper right)
	var cc = pts[n] + Vector2(lean * 0.2, -h * 0.17)
	var Rx = h * 0.36
	var Ry = h * 0.22
	var g_d = hz(Color("#27501f"), lane)
	var g_m = hz(Color("#3a7a2e"), lane)
	var g_l = hz(Color("#5aa043"), lane)
	var g_h = hz(Color("#9bd563"), lane)
	var lobes := []
	var N = 34
	for i in N:
		var ang2 = i * 2.39996 + sd
		var rr = sqrt((i + 0.5) / N)
		var jx = (MK.hash1(sd + i * 1.3) - 0.5) * 0.25
		var jy = (MK.hash1(sd + i * 2.7) - 0.5) * 0.25
		var pos = cc + Vector2((cos(ang2) * rr + jx) * Rx, (sin(ang2) * rr * 0.9 + jy) * Ry)
		var rad = h * (0.062 + 0.05 * MK.hash1(sd + i * 3.9)) * (1.15 - 0.4 * rr)
		lobes.append([pos, rad])
	for e in ends:
		lobes.append([e, h * 0.058])
	lobes.sort_custom(self, "_lobe_y")
	var shadow_ell = Color(g_d.r * 0.6, g_d.g * 0.6, g_d.b * 0.6, 0.4)
	mk.ellipse(cc + Vector2(0, Ry * 0.95), Rx * 0.85, Ry * 0.38, shadow_ell, 16)
	var k2 = 0
	for L in lobes:
		mk.blob_ink(L[0] + Vector2(-h * 0.012, h * 0.016), L[1] * 1.1, L[1] * 0.98, sd + k2, 0.05, g_d, 4.5, 16)
		k2 += 1
	k2 = 0
	for L in lobes:
		mk.blob(L[0], L[1] * 0.97, L[1] * 0.86, sd + k2 * 1.3, 0.06, g_m, 16, g_l.linear_interpolate(g_m, 0.4))
		k2 += 1
	k2 = 0
	for L in lobes:
		var lp = L[0] + Vector2(L[1] * 0.2, -L[1] * 0.22)
		mk.blob(lp, L[1] * 0.62, L[1] * 0.5, sd + k2 * 2.1, 0.08, g_l, 12, g_h.linear_interpolate(g_l, 0.35))
		# leaf flecks: bright on the sunny side, dark on the other
		for q in 5:
			var fa = TAU * q / 5.0 + k2
			var fr = L[1] * (0.25 + 0.55 * MK.hash1(sd + k2 * 7.0 + q))
			var fp = L[0] + Vector2(cos(fa), sin(fa) * 0.8) * fr
			var sunny = (cos(fa) - sin(fa)) > 0.0
			mk.ellipse(fp, L[1] * 0.13, L[1] * 0.08, Color(g_h.r, g_h.g, g_h.b, 0.75) if sunny else Color(g_d.r, g_d.g, g_d.b, 0.55), 6, fa)
		k2 += 1
	# the scalloped edge: small clusters hanging off the crown
	for i in 12:
		var ea = TAU * i / 12.0 + sd
		var ep = cc + Vector2(cos(ea) * Rx * 1.02, sin(ea) * Ry * 0.98)
		var er = h * (0.03 + 0.025 * MK.hash1(sd + i * 8.3))
		mk.blob_ink(ep, er, er * 0.9, sd + i * 5.0, 0.06, g_m, 3.0, 10, g_l)
	if MK.hash1(sd + 8.0) > 0.4:
		for i in 11:
			var a2 = PI * (0.05 + 0.9 * MK.hash1(sd + i * 4.4))
			var rr2 = 0.45 + 0.55 * MK.hash1(sd + i * 6.6)
			var fcol = Color("#d9413a") if MK.hash1(sd + 9.0) > 0.5 else Color("#f0a233")
			mk.ellipse_ink(cc + Vector2(cos(a2) * Rx * rr2, sin(a2) * Ry * rr2 * 0.8), 7.0 * sc + 2.5, 7.0 * sc + 2.5, fcol, 2.2, 9)
	sh.shadow(b + Vector2(-w * 1.8, 5.0), w * 2.8 + h * 0.12, w * 0.34, Color(0.06, 0.1, 0.04, 0.18), 3)
	var ext = Rx * 1.25 + w * 1.3
	return {"mesh": mk.build(), "shade": sh.build(), "slice": slice_of(lane), "x0": min(b.x, cc.x) - ext, "x1": max(b.x, cc.x) + ext}


func _lobe_y(a, b) -> bool:
	return a[0].y < b[0].y


func _boulder(f: Dictionary) -> Dictionary:
	var mk = MK.new()
	var sh = MK.new()
	var lane: float = f["lane"]
	var sc = persp(lane)
	var rx = f["w"] * sc * 0.5
	var sd: float = f["seed"]
	var ry = rx * (0.55 + 0.25 * MK.hash1(sd + 1.0))
	var b = _base_point(f)
	var warm = MK.hash1(sd + 2.0)
	var base_c = hz(Color("#8d8c88").linear_interpolate(Color("#8f7e68"), warm), lane)
	var dark = base_c.darkened(0.3)
	var lite = base_c.lightened(0.28)
	mk.blob_ink(b + Vector2(0, -ry * 0.85), rx, ry, sd, 0.13, base_c, 4.0 * sc + 1.0, 14)
	mk.blob(b + Vector2(-rx * 0.18, -ry * 0.45), rx * 0.82, ry * 0.5, sd + 1.0, 0.12, Color(dark.r, dark.g, dark.b, 0.6), 12)
	mk.blob(b + Vector2(rx * 0.22, -ry * 1.3), rx * 0.55, ry * 0.38, sd + 2.0, 0.14, Color(lite.r, lite.g, lite.b, 0.85), 10)
	for k in 2:
		var cx = b.x + (MK.hash1(sd + k * 4.0) - 0.5) * rx * 0.8
		var cp := PoolVector2Array()
		var cw := PoolRealArray()
		for j in 4:
			var u = float(j) / 3.0
			cp.append(Vector2(cx + sin(u * 4.0 + k) * rx * 0.08, b.y - ry * (1.5 - 0.9 * u)))
			cw.append(3.0 * sc + 1.0)
		mk.ribbon(cp, cw, Color(0.1, 0.08, 0.07, 0.55))
	if MK.hash1(sd + 6.0) > 0.4:
		mk.blob(b + Vector2(-rx * 0.3, -ry * 1.6), rx * 0.45, ry * 0.2, sd + 3.0, 0.2, hz(Color("#5b8f3a"), lane), 9)
	for k in 3:
		var q = b + Vector2((MK.hash1(sd + k * 9.0) - 0.5) * rx * 2.6, 0)
		var pr = rx * (0.06 + 0.07 * MK.hash1(sd + k * 3.0))
		mk.ellipse_ink(q + Vector2(0, -pr * 0.5), pr, pr * 0.65, base_c, 1.5, 8)
	sh.shadow(b + Vector2(-rx * 0.5, 4.0), rx * 1.6, ry * 0.3, Color(0.06, 0.1, 0.04, 0.2), 3)
	return {"mesh": mk.build(), "shade": sh.build(), "slice": slice_of(lane), "x0": b.x - rx * 2.2, "x1": b.x + rx * 1.4}


func _cliff(f: Dictionary) -> Dictionary:
	var mk = MK.new()
	var C = g.CELL
	var sd: float = f["seed"]
	var W: float = f["w"]
	var H: float = f["h"]
	var cx = (f["x"] + 0.5) * C
	var x0 = cx - W * 0.5
	var step = 18.0
	var n = int(W / step)
	var tops := PoolVector2Array()
	var bots := PoolVector2Array()
	var c_top = hz(Color("#9d9282"), 0.1)
	var c_bot = hz(Color("#5d544b"), 0.1)
	var wk := PoolRealArray()
	for i in n + 1:
		var x = x0 + i * step
		var by = lane_y(_sm(int(floor(x / C))), 0.0) + 6.0
		var u = float(i) / n
		var env = pow(sin(u * PI), 0.55)
		var nz = 0.5 + 0.5 * sin(u * 7.0 + sd) * cos(u * 3.1 + sd * 2.0)
		var hh = H * (0.4 + 0.6 * floor(nz * 4.0) / 3.0) * env
		tops.append(Vector2(x, by - hh))
		bots.append(Vector2(x, by + 4.0))
		wk.append(7.0)
	for i in n:
		mk.quad_c(tops[i], c_top, tops[i + 1], c_top, bots[i + 1], c_bot, bots[i], c_bot)
	for s_f in [0.3, 0.55, 0.8]:
		for i in n:
			var a1 = tops[i].linear_interpolate(bots[i], s_f)
			var a2 = tops[i + 1].linear_interpolate(bots[i + 1], s_f)
			mk.quad(a1, a2, a2 + Vector2(0, 5.0), a1 + Vector2(0, 5.0), Color(0.1, 0.08, 0.07, 0.2))
	for i in range(1, n):
		if MK.hash1(sd + i * 1.7) > 0.7:
			var cp := PoolVector2Array()
			var cw := PoolRealArray()
			for j in 4:
				var u2 = float(j) / 3.0
				cp.append(tops[i].linear_interpolate(bots[i], 0.1 + 0.8 * u2) + Vector2(sin(u2 * 5.0 + i) * 4.0, 0))
				cw.append(3.0)
			mk.ribbon(cp, cw, Color(0.08, 0.06, 0.05, 0.4))
		if MK.hash1(sd + i * 2.9) > 0.6 and tops[i].y < bots[i].y - 30.0:
			mk.quad(tops[i] + Vector2(0, 2), tops[i + 1] + Vector2(0, 2), tops[i + 1] + Vector2(0, 11), tops[i] + Vector2(0, 11), hz(Color("#5b8f3a"), 0.1))
	mk.ribbon(tops, wk, INK)
	if f.get("cave", false):
		var cxm = x0 + W * f["cave_at"]
		var cw2 = 110.0 + 90.0 * MK.hash1(sd + 4.0)
		var cby = lane_y(_sm(int(floor(cxm / C))), 0.0) + 8.0
		_arch(mk, Vector2(cxm, cby), cw2 * 0.62 + 7.0, cw2 * 0.55 + 7.0, INK)
		_arch(mk, Vector2(cxm, cby), cw2 * 0.62, cw2 * 0.55, Color("#2b211a"))
		_arch(mk, Vector2(cxm, cby), cw2 * 0.5, cw2 * 0.44, Color("#130d0a"))
		_arch(mk, Vector2(cxm, cby), cw2 * 0.34, cw2 * 0.3, Color("#060403"))
		for k in 5:
			var tx = cxm + (k - 2) * cw2 * 0.18
			mk.tri(Vector2(tx - 6.0, cby - cw2 * 0.5 + 6.0 * abs(k - 2)), Vector2(tx + 6.0, cby - cw2 * 0.5 + 6.0 * abs(k - 2)), Vector2(tx, cby - cw2 * 0.34 + 4.0 * abs(k - 2)), Color("#3a2e25"))
		for k in 4:
			var sx = cxm + (k - 1.5) * cw2 * 0.5
			mk.ellipse_ink(Vector2(sx, cby - 4.0), 10.0 + 6.0 * MK.hash1(sd + k), 7.0, c_top.darkened(0.1), 2.0, 9)
	return {"mesh": mk.build(), "shade": null, "slice": 0, "x0": x0 - 20.0, "x1": x0 + W + 20.0}


func _arch(mk, base: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PoolVector2Array()
	for k in 19:
		var a = PI + PI * k / 18.0
		pts.append(base + Vector2(cos(a) * rx, sin(a) * ry))
	mk.fan(base, pts, col)
