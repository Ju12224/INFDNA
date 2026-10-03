extends Reference
# Draws the caverns (core/ug/caverns.gd) over the open cells the terrain shader leaves: a dark interior that deepens toward the
# middle, two layers of rock silhouettes receding into it, stalactites, stalagmites and the odd column, glow-worm threads; then,
# every frame, the pool (its mesh rebuilt only when the water level moves), a shimmer on its surface, the glow-worms' twinkle
# (and their reflection in the pool) and drips falling from stalactite tips.
# The static part of each cavern is one cached ArrayMesh (built once, one draw_mesh call); the moving part is a handful of
# draw calls per cavern on screen, and none at all when no cavern is in view (animated() then reports false, see below).

const MK = preload("res://mods-unpacked/Judah-InfDNA/content/colony/mesh_kit.gd")
const CAV = preload("res://mods-unpacked/Judah-InfDNA/core/ug/caverns.gd")
const INK = Color("#15121a")
const ANIM_META = "infdna_cav_anim"
const CACHE_META = "cav_cache"
const LIME = Color(0.70, 0.66, 0.55)
const SAND = Color(0.74, 0.57, 0.36)
const GLOW = Color(0.62, 1.0, 0.95)
const TWINKLE_ZOOM = 2.3      # zoomed out further than this, the specks and drips are below a pixel: drawn static


# True when the last draw() had something that moves in view (ug_view asks right after draw(), so this frame's answer).
static func animated() -> bool:
	return Engine.has_meta(ANIM_META) and bool(Engine.get_meta(ANIM_META))


static func draw(ci: CanvasItem, sim, feats: Array, t: float, zoom: float) -> void:
	var g = sim.grid
	var C = g.CELL
	var inv = ci.get_global_transform_with_canvas().affine_inverse()
	var vr = Rect2(inv.xform(Vector2.ZERO), inv.basis_xform(ci.get_viewport_rect().size)).abs().grow(24.0)
	var cache: Dictionary
	if ci.has_meta(CACHE_META):
		cache = ci.get_meta(CACHE_META)
	else:
		cache = {}
		ci.set_meta(CACHE_META, cache)
	var anim := false
	var sl = g.sim_l()
	var sr = g.sim_r()
	var wet = clamp(float(sim.wet), 0.0, 1.0)
	for f in feats:
		# only hollows the sim has stamped whole (half a cavern at the edge of the simulated columns is not drawn yet)
		if int(f["x0"]) < sl or int(f["x1"]) > sr:
			continue
		var bb = Rect2(int(f["x0"]) * C, int(f["y0"]) * C, (int(f["x1"]) - int(f["x0"]) + 1) * C, (int(f["y1"]) - int(f["y0"]) + 1) * C)
		if not vr.intersects(bb):
			continue
		var key = "%d:%s" % [g._seed, f["id"]]
		var e = cache.get(key)
		if e == null:
			if cache.size() > 300:
				cache.clear()
			e = _build(g, f)
			cache[key] = e
		if e["mesh"] != null:
			ci.draw_mesh(e["mesh"], null)
		var moving = zoom <= TWINKLE_ZOOM
		var lvl = CAV.pool_level(sim, f)
		if f.get("pool", false):
			_pool(ci, e, f, lvl, t, moving)
		if moving:
			_glow(ci, e, t, zoom)
			_drips(ci, e, t, wet, zoom)
			if not e["glow"].empty() or not e["drips"].empty() or f.get("pool", false):
				anim = true
	Engine.set_meta(ANIM_META, anim)


static func _h(a: float, b: float) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


# Moves each point toward c by `by` px (the outline is star-shaped around c, so the result stays a simple polygon).
static func _inset(pts: PoolVector2Array, c: Vector2, by: float) -> PoolVector2Array:
	var out := PoolVector2Array()
	for p in pts:
		var d = p - c
		var l = d.length()
		out.append(c + d * (max(0.0, l - by) / max(0.001, l)))
	return out


# Fills each polygon of `polys` (clipping results) by triangulation, one colour from top (y_top) to bottom (y_bot).
static func _fill(mk, polys: Array, c_top: Color, c_bot: Color, y_top: float, y_bot: float) -> void:
	for poly in polys:
		if poly.size() < 3:
			continue
		var idx = Geometry.triangulate_polygon(poly)
		for i in range(0, idx.size() - 2, 3):
			var a = poly[idx[i]]
			var b = poly[idx[i + 1]]
			var d = poly[idx[i + 2]]
			mk.tri_c(a, _grad(c_top, c_bot, a.y, y_top, y_bot), b, _grad(c_top, c_bot, b.y, y_top, y_bot), d, _grad(c_top, c_bot, d.y, y_top, y_bot))


static func _grad(a: Color, b: Color, y: float, y0: float, y1: float) -> Color:
	return a.linear_interpolate(b, clamp((y - y0) / max(0.001, y1 - y0), 0.0, 1.0))


# ---------------------------------------------------------------- static geometry (once per cavern)
static func _build(g, f: Dictionary) -> Dictionary:
	var C = g.CELL
	var kind = f["kind"]
	var mk = MK.new()
	var sd = float(int(f["x0"]) * 131 + int(f["y"]) * 7) + float(g._seed % 9973) * 0.37
	var segs = 64 if kind == "cavern" else (44 if kind == "cave" else 26)
	var ctr = Vector2(f["cx"], f["cy"]) * C
	var outl := PoolVector2Array()
	for p in CAV.outline(f, segs):
		outl.append(p * C)
	var small = min(f["rx"], f["ry"]) * C
	var deep = g.strata_at(int(f["cx"]), int(f["cy"])) >= g.M_RED
	var tint = LIME if deep else SAND
	var x0 = int(f["x0"])
	var x1 = int(f["x1"])
	# per column: ceiling edge and floor edge (px) of the open cells, -1 where the column misses the hollow
	var tops := {}
	var bots := {}
	for x in range(x0, x1 + 1):
		var ty = CAV.top_cell(f, x)
		if ty >= 0:
			tops[x] = ty * C
			bots[x] = (CAV.bottom_cell(f, x) + 1) * C
	# 1. the dark: transparent at the walls (the terrain's rim and ink stay visible), deepest in the middle
	var o0 = _inset(outl, ctr, min(0.3 * C, small * 0.2))
	var o1 = _inset(outl, ctr, min(1.4 * C, small * 0.45))
	var dark = Color(0.02, 0.025, 0.04)
	var a_edge = 0.62 if kind != "pocket" else 0.5
	var c_clear = Color(dark.r, dark.g, dark.b, 0.0)
	var c_edge = Color(dark.r, dark.g, dark.b, a_edge)
	var c_mid = Color(dark.r, dark.g, dark.b, 0.9 if kind != "pocket" else 0.7)
	var n = outl.size()
	for i in n:
		var j = (i + 1) % n
		mk.quad_c(o0[i], c_clear, o0[j], c_clear, o1[j], c_edge, o1[i], c_edge)
	mk.fan(ctr, o1, c_edge, c_mid)
	var e = {"mesh": null, "glow": [], "drips": [], "pool_q": -1, "pool_mesh": null, "surf": [], "outl": o0, "ctr": ctr, "C": C}
	if kind == "pocket":
		e["mesh"] = mk.build()
		return e
	# 2. rock receding into the dark: a far layer of tall ridges and hanging curtains, then a nearer, lower, lighter one
	var clip = [o1]
	var far_c = Color(tint.r * 0.13, tint.g * 0.13, tint.b * 0.15 + 0.01, 0.95)
	var mid_c = Color(tint.r * 0.24, tint.g * 0.23, tint.b * 0.22, 0.97)
	var mid_c2 = Color(tint.r * 0.17, tint.g * 0.16, tint.b * 0.16, 0.97)
	for layer in 2:
		var up := PoolVector2Array()
		var dn := PoolVector2Array()
		var amp_f = 0.42 if layer == 0 else 0.2
		var amp_c = 0.26 if layer == 0 else 0.1
		var ys_bot = -1e9
		var ys_top = 1e9
		for x in range(x0, x1 + 1):
			if not tops.has(x):
				continue
			var hgt = bots[x] - tops[x]
			var px = (x + 0.5) * C
			var r1 = 0.55 * _h(sd + layer * 3.1, x * 0.37) + 0.45 * (0.5 + 0.5 * sin(x * (0.45 + 0.3 * layer) + sd))
			var r2 = 0.6 * _h(sd + layer * 5.7, x * 0.53) + 0.4 * (0.5 + 0.5 * sin(x * (0.7 + 0.2 * layer) + sd * 1.3))
			up.append(Vector2(px, bots[x] - hgt * amp_f * r1))
			dn.append(Vector2(px, tops[x] + hgt * amp_c * r2 * r2))
			ys_bot = max(ys_bot, bots[x])
			ys_top = min(ys_top, tops[x])
		if up.size() < 2:
			continue
		var floor_poly = PoolVector2Array(up)
		floor_poly.append(Vector2(up[up.size() - 1].x + C, ys_bot + 3.0 * C))
		floor_poly.append(Vector2(up[0].x - C, ys_bot + 3.0 * C))
		var ceil_poly = PoolVector2Array(dn)
		ceil_poly.append(Vector2(dn[dn.size() - 1].x + C, ys_top - 3.0 * C))
		ceil_poly.append(Vector2(dn[0].x - C, ys_top - 3.0 * C))
		var col = far_c if layer == 0 else mid_c
		var col2 = far_c if layer == 0 else mid_c2
		_fill(mk, Geometry.intersect_polygons_2d(floor_poly, o1), col, col2, ys_top, ys_bot)
		_fill(mk, Geometry.intersect_polygons_2d(ceil_poly, o1), col2, col, ys_top, ys_bot)
	# 3. stalactites, stalagmites, now and then a column where the two meet
	var w = x1 - x0
	var n_st = int(w / 2.4) if kind == "cavern" else int(w / 3.5)
	var tips := []
	var lite = Color(tint.r * 0.66 + 0.06, tint.g * 0.66 + 0.06, tint.b * 0.66 + 0.06)
	var body = Color(tint.r * 0.5, tint.g * 0.48, tint.b * 0.45)
	var shade = Color(tint.r * 0.32, tint.g * 0.3, tint.b * 0.3)
	for i in n_st:
		var x = x0 + 1 + int(_h(sd, 11.0 + i) * (w - 1))
		if not tops.has(x) or not tops.has(x - 1) or not tops.has(x + 1):
			continue
		var hgt = (bots[x] - tops[x]) / C
		if hgt < 2.5:
			continue
		var px = (x + _h(sd, 31.0 + i)) * C
		var r = _h(sd, 51.0 + i)
		if hgt < 6.0 and r < 0.18 and kind == "cavern":
			_column(mk, px, tops[x], bots[x], C * (0.7 + 0.5 * _h(sd, 71.0 + i)), lite, body, shade)
			continue
		var ln = C * (0.8 + r * r * min(4.0, hgt * 0.42))
		var hw = C * (0.3 + 0.38 * _h(sd, 91.0 + i)) * (0.7 + 0.5 * ln / (C * 3.0))
		var tip = _stalactite(mk, px, tops[x] - 2.0, ln, hw, lite, body, shade, _h(sd, 111.0 + i) - 0.5)
		tips.append([tip, ln])
		if _h(sd, 131.0 + i) < 0.45:
			# a thin soda straw beside it
			var px2 = px + (C * 0.9 if _h(sd, 151.0 + i) < 0.5 else -C * 0.9)
			tips.append([_stalactite(mk, px2, tops[x] - 1.0, ln * 0.45, hw * 0.4, lite, body, shade, 0.0), ln * 0.45])
		if _h(sd, 171.0 + i) < 0.55 and not f.get("pool", false) or _h(sd, 171.0 + i) < 0.25:
			var up_l = C * (0.5 + _h(sd, 191.0 + i) * min(2.6, hgt * 0.3))
			_stalagmite(mk, px + C * (_h(sd, 211.0 + i) - 0.5), bots[x] + 1.5, up_l, hw * 1.35 + C * 0.25, lite, body, shade)
	# 4. glow-worms: a faint halo each and the sticky threads they let down
	var gl := []
	for i in int(f.get("glow", 0)):
		var x = x0 + 2 + int(_h(sd, 301.0 + i) * max(1, w - 3))
		if not tops.has(x):
			continue
		var p = Vector2((x + _h(sd, 321.0 + i)) * C, tops[x] + 1.5 + 2.0 * _h(sd, 341.0 + i))
		var th = 3.0 + 10.0 * _h(sd, 361.0 + i)
		mk.quad_c(p + Vector2(-0.35, 0), Color(GLOW.r, GLOW.g, GLOW.b, 0.22), p + Vector2(0.35, 0), Color(GLOW.r, GLOW.g, GLOW.b, 0.22),
			p + Vector2(0.35, th), Color(GLOW.r, GLOW.g, GLOW.b, 0.0), p + Vector2(-0.35, th), Color(GLOW.r, GLOW.g, GLOW.b, 0.0))
		mk.ellipse(p, 4.5, 3.8, Color(0.3, 0.9, 1.0, 0.0), 10, 0.0, Color(0.35, 0.95, 1.0, 0.12))
		gl.append([p, _h(sd, 381.0 + i) * TAU, 0.6 + 1.6 * _h(sd, 401.0 + i), bots.get(x, p.y)])
	e["glow"] = gl
	# 5. drips from the longest stalactite tips
	tips.sort_custom(_ByLen.new(), "longer")
	var dr := []
	for i in min(4 if kind == "cavern" else 2, tips.size()):
		var tip: Vector2 = tips[i][0]
		var tx = int(floor(tip.x / C))
		if not bots.has(tx):
			continue
		dr.append([tip, bots[tx] - 1.0, 2.8 + 3.6 * _h(sd, 501.0 + i), _h(sd, 521.0 + i)])
	e["drips"] = dr
	e["mesh"] = mk.build()
	return e


class _ByLen:
	func longer(a, b) -> bool:
		return a[1] > b[1]


# A cone hanging from (px, y): ink outline, a lit left flank, a shaded right one, a wet glint near the tip. Returns the tip.
static func _stalactite(mk, px: float, y: float, ln: float, hw: float, lite: Color, body: Color, shade: Color, bend: float) -> Vector2:
	var tip = Vector2(px + bend * hw * 0.8, y + ln)
	var mid = Vector2(px + bend * hw * 0.3, y + ln * 0.55)
	var ow = 1.3
	mk.quad(Vector2(px - hw - ow, y), Vector2(px + hw + ow, y), mid + Vector2(hw * 0.42 + ow, 0), mid + Vector2(-hw * 0.42 - ow, 0), INK)
	mk.tri(mid + Vector2(-hw * 0.42 - ow, 0), mid + Vector2(hw * 0.42 + ow, 0), tip + Vector2(0, ow * 1.4), INK)
	mk.quad_c(Vector2(px - hw, y), lite, Vector2(px, y), body, mid, body, mid + Vector2(-hw * 0.42, 0), lite)
	mk.tri_c(mid + Vector2(-hw * 0.42, 0), lite, mid, body, tip, body)
	mk.quad_c(Vector2(px, y), body, Vector2(px + hw, y), shade, mid + Vector2(hw * 0.42, 0), shade, mid, body)
	mk.tri_c(mid, body, mid + Vector2(hw * 0.42, 0), shade, tip, shade)
	if ln > 4.0:
		mk.ellipse(tip + Vector2(-0.2, -1.2), 0.55, 0.9, Color(0.85, 0.95, 1.0, 0.55), 6)
	return tip


# A rounded cone standing on (px, y), height up_l.
static func _stalagmite(mk, px: float, y: float, up_l: float, hw: float, lite: Color, body: Color, shade: Color) -> void:
	var top = Vector2(px, y - up_l)
	var sh = Vector2(px, y - up_l * 0.45)
	var ow = 1.3
	var pts = [Vector2(px - hw, y), Vector2(px - hw * 0.55, sh.y), Vector2(px - hw * 0.22, top.y + 1.0), top, Vector2(px + hw * 0.22, top.y + 1.0), Vector2(px + hw * 0.55, sh.y), Vector2(px + hw, y)]
	var ink := PoolVector2Array()
	for p in pts:
		ink.append(p + (p - Vector2(px, y - up_l * 0.35)).normalized() * ow)
	mk.fan(Vector2(px, y - up_l * 0.35), ink, INK)
	var c = Vector2(px, y - up_l * 0.35)
	for i in pts.size() - 1:
		var a = pts[i]
		var b = pts[i + 1]
		var ca = lite if a.x < px - 0.1 else (body if a.x <= px + 0.1 else shade)
		var cb = lite if b.x < px - 0.1 else (body if b.x <= px + 0.1 else shade)
		mk.tri_c(c, body, a, ca, b, cb)
	mk.tri_c(c, body, pts[pts.size() - 1], shade, Vector2(px - hw, y), lite)


# Ceiling and floor joined: an hourglass of flowstone.
static func _column(mk, px: float, y0: float, y1: float, hw: float, lite: Color, body: Color, shade: Color) -> void:
	var ym = lerp(y0, y1, 0.55)
	var wn = hw * 0.4
	var ow = 1.3
	mk.quad(Vector2(px - hw - ow, y0 - 2.0), Vector2(px + hw + ow, y0 - 2.0), Vector2(px + wn + ow, ym), Vector2(px - wn - ow, ym), INK)
	mk.quad(Vector2(px - wn - ow, ym), Vector2(px + wn + ow, ym), Vector2(px + hw * 1.3 + ow, y1 + 1.5), Vector2(px - hw * 1.3 - ow, y1 + 1.5), INK)
	mk.quad_c(Vector2(px - hw, y0 - 2.0), lite, Vector2(px, y0 - 2.0), body, Vector2(px, ym), body, Vector2(px - wn, ym), lite)
	mk.quad_c(Vector2(px, y0 - 2.0), body, Vector2(px + hw, y0 - 2.0), shade, Vector2(px + wn, ym), shade, Vector2(px, ym), body)
	mk.quad_c(Vector2(px - wn, ym), lite, Vector2(px, ym), body, Vector2(px, y1 + 1.5), body, Vector2(px - hw * 1.3, y1 + 1.5), lite)
	mk.quad_c(Vector2(px, ym), body, Vector2(px + wn, ym), shade, Vector2(px + hw * 1.3, y1 + 1.5), shade, Vector2(px, y1 + 1.5), body)


# ---------------------------------------------------------------- moving parts (every frame, only for caverns in view)
static func _pool(ci: CanvasItem, e: Dictionary, f: Dictionary, lvl: float, t: float, moving: bool) -> void:
	var q = int(round(lvl * 48.0))
	if q != e["pool_q"]:
		_build_pool(e, f, q / 48.0)
	if e["pool_mesh"] != null:
		ci.draw_mesh(e["pool_mesh"], null)
	if not moving:
		return
	# shimmer: short bright glints sliding along each stretch of surface
	for s in e["surf"]:
		var xl = s[0]
		var xr = s[1]
		var y = s[2]
		var span = xr - xl
		if span < 4.0:
			continue
		for k in 3:
			var u = fmod(k * 0.37 + t * (0.025 + 0.012 * k) * (1.0 if k % 2 == 0 else -1.0) + 10.0, 1.0)
			var x = xl + 2.0 + u * (span - 4.0)
			var a = 0.25 + 0.3 * (0.5 + 0.5 * sin(t * 2.3 + k * 2.1))
			var hl = min(5.0, span * 0.12)
			ci.draw_line(Vector2(x - hl, y + 0.6), Vector2(x + hl, y + 0.6), Color(0.85, 1.0, 1.0, a), 1.0)


static func _build_pool(e: Dictionary, f: Dictionary, lvl: float) -> void:
	e["pool_q"] = int(round(lvl * 48.0))
	e["pool_mesh"] = null
	e["surf"] = []
	var o: PoolVector2Array = e["outl"]
	var ymax = -1e9
	var xmin = 1e9
	var xmax = -1e9
	for p in o:
		ymax = max(ymax, p.y)
		xmin = min(xmin, p.x)
		xmax = max(xmax, p.x)
	var C = e["C"]
	var y_w = ymax - f.get("pool_d", 2.0) * C * lvl
	if ymax - y_w < 1.0:
		return
	var box = PoolVector2Array([Vector2(xmin - 4.0, y_w), Vector2(xmax + 4.0, y_w), Vector2(xmax + 4.0, ymax + 8.0), Vector2(xmin - 4.0, ymax + 8.0)])
	var polys = Geometry.intersect_polygons_2d(o, box)
	var mk = MK.new()
	_fill(mk, polys, Color(0.2, 0.42, 0.48, 0.66), Color(0.03, 0.09, 0.13, 0.9), y_w, ymax)
	for poly in polys:
		var xl = 1e9
		var xr = -1e9
		for p in poly:
			if abs(p.y - y_w) < 0.5:
				xl = min(xl, p.x)
				xr = max(xr, p.x)
		if xr - xl > 1.0:
			e["surf"].append([xl, xr, y_w])
			mk.quad(Vector2(xl, y_w), Vector2(xr, y_w), Vector2(xr, y_w + 1.0), Vector2(xl, y_w + 1.0), Color(0.62, 0.9, 0.95, 0.55))
			mk.quad_c(Vector2(xl, y_w + 1.0), Color(0.45, 0.8, 0.9, 0.22), Vector2(xr, y_w + 1.0), Color(0.45, 0.8, 0.9, 0.22),
				Vector2(xr, y_w + 4.0), Color(0.45, 0.8, 0.9, 0.0), Vector2(xl, y_w + 4.0), Color(0.45, 0.8, 0.9, 0.0))
	e["pool_mesh"] = mk.build()


static func _glow(ci: CanvasItem, e: Dictionary, t: float, zoom: float) -> void:
	var sz = max(1.5, 1.3 * zoom)
	var surf = e["surf"]
	for gw in e["glow"]:
		var p: Vector2 = gw[0]
		var k = 0.5 + 0.5 * sin(t * gw[2] + gw[1])
		var a = 0.3 + 0.7 * k * k * k
		ci.draw_rect(Rect2(p.x - sz * 0.5, p.y - sz * 0.5, sz, sz), Color(GLOW.r, GLOW.g, GLOW.b, a))
		# its reflection, where the pool lies under it
		for s in surf:
			if p.x > s[0] and p.x < s[1] and s[2] > p.y:
				var ry = 2.0 * s[2] - p.y
				if ry < gw[3] - 1.0:
					ci.draw_rect(Rect2(p.x - sz * 0.5, ry - sz * 0.5, sz, sz), Color(GLOW.r, GLOW.g, GLOW.b, a * 0.35))
				break


static func _drips(ci: CanvasItem, e: Dictionary, t: float, wet: float, zoom: float) -> void:
	var surf = e["surf"]
	var r0 = max(0.8, 0.6 * zoom)
	for d in e["drips"]:
		var tip: Vector2 = d[0]
		var land = d[1]
		for s in surf:
			if tip.x > s[0] and tip.x < s[1]:
				land = min(land, s[2])
		var dist = land - tip.y
		if dist < 3.0:
			continue
		var period = d[2] / (1.0 + 1.5 * wet)
		var u = fmod(t / period + d[3], 1.0) * period
		var form = period * 0.55
		var fall = sqrt(2.0 * dist / 420.0)
		var col = Color(0.75, 0.92, 1.0, 0.8)
		if u < form:
			var k = u / form
			ci.draw_circle(tip + Vector2(0, 0.3 + k * 0.9), r0 * (0.5 + 0.6 * k), col)
		elif u < form + fall:
			var s2 = u - form
			ci.draw_circle(tip + Vector2(0, 0.5 * 420.0 * s2 * s2 + 1.0), r0, col)
		elif u < form + fall + 0.45:
			var k2 = (u - form - fall) / 0.45
			var c2 = Color(col.r, col.g, col.b, 0.7 * (1.0 - k2))
			var rr = 1.0 + 4.0 * k2
			ci.draw_line(Vector2(tip.x - rr, land - 0.2), Vector2(tip.x - rr * 0.4, land - 0.2), c2, 1.0)
			ci.draw_line(Vector2(tip.x + rr * 0.4, land - 0.2), Vector2(tip.x + rr, land - 0.2), c2, 1.0)
