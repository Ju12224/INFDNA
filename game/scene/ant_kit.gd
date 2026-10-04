extends Node
# Ants assembled from the owner's part kit (art/antkit, listed in antkit_manifest.json; all pieces face right), the way the Godot 3
# view did it (kit_painter.gd + sprite_baker.gd): the genome picks the pieces and their sizes, they are laid out from the tail to the
# head, and the legs walk an alternating tripod. Only the drawn pieces go on screen (tinted, scaled, rotated); what the kit has no
# picture for (tentacles, claw arms, fins, organs, glow, the crown) is left out.
#
# What the genome picks (as kit_painter.gd):
#   head      big-headed (major) / armoured / spiked heads -> armoured head, many eyes -> beaked big-eyed head (+ compound eye and
#             ocelli), no jaw or a tentacle jaw -> the snout; else the round head. Heads come antenna-less ("*_bare").
#   mandibles by jaw form and major / venom jaws / head spikes: hook, sickle, crusher, fang, jagged, claw; a near and a far jaw
#   antennae  by form (elbowed, clubbed, feathered, whip, forked), length by the antenna gene; they sway as it walks
#   thorax    one per middle segment: tufted when hairy, lobed when smooth, small / big by its size, spiked with spikes
#   abdomen   eggs (the crowned queen, very replete), round (replete), spiked, slim (wings, jumping or stilt legs, a thin gaster), plain
#   legs      plain; digging forelegs spiny, jumping hind legs flared, raptorial forelegs armoured and held up, furry on hairy lines
#   wings folded over the gaster, sting, spines / horns for spikes, plates for armour, fur tufts for hair
# Castes on top of the genome: soldiers get a bigger head and heavier jaws (major + SOLDIER_MAJOR), diggers spiny digging forelegs.
#
# Each look (a strain's body plan for one caste, sizes rounded so a drifting line reuses its picture) is baked ONCE into one texture:
# FRAMES walk frames and a standing pose side by side, and for winged looks a second row with the wings alone (drawn barely tinted).
# Pieces are baked in a neutral grey, so the strain's colour is the modulate the view draws with. The bake is premultiplied alpha
# (what a transparent viewport holds): the view draws it with a premultiplied-alpha material. One bake per frame at most; until a
# look is baked, look() returns null and the view draws its whole-body picture.

const Art = preload("res://scene/art.gd")

const MANIFEST = "antkit_manifest.json"
const FRAMES = 6                  # walk-cycle frames (the old baker's count)
const CELLS = FRAMES + 1          # + the standing pose
const STAND = FRAMES              # cell of the standing pose
const BAKE_LEN = 128.0            # bake px from tail to nose: crisp up to zoom 5 or so
const RING = 0.018                # extra ink round every piece, in body lengths (the old 3.4 painter units)
const RING_N = 8
const INK = Color(0.035, 0.03, 0.045)
const PAD = 6                     # bake px of empty border round every cell (mipmaps of neighbours never bleed in)
const MAX_LOOKS = 180             # baked looks kept; the least recently drawn go first
const SOLDIER_MAJOR = 0.35        # a soldier's head and jaws: as a line this much more big-headed
const FAR_TINT = Color(0.5, 0.5, 0.5)      # far legs, jaw and antenna (kit_painter's tint.darkened(0.5))
const LEG_TINT = Color(0.88, 0.88, 0.88)   # near legs (tint.darkened(0.12))
const R_STEP = 2.0                # segment sizes are rounded to this (after scaling the plan to an ordinary ant) ...
const LEN_STEP = 6.0              # ... leg lengths to this, antenna to ANT_STEP
const ANT_STEP = 8.0

# role -> candidate pieces; the first the manifest lists is used
const ROLES = {
	"head": ["head_round_bare", "head_round"],
	"head_eyes": ["head_beak_bare", "head_beak"],
	"head_armored": ["head_armored_bare", "head_armored"],
	"head_snout": ["head_snout_bare", "head_snout"],
	"thorax": ["thorax_tufted_1", "thorax_lobed_1"],
	"thorax_big": ["thorax_tufted_3", "thorax_tufted_2", "thorax_tufted_1"],
	"thorax_smooth": ["thorax_lobed_2", "thorax_lobed_1", "thorax_tufted_1"],
	"thorax_small": ["thorax_lobed_4", "thorax_lobed_3", "thorax_lobed_1"],
	"thorax_spiked": ["thorax_spiked", "thorax_tufted_2"],
	"abdomen": ["abdomen_plain"],
	"abdomen_round": ["abdomen_round", "abdomen_plain"],
	"abdomen_eggs": ["abdomen_eggs", "abdomen_round"],
	"abdomen_spiked": ["abdomen_spiked", "abdomen_plain"],
	"abdomen_slim": ["abdomen_slim", "abdomen_plain"],
	"node": ["abdomen_round", "abdomen_plain"],
	"leg": ["leg_plain"],
	"leg_dig": ["leg_spiny", "leg_plain"],
	"leg_jump": ["leg_flared", "leg_plain"],
	"leg_raptor": ["leg_armored", "leg_plain"],
	"leg_furry": ["leg_furry", "leg_plain"],
	"leg_stilt": ["leg_stilt", "leg_plain"],
	"ant_elbow": ["antenna_plain_l", "antenna_elbow"],
	"ant_elbow_far": ["antenna_plain_r", "antenna_plain_l"],
	"ant_club": ["antenna_club_l", "antenna_bigclub"],
	"ant_club_far": ["antenna_club_r", "antenna_club_l"],
	"ant_feather": ["antenna_feather_l", "antenna_fern"],
	"ant_feather_far": ["antenna_feather_r", "antenna_feather_l"],
	"ant_whip": ["antenna_whip", "antenna_plain_l"],
	"ant_whip_far": ["antenna_whip", "antenna_plain_r"],
	"ant_fork": ["antenna_segclub", "antenna_plain_l"],
	"ant_fork_far": ["antenna_segclub", "antenna_plain_r"],
	"mand_hook": ["mandible_hook_r"],
	"mand_hook_far": ["mandible_hook_l"],
	"mand_crusher": ["mandible_crusher_r", "mandible_hook_r"],
	"mand_crusher_far": ["mandible_crusher_l", "mandible_hook_l"],
	"mand_fang": ["mandible_fang_r", "mandible_hook_r"],
	"mand_fang_far": ["mandible_fang_l", "mandible_hook_l"],
	"mand_jagged": ["mandible_jagged_r", "mandible_hook_r"],
	"mand_jagged_far": ["mandible_jagged_l", "mandible_hook_l"],
	"mand_sickle": ["mandible_sickle_r", "mandible_hook_r"],
	"mand_sickle_far": ["mandible_sickle_l", "mandible_hook_l"],
	"mand_claw": ["mandible_claw_r", "mandible_crusher_r"],
	"mand_claw_far": ["mandible_claw_l", "mandible_crusher_l"],
	"mand_small": ["mandible_small_r", "mandible_hook_r"],
	"mand_small_far": ["mandible_small_l", "mandible_hook_l"],
	"wing_fore": ["wing_veined_fore"],
	"wing_hind": ["wing_veined_hind"],
	"sting": ["sting"],
	"spine_trio": ["spine_trio"],
	"spine_crest": ["spine_crest", "spine_trio"],
	"spine_crest_tall": ["spine_crest_tall", "spine_crest"],
	"spine_cluster": ["spine_cluster", "spine_trio"],
	"spine_knob": ["spine_knob", "spine_trio"],
	"spine_hook": ["spine_hook", "horn_small"],
	"spine_ridge": ["spine_ridge"],
	"spine_backbone": ["spine_backbone", "spine_ridge"],
	"horn_long": ["horn_long"],
	"horn_small": ["horn_small"],
	"horn_curl": ["horn_curl"],
	"plate_1": ["plate_lobes"],
	"plate_2": ["plate_fringed"],
	"plate_3": ["plate_spiked"],
	"fur": ["fur_tuft"],
	"fur_small": ["fur_tuft_small"],
	"eye_compound": ["eye_compound"],
	"eye_glossy": ["eye_glossy"],
}

# Head landmarks in the owner's SHEET pixels (converted with each piece's src box and scale, so the antenna-less re-cut of a drawing
# keeps them): the head capsule ("dome"), antenna socket, jaw hinge, eye and crown. Unknown heads use HEAD_RIG_N (piece fractions).
const HEAD_RIG = {
	"head_round": {"dome": [25, 395, 340, 650], "sock": [200, 440], "jaw": [272, 602], "eye": [215, 510], "top": [140, 400]},
	"head_snout": {"dome": [385, 385, 690, 610], "sock": [545, 440], "jaw": [652, 640], "eye": [530, 500], "top": [500, 392]},
	"head_beak": {"dome": [720, 380, 1040, 680], "sock": [920, 440], "jaw": [990, 610], "eye": [880, 500], "top": [860, 388]},
	"head_armored": {"dome": [1090, 370, 1420, 700], "sock": [1245, 440], "jaw": [1322, 640], "eye": [1290, 520], "top": [1210, 385]},
}
const HEAD_RIG_N = {"dome": [0.03, 0.4, 0.85, 0.98], "sock": [0.5, 0.45], "jaw": [0.78, 0.82], "eye": [0.55, 0.62], "top": [0.4, 0.42]}
# Thorax landmarks, fractions of the piece (all the kit's thoraxes share one layout: tufted rear, pronotum lobe in front, coxae below)
const THX_RIG = {"core": [0.52, 0.42], "waist": [0.1, 0.5], "neck": [0.9, 0.36], "top": [0.5, 0.08],
	"hips": [[0.3, 0.72], [0.55, 0.74], [0.8, 0.72]]}

# draw layers, back to front
const K_FAR = 0       # far legs, antenna, jaw
const K_BODY = 1      # waist, gaster, thoraxes, head and what sits on them
const K_LEG = 2       # near legs (their tops overlap the coxae, as in the owner's drawings)
const K_NEAR = 3      # near jaw and antenna, raptorial forelegs
const K_WING = 4      # baked into the second row

var ok := false               # the kit is there and this machine can render a bake (not --headless)
var _pieces := {}             # manifest pieces
var _role := {}               # role -> piece name ("" = none)
var _info := {}               # piece name -> {tex, size, pivot, far, low, scale, src, pad, bare, name}
var _looks := {}              # look key -> look (see _bake); "tex" is null until baked
var _key_of := {}             # genome uid * 4 + caste -> [look key, world length (px, before the caste scale), spec]
var _queue := []              # look keys waiting for a bake
var _busy := false
var _frame := 0
var bake_us := 0              # the last bake's cost on this thread (layout + readback), and the worst so far
var bake_max_us := 0
var _L := []                  # _build's output: per layer, [piece info, Transform2D (painter units), Color, ink]


func _ready() -> void:
	_pieces = Art.manifest(MANIFEST).get("pieces", {})
	ok = not _pieces.is_empty() and DisplayServer.get_name() != "headless"
	for r in ["head", "thorax", "abdomen", "leg"]:
		if _rolename(r) == "":
			ok = false


func reset() -> void:
	_key_of = {}


# The baked look of this genome and caste, or null while it waits for its bake (then the view draws something else). A look is
# {tex, cell (Vector2, px of one frame), feet (where the feet are in a cell), len (BAKE_LEN), cycle (ground covered by one walk
# cycle, in body lengths), wings (true: row 2 holds the wings), jaw (the jaws, from the feet), mid (the body's middle, from the feet)}.
func look(gn, caste: int):
	if not ok:
		return null
	var e = _entry(gn, caste)
	var lk = _looks.get(e[0])
	if lk == null:
		lk = {"tex": null, "used": _frame}
		_looks[e[0]] = lk
		_queue.append([e[0], e[2], caste])
	lk["used"] = _frame
	return lk if lk["tex"] != null else null


# Body length in world px (tail to nose, before caste and depth scaling) the old view drew this genome at: its painter laid the body
# out over T painter units (the segments' widths, the waist and neck) and drew 0.132 * T * min(1, 310 / (T + 120)) px of it.
func world_len(gn, caste: int) -> float:
	return _entry(gn, caste)[1] if ok else -1.0


func _entry(gn, caste: int) -> Array:
	var id = (gn.uid * 4 + caste) if gn.uid > 0 else "%d.%d" % [gn.get_instance_id(), caste]
	var e = _key_of.get(id)
	if e == null:
		var spec = _spec(gn, caste)
		var t = _total(gn.segments, float(gn.morph.get("major", 0.0)) + (SOLDIER_MAJOR if caste == 2 else 0.0),
			float(gn.morph.get("replete", 0.0)), int(gn.morph.get("petiole", 1)))
		e = [spec[0], 0.132 * t * min(1.0, 310.0 / (t + 120.0)), spec[1]]
		if _key_of.size() > 4000:
			_key_of = {}
		_key_of[id] = e
	return e


func _process(_delta: float) -> void:
	_frame += 1
	if _frame % 300 == 0 and _looks.size() > MAX_LOOKS:
		_evict()
	if not _busy and not _queue.is_empty():
		_bake_next()


# Drop the looks drawn longest ago, down to three quarters of MAX_LOOKS.
func _evict() -> void:
	var keys = _looks.keys()
	keys.sort_custom(func(a, b): return _looks[a]["used"] < _looks[b]["used"])
	for i in keys.size() - int(MAX_LOOKS * 0.75):
		if _looks[keys[i]]["tex"] != null and _frame - _looks[keys[i]]["used"] > 120:
			_looks.erase(keys[i])


# ------------------------------------------------------------------------------------------------ the look a genome gets

# [key, spec]: what the painter needs, with sizes scaled to an ordinary ant (mean segment size 24) and rounded, so the slow drift of
# a line's size and colour reuses one picture (the size on screen comes from world_len, the colour is the view's tint).
static func _spec(gn, caste: int) -> Array:
	var segs: Array = gn.segments
	var mean := 0.0
	for s in segs:
		mean += float(s["r"])
	mean = max(1.0, mean / segs.size())
	var f = 24.0 / mean
	var out_segs := []
	var key := PackedStringArray([str(caste)])
	for i in segs.size():
		var s: Dictionary = segs[i]
		var r = max(8.0, round(float(s["r"]) * f / R_STEP) * R_STEP)
		var limb = str(s.get("limb", ""))
		var n = int(s.get("n", 0)) if limb != "" else 0
		var ln = round(float(s.get("len", 0.0)) * f / LEN_STEP) * LEN_STEP if n > 0 else 0.0
		var o = {"r": r, "limb": limb, "n": n, "len": ln, "armor": int(s.get("armor", 0)), "spikes": int(s.get("spikes", 0))}
		key.append("%d%s%d.%d.%d%d" % [int(r), limb.left(2), n, int(ln), o["armor"], o["spikes"]])
		if i == segs.size() - 1:
			o["eyes"] = int(s.get("eyes", 1))
			o["jaw"] = str(s.get("jaw", "mandible"))
			o["antenna"] = round(float(s.get("antenna", 0.0)) / ANT_STEP) * ANT_STEP
			o["crown"] = bool(s.get("crown", false))
			key.append("h%d%s%d%d" % [o["eyes"], o["jaw"].left(3), int(o["antenna"]), int(o["crown"])])
		out_segs.append(o)
	var M: Dictionary = gn.morph
	var morph = {}
	for k in ["petiole", "wings", "stinger", "acid"]:
		morph[k] = int(M.get(k, 1 if k == "petiole" else 0))
	for k in ["major", "replete", "hair"]:
		morph[k] = round(float(M.get(k, 0.0)) * 4.0) / 4.0
	var forms = {}
	for k in ["spike", "leg", "antenna", "sting", "acid"]:
		forms[k] = int(gn.forms.get(k, 0))
	key.append("m%d%d%d%d%d%d%d" % [morph["petiole"], morph["wings"], morph["stinger"], morph["acid"], int(morph["major"] * 4),
		int(morph["replete"] * 4), int(morph["hair"] * 4)])
	key.append("f%d%d%d%d%d" % [forms["spike"], forms["leg"], forms["antenna"], forms["sting"], forms["acid"]])
	return ["|".join(key), {"segs": out_segs, "morph": morph, "forms": forms, "caste": caste}]


# The painter's body length T (painter units) for these segments: as _build lays them out.
static func _total(segs: Array, major: float, repl: float, nodes: int) -> float:
	var ns = segs.size()
	var total: float = _waist(ns, nodes) + 3.0
	for i in ns:
		var r = float(segs[i]["r"])
		if i == ns - 1:
			total += 2.0 * r * 0.98 * (1.0 + 0.5 * min(1.0, major))
		elif i == 0:
			total += 2.0 * r * 1.12 * (1.0 + 0.5 * repl)
		else:
			total += 2.0 * r * 1.3 - r * 1.3 * 0.18
	return total


# Gap between the gaster and the first thorax: the owner's kit has no waist piece, so the petiole nodes are small beads drawn with
# a scaled abdomen (the old painter left 12 + 10 per node painter units here and drew the nodes as procedural knobs).
static func _waist(ns: int, nodes: int) -> float:
	return (4.0 + 7.0 * nodes) if ns > 2 else 3.0


# ------------------------------------------------------------------------------------------------ kit pieces

func _rolename(role: String) -> String:
	if _role.has(role):
		return _role[role]
	var found := ""
	for n in ROLES.get(role, []):
		var e = _pieces.get(n)
		if e is Dictionary and Art.tex(str(e.get("file", ""))) != null:
			found = n
			break
	_role[role] = found
	return found


# Everything about one piece: a mipmapped texture, its size, hinge, and landmarks measured once from its alpha.
func _piece(name: String) -> Dictionary:
	if name == "":
		return {}
	if _info.has(name):
		return _info[name]
	var inf := {}
	var e = _pieces.get(name)
	var tex = Art.tex(str(e.get("file", ""))) if e is Dictionary else null
	var img: Image = tex.get_image() if tex != null else null
	if img != null and not img.is_empty():
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var sz = Vector2(img.get_width(), img.get_height())
		var pv = e.get("pivot", [sz.x * 0.5, sz.y * 0.5])
		inf = {"size": sz, "pivot": Vector2(float(pv[0]), float(pv[1])), "scale": float(e.get("scale", 1.0)), "name": name,
			"bare": name.ends_with("_bare") or bool(e.get("antennae_removed", false))}
		var src = e.get("src")
		if src is Array and src.size() == 4:
			inf["src"] = Vector2(float(src[0]), float(src[1]))
			inf["pad"] = (sz.x - (float(src[2]) - float(src[0])) * inf["scale"]) * 0.5
		_landmarks(img, inf)
		var mip = img.duplicate()
		mip.generate_mipmaps()
		inf["tex"] = ImageTexture.create_from_image(mip)
	_info[name] = inf
	return inf


# far: the opaque point farthest from the hinge (tip of a leg, jaw, antenna, wing, abdomen); low: the lowest opaque point (a foot).
static func _landmarks(img: Image, inf: Dictionary) -> void:
	var w = img.get_width()
	var h = img.get_height()
	var data = img.get_data()
	var pv: Vector2 = inf["pivot"]
	var far = pv
	var fd = -1.0
	var low_y = -1
	var low_x = 0.0
	var low_n = 0
	for y in range(0, h, 2):
		var row = y * w * 4 + 3
		for x in range(0, w, 2):
			if data[row + x * 4] > 127:
				var d = pv.distance_squared_to(Vector2(x, y))
				if d > fd:
					fd = d
					far = Vector2(x, y)
				if y > low_y:
					low_y = y
					low_x = 0.0
					low_n = 0
				if y == low_y:
					low_x += x
					low_n += 1
	inf["far"] = far
	inf["low"] = Vector2(low_x / max(1, low_n), low_y) if low_y >= 0 else Vector2(pv.x, h)


static func _sheet_pt(inf: Dictionary, p: Array) -> Vector2:
	if inf.has("src"):
		return (Vector2(p[0], p[1]) - inf["src"]) * inf["scale"] + Vector2(inf["pad"], inf["pad"])
	return Vector2(p[0], p[1])


# ------------------------------------------------------------------------------------------------ layout (kit_painter._build)

# Lays one pose of the ant out into _L, in painter units with the feet at the origin, facing right. g: 0..1 walk-cycle phase;
# animate = false: the standing pose. Returns the body's landmarks: {total, leg (longest leg), jaw, mid}.
func _build(sp: Dictionary, g: float, animate: bool) -> Dictionary:
	_L = [[], [], [], [], []]
	var M: Dictionary = sp["morph"]
	var FM: Dictionary = sp["forms"]
	var segs: Array = sp["segs"]
	var caste: int = sp["caste"]
	var ns = segs.size()
	var major = min(1.0, float(M["major"]) + (SOLDIER_MAJOR if caste == 2 else 0.0))
	var repl = float(M["replete"])
	var hair = float(M["hair"])
	var nodes = int(M["petiole"])
	var f_spike = int(FM["spike"])
	var f_leg = int(FM["leg"])
	var f_ant = int(FM["antenna"])
	var f_sting = int(FM["sting"])
	var f_acid = int(FM["acid"])
	var stilt = 1.3 if f_leg == 4 else 1.0
	var h: Dictionary = segs[ns - 1]
	var crown = bool(h.get("crown", false))
	var tint = Color.WHITE

	# --- per-segment size ---
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

	# --- stance: the kit's ants stand tall (legs about 0.9 L under the hips) ---
	var lmax := 0.0
	var max_ry := 0.0
	var has_legs := false
	for i in ns:
		max_ry = max(max_ry, RY[i])
		if segs[i]["limb"] == "leg" and segs[i]["n"] > 0:
			has_legs = true
			lmax = max(lmax, float(segs[i]["len"]) * stilt)
	var yb = -(lmax * 0.9 + RY[1 if ns > 2 else 0] * 0.45 + 8.0) if has_legs else -(max_ry * 0.95 + 6.0)
	yb = min(yb, -(max_ry * 0.75 + 8.0))
	if not has_legs:
		for i in range(1, ns - 1):
			yb = min(yb, -(HX[i] * 1.1 + 4.0))

	# --- layout rear (left) -> head (right) ---
	var waist: float = _waist(ns, nodes)
	var neck := 3.0
	var total := waist
	for i in ns:
		total += HX[i] * 2.0
		if i > 0 and i < ns - 1:
			total -= HX[i] * 0.18
	total += neck
	var pos := []
	var ang := []
	var x := -total / 2.0
	for i in ns:
		x += HX[i]
		var y = yb - RY[i] * (0.12 if kind[i] == "gaster" else 0.2)
		pos.append(Vector2(x, y))
		ang.append(0.0)
		x += HX[i]
		if i == 0:
			x += waist
		elif i < ns - 2:
			x -= HX[i] * 0.18
		elif i == ns - 2:
			x += neck
	# the trunk bobs with every tripod step, the gaster counter-swings, the head nods
	if animate:
		for i in ns:
			var bob = sin(g * TAU * 2.0 + i * 0.5) * 1.8
			var dx = 0.0
			var da = 0.0
			if kind[i] == "gaster":
				dx = sin(g * TAU + 0.6) * 1.6
				da = sin(g * TAU * 2.0 + 1.2) * 0.035
			elif kind[i] == "head":
				dx = sin(g * TAU + 2.0) * 0.8
				da = sin(g * TAU * 2.0 + 2.2) * 0.045
			pos[i] = pos[i] + Vector2(dx, bob)
			ang[i] = da

	# --- body pieces ---
	var thx := {}
	var g_attach = pos[0] + Vector2(HX[0] * 1.0, -RY[0] * 0.3).rotated(ang[0])
	if ns > 2:
		var t_inf = _piece(_thorax_role(segs[1], RY[1], hair, f_spike))
		var t_xf = _thorax_xf(t_inf, pos[1], HX[1], ang[1])
		thx[1] = {"xf": t_xf, "inf": t_inf}
		var t_waist = t_xf * _npt(t_inf, THX_RIG["waist"])
		var nd = _piece(_rolename("node"))
		if not nd.is_empty():
			for nn in nodes:
				var nt = (nn + 1.0) / (nodes + 1.0)
				var np = g_attach.lerp(t_waist, nt) + Vector2(0, -2.0)
				var nr = (8.5 if nodes == 1 else 7.0) * clamp(RY[1] / 15.6, 0.8, 1.5)
				var ndv: Vector2 = nd["far"] - nd["pivot"]
				var ns_ = nr * 2.1 / max(1.0, ndv.length())
				# the bead stands upright, hinge on top, centred on the waist line
				_op(K_BODY, nd, _xf_piece(nd, np - Vector2(0, nr * 1.05), PI * 0.5 - ndv.angle(), ns_), tint)
	# gaster
	var g_role = _abdomen_role(segs, M, f_leg, crown, repl)
	var g_inf = _piece(_rolename(g_role))
	var g_tip = pos[0] + Vector2(-HX[0], RY[0] * 0.3)
	if not g_inf.is_empty():
		var gax: Vector2 = g_inf["far"] - g_inf["pivot"]
		var gs = HX[0] * 2.35 / max(1.0, gax.length())
		var droop = 0.62 + 0.1 * repl
		var glen = gax.length() * gs
		droop = min(droop, asin(clamp((-6.0 - g_attach.y) / max(1.0, glen), -1.0, 1.0)) + 0.35)
		var grot = (PI - droop) - gax.angle() + ang[0]
		var g_xf = _xf_piece(g_inf, g_attach, grot, gs)
		g_tip = g_xf * g_inf["far"]
		_op(K_BODY, g_inf, g_xf, tint)
	# thoraxes, front to back so the front one overlaps
	for i in range(1, ns - 1):
		if not thx.has(i):
			var t_inf2 = _piece(_thorax_role(segs[i], RY[i], hair, f_spike))
			thx[i] = {"xf": _thorax_xf(t_inf2, pos[i], HX[i], ang[i]), "inf": t_inf2}
	for i in range(ns - 2, 0, -1):
		if not thx[i]["inf"].is_empty():
			_op(K_BODY, thx[i]["inf"], thx[i]["xf"], tint)
	# head
	var hp: Vector2 = pos[ns - 1]
	var hhx: float = HX[ns - 1]
	var hry: float = RY[ns - 1]
	var ha: float = ang[ns - 1]
	var h_inf = _piece(_head_role(h, major))
	var rig = _head_rig(h_inf)
	var h_sheet = 1.0
	var sock = hp + Vector2(hhx * 0.1, -hry * 0.8)
	var jawp = hp + Vector2(hhx * 0.75, hry * 0.45)
	var eyep = hp
	var topp = hp + Vector2(-hhx * 0.2, -hry * 0.9)
	var head_baked = false
	if not h_inf.is_empty():
		var dome: Rect2 = rig["dome"]
		var hs = hhx * 2.0 / max(1.0, dome.size.x)
		h_sheet = hs * h_inf["scale"]
		var dc = dome.position + dome.size * 0.5
		var h_xf = Transform2D(ha, hp + Vector2(-hhx * 0.22, hry * 0.08)) * Transform2D(0.0, Vector2(hs, hs), 0.0, Vector2.ZERO) * Transform2D(0.0, -dc)
		sock = h_xf * rig["sock"]
		jawp = h_xf * rig["jaw"]
		eyep = h_xf * rig["eye"]
		topp = h_xf * rig["top"]
		head_baked = not h_inf["bare"]
		_op(K_BODY, h_inf, h_xf, tint)
		var ne = int(h.get("eyes", 1))
		if ne >= 3:
			var ce = _piece(_rolename("eye_compound"))
			if not ce.is_empty():
				var es = hry * (0.62 + 0.05 * min(ne - 3, 2)) / ce["size"].y
				_op(K_BODY, ce, _xf_piece(ce, eyep, 0.0, es), Color.WHITE, false)
		if ne >= 2:
			var oc = _piece(_rolename("eye_glossy"))
			if not oc.is_empty():
				for e in range(1, min(ne, 5)):
					var op = topp + Vector2(hhx * (0.12 + 0.2 * (e - 1)), hry * (0.18 + 0.06 * (e % 2)))
					_op(K_BODY, oc, _xf_piece(oc, op, 0.0, hry * 0.2 / oc["size"].y), Color.WHITE, false)

	# --- armour, spikes, fur on the body pieces ---
	var spiked_gaster = g_role == "abdomen_spiked" and _rolename("abdomen_spiked") != ""
	for i in ns:
		var s: Dictionary = segs[i]
		var top_pt: Vector2
		var wdt: float = HX[i] * 2.0
		if kind[i] == "thorax" and thx.has(i) and not thx[i]["inf"].is_empty():
			top_pt = thx[i]["xf"] * _npt(thx[i]["inf"], THX_RIG["top"])
		elif kind[i] == "head":
			top_pt = topp
		else:
			top_pt = pos[i] + Vector2(HX[i] * 0.1, -RY[i] * 0.95).rotated(ang[i])
		var arm = int(s.get("armor", 0))
		if arm > 0:
			var pl = _piece(_rolename("plate_%d" % clamp(arm, 1, 3)))
			if not pl.is_empty():
				var ps = wdt * (0.55 + 0.08 * arm) / pl["size"].x
				_op(K_BODY, pl, _xf_piece(pl, top_pt + Vector2(0, RY[i] * 0.32), ang[i] - 0.05, ps), Color(0.85, 0.85, 0.85))
		var spk = int(s.get("spikes", 0))
		if spk > 0 and not (kind[i] == "gaster" and spiked_gaster and spk <= 2):
			_spikes(kind[i], spk, f_spike, top_pt, wdt, RY[i], ang[i], thx.get(i))
		if hair >= 0.3 and kind[i] != "head":
			var fu = _piece(_rolename("fur" if i % 2 == 0 else "fur_small"))
			if not fu.is_empty():
				var fs = RY[i] * (0.5 + 0.5 * hair) / fu["size"].y
				_op(K_BODY, fu, _xf_piece(fu, top_pt + Vector2(-wdt * 0.18, RY[i] * 0.12), -0.25, fs), tint)
				if hair >= 0.7:
					_op(K_BODY, fu, _xf_piece(fu, top_pt + Vector2(wdt * 0.15, RY[i] * 0.15), 0.2, fs * 0.8), tint)

	# --- legs (other limbs have no pictures in the kit) ---
	var leg_front := -1
	var leg_rear := -1
	for i in ns:
		if segs[i]["limb"] == "leg" and segs[i]["n"] > 0:
			if leg_rear < 0:
				leg_rear = i
			leg_front = i
	for i in ns:
		var s2: Dictionary = segs[i]
		var n: int = s2["n"]
		if s2["limb"] != "leg" or n <= 0:
			continue
		var L: float = float(s2["len"])
		for j in n:
			var t = 0.0 if n == 1 else (j - (n - 1) / 2.0) / ((n - 1) / 2.0)   # -1 rear .. +1 front
			for side in 2:   # 0 far, 1 near
				var role = 0      # 1 front pair, 2 rear pair
				var form = f_leg
				if i == leg_front and j == n - 1 and (f_leg in [1, 3] or caste == 1):
					role = 1
					if caste == 1 and f_leg != 3:
						form = 1          # a digger's forelegs dig
				elif i == leg_rear and j == 0 and f_leg == 2:
					role = 2
				var hip = _hip(thx.get(i), pos[i], HX[i], RY[i], ang[i], j, n, t)
				_leg(hip, L * stilt, t, i, j, side, form, role, hair, LEG_TINT if side == 1 else FAR_TINT, g)

	# --- head parts: jaws, antennae ---
	if not h_inf.is_empty() and not (head_baked and h_inf["name"].find("jaws") >= 0):
		var jaw = str(h.get("jaw", ""))
		var mrole = _mandible_role(jaw, major, M, f_acid, int(h.get("spikes", 0)))
		if mrole != "":
			var mn = _piece(_rolename(mrole))
			var mf = _piece(_rolename(mrole + "_far"))
			var msz = (1.0 + 0.35 * major) * (0.92 if mrole == "mand_small" else 0.8) * (1.15 if caste == 2 else 1.0)
			var open = 0.0
			if animate:
				open = 0.05 + 0.07 * (0.5 + 0.5 * sin(g * TAU * 2.0 + 0.7))
			if not mf.is_empty():
				var axf: Vector2 = mf["far"] - mf["pivot"]
				axf.x = -axf.x
				var rotf = (0.75 + open) - axf.angle() + ha
				_op(K_FAR, mf, _xf_piece(mf, jawp + Vector2(-3.0, -2.5), rotf, h_sheet * msz / mf["scale"], true), FAR_TINT)
			if not mn.is_empty():
				var axn: Vector2 = mn["far"] - mn["pivot"]
				var rotn = (0.55 - open) - axn.angle() + ha
				_op(K_NEAR, mn, _xf_piece(mn, jawp, rotn, h_sheet * msz / mn["scale"]), tint)
	if not head_baked and float(h.get("antenna", 0.0)) > 0.0:
		var alen = float(h["antenna"])
		var ar = ["ant_elbow", "ant_club", "ant_feather", "ant_whip", "ant_fork"][clamp(f_ant, 0, 4)]
		var an = _piece(_rolename(ar))
		var af = _piece(_rolename(ar + "_far"))
		if af.is_empty():
			af = an
		var alen_u = hhx * 2.0 * (0.45 + 0.017 * alen) * [1.0, 0.78, 0.95, 1.25, 1.0][clamp(f_ant, 0, 4)]
		for side in 2:
			var inf = af if side == 0 else an
			if inf.is_empty():
				continue
			var av: Vector2 = inf["far"] - inf["pivot"]
			var asc = alen_u / max(1.0, av.length())
			var sway = 0.0
			if animate:
				sway = sin(g * TAU + (1.3 if side == 0 else 0.0)) * 0.09 + sin(g * TAU * 2.0 + side) * 0.03
			var base_rot = 0.08 + ha + sway + (-0.18 if side == 0 else 0.0)
			var sp_ = sock + (Vector2(-4.0, -2.0) if side == 0 else Vector2.ZERO)
			var layer = K_FAR if side == 0 else K_NEAR
			_op(layer, inf, _xf_piece(inf, sp_, base_rot, asc), FAR_TINT if side == 0 else LEG_TINT)
			if f_ant == 4:
				_op(layer, inf, _xf_piece(inf, sp_, base_rot - 0.42, asc * 0.72), FAR_TINT if side == 0 else LEG_TINT)

	# --- wings: folded back over the gaster (row 2) ---
	if int(M["wings"]) == 1 and ns >= 2:
		var wi = 1 if ns > 2 else 0
		var wroot: Vector2
		if thx.has(wi) and not thx[wi]["inf"].is_empty():
			wroot = thx[wi]["xf"] * _npt(thx[wi]["inf"], [0.42, 0.18])
		else:
			wroot = pos[wi] + Vector2(HX[wi] * 0.1, -RY[wi] * 0.8)
		for w in 2:
			var wn = _piece(_rolename("wing_hind" if w == 0 else "wing_fore"))
			if wn.is_empty():
				continue
			var wv: Vector2 = wn["far"] - wn["pivot"]
			var wl = max(HX[0] * 1.6, wroot.x - g_tip.x + 14.0) * (0.86 if w == 0 else 1.06)
			var flutter = sin(g * TAU * 2.0 + w) * 0.02 if animate else 0.0
			var wa = PI + (0.1 if w == 0 else 0.2) - wv.angle() + flutter
			_op(K_WING, wn, _xf_piece(wn, wroot + Vector2(0, -1.0 + w * 2.0), wa, wl / max(1.0, wv.length())), Color(1, 1, 1, 0.9), false)

	# --- sting ---
	if int(M["stinger"]) == 1:
		var st = _piece(_rolename("sting"))
		if not st.is_empty():
			var gdir = (g_tip - g_attach).normalized()
			var sv: Vector2 = st["far"] - st["pivot"]
			var slen = RY[0] * (1.35 if f_sting in [1, 2] else 1.1) * (1.4 if f_sting == 2 else 1.0)
			var ssc = slen / max(1.0, sv.length())
			var base_a = gdir.angle() + 0.25 - (1.6 if f_sting == 2 else 0.0)     # a scorpion tail curls up over the back
			var nst = 2 if f_sting == 3 else 1
			for q in nst:
				var da = 0.0 if nst == 1 else (q - 0.5) * 0.55
				_op(K_BODY, st, _xf_piece(st, g_tip - gdir * slen * 0.2, base_a + da - sv.angle(), ssc), Color(1.25, 1.25, 1.1))
	var mouth = jawp + Vector2(hhx * 0.45, hry * 0.3)
	return {"total": total, "leg": lmax, "jaw": mouth, "mid": Vector2(0.0, yb), "top": topp}


func _head_role(h: Dictionary, major: float) -> String:
	var r = "head"
	if major >= 0.5 or int(h.get("armor", 0)) > 0 or int(h.get("spikes", 0)) > 0:
		r = "head_armored"
	elif int(h.get("eyes", 1)) >= 3:
		r = "head_eyes"
	elif str(h.get("jaw", "mandible")) in ["", "tentacle"]:
		r = "head_snout"
	var n = _rolename(r)
	return n if n != "" else _rolename("head")


func _thorax_role(s: Dictionary, ry: float, hair: float, f_spike: int) -> String:
	var r = "thorax"
	if int(s.get("spikes", 0)) > 0 and f_spike in [0, 1]:
		r = "thorax_spiked"
	elif ry < 13.0:
		r = "thorax_small"
	elif ry > 21.0:
		r = "thorax_big"
	elif hair < 0.3:
		r = "thorax_smooth"
	var n = _rolename(r)
	return n if n != "" else _rolename("thorax")


static func _abdomen_role(segs: Array, M: Dictionary, f_leg: int, crown: bool, repl: float) -> String:
	if crown or repl >= 0.75:
		return "abdomen_eggs"
	if repl >= 0.35:
		return "abdomen_round"
	if segs.size() > 1 and int(segs[0].get("spikes", 0)) > 0:
		return "abdomen_spiked"
	if int(M.get("wings", 0)) == 1 or f_leg in [2, 4] or float(segs[0]["r"]) < 22.0:
		return "abdomen_slim"
	return "abdomen"


static func _mandible_role(jaw: String, major: float, M: Dictionary, f_acid: int, head_spikes: int) -> String:
	match jaw:
		"mandible":
			if major >= 0.5:
				return "mand_crusher"
			if int(M.get("acid", 0)) == 1 and f_acid == 2:
				return "mand_fang"
			if head_spikes > 0:
				return "mand_jagged"
			if major >= 0.25:
				return "mand_sickle"
			return "mand_hook"
		"claw":
			return "mand_claw"
	return ""


# Piece transform: its hinge at `at`, rotated `rot`, `sc` painter units per piece pixel, mirrored left-right when flip.
static func _xf_piece(inf: Dictionary, at: Vector2, rot: float, sc: float, flip: bool = false) -> Transform2D:
	return Transform2D(rot, at) * Transform2D(0.0, Vector2(-sc if flip else sc, sc), 0.0, Vector2.ZERO) * Transform2D(0.0, -inf["pivot"])


static func _npt(inf: Dictionary, f: Array) -> Vector2:
	return Vector2(f[0] * inf["size"].x, f[1] * inf["size"].y)


static func _thorax_xf(inf: Dictionary, p: Vector2, hx: float, a: float) -> Transform2D:
	if inf.is_empty():
		return Transform2D()
	var s = hx * 2.3 / inf["size"].x
	return Transform2D(a, p) * Transform2D(0.0, Vector2(s, s), 0.0, Vector2.ZERO) * Transform2D(0.0, -_npt(inf, THX_RIG["core"]))


static func _head_rig(inf: Dictionary) -> Dictionary:
	if inf.is_empty():
		return {}
	var base_name = inf["name"].replace("_bare", "")
	var out := {}
	if HEAD_RIG.has(base_name) and inf.has("src"):
		var r = HEAD_RIG[base_name]
		var d0 = _sheet_pt(inf, [r["dome"][0], r["dome"][1]])
		var d1 = _sheet_pt(inf, [r["dome"][2], r["dome"][3]])
		out["dome"] = Rect2(d0, d1 - d0)
		for key in ["sock", "jaw", "eye", "top"]:
			out[key] = _sheet_pt(inf, r[key])
	else:
		var sz: Vector2 = inf["size"]
		var dm = HEAD_RIG_N["dome"]
		out["dome"] = Rect2(Vector2(dm[0], dm[1]) * sz, Vector2(dm[2] - dm[0], dm[3] - dm[1]) * sz)
		for key in ["sock", "jaw", "eye", "top"]:
			out[key] = Vector2(HEAD_RIG_N[key][0], HEAD_RIG_N[key][1]) * sz
	return out


# Hip of leg j (of n) on segment i: the thorax's coxae when it is a thorax piece, else along the underside of the segment.
static func _hip(th, p: Vector2, hx: float, ry: float, a: float, j: int, n: int, t: float) -> Vector2:
	if th != null and not th["inf"].is_empty():
		var hips: Array = THX_RIG["hips"]
		var f = 0.5 if n == 1 else float(j) / (n - 1)
		var q = f * (hips.size() - 1)
		var q0 = int(min(floor(q), hips.size() - 2))
		var u = q - q0
		var hp = Vector2(hips[q0][0], hips[q0][1]).lerp(Vector2(hips[q0 + 1][0], hips[q0 + 1][1]), u)
		return th["xf"] * (hp * th["inf"]["size"])
	return p + Vector2(t * hx * 0.55, ry * 0.7).rotated(a)


# One leg: the kit leg swings about its hip; the stance foot is planted on the ground and slides back at the body's speed (half
# stride 0.46 L), the swing foot comes forward on a lift arc; the leg stretches or folds a little so the claw lands on the ground.
func _leg(hip: Vector2, L: float, t: float, i: int, j: int, side: int, form: int, role: int, hair: float, tint: Color, g: float) -> void:
	var lr = "leg"
	if form == 4:
		lr = "leg_stilt"
	elif hair >= 0.5:
		lr = "leg_furry"
	if role == 1 and form == 1:
		lr = "leg_dig"
	elif role == 1 and form == 3:
		lr = "leg_raptor"
	elif role == 2:
		lr = "leg_jump"
	var inf = _piece(_rolename(lr))
	if inf.is_empty():
		inf = _piece(_rolename("leg"))
		if inf.is_empty():
			return
	var layer = K_FAR if side == 0 else K_LEG
	if side == 0:
		hip += Vector2(-7.0, -6.0)
	var hip_h = max(4.0, -hip.y - (5.0 if side == 0 else 0.0))
	var mirror = t < -0.34 and not (role == 1)
	if role == 1 and form == 3:
		# raptorial foreleg: held up and folded in front of the head, never on the ground
		var sway = sin(g * TAU) * 0.06
		var rv: Vector2 = inf["low"] - inf["pivot"]
		var rs = L * 0.85 / max(1.0, rv.length())
		_op(K_NEAR if side == 1 else K_FAR, inf, _xf_piece(inf, hip + Vector2(3, -3), -0.5 + sway - rv.angle(), rs), tint.lightened(0.1) if side == 1 else tint)
		return
	# gait phase: tripods alternate by (leg + side) parity; frames sample the middle of each sixth of the cycle
	var cyc = fposmod(g + 1.0 / 12.0 + (0.5 if (j + side) % 2 == 1 else 0.0) + i * 0.04, 1.0)
	var half = L * 0.46 * (0.6 if role == 2 else 1.0)
	var reach = clamp(t, -1.0, 1.0)
	var base_off = (reach * (0.95 if reach > 0.0 else 1.05) - 0.12) * hip_h
	if role == 2:
		base_off = -0.95 * hip_h
	var fx: float
	var lift := 0.0
	if cyc < 0.5:
		fx = lerp(half, -half, cyc / 0.5)
	else:
		var u = (cyc - 0.5) / 0.5
		fx = lerp(-half, half, u * u * (3.0 - 2.0 * u))
		lift = sin(u * PI) * hip_h * (0.3 if role != 2 else 0.12)
	var ground = -5.0 if side == 0 else 0.0
	var foot = Vector2(hip.x + base_off + fx, ground - lift)
	var pre = Transform2D(0.0, Vector2(-1.0 if mirror else 1.0, 1.0), 0.0, Vector2.ZERO) * Transform2D(0.0, -inf["pivot"])
	var v0: Vector2 = pre * inf["low"]
	var d_mid = Vector2(base_off, hip_h).length()
	var d_ext = max(Vector2(base_off + half, hip_h).length(), Vector2(base_off - half, hip_h).length())
	var D = (d_mid + d_ext) * 0.5
	var sc = D / max(1.0, v0.length())
	var tv = foot - hip
	var stretch = clamp(tv.length() / D, 0.68, 1.16)
	var thick = 0.86
	if form == 4:
		thick = 0.7
	elif role == 2:
		thick = 1.45
	elif role == 1:
		thick = 1.12
	var xf = Transform2D(tv.angle(), hip) * Transform2D(0.0, Vector2(stretch, thick), 0.0, Vector2.ZERO) * Transform2D(-v0.angle(), Vector2.ZERO) \
		* Transform2D(0.0, Vector2(sc, sc), 0.0, Vector2.ZERO) * pre
	_op(layer, inf, xf, tint)


func _spikes(kd: String, n: int, form: int, top: Vector2, wdt: float, ry: float, a: float, th) -> void:
	var bone = Color(1.1, 1.1, 1.05)
	if kd == "head":
		var hr = _piece(_rolename("horn_curl" if form == 2 else "horn_small"))
		if hr.is_empty():
			return
		var hs = ry * (0.7 + 0.12 * n) / max(1.0, (hr["far"] - hr["pivot"]).length())
		for q in min(n, 2):
			_op(K_BODY, hr, _xf_piece(hr, top + Vector2(-wdt * 0.12 * q, 2.0), -0.15 - 0.25 * q, hs), bone)
		return
	if form == 4 and kd == "thorax" and th != null and not th["inf"].is_empty():
		# propodeal spines: one long pair at the back of the mesosoma
		var hl = _piece(_rolename("horn_long"))
		if not hl.is_empty():
			var root = th["xf"] * _npt(th["inf"], [0.18, 0.3])
			var hls = ry * (1.6 + 0.2 * n) / max(1.0, (hl["far"] - hl["pivot"]).length())
			var hv: Vector2 = hl["far"] - hl["pivot"]
			var target = -PI * 0.5 - 0.75
			_op(K_BODY, hl, _xf_piece(hl, root + Vector2(-3, 2), target - hv.angle(), hls), bone.darkened(0.2))
			_op(K_BODY, hl, _xf_piece(hl, root, target + 0.12 - hv.angle(), hls), bone)
		return
	var r = "spine_trio"
	match form:
		1:
			r = "spine_cluster" if n <= 2 else "spine_knob"
		2:
			r = "spine_hook"
		3:
			r = "spine_ridge" if kd != "gaster" else "spine_backbone"
		_:
			r = "spine_trio" if n <= 2 else ("spine_crest" if n <= 4 else "spine_crest_tall")
	var sp = _piece(_rolename(r))
	if sp.is_empty():
		return
	var w_t = wdt * (0.45 + 0.08 * n)
	if form == 3:
		w_t = wdt * 0.9
	var ss = w_t / sp["size"].x
	if form == 2:
		ss = ry * (0.9 + 0.12 * n) / sp["size"].y
		for q in min(n, 3):
			var off = Vector2((q - (min(n, 3) - 1) * 0.5) * wdt * 0.28, 3.0)
			_op(K_BODY, sp, _xf_piece(sp, top + off, a - 0.1, ss), bone)
		return
	_op(K_BODY, sp, _xf_piece(sp, top + Vector2(0, 3.0), a, ss), bone)


func _op(layer: int, inf: Dictionary, xf: Transform2D, mod: Color, ink: bool = true) -> void:
	if not inf.is_empty():
		_L[layer].append([inf, xf, mod, ink])


# ------------------------------------------------------------------------------------------------ baking

class BakeCanvas extends Node2D:
	var cmds := []      # [texture, Transform2D, size, colour]

	func _draw() -> void:
		for c in cmds:
			draw_set_transform_matrix(c[1])
			draw_texture_rect(c[0], Rect2(Vector2.ZERO, c[2]), false, c[3])


# Lays out every pose of the next queued look, renders them into one texture in a SubViewport and reads it back (with mipmaps).
func _bake_next() -> void:
	var job = _queue.pop_front()
	var lk = _looks.get(job[0])
	if lk == null or lk["tex"] != null:
		return
	_busy = true
	var t0 = Time.get_ticks_usec()
	var sp: Dictionary = job[1]
	var poses := []
	var info := {}
	var bb := Rect2()
	var first := true
	for f in CELLS:
		var animate = f != STAND
		var res = _build(sp, float(f) / FRAMES if animate else 0.0, animate)
		if f == STAND:
			info = res
		poses.append(_L)
		for layer in _L:
			for op in layer:
				var sz: Vector2 = op[0]["size"]
				for c in [Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]:
					var p: Vector2 = op[1] * c
					if first:
						bb = Rect2(p, Vector2.ZERO)
						first = false
					else:
						bb = bb.expand(p)
	var total: float = max(1.0, info["total"])
	var k = BAKE_LEN / total
	var ring = RING * BAKE_LEN
	var cell = (bb.size * k + Vector2.ONE * (2 * PAD + 2.0 * ring)).ceil()
	var feet = (-bb.position * k + Vector2.ONE * (PAD + ring)).round()
	var wings := false
	for pose in poses:
		if not pose[K_WING].is_empty():
			wings = true
	var canvas = BakeCanvas.new()
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var ink_o := []
	for q in RING_N:
		ink_o.append(Vector2.from_angle(TAU * q / RING_N) * ring)
	for f in CELLS:
		var pose: Array = poses[f]
		for li in pose.size():
			var origin = feet + Vector2(cell.x * f, cell.y if li == K_WING else 0.0)
			var base = Transform2D(0.0, Vector2(k, k), 0.0, origin)
			for op in pose[li]:
				var inf: Dictionary = op[0]
				if op[3]:
					for o in ink_o:
						canvas.cmds.append([inf["tex"], Transform2D(0.0, Vector2(k, k), 0.0, origin + o) * op[1], inf["size"], INK])
				canvas.cmds.append([inf["tex"], base * op[1], inf["size"], op[2]])
	var vp = SubViewport.new()
	vp.size = Vector2i(int(cell.x) * CELLS, int(cell.y) * (2 if wings else 1))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.add_child(canvas)
	add_child(vp)
	var t1 = Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var t2 = Time.get_ticks_usec()
	var img = vp.get_texture().get_image()
	vp.queue_free()
	_busy = false
	if img == null or img.is_empty():
		ok = false              # this machine cannot read a bake back: the view keeps its whole-body pictures
		return
	img.generate_mipmaps()
	var leg_l: float = max(info["leg"], 20.0)
	lk["cell"] = cell
	lk["feet"] = feet
	lk["len"] = BAKE_LEN
	lk["cycle"] = 1.84 * leg_l / total
	lk["wings"] = wings
	lk["jaw"] = info["jaw"] * k
	lk["mid"] = info["mid"] * k
	lk["top"] = info["top"] * k
	lk["tex"] = ImageTexture.create_from_image(img)
	bake_us = (t1 - t0) + (Time.get_ticks_usec() - t2)
	bake_max_us = max(bake_max_us, bake_us)


# ------------------------------------------------------------------------------------------------ tests and tools

# How many looks are baked and waiting (for the perf test).
func stats() -> Dictionary:
	var baked := 0
	for lk in _looks.values():
		if lk["tex"] != null:
			baked += 1
	return {"looks": _looks.size(), "baked": baked, "queued": _queue.size(), "bake_ms": bake_us / 1000.0, "bake_max_ms": bake_max_us / 1000.0}
