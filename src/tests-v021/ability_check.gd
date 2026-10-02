extends SceneTree
# v0.21 organ abilities in a live colony: -- <sim_seconds> <seed> <mode>
# mode 0 = control (no organs), 1 = at 150 s half the colony is rebuilt with tier-3 organs
# and all four fusions. Counts ability effects, kills, deaths, queen HP, toasts.
const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
func _init() -> void:
	var args = OS.get_cmdline_args()
	var i = args.find("--")
	var secs = float(args[i + 1])
	var sim = Sim.new(int(args[i + 2]))
	var mode = int(args[i + 3])
	var t = 0.0
	var injected = false
	var cnt = {}
	var ms = OS.get_ticks_msec()
	while t < secs and not sim.collapsed:
		sim.step(0.05)
		t += 0.05
		if sim.shop_pending:
			sim.shop_pending = false
		if mode == 1 and not injected and t >= 150.0:
			injected = true
			var plans = {}
			var k = 0
			for a in sim.ants:
				k += 1
				if k % 2 == 0:
					continue
				var u = a.genome.uid
				if not plans.has(u):
					var g = a.genome.copy()
					for ln in ["sonic", "electric", "shell", "silk", "tongue", "regen"]:
						g.organs[ln] = 3
					g.note = "test: all organs"
					sim.register_genome(g, a.gen)
					plans[u] = g
				a.genome = plans[u]
				a.ph = sim.phenotype(a.genome)
				a.hp = a.ph["hp"]
			print("injected into %d ants, %d plans, fusions %s" % [int(sim.ants.size() / 2), plans.size(), str(plans.values()[0].fusions())])
		for f in sim.fx:
			if not f.has("seen"):
				f["seen"] = true
				var key = f["kind"] if f["kind"] != "text" else "text:" + str(f.get("text", ""))
				if key in ["wave", "arc", "beam", "web", "text:CURL", "text:SPLITS"]:
					cnt[key] = cnt.get(key, 0) + 1
	print("mode %d seed %s t %.0f  ants %d  raid %d  kills %d  died_combat %d  queen %.0f/%.0f  collapsed %s  %.1fs wall" % [mode, args[i + 2], t, sim.ants.size(), sim.raid_n, sim.kills, sim.died_combat, sim.queen_hp, sim.queen_max, str(sim.collapsed), (OS.get_ticks_msec() - ms) / 1000.0])
	print("ability fx: ", cnt)
	var with = 0
	for a in sim.ants:
		if not a.genome.fusions().empty():
			with += 1
	print("ants carrying a fusion at end: ", with)
	var peak = {}
	for e in sim.evo_log:
		for k in ["sonic", "electric", "shell", "silk", "tongue", "regen", "fusion"]:
			peak[k] = max(peak.get(k, 0.0), e["share"][k])
	print("peak organ share: ", peak)
	var tiers = {}
	for a in sim.ants:
		for ln in a.genome.organs.keys():
			if a.genome.organs[ln] > 0:
				var key = "%s%d" % [ln, a.genome.organs[ln]]
				tiers[key] = tiers.get(key, 0) + 1
	print("tiers alive at end: ", tiers)
	for x in sim.toasts:
		print("  toast: ", x["text"])
	quit()
