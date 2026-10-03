extends Node2D
# Raiders: Brotato / Abyssal Terrors sprites, squash-bob like vanilla,
# hit flash, HP bars. Plus combat effects (puffs, floating numbers).

const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")
const CreatureArt = preload("res://mods-unpacked/Judah-InfDNA/content/colony/creature_art.gd")
const Lib = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
const Critters = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_critters.gd")
const SPINE_N = 18           # joints in a worm's spine
const INK = Color("#15121a")
const FONT_PATH = "res://resources/fonts/raw/Anybody-Medium.ttf"

const P = "res://particles/sprites/particle_%d.png"
const LIFE = {"puff": 1.0, "text": 1.2, "spark": 0.45, "heal": 1.3, "ring": 0.7, "hatch": 0.9, "burst": 0.8,
	"wave": 0.6, "arc": 0.28, "beam": 0.22, "web": 1.4, "corpse": 0.9}

const ANT_SCALE = 0.24      # the same drawing scale as ant_view.gd: a kin ant is as big as one of yours
const KIN_SIZE = {"small": 1.0, "brute": 1.1, "elite": 1.22, "boss": 1.4}   # their soldiers are only a little bigger than yours (the body plan itself carries the rest)

var sim
var baker            # sprite_baker.gd (set by the scene): the rival's kin are drawn from their genome, like your own ants
var perf             # perf.gd (optional): caps the effects drawn per frame
var _dust := []
var _stars := []
var _plus
var _sparkle
var _ring
var _tex := {}
var _font: DynamicFont
var _t := 0.0
var _spines := {}     # raider id -> {"pts": [Vector2], "ph": crawl phase, "t": last time, "flip": bool}: the worms' spines (see _draw_spine)
var under: Node2D     # hit sparks, dust and bursts are drawn on this layer, UNDER the ants and raiders (the scene puts it there), so a fight is never covered by its own effects
const UNDER_KINDS = ["spark", "puff", "burst"]


func _ready() -> void:
	for kind in EnemyDefs.DEFS.keys():
		for path in EnemyDefs.DEFS[kind]["tex"]:
			if ResourceLoader.exists(path):
				_tex[kind] = load(path)
				break
	for i in range(1, 9):
		_dust.append(load(P % i) if ResourceLoader.exists(P % i) else null)
	for i in range(16, 23):
		_stars.append(load(P % i) if ResourceLoader.exists(P % i) else null)
	_plus = load(P % 26) if ResourceLoader.exists(P % 26) else null
	_sparkle = load(P % 29) if ResourceLoader.exists(P % 29) else null
	_ring = load(P % 30) if ResourceLoader.exists(P % 30) else null
	_font = DynamicFont.new()
	if ResourceLoader.exists(FONT_PATH):
		_font.font_data = load(FONT_PATH)
	_font.size = 30
	_font.outline_size = 3
	_font.outline_color = INK


func _process(delta: float) -> void:
	_t += delta
	if not _spines.empty() and int(_t * 2.0) != int((_t - delta) * 2.0):
		forget_spines()
	var i = 0
	while i < sim.fx.size():
		var f = sim.fx[i]
		f["t"] += delta
		if f["t"] > LIFE.get(f["kind"], 1.2):
			sim.fx.remove(i)
		else:
			i += 1
	update()
	if under != null:
		under.update()


func draw_enemy(ci: CanvasItem, e, feet: Vector2, depth_scale: float, shade: float, alpha: float = 1.0, air: float = 0.0) -> void:
	var h = EnemyDefs.height_of(e) * depth_scale
	var tex = _tex.get(e.kind)
	var moving = e.tx != e.x or e.ty != e.y
	var bob = sin(_t * (12.0 if moving else 4.0) + e.id) * (0.06 if moving else 0.025)
	var mod = Color(1, 0.5, 0.5) if e.flash > 0.0 else Color.white
	mod = Color(mod.r * shade, mod.g * shade, mod.b * shade, (0.75 if e.state == 2 else 1.0) * alpha)
	var art = e.def.get("art", "")
	if e.genome != null:
		_draw_kin(ci, e, feet, depth_scale, shade, alpha, moving)
	elif e.def.get("spine", "") != "" and _draw_spine(ci, e, feet, h, shade, alpha, moving):
		pass
	elif e.def.has("critter"):
		_draw_critter(ci, e, feet, depth_scale, shade, alpha, moving)
		if e.def.get("fly", false):
			feet = feet - Vector2(0, 40.0 * depth_scale)     # its bar rides with it
	elif art != "":
		var fly = e.def.get("fly", false)
		var lift = 6.0 + 22.0 * air if fly else 0.0
		var mouth = (0.5 + 0.5 * sin(_t * 8.0 + e.id)) if (e.engaged and e.state != 2) else (0.12 + 0.12 * sin(_t * 1.6 + e.id))
		var em = _emerge_k(e) if e.void_born else 1.0
		if em < 1.0:
			_draw_emerging(ci, e, feet, depth_scale, shade, alpha, h, em, moving, mouth)
		else:
			CreatureArt.draw(art, ci, feet, depth_scale * float(e.def.get("art_scale", 1.0)), shade, alpha * (0.75 if e.state == 2 else 1.0), _t, e.facing, e.id, moving, e.flash > 0.0, lift, mouth)
		if fly:
			feet = feet - Vector2(0, (lift + 14.0) * depth_scale)     # marks and bars ride with the flyer
	elif tex != null:
		var s = h / tex.get_height()
		ci.draw_set_transform(feet, 0.0, Vector2(e.facing * s, s * (1.0 + bob)))
		ci.draw_texture(tex, Vector2(-tex.get_width() * 0.5, -tex.get_height()), mod)
	else:
		ci.draw_set_transform(feet, 0.0, Vector2(1.0, 1.0 + bob))
		ci.draw_circle(Vector2(0, -h * 0.5), h * 0.5, INK)
		ci.draw_circle(Vector2(0, -h * 0.5), h * 0.5 - 4.0, Color("#b0413e") * mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mid = feet + Vector2(0, -h * 0.5)
	if e.stun_t > 0.0:
		# snared: wrapped in silk, a few loose strands swaying
		for j in 4:
			var yy = -h * (0.2 + 0.18 * j)
			ci.draw_line(feet + Vector2(-h * 0.42, yy + 6.0), feet + Vector2(h * 0.42, yy - 6.0), Color(1, 1, 1, 0.75), 3.0, true)
		ci.draw_arc(mid, h * 0.5, 0.0, TAU, 24, Color(1, 1, 1, 0.55), 2.5, true)
		var sw = sin(_t * 3.0 + e.id) * 6.0
		ci.draw_line(feet + Vector2(-h * 0.3, -h * 0.9), feet + Vector2(-h * 0.36 + sw, -h * 1.15), Color(1, 1, 1, 0.6), 2.0, true)
	elif e.slow_t > 0.0:
		# webbed: sticky strands trailing from the legs
		for j in 3:
			var sx = (j - 1) * h * 0.25
			ci.draw_line(feet + Vector2(sx, -4.0), feet + Vector2(sx - e.facing * h * 0.35, 2.0), Color(1, 1, 1, 0.6), 2.0, true)
	if e.cls == "burrower" and e.state == 3:
		# telegraph: a pulsing red marker so a borer is easy to spot underground
		var pulse = 0.5 + 0.5 * sin(_t * 9.0)
		ci.draw_arc(feet + Vector2(0, -h * 0.5), h * 0.62 + pulse * 5.0, 0.0, TAU, 28, Color(1, 0.3, 0.2, 0.5 + 0.4 * pulse), 4.0, true)
	if e.hp < e.max_hp:
		var w = max(36.0, h * 0.7)
		var top = feet + Vector2(-w * 0.5, -h - 14.0)
		ci.draw_rect(Rect2(top - Vector2(2, 2), Vector2(w + 4, 10)), INK)
		ci.draw_rect(Rect2(top, Vector2(w * clamp(e.hp / e.max_hp, 0.0, 1.0), 6)), Color("#e8483b"))


# ---- a Void Maw climbing out of the collapse pit (arc.gd: void_born). For its first EMERGE_T sim seconds it rises out of the pit (world_view
# draws the pit): young and small, sunk to the chest, dark as the void it came from and lit violet from below, the front rim of the pit and
# a cloud of dust over its lower body, clods flying. Then it is the plain Void Maw. The clock is the sim's, so a paused game holds it.
const WorldView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/world_view.gd")
const EMERGE_T = 4.5
var _born := {}       # void-born raider id -> sim time it began to climb out (first seen at the pit), or -1e9 when first seen already out
var _glow = null      # soft radial light (loaded when first wanted; false when missing)


func _emerge_k(e) -> float:
	var b = _born.get(e.id)
	if b == null:
		b = sim.time if (sim.arc_stage == 3 and abs(e.x - sim.void_x) <= 6) else -1e9
		if _born.size() > 12:
			_born.clear()
		_born[e.id] = b
	return clamp((sim.time - float(b)) / EMERGE_T, 0.0, 1.0)


func _draw_emerging(ci: CanvasItem, e, feet: Vector2, depth_scale: float, shade: float, alpha: float, h: float, em: float, moving: bool, mouth: float) -> void:
	var q = 1.0 - pow(1.0 - em, 2.2)
	var pc = WorldView.pit_point(sim.grid, sim.void_x)
	var on = smoothstep(0.55, 1.0, em)                         # held over the middle of the pit until it is nearly out
	var f2 = Vector2(lerp(pc.x, feet.x, on), lerp(pc.y, feet.y, on) + (1.0 - q) * h * 0.46)
	var sc = depth_scale * float(e.def.get("art_scale", 1.0)) * lerp(0.7, 1.0, q)
	var lit = smoothstep(0.05, 0.85, em)
	var tint = Color(lerp(0.3, 1.0, lit), lerp(0.2, 1.0, lit), lerp(0.42, 1.0, lit)) * shade
	tint.a = alpha
	var vv = WorldView.VOID_VIOLET
	var gt = _dust[0] if not _dust.empty() else null
	if not (CreatureArt.Rig.available("void") and CreatureArt.Rig.draw(ci, "void", f2, sc, e.facing, _t + e.id * 0.7, moving or em < 0.8, mouth, tint, e.flash > 0.0)):
		CreatureArt.draw("voidmaw", ci, f2, sc, shade * lerp(0.35, 1.0, lit), alpha, _t, e.facing, e.id, moving, e.flash > 0.0, 0.0, mouth)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fade = 1.0 - smoothstep(0.55, 1.0, em)
	var rx = WorldView.PIT_RX
	var ry = rx * WorldView.PIT_FLAT
	# violet light from the pit on its underside
	if _glow == null:
		_glow = load(WorldView.GLOW_TEX) if ResourceLoader.exists(WorldView.GLOW_TEX) else false
	if _glow:
		var lw = Vector2(h * 1.7, h * 0.9)
		ci.draw_texture_rect(_glow, Rect2(pc + Vector2(0, -h * 0.12) - lw * 0.5, lw), false, Color(vv.r, vv.g, vv.b, 0.4 * fade * alpha))
	# the front rim of the pit, in front of its sunk body: earth and turf heaped along the near edge
	for j in 11:
		var ang = PI * (0.06 + 0.88 * (j + 0.5) / 11.0)
		var hj = fmod(abs(sin(j * 12.9898 + 3.0) * 43758.5453), 1.0)
		var p = pc + Vector2(cos(ang) * rx * (1.02 + 0.1 * hj), sin(ang) * ry * (1.02 + 0.1 * hj))
		var s = (12.0 + 10.0 * hj) * (0.5 + 0.5 * fade)
		ci.draw_circle(p + Vector2(0, 2.0), s, Color(0.12, 0.08, 0.06, 0.7 * alpha))
		ci.draw_circle(p, s, Color(0.42, 0.29, 0.19, alpha) if j % 3 != 1 else Color(0.33, 0.48, 0.2, alpha))
		ci.draw_circle(p + Vector2(-s * 0.25, -s * 0.3), s * 0.45, Color(0.55, 0.4, 0.27, alpha) if j % 3 != 1 else Color(0.45, 0.62, 0.28, alpha))
	# dust billowing up round it (the thickest at the start), and clods thrown out of the pit
	if gt != null:
		for j in 10:
			var hj = fmod(abs(sin(j * 7.31 + 1.0) * 43758.5453), 1.0)
			var ph = fmod(_t * (0.35 + 0.25 * hj) + hj, 1.0)
			var bx = (float(j) / 9.0 - 0.5) * rx * 1.9
			var dp = pc + Vector2(bx + sin(_t + j) * 8.0, ry * 0.7 - ph * (40.0 + 90.0 * hj))
			var ds = (60.0 + 70.0 * hj) * (0.6 + 0.6 * ph)
			var dc = Color(0.62, 0.52, 0.45).linear_interpolate(Color(0.55, 0.42, 0.7), 0.3 * hj)
			dc.a = sin(PI * ph) * 0.75 * fade * alpha
			ci.draw_texture_rect(_dust[j % _dust.size()] if _dust[j % _dust.size()] != null else gt, Rect2(dp - Vector2(ds, ds) * 0.5, Vector2(ds, ds)), false, dc)
	for j in 7:
		var hj = fmod(abs(sin(j * 3.77 + 5.0) * 43758.5453), 1.0)
		var ph = fmod(_t * 0.9 + hj, 1.0)
		var vx = (hj - 0.5) * 2.0 * rx * 1.4
		var cp = pc + Vector2(vx * ph, -ph * 150.0 * (0.6 + hj) + ph * ph * 190.0)
		ci.draw_circle(cp, 3.0 + 3.0 * hj, Color(0.3, 0.2, 0.13, (1.0 - ph) * fade * alpha))


# The meadow's critters (prey: they run, they never bite). Ground ones walk with legs keyed to the distance travelled; the grasshopper
# hops; butterflies and honeybees flutter above the grass, out of reach of anything without wings.
const BUTTERFLY_WINGS = [Color("#f2c14e"), Color("#e8728f"), Color("#7fb7e8"), Color("#f29b4e"), Color("#c9a6f2")]


func _draw_critter(ci: CanvasItem, e, feet: Vector2, depth_scale: float, shade: float, alpha: float, moving: bool) -> void:
	var kind = str(e.def["critter"])
	var a = alpha * (0.75 if e.state == 2 else 1.0)
	if kind == "butterfly" or kind == "bee":
		var lift = (34.0 + 10.0 * sin(_t * 2.1 + e.id)) * depth_scale
		ci.draw_set_transform(feet, 0.0, Vector2(1.0, 0.3))
		ci.draw_circle(Vector2.ZERO, 7.0 * depth_scale, Color(0.05, 0.1, 0.03, 0.14 * a))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if kind == "bee":
			CreatureArt.draw("bee", ci, feet, 0.42 * depth_scale, shade, a, _t + e.id, e.facing, e.id, true, e.flash > 0.0, lift)
		else:
			CreatureArt.butterfly(ci, feet + Vector2(0.0, -lift - 10.0 * depth_scale), 1.3 * depth_scale, _t + e.id * 0.37, e.facing, BUTTERFLY_WINGS[e.id % BUTTERFLY_WINGS.size()], a)
		return
	var walk = feet.x
	var air = 0.0
	var crouch = 0.0
	if kind == "grasshopper" and moving:
		var u = fposmod(walk / 46.0, 1.0)
		air = u if u < 0.75 else 0.0
		crouch = clamp((u - 0.75) / 0.25, 0.0, 1.0)
	var sh = shade * (0.6 if e.flash > 0.0 else 1.0)
	ci.draw_set_transform(feet + Vector2(-3.0 * depth_scale, 0.0), 0.0, Vector2(1.0, 0.3))
	ci.draw_circle(Vector2.ZERO, (9.0 + 6.0 * depth_scale) * (1.0 - air * 0.4), Color(0.05, 0.1, 0.03, 0.16 * a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	Critters.draw(kind, ci, feet, (1.1 if kind == "snail" else 1.0) * depth_scale, e.facing, _t + e.id, walk, moving, air / 0.75 if air > 0.0 else 0.0, crouch, sh)


# A worm (the Tunnel Borer) has a spine: a chain of joints. The head goes where the raider is; every joint follows the one before it at
# a fixed distance, like links of a rope, so the body trails along the very path the worm took (down through the soil, round a bend).
# A squeeze runs from head to tail as it crawls: a segment shortens and swells, then stretches thin, as an earthworm does. The owner's
# picture (straightened into content/art/worm_strip.png by tools/art/make_worm.py) is laid along the spine one slice per link, so the
# drawing itself bends and bulges. Returns false if the picture is missing (the old sprite is drawn instead).
func _draw_spine(ci: CanvasItem, e, feet: Vector2, h: float, shade: float, alpha: float, moving: bool) -> bool:
	var tex = Lib.get_lib().tex(str(e.def["spine"]))
	if tex == null:
		return false
	var length = h * 4.2
	var thick = length * float(tex.get_height()) / float(tex.get_width())
	var seg = length / float(SPINE_N - 1)
	var boring = e.state == 3
	var C = sim.grid.CELL
	var ground = feet.y - thick * 0.42
	# where the head wants to be: on the meadow a little ahead of the raider's spot; boring, in the middle of the cell it is chewing
	var target = feet - Vector2(0.0, C * 0.5) if boring else feet + Vector2(e.facing * length * 0.3, -thick * 0.42)
	if e.state == 0:
		# the wind-up before it bores: it rears up, then plunges head first into the soil
		var k1 = clamp(e.timer / 1.3, 0.0, 1.0)
		var k2 = clamp((e.timer - 1.3) / 0.9, 0.0, 1.0)
		target += Vector2(e.facing * thick * 0.6 * k2, -thick * 1.1 * sin(k1 * PI) * (1.0 - k2) + thick * 1.4 * k2)
	var sp = _spines.get(e.id)
	if sp == null or sp["head"].distance_to(target) > length * 1.5:
		var pts := []
		for i in SPINE_N:
			pts.append(target - Vector2(e.facing * seg * i, 0.0))
		sp = {"pts": pts, "ph": 0.0, "t": _t, "flip": e.facing < 0, "head": target, "hole": null}
		_spines[e.id] = sp
	var dt = clamp(_t - sp["t"], 0.0, 0.1)
	sp["t"] = _t
	sp["ph"] += dt * (7.0 if (moving or boring) else 1.4)
	var ph = sp["ph"]
	var pts: Array = sp["pts"]
	sp["head"] = sp["head"].linear_interpolate(target, clamp(dt * 9.0, 0.0, 1.0))
	if boring and sp["hole"] == null:
		sp["hole"] = Vector2(sp["head"].x, ground + thick * 0.42)     # where it went in: a hole with a ring of thrown-up dirt stays there
	# the head probes a little from side to side; the rest follows
	pts[0] = sp["head"] + Vector2(0.0, sin(ph * 0.5) * thick * (0.05 if boring else 0.12))
	var on_ground = not boring            # out on the meadow it lies along the ground; boring, it trails up its own tunnel
	if sp["hole"] != null:
		_draw_hole(ci, sp["hole"], thick, shade, alpha)
	var k := []
	for i in range(1, SPINE_N):
		var f = 1.0 + 0.16 * sin(ph - i * 0.7)
		k.append(f)
		var d: Vector2 = pts[i] - pts[i - 1]
		var want = seg * f
		if d.length() > 0.001:
			pts[i] = pts[i - 1] + d.normalized() * min(d.length(), want) if d.length() < want * 0.6 else pts[i - 1] + d.normalized() * want
		if on_ground:
			pts[i].y = lerp(pts[i].y, ground, clamp(dt * 6.0, 0.0, 1.0))
	k.push_front(k[0])
	# keep the top of the picture up: decide which way it lies from head to tail (with a margin, so it never flips back and forth)
	var dx = pts[0].x - pts[SPINE_N - 1].x
	if sp["flip"] and dx > seg:
		sp["flip"] = false
	elif not sp["flip"] and dx < -seg:
		sp["flip"] = true
	var up_sign = -1.0 if sp["flip"] else 1.0
	var mod = Color(shade, shade, shade, (0.75 if e.state == 2 else 1.0) * alpha)
	if e.flash > 0.0:
		mod = Color(shade, shade * 0.5, shade * 0.5, mod.a)
	var cols = PoolColorArray([mod, mod, mod, mod])
	var tops := []
	var bots := []
	for i in SPINE_N:
		var a: Vector2 = pts[max(0, i - 1)]
		var b: Vector2 = pts[min(SPINE_N - 1, i + 1)]
		var t = (a - b).normalized()
		var n = Vector2(t.y, -t.x) * up_sign
		var w = thick * 0.5 * clamp(1.0 - 1.6 * (k[i] - 1.0), 0.75, 1.3)
		tops.append(pts[i] + n * w)
		bots.append(pts[i] - n * w)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(SPINE_N - 1):
		var u0 = 1.0 - float(i) / (SPINE_N - 1)
		var u1 = 1.0 - float(i + 1) / (SPINE_N - 1)
		var v0 = 0.0 if not sp["flip"] else 0.0
		ci.draw_primitive(PoolVector2Array([tops[i], tops[i + 1], bots[i + 1], bots[i]]), cols,
			PoolVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, 1.0), Vector2(u0, 1.0)]), tex)
	if boring or (e.state == 0 and e.timer > 1.3):
		# clods of soil flicked back from the mouth as it chews
		var fwd = (pts[0] - pts[2]).normalized()
		for j in 5:
			var life = fposmod(ph * 0.45 + j * 0.2, 1.0)
			var side = (1.0 if j % 2 == 0 else -1.0) * (0.6 + 0.25 * (j % 3))
			var dirv = (-fwd + Vector2(fwd.y, -fwd.x) * side).normalized()
			var cp = pts[0] + fwd * thick * 0.4 + dirv * thick * (0.3 + 1.6 * life) + Vector2(0.0, thick * 0.9 * life * life)
			var r = thick * (0.11 - 0.05 * life)
			var cc = Color(0.45 * shade, 0.32 * shade, 0.2 * shade, alpha * (1.0 - life))
			ci.draw_circle(cp, r + 1.5, Color(INK.r, INK.g, INK.b, cc.a))
			ci.draw_circle(cp, r, cc)
	return true


# The hole a worm bored into the meadow: dark mouth, a lip of churned soil thrown up on both sides.
func _draw_hole(ci: CanvasItem, at: Vector2, thick: float, shade: float, alpha: float) -> void:
	var w = thick * 0.8
	ci.draw_set_transform(at, 0.0, Vector2(1.0, 0.38))
	ci.draw_circle(Vector2.ZERO, w + 3.0, Color(INK.r, INK.g, INK.b, 0.9 * alpha))
	ci.draw_circle(Vector2.ZERO, w, Color(0.12 * shade, 0.08 * shade, 0.06 * shade, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for j in 6:
		var sx = (-1.0 if j < 3 else 1.0) * (w * (0.9 + 0.28 * (j % 3)))
		var r = thick * (0.2 - 0.04 * (j % 3))
		var cp = at + Vector2(sx, -r * 0.4)
		ci.draw_circle(cp, r + 2.0, Color(INK.r, INK.g, INK.b, 0.85 * alpha))
		ci.draw_circle(cp, r, Color(0.5 * shade, 0.36 * shade, 0.23 * shade, alpha))


func forget_spines() -> void:
	# called now and then: drop the spines of worms that are gone
	var alive := {}
	for e in sim.enemies:
		alive[e.id] = true
	for id in _spines.keys():
		if not alive.has(id):
			_spines.erase(id)


# The rival's descendants: the very body plan your old colony bred, baked like any ant and given a red cast so it is never mistaken for
# one of yours. Until the sprite is baked (the first frame of a new body) the plain red ant stands in.
func _draw_kin(ci: CanvasItem, e, feet: Vector2, depth_scale: float, shade: float, alpha: float, moving: bool) -> void:
	var k = float(e.def.get("art_scale", 1.0))
	var a = alpha * (0.75 if e.state == 2 else 1.0)
	var kin_k = KIN_SIZE.get(e.cls, 1.0)
	var frame = int(fposmod(_t * 2.6 + e.id * 0.37, 1.0) * baker.FRAMES) % baker.FRAMES if moving else 0
	var tex = baker.get_texture(e.genome, 1.0, frame) if baker != null else null
	if tex == null:
		CreatureArt.draw("redant", ci, feet, depth_scale * k, shade, a, _t, e.facing, e.id, moving, e.flash > 0.0, 0.0)
		return
	var s = ANT_SCALE * depth_scale * kin_k
	var bob = sin(_t * 12.0 + e.id) * 0.05 if moving else 0.0
	var tint = Color(shade, shade * 0.72, shade * 0.68, a)
	if e.flash > 0.0:
		tint = Color(shade, shade * 0.45, shade * 0.45, a)
	ci.draw_set_transform(feet, 0.0, Vector2(e.facing * s, s * (1.0 + bob)))
	ci.draw_texture_rect(tex, Rect2(-baker.FEET, baker.SIZE), false, tint)


# Only effects here; units are drawn depth-sorted by ant_view.gd.
func _sprite(tex, p: Vector2, rot: float, size: float, col: Color, ci = null) -> void:
	if tex == null or size <= 0.5 or col.a <= 0.01:
		return
	if ci == null:
		ci = self
	ci.draw_set_transform(p, rot, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(-size * 0.5, -size * 0.5, size, size), false, col)


# The hit effects (sparks, dust, bursts) go under the units and are small and faint: a fight is many hits a second, and big bright effects
# between the bodies are what made it hard to see. Called from the `under` layer's draw.
# Drawn from the owner's 4-frame effect pictures (dust for a puff, the hit star/burst for spark and burst: see _fx_hit_kind) at the old sizes
# and alphas; the old procedural sprites below are the fallback when a picture is missing.
func _draw_under() -> void:
	if under == null:
		return
	var cap = (perf.fx if perf != null else 400) / 2
	var nfx := 0
	for f in sim.fx:
		if not (f["kind"] in UNDER_KINDS):
			continue
		nfx += 1
		if nfx > cap:
			break
		var k = clamp(f["t"] / LIFE.get(f["kind"], 1.2), 0.0, 1.0)
		var c: Color = f["color"]
		var pos: Vector2 = f["pos"]
		var seed_i = int(abs(pos.x)) + int(abs(pos.y))
		if _fx_hit_kind(under, f, k, false):
			continue
		match f["kind"]:
			"puff":
				for j in 4:
					var ang = j * TAU / 4.0 + seed_i * 0.37
					var dist = 4.0 + k * 16.0
					var tx = _dust[(j + seed_i) % _dust.size()] if _dust.size() > 0 else null
					_sprite(tx, pos + Vector2(cos(ang), sin(ang) * 0.7) * dist, ang + k * 2.5, 17.0 * (1.0 - k * 0.5) + 3.0, Color(c.r, c.g, c.b, (1.0 - k) * 0.55), under)
			"spark":
				for j in 3:
					var ang2 = j * TAU / 3.0 + seed_i * 0.9
					var dist2 = 3.0 + k * 16.0
					var tx2 = _stars[(j + seed_i) % _stars.size()] if _stars.size() > 0 else null
					_sprite(tx2, pos + Vector2(cos(ang2), sin(ang2)) * dist2, ang2 + k * 4.0, 12.0 * (1.0 - k), Color(c.r, c.g, c.b, (1.0 - k * k) * 0.8), under)
			"burst":
				for j in 6:
					var ang3 = j * TAU / 6.0 + seed_i * 0.21
					var dist3 = 6.0 + k * 34.0
					var tx3 = _stars[(j + seed_i) % _stars.size()] if _stars.size() > 0 else null
					_sprite(tx3, pos + Vector2(cos(ang3), sin(ang3) * 0.8) * dist3, ang3 * 2.0 + k * 5.0, 18.0 * (1.0 - k * 0.75), Color(c.r, c.g, c.b, (1.0 - k * k) * 0.75), under)
	under.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Effects over the units. The sonic wave, the lightning arc and the silk snare are the owner's 4-frame pictures (see _fx_anim; the frame comes
# from the effect's age, cross-faded), the rest is procedural; each picture effect falls back to its old drawing when the picture is missing.
func _draw() -> void:
	var cap = perf.fx if perf != null else 400
	var nfx := 0
	for f in sim.fx:
		if under != null and (f["kind"] in UNDER_KINDS):
			continue
		nfx += 1
		if nfx > cap:
			break
		var k = clamp(f["t"] / LIFE.get(f["kind"], 1.2), 0.0, 1.0)
		var c: Color = f["color"]
		var pos: Vector2 = f["pos"]
		var seed_i = int(abs(pos.x)) + int(abs(pos.y))
		if (f["kind"] in UNDER_KINDS) and _fx_hit_kind(self, f, k, true):
			continue
		if _fx_over_kind(f, k, seed_i):
			continue
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)     # the sprite effects leave their transform set; lines and arcs are in world px
		match f["kind"]:
			"puff":
				for j in 6:
					var ang = j * TAU / 6.0 + seed_i * 0.37
					var dist = 5.0 + k * 26.0
					var tx = _dust[(j + seed_i) % _dust.size()] if _dust.size() > 0 else null
					_sprite(tx, pos + Vector2(cos(ang), sin(ang) * 0.7) * dist, ang + k * 2.5, 30.0 * (1.0 - k * 0.55) + 6.0, Color(c.r, c.g, c.b, (1.0 - k) * 0.9))
			"spark":
				for j in 5:
					var ang2 = j * TAU / 5.0 + seed_i * 0.9
					var dist2 = 4.0 + k * 30.0
					var tx2 = _stars[(j + seed_i) % _stars.size()] if _stars.size() > 0 else null
					_sprite(tx2, pos + Vector2(cos(ang2), sin(ang2)) * dist2, ang2 + k * 4.0, 22.0 * (1.0 - k), Color(c.r, c.g, c.b, 1.0 - k * k))
			"burst":
				for j in 8:
					var ang3 = j * TAU / 8.0 + seed_i * 0.21
					var dist3 = 8.0 + k * 62.0
					var tx3 = _stars[(j + seed_i) % _stars.size()] if _stars.size() > 0 else null
					_sprite(tx3, pos + Vector2(cos(ang3), sin(ang3) * 0.8) * dist3, ang3 * 2.0 + k * 5.0, 32.0 * (1.0 - k * 0.75), Color(c.r, c.g, c.b, 1.0 - k * k))
			"ring":
				_sprite(_ring, pos, 0.0, 28.0 + k * 100.0, Color(c.r, c.g, c.b, (1.0 - k) * 0.6))
			"heal":
				for j in 3:
					var jk = clamp(k * 1.3 - j * 0.12, 0.0, 1.0)
					_sprite(_plus, pos + Vector2((j - 1) * 20.0 + sin(k * 6.0 + j) * 4.0, -jk * 52.0), 0.0, 26.0 * (1.0 - jk * 0.4), Color(c.r, c.g, c.b, (1.0 - jk) * 0.95))
			"hatch":
				_sprite(_ring, pos, 0.0, 14.0 + k * 62.0, Color(1.0, 0.96, 0.8, (1.0 - k) * 0.9))
				_sprite(_sparkle, pos + Vector2(0, -8.0 * k), k * 1.6, 42.0 * sin(k * PI) + 6.0, Color(1.0, 0.96, 0.8, 1.0 - k * k))
				for j in 4:
					var ang4 = j * TAU / 4.0 + 0.6
					_sprite(_sparkle, pos + Vector2(cos(ang4), sin(ang4)) * (8.0 + k * 30.0), k * 3.0, 14.0 * (1.0 - k), Color(1.0, 0.96, 0.8, 1.0 - k))
			"wave":
				# sonic shockwave: three expanding ink-backed arcs
				var R = f.get("r", 100.0)
				for j in 3:
					var jk = clamp(k * 1.25 - j * 0.14, 0.0, 1.0)
					if jk <= 0.0 or jk >= 1.0:
						continue
					var rr = 12.0 + jk * R
					var al = (1.0 - jk) * 0.9
					draw_arc(pos, rr, 0.0, TAU, 48, Color(INK.r, INK.g, INK.b, al * 0.6), 9.0 * (1.0 - jk) + 3.0, true)
					draw_arc(pos, rr, 0.0, TAU, 48, Color(c.r, c.g, c.b, al), 5.0 * (1.0 - jk) + 1.5, true)
			"arc":
				# electric bolt: jagged polyline, re-jittered every frame
				var to: Vector2 = f.get("to", pos)
				var pts := PoolVector2Array()
				var n = 7
				var nrm = (to - pos).normalized().rotated(PI * 0.5)
				for j in n + 1:
					var jit = 0.0 if j == 0 or j == n else (randf() - 0.5) * 26.0
					pts.append(pos.linear_interpolate(to, float(j) / n) + nrm * jit)
				draw_polyline(pts, Color(INK.r, INK.g, INK.b, 0.7 * (1.0 - k)), 8.0, true)
				draw_polyline(pts, Color(c.r, c.g, c.b, 1.0 - k * 0.5), 4.0, true)
				draw_polyline(pts, Color(1, 1, 1, 1.0 - k), 1.6, true)
			"beam":
				# tongue / silk line: snaps out and back
				var to2: Vector2 = f.get("to", pos)
				var reach = sin(k * PI)
				var tip = pos.linear_interpolate(to2, reach)
				draw_line(pos, tip, Color(INK.r, INK.g, INK.b, 0.8), 8.0, true)
				draw_line(pos, tip, c, 4.5, true)
				draw_circle(tip, 7.0, INK)
				draw_circle(tip, 5.0, c)
			"web":
				# snare: a silk net over the raider, fading out
				var al2 = (1.0 - k * k) * 0.85
				var wr = 34.0
				for j in 8:
					var ang5 = TAU * j / 8.0
					draw_line(pos, pos + Vector2(cos(ang5), sin(ang5)) * wr, Color(c.r, c.g, c.b, al2), 2.0, true)
				for j in 3:
					draw_arc(pos, wr * (0.35 + 0.3 * j), 0.0, TAU, 16, Color(c.r, c.g, c.b, al2), 1.8, true)
			"text":
				var c2 = c
				c2.a = 1.0 - k * k
				var sc = 1.0 + 0.7 * max(0.0, 1.0 - k * 7.0)     # pops in, then settles
				draw_set_transform(pos, 0.0, Vector2(sc, sc))
				draw_string(_font, Vector2(-16, -k * 40.0), f["text"], c2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- the drawn effect animations (content/art/fx/<name>_<0..3>.png and fx_manifest.json, made by tools/art/make_fx.py) ----
# Every effect is 4 frames played over its life: the frame comes from the age t / LIFE[kind] and cross-fades into the next one. The frames of
# one effect share one scale (they keep their sizes relative to each other: the growth is part of the animation), so the sizes below are the
# widest frame's width in world px.
var _fx_anims = null   # name -> {"f": [{"tex", "c": anchor in the frame's px, "ax": [x0, x1] the bolt's ends}], "ref": widest frame px}; {} when a frame is missing
var _fx_man = null     # the "anims" of fx_manifest.json ({} without it: anchors then default to the middle, or the bottom middle for dust and acid)
const FX_FADE = 0.35   # share of a frame's slot spent cross-fading into the next frame
const FX_GROUND = ["dust", "acid"]


func _fx_anim(name: String) -> Dictionary:
	if _fx_anims == null:
		_fx_anims = {}
		_fx_man = {}
		var fh = File.new()
		if fh.open(Lib.DIR + "fx_manifest.json", File.READ) == OK:
			var res = JSON.parse(fh.get_as_text())
			fh.close()
			if res.error == OK and res.result is Dictionary and res.result.get("anims", null) is Dictionary:
				_fx_man = res.result["anims"]
	if _fx_anims.has(name):
		return _fx_anims[name]
	var ent = _fx_man.get(name, {})
	var info = ent.get("frames", []) if ent is Dictionary else []
	if not (info is Array):
		info = []
	var frames := []
	var ref := 1.0
	for i in 4:
		var tex = Lib.get_lib().tex("fx/%s_%d.png" % [name, i])
		if tex == null:
			frames = []
			break
		var sz: Vector2 = tex.get_size()
		var c = Vector2(sz.x * 0.5, sz.y if name in FX_GROUND else sz.y * 0.5)
		var ax = [0.0, sz.x]
		if i < info.size() and info[i] is Dictionary:
			var cc = info[i].get("center", null)
			if cc is Array and cc.size() == 2:
				c = Vector2(float(cc[0]), float(cc[1]))
			var aa = info[i].get("axis", null)
			if aa is Array and aa.size() == 4 and float(aa[2]) > float(aa[0]):
				ax = [float(aa[0]), float(aa[2])]
		ref = max(ref, sz.x)
		frames.append({"tex": tex, "c": c, "ax": ax})
	_fx_anims[name] = {"f": frames, "ref": ref} if frames.size() == 4 else {}
	return _fx_anims[name]


# Frame position 0..4 for an age k in 0..1: frame i starts at marks[i - 1] (evenly spread without marks).
func _fx_fp(k: float, marks: Array = []) -> float:
	if marks.empty():
		return k * 4.0
	var prev := 0.0
	for i in marks.size():
		if k < marks[i]:
			return i + (k - prev) / max(0.0001, marks[i] - prev)
		prev = marks[i]
	return marks.size() + (k - prev) / max(0.0001, 1.0 - prev)


# Draws an effect animation at frame position fp: that frame, cross-faded into the next near the end of its slot (both stay at full strength
# through the middle of the fade, so it never dips). scl: picture px -> world px, rot turns it about its anchor. stretch > 0 draws each frame's
# bolt axis that long instead (lightning from one point to another): scl.y is then the most the thickness may scale (its sign flips it).
# Leaves its transform set, like _sprite (the draw functions reset it).
func _fx_draw(ci: CanvasItem, an: Dictionary, fp: float, pos: Vector2, rot: float, scl: Vector2, col: Color, stretch: float = 0.0) -> void:
	if col.a <= 0.01:
		return
	var frames: Array = an["f"]
	var n = frames.size()
	fp = clamp(fp, 0.0, n - 0.001)
	var i = int(fp)
	var b = 0.0
	if i < n - 1:
		b = clamp((fp - i - (1.0 - FX_FADE)) / FX_FADE, 0.0, 1.0)
	if b < 1.0:
		_fx_frame(ci, frames[i], pos, rot, scl, Color(col.r, col.g, col.b, col.a * min(1.0, 2.0 * (1.0 - b))), stretch)
	if b > 0.0:
		_fx_frame(ci, frames[i + 1], pos, rot, scl, Color(col.r, col.g, col.b, col.a * min(1.0, 2.0 * b)), stretch)


func _fx_frame(ci: CanvasItem, fr: Dictionary, pos: Vector2, rot: float, scl: Vector2, col: Color, stretch: float) -> void:
	var c: Vector2 = fr["c"]
	if stretch > 0.0:
		var x0: float = fr["ax"][0]
		var x1: float = fr["ax"][1]
		var sx = stretch / max(1.0, x1 - x0)
		c = Vector2((x0 + x1) * 0.5, c.y)
		scl = Vector2(sx, sign(scl.y) * min(sx, abs(scl.y)))
	ci.draw_set_transform(pos, rot, scl)
	ci.draw_texture(fr["tex"], -c, col)


# Puff, spark and burst from the pictures. A puff is kicked-up dust, brown as drawn (only a puff of another colour than earth, like the blue zap
# or the green taming, is tinted toward it); a spark is the hit star drawn small, a burst the same bigger. Under the units they keep the old
# small sizes and faint alphas; `over` (no under layer) draws them as big as the old over-the-units ones. False when a picture is missing.
func _fx_hit_kind(ci: CanvasItem, f: Dictionary, k: float, over: bool) -> bool:
	var c: Color = f["color"]
	var pos: Vector2 = f["pos"]
	var seed_i = int(abs(pos.x)) + int(abs(pos.y))
	var flip = -1.0 if seed_i % 2 == 1 else 1.0
	match f["kind"]:
		"puff":
			var an = _fx_anim("dust")
			if an.empty():
				return false
			var earth = c.s < 0.15 or (c.h > 0.02 and c.h < 0.17)
			var tint = Color(1, 1, 1) if earth else Color(1, 1, 1).linear_interpolate(c, 0.6)
			tint.a = (0.9 if over else 0.6) * (1.0 - k * k)
			var s = (66.0 if over else 44.0) / an["ref"]
			_fx_draw(ci, an, _fx_fp(k, [0.16, 0.38, 0.66]), pos + Vector2(0, 3), 0.0, Vector2(s * flip, s), tint)
			return true
		"spark", "burst":
			var an2 = _fx_anim("hit")
			if an2.empty():
				return false
			var big = f["kind"] == "burst"
			var s2 = (56.0 if big else 26.0) * (1.6 if over else 1.0) / an2["ref"] * (0.85 + 0.3 * k)
			var tint2 = Color(1, 1, 1).linear_interpolate(c, 0.5)
			tint2.a = (1.0 if over else (0.75 if big else 0.8)) * (1.0 - k * k)
			_fx_draw(ci, an2, k * 4.0, pos, fmod(seed_i * 0.7, TAU), Vector2(s2 * flip, s2), tint2)
			return true
	return false


# The sonic wave, the lightning arc, the silk snare (and an acid splash, ready for when the sim makes one) from the pictures, over the units.
# False when the kind has no picture or one is missing (the caller then draws the old procedural effect).
func _fx_over_kind(f: Dictionary, k: float, seed_i: int) -> bool:
	var c: Color = f["color"]
	var pos: Vector2 = f["pos"]
	var white = Color(1, 1, 1)
	match f["kind"]:
		"wave":
			# the shock ring grows to the pulse radius (the frames grow too; the scale adds a steady swell between them)
			var an = _fx_anim("sonic")
			if an.empty():
				return false
			var s = 2.2 * (12.0 + f.get("r", 100.0)) / an["ref"] * (0.65 + 0.35 * k)
			var tint = white.linear_interpolate(c, 0.8)      # the pale ring takes the pulse's colour (cyan thunder, warm plain pulse)
			tint.a = 0.85 * (1.0 - k * k)
			_fx_draw(self, an, k * 4.0, pos, fmod(seed_i * 0.9, TAU), Vector2(s, s), tint)
			return true
		"arc":
			# the bolt is stretched from pos to "to" and flipped every 1/30 s, so it crackles
			var an2 = _fx_anim("lightning")
			var to: Vector2 = f.get("to", pos)
			var d = to - pos
			if an2.empty() or d.length() < 2.0:
				return false
			var tint2 = white.linear_interpolate(c, 0.3)
			tint2.a = clamp((1.0 - k) * 4.0, 0.0, 1.0)
			var thick = 0.16 * (-1.0 if int(f["t"] * 30.0) % 2 == 1 else 1.0)
			_fx_draw(self, an2, k * 4.0, (pos + to) * 0.5, d.angle(), Vector2(1.0, thick), tint2, d.length())
			return true
		"web":
			# the silk ball hits, splats, hangs as a web over the snared raider, then drips and fades. The ball flies the way the silk line
			# that came with it was shot (remembered on the effect once, as the line is gone long before the web)
			var an3 = _fx_anim("web")
			if an3.empty():
				return false
			if not f.has("face"):
				# first sight of this web: which way it was shot, and an older web on the same raider gives way to it (webs never stack
				# into a white blob over the fight)
				f["face"] = 1.0
				for g in sim.fx:
					if g["kind"] == "beam" and g.get("to", Vector2.INF).distance_to(pos) < 2.0:
						f["face"] = -1.0 if g["to"].x < g["pos"].x else 1.0
					elif g["kind"] == "web" and g != f and g["t"] > f["t"] and g["pos"].distance_to(pos) < 10.0:
						g["gone"] = true
			if f.get("gone", false):
				return true
			var s3 = 54.0 / an3["ref"]
			var tint3 = c
			tint3.a = 0.75 * (1.0 - k * k * k) * (1.0 - 0.25 * smoothstep(0.16, 0.4, k))    # the hanging web settles fainter than the hit
			_fx_draw(self, an3, _fx_fp(k, [0.07, 0.16, 0.72]), pos, 0.0, Vector2(s3 * f["face"], s3), tint3)
			return true
		"acid":
			var an4 = _fx_anim("acid")
			if an4.empty():
				return false
			var s4 = 40.0 / an4["ref"]
			var tint4 = white
			tint4.a = 0.9 * (1.0 - k * k)
			_fx_draw(self, an4, k * 4.0, pos, 0.0, Vector2(s4 * (-1.0 if seed_i % 2 == 1 else 1.0), s4), tint4)
			return true
	return false
