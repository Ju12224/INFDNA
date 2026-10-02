extends SceneTree
const G = preload("res://mods-unpacked/Judah-InfDNA/core/genome.gd")
const PH = preload("res://mods-unpacked/Judah-InfDNA/core/phenotype.gd")
func _init():
	var rng = RandomNumberGenerator.new(); rng.seed = 7
	var notes = {}
	var forms_seen = {}
	var g = G.make_ant()
	var minc = 99.0
	var organ_seen = {}
	var fusion_seen = {}
	var abil_n = 0
	for i in 20000:
		var bias = {} if i % 3 else {"leg": 1.0, "spike": 1.0, "stinger": 1.0, "acid": 1.0, "eyes": 1.0, "organ": 0.8, "sonic": 1.6, "silk": 1.6, "shell": 1.6}
		g = g.mutated(rng, bias)
		g.uid = i + 1
		if g.note != "":
			for part in g.note.split(", "):
				notes[part] = notes.get(part, 0) + 1
		for f in g.forms.keys():
			forms_seen["%s=%d" % [f, g.forms[f]]] = true
		for ln in g.organs.keys():
			organ_seen["%s%d" % [ln, g.organs[ln]]] = true
		for fid in g.fusions():
			fusion_seen[fid] = fusion_seen.get(fid, 0) + 1

		var ph = PH.compute(g)
		if ph["abil"]:
			abil_n += 1
		minc = min(minc, ph["carry"])
		g.describe()
		if i % 400 == 0:
			g = G.make_ant()
	var keys = notes.keys(); keys.sort()
	for k in keys:
		for fam in G.FORMS.keys():
			if k in G.FORMS[fam] or k.ends_with(G.FORMS[fam][0]) or k.begins_with("grew") and k.substr(5) in G.FORMS[fam]:
				print("NOTE ", k, " ", notes[k]); break
	print("forms seen: ", forms_seen.size(), " min carry ", minc)
	var ok = organ_seen.keys(); ok.sort()
	print("organ tiers seen (%d): %s" % [ok.size(), str(ok)])
	print("fusion genomes: ", fusion_seen, "  genomes with abilities: ", abil_n)
	var fn = 0
	for k in notes.keys():
		if k.begins_with("evolved") or k.begins_with("fused") or k.begins_with("lost "):
			fn += notes[k]
	print("organ/fusion notes: ", fn)
	quit()
