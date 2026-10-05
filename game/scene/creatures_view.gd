extends Node2D
# Everything alive that is not one of our ants, all from the owner's drawings: the raiders and the meadow's prey (colony_sim.enemies),
# the rival colony's ants and its mound (core/rival.gd), the beehives on the trees with their bees (core/hives.gd), the bosses (the bird,
# the anteater, the spider, the Void Maw) and the food lying on the meadow (colony_sim.piles, the bird's carcass among them).
#
# Rigs (the old mod's rig_art.gd, ported): a creature is a body, a far and a near set of legs, jaws, wings and a glow, each piece placed where
# its manifest says (art_manifest "spider"/"void", critter_manifest, fauna_rig_manifest) and swung about its hinge, so one set of pictures
# walks, bites and flaps. The anteater has its own four parts (anteater/), the bird its five (bird_*.png).
#
# Placement copies units_view.gd: a raider stands on its cell's floor; on the surface it walks in a lane of the meadow band (band.gd), lifted,
# smaller and hazier toward the back, in the daylight tint; underground it stands flat in the cross-section, smaller and dimmer in the back
# tunnel plane and ghosted where front dirt hides it. Sizes are the old mod's (the manifests' game_len times the raid roster's art_scale).
# Zoomed out, every creature grows a little like the ants do, and a boss never shrinks below BOSS_MIN_PX on screen.
#
# Two canvases: this node (z 45, over the ants) draws the creatures and the bird; a child at BACK_Z (under the ants, over the nest) draws
# what lies on the ground or hangs in the trees: piles, carcass, hives, the rival mound and its idle ants. Everything off screen is skipped.
# A creature that has no picture (the grasshopper and the butterfly) is not drawn.

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WorldGrid = preload("res://core/world_grid.gd")
const EnemyDefs = preload("res://core/enemy_defs.gd")
const Hives = preload("res://core/hives.gd")
const WF = preload("res://core/world_features.gd")

const C = WorldGrid.CELL
const MARGIN = 420.0                 # world px past the view a creature can still reach into it (the Void Maw is 420 px wide)
const BACK_Z = -8                    # the back canvas, relative to this view: under the ants (40), over the nest (30)
const LANE_BUCKETS = 16
const BACK_SCALE = 0.8               # the back tunnel plane, as units_view.gd
const BACK_SHADE = 0.5
const HIDDEN_SHADE = 0.7
const HIDDEN_ALPHA = 0.55
const HAZE = Color(0.88, 0.92, 0.97)
const SURF_RATE = 3.0
const LANE_RATE = 4.0
const TURN_RATE = 6.0
const TURN_MIN = 0.3
const FAR_ZOOM = 0.45                # zoomed out past this, creatures grow (up to FAR_MAX), as the ants do
const FAR_MAX = 1.6
const BOSS_MIN_PX = 72.0             # a boss is never shorter than this on screen, at any zoom
const BOSS_ART = ["voidmaw", "anteater", "spider"]   # bosses besides the roster's "boss" class (the Emperor Scorpion, the Void Maw)
const RETREAT_ALPHA = 0.75
const LOD_PX = 9.0                   # a rig shorter than this on screen draws only its body
const HURT_FLASH = true
# the roster's art names -> rig names (anything else is its own name)
const RIG_OF = {"voidmaw": "void", "redant": "redant_small"}
const CRITTER_RIG = {"ladybird": "ladybug", "snail": "snail", "caterpillar": "caterpillar", "bee": "bee", "dragonfly": "dragonfly"}
# the rival's own ants drawn with our kit, tinted by its genome: caste body by raider class, and how much bigger than an ordinary ant
const KIN_BODY = {"small": "worker_full", "brute": "soldier_full", "elite": "soldier_full", "boss": "soldier_full"}
const KIN_SIZE = {"small": 1.0, "brute": 1.1, "elite": 1.22, "boss": 1.4}
const KIN_CAST = Color(1.0, 0.74, 0.7)    # a red cast, so the descendants are never mistaken for ours
const KIT_BASE = Color(0.60, 0.52, 0.46)  # the kit's mean fill (units_view.gd): genome colour / this tints a picture
const LEN_PER_SIZE = 2.2                  # ant length from phenotype size, as units_view.gd
const LEN_BASE = 24.0
const LEN_K = 0.132
# the Tunnel Borer: world px at scale 1. An ant is ~17 long and ~7 high; the worm is five or six ants long and fills the ~18 px tunnel it bores.
const WORM_LEN = 96.0
const WORM_THICK = 13.0              # mean thickness of the body (the head is wider)
const WORM_SEGS = 16                 # slices of the picture along its length
const WORM_STEP = 3.0                # px between the samples of the head's trail
const WORM_KEEP = 90                 # samples kept: the longest body (zoomed out, thick and thin) with room to spare
const WORM_SMOOTH = 3                # samples either side the trail is averaged over, so the cell steps do not kink the body
const WORM_WAVES = 2.4               # peristaltic waves along the body
const WORM_WAVE = 38.0               # px the head travels while the wave moves on one wavelength
const WORM_LIFT_N = 5                # stations of the head that rear on the meadow
const WORM_PROF = 5                  # columns the picture's outline is smoothed over
# the anteater (the old creature_art.gd): nose to tail in world px, and how far its legs rock
const ANTEATER_LEN = 380.0
const ANTEATER_STEP = 0.07
# the bird (the old rig_art.gd and predator_view.gd): its five pieces flapped about the shoulder
const BIRD_K = 0.5
const BIRD_LANE = 0.5
const BIRD_SPAN = 600.0                 # art px from wing tip to beak
const BIRD_DROP = 260.0                 # art px from the shoulder origin down to the talons and the low wing tip
const BIRD_FALL_T = 1.3                 # seconds the sim lets bird_fall drop (colony_sim._step_bird_fall)
const DEAD_PIVOT = Vector2(-60, 20)
const DEAD_REACH = 198.0
const DEAD_REACH_K = -86.0
const DEAD_SINK = 10.0
const DEAD_TILT = 2.85
const WING_B_DEAD = -0.5
const WING_A_DEAD = -0.1
const HEAD_DEAD = 0.15
# the Void Maw climbing out of the collapse pit (arc.gd void_born): seconds it takes
const EMERGE_T = 4.5
# a raider killed keels over and fades
const DIE_T = 0.9
const DIE_T_BOSS = 1.6
# hives (the old hive_art.gd): the three hanging stages, how many bees circle a hive
const HANGING = ["hive_whole", "hive_drip", "hive_damaged"]
const HIVE_BEES = 3
const TREE_PICK_FALLBACK = [[0.30, "oak1", 0.88], [0.58, "oak2", 0.88], [0.68, "mossoak", 0.55], [0.76, "acacia", 0.4], [0.82, "grove", 0.5],
	[0.93, "spruce", 0.95], [0.97, "stump", 0.38], [1.0, "log", 0.16]]
# piles: the lane they lie in (units_view.gd pulls foragers onto it), the food pictures, honey pieces
const PILE_LANE = 0.5
const PILE_FOODS = ["seeds", "crumb", "berries", "honeydew", "seeds", "crumb"]
const PILE_K = 0.8                  # food pictures at this share of their manifest size (sized for a 40 px worker; ours are about 25)
const PILE_ROWS = [[0, 0], [-1, 0], [1, 0], [-2, 0], [2, 0], [-0.5, 1], [0.5, 1], [-1.5, 1], [1.5, 1], [0, 2]]
const HONEY_PIECES = ["comb_three", "comb_one", "comb_chunk", "comb_cell", "comb_bit", "comb_drip", "comb_big"]
# the rival mound (core/rival.gd): its lane and width at the front of the band
const RIVAL_LANE = 0.5
const RIVAL_W = 290.0
const RIVAL_TINT = Color(0.9, 0.78, 0.74)
const RIVAL_IDLE = 8

var colony
var _back: Node2D
var _t := 0.0
var _dt := 0.016
var _tex := {}              # path -> mipmapped texture (or null)
var _rigs := {}             # rig name -> {scale, feet, height, order, layers, ...} (see _add_rig)
var _kit := {}              # antkit body name -> {tex, feet, length}
var _foods := []            # [{tex, size}] food pictures for piles
var _trees := {}            # tree name -> manifest entry
var _tree_pick := TREE_PICK_FALLBACK
var _anteater := {}         # anteater_manifest.json
var _state := {}            # raider id -> Vector3(surface 0..1, drawn lane, drawn facing)
var _seen := {}             # raider id -> [raider, pos, state, k] as drawn last frame (for the death fall)
var _dying := []            # [{e, p, st, k, t}]
var _born := {}             # raider id -> sim time first seen (the Void Maw's climb out of the pit)
var _lane_alpha := Callable()   # band.gd's lane_alpha(lane[, tall]) when it has one: the depth zoom cuts the near lanes
var _alpha_tall := false        # ... and it takes the `tall` flag (for what hangs in the trees)
var _worm := {}             # borer id -> {tr: the head's trail (cell-space samples, oldest first), last, p, spd, mv, ph (wave), flip, ftgt, lane, rear}
var _worm_gc_t := 0.0
var _earthworm := {}        # fauna_manifest "earthworm": the Tunnel Borer's picture
var _wp := {}               # its outline per column (_worm_profile)
var _hover := 0.0           # the bird wheels about over its prey
var _bird_px := 0.0
var _bird_last := Vector2.ZERO
var _bird_ok := false
var _fall_origin = null
var _had_fall := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_back = Node2D.new()
	_back.name = "ground_things"
	_back.z_index = BACK_Z
	_back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_back.draw.connect(_draw_back)
	add_child(_back)
	_load_rigs()
	var band: Object = Band
	for m in band.get_script_method_list():
		if m["name"] == "lane_alpha":
			_lane_alpha = Callable(band, "lane_alpha")
			_alpha_tall = m.get("args", []).size() >= 2
	var kit = Art.manifest("antkit_manifest.json").get("pieces", {})
	for name in ["worker_full", "soldier_full", "worker_small_full"]:
		var p = kit.get(name)
		if p == null or _tx(str(p["file"])) == null:
			continue
		_kit[name] = {"tex": _tx(str(p["file"])), "feet": Vector2(p["feet"][0], p["feet"][1]), "length": float(p["length"])}
	var fauna = Art.manifest("fauna_manifest.json").get("items", {})
	for name in PILE_FOODS + ["apple"]:
		var f = fauna.get(name)
		if f != null and _tx(str(f["file"])) != null:
			_foods.append({"name": name, "tex": _tx(str(f["file"])), "size": Vector2(f["w"], f["h"]) * float(f["scale"]) * PILE_K})
	for t in Art.manifest("art_manifest.json").get("trees", []):
		_trees[t["name"]] = t
	if ResourceLoader.exists("res://scene/surface_view.gd"):
		var sv = load("res://scene/surface_view.gd")
		if sv != null:
			_tree_pick = sv.get_script_constant_map().get("TREE_PICK", TREE_PICK_FALLBACK)
	_anteater = Art.manifest("anteater/anteater_manifest.json")
	_earthworm = Art.manifest("fauna_manifest.json").get("items", {}).get("earthworm", {})
	_worm_profile()


func reset() -> void:
	_state = {}
	_seen = {}
	_dying = []
	_born = {}
	_worm = {}
	_bird_ok = false
	_fall_origin = null


func _process(delta: float) -> void:
	_dt = delta
	if not colony.paused:
		_t += delta
	if _born.size() > 400:
		# forget the raiders that are gone (critters come and go all game)
		var live := {}
		for e in colony.sim.enemies:
			if _born.has(e.id):
				live[e.id] = _born[e.id]
		_born = live
	queue_redraw()
	_back.queue_redraw()


# ---------------------------------------------------------------- textures
# The pictures are imported without mipmaps; creatures are drawn at a fifth of their size or less, which without them sparkles.
func _tx(path: String) -> Texture2D:
	if not _tex.has(path):
		var t = Art.tex(path)
		if t != null:
			var img = t.get_image()
			if img != null and not img.is_empty() and not img.has_mipmaps():
				img.generate_mipmaps()
				t = ImageTexture.create_from_image(img)
		_tex[path] = t
	return _tex[path]


# ---------------------------------------------------------------- rigs
func _load_rigs() -> void:
	var man = Art.manifest("art_manifest.json")
	for k in ["spider", "void"]:
		if man.get(k) is Dictionary:
			_add_rig(k, man[k], "")
	for src in [["critter_manifest.json", ""], ["fauna_rig_manifest.json", "fauna_rig/"]]:
		var m = Art.manifest(src[0])
		for k in m:
			if m[k] is Dictionary and m[k].has("body") and not _rigs.has(k):
				_add_rig(k, m[k], src[1])


# A file named in a rig manifest: as written when it has a folder, else under the manifest's folder (the void pictures also live in fauna/).
static func _rig_path(file: String, pre: String) -> String:
	var p = file if file.find("/") >= 0 else pre + file
	if Art.tex(p) == null and Art.tex("fauna/" + file.get_file()) != null:
		return "fauna/" + file.get_file()
	return p


static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _add_rig(name: String, e: Dictionary, pre: String) -> void:
	var r := {"scale": float(e["scale"]), "feet": _v(e["feet"]), "height": float(e.get("height", 100.0)), "order": e.get("order", ["far", "body", "near"]),
		"wave": bool(e.get("wave", false)), "strip": float(e.get("wave_strip", 34.0)), "cw": max(1.0, float(e.get("canvas", [1, 1])[0])), "layers": {}}
	r["body"] = {"file": _rig_path(str(e["body"]["file"]), pre), "pos": Vector2(float(e["body"]["x"]), float(e["body"]["y"]))}
	for p in e.get("parts", []):
		var l = str(p["layer"])
		if not r["layers"].has(l):
			r["layers"][l] = []
		r["layers"][l].append({"file": _rig_path(str(p["file"]), pre), "pos": Vector2(float(p["x"]), float(p["y"])), "pivot": _v(p["pivot"]),
			"phase": float(p.get("phase", 0))})
	for key in ["cavity", "glow"]:
		if e.get(key) is Dictionary:
			r[key] = {"file": _rig_path(str(e[key]["file"]), pre), "pos": Vector2(float(e[key]["x"]), float(e[key]["y"]))}
	if e.get("jaws") is Array:
		r["jaws"] = []
		for j in e["jaws"]:
			r["jaws"].append({"file": _rig_path(str(j["file"]), pre), "pos": Vector2(float(j["x"]), float(j["y"])), "pivot": _v(j["pivot"]), "open": float(j.get("open", 0.0))})
	if e.get("wings") is Array:
		r["wings"] = []
		for w in e["wings"]:
			r["wings"].append({"file": _rig_path(str(w["file"]), pre), "pos": Vector2(float(w["x"]), float(w["y"])), "pivot": _v(w["pivot"]),
				"layer": str(w.get("layer", "near")), "flap": float(w.get("flap", 0.4)), "speed": float(w.get("speed", 40.0)), "phase": float(w.get("phase", 0.0))})
	_rigs[name] = r


# World height of a rig at scale 1.
func _rig_h(name: String) -> float:
	var r = _rigs.get(name)
	return r["height"] * r["scale"] if r != null else 40.0


static func _put(ci: CanvasItem, base: Transform2D, tex: Texture2D, pos: Vector2, pivot: Vector2, ang: float, mod: Color) -> void:
	var m = base
	if ang != 0.0:
		m = base * Transform2D(0.0, pivot) * Transform2D(ang, Vector2.ZERO) * Transform2D(0.0, -pivot)
	ci.draw_set_transform_matrix(m)
	ci.draw_texture(tex, pos, mod)


static func _flash(mod: Color) -> Color:
	return Color(min(1.0, mod.r + 0.35), mod.g * 0.55, mod.b * 0.55, mod.a)


# A rigged creature standing at `feet` (world), `scale` times its manifest size, facing +1/-1 (a fraction squashes it through a turn).
# `mouth` 0..1 opens the jaws; `rot` tips the whole creature about its feet (a death). False when the art is missing.
func _rig(ci: CanvasItem, name: String, feet: Vector2, scale: float, facing: float, t: float, moving: bool, mouth: float, mod: Color, flash: bool, rot: float = 0.0) -> bool:
	var r = _rigs.get(name)
	if r == null:
		return false
	var btex = _tx(r["body"]["file"])
	if btex == null:
		return false
	var s = r["scale"] * scale
	var fv: Vector2 = r["feet"]
	var base = Transform2D(rot, feet) * Transform2D(Vector2(facing * s, 0), Vector2(0, s), Vector2.ZERO)
	if flash:
		mod = _flash(mod)
	if r["height"] * s * colony.zoom() < LOD_PX:
		# a few pixels on screen (zoomed far out): the body alone reads the same and costs one draw instead of a dozen
		_put(ci, base, btex, r["body"]["pos"] - fv, Vector2.ZERO, 0.0, mod)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return true
	var fly = r.has("wings")
	var gait = 2.2 if fly else (6.0 if moving else 1.6)
	var amp = 0.1 if fly else (0.13 if moving else 0.025)
	var bob = sin(t * gait * 2.0) * (3.0 if moving else 1.2)
	for layer in r["order"]:
		if layer == "body":
			_rig_body(ci, r, base, fv, btex, t, moving, mouth, mod, bob)
			continue
		var parts: Array = r["layers"].get(layer, [])
		var wave = parts.size() > 5         # many legs a side (a centipede, the Void Maw): a wave runs from tail to head
		for p in parts:
			var tx = _tx(p["file"])
			if tx == null:
				continue
			var ph = p["phase"] * PI + (0.0 if layer == "near" else 0.7)
			if wave:
				ph = -p["pivot"].x / r["cw"] * TAU * 1.5 + (0.0 if layer == "near" else PI)
			var sw = sin(t * gait + ph)
			var lift = max(0.0, cos(t * gait + ph)) * (9.0 if moving else 0.0) * (0.6 if wave else 1.0)
			if fly:
				lift = -bob
			var pos = p["pos"] - fv + Vector2(0, -lift)
			var pv = p["pivot"] - fv + (Vector2(0, -lift) if fly else Vector2.ZERO)
			_put(ci, base, tx, pos, pv, sw * amp * (0.7 if wave else 1.0), mod)
		if fly:
			for w in r["wings"]:
				if w["layer"] != layer:
					continue
				var wt = _tx(w["file"])
				if wt == null:
					continue
				var wa = sin(t * w["speed"] + w["phase"]) * w["flap"]
				var wo = Vector2(0, bob)
				_put(ci, base, wt, w["pos"] - fv + wo, w["pivot"] - fv + wo, wa, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _rig_body(ci: CanvasItem, r: Dictionary, base: Transform2D, fv: Vector2, btex: Texture2D, t: float, moving: bool, mouth: float, mod: Color, bob: float) -> void:
	var bpos = r["body"]["pos"] - fv + Vector2(0, bob)
	if r.has("cavity"):
		var ct = _tx(r["cavity"]["file"])
		if ct != null:
			_put(ci, base, ct, r["cavity"]["pos"] - fv + Vector2(0, bob), Vector2.ZERO, 0.0, mod)
	if r["wave"]:
		# a rippling crawl: the body in strips that rise and fall in a wave from the tail to the head, quiet at the head
		var sz = btex.get_size()
		var sw: float = r["strip"]
		ci.draw_set_transform_matrix(base)
		var x := 0.0
		while x < sz.x:
			var u = x / sz.x
			var dy = sin(t * (3.2 if moving else 1.2) - u * 8.0) * (11.0 if moving else 4.0) * (1.0 - clamp((u - 0.45) / 0.45, 0.0, 1.0))
			var w = min(sw + 1.0, sz.x - x)
			ci.draw_texture_rect_region(btex, Rect2(bpos.x + x, bpos.y + dy, w, sz.y), Rect2(x, 0, w, sz.y), mod)
			x += sw
	else:
		_put(ci, base, btex, bpos, Vector2.ZERO, 0.0, mod)
	if r.has("jaws"):
		for j in r["jaws"]:
			var jt = _tx(j["file"])
			if jt != null:
				_put(ci, base, jt, j["pos"] - fv + Vector2(0, bob), j["pivot"] - fv + Vector2(0, bob), j["open"] * mouth, mod)
	if r.has("glow"):
		var gt = _tx(r["glow"]["file"])
		if gt != null:
			_put(ci, base, gt, r["glow"]["pos"] - fv + Vector2(0, bob), Vector2.ZERO, 0.0, Color(1, 1, 1, mod.a * (0.45 + 0.4 * sin(t * 2.6))))


# ---------------------------------------------------------------- the Tunnel Borer
# The owner's earthworm (fauna/earthworm.png, mouth to the right) bent along the path the borer has travelled. The head's positions are kept
# (_worm_track: a sample every WORM_STEP px, on screen or not) and each frame the body is laid along that trail from the head back: the
# picture cut into WORM_SEGS slices, each a quad between two points of the trail pushed half a thickness out either side, so it follows the
# tunnel it bored round every corner and is never drawn where it has not been. The picture's own S-curve is straightened first (_worm_profile:
# per column, where the body's middle and edges are). A wave of thick and thin runs tail to head while it crawls (shorter and fatter, then
# long and thin), a slow breathing while it rests. On the meadow it lies along the ground in its lane, head lifted, and goes down the hole at
# the lip. The back of the picture stays up: when the head turns round the body rolls over, it never hangs upside down.
func _worm_profile() -> void:
	var tex = _tx(str(_earthworm.get("file", "")))
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	if img.is_compressed():
		img.decompress()
	var w = img.get_width()
	var h = img.get_height()
	var top := PackedFloat32Array()
	var bot := PackedFloat32Array()
	top.resize(w)
	bot.resize(w)
	var first := -1
	var last := -1
	for x in w:
		var a := -1
		var b := -1
		for y in h:
			if img.get_pixel(x, y).a >= 0.1:
				if a < 0:
					a = y
				b = y
		top[x] = float(a)
		bot[x] = float(b + 1)
		if a >= 0:
			if first < 0:
				first = x
			last = x
	if first < 0:
		return
	for x in w:
		var xi = clampi(x, first, last)
		if top[xi] < 0.0:
			var l = xi
			while l > first and top[l] < 0.0:
				l -= 1
			var r = xi
			while r < last and top[r] < 0.0:
				r += 1
			top[x] = (top[l] + top[r]) * 0.5
			bot[x] = (bot[l] + bot[r]) * 0.5
		elif x != xi:
			top[x] = top[xi]
			bot[x] = bot[xi]
	var c := PackedFloat32Array()
	var hh := PackedFloat32Array()
	c.resize(w)
	hh.resize(w)
	var sum := 0.0
	for x in w:
		var a := 0.0
		var b := 0.0
		var n := 0
		for d in range(-WORM_PROF, WORM_PROF + 1):
			var xi = clampi(x + d, 0, w - 1)
			a += top[xi]
			b += bot[xi]
			n += 1
		c[x] = (a + b) * 0.5 / n
		hh[x] = (b - a) * 0.5 / n
		if x >= 14 and x < w - 6:
			sum += hh[x]
	var mean = sum / float(max(1, w - 20))
	for x in w:
		hh[x] += 2.5            # a little of the clear border, so the edge stays soft
	_wp = {"c": c, "h": hh, "w": float(w), "ht": float(h), "k": WORM_THICK * 0.5 / mean}


func _wp_at(xt: float) -> Vector2:
	var c: PackedFloat32Array = _wp["c"]
	var h: PackedFloat32Array = _wp["h"]
	var x = clampf(xt, 0.0, float(c.size() - 1))
	var i = int(x)
	var j = mini(i + 1, c.size() - 1)
	var f = x - i
	return Vector2(lerpf(c[i], c[j], f), lerpf(h[i], h[j], f))


# A borer's trail begins lying along the ground behind its head (a borer is born on the meadow); one that appears underground gets what open
# room there is behind it (at least a short neck).
func _worm_new(e, p: Vector2) -> Dictionary:
	var g = colony.grid
	var dir = -float(e.facing) if e.facing != 0 else 1.0
	var under = p.y > (g.surf_y(int(floor(p.x / C))) + 0.6) * C
	var pts := []
	for sgn in [dir, -dir]:
		var one := []
		for i in range(1, WORM_KEEP):
			var x = p.x + sgn * i * WORM_STEP
			var cx = int(floor(x / C))
			var y = p.y if under else (g.surf_y(cx) - 0.5) * C
			if under and i > 4 and g.is_solid(cx, int(floor(y / C))):
				break
			one.append(Vector2(x, y))
		if one.size() > pts.size():
			pts = one
		if not under:
			break
	pts.reverse()
	pts.append(p)
	var f = 1.0 if e.facing >= 0 else -1.0
	return {"tr": pts, "last": p, "p": p, "spd": 0.0, "mv": 0.0, "ph": randf() * TAU, "flip": f, "ftgt": f, "lane": -1.0, "rear": 1.0}


func _worm_track(e, p: Vector2) -> void:
	var w = _worm.get(e.id)
	if w == null or w["last"].distance_to(p) > 48.0:
		w = _worm_new(e, p)
		_worm[e.id] = w
	var tr: Array = w["tr"]
	var last: Vector2 = w["last"]
	while last.distance_to(p) >= WORM_STEP:
		last = last.move_toward(p, WORM_STEP)
		tr.append(last)
	while tr.size() > WORM_KEEP:
		tr.pop_front()
	w["last"] = last
	var moved = p.distance_to(w["p"])
	w["p"] = p
	if colony.paused or _dt <= 0.0:
		return
	w["spd"] = lerpf(w["spd"], moved / _dt, 1.0 - exp(-_dt * 6.0))
	w["mv"] = clampf(w["spd"] / 6.0, 0.0, 1.0)
	w["ph"] += _dt * (1.2 + 0.8 * w["mv"]) + moved * TAU / WORM_WAVE


func _worm_gc() -> void:
	_worm_gc_t -= _dt
	if _worm_gc_t > 0.0 or _worm.is_empty():
		return
	_worm_gc_t = 0.5
	var live := {}
	for e in colony.sim.enemies:
		if e.cls == "burrower":
			live[e.id] = true
	for d in _dying:
		live[d["it"][0].id] = true
	for id in _worm.keys():
		if not live.has(id):
			_worm.erase(id)


func _draw_worm(ci: CanvasItem, e, p: Vector2, st: Vector3, kk: float, col: Color, flash: bool, rot: float) -> bool:
	var tex = _tx(str(_earthworm.get("file", "")))
	var w = _worm.get(e.id)
	if tex == null or w == null or _wp.is_empty():
		return false
	var g = colony.grid
	# the lane it lies in: it comes forward to the lip as it gets ready to dive, so it goes in at the ground line
	var lane_t = lerpf(st.y, 1.0, smoothstep(0.3, 2.0, e.timer)) if e.state == 0 else 1.0
	var lane = lane_t if w["lane"] < 0.0 else lerpf(w["lane"], lane_t, 1.0 - exp(-_dt * 5.0))
	w["lane"] = lane
	var rz = Band.raise(lane)
	var pl = Band.persp(lane)
	var half = WORM_THICK * 0.5 * kk
	# the trail as drawn, head first: on the meadow raised to its lane, in the soil where it was
	var tr: Array = w["tr"]
	var raw := PackedVector2Array()
	var sc := PackedFloat32Array()
	var wg := PackedFloat32Array()
	var n = tr.size()
	for j in range(-1, n):
		var q: Vector2 = p if j < 0 else tr[n - 1 - j]
		var gy = float(g.surf_y(int(floor(q.x / C)))) * C
		var s = clampf((gy + 1.5 * C - q.y) / (2.0 * C), 0.0, 1.0)
		var k = lerpf(1.0, pl, s)
		raw.append(Vector2(q.x, q.y + s * (C * 0.5 - rz - half * k)))
		sc.append(k)
		wg.append(s)
	var m = raw.size()
	var pol := PackedVector2Array()
	pol.resize(m)
	for j in m:
		var a := Vector2.ZERO
		for d in range(-WORM_SMOOTH, WORM_SMOOTH + 1):
			a += raw[clampi(j + d, 0, m - 1)]
		pol[j] = a / float(2 * WORM_SMOOTH + 1)
	var mv: float = w["mv"]
	var amp = lerpf(0.05, 0.17, mv) * (0.35 if e.stun_t > 0.0 else 1.0)
	var ph: float = w["ph"]
	# the stations: WORM_SEGS slices from the head back, spaced along the trail (a fat slice is a short one)
	var N = WORM_SEGS
	var ps := PackedVector2Array()
	var pk := PackedFloat32Array()
	var pw := PackedFloat32Array()
	var pu := PackedFloat32Array()
	ps.append(pol[0])
	pk.append(sc[0])
	pw.append(wg[0])
	pu.append(0.0)
	var seg = 0
	var acc := 0.0
	var target := 0.0
	var nominal = WORM_LEN * kk / N
	var cut := false
	for i in range(1, N + 1):
		var li = nominal * (1.0 - 0.8 * amp * sin(TAU * WORM_WAVES * (i - 0.5) / N + ph))
		target += li
		var found := false
		while seg < m - 1:
			var d = pol[seg].distance_to(pol[seg + 1])
			var c = d / maxf(0.5 * (sc[seg] + sc[seg + 1]), 0.05)
			if acc + c >= target:
				var f = (target - acc) / maxf(c, 0.0001)
				ps.append(pol[seg].lerp(pol[seg + 1], f))
				pk.append(lerpf(sc[seg], sc[seg + 1], f))
				pw.append(lerpf(wg[seg], wg[seg + 1], f))
				pu.append(float(i))
				found = true
				break
			acc += c
			seg += 1
		if not found:
			# the trail ran out (it has not come that far yet): the body ends where the tunnel does, in a rounded tail
			cut = true
			var f = clampf((acc - (target - li)) / li, 0.0, 1.0)
			if f > 0.08:
				ps.append(pol[m - 1])
				pk.append(sc[m - 1])
				pw.append(wg[m - 1])
				pu.append(float(i - 1) + f)
			break
	var cnt = ps.size()
	if cnt < 2:
		return false
	# the head rears a little on the meadow, never in the soil (it would leave its tunnel)
	w["rear"] = lerpf(w["rear"], pw[0], 1.0 - exp(-_dt * 4.0))
	var lift = half * 2.2 * (0.55 + 0.45 * sin(_t * 1.7 + e.id)) * (1.0 - 0.45 * mv) * w["rear"]
	for i in mini(cnt, WORM_LIFT_N):
		var r = 1.0 - float(i) / WORM_LIFT_N
		ps[i].y -= lift * r * r
	# the back stays up: the picture faces the way the head goes, rolling over when it turns round
	var hd = ps[0] - ps[mini(3, cnt - 1)]
	var tgt: float = w["ftgt"]
	if hd.x > 0.3 * hd.length():
		tgt = 1.0
	elif hd.x < -0.3 * hd.length():
		tgt = -1.0
	w["ftgt"] = tgt
	w["flip"] = move_toward(w["flip"], tgt, _dt * 8.0)
	var flip: float = w["flip"]
	if flash:
		col = _flash(col)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var tw: float = _wp["w"]
	var th: float = _wp["ht"]
	var hk: float = _wp["k"] * kk
	var tdir := Vector2.RIGHT
	for i in cnt:
		var tv = ps[maxi(i - 2, 0)] - ps[mini(i + 2, cnt - 1)]      # the heading over a few slices, so a sharp bend does not twist one
		if tv.length_squared() > 0.0001:
			tdir = tv.normalized()
		var u = 1.0 - pu[i] / N
		var pr = _wp_at(u * tw)
		var tip := 1.0
		if cut and i >= cnt - 3:
			var q = float(i - (cnt - 4)) / 3.0
			tip = maxf(sqrt(1.0 - q * q), 0.12)
		var nrm = tdir.rotated(PI * 0.5) * (flip * tip * pr.y * hk * pk[i] * (1.0 + amp * sin(TAU * WORM_WAVES * pu[i] / N + ph)))
		pts.append(ps[i] - nrm)
		pts.append(ps[i] + nrm)
		uvs.append(Vector2(u, (pr.x - pr.y) / th))
		uvs.append(Vector2(u, (pr.x + pr.y) / th))
		cols.append(col)
		cols.append(col)
		if i < cnt - 1:
			var b = 2 * i
			idx.append_array(PackedInt32Array([b, b + 2, b + 1, b + 1, b + 2, b + 3]))
	if rot != 0.0:
		for i in pts.size():
			pts[i] = ps[0] + (pts[i] - ps[0]).rotated(rot)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())
	return true


# ---------------------------------------------------------------- the anteater (four parts: tail, hind legs, front legs, body with head)
func _anteater_h() -> float:
	if _anteater.is_empty():
		return 150.0
	return ANTEATER_LEN / float(_anteater["x1"] - _anteater["x0"]) * float(_anteater["ground"])


func _draw_anteater(ci: CanvasItem, feet: Vector2, scale: float, facing: float, t: float, moving: bool, col: Color, flash: bool, rot: float = 0.0) -> bool:
	var m = _anteater
	if m.is_empty() or int(m.get("version", 1)) < 2:
		return false
	var k = ANTEATER_LEN / float(m["x1"] - m["x0"]) * scale
	var mid = (float(m["x0"]) + float(m["x1"])) * 0.5
	var base = Transform2D(rot, feet) * Transform2D(Vector2(facing * k, 0.0), Vector2(0.0, k), Vector2.ZERO) * Transform2D(0.0, Vector2(-mid, -float(m["ground"])))
	if flash:
		col = Color(1.0, 0.45, 0.42, col.a)
	var ph = t * (3.0 if moving else 0.6)
	var bob = abs(sin(ph)) * -14.0 if moving else sin(t * 1.3) * 4.0
	for p in m["parts"]:
		var tex = _tx(str(p["file"]))
		if tex == null:
			continue
		var sz = Vector2(float(p["w"]), float(p["h"]))
		var piv = Vector2(float(p["pivot"][0]), float(p["pivot"][1])) * sz
		var at = Vector2(float(p["off"][0]), float(p["off"][1])) + piv
		var a := 0.0
		var d := Vector2.ZERO
		match str(p["name"]):
			"tail":
				a = sin(t * 1.4) * 0.05 + (sin(ph) * 0.03 if moving else 0.0)
				d.y = bob * 0.6
			"hind", "front":
				var lp = ph + (PI if p["name"] == "hind" else 0.0)
				if moving:
					a = sin(lp) * ANTEATER_STEP
					d = Vector2(sin(lp) * 18.0, bob * 0.3 - max(0.0, cos(lp)) * 10.0)
				else:
					a = sin(t * 0.9 + (1.0 if p["name"] == "hind" else 0.0)) * 0.008
			"body":
				a = sin(ph * 2.0) * (0.012 if moving else 0.004)
				d.y = bob
		ci.draw_set_transform_matrix(base * Transform2D(a, at + d))
		ci.draw_texture_rect(tex, Rect2(-piv, sz), false, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


# ---------------------------------------------------------------- the raiders and the prey
func _draw() -> void:
	var sim = colony.sim
	var g = colony.grid
	var vr = colony.view_rect(MARGIN)
	vr.size.y += Band.DEPTH * Band.LANE_K + 120.0     # surface creatures stand up to a lane above their cell, fliers higher
	vr.position.y -= 120.0
	var zoom = colony.zoom()
	var far = clamp(sqrt(FAR_ZOOM / zoom), 1.0, FAR_MAX)
	var ks = 1.0 - exp(-_dt * SURF_RATE)
	var kl = 1.0 - exp(-_dt * LANE_RATE)
	var state := {}
	var seen := {}
	var back := []
	var front := []
	var lanes := []
	for i in LANE_BUCKETS:
		lanes.append([])
	for e in sim.enemies:
		if not _born.has(e.id):
			_born[e.id] = sim.time
		var p = sim.enemy_pos(e)
		if e.cls == "burrower":
			_worm_track(e, p)        # its trail is kept off screen too
		if not vr.has_point(p):
			continue
		var surf = 1.0 if e.ty <= g.surf_y(e.tx) else 0.0
		var st: Vector3 = _state.get(e.id, Vector3(surf, e.lane, e.facing))
		st = Vector3(lerp(st.x, surf, ks), lerp(st.y, e.lane, kl), move_toward(st.z, e.facing, _dt * TURN_RATE))
		state[e.id] = st
		var it = [e, p, st]
		if st.x >= 0.5:
			lanes[clampi(int(st.y * LANE_BUCKETS), 0, LANE_BUCKETS - 1)].append(it)
		elif lerp(float(e.z), float(e.tz), clamp(e.t, 0.0, 1.0)) > 0.5:
			back.append(it)
		else:
			front.append(it)
	_state = state
	for it in back:
		seen[it[0].id] = _draw_enemy(self, it[0], it[1], it[2], far, zoom)
	for it in front:
		seen[it[0].id] = _draw_enemy(self, it[0], it[1], it[2], far, zoom)
	for bucket in lanes:
		for it in bucket:
			seen[it[0].id] = _draw_enemy(self, it[0], it[1], it[2], far, zoom)
	_note_deaths(seen)
	_draw_dying(far, zoom)
	_worm_gc()
	_step_bird()
	if sim.bird != null:
		_draw_bird(sim.bird, zoom)
	if sim.bird_fall != null:
		_draw_bird_fall(sim.bird_fall, zoom)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _is_boss(e) -> bool:
	return e.cls == "boss" or e.def.get("art", "") in BOSS_ART


# Draws one raider; returns what the death fall needs to redraw it as it was: [raider, pos, state].
func _draw_enemy(ci: CanvasItem, e, p: Vector2, st: Vector3, far: float, zoom: float, die: float = -1.0) -> Array:
	var g = colony.grid
	var t = clamp(e.t, 0.0, 1.0)
	var plane = lerp(float(e.z), float(e.tz), t)
	var hidden = lerp(_behind(g, e.x, e.y, e.z), _behind(g, e.tx, e.ty, e.tz), t)
	var surf = st.x
	var lane = st.y
	var depth = lerp(1.0, Band.persp(lane), surf) * lerp(1.0, BACK_SCALE, plane)
	var feet = p + Vector2(0, C * 0.5)
	feet.y = lerp(feet.y, Band.lane_y(feet.y, lane), surf)
	var shade = lerp(1.0, BACK_SHADE, plane) * lerp(1.0, HIDDEN_SHADE, hidden)
	var col = Color(shade, shade, shade, lerp(1.0, HIDDEN_ALPHA, hidden) * (RETREAT_ALPHA if e.state == 2 else 1.0))
	col *= Color.WHITE.lerp(HAZE.lerp(Color.WHITE, clamp(lane, 0.0, 1.0)) * colony.day.tint, surf)
	if surf > 0.0 and not _is_boss(e):
		col.a *= lerp(1.0, _la(lane), surf)        # the depth zoom cuts the near lanes (a boss always shows)
		if col.a <= 0.01:
			return [e, p, st]
	var face = st.z if abs(st.z) > TURN_MIN else (TURN_MIN if st.z >= 0.0 else -TURN_MIN)
	var moving = (e.tx != e.x or e.ty != e.y) and e.stun_t <= 0.0 and die < 0.0
	var tt = _t + e.id * 0.7
	var flash = e.flash > 0.0 and die < 0.0
	var mouth = (0.5 + 0.5 * sin(_t * 8.0 + e.id)) if (e.engaged and e.state != 2) else (0.12 + 0.12 * sin(_t * 1.6 + e.id))
	var rot := 0.0
	if die >= 0.0:
		# killed: it rears a little, keels over backwards and fades into the ground
		rot = -face * 1.25 * die * die
		feet.y += die * die * 6.0 * depth
		col.a *= 1.0 - die * die
		mouth = 0.6
	var art = str(e.def.get("art", ""))
	var k = far * depth
	var h := 40.0
	var drawn := false
	if e.genome != null:
		drawn = _draw_kin(ci, e, feet, k, face, col, flash, rot, moving)
		h = 20.0 * k
	elif e.def.has("critter"):
		var rig = CRITTER_RIG.get(str(e.def["critter"]), "")
		if rig != "":
			var lift = (30.0 + 8.0 * sin(_t * 2.1 + e.id)) * k * surf if e.def.get("fly", false) else 0.0
			h = _rig_h(rig) * k
			drawn = _rig(ci, rig, feet - Vector2(0, lift), k, face, tt, moving or e.def.get("fly", false), 0.2, col, flash, rot)
			feet.y -= lift
	elif e.cls == "burrower":
		h = WORM_THICK * 3.0 * k
		drawn = _draw_worm(ci, e, p, st, far * lerp(1.0, BACK_SCALE, plane), col, flash, rot)
	elif art == "anteater":
		h = _anteater_h()
		k = _boss_k(k, h, zoom)
		h *= k
		drawn = _draw_anteater(ci, feet, k, face, tt, moving, col, flash, rot)
	elif art != "":
		var rig = RIG_OF.get(art, art)
		if _rigs.has(rig):
			k *= float(e.def.get("art_scale", 1.0))
			var h1 = _rig_h(rig)
			if _is_boss(e):
				k = _boss_k(k, h1, zoom)
			h = h1 * k
			var lift := 0.0
			if e.def.get("fly", false) or _rigs[rig].has("wings"):
				lift = (6.0 + 22.0 * surf) * k
			var em = _emerge(e) if e.void_born else 1.0
			if em < 1.0:
				# climbing out of the pit: young and small, dark as the void it came from, lit as it comes up into the day
				var q = 1.0 - pow(1.0 - em, 2.2)
				var lit = smoothstep(0.05, 0.85, em)
				col = col * Color(lerp(0.42, 1.0, lit), lerp(0.3, 1.0, lit), lerp(0.58, 1.0, lit), smoothstep(0.0, 0.35, em))
				k *= lerp(0.7, 1.0, q)
				feet.y += (1.0 - q) * h * 0.3
			drawn = _rig(ci, rig, feet - Vector2(0, lift), k, face, tt, moving or em < 0.8, mouth, col, flash, rot)
			feet.y -= lift
	# (the grasshopper and the butterfly have no picture: nothing is drawn)
	if drawn and die < 0.0 and (e.stun_t > 0.0 or e.slow_t > 0.0):
		_draw_silk(ci, e, feet, h, col.a)
	return [e, p, st]


# A boss is never smaller on screen than BOSS_MIN_PX: k grown so that h1 * k * zoom reaches it.
static func _boss_k(k: float, h1: float, zoom: float) -> float:
	return max(k, BOSS_MIN_PX / max(1.0, h1 * zoom))


# Snared (stun_t): the owner's hanging web over it; webbed (slow_t): the dripping web, faint, over its legs.
func _draw_silk(ci: CanvasItem, e, feet: Vector2, h: float, alpha: float) -> void:
	var stun = e.stun_t > 0.0
	var tex = _tx("fx/web_2.png" if stun else "fx/web_3.png")
	if tex == null:
		return
	var w = max(h * (1.15 if stun else 0.7), 22.0)
	var size = Vector2(w, w * tex.get_height() / tex.get_width())
	var c = feet + Vector2(0, -h * (0.5 if stun else 0.25))
	var a = alpha * (0.8 if stun else 0.45) * clamp((e.stun_t if stun else e.slow_t) * 3.0, 0.0, 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(c - size * 0.5, size), false, Color(1, 1, 1, a))


# 0..1 as a Void Maw born of the pit climbs out (its first EMERGE_T sim seconds), 1 for any other.
func _emerge(e) -> float:
	return clamp((colony.sim.time - float(_born.get(e.id, -100.0))) / EMERGE_T, 0.0, 1.0)


# The rival's descendants: our own kit body (worker for its runners, soldier for the rest), tinted by the line's genome with a red cast.
func _draw_kin(ci: CanvasItem, e, feet: Vector2, k: float, face: float, col: Color, flash: bool, rot: float, moving: bool) -> bool:
	var b = _kit.get(KIN_BODY.get(e.cls, "worker_full"))
	if b == null:
		return false
	var size = float(colony.sim.phenotype(e.genome).get("size", 74.0))
	var length = _ant_len(size) * KIN_SIZE.get(e.cls, 1.0) * k
	var s = length / b["length"]
	var bob = sin(_t * 12.0 + e.id) * 0.05 if moving else 0.0
	var tint = col * _kin_tint(e.genome.color)
	if flash:
		tint = _flash(tint)
	ci.draw_set_transform_matrix(Transform2D(rot, feet) * Transform2D(Vector2(face * s, 0), Vector2(0, s * (1.0 + bob)), Vector2.ZERO))
	ci.draw_texture(b["tex"], -b["feet"], tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


static func _kin_tint(c: Color) -> Color:
	if c.v < 0.3:
		c = Color.from_hsv(c.h, c.s, 0.3)
	return Color(c.r / KIT_BASE.r * KIN_CAST.r, c.g / KIT_BASE.g * KIN_CAST.g, c.b / KIT_BASE.b * KIN_CAST.b)


static func _ant_len(size: float) -> float:
	var t = LEN_PER_SIZE * size + LEN_BASE
	return LEN_K * t * min(1.0, 310.0 / (t + 120.0))


static func _behind(g, x: int, y: int, z: int) -> float:
	return 1.0 if z == 1 and g.is_solid(x, y, 0) else 0.0


# A raider that was on screen last frame and is gone now with a fresh hit burst where it stood was killed: it keels over (_draw_dying).
func _note_deaths(seen: Dictionary) -> void:
	var sim = colony.sim
	for id in _seen:
		if seen.has(id):
			continue
		var it = _seen[id]
		var e = it[0]
		if sim.enemies.has(e):
			continue
		var at = sim.enemy_pos(e) + Vector2(0, -12)
		for f in sim.fx:
			if f["kind"] == "burst" and f["t"] < 0.35 and f["pos"].distance_squared_to(at) < 64.0:
				_dying.append({"it": it, "t": 0.0, "life": DIE_T_BOSS if _is_boss(e) else DIE_T})
				break
	_seen = seen


func _draw_dying(far: float, zoom: float) -> void:
	var i = _dying.size() - 1
	while i >= 0:
		var d = _dying[i]
		d["t"] += _dt
		if d["t"] >= d["life"]:
			_dying.remove_at(i)
		else:
			var it = d["it"]
			if colony.view_rect(MARGIN).has_point(it[1]):
				_draw_enemy(self, it[0], it[1], it[2], far, zoom, d["t"] / d["life"])
		i -= 1


# ---------------------------------------------------------------- the bird
# Ground y (world px) at world x, smoothed over a few columns as surface_view.gd does (a hole does not pull it down, the mound lifts it).
func _ground(px: float, smooth: int = 2) -> float:
	var g = colony.grid
	var cx = px / C - 0.5
	var c0 = int(floor(cx))
	var f = cx - c0
	var a := 0.0
	var b := 0.0
	for d in range(-smooth, smooth + 1):
		a += min(g.surf_y(c0 + d), g.base_y(c0 + d))
		b += min(g.surf_y(c0 + 1 + d), g.base_y(c0 + 1 + d))
	return lerp(a, b, f) / (2 * smooth + 1) * C


func _step_bird() -> void:
	var sim = colony.sim
	var b = sim.bird
	var f = sim.bird_fall
	if f != null and not _had_fall:
		_fall_origin = _bird_last if (_bird_ok and abs(_bird_px - float(f["x"])) < 3.0) else null
	_had_fall = f != null
	if f == null:
		_fall_origin = null
	if b != null:
		_hover = lerp(_hover, 0.0 if abs(float(b["x"]) - _bird_px) > 0.05 else 1.0, clamp(_dt * 3.0, 0.0, 1.0))
		_bird_px = float(b["x"])
		_bird_last = _bird_pose(b)[0]
		_bird_ok = true
	elif f == null:
		_bird_ok = false


# Where the live bird is: [position (where the neck meets the shoulders), facing].
func _bird_pose(b: Dictionary) -> Array:
	var ps = Band.persp(BIRD_LANE)
	var gy = Band.lane_y(_ground((float(b["x"]) + 0.5) * C), BIRD_LANE)
	var pos = Vector2((float(b["x"]) + 0.5) * C, gy - (34.0 + 230.0 * float(b["alt"])) * ps)
	pos += Vector2(sin(_t * 1.1) * 60.0 * ps, sin(_t * 2.3) * 9.0 * ps) * _hover       # circling over its prey, never frozen
	var face = int(b["face"]) if _hover < 0.3 else (1 if cos(_t * 1.1) >= 0.0 else -1)
	return [pos, face]


# The bird's drawing scale: its lane's perspective, but never under BOSS_MIN_PX * 1.5 across on screen (BIRD_SPAN art px wide).
func _bird_scale(zoom: float) -> float:
	return max(BIRD_K * 0.95 * Band.persp(BIRD_LANE), BOSS_MIN_PX * 1.5 / (BIRD_SPAN * max(0.05, zoom)))


func _draw_bird(b: Dictionary, zoom: float) -> void:
	var bp = _bird_pose(b)
	var pos: Vector2 = bp[0]
	if not colony.view_rect(400.0).has_point(pos):
		return
	var alt = float(b["alt"])
	var fold = clamp(float(b["dive"]) * 1.2 + (1.0 - alt) * 0.45, 0.0, 1.0)
	var hit = float(b.get("hit", 0.0))
	var hurt = false
	if hit > 0.0:
		hurt = fmod(_t, 0.22) < 0.1                  # winged ants are on it: it flinches and blinks red
		pos += Vector2(sin(_t * 83.0), cos(_t * 71.0)) * 3.0 * clamp(hit / 0.3, 0.0, 1.0)
	var fade = clamp(float(b["t"]) / 2.0, 0.0, 1.0)
	var s = _bird_scale(zoom)
	pos.y -= (s - BIRD_K * 0.95 * Band.persp(BIRD_LANE)) * BIRD_DROP      # grown to stay readable: lifted so its talons stay off the ground
	_bird(self, pos, s, _t, int(bp[1]), fold, fade, hurt)


func _bird_tex() -> Array:
	var out = [_tx("bird_head.png"), _tx("bird_wing_b.png"), _tx("bird_wing_a.png"), _tx("bird_claw_1.png"), _tx("bird_claw_2.png")]
	return [] if out.has(null) else out


# The live bird from five pieces: far foot, far wing, near wing with the shoulder, head, near foot. `fold` tucks the wings for a stoop.
func _bird(ci: CanvasItem, pos: Vector2, s: float, t: float, facing: int, fold: float, alpha: float, hurt: bool) -> void:
	var tx = _bird_tex()
	if tx.is_empty():
		return
	var th: Texture2D = tx[0]
	var twb: Texture2D = tx[1]
	var twa: Texture2D = tx[2]
	var tc1: Texture2D = tx[3]
	var tc2: Texture2D = tx[4]
	var base = Transform2D(Vector2(facing * s, 0), Vector2(0, s), pos)
	var tint = colony.day.tint
	var mod = Color(tint.r, tint.g, tint.b, alpha)
	var dim = Color(0.72 * tint.r, 0.72 * tint.g, 0.8 * tint.b, alpha)
	if hurt:
		mod = Color(1, 0.6, 0.6, alpha)
	var flap = 0.5 + 0.5 * sin(t * 9.0)
	var ang_b = lerp(-0.95 * flap, 0.55, fold)
	var ang_a = lerp(-0.95 * (0.5 + 0.5 * sin(t * 9.0 - 0.7)), 0.45, fold)
	var wb = twb.get_size()
	var wa = twa.get_size()
	var org = Vector2(wb.x * 0.88, wb.y * 0.6)
	var hinge_b = Vector2(wb.x * 0.72, wb.y * 0.62) - org
	var hinge_a_src = Vector2(wa.x * 0.8, wa.y * 0.75)
	var pos_a = hinge_b + Vector2(-8, -10) - hinge_a_src
	var bob = sin(t * 9.0) * 5.0
	var up = Vector2(0, -bob)
	var c2 = Vector2(-150, -10)
	_put(ci, base, tc2, c2 + Vector2(0, bob * 0.3), c2 + Vector2(tc2.get_size().x * 0.4, 0), -0.6 * fold, dim)
	_put(ci, base, twa, pos_a + up, hinge_b + Vector2(-8, -10) + up, ang_a, dim)
	_put(ci, base, twb, -org + up, hinge_b + up, ang_b, mod)
	ci.draw_set_transform_matrix(base * Transform2D(Vector2(0.9, 0), Vector2(0, 0.9), Vector2(-36, -157) + up))
	ci.draw_texture(th, Vector2.ZERO, mod)
	var c1 = Vector2(-105, -30)
	_put(ci, base, tc1, c1 + Vector2(0, bob * 0.3 + 8.0 * fold), c1 + Vector2(tc1.get_size().x * 0.4, 0), -0.6 * fold, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# The foot of a carcass pile at column x: the ground five columns about it, at the pile lane (the falling bird lands exactly there).
func _carcass_base(x: int) -> Vector2:
	var g = colony.grid
	var acc := 0.0
	for k in range(-2, 3):
		acc += g.surf_y(x + k)
	return Vector2((float(x) + 0.5) * C, Band.lane_y(acc / 5.0 * C, PILE_LANE))


static func _carcass_pivot(base: Vector2, sc: float, spin: float) -> Vector2:
	return base + Vector2(0.0, -sc * (DEAD_REACH + DEAD_REACH_K * 0.15 * spin - DEAD_SINK))


# The shot-down bird tumbling out of the sky: from where it was last drawn to its carcass's spot and angle, faster and faster.
func _draw_bird_fall(f: Dictionary, zoom: float) -> void:
	var g = colony.grid
	var u = clamp(float(f["t"]) / BIRD_FALL_T, 0.0, 1.0)
	var face = int(f["face"])
	var spin = float(f["spin"])
	var landx = int(clamp(float(f["x"]), g.sim_l() + 3, g.sim_r() - 3))
	var ps = Band.persp(BIRD_LANE)
	var sc = BIRD_K * 0.95 * ps
	var base = _carcass_base(landx)
	var origin = _fall_origin if _fall_origin != null else Vector2((float(f["x"]) + 0.5) * C, base.y - (34.0 + 230.0 * float(f["alt"])) * ps)
	var p0 = origin + Vector2(face * sc * DEAD_PIVOT.x, sc * DEAD_PIVOT.y)
	var p1 = _carcass_pivot(base, sc, spin)
	var pos = Vector2(lerp(p0.x, p1.x, smoothstep(0.0, 1.0, u)), lerp(p0.y, p1.y, u * u))
	if not colony.view_rect(400.0).has_point(pos):
		return
	var total = DEAD_TILT + 0.15 * spin
	if spin < 0.0:
		total -= TAU
	var ang = face * total * pow(u, 1.2) + sin(u * 11.0 + spin * 3.0) * 0.12 * (1.0 - u)
	var limp = smoothstep(0.0, 0.3, u)
	var fold = clamp((1.0 - float(f["alt"])) * 0.45, 0.0, 1.0)
	_dead_bird(self, pos, sc, face, ang, limp, fold * (1.0 - limp), _t, 1.0, colony.day.tint, [], 0.3 * (1.0 - u))


# The bird from its five pieces, dead: wings fallen open and limp, the head dropped. Turned by `ang` about the middle of its body at `piv`.
# `pa`: five alphas (far foot, far wing, near wing, head, near foot) for a carcass coming apart; `outer` slumps it toward the ground.
func _dead_bird(ci: CanvasItem, piv: Vector2, s: float, face: int, ang: float, limp: float, fold: float, flutter: float, alpha: float, tint: Color, pa: Array, flop: float = 0.0, outer = null) -> void:
	var tx = _bird_tex()
	if tx.is_empty():
		return
	var th: Texture2D = tx[0]
	var twb: Texture2D = tx[1]
	var twa: Texture2D = tx[2]
	var tc1: Texture2D = tx[3]
	var tc2: Texture2D = tx[4]
	var base = Transform2D(ang, piv) * Transform2D(Vector2(face * s, 0), Vector2(0, s), Vector2.ZERO) * Transform2D(0.0, -DEAD_PIVOT)
	if outer != null:
		base = outer * base
	var al = pa if pa.size() == 5 else [1.0, 1.0, 1.0, 1.0, 1.0]
	var mod = Color(tint.r, tint.g, tint.b, alpha)
	var dim = Color(tint.r * 0.72, tint.g * 0.72, tint.b * 0.8, alpha)
	var wb = twb.get_size()
	var wa = twa.get_size()
	var org = Vector2(wb.x * 0.88, wb.y * 0.6)
	var hinge_b = Vector2(wb.x * 0.72, wb.y * 0.62) - org
	var hinge_a_src = Vector2(wa.x * 0.8, wa.y * 0.75)
	var pos_a = hinge_b + Vector2(-8, -10) - hinge_a_src
	var beat = 0.5 + 0.5 * sin(flutter * 9.0)
	var stir_b = sin(flutter * 7.0) * flop * limp
	var stir_a = sin(flutter * 7.0 + 1.9) * flop * limp
	var ang_b = lerp(lerp(-0.95 * beat, 0.55, fold), WING_B_DEAD + stir_b, limp)
	var ang_a = lerp(lerp(-0.95 * (0.5 + 0.5 * sin(flutter * 9.0 - 0.7)), 0.45, fold), WING_A_DEAD + stir_a, limp)
	var c2 = Vector2(-150, -10) + Vector2(-15, 5) * limp
	var c1 = Vector2(-105, -30) + Vector2(-15, 5) * limp
	if al[0] > 0.01:
		_put(ci, base, tc2, c2, c2 + Vector2(tc2.get_size().x * 0.4, 0), lerp(0.0, -0.5, limp), Color(dim.r, dim.g, dim.b, alpha * al[0]))
	if al[1] > 0.01:
		_put(ci, base, twa, pos_a, hinge_b + Vector2(-8, -10), ang_a, Color(dim.r, dim.g, dim.b, alpha * al[1]))
	if al[2] > 0.01:
		_put(ci, base, twb, -org, hinge_b, ang_b, Color(mod.r, mod.g, mod.b, alpha * al[2]))
	if al[4] > 0.01:
		_put(ci, base, tc1, c1 + Vector2(0, 8.0 * limp), c1 + Vector2(tc1.get_size().x * 0.4, 0), lerp(0.0, -0.5, limp), Color(mod.r, mod.g, mod.b, alpha * al[4]))
	if al[3] > 0.01:
		var neck = Vector2(60, 190)
		var hp = Vector2(-36, -157)
		ci.draw_set_transform_matrix(base * Transform2D(0.0, hp + neck * 0.9) * Transform2D(lerp(0.0, HEAD_DEAD, limp), Vector2.ZERO) * Transform2D(Vector2(0.9, 0), Vector2(0, 0.9), -neck * 0.9))
		ci.draw_texture(th, Vector2.ZERO, Color(mod.r, mod.g, mod.b, alpha * al[3]))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- on the ground and in the trees (the back canvas, under the ants)
func _draw_back() -> void:
	var sim = colony.sim
	var vr = colony.view_rect(MARGIN)
	var x0 = int(floor(vr.position.x / C))
	var x1 = int(ceil(vr.end.x / C))
	_draw_hives(sim, x0, x1, vr)
	if sim.rival != null:
		_draw_rival(sim.rival, vr)
	for p in sim.piles:
		var px = (float(p["x"]) + 0.5) * C
		if px > vr.position.x and px < vr.end.x:
			_draw_pile(p)
	_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# How much of something on the surface in `lane` to draw (band.gd lane_alpha): 0 = cut by the depth zoom, skip it.
func _la(lane: float, tall: bool = false) -> float:
	if not _lane_alpha.is_valid():
		return 1.0
	return float(_lane_alpha.call(lane, tall)) if _alpha_tall else float(_lane_alpha.call(lane))


func _lane_tint(lane: float) -> Color:
	var c = HAZE.lerp(Color.WHITE, clamp(lane, 0.0, 1.0))
	c.a = 1.0
	return c * colony.day.tint


# ---- beehives (core/hives.gd): hung under the canopy of their tree (placed as surface_view.gd places the tree), swinging a little on the
# branch; whole, dripping, then torn open as the ants take their honey; fallen, broken at the tree's foot until a new one grows. By day a
# few bees circle a hanging hive.
func _draw_hives(sim, x0: int, x1: int, vr: Rect2) -> void:
	if sim.hives.is_empty():
		return
	for f in WF.in_range(sim.seed_base, x0 - 60, x1 + 60, int(colony.grid.entrance.x)):
		if f["kind"] != "tree" or not sim.hives.has(f["id"]):
			continue
		var h = sim.hives[f["id"]]
		var tr = _tree_rect(f)
		if tr.is_empty():
			continue
		var box: Rect2 = tr["canopy"]
		if box.end.x < vr.position.x or box.position.x > vr.end.x or box.position.y > vr.end.y or tr["foot"].y + 60.0 < vr.position.y:
			continue
		var sd = float(h["seed"])
		var lane = float(f["lane"])
		var mod = _lane_tint(lane)
		mod.a = _la(lane, true)
		if mod.a <= 0.01:
			continue
		var hh = clamp(tr["size"].y * 0.09, 50.0, 130.0)     # bigger than an ant, small against a giant tree
		var hang = Vector2(box.position.x + box.size.x * (0.3 + 0.4 * Hives.hash1(sd + 5.1)), box.end.y - box.size.y * 0.18)
		var st = Hives.stage(h)
		if st < 3:
			var tex = _tx("hive/%s.png" % HANGING[st])
			if tex == null:
				continue
			var w = hh * tex.get_width() / float(tex.get_height())
			_back.draw_set_transform(hang, sin(_t * 1.3 + sd) * 0.035, Vector2.ONE)
			_back.draw_texture_rect(tex, Rect2(Vector2(-w * 0.5, -hh * 0.12), Vector2(w, hh)), false, mod)
			var day = colony.day
			if day.leaf > 0.3 and day.night < 0.5 and sim.rain < 0.5:
				_hive_bees(hang + Vector2(0.0, hh * 0.45), w, hh, sd, mod)
		else:
			var tf = _tx("hive/hive_fallen.png")
			if tf == null:
				continue
			mod.a = _la(lane)           # lying on the ground now, not hanging in the tree
			var fw = hh * 1.5
			var fh = fw * tf.get_height() / float(tf.get_width())
			var by: float = tr["foot"].y
			_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_back.draw_texture_rect(tf, Rect2(Vector2(hang.x - fw * 0.5, by - fh * 0.82), Vector2(fw, fh)), false, mod)
	_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A few bees circling the hive on loops of their own, facing the way they fly.
func _hive_bees(c: Vector2, w: float, hh: float, sd: float, mod: Color) -> void:
	var s = hh / 70.0 * 0.32
	for k in HIVE_BEES:
		var tex = _tx("hive/bee_%d.png" % int(Hives.hash1(sd + k * 3.7) * 7.99))
		if tex == null:
			continue
		var a = _t * (1.5 + 0.35 * k) + k * 2.1 + sd
		var p = c + Vector2(cos(a) * w * (0.75 + 0.2 * k), sin(a * 1.3) * hh * 0.4 + sin(_t * 31.0 + k) * 1.2)
		var fl = 1.0 if -sin(a) >= 0.0 else -1.0
		var size = tex.get_size() * s
		_back.draw_set_transform(p, 0.0, Vector2(-fl, 1.0))
		_back.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, mod)


# Where surface_view.gd draws a tree landmark: {"size", "foot" (world point on the ground), "canopy" (world rect of the leaves)}.
func _tree_rect(f: Dictionary) -> Dictionary:
	var sd: float = f["seed"]
	var pick = _tree_pick[_tree_pick.size() - 1]
	var r = Hives.hash1(sd + 99.0)
	for p in _tree_pick:
		if r < p[0]:
			pick = p
			break
	var def = _trees.get(pick[1])
	if def == null:
		return {}
	var tw = float(def.get("w", 1.0))
	var th = float(def.get("h", 1.0))
	var lane: float = f["lane"]
	var sc = Band.persp(lane)
	var size: Vector2
	if pick[1] == "log":
		size = Vector2(f["w"] * sc * 5.5, f["w"] * sc * 5.5 * th / tw)
	else:
		var hgt = f["h"] * sc * pick[2]
		size = Vector2(hgt * tw / th, hgt)
	var px = (f["x"] + 0.5) * C
	var base = Vector2(px, Band.lane_y(_ground(px), lane))
	var foot = def.get("foot", [0.5, 1.0])
	var flip = Hives.hash1(sd + 3.0) > 0.5
	var pos = base - Vector2((1.0 - foot[0] if flip else foot[0]) * size.x, foot[1] * size.y)
	var cb = def.get("canopy", [0.1, 0.1, 0.9, 0.7])
	var cx0 = 1.0 - float(cb[2]) if flip else float(cb[0])
	var cx1 = 1.0 - float(cb[0]) if flip else float(cb[2])
	return {"size": size, "foot": base, "canopy": Rect2(pos + Vector2(cx0 * size.x, float(cb[1]) * size.y), Vector2((cx1 - cx0) * size.x, (float(cb[3]) - float(cb[1])) * size.y))}


# ---- the rival colony's mound (the owner's anthill, darker and redder than ours), and its idle ants going in and out round it
func _draw_rival(r, vr: Rect2) -> void:
	var px = (float(r.x) + 0.5) * C
	var ps = Band.persp(RIVAL_LANE)
	var W = RIVAL_W * ps
	if px + W < vr.position.x or px - W > vr.end.x:
		return
	var gy = Band.lane_y(_ground(px, 3), RIVAL_LANE)
	if gy - W > vr.end.y or gy + 60.0 < vr.position.y:
		return
	var alive = r.alive()
	var mounds = Art.manifest("anthill/anthill_manifest.json").get("mounds", [])
	var pick = null
	for m in mounds:
		if str(m.get("name", "")) == ("mound_large" if alive else "mound_small"):
			pick = m
	if pick != null:
		var tex = _tx(str(pick["file"]))
		if tex != null:
			var w = W * (1.0 if alive else 0.7)
			var size = Vector2(w, w * tex.get_height() / tex.get_width())
			var col = _lane_tint(RIVAL_LANE) * RIVAL_TINT * (1.0 if alive else 0.72)
			col.a = _la(RIVAL_LANE)
			if r.hit_t > 0.0:
				col = _flash(col)
			_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_back.draw_texture_rect(tex, Rect2(Vector2(px - w * 0.5, gy - size.y * 0.9), size), false, col)
	var n = RIVAL_IDLE if alive else 2
	for k in n:
		var hk = Hives.hash1(k * 11.0 + 0.5)
		var ph = _t * (0.28 + 0.12 * hk) + k * 1.3
		var ax = px + sin(ph) * W * (0.55 + 0.25 * Hives.hash1(k * 12.0 + 0.5))
		var al = 0.25 + 0.7 * Hives.hash1(k * 13.0 + 0.5)
		var ay = Band.lane_y(_ground(ax), al)
		var face = 1.0 if cos(ph) >= 0.0 else -1.0
		var col = _lane_tint(al)
		col.a = _la(al)
		if col.a <= 0.01:
			continue
		if r.genome != null:
			var b = _kit.get("worker_full")
			if b != null:
				var s = _ant_len(float(colony.sim.phenotype(r.genome).get("size", 74.0))) * Band.persp(al) / b["length"]
				_back.draw_set_transform(Vector2(ax, ay), 0.0, Vector2(face * s, s))
				_back.draw_texture(b["tex"], -b["feet"], col * _kin_tint(r.genome.color))
		else:
			_rig(_back, "redant_small", Vector2(ax, ay), Band.persp(al), face, _t + k, true, 0.2, col, false)
	_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- food on the meadow: a heap of the owner's food pictures (more the more there is), honeycomb on a honey puddle under a hive, apples
# under a fruit tree, a big heap at a cave hoard, and a shot-down bird lying on its back as it rots away.
func _draw_pile(p: Dictionary) -> void:
	var x = int(p["x"])
	var kind = str(p.get("kind", ""))
	if kind == "carcass":
		_draw_carcass(p)
		return
	var px = (float(x) + 0.5) * C
	var base = Vector2(px, Band.lane_y(_ground(px), PILE_LANE))
	if not colony.view_rect(80.0).has_point(base):
		return
	var mod = _lane_tint(PILE_LANE)
	mod.a = _la(PILE_LANE)
	if mod.a <= 0.01:
		return
	var ps = Band.persp(PILE_LANE)
	var share = clamp(float(p["amount"]) / max(1.0, float(p["max"])), 0.0, 1.0)
	if float(p["amount"]) <= 0.0:
		return
	_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if kind == "honey":
		var big = p.get("fallen", false)
		var pud = _tx("hive/puddle_a.png" if big else "hive/puddle_b.png")
		if pud != null:
			var pw = (110.0 if big else 46.0) * (0.6 + 0.4 * share) * ps
			var ph = pw * pud.get_height() / float(pud.get_width())
			_back.draw_texture_rect(pud, Rect2(base + Vector2(-pw * 0.5, -ph * 0.6), Vector2(pw, ph)), false, mod)
		var nh = int(clamp(ceil(share * (7.0 if big else 4.0)), 1, 7))
		for i in nh:
			var t = _tx("hive/%s.png" % HONEY_PIECES[(i + x) % HONEY_PIECES.size()])
			if t == null:
				continue
			var w = (22.0 if big else 16.0) * (0.8 + 0.4 * Hives.hash1(x * 1.7 + i)) * ps
			var h = w * t.get_height() / float(t.get_width())
			var off = Vector2((i - (nh - 1) * 0.5) * w * 0.8, -(i % 2) * 6.0 * ps - 4.0 * ps)
			_back.draw_texture_rect(t, Rect2(base + off - Vector2(w * 0.5, h), Vector2(w, h)), false, mod)
		return
	if _foods.is_empty():
		return
	var pics := []
	if kind == "fruit":
		for f in _foods:
			if f["name"] == "apple":
				pics.append(f)
	if pics.is_empty():
		for f in _foods:
			if f["name"] != "apple":
				pics.append(f)
	var n = int(clamp(ceil(float(p["amount"]) / (10.0 if kind == "fruit" else 7.0)), 1, 5 if kind == "fruit" else PILE_ROWS.size()))
	if kind == "jackpot":
		n = PILE_ROWS.size()
	var big_k = 1.35 if kind == "jackpot" else 1.0
	for i in n:
		var o = PILE_ROWS[i]
		var f = pics[(x * 7 + i * 3) % pics.size()]
		var size: Vector2 = f["size"] * ps * big_k
		var c = base + Vector2(o[0] * 11.0 * big_k * ps, -o[1] * 8.0 * big_k * ps)
		var flip = (x + i) % 2 == 1
		_back.draw_set_transform(c, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
		_back.draw_texture_rect(f["tex"], Rect2(Vector2(-size.x * 0.5, -size.y), size), false, mod)
	_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A shot-down bird lying on its back, in exactly the pose it landed in. It rots away as pile["rot"] runs 1 -> 0: it slumps toward the ground
# and shrinks, greys and fades, losing the parts that stick up first (feet, far wing, near wing) and the body on the grass last.
func _draw_carcass(p: Dictionary) -> void:
	var rot = clamp(float(p.get("rot", float(p["amount"]) / max(1.0, float(p["max"])))), 0.0, 1.0)
	if rot < 0.004:
		return
	var e = 1.0 - rot
	var base = _carcass_base(int(p["x"]))
	if not colony.view_rect(240.0).has_point(base):
		return
	var ps = Band.persp(BIRD_LANE)
	var face = int(p.get("face", 1))
	var spin = float(p.get("spin", 0.0))
	var k = 0.72 + 0.28 * rot
	var sc = BIRD_K * 0.95 * ps * k
	var flat = lerp(0.42, 1.0, smoothstep(0.0, 1.0, rot))
	var slump = Transform2D(Vector2(1.0 + 0.12 * (1.0 - flat), 0.0), Vector2(0.0, flat), base) * Transform2D(0.0, -base)
	var alpha = (0.4 + 0.6 * pow(rot, 0.6)) * _la(PILE_LANE)
	var tint = colony.day.tint * Color.WHITE.lerp(Color(0.62, 0.72, 0.58), clamp(e * 0.9, 0.0, 0.8))
	var pa = [smoothstep(0.55, 0.75, rot), smoothstep(0.35, 0.6, rot), smoothstep(0.1, 0.35, rot), smoothstep(0.0, 0.16, rot), smoothstep(0.45, 0.65, rot)]
	var piv = _carcass_pivot(base, sc, spin)
	_dead_bird(_back, piv, sc, face, face * (DEAD_TILT + 0.15 * spin), 1.0, 0.0, 0.0, alpha, tint, pa, 0.0, slump)
