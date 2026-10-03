extends Node2D
# Raiders: Brotato / Abyssal Terrors sprites, squash-bob like vanilla,
# hit flash, HP bars. Plus combat effects (puffs, floating numbers).

const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")
const CreatureArt = preload("res://mods-unpacked/Judah-InfDNA/content/colony/creature_art.gd")
const Lib = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
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
	elif art != "":
		var fly = e.def.get("fly", false)
		var lift = 6.0 + 22.0 * air if fly else 0.0
		var mouth = (0.5 + 0.5 * sin(_t * 8.0 + e.id)) if (e.engaged and e.state != 2) else (0.12 + 0.12 * sin(_t * 1.6 + e.id))
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
