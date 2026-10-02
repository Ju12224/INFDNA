extends SceneTree
# Headless balance probe (rebuilt: the original tests/bal_probe.gd was not in the source zip).
# env: SEED, MINS (default 20), QUEEN (default well_rounded), BOT (balanced|none), STEP (default 0.05)
# Output: TL rows (one per sim-minute), ROW (final), PERF (wall ms per sim-second, section split)

const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")

func _env(k, d):
	var v = OS.get_environment(k)
	return d if v == "" else v

func _init():
	var seed_v = int(_env("SEED", "11"))
	var mins = float(_env("MINS", "20"))
	var queen = _env("QUEEN", "well_rounded")
	var bot = _env("BOT", "balanced")
	var step = float(_env("STEP", "0.05"))
	var sim = Sim.new(seed_v, queen)
	sim.prof = {}
	var peak = 0
	var peak_t = 0.0
	var min_qhp = sim.queen_hp
	var next_tl = 60.0
	var w0 = OS.get_ticks_usec()
	var end_t = mins * 60.0
	var buys = 0
	var dead_at = -1.0
	while sim.time < end_t and not sim.collapsed:
		sim.step(step)
		if bot == "balanced" and sim.shop_pending and sim.hostile_count() == 0:
			sim.open_shop()
			var reserve = 30.0 + 0.6 * sim.ants.size()
			var n_buy = 0
			var order = range(sim.offers.size())
			for i in order:
				if n_buy >= 2:
					break
				var id = sim.offers[i]
				if id == "":
					continue
				if sim.food - sim.price(id) >= reserve:
					if sim.buy(i):
						n_buy += 1
						buys += 1
		if sim.ants.size() > peak:
			peak = sim.ants.size()
			peak_t = sim.time
		min_qhp = min(min_qhp, sim.queen_hp)
		if sim.time >= next_tl:
			next_tl += 60.0
			var tc = sim.task_counts()
			var cc = sim.caste_counts()
			print("TL,%d,%d,%d,%.0f,%d,%d,%d,%.0f,F%d,D%d,N%d,H%d,X%d,c%d_%d_%d,old%d,starve%d,comb%d,kills%d" % [
				seed_v, int(sim.time), sim.ants.size(), sim.food, sim.eggs.size(), sim.raid_n, sim.hostile_count(), sim.queen_hp,
				tc[1], tc[2], tc[0], tc[3], tc[4], cc[0], cc[1], cc[2],
				sim.deaths["old"], sim.deaths["starve"], sim.deaths["combat"], sim.kills])
	var wall = (OS.get_ticks_usec() - w0) / 1000.0
	var simsec = max(1.0, sim.time)
	print("ROW,%d,%d,%s,%s,%d,%d,%d,%d,%d,%.0f,%.0f,buys%d" % [seed_v, int(sim.time), str(sim.collapsed), sim.collapse_reason, sim.ants.size(), peak, int(peak_t), sim.raid_n, sim.died, min_qhp, sim.queen_hp, buys])
	print("LEDGER,%d,%s,deliv=%.0f,born=%d,died=%d" % [seed_v, str(sim.ledger), sim.delivered_total, sim.born, sim.died])
	var parts = []
	for k in sim.prof.keys():
		parts.append("%s=%.1f" % [k, sim.prof[k] / 1000.0 / simsec])
	print("PERF,%d,ms_per_simsec=%.1f,%s" % [seed_v, wall / simsec, " ".join(parts)])
	quit()
