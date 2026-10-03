extends Reference
# Procedural creatures in the same chunky ink style as the ants: spiders, bees and hornets.
# Drawn straight onto a CanvasItem each frame (there are only ever a handful on screen), animated:
# the spider walks a diagonal gait with bobbing body, the bee hovers with blurred flapping wings.
# Local origin = the feet on the ground; +x is the way the creature faces, up is -y.

const INK = Color("#15121a")
const Rig = preload("res://mods-unpacked/Judah-InfDNA/content/colony/rig_art.gd")


static func _ell(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, rot: float = 0.0, segs: int = 18) -> void:
	var pts := PoolVector2Array()
	var cs = cos(rot)
	var sn = sin(rot)
	for i in segs:
		var a = TAU * i / segs
		var p = Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(c + Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs))
	ci.draw_colored_polygon(pts, col)


static func _ink(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, ow: float = 3.0, rot: float = 0.0) -> void:
	_ell(ci, c, rx + ow, ry + ow, INK, rot)
	_ell(ci, c, rx, ry, col, rot)


static func _limb(ci: CanvasItem, pts: PoolVector2Array, w: float, col: Color) -> void:
	ci.draw_polyline(pts, INK, w + 4.0, true)
	ci.draw_polyline(pts, col, w, true)


static func _tint(c: Color, shade: float, alpha: float, flash: bool) -> Color:
	var k = shade
	if flash:
		return Color(min(1.0, c.r * k + 0.35), c.g * k * 0.55, c.b * k * 0.55, alpha)
	return Color(c.r * k, c.g * k, c.b * k, alpha)


# A filled polygon with an ink outline.
static func _poly(ci: CanvasItem, pts: PoolVector2Array, fill: Color, ow: float = 2.4) -> void:
	var closed = PoolVector2Array(pts)
	closed.append(pts[0])
	ci.draw_polyline(closed, INK, ow * 2.0, true)
	ci.draw_colored_polygon(pts, fill)


# A limb or tail as a chain of tapering segments: all the ink first, then all the colour, so the joints join up without ink lines across them.
static func _bones(ci: CanvasItem, pts: PoolVector2Array, widths: PoolRealArray, col: Color, ow: float = 2.2) -> void:
	var n = pts.size()
	for pass_i in 2:
		for i in n - 1:
			var a = pts[i]
			var b = pts[i + 1]
			var d = b - a
			if d.length() < 0.01:
				continue
			var nn = Vector2(-d.y, d.x).normalized()
			var wa = widths[i] * 0.5 + (ow if pass_i == 0 else 0.0)
			var wb = widths[i + 1] * 0.5 + (ow if pass_i == 0 else 0.0)
			var c = INK if pass_i == 0 else col
			ci.draw_colored_polygon(PoolVector2Array([a + nn * wa, b + nn * wb, b - nn * wb, a - nn * wa]), c)
			ci.draw_circle(a, wa, c)
			if i == n - 2:
				ci.draw_circle(b, wb, c)


# Entry point used by enemy_view. `lift` raises flyers off the ground (px, before scale).
static func draw(art: String, ci: CanvasItem, feet: Vector2, scale: float, shade: float, alpha: float, t: float, facing: int, id: int, moving: bool, flash: bool, lift: float, mouth: float = -1.0) -> void:
	# the drawn creatures (the owner's art, rigged in rig_art.gd); the procedural ones below are the fallback when the art files are not there
	if art == "spider" or art == "voidmaw":
		var key = "spider" if art == "spider" else "void"
		if Rig.available(key):
			var m = mouth if mouth >= 0.0 else 0.18 + 0.12 * sin(t * 1.7 + id)
			Rig.draw(ci, key, feet, scale, facing, t + id * 0.7, moving, m, Color(shade, shade, shade, alpha), flash)
			return
	ci.draw_set_transform(feet, 0.0, Vector2(facing * scale, scale))
	match art:
		"spider":
			_spider(ci, t + id * 0.7, shade, alpha, moving, flash)
		"hornet":
			_bee(ci, t + id * 0.9, shade, alpha, moving, flash, lift, true)
		"anteater":
			_anteater(ci, t + id * 0.3, shade, alpha, moving, flash)
		"redant":
			_redant(ci, t + id * 0.6, shade, alpha, moving, flash)
		_:
			_bee(ci, t + id * 0.9, shade, alpha, moving, flash, lift, false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A butterfly flapping over the meadow. `pos` is its centre in world px; `c` the wing colour. Seen from above and slightly behind: the body is
# upright and tilted the way it flies, and the four wings spread out to the sides and close on a smooth beat (they narrow toward the body,
# they are never cut off).
const BF_FORE = [Vector2(1, -2), Vector2(9, -10), Vector2(19, -20), Vector2(26, -17), Vector2(25, -7), Vector2(17, 1), Vector2(2, 3)]
const BF_HIND = [Vector2(1, 2), Vector2(12, 2), Vector2(21, 8), Vector2(19, 17), Vector2(10, 19), Vector2(3, 11)]


static func _bf_wing(ci: CanvasItem, pts: Array, side: float, open: float, fill: Color, edge: Color) -> void:
	var poly := PoolVector2Array()
	for p in pts:
		poly.append(Vector2(p.x * side * open, p.y))
	if side < 0.0:
		poly.invert()           # mirrored: keep the winding the polygon filler expects
	ci.draw_colored_polygon(poly, fill)
	poly.append(poly[0])
	ci.draw_polyline(poly, edge, 1.8, true)


static func butterfly(ci: CanvasItem, pos: Vector2, scale: float, t: float, facing: int, c: Color, alpha: float) -> void:
	ci.draw_set_transform(pos, 0.45 * facing, Vector2(scale, scale))
	var open = 0.28 + 0.72 * (0.5 + 0.5 * cos(t * 8.0))
	var wing = Color(c.r, c.g, c.b, alpha)
	var hind = Color(c.r * 0.88, c.g * 0.88, c.b * 0.88, alpha)
	var dark = Color(c.r * 0.42, c.g * 0.42, c.b * 0.42, alpha)
	var pale = Color(1, 1, 1, 0.75 * alpha)
	for side in [-1.0, 1.0]:
		_bf_wing(ci, BF_HIND, side, open, hind, dark)
		_bf_wing(ci, BF_FORE, side, open, wing, dark)
		ci.draw_circle(Vector2(side * 18.0 * open, -11.0), 2.8 * (0.4 + 0.6 * open), pale)
		ci.draw_circle(Vector2(side * 13.0 * open, 11.0), 2.2 * (0.4 + 0.6 * open), dark.lightened(0.35))
	# the body over the wing roots, the head and the feelers
	ci.draw_line(Vector2(0.0, -6.0), Vector2(0.0, 16.0), INK, 5.0, true)
	ci.draw_line(Vector2(0.0, -6.0), Vector2(0.0, 16.0), dark.lightened(0.12), 3.0, true)
	ci.draw_circle(Vector2(0.0, -8.0), 3.2, INK)
	ci.draw_circle(Vector2(0.0, -8.0), 2.2, dark.lightened(0.25))
	ci.draw_polyline(PoolVector2Array([Vector2(-1.0, -10.0), Vector2(-4.0, -16.0), Vector2(-8.0, -18.0)]), INK, 1.4, true)
	ci.draw_polyline(PoolVector2Array([Vector2(1.0, -10.0), Vector2(4.0, -16.0), Vector2(8.0, -18.0)]), INK, 1.4, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A rival colony's ant, side-on, facing +x: saturated red with a dark gaster and black legs, so it is never mistaken for yours.
# About 75 px nose to tail before `scale`.
static func _redant(ci: CanvasItem, t: float, shade: float, alpha: float, moving: bool, flash: bool) -> void:
	var red = _tint(Color("#c63a2a"), shade, alpha, flash)
	var red_d = _tint(Color("#7e211a"), shade, alpha, flash)
	var red_l = _tint(Color("#e4604a"), shade, alpha, flash)
	var blk = _tint(Color("#2a1210"), shade, alpha, flash)
	var gait = 10.0 if moving else 1.8
	var bob = sin(t * gait * 2.0) * (1.4 if moving else 0.4)
	for side in 2:
		for i in 3:
			var ph = t * gait + i * 2.1 + side * PI
			var sw = sin(ph) * (8.0 if moving else 1.0)
			var lf = max(0.0, cos(ph)) * (6.0 if moving else 0.0)
			var ax = -4.0 + i * 8.0
			var hip = Vector2(ax, -17.0 + bob)
			var knee = Vector2(ax + (i - 1) * 6.0 + sw * 0.35, -31.0 - lf * 0.4)
			var foot = Vector2(ax + (i - 1) * 11.0 + sw, -lf)
			_limb(ci, PoolVector2Array([hip, knee, foot]), 2.4, blk if side == 0 else red_d)
	_ink(ci, Vector2(-30.0, -20.0 + bob), 19.0, 14.0, red_d, 2.8, 0.12)
	_ell(ci, Vector2(-32.0, -25.0 + bob), 8.0, 4.0, Color(1, 1, 1, 0.22 * alpha), 0.1, 8)
	_ink(ci, Vector2(-11.0, -17.0 + bob), 6.0, 5.0, red, 2.2)
	_ink(ci, Vector2(3.0, -19.0 + bob), 12.0, 10.0, red, 2.8)
	_ell(ci, Vector2(5.0, -23.0 + bob), 6.0, 3.0, red_l, 0.0, 8)
	_ink(ci, Vector2(24.0, -19.0 + bob), 11.0, 9.5, red, 2.8)
	ci.draw_circle(Vector2(29.0, -23.0 + bob), 3.3, INK)
	ci.draw_circle(Vector2(29.0, -23.0 + bob), 2.2, Color(1.0, 0.92, 0.7, alpha))
	ci.draw_circle(Vector2(29.8, -23.0 + bob), 1.0, INK)
	var open = 0.45 + 0.3 * sin(t * 6.0) if not moving else 0.3
	for sgn in [-1.0, 1.0]:
		var base = Vector2(34.0, -18.0 + bob + sgn * 3.0)
		ci.draw_colored_polygon(PoolVector2Array([base + Vector2(0, -2.4), base + Vector2(9.0, sgn * open * 8.0 - 1.5), base + Vector2(1.0, 2.4)]), INK)
		ci.draw_colored_polygon(PoolVector2Array([base + Vector2(0, -1.4), base + Vector2(7.0, sgn * open * 8.0 - 0.8), base + Vector2(1.0, 1.4)]), blk)
	var aw = sin(t * 4.0) * 2.0
	ci.draw_polyline(PoolVector2Array([Vector2(28.0, -27.0 + bob), Vector2(36.0, -36.0 + bob + aw), Vector2(46.0, -39.0 + bob + aw * 1.4)]), INK, 2.0, true)


# A giant anteater, side-on: shaggy grey-brown, a black shoulder stripe edged in white, a long sniffing snout, a bushy tail and big
# foreclaws. About 350 px from tail to snout before `scale`; it ambles on its knuckles. The tongue is a fx beam from the sim.
static func _spline(pts: Array, per: int) -> PoolVector2Array:
	var out := PoolVector2Array()
	var n = pts.size()
	for i in n:
		var p0: Vector2 = pts[(i + n - 1) % n]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n]
		for k in per:
			var u = float(k) / per
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u))
	return out


# The outline of a ribbon of varying width along a centre line (left edge out, right edge back).
static func _ribbon_poly(path: PoolVector2Array, widths: PoolRealArray) -> PoolVector2Array:
	var left := PoolVector2Array()
	var right := PoolVector2Array()
	var n = path.size()
	for i in n:
		var d = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
		var nn = Vector2(-d.y, d.x)
		left.append(path[i] + nn * widths[i] * 0.5)
		right.append(path[i] - nn * widths[i] * 0.5)
	for i in range(n - 1, -1, -1):
		left.append(right[i])
	return left


static func _anteater(ci: CanvasItem, t: float, shade: float, alpha: float, moving: bool, flash: bool) -> void:
	var fur = _tint(Color("#7d6c5a"), shade, alpha, flash)
	var fur_d = _tint(Color("#4a3f34"), shade, alpha, flash)
	var fur_l = _tint(Color("#b09a80"), shade, alpha, flash)
	var fur_dd = _tint(Color("#352c25"), shade, alpha, flash)
	var blk = _tint(Color("#241b17"), shade, alpha, flash)
	var wht = _tint(Color("#efe6d3"), shade, alpha, flash)
	var gait = 3.0 if moving else 0.7
	var bob = sin(t * gait * 2.0) * (2.6 if moving else 0.8)
	var by = -72.0 + bob
	var sn = sin(t * 2.3) * 4.0
	# the far legs first, in shadow
	for lg in 2:
		var front = lg == 0
		var ph = t * gait + (0.0 if front else PI) + PI
		var swing = sin(ph) * (12.0 if moving else 1.0)
		var lift = max(0.0, cos(ph)) * (10.0 if moving else 0.0)
		if front:
			var sh = Vector2(30.0, by + 18.0)
			var paw = Vector2(40.0 + swing, -lift)
			_bones(ci, PoolVector2Array([sh, Vector2(34.0 + swing * 0.4, by + 40.0), paw + Vector2(-3.0, -22.0), paw]), PoolRealArray([26.0, 20.0, 13.0, 12.0]), fur_dd, 2.4)
		else:
			var hip = Vector2(-54.0, by + 20.0)
			var heel = Vector2(-58.0 + swing, -lift - 6.0)
			_bones(ci, PoolVector2Array([hip, Vector2(-46.0 + swing * 0.3, by + 44.0), heel, heel + Vector2(26.0, 5.0 + lift * 0.1)]), PoolRealArray([34.0, 22.0, 12.0, 14.0]), fur_dd, 2.4)
	# the tail: a long bushy plume streaming back and down, swaying
	var sw = sin(t * 1.4) * 6.0
	var spine := PoolVector2Array()
	var wd := PoolRealArray()
	for k in 12:
		var u = float(k) / 11.0
		spine.append(Vector2(-80.0 - u * 118.0, by + 2.0 + u * u * 56.0 + sw * u * 0.7))
		wd.append(54.0 * (1.0 - u * 0.78) + 5.0 * sin(u * 10.0))
	var plume = _ribbon_poly(spine, wd)
	CA_plume(ci, plume, fur_d, fur, fur_l, spine, wd, sw, alpha)
	# the body: a shaggy outline, darker along the back, lighter along the belly
	var key = [Vector2(66.0, by - 30.0), Vector2(14.0, by - 44.0), Vector2(-38.0, by - 42.0), Vector2(-86.0, by - 24.0), Vector2(-90.0, by + 10.0), Vector2(-52.0, by + 38.0), Vector2(2.0, by + 44.0), Vector2(44.0, by + 40.0), Vector2(70.0, by + 26.0), Vector2(78.0, by + 0.0), Vector2(76.0, by - 18.0)]
	var body = _spline(key, 5)
	var cen = Vector2(-4.0, by)
	var shaggy := PoolVector2Array()
	for i in body.size():
		var q = body[i]
		if i % 2 == 0 and q.x < 62.0:
			q += (q - cen).normalized() * (3.5 + 2.0 * abs(sin(i * 1.7)))
		shaggy.append(q)
	_poly(ci, shaggy, fur, 3.4)
	_ell(ci, Vector2(8.0, by + 28.0), 64.0, 12.0, fur_l, 0.0, 16)
	_ell(ci, Vector2(-14.0, by - 32.0), 66.0, 11.0, fur_d, 0.04, 14)
	for k in 26:
		var fx0 = -76.0 + k * 5.6
		var fy0 = by - 30.0 + 16.0 * abs(sin(k * 2.3)) + (k % 3) * 8.0
		ci.draw_line(Vector2(fx0, fy0), Vector2(fx0 - 6.0, fy0 + 9.0), Color(0.12, 0.09, 0.06, 0.4 * alpha), 1.8, true)
	# the black shoulder stripe edged in white: one smooth band from the chest up and back across the shoulder to a point
	var sp := PoolVector2Array()
	var sw2 := PoolRealArray()
	for k in 14:
		var u = float(k) / 13.0
		var p0 = Vector2(74.0, by + 20.0)
		var p1 = Vector2(46.0, by - 34.0)
		var p2 = Vector2(-34.0, by - 36.0)
		sp.append((1.0 - u) * (1.0 - u) * p0 + 2.0 * (1.0 - u) * u * p1 + u * u * p2)
		sw2.append(max(1.0, 26.0 * sin(PI * pow(u, 0.5)) * (1.0 - 0.45 * u) + 4.0 * (1.0 - u)))
	var wide := PoolRealArray()
	for w in sw2:
		wide.append(w + 8.0)
	ci.draw_colored_polygon(_ribbon_poly(sp, wide), wht)
	ci.draw_colored_polygon(_ribbon_poly(sp, sw2), blk)
	# the near legs over the body
	for lg in 2:
		var front = lg == 0
		var ph2 = t * gait + (0.0 if front else PI)
		var swing2 = sin(ph2) * (12.0 if moving else 1.0)
		var lift2 = max(0.0, cos(ph2)) * (10.0 if moving else 0.0)
		if front:
			var sh2 = Vector2(36.0, by + 16.0)
			var paw2 = Vector2(46.0 + swing2, -lift2)
			_bones(ci, PoolVector2Array([sh2, Vector2(40.0 + swing2 * 0.4, by + 40.0), paw2 + Vector2(-3.0, -22.0), paw2]), PoolRealArray([28.0, 22.0, 14.0, 13.0]), fur, 2.6)
			for c in 3:
				var cb = paw2 + Vector2(-3.0 + c * 5.5, -2.0)
				var claw = PoolVector2Array([cb, cb + Vector2(7.0, 4.0 + c), cb + Vector2(11.0, 11.0 + c * 2.0)])
				ci.draw_polyline(claw, INK, 5.0, true)
				ci.draw_polyline(claw, wht, 2.4, true)
		else:
			var hip2 = Vector2(-48.0, by + 18.0)
			var heel2 = Vector2(-52.0 + swing2, -lift2 - 6.0)
			_bones(ci, PoolVector2Array([hip2, Vector2(-40.0 + swing2 * 0.3, by + 44.0), heel2, heel2 + Vector2(28.0, 5.0 + lift2 * 0.1)]), PoolRealArray([36.0, 24.0, 13.0, 15.0]), fur, 2.6)
	# the head: a small skull, a long tapering snout that sniffs, a bead of an eye and a round ear
	var hd = Vector2(90.0, by - 14.0)
	_ink(ci, hd + Vector2(-14.0, -20.0), 8.0, 10.0, fur_d, 2.2, -0.4)
	_ell(ci, hd + Vector2(-14.0, -19.0), 4.0, 6.0, fur_l, -0.4, 8)
	_ink(ci, hd, 25.0, 22.0, fur, 3.4, 0.1)
	_ell(ci, hd + Vector2(-4.0, 10.0), 16.0, 6.0, fur_l, 0.1, 10)
	var snout_pts = PoolVector2Array([hd + Vector2(8.0, -2.0), hd + Vector2(36.0, 8.0 + sn * 0.3), hd + Vector2(64.0, 20.0 + sn * 0.7), hd + Vector2(80.0, 27.0 + sn)])
	_bones(ci, snout_pts, PoolRealArray([28.0, 17.0, 10.0, 7.0]), fur_l, 3.0)
	ci.draw_line(hd + Vector2(14.0, 9.0), hd + Vector2(78.0, 28.0 + sn), fur_d, 1.8, true)
	ci.draw_line(hd + Vector2(12.0, -6.0), hd + Vector2(70.0, 18.0 + sn * 0.8), Color(1, 1, 1, 0.18 * alpha), 2.0, true)
	_ink(ci, hd + Vector2(81.0, 27.0 + sn), 4.6, 3.8, blk, 1.6, 0.4)
	ci.draw_circle(hd + Vector2(10.0, -8.0), 5.2, INK)
	ci.draw_circle(hd + Vector2(10.0, -8.0), 3.5, Color(0.96, 0.92, 0.82, alpha))
	ci.draw_circle(hd + Vector2(11.0, -8.0), 1.8, INK)
	ci.draw_circle(hd + Vector2(9.0, -10.0), 0.9, Color(1, 1, 1, 0.9 * alpha))


# The anteater's tail: ink, a dark plume, a lighter one inside it, and streaming hairs.
static func CA_plume(ci: CanvasItem, plume: PoolVector2Array, dark: Color, mid: Color, light: Color, spine: PoolVector2Array, wd: PoolRealArray, sw: float, alpha: float) -> void:
	_poly(ci, plume, dark, 3.4)
	var inner := PoolRealArray()
	for w in wd:
		inner.append(w * 0.55)
	ci.draw_colored_polygon(_ribbon_poly(spine, inner), mid)
	for k in 14:
		var u = float(k) / 13.0
		var i = int(u * (spine.size() - 1))
		var a0 = spine[i] + Vector2(0.0, -wd[i] * 0.3)
		ci.draw_line(a0, a0 + Vector2(-14.0, 12.0 + u * 8.0), light, 1.8, true)
		var a1 = spine[i] + Vector2(0.0, wd[i] * 0.25)
		ci.draw_line(a1, a1 + Vector2(-12.0, 11.0), Color(0.1, 0.07, 0.05, 0.45 * alpha), 1.6, true)


static func _spider(ci: CanvasItem, t: float, shade: float, alpha: float, moving: bool, flash: bool) -> void:
	var body = _tint(Color("#3d2f2a"), shade, alpha, flash)
	var body_hi = _tint(Color("#5a463d"), shade, alpha, flash)
	var abd = _tint(Color("#4d3529"), shade, alpha, flash)
	var mark = _tint(Color("#e0a93c"), shade, alpha, flash)
	var leg_n = _tint(Color("#2f2420"), shade, alpha, flash)
	var leg_f = _tint(Color("#1e1715"), shade, alpha, flash)
	var gait = 7.0 if moving else 1.4
	var bob = sin(t * gait * 2.0) * (2.2 if moving else 0.8)
	var rise = 30.0 + bob
	# eight legs: four on the near side, four on the far side drawn darker and behind
	for side in 2:
		for i in 4:
			var ph = t * gait + i * 1.57 + side * PI
			var swing = sin(ph) * (9.0 if moving else 1.5)
			var lift = max(0.0, cos(ph)) * (9.0 if moving else 1.0)
			var ax = 4.0 + i * 4.5 + side * 2.0
			var a = Vector2(ax, -rise - 4.0 + bob * 0.5)
			var reach = -42.0 + i * 26.0 + (side * 5.0)
			var foot = Vector2(ax + reach + swing, -lift)
			var knee = Vector2(ax + reach * 0.45 + (i - 1.5) * 4.0, -rise - 30.0 - abs(reach) * 0.12 - lift * 0.4)
			var pts = PoolVector2Array([a, knee, foot])
			_limb(ci, pts, 3.2, leg_f if side == 0 else leg_n)
			if side == 1:
				ci.draw_circle(knee, 2.4, body_hi)
		# the far-side legs go first, so draw order is side 0 then 1
	# abdomen with the hourglass mark, then cephalothorax and head
	_ink(ci, Vector2(-26, -rise - 6.0 + bob * 0.6), 27.0, 22.0, abd, 3.4, -0.1)
	_ell(ci, Vector2(-30, -rise - 8.0), 5.0, 9.0, mark, 0.0, 10)
	_ell(ci, Vector2(-20, -rise - 6.0), 5.0, 9.0, mark, 0.0, 10)
	_ell(ci, Vector2(-26, -rise - 15.0), 14.0, 6.0, _tint(Color("#6a4d3a"), shade, alpha * 0.6, flash), 0.0, 12)
	_ink(ci, Vector2(14, -rise - 2.0 + bob * 0.4), 17.0, 13.0, body, 3.2, 0.1)
	_ell(ci, Vector2(10, -rise - 8.0), 8.0, 5.0, body_hi, 0.0, 10)
	# eyes and fangs
	var eye = Color(0.95, 0.95, 0.9, alpha)
	var pup = Color(0.05, 0.04, 0.05, alpha)
	for e in [[Vector2(25, -rise - 9.0), 4.4], [Vector2(19, -rise - 11.0), 3.6], [Vector2(28, -rise - 3.0), 2.4], [Vector2(22, -rise - 4.0), 2.2]]:
		ci.draw_circle(e[0], e[1] + 1.8, INK)
		ci.draw_circle(e[0], e[1], eye)
		ci.draw_circle(e[0] + Vector2(1.2, 0.4), e[1] * 0.5, pup)
	var fang = _tint(Color("#d8cdb8"), shade, alpha, flash)
	var fo = 0.8 * sin(t * 6.0) if moving else 0.0
	for f in [-1.0, 1.0]:
		var fp = Vector2(31.0 + f * 1.0, -rise + 4.0 + f * 2.0)
		ci.draw_colored_polygon(PoolVector2Array([fp + Vector2(-2.6, -3), fp + Vector2(2.6, -3), fp + Vector2(0.6 + fo, 7.0)]), INK)
		ci.draw_colored_polygon(PoolVector2Array([fp + Vector2(-1.4, -2), fp + Vector2(1.4, -2), fp + Vector2(0.6 + fo, 5.0)]), fang)


static func _bee(ci: CanvasItem, t: float, shade: float, alpha: float, moving: bool, flash: bool, lift: float, hornet: bool) -> void:
	var y1 = _tint(Color("#e8892b") if hornet else Color("#f4c632"), shade, alpha, flash)
	var y2 = _tint(Color("#f2b04a") if hornet else Color("#ffe27a"), shade, alpha, flash)
	var blk = _tint(Color("#2a2220"), shade, alpha, flash)
	var fuzz = _tint(Color("#3a2e26"), shade, alpha, flash)
	var hover = 20.0 + lift
	var bob = sin(t * 9.0) * (3.0 if lift > 1.0 else 0.8)
	var cy = -hover + bob
	var tilt = -0.18 if moving else -0.05
	# legs dangle, wings behind the body first
	for k in 3:
		var lx = -2.0 + k * 6.0
		_limb(ci, PoolVector2Array([Vector2(lx, cy + 6.0), Vector2(lx + 3.0, cy + 12.0 + sin(t * 7.0 + k) * 1.5), Vector2(lx + 1.0 + (k - 1) * 3.0, cy + 18.0)]), 1.8, fuzz)
	var beat = sin(t * (60.0 if lift > 1.0 else 24.0))
	var spread = 0.55 + 0.45 * beat
	for w in 2:
		var wr = -1.15 + w * 0.5 + spread * (0.9 - 0.3 * w)
		var wl = 24.0 - w * 5.0
		var root = Vector2(3.0, cy - 8.0)
		var ang = -PI * 0.5 - wr * 0.0 + (-0.35 - w * 0.45) * (0.4 + 0.6 * spread)
		var tip = root + Vector2(cos(ang), sin(ang)) * wl
		var mid = (root + tip) * 0.5
		var wa = Color(0.9, 0.95, 1.0, 0.5 * alpha)
		_ell(ci, mid, wl * 0.5 + 1.5, 6.0 + (1 - w) * 2.0, Color(0.1, 0.1, 0.15, 0.45 * alpha), ang)
		_ell(ci, mid, wl * 0.5, 5.0 + (1 - w) * 2.0, wa, ang)
	# abdomen with stripes, thorax, head
	var ab = Vector2(-13.0, cy + 1.0)
	_ink(ci, ab, 16.0, 10.5, y1, 3.0, tilt)
	for s in 3:
		_ell(ci, ab + Vector2(-9.0 + s * 8.0, 0), 2.8, 9.6, blk, tilt, 8)
	ci.draw_colored_polygon(PoolVector2Array([ab + Vector2(-16.0, -2.0), ab + Vector2(-27.0, 1.5), ab + Vector2(-16.0, 3.0)]), INK)
	ci.draw_colored_polygon(PoolVector2Array([ab + Vector2(-16.0, -1.0), ab + Vector2(-24.0, 1.5), ab + Vector2(-16.0, 2.0)]), blk)
	_ink(ci, Vector2(7.0, cy - 1.0), 10.0, 9.0, fuzz, 3.0)
	_ell(ci, Vector2(8.0, cy - 5.0), 6.0, 3.2, y2, 0.0, 10)
	_ink(ci, Vector2(18.0, cy + 1.0), 7.5, 7.0, blk, 2.8)
	var eye = Color(0.95, 0.95, 0.9, alpha)
	ci.draw_circle(Vector2(21.0, cy - 1.0), 3.4, INK)
	ci.draw_circle(Vector2(21.0, cy - 1.0), 2.5, eye)
	ci.draw_circle(Vector2(21.8, cy - 0.8), 1.2, Color(0.05, 0.05, 0.06, alpha))
	_limb(ci, PoolVector2Array([Vector2(22.0, cy - 5.0), Vector2(27.0, cy - 11.0), Vector2(32.0, cy - 10.0 + sin(t * 5.0) * 1.5)]), 1.6, blk)


# A bird of prey seen side-on, facing +x, origin at the body centre. `flap` 0..1 is how raised the wings are, `fold` 0..1 tucks them
# for a stoop (talons forward). About 250 px across before `scale`: the size of a small cloud next to an ant.
static func bird(ci: CanvasItem, pos: Vector2, scale: float, t: float, facing: int, fold: float, alpha: float) -> void:
	ci.draw_set_transform(pos, 0.0, Vector2(facing * scale, scale))
	var flap = 0.5 + 0.5 * sin(t * 9.0)
	var body = Color(0.36, 0.29, 0.24, alpha)
	var dark = Color(0.24, 0.19, 0.16, alpha)
	var belly = Color(0.82, 0.74, 0.58, alpha)
	var beak = Color(0.95, 0.66, 0.2, alpha)
	var ink = Color(INK.r, INK.g, INK.b, alpha)
	# the wing on the far side first, darker; then the tail; body; head; the near wing over everything
	for pass_n in 2:
		var near = pass_n == 1
		if near:
			_ell(ci, Vector2(-62, 6), 30.0, 12.0, dark, -0.25, 12)           # tail base
			var tail = PoolVector2Array([Vector2(-70, -2), Vector2(-150, -10 + 14.0 * fold), Vector2(-146, 14 + 10.0 * fold), Vector2(-68, 16)])
			ci.draw_colored_polygon(PoolVector2Array([tail[0] + Vector2(2, -3), tail[1] + Vector2(-5, -4), tail[2] + Vector2(-5, 5), tail[3] + Vector2(2, 4)]), ink)
			ci.draw_colored_polygon(tail, dark)
			for k in 3:
				ci.draw_line(Vector2(-78 - k * 4, 0 + k * 6), Vector2(-142, -2 + k * 9 + 6.0 * fold), Color(0.45, 0.36, 0.3, alpha), 2.0, true)
			_ink(ci, Vector2(0, 0), 78.0, 36.0, body, 3.4, 0.05)
			_ell(ci, Vector2(8, 15), 60.0, 18.0, belly, 0.06, 16)
			_ink(ci, Vector2(76, -16), 25.0, 23.0, body, 3.2)
			_ell(ci, Vector2(80, -4), 17.0, 11.0, belly, 0.0, 12)
			var bk = PoolVector2Array([Vector2(97, -20), Vector2(130, -10), Vector2(97, -4)])
			ci.draw_colored_polygon(PoolVector2Array([bk[0] + Vector2(-3, -4), bk[1] + Vector2(5, 0), bk[2] + Vector2(-3, 4)]), ink)
			ci.draw_colored_polygon(bk, beak)
			ci.draw_circle(Vector2(86, -26), 7.0, ink)
			ci.draw_circle(Vector2(86, -26), 5.0, Color(1.0, 0.95, 0.7, alpha))
			ci.draw_circle(Vector2(87.5, -26), 2.6, Color(0.05, 0.04, 0.05, alpha))
			ci.draw_line(Vector2(78, -41), Vector2(104, -34), ink, 4.0, true)   # a stern brow
			# talons: tucked in cruise, thrust forward and down in a stoop
			for k in 2:
				var lx = 8.0 + k * 14.0
				var foot = Vector2(lx + 44.0 * fold, 34.0 + 30.0 * fold)
				ci.draw_line(Vector2(lx, 30), foot, ink, 7.0, true)
				ci.draw_line(Vector2(lx, 30), foot, beak, 3.2, true)
				for c in 3:
					ci.draw_line(foot, foot + Vector2(10 + c * 4, 8 - c * 6), ink, 3.0, true)
		var ang = lerp(0.2 + 1.1 * flap, -0.55, fold) * (1.0 if near else 0.8)    # wing angle above horizontal
		var sh = Vector2(8, -22) + Vector2(0, 0 if near else -4)
		var tip = sh + Vector2(-26.0 - 10.0 * (1.0 - fold), -150.0 * sin(ang) * (1.0 - 0.45 * fold)) + Vector2(-60.0 * fold, 0)
		var axis = tip - sh
		var ad = axis.normalized()
		var an = Vector2(-ad.y, ad.x)
		if an.x > 0.0:
			an = -an           # the trailing edge always sweeps back toward the tail
		# leading edge shoulder -> tip, then back along the wider, tapering trailing edge: a simple outline in every pose
		# (a hand-placed outline crossed itself when the wings dropped and the polygon was refused)
		var us = [0.0, 0.3, 0.65, 1.0]
		var fwd = [8.0, 10.0, 8.0, 2.0]
		var chord = [62.0, 68.0, 48.0, 16.0]
		var wing = PoolVector2Array()
		for i in 4:
			wing.append(sh + axis * us[i] - an * fwd[i])
		for i in range(3, -1, -1):
			var qb = sh + axis * us[i] + an * chord[i]
			if i < 3 and i > 0:
				wing.append(sh + axis * (us[i] + 0.1) + an * (chord[i] + 9.0))     # a feather tip along the trailing edge
			wing.append(qb)
		var wc = body if near else dark
		var cen = Vector2.ZERO
		for q in wing:
			cen += q
		cen /= wing.size()
		var outer = PoolVector2Array()
		var inner = PoolVector2Array()
		for q in wing:
			outer.append(cen + (q - cen) * 1.05)
			inner.append(cen + (q - cen) * 0.94)
		ci.draw_colored_polygon(outer, ink)
		ci.draw_colored_polygon(inner, wc)
		for k in 5:      # primary feathers
			var u = 0.3 + 0.14 * k
			var f0 = sh + axis * u + an * 12.0
			ci.draw_line(f0, f0 + an * (38.0 - 3.0 * k) + ad * 5.0, Color(0.2, 0.15, 0.12, alpha * 0.7), 2.2, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
