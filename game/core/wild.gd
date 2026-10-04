extends RefCounted
# The Wild: history as the world. When a colony falls, its champion strain is not lost; it escapes into the Wild and keeps evolving.
# The next colony's rival, the nest out on the meadow, is the strongest such line: your own old ants, evolved without you, wearing
# your old body plan and carrying your old organs. Beat them and you take their best trait back (a batch of eggs born with it) and the
# line ends. Leave them be and they come back stronger next run. Everything you bred well is your future enemy.
#
# Saved in user://infdna_wild.json: {"use": bool, "next_id": n, "lines": [line, ...]}. A line is
#   {"id", "title", "queen", "genome", "plan", "raids", "time", "peak", "gens", "runs"}
# where "genome" is genome_to_dict() of the champion, and "runs" counts the runs it has survived since. If the file cannot be read or
# written the game simply has no Wild (the first rival is the plain red ants).

const Genome = preload("res://core/genome.gd")
const Phenotype = preload("res://core/phenotype.gd")
const PATH = "user://infdna_wild.json"
const KEEP = 6                         # lines kept; the weakest is forgotten
const KIN_UID = 900000                 # sprite-cache keys of kin genomes: never collide with the colony's own uids

const NOUNS = ["Marchers", "Reapers", "Wardens", "Harriers", "Drifters", "Delvers", "Stalkers", "Chargers"]
const ORGAN_ADJ = {"sonic": "Echoing", "electric": "Sparking", "shell": "Shelled", "silk": "Weaving", "tongue": "Lashing", "regen": "Mending"}
const FUSION_ADJ = {"thunderclap": "Thunder", "slingshot": "Slinging", "fortress": "Fortress", "sonarweb": "Sonar"}
const MORPH_ADJ = {"wings": "Winged", "acid": "Acid", "stinger": "Stinging", "glow": "Glowing"}
const INT_SEG_KEYS = ["n", "armor", "spikes", "eyes"]


# ------------------------------------------------------------------ the file
static func _load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var res = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return res if res is Dictionary else {}


static func _store(d: Dictionary) -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


static func lines() -> Array:
	var ls = _load().get("lines", [])
	return ls if ls is Array else []


static func is_on() -> bool:
	return bool(_load().get("use", true))


static func set_use(on: bool) -> void:
	var d = _load()
	d["use"] = on
	_store(d)


static func clear() -> void:
	_store({})


static func score(r: Dictionary) -> float:
	return float(r.get("raids", 0)) * 10.0 + float(r.get("time", 0.0)) / 60.0 + 3.0 * float(r.get("runs", 0))


# The line the next colony will meet: the strongest one ({} when there is none, or the Wild is switched off).
static func active() -> Dictionary:
	if not is_on():
		return {}
	var best := {}
	var bs := -1.0
	for r in lines():
		if r is Dictionary and r.has("genome"):
			var s = score(r)
			if s > bs:
				bs = s
				best = r
	return best


# ------------------------------------------------------------------ genomes <-> JSON
static func genome_to_dict(g) -> Dictionary:
	return {"color": g.color.to_html(false), "segments": g.segments.duplicate(true), "traits": g.traits.duplicate(),
		"morph": g.morph.duplicate(), "forms": g.forms.duplicate(), "organs": g.organs.duplicate()}


# JSON has no integers: everything the sim indexes or compares as a whole number is turned back into one.
static func genome_from_dict(d: Dictionary):
	var g = Genome.make_ant()
	g.color = Color("#" + str(d.get("color", "8a4b2e")).trim_prefix("#"))
	var segs := []
	for s in d.get("segments", []):
		if not (s is Dictionary):
			continue
		var c := {}
		for k in s.keys():
			var v = s[k]
			if k in INT_SEG_KEYS:
				v = int(v)
			c[str(k)] = v
		for k in ["r", "len"]:
			c[k] = float(c.get(k, 0.0))
		c["limb"] = str(c.get("limb", ""))
		for k in INT_SEG_KEYS:
			if k != "eyes" or c.get("head", false):
				c[k] = int(c.get(k, 0))
		segs.append(c)
	if segs.size() >= 2 and segs.size() <= Genome.MAX_SEGMENTS:
		g.segments = segs
	var tr = d.get("traits", {})
	if tr is Dictionary:
		for k in g.traits.keys():
			if tr.has(k):
				g.traits[k] = clamp(float(tr[k]), 0.02, 1.0)
	var mo = d.get("morph", {})
	if mo is Dictionary:
		for k in mo.keys():
			var v2 = mo[k]
			g.morph[str(k)] = int(v2) if (str(k) in Genome.MORPH_BOOL or str(k) in ["petiole", "pattern"]) else float(v2)
	var fo = d.get("forms", {})
	if fo is Dictionary:
		for k in fo.keys():
			if Genome.FORMS.has(str(k)):
				g.forms[str(k)] = int(clamp(int(fo[k]), 0, Genome.FORMS[str(k)].size() - 1))
	var og = d.get("organs", {})
	if og is Dictionary:
		for k in og.keys():
			if Genome.ORGANS.has(str(k)):
				g.organs[str(k)] = int(clamp(int(og[k]), 0, 3))
	return g


# ------------------------------------------------------------------ names
static func species_name(g) -> String:
	var adj := ""
	var fu = g.fusions()
	if not fu.is_empty():
		adj = FUSION_ADJ.get(fu[0], "Strange")
	if adj == "":
		for ln in ORGAN_ADJ.keys():
			if g.organ(ln) >= 2:
				adj = ORGAN_ADJ[ln]
				break
	if adj == "":
		for k in MORPH_ADJ.keys():
			if int(g.m(k)) == 1:
				adj = MORPH_ADJ[k]
				break
	var armor := 0
	var spikes := 0
	var legs := 0
	for s in g.segments:
		armor += int(s.get("armor", 0))
		spikes += int(s.get("spikes", 0))
		if s.get("limb", "") == "leg":
			legs = int(max(legs, int(s.get("n", 0))))
	if adj == "" and spikes >= 3:
		adj = "Thorned"
	if adj == "" and armor >= 3:
		adj = "Plated"
	if adj == "" and float(g.m("major")) >= 0.5:
		adj = "Bigjawed"
	if adj == "" and float(g.m("camo")) >= 0.5:
		adj = "Veiled"
	if adj == "" and legs >= 4:
		adj = "Many-legged"
	if adj == "":
		adj = "Common"
	return "%s %s" % [adj, NOUNS[posmod(g.describe().hash(), NOUNS.size())]]


# ------------------------------------------------------------------ kin stats
# What a kin ant is worth next to a plain ant: ratios of the body's own numbers, squeezed into a narrow band so the descendants of a
# monster colony are a sharper enemy, not an impossible one. (hp, bite, speed, and the share of an ant's own bites they shrug off.)
static func kin_mods(g) -> Dictionary:
	var ph = Phenotype.compute(g)
	var base = Phenotype.compute(Genome.make_ant())
	return {
		"hp_k": clamp(pow(float(ph["hp"]) / float(base["hp"]), 0.55), 0.85, 1.35),
		"dmg_k": clamp(pow(float(ph["attack"]) / max(0.2, float(base["attack"])), 0.55), 0.85, 1.35),
		"speed_k": clamp(float(ph["speed"]) / float(base["speed"]), 0.85, 1.25),
		"armor": clamp(float(ph["armor_red"]) * 0.7, 0.0, 0.25),
	}


# How strong a body is, as one number (used to pick the fitter of a few mutants).
static func power(g) -> float:
	var m = kin_mods(g)
	return float(m["hp_k"]) * float(m["dmg_k"]) * (1.0 + 2.0 * float(m["armor"])) * pow(float(m["speed_k"]), 0.5)


# ------------------------------------------------------------------ the end of a run
# The strain that goes into the Wild: the most evolved body the colony ended with (its champion and the plans it had most of when it fell,
# scored by how strong the body is and how many visible changes lie behind it). Often the champion is just the founders' own plan, which
# says nothing about what the colony became, so that plan is only the last resort.
static func pick_ancestor(sim):
	var pool := []
	if sim.champion != null:
		pool.append(sim.champion)
	for e in sim.top_genomes(6):
		pool.append(e["genome"])
	var best = null
	var bs := -1.0
	for g in pool:
		if g.uid == sim.founder_genome.uid or g.uid == sim.queen_genome.uid:
			continue
		var sc = power(g) * (1.0 + 0.1 * g.ancestry().size())
		if sc > bs:
			bs = sc
			best = g
	if best != null:
		return best
	return sim.champion if sim.champion != null else sim.founder_genome


static func line_from(sim, queen_name: String, id: int) -> Dictionary:
	var g = pick_ancestor(sim)
	return {"id": id, "title": species_name(g), "queen": queen_name, "genome": genome_to_dict(g), "plan": g.describe(),
		"raids": sim.raid_n, "time": sim.time, "peak": sim.peak_ants, "gens": sim.max_gen, "runs": 0}


# Called once when a colony falls. Returns what the player should be told (a line per thing that happened).
static func finish_run(sim, queen_name: String) -> Array:
	var msgs := []
	if not is_on():
		return msgs
	var d = _load()
	var ls: Array = d.get("lines", [])
	if not (ls is Array):
		ls = []
	var next_id = int(d.get("next_id", 1))
	# the line this colony met on the meadow: broken for good, or evolved on a step further
	if not sim.kin.is_empty() and sim.rival.genome != null:
		for i in ls.size():
			if int(ls[i].get("id", -1)) == int(sim.kin.get("id", -2)):
				var title = str(ls[i].get("title", "the Kin"))
				if sim.rival.conquered > 0:
					msgs.append("You broke the %s of colony #%d for good. That line is extinct." % [title, int(ls[i]["id"])])
					ls.remove_at(i)
				else:
					ls[i]["genome"] = genome_to_dict(sim.rival.genome)
					ls[i]["plan"] = sim.rival.genome.describe()
					ls[i]["runs"] = int(ls[i].get("runs", 0)) + 1
					msgs.append("The %s of colony #%d were never broken. They go on evolving without you." % [title, int(ls[i]["id"])])
				break
	# this colony's champion strain escapes into the Wild
	var line = line_from(sim, queen_name, next_id)
	ls.append(line)
	next_id += 1
	while ls.size() > KEEP:
		var worst = 0
		for i in ls.size():
			if score(ls[i]) < score(ls[worst]):
				worst = i
		ls.remove_at(worst)
	d["lines"] = ls
	d["next_id"] = next_id
	_store(d)
	msgs.append("Your champion strain, the %s (colony #%d), escapes into the Wild. Your next rival may be their child." % [line["title"], int(line["id"])])
	return msgs
