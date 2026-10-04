extends Reference
# The creatures: every one is the owner's drawn art, rigged and animated by rig_art.gd. The only drawn-in-code creature left is the
# anteater, which has no picture yet. Local origin = the feet on the ground; +x is the way the creature faces, up is -y.

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


# Creature names whose rig in the art manifests has another name.
const RIG_NAMES = {"voidmaw": "void", "redant": "redant_small"}


# Entry point used by enemy_view. `lift` raises flyers off the ground (px, before scale).
static func draw(art: String, ci: CanvasItem, feet: Vector2, scale: float, shade: float, alpha: float, t: float, facing: int, id: int, moving: bool, flash: bool, lift: float, mouth: float = -1.0) -> void:
	# the drawn creatures (the owner's art, rigged in rig_art.gd); the procedural ones below are the fallback when the art files are not there
	var key = RIG_NAMES.get(art, art)
	if Rig.available(key):
		var m = mouth if mouth >= 0.0 else 0.18 + 0.12 * sin(t * 1.7 + id)
		Rig.draw(ci, key, feet - Vector2(0.0, lift * scale), scale, facing, t + id * 0.7, moving, m, Color(shade, shade, shade, alpha), flash)
		return
	if art != "anteater":
		return          # no picture: nothing is drawn (the old drawn creatures are gone; the anteater keeps its drawing until it has a picture)
	ci.draw_set_transform(feet, 0.0, Vector2(facing * scale, scale))
	_anteater(ci, t + id * 0.3, shade, alpha, moving, flash)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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

