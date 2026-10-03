extends Reference
# Draws the deep earth (core/ug/veins.gd): mineral veins, crystal geodes, the Void cracks in the deep floor, and the mulch under
# the turf. Everything that does not move is built once per structure into an ArrayMesh (mesh_kit.gd) kept on the structure's
# dictionary ("_m"; "_c" for a crack's line lists), cut against the tunnels it crosses so nothing paints over a hole, and dropped
# by on_carve when the colony digs next to it. Per frame only the glow moves: a geode costs about six draw calls, a crack three,
# a vein or a mulch strip one. animated() is true only while something that glows was on screen in the last draw.
#
# Mulch art: when the owner's pictures exist they replace the procedural chips, nothing else to change. Looked for, in
# content/art/: mulch/chips.png (a strip of square frames, side by side), mulch/chip_0.png .. chip_11.png, and the same for
# twigs (mulch/twigs.png, mulch/twig_0.png ..). Missing files are never loaded (no log spam), and with none the chips are drawn.

const Veins = preload("res://mods-unpacked/Judah-InfDNA/core/ug/veins.gd")
const MeshKit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/mesh_kit.gd")
const Lib = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")

const ANIM = "infdna_ug_veins_anim"     # Engine meta: did the last draw show anything that glows
const RES = "infdna_ug_veins_res"       # Engine meta: the glow texture and the mulch art, made once
const MAX_BUILDS = 10                    # meshes built per frame at most (a first zoomed-out look streams in over a few frames)
const MULCH_ZOOM = 2.1                   # farther out than this the chips are under two pixels: skipped
const INK = Color("#15121a")

const BARK = [Color(0.27, 0.16, 0.09), Color(0.42, 0.23, 0.12), Color(0.52, 0.31, 0.16), Color(0.66, 0.47, 0.28), Color(0.36, 0.25, 0.16), Color(0.58, 0.36, 0.2)]
const TWIG = Color(0.22, 0.14, 0.08)
const QUARTZ = [Color(0.88, 0.86, 0.82), Color(0.9, 0.8, 0.8), Color(0.8, 0.84, 0.88)]
const IRON = [Color(0.66, 0.35, 0.14), Color(0.74, 0.47, 0.18), Color(0.56, 0.27, 0.12)]
const AMBER_LIT = Color(1.0, 0.84, 0.46)
const AMBER_DARK = Color(0.82, 0.47, 0.14)
const VIOLET_LIT = Color(0.88, 0.7, 1.0)
const VIOLET_DARK = Color(0.5, 0.27, 0.86)
const VOID_CORE = Color(0.86, 0.66, 1.0)
const VOID_MID = Color(0.62, 0.3, 0.98)
const VOID_GLOW = Color(0.46, 0.14, 0.86)


static func animated() -> bool:
	return Engine.has_meta(ANIM) and Engine.get_meta(ANIM)


static func draw(ci: CanvasItem, sim, feats: Array, t: float, zoom: float) -> void:
	var g = sim.grid
	var C = g.CELL
	var vr = _view_rect(ci).grow(36.0)
	var res = _res()
	var sig = _sig(sim)
	var vs = _void_state(sim, t)
	var lists = {"mulch": [], "vein": [], "crack": [], "geode": []}
	for f in feats:
		var k = f["kind"]
		if not lists.has(k):
			continue
		var y0 = f["y0"]
		if k == "crack" and vs["stage"] != 3:
			y0 = f["by0"]          # the rift above the fissure is only drawn after the collapse
		if Rect2(f["x0"] * C, y0 * C, (f["x1"] - f["x0"] + 1) * C, (f["y1"] - y0 + 1) * C).intersects(vr):
			lists[k].append(f)
	var budget = [MAX_BUILDS]
	var anim = false
	if zoom < MULCH_ZOOM:
		for f in lists["mulch"]:
			_draw_mulch(ci, sim, f, sig, budget, res)
	for f in lists["vein"]:
		var m = _cached(f, "_m", sig, budget)
		if m == null and _spend(budget):
			m = _put(f, "_m", sig, {"mesh": _vein_mesh(sim, f)})
		if m != null and m["mesh"] != null:
			ci.draw_mesh(m["mesh"], null)
	for f in lists["crack"]:
		if _draw_crack(ci, sim, f, sig, budget, vs, t, res):
			anim = true
	for f in lists["geode"]:
		_draw_geode(ci, sim, f, sig, budget, t, res)
		anim = true
	if budget[0] <= 0:
		anim = true                # come back next frame for the ones that did not fit
	Engine.set_meta(ANIM, anim)


# ------------------------------------------------------------------ cache plumbing
# World rectangle on screen (the view is told the columns, not the rows).
static func _view_rect(ci: CanvasItem) -> Rect2:
	var inv = ci.get_canvas_transform().affine_inverse()
	return inv.xform(Rect2(Vector2.ZERO, ci.get_viewport_rect().size))


# What a cached shape depends on besides the colony's digging (which on_carve reports): the world itself, new shafts, the pit.
static func _sig(sim) -> String:
	var g = sim.grid
	return "%d:%d:%d" % [g.get_instance_id(), g.entrances.size(), sim.void_x if sim.arc_stage == 3 else -99999]


static func _cached(f: Dictionary, key: String, sig: String, budget: Array):
	if f.has(key):
		var e = f[key]
		if e["sig"] == sig or budget[0] <= 0:
			return e               # (stale but drawable while the build budget is spent)
	return null


static func _spend(budget: Array) -> bool:
	if budget[0] <= 0:
		return false
	budget[0] -= 1
	return true


static func _put(f: Dictionary, key: String, sig: String, e: Dictionary) -> Dictionary:
	e["sig"] = sig
	f[key] = e
	return e


static func _res() -> Dictionary:
	if Engine.has_meta(RES):
		return Engine.get_meta(RES)
	var r = {"glow": _glow_tex(), "chips": _art_pieces("chip"), "twigs": _art_pieces("twig")}
	Engine.set_meta(RES, r)
	return r


# A soft round spot (white, alpha falling off to the rim): drawn tinted for every glow, one call each.
static func _glow_tex() -> ImageTexture:
	var n = 64
	var img = Image.new()
	img.create(n, n, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in n:
		for x in n:
			var d = Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a = clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	img.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	return tex


# [[texture, region], ...] for the mulch art of one kind ("chip" or "twig"), or [] when there is none yet.
static func _art_pieces(kind: String) -> Array:
	var out := []
	var f = File.new()
	var lib = Lib.get_lib()
	var sheet = "mulch/%ss.png" % kind
	if f.file_exists(Lib.DIR + sheet):
		var tx = lib.tex(sheet)
		if tx != null:
			var sz = tx.get_size()
			var nfr = max(1, int(round(sz.x / max(1.0, sz.y))))
			var fw = sz.x / nfr
			for i in nfr:
				out.append([tx, Rect2(i * fw, 0, fw, sz.y)])
	for i in 12:
		var one = "mulch/%s_%d.png" % [kind, i]
		if f.file_exists(Lib.DIR + one):
			var tx2 = lib.tex(one)
			if tx2 != null:
				out.append([tx2, Rect2(Vector2.ZERO, tx2.get_size())])
	return out


static func _glow(ci: CanvasItem, res: Dictionary, pos: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(res["glow"], Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


# The terrain shader darkens the soil with depth; things set into it follow.
static func _depth_dim(d: float) -> float:
	return 1.0 - 0.3 * smoothstep(25.0, 190.0, d)


static func _solid(g, p: Vector2) -> bool:
	return g.is_solid(int(floor(p.x)), int(floor(p.y)), 0)


static func _shade(c: Color, k: float, a: float = 1.0) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, a)


# ------------------------------------------------------------------ mulch
static func _draw_mulch(ci: CanvasItem, sim, f: Dictionary, sig: String, budget: Array, res: Dictionary) -> void:
	var m = _cached(f, "_m", sig, budget)
	if m == null:
		if not _spend(budget):
			return
		m = _put(f, "_m", sig, _mulch_build(sim, f, res))
	if m["mesh"] != null:
		ci.draw_mesh(m["mesh"], null)
	for c in m["art"]:
		ci.draw_texture_rect_region(c[0], c[1], c[2])


static func _mulch_build(sim, f: Dictionary, res: Dictionary) -> Dictionary:
	var g = sim.grid
	var C = g.CELL
	var mk = MeshKit.new()
	var art := []
	var chips: Array = res["chips"]
	var twigs: Array = res["twigs"]
	for x in range(int(f["x0"]), int(f["x1"]) + 1):
		var h = g._ih(x, 17, 9301)
		var n = 0 if h < 0.4 else (1 if h < 0.85 else 2)
		var by = g.base_y(x)
		for i in n:
			var yc = by + 1.9 + g._ih(x, i, 9302) * 3.4
			var pc = Vector2(x + g._ih(x, i, 9303), yc)
			if yc < g.surf_y(x) + 1.8:
				continue                       # in the turf (or a mouth's rim)
			var twig = g._ih(x, i, 9304) < 0.14
			var ln = (8.0 + 6.0 * g._ih(x, i, 9305)) if twig else (3.6 + 4.2 * g._ih(x, i, 9305))
			var ang = (g._ih(x, i, 9306) - 0.5) * (1.4 if twig else 1.0)
			var dir = Vector2(cos(ang), sin(ang))
			var half = dir * ln * 0.5 / C
			if not (_solid(g, pc) and _solid(g, pc + half) and _solid(g, pc - half)):
				continue                       # never over a hole
			var p = pc * C
			var pieces = twigs if twig else chips
			if not pieces.empty():
				var pick = pieces[int(g._ih(x, i, 9307) * pieces.size()) % pieces.size()]
				var rg: Rect2 = pick[1]
				var sz = Vector2(ln, ln * rg.size.y / max(1.0, rg.size.x))
				if g._ih(x, i, 9308) < 0.5:
					art.append([pick[0], Rect2(p + Vector2(sz.x * 0.5, -sz.y * 0.5), Vector2(-sz.x, sz.y)), rg])
				else:
					art.append([pick[0], Rect2(p - sz * 0.5, sz), rg])
				continue
			if twig:
				_twig(mk, g, x, i, p, dir, ln)
			else:
				_chip(mk, g, x, i, p, dir, ln)
	return {"mesh": mk.build(), "art": art}


static func _chip(mk, g, x: int, i: int, p: Vector2, dir: Vector2, ln: float) -> void:
	var th = 1.5 + 1.5 * g._ih(x, i, 9310)
	var nrm = Vector2(-dir.y, dir.x)
	var a = dir * ln * 0.5
	var b = nrm * th * 0.5
	var j1 = nrm * (g._ih(x, i, 9311) - 0.5) * th * 0.6     # a ragged, not quite square chip
	var j2 = dir * (g._ih(x, i, 9312) - 0.5) * ln * 0.25
	var q = [p - a - b + j2, p + a - b + j1, p + a + b, p - a + b - j1 * 0.5]
	var o = 0.8
	mk.quad(q[0] + (-dir - nrm) * o, q[1] + (dir - nrm) * o, q[2] + (dir + nrm) * o, q[3] + (-dir + nrm) * o, Color(INK.r, INK.g, INK.b, 0.8))
	var col: Color = BARK[int(g._ih(x, i, 9313) * BARK.size()) % BARK.size()]
	mk.quad(q[0], q[1], q[2], q[3], col)
	if g._ih(x, i, 9314) < 0.6:
		# the cut face catches the light along its top edge
		mk.quad(q[0], q[1], q[1].linear_interpolate(q[2], 0.4), q[0].linear_interpolate(q[3], 0.4), col.lightened(0.22))


static func _twig(mk, g, x: int, i: int, p: Vector2, dir: Vector2, ln: float) -> void:
	var nrm = Vector2(-dir.y, dir.x)
	var bend = (g._ih(x, i, 9315) - 0.5) * 3.0
	var pts = PoolVector2Array([p - dir * ln * 0.5, p + nrm * bend, p + dir * ln * 0.5])
	mk.ribbon(pts, PoolRealArray([2.8, 2.6, 2.0]), Color(INK.r, INK.g, INK.b, 0.75))
	mk.ribbon(pts, PoolRealArray([1.3, 1.2, 0.8]), TWIG.lightened(g._ih(x, i, 9316) * 0.25))
	if g._ih(x, i, 9317) < 0.5:
		var s = pts[1]
		var e = s + (dir * 0.6 + nrm * (0.8 if bend < 0.0 else -0.8)).normalized() * ln * 0.3
		mk.ribbon(PoolVector2Array([s, e]), PoolRealArray([2.2, 1.6]), Color(INK.r, INK.g, INK.b, 0.7))
		mk.ribbon(PoolVector2Array([s, e]), PoolRealArray([1.0, 0.6]), TWIG)


# ------------------------------------------------------------------ veins
static func _vein_mesh(sim, f: Dictionary):
	var g = sim.grid
	var C = g.CELL
	var pts: PoolVector2Array = f["pts"]
	var ws: PoolRealArray = f["w"]
	# runs of the band over solid rock: a tunnel cuts the vein, it does not paint over the tunnel
	var runs := []
	var cp := PoolVector2Array()
	var cw := PoolRealArray()
	for i in pts.size():
		if _solid(g, pts[i]):
			cp.append(pts[i] * C)
			cw.append(ws[i] * C)
		else:
			if cp.size() >= 2:
				runs.append([cp, cw])
			cp = PoolVector2Array()
			cw = PoolRealArray()
	if cp.size() >= 2:
		runs.append([cp, cw])
	if runs.empty():
		return null
	var dim = _depth_dim(f["d"])
	var q = f["q"]
	var s = f["seed"]
	var fill: Color = (QUARTZ if q else IRON)[int(s * 3.0) % 3]
	fill = _shade(fill, dim)
	var edge = Color(0.2 * dim, 0.16 * dim, 0.17 * dim, 0.7) if q else Color(0.24 * dim, 0.11 * dim, 0.05 * dim, 0.65)
	var mk = MeshKit.new()
	for run in runs:
		var p: PoolVector2Array = run[0]
		var w: PoolRealArray = run[1]
		var n = w.size()
		if not q:
			# iron leaches into the rock around it: a faint rust stain either side of the band
			mk.ribbon(p, _scaled(w, 3.4, 2.0), Color(0.62 * dim, 0.3 * dim, 0.1 * dim, 0.16))
		mk.ribbon(p, _scaled(w, 1.0, 1.8), edge)
		mk.ribbon(p, w, fill)
		if q:
			mk.ribbon(p, _scaled(w, 0.32, 0.0), Color(1, 1, 1, 0.45 * dim))       # the glassy streak down the middle
		# glints (quartz) or dark nodules (iron) along the band
		for i in range(2, n - 2, 5):
			var hh = fmod(s * 97.0 + i * 0.618, 1.0)
			if hh > 0.45:
				continue
			var c = p[i] + Vector2(0, (hh - 0.22) * w[i] * 0.8)
			if q:
				var r = 0.6 + w[i] * 0.22
				mk.quad(c + Vector2(0, -r * 1.6), c + Vector2(r, 0), c + Vector2(0, r * 1.6), c + Vector2(-r, 0), Color(1, 1, 1, 0.8 * dim))
			else:
				mk.ellipse(c, 0.9 + w[i] * 0.25, 0.7 + w[i] * 0.2, Color(0.2 * dim, 0.09 * dim, 0.05 * dim, 0.85), 6)
	return mk.build()


static func _scaled(w: PoolRealArray, k: float, add: float) -> PoolRealArray:
	var out := PoolRealArray()
	for v in w:
		out.append(v * k + add)
	return out


# ------------------------------------------------------------------ the Void cracks
# How strongly the Void shows through, for the whole screen at once.
static func _void_state(sim, t: float) -> Dictionary:
	var ms = clamp(sim.monstrosity / 100.0, 0.0, 1.0)
	var b = 0.2 + 0.5 * smoothstep(0.1, 0.95, ms)
	var w = 1.0
	var st = int(sim.arc_stage)
	var moving = ms > 0.2
	match st:
		1:
			b += 0.1 + 0.08 * sin(t * 1.4)
			moving = true
		2:
			var pulse = exp(-sim.arc_t * 1.1)            # arc_t restarts at each tremor
			b += 0.2 + 0.55 * pulse + 0.05 * sin(t * 5.0)
			w = 1.0 + 0.1 * sim.arc_tremors + 0.9 * pulse
			moving = true
		3:
			b = max(b, 0.8) + 0.08 * sin(t * 3.1)
			w = 1.3
			moving = true
	b += 0.05 * min(3, sim.void_cycles)                  # every sealed Void leaves the cracks a little brighter
	if moving and st == 0:
		b += 0.05 * sin(t * 0.9)
	return {"b": clamp(b, 0.0, 1.6), "w": w, "stage": st, "moving": moving, "vx": float(sim.void_x), "at": sim.arc_t}


static func _draw_crack(ci: CanvasItem, sim, f: Dictionary, sig: String, budget: Array, vs: Dictionary, t: float, res: Dictionary) -> bool:
	var g = sim.grid
	var C = g.CELL
	var e = _cached(f, "_c", sig, budget)
	if e == null:
		if not _spend(budget):
			return true
		e = _put(f, "_c", sig, _crack_build(sim, f))
	var prox = 0.0
	if vs["stage"] == 3:
		prox = 1.0 - clamp(abs(f["rx"] - vs["vx"]) / 170.0, 0.0, 1.0)
	var flick = 0.92 + 0.08 * sin(t * 2.3 + f["ph"])
	var b = (vs["b"] + 0.45 * prox) * flick
	var w = vs["w"] * (1.0 + 2.2 * prox)
	var segs: PoolVector2Array = e["segs"]
	if segs.size() >= 2:
		if b > 0.45:
			_glow(ci, res, Vector2(f["rx"], f["ry"]) * C, (14.0 + 10.0 * w) * (0.6 + 0.4 * b), Color(VOID_GLOW.r, VOID_GLOW.g, VOID_GLOW.b, 0.22 * b))
		ci.draw_multiline(segs, Color(VOID_GLOW.r, VOID_GLOW.g, VOID_GLOW.b, clamp(0.16 * b, 0.0, 0.5)), 4.5 * w)
		ci.draw_multiline(segs, Color(VOID_MID.r, VOID_MID.g, VOID_MID.b, clamp(0.55 * b, 0.0, 0.95)), 1.9 * w)
		ci.draw_multiline(segs, Color(VOID_CORE.r, VOID_CORE.g, VOID_CORE.b, clamp(b - 0.25, 0.0, 1.0)), max(0.8, 0.8 * w))
	# after the collapse the fissures near the pit climb toward it, bending in as they rise
	if prox > 0.2:
		var rift: PoolVector2Array = e["rift"]
		var ok: PoolByteArray = e["rok"]
		var grow = clamp(vs["at"] / 30.0, 0.12, 1.0) * smoothstep(0.2, 0.85, prox)
		var nd = int(rift.size() * grow)
		var vx = vs["vx"] * C
		var line := PoolVector2Array()
		var prev = Vector2()
		for i in nd:
			var k = float(i) / max(1, rift.size() - 1)
			var p = rift[i]
			p.x += (vx - p.x) * k * 0.75 * prox
			if i > 0 and ok[i] == 1 and ok[i - 1] == 1:
				line.append(prev)
				line.append(p)
			prev = p
		if line.size() >= 2:
			var rb = b * (0.7 + 0.3 * prox)
			ci.draw_multiline(line, Color(VOID_GLOW.r, VOID_GLOW.g, VOID_GLOW.b, clamp(0.18 * rb, 0.0, 0.5)), 6.0 * w * 0.7)
			ci.draw_multiline(line, Color(VOID_MID.r, VOID_MID.g, VOID_MID.b, clamp(0.6 * rb, 0.0, 0.95)), 2.2 * w * 0.7)
			ci.draw_multiline(line, Color(VOID_CORE.r, VOID_CORE.g, VOID_CORE.b, clamp(rb - 0.2, 0.0, 1.0)), max(0.9, w * 0.6))
			if nd > 0:
				_glow(ci, res, prev, 18.0 + 14.0 * prox, Color(VOID_MID.r, VOID_MID.g, VOID_MID.b, 0.35 * rb))   # the tip, still splitting the rock
	return vs["moving"] or prox > 0.0


static func _crack_build(sim, f: Dictionary) -> Dictionary:
	var g = sim.grid
	var C = g.CELL
	var src: PoolVector2Array = f["segs"]
	var segs := PoolVector2Array()
	var i = 0
	while i + 1 < src.size():
		var a = src[i]
		var b = src[i + 1]
		if _solid(g, (a + b) * 0.5):
			segs.append(a * C)
			segs.append(b * C)
		i += 2
	var rift := PoolVector2Array()
	var rok := PoolByteArray()
	for p in f["rift"]:
		rift.append(p * C)
		rok.append(1 if _solid(g, p) else 0)
	return {"segs": segs, "rift": rift, "rok": rok}


# ------------------------------------------------------------------ geodes
static func _draw_geode(ci: CanvasItem, sim, f: Dictionary, sig: String, budget: Array, t: float, res: Dictionary) -> void:
	var C = sim.grid.CELL
	var vi = Veins.violet(sim, f)
	var hsig = "%s:%d" % [sig, int(round(vi * 8.0))]
	var e = _cached(f, "_m", hsig, budget)
	if e == null:
		if not _spend(budget):
			return
		e = _put(f, "_m", hsig, _geode_build(sim, f, vi))
	var c = Vector2(f["cx"], f["cy"]) * C
	var R = max(f["rx"], f["ry"]) * C
	var hue = AMBER_DARK.linear_interpolate(VIOLET_DARK, vi)
	var lit = AMBER_LIT.linear_interpolate(VIOLET_LIT, vi)
	var sh = 0.5 + 0.5 * sin(t * 1.7 + f["seed"] * 20.0)
	var opened = Veins.is_open(sim, f)
	var k = 1.15 if opened else 1.0
	# a faint halo on the rock around it, the rind and the dark hollow, the light inside, the crystals, a glint
	_glow(ci, res, c, R * 2.7, Color(hue.r, hue.g, hue.b, (0.1 + 0.05 * sh) * k))
	if e["m0"] != null:
		ci.draw_mesh(e["m0"], null)
	_glow(ci, res, c + Vector2(0, R * 0.15), R * 1.15, Color(lit.r, lit.g, lit.b, (0.26 + 0.12 * sh) * k))
	if e["m1"] != null:
		ci.draw_mesh(e["m1"], null)
	var tips: PoolVector2Array = e["tips"]
	if tips.size() > 0:
		var ph = t * 0.8 + f["seed"] * 31.0
		var tip = tips[int(floor(ph)) % tips.size()]
		var a = sin(fmod(ph, 1.0) * PI)
		var s = 1.5 + 3.5 * a
		var col = Color(1.0, 0.97, 0.9, 0.9 * a)
		ci.draw_line(tip - Vector2(s, 0), tip + Vector2(s, 0), col, 1.0)
		ci.draw_line(tip - Vector2(0, s * 1.3), tip + Vector2(0, s * 1.3), col, 1.0)


static func _geode_build(sim, f: Dictionary, vi: float) -> Dictionary:
	var g = sim.grid
	var C = g.CELL
	var c = Vector2(f["cx"], f["cy"]) * C
	var rx = f["rx"] * C
	var ry = f["ry"] * C
	var s = f["seed"]
	var dim = _depth_dim(f["d"])
	# rind: banded chalcedony in sectors, a sector left out where a tunnel has cut through it
	var m0 = MeshKit.new()
	var bands = [[1.25 * C, 1.6, _shade(INK, 1.0, 0.9)], [0.95 * C, 1.0, _shade(Color(0.62, 0.6, 0.62), dim)],
		[0.5 * C, 1.0, _shade(Color(0.78, 0.76, 0.8).linear_interpolate(Color(0.86, 0.76, 0.62), 1.0 - vi), dim)], [0.18 * C, 1.0, _shade(Color(0.5, 0.48, 0.55), dim)]]
	var nsec = 28
	for bi in bands.size():
		var out_r = bands[bi][0]
		var col: Color = bands[bi][2]
		for i in nsec:
			var a0 = TAU * i / nsec
			var a1 = TAU * (i + 1) / nsec
			var wob0 = 1.0 + 0.06 * sin(a0 * 3.0 + s * 40.0)
			var wob1 = 1.0 + 0.06 * sin(a1 * 3.0 + s * 40.0)
			var mid = (a0 + a1) * 0.5
			var probe = c + Vector2(cos(mid) * (rx + out_r * 0.5), sin(mid) * (ry + out_r * 0.5))
			if not _solid(g, probe / C):
				continue
			var i0 = c + Vector2(cos(a0) * rx * wob0, sin(a0) * ry * wob0)
			var i1 = c + Vector2(cos(a1) * rx * wob1, sin(a1) * ry * wob1)
			var o0 = c + Vector2(cos(a0) * (rx * wob0 + out_r), sin(a0) * (ry * wob0 + out_r))
			var o1 = c + Vector2(cos(a1) * (rx * wob1 + out_r), sin(a1) * (ry * wob1 + out_r))
			m0.quad(i0, i1, o1, o0, col)
	# the hollow: dark, lit a little from inside
	var cav = Color(0.07, 0.05, 0.08).linear_interpolate(Color(0.12, 0.06, 0.16), vi)
	var cav_c = cav.linear_interpolate(AMBER_DARK.linear_interpolate(VIOLET_DARK, vi), 0.35)
	m0.ellipse(c, rx * 1.02, ry * 1.02, cav, 24, 0.0, cav_c)
	# crystals: pointed prisms around the wall, aimed roughly at the middle, two-toned (lit / shaded face)
	var m1 = MeshKit.new()
	var lit = AMBER_LIT.linear_interpolate(VIOLET_LIT, vi)
	var drk = AMBER_DARK.linear_interpolate(VIOLET_DARK, vi)
	var tips := PoolVector2Array()
	var n = 11 + int(s * 7.0)
	for layer in 2:
		for i in n:
			var h = fmod(s * 53.0 + i * 0.381 + layer * 0.17, 1.0)
			var a = TAU * (i + 0.5 * layer + 0.3 * h) / n
			var base = c + Vector2(cos(a) * rx * 0.98, sin(a) * ry * 0.98)
			if not _solid(g, (c + Vector2(cos(a) * (rx + 0.7 * C), sin(a) * (ry + 0.7 * C))) / C):
				continue                           # the wall is gone here (a tunnel came in)
			var dir = (c - base).normalized().rotated((h - 0.5) * 0.6)
			var ln = (0.32 + 0.42 * h) * min(rx, ry) * (0.55 if layer == 1 else 1.0)
			var hw = (0.13 + 0.09 * fmod(h * 7.0, 1.0)) * C * (0.7 if layer == 1 else 1.0)
			var nr = Vector2(-dir.y, dir.x)
			var mid_top = base + dir * ln * 0.7
			var tip = base + dir * ln
			var p0 = base - nr * hw
			var p1 = base + nr * hw
			var p2 = mid_top + nr * hw * 0.9
			var p3 = mid_top - nr * hw * 0.9
			var o = 0.9
			m1.quad(p0 - nr * o - dir * o, p1 + nr * o - dir * o, p2 + nr * o, p3 - nr * o, Color(INK.r, INK.g, INK.b, 0.85))
			m1.tri(p3 - nr * o, p2 + nr * o, tip + dir * o * 1.4, Color(INK.r, INK.g, INK.b, 0.85))
			var l2 = lit if layer == 0 else lit.linear_interpolate(drk, 0.3)
			m1.quad(p0, base, mid_top, p3, l2)
			m1.quad(base, p1, p2, mid_top, drk)
			m1.tri(p3, mid_top, tip, l2.lightened(0.25))
			m1.tri(mid_top, p2, tip, drk.lightened(0.15))
			if layer == 0:
				tips.append(tip)
	return {"m0": m0.build(), "m1": m1.build(), "tips": tips}
