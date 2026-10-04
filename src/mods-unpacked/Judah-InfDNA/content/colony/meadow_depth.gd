extends Node2D
# Thick meadow grass in depth rows (the owner's "super thick grass"). The surface is a deep world of walking lanes, and four rows
# ("curtains") of tall, dense grass stand across it at fixed depths. Zoomed out, the rows are closed and hide the lanes behind them
# (and the cost of drawing whatever walks there); small symbols float over the grass where something happens below (a fight, a pile
# being harvested, the bird striking, an Apex ant, a squad under orders), and a click on one flies the camera down to it. Zooming in
# picks the depth in focus: the rows in front of it lean apart, bow, slide toward the camera and fade (the "2D and 3D" feel), so the
# lane in focus is clear. Key 6 turns the grass off and on.
#
# How it is drawn
# - Each row of each ground chunk (ground_view.CH columns) is built ONCE into two cached meshes (one per half chunk). The meshes carry
#   no vertex colours, only UVs into a tiny palette texture per row (height along the blade x tone): GLES2 ignores the modulate of
#   draw_mesh for vertex-coloured meshes, so this is what lets a row fade, and a change of season only repaints four 8x16 textures.
# - Wind is a shear about the root line per half chunk (a slow wave rolling across the meadow); parting is the same one transform with
#   a lean away from the screen centre, a bow, a drop and a scale about the camera. No per-blade GDScript runs per frame.
# - The rows must stand BETWEEN the units in depth, so they are drawn inside ant_view's depth-sorted loop: ant_view calls pass_item()
#   for every item it draws, which first draws any row whose lane the loop has just passed, then says whether the item is completely
#   hidden behind a closed row (ant_view then skips it). The row lanes sit exactly on ant_view's depth-bucket boundaries, so nothing is
#   drawn on the wrong side of a row. Rows in front of every unit are drawn by this node right after ant_view.

const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const Seasons = preload("res://mods-unpacked/Judah-InfDNA/core/seasons.gd")
const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")
const Orders = preload("res://mods-unpacked/Judah-InfDNA/core/orders.gd")
const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")

const INK = Color("#15121a")
const TOGGLE_KEY = KEY_6
const CH = GroundView.CH          # columns per chunk (the ground's cache unit, whose smoothed heights the rows stand on)
const PIECES = 2                  # meshes per row and chunk, each with its own sway and parting
const PW = 24                     # columns per piece (CH / PIECES)
const NC = 4
const INNER = 4                   # rows that can hide a unit: all of them, the fringe in front of the lip too (no gap anywhere in the meadow)
# ant_view sorts by depth into 48 buckets of (lane + 2) / 3.2; bucket b starts at lane b / 15 - 2. Each row sits on one such boundary:
# back row 0.2 (behind the empty-handed trail), middle 0.533 (just in front of the food piles), front 0.867 (in front of the fight
# lane), and a fringe at 1.067 in front of the lip.
const ROW_B = [33, 38, 43, 46]
const HEIGHT = [130.0, 150.0, 146.0, 118.0]  # tallest blades, px before perspective (tall enough to hide the lanes behind across the deep band)
const SOLID = [0.62, 0.66, 0.66, 0.62]     # share of the height that is a closed wall of grass at the foot
# The rows open one at a time, front first, as the camera comes in: at every usual zoom they all stand (the colony is hidden in the grass,
# and what it hides is not drawn; symbols mark what goes on, a boss always shows), and each step further in opens one more row. The last
# row opens deep in (the camera goes down to cam.min_zoom), where the dense short lawn (ground_view.gd) still covers the ground.
const Z_HI = [0.18, 0.27, 0.38, 0.50]       # camera zoom at which a row begins to part (zoom < 1 is a magnified view) ...
const Z_LO = [0.12, 0.20, 0.29, 0.40]       # ... and has gone
const FADE_IN = 0.45              # a freshly built row fades in (never pops)
const ANT_H = 34.0                # px an ant stands at perspective 1 (the tallest caste)
const DL = GroundView.DEPTH * GroundView.LANE_K
const FLY_TIME = 0.85
const SYM_R = 9.0                 # symbol radius, screen px
const MAX_SYM = 9
const KINDS = ["fight", "bird", "apex", "squad", "harvest"]    # symbol priority
const LABELS = {"fight": "Fight", "bird": "Bird strike", "apex": "Apex ant", "squad": "Squad", "harvest": "Harvest"}
const ACCENT = {"fight": Color("#ff5a4a"), "bird": Color("#9fd3ff"), "apex": Color(1.0, 0.82, 0.32), "harvest": Color("#7ed957")}
# palette rows: 12 tones (shade -> sunlit), then snow, seed heads, petals, flower hearts; 8 texels root -> tip
const V_SNOW = 12.5 / 16.0
const V_SEED = 13.5 / 16.0
const V_PETAL = 14.5 / 16.0
const V_HEART = 15.5 / 16.0
const PETALS = [Color("#d9c8f2"), Color("#f6f1e2"), Color("#f7d046"), Color("#f6f1e2")]
# blade layers of a row, back to front: the dark thatch, the body, the lit front blades
const L_SP = [4.2, 6.4, 9.6]      # spacing, px before perspective
const L_H0 = [0.5, 0.62, 0.36]    # height range (share of the row's height)
const L_H1 = [0.8, 1.0, 0.8]
const L_W0 = [8.0, 6.5, 7.0]      # base width range
const L_W1 = [12.0, 9.5, 11.0]
const L_LEAN = [0.3, 0.45, 0.7]   # how far a tip may lean (share of its height)
const L_DROOP = [0.0, 0.22, 0.46] # how far a long blade arches over
const L_T0 = [0.02, 0.2, 0.47]    # tone of the shaded side
const L_T1 = [0.13, 0.38, 0.64]
const L_TR = [0.12, 0.26, 0.36]   # the sunlit side (the sun stands up and to the right) is this much brighter
const L_FOLD = [false, true, true]
const L_DY = [0.5, 2.0, 4.5]      # roots this far toward the viewer, px before perspective
const L_INK = [false, false, true]

var scene                  # colony_scene.gd: everything else is read from it
var sim
var cam
var ground
var ant_view
var day
var perf
var enabled := true
var stat_skipped := 0      # units ant_view skipped in its last pass (hidden in the grass)
var stat_build_us := 0     # build time spent in the last frame
var _on_k := 1.0
var _t := 0.0
var _lanes := []
var _ps := []
var _part := [0.0, 0.0, 0.0, 0.0]
var _alpha := [1.0, 1.0, 1.0, 1.0]
var _dense := [false, false, false, false]
var _hs := [0.0, 0.0, 0.0, 0.0]       # closed height of each row, px (with a margin)
var _cover_max := -1.0                # lane of the frontmost closed row (-1: none)
var _chunks := {}                     # chunk index -> built rows (see _new_entry)
var _vis := []                        # [chunk index, entry] in view, left to right
var _pal := []                        # palette texture per row
var _pal_img := []
var _pal_t := -9999.0
var _pal_i := 0
var _snow := 0.0
var _flat := 1.0                      # under snow the grass is pressed down a little
var _wind := 1.0
var _cx := 0.0                        # camera centre x and half the view width (world px)
var _half := 1000.0
var _pf := -1                         # frame of ant_view's last pass
var _nxt := 0                         # next row that pass will draw
var _keep := {}                       # ids that are never skipped (the selection)
var _lp := {}                         # rows parted locally around the selection: (piece * NC + row) -> 0..1
var _sig_t := 0.0
var _ent := []                        # what clears the grass: nest holes, the rival mound, a fallen bird (back row only)
var _rival_x := -999999
var _carc := []
var _bv := PoolVector2Array()         # the mesh being built
var _bu := PoolVector2Array()
var _btips := PoolVector2Array()
var _sym := []                        # live symbols: {kind, x, tx, lane, col, a, on}
var _sym_t := 0.0
var _hover = null
var _fly := {}
var _fly_p := Vector2.ZERO
var _fly_z := 0.0
var _symn: Node2D
var _font = null
var _C := 6.0                         # world px per grid cell


func _ready() -> void:
	for c in NC:
		_lanes.append(float(ROW_B[c]) / 15.0 - 2.0)
		_ps.append(GroundView.persp(_lanes[c]))
		var img = Image.new()
		img.create(8, 16, false, Image.FORMAT_RGBA8)
		_pal_img.append(img)
		var tex = ImageTexture.new()
		tex.create_from_image(img, Texture.FLAG_FILTER)
		_pal.append(tex)
	_symn = Node2D.new()          # the symbols: above the light pass and the weather, so they read at night and in rain
	_symn.z_index = 1
	_symn.connect("draw", self, "_draw_symbols")
	add_child(_symn)
	_font = Kit.font(14, 2)
	if Engine.has_meta("infdna_meadow"):
		enabled = bool(Engine.get_meta("infdna_meadow"))
		_on_k = 1.0 if enabled else 0.0
	_bind()


func _bind() -> void:
	if scene == null:
		return
	sim = scene.sim
	if sim != null:
		_C = sim.grid.CELL
	cam = scene.cam
	ant_view = scene.ant_view
	day = scene.day
	perf = scene.perf
	if scene.world_view != null:
		ground = scene.world_view.ground


func set_enabled(on: bool) -> void:
	enabled = on
	Engine.set_meta("infdna_meadow", on)
	if sim != null:
		sim.toasts.append({"text": "Thick grass on: zoom in to see into it, click a symbol to go there (6)" if on else "Thick grass off (6)", "t": 3.0})


# ---------------------------------------------------------------- queries
# True when a unit at `lane` (0 back .. 1 front) and world x stands wholly behind a closed row of grass, so drawing it is wasted.
# `h` is how tall it stands in px (default: an ant at that depth).
func hidden(lane: float, x: float, h: float = -1.0) -> bool:
	if lane < 0.0 or lane >= _cover_max:
		return false
	return _hidden_at(lane, x, h if h >= 0.0 else ANT_H * GroundView.persp(lane))


# How much of a unit at this lane can be seen at the current zoom (ignoring clearings): 2 in front of every standing row (or with the
# grass off), 1 behind a row that is parting, 0 behind a closed row.
func detail(lane: float) -> int:
	var d = 2
	for c in INNER:
		if _lanes[c] > lane:
			if _dense[c]:
				return 0
			if _alpha[c] > 0.05:
				d = 1
	return d


# Called by ant_view for every item of its depth-sorted draw loop ([depth key, kind (0 ant, 1 raider, 2 scenery slice), unit]):
# draws the rows the loop has just passed into its canvas, then returns true when the unit is hidden in the grass (skip it).
func pass_item(ci: CanvasItem, it: Array) -> bool:
	var f = Engine.get_idle_frames()
	if f != _pf:
		_pf = f
		_nxt = 0
		stat_skipped = 0
	var key: float = it[0]
	while _nxt < NC and _lanes[_nxt] <= key:
		_draw_row(ci, _nxt)
		_nxt += 1
	if key < 0.0 or key >= _cover_max:
		return false
	var kind = it[1]
	if kind == 2:
		return false
	var u = it[2]
	var hid := false
	if kind == 0:
		if _keep.has(u.id) or u.ph.get("wings", 0) > 0:      # the selection always shows; a winged ant may be in the air
			return false
		hid = _hidden_at(key, (u.x + 0.5) * _C, ANT_H * GroundView.persp(key))
	else:
		if u.def.get("fly", false) or u.cls == "boss":
			return false          # a flyer may be in the air; a boss always shows, whatever stands in front of it
		hid = _hidden_at(key, (u.x + 0.5) * _C, EnemyDefs.height_of(u) * GroundView.persp(key))
	if hid:
		stat_skipped += 1
	return hid


func _hidden_at(l: float, px: float, h: float) -> bool:
	var C = sim.grid.CELL
	var col = int(floor(px / C))
	var ci = int(floor(float(col) / CH))
	var e = _chunks.get(ci)
	if e == null:
		return false
	var i = col - ci * CH
	var pidx = ci * PIECES + i / PW
	for c in INNER:
		var lc = _lanes[c]
		if lc <= l or not _dense[c]:
			continue
		var born = e["born"][c]
		if born < 0.0 or _t - born < FADE_IN:
			continue
		if not _lp.empty() and _lp.get(pidx * NC + c, 0.0) > 0.01:
			continue
		if e["hk"][c][i] < 0.97:
			continue
		if (lc - l) * DL + h <= _hs[c]:
			return true
	return false


# Something at this lane and x is behind a closed row (for the symbols: its feet are in the grass, whatever pokes out above).
func _covered(l: float, px: float) -> bool:
	if l < 0.0 or l >= _cover_max:
		return false
	var C = sim.grid.CELL
	var col = int(floor(px / C))
	var ci = int(floor(float(col) / CH))
	var e = _chunks.get(ci)
	if e == null:
		return false
	var i = col - ci * CH
	for c in INNER:
		if _lanes[c] > l and _dense[c] and e["born"][c] >= 0.0 and e["hk"][c][i] >= 0.97:
			return true
	return false


# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if cam == null or ground == null or sim == null:
		_bind()
		if cam == null or ground == null or sim == null:
			return
	_t += delta
	var goal_on = 1.0 if enabled else 0.0
	_on_k = move_toward(_on_k, goal_on, delta * 2.5)
	var z = cam.zoom.x
	var k = 1.0 - exp(-delta * 7.0)
	var st = day.sea_t if day != null else sim.time
	_snow = day.snow if day != null else Seasons.snow(st)
	_flat = 1.0 - 0.2 * _snow
	_wind = 1.0 + 1.6 * sim.rain
	_cover_max = -1.0
	for c in NC:
		var goal = 1.0 - smoothstep(Z_LO[c], Z_HI[c], z)
		_part[c] = lerp(_part[c], goal, k)
		if abs(_part[c] - goal) < 0.002:
			_part[c] = goal
		_alpha[c] = _on_k * pow(1.0 - _part[c], 1.5)
		_dense[c] = c < INNER and _part[c] < 0.01 and _on_k >= 1.0
		_hs[c] = SOLID[c] * HEIGHT[c] * _ps[c] * 0.9 * _flat
		if _dense[c]:
			_cover_max = max(_cover_max, _lanes[c])
	# the palettes follow the year (one row repainted per frame when due; all four at once the first time)
	if _pal_t < -9000.0:
		for c in NC:
			_paint(c, st)
		_pal_t = st
	elif abs(st - _pal_t) > 2.0 or _pal_i > 0:
		_paint(_pal_i, st)
		_pal_i = (_pal_i + 1) % NC
		if _pal_i == 0:
			_pal_t = st
	_update_view(delta)
	_update_local(delta)
	_sym_t -= delta
	if _sym_t <= 0.0:
		_sym_t = 0.2
		_refresh_symbols()
	_step_symbols(delta)
	_step_fly(delta)
	if ant_view != null:
		ant_view.update()        # its _draw (which draws most rows) must run before this node's in every frame
	update()
	_symn.update()


# Chunks in view: build what is missing (center out, within a time budget), and keep the list of what to draw, left to right.
func _update_view(delta: float) -> void:
	var vp = get_viewport_rect().size
	var z = cam.zoom.x
	var cc = cam.get_camera_screen_center()
	_cx = cc.x
	_half = vp.x * z * 0.5
	var vy0 = cc.y - vp.y * z * 0.5
	var vy1 = cc.y + vp.y * z * 0.5
	var CHW = float(CH) * sim.grid.CELL
	var lo_v = int(floor((_cx - _half - 160.0) / CHW))
	var hi_v = int(floor((_cx + _half + 160.0) / CHW))
	var lo = lo_v - 1          # one chunk past each side is built too (after what is in view), so a pan finds the grass already standing
	var hi = hi_v + 1
	var mid = int(floor(_cx / CHW))
	_sig_t -= delta
	var resig = _sig_t <= 0.0
	if resig:
		_sig_t = 0.5
		_refresh_sources()
	var t0 = OS.get_ticks_usec()
	var built := 0
	var vis := []
	var missing := 0
	for ci in range(lo_v, hi_v + 1):
		var e = _chunks.get(ci)
		if e == null or e["born"][1] < 0.0:
			missing += 1
	# an empty screen fills at once; grass missing anywhere in view gets a good share of the frame (a gap must not linger); the margin
	# past the view streams in at leisure
	var budget = 12000 if missing * 2 > hi_v - lo_v + 1 else (7000 if missing > 0 else 2500)
	for d in range(0, max(mid - lo, hi - mid) + 1):
		for ci in ([mid - d] if d == 0 else [mid - d, mid + d]):
			if ci < lo or ci > hi:
				continue
			var e = _chunks.get(ci)
			var gch = ground._chunks.get(ci)
			if enabled and gch != null:
				if e == null:
					e = _new_entry(ci, gch)
					_chunks[ci] = e
				else:
					if gch["t"] != e["src_t"]:
						e["src_t"] = gch["t"]
						var hsh = _thash(gch)
						if abs(hsh - e["hash"]) > 0.001:          # the ground itself changed (the mound grew), not just the season
							e["hash"] = hsh
							_set_range(e, gch)
							for c in NC:
								e["need"][c] = true
					if resig:
						var s = _sig(ci)
						if s != e["sig"]:
							e["sig"] = s
							for c in NC:
								e["need"][c] = true
						var cs = _csig(ci)
						if cs != e["csig"]:
							e["csig"] = cs
							e["need"][0] = true
				for c in NC:
					if e["need"][c] and (built == 0 or OS.get_ticks_usec() - t0 < budget):
						_build_row(e, ci, c, gch)
						built += 1
			if e != null and ci >= lo_v and ci <= hi_v and e["y1"] > vy0 and e["y0"] < vy1:
				vis.append([ci, e])
	# snow on the grass, built once snow lies (cheap, a few pieces a frame)
	if _snow > 0.01:
		var sb = 6
		for v in vis:
			var e2 = v[1]
			for c in NC:
				if sb > 0 and not e2["snowed"][c] and e2["born"][c] >= 0.0:
					sb -= 1
					var sm = []
					for p in PIECES:
						sm.append(_build_snow(e2["tops"][c][p], e2["tips"][c][p], _ps[c]))
					e2["sn"][c] = sm
					e2["snowed"][c] = true
	vis.sort_custom(self, "_by_ci")     # a steady order: the blades where two pieces meet never swap places
	_vis = vis
	stat_build_us = OS.get_ticks_usec() - t0
	if _chunks.size() > 72:
		for ci2 in _chunks.keys():
			if ci2 < lo - 24 or ci2 > hi + 24:
				_chunks.erase(ci2)


func _by_ci(a, b) -> bool:
	return a[0] < b[0]


# The rows in front of a selected ant part around it (a window of a piece or two), so the selection can always be seen.
func _update_local(delta: float) -> void:
	_keep = {}
	var want := {}
	if scene != null and ant_view != null:
		var list := []
		if scene.selected != null:
			list.append(scene.selected)
		for a in scene.selection:
			if list.size() >= 10:
				break
			if a != scene.selected:
				list.append(a)
		for id in ant_view.sel_ids:
			_keep[id] = true
		# watch mode: the ant the camera follows shows too, whatever stands in front of it
		var w = scene.watch
		if scene.watch_mode and w != null and w._unit != null and sim.ants.has(w._unit) and not (w._unit in list):
			list.append(w._unit)
		var C = sim.grid.CELL
		var pw = PW * C
		for a in list:
			_keep[a.id] = true
			if sim.grid.is_under(a.x, a.y):
				continue
			var px = (a.x + 0.5) * C
			var ln = ant_view.lane_of(a, a.id)
			for pidx in range(int(floor((px - 70.0) / pw)), int(floor((px + 70.0) / pw)) + 1):
				for c in NC:
					if _lanes[c] > ln + 0.004:
						want[pidx * NC + c] = 1.0
		# a boss (and, in watch mode, the raider of the fight being shown): the rows in front of it part over its whole width
		var shown = w.focus_enemy if (scene.watch_mode and w != null) else null
		for e in sim.enemies:
			if (e.cls != "boss" and e != shown) or e.hp <= 0.0 or sim.grid.is_under(e.x, e.y):
				continue
			var bx = (e.x + 0.5) * C
			var half = max(120.0, EnemyDefs.height_of(e) * 1.1)
			var bl = float(e.lane)
			for pidx in range(int(floor((bx - half) / pw)), int(floor((bx + half) / pw)) + 1):
				for c in NC:
					if _lanes[c] > bl + 0.004:
						want[pidx * NC + c] = 1.0
	if want.empty() and _lp.empty():
		return
	for key in want:
		if not _lp.has(key):
			_lp[key] = 0.0
	var kk = 1.0 - exp(-delta * 6.0)
	for key in _lp.keys():
		var v = lerp(_lp[key], want.get(key, 0.0), kk)
		if v < 0.004 and not want.has(key):
			_lp.erase(key)
		else:
			_lp[key] = v


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	# the rows in front of every unit ant_view drew this frame (all of them when it drew none)
	var start = _nxt if _pf == Engine.get_idle_frames() else 0
	for c in range(start, NC):
		_draw_row(self, c)


func _draw_row(ci: CanvasItem, c: int) -> void:
	var a0 = _alpha[c]
	if a0 <= 0.004 or _vis.empty():
		return
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tex = _pal[c]
	var snow = _snow > 0.01
	var any_lp = not _lp.empty()
	for v in _vis:
		var e = v[1]
		var born = e["born"][c]
		if born < 0.0:
			continue
		var fa = a0 * min(1.0, (_t - born) / FADE_IN)
		var ms = e["m"][c]
		var oys = e["oy"][c]
		for p in PIECES:
			var m = ms[p]
			if m == null:
				continue
			var lp = 0.0
			if any_lp:
				lp = _lp.get((v[0] * PIECES + p) * NC + c, 0.0)
			var a = fa * (1.0 - 0.85 * lp)
			if a <= 0.004:
				continue
			var xf = _xf(c, oys[p], e["xm"][p], lp)
			ci.draw_mesh(m, tex, null, xf, Color(1, 1, 1, a))
			if snow and e["snowed"][c]:
				var sm = e["sn"][c][p]
				if sm != null:
					ci.draw_mesh(sm, tex, null, xf, Color(1, 1, 1, a * _snow))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# The one transform of a piece: wind (a shear about its root line, a slow wave that rolls across the meadow, stronger in rain), and
# while the row parts a lean away from the screen centre, a bow, a slide toward the viewer and a scale about the camera (parallax).
func _xf(c: int, oy: float, xm: float, lp: float) -> Transform2D:
	var ph = xm * 0.0042 + c * 1.3
	var gust = 0.7 + 0.45 * sin(_t * 0.31 - xm * 0.0017 + c)
	var sw = (0.02 + 0.009 * c) * _wind * gust * (0.25 + sin(_t * 1.25 - ph) + 0.35 * sin(_t * 2.7 - ph * 1.9 + 1.1))
	var pt = _part[c]
	if pt <= 0.0005 and lp <= 0.0005 and _flat >= 0.999:
		return Transform2D(Vector2(1, 0), Vector2(sw, 1), Vector2(-sw * oy, 0))
	var s = 1.0 + 0.22 * pt
	var rel = clamp((xm - _cx) / max(1.0, _half), -1.3, 1.3)
	var sh = sw - 0.9 * rel * pt
	var syk = _flat * (1.0 - 0.45 * pt) * (1.0 - 0.3 * lp)
	var drop = pt * 14.0 * _ps[c]
	return Transform2D(Vector2(s, 0), Vector2(s * sh, syk), Vector2(_cx * (1.0 - s) - s * sh * oy, oy * (1.0 - syk) + drop))


# ---------------------------------------------------------------- palettes
# The colours of one row for this point of the year: the meadow greens of ground_view (fresh in spring, straw in autumn and winter,
# the tips bleaching first), darker and hazier toward the back, AO at the roots and sunlit tips.
func _paint(c: int, st: float) -> void:
	var img: Image = _pal_img[c]
	var gb = Seasons.blend_color(st, [Color("#72b04f"), GroundView.GRASS_BACK, Color("#93994a"), Color("#8a9877")])
	var gf = Seasons.blend_color(st, [Color("#aade5e"), GroundView.GRASS_FRONT, Color("#bdb65a"), Color("#a8b79b")])
	var dry = Seasons.blend(st, [0.0, 0.12, 0.7, 0.85])
	var lane = _lanes[c]
	var shade = (0.72 + 0.28 * lane) if lane <= 1.0 else 0.84
	var haze = (1.0 - clamp(lane, 0.0, 1.0)) * 0.24
	var deep = gb.darkened(0.64).linear_interpolate(Color(0.04, 0.1, 0.08), 0.3)
	var mid = gb.linear_interpolate(gf, 0.45)
	var hi = gf.lightened(0.24).linear_interpolate(Color(0.98, 1.0, 0.66), 0.22)
	var straw = GroundView.STRAW
	img.lock()
	for r in 12:
		var t = r / 11.0
		var rc = deep.linear_interpolate(mid.darkened(0.32), t * 0.85)
		var tc = mid.darkened(0.16).linear_interpolate(hi, t)
		var sc = straw.darkened(0.42 * (1.0 - t))
		for q in 8:
			var h = q / 7.0
			var col = rc.linear_interpolate(tc, pow(h, 0.85))
			col = col.linear_interpolate(sc.darkened(0.25 * (1.0 - h)), dry * (0.3 + 0.55 * h))
			col = col.linear_interpolate(GroundView.HAZE, haze * (0.5 + 0.5 * h))
			img.set_pixel(q, r, Color(col.r * shade, col.g * shade, col.b * shade, 1.0))
	var seed_c = Seasons.blend_color(st, [Color("#bcd48c"), Color("#e4d690"), Color("#cfa055"), Color("#a39276")])
	var seed_a = Seasons.blend(st, [0.3, 1.0, 1.0, 0.7])
	var bloom = Seasons.bloom(st)
	var pc: Color = PETALS[c]
	var ss = 0.88 + 0.12 * shade
	for q in 8:
		var h = q / 7.0
		var sn = Color(0.64, 0.74, 0.88).linear_interpolate(Color(0.98, 0.99, 1.0), pow(h, 0.7))
		img.set_pixel(q, 12, Color(sn.r * ss, sn.g * ss, sn.b * ss, 1.0))
		var sd = seed_c.darkened(0.3 * (1.0 - h)).linear_interpolate(GroundView.HAZE, haze * 0.6)
		img.set_pixel(q, 13, Color(sd.r * shade, sd.g * shade, sd.b * shade, seed_a))
		var pp = pc.darkened(0.18 * (1.0 - h))
		img.set_pixel(q, 14, Color(pp.r * shade, pp.g * shade, pp.b * shade, bloom))
		img.set_pixel(q, 15, Color(0.95 * shade, 0.71 * shade, 0.2 * shade, bloom))
	img.unlock()
	_pal[c].set_data(img)


# ---------------------------------------------------------------- building
func _new_entry(ci: int, gch: Dictionary) -> Dictionary:
	var C = sim.grid.CELL
	var x0 = float(ci * CH) * C
	var e = {"src_t": gch["t"], "hash": _thash(gch), "sig": _sig(ci), "csig": _csig(ci),
		"need": [true, true, true, true], "born": [-1.0, -1.0, -1.0, -1.0],
		"m": [null, null, null, null], "oy": [null, null, null, null], "hk": [null, null, null, null],
		"tips": [null, null, null, null], "tops": [null, null, null, null],
		"sn": [null, null, null, null], "snowed": [false, false, false, false],
		"xm": [x0 + PW * C * 0.5, x0 + PW * C * 1.5], "y0": 0.0, "y1": 0.0}
	_set_range(e, gch)
	return e


func _set_range(e: Dictionary, gch: Dictionary) -> void:
	var lo = 1e9
	var hi = -1e9
	for v in gch["sy"]:
		lo = min(lo, v)
		hi = max(hi, v)
	e["y0"] = lo - DL - 200.0
	e["y1"] = hi + 60.0


static func _thash(gch: Dictionary) -> float:
	var h := 0.0
	var sy: PoolRealArray = gch["sy"]
	var mf: PoolRealArray = gch["mf"]
	for i in sy.size():
		h += sy[i] * (1.0 + i * 0.013) + mf[i] * (31.0 + i)
	return h


func _refresh_sources() -> void:
	_ent = []
	for en in sim.grid.entrances:
		_ent.append(int(en.x))
	_rival_x = int(sim.rival.x) if sim.rival != null else -999999
	_carc = []
	for p in sim.piles:
		if p.get("kind", "") == "carcass":
			_carc.append(int(p["x"]))


func _sig(ci: int) -> String:
	var c0 = ci * CH
	var s = ""
	for ex in _ent:
		if ex > c0 - 18 and ex < c0 + CH + 18:
			s += str(ex) + ","
	if _rival_x > c0 - 30 and _rival_x < c0 + CH + 30:
		s += "r" + str(_rival_x)
	return s


func _csig(ci: int) -> String:
	var c0 = ci * CH
	var s = ""
	for px in _carc:
		if px > c0 - 24 and px < c0 + CH + 24:
			s += str(px) + ","
	return s


# How tall the grass grows at a column, 0..1: everywhere at full height. There are no clearings (the owner: no gaps anywhere): the grass
# stands over the spoil heaps, round the nest holes and the rival mound, and over a fallen bird; zooming in is how one looks past it.
func _clear_k(_c: int, _col: int, _mfv: float) -> float:
	return 1.0


static func _undul(x: float, c: int) -> float:
	return 0.82 + 0.18 * (0.5 + 0.5 * sin(x * 0.011 + c * 2.1) * sin(x * 0.0047 + c * 0.7))


func _build_row(e: Dictionary, ci: int, c: int, gch: Dictionary) -> void:
	var C = sim.grid.CELL
	var c0 = ci * CH
	var sy: PoolRealArray = gch["sy"]
	var mf: PoolRealArray = gch["mf"]
	var lane = _lanes[c]
	var ps = _ps[c]
	var H = HEIGHT[c] * ps
	var ih = 1.0 / H
	var off = (1.0 - lane) * DL
	var hk := PoolRealArray()
	hk.resize(CH + 1)
	for i in CH + 1:
		hk[i] = _clear_k(c, c0 + i, mf[i])
	var meshes := []
	var oys := []
	var tips_l := []
	var tops_l := []
	for p in PIECES:
		_bv = PoolVector2Array()
		_bu = PoolVector2Array()
		_btips = PoolVector2Array()
		var tops := PoolVector3Array()
		var i0 = p * PW
		var px0 = float(c0 + i0) * C
		var px1 = px0 + PW * C
		var oy := 0.0
		for i in range(i0, i0 + PW + 1):
			oy += sy[i]
		oys.append(oy / (PW + 1) - off)
		if SOLID[c] > 0.0:
			# the closed wall at the foot of the row: darkest at the roots
			var u0 = 0.5 / 8.0
			var vb = 0.5 / 16.0
			var vt = (0.5 + 11.0 * 0.1) / 16.0
			var prev = Vector3()
			for i in range(i0, i0 + PW + 1):
				var x = float(c0 + i) * C
				var hh = H * SOLID[c] * hk[i] * _undul(x, c) * (0.93 + 0.07 * sin(x * 0.41 + c * 1.7))
				var cur = Vector3(x, sy[i] - off, hh)
				tops.append(Vector3(x, cur.y - hh, hh))
				if i > i0 and (prev.z > 0.5 or cur.z > 0.5):
					_q(Vector2(prev.x, prev.y + 2.0), Vector2(u0, vb), Vector2(cur.x, cur.y + 2.0), Vector2(u0, vb),
						Vector2(cur.x, cur.y - cur.z), Vector2((0.5 + 7.0 * min(1.0, cur.z * ih)) / 8.0, vt),
						Vector2(prev.x, prev.y - prev.z), Vector2((0.5 + 7.0 * min(1.0, prev.z * ih)) / 8.0, vt))
				prev = cur
		for L in 3:
			if c == NC - 1 and L == 0:
				continue           # the fringe is loose clumps: no thatch
			_layer(c, L, px0, px1, c0, sy, off, hk, H, ih, ps)
		meshes.append(_finish())
		tips_l.append(_btips)
		tops_l.append(tops)
	e["m"][c] = meshes
	e["oy"][c] = oys
	e["hk"][c] = hk
	e["tips"][c] = tips_l
	e["tops"][c] = tops_l
	e["sn"][c] = null
	e["snowed"][c] = false
	if e["born"][c] < 0.0:
		e["born"][c] = _t
	e["need"][c] = false


func _layer(c: int, L: int, px0: float, px1: float, c0: int, sy: PoolRealArray, off: float, hk: PoolRealArray, H: float, ih: float, ps: float) -> void:
	var C = sim.grid.CELL
	var fringe = c == NC - 1
	var step = L_SP[L] * ps * (1.5 if fringe else 1.0)
	var j0 = int(ceil(px0 / step))
	var j1 = int(ceil(px1 / step))
	for j in range(j0, j1):
		var sd = float(j) * 0.7071 + c * 31.7 + L * 7.3
		# one hash, read digit by digit, gives the handful of random numbers a blade needs
		var r1 = abs(sin(sd * 12.9898) * 43758.5453)
		var r2 = abs(sin(sd * 78.233) * 43758.5453)
		var h1 = fmod(r1, 1.0)
		var h2 = fmod(r1 * 10.0, 1.0)
		var h3 = fmod(r1 * 100.0, 1.0)
		var h4 = fmod(r2, 1.0)
		var h5 = fmod(r2 * 10.0, 1.0)
		var h6 = fmod(r2 * 100.0, 1.0)
		var h7 = fmod(r1 * 1000.0, 1.0)
		var h8 = fmod(r2 * 1000.0, 1.0)
		var x = (float(j) + 0.85 * h1 - 0.42) * step
		var col = int(clamp(floor(x / C) - c0, 0, CH))
		var kk = hk[col]
		if fringe:
			kk *= smoothstep(0.42, 0.66, 0.5 + 0.5 * sin(x * 0.019 + 1.1) * sin(x * 0.0071 + 0.3) + 0.12 * sin(x * 0.061))
		if kk < 0.12 + 0.3 * h4:
			continue
		var ry = GroundView._sy_at(sy, c0, x, C) - off
		var h = H * lerp(L_H0[L], L_H1[L], h2) * min(1.0, kk * 1.15) * _undul(x, c)
		var w = lerp(L_W0[L], L_W1[L], h3) * ps
		var droop = L_DROOP[L] * pow(h6, 1.5)
		var lean = (h5 - 0.45) * 2.0 * L_LEAN[L] * h
		if droop > 0.14:
			lean = sign(lean) * max(abs(lean), (0.32 + 0.5 * droop) * h)       # a blade that arches over bends to one side
		var tl = lerp(L_T0[L], L_T1[L], h7)
		var b = Vector2(x, ry + L_DY[L] * ps)
		if L_INK[L]:
			_ink_blade(b, h * 1.03 + 1.2 * ps, w + 2.4 * ps, lean * 1.03, droop)
		var tp = _blade(b, h, w, lean, droop, tl, tl + L_TR[L], L_FOLD[L], ry, ih)
		if L < 2 and droop < 0.06 and abs(lean) < 0.22 * h and h8 > 0.4:
			_btips.append(tp)
		if L == 1 and c > 0 and h > 0.84 * H and h8 > 0.7:
			_seed_head(b, h, lean, droop, ps, ry, ih)
		elif L == 2 and (c == 1 or c == 2) and h8 > 0.955:
			_flower(b, h, lean, ps, ry, ih, sd)


func _q(a: Vector2, ua: Vector2, b: Vector2, ub: Vector2, c: Vector2, uc: Vector2, d: Vector2, ud: Vector2) -> void:
	_bv.append(a)
	_bv.append(b)
	_bv.append(c)
	_bv.append(a)
	_bv.append(c)
	_bv.append(d)
	_bu.append(ua)
	_bu.append(ub)
	_bu.append(uc)
	_bu.append(ua)
	_bu.append(uc)
	_bu.append(ud)


func _t3(a: Vector2, ua: Vector2, b: Vector2, ub: Vector2, c: Vector2, uc: Vector2) -> void:
	_bv.append(a)
	_bv.append(b)
	_bv.append(c)
	_bu.append(ua)
	_bu.append(ub)
	_bu.append(uc)


# One blade: base b, height h, base width w, the tip `lean` px to the side, `droop` (share of h) let down again at the tip; tones of
# its shaded left and sunlit right side. A folded blade shows its crease (each half has its own tone). Returns the tip.
func _blade(b: Vector2, h: float, w: float, lean: float, droop: float, tl: float, tr: float, fold: bool, ry: float, ih: float) -> Vector2:
	var p1 = b + Vector2(lean * 0.1764, h * (droop * 0.0741 - 0.42))
	var p2 = b + Vector2(lean * 0.5625, h * (droop * 0.4219 - 0.75))
	var tp = b + Vector2(lean, h * (droop - 1.0))
	var n0 = Vector2(b.y - p1.y, p1.x - b.x).normalized()
	var n1 = Vector2(b.y - p2.y, p2.x - b.x).normalized()
	var n2 = Vector2(p1.y - tp.y, tp.x - p1.x).normalized()
	var l0 = b - n0 * (w * 0.5)
	var r0 = b + n0 * (w * 0.5)
	var l1 = p1 - n1 * (w * 0.37)
	var r1 = p1 + n1 * (w * 0.37)
	var l2 = p2 - n2 * (w * 0.2)
	var r2 = p2 + n2 * (w * 0.2)
	# u: height above the row's root line (the same for every blade of the row, so the short ones stay down in the shade)
	var u0 = (0.5 + 7.0 * clamp((ry - b.y) * ih, 0.0, 1.0)) * 0.125
	var u1 = (0.5 + 7.0 * clamp((ry - p1.y) * ih, 0.0, 1.0)) * 0.125
	var u2 = (0.5 + 7.0 * clamp((ry - p2.y) * ih, 0.0, 1.0)) * 0.125
	var ut = (0.5 + 7.0 * clamp((ry - tp.y) * ih, 0.0, 1.0)) * 0.125
	var vl = (0.5 + 11.0 * clamp(tl, 0.0, 1.0)) * 0.0625
	var vr = (0.5 + 11.0 * clamp(tr, 0.0, 1.0)) * 0.0625
	if fold:
		var vm = (0.5 + 11.0 * clamp((tl + tr) * 0.5 + 0.08, 0.0, 1.0)) * 0.0625
		_q(l0, Vector2(u0, vl), b, Vector2(u0, vm), p1, Vector2(u1, vm), l1, Vector2(u1, vl))
		_q(l1, Vector2(u1, vl), p1, Vector2(u1, vm), p2, Vector2(u2, vm), l2, Vector2(u2, vl))
		_q(b, Vector2(u0, vm), r0, Vector2(u0, vr), r1, Vector2(u1, vr), p1, Vector2(u1, vm))
		_q(p1, Vector2(u1, vm), r1, Vector2(u1, vr), r2, Vector2(u2, vr), p2, Vector2(u2, vm))
		_t3(l2, Vector2(u2, vl), p2, Vector2(u2, vm), tp, Vector2(ut, vm))
		_t3(p2, Vector2(u2, vm), r2, Vector2(u2, vr), tp, Vector2(ut, vm))
	else:
		_q(l0, Vector2(u0, vl), r0, Vector2(u0, vr), r1, Vector2(u1, vr), l1, Vector2(u1, vl))
		_q(l1, Vector2(u1, vl), r1, Vector2(u1, vr), r2, Vector2(u2, vr), l2, Vector2(u2, vl))
		_t3(l2, Vector2(u2, vl), r2, Vector2(u2, vr), tp, Vector2(ut, (vl + vr) * 0.5))
	return tp


# The dark rim behind a front blade (the game's inked look), in the darkest shade of the palette.
func _ink_blade(b: Vector2, h: float, w: float, lean: float, droop: float) -> void:
	var p1 = b + Vector2(lean * 0.1764, h * (droop * 0.0741 - 0.42))
	var p2 = b + Vector2(lean * 0.5625, h * (droop * 0.4219 - 0.75))
	var tp = b + Vector2(lean, h * (droop - 1.0))
	var n0 = Vector2(b.y - p1.y, p1.x - b.x).normalized()
	var n1 = Vector2(b.y - p2.y, p2.x - b.x).normalized()
	var n2 = Vector2(p1.y - tp.y, tp.x - p1.x).normalized()
	var uk = Vector2(0.5 / 8.0, 0.5 / 16.0)
	_q(b - n0 * (w * 0.5), uk, b + n0 * (w * 0.5), uk, p1 + n1 * (w * 0.37), uk, p1 - n1 * (w * 0.37), uk)
	_q(p1 - n1 * (w * 0.37), uk, p1 + n1 * (w * 0.37), uk, p2 + n2 * (w * 0.22), uk, p2 - n2 * (w * 0.22), uk)
	_t3(p2 - n2 * (w * 0.22), uk, p2 + n2 * (w * 0.22), uk, tp, uk)


# An oat-like seed head over a tall blade: a thin stalk and a few hanging grains (they ripen to gold and thin out with the year).
func _seed_head(b: Vector2, h: float, lean: float, droop: float, ps: float, ry: float, ih: float) -> void:
	var top = b + Vector2(lean * 0.8, -h * 1.12)
	var uu = (0.5 + 7.0 * clamp((ry - top.y) * ih, 0.0, 1.0)) * 0.125
	var ub = (0.5 + 7.0 * clamp((ry - (b.y - h * 0.6)) * ih, 0.0, 1.0)) * 0.125
	var mid = b + Vector2(lean * 0.35, -h * 0.6)
	_t3(mid - Vector2(0.8 * ps, 0), Vector2(ub, V_SEED), mid + Vector2(0.8 * ps, 0), Vector2(ub, V_SEED), top, Vector2(uu, V_SEED))
	var d = (top - mid).normalized()
	var n = Vector2(-d.y, d.x)
	for g in 5:
		var s = 0.45 + 0.13 * g
		var side = 1.0 if g % 2 == 0 else -1.0
		var cpos = mid.linear_interpolate(top, s) + n * side * 2.0 * ps
		var ax = (d * 0.6 + n * side * 0.8).normalized() * 3.0 * ps
		var bx = Vector2(-ax.y, ax.x) * 0.45
		var ug = (0.5 + 7.0 * clamp((ry - cpos.y) * ih, 0.0, 1.0)) * 0.125
		var uv = Vector2(ug, V_SEED)
		_q(cpos - ax, uv, cpos + bx, uv, cpos + ax, uv, cpos - bx, uv)


# A small meadow flower on a thin stalk among the front blades (only while the meadow blooms: its petals fade with the year).
func _flower(b: Vector2, h: float, lean: float, ps: float, ry: float, ih: float, sd: float) -> void:
	var head = _blade(b, h * 1.08, 1.8 * ps, lean * 0.25, 0.0, 0.3, 0.46, false, ry, ih)
	for k in 5:
		var ang = TAU * k / 5.0 + sd
		var dir = Vector2(cos(ang), sin(ang) * 0.75)
		var cpos = head + dir * 2.8 * ps
		var ax = dir * 2.6 * ps
		var bx = Vector2(-dir.y, dir.x) * 1.6 * ps
		var uv = Vector2(0.3 + 0.6 * (0.5 - 0.5 * dir.y), V_PETAL)
		_q(cpos - ax, uv, cpos + bx, uv, cpos + ax, uv, cpos - bx, uv)
	var hu = Vector2(0.6, V_HEART)
	_q(head + Vector2(-1.6 * ps, 0), hu, head + Vector2(0, -1.4 * ps), hu, head + Vector2(1.6 * ps, 0), hu, head + Vector2(0, 1.4 * ps), hu)


# Snow lying on a piece of a row: a soft ridge along the top of its closed wall and little caps on the upright tips.
func _build_snow(tops: PoolVector3Array, tips: PoolVector2Array, ps: float):
	_bv = PoolVector2Array()
	_bu = PoolVector2Array()
	var us0 = Vector2(0.5 / 8.0, V_SNOW)
	var us1 = Vector2(7.5 / 8.0, V_SNOW)
	var usm = Vector2(4.0 / 8.0, V_SNOW)
	for i in tops.size() - 1:
		var a = tops[i]
		var b = tops[i + 1]
		if a.z < 4.0 or b.z < 4.0:
			continue
		var ta = (2.4 + 2.6 * fmod(abs(sin(a.x * 0.31) * 43758.5453), 1.0)) * ps
		var tb = (2.4 + 2.6 * fmod(abs(sin(b.x * 0.31) * 43758.5453), 1.0)) * ps
		_q(Vector2(a.x, a.y + 1.6 * ps), us0, Vector2(b.x, b.y + 1.6 * ps), us0, Vector2(b.x, b.y - tb), us1, Vector2(a.x, a.y - ta), us1)
	for t in tips:
		var cpos = t + Vector2(0, -0.8 * ps)
		var rx = 3.2 * ps
		var ry = 2.1 * ps
		var prev = cpos + Vector2(rx, 0)
		for k in range(1, 9):
			var ang = TAU * k / 8.0
			var q = cpos + Vector2(cos(ang) * rx, sin(ang) * ry)
			_t3(cpos, us1, prev, us1 if prev.y < cpos.y else usm, q, us1 if q.y < cpos.y else usm)
			prev = q
	return _finish()


func _finish():
	if _bv.size() == 0:
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _bv
	arrays[Mesh.ARRAY_TEX_UV] = _bu
	var m = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], 0)      # uncompressed: GLES2 reads plain floats
	_bv = PoolVector2Array()
	_bu = PoolVector2Array()
	return m


# ---------------------------------------------------------------- symbols
# Every 0.2 s: what is happening behind the closed rows, in view. Merged by kind when close on screen, capped, matched to the live
# symbols so each one glides and fades instead of popping.
func _refresh_symbols() -> void:
	var cand := []
	if _cover_max > 0.0 and _on_k > 0.5:
		var g = sim.grid
		var C = g.CELL
		var lo = _cx - _half - 40.0
		var hi = _cx + _half + 40.0
		for e in sim.enemies:
			if e.cls == "prey" or not e.engaged or g.is_under(e.x, e.y):
				continue
			var px = (e.x + 0.5) * C
			if px > lo and px < hi:
				var ln = ant_view.lane_of(e, -e.id) if ant_view != null else e.lane
				if _covered(ln, px):
					cand.append(["fight", px, ln, ACCENT["fight"]])
		if sim.bird != null and (float(sim.bird["dive"]) > 0.05 or float(sim.bird["alt"]) < 0.3):
			var bx = (float(sim.bird["x"]) + 0.5) * C
			if bx > lo and bx < hi and _covered(0.5, bx):
				cand.append(["bird", bx, 0.5, ACCENT["bird"]])
		if cam.zoom.x >= 0.8:             # closer in, ant_view tags the Apex ants itself
			for ap in sim.apex:
				if ap == scene.selected or g.is_under(ap.x, ap.y):
					continue
				var ax = (ap.x + 0.5) * C
				var al = ant_view.lane_of(ap, ap.id)
				if ax > lo and ax < hi and _covered(al, ax):
					cand.append(["apex", ax, al, ACCENT["apex"]])
		var forage := {}
		var squads := {}
		var have_sq = not sim.squads.empty()
		for a in sim.ants:
			if a.task != 1 and a.squad == 0:
				continue
			if g.is_under(a.x, a.y):
				continue
			if a.task == 1:
				forage[int(a.x) / 4] = true
			if have_sq and a.squad != 0:
				var px2 = (a.x + 0.5) * C
				if px2 < lo or px2 > hi:
					continue
				var acc = squads.get(a.squad)
				if acc == null:
					acc = [0.0, 0, 0, 0.0]
					squads[a.squad] = acc
				var ln2 = ant_view.lane_of(a, a.id)
				acc[0] += px2
				acc[1] += 1
				acc[3] += ln2
				if _covered(ln2, px2):
					acc[2] += 1
		for id in squads:
			var acc2 = squads[id]
			if acc2[2] * 2 > acc2[1]:
				var sq = sim.squads.get(id)
				var col = Orders.COLORS.get(sq["kind"], Color(0.6, 0.8, 1.0)) if sq != null else Color(0.6, 0.8, 1.0)
				cand.append(["squad", acc2[0] / acc2[1], acc2[3] / acc2[1], col])
		for p in sim.piles:
			if float(p["amount"]) <= 4.0 or p.get("kind", "") == "carcass":
				continue
			var qx = (float(p["x"]) + 0.5) * C
			if qx < lo or qx > hi:
				continue
			var q4 = int(p["x"]) / 4
			if (forage.has(q4) or forage.has(q4 - 1) or forage.has(q4 + 1)) and _covered(0.5, qx):
				cand.append(["harvest", qx, 0.5, ACCENT["harvest"]])
	var z = cam.zoom.x
	var merged := []
	for cd in cand:
		var hit = false
		for m in merged:
			if m[0] == cd[0] and abs(m[1] - cd[1]) < 48.0 * z:
				m[1] = (m[1] * m[4] + cd[1]) / (m[4] + 1)
				m[2] = max(m[2], cd[2])
				m[4] += 1
				hit = true
				break
		if not hit:
			merged.append([cd[0], cd[1], cd[2], cd[3], 1])
	merged.sort_custom(self, "_by_prio")
	if merged.size() > MAX_SYM:
		merged.resize(MAX_SYM)
	for s in _sym:
		s["on"] = false
	for m in merged:
		var best = null
		var bd = 110.0 * z
		for s in _sym:
			if s["kind"] == m[0] and not s["on"] and abs(s["tx"] - m[1]) < bd:
				best = s
				bd = abs(s["tx"] - m[1])
		if best == null:
			best = {"kind": m[0], "x": m[1], "a": 0.0}
			_sym.append(best)
		best["tx"] = m[1]
		best["lane"] = m[2]
		best["col"] = m[3]
		best["on"] = true


func _by_prio(a, b) -> bool:
	return KINDS.find(a[0]) < KINDS.find(b[0])


func _step_symbols(delta: float) -> void:
	var kx = 1.0 - exp(-delta * 6.0)
	for i in range(_sym.size() - 1, -1, -1):
		var s = _sym[i]
		s["a"] = move_toward(s["a"], 1.0 if s["on"] else 0.0, delta * 4.0)
		s["x"] = lerp(s["x"], s["tx"], kx)
		if s["a"] <= 0.0 and not s["on"]:
			_sym.remove(i)
	_hover = null
	if not _sym.empty() and not _blocked():
		_hover = _symbol_at(get_viewport().get_mouse_position())


# Where a symbol floats: just above the tips of the row in front of what it marks (deeper things float higher), bobbing gently.
func _sym_pos(s: Dictionary) -> Vector2:
	var lane = s["lane"]
	var c = INNER - 1
	for cc in INNER:
		if _lanes[cc] > lane:
			c = cc
			break
	var sy = ground.smooth_px(int(floor(s["x"] / sim.grid.CELL)))
	var top = GroundView.lane_y(sy, _lanes[c]) - HEIGHT[c] * _ps[c] * 0.9 * _flat
	var z = cam.zoom.x
	return Vector2(s["x"], top - (SYM_R + 8.0) * z + sin(_t * 2.1 + s["x"] * 0.013) * 1.3 * z)


func _symbol_at(screen_pos: Vector2):
	var wp = get_canvas_transform().affine_inverse().xform(screen_pos)
	var z = cam.zoom.x
	for s in _sym:
		if s["on"] and s["a"] > 0.4 and (_sym_pos(s) - wp).length() < (SYM_R + 5.0) * z:
			return s
	return null


func _blocked() -> bool:
	return scene == null or scene.watch_mode or scene.shop_open or sim.collapsed or scene.armed != ""


func _draw_symbols() -> void:
	if _sym.empty() or cam == null:
		return
	var z = cam.zoom.x
	for s in _sym:
		var a = s["a"] * s["a"] * (3.0 - 2.0 * s["a"])
		if a <= 0.01:
			continue
		var hov = s == _hover
		var sc = z * (1.22 if hov else 1.0)
		_symn.draw_set_transform(_sym_pos(s), 0.0, Vector2(sc, sc))
		_badge(s, a * (1.0 if hov else 0.9))
		if hov:
			var txt = LABELS.get(s["kind"], "")
			var w = _font.get_string_size(txt).x
			_symn.draw_string(_font, Vector2(-w * 0.5, SYM_R + 17.0), txt, Color(1.0, 0.97, 0.88, a))
	_symn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A small round badge: ink rim, dark glass, a ring in the colour of what it marks, and a pale glyph.
func _badge(s: Dictionary, a: float) -> void:
	var R = SYM_R
	var acc: Color = s["col"]
	var n = _symn
	n.draw_circle(Vector2(0, 1.6), R + 2.6, Color(0, 0, 0, 0.22 * a))
	n.draw_circle(Vector2.ZERO, R + 1.8, Color(INK.r, INK.g, INK.b, 0.92 * a))
	n.draw_circle(Vector2.ZERO, R, Color(0.12, 0.14, 0.13, 0.84 * a))
	n.draw_arc(Vector2.ZERO, R - 0.7, 0.0, TAU, 24, Color(acc.r, acc.g, acc.b, 0.95 * a), 1.6, true)
	var ic = Color(0.98, 0.95, 0.86, a)
	match s["kind"]:
		"fight":         # crossed blades
			n.draw_line(Vector2(-4.4, 4.4), Vector2(4.0, -4.0), ic, 1.9, true)
			n.draw_line(Vector2(4.4, 4.4), Vector2(-4.0, -4.0), ic, 1.9, true)
			n.draw_line(Vector2(-4.9, 1.9), Vector2(-1.9, 4.9), Color(acc.r, acc.g, acc.b, a), 1.6, true)
			n.draw_line(Vector2(4.9, 1.9), Vector2(1.9, 4.9), Color(acc.r, acc.g, acc.b, a), 1.6, true)
		"harvest":       # the colony's green food gem
			var gem = PoolVector2Array([Vector2(0, -5.6), Vector2(4.6, -1.8), Vector2(3.2, 4.4), Vector2(-3.2, 4.4), Vector2(-4.6, -1.8)])
			n.draw_colored_polygon(gem, Color(0.42, 0.78, 0.27, a))
			n.draw_colored_polygon(PoolVector2Array([Vector2(0, -5.6), Vector2(4.6, -1.8), Vector2(0, 0.4), Vector2(-4.6, -1.8)]), Color(0.66, 0.93, 0.45, a))
		"bird":          # wings
			n.draw_polyline(PoolVector2Array([Vector2(-6.2, -0.2), Vector2(-3.2, -3.0), Vector2(0, 1.0), Vector2(3.2, -3.0), Vector2(6.2, -0.2)]), ic, 1.9, true)
		"apex":          # a crown
			var cr = PoolVector2Array([Vector2(-5.6, 3.8), Vector2(-5.6, -2.6), Vector2(-2.6, 0.2), Vector2(0, -4.8), Vector2(2.6, 0.2), Vector2(5.6, -2.6), Vector2(5.6, 3.8)])
			n.draw_colored_polygon(cr, Color(acc.r, acc.g, acc.b, a))
		"squad":         # a flag in the order's colour
			n.draw_line(Vector2(-3.6, 5.4), Vector2(-3.6, -5.4), ic, 1.6, true)
			n.draw_colored_polygon(PoolVector2Array([Vector2(-3.0, -5.4), Vector2(5.0, -2.8), Vector2(-3.0, -0.2)]), Color(acc.r, acc.g, acc.b, a))


# ---------------------------------------------------------------- input and the camera flight
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == TOGGLE_KEY:
		set_enabled(not enabled)
		get_tree().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT and cam != null:
		if _blocked():
			return
		var s = _symbol_at(event.position)
		if s != null:
			_fly_to(s)
			get_tree().set_input_as_handled()


# Fly down to a symbol: centre what it marks and zoom in until the rows in front of its lane have parted.
func _fly_to(s: Dictionary) -> void:
	var lane = s["lane"]
	var tz = cam.zoom.x
	for c in INNER:
		if _lanes[c] > lane:
			tz = min(tz, Z_LO[c] * 0.94)
			break
	tz = clamp(tz, cam.min_zoom, cam.max_zoom)
	var sy = ground.smooth_px(int(floor(s["x"] / sim.grid.CELL)))
	_fly = {"p0": cam.position, "z0": cam.zoom.x, "p1": Vector2(s["x"], GroundView.lane_y(sy, lane) - 34.0), "z1": tz, "t": 0.0}
	_fly_p = cam.position
	_fly_z = cam.zoom.x


func _step_fly(delta: float) -> void:
	if _fly.empty():
		return
	if (cam.position - _fly_p).length() > 0.5 or abs(cam.zoom.x - _fly_z) > 0.0005 or (scene != null and scene.watch_mode):
		_fly = {}            # the player took the camera (keys, wheel, drag): let go
		return
	_fly["t"] = min(1.0, _fly["t"] + delta / FLY_TIME)
	var e = smoothstep(0.0, 1.0, _fly["t"])
	cam.zoom = Vector2.ONE * exp(lerp(log(_fly["z0"]), log(_fly["z1"]), e))
	cam.position = _fly["p0"].linear_interpolate(_fly["p1"], e)
	_fly_p = cam.position
	_fly_z = cam.zoom.x
	if _fly["t"] >= 1.0:
		_fly = {}
