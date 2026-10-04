extends Node2D
# Draws the bird (colony_sim.bird): a soft shadow on the open ground, then the bird itself high above the meadow, stooping
# as it closes on an ant. While winged ants tear at it (bird["hit"] > 0) it flinches, blinks red and sheds feathers; when its hit
# points run out the sim hands over a bird_fall, drawn here as the dead bird tumbling out of the sky with its wings limp and a
# shadow that gathers under it, and then it lies on the ground as a carcass pile (world_view draws that with draw_dead below).
# Drawn before the light pass so dusk and night tint it like everything else.

const CreatureArt = preload("res://mods-unpacked/Judah-InfDNA/content/colony/creature_art.gd")
const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const Rig = preload("res://mods-unpacked/Judah-InfDNA/content/colony/rig_art.gd")
const Lib = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")

const INK = Color("#15121a")
const FALL_T = 1.3                      # seconds the sim lets bird_fall drop (colony_sim._step_bird_fall)
const LANE = 0.5                        # the bird, its shadow, its feathers and the carcass all live in this depth lane
const FEATHER_DARK = Color(0.24, 0.23, 0.31)
const FEATHER_CREAM = Color(0.83, 0.77, 0.66)
# The dead bird, in the art's own pixels: the point it tumbles about (the middle of the body, measured from the neck / shoulder origin the
# live bird is drawn from), and how far below that point the pose reaches the ground (measured; it varies about +-10 with the tilt).
const DEAD_PIVOT = Vector2(-60, 20)
const DEAD_REACH = 198.0
const DEAD_REACH_K = -86.0              # ... which shrinks this much per radian of extra tilt (measured over 2.70..3.00)
const DEAD_SINK = 10.0                  # art px the carcass settles into the grass
const DEAD_TILT = 2.85                  # radians: lies on its back, feet up, head down, wings fanned out behind (a quarter turn reads as a nose-dive)
const DEPTH = GroundView.DEPTH
const WING_B_DEAD = -0.5                # the near and far wing when limp, in rig_art's wing angles
const WING_A_DEAD = -0.1
const HEAD_DEAD = 0.15                  # the head dropped about the neck
# Points on the outline of the dead bird (art px from the pivot, facing +1, at DEAD_TILT): where a rotting carcass sheds its specks.
const DEAD_EDGE = [Vector2(-232, 62), Vector2(-216, 104), Vector2(-202, 14), Vector2(-184, 70), Vector2(-174, 118), Vector2(-164, -50), Vector2(-156, 32),
	Vector2(-120, -28), Vector2(-84, -96), Vector2(-72, -16), Vector2(-8, -130), Vector2(-8, -30), Vector2(-6, -80), Vector2(28, -164), Vector2(62, 112),
	Vector2(94, -130), Vector2(106, 74), Vector2(124, -166), Vector2(148, 118), Vector2(166, -148), Vector2(210, -178), Vector2(236, -132), Vector2(260, -170),
	Vector2(276, 24), Vector2(300, -104), Vector2(304, -158), Vector2(316, 96), Vector2(322, 42), Vector2(336, -32), Vector2(344, -102)]

var sim
var cam
var ground
var _t := 0.0
var _was := false
var _px := 0.0
var _hover := 0.0     # 1 while the bird is over its prey and not travelling: it then wheels about instead of hanging still
var _feathers := []   # loose feathers: {p, v, a, w, age, life, sz, ph, cream}
var _spawn := 0.0
var _last_origin := Vector2.ZERO    # where the live bird was last drawn
var _last_ok := false
var _had_fall := false
var _fall_origin = null             # where the falling bird starts: the live bird's last drawn spot, taken once when the fall begins
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	_t += delta
	if sim == null or ground == null:
		return
	var b = sim.bird
	var f = sim.bird_fall
	if f != null and not _had_fall:
		# a fall has just begun: it starts where the bird was last seen (circling included), if that was this bird
		_fall_origin = _last_origin if (_last_ok and abs(_px - float(f["x"])) < 3.0) else null
	_had_fall = f != null
	if f == null:
		_fall_origin = null
	if b != null:
		_hover = lerp(_hover, 0.0 if abs(float(b["x"]) - _px) > 0.05 else 1.0, clamp(delta * 3.0, 0.0, 1.0))
		_px = float(b["x"])
		_last_origin = _bird_pose(b)[0]
		_last_ok = true
	elif f == null:
		_last_ok = false
	_shed(delta, b, f)
	var on = b != null or f != null or not _feathers.empty()
	# (a canvas keeps its last drawing until update() is called again, so the frame after it goes quiet must be drawn too, or the last bird / flag / leaf / raindrop stays frozen on screen)
	if on or _was:
		update()
	_was = on


# ---------------------------------------------------------------- where things are
# The ground under a cell column at the bird's lane: [y of the ground, perspective scale].
func _ground_at(xcell: float) -> Array:
	return [GroundView.lane_y(ground.smooth_px(int(xcell)), LANE), GroundView.persp(LANE)]


# Where the live bird is drawn: [position, ground y, perspective scale, facing].
func _bird_pose(b: Dictionary) -> Array:
	var C = sim.grid.CELL
	var gp = _ground_at(float(b["x"]))
	var gy = float(gp[0])
	var ps = float(gp[1])
	var height = (34.0 + 230.0 * float(b["alt"])) * ps
	var pos = Vector2((float(b["x"]) + 0.5) * C, gy - height)
	pos += Vector2(sin(_t * 1.1) * 60.0 * ps, sin(_t * 2.3) * 9.0 * ps) * _hover       # circling over its prey, never frozen
	var face = int(b["face"]) if _hover < 0.3 else (1 if cos(_t * 1.1) >= 0.0 else -1)
	return [pos, gy, ps, face]


# The dead bird's fall: where the middle of its body is, how it is turned, and the ground it is falling to. It starts exactly where the live bird
# was last drawn (circling included) and speeds up like anything let go of (u is 0..1 over the drop); the last stretch of the turn and of the
# slide sideways lands it at the carcass's own spot and angle, so there is no jump when the pile takes over.
func _fall_pose(f: Dictionary) -> Dictionary:
	var C = sim.grid.CELL
	var g = sim.grid
	var u = clamp(float(f["t"]) / FALL_T, 0.0, 1.0)
	var face = int(f["face"])
	var spin = float(f["spin"])
	var landx = int(clamp(float(f["x"]), g.sim_l() + 3, g.sim_r() - 3))      # where the sim puts the carcass
	var ps = GroundView.persp(LANE)
	var sc = bird_scale(ps)
	var base = carcass_base(g, landx)                                        # the carcass pile's own foot (world_view draws it from here)
	var gy = base.y
	var origin = _fall_origin if _fall_origin != null else Vector2((float(f["x"]) + 0.5) * C, gy - (34.0 + 230.0 * float(f["alt"])) * ps)
	var p0 = origin + Vector2(face * sc * DEAD_PIVOT.x, sc * DEAD_PIVOT.y)       # the middle of the body, where the live bird had it
	var p1 = carcass_pivot(base, sc, spin)
	var drop = u * u                                                          # let go: it falls faster and faster
	var pos = Vector2(lerp(p0.x, p1.x, smoothstep(0.0, 1.0, u)), lerp(p0.y, p1.y, drop))
	# it tumbles forward or back (which one is the sim's `spin`), turning faster as it goes, and ends on its back at the carcass's angle
	var total = DEAD_TILT + 0.15 * spin
	if spin < 0.0:
		total -= TAU
	var ang = face * total * pow(u, 1.2) + sin(u * 11.0 + spin * 3.0) * 0.12 * (1.0 - u)
	return {"pos": pos, "gy": gy, "ps": ps, "sc": sc, "u": u, "drop": drop, "ang": ang, "fold": clamp((1.0 - float(f["alt"])) * 0.45, 0.0, 1.0)}


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if sim == null or ground == null:
		return
	if sim.bird != null:
		_draw_bird(sim.bird)
	if sim.bird_fall != null:
		_draw_fall(sim.bird_fall)
	_draw_feathers()


func _draw_bird(b: Dictionary) -> void:
	var bp = _bird_pose(b)
	var pos: Vector2 = bp[0]
	var gy = float(bp[1])
	var ps = float(bp[2])
	var face = int(bp[3])
	var alt = float(b["alt"])
	var fade = clamp(b["t"] / 2.0, 0.0, 1.0)
	var hit = float(b.get("hit", 0.0))
	# shadow
	draw_set_transform(Vector2(pos.x, gy), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, (95.0 - 25.0 * alt) * ps, Color(0.04, 0.07, 0.03, 0.28 * (1.0 - 0.5 * alt) * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fold = clamp(float(b["dive"]) * 1.2 + (1.0 - alt) * 0.45, 0.0, 1.0)
	var hurt = false
	if hit > 0.0:
		# winged ants are on it: it flinches and blinks red
		hurt = fmod(_t, 0.22) < 0.1
		pos += Vector2(sin(_t * 83.0), cos(_t * 71.0)) * 3.0 * ps * clamp(hit / 0.3, 0.0, 1.0)
	if Rig.bird_available():
		Rig.bird(self, pos, 0.95 * ps, _t, face, fold, fade, hurt)


func _draw_fall(f: Dictionary) -> void:
	var fp = _fall_pose(f)
	var pos: Vector2 = fp["pos"]
	var u = float(fp["u"])
	var ps = float(fp["ps"])
	var gp = Vector2(pos.x, float(fp["gy"]))
	# the live bird's broad shadow hands over to one that gathers under the body as it comes down
	var alt = float(f["alt"])
	if u < 1.0:
		draw_set_transform(gp, 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, (95.0 - 25.0 * alt) * ps, Color(0.04, 0.07, 0.03, 0.28 * (1.0 - 0.5 * alt) * (1.0 - u) * (1.0 - u)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_dead_shadow(self, gp, ps, float(fp["drop"]), smoothstep(0.0, 0.5, u))
	# the wings go limp at once and flop about in the rush of air, settling into the carcass's pose as it lands
	var limp = smoothstep(0.0, 0.3, u)
	if not draw_dead(self, pos, float(fp["sc"]), int(f["face"]), float(fp["ang"]), limp, float(fp["fold"]) * (1.0 - limp), _t, 1.0, Color.white, null, 0.3 * (1.0 - u)):
		draw_circle(pos, 30.0 * ps, FEATHER_DARK)


func _draw_feathers() -> void:
	for fe in _feathers:
		var fade = clamp(min(float(fe["age"]) * 6.0, (float(fe["life"]) - float(fe["age"])) * 1.2), 0.0, 1.0)
		if fade > 0.0:
			draw_feather(self, fe["p"], float(fe["a"]), float(fe["sz"]), bool(fe["cream"]), fade)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# One loose feather (length L px, lying along angle `a`), inked like everything else. Also used for the ones lying round a carcass.
static func draw_feather(ci: CanvasItem, p: Vector2, a: float, L: float, cream: bool, alpha: float) -> void:
	var W = L * 0.24
	var col = FEATHER_CREAM if cream else FEATHER_DARK
	var shape = PoolVector2Array([Vector2(-L * 0.5, 0), Vector2(-L * 0.18, -W), Vector2(L * 0.32, -W * 0.8), Vector2(L * 0.52, 0), Vector2(L * 0.32, W * 0.8), Vector2(-L * 0.18, W)])
	var grown = PoolVector2Array()
	for q in shape:
		grown.append(q * 1.28 + Vector2(-0.8, 0))
	ci.draw_set_transform(p, a, Vector2.ONE)
	ci.draw_colored_polygon(grown, Color(INK.r, INK.g, INK.b, alpha))
	ci.draw_colored_polygon(shape, Color(col.r, col.g, col.b, alpha))
	ci.draw_line(Vector2(-L * 0.55, 0), Vector2(L * 0.4, 0), Color(INK.r, INK.g, INK.b, 0.55 * alpha), 1.2, true)


# ---------------------------------------------------------------- loose feathers
# Fresh feathers come off a bird that is being bitten (a few a second) and off one that is falling; they drift down swaying and
# lie on the ground a moment before they fade.
func _shed(delta: float, b, f) -> void:
	if (b != null and float(b.get("hit", 0.0)) > 0.0) or f != null:
		_spawn -= delta
		var cap = 10 if f != null else 8
		if _spawn <= 0.0 and _feathers.size() < cap:
			_spawn = 0.07 if f != null else 0.16
			var at: Vector2
			if f != null:
				at = _fall_pose(f)["pos"]
			else:
				at = _bird_pose(b)[0]
			var ps = GroundView.persp(LANE)
			at += Vector2(_rng.randf_range(-70.0, 30.0) * ps * (1.0 if int(b["face"] if b != null else f["face"]) > 0 else -1.0), _rng.randf_range(-20.0, 30.0) * ps)
			var kick = 70.0 if f != null else 40.0
			_feathers.append({"p": at, "v": Vector2(_rng.randf_range(-kick, kick), _rng.randf_range(-kick * 0.8, kick * 0.2)), "a": _rng.randf() * TAU, "w": _rng.randf_range(-3.0, 3.0),
				"age": 0.0, "life": _rng.randf_range(3.8, 5.6), "sz": _rng.randf_range(15.0, 24.0) * ps, "ph": _rng.randf() * TAU, "cream": _rng.randf() < 0.4})
	else:
		_spawn = 0.0
	var C = sim.grid.CELL
	var i = _feathers.size() - 1
	while i >= 0:
		var fe = _feathers[i]
		fe["age"] += delta
		if fe["age"] >= fe["life"]:
			_feathers.remove(i)
			i -= 1
			continue
		var gy = float(_ground_at(float(fe["p"].x) / C)[0])
		if fe["p"].y >= gy - 1.0:
			fe["p"].y = gy - 1.0              # it has landed: it just lies there
			fe["v"] = Vector2.ZERO
			fe["w"] = 0.0
		else:
			var v: Vector2 = fe["v"]
			v.y = min(v.y + 150.0 * delta, 38.0)         # light: it reaches its slow drifting speed almost at once
			v.x = lerp(v.x, 0.0, clamp(delta * 1.6, 0.0, 1.0))
			fe["v"] = v
			var sway = sin(float(fe["age"]) * 3.4 + float(fe["ph"]))
			fe["p"] += Vector2(v.x + sway * 34.0, v.y * (0.6 + 0.4 * (1.0 - abs(sway)))) * delta
			fe["a"] += (float(fe["w"]) * 0.5 + sway * 1.4) * delta
		i -= 1


# ---------------------------------------------------------------- the dead bird
# How big the bird is drawn at a lane's perspective scale (the same as the live bird).
static func bird_scale(ps: float) -> float:
	return Rig.BIRD_K * 0.95 * ps


# The angle the dead bird ends at (and so the carcass lies at), radians clockwise on the screen: on its back, a little askew.
static func dead_angle(face: int, spin: float) -> float:
	return float(face) * (DEAD_TILT + 0.15 * spin)


# The foot of a carcass pile at cell column x: the same point world_view draws every pile from (the ground five columns
# about it, at the middle lane), so the falling bird lands exactly where the carcass then lies.
static func carcass_base(g, x: int) -> Vector2:
	var acc := 0.0
	for k in range(-2, 3):
		acc += g.surf_y(x + k)
	return Vector2((float(x) + 0.5) * g.CELL, acc / 5.0 * g.CELL - DEPTH * 0.45)


# Where the middle of the dead bird's body sits for it to lie on the ground at `base` (its lowest feathers just into the grass).
# `sc` as for draw_dead; the reach depends on how far it is turned, i.e. on the sim's spin.
static func carcass_pivot(base: Vector2, sc: float, spin: float) -> Vector2:
	return base + Vector2(0.0, -sc * (DEAD_REACH + DEAD_REACH_K * 0.15 * spin - DEAD_SINK))


# The dead bird's soft shadow on the ground: `near` 0 (high up: small, faint) to 1 (lying there). `ground` is the point on the ground under it.
static func draw_dead_shadow(ci: CanvasItem, ground: Vector2, ps: float, near: float, alpha: float) -> void:
	var sr = lerp(46.0, 66.0, near) * ps
	ci.draw_set_transform(ground, 0.0, Vector2(1.0, 0.28))
	ci.draw_circle(Vector2.ZERO, sr * 1.25, Color(0.04, 0.07, 0.03, lerp(0.07, 0.13, near) * alpha))
	ci.draw_circle(Vector2.ZERO, sr * 0.8, Color(0.04, 0.07, 0.03, lerp(0.10, 0.22, near) * alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _put(ci: CanvasItem, base: Transform2D, tex, pos: Vector2, pivot: Vector2, ang: float, mod: Color) -> void:
	var tp = Transform2D(Vector2(1, 0), Vector2(0, 1), pivot)
	ci.draw_set_transform_matrix(base * tp * Transform2D(ang, Vector2.ZERO) * tp.affine_inverse())
	ci.draw_texture(tex, pos, mod)


# The bird from the same five drawn pieces as the live one (rig_art.gd), but dead: wings fallen open and limp (`limp` 0 keeps the
# wing-beat pose it died in, 1 lets them hang and loll; `flutter` is the time they stir in the wind of the fall), the head dropped, the eye
# crossed out. Turned by `ang` about the middle of the body, which sits at `piv`; `scale` as for Rig.bird. `pa` is an optional list of five
# alphas (far foot, far wing, near wing, head, near foot) for a bird coming apart; `flop` (radians) lets the limp wings flap loosely with
# `flutter`, as in the wind of a fall; `outer` (a Transform2D) is applied on top of it all, e.g. to slump a rotting carcass toward the
# ground. Returns false when the art is missing.
static func draw_dead(ci: CanvasItem, piv: Vector2, scale: float, face: int, ang: float, limp: float, fold: float, flutter: float, alpha: float, tint: Color, pa = null, flop: float = 0.0, outer = null) -> bool:
	var lib = Lib.get_lib()
	var th = lib.tex("bird_head.png")
	var twb = lib.tex("bird_wing_b.png")
	var twa = lib.tex("bird_wing_a.png")
	var tc1 = lib.tex("bird_claw_1.png")
	var tc2 = lib.tex("bird_claw_2.png")
	if th == null or twb == null or twa == null or tc1 == null or tc2 == null:
		return false
	var s = scale
	var base = Transform2D(ang, piv) * Transform2D(Vector2(face * s, 0), Vector2(0, s), Vector2.ZERO) * Transform2D(0.0, -DEAD_PIVOT)
	if outer != null:
		base = outer * base
	var a0 = alpha
	var al = [1.0, 1.0, 1.0, 1.0, 1.0]
	if pa != null:
		al = pa
	var mod = Color(tint.r, tint.g, tint.b, a0)
	var dim = Color(tint.r * 0.72, tint.g * 0.72, tint.b * 0.8, a0)
	var wb = twb.get_size()
	var wa = twa.get_size()
	var org = Vector2(wb.x * 0.88, wb.y * 0.6)
	var hinge_b = Vector2(wb.x * 0.72, wb.y * 0.62) - org
	var hinge_a_src = Vector2(wa.x * 0.8, wa.y * 0.75)
	var pos_b = -org
	var pos_a = hinge_b + Vector2(-8, -10) - hinge_a_src
	var beat = 0.5 + 0.5 * sin(flutter * 9.0)
	var stir_b = sin(flutter * 7.0) * flop * limp
	var stir_a = sin(flutter * 7.0 + 1.9) * flop * limp
	var ang_b = lerp(lerp(-0.95 * beat, 0.55, fold), WING_B_DEAD + stir_b, limp)
	var ang_a = lerp(lerp(-0.95 * (0.5 + 0.5 * sin(flutter * 9.0 - 0.7)), 0.45, fold), WING_A_DEAD + stir_a, limp)
	var c2 = Vector2(-150, -10) + Vector2(-15, 5) * limp
	var c1 = Vector2(-105, -30) + Vector2(-15, 5) * limp
	if al[0] > 0.01:
		_put(ci, base, tc2, c2, c2 + Vector2(tc2.get_size().x * 0.4, 0), lerp(0.0, -0.5, limp), Color(dim.r, dim.g, dim.b, a0 * al[0]))
	if al[1] > 0.01:
		_put(ci, base, twa, pos_a, hinge_b + Vector2(-8, -10), ang_a, Color(dim.r, dim.g, dim.b, a0 * al[1]))
	if al[2] > 0.01:
		_put(ci, base, twb, pos_b, hinge_b, ang_b, Color(mod.r, mod.g, mod.b, a0 * al[2]))
	if al[4] > 0.01:
		_put(ci, base, tc1, c1 + Vector2(0, 8.0 * limp), c1 + Vector2(tc1.get_size().x * 0.4, 0), lerp(0.0, -0.5, limp), Color(mod.r, mod.g, mod.b, a0 * al[4]))
	if al[3] > 0.01:
		# the head lolls forward and down about the neck
		var hm = Color(mod.r, mod.g, mod.b, a0 * al[3])
		var neck = Vector2(60, 190)
		var hp = Vector2(-36, -157)
		ci.draw_set_transform_matrix(base * Transform2D(Vector2(1, 0), Vector2(0, 1), hp + neck * 0.9) * Transform2D(lerp(0.0, HEAD_DEAD, limp), Vector2.ZERO) * Transform2D(Vector2(0.9, 0), Vector2(0, 0.9), -neck * 0.9))
		ci.draw_texture(th, Vector2.ZERO, hm)
		if limp > 0.4:
			# the pink eye is gone: a dark disc and a cream X
			var ec = Vector2(167, 129)
			var k = clamp((limp - 0.4) / 0.4, 0.0, 1.0)
			ci.draw_circle(ec, 14.0, Color(0.04, 0.02, 0.05, hm.a))
			var xc = Color(0.86, 0.8, 0.68, hm.a * k)
			ci.draw_line(ec + Vector2(-7, -7), ec + Vector2(7, 7), xc, 4.5, true)
			ci.draw_line(ec + Vector2(-7, 7), ec + Vector2(7, -7), xc, 4.5, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
