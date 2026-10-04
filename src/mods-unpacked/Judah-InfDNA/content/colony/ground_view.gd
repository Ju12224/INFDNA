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
const AL = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
const WF = preload("res://mods-unpacked/Judah-InfDNA/core/world_features.gd")
const Seasons = preload("res://mods-unpacked/Judah-InfDNA/core/seasons.gd")

const INK = Color("#15121a")
# How a drawn tree changes with the camera zoom (the camera's zoom is below 1 when the view is magnified)
const CLOSE_INK_LO = 0.3      # the owner's outline as drawn is on the tree at and beyond CLOSE_INK_HI and fades out over the thin crisp close-up line by CLOSE_INK_LO
const CLOSE_INK_HI = 0.62
const CLOSE_DETAIL_LO = 0.42  # bark furrows, moss and rim leaves are full strength at and below CLOSE_DETAIL_LO and gone at CLOSE_DETAIL_HI
const CLOSE_DETAIL_HI = 0.95
const SHADE_FAR = 0.3         # the share of the soft light and shadow that stays on a tree seen from afar
const SWAY_Z = 0.95           # at and below this zoom the clumps of a canopy move each their own way (beyond it the whole tree bends as one)
const SWAY_N = 6              # the canopy moves on a (SWAY_N + 1)^2 grid of points (the manifest's `sway` says how much each one is leaf)
const FOG_K = 0.1             # depth fog on the trees: the share of haze on the farthest (trees stand in lanes 0.1 to 0.45; less close up, where it would wash out the detail)
const FOG_COL = Color(0.8, 0.87, 0.91)
const LEAF_Z = 1.05           # falling leaves are drawn at and below this zoom
const DEPTH = 192.0          # thickness of the walkable band, px (deep, so the rows of thick grass stand well apart)
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
const STRAW = Color("#b8ab5c")
# autumn leaves: [dark, mid, light, high] for orange, red and gold trees
const AUTUMN_SETS = [
	[Color("#8a3f16"), Color("#c8661e"), Color("#e8892b"), Color("#f7c25a")],
	[Color("#6e1d17"), Color("#a82f22"), Color("#cf4a2e"), Color("#ee8a5a")],
	[Color("#8a6a10"), Color("#c79a1c"), Color("#e8c23a"), Color("#f7e07a")],
]

var sim
var g
var world_seed := 0
var _t := 0.0
var _chunks := {}            # chunk index -> {band, shade, sl[], sy, oy, t}
var _stale := {}
var _vis := []               # [chunk index, chunk] for the chunks in view
var _vis_spr := []           # per slice: the drawn scenery (bushes, ferns, mushrooms) of the chunks in view
var _fcache := {}            # feature id -> {mesh, shade, slice, x0, x1}
var _flist := []
var _flist_key := -999999
var _vis_f := []             # per slice: visible feature entries
var _vis_shade := []
var perf             # perf.gd (optional): scenery detail level
var day              # day_cycle.gd (optional): the year, which tints the grass, turns the leaves and brings the snow
var poll_features := true   # rebuild a cached tree or rock whose ground has moved (see _prepare_features)
var _sk := -1        # season stage the cached scenery was built for: when it changes, chunks and trees are rebuilt a few per frame
var _P := {}         # the seasonal palette of the build in progress
var _lib = null       # art_lib.gd, once asked for
var _tex_loads := 0  # seasonal pictures loaded this frame (one a frame; the big close-up ones are read off the main thread)
var _grid_idx := PoolIntArray()     # the triangles of the canopy sway grid (the same for every tree)
var _grid_uv := PoolVector2Array()
var _pit_x := -999999 # the column of the open Void pit (arc.gd, drawn by world_view): no grass or scenery grows in it
const PIT_COLS = 28
const PIT_SWALLOW = 125.0     # px: scenery whose middle is this near the pit's falls into it


func _init(sim_) -> void:
	sim = sim_
	g = sim_.grid
	world_seed = sim_.seed_base
	for s in SLICES + 1:
		_vis_f.append([])
	var n = SWAY_N
	for j in n + 1:
		for i in n + 1:
			_grid_uv.append(Vector2(float(i) / n, float(j) / n))
	for j in n:
		for i in n:
			var a = j * (n + 1) + i
			_grid_idx.append_array(PoolIntArray([a, a + 1, a + n + 2, a, a + n + 2, a + n + 1]))


# The look of the year for whatever is about to be built (read once per chunk or feature, so one build is consistent).
func _season_palette() -> void:
	var t = day.sea_t if day != null else 0.0
	_P = {
		"gb": Seasons.blend_color(t, [Color("#72b04f"), GRASS_BACK, Color("#93994a"), Color("#8a9877")]),
		"gf": Seasons.blend_color(t, [Color("#aade5e"), GRASS_FRONT, Color("#bdb65a"), Color("#a8b79b")]),
		"dry": Seasons.blend(t, [0.0, 0.12, 0.7, 0.85]),
		"bloom": Seasons.bloom(t),
		"shroom": Seasons.blend(t, [0.35, 0.3, 1.0, 0.0]),
		"autumn": Seasons.autumn(t),
		"leaf": Seasons.leaf(t),
		"snow": Seasons.snow(t),
		"blossom": 1.0 - smoothstep(0.05, 0.2, Seasons.phase(t)),
	}


# A green of the meadow as the season has left it: fresh in spring, straw in autumn and winter.
func _sg(col: Color) -> Color:
	return col.linear_interpolate(STRAW, float(_P.get("dry", 0.0)) * 0.75)


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
	_tex_loads = 0
	if day != null:
		_sk = day.stage
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
	var pit = sim.void_x if sim.arc_stage == 3 else -999999
	if pit != _pit_x:
		for px in [_pit_x, pit]:
			if px != -999999:
				for ci2 in range(int(floor(float(px - PIT_COLS) / CH)), int(floor(float(px + PIT_COLS) / CH)) + 1):
					_stale[ci2] = true
		_pit_x = pit
	var c_lo = int(floor(float(cols[0]) / CH))
	var c_hi = int(floor(float(cols[1]) / CH))
	var budget = 14 if _chunks.empty() else 3
	_vis = []
	for ci in range(c_lo, c_hi + 1):
		var ch = _chunks.get(ci)
		var seasonal = ch != null and ch.get("sk", -1) != _sk
		if ch == null or seasonal or (_stale.has(ci) and t - ch["t"] > 0.6):
			var cost = 3 if seasonal else 1          # a change of season rebuilds one chunk per frame, so it never shows as a hitch
			if budget >= cost:
				budget -= cost
				ch = _build_chunk(ci)
				_chunks[ci] = ch
				_stale.erase(ci)
		if ch != null:
			_vis.append([ci, ch])
	# the drawn scenery of the chunks in view, per slice (gathered once a frame, not once per slice drawn)
	_vis_spr = []
	for s in SLICES + 1:
		_vis_spr.append([])
	for e in _vis:
		var by_slice = e[1].get("spr", {})
		for s2 in by_slice.keys():
			_vis_spr[s2].append_array(by_slice[s2])
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
		# The ground under a cached tree or rock can move: spoil mounds grow, outpost shafts open. Twice a second each one checks that it
		# still stands on the ground, and is rebuilt (one or two a frame, the old one drawn meanwhile) once it is more than 3 px off.
		if poll_features and e != null and _t - float(e.get("chk", -9.0)) > 0.5:
			e["chk"] = _t
			if abs(_base_point(f).y - float(e.get("by", 0.0))) > 3.0:
				e["sk"] = -2
		if e == null or e.get("sk", -1) != _sk:
			if budget > 0:
				budget -= 1
				e = _build_feature(f)
				e["sk"] = _sk
				e["by"] = _base_point(f).y
				e["chk"] = _t
				_fcache[f["id"]] = e
			elif e == null:
				continue
		if e["x1"] < px0 or e["x0"] > px1:
			continue
		if _pit_x != -999999 and abs((e["x0"] + e["x1"]) * 0.5 - (_pit_x + 0.5) * C) < PIT_SWALLOW:
			continue                    # a rock or tree standing where the ground gave way went down with it (while the pit is open)
		_vis_f[e["slice"]].append(e)
		if e["shade"] != null:
			_vis_shade.append(e)
	if _fcache.size() > 90:
		for id in _fcache.keys():
			var e2 = _fcache[id]
			if e2["x1"] < px0 - 6000.0 or e2["x0"] > px1 + 6000.0:
				_fcache.erase(id)


# The turf, drawn first (under every unit), then the snow over it (a node of its own, faded by how much has fallen), then the
# shadows over both.
func draw_turf(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for e in _vis:
		var ch = e[1]
		if ch["band"] != null:
			ci.draw_mesh(ch["band"], null)


func draw_shade(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for e in _vis:
		var ch2 = e[1]
		if ch2["shade"] != null:
			ci.draw_mesh(ch2["shade"], null)
	for fe in _vis_shade:
		ci.draw_mesh(fe["shade"], null)


func draw_snow(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var budget = 2
	for e in _vis:
		var ch = e[1]
		if not ch.has("snow"):
			if budget <= 0:
				continue
			budget -= 1
			ch["snow"] = _build_snow(e[0], ch)
		if ch["snow"] != null:
			ci.draw_mesh(ch["snow"], null)


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
	var lst = _vis_spr[s] if s < _vis_spr.size() and detail > 0 else []
	if lst.empty() and _vis_f[s].empty():
		return
	# how close the camera is (a zoom below 1 is a magnified view) and what part of the world it sees: only what is in view is drawn
	var ct = ci.get_canvas_transform()
	var z = 1.0 / max(0.01, ct.get_scale().x)
	var vr = ct.affine_inverse().xform(Rect2(Vector2.ZERO, ci.get_viewport_rect().size))
	if not lst.empty():
		var gust0 = 1.0 + 1.6 * sim.rain
		var shk = -1.0
		var au0 = day.autumn if day != null else 0.0
		var berry = 0.0
		if day != null:
			var yp = Seasons.phase(day.sea_t)
			berry = smoothstep(0.38, 0.44, yp) * (1.0 - smoothstep(0.71, 0.76, yp))      # berries from late summer through autumn
		var n_drawn = 0
		for it in lst:
			n_drawn += 1
			if detail == 1 and n_drawn % 2 == 0:
				continue
			if it["x"] + it["size"].x < vr.position.x or it["x"] - it["size"].x > vr.end.x:
				continue
			if it["kind"] == "shroom" and shk < 0.0:
				shk = _shroom_k()
			_draw_scenery(ci, it, gust0, shk, au0, berry)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _vis_f[s].empty():
		return
	var gust = 1.0 + 1.6 * sim.rain
	for fe in _vis_f[s]:
		if fe["x1"] < vr.position.x - 200.0 or fe["x0"] > vr.end.x + 200.0:
			continue
		var sway = 0.0
		var ph = fe["x0"] * 0.0137
		if fe.get("sway", 0.0) > 0.0:
			# a tree bends in the wind: the base stays put and the crown sways (a shear about the foot), more in rain
			sway = 0.0065 * gust * (sin(_t * 0.85 + ph) + 0.4 * sin(_t * 1.9 + ph * 1.7))
		var xf = Transform2D(Vector2(1, 0), Vector2(sway, 1), Vector2(-sway * fe["by"], 0))
		if fe.has("spr"):
			if fe["spr"].has("tree"):
				_draw_tree(ci, fe["spr"], fe["by"], z, sway, gust)
			else:
				_draw_sprite(ci, fe["spr"], xf)
		if fe["mesh"] != null:
			if sway != 0.0:
				ci.draw_mesh(fe["mesh"], null, null, xf)
			else:
				ci.draw_mesh(fe["mesh"], null)
		if fe.has("spr") and fe["spr"].has("leaves") and z < LEAF_Z:
			_draw_leaves(ci, fe["spr"], fe["by"], z, gust)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A drawn rock (or anything else with one picture): the picture of the entry at its place.
func _draw_sprite(ci: CanvasItem, sp: Dictionary, xf: Transform2D) -> void:
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture_rect(sp["base"], Rect2(sp["pos"], sp["size"]), false, sp["mod"])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A drawn tree, in layers (tree_art.py makes them): the base picture with its lines painted out, the spring and autumn looks blended over it by how far the
# year has gone (live, every frame, so the colours move smoothly between rebuilds of the cached entry), soft light and shadow (`shade`, stronger close up), the
# close-up detail (bark furrows, moss, rim leaves; only close up), the outline (as drawn far off; close up it fades out over a thinner crisp one, so the line
# keeps a sensible width on screen at every zoom), and a veil of haze on the trees of the back lanes (depth fog). Close up the canopy moves on a grid, every
# clump its own way; farther out the whole tree bends as one. z is the camera zoom (below 1 is a magnified view).
func _draw_tree(ci: CanvasItem, sp: Dictionary, by: float, z: float, sway: float, gust: float) -> void:
	var mod: Color = sp["mod"]
	if day != null and day.snow > 0.01:
		mod = mod.linear_interpolate(Color(0.86, 0.9, 0.97, mod.a), 0.3 * day.snow)     # frost
	var layers := []
	layers.append([sp["base"], mod])
	if sp.has("looks") and day != null:
		var spring = 1.0 - smoothstep(0.06, 0.3, Seasons.phase(day.sea_t))
		if spring > 0.02:
			var ts = _lazy(sp, "spring", false)
			if ts != null:
				layers.append([ts, Color(mod.r, mod.g, mod.b, spring)])
		var au = max(day.autumn, 1.0 - day.leaf)       # the dry autumn look stays on through winter (there is no bare picture yet)
		if au > 0.02:
			var ta = _lazy(sp, sp["autumn"], false)
			if ta != null:
				layers.append([ta, Color(mod.r, mod.g, mod.b, au)])
	if sp["shade"] != null:
		layers.append([sp["shade"], Color(mod.r, mod.g, mod.b, SHADE_FAR + (1.0 - SHADE_FAR) * (1.0 - smoothstep(0.35, 0.8, z)))])
	var da = 1.0 - smoothstep(CLOSE_DETAIL_LO, CLOSE_DETAIL_HI, z)
	if da > 0.03:
		var td = _lazy(sp, "detail", true)
		if td != null:
			layers.append([td, Color(mod.r, mod.g, mod.b, da)])
	var tc = _lazy(sp, "inkc", true) if z < CLOSE_INK_HI + 0.15 else null
	var ia = 1.0 if tc == null else smoothstep(CLOSE_INK_LO, CLOSE_INK_HI, z)
	if ia > 0.01 and sp["ink"] != null:
		layers.append([sp["ink"], Color(mod.r, mod.g, mod.b, ia)])
	if tc != null and z < CLOSE_INK_HI:
		layers.append([tc, mod])
	var fog = float(sp["fog"]) * (0.3 + 0.7 * smoothstep(0.5, 1.1, z))
	if fog > 0.01 and sp["sil"] != null:
		layers.append([sp["sil"], Color(FOG_COL.r, FOG_COL.g, FOG_COL.b, fog)])
	if z < SWAY_Z and sp.has("g_p0"):
		var amp = float(sp["g_amp"]) * gust * (1.0 - smoothstep(SWAY_Z * 0.75, SWAY_Z, z))
		var pts = _grid_points(sp, sway, by, amp)
		var rid = ci.get_canvas_item()
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for L in layers:
			VisualServer.canvas_item_add_triangle_array(rid, _grid_idx, pts, PoolColorArray([L[1]]), _grid_uv, PoolIntArray(), PoolRealArray(), L[0].get_rid())
	else:
		ci.draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(sway, 1), Vector2(-sway * by, 0)))
		var rect = Rect2(sp["pos"], sp["size"])
		for L in layers:
			ci.draw_texture_rect(L[0], rect, false, L[1])
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# The points of a tree's sway grid this frame: the whole tree sheared about its foot, and every point that is leaf moved besides on a little loop of its own
# (neighbouring points nearly together, so a clump moves as one and the next clump a little differently).
func _grid_points(sp: Dictionary, sway: float, by: float, amp: float) -> PoolVector2Array:
	var p0: PoolVector2Array = sp["g_p0"]
	var w: PoolRealArray = sp["g_w"]
	var ph1: PoolRealArray = sp["g_ph"]
	var ph2: PoolRealArray = sp["g_ph2"]
	var out := PoolVector2Array()
	out.resize(p0.size())
	var t1 = _t * 1.7
	var t2 = _t * 2.3
	var ay = amp * 0.4
	for k in p0.size():
		var p = p0[k]
		var wk = w[k]
		if wk > 0.0:
			out[k] = Vector2(p.x - sway * (by - p.y) + wk * amp * sin(t1 + ph1[k]), p.y + wk * ay * sin(t2 + ph2[k]))
		else:
			out[k] = Vector2(p.x - sway * (by - p.y), p.y)
	return out


# A picture of a tree entry that is not loaded with the entry: a seasonal look (read at once, one a frame) or a close-up layer (read off the main thread).
# Null until it is there, or when the entry has no such file.
func _lazy(sp: Dictionary, key: String, big: bool):
	if sp.has(key):
		return sp[key]
	var f = str(sp["files"].get(key, ""))
	if f == "":
		return null
	if _lib == null:
		_lib = AL.get_lib()
	var t = null
	if big:
		t = _lib.tex_mip_async(f)
		if t == null:
			return null
	else:
		if not _lib.has_tex_mip(f):
			if _tex_loads >= 1:
				return null
			_tex_loads += 1
		t = _lib.tex_mip(f)
	sp[key] = t
	return t


# Leaves drifting down from a leafy tree (only close up, and only for trees in view): a handful in summer, many in autumn, none on a bare tree. Each leaf is a
# pure function of the clock (no state): it lets go somewhere in the lower canopy, flutters and tumbles down, and fades as it lands at the foot.
func _draw_leaves(ci: CanvasItem, sp: Dictionary, by: float, z: float, gust: float) -> void:
	var lf = sp["leaves"]
	var au = day.autumn if day != null else 0.0
	var leaf = day.leaf if day != null else 1.0
	if leaf < 0.15:
		return
	var vis = 1.0 - smoothstep(LEAF_Z * 0.75, LEAF_Z, z)
	var n = int(round((lf["n"] + 2.0 * au * lf["n"]) * vis))
	if n <= 0:
		return
	var cb: Rect2 = lf["box"]
	var sd: float = lf["sd"]
	var c0: Color = lf["green"].linear_interpolate(lf["autumn"], au)
	var mod: Color = sp["mod"]
	var sz: float = lf["size"]
	var lt = _leaf_texture()
	for i in n:
		var h1 = MK.hash1(sd + i * 3.17)
		var h2 = MK.hash1(sd + i * 5.71 + 1.0)
		var h3 = MK.hash1(sd + i * 7.93 + 2.0)
		var period = 7.0 + 6.0 * h2
		var u = fposmod(_t / period + h1, 1.0)
		var x0 = cb.position.x + cb.size.x * h3
		var y0 = cb.position.y + cb.size.y * (0.35 + 0.65 * h2)
		var yb = by - 3.0 - 12.0 * h1
		var y = lerp(y0, yb, u)
		var drift = (14.0 + 30.0 * h3) * (1.0 if h1 > 0.5 else -1.0) * gust
		var x = x0 + drift * u + sin(_t * (1.3 + 0.7 * h2) + h3 * 6.0) * (6.0 + 6.0 * h1) * gust
		var a = smoothstep(0.0, 0.07, u) * (1.0 - smoothstep(0.86, 1.0, u))
		if a < 0.02:
			continue
		var spin = _t * (1.6 + 1.4 * h3) + h2 * 6.28
		var flip = cos(_t * (2.2 + 1.5 * h1) + h3 * 5.0)
		var col = c0.linear_interpolate(Color(c0.r * 0.7, c0.g * 0.7, c0.b * 0.6), h3 * 0.6)
		ci.draw_set_transform(Vector2(x, y), spin, Vector2(1.0, 0.25 + 0.75 * abs(flip)))
		var L = sz * (0.8 + 0.4 * h2)
		ci.draw_texture_rect(lt, Rect2(-L * 1.2, -L * 0.48, L * 2.4, L * 0.96), false, Color(col.r * mod.r * 1.15, col.g * mod.g * 1.15, col.b * mod.b * 1.15, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# The little leaf the falling leaves are drawn with: grey (lighter toward the tip, a darker midrib), tinted by the colour it is drawn in. Made once.
var _leaf_tex = null


func _leaf_texture():
	if _leaf_tex != null:
		return _leaf_tex
	var w = 40
	var h = 16
	var img = Image.new()
	img.create(w, h, false, Image.FORMAT_RGBA8)
	img.lock()
	for yy in h:
		for xx in w:
			var u = (xx + 0.5) / w
			var v = ((yy + 0.5) / h - 0.5) * 2.0
			var hw = pow(max(0.0, sin(PI * min(1.0, u * 1.06))), 0.75) * (1.0 - 0.25 * u)
			var edge = clamp((hw - abs(v)) * h * 0.5, 0.0, 1.0)
			var stem = clamp(1.0 - abs(v) * h * 0.5, 0.0, 1.0) * (1.0 if u < 0.12 else 0.0)
			var a = max(edge, stem)
			var g = 0.68 + 0.3 * u - 0.12 * abs(v)
			g *= 1.0 - 0.35 * clamp(1.0 - abs(v) * h * 0.6, 0.0, 1.0)          # the midrib
			img.set_pixel(xx, yy, Color(g, g, g, a))
	img.unlock()
	var t = ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	_leaf_tex = t
	return t


# The picture entry of a tree or rock feature, or null when the art is not there. `sh` is the ground shadow mesh builder.
func _sprite_entry(f: Dictionary, spr: Dictionary, sh) -> Dictionary:
	var lane: float = f["lane"]
	var b = _base_point(f)
	var sz: Vector2 = spr["size"]
	return {"mesh": null, "shade": sh.build(), "slice": slice_of(lane), "x0": b.x - sz.x * 0.6, "x1": b.x + sz.x * 0.6, "sway": spr.get("sway", 0.0), "by": b.y, "spr": spr}


func _tint(lane: float) -> Color:
	return Color.white.linear_interpolate(Color(0.8, 0.87, 0.93), (1.0 - clamp(lane, 0.0, 1.0)) * 0.5)


# No two trees of one kind are quite the same colour: a little lighter or darker, a little warmer or cooler.
static func _vary(sd: float) -> Color:
	var v = 0.945 + 0.1 * MK.hash1(sd + 21.0)
	var w = (MK.hash1(sd + 22.0) - 0.5) * 0.07
	return Color(v + w, v, v - w * 0.9, 1.0)


func _tree_sprite(f: Dictionary):
	var lib = AL.get_lib()
	var trees = lib.manifest().get("trees", [])
	if trees.empty():
		return null
	var sd: float = f["seed"]
	var r = MK.hash1(sd + 99.0)
	var name = "oak1"
	var hmul = 0.88
	if r < 0.30:
		name = "oak1"
	elif r < 0.58:
		name = "oak2"
	elif r < 0.68:
		name = "mossoak"
		hmul = 0.55
	elif r < 0.76:
		name = "acacia"
		hmul = 0.4
	elif r < 0.82:
		name = "grove"
		hmul = 0.5
	elif r < 0.93:
		name = "spruce"
		hmul = 0.95
	elif r < 0.97:
		name = "stump"
		hmul = 0.38
	else:
		name = "log"
		hmul = 0.16
	var def = null
	for t in trees:
		if t["name"] == name:
			def = t
	if def == null:
		return null
	var lane: float = f["lane"]
	var sc = persp(lane)
	var leafy = bool(def["leafy"])
	var base = lib.tex_mip(str(def["looks"]["summer"]))
	if base == null:
		return null
	var H = float(f["h"]) * sc * hmul
	var aspect = float(def["w"]) / float(def["h"])
	var size = Vector2(H * aspect, H)
	if name == "log":
		size = Vector2(float(f["w"]) * sc * 5.5, float(f["w"]) * sc * 5.5 * float(def["h"]) / float(def["w"]))
	var b = _base_point(f)
	var sways = leafy or name == "spruce"
	# a tree in a back lane is farther off: a little cooler, and veiled by the haze (the fog layer, see _draw_tree)
	var tint = Color.white.linear_interpolate(Color(0.9, 0.93, 0.97), 1.0 - clamp(lane, 0.0, 1.0))
	var spr = {"tree": true, "base": base, "size": size, "pos": Vector2(b.x - size.x * 0.5, b.y - size.y + 6.0 * sc), "mod": tint * _vary(sd),
		"sway": 1.0 if sways else 0.0, "files": {}, "fog": FOG_K * clamp((0.47 - lane) / 0.37, 0.0, 1.0)}
	if leafy:
		# the spring look and the autumn one (each tree turns orange, red or gold) are read when the year first needs them
		spr["autumn"] = ["orange", "red", "gold"][int(MK.hash1(sd + 55.0) * 2.99)]
		if def["looks"].has(spr["autumn"]):
			spr["looks"] = true
			for k in ["spring", spr["autumn"]]:
				if def["looks"].has(k):
					spr["files"][k] = str(def["looks"][k])
	# the outline as drawn and the soft light and shadow come with the tree; the close-up line and detail are read when the camera first comes close
	spr["ink"] = lib.tex_mip(str(def["ink"])) if def.has("ink") else null
	spr["shade"] = lib.tex_mip(str(def["shade"])) if def.has("shade") else null
	spr["sil"] = lib.tex_mip(str(def["sil"])) if def.has("sil") else null
	for k in [["inkc", "ink_close"], ["detail", "detail"]]:
		if def.has(k[1]):
			spr["files"][k[0]] = str(def[k[1]])
	if sways and def.has("sway"):
		_grid_setup(spr, def["sway"], sd)
	if leafy and def.has("canopy"):
		var cb = def["canopy"]
		var lc = def.get("leaf_rgb", {})
		var gcol = lc.get("summer", [90, 140, 60])
		var acol = lc.get(spr["autumn"], [200, 110, 40])
		spr["leaves"] = {"box": Rect2(spr["pos"] + Vector2(size.x * float(cb[0]), size.y * float(cb[1])), Vector2(size.x * float(cb[2] - cb[0]), size.y * float(cb[3] - cb[1]))),
			"sd": sd, "n": 2.0 + 2.0 * MK.hash1(sd + 41.0), "size": 5.5 * sc + 1.5,
			"green": Color8(int(gcol[0]), int(gcol[1]), int(gcol[2])), "autumn": Color8(int(acol[0]), int(acol[1]), int(acol[2]))}
	var sh = MK.new()
	sh.shadow(b + Vector2(-size.x * 0.12, 5.0), size.x * 0.42, 14.0 * sc + size.x * 0.03, Color(0.06, 0.1, 0.04, 0.2), 3)
	var e = _sprite_entry(f, spr, sh)
	var dress = MK.new()
	_tree_foot(dress, spr, def, b, sc, lane, sd)
	e["mesh"] = dress.build()
	return e


# The sway grid of a tree: the grid points over its picture, how much each one is leaf (from the manifest), and the phase of its own little loop (a smooth
# function of where it is, so a clump moves together and its neighbour a little out of step).
func _grid_setup(spr: Dictionary, grid: Array, sd: float) -> void:
	var n = SWAY_N
	if grid.size() != n + 1:
		return
	var p0 := PoolVector2Array()
	var w := PoolRealArray()
	var gph := PoolRealArray()
	var pos: Vector2 = spr["pos"]
	var size: Vector2 = spr["size"]
	for j in n + 1:
		var row = grid[j]
		for i in n + 1:
			p0.append(pos + Vector2(size.x * i / n, size.y * j / n))
			w.append(float(row[i]) if row.size() > i else 0.0)
			gph.append(2.4 * sin(i * 1.37 + sd) + 2.1 * sin(j * 1.91 + sd * 1.3) + 1.4 * sin((i + j) * 0.83 + sd * 0.7))
	var gph2 := PoolRealArray()
	for v in gph:
		gph2.append(v * 1.3)
	spr["g_p0"] = p0
	spr["g_w"] = w
	spr["g_ph"] = gph
	spr["g_ph2"] = gph2
	spr["g_amp"] = 0.0045 * size.y


# Where a drawn tree meets the ground: a soft dark patch over the join and two rows of grass in front of it (the far row darker and taller), so the flat bottom
# edge of the picture is buried and the trunk grows out of the meadow. Built once with the tree.
func _tree_foot(mk, spr: Dictionary, def: Dictionary, b: Vector2, sc: float, lane: float, sd: float) -> void:
	var size: Vector2 = spr["size"]
	var foot = def.get("foot", [0.25, 0.75])
	var x0 = spr["pos"].x + size.x * float(foot[0])
	var x1 = spr["pos"].x + size.x * float(foot[1])
	var fw = max(x1 - x0, 30.0)
	var cx = (x0 + x1) * 0.5
	var fy = spr["pos"].y + size.y                  # the bottom of the picture
	var ry = 4.0 * sc + fw * 0.03
	if float(_P["snow"]) > 0.3:
		mk.ellipse(Vector2(cx, fy + 1.0), fw * 0.62, ry * 1.1, Color(0.62, 0.73, 0.86), 16)
		mk.ellipse(Vector2(cx, fy - 1.0), fw * 0.6, ry * 0.95, Color(0.97, 0.985, 1.0), 16)
		return
	mk.shadow(Vector2(cx, fy - 2.0), fw * 0.6, ry * 1.5, Color(0.04, 0.06, 0.02, 0.17), 4)
	mk.shadow(Vector2(cx, fy - 1.0), fw * 0.44, ry * 0.7, Color(0.03, 0.04, 0.02, 0.2), 3)      # the contact shadow, tight under the trunk
	var c_dark = hz(_sg(Color("#2f6420")), lane)
	var c_mid = hz(_sg(Color("#4f8e30")), lane)
	var c_lite = hz(_sg(Color("#8cc656")), lane)
	for row in 2:
		var n = int(clamp(fw / (7.0 if row == 0 else 10.0), 10.0, 64.0))
		for k in n:
			var h1 = MK.hash1(sd + k * 1.9 + row * 40.0)
			var gp = Vector2(x0 - fw * 0.05 + (float(k) + h1) / n * fw * 1.1, fy + (-3.0 if row == 0 else 3.0) + MK.hash1(sd + k * 4.3 + row) * 4.0)
			var gl = (16.0 + 24.0 * MK.hash1(sd + k * 5.7 + row * 9.0)) * (0.6 + 0.4 * sc) * (1.0 if row == 0 else 0.62)
			mk.blade(gp, (MK.hash1(sd + k * 8.1 + row * 3.0) - 0.5) * gl * 0.9, gl, clamp(gl * 0.17, 2.0, 5.5), c_dark if row == 0 else c_mid, c_mid if row == 0 else c_lite)


func _rock_sprite(f: Dictionary):
	var lib = AL.get_lib()
	var rocks = lib.manifest().get("rocks", [])
	if rocks.size() < 7:
		return null
	var sd: float = f["seed"]
	var w: float = float(f["w"])
	var lane: float = f["lane"]
	var sc = persp(lane)
	# rock_0 is the spire, 1 the dome, 2 the cairn, 3 and 4 low boulders, 5 a slab, 6 a single stone
	var idx = 6
	if w > 170.0:
		idx = [0, 1, 1, 2][int(MK.hash1(sd + 7.0) * 3.99)]
	elif w > 110.0:
		idx = [1, 2, 3, 4][int(MK.hash1(sd + 7.0) * 3.99)]
	elif w > 70.0:
		idx = [3, 4, 5][int(MK.hash1(sd + 7.0) * 2.99)]
	elif w > 45.0:
		idx = [5, 6, 4][int(MK.hash1(sd + 7.0) * 2.99)]
	var def = rocks[idx]
	var tx = lib.tex(str(def["file"]))
	if tx == null:
		return null
	var width = w * sc * (0.95 if idx != 0 else 0.6)
	var size = Vector2(width, width * float(def["h"]) / float(def["w"]))
	var b = _base_point(f)
	var flip = MK.hash1(sd + 3.0) > 0.5
	var spr = {"base": tx, "size": size, "pos": Vector2(b.x - size.x * 0.5, b.y - size.y + 4.0 * sc), "mod": _tint(lane)}
	var sh = MK.new()
	sh.shadow(b + Vector2(-size.x * 0.1, 3.0), size.x * 0.62, 6.0 * sc + size.y * 0.07, Color(0.06, 0.1, 0.04, 0.22), 3)
	var e = _sprite_entry(f, spr, sh)
	# snow lies on the top of it in winter
	if float(_P["snow"]) > 0.5:
		var mk = MK.new()
		var top = Vector2(b.x, b.y - size.y * 0.97)
		mk.blob(top + Vector2(0, size.y * 0.05), size.x * 0.34, size.y * 0.1, sd, 0.15, Color(0.62, 0.73, 0.86), 12)
		mk.blob(top + Vector2(size.x * 0.01, size.y * 0.03), size.x * 0.32, size.y * 0.085, sd + 1.0, 0.15, Color(0.97, 0.985, 1.0), 12)
		e["mesh"] = mk.build()
	return e


func visible_slices() -> Array:
	var out := []
	for s in SLICES + 1:
		var any = not _vis_f[s].empty() or (s < _vis_spr.size() and not _vis_spr[s].empty())
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
	_season_palette()
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
	var spr := []
	_band(band, c0, sy, mf)
	_decor(sl, shade, band, c0, sy, mf, spr)
	var outs := []
	for mk in sl:
		outs.append(mk.build())
	var oy := 0.0
	for i in CH + 1:
		oy += sy[i]
	# the drawn scenery, per lane slice, back to front
	spr.sort_custom(self, "_by_lane")
	var by_slice := {}
	for e in spr:
		if not by_slice.has(e["slice"]):
			by_slice[e["slice"]] = []
		by_slice[e["slice"]].append(e)
	return {"band": band.build(), "shade": shade.build(), "sl": outs, "sy": sy, "mf": mf, "oy": oy / (CH + 1), "t": _t, "sk": _sk, "spr": by_slice}


func _by_lane(a, b) -> bool:
	return a["lane"] < b["lane"]


func _lane_col(lane: float, mfv: float, i: int, j: int, slope: float = 0.0) -> Color:
	var t = clamp(lane, 0.0, 1.0)
	var col = _P["gb"].linear_interpolate(_P["gf"], t)
	var n = sin((i) * 0.11 + j * 1.7) * 0.022 + (0.018 if j % 2 == 0 else -0.018)
	col = col.lightened(n) if n > 0.0 else col.darkened(-n)
	if mfv > 0.0:
		var m = MOUND_BACK.linear_interpolate(MOUND_FRONT, t)
		# the heap is lit from the upper right: faces that look right are warm and bright, those that look left fall into shade;
		# soil strata show as faint rows, and the foot of the heap is darker where it meets the turf
		var lit = clamp(slope * 1.3, -1.0, 1.0)
		m = m.lightened(0.16 * lit) if lit > 0.0 else m.darkened(-0.2 * lit)
		var row = 0.035 if j % 2 == 0 else -0.035
		m = m.lightened(row) if row > 0.0 else m.darkened(-row)
		col = col.linear_interpolate(m, mfv)
	return col


# A chunk's snow: a white cover over the whole walkable band (not over the bare mound), soft drifts, and a thick lip along the front edge.
# Built only once snow is on the ground; the node that draws it fades it in and out.
func _build_snow(ci: int, ch: Dictionary):
	var mk = MK.new()
	var C = g.CELL
	var c0 = ci * CH
	var sy: PoolRealArray = ch["sy"]
	var mf: PoolRealArray = ch["mf"]
	var white = Color(0.975, 0.985, 1.0)
	var cool = Color(0.8, 0.88, 0.96)
	var shade_c = Color(0.62, 0.73, 0.86)
	var rows = 5
	for j in rows:
		var la = -0.11 + 1.13 * float(j) / rows
		var lb = -0.11 + 1.13 * float(j + 1) / rows
		var ca = cool.linear_interpolate(white, clamp(la, 0.0, 1.0))
		var cb = cool.linear_interpolate(white, clamp(lb, 0.0, 1.0))
		for i in CH:
			var m0 = 1.0 - clamp(mf[i] * 1.6, 0.0, 1.0)
			var m1 = 1.0 - clamp(mf[i + 1] * 1.6, 0.0, 1.0)
			if m0 <= 0.01 and m1 <= 0.01:
				continue
			var xa = (c0 + i) * C
			var xb = xa + C
			mk.quad_c(Vector2(xa, lane_y(sy[i], la)), Color(ca.r, ca.g, ca.b, 0.88 * m0), Vector2(xb, lane_y(sy[i + 1], la)), Color(ca.r, ca.g, ca.b, 0.88 * m1),
				Vector2(xb, lane_y(sy[i + 1], lb)), Color(cb.r, cb.g, cb.b, 0.9 * m1), Vector2(xa, lane_y(sy[i], lb)), Color(cb.r, cb.g, cb.b, 0.9 * m0))
	# soft drifts: long ridges that follow the lanes across the whole chunk (their thickness comes from the absolute column, so they run on
	# over the chunk edges), thick in some places and thin in others; not blobs scattered on the turf
	for j in 6:
		var dl = 0.06 + 0.88 * float(j) / 5.0
		var dp := PoolVector2Array()
		var dpl := PoolVector2Array()
		var dw := PoolRealArray()
		var dw2 := PoolRealArray()
		var dps = persp(dl)
		for i in CH + 1:
			var colx = c0 + i
			var nz = 0.5 + 0.5 * sin(colx * 0.083 + j * 2.3) * sin(colx * 0.029 + j * 1.1 + 0.7)
			var thick = (2.0 + 13.0 * nz * nz) * dps * (1.0 - clamp(mf[i] * 3.0, 0.0, 1.0))
			var yy = lane_y(sy[i], dl) - 1.5 * dps * nz + sin(colx * 0.21 + j) * 0.8
			dp.append(Vector2(colx * C, yy))
			dpl.append(Vector2(colx * C, yy + 2.0 * dps))
			dw.append(max(0.5, thick))
			dw2.append(max(0.5, thick * 1.1))
		mk.ribbon(dpl, dw2, Color(shade_c.r, shade_c.g, shade_c.b, 0.7))
		mk.ribbon(dp, dw, white)
	# the lip: a thick white edge with a cool shadow under it, broken where the mound is
	var run := PoolVector2Array()
	var run_lo := PoolVector2Array()
	var wl := PoolRealArray()
	var wl2 := PoolRealArray()
	for i in CH + 1:
		var bare = mf[i] > 0.3
		if not bare:
			run.append(Vector2((c0 + i) * C, sy[i] - 2.5))
			run_lo.append(Vector2((c0 + i) * C, sy[i] + 3.0))
			wl.append(8.0 + 3.0 * MK.hash1((c0 + i) * 1.9))
			wl2.append(7.0)
		if (bare or i == CH) and run.size() >= 2:
			mk.ribbon(run_lo, wl2, shade_c)
			mk.ribbon(run, wl, white)
		if bare or i == CH:
			run = PoolVector2Array()
			run_lo = PoolVector2Array()
			wl = PoolRealArray()
			wl2 = PoolRealArray()
	return mk.build()


# Slope of the ground at column i of a chunk (px of height per px of width, + = falling to the right).
func _slope_at(sy: PoolRealArray, i: int) -> float:
	return (sy[min(i + 1, sy.size() - 1)] - sy[max(i - 1, 0)]) / (2.0 * g.CELL)


func _band(mk, c0: int, sy: PoolRealArray, mf: PoolRealArray) -> void:
	var C = g.CELL
	for j in STRIPS:
		var la = -0.11 + 1.13 * float(j) / STRIPS
		var lb = -0.11 + 1.13 * float(j + 1) / STRIPS
		for i in CH:
			var xa = (c0 + i) * C
			var xb = xa + C
			var s0 = _slope_at(sy, i)
			var s1 = _slope_at(sy, i + 1)
			mk.quad_c(Vector2(xa, lane_y(sy[i], la)), _lane_col(la, mf[i], c0 + i, j, s0),
				Vector2(xb, lane_y(sy[i + 1], la)), _lane_col(la, mf[i + 1], c0 + i + 1, j, s1),
				Vector2(xb, lane_y(sy[i + 1], lb)), _lane_col(lb, mf[i + 1], c0 + i + 1, j, s1),
				Vector2(xa, lane_y(sy[i], lb)), _lane_col(lb, mf[i], c0 + i, j, s0))
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
				if k == 0 and MK.hash1(col2 * 4.9 + 3.0) > 0.9:
					# a clod of packed earth with a dark rim and a lit top
					var cr = (4.0 + 4.0 * h1) * ps
					mk.ellipse(p1 + Vector2(0, 1.0 * ps), cr * 1.15, cr * 0.78, Color(0.2, 0.11, 0.06, 0.8), 9)
					mk.ellipse(p1, cr, cr * 0.7, Color("#8d5f38").linear_interpolate(Color("#b8834f"), h1), 9)
					mk.ellipse(p1 + Vector2(-cr * 0.25, -cr * 0.22), cr * 0.5, cr * 0.3, Color(1.0, 0.9, 0.7, 0.35), 7)
			elif mf[i] < 0.2:
				mk.blade(p1, (h1 - 0.5) * 5.0, (3.0 + 5.0 * h1) * ps, 1.7 * ps + 0.4, _sg(BLADES[0]), _sg(BLADES[int(h1 * 2.99)]))
		if mf[i] < 0.2 and MK.hash1(col2 * 2.37 + 4.0) > 0.86 - 0.45 * float(_P["autumn"]):
			var lane2 = MK.hash1(col2 * 8.1)
			var p2 = Vector2(col2 * C, lane_y(sy[i], lane2))
			var ps2 = persp(lane2)
			var lc = Color("#8a6a3a") if MK.hash1(col2 * 3.3) > 0.5 else Color("#6e5530")
			if float(_P["autumn"]) > 0.25 and MK.hash1(col2 * 5.9) > 0.35:
				lc = AUTUMN_SETS[int(MK.hash1(col2 * 7.7) * 2.99)][1]          # fallen leaves
			mk.ellipse(p2, 5.5 * ps2, 1.9 * ps2, hz(lc, lane2), 8, (MK.hash1(col2) - 0.5) * 0.9)


func _decor(sl: Array, shade, band, c0: int, sy: PoolRealArray, mf: PoolRealArray, spr: Array = []) -> void:
	var C = g.CELL
	var drawn = _scenery_ready()
	var ents := []
	for en in g.entrances:
		ents.append(int(en.x))
	for i in range(0, CH, 2):
		var col = c0 + i
		var h0 = MK.hash1(col * 3.17 + 0.5)
		# meadow patches: thick grass in some stretches, thin in others (a smooth function of the column, so it flows over chunk edges)
		var patch = 0.5 + 0.5 * sin(col * 0.047 + 1.3) * sin(col * 0.0173 + 0.4)
		if h0 > 0.12 + 0.62 * patch or mf[i] > 0.25:
			continue
		var near = false
		for ex in ents:
			if abs(col - ex) < 9:
				near = true
		if near or abs(col - _pit_x) < PIT_COLS:
			continue
		var lane = fposmod(col * 0.618034 + 0.2 * MK.hash1(col * 5.71 + 2.0), 1.0)      # spread evenly through the depth, not in random clumps and gaps
		var px = (col + MK.hash1(col * 9.1)) * C
		var p = Vector2(px, lane_y(_sy_at(sy, c0, px, C), lane))
		var ps = persp(lane)
		var sd = col * 1.37 + 0.11
		var r = MK.hash1(col * 1.93 + 7.0)
		if patch > 0.62 and r > 0.5 and MK.hash1(col * 2.6 + 5.0) > 0.45:
			r = r * 0.7                  # in a thick patch most of what grows is grass and flowers
		var mkr = sl[slice_of(lane)]
		if r < 0.36:
			_tuft(mkr, p, ps, sd, lane)
		elif r < 0.50:
			if MK.hash1(col * 4.3 + 1.0) < float(_P["bloom"]):
				_flowers(mkr, p, ps, sd, lane)
			else:
				_tuft(mkr, p, ps, sd, lane)
		elif r < 0.58:
			_clover(band, p, ps, sd, lane)
		elif r < 0.68:
			_pebbles(mkr, shade, p, ps, sd, lane)
		elif r < 0.76:
			if drawn:
				if MK.hash1(col * 6.1 + 2.0) > 0.6 or not _scenery_add(spr, shade, "shroom", col, c0, sy):
					_tuft(mkr, p, ps, sd, lane)
			elif MK.hash1(col * 6.1 + 2.0) < float(_P["shroom"]):
				_mushroom(mkr, shade, p, ps, sd, lane)
			else:
				_tuft(mkr, p, ps, sd, lane)
		elif r < 0.87:
			if drawn:
				if MK.hash1(col * 7.3 + 3.0) > 0.42 or not _scenery_add(spr, shade, "bush", col, c0, sy):
					_tuft(mkr, p, ps, sd, lane)
			else:
				_bush(mkr, shade, p, ps, sd, lane)
		else:
			if drawn:
				if MK.hash1(col * 8.9 + 4.0) > 0.36 or not _scenery_add(spr, shade, "fern", col, c0, sy):
					_tuft(mkr, p, ps, sd, lane)
			else:
				_fern(mkr, p, ps, sd, lane)
	# foreground: tall grass in front of everything (units walk behind it)
	for i in range(0, CH, 6):
		var col2 = c0 + i
		var patch2 = 0.5 + 0.5 * sin(col2 * 0.047 + 1.3) * sin(col2 * 0.0173 + 0.4)
		if mf[i] > 0.25 or MK.hash1(col2 * 4.4 + 1.0) > 0.25 + 0.6 * patch2:
			continue
		var lane2 = 1.03 + 0.12 * MK.hash1(col2 * 6.1)
		var px2 = (col2 + MK.hash1(col2 * 2.9)) * C
		var p2 = Vector2(px2, lane_y(_sy_at(sy, c0, px2, C), lane2))
		_tall(sl[SLICES], p2, persp(lane2), col2 * 2.11 + 0.3, lane2)


# ---------------------------------------------------------------- drawn scenery (the owner's bushes, ferns and mushrooms; scenery_art.py cuts them)
# They stand in the back lanes only (behind the trails, so the ants and the fights in front stay readable), a modest few per chunk, each picked,
# sized, flipped and placed from its column (the same every time). The season is read when the chunk is built (a change of season rebuilds it):
# bushes turn in autumn (live crossfade) and bear berries from late summer through autumn, ferns go rust-brown and in winter lie flat or are gone,
# mushrooms come up in autumn and after rain (sim.wet, read live: they grow out of the ground) and never in winter.
const SCENERY_LANE = [0.02, 0.27]
var _scen = null      # manifest items by kind, once read


func _scenery_ready() -> bool:
	if _scen == null:
		_scen = {}
		var sc = AL.get_lib().manifest().get("scenery", {})
		var items = sc.get("items", {}) if sc is Dictionary else {}
		var names = items.keys()
		names.sort()
		for nm in names:
			var it = items[nm]
			if not (it is Dictionary) or not it.has("files"):
				continue
			var k = str(it.get("kind", ""))
			if not _scen.has(k):
				_scen[k] = []
			_scen[k].append(it)
	return not _scen.empty()


# One drawn item of `kind` for the decor spot at column col (false when none goes here: no art, the season, or too close to the last one).
func _scenery_add(spr: Array, shade, kind: String, col: int, c0: int, sy: PoolRealArray) -> bool:
	var list = _scen.get(kind, [])
	if list.empty():
		return false
	var snow = float(_P["snow"])
	var hs = MK.hash1(col * 2.71 + 11.0)
	if kind == "shroom" and snow > 0.3:
		return false                                   # no mushrooms in winter
	if kind == "fern" and snow > 0.5 and hs < 0.65:
		return false                                   # most ferns are gone in winter; the rest lie flat
	if kind == "bush" and snow > 0.5 and hs < 0.5:
		return false
	var def = list[int(MK.hash1(col * 3.31 + 5.0) * list.size() * 0.999)]
	var C = g.CELL
	var lane = lerp(SCENERY_LANE[0], SCENERY_LANE[1], MK.hash1(col * 4.73 + 1.3))
	var ps = persp(lane)
	var gh = lerp(float(def["game_h"][0]), float(def["game_h"][1]), MK.hash1(col * 5.97 + 2.0)) * ps
	var k = gh / float(def["h"])
	var size = Vector2(float(def["w"]), float(def["h"])) * k
	var px = (col + MK.hash1(col * 9.1)) * C
	for o in spr:
		if abs(o["x"] - px) < (o["size"].x + size.x) * 0.32:
			return false                               # never two in a heap
	var reach = int(ceil(size.x * 0.5 / C)) + 2
	for en in g.entrances:
		if abs(col - int(en.x)) < reach + 8:
			return false                               # clear of the nest mouths
	for xx in range(col - reach, col + reach + 1, 2):
		if g.mound_h(xx) > 0.2:
			return false                               # and of the bare spoil heaps
	var by = lane_y(_sy_at(sy, c0, px, C), lane) + 2.0 * ps
	var foot = Vector2(float(def["foot"][0]), float(def["foot"][1])) * k
	var flip = MK.hash1(col * 2.23 + 9.0) > 0.5
	var lib = AL.get_lib()
	var files = def["files"]
	var pos = Vector2(px - foot.x, by - foot.y)          # (a flipped one is mirrored about its foot when drawn)
	var e = {"kind": kind, "lane": lane, "slice": slice_of(lane), "x": px, "by": by, "size": size, "flip": flip, "ph": col * 0.37, "pos": pos, "sy": 1.0, "sway": 0.0}
	# lane shading: cooler and a little darker toward the back, and no two quite alike
	var v = 0.93 + 0.1 * MK.hash1(col * 6.37 + 3.0)
	var tint = Color.white.linear_interpolate(Color(0.84, 0.9, 0.93), (1.0 - lane) * 0.45)
	e["mod"] = Color(tint.r * v, tint.g * v, tint.b * v)
	if kind == "bush":
		e["sway"] = 0.012
		var berry = files.has("summer_nb")
		e["berry"] = berry
		for lk in ["summer", "autumn", "summer_nb", "autumn_nb"]:
			e[lk] = lib.tex_mip(str(files[lk])) if files.has(lk) else null
		if snow > 0.5:
			e["winter"] = true
			e["mod"] = Color(e["mod"].r * 0.72, e["mod"].g * 0.72, e["mod"].b * 0.8)
	elif kind == "fern":
		e["sway"] = 0.03
		e["summer"] = lib.tex_mip(str(files["summer"]))
		e["autumn"] = lib.tex_mip(str(files.get("autumn", files["summer"])))
		if snow > 0.5:
			e["winter"] = true
			e["sway"] = 0.0
			e["sy"] = 0.38
			e["mod"] = Color(e["mod"].r * 0.62, e["mod"].g * 0.56, e["mod"].b * 0.52)
	else:
		e["summer"] = lib.tex_mip(str(files["summer"]))
		e["thr"] = MK.hash1(col * 7.77 + 6.0)
	if e["summer"] == null:
		return false
	spr.append(e)
	if kind != "shroom":
		shade.shadow(Vector2(px, by + 1.0), size.x * 0.4, 3.0 + size.y * 0.05, Color(0.06, 0.1, 0.04, 0.18), 3)
	return true


# How much the year and the weather bring mushrooms up (0 none, 1 all of them), read live each frame.
func _shroom_k() -> float:
	if day == null:
		return 0.3
	var sk = Seasons.blend(day.sea_t, [0.12, 0.1, 0.85, 0.0])
	var w = float(sim.wet)
	return clamp(sk + 0.6 * w * max(sk * 1.5, 0.3), 0.0, 1.0) * (1.0 - float(day.snow))


# One drawn item: its picture(s) blended by the season, swayed by the wind (a shear about its foot), flipped, flattened or grown as it stands.
func _draw_scenery(ci: CanvasItem, e: Dictionary, gust: float, shk: float, au: float, berry: float) -> void:
	var gx = 1.0
	var gy = float(e["sy"])
	var mod: Color = e["mod"]
	if e["kind"] == "shroom":
		var gk = smoothstep(e["thr"], e["thr"] + 0.12, shk)
		if gk < 0.03:
			return
		gx = 0.55 + 0.45 * gk
		gy = gk
	var sw = 0.0
	if e["sway"] > 0.0:
		sw = float(e["sway"]) * gust * (sin(_t * 1.3 + e["ph"]) + 0.35 * sin(_t * 2.9 + e["ph"] * 1.7))
	var sx = -gx if e["flip"] else gx
	var by: float = e["by"]
	var cx: float = e["x"]
	ci.draw_set_transform_matrix(Transform2D(Vector2(sx, 0), Vector2(sw, gy), Vector2(cx - sx * cx - sw * by, by - gy * by)))
	var rect = Rect2(e["pos"], e["size"])
	if e["kind"] == "bush":
		var a = 1.0 if e.has("winter") else au
		var b = berry if e["berry"] else 0.0
		var t0 = e["summer_nb"] if e["berry"] else e["summer"]
		var t1 = e["autumn_nb"] if e["berry"] else e["autumn"]
		if a < 0.98:
			ci.draw_texture_rect(t0, rect, false, mod)
			if b > 0.02:
				ci.draw_texture_rect(e["summer"], rect, false, Color(mod.r, mod.g, mod.b, b))
		if a > 0.02 and t1 != null:
			ci.draw_texture_rect(t1, rect, false, Color(mod.r, mod.g, mod.b, a if a < 0.98 else 1.0))
			if b > 0.02 and e["autumn"] != null:
				ci.draw_texture_rect(e["autumn"], rect, false, Color(mod.r, mod.g, mod.b, a * b))
	elif e["kind"] == "fern":
		var a2 = 1.0 if e.has("winter") else au
		if a2 < 0.98:
			ci.draw_texture_rect(e["summer"], rect, false, mod)
		if a2 > 0.02:
			ci.draw_texture_rect(e["autumn"], rect, false, Color(mod.r, mod.g, mod.b, a2 if a2 < 0.98 else 1.0))
	else:
		ci.draw_texture_rect(e["summer"], rect, false, mod)


func _tuft(mk, p: Vector2, ps: float, sd: float, lane: float, big: float = 1.0) -> void:
	var n = 6 + int(MK.hash1(sd) * 5.0)
	for i in n:
		var h1 = MK.hash1(sd + i * 1.7)
		var h2 = MK.hash1(sd + i * 3.1 + 5.0)
		mk.blade(p + Vector2((h1 - 0.5) * 18.0 * ps * big, 0), (h2 - 0.5) * 16.0 * ps, (13.0 + 16.0 * h2) * ps * big,
			3.4 * ps, hz(_sg(GREENS[int(h1 * 1.99)]), lane), hz(_sg(GREENS[2 + int(h2 * 1.99)]), lane))


func _tall(mk, p: Vector2, ps: float, sd: float, lane: float) -> void:
	for i in 9:
		var h1 = MK.hash1(sd + i * 1.3)
		var h2 = MK.hash1(sd + i * 2.9 + 4.0)
		mk.blade(p + Vector2((h1 - 0.5) * 30.0 * ps, 0), (h2 - 0.5) * 26.0 * ps, (28.0 + 48.0 * h2) * ps, 3.8 * ps,
			_sg(Color("#3a6620")), _sg(GREENS[2 + int(h1 * 1.99)]))


func _flowers(mk, p: Vector2, ps: float, sd: float, lane: float) -> void:
	var fc = FLOWERS[int(MK.hash1(sd + 9.0) * 4.99)]
	var n = 2 + int(MK.hash1(sd + 3.0) * 3.0)
	for i in n:
		var h1 = MK.hash1(sd + i * 2.3)
		var h2 = MK.hash1(sd + i * 4.7 + 1.0)
		var bx = (h1 - 0.5) * 22.0 * ps
		var ln = (16.0 + 18.0 * h2) * ps
		var lean = (h2 - 0.5) * 8.0 * ps
		mk.blade(p + Vector2(bx, 0), lean, ln, 1.8 * ps + 0.4, hz(_sg(Color("#46742a")), lane), hz(_sg(Color("#6aa23c")), lane))
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
		mk.ellipse(p + Vector2((h1 - 0.5) * 30.0 * ps, (h2 - 0.5) * 5.0 * ps), 4.4 * ps, 1.8 * ps, hz(_sg(Color("#4f8f33") if h1 > 0.5 else Color("#5fa03a")), lane), 8, (h2 - 0.5) * 0.6)
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
	var aut = float(_P["autumn"]) * (0.0 if MK.hash1(sd + 12.0) > 0.7 else 1.0)
	if aut > 0.0:
		var bs = AUTUMN_SETS[int(MK.hash1(sd + 11.0) * 2.99)]
		dark = hz(dark.linear_interpolate(bs[0], aut), lane)
		mid = hz(mid.linear_interpolate(bs[1], aut), lane)
		lite = hz(lite.linear_interpolate(bs[2], aut), lane)
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
	if MK.hash1(sd + 5.0) > 0.6 and float(_P["snow"]) < 0.5:
		for i in 5:
			mk.ellipse(p + Vector2((MK.hash1(sd + i * 3.0) - 0.5) * sz * 1.8, -sz * (0.5 + 0.5 * MK.hash1(sd + i * 7.0))), 2.2 * ps, 2.2 * ps, Color("#d9413a"), 6)
	if float(_P["snow"]) > 0.5:
		for i in n / 2 + 1:
			var q4 = p + Vector2((float(i) / max(1, n / 2) - 0.5) * sz * 1.6 + sz * 0.14, -sz * 1.0 - sz * 0.3 * sin(i * 2.1 + sd))
			mk.blob(q4, sz * 0.36, sz * 0.2, sd + i * 3.1, 0.12, Color(0.97, 0.985, 1.0), 9)
	sh.shadow(p + Vector2(-sz * 0.5, 2.0), sz * 1.7, sz * 0.3, Color(0.06, 0.1, 0.04, 0.2), 3)


func _fern(mk, p: Vector2, ps: float, sd: float, lane: float) -> void:
	for i in 6:
		var h1 = MK.hash1(sd + i * 1.7)
		var sgn = -1.0 if i % 2 == 0 else 1.0
		mk.blade(p + Vector2(sgn * 2.0 * ps, 0), sgn * (16.0 + 18.0 * h1) * ps, (26.0 + 22.0 * h1) * ps, 4.4 * ps,
			hz(_sg(Color("#3f7a2a")), lane), hz(_sg(Color("#7cbc4c")), lane))


# ---------------------------------------------------------------- landmarks
func _build_feature(f: Dictionary) -> Dictionary:
	_season_palette()
	match f["kind"]:
		"tree":
			return _tree(f)
		"cliff":
			return _cliff(f)
	return _boulder(f)


func _base_point(f: Dictionary) -> Vector2:
	return Vector2((f["x"] + 0.5) * g.CELL, lane_y(_sm(f["x"]), f["lane"]) + 4.0)


func _tree(f: Dictionary) -> Dictionary:
	var drawn = _tree_sprite(f)
	if drawn != null:
		return drawn
	# every tree is one of the owner's pictures; without its picture (art missing) nothing stands here
	var b = _base_point(f)
	return {"mesh": null, "shade": null, "slice": slice_of(float(f["lane"])), "x0": b.x, "x1": b.x, "sway": 0.0, "by": b.y}


func _boulder(f: Dictionary) -> Dictionary:
	var drawn = _rock_sprite(f)
	if drawn != null:
		return drawn
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
	var dark = base_c.darkened(0.34)
	var lite = base_c.lightened(0.3)
	var mid = base_c.lightened(0.12)
	var snowy = float(_P["snow"]) > 0.5
	# an angular silhouette (a rock, not a blob) with a flat base
	var c = b + Vector2(0, -ry * 0.62)
	var n = 12
	var outl := PoolVector2Array()
	for i in n:
		var a2 = TAU * (i + 0.5 * MK.hash1(sd + i)) / n
		var k = 0.84 + 0.3 * MK.hash1(sd + i * 3.7)
		var p = Vector2(cos(a2) * rx * k, sin(a2) * ry * k)
		p.y = min(p.y, ry * 0.62)
		outl.append(c + p)
	var ow = 3.4 * sc + 1.4
	var ink_pts := PoolVector2Array()
	for p in outl:
		ink_pts.append(p + (p - c).normalized() * ow)
	mk.fan(c, ink_pts, INK)
	mk.fan(c, outl, base_c, base_c.lightened(0.08))
	# planes: a lit top, a lighter right face, a shaded left and underside
	for i in n:
		var j = (i + 1) % n
		var d0 = outl[i] - c
		var d1 = outl[j] - c
		var am = atan2((d0.y + d1.y) * 0.5, (d0.x + d1.x) * 0.5)
		var col = null
		var r = 0.6
		if am > -2.45 and am < -0.75:
			col = Color(lite.r, lite.g, lite.b, 0.9)
			r = 0.5
		elif am >= -0.75 and am < 0.75:
			col = Color(mid.r, mid.g, mid.b, 0.75)
			r = 0.68
		elif am > 1.5 or am < -2.6:
			col = Color(dark.r, dark.g, dark.b, 0.6)
			r = 0.55
		if col != null:
			mk.quad(outl[i], outl[j], c + d1 * r, c + d0 * r, col)
			mk.ribbon(PoolVector2Array([c + d0 * r, outl[i]]), PoolRealArray([1.6 * sc + 0.6, 1.6 * sc + 0.6]), Color(0.08, 0.06, 0.05, 0.35))
	# strata
	for k in 3:
		var yy = c.y + ry * (-0.25 + 0.3 * k)
		var hw = rx * (0.78 - 0.18 * abs(-0.25 + 0.3 * k) * 2.0)
		var lp := PoolVector2Array()
		var lw := PoolRealArray()
		for j in 6:
			var u = float(j) / 5.0
			lp.append(Vector2(c.x - hw + 2.0 * hw * u, yy + sin(u * 5.0 + sd + k) * ry * 0.05))
			lw.append((1.8 + 0.8 * sin(u * PI)) * sc + 0.5)
		mk.ribbon(lp, lw, Color(0.08, 0.06, 0.05, 0.22))
	# cracks that fork
	for k in 2:
		var cx = c.x + (MK.hash1(sd + k * 4.0) - 0.5) * rx * 0.9
		var cp := PoolVector2Array()
		var cw := PoolRealArray()
		for j in 5:
			var u = float(j) / 4.0
			cp.append(Vector2(cx + sin(u * 5.0 + k * 2.0 + sd) * rx * 0.1, c.y - ry * (0.85 - 1.15 * u)))
			cw.append((3.2 * (1.0 - u * 0.6)) * sc + 0.8)
		mk.ribbon(cp, cw, Color(0.07, 0.05, 0.05, 0.62))
		var fork := PoolVector2Array([cp[2], cp[2] + Vector2((1.0 if k == 0 else -1.0) * rx * 0.2, ry * 0.12), cp[2] + Vector2((1.0 if k == 0 else -1.0) * rx * 0.3, ry * 0.34)])
		mk.ribbon(fork, PoolRealArray([2.2 * sc + 0.6, 1.8 * sc + 0.5, 1.2 * sc + 0.4]), Color(0.07, 0.05, 0.05, 0.55))
	# mineral speckle
	for k in 16:
		var sa = TAU * MK.hash1(sd + k * 2.9)
		var sr = sqrt(MK.hash1(sd + k * 5.3)) * 0.72
		var q = c + Vector2(cos(sa) * rx * sr, sin(sa) * ry * sr * 0.8)
		mk.ellipse(q, 1.5 * sc + 0.7, 1.1 * sc + 0.5, Color(0.05, 0.04, 0.04, 0.4) if k % 2 == 0 else Color(1, 1, 1, 0.35), 5)
	if not snowy:
		# lichen on the lit top, moss in the shade and round the foot
		for k in 3:
			var la = -2.3 + 1.5 * MK.hash1(sd + 20.0 + k)
			var lp2 = c + Vector2(cos(la) * rx * 0.55, sin(la) * ry * 0.5)
			var lc = hz(Color("#d9a441") if MK.hash1(sd + 30.0 + k) > 0.5 else Color("#a8c08a"), lane)
			var lr = rx * (0.07 + 0.05 * MK.hash1(sd + 40.0 + k))
			mk.blob(lp2, lr, lr * 0.7, sd + 50.0 + k, 0.25, lc, 9)
			for q2 in 4:
				mk.ellipse(lp2 + Vector2((q2 - 1.5) * lr * 0.55, (q2 % 2) * lr * 0.2 - lr * 0.1), lr * 0.22, lr * 0.16, lc.lightened(0.25), 5)
		if MK.hash1(sd + 6.0) > 0.3:
			mk.blob(c + Vector2(-rx * 0.28, -ry * 0.82), rx * 0.42, ry * 0.2, sd + 3.0, 0.22, hz(Color("#4f8a3a"), lane), 10)
			mk.blob(c + Vector2(-rx * 0.22, -ry * 0.88), rx * 0.28, ry * 0.12, sd + 4.0, 0.2, hz(Color("#7cb653"), lane), 9)
		mk.blob(b + Vector2(-rx * 0.5, -ry * 0.08), rx * 0.3, ry * 0.12, sd + 5.0, 0.25, hz(Color("#4a7e36"), lane), 9)
	else:
		mk.blob(c + Vector2(rx * 0.02, -ry * 1.0), rx * 0.82, ry * 0.4, sd + 7.0, 0.14, Color(0.62, 0.73, 0.86), 12)
		mk.blob(c + Vector2(rx * 0.04, -ry * 1.08), rx * 0.78, ry * 0.32, sd + 8.0, 0.14, Color(0.97, 0.985, 1.0), 12)
		mk.ellipse(b + Vector2(0, 1.0), rx * 1.25, ry * 0.18, Color(0.97, 0.985, 1.0), 12)
	# pebbles and a few blades of grass round the foot
	for k in 5:
		var q3 = b + Vector2((MK.hash1(sd + k * 9.0) - 0.5) * rx * 2.8, MK.hash1(sd + k * 4.0) * 2.0)
		var pr = rx * (0.05 + 0.07 * MK.hash1(sd + k * 3.0))
		mk.ellipse_ink(q3 + Vector2(0, -pr * 0.5), pr, pr * 0.65, base_c.darkened(0.08 * (k % 3)), 1.4, 8)
	if not snowy:
		for k in 5:
			var gx = b.x + (MK.hash1(sd + 60.0 + k) - 0.5) * rx * 2.2
			var gl = clamp(rx * (0.18 + 0.2 * MK.hash1(sd + 70.0 + k)), 8.0, 40.0)
			mk.blade(Vector2(gx, b.y + 1.0), (MK.hash1(sd + 80.0 + k) - 0.5) * gl * 0.9, gl, clamp(rx * 0.04, 2.5, 5.0), hz(_sg(Color("#3f7a2a")), lane), hz(_sg(Color("#7cbc4c")), lane))
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
	if float(_P["snow"]) > 0.5:
		for i in n:
			var d0 = 9.0 + 9.0 * MK.hash1(sd + i * 3.3)
			var d1 = 9.0 + 9.0 * MK.hash1(sd + (i + 1) * 3.3)
			mk.quad(tops[i], tops[i + 1], tops[i + 1] + Vector2(0, d1), tops[i] + Vector2(0, d0), Color(0.96, 0.98, 1.0))
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
