extends RefCounted
# Legacy between runs. When a colony falls, its champion strain (the body plan that once outnumbered the rest) can hand ONE
# trait down to the next queen: every founder ant of the next colony is born with it. The choice is kept in
# user://infdna_legacy.json until the player picks another. Everything is optional: if the file cannot be read or written
# the game simply has no heirloom.
#
# An heirloom is {"kind", "key", "value", "label", "from"}:
#   morph - an anatomy gene (stinger, acid, wings, glow, hair, major, replete, camo, phero)
#   organ - the first tier of an organ line (sonic, electric, shell, silk, tongue, regen)
#   form  - a part form (jumping hind legs, hooked barbs, ...)
#   legs  - one more pair of legs      armor - 1 plating on every segment      spikes - spines on the abdomen
#   size  - a little bigger            trait - an instinct nudge               mods - the veteran stock fallback

const Genome = preload("res://core/genome.gd")
const PATH = "user://infdna_legacy.json"

const MORPH_LABEL = {
	"stinger": "Born with a stinger", "acid": "Born with acid glands", "wings": "Born with wings", "glow": "Born with glow spots",
	"hair": "Born hairy", "major": "Born big-headed", "replete": "Born plump (honey gaster)", "camo": "Born camouflaged", "phero": "Born strong-scented",
}
const TRAIT_LABEL = {
	"forage_t": ["Instinct: forages at weaker hunger", -0.08], "dig_t": ["Instinct: digs without being crowded", -0.08],
	"defend_t": ["Instinct: joins fights sooner", -0.08], "dig_down": ["Instinct: digs straight down", 0.1], "explore": ["Instinct: pushes outward", 0.1],
}


static func _load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var res = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return res if res is Dictionary else {}


static func _store(d: Dictionary) -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


# The saved heirloom (empty if none), whether or not it is switched on.
static func saved() -> Dictionary:
	var d = _load()
	var h = d.get("heirloom")
	return h if h is Dictionary else {}


# The heirloom the next colony will actually carry ({} when none, or when the player switched it off).
static func active() -> Dictionary:
	var d = _load()
	if not bool(d.get("use", true)):
		return {}
	return saved()


static func is_on() -> bool:
	return bool(_load().get("use", true))


static func save(h: Dictionary) -> void:
	_store({"heirloom": h, "use": true})


static func set_use(on: bool) -> void:
	var d = _load()
	d["use"] = on
	_store(d)


static func clear() -> void:
	_store({})


# What the champion strain `g` has that the founders `founder` lack, most remarkable first (organs, forms, anatomy, then body).
# `from` says where it came from, for the queen card. Never empty: a colony that stayed plain still leaves veteran stock.
static func candidates(g, founder, from: String) -> Array:
	var out := []
	if g != null:
		for line in Genome.ORGANS.keys():
			var t = g.organ(line)
			if t >= 1 and founder.organ(line) < 1:
				out.append({"kind": "organ", "key": line, "value": 1, "label": "Born with a %s (%s)" % [Genome.ORGANS[line][1], Genome.ORGAN_SRC[line][1]]})
		for fam in Genome.FORMS.keys():
			var fi = g.form(fam)
			if fi > 0 and founder.form(fam) == 0:
				out.append({"kind": "form", "key": fam, "value": fi, "label": "Born with " + Genome.FORMS[fam][fi]})
		for k in Genome.MORPH_BOOL:
			if int(g.m(k)) == 1 and int(founder.m(k)) == 0:
				out.append({"kind": "morph", "key": k, "value": 1, "label": MORPH_LABEL[k]})
		for k in ["major", "replete", "camo", "phero", "hair"]:
			if float(g.m(k)) >= 0.5 and float(founder.m(k)) < 0.3:
				out.append({"kind": "morph", "key": k, "value": 0.7, "label": MORPH_LABEL[k]})
		var legs_g = _legs(g)
		if legs_g > _legs(founder):
			out.append({"kind": "legs", "key": "", "value": 1, "label": "An extra pair of legs (%d legs)" % (2 * (_legs(founder) + 1))})
		if _armor(g) > _armor(founder):
			out.append({"kind": "armor", "key": "", "value": 1, "label": "Born armored (plating on every segment)"})
		if _spikes(g) > _spikes(founder):
			out.append({"kind": "spikes", "key": "", "value": 1, "label": "Born spiny (spines on the abdomen)"})
		if _size(g) > _size(founder) * 1.1:
			out.append({"kind": "size", "key": "", "value": 1.08, "label": "Born bigger (+8% body)"})
		for k in TRAIT_LABEL.keys():
			var d = float(g.traits.get(k, 0.5)) - float(founder.traits.get(k, 0.5))
			var want = float(TRAIT_LABEL[k][1])
			if d * want > 0.0 and abs(d) >= 0.12:
				out.append({"kind": "trait", "key": k, "value": want, "label": TRAIT_LABEL[k][0]})
	if out.size() < 2:
		out.append({"kind": "mods", "key": "", "value": 0.06, "label": "Veteran stock (+6% HP and attack)"})
	for h in out:
		h["from"] = from
	return out.slice(0, 3)


static func apply(h: Dictionary, g) -> void:
	match str(h.get("kind", "")):
		"morph":
			g.morph[h["key"]] = h["value"]
		"organ":
			g.organs[h["key"]] = int(max(g.organ(h["key"]), int(h["value"])))
		"form":
			g.forms[h["key"]] = int(h["value"])
		"legs":
			for s in g.segments:
				if s.get("limb", "") == "leg":
					s["n"] = int(min(5, int(s["n"]) + 1))
					break
		"armor":
			for s in g.segments:
				s["armor"] = int(max(int(s.get("armor", 0)), 1))
		"spikes":
			g.segments[0]["spikes"] = int(max(int(g.segments[0].get("spikes", 0)), 1))
		"size":
			for s in g.segments:
				s["r"] = float(s["r"]) * float(h["value"])
		"trait":
			g.traits[h["key"]] = clamp(float(g.traits[h["key"]]) + float(h["value"]), 0.02, 1.0)


static func _legs(g) -> int:
	var best := 0
	for s in g.segments:
		if s.get("limb", "") == "leg":
			best = int(max(best, int(s.get("n", 0))))
	return best


static func _armor(g) -> int:
	var best := 0
	for s in g.segments:
		best = int(max(best, int(s.get("armor", 0))))
	return best


static func _spikes(g) -> int:
	var best := 0
	for s in g.segments:
		best = int(max(best, int(s.get("spikes", 0))))
	return best


static func _size(g) -> float:
	var sum := 0.0
	for s in g.segments:
		sum += float(s.get("r", 0.0))
	return sum
