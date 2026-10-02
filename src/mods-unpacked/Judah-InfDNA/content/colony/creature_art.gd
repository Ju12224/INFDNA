extends Reference
# Procedural creatures in the same chunky ink style as the ants: spiders, bees and hornets.
# Drawn straight onto a CanvasItem each frame (there are only ever a handful on screen), animated:
# the spider walks a diagonal gait with bobbing body, the bee hovers with blurred flapping wings.
# Local origin = the feet on the ground; +x is the way the creature faces, up is -y.

const INK = Color("#15121a")


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


# Entry point used by enemy_view. `lift` raises flyers off the ground (px, before scale).
static func draw(art: String, ci: CanvasItem, feet: Vector2, scale: float, shade: float, alpha: float, t: float, facing: int, id: int, moving: bool, flash: bool, lift: float) -> void:
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


# A butterfly flapping over the meadow. `pos` is its centre in world px; `c` the wing colour.
static func butterfly(ci: CanvasItem, pos: Vector2, scale: float, t: float, facing: int, c: Color, alpha: float) -> void:
	ci.draw_set_transform(pos, 0.0, Vector2(facing * scale, scale))
	var flap = abs(sin(t * 9.0))
	var wing = Color(c.r, c.g, c.b, alpha)
	var dark = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, alpha)
	# two wing pairs, seen side-on so they open and close as they flap
	var w = 10.0 * (0.25 + 0.75 * flap)
	_ink(ci, Vector2(-5.0, -w * 0.5), 8.0, w, wing, 1.6, -0.5)
	_ink(ci, Vector2(-8.0, w * 0.35), 6.0, w * 0.7, dark.lightened(0.25), 1.4, 0.4)
	_ell(ci, Vector2(-6.0, -w * 0.5), 2.2, w * 0.45, Color(1, 1, 1, 0.55 * alpha), -0.5, 8)
	ci.draw_line(Vector2(-3.0, 0.0), Vector2(5.0, 0.0), INK, 3.4, true)
	ci.draw_line(Vector2(-3.0, 0.0), Vector2(5.0, 0.0), dark, 1.8, true)
	ci.draw_circle(Vector2(6.0, -0.5), 2.2, INK)
	ci.draw_line(Vector2(6.0, -1.5), Vector2(10.0, -5.0), INK, 1.2, true)
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
# foreclaws. About 320 px from tail to snout before `scale`; it ambles on its knuckles. The tongue is a fx beam from the sim.
static func _anteater(ci: CanvasItem, t: float, shade: float, alpha: float, moving: bool, flash: bool) -> void:
	var fur = _tint(Color("#7b6b5a"), shade, alpha, flash)
	var fur_d = _tint(Color("#4f4337"), shade, alpha, flash)
	var fur_l = _tint(Color("#a8957c"), shade, alpha, flash)
	var blk = _tint(Color("#211a17"), shade, alpha, flash)
	var wht = _tint(Color("#ede3cf"), shade, alpha, flash)
	var gait = 3.0 if moving else 0.7
	var bob = sin(t * gait * 2.0) * (2.6 if moving else 0.8)
	var by = -68.0 + bob
	var sn = sin(t * 2.3) * 4.0
	# the legs on the far side first, darker; then the tail and body; the near legs over them; head and snout last
	for side in 2:
		var near = side == 1
		if near:
			# the long bushy tail trailing behind and down, swaying a little: one tapering plume with streaming hair
			var sw = sin(t * 1.4) * 5.0
			var top := PoolVector2Array()
			var bot := PoolVector2Array()
			for k in 8:
				var u = float(k) / 7.0
				var spine = Vector2(-78.0 - u * 108.0, by + 2.0 + u * u * 50.0 + sw * u * 0.6)
				var wd = 26.0 * (1.0 - u * 0.55) + 4.0 * sin(u * 9.0)
				top.append(spine + Vector2(0.0, -wd))
				bot.append(spine + Vector2(0.0, wd * 0.8))
			var plume := PoolVector2Array()
			for q in top:
				plume.append(q)
			for q in range(bot.size() - 1, -1, -1):
				plume.append(bot[q])
			var plume_ink := PoolVector2Array()
			var pc = Vector2(-150.0, by + 20.0)
			for q in plume:
				plume_ink.append(pc + (q - pc) * 1.07)
			ci.draw_colored_polygon(plume_ink, INK)
			ci.draw_colored_polygon(plume, fur_d)
			for k in 11:
				var u2 = float(k) / 10.0
				var a0 = Vector2(-84.0 - u2 * 96.0, by - 18.0 + u2 * u2 * 50.0 + sw * u2 * 0.6)
				ci.draw_line(a0, a0 + Vector2(-12.0, 11.0), fur_l, 1.8, true)
				ci.draw_line(a0 + Vector2(0.0, 12.0), a0 + Vector2(-10.0, 22.0), fur, 1.6, true)
			_ink(ci, Vector2(0.0, by), 88.0, 42.0, fur, 3.6, 0.0)
			_ell(ci, Vector2(10.0, by + 24.0), 66.0, 14.0, fur_l, 0.0, 16)
			_ell(ci, Vector2(-8.0, by - 24.0), 70.0, 12.0, fur_d, 0.0, 14)
			# the black shoulder stripe with its white edge
			ci.draw_colored_polygon(PoolVector2Array([Vector2(60.0, by + 32.0), Vector2(84.0, by + 6.0), Vector2(44.0, by - 44.0), Vector2(-40.0, by - 34.0)]), wht)
			ci.draw_colored_polygon(PoolVector2Array([Vector2(58.0, by + 27.0), Vector2(77.0, by + 6.0), Vector2(41.0, by - 38.0), Vector2(-30.0, by - 31.0)]), blk)
			for k in 12:
				var fx0 = -64.0 + k * 9.5
				var fy0 = by - 38.0 + abs(sin(k * 1.7)) * 8.0
				ci.draw_line(Vector2(fx0, fy0), Vector2(fx0 - 5.0, fy0 + 9.0), Color(0.1, 0.07, 0.05, 0.45 * alpha), 2.0, true)
		for lg in 2:
			var front = lg == 0
			var ph = t * gait + (0.0 if front else PI) + (PI if near else 0.0)
			var swing = sin(ph) * (11.0 if moving else 1.0)
			var lift = max(0.0, cos(ph)) * (9.0 if moving else 0.0)
			var hip = Vector2(34.0 if front else -48.0, by + 20.0)
			var foot = Vector2(hip.x + 8.0 + swing, -lift)
			var col = fur if near else fur_d
			_limb(ci, PoolVector2Array([hip, Vector2(hip.x + 3.0, (hip.y + foot.y) * 0.5 + 6.0), foot]), 15.0 if front else 17.0, col)
			if front:
				for c in 3:
					var cb = foot + Vector2(-2.0 + c * 5.0, -2.0)
					ci.draw_polyline(PoolVector2Array([cb, cb + Vector2(7.0, 3.0 + c), cb + Vector2(11.0, 9.0 + c * 2.0)]), INK, 4.6, true)
					ci.draw_polyline(PoolVector2Array([cb, cb + Vector2(7.0, 3.0 + c), cb + Vector2(11.0, 9.0 + c * 2.0)]), wht, 2.2, true)
	# head: a small skull, a long tube of a snout that sniffs, a tiny eye and ear
	var hd = Vector2(96.0, by - 14.0)
	_ink(ci, hd, 24.0, 22.0, fur, 3.2, 0.1)
	var snout = PoolVector2Array([hd + Vector2(8.0, -14.0), hd + Vector2(70.0, 14.0 + sn), hd + Vector2(72.0, 24.0 + sn), hd + Vector2(10.0, 12.0)])
	var big = PoolVector2Array([snout[0] + Vector2(-2.0, -3.4), snout[1] + Vector2(3.4, -3.0), snout[2] + Vector2(3.4, 3.4), snout[3] + Vector2(-2.0, 3.4)])
	ci.draw_colored_polygon(big, INK)
	ci.draw_colored_polygon(snout, fur_l)
	ci.draw_line(hd + Vector2(12.0, 6.0), hd + Vector2(70.0, 20.0 + sn), fur_d, 2.0, true)
	_ell(ci, hd + Vector2(72.0, 21.0 + sn), 5.0, 4.0, blk, 0.0, 8)
	_ink(ci, hd + Vector2(-12.0, -18.0), 7.0, 10.0, fur_d, 2.0, -0.4)
	ci.draw_circle(hd + Vector2(8.0, -6.0), 5.0, INK)
	ci.draw_circle(hd + Vector2(8.0, -6.0), 3.4, Color(0.95, 0.9, 0.8, alpha))
	ci.draw_circle(hd + Vector2(9.0, -6.0), 1.6, INK)


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
