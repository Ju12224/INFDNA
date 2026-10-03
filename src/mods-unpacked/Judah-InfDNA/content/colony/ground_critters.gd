extends Reference
# Small ground life crawling over the meadow, for atmosphere: ladybirds, snails (they come out in the rain),
# caterpillars and grasshoppers. Each is drawn from the time and from the distance it has walked (so the legs never
# skate over the ground), in the same chunky ink style as creature_art.gd. Local origin = the feet on the ground,
# +x = the way it faces, up = -y. Nothing here touches the sim.

const CA = preload("res://mods-unpacked/Judah-InfDNA/content/colony/creature_art.gd")
const INK = Color("#15121a")
const KINDS = ["ladybird", "snail", "caterpillar", "grasshopper"]


# `walk` = distance travelled (px), `air` = 0..1 progress of a hop (grasshopper), `crouch` = 0..1 gathering for the jump.
static func draw(kind: String, ci: CanvasItem, feet: Vector2, scale: float, facing: int, t: float, walk: float, moving: bool, air: float = 0.0, crouch: float = 0.0, shade: float = 1.0) -> void:
	var rot = 0.0
	var lift = 0.0
	if kind == "grasshopper" and air > 0.0:
		rot = -facing * lerp(0.55, -0.5, air) * sin(PI * air)
		lift = sin(PI * air) * 44.0
	ci.draw_set_transform(feet + Vector2(0.0, -lift * scale), rot, Vector2(facing * scale, scale))
	match kind:
		"ladybird":
			_ladybird(ci, walk, moving, shade)
		"snail":
			_snail(ci, walk, t, moving, shade)
		"caterpillar":
			_caterpillar(ci, walk, moving, shade)
		_:
			_grasshopper(ci, t, air, crouch, shade)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _c(col: Color, shade: float) -> Color:
	return Color(col.r * shade, col.g * shade, col.b * shade, col.a)


static func _ladybird(ci: CanvasItem, walk: float, moving: bool, shade: float) -> void:
	var hop = abs(sin(walk * 0.5)) * 0.7 if moving else 0.0
	for i in 3:
		var lx = -4.5 + i * 4.5
		var sw = sin(walk * 0.55 + i * 2.1) * 2.4 if moving else 0.0
		ci.draw_line(Vector2(lx, -3.5 - hop), Vector2(lx + sw - 1.5, 0.0), INK, 2.2, true)
		ci.draw_line(Vector2(lx + 1.0, -3.5 - hop), Vector2(lx - sw + 2.0, 0.0), INK, 2.2, true)
	var red = _c(Color("#dd3b2d"), shade)
	CA._ink(ci, Vector2(-0.5, -6.8 - hop), 11.0, 7.6, red, 1.8)
	CA._ell(ci, Vector2(2.5, -11.0 - hop), 4.6, 1.8, Color(1, 1, 1, 0.5), -0.3, 8)
	for sp in [Vector2(-6.0, -7.5), Vector2(-0.5, -10.2), Vector2(5.0, -7.0)]:
		ci.draw_circle(sp + Vector2(0.0, -hop), 1.9, INK)
	CA._ink(ci, Vector2(10.0, -5.2 - hop), 4.2, 3.8, _c(Color("#2a2127"), shade), 1.4)
	ci.draw_circle(Vector2(11.6, -6.4 - hop), 1.1, Color.white)
	ci.draw_line(Vector2(12.5, -8.0 - hop), Vector2(16.0, -12.0 - hop + sin(walk * 0.3) * 0.8), INK, 1.2, true)


static func _snail(ci: CanvasItem, walk: float, t: float, moving: bool, shade: float) -> void:
	var st = 1.0 + (0.1 * sin(walk * 0.35) if moving else 0.0)
	var L = 30.0 * st
	var skin = _c(Color("#d2b992"), shade)
	var skin_d = _c(Color("#a68b64"), shade)
	var shell = _c(Color("#bb7d3d"), shade)
	var shell_d = _c(Color("#85521f"), shade)
	# the foot, a low soft body that stretches and gathers as it glides
	CA._ink(ci, Vector2(-L * 0.06, -3.6), L * 0.52, 4.2, skin, 1.8)
	CA._ink(ci, Vector2(-L * 0.52, -2.0), 6.5, 2.4, skin, 1.4)
	# the head rises at the front, with two eye stalks that sway
	CA._ink(ci, Vector2(L * 0.42, -8.5), 4.6, 7.2, skin, 1.8, 0.3)
	for e in 2:
		var sx = L * 0.46 + e * 3.4
		var tip = Vector2(sx + 3.5 + sin(t * 2.0 + e * 1.7) * 1.4, -20.0 - e * 1.6 + sin(t * 1.3 + e) * 0.8)
		ci.draw_line(Vector2(sx - 0.6, -12.0), tip, INK, 3.2, true)
		ci.draw_line(Vector2(sx - 0.6, -12.0), tip, skin_d, 1.5, true)
		ci.draw_circle(tip, 2.6, INK)
		ci.draw_circle(tip + Vector2(0.4, -0.2), 1.3, Color(0.95, 0.95, 0.9))
	# the shell: ink rim, a coil, a bright shine
	var sc = Vector2(-L * 0.14, -16.5)
	CA._ink(ci, sc, 12.6, 12.0, shell, 1.9)
	ci.draw_arc(sc + Vector2(1.0, 0.5), 8.6, 0.6, 5.8, 20, shell_d, 2.0, true)
	ci.draw_arc(sc + Vector2(1.6, 0.8), 5.0, 1.6, 6.4, 16, shell_d, 2.0, true)
	ci.draw_circle(sc + Vector2(1.5, 0.6), 1.5, shell_d)
	CA._ell(ci, sc + Vector2(3.6, -7.0), 4.4, 1.8, Color(1, 1, 1, 0.42), -0.3, 8)


static func _caterpillar(ci: CanvasItem, walk: float, moving: bool, shade: float) -> void:
	var n = 9
	var ph = walk * 0.16
	var pos := []
	var rad := []
	for i in n:
		var arch = max(0.0, sin(ph - i * 0.65)) if moving else 0.0
		pos.append(Vector2(-25.0 + i * 6.2 - arch * 1.2, -5.4 - arch * 5.2))
		rad.append(5.7 - (1.0 - float(i) / (n - 1)) * 1.0 if i < n - 1 else 6.6)
	for i in n:
		ci.draw_line(pos[i] + Vector2(0, rad[i] - 1.0), Vector2(pos[i].x + sin(walk * 0.5 + i) * 1.2, 0.0), INK, 2.0, true)
	for i in n:
		ci.draw_circle(pos[i], rad[i] + 1.7, INK)
	for i in n:
		var col = _c(Color("#90d04f") if i % 2 == 0 else Color("#6db83a"), shade)
		ci.draw_circle(pos[i], rad[i], col)
		ci.draw_circle(pos[i] + Vector2(1.0, -2.2), rad[i] * 0.42, Color(1, 1, 1, 0.32))
		if i % 3 == 1:
			ci.draw_circle(pos[i] + Vector2(0.0, -rad[i] * 0.45), 1.1, _c(Color("#f5d84a"), shade))
	var hd = pos[n - 1]
	ci.draw_circle(hd + Vector2(2.4, 0.4), 1.9, Color(0.95, 0.95, 0.9))
	ci.draw_circle(hd + Vector2(3.0, 0.6), 0.9, INK)
	ci.draw_line(hd + Vector2(3.0, -4.5), hd + Vector2(7.0, -10.0), INK, 1.3, true)


static func _grasshopper(ci: CanvasItem, t: float, air: float, crouch: float, shade: float) -> void:
	var green = _c(Color("#7fb336"), shade)
	var green_l = _c(Color("#a8d655"), shade)
	var green_d = _c(Color("#4e7a22"), shade)
	var olive = _c(Color("#657f2a"), shade)
	var belly = _c(Color("#e2da8c"), shade)
	var gold = _c(Color("#e9d56a"), shade)
	var wing_c = _c(Color("#93c04a"), shade)
	var folded = 1.0 - air
	var dip = crouch * 3.0 * folded
	var br = sin(t * 3.0) * 0.5
	# the far side first: a hind leg and two thin legs, darker
	_hind(ci, Vector2(1.0, -1.0), folded, air, dip, green_d, olive, shade)
	CA._bones(ci, PoolVector2Array([Vector2(10.0, -9.0 + dip), Vector2(14.0, -5.0), Vector2(15.0 - 3.0 * air, -1.0 - 6.0 * air)]), PoolRealArray([2.6, 2.2, 1.8]), olive, 1.6)
	# the folded hindwings fan open in the air
	if air > 0.15:
		var wa = clamp((air - 0.15) * 2.0, 0.0, 1.0)
		var fan = PoolVector2Array([Vector2(4.0, -20.0), Vector2(-4.0, -20.0 - 22.0 * wa), Vector2(-22.0, -22.0 - 20.0 * wa), Vector2(-33.0, -17.0 - 10.0 * wa), Vector2(-28.0, -15.0)])
		CA._poly(ci, fan, Color(1.0, 0.95, 0.72, 0.6 * wa), 1.4)
		for k in 3:
			ci.draw_line(Vector2(4.0, -20.0), fan[1 + k], Color(0.45, 0.4, 0.2, 0.5 * wa), 1.0, true)
	# the long tapering abdomen with its rings, the thorax and its saddle, the blunt head
	var ab = PoolVector2Array([Vector2(3.0, -19.0 + dip), Vector2(-8.0, -20.5 + dip + br), Vector2(-20.0, -19.0 + dip + br), Vector2(-32.0, -15.5 + dip), Vector2(-38.0, -11.0 + dip), Vector2(-34.0, -8.0 + dip), Vector2(-24.0, -8.5 + dip), Vector2(-12.0, -9.0 + dip), Vector2(1.0, -9.5 + dip)])
	CA._poly(ci, ab, green, 2.0)
	CA._ell(ci, Vector2(-14.0, -10.6 + dip), 15.0, 2.2, belly, 0.03, 12)
	CA._ell(ci, Vector2(-12.0, -19.0 + dip + br), 14.0, 1.5, green_l, 0.0, 10)
	for k in 5:
		var rx = -7.0 - k * 6.2
		ci.draw_line(Vector2(rx, -20.0 + dip + k * 1.1), Vector2(rx + 1.2, -9.5 + dip), Color(green_d.r, green_d.g, green_d.b, 0.5), 1.2, true)
	var thorax = PoolVector2Array([Vector2(-3.0, -19.5 + dip), Vector2(5.0, -22.5 + dip), Vector2(13.0, -21.5 + dip), Vector2(16.0, -16.0 + dip), Vector2(13.0, -10.0 + dip), Vector2(0.0, -9.5 + dip)])
	CA._poly(ci, thorax, green, 2.0)
	CA._ell(ci, Vector2(6.0, -19.5 + dip), 8.0, 1.8, green_l, -0.1, 10)
	ci.draw_line(Vector2(-2.0, -20.0 + dip), Vector2(14.0, -20.0 + dip), Color(green_d.r, green_d.g, green_d.b, 0.7), 1.4, true)
	var head = PoolVector2Array([Vector2(13.0, -21.5 + dip), Vector2(20.0, -23.0 + dip), Vector2(26.0, -19.0 + dip), Vector2(27.5, -12.5 + dip), Vector2(23.0, -8.0 + dip), Vector2(15.0, -9.0 + dip), Vector2(13.0, -14.0 + dip)])
	CA._poly(ci, head, green, 2.0)
	CA._ell(ci, Vector2(20.0, -21.0 + dip), 5.0, 1.4, green_l, 0.0, 8)
	ci.draw_line(Vector2(26.5, -13.0 + dip), Vector2(23.0, -9.5 + dip), green_d, 1.6, true)
	# the big eye
	CA._ell(ci, Vector2(21.5, -16.8 + dip), 4.6, 5.4, INK, 0.0, 14)
	CA._ell(ci, Vector2(21.5, -16.8 + dip), 3.6, 4.4, gold, 0.0, 14)
	ci.draw_circle(Vector2(22.4, -16.4 + dip), 1.7, INK)
	ci.draw_circle(Vector2(21.0, -18.4 + dip), 1.0, Color(1, 1, 0.9, 0.9))
	# the folded forewing lies along the back, longer than the abdomen
	var fw = PoolVector2Array([Vector2(8.0, -22.0 + dip), Vector2(-6.0, -24.0 + dip), Vector2(-22.0, -22.5 + dip), Vector2(-38.0, -17.5 + dip), Vector2(-44.0, -14.5 + dip), Vector2(-38.0, -12.8 + dip), Vector2(-22.0, -15.0 + dip), Vector2(-6.0, -17.0 + dip), Vector2(6.0, -18.0 + dip)])
	CA._poly(ci, fw, wing_c, 1.8)
	ci.draw_polyline(PoolVector2Array([Vector2(6.0, -20.0 + dip), Vector2(-14.0, -20.5 + dip), Vector2(-36.0, -15.5 + dip)]), Color(green_d.r, green_d.g, green_d.b, 0.8), 1.2, true)
	for k in 4:
		ci.draw_line(Vector2(-4.0 - k * 9.0, -21.5 + dip + k * 1.0), Vector2(-9.0 - k * 9.0, -15.5 + dip + k * 0.7), Color(green_d.r, green_d.g, green_d.b, 0.45), 1.0, true)
	# the near side: two front legs, the great hind leg over everything
	CA._bones(ci, PoolVector2Array([Vector2(7.0, -9.0 + dip), Vector2(10.0, -5.0), Vector2(11.0 - 3.0 * air, -1.0 - 6.0 * air)]), PoolRealArray([2.8, 2.3, 1.9]), green, 1.7)
	CA._bones(ci, PoolVector2Array([Vector2(12.0, -9.0 + dip), Vector2(17.0, -5.5), Vector2(19.0 - 3.0 * air, -1.0 - 6.0 * air)]), PoolRealArray([2.8, 2.3, 1.9]), green, 1.7)
	_hind(ci, Vector2.ZERO, folded, air, dip, green, green_l, shade)
	# the feelers
	var tw = sin(t * 5.0) * 1.4
	CA._limb(ci, PoolVector2Array([Vector2(24.0, -22.0 + dip), Vector2(31.0, -30.0 + dip + tw), Vector2(41.0, -32.0 + dip + tw * 1.6)]), 0.9, olive)


# The great jumping leg: a thick thigh folded up behind the body, the shin tucked back down; it straightens in the air.
static func _hind(ci: CanvasItem, off: Vector2, folded: float, air: float, dip: float, col: Color, col_s: Color, shade: float) -> void:
	var hip = Vector2(-2.0, -12.0 + dip) + off
	var knee = hip.linear_interpolate(Vector2(-21.0, -25.0 + dip) + off, folded) + Vector2(-16.0, 4.0) * air
	var foot = Vector2(-8.0, 0.0).linear_interpolate(Vector2(-36.0, 0.0), air) + Vector2(0.0, -8.0) * air + off
	var mid = (hip + knee) * 0.5 + Vector2(0.0, -2.0 - 2.0 * folded)
	CA._bones(ci, PoolVector2Array([hip, mid, knee]), PoolRealArray([9.0, 7.0, 3.0]), col, 2.0)
	var dir = (knee - hip).normalized()
	var nrm = Vector2(-dir.y, dir.x)
	for k in 3:
		var q = hip.linear_interpolate(knee, 0.3 + 0.2 * k)
		ci.draw_line(q - nrm * 2.4, q + nrm * 1.2 + dir * 2.4, Color(0.2, 0.3, 0.08, 0.55), 1.2, true)
	var smid = (knee + foot) * 0.5 + Vector2(-2.0, 0.0) * folded
	CA._bones(ci, PoolVector2Array([knee, smid, foot]), PoolRealArray([3.2, 2.6, 2.0]), col_s, 1.6)
	for k in 3:
		var q2 = knee.linear_interpolate(foot, 0.3 + 0.2 * k)
		ci.draw_line(q2, q2 + Vector2(-2.4, -1.2), INK, 1.0, true)
	ci.draw_line(foot, foot + Vector2(-4.0, 0.0), INK, 2.2, true)
	ci.draw_line(foot, foot + Vector2(3.0, 0.0), INK, 2.2, true)
