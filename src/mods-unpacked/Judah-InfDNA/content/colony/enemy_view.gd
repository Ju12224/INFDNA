extends Node2D
# Raiders: Brotato / Abyssal Terrors sprites, squash-bob like vanilla,
# hit flash, HP bars. Plus combat effects (puffs, floating numbers).

const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")
const CreatureArt = preload("res://mods-unpacked/Judah-InfDNA/content/colony/creature_art.gd")
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
	var h = EnemyDefs.HEIGHT[e.cls] * depth_scale
	var tex = _tex.get(e.kind)
	var moving = e.tx != e.x or e.ty != e.y
	var bob = sin(_t * (12.0 if moving else 4.0) + e.id) * (0.06 if moving else 0.025)
	var mod = Color(1, 0.5, 0.5) if e.flash > 0.0 else Color.white
	mod = Color(mod.r * shade, mod.g * shade, mod.b * shade, (0.75 if e.state == 2 else 1.0) * alpha)
	var art = e.def.get("art", "")
	if e.genome != null:
		_draw_kin(ci, e, feet, depth_scale, shade, alpha, moving)
	elif art != "":
		var fly = e.def.get("fly", false)
		var lift = 6.0 + 22.0 * air if fly else 0.0
		CreatureArt.draw(art, ci, feet, depth_scale * float(e.def.get("art_scale", 1.0)), shade, alpha * (0.75 if e.state == 2 else 1.0), _t, e.facing, e.id, moving, e.flash > 0.0, lift)
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
