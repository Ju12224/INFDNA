extends Node2D
# Paints a genome as a side-view ant in Brotato's style. v0.19 art pass:
# real ant anatomy (teardrop gaster, humped mesosoma, tilted head), a low
# crouched stance with six visible legs (near + far side), tapered jointed
# limbs, curved toothed mandibles, beaded elbowed antennae, glossy chitin
# shading, and veined wings folded over the back.
# Draw groups run back to front; each group does ink -> fill -> detail, so
# parts inside a group share one unified heavy outline:
#   far side (legs, antenna, mandible) -> near legs -> body -> near head parts -> wings
# Origin = feet; the body extends upward and is centered horizontally.
# Public interface unchanged: genome, paint_scale, anim_t, gait.

const INK = Color("#15121a")
const OL = 7.0

var genome = null
var paint_scale := 0.5
var anim_t := 0.0
var gait := 0.0          # 0..1 walk-cycle phase (baked into animation frames)

# groups: each is [ink ops, fill ops, detail ops]
var _G := []
const G_FAR = 0
const G_LEG = 1
const G_BODY = 2
const G_NEAR = 3
const G_WING = 4


func _draw() -> void:
	if genome == null:
		return
	_G = [[[], [], []], [[], [], []], [[], [], []], [[], [], []], [[], [], []]]

	var M = genome.morph if "morph" in genome else {}
	var camo = float(M.get("camo", 0.0))
	var base: Color = genome.color.linear_interpolate(Color(0.44, 0.42, 0.33), 0.55 * camo)
	var dark: Color = base.darkened(0.38)
	var hi: Color = base.lightened(0.55)
	var limbc: Color = base.darkened(0.22)
	var farc: Color = base.darkened(0.55)
	var segs: Array = genome.segments
	var ns = segs.size()
	var major = float(M.get("major", 0.0))
	var repl = float(M.get("replete", 0.0))
	var nodes = int(M.get("petiole", 1))
	var FM = genome.forms if "forms" in genome else {}
	var f_spike = int(FM.get("spike", 0))
	var f_acid = int(FM.get("acid", 0))
	var f_leg = int(FM.get("leg", 0))
	var f_ant = int(FM.get("antenna", 0))
	var f_sting = int(FM.get("sting", 0))
	var stilt = 1.3 if f_leg == 4 else 1.0

	# --- per-segment shape: kind, half-length hx, half-height ry ---
	var kind := []
	var HX := []
	var RY := []
	for i in ns:
		var r: float = segs[i]["r"]
		var kd = "thorax"
		if i == ns - 1:
			kd = "head"
		elif i == 0 and ns > 1:
			kd = "gaster"
		kind.append(kd)
		match kd:
			"gaster":
				var sw = 1.0 + 0.5 * repl
				HX.append(r * 1.12 * sw)
				RY.append(r * 0.84 * sw * (1.0 + 0.08 * repl))
			"head":
				var hm = 1.0 + 0.5 * major
				HX.append(r * 0.98 * hm)
				RY.append(r * 0.86 * hm * (1.0 + 0.08 * major))
			_:
				HX.append(r * 1.3)
				RY.append(r * 0.78)

	# --- stance height: legs hold the body low, knees above the back ---
	var lmax := 0.0
	var max_ry := 0.0
	var has_legs := false
	for i in ns:
		max_ry = max(max_ry, RY[i])
		if segs[i]["limb"] == "leg" and segs[i]["n"] > 0:
			has_legs = true
			lmax = max(lmax, float(segs[i]["len"]) * stilt)
	var yb = -(lmax * 0.66 + 12.0) if has_legs else -(max_ry * 0.95 + 6.0)
	yb = min(yb, -(max_ry * 0.62 + 6.0))

	# --- layout: rear (left) -> head (right) ---
	var waist: float = (12.0 + 10.0 * nodes) if ns > 2 else 4.0
	var neck := 3.0
	var total := waist
	for i in ns:
		total += HX[i] * 2.0
		if i > 0 and i < ns - 1:
			total -= HX[i] * 0.18   # thorax segments overlap a little
	total += neck
	var pos := []
	var ang := []
	var x := -total / 2.0
	for i in ns:
		x += HX[i]
		var y = yb
		var a = 0.0
		match kind[i]:
			"gaster":
				y = yb - RY[i] * 0.12
				a = -0.1
			"head":
				y = yb - RY[i] * 0.05
				a = 0.28
			_:
				y = yb - RY[i] * 0.2
		pos.append(Vector2(x, y))
		ang.append(a)
		x += HX[i]
		if i == 0:
			x += waist
		elif i < ns - 2:
			x -= HX[i] * 0.18
		elif i == ns - 2:
			x += neck

	# v0.23: the body is not rigid. The mesosoma bobs with every tripod step, the gaster counter-swings
	# and the head nods, so the legs, antennae, mandibles and trunk all move on their own beat.
	for i in ns:
		var bob = sin(gait * TAU * 2.0 + i * 0.5) * 1.8
		var dx = 0.0
		var da = 0.0
		if kind[i] == "gaster":
			dx = sin(gait * TAU + 0.6) * 2.2
			da = sin(gait * TAU * 2.0 + 1.2) * 0.04
		elif kind[i] == "head":
			dx = sin(gait * TAU + 2.0) * 0.9
			da = sin(gait * TAU * 2.0 + 2.2) * 0.06
		pos[i] = pos[i] + Vector2(dx, bob)
		ang[i] = ang[i] + da

	var k = min(1.0, 310.0 / (total + 120.0)) * paint_scale
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))

	# (no baked ground shadow: ant_view draws a proper one per unit, tilted to the slope and kept
	# on the ground when the ant flies; a shadow baked into the sprite tilted with it and doubled up)

	# --- limbs: far side behind the body, near side in front ---
	var leg_front := -1
	var leg_rear := -1
	for i in ns:
		if segs[i]["limb"] == "leg" and segs[i]["n"] > 0:
			if leg_rear < 0:
				leg_rear = i
			leg_front = i
	for i in ns:
		var s: Dictionary = segs[i]
		var limb: String = s["limb"]
		var n: int = s["n"]
		if limb == "" or n <= 0:
			continue
		var p: Vector2 = pos[i]
		var hx: float = HX[i]
		var ry: float = RY[i]
		var L: float = s["len"]
		for j in n:
			var t = 0.0 if n == 1 else (j - (n - 1) / 2.0) / ((n - 1) / 2.0)   # -1 rear .. +1 front
			for side in 2:   # 0 far, 1 near
				var grp = G_FAR if side == 0 else (G_LEG if limb != "claw" else G_NEAR)
				var col = farc if side == 0 else limbc
				var off = Vector2(-6.0, -5.0) if side == 0 else Vector2.ZERO
				match limb:
					"leg":
						var role = 0   # 1 front pair, 2 rear pair
						if i == leg_front and j == n - 1 and f_leg in [1, 3]:
							role = 1
						elif i == leg_rear and j == 0 and f_leg == 2:
							role = 2
						_leg(grp, p + off, hx, ry, L * stilt, t, i, j, side, col, f_leg, role)
					"tentacle":
						_tentacle(grp, p + off, hx, ry, t, j, side, col)
					"claw":
						_claw_limb(grp, p + off, hx, ry, L, t, side, col, base)
					"fin":
						if side == 1:
							_fin(p, hx, ry, L, t, j, dark, base)

	# --- waist / neck ---
	if ns > 2:
		var a0 = pos[0] + Vector2(HX[0] * 0.85, -RY[0] * 0.05)
		var a1 = pos[1] - Vector2(HX[1] * 0.8, -RY[1] * 0.15)
		_taper(G_BODY, a0, a1, 4.5, 4.5, dark)
		for nn in nodes:
			var nt = (nn + 1.0) / (nodes + 1.0)
			var np = a0.linear_interpolate(a1, nt)
			var nr = 9.0 if nodes == 1 else 7.5
			_seg(G_BODY, "node", np + Vector2(0, -nr * 0.35), nr * 0.75, nr * 1.15, 0.0, base, dark, hi)
	if ns >= 2:
		var h0 = pos[ns - 2] + Vector2(HX[ns - 2] * 0.85, -RY[ns - 2] * 0.1)
		var h1 = pos[ns - 1] + Vector2(-HX[ns - 1] * 0.6, RY[ns - 1] * 0.05)
		_taper(G_BODY, h0, h1, 6.0, 5.0, dark)

	# --- body segments, rear to front (head on top) ---
	for i in ns:
		var s2: Dictionary = segs[i]
		var p2: Vector2 = pos[i]
		_seg(G_BODY, kind[i], p2, HX[i], RY[i], ang[i], base, dark, hi)
		if kind[i] == "gaster":
			_gaster_marks(p2, HX[i], RY[i], ang[i], base, dark, M)
		elif kind[i] == "thorax":
			_add(G_BODY, 2, {"t": "line", "pts": _xf(_quad(Vector2(HX[i] * 0.2, -RY[i] * 0.95), Vector2(HX[i] * 0.05, -RY[i] * 0.4), Vector2(HX[i] * 0.12, RY[i] * 0.1), 6), p2, ang[i]), "w": 2.5, "c": Color(dark.r, dark.g, dark.b, 0.75)})
		if camo > 0.25:
			_mottle(p2, HX[i], RY[i], ang[i], base, camo, i)
		_hair(p2, HX[i], RY[i], ang[i], dark, float(M.get("hair", 0.0)), i)
		_armor(p2, HX[i], RY[i], ang[i], int(s2["armor"]), base)
		_spikes(p2, HX[i], RY[i], ang[i], int(s2["spikes"]), f_spike, kind[i])

	# --- head ---
	var h: Dictionary = segs[ns - 1]
	var hp: Vector2 = pos[ns - 1]
	var hhx: float = HX[ns - 1]
	var hry: float = RY[ns - 1]
	var ha: float = ang[ns - 1]
	var jaw_scale = (0.75 + 0.3 * major) * clamp(hry / 20.0, 0.8, 1.5)
	match h.get("jaw", ""):
		"mandible":
			_mandible(G_FAR, hp + Vector2(-4, -3), hhx, hry, ha, jaw_scale * 0.95, farc, 0.0)
			_mandible(G_NEAR, hp, hhx, hry, ha, jaw_scale, limbc, 1.0)
		"claw":
			_head_claw(G_FAR, hp + Vector2(-4, -3), hhx, hry, ha, jaw_scale * 0.9, farc, farc)
			_head_claw(G_NEAR, hp, hhx, hry, ha, jaw_scale, limbc, base)
		"tentacle":
			for q in 3:
				var root = hp + _rot(Vector2(hhx * 0.8, hry * 0.45), ha)
				var sway = sin(anim_t * 4.0 + q * 1.3) * 5.0
				var pts = _quad(root, root + Vector2(16 + q * 5, 10 + q * 3), root + Vector2(10 + q * 9 + sway, 30 - q * 3), 8)
				_tapered_chain(G_NEAR if q != 1 else G_FAR, pts, 5.5, 2.0, limbc if q != 1 else farc)
	if int(M.get("acid", 0)) == 1 and f_acid == 2:
		_venom_jaws(hp, hhx, hry, ha, jaw_scale, h.get("jaw", ""))
	# clypeus line and antennal socket ridge
	_add(G_BODY, 2, {"t": "line", "pts": _xf(_quad(Vector2(hhx * 0.62, -hry * 0.05), Vector2(hhx * 0.82, hry * 0.12), Vector2(hhx * 0.78, hry * 0.42), 6), hp, ha), "w": 2.5, "c": Color(dark.r, dark.g, dark.b, 0.8)})
	if h.get("antenna", 0.0) > 0.0:
		var alen: float = h["antenna"]
		_antenna(G_FAR, hp + Vector2(-5, -2), hhx, hry, ha, alen, farc, 1.3, f_ant)
		_antenna(G_NEAR, hp, hhx, hry, ha, alen, limbc, 0.0, f_ant)
	if h.get("crown", false):
		var cb = hp + _rot(Vector2(-hhx * 0.15, -hry * 0.92), ha)
		var crown = PoolVector2Array([cb + Vector2(-15, 6), cb + Vector2(-18, -11), cb + Vector2(-8, -2), cb + Vector2(0, -16),
			cb + Vector2(8, -2), cb + Vector2(18, -11), cb + Vector2(15, 6)])
		_add(G_NEAR, 0, {"t": "poly_ol", "pts": crown, "c": Color("#f2c14e"), "w": 4.0})
		_add(G_NEAR, 2, {"t": "circle", "p": cb + Vector2(0, -6), "r": 3.0, "c": Color("#e8483b")})
		_add(G_NEAR, 2, {"t": "line", "pts": PoolVector2Array([cb + Vector2(-11, -4), cb + Vector2(-13, 2)]), "w": 2.5, "c": Color("#fff2b8")})
	var OG = genome.organs if "organs" in genome else {}
	var FUS = genome.fusions() if genome.has_method("fusions") else []
	if int(OG.get("tongue", 0)) >= 3:
		_turret_eye(hp, hhx, hry, ha, base, dark)   # chameleon: the eye sits in a swivelling cone
	_eyes(hp, hhx, hry, ha, int(h.get("eyes", 1)))
	_organs(OG, FUS, pos, HX, RY, ang, ns, base, dark, limbc, farc)

	# glow: luminous photophores along the body
	if int(M.get("glow", 0)) == 1:
		for i in ns:
			var gp = pos[i] + _rot(Vector2(-HX[i] * 0.15, RY[i] * 0.3), ang[i])
			_add(G_BODY, 2, {"t": "circle", "p": gp, "r": RY[i] * 0.55, "c": Color(0.6, 1.0, 0.55, 0.16)})
			_add(G_BODY, 2, {"t": "circle", "p": gp, "r": RY[i] * 0.34, "c": Color(0.65, 1.0, 0.6, 0.3)})
			_add(G_BODY, 2, {"t": "circle", "p": gp, "r": RY[i] * 0.17, "c": Color(0.85, 1.0, 0.75, 0.95)})

	# --- rear weapons: sting and acid at the gaster tip ---
	var gtip = pos[0] + _rot(Vector2(-HX[0] * 1.02, RY[0] * 0.22), ang[0])
	if int(M.get("stinger", 0)) == 1:
		_sting(gtip, f_sting, pos[0], HX[0], RY[0])
	if int(M.get("acid", 0)) == 1:
		match f_acid:
			1:
				_venom_sacs(pos[0], HX[0], RY[0], ang[0])
			2:
				pass   # drawn on the jaws
			3:
				_spray_nozzle(gtip + Vector2(6, -2))
			_:
				_acid_drop(gtip + Vector2(10, 12))

	# --- wings (alates): folded back over the body, veined and translucent ---
	if int(M.get("wings", 0)) == 1 and ns >= 2:
		var wi_seg = 1 if ns > 2 else 0
		var wroot = pos[wi_seg] + Vector2(HX[wi_seg] * 0.2, -RY[wi_seg] * 0.85)
		for wi in 2:
			var wl = 160.0 - wi * 34.0
			var tipw = wroot + Vector2(-wl, -16.0 + wi * 20.0)
			var wh = 22.0 - wi * 5.0
			var axis = tipw - wroot
			var wa = axis.angle()
			var cc = wroot + axis * 0.5
			var wpts := PoolVector2Array()
			for q in 24:
				var a2 = TAU * q / 24.0
				# leading edge straighter, trailing edge rounder, narrow at the root
				var yy = sin(a2) * wh * (0.85 if sin(a2) < 0 else 1.1)
				var xx = cos(a2) * axis.length() * 0.5
				var pinch = 1.0 - 0.55 * pow(max(0.0, cos(a2)), 6.0)
				wpts.append(cc + Vector2(xx, yy * pinch).rotated(wa))
			var memb = Color(0.82, 0.9, 1.0, 0.34) if wi == 0 else Color(0.88, 0.84, 1.0, 0.26)
			_add(G_WING, 0, {"t": "ring", "pts": wpts, "w": 4.5, "c": INK})
			_add(G_WING, 1, {"t": "poly", "pts": wpts, "c": memb})
			# veins: costa along the leading edge, a stigma, two radial veins
			var vc = Color(0.25, 0.22, 0.32, 0.75)
			var lead0 = wroot + Vector2(0, -wh * 0.35).rotated(wa)
			var lead1 = wroot + axis * 0.62 + Vector2(0, -wh * 0.8).rotated(wa)
			_add(G_WING, 2, {"t": "line", "pts": _quad(lead0, wroot + axis * 0.3 + Vector2(0, -wh * 0.75).rotated(wa), lead1, 8), "w": 3.0, "c": vc})
			if wi == 0:
				_add(G_WING, 2, {"t": "poly", "pts": _ellipse_r(lead1 + Vector2(0, 3).rotated(wa), 9.0, 3.5, wa), "c": Color(0.2, 0.16, 0.24, 0.85)})
			for v in 2:
				var vb = wroot + axis * (0.18 + v * 0.2)
				_add(G_WING, 2, {"t": "line", "pts": _quad(vb, vb + axis * 0.3 + Vector2(0, (v * 2 - 1) * wh * 0.25).rotated(wa), vb + axis * (0.55 - v * 0.1) + Vector2(0, (v * 2 - 1) * wh * 0.55).rotated(wa), 8), "w": 1.8, "c": Color(vc.r, vc.g, vc.b, 0.55)})
			_add(G_WING, 2, {"t": "line", "pts": _quad(wroot + axis * 0.3 + Vector2(0, -wh * 0.4).rotated(wa), wroot + axis * 0.55 + Vector2(0, -wh * 0.55).rotated(wa), wroot + axis * 0.75 + Vector2(0, -wh * 0.3).rotated(wa), 6), "w": 3.0, "c": Color(1, 1, 1, 0.35)})

	# --- execute groups back to front ---
	for grp in _G:
		for pass_ops in grp:
			for op in pass_ops:
				_exec(op)


# ---------- anatomy ----------
func _leg(grp: int, p: Vector2, hx: float, ry: float, L: float, t: float, i: int, j: int, side: int, col: Color, form: int = 0, role: int = 0) -> void:
	var lw = clamp(L / 55.0, 0.8, 1.4)
	if form == 4:
		lw = clamp(L / 75.0, 0.8, 1.2) * 0.85   # stilts: long and spindly
	# tripod gait: legs 0/2 of one side swing with leg 1 of the other side
	var ph = gait * TAU + (PI if (j + side) % 2 == 1 else 0.0) + i * 0.35
	var stride = L * 0.22
	var te = t if abs(t) > 0.01 else -0.3   # mid legs angle slightly back
	var hip = p + Vector2(t * hx * 0.4, ry * 0.45)
	if role != 0 and side == 1:
		grp = G_NEAR   # specialised near legs sit in front of the body so they read
		col = col.lightened(0.18)
	if role == 1 and form == 3:
		_raptorial(grp, hip, L, lw, side, col)
		return
	var foot = Vector2(hip.x + te * L * 1.0 + cos(ph) * stride, -max(0.0, sin(ph)) * L * 0.18)
	if side == 0:
		foot += Vector2(6.0, -4.0)
	# femur reaches out and slightly up, tibia drops to the ground: knees read clearly
	var knee = Vector2(hip.x + te * L * 0.52 + cos(ph) * stride * 0.35, hip.y - L * 0.1 - max(0.0, sin(ph)) * L * 0.08)
	var fem_a = 4.4 * lw
	var fem_b = 3.4 * lw
	var tib_a = 3.0 * lw
	var tib_b = 1.9 * lw
	if role == 2:
		# jumping hind leg: swollen femur, knee cocked high, long tibia planted far back
		knee = Vector2(hip.x - L * 0.42, hip.y - L * 0.42 - max(0.0, sin(ph)) * L * 0.05)
		foot = Vector2(hip.x - L * 1.1 + cos(ph) * stride * 0.5, -max(0.0, sin(ph)) * L * 0.1)
		fem_a = 8.0 * lw
		fem_b = 4.0 * lw
	elif role == 1 and form == 1:
		# digging foreleg: thick femur, broad flattened tibia ending in a rake
		fem_a = 6.0 * lw
		tib_a = 5.0 * lw
		tib_b = 8.0 * lw
	_taper(grp, hip, knee, fem_a, fem_b, col, 5.5)
	_taper(grp, knee, foot, tib_a, tib_b, col, 5.0)
	var tdir = 1.0 if te >= 0.0 else -1.0
	if role == 1 and form == 1:
		var td0 = (foot - knee).normalized()
		for q in 4:
			var rb = foot + Vector2(-td0.y, td0.x) * (q - 1.5) * 3.6 * lw
			var rt = rb + (td0 + Vector2(0.7, 0.1)).normalized() * (11.0 + q % 2 * 3.0)
			_taper(grp, rb, rt, 2.2 * lw, 1.0, col.darkened(0.2), 4.0)
	else:
		var tar = foot + Vector2(tdir * 10.0, 0.5)
		_taper(grp, foot, tar, 1.9 * lw, 1.3 * lw, col, 4.5)
		_add(grp, 2, {"t": "line", "pts": PoolVector2Array([tar, tar + Vector2(tdir * 4.5, -3.0)]), "w": 1.8, "c": col.darkened(0.4)})
	if side == 1:
		# shine along the femur, spurs on the tibia
		var fm = hip.linear_interpolate(knee, 0.5)
		var fd = (knee - hip).normalized()
		var fn = Vector2(fd.y, -fd.x)
		if fn.y > 0.0:
			fn = -fn
		_add(grp, 2, {"t": "line", "pts": PoolVector2Array([fm - fd * 7.0 + fn * 1.4 * lw, fm + fd * 7.0 + fn * 1.4 * lw]), "w": 1.8 if role != 2 else 3.0, "c": col.lightened(0.35)})
		if role == 2:
			# muscle bands on the jumping femur
			for q in 3:
				var mp = hip.linear_interpolate(knee, 0.3 + q * 0.18)
				_add(grp, 2, {"t": "line", "pts": PoolVector2Array([mp - fn * fem_a * 0.7, mp + fn * fem_a * 0.5]), "w": 1.5, "c": col.darkened(0.3)})
		_add(grp, 2, {"t": "circle", "p": knee, "r": 2.4 * lw, "c": col.lightened(0.18)})
		var td = (foot - knee).normalized()
		for q in 2:
			var sp0 = knee.linear_interpolate(foot, 0.45 + q * 0.25)
			var sn = Vector2(td.y, -td.x) * (1.0 if td.x < 0.0 else -1.0)
			_add(grp, 2, {"t": "line", "pts": PoolVector2Array([sp0, sp0 + sn * 4.0 + td * 3.5]), "w": 1.5, "c": col.darkened(0.45)})


# Mantis-style grabbing foreleg: held up and folded, spined, never touches the ground.
func _raptorial(grp: int, hip: Vector2, L: float, lw: float, side: int, col: Color) -> void:
	var sway = sin(gait * TAU) * 2.5
	var knee = hip + Vector2(L * 0.38, -L * 0.42 + sway)
	var claw = knee + Vector2(L * 0.12, L * 0.38)
	var hook = claw + Vector2(-L * 0.12, -L * 0.06)
	_taper(grp, hip, knee, 5.0 * lw, 4.2 * lw, col, 5.5)
	_taper(grp, knee, claw, 3.6 * lw, 2.6 * lw, col, 5.0)
	_taper(grp, claw, hook, 2.4 * lw, 1.2, col, 4.0)
	if side == 1:
		var fd = (knee - hip).normalized()
		var td = (claw - knee).normalized()
		for q in 3:
			var a0 = hip.linear_interpolate(knee, 0.35 + q * 0.2)
			_add(grp, 2, {"t": "poly", "pts": PoolVector2Array([a0 - fd * 2.0, a0 + Vector2(fd.y, -fd.x) * -6.0 + fd * 1.5, a0 + fd * 2.0]), "c": Color("#ece4d2")})
			var b0 = knee.linear_interpolate(claw, 0.3 + q * 0.22)
			_add(grp, 2, {"t": "poly", "pts": PoolVector2Array([b0 - td * 1.6, b0 + Vector2(-td.y, td.x) * -4.5, b0 + td * 1.6]), "c": Color("#ece4d2")})
		_add(grp, 2, {"t": "circle", "p": knee, "r": 2.6 * lw, "c": col.lightened(0.2)})


func _tentacle(grp: int, p: Vector2, hx: float, ry: float, t: float, j: int, side: int, col: Color) -> void:
	var root = p + Vector2(t * hx * 0.5, ry * 0.5)
	var pts := []
	for q in 9:
		var f = q / 8.0
		var sway = sin(j * 1.7 + f * 4.0 + anim_t * 3.0 + side) * 12.0 * f
		pts.append(Vector2(root.x + sway + t * 14.0 * f, lerp(root.y, -1.0, f)))
	_tapered_chain(grp, pts, 7.0, 2.5, col)
	if side == 1:
		for q in range(2, 8, 2):
			_add(grp, 2, {"t": "circle", "p": pts[q] + Vector2(3, 0), "r": 1.8, "c": col.lightened(0.45)})


func _claw_limb(grp: int, p: Vector2, hx: float, ry: float, L: float, t: float, side: int, col: Color, base: Color) -> void:
	var sh = p + Vector2(t * hx * 0.4, ry * 0.3)
	var el = sh + Vector2(L * 0.3, L * 0.22)
	var wr = el + Vector2(L * 0.42, -L * 0.12)
	_taper(grp, sh, el, 6.5, 5.0, col)
	_taper(grp, el, wr, 5.0, 4.5, col)
	_pincer(grp, wr, 0.0, 1.0, col, base if side == 1 else col)


func _fin(p: Vector2, hx: float, ry: float, L: float, t: float, j: int, dark: Color, base: Color) -> void:
	var bx = p.x + t * hx * 0.5
	var b0 = Vector2(bx - 12, p.y - ry * 0.7)
	var b1 = Vector2(bx + 14, p.y - ry * 0.65)
	var top = Vector2(bx - 6 - L * 0.15, p.y - ry - L * 0.55)
	var fin := PoolVector2Array()
	for v in _quad(b0, top + Vector2(-6, 6), top, 6):
		fin.append(v)
	var back = _quad(top, Vector2(bx + 10, p.y - ry - L * 0.2), b1, 6)
	for q in range(1, back.size()):
		fin.append(back[q])
	_add(G_FAR, 0, {"t": "poly", "pts": fin, "c": INK})
	_add(G_FAR, 0, {"t": "ring", "pts": fin, "w": OL * 2.0, "c": INK})
	_add(G_FAR, 1, {"t": "poly", "pts": fin, "c": dark})
	for r in 3:
		var f = (r + 1) / 4.0
		_add(G_FAR, 2, {"t": "line", "pts": PoolVector2Array([b0.linear_interpolate(b1, f), top.linear_interpolate(b1, f * 0.6)]), "w": 2.0, "c": base.lightened(0.2)})


func _mandible(grp: int, hp: Vector2, hx: float, ry: float, ha: float, sc: float, col: Color, near: float) -> void:
	var m0 = hp + _rot(Vector2(hx * 0.78, ry * 0.38), ha)
	# curved blade: forward then hooking down and back toward the mouth
	var outer = _quad(m0 + Vector2(-2, -5) * sc, m0 + Vector2(22, -6) * sc, m0 + Vector2(26, 12) * sc, 8)
	var inner = _quad(m0 + Vector2(19, 12) * sc, m0 + Vector2(15, 2) * sc, m0 + Vector2(0, 5) * sc, 8)
	var blade := PoolVector2Array()
	for v in outer:
		blade.append(v)
	for v in inner:
		blade.append(v)
	_add(grp, 0, {"t": "poly", "pts": blade, "c": INK})
	_add(grp, 0, {"t": "ring", "pts": blade, "w": OL * 1.6, "c": INK})
	_add(grp, 1, {"t": "poly", "pts": blade, "c": col})
	if near > 0.5:
		for q in 3:
			var tp = m0 + Vector2(6 + q * 4.5, 3.5 - q * 0.2) * sc
			_add(grp, 2, {"t": "poly", "pts": PoolVector2Array([tp + Vector2(-2, 0) * sc, tp + Vector2(0.5, 4.5) * sc, tp + Vector2(2, 0) * sc]), "c": INK})
		_add(grp, 2, {"t": "line", "pts": _quad(m0 + Vector2(4, -3) * sc, m0 + Vector2(16, -3.5) * sc, m0 + Vector2(21, 3) * sc, 6), "w": 2.0, "c": col.lightened(0.4)})


func _head_claw(grp: int, hp: Vector2, hx: float, ry: float, ha: float, sc: float, col: Color, fill: Color) -> void:
	var m0 = hp + _rot(Vector2(hx * 0.75, ry * 0.4), ha)
	var w = m0 + Vector2(16, 6) * sc
	_taper(grp, m0, w, 5.5 * sc, 4.5 * sc, col)
	_pincer(grp, w, 0.25, sc, col, fill)


# Two-fingered pincer: a fat palm and a hinged finger.
func _pincer(grp: int, p: Vector2, a: float, sc: float, col: Color, fill: Color) -> void:
	var palm = _ellipse_r(p + Vector2(8, 0).rotated(a) * sc, 12.0 * sc, 8.5 * sc, a)
	_add(grp, 0, {"t": "poly", "pts": _ellipse_r(p + Vector2(8, 0).rotated(a) * sc, 12.0 * sc + OL, 8.5 * sc + OL, a), "c": INK})
	var f1 = _quad(p + Vector2(16, -5).rotated(a) * sc, p + Vector2(30, -9).rotated(a) * sc, p + Vector2(34, -1).rotated(a) * sc, 6)
	var f2 = _quad(p + Vector2(16, 4).rotated(a) * sc, p + Vector2(28, 8).rotated(a) * sc, p + Vector2(31, 2).rotated(a) * sc, 6)
	_tapered_chain(grp, Array(f1), 4.5 * sc, 1.5 * sc, col)
	_tapered_chain(grp, Array(f2), 3.8 * sc, 1.4 * sc, col)
	_add(grp, 1, {"t": "poly", "pts": palm, "c": fill})
	_add(grp, 2, {"t": "line", "pts": PoolVector2Array([p + Vector2(2, -4).rotated(a) * sc, p + Vector2(12, -6).rotated(a) * sc]), "w": 2.5, "c": fill.lightened(0.4)})


func _antenna(grp: int, hp: Vector2, hx: float, ry: float, ha: float, alen: float, col: Color, phase: float, form: int = 0) -> void:
	var a0 = hp + _rot(Vector2(hx * 0.5, -ry * 0.5), ha)
	var sway = sin(gait * TAU + phase) * 3.5
	var sway2 = sin(gait * TAU + phase + 1.1) * 4.0
	if form == 3:
		# whip: no elbow, one long tapering lash swept up and back over the body
		var wl = alen * 1.5 + 24.0
		var pts = _quad(a0, a0 + Vector2(wl * 0.15, -wl * 0.75 + sway), a0 + Vector2(-wl * 0.55 + sway2, -wl * 0.7), 12)
		_tapered_chain(grp, Array(pts), 3.0, 0.9, col)
		return
	var scape = alen * 0.62 + 8.0
	var elbow = a0 + Vector2(-scape * 0.12, -scape * 0.95 + sway * 0.4)
	var fl = alen * 0.95 + 12.0
	var tip = elbow + Vector2(fl * 0.86, fl * 0.42 + sway2)
	var mid = elbow.linear_interpolate(tip, 0.5) + Vector2(0, -fl * 0.12)
	_taper(grp, a0, elbow, 3.4, 2.8, col)
	var beads = 9
	var pts2 = _quad(elbow, mid, tip, beads)
	_tapered_chain(grp, Array(pts2), 2.2, 2.6, col)
	for q in range(1, beads + 1):
		var club = q >= beads - 2
		var br = 3.6 if club else 2.4
		if form == 1:
			br = [2.2, 2.2, 2.3, 2.4, 2.5, 2.7, 4.6, 5.8, 6.4][q - 1]   # heavy three-bead club
		_add(grp, 0, {"t": "circle", "p": pts2[q], "r": br + OL * 0.75, "c": INK})
		_add(grp, 1, {"t": "circle", "p": pts2[q], "r": br, "c": col if not club else col.lightened(0.08)})
	if form == 1:
		_add(grp, 2, {"t": "circle", "p": pts2[beads - 1] + Vector2(-1.5, -2.0), "r": 1.8, "c": col.lightened(0.45)})
	elif form == 2:
		# feathered: paired side branches along the funiculus
		for q in range(1, beads):
			var d = (pts2[q + 1] - pts2[q - 1]).normalized()
			var nrm = Vector2(-d.y, d.x)
			var bl = 7.0 + 4.0 * sin(PI * q / beads)
			for sgn in [-1.0, 1.0]:
				var e = pts2[q] + nrm * sgn * bl + d * 3.0
				_add(grp, 0, {"t": "line", "pts": PoolVector2Array([pts2[q], e]), "w": 1.8 + OL * 0.9, "c": INK})
				_add(grp, 1, {"t": "line", "pts": PoolVector2Array([pts2[q], e]), "w": 1.8, "c": col.lightened(0.12)})
	elif form == 4:
		# forked: the tip splits into two clubbed tines
		var d2 = (pts2[beads] - pts2[beads - 1]).normalized()
		for sgn in [-1.0, 1.0]:
			var e2 = pts2[beads] + d2.rotated(sgn * 0.7) * 18.0
			_taper(grp, pts2[beads], e2, 2.6, 2.0, col)
			_add(grp, 0, {"t": "circle", "p": e2, "r": 3.0 + OL * 0.75, "c": INK})
			_add(grp, 1, {"t": "circle", "p": e2, "r": 3.0, "c": col})
	_add(grp, 1, {"t": "circle", "p": elbow, "r": 3.4, "c": col.lightened(0.15)})


func _eyes(hp: Vector2, hx: float, ry: float, ha: float, ne: int) -> void:
	var ec = hp + _rot(Vector2(hx * 0.18, -ry * 0.18), ha)
	var er = clamp(ry * 0.3, 6.5, 11.0) * (1.0 + 0.08 * min(ne - 1, 3))   # majors keep small eyes
	_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(ec, er + 3.0, er * 0.82 + 3.0, ha, 20), "c": INK})
	_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(ec, er, er * 0.82, ha, 20), "c": Color("#241e2c")})
	_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(ec + Vector2(er * 0.1, er * 0.15), er * 0.7, er * 0.5, ha, 16), "c": Color("#3a3248")})
	for fy in 3:
		for fx in 4:
			var fp = ec + _rot(Vector2((fx - 1.5) * er * 0.42 + (fy % 2) * er * 0.21, (fy - 1) * er * 0.38), ha)
			if (fp - ec).length() < er * 0.72:
				_add(G_BODY, 2, {"t": "circle", "p": fp, "r": max(1.1, er * 0.1), "c": Color("#5a5170")})
	_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(ec + Vector2(-er * 0.32, -er * 0.32), er * 0.34, er * 0.22, -0.5), "c": Color(1, 1, 1, 0.92)})
	_add(G_BODY, 2, {"t": "circle", "p": ec + Vector2(er * 0.35, er * 0.25), "r": max(1.2, er * 0.1), "c": Color(1, 1, 1, 0.55)})
	# extra eyes: ocelli on the vertex
	for e in range(1, ne):
		var ox = hp + _rot(Vector2(-hx * 0.3 + (e - 1) * hx * 0.25, -ry * 0.72 - (e % 2) * 2.5), ha)
		_add(G_BODY, 2, {"t": "circle", "p": ox, "r": 4.6, "c": INK})
		_add(G_BODY, 2, {"t": "circle", "p": ox, "r": 3.0, "c": Color("#f4e6a8")})
		_add(G_BODY, 2, {"t": "circle", "p": ox + Vector2(-1, -1), "r": 1.1, "c": Color.white})


# Gaster markings + tergite plates; replete gasters show a honey sheen.
func _gaster_marks(p: Vector2, hx: float, ry: float, a: float, base: Color, dark: Color, M: Dictionary) -> void:
	var ink2 = base.darkened(0.55)
	var repl = float(M.get("replete", 0.0))
	if repl > 0.15:
		# stretched membrane between plates: amber, translucent
		_add(G_BODY, 1, {"t": "poly", "pts": _xf(_ellipse(Vector2(-hx * 0.05, ry * 0.02), hx * 0.86, ry * 0.76), p, a), "c": Color(1.0, 0.72, 0.25, 0.25 + 0.4 * repl)})
		_add(G_BODY, 1, {"t": "poly", "pts": _xf(_ellipse(Vector2(-hx * 0.15, -ry * 0.1), hx * 0.55, ry * 0.45), p, a), "c": Color(1.0, 0.86, 0.45, 0.25 + 0.3 * repl)})
	# tergite seams, curved toward the tip
	var seam_c = Color(dark.r, dark.g, dark.b, 0.32 if repl < 0.15 else 0.7)
	for q in 2:
		var sx = hx * (0.3 - q * 0.42)
		var hgt = ry * (0.95 - 0.12 * q * q * 0.5)
		_add(G_BODY, 1, {"t": "line", "pts": _xf(_quad(Vector2(sx + 4, -hgt), Vector2(sx - 9, 0), Vector2(sx + 4, hgt * 0.8), 8), p, a), "w": max(2.5, ry * 0.06), "c": seam_c})
	match int(M.get("pattern", 0)):
		1:
			for b in 3:
				var bx = hx * (0.3 - b * 0.36)
				_add(G_BODY, 1, {"t": "line", "pts": _xf(_quad(Vector2(bx - 2, -ry * 0.82), Vector2(bx - 12, 0), Vector2(bx - 2, ry * 0.7), 8), p, a), "w": max(5.0, ry * 0.16), "c": ink2})
		2:
			for q in 4:
				var sp = Vector2(-hx * 0.5 + q * hx * 0.32, -ry * 0.32 + (q % 2) * ry * 0.3)
				_add(G_BODY, 1, {"t": "poly", "pts": _xf(_ellipse(sp, ry * 0.15, ry * 0.12, 12), p, a), "c": base.lightened(0.5)})
		3:
			var tip := PoolVector2Array()
			var full = _gaster_pts(hx, ry)
			for v in full:
				if v.x < -hx * 0.35:
					tip.append(v)
			if tip.size() >= 3:
				_add(G_BODY, 1, {"t": "poly", "pts": _xf(tip, p, a), "c": ink2})


# Drab blotches for camouflaged lines, placed deterministically per segment.
func _mottle(p: Vector2, hx: float, ry: float, a: float, base: Color, camo: float, idx: int) -> void:
	for q in 5:
		var h1 = fmod(abs(sin(idx * 12.9898 + q * 78.233)) * 43758.5453, 1.0)
		var h2 = fmod(abs(sin(idx * 39.346 + q * 11.135)) * 24634.6345, 1.0)
		var c = Vector2((h1 - 0.5) * hx * 1.2, (h2 - 0.55) * ry * 1.1)
		var col = base.darkened(0.3) if q % 2 == 0 else base.lightened(0.15)
		_add(G_BODY, 1, {"t": "poly", "pts": _xf(_ellipse(c, ry * (0.18 + 0.1 * h2), ry * (0.12 + 0.08 * h1), 10), p, a), "c": Color(col.r, col.g, col.b, 0.55 * camo)})


# Fine setae along the top contour.
func _hair(p: Vector2, hx: float, ry: float, a: float, dark: Color, hair: float, idx: int) -> void:
	var n = int(hair * 11.0)
	for q in n:
		var an = PI * (1.1 + 0.8 * (q + 0.5) / max(1, n)) + idx * 0.05
		var root = Vector2(cos(an) * hx * 0.97, sin(an) * ry * 0.97)
		var nrm = Vector2(cos(an) / hx, sin(an) / ry).normalized()
		var tip = root + nrm * 10.0 + Vector2(-2.5, 0)
		_add(G_BODY, 2, {"t": "line", "pts": _xf(PoolVector2Array([root, root + nrm * 5.0 + Vector2(-0.5, 0), tip]), p, a), "w": 1.8, "c": dark.darkened(0.3)})


# Overlapping dorsal scutes; each level adds a plate.
func _armor(p: Vector2, hx: float, ry: float, a: float, n: int, base: Color) -> void:
	if n <= 0:
		return
	var armc: Color = base.darkened(0.5)
	for q in n:
		var off = (q - (n - 1) / 2.0) * hx * 0.5
		var c = Vector2(off, -ry * 0.12)
		var plate := PoolVector2Array()
		var pw = hx * (0.62 if n > 1 else 0.85)
		for s in 15:
			var an = PI + PI * s / 14.0
			plate.append(c + Vector2(cos(an) * pw, sin(an) * ry * 0.98))
		_add(G_BODY, 2, {"t": "poly_ol", "pts": _xf(plate, p, a), "c": armc, "w": 4.0})
		_add(G_BODY, 2, {"t": "line", "pts": _xf(_quad(c + Vector2(-pw * 0.55, -ry * 0.55), c + Vector2(0, -ry * 0.88), c + Vector2(pw * 0.45, -ry * 0.62), 8), p, a), "w": 3.0, "c": armc.lightened(0.55)})
		for r in 2:
			_add(G_BODY, 2, {"t": "circle", "p": p + _rot(c + Vector2((r - 0.5) * pw * 0.9, -ry * 0.18), a), "r": 2.2, "c": armc.lightened(0.35)})


const BONE = Color("#ece4d2")


func _spikes(p: Vector2, hx: float, ry: float, a: float, n: int, form: int = 0, kind: String = "") -> void:
	if n <= 0:
		return
	if form == 4 and kind == "thorax":
		# propodeal spines: one long pair at the back of the mesosoma, thicker with more spikes
		var sl = 34.0 + 4.0 * n
		for q in 2:
			var root = Vector2(-hx * 0.6 - q * 4.0, -ry * 0.6)
			var tip = root + Vector2(-sl * 0.62, -sl * 0.78) + Vector2(q * 5.0, q * 4.0)
			var w = 5.0 + 0.6 * n
			var dn = (tip - root).normalized()
			var nn = Vector2(-dn.y, dn.x)
			_add(G_BODY, 2 if q == 1 else 1, {"t": "poly_ol", "pts": _xf(PoolVector2Array([root + nn * w, tip, root - nn * w]), p, a), "c": BONE if q == 1 else BONE.darkened(0.25), "w": 3.5})
		return
	if form == 3:
		# dorsal ridge: one sawtooth crest that follows the back
		var teeth = n * 2 + 2
		var crest := PoolVector2Array()
		var steps = teeth * 2
		for q in steps + 1:
			var an = PI * (1.12 + 0.76 * float(q) / steps)
			var base_pt = Vector2(cos(an) * hx * 0.9, sin(an) * ry * 0.9)
			var nrm = Vector2(cos(an) / hx, sin(an) / ry).normalized()
			var hgt = (14.0 + 1.5 * n) if q % 2 == 1 else 3.0
			crest.append(base_pt + nrm * hgt + (Vector2(-3, 0) if q % 2 == 1 else Vector2.ZERO))
		for q in range(steps, -1, -1):
			var an2 = PI * (1.12 + 0.76 * float(q) / steps)
			crest.append(Vector2(cos(an2) * hx * 0.8, sin(an2) * ry * 0.75))
		_add(G_BODY, 2, {"t": "poly_ol", "pts": _xf(crest, p, a), "c": Color("#d9cdb4"), "w": 3.5})
		return
	var count = n * 2 if form == 1 else n
	for q in count:
		var an = PI * (1.15 + 0.7 * (q + 0.5) / count)
		var root = Vector2(cos(an) * hx * 0.92, sin(an) * ry * 0.92)
		var nrm = Vector2(cos(an) / hx, sin(an) / ry).normalized()
		var tg = Vector2(-nrm.y, nrm.x)
		match form:
			1:
				# rose thorns: short, broad, curved back toward the tail
				var tip1 = root + nrm * 11.0 + Vector2(-7, 2)
				var pts1 = PoolVector2Array([root + tg * 5.0, root + nrm * 5.0 + Vector2(-4, 0), tip1, root - tg * 5.0])
				_add(G_BODY, 2, {"t": "poly_ol", "pts": _xf(pts1, p, a), "c": Color("#c98a5a"), "w": 3.0})
			2:
				# hooked barbs: long shaft that hooks forward at the tip
				# tg points toward the head, so the hook curls forward
				var apex = root + nrm * 24.0
				var pts2 = PoolVector2Array([root - tg * 6.0, apex - tg * 2.5, apex + tg * 1.0, apex + tg * 11.0 - nrm * 6.0, apex + tg * 3.0 - nrm * 8.0, root + tg * 6.0])
				_add(G_BODY, 2, {"t": "poly_ol", "pts": _xf(pts2, p, a), "c": BONE, "w": 3.2})
			_:
				var tip = root + nrm * 22.0 + Vector2(-5, 0)
				var pts = PoolVector2Array([root + tg * 6.0, root + nrm * 10.0 + tg * 2.5 + Vector2(-2, 0), tip, root - tg * 6.0])
				_add(G_BODY, 2, {"t": "poly_ol", "pts": _xf(pts, p, a), "c": BONE, "w": 3.5})
				_add(G_BODY, 2, {"t": "line", "pts": _xf(PoolVector2Array([root - tg * 2.5 + nrm * 3.0, tip - nrm * 5.0 + Vector2(1, 0)]), p, a), "w": 1.8, "c": Color("#b8ac94")})


# ---------- rear weapons ----------
const VENOM = Color("#8fdc4a")
const VENOM_HI = Color("#e9ffc8")


func _sting(gtip: Vector2, form: int, gp: Vector2, ghx: float, gry: float) -> void:
	var sd = Vector2(-1.0, 0.32).normalized()
	var sn = Vector2(-sd.y, sd.x)
	match form:
		1:
			# barbed: longer blade with a saw edge on the underside
			var pts = PoolVector2Array([gtip + sn * 6.0 + sd * 4.0, gtip + sd * 36.0])
			for q in 4:
				var f = 0.85 - q * 0.18
				pts.append(gtip + sd * (36.0 * f) - sn * (1.5 + 3.5 * (1.0 - f)) )
				pts.append(gtip + sd * (36.0 * f - 4.0) - sn * (6.0 + 2.0 * (1.0 - f)))
			pts.append(gtip - sn * 6.0 + sd * 4.0)
			_add(G_BODY, 2, {"t": "poly_ol", "pts": pts, "c": Color("#e3cf86"), "w": 3.0})
		2:
			# scorpion tail: beaded segments arching up over the gaster, sting aimed forward
			var top = gp + Vector2(-ghx * 0.55, -gry * 1.0 - 40.0)
			var pts2 = _quad(gtip, gtip + Vector2(-34, -36), top, 6)
			for q in pts2.size() - 1:
				var r0 = 8.0 - q * 0.7
				_taper(G_BODY, pts2[q], pts2[q + 1], r0, r0 - 0.7, Color("#c9a86a").darkened(0.1 * (q % 2)))
			for q in range(1, pts2.size() - 1):
				_add(G_BODY, 2, {"t": "circle", "p": pts2[q] + Vector2(1, -2), "r": 1.8, "c": Color("#fff4cf")})
			var bulb = top + Vector2(10, 4)
			_add(G_BODY, 0, {"t": "poly", "pts": _ellipse_r(bulb, 11.0 + OL, 8.0 + OL, 0.4), "c": INK})
			_add(G_BODY, 1, {"t": "poly", "pts": _ellipse_r(bulb, 11.0, 8.0, 0.4), "c": Color("#e3cf86")})
			var hk = PoolVector2Array([bulb + Vector2(6, -5), bulb + Vector2(24, 8), bulb + Vector2(16, 12), bulb + Vector2(6, 5)])
			_add(G_BODY, 2, {"t": "poly_ol", "pts": hk, "c": Color("#f2e6b8"), "w": 3.0})
		3:
			# twin stingers: two blades spread in a V
			for q in 2:
				var d = sd.rotated(-0.32 + q * 0.6)
				var n2 = Vector2(-d.y, d.x)
				_add(G_BODY, 2, {"t": "poly_ol", "pts": PoolVector2Array([gtip + n2 * 5.0 + d * 3.0, gtip + d * 28.0, gtip - n2 * 5.0 + d * 3.0]), "c": Color("#e3cf86"), "w": 3.0})
		_:
			var sting = PoolVector2Array([gtip + sn * 6.0 + sd * 4.0, gtip + sd * 30.0, gtip - sn * 6.0 + sd * 4.0])
			_add(G_BODY, 2, {"t": "poly_ol", "pts": sting, "c": Color("#e3cf86"), "w": 3.0})
			_add(G_BODY, 2, {"t": "line", "pts": PoolVector2Array([gtip + sd * 8.0 - sn * 1.5, gtip + sd * 22.0]), "w": 2.0, "c": Color("#fff4cf")})


func _acid_drop(ap: Vector2) -> void:
	_add(G_BODY, 2, {"t": "poly", "pts": _drop(ap, 10.0), "c": INK})
	_add(G_BODY, 2, {"t": "poly", "pts": _drop(ap, 7.0), "c": VENOM})
	_add(G_BODY, 2, {"t": "circle", "p": ap + Vector2(-2, 1), "r": 2.2, "c": VENOM_HI})
	_add(G_BODY, 2, {"t": "circle", "p": ap + Vector2(-4, 17), "r": 4.0, "c": INK})
	_add(G_BODY, 2, {"t": "circle", "p": ap + Vector2(-4, 17), "r": 2.6, "c": VENOM})


# Venom sacs: two swollen glowing bladders bulging from the gaster's underside.
func _venom_sacs(gp: Vector2, hx: float, ry: float, a: float) -> void:
	for q in 2:
		var c = gp + _rot(Vector2(-hx * 0.15 + q * hx * 0.42, ry * 0.68), a)
		var r = ry * (0.42 - q * 0.08) + 4.0
		var grp = G_BODY
		_add(grp, 2, {"t": "poly", "pts": _ellipse(c, r + 4.0, r * 0.8 + 4.0, 18), "c": INK})
		_add(grp, 2, {"t": "poly", "pts": _ellipse(c, r, r * 0.8, 18), "c": VENOM.darkened(0.25)})
		_add(grp, 2, {"t": "poly", "pts": _ellipse(c + Vector2(-r * 0.1, -r * 0.12), r * 0.7, r * 0.5, 14), "c": VENOM})
		_add(grp, 2, {"t": "line", "pts": _quad(c + Vector2(-r * 0.6, -r * 0.1), c + Vector2(0, r * 0.3), c + Vector2(r * 0.5, -r * 0.2), 6), "w": 1.6, "c": VENOM.darkened(0.45)})
		_add(grp, 2, {"t": "circle", "p": c + Vector2(-r * 0.35, -r * 0.3), "r": max(1.8, r * 0.16), "c": VENOM_HI})
	_add(G_BODY, 2, {"t": "circle", "p": gp + _rot(Vector2(hx * 0.1, ry * 1.3), a) + Vector2(0, 6), "r": 2.8, "c": VENOM})


# Spray nozzle: a short turret at the gaster tip, ringed mouth, misting droplets.
func _spray_nozzle(base: Vector2) -> void:
	var mouth = base + Vector2(-22, -30)
	_taper(G_BODY, base, mouth, 10.0, 7.0, Color("#6f9a3a"))
	_taper(G_BODY, base.linear_interpolate(mouth, 0.45), base.linear_interpolate(mouth, 0.55), 11.5, 11.5, Color("#5a7f2c"))
	var ring = _ellipse_r(mouth, 10.0, 5.5, -0.9, 14)
	_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(mouth, 13.0, 8.5, -0.9, 14), "c": INK})
	_add(G_BODY, 2, {"t": "poly", "pts": ring, "c": VENOM})
	_add(G_BODY, 2, {"t": "line", "pts": PoolVector2Array([base + Vector2(-4, -6), mouth + Vector2(1, 3)]), "w": 2.0, "c": Color(1, 1, 1, 0.4)})
	for q in 4:
		var f = gait + q * 0.25
		var dp = mouth + Vector2(-10.0 - 11.0 * q, -8.0 - 8.0 * q + 4.0 * sin(f * TAU))
		_add(G_BODY, 2, {"t": "circle", "p": dp, "r": 5.5 - q * 0.8, "c": INK})
		_add(G_BODY, 2, {"t": "circle", "p": dp, "r": 3.6 - q * 0.6, "c": VENOM_HI if q % 2 == 0 else VENOM})


# Venom coating the jaws, with drops falling from the tips.
func _venom_jaws(hp: Vector2, hx: float, ry: float, ha: float, sc: float, jaw: String) -> void:
	var m0 = hp + _rot(Vector2(hx * 0.78, ry * 0.38), ha)
	var tip = m0 + Vector2(24, 10) * sc
	if jaw == "claw":
		tip = m0 + Vector2(40, 10) * sc
	elif jaw == "":
		tip = m0 + Vector2(6, 8) * sc
	_add(G_NEAR, 2, {"t": "line", "pts": _quad(m0 + Vector2(12, -4) * sc, m0 + Vector2(22, -3) * sc, tip, 6), "w": 4.0, "c": Color(VENOM.r, VENOM.g, VENOM.b, 0.85)})
	var ph = fmod(gait * 2.0, 1.0)
	for q in 2:
		var dp = tip + Vector2(-2 - q * 6, 8 + ph * 10.0 + q * 12)
		_add(G_NEAR, 2, {"t": "poly", "pts": _drop(dp, 5.5 - q * 1.5), "c": INK})
		_add(G_NEAR, 2, {"t": "poly", "pts": _drop(dp, 3.6 - q * 1.0), "c": VENOM})
		_add(G_NEAR, 2, {"t": "circle", "p": dp + Vector2(-1, 0), "r": 1.1, "c": VENOM_HI})


# One shaded body part: ink -> shadow -> lit body -> top band -> rim light + speculars.
func _seg(grp: int, kind: String, c: Vector2, hx: float, ry: float, a: float, base: Color, dark: Color, hi: Color) -> void:
	var outer = _shape(kind, hx + OL, ry + OL)
	_add(grp, 0, {"t": "poly", "pts": _xf(outer, c, a), "c": INK})
	_add(grp, 1, {"t": "poly", "pts": _xf(_shape(kind, hx, ry), c, a), "c": dark})
	_add(grp, 1, {"t": "poly", "pts": _xf(_shape(kind, hx * 0.93, ry * 0.8, Vector2(hx * 0.02, -ry * 0.14)), c, a), "c": base})
	_add(grp, 1, {"t": "poly", "pts": _xf(_shape(kind, hx * 0.72, ry * 0.42, Vector2(hx * 0.04, -ry * 0.4)), c, a), "c": base.lightened(0.12)})
	# reflected light along the underside: separates the body from dark floors
	_add(grp, 1, {"t": "line", "pts": _xf(_quad(Vector2(-hx * 0.55, ry * 0.62), Vector2(0, ry * 0.9), Vector2(hx * 0.55, ry * 0.62), 8), c, a), "w": max(2.0, ry * 0.08), "c": base.lightened(0.2)})
	# glossy chitin: a long soft highlight plus a hot specular dot
	_add(grp, 2, {"t": "line", "pts": _xf(_quad(Vector2(-hx * 0.45, -ry * 0.5), Vector2(hx * 0.02, -ry * 0.82), Vector2(hx * 0.42, -ry * 0.58), 8), c, a), "w": max(3.0, ry * 0.15), "c": Color(hi.r, hi.g, hi.b, 0.75)})
	_add(grp, 2, {"t": "poly", "pts": _xf(_ellipse(Vector2(hx * 0.22, -ry * 0.55), max(2.5, ry * 0.13), max(1.8, ry * 0.08), 10), c, a), "c": Color(1, 1, 1, 0.85)})


# ---------- organ lines (v0.21) ----------
const SHELL_C = Color("#d2a868")
const SILK_C = Color(0.97, 0.97, 1.0, 0.8)
const PINK = Color("#ff8fb1")
const CYAN = Color("#7fe9ff")


func _organs(OG: Dictionary, FUS: Array, pos: Array, HX: Array, RY: Array, ang: Array, ns: int, base: Color, dark: Color, limbc: Color, farc: Color) -> void:
	var gi = 0
	var ti = 1 if ns > 2 else 0
	var hi_ = ns - 1
	var gp: Vector2 = pos[gi]
	var ghx: float = HX[gi]
	var gry: float = RY[gi]
	var ga: float = ang[gi]
	var hp: Vector2 = pos[hi_]
	var hhx: float = HX[hi_]
	var hry: float = RY[hi_]
	var ha: float = ang[hi_]
	var gtip = gp + _rot(Vector2(-ghx * 1.02, gry * 0.22), ga)
	var mouth = hp + _rot(Vector2(hhx * 0.82, hry * 0.42), ha)
	var t_son = int(OG.get("sonic", 0))
	var t_ele = int(OG.get("electric", 0))
	var t_she = int(OG.get("shell", 0))
	var t_sil = int(OG.get("silk", 0))
	var t_ton = int(OG.get("tongue", 0))
	var t_reg = int(OG.get("regen", 0))
	var hsc = clamp(hry / 20.0, 0.8, 1.6)

	# --- shell (drawn first: it sits on the gaster under the other organs) ---
	if t_she == 1:
		for q in 5:
			var an = PI * (1.2 + 0.6 * q / 4.0)
			var c = Vector2(cos(an) * ghx * 0.62, sin(an) * gry * 0.55 - gry * 0.05)
			var hx_pts := PoolVector2Array()
			for v in 6:
				var a6 = TAU * v / 6.0 + PI / 6.0
				hx_pts.append(c + Vector2(cos(a6), sin(a6) * 0.85) * gry * 0.3)
			_add(G_BODY, 2, {"t": "poly_ol", "pts": _xf(hx_pts, gp, ga), "c": SHELL_C.darkened(0.15 * (q % 2)), "w": 2.5})
	elif t_she >= 2:
		var sc = gp + _rot(Vector2(-ghx * 0.1, -gry * 0.5), ga)
		var R = gry * 1.08
		var shell = _ellipse(sc, R * 1.08, R, 30)
		_add(G_BODY, 2, {"t": "poly_ol", "pts": shell, "c": SHELL_C, "w": 4.5})
		_add(G_BODY, 2, {"t": "poly", "pts": _ellipse(sc + Vector2(R * 0.1, R * 0.15), R * 0.85, R * 0.75, 24), "c": SHELL_C.darkened(0.12)})
		var spiral := PoolVector2Array()
		for q in 40:
			var f = q / 39.0
			var an2 = f * TAU * 2.3
			spiral.append(sc + Vector2(cos(an2), sin(an2) * 0.92) * R * (0.08 + 0.88 * f))
		_add(G_BODY, 2, {"t": "line", "pts": spiral, "w": 3.5, "c": Color("#7a5530")})
		for q in 9:
			var an3 = TAU * q / 9.0
			_add(G_BODY, 2, {"t": "line", "pts": PoolVector2Array([sc + Vector2(cos(an3), sin(an3)) * R * 0.78, sc + Vector2(cos(an3), sin(an3)) * R * 0.98]), "w": 2.0, "c": Color("#9a7442")})
		_add(G_BODY, 2, {"t": "arc", "p": sc, "r": R * 0.82, "a0": PI * 1.15, "a1": PI * 1.55, "w": 4.0, "c": Color(1, 0.96, 0.85, 0.7)})
		if "fortress" in FUS:
			_add(G_BODY, 2, {"t": "arc", "p": sc, "r": R * 1.12, "a0": 0.0, "a1": TAU, "w": 3.0, "c": Color(0.55, 1.0, 0.6, 0.75)})
	if t_she >= 3:
		# armadillo: banded plates across thorax and head
		for i in range(1, ns):
			var p = pos[i]
			for b in 3:
				var ox = (b - 1) * HX[i] * 0.45
				var band := PoolVector2Array()
				for q in 9:
					var an4 = PI + PI * q / 8.0
					band.append(Vector2(ox + cos(an4) * HX[i] * 0.24, -RY[i] * 0.15 + sin(an4) * RY[i] * 0.98))
				_add(G_BODY, 2, {"t": "poly_ol", "pts": _xf(band, p, ang[i]), "c": Color("#b8976a").darkened(0.08 * b), "w": 3.0})

	# --- sonic ---
	if t_son >= 1:
		for q in 7:
			var x = ghx * (0.22 + 0.085 * q)
			_add(G_BODY, 2, {"t": "line", "pts": _xf(PoolVector2Array([Vector2(x, -gry * 0.92), Vector2(x + 2.5, -gry * 0.62)]), gp, ga), "w": 2.4, "c": dark.darkened(0.3)})
		var cc = gp + _rot(Vector2(ghx * 0.55, -gry * 1.05), ga)
		for q in 2:
			_add(G_BODY, 2, {"t": "arc", "p": cc, "r": 9.0 + q * 7.0, "a0": -PI * 0.9, "a1": -PI * 0.55, "w": 6.0, "c": INK})
			_add(G_BODY, 2, {"t": "arc", "p": cc, "r": 9.0 + q * 7.0, "a0": -PI * 0.9, "a1": -PI * 0.55, "w": 2.8, "c": Color("#ffe9a8")})
	if t_son >= 2:
		for side in 2:
			var grp = G_FAR if side == 0 else G_BODY
			var off = Vector2(-7, -3) if side == 0 else Vector2.ZERO
			var e0 = hp + off + _rot(Vector2(-hhx * 0.3, -hry * 0.7), ha)
			var tipe = e0 + Vector2(-16, -34) * hsc
			var ear = PoolVector2Array()
			for v in _quad(e0 + Vector2(-9, 2) * hsc, e0 + Vector2(-26, -18) * hsc, tipe, 7):
				ear.append(v)
			var back = _quad(tipe, e0 + Vector2(4, -22) * hsc, e0 + Vector2(8, 2) * hsc, 7)
			for q in range(1, back.size()):
				ear.append(back[q])
			_add(grp, 2, {"t": "poly_ol", "pts": ear, "c": (base if side == 1 else farc), "w": 4.0})
			if side == 1:
				var inner := PoolVector2Array()
				for v in ear:
					inner.append(e0 + (v - e0) * 0.62 + Vector2(-1, -2))
				_add(grp, 2, {"t": "poly", "pts": inner, "c": Color("#e89aa8")})
				for q in 3:
					_add(grp, 2, {"t": "line", "pts": PoolVector2Array([e0 + Vector2(-4 - q * 3, -6 - q * 7) * hsc, e0 + Vector2(-1 - q * 3, -9 - q * 7) * hsc]), "w": 1.6, "c": Color("#b86a7a")})
	if t_son >= 3:
		var tp: Vector2 = pos[ti]
		var dc = tp + _rot(Vector2(HX[ti] * 0.05, -RY[ti] * 0.95), ang[ti])
		var dr = HX[ti] * 0.55 + 6.0
		var dome := PoolVector2Array()
		for q in 15:
			var an5 = PI + PI * q / 14.0
			dome.append(dc + Vector2(cos(an5) * dr, sin(an5) * dr * 0.85))
		var ringc = CYAN if "thunderclap" in FUS else Color("#ffd36b")
		_add(G_BODY, 2, {"t": "poly_ol", "pts": dome, "c": Color("#e8d9a8"), "w": 4.0})
		for q in 3:
			_add(G_BODY, 2, {"t": "arc", "p": dc, "r": dr * (0.3 + 0.22 * q), "a0": PI * 1.05, "a1": PI * 1.95, "w": 2.6, "c": ringc.darkened(0.25 * q)})
		_add(G_BODY, 2, {"t": "circle", "p": dc + Vector2(-dr * 0.35, -dr * 0.5), "r": 3.0, "c": Color(1, 1, 1, 0.9)})
		for q in 2:
			_add(G_BODY, 2, {"t": "arc", "p": dc + Vector2(dr * 0.4, 0), "r": dr * (0.9 + 0.45 * q), "a0": -PI * 0.42, "a1": -PI * 0.08, "w": 6.5, "c": INK})
			_add(G_BODY, 2, {"t": "arc", "p": dc + Vector2(dr * 0.4, 0), "r": dr * (0.9 + 0.45 * q), "a0": -PI * 0.42, "a1": -PI * 0.08, "w": 3.0, "c": ringc})
		if "thunderclap" in FUS:
			var bz = PoolVector2Array([dc + Vector2(-4, -dr * 0.9), dc + Vector2(4, -dr * 0.55), dc + Vector2(-3, -dr * 0.45), dc + Vector2(5, -dr * 0.1)])
			_add(G_BODY, 2, {"t": "line", "pts": bz, "w": 5.0, "c": INK})
			_add(G_BODY, 2, {"t": "line", "pts": bz, "w": 2.5, "c": CYAN})

	# --- electric ---
	if t_ele >= 1:
		for q in 5:
			var pp = hp + _rot(Vector2(hhx * (0.42 + 0.1 * (q % 3)), hry * (0.02 + 0.13 * (q / 3) + 0.04 * (q % 2))), ha)
			_add(G_BODY, 2, {"t": "circle", "p": pp, "r": 3.6, "c": Color(CYAN.r, CYAN.g, CYAN.b, 0.9)})
			_add(G_BODY, 2, {"t": "circle", "p": pp, "r": 2.0, "c": INK})
	if t_ele >= 2:
		for q in 3:
			var bx = ghx * (0.32 - q * 0.38)
			var band = _xf(_quad(Vector2(bx + 3, -gry * 0.82), Vector2(bx - 9, 0), Vector2(bx + 3, gry * 0.72), 8), gp, ga)
			_add(G_BODY, 2, {"t": "line", "pts": band, "w": max(7.0, gry * 0.22), "c": Color(CYAN.r, CYAN.g, CYAN.b, 0.25)})
			_add(G_BODY, 2, {"t": "line", "pts": band, "w": max(3.0, gry * 0.09), "c": CYAN})
	if t_ele >= 3:
		var r0 = gp + _rot(Vector2(ghx * 0.05, -gry * 0.88), ga)
		var r1 = gp + _rot(Vector2(ghx * 0.5, -gry * 0.78), ga)
		var b0 = r0 + Vector2(-6, -28)
		var b1 = r1 + Vector2(4, -26)
		_taper(G_BODY, r0, b0, 3.2, 2.4, Color("#9aa3b5"))
		_taper(G_BODY, r1, b1, 3.2, 2.4, Color("#9aa3b5"))
		for bp in [b0, b1]:
			_add(G_BODY, 0, {"t": "circle", "p": bp, "r": 6.5 + OL * 0.7, "c": INK})
			_add(G_BODY, 1, {"t": "circle", "p": bp, "r": 6.5, "c": CYAN})
			_add(G_BODY, 2, {"t": "circle", "p": bp + Vector2(-2, -2), "r": 2.2, "c": Color.white})
		var zz = PoolVector2Array([b0 + Vector2(4, -2), b0.linear_interpolate(b1, 0.35) + Vector2(0, -10), b0.linear_interpolate(b1, 0.65) + Vector2(0, 4), b1 + Vector2(-4, -2)])
		_add(G_BODY, 2, {"t": "line", "pts": zz, "w": 5.0, "c": Color(CYAN.r, CYAN.g, CYAN.b, 0.45)})
		_add(G_BODY, 2, {"t": "line", "pts": zz, "w": 2.0, "c": Color.white})

	# --- silk ---
	if t_sil >= 1:
		var thread = _quad(gtip + Vector2(-4, 4), gtip + Vector2(-34, 6), Vector2(gtip.x - 48, -1), 10)
		_add(G_FAR, 2, {"t": "line", "pts": thread, "w": 1.8, "c": SILK_C})
		for q in 3:
			var sp = gtip + Vector2(2 - q * 3, 2 + q * 3)
			_add(G_BODY, 2, {"t": "circle", "p": sp, "r": 4.2, "c": INK})
			_add(G_BODY, 2, {"t": "circle", "p": sp, "r": 2.6, "c": base.lightened(0.25)})
	if t_sil >= 2:
		var wc = gtip + Vector2(-6, 10)
		var spokes := []
		for q in 6:
			var an6 = PI * (0.55 + 0.42 * q / 5.0)
			spokes.append(wc + Vector2(cos(an6), sin(an6)) * 40.0)
			_add(G_FAR, 2, {"t": "line", "pts": PoolVector2Array([wc, spokes[q]]), "w": 1.5, "c": Color(1, 1, 1, 0.55)})
		for ring in 3:
			var rp := PoolVector2Array()
			for q in 6:
				rp.append(wc.linear_interpolate(spokes[q], 0.35 + 0.25 * ring))
			_add(G_FAR, 2, {"t": "line", "pts": rp, "w": 1.3, "c": Color(1, 1, 1, 0.5)})
		_add(G_FAR, 2, {"t": "circle", "p": wc.linear_interpolate(spokes[2], 0.6), "r": 2.2, "c": Color(0.85, 0.95, 1.0, 0.9)})
		if "sonarweb" in FUS:
			for q in 2:
				_add(G_FAR, 2, {"t": "arc", "p": wc, "r": 46.0 + q * 8.0, "a0": PI * 0.55, "a1": PI * 0.95, "w": 2.5, "c": Color("#ffe9a8")})
	if t_sil >= 3:
		var ballc = PINK if "slingshot" in FUS else Color("#f2d38a")
		var ball = mouth + Vector2(14, 30) + Vector2(sin(gait * TAU) * 3.0, 0)
		_add(G_NEAR, 2, {"t": "line", "pts": PoolVector2Array([mouth + Vector2(4, 2), ball]), "w": 1.8, "c": Color(1, 1, 1, 0.85)})
		_add(G_NEAR, 2, {"t": "circle", "p": ball, "r": 8.5, "c": INK})
		_add(G_NEAR, 2, {"t": "circle", "p": ball, "r": 6.5, "c": ballc})
		_add(G_NEAR, 2, {"t": "circle", "p": ball + Vector2(-2, -2.5), "r": 2.0, "c": Color(1, 1, 1, 0.9)})

	# --- tongue ---
	if t_ton >= 1:
		var tl = [0.0, 22.0, 34.0, 44.0][t_ton]
		var tpts = _quad(mouth, mouth + Vector2(tl * 0.7, -2), mouth + Vector2(tl, tl * 0.45), 8)
		_tapered_chain(G_NEAR, Array(tpts), 3.0, 1.8, PINK.darkened(0.1))
		if t_ton >= 2:
			var tt = tpts[tpts.size() - 1]
			_add(G_NEAR, 0, {"t": "circle", "p": tt, "r": 5.5 + OL * 0.7, "c": INK})
			_add(G_NEAR, 1, {"t": "circle", "p": tt, "r": 5.5, "c": PINK.lightened(0.15)})
			_add(G_NEAR, 2, {"t": "circle", "p": tt + Vector2(-1.5, -1.5), "r": 1.8, "c": Color(1, 1, 1, 0.85)})

	# --- regen ---
	if t_reg >= 1:
		for i in [gi, ti]:
			for q in 2:
				var v0 = Vector2(-HX[i] * 0.4 + q * HX[i] * 0.5, -RY[i] * 0.1)
				var vein = _xf(_quad(v0, v0 + Vector2(8, -RY[i] * 0.3), v0 + Vector2(16, RY[i] * 0.1), 6), pos[i], ang[i])
				_add(G_BODY, 2, {"t": "line", "pts": vein, "w": 2.2, "c": Color(0.6, 1.0, 0.65, 0.65)})
	if t_reg >= 2:
		for side in 2:
			var grp2 = G_FAR if side == 0 else G_NEAR
			var gc = PINK if side == 1 else PINK.darkened(0.35)
			var off2 = Vector2(-6, -4) if side == 0 else Vector2.ZERO
			for q in 3:
				var g0 = hp + off2 + _rot(Vector2(-hhx * 0.62, -hry * 0.35 + q * hry * 0.3), ha)
				var g1 = g0 + Vector2(-14 - q * 2, -16 + q * 9) * hsc
				var g2 = g1 + Vector2(-8, -6 + q * 3) * hsc
				var gpts = _quad(g0, g1, g2, 5)
				_tapered_chain(grp2, Array(gpts), 2.8, 2.0, gc)
				if side == 1:
					for f in range(1, 5):
						var d = (gpts[f] - gpts[f - 1]).normalized()
						var n2 = Vector2(-d.y, d.x)
						_add(grp2, 2, {"t": "line", "pts": PoolVector2Array([gpts[f] + n2 * 2.0, gpts[f] + n2 * 6.5 - d * 2.0]), "w": 1.5, "c": gc.lightened(0.25)})
						_add(grp2, 2, {"t": "line", "pts": PoolVector2Array([gpts[f] - n2 * 2.0, gpts[f] - n2 * 6.5 - d * 2.0]), "w": 1.5, "c": gc.lightened(0.25)})
	if t_reg >= 3:
		var bc = gp + _rot(Vector2(-ghx * 0.42, -gry * 0.9), ga)
		_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(bc, 15.0, 10.0, -0.3, 18), "c": INK})
		_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(bc, 12.0, 7.5, -0.3, 18), "c": Color(1.0, 0.75, 0.82, 0.85)})
		for q in 2:
			_add(G_BODY, 2, {"t": "circle", "p": bc + Vector2(3 + q * 5, -2 - q * 1.5), "r": 1.6, "c": INK})
		_add(G_BODY, 2, {"t": "arc", "p": bc, "r": 9.0, "a0": PI * 1.1, "a1": PI * 1.5, "w": 2.0, "c": Color(1, 1, 1, 0.7)})


# Chameleon turret: a scaly cone around the eye, pupil aimed forward.
func _turret_eye(hp: Vector2, hx: float, ry: float, ha: float, base: Color, dark: Color) -> void:
	var ec = hp + _rot(Vector2(hx * 0.18, -ry * 0.18), ha)
	var er = clamp(ry * 0.3, 6.5, 11.0) * 1.7
	_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(ec, er + 4.0, er * 0.9 + 4.0, ha, 20), "c": INK})
	_add(G_BODY, 2, {"t": "poly", "pts": _ellipse_r(ec, er, er * 0.9, ha, 20), "c": base.lightened(0.3)})
	for q in 3:
		_add(G_BODY, 2, {"t": "arc", "p": ec, "r": er * (0.55 + 0.17 * q), "a0": 0.0, "a1": TAU, "w": 2.2, "c": dark.darkened(0.2)})
	for q in 8:
		var an = TAU * q / 8.0
		_add(G_BODY, 2, {"t": "circle", "p": ec + Vector2(cos(an), sin(an)) * er * 0.9, "r": 1.8, "c": base.lightened(0.5)})


# ---------- shapes (local space, +x toward the head) ----------
func _shape(kind: String, hx: float, ry: float, off: Vector2 = Vector2.ZERO) -> PoolVector2Array:
	match kind:
		"gaster":
			return _gaster_pts(hx, ry, off)
		"head":
			var pts := PoolVector2Array()
			for i in 30:
				var an = TAU * i / 30.0
				var ca = cos(an)
				var sa = sin(an)
				var sx = sign(ca) * pow(abs(ca), 0.85)
				var sy = sign(sa) * pow(abs(sa), 0.85)
				var narrow = 1.0 - 0.22 * pow(max(0.0, ca), 2.0)   # tapers toward the mouth
				pts.append(off + Vector2(sx * hx, sy * ry * narrow))
			return pts
		"thorax":
			var pts2 := PoolVector2Array()
			for i in 32:
				var an = TAU * i / 32.0
				var ca = cos(an)
				var sa = sin(an)
				var yy = sa * ry
				if sa < 0.0:
					# pronotum hump at the front, propodeal slope at the rear
					yy *= 1.0 + 0.4 * exp(-pow((ca - 0.38) / 0.33, 2.0)) - 0.2 * exp(-pow((ca + 0.6) / 0.3, 2.0))
				else:
					yy *= 0.85
				pts2.append(off + Vector2(ca * hx, yy))
			return pts2
	return _ellipse(off, hx, ry, 20)


func _gaster_pts(hx: float, ry: float, off: Vector2 = Vector2.ZERO) -> PoolVector2Array:
	var pts := PoolVector2Array()
	for i in 32:
		var an = TAU * i / 32.0
		var ca = cos(an)
		var sa = sin(an)
		var rear = max(0.0, -ca)
		var front = max(0.0, ca)
		var yy = sa * ry * (1.0 - 0.32 * pow(rear, 2.5)) * (1.0 - 0.18 * pow(front, 3.0))
		yy += pow(rear, 3.0) * ry * 0.22   # tip droops
		var xx = ca * hx * (1.0 + 0.08 * pow(rear, 2.0))
		pts.append(off + Vector2(xx, yy))
	return pts


# ---------- command builders ----------
func _add(grp: int, pass_i: int, op: Dictionary) -> void:
	_G[grp][pass_i].append(op)


# Tapered capsule from a (radius ra) to b (radius rb), with ink.
func _taper(grp: int, a: Vector2, b: Vector2, ra: float, rb: float, col: Color, ol: float = OL) -> void:
	if a.distance_to(b) < 0.5:
		_add(grp, 0, {"t": "circle", "p": a, "r": ra + ol, "c": INK})
		_add(grp, 1, {"t": "circle", "p": a, "r": ra, "c": col})
		return
	_add(grp, 0, {"t": "poly", "pts": _capsule(a, b, ra + ol, rb + ol), "c": INK})
	_add(grp, 1, {"t": "poly", "pts": _capsule(a, b, ra, rb), "c": col})


func _tapered_chain(grp: int, pts: Array, r0: float, r1: float, col: Color) -> void:
	var n = pts.size()
	for q in n - 1:
		var f0 = float(q) / (n - 1)
		var f1 = float(q + 1) / (n - 1)
		_taper(grp, pts[q], pts[q + 1], lerp(r0, r1, f0), lerp(r0, r1, f1), col)


func _capsule(a: Vector2, b: Vector2, ra: float, rb: float) -> PoolVector2Array:
	var d = (b - a).normalized()
	var base_ang = d.angle()
	var pts := PoolVector2Array()
	var steps = 7
	for i in steps + 1:
		var an = base_ang - PI * 0.5 + PI * i / steps
		pts.append(b + Vector2(cos(an), sin(an)) * rb)
	for i in steps + 1:
		var an2 = base_ang + PI * 0.5 + PI * i / steps
		pts.append(a + Vector2(cos(an2), sin(an2)) * ra)
	return pts


# ---------- executor ----------
func _exec(op: Dictionary) -> void:
	match op["t"]:
		"poly":
			draw_colored_polygon(op["pts"], op["c"], PoolVector2Array(), null, null, true)
		"line":
			draw_polyline(op["pts"], op["c"], op["w"], true)
			for p in op["pts"]:  # round caps + joins (Godot 3 polylines have none)
				draw_circle(p, op["w"] / 2.0, op["c"])
		"ring":
			var closed = PoolVector2Array(op["pts"])
			closed.append(op["pts"][0])
			draw_polyline(closed, op["c"], op["w"], true)
		"poly_ol":
			var closed2 = PoolVector2Array(op["pts"])
			closed2.append(op["pts"][0])
			draw_polyline(closed2, INK, op["w"] * 2.0, true)
			for p in op["pts"]:
				draw_circle(p, op["w"], INK)
			draw_colored_polygon(op["pts"], op["c"], PoolVector2Array(), null, null, true)
		"circle":
			draw_circle(op["p"], op["r"], op["c"])
		"arc":
			draw_arc(op["p"], op["r"], op["a0"], op["a1"], 20, op["c"], op["w"], true)


# ---------- geometry ----------
func _rot(v: Vector2, a: float) -> Vector2:
	return v.rotated(a)


func _xf(pts: PoolVector2Array, c: Vector2, a: float) -> PoolVector2Array:
	var out := PoolVector2Array()
	for v in pts:
		out.append(c + v.rotated(a))
	return out


func _ellipse(c: Vector2, rx: float, ry: float, n: int = 28) -> PoolVector2Array:
	var pts = PoolVector2Array()
	for i in n:
		var a = TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _ellipse_r(c: Vector2, rx: float, ry: float, rot: float, n: int = 16) -> PoolVector2Array:
	var pts = PoolVector2Array()
	for i in n:
		var a = TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


func _drop(c: Vector2, r: float) -> PoolVector2Array:
	var pts = PoolVector2Array()
	for i in 16:
		var a = TAU * i / 16.0
		var v = Vector2(cos(a) * r, sin(a) * r)
		if v.y < 0.0:
			v.x *= 1.0 + v.y / r * 0.85
			v.y *= 1.5
		pts.append(c + v)
	return pts


func _quad(a: Vector2, b: Vector2, c: Vector2, n: int) -> PoolVector2Array:
	var pts = PoolVector2Array()
	for i in n + 1:
		var t = float(i) / n
		pts.append(a.linear_interpolate(b, t).linear_interpolate(b.linear_interpolate(c, t), t))
	return pts
