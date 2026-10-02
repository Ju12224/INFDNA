extends Reference
# Body-plan + behavior genome. Pure data + mutation, no Brotato dependencies.
# Body: chain of segments (rear -> head) with part slots.
# Behavior: response thresholds and digging tendencies that drive task choice.

const SELF_PATH = "res://mods-unpacked/Judah-InfDNA/core/genome.gd"
const PALETTE = ["#8a4b2e", "#6b5a8e", "#a8322d", "#3d6b3a", "#c9a13b", "#2f5f7a", "#7a3d6b", "#d9772b", "#2a9d8f", "#e0c341", "#d94f8a", "#4a6fd6", "#25201f", "#b8b0a2", "#6fbf4a"]
const MAX_SEGMENTS = 5
# Anatomy genes (M4). Bools are 0/1, the rest 0..1. Every gain has a cost in phenotype.gd.
const MORPH_DEFAULT = {
	"petiole": 1,     # waist nodes: 1 (formicine) or 2 (myrmicine)
	"pattern": 0,     # gaster pattern: 0 plain, 1 bands, 2 spots, 3 dark tip
	"hair": 0.0,      # bristles: a little armor, a little slower
	"stinger": 0,     # sting: attack up, upkeep up
	"acid": 0,        # acid gland: thorns + attack, carries less
	"wings": 0,       # alates: fast on the surface, frail, cramped in tunnels
	"major": 0.0,     # big-headed majors: bite and dig harder, slower
	"replete": 0.0,   # swollen honey gaster: carries more, waddles
	"glow": 0,        # luminous spots: senses further in the dark
	"camo": 0.0,      # mottled drab colouring: harder to hit
	"phero": 0.0,     # pheromone strength: trails pull harder
}
const MACRO_CHANCE = 0.06    # chance a mutation is a macro-mutation (three changes at once)
const MORPH_BOOL = ["stinger", "acid", "wings", "glow"]
# Part forms (v0.20): a subtype inside an existing part family. 0 = the classic form.
# A form gene can sit hidden in a line that lacks the organ and shows once the organ
# appears. Every non-zero form has a gain and a cost in phenotype.gd.
const FORMS = {
	"spike": ["spines", "thorns", "hooked barbs", "dorsal ridge", "propodeal spines"],
	"acid": ["acid gland", "venom sacs", "venom-dripping jaws", "spray nozzle"],
	"leg": ["walking legs", "digging forelegs", "jumping hind legs", "raptorial forelegs", "stilt legs"],
	"antenna": ["elbowed antennae", "clubbed antennae", "feathered antennae", "whip antennae", "forked antennae"],
	"sting": ["stinger", "barbed stinger", "scorpion tail", "twin stingers"],
}
# Organ lines (v0.21): borrowed from across the animal kingdom. Each line evolves one
# tier at a time (0 none -> 1 -> 2 -> 3); tiers are cumulative, so a tier-3 ant still has
# the tier 1-2 organs it grew from. Tier 3 organs are live abilities in the sim.
const ORGANS = {
	"sonic": ["", "stridulator", "echo horns", "sonic cannon"],
	"electric": ["", "electroreceptors", "electric organ", "arc discharger"],
	"shell": ["", "turtle scutes", "spiral shell", "armadillo roll"],
	"silk": ["", "spinnerets", "web glands", "bolas snare"],
	"tongue": ["", "lapping tongue", "sticky tongue", "ballistic tongue"],
	"regen": ["", "starfish regrowth", "axolotl gills", "planarian split"],
}
const ORGAN_SRC = {
	"sonic": ["", "cricket", "bat", "pistol shrimp"],
	"electric": ["", "platypus", "electric eel", "torpedo ray"],
	"shell": ["", "turtle", "snail", "armadillo"],
	"silk": ["", "spider", "orb weaver", "bolas spider"],
	"tongue": ["", "anteater", "frog", "chameleon"],
	"regen": ["", "starfish", "axolotl", "planarian"],
}
# Fusions: when two lines both reach tier 2 in one body, a new ability emerges from the
# pair. Each is computed from the genome, so it is always traceable to its two parents.
const FUSIONS = {
	"thunderclap": {"name": "Thunderclap", "a": "sonic", "b": "electric", "why": "sound resonator + electric organ"},
	"slingshot": {"name": "Silk slingshot", "a": "silk", "b": "tongue", "why": "silk line + ballistic tongue"},
	"fortress": {"name": "Living fortress", "a": "shell", "b": "regen", "why": "shell + regrowing tissue"},
	"sonarweb": {"name": "Sonar web", "a": "sonic", "b": "silk", "why": "echo hearing + vibrating web"},
}
const FUSION_TIER = 2

# Lab bias keys (existing strains) that also favour a form family
const FORM_BIAS = {"spike": "spike", "acid": "acid", "leg": "leg", "antenna": "eyes", "sting": "stinger"}
const MORPH_NAMES = {"stinger": "a stinger", "acid": "acid glands", "wings": "wings", "glow": "glow spots",
	"hair": "hairy", "major": "big-headed", "replete": "a replete", "camo": "camouflaged", "phero": "strong-scented"}

var uid: int = 0        # assigned by the colony; used as the sprite cache key
# Lineage (M4): each body-plan change links back to the plan it came from, so the HUD
# can show a line's history. Only visible changes create a link; behaviour and small
# size/colour drift keep the parent's link, so chains stay short.
var parent = null       # genome this plan branched from (null = founder)
var note := ""          # what changed at the branch, e.g. "gained wings"
var born_gen := 0       # generation of the first ant with this plan
var born_t := -1.0      # sim time the plan appeared (-1 = before the run)
const LINEAGE_MAX = 40
var color: Color = Color("#8a4b2e")
var segments: Array = []
var morph: Dictionary = MORPH_DEFAULT.duplicate()
var forms: Dictionary = {}      # family -> form index; missing = 0 (classic)
var organs: Dictionary = {}     # organ line -> tier 0..3; missing = 0
var traits: Dictionary = {
	"forage_t": 0.45,   # lower = forages at weaker hunger signals
	"dig_t": 0.55,      # lower = digs at weaker crowding signals
	"dig_down": 0.5,    # 0 = digs sideways, 1 = digs straight down
	"explore": 0.6,     # tendency to push outward to tunnel tips
	"defend_t": 0.6,    # lower = joins the fight at weaker alarm signals
}


static func make_ant():
	var g = load(SELF_PATH).new()
	g.segments = [
		{"r": 30.0, "limb": "", "n": 0, "len": 0.0, "armor": 0, "spikes": 0},
		{"r": 20.0, "limb": "leg", "n": 3, "len": 55.0, "armor": 0, "spikes": 0},
		{"r": 24.0, "limb": "", "n": 0, "len": 0.0, "armor": 0, "spikes": 0,
			"head": true, "eyes": 1, "jaw": "mandible", "antenna": 30.0},
	]
	return g


static func make_queen():
	var g = make_ant()
	g.color = Color("#6e3a22")
	g.segments[0]["r"] = 44.0
	g.segments[1]["r"] = 24.0
	g.segments[2]["r"] = 26.0
	g.segments[2]["crown"] = true
	return g


func copy():
	var g = load(SELF_PATH).new()
	g.color = color
	g.segments = segments.duplicate(true)
	g.traits = traits.duplicate()
	g.morph = MORPH_DEFAULT.duplicate()
	for k in morph.keys():
		g.morph[k] = morph[k]
	g.forms = forms.duplicate()
	g.organs = organs.duplicate()
	g.parent = node()     # a plain copy is the same line; mutated() overrides this
	return g


func m(key: String):
	return morph.get(key, MORPH_DEFAULT.get(key, 0))


# Form index for a family (0 = classic). Safe on genomes saved before v0.20.
func form(family: String) -> int:
	return int(forms.get(family, 0)) if "forms" in self else 0


# Organ tier for a line (0 = none). Safe on genomes from before v0.21.
func organ(line: String) -> int:
	return int(organs.get(line, 0)) if "organs" in self else 0


# Fusion ids this body carries (both parent lines at FUSION_TIER or above).
func fusions() -> Array:
	var out := []
	for id in FUSIONS.keys():
		var f = FUSIONS[id]
		if organ(f["a"]) >= FUSION_TIER and organ(f["b"]) >= FUSION_TIER:
			out.append(id)
	return out


# True when the organ that shows this family's form is present.
func form_visible(family: String) -> bool:
	match family:
		"spike":
			for s in segments:
				if s["spikes"] > 0:
					return true
			return false
		"acid":
			return int(m("acid")) == 1
		"sting":
			return int(m("stinger")) == 1
		"leg":
			for s in segments:
				if s["limb"] == "leg" and s["n"] > 0:
					return true
			return false
		"antenna":
			return head().get("antenna", 0.0) > 0.0
	return false


func head() -> Dictionary:
	return segments[segments.size() - 1]


# Returns a mutated copy (uid 0 until the colony assigns one).
# bias: {"leg","claw","tentacle","armor","spike","eyes","size","segment"} -> weight
# boosts from the shop; each shifts odds, never guarantees an outcome.
func mutated(rng: RandomNumberGenerator, bias: Dictionary = {}, macro_depth: int = 0):
	# v0.23: now and then a macro-mutation changes three things at once (a new body plan in one
	# generation), so lineages can jump instead of only creeping.
	if macro_depth == 0 and rng.randf() < MACRO_CHANCE:
		var mm = mutated(rng, bias, 1)
		mm = mm.mutated(rng, bias, 1)
		return mm.mutated(rng, bias, 1)
	var g = copy()
	# Lineage link. An unregistered intermediate (first half of a double mutation)
	# never becomes a node: its change is folded into the final plan's note.
	var link_parent = node()
	var carried := ""
	if uid == 0 and parent != null:
		link_parent = parent
		carried = note
	var what := ""
	if rng.randf() < 0.2:
		var keys = g.traits.keys()
		var k = keys[rng.randi_range(0, keys.size() - 1)]
		g.traits[k] = clamp(g.traits[k] + rng.randf_range(-0.28, 0.28), 0.02, 1.0)
		g._set_link(link_parent, carried, what)
		return g

	var segs: Array = g.segments
	var s: Dictionary = segs[rng.randi_range(0, segs.size() - 1)]
	var b_limb = bias.get("leg", 0.0) + bias.get("claw", 0.0) + bias.get("tentacle", 0.0)
	var ops = ["dup", "loss", "limb", "tune", "armor", "spikes", "size", "head", "color", "morph", "form", "organ"]
	var w = [10.0 * (1.0 + bias.get("segment", 0.0)), 4.0, 28.0 * (1.0 + b_limb * 0.5), 9.0,
		11.0 * (1.0 + bias.get("armor", 0.0)), 9.0 * (1.0 + bias.get("spike", 0.0)),
		20.0 * (1.0 + bias.get("size", 0.0) * 0.5), 11.0 * (1.0 + bias.get("eyes", 0.0)), 16.0,
		26.0 * (1.0 + bias.get("morph", 0.0)), 12.0 * (1.0 + 0.3 * _form_bias_sum(bias)),
		15.0 * (1.0 + bias.get("organ", 0.0))]
	match _pick(rng, ops, w):
		"form":
			what = g._mutate_form(rng, bias)
		"organ":
			what = g._mutate_organ(rng, bias)
		"morph":
			what = g._mutate_morph(rng, bias)
		"dup":
			if segs.size() < MAX_SEGMENTS:
				var i = rng.randi_range(0, segs.size() - 2)
				var dup: Dictionary = segs[i].duplicate(true)
				dup.erase("head")
				dup.erase("crown")
				segs.insert(i, dup)
				what = "extra body segment"
		"loss":
			if segs.size() > 2:
				segs.remove(rng.randi_range(0, segs.size() - 2))
				what = "lost a segment"
		"limb":
			var kinds = ["leg", "tentacle", "claw", "fin", ""]
			var kw = [2.0 * (1.0 + bias.get("leg", 0.0)), 1.0 + bias.get("tentacle", 0.0) * 1.5,
				1.0 + bias.get("claw", 0.0) * 1.5, 1.0, 1.0]
			var old_limb = s["limb"]
			s["limb"] = _pick(rng, kinds, kw)
			s["n"] = rng.randi_range(1, 4)
			if s["limb"] != old_limb:
				what = ("grew %ss" % s["limb"]) if s["limb"] != "" else ("lost %ss" % old_limb)
			s["len"] = rng.randf_range(30.0, 80.0)
		"tune":
			if s["limb"] != "":
				s["len"] = clamp(s["len"] + rng.randf_range(-12.0, 12.0), 25.0, 90.0)
				s["n"] = int(clamp(s["n"] + [-1, 1][rng.randi_range(0, 1)], 1, 4))
		"armor":
			var up = 0.66 + 0.1 * bias.get("armor", 0.0)
			var a0 = s["armor"]
			s["armor"] = int(clamp(s["armor"] + (1 if rng.randf() < up else -1), 0, 3))
			if s["armor"] != a0:
				what = "thicker armor" if s["armor"] > a0 else "thinner armor"
		"spikes":
			var up2 = 0.66 + 0.1 * bias.get("spike", 0.0)
			var s0 = s["spikes"]
			s["spikes"] = int(clamp(s["spikes"] + (rng.randi_range(1, 2) if rng.randf() < up2 else -1), 0, 5))
			if s["spikes"] != s0:
				what = "more spikes" if s["spikes"] > s0 else "fewer spikes"
		"size":
			var lo = -9.0 + 4.0 * bias.get("size", 0.0)
			s["r"] = clamp(s["r"] + rng.randf_range(lo, 11.0), 12.0, 50.0)
		"head":
			var h = g.head()
			if rng.randf() < 0.5 + 0.2 * bias.get("eyes", 0.0):
				var e0 = h.get("eyes", 1)
				h["eyes"] = int(clamp(h.get("eyes", 1) + [-1, 1, 2][rng.randi_range(0, 2)], 1, 5))
				if h["eyes"] != e0:
					what = "%d eyes" % h["eyes"]
				h["antenna"] = clamp(h.get("antenna", 30.0) + rng.randf_range(-6.0, 10.0 + 4.0 * bias.get("eyes", 0.0)), 0.0, 50.0)
			else:
				var j0 = h.get("jaw", "")
				h["jaw"] = _pick(rng, ["mandible", "claw", "tentacle", ""],
					[2.0, 1.0 + bias.get("claw", 0.0), 1.0 + bias.get("tentacle", 0.0), 0.5])
				if h["jaw"] != j0:
					what = (h["jaw"] + " jaw") if h["jaw"] != "" else "lost its jaw"
		"color":
			if rng.randf() < 0.45:
				g.color = g.color.lightened(0.16) if rng.randf() < 0.5 else g.color.darkened(0.16)
			else:
				g.color = Color(PALETTE[rng.randi_range(0, PALETTE.size() - 1)])
				what = "new colour"
	# v0.23 slow drift: nearly every lineage shifts a little in hue and size each generation, so a colony
	# visibly diversifies and, given time, looks nothing like its founders
	if rng.randf() < 0.55:
		g.color = Color.from_hsv(fposmod(g.color.h + rng.randf_range(-0.045, 0.045), 1.0),
			clamp(g.color.s + rng.randf_range(-0.06, 0.06), 0.1, 0.95), clamp(g.color.v + rng.randf_range(-0.05, 0.05), 0.2, 0.95))
	if rng.randf() < 0.4:
		var sg: Dictionary = g.segments[rng.randi_range(0, g.segments.size() - 1)]
		sg["r"] = clamp(sg["r"] * rng.randf_range(0.9, 1.12), 12.0, 50.0)
	g._set_link(link_parent, carried, what)
	return g


static func _form_bias_sum(bias: Dictionary) -> float:
	var t := 0.0
	for fam in FORM_BIAS.keys():
		t += bias.get(FORM_BIAS[fam], 0.0)
	return t


# Swap one family to a new form; reverting to the classic form is less likely than
# a new specialisation. Only a change to a visible organ makes a lineage note.
func _mutate_form(rng: RandomNumberGenerator, bias: Dictionary) -> String:
	var fams = FORMS.keys()
	var fw := []
	for fam in fams:
		fw.append(1.0 + 2.0 * bias.get(FORM_BIAS[fam], 0.0) + (0.6 if form_visible(fam) else 0.0))
	var fam = _pick(rng, fams, fw)
	var before = form(fam)
	var n = FORMS[fam].size()
	var now = before
	if before != 0 and rng.randf() < 0.25:
		now = 0
	else:
		now = rng.randi_range(1, n - 1)
	forms[fam] = now
	if now == before or not form_visible(fam):
		return ""
	if now == 0:
		return "back to " + FORMS[fam][0]
	return ("grew " if fam in ["leg", "antenna", "acid"] else "") + FORMS[fam][now]


# Organ lines climb or drop one tier at a time. Gaining is likelier than losing once a
# line has started, so lines tend to keep building. Fusions gained or lost are noted.
func _mutate_organ(rng: RandomNumberGenerator, bias: Dictionary) -> String:
	var lines = ORGANS.keys()
	var lw := []
	for ln in lines:
		lw.append(1.0 + 2.0 * bias.get(ln, 0.0) + (1.5 if organ(ln) > 0 else 0.0))   # started lines keep building
	var ln = _pick(rng, lines, lw)
	var before_f = fusions()
	var t0 = organ(ln)
	var t1 = t0
	var r = rng.randf()
	if t0 == 0:
		if r < 0.5 + 0.15 * bias.get(ln, 0.0):
			t1 = 1
	elif t0 < 3 and r < 0.62 + 0.1 * bias.get(ln, 0.0):
		t1 = t0 + 1
	elif r > 0.8:
		t1 = t0 - 1
	if t1 == t0:
		return ""
	organs[ln] = t1
	var parts := []
	if t1 > t0:
		parts.append("evolved %s (%s)" % [ORGANS[ln][t1], ORGAN_SRC[ln][t1]])
	else:
		parts.append("lost " + ORGANS[ln][t0])
	var after_f = fusions()
	for id in after_f:
		if not id in before_f:
			parts.append("fused into " + FUSIONS[id]["name"])
	for id in before_f:
		if not id in after_f:
			parts.append("lost " + FUSIONS[id]["name"])
	return PoolStringArray(parts).join(", ")


func _mutate_morph(rng: RandomNumberGenerator, bias: Dictionary) -> String:
	var keys = MORPH_DEFAULT.keys()
	var kw := []
	for k in keys:
		kw.append(1.0 + bias.get(k, 0.0) * 2.0)
	var k = _pick(rng, keys, kw)
	var before = m(k)
	if k in MORPH_BOOL:
		# gaining a new organ is rarer than losing one
		if int(m(k)) == 0:
			if rng.randf() < 0.45 + 0.15 * bias.get(k, 0.0):
				morph[k] = 1
		elif rng.randf() < 0.55:
			morph[k] = 0
		if int(morph[k]) != int(before):
			return ("gained " if int(morph[k]) == 1 else "lost ") + MORPH_NAMES[k]
		return ""
	elif k == "petiole":
		morph[k] = 2 if int(m(k)) == 1 else 1
		return "%d-node waist" % int(morph[k])
	elif k == "pattern":
		morph[k] = rng.randi_range(0, 3)
		return "" if int(morph[k]) == int(before) else ["plain gaster", "banded gaster", "spotted gaster", "dark-tipped gaster"][int(morph[k])]
	morph[k] = clamp(float(m(k)) + rng.randf_range(-0.2, 0.3), 0.0, 1.0)
	if morph[k] < 0.08:
		morph[k] = 0.0
	# a continuous trait only counts as a visible change when it crosses 0.4
	var was = float(before) >= 0.4
	var now = float(morph[k]) >= 0.4
	if was == now:
		return ""
	return ("became " if now else "no longer ") + MORPH_NAMES[k]


# Lineage node of this plan: itself if its birth was a visible change (or it is a
# founder), else the node it inherited.
func node():
	return self if (note != "" or parent == null) else parent


func _set_link(link_parent, carried: String, what: String) -> void:
	parent = link_parent
	var parts := []
	for t in [carried, what]:
		if t != "":
			parts.append(t)
	note = PoolStringArray(parts).join(", ")
	# keep chains short: past LINEAGE_MAX nodes the oldest history is dropped
	var n = node()
	var depth := 0
	while n != null and n.parent != null:
		depth += 1
		if depth >= LINEAGE_MAX:
			n.parent = null
			break
		n = n.parent


# Nodes from the founder down to this plan: [oldest, ..., node()]
func ancestry() -> Array:
	var out := []
	var n = node()
	var guard := 0
	while n != null and guard < LINEAGE_MAX + 2:
		out.push_front(n)
		n = n.parent
		guard += 1
	return out


static func _pick(rng: RandomNumberGenerator, items: Array, weights: Array):
	var total := 0.0
	for x in weights:
		total += x
	var r = rng.randf() * total
	for i in items.size():
		r -= weights[i]
		if r <= 0.0:
			return items[i]
	return items[items.size() - 1]


# Short human-readable body description for the HUD.
func describe() -> String:
	var parts := []
	var limbs := {}
	var armor := 0
	var spikes := 0
	for s in segments:
		if s["limb"] != "":
			limbs[s["limb"]] = limbs.get(s["limb"], 0) + s["n"] * 2
		armor += s["armor"]
		spikes += s["spikes"]
	for k in limbs.keys():
		parts.append("%d %s%s" % [limbs[k], k, "" if limbs[k] == 1 else "s"])
	if armor > 0:
		parts.append("armor %d" % armor)
	if spikes > 0:
		parts.append("%d %s" % [spikes, "spike%s" % ("" if spikes == 1 else "s") if form("spike") == 0 else FORMS["spike"][form("spike")]])
	if form("leg") != 0 and form_visible("leg"):
		parts.append(FORMS["leg"][form("leg")])
	if form("antenna") != 0 and form_visible("antenna"):
		parts.append(FORMS["antenna"][form("antenna")])
	var jaw = head().get("jaw", "")
	if jaw != "":
		parts.append(jaw + " jaw")
	for k in ["wings", "stinger", "acid", "glow"]:
		if int(m(k)) == 1:
			var lbl = {"wings": "winged", "stinger": "stinger", "acid": "acid gland", "glow": "glowing"}[k]
			if k == "stinger" and form("sting") != 0:
				lbl = FORMS["sting"][form("sting")]
			elif k == "acid" and form("acid") != 0:
				lbl = FORMS["acid"][form("acid")]
			parts.append(lbl)
	if float(m("major")) >= 0.4:
		parts.append("big-headed")
	if float(m("replete")) >= 0.4:
		parts.append("replete")
	if float(m("camo")) >= 0.5:
		parts.append("camouflaged")
	for ln in ORGANS.keys():
		if organ(ln) > 0:
			parts.append(ORGANS[ln][organ(ln)])
	for id in fusions():
		parts.append(FUSIONS[id]["name"].to_upper())
	return "%d segments, " % segments.size() + PoolStringArray(parts).join(", ")
