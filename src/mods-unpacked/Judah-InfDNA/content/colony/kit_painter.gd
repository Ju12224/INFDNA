extends Node2D
# KitPainter: paints a genome as an ant ASSEMBLED FROM THE OWNER'S PART KIT (content/art/antkit/*.png, cut by
# tools/art/make_antkit.py, listed in content/art/antkit_manifest.json). A drop-in for body_painter.gd with the same public
# interface (genome, paint_scale, anim_t, gait), the same origin (the feet, body centred, facing right) and the same overall size,
# so sprite_baker bakes it unchanged (FRAMES, SIZE, FEET).
#
# What the genome picks:
#   head      big-headed majors and armoured / spiked heads get the armoured head, many eyes the big-eyed head (+ a compound eye),
#             jawless / tentacle-jawed lines the snout; otherwise the round head. Heads come antennae-less ("*_bare") so the antennae
#             and mandibles are separate, animated pieces; when the kit has no bare heads the heads with drawn antennae are used.
#   mandibles by jaw form (and major / venom jaws / head spikes), a near and a far jaw that open a little with the stride
#   antennae  by antenna form (elbowed / clubbed / feathered / whip / forked), length by the antenna gene; they sway
#   thorax    by size and hair (tufted when hairy, lobed when smooth, spiked with spikes), one per middle segment
#   abdomen   round (replete) / egg-laden (very replete or the crowned queen) / spiked / slim (fast forms) / plain
#   legs      by leg form: walking -> plain, digging forelegs -> spiny, jumping hind legs -> flared, raptorial forelegs -> armoured
#             (held up, folded), stilts -> plain stretched; furry legs on hairy lines; n per side from each segment's gene
#   wings, sting, spines / horns / ridges for spikes, plates for armour, fur tufts for hair, ocelli for extra eyes
#   anything the kit has no drawing for (tentacles, claw arms, fins, organs, venom, glow, the crown) is drawn by body_painter's own
#   procedural code (a private body_painter instance queues the shapes, this node draws them in its layer order). Not a subclass:
#   Godot 3 calls _draw on every level of a script chain, so a subclass would paint the procedural ant underneath.
# Walk cycle: alternating tripod (near front + near hind + far middle vs the other three). Each leg swings about its hip pivot:
# in stance the foot is planted and slides back at the body's speed (half-stride 0.46 L, the stride ant_view assumes), in swing it
# comes forward on a lift arc; the leg is stretched / folded a little along the hip-foot line so the claw lands exactly on the
# ground. The trunk bobs with every step, the gaster counter-swings, the head nods, antennae sway, mandibles work.
# Colour: every kit piece is drab warm grey; it is tinted by modulate = genome colour / KIT_BASE (a per-channel multiply that keeps
# the drawn shading and the black outlines), and gets an extra ink ring so the outline still reads when the ant is 40 px long.
# Cost: textures are loaded once (kept as meta on the scene tree root, freed with it), alpha landmarks are measured once per piece, the fit to the bake box once per genome.

const BodyPainter = preload("res://mods-unpacked/Judah-InfDNA/core/body_painter.gd")
const INK = Color("#15121a")
const G_FAR = 0       # body_painter's groups
const G_LEG = 1
const G_BODY = 2
const G_NEAR = 3
const G_WING = 4
const KIT_ART = "res://mods-unpacked/Judah-InfDNA/content/art/"
const KIT_MANIFEST = "res://mods-unpacked/Judah-InfDNA/content/art/antkit_manifest.json"
const KIT_META = "infdna_antkit"
const KIT_BASE = Color(0.60, 0.52, 0.46)    # mean fill colour of the kit's pieces
const RING = 3.4                            # extra ink round every piece, painter units
const RING_N = 10                           # ink copies per piece
const STING_TINT = Color(1.45, 1.5, 1.1)     # the kit's sting in body_painter's sting cream (#e3cf86 / KIT_BASE)
const FIT_W = 150.0                         # half the bake width in painter units at k = paint_scale (SIZE/FEET of sprite_baker)
const FIT_UP = 222.0                        # room above the feet
const FIT_DOWN = 16.0                       # room below the feet

# role -> candidate pieces; the first one the manifest lists (and whose file exists) is used, so a re-cut or a renamed piece only
# needs a name added here
const ROLES = {
	"head": ["head_round_bare", "head_round_jaws", "head_round", "head_1"],
	"head_eyes": ["head_beak_bare", "head_bugeye_jaws", "head_beak", "head_3"],
	"head_armored": ["head_armored_bare", "head_horned_jaws", "head_armored", "head_4"],
	"head_snout": ["head_snout_bare", "head_long_jaws", "head_snout", "head_2"],
	"thorax": ["thorax_tufted_1", "thorax_1"],
	"thorax_big": ["thorax_tufted_3", "thorax_tufted_2", "thorax_tufted_1", "thorax_3"],
	"thorax_smooth": ["thorax_lobed_2", "thorax_lobed_1", "thorax_tufted_1", "thorax_5"],
	"thorax_small": ["thorax_lobed_4", "thorax_lobed_3", "thorax_lobed_1", "thorax_tufted_1"],
	"thorax_spiked": ["thorax_spiked", "thorax_4", "thorax_tufted_2"],
	"abdomen": ["abdomen_plain", "abdomen_1"],
	"abdomen_round": ["abdomen_round", "abdomen_3", "abdomen_plain"],
	"abdomen_eggs": ["abdomen_eggs", "abdomen_5", "abdomen_round"],
	"abdomen_spiked": ["abdomen_spiked", "abdomen_4", "abdomen_plain"],
	"abdomen_slim": ["abdomen_slim", "abdomen_2", "abdomen_plain"],
	"leg": ["leg_plain", "leg_1"],
	"leg_dig": ["leg_spiny", "leg_2", "leg_plain"],
	"leg_jump": ["leg_flared", "leg_3", "leg_plain"],
	"leg_raptor": ["leg_armored", "leg_5", "leg_plain"],
	"leg_furry": ["leg_furry", "leg_4", "leg_plain"],
	"leg_stilt": ["leg_stilt", "leg_plain", "leg_1"],
	"ant_elbow": ["antenna_plain_l", "antenna_1_l", "antenna_elbow"],
	"ant_elbow_far": ["antenna_plain_r", "antenna_1_r", "antenna_plain_l"],
	"ant_club": ["antenna_club_l", "antenna_3_l", "antenna_bigclub"],
	"ant_club_far": ["antenna_club_r", "antenna_3_r", "antenna_club_l"],
	"ant_feather": ["antenna_feather_l", "antenna_2_r", "antenna_fern"],
	"ant_feather_far": ["antenna_feather_r", "antenna_2_l", "antenna_feather_l"],
	"ant_whip": ["antenna_whip", "antenna_5_l", "antenna_plain_l"],
	"ant_fork": ["antenna_segclub", "antenna_plain_l"],
	"mand_hook": ["mandible_hook_r", "mandible_1_r"],
	"mand_hook_far": ["mandible_hook_l", "mandible_1_l"],
	"mand_crusher": ["mandible_crusher_r", "mandible_4_r", "mandible_hook_r"],
	"mand_crusher_far": ["mandible_crusher_l", "mandible_4_l", "mandible_hook_l"],
	"mand_fang": ["mandible_fang_r", "mandible_3_r", "mandible_hook_r"],
	"mand_fang_far": ["mandible_fang_l", "mandible_3_l", "mandible_hook_l"],
	"mand_jagged": ["mandible_jagged_r", "mandible_8_r", "mandible_hook_r"],
	"mand_jagged_far": ["mandible_jagged_l", "mandible_8_l", "mandible_hook_l"],
	"mand_sickle": ["mandible_sickle_r", "mandible_2_r", "mandible_hook_r"],
	"mand_sickle_far": ["mandible_sickle_l", "mandible_2_l", "mandible_hook_l"],
	"mand_claw": ["mandible_claw_r", "mandible_6_r", "mandible_crusher_r"],
	"mand_claw_far": ["mandible_claw_l", "mandible_6_l", "mandible_crusher_l"],
	"mand_trap": ["mandible_trap_r", "mandible_7_r", "mandible_hook_r"],
	"mand_trap_far": ["mandible_trap_l", "mandible_7_l", "mandible_hook_l"],
	"mand_small": ["mandible_small_r", "mandible_5_r", "mandible_hook_r"],
	"mand_small_far": ["mandible_small_l", "mandible_5_l", "mandible_hook_l"],
	"wing_fore": ["wing_veined_fore", "wing_1_fore"],
	"wing_hind": ["wing_veined_hind", "wing_1_hind"],
	"sting": ["sting", "sting_1"],
	"spine_trio": ["spine_trio", "spine_5"],
	"spine_crest": ["spine_crest", "spine_3", "spine_trio"],
	"spine_crest_tall": ["spine_crest_tall", "spine_4", "spine_crest"],
	"spine_cluster": ["spine_cluster", "spine_6", "spine_trio"],
	"spine_knob": ["spine_knob", "spine_7", "spine_trio"],
	"spine_hook": ["spine_hook", "horn_1"],
	"spine_ridge": ["spine_ridge", "spine_1"],
	"spine_backbone": ["spine_backbone", "spine_2", "spine_ridge"],
	"horn_long": ["horn_long", "horn_4"],
	"horn_small": ["horn_small", "horn_2"],
	"horn_curl": ["horn_curl", "horn_3"],
	"plate_1": ["plate_lobes", "plate_3"],
	"plate_2": ["plate_fringed", "plate_1"],
	"plate_3": ["plate_spiked", "plate_2"],
	"fur": ["fur_tuft", "fur_3"],
	"fur_small": ["fur_tuft_small", "fur_4"],
	"fur_puff": ["fur_puff", "fur_1"],
	"eye_compound": ["eye_compound", "eye_2"],
	"eye_glossy": ["eye_glossy", "eye_1"],
}

# Heads: where the head capsule ("dome"), the antenna socket, the jaw hinge, the eye and the crown of the head are, in SHEET pixels
# (the owner's sheet; converted with the piece's src box and scale, so a re-trim or the antenna-less re-cut of the same drawing
# keeps them). Unknown heads use HEAD_RIG_N (fractions of the piece).
const HEAD_RIG = {
	"head_round": {"dome": [25, 395, 340, 650], "sock": [200, 440], "jaw": [272, 602], "eye": [215, 510], "top": [140, 400]},
	"head_snout": {"dome": [385, 385, 690, 610], "sock": [545, 440], "jaw": [652, 640], "eye": [530, 500], "top": [500, 392]},
	"head_beak": {"dome": [720, 380, 1040, 680], "sock": [920, 440], "jaw": [990, 610], "eye": [880, 500], "top": [860, 388]},
	"head_armored": {"dome": [1090, 370, 1420, 700], "sock": [1245, 440], "jaw": [1322, 640], "eye": [1290, 520], "top": [1210, 385]},
	"head_round_jaws": {"dome": [30, 250, 300, 470], "sock": [210, 300], "jaw": [262, 448], "eye": [165, 345], "top": [150, 255]},
	"head_long_jaws": {"dome": [400, 235, 680, 440], "sock": [575, 305], "jaw": [620, 430], "eye": [540, 330], "top": [530, 245]},
	"head_bugeye_jaws": {"dome": [745, 240, 1050, 470], "sock": [950, 290], "jaw": [980, 470], "eye": [895, 375], "top": [880, 250]},
	"head_horned_jaws": {"dome": [1130, 230, 1440, 480], "sock": [1335, 230], "jaw": [1360, 470], "eye": [1305, 370], "top": [1250, 245]},
}
const HEAD_RIG_N = {"dome": [0.03, 0.4, 0.85, 0.98], "sock": [0.5, 0.45], "jaw": [0.78, 0.82], "eye": [0.55, 0.62], "top": [0.4, 0.42]}
# Thorax: fractions of the piece (all the kit's thoraxes share one layout: tufted rear, pronotum lobe in front, coxae below).
const THX_RIG = {"core": [0.52, 0.42], "waist": [0.1, 0.5], "neck": [0.9, 0.36], "top": [0.5, 0.08],
	"hips": [[0.3, 0.72], [0.55, 0.74], [0.8, 0.72]]}

# draw layers, back to front
const K_FAR = 0       # far-side legs, antenna, jaw
const K_BODY = 1      # waist, gaster, thoraxes, head and what sits on them
const K_LEG = 2       # near legs, over the body (their tops overlap the coxae, as in the owner's drawings)
const K_DECO = 3      # procedural organs, venom, glow (body_painter)
const K_NEAR = 4      # near jaw and antenna, raptorial forelegs
const K_WING = 5

var genome = null
var paint_scale := 0.5
var anim_t := 0.0
var gait := 0.0          # 0..1 walk-cycle phase (baked into animation frames)

var _bp = null        # body_painter used as a library for the procedural extras (not in the tree; freed with this node)
var _L := []          # per layer: ops, either {"kit": ...} or a body_painter op
var _bb := Rect2()    # bounds of the kit pieces (painter units), for the fit
var _bb_on := false
var _reach := 0.0     # longest leg's forward / backward reach beyond the rest pose (fit margin for the stride)


# ------------------------------------------------------------------------------------------------ kit loading (shared, static)

static func _holder() -> Object:
	var ml = Engine.get_main_loop()
	if ml is SceneTree and ml.root != null:
		return ml.root
	return Engine


static func _kit() -> Dictionary:
	var hold = _holder()
	if hold.has_meta(KIT_META):
		return hold.get_meta(KIT_META)
	var k = {"pieces": {}, "info": {}, "role": {}, "fit": {}, "ok": false}
	var f = File.new()
	if f.file_exists(KIT_MANIFEST) and f.open(KIT_MANIFEST, File.READ) == OK:
		var res = JSON.parse(f.get_as_text())
		f.close()
		if res.error == OK and res.result is Dictionary and res.result.get("pieces") is Dictionary:
			k["pieces"] = res.result["pieces"]
	var ok = not k["pieces"].empty()
	for role in ["head", "thorax", "abdomen", "leg"]:
		if _role(k, role) == "":
			ok = false
	k["ok"] = ok
	hold.set_meta(KIT_META, k)
	return k


# True when the part kit (manifest + the key pieces) is there, so sprite_baker can use this painter.
static func available() -> bool:
	return _kit()["ok"]


# Forget the loaded kit (after a re-cut, in tools); the next paint reloads it.
static func reload() -> void:
	var hold = _holder()
	if hold.has_meta(KIT_META):
		hold.remove_meta(KIT_META)


static func _role(k: Dictionary, role: String) -> String:
	if k["role"].has(role):
		return k["role"][role]
	var found := ""
	var f = File.new()
	for n in ROLES.get(role, []):
		var e = k["pieces"].get(n)
		if e is Dictionary and f.file_exists(KIT_ART + str(e.get("file", ""))):
			found = n
			break
	k["role"][role] = found
	return found


# Everything about one piece: texture, size, hinge, and landmarks measured once from its alpha.
static func _info(k: Dictionary, name: String) -> Dictionary:
	if name == "":
		return {}
	if k["info"].has(name):
		return k["info"][name]
	var inf := {}
	var e = k["pieces"].get(name)
	if e is Dictionary:
		var img = _load_png(KIT_ART + str(e.get("file", "")))
		if img != null:
			var tex = ImageTexture.new()
			tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
			var sz = Vector2(img.get_width(), img.get_height())
			var pv = e.get("pivot", [sz.x * 0.5, sz.y * 0.5])
			inf = {"tex": tex, "size": sz, "pivot": Vector2(float(pv[0]), float(pv[1])), "kind": str(e.get("kind", "")),
				"scale": float(e.get("scale", 1.0)), "name": name,
				"bare": name.ends_with("_bare") or bool(e.get("antennae_removed", false))}
			var src = e.get("src")
			if src is Array and src.size() == 4:
				inf["src"] = Vector2(float(src[0]), float(src[1]))
				inf["pad"] = (sz.x - (float(src[2]) - float(src[0])) * inf["scale"]) * 0.5
			_landmarks(img, inf)
	k["info"][name] = inf
	return inf


# The PNGs ship in the mod without import files: read the bytes (Image.load on a res:// path warns on every call).
static func _load_png(path: String):
	var f = File.new()
	if f.open(path, File.READ) != OK:
		return null
	var buf = f.get_buffer(f.get_len())
	f.close()
	var img = Image.new()
	if img.load_png_from_buffer(buf) != OK:
		return null
	return img


# far: the opaque point farthest from the hinge (tip of a leg, jaw, antenna, wing, abdomen); low: the lowest opaque point (a foot).
static func _landmarks(img: Image, inf: Dictionary) -> void:
	img.lock()
	var w = img.get_width()
	var h = img.get_height()
	var pv: Vector2 = inf["pivot"]
	var far = pv
	var fd = -1.0
	var low_y = -1
	var low_x = 0.0
	var low_n = 0
	var step = 3
	for y in range(0, h, step):
		for x in range(0, w, step):
			if img.get_pixel(x, y).a > 0.5:
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
	img.unlock()
	inf["far"] = far
	inf["low"] = Vector2(low_x / max(1, low_n), low_y) if low_y >= 0 else Vector2(pv.x, h)


# A rig point of a piece in its own pixels: sheet pixels when the piece knows its sheet box, else fractions of the piece.
static func _sheet_pt(inf: Dictionary, p: Array) -> Vector2:
	if inf.has("src"):
		return (Vector2(p[0], p[1]) - inf["src"]) * inf["scale"] + Vector2(inf["pad"], inf["pad"])
	return Vector2(p[0], p[1])


# ------------------------------------------------------------------------------------------------ painting

func _ready() -> void:
	if not available():
		# no kit: the procedural painter draws instead (sprite_baker normally checks available() first)
		var p = BodyPainter.new()
		p.genome = genome
		p.paint_scale = paint_scale
		p.anim_t = anim_t
		p.gait = gait
		add_child(p)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _bp != null and is_instance_valid(_bp):
		_bp.free()


func _draw() -> void:
	if genome == null:
		return
	var k = _kit()
	if not k["ok"]:
		return
	if _bp == null:
		_bp = BodyPainter.new()
	_bp.genome = genome
	_bp.gait = gait
	_bp.anim_t = anim_t
	var key = str(genome.get_instance_id())
	var fit = k["fit"].get(key)
	if fit == null:
		# first frame of this body plan: lay it out at rest, measure it, shrink to the bake box if it does not fit
		_bb_on = true
		_bb = Rect2()
		var f0 = _build(k, false) / max(0.0001, paint_scale)    # body_painter's size factor (1 for an ordinary ant)
		_bb_on = false
		fit = 1.0
		if _bb.size.x > 0.0:
			var ext_x = (max(-_bb.position.x, _bb.end.x) + 6.0 + _reach) * f0
			var ext_up = (-_bb.position.y + 6.0) * f0
			var ext_dn = (_bb.end.y + 2.0) * f0
			fit = min(1.0, min(FIT_W / ext_x, min(FIT_UP / ext_up, FIT_DOWN / max(1.0, ext_dn))))
		if k["fit"].size() > 4000:
			k["fit"].clear()
		k["fit"][key] = fit
	var kk = _build(k, true)
	var base = Transform2D(Vector2(kk * fit, 0), Vector2(0, kk * fit), Vector2.ZERO)
	_execute(base)


# Lays the ant out and fills _L. Returns the body_painter scale k (before the fit). animate = false: the rest pose.
func _build(k: Dictionary, animate: bool) -> float:
	_bp._G = [[[], [], []], [[], [], []], [[], [], []], [[], [], []], [[], [], []]]
	_L = [[], [], [], [], [], []]
	var g = gait if animate else 0.0
	var M = genome.morph if "morph" in genome else {}
	var FM = genome.forms if "forms" in genome else {}
	var camo = float(M.get("camo", 0.0))
	var col: Color = genome.color.linear_interpolate(Color(0.44, 0.42, 0.33), 0.55 * camo)
	if col.v < 0.3:
		col = Color.from_hsv(col.h, col.s, 0.3)      # near-black lines still show their shading against the ink
	var tint = Color(col.r / KIT_BASE.r, col.g / KIT_BASE.g, col.b / KIT_BASE.b, 1.0)
	var tint_leg = tint.darkened(0.12)
	var tint_far = tint.darkened(0.5)
	var base: Color = col
	var dark: Color = base.darkened(0.38)
	var limbc: Color = base.darkened(0.22)
	var farc: Color = base.darkened(0.55)
	var segs: Array = genome.segments
	var ns = segs.size()
	var major = float(M.get("major", 0.0))
	var repl = float(M.get("replete", 0.0))
	var hair = float(M.get("hair", 0.0))
	var nodes = int(M.get("petiole", 1))
	var f_spike = int(FM.get("spike", 0))
	var f_leg = int(FM.get("leg", 0))
	var f_ant = int(FM.get("antenna", 0))
	var f_sting = int(FM.get("sting", 0))
	var f_acid = int(FM.get("acid", 0))
	var stilt = 1.3 if f_leg == 4 else 1.0
	var h: Dictionary = segs[ns - 1]
	var crown = bool(h.get("crown", false))

	# --- per-segment size: the same ellipses as body_painter, so a body plan keeps its size ---
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
	_reach = lmax * 0.46
	var yb = -(lmax * 0.9 + RY[1 if ns > 2 else 0] * 0.45 + 8.0) if has_legs else -(max_ry * 0.95 + 6.0)
	yb = min(yb, -(max_ry * 0.75 + 8.0))
	if not has_legs:
		for i in range(1, ns - 1):
			yb = min(yb, -(HX[i] * 1.1 + 4.0))     # a legless body rests on its thorax pieces' coxae, not below the ground

	# --- layout rear (left) -> head (right), as body_painter ---
	var waist: float = (12.0 + 10.0 * nodes) if ns > 2 else 4.0
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
		var y = yb
		match kind[i]:
			"gaster":
				y = yb - RY[i] * 0.12
			"head":
				y = yb - RY[i] * 0.2
			_:
				y = yb - RY[i] * 0.2
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
	var kk = min(1.0, 310.0 / (total + 120.0)) * paint_scale

	# --- body pieces ---
	var thx := {}     # segment index -> {"xf", "inf"} for thoraxes (legs, wings and spines hang from their rig)
	# waist nodes between gaster and thorax
	var g_attach = pos[0] + Vector2(HX[0] * 1.0, -RY[0] * 0.3).rotated(ang[0])
	if ns > 2:
		var t_inf = _info(k, _thorax_role(k, segs[1], RY[1], hair, f_spike))
		var t_xf = _thorax_xf(t_inf, pos[1], HX[1], ang[1])
		thx[1] = {"xf": t_xf, "inf": t_inf}
		var t_waist = t_xf.xform(_npt(t_inf, THX_RIG["waist"]))
		for nn in nodes:
			var nt = (nn + 1.0) / (nodes + 1.0)
			var np = g_attach.linear_interpolate(t_waist, nt) + Vector2(0, -2.0)
			var nr = (8.5 if nodes == 1 else 7.0) * clamp(RY[1] / 15.6, 0.8, 1.5)
			_node(np, nr * 0.8, nr * 1.05, base, dark)
	# gaster
	var g_inf = _info(k, _role(k, _abdomen_role(segs, M, f_leg, crown, repl)))
	var g_tip = pos[0] + Vector2(-HX[0], RY[0] * 0.3)
	var g_xf = Transform2D()
	if not g_inf.empty():
		var gax: Vector2 = g_inf["far"] - g_inf["pivot"]
		var gs = HX[0] * 2.35 / max(1.0, gax.length())
		var droop = 0.62 + 0.1 * repl
		# a low body (no legs, short legs): the gaster hangs less, its tip stays above the ground
		var glen = gax.length() * gs
		droop = min(droop, asin(clamp((-6.0 - g_attach.y) / max(1.0, glen), -1.0, 1.0)) + 0.35)
		var grot = (PI - droop) - gax.angle() + ang[0]
		g_xf = _xf_piece(g_inf, g_attach, grot, gs)
		g_tip = g_xf.xform(g_inf["far"])
		_kit_op(K_BODY, g_inf, g_xf, tint)
	# thoraxes (every middle segment)
	for i in range(1, ns - 1):
		if not thx.has(i):
			var t_inf2 = _info(k, _thorax_role(k, segs[i], RY[i], hair, f_spike))
			thx[i] = {"xf": _thorax_xf(t_inf2, pos[i], HX[i], ang[i]), "inf": t_inf2}
	for i in range(ns - 2, 0, -1):
		if not thx[i]["inf"].empty():
			_kit_op(K_BODY, thx[i]["inf"], thx[i]["xf"], tint)
	# head
	var hp: Vector2 = pos[ns - 1]
	var hhx: float = HX[ns - 1]
	var hry: float = RY[ns - 1]
	var ha: float = ang[ns - 1]
	var h_inf = _info(k, _head_role(k, h, major))
	var rig = _head_rig(h_inf)
	var h_xf = Transform2D()
	var h_sheet = 1.0         # painter units per sheet pixel of the head's sheet (jaws are sized with it)
	var sock = hp + Vector2(hhx * 0.1, -hry * 0.8)
	var jawp = hp + Vector2(hhx * 0.75, hry * 0.45)
	var eyep = hp
	var topp = hp + Vector2(-hhx * 0.2, -hry * 0.9)
	var head_baked = false
	if not h_inf.empty():
		var dome: Rect2 = rig["dome"]
		var hs = hhx * 2.0 / max(1.0, dome.size.x)
		h_sheet = hs * h_inf["scale"]
		var dc = dome.position + dome.size * 0.5
		h_xf = Transform2D(ha, hp + Vector2(-hhx * 0.22, hry * 0.08)) * Transform2D(Vector2(hs, 0), Vector2(0, hs), Vector2.ZERO) * Transform2D(0.0, -dc)
		sock = h_xf.xform(rig["sock"])
		jawp = h_xf.xform(rig["jaw"])
		eyep = h_xf.xform(rig["eye"])
		topp = h_xf.xform(rig["top"])
		head_baked = not h_inf["bare"]
		_kit_op(K_BODY, h_inf, h_xf, tint)
		var ne = int(h.get("eyes", 1))
		if ne >= 3:
			var ce = _info(k, _role(k, "eye_compound"))
			if not ce.empty():
				var es = hry * (0.62 + 0.05 * min(ne - 3, 2)) / ce["size"].y
				_kit_op(K_BODY, ce, _xf_piece(ce, eyep, 0.0, es), Color(1, 1, 1), false)
		if ne >= 2:
			var oc = _info(k, _role(k, "eye_glossy"))
			if not oc.empty():
				for e in range(1, min(ne, 5)):
					var op = topp + Vector2(hhx * (0.12 + 0.2 * (e - 1)), hry * (0.18 + 0.06 * (e % 2)))
					_kit_op(K_BODY, oc, _xf_piece(oc, op, 0.0, hry * 0.2 / oc["size"].y), Color(1, 1, 1), false)

	# --- armour, spikes, fur on the body pieces ---
	for i in ns:
		var s: Dictionary = segs[i]
		var top_pt: Vector2
		var wdt: float = HX[i] * 2.0
		if kind[i] == "thorax" and thx.has(i) and not thx[i]["inf"].empty():
			top_pt = thx[i]["xf"].xform(_npt(thx[i]["inf"], THX_RIG["top"]))
		elif kind[i] == "head":
			top_pt = topp
		else:
			top_pt = pos[i] + Vector2(HX[i] * 0.1, -RY[i] * 0.95).rotated(ang[i])
			if kind[i] == "gaster" and not g_inf.empty():
				top_pt = g_xf.xform((g_inf["pivot"] + g_inf["far"]) * 0.5) + Vector2(0, -RY[i] * 0.72)
		var arm = int(s.get("armor", 0))
		if arm > 0:
			var pl = _info(k, _role(k, "plate_%d" % clamp(arm, 1, 3)))
			if not pl.empty():
				var ps = wdt * (0.55 + 0.08 * arm) / pl["size"].x
				_kit_op(K_BODY, pl, _xf_piece(pl, top_pt + Vector2(0, RY[i] * 0.32), ang[i] - 0.05, ps), tint.darkened(0.15))
		var sp = int(s.get("spikes", 0))
		if sp > 0 and not (kind[i] == "gaster" and _role(k, "abdomen_spiked") != "" and _abdomen_role(segs, M, f_leg, crown, repl) == "abdomen_spiked" and sp <= 2):
			_spikes_kit(k, kind[i], sp, f_spike, top_pt, wdt, RY[i], ang[i], thx.get(i), tint)
		if hair >= 0.3 and kind[i] != "head":
			var fu = _info(k, _role(k, "fur" if i % 2 == 0 else "fur_small"))
			if not fu.empty():
				var fs = RY[i] * (0.5 + 0.5 * hair) / fu["size"].y
				_kit_op(K_BODY, fu, _xf_piece(fu, top_pt + Vector2(-wdt * 0.18, RY[i] * 0.12), -0.25, fs), tint)
				if hair >= 0.7:
					_kit_op(K_BODY, fu, _xf_piece(fu, top_pt + Vector2(wdt * 0.15, RY[i] * 0.15), 0.2, fs * 0.8), tint)

	# --- legs and other limbs ---
	var leg_front := -1
	var leg_rear := -1
	for i in ns:
		if segs[i]["limb"] == "leg" and segs[i]["n"] > 0:
			if leg_rear < 0:
				leg_rear = i
			leg_front = i
	for i in ns:
		var s2: Dictionary = segs[i]
		var limb: String = s2["limb"]
		var n: int = s2["n"]
		if limb == "" or n <= 0:
			continue
		var L: float = float(s2["len"])
		for j in n:
			var t = 0.0 if n == 1 else (j - (n - 1) / 2.0) / ((n - 1) / 2.0)   # -1 rear .. +1 front
			for side in 2:   # 0 far, 1 near
				if limb == "leg":
					var role = 0      # 1 front pair, 2 rear pair
					if i == leg_front and j == n - 1 and f_leg in [1, 3]:
						role = 1
					elif i == leg_rear and j == 0 and f_leg == 2:
						role = 2
					var hip = _hip(thx.get(i), pos[i], HX[i], RY[i], ang[i], j, n, t)
					_leg_kit(k, hip, L * stilt, t, i, j, side, f_leg, role, hair, tint_leg if side == 1 else tint_far, g)
				else:
					var off = Vector2(-6.0, -5.0) if side == 0 else Vector2.ZERO
					var colx = farc if side == 0 else limbc
					var grp = G_FAR if side == 0 else (G_LEG if limb != "claw" else G_NEAR)
					match limb:
						"tentacle":
							_bp._tentacle(grp, pos[i] + off, HX[i], RY[i], t, j, side, colx)
						"claw":
							_bp._claw_limb(grp, pos[i] + off, HX[i], RY[i], L, t, side, colx, base)
						"fin":
							if side == 1:
								_bp._fin(pos[i], HX[i], RY[i], L, t, j, dark, base)
	_harvest(K_FAR, K_LEG, K_NEAR)

	# --- head parts: jaws, antennae ---
	if not h_inf.empty() and not (head_baked and h_inf["name"].find("jaws") >= 0):
		var jaw = str(h.get("jaw", ""))
		var mrole = _mandible_role(jaw, major, M, f_acid, int(h.get("spikes", 0)))
		if mrole != "":
			var mn = _info(k, _role(k, mrole))
			var mf = _info(k, _role(k, mrole + "_far"))
			var msz = (1.0 + 0.35 * major) * (0.92 if mrole == "mand_small" else 0.8)
			var open = 0.0
			if animate:
				open = 0.05 + 0.07 * (0.5 + 0.5 * sin(g * TAU * 2.0 + 0.7))
			if not mf.empty():
				var axf: Vector2 = mf["far"] - mf["pivot"]
				axf.x = -axf.x
				var rotf = (0.75 + open) - axf.angle() + ha
				_kit_op(K_FAR, mf, _xf_piece(mf, jawp + Vector2(-3.0, -2.5), rotf, h_sheet * msz / mf["scale"], true), tint_far)
			if not mn.empty():
				var axn: Vector2 = mn["far"] - mn["pivot"]
				var rotn = (0.55 - open) - axn.angle() + ha
				_kit_op(K_NEAR, mn, _xf_piece(mn, jawp, rotn, h_sheet * msz / mn["scale"]), tint)
		elif jaw == "tentacle":
			for q in 3:
				var root = jawp + Vector2(-2.0, 2.0)
				var sway = sin(anim_t * 4.0 + q * 1.3) * 5.0
				var pts = _bp._quad(root, root + Vector2(16 + q * 5, 10 + q * 3), root + Vector2(10 + q * 9 + sway, 30 - q * 3), 8)
				_bp._tapered_chain(G_NEAR if q != 1 else G_FAR, pts, 5.5, 2.0, limbc if q != 1 else farc)
	if not head_baked and float(h.get("antenna", 0.0)) > 0.0:
		var alen = float(h["antenna"])
		var ar = ["ant_elbow", "ant_club", "ant_feather", "ant_whip", "ant_fork"][clamp(f_ant, 0, 4)]
		var an = _info(k, _role(k, ar))
		var af = _info(k, _role(k, ar + "_far")) if ar + "_far" in ROLES else an
		if af.empty():
			af = an
		var alen_u = hhx * 2.0 * (0.45 + 0.017 * alen) * [1.0, 0.78, 0.95, 1.25, 1.0][clamp(f_ant, 0, 4)]
		for side in 2:
			var inf = af if side == 0 else an
			if inf.empty():
				continue
			var av: Vector2 = inf["far"] - inf["pivot"]
			var asc = alen_u / max(1.0, av.length())
			var sway = 0.0
			if animate:
				sway = sin(g * TAU + (1.3 if side == 0 else 0.0)) * 0.09 + sin(g * TAU * 2.0 + side) * 0.03
			var base_rot = 0.08 + ha + sway + (-0.18 if side == 0 else 0.0)
			var sp_ = sock + (Vector2(-4.0, -2.0) if side == 0 else Vector2.ZERO)
			var layer = K_FAR if side == 0 else K_NEAR
			_kit_op(layer, inf, _xf_piece(inf, sp_, base_rot, asc), tint_far if side == 0 else tint_leg)
			if f_ant == 4:
				# forked: a second, shorter lash from the same socket
				_kit_op(layer, inf, _xf_piece(inf, sp_, base_rot - 0.42, asc * 0.72), tint_far if side == 0 else tint_leg)

	# --- wings: folded back over the gaster ---
	if int(M.get("wings", 0)) == 1 and ns >= 2:
		var wi = 1 if ns > 2 else 0
		var wroot: Vector2
		if thx.has(wi) and not thx[wi]["inf"].empty():
			wroot = thx[wi]["xf"].xform(_npt(thx[wi]["inf"], [0.42, 0.18]))
		else:
			wroot = pos[wi] + Vector2(HX[wi] * 0.1, -RY[wi] * 0.8)
		var wtint = Color(1, 1, 1).linear_interpolate(tint, 0.25)
		for w in 2:
			var wn = _info(k, _role(k, "wing_hind" if w == 0 else "wing_fore"))
			if wn.empty():
				continue
			var wv: Vector2 = wn["far"] - wn["pivot"]
			var wl = max(HX[0] * 1.6, wroot.x - g_tip.x + 14.0) * (0.86 if w == 0 else 1.06)   # just past the gaster tip
			var flutter = sin(g * TAU * 2.0 + w) * 0.02 if animate else 0.0
			var wa = PI + (0.1 if w == 0 else 0.2) - wv.angle() + flutter
			# the wing pieces are drawn root-right; rotate so the root-to-tip line runs back and a little up
			_kit_op(K_WING, wn, _xf_piece(wn, wroot + Vector2(0, -1.0 + w * 2.0), wa, wl / max(1.0, wv.length())),
				Color(wtint.r, wtint.g, wtint.b, 0.88), false)

	# --- rear weapons and organs (procedural, body_painter) ---
	var gp0: Vector2 = pos[0]
	if int(M.get("stinger", 0)) == 1:
		var st = _info(k, _role(k, "sting"))
		var gdir = (g_tip - g_attach).normalized()
		if f_sting == 2 or st.empty():
			_bp._sting(g_tip, f_sting, gp0, HX[0], RY[0])
		else:
			var sv: Vector2 = st["far"] - st["pivot"]
			var slen = RY[0] * (1.35 if f_sting == 1 else 1.1)
			var ssc = slen / max(1.0, sv.length())
			var base_a = gdir.angle() + 0.25
			var nst = 2 if f_sting == 3 else 1
			for q in nst:
				var da = 0.0 if nst == 1 else (q - 0.5) * 0.55
				_kit_op(K_BODY, st, _xf_piece(st, g_tip - gdir * slen * 0.2, base_a + da - sv.angle(), ssc), STING_TINT)
	if int(M.get("acid", 0)) == 1:
		match f_acid:
			1:
				_bp._venom_sacs(gp0, HX[0], RY[0], 0.0)
			2:
				_bp._venom_jaws(hp, hhx, hry, 0.0, (0.75 + 0.3 * major) * clamp(hry / 20.0, 0.8, 1.5), str(h.get("jaw", "")))
			3:
				_bp._spray_nozzle(g_tip + Vector2(6, -2))
			_:
				_bp._acid_drop(g_tip + Vector2(10, 12))
	var OG = genome.organs if "organs" in genome else {}
	var FUS = genome.fusions() if genome.has_method("fusions") else []
	if int(OG.get("tongue", 0)) >= 3:
		_bp._turret_eye(hp, hhx, hry, 0.0, base, dark)
	var hang = ang.duplicate()
	_bp._organs(OG, FUS, pos, HX, RY, hang, ns, base, dark, limbc, farc)
	if int(M.get("glow", 0)) == 1:
		for i in ns:
			var gpp = pos[i] + Vector2(-HX[i] * 0.15, RY[i] * 0.3)
			_bp._add(G_BODY, 2, {"t": "circle", "p": gpp, "r": RY[i] * 0.55, "c": Color(0.6, 1.0, 0.55, 0.16)})
			_bp._add(G_BODY, 2, {"t": "circle", "p": gpp, "r": RY[i] * 0.34, "c": Color(0.65, 1.0, 0.6, 0.3)})
			_bp._add(G_BODY, 2, {"t": "circle", "p": gpp, "r": RY[i] * 0.17, "c": Color(0.85, 1.0, 0.75, 0.95)})
	if crown:
		var cb = topp + Vector2(0, -2)
		var crown_pts = PoolVector2Array([cb + Vector2(-15, 6), cb + Vector2(-18, -11), cb + Vector2(-8, -2), cb + Vector2(0, -16),
			cb + Vector2(8, -2), cb + Vector2(18, -11), cb + Vector2(15, 6)])
		_bp._add(G_NEAR, 0, {"t": "poly_ol", "pts": crown_pts, "c": Color("#f2c14e"), "w": 4.0})
		_bp._add(G_NEAR, 2, {"t": "circle", "p": cb + Vector2(0, -6), "r": 3.0, "c": Color("#e8483b")})
		_bp._add(G_NEAR, 2, {"t": "line", "pts": PoolVector2Array([cb + Vector2(-11, -4), cb + Vector2(-13, 2)]), "w": 2.5, "c": Color("#fff2b8")})
	_harvest(K_FAR, K_DECO, K_NEAR)
	return kk


# ------------------------------------------------------------------------------------------------ piece choice

func _head_role(k: Dictionary, h: Dictionary, major: float) -> String:
	var r = "head"
	if major >= 0.5 or int(h.get("armor", 0)) > 0 or int(h.get("spikes", 0)) > 0:
		r = "head_armored"
	elif int(h.get("eyes", 1)) >= 3:
		r = "head_eyes"
	elif str(h.get("jaw", "mandible")) in ["", "tentacle"]:
		r = "head_snout"
	var n = _role(k, r)
	return n if n != "" else _role(k, "head")


func _thorax_role(k: Dictionary, s: Dictionary, ry: float, hair: float, f_spike: int) -> String:
	var r = "thorax"
	if int(s.get("spikes", 0)) > 0 and f_spike in [0, 1]:
		r = "thorax_spiked"
	elif ry < 13.0:
		r = "thorax_small"
	elif ry > 21.0:
		r = "thorax_big"
	elif hair < 0.3:
		r = "thorax_smooth"
	var n = _role(k, r)
	return n if n != "" else _role(k, "thorax")


func _abdomen_role(segs: Array, M: Dictionary, f_leg: int, crown: bool, repl: float) -> String:
	if crown or repl >= 0.75:
		return "abdomen_eggs"
	if repl >= 0.35:
		return "abdomen_round"
	if segs.size() > 1 and int(segs[0].get("spikes", 0)) > 0:
		return "abdomen_spiked"
	if int(M.get("wings", 0)) == 1 or f_leg in [2, 4] or float(segs[0]["r"]) < 22.0:
		return "abdomen_slim"
	return "abdomen"


func _mandible_role(jaw: String, major: float, M: Dictionary, f_acid: int, head_spikes: int) -> String:
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


# ------------------------------------------------------------------------------------------------ placement helpers

# Piece transform: its hinge at `at`, rotated `rot`, `sc` painter units per piece pixel, mirrored left-right when flip.
func _xf_piece(inf: Dictionary, at: Vector2, rot: float, sc: float, flip: bool = false) -> Transform2D:
	var sx = -sc if flip else sc
	return Transform2D(rot, at) * Transform2D(Vector2(sx, 0), Vector2(0, sc), Vector2.ZERO) * Transform2D(0.0, -inf["pivot"])


func _npt(inf: Dictionary, f: Array) -> Vector2:
	return Vector2(f[0] * inf["size"].x, f[1] * inf["size"].y)


func _thorax_xf(inf: Dictionary, p: Vector2, hx: float, a: float) -> Transform2D:
	if inf.empty():
		return Transform2D()
	var s = hx * 2.3 / inf["size"].x
	var core = _npt(inf, THX_RIG["core"])
	return Transform2D(a, p) * Transform2D(Vector2(s, 0), Vector2(0, s), Vector2.ZERO) * Transform2D(0.0, -core)


func _head_rig(inf: Dictionary) -> Dictionary:
	if inf.empty():
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
func _hip(th, p: Vector2, hx: float, ry: float, a: float, j: int, n: int, t: float) -> Vector2:
	if th != null and not th["inf"].empty():
		var hips: Array = THX_RIG["hips"]
		var f = 0.5 if n == 1 else float(j) / (n - 1)
		var q = f * (hips.size() - 1)
		var q0 = int(min(floor(q), hips.size() - 2))
		var u = q - q0
		var hp = Vector2(hips[q0][0], hips[q0][1]).linear_interpolate(Vector2(hips[q0 + 1][0], hips[q0 + 1][1]), u)
		return th["xf"].xform(hp * th["inf"]["size"])
	return p + Vector2(t * hx * 0.55, ry * 0.7).rotated(a)


# One leg: the kit leg swings about its hip; stance foot planted on the ground, swing foot on a lift arc.
func _leg_kit(k: Dictionary, hip: Vector2, L: float, t: float, i: int, j: int, side: int, form: int, role: int, hair: float, tint: Color, g: float) -> void:
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
	var inf = _info(k, _role(k, lr))
	if inf.empty():
		inf = _info(k, _role(k, "leg"))
		if inf.empty():
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
		var rot = -0.5 + sway - rv.angle()      # hip-to-claw line raised forward and up
		_kit_op(K_NEAR if side == 1 else K_FAR, inf, _xf_piece(inf, hip + Vector2(3, -3), rot, rs), tint.lightened(0.1) if side == 1 else tint)
		return
	# gait phase: tripods alternate by (leg + side) parity; frames sample the middle of each sixth of the cycle
	var cyc = fposmod(g + 1.0 / 12.0 + (0.5 if (j + side) % 2 == 1 else 0.0) + i * 0.04, 1.0)
	var half = L * 0.46
	if role == 2:
		half *= 0.6
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
	# leg vector in its own (mirrored) pixels; its length at rest is the mean hip-foot distance of the stance
	var pre = Transform2D(Vector2(-1.0 if mirror else 1.0, 0), Vector2(0, 1), Vector2.ZERO) * Transform2D(0.0, -inf["pivot"])
	var v0: Vector2 = pre.xform(inf["low"])
	var d_mid = Vector2(base_off, hip_h).length()
	var d_ext = max(Vector2(base_off + half, hip_h).length(), Vector2(base_off - half, hip_h).length())
	var D = (d_mid + d_ext) * 0.5
	var sc = D / max(1.0, v0.length())
	var tv = foot - hip
	var d = tv.length()
	var stretch = clamp(d / D, 0.68, 1.16)
	var thick = 0.86
	if form == 4:
		thick = 0.7
	elif role == 2:
		thick = 1.45
	elif role == 1:
		thick = 1.12
	var xf = Transform2D(tv.angle(), hip) * Transform2D(Vector2(stretch, 0), Vector2(0, thick), Vector2.ZERO) * Transform2D(-v0.angle(), Vector2.ZERO) \
		* Transform2D(Vector2(sc, 0), Vector2(0, sc), Vector2.ZERO) * pre
	_kit_op(layer, inf, xf, tint, true, true)


func _spikes_kit(k: Dictionary, kd: String, n: int, form: int, top: Vector2, wdt: float, ry: float, a: float, th, tint: Color) -> void:
	var bone = Color(1, 1, 1).linear_interpolate(tint, 0.35)
	if kd == "head":
		var hr = _info(k, _role(k, "horn_curl" if form == 2 else "horn_small"))
		if hr.empty():
			return
		var hs = ry * (0.7 + 0.12 * n) / max(1.0, (hr["far"] - hr["pivot"]).length())
		for q in min(n, 2):
			_kit_op(K_BODY, hr, _xf_piece(hr, top + Vector2(-wdt * 0.12 * q, 2.0), -0.15 - 0.25 * q, hs), bone)
		return
	if form == 4 and kd == "thorax" and th != null and not th["inf"].empty():
		# propodeal spines: one long pair at the back of the mesosoma
		var hl = _info(k, _role(k, "horn_long"))
		if not hl.empty():
			var root = th["xf"].xform(_npt(th["inf"], [0.18, 0.3]))
			var hls = ry * (1.6 + 0.2 * n) / max(1.0, (hl["far"] - hl["pivot"]).length())
			var hv: Vector2 = hl["far"] - hl["pivot"]
			var target = -PI * 0.5 - 0.75    # up and back
			_kit_op(K_BODY, hl, _xf_piece(hl, root + Vector2(-3, 2), target - hv.angle(), hls), bone.darkened(0.2))
			_kit_op(K_BODY, hl, _xf_piece(hl, root, target + 0.12 - hv.angle(), hls), bone)
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
	var sp = _info(k, _role(k, r))
	if sp.empty():
		return
	var w_t = wdt * (0.45 + 0.08 * n)
	if form == 3:
		w_t = wdt * 0.9
	var ss = w_t / sp["size"].x
	if form == 2:
		ss = ry * (0.9 + 0.12 * n) / sp["size"].y
		for q in min(n, 3):
			var off = Vector2((q - (min(n, 3) - 1) * 0.5) * wdt * 0.28, 3.0)
			_kit_op(K_BODY, sp, _xf_piece(sp, top + off, a - 0.1, ss), bone)
		return
	_kit_op(K_BODY, sp, _xf_piece(sp, top + Vector2(0, 3.0), a, ss), bone)


# Petiole node: an inked knob in the body colour.
func _node(c: Vector2, rx: float, ry: float, base: Color, dark: Color) -> void:
	_L[K_BODY].append({"t": "poly", "pts": _ellipse(c, rx + RING + 2.5, ry + RING + 2.5, 18), "c": INK})
	_L[K_BODY].append({"t": "poly", "pts": _ellipse(c, rx, ry, 18), "c": dark})
	_L[K_BODY].append({"t": "poly", "pts": _ellipse(c + Vector2(rx * 0.05, -ry * 0.15), rx * 0.82, ry * 0.7, 16), "c": base})
	_L[K_BODY].append({"t": "circle", "p": c + Vector2(-rx * 0.25, -ry * 0.45), "r": max(1.5, rx * 0.22), "c": base.lightened(0.45)})


# ------------------------------------------------------------------------------------------------ ops

# feet_ok: the piece is a leg standing on the ground, its rect corners below the feet do not count for the fit.
func _kit_op(layer: int, inf: Dictionary, xf: Transform2D, mod: Color, ink: bool = true, feet_ok: bool = false) -> void:
	if inf.empty():
		return
	_L[layer].append({"t": "kit", "tex": inf["tex"], "xf": xf, "size": inf["size"], "m": mod, "ink": ink})
	if _bb_on:
		var sz: Vector2 = inf["size"]
		for c in [Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]:
			var p = xf.xform(c)
			if feet_ok:
				p.y = min(p.y, 0.0)
			if _bb.size == Vector2.ZERO and _bb.position == Vector2.ZERO:
				_bb = Rect2(p, Vector2(0.001, 0.001))
			else:
				_bb = _bb.expand(p)


# Move body_painter's queued procedural ops into kit layers (far, middle, near groups).
func _harvest(l_far: int, l_mid: int, l_near: int) -> void:
	var dest = {G_FAR: l_far, G_LEG: l_mid, G_BODY: l_mid, G_NEAR: l_near, G_WING: K_WING}
	for grp in _bp._G.size():
		for pass_ops in _bp._G[grp]:
			for op in pass_ops:
				_L[dest[grp]].append(op)
	_bp._G = [[[], [], []], [[], [], []], [[], [], []], [[], [], []], [[], [], []]]


func _execute(base: Transform2D) -> void:
	var ring := []
	for q in RING_N:
		var a = TAU * q / RING_N
		ring.append(Vector2(cos(a), sin(a)) * RING)
	var ink_c = Color(INK.r, INK.g, INK.b, 1.0)
	draw_set_transform_matrix(base)
	var cur_kit = false
	for layer in _L:
		for op in layer:
			if op["t"] == "kit":
				var r = Rect2(Vector2.ZERO, op["size"])
				if op["ink"]:
					for o in ring:
						draw_set_transform_matrix(base * Transform2D(0.0, o) * op["xf"])
						draw_texture_rect(op["tex"], r, false, ink_c)
				draw_set_transform_matrix(base * op["xf"])
				draw_texture_rect(op["tex"], r, false, op["m"])
				cur_kit = true
			else:
				if cur_kit:
					draw_set_transform_matrix(base)
					cur_kit = false
				_exec(op)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# body_painter's op executor (its ops, drawn on this canvas item)
func _exec(op: Dictionary) -> void:
	match op["t"]:
		"poly":
			draw_colored_polygon(op["pts"], op["c"], PoolVector2Array(), null, null, true)
		"line":
			draw_polyline(op["pts"], op["c"], op["w"], true)
			for p in op["pts"]:
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


func _ellipse(c: Vector2, rx: float, ry: float, n: int = 28) -> PoolVector2Array:
	var pts = PoolVector2Array()
	for i in n:
		var a = TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
