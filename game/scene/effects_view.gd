extends Node2D
# The fight effects (colony_sim.fx), from the owner's 4-frame effect pictures (fx/<name>_0..3.png, fx_manifest.json): every effect plays
# its four frames over its life, cross-fading from one to the next (the old mod's enemy_view.gd, ported).
#   puff   dust kicked up (fx/dust)            spark, burst   a hit, small and big (fx/hit)
#   wave   a sonic pulse (fx/sonic)            arc            a lightning bolt stretched from pos to "to" (fx/lightning)
#   web    the silk snare (fx/web)             acid           an acid splash (fx/acid; the sim does not make one yet)
#   corpse one of our ants killed: it is knocked up, tips over and fades (the antkit body, as units_view.gd draws it)
#   text   the floating words and numbers ("+24", "RALLY!"), in the interface font, the same size at every zoom
# Hits, dust and bursts go on a child canvas under the ants (a fight is many hits a second; over the bodies they would hide it), the rest
# over everything. This view also ages the effects and drops the finished ones (nothing in the sim does). The kinds with no picture
# (ring, heal, hatch, and beam: the tongues and silk lines) are not drawn.
#
# The sim puts an effect at a cell's centre; on the surface the creatures stand in the lanes of the meadow band, so an effect there is
# lifted into the lane of the fight (FIGHT_LANE, or the lane the effect carries).

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const C = WorldGrid.CELL
const LIFE = {"puff": 1.0, "text": 1.2, "spark": 0.45, "heal": 1.3, "ring": 0.7, "hatch": 0.9, "burst": 0.8, "wave": 0.6, "arc": 0.28,
	"beam": 0.22, "web": 1.4, "corpse": 0.9, "acid": 0.9}
const UNDER = ["puff", "spark", "burst"]
const ANIMS = {"puff": "dust", "spark": "hit", "burst": "hit", "wave": "sonic", "arc": "lightning", "web": "web", "acid": "acid"}
const FX_FADE = 0.35            # share of a frame's slot spent cross-fading into the next frame
const FX_GROUND = ["dust", "acid"]
const FIGHT_LANE = 0.78         # colony_sim.FIGHT_LANE: an engaged raider and its ants are drawn in this lane
const MARGIN = 160.0
const FAR_ZOOM = 0.45           # zoomed out past this, effects grow (up to FAR_MAX) as the ants do
const FAR_MAX = 1.6
const TEXT_PX = 22              # floating text height on screen
const HAZE = Color(0.88, 0.92, 0.97)
# our ants' bodies, as units_view.gd draws them
const CASTE_BODY = ["worker_full", "worker_small_full", "soldier_full"]
const CASTE_SCALE = [0.94, 1.0, 1.12]
const LEN_PER_SIZE = 2.2
const LEN_BASE = 24.0
const LEN_K = 0.132
const KIT_BASE = Color(0.60, 0.52, 0.46)

var colony
var _under: Node2D
var _anims := {}        # anim name -> {"f": [{tex, c, ax}], "ref": widest frame px}, {} when a frame is missing
var _bodies := {}       # antkit body -> {tex, feet, length}
var _font: Font
var _far := 1.0
var _fa := 1.0                  # the effect being drawn: its lane's share of band.gd lane_alpha (the depth zoom cuts near lanes)
var _lane_alpha := Callable()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_under = Node2D.new()
	_under.name = "under_units"
	_under.z_index = -12          # 50 - 12: under the ants (40), over the nest (30)
	_under.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_under.draw.connect(_draw_under)
	add_child(_under)
	var man = Art.manifest("fx_manifest.json").get("anims", {})
	for name in ["dust", "hit", "sonic", "lightning", "web", "acid"]:
		_anims[name] = _load_anim(name, man.get(name, {}))
	var kit = Art.manifest("antkit_manifest.json").get("pieces", {})
	for name in CASTE_BODY + ["alate_full"]:
		var p = kit.get(name)
		var tex = _mip(Art.tex(str(p["file"]))) if p != null else null
		if tex != null:
			_bodies[name] = {"tex": tex, "feet": Vector2(p["feet"][0], p["feet"][1]), "length": float(p["length"])}
	_font = ThemeDB.fallback_font
	var band: Object = Band
	for m in band.get_script_method_list():
		if m["name"] == "lane_alpha":
			_lane_alpha = Callable(band, "lane_alpha")


static func _mip(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img = tex.get_image()
	if img == null or img.is_empty() or img.has_mipmaps():
		return tex
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _load_anim(name: String, ent) -> Dictionary:
	var info = ent.get("frames", []) if ent is Dictionary else []
	var frames := []
	var ref := 1.0
	for i in 4:
		var tex = _mip(Art.tex("fx/%s_%d.png" % [name, i]))
		if tex == null:
			return {}
		var sz: Vector2 = tex.get_size()
		var c = Vector2(sz.x * 0.5, sz.y if name in FX_GROUND else sz.y * 0.5)
		var ax = [0.0, sz.x]
		if i < info.size() and info[i] is Dictionary:
			var cc = info[i].get("center")
			if cc is Array and cc.size() == 2:
				c = Vector2(float(cc[0]), float(cc[1]))
			var aa = info[i].get("axis")
			if aa is Array and aa.size() == 4 and float(aa[2]) > float(aa[0]):
				ax = [float(aa[0]), float(aa[2])]
		ref = max(ref, sz.x)
		frames.append({"tex": tex, "c": c, "ax": ax})
	return {"f": frames, "ref": ref}


func reset() -> void:
	pass


func _process(delta: float) -> void:
	var fx: Array = colony.sim.fx
	if not colony.paused:
		var i := 0
		while i < fx.size():
			var f = fx[i]
			f["t"] += delta
			if f["t"] > LIFE.get(f["kind"], 1.2):
				fx.remove_at(i)
			else:
				i += 1
	queue_redraw()
	_under.queue_redraw()


func _la(lane: float) -> float:
	return float(_lane_alpha.call(lane)) if _lane_alpha.is_valid() else 1.0


# Where an effect is drawn: on the surface, lifted into its lane.
func _at(p: Vector2, lane: float = FIGHT_LANE) -> Vector2:
	var g = colony.grid
	if p.y <= (g.surf_y(int(floor(p.x / C))) + 1.0) * C:
		return Vector2(p.x, Band.lane_y(p.y, lane))
	return p


func _draw_under() -> void:
	var vr = colony.view_rect(MARGIN)
	_far = clamp(sqrt(FAR_ZOOM / colony.zoom()), 1.0, FAR_MAX)
	for f in colony.sim.fx:
		if f["kind"] in UNDER and vr.has_point(f["pos"]):
			_draw_fx(_under, f)
	_under.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var vr = colony.view_rect(MARGIN)
	_far = clamp(sqrt(FAR_ZOOM / colony.zoom()), 1.0, FAR_MAX)
	var texts := []
	for f in colony.sim.fx:
		var k = f["kind"]
		if k in UNDER or not vr.has_point(f["pos"]):
			continue
		if k == "text":
			texts.append(f)
		elif k == "corpse":
			_draw_corpse(f)
		else:
			_draw_fx(self, f)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for f in texts:
		_draw_text(f)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_fx(ci: CanvasItem, f: Dictionary) -> void:
	var an = _anims.get(ANIMS.get(f["kind"], ""), {})
	if an.is_empty():
		return
	var k = clamp(f["t"] / LIFE.get(f["kind"], 1.2), 0.0, 1.0)
	var c: Color = f["color"]
	var raw: Vector2 = f["pos"]
	var pos = _at(raw, float(f.get("lane", FIGHT_LANE)))
	var seed_i = int(abs(raw.x)) + int(abs(raw.y))
	var flip = -1.0 if seed_i % 2 == 1 else 1.0
	var white = Color.WHITE
	var day = colony.day.tint if pos != raw else Color.WHITE
	_fa = _la(float(f.get("lane", FIGHT_LANE))) if pos != raw else 1.0
	if _fa <= 0.01:
		return
	match f["kind"]:
		"puff":
			# dust, brown as drawn; a puff of another colour than earth (the blue zap, the green kill) leans toward it
			var earth = c.s < 0.15 or (c.h > 0.02 and c.h < 0.17)
			var tint = white if earth else white.lerp(c, 0.6)
			tint = tint * day
			tint.a = 0.6 * (1.0 - k * k)
			var s = 44.0 * _far / an["ref"]
			_anim(ci, an, _fp(k, [0.16, 0.38, 0.66]), pos + Vector2(0, 3), 0.0, Vector2(s * flip, s), tint)
		"spark", "burst":
			var big = f["kind"] == "burst"
			var s2 = (56.0 if big else 26.0) * _far / an["ref"] * (0.85 + 0.3 * k)
			var tint2 = white.lerp(c, 0.5)
			tint2.a = (0.75 if big else 0.8) * (1.0 - k * k)
			_anim(ci, an, k * 4.0, pos, fmod(seed_i * 0.7, TAU), Vector2(s2 * flip, s2), tint2)
		"wave":
			# the shock ring grows to the pulse radius (the frames grow too; the scale adds a steady swell between them)
			var s3 = 2.2 * (12.0 + float(f.get("r", 100.0))) / an["ref"] * (0.65 + 0.35 * k)
			var tint3 = white.lerp(c, 0.8)
			tint3.a = 0.85 * (1.0 - k * k)
			_anim(ci, an, k * 4.0, pos, fmod(seed_i * 0.9, TAU), Vector2(s3, s3), tint3)
		"arc":
			# the bolt stretched from pos to "to", flipped every 1/30 s so it crackles
			var to = _at(f.get("to", raw), float(f.get("lane", FIGHT_LANE)))
			var d = to - pos
			if d.length() < 2.0:
				return
			var tint4 = white.lerp(c, 0.3)
			tint4.a = clamp((1.0 - k) * 4.0, 0.0, 1.0)
			var thick = 0.16 * (-1.0 if int(f["t"] * 30.0) % 2 == 1 else 1.0)
			_anim(ci, an, k * 4.0, (pos + to) * 0.5, d.angle(), Vector2(1.0, thick), tint4, d.length())
		"web":
			# the silk ball hits, splats, hangs as a web over the snared raider, then drips and fades; it flies the way its silk line was shot,
			# and a newer web on the same raider takes over (webs never stack into a white blob over the fight)
			if not f.has("face"):
				f["face"] = 1.0
				for g in colony.sim.fx:
					if g["kind"] == "beam" and g.get("to", Vector2.INF).distance_to(raw) < 2.0:
						f["face"] = -1.0 if g["to"].x < g["pos"].x else 1.0
					elif g["kind"] == "web" and g != f and g["t"] > f["t"] and g["pos"].distance_to(raw) < 10.0:
						g["gone"] = true
			if f.get("gone", false):
				return
			var s5 = 54.0 * _far / an["ref"]
			var tint5 = c
			tint5.a = 0.75 * (1.0 - k * k * k) * (1.0 - 0.25 * smoothstep(0.16, 0.4, k))
			_anim(ci, an, _fp(k, [0.07, 0.16, 0.72]), pos, 0.0, Vector2(s5 * f["face"], s5), tint5)
		"acid":
			var s6 = 40.0 * _far / an["ref"]
			var tint6 = white * day
			tint6.a = 0.9 * (1.0 - k * k)
			_anim(ci, an, k * 4.0, pos, 0.0, Vector2(s6 * flip, s6), tint6)


# Frame position 0..4 for an age k in 0..1: frame i starts at marks[i - 1] (evenly spread without marks).
static func _fp(k: float, marks: Array = []) -> float:
	if marks.is_empty():
		return k * 4.0
	var prev := 0.0
	for i in marks.size():
		if k < marks[i]:
			return i + (k - prev) / max(0.0001, marks[i] - prev)
		prev = marks[i]
	return marks.size() + (k - prev) / max(0.0001, 1.0 - prev)


# An animation at frame position fp: that frame, cross-faded into the next near the end of its slot (both at full strength through the
# middle of the fade, so it never dips). scl: picture px -> world px about the anchor; stretch > 0 draws each frame's bolt axis that long
# (scl.y is then the most the thickness may scale, its sign flips it).
func _anim(ci: CanvasItem, an: Dictionary, fp: float, pos: Vector2, rot: float, scl: Vector2, col: Color, stretch: float = 0.0) -> void:
	col.a *= _fa
	if col.a <= 0.01:
		return
	var frames: Array = an["f"]
	var n = frames.size()
	fp = clamp(fp, 0.0, n - 0.001)
	var i = int(fp)
	var b := 0.0
	if i < n - 1:
		b = clamp((fp - i - (1.0 - FX_FADE)) / FX_FADE, 0.0, 1.0)
	if b < 1.0:
		_frame(ci, frames[i], pos, rot, scl, Color(col.r, col.g, col.b, col.a * min(1.0, 2.0 * (1.0 - b))), stretch)
	if b > 0.0:
		_frame(ci, frames[i + 1], pos, rot, scl, Color(col.r, col.g, col.b, col.a * min(1.0, 2.0 * b)), stretch)


static func _frame(ci: CanvasItem, fr: Dictionary, pos: Vector2, rot: float, scl: Vector2, col: Color, stretch: float) -> void:
	var c: Vector2 = fr["c"]
	if stretch > 0.0:
		var x0: float = fr["ax"][0]
		var x1: float = fr["ax"][1]
		var sx = stretch / max(1.0, x1 - x0)
		c = Vector2((x0 + x1) * 0.5, c.y)
		scl = Vector2(sx, sign(scl.y) * min(sx, abs(scl.y)))
	ci.draw_set_transform(pos, rot, scl)
	ci.draw_texture(fr["tex"], -c, col)


# One of our ants killed: knocked up, tips over and fades (old age: it just curls and settles). Placed and sized as units_view.gd draws it.
func _draw_corpse(f: Dictionary) -> void:
	var g = f.get("genome")
	if g == null:
		return
	var ph = colony.sim.phenotype(g)
	var caste = clampi(int(f.get("caste", 0)), 0, 2)
	var b = _bodies.get("alate_full" if ph.get("wings", 0) > 0 else CASTE_BODY[caste], _bodies.get(CASTE_BODY[caste]))
	if b == null:
		return
	var k = clamp(f["t"] / LIFE["corpse"], 0.0, 1.0)
	var raw: Vector2 = f["pos"]
	var lane = float(f.get("lane", 0.5))
	var pos = _at(raw, lane)
	var surf = pos != raw
	var old = f.get("old", false)
	var face = float(f.get("face", 1))
	var length = _length(float(ph.get("size", 74.0))) * CASTE_SCALE[caste] * _far * (Band.persp(lane) if surf else 1.0)
	var s = length / b["length"]
	var rise = 0.0 if old else sin(min(1.0, k * 2.2) * PI) * 10.0
	var tip = (0.35 if old else 1.6) * k * k * face
	var sag = (1.0 - 0.3 * k) if old else 1.0
	var shade = 0.85 - 0.25 * k
	var col = Color(shade, shade, shade, 1.0 - k * k) * _tint(g.color)
	if surf:
		col *= HAZE.lerp(Color.WHITE, clamp(lane, 0.0, 1.0)) * colony.day.tint
		col.a = (1.0 - k * k) * _la(lane)
		if col.a <= 0.01:
			return
	draw_set_transform(pos + Vector2(0, -rise + k * k * (3.0 if old else 8.0)), float(f.get("rot", 0.0)) + tip, Vector2(face * s, s * sag))
	draw_texture(b["tex"], -b["feet"], col)


static func _tint(c: Color) -> Color:
	if c.v < 0.3:
		c = Color.from_hsv(c.h, c.s, 0.3)
	return Color(c.r / KIT_BASE.r, c.g / KIT_BASE.g, c.b / KIT_BASE.b)


static func _length(size: float) -> float:
	var t = LEN_PER_SIZE * size + LEN_BASE
	return LEN_K * t * min(1.0, 310.0 / (t + 120.0))


# A floating word: pops in, rises and fades, outlined in ink so it reads on sky, grass and dirt; the same size on screen at any zoom.
func _draw_text(f: Dictionary) -> void:
	if _font == null:
		return
	var k = clamp(f["t"] / LIFE["text"], 0.0, 1.0)
	var c: Color = f["color"]
	c.a = 1.0 - k * k
	var pop = 1.0 + 0.6 * max(0.0, 1.0 - k * 7.0)
	var z = 1.0 / colony.zoom()
	var txt = str(f.get("text", ""))
	var w = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_PX).x
	draw_set_transform(_at(f["pos"]) + Vector2(0, -k * 40.0 * z), 0.0, Vector2(z, z) * pop)
	draw_string_outline(_font, Vector2(-w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_PX, 6, Color(0.08, 0.07, 0.1, c.a))
	draw_string(_font, Vector2(-w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_PX, c)
