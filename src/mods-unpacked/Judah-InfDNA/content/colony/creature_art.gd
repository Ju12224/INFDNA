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
		_:
			_bee(ci, t + id * 0.9, shade, alpha, moving, flash, lift, false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
