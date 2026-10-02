extends SceneTree
const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
func _init():
	var t0 = OS.get_ticks_usec()
	var sim = Sim.new(11, "well_rounded")
	print("init ms: %.0f  grid W=%d" % [(OS.get_ticks_usec() - t0) / 1000.0, sim.grid.W])
	sim.prof = {}
	var maxd = 0
	var ex = int(sim.grid.entrance.x)
	var w0 = OS.get_ticks_usec()
	while sim.time < 600.0 and not sim.collapsed:
		sim.step(0.1 if sim.time > 200.0 else 0.05)
		if int(sim.time) == 60 and sim._beacon_cd <= 0.0:
			sim.place_beacon(ex + 200)
		if int(sim.time) == 100 and sim.ants.size() > 0 and sim.blessed_left == 0 and sim.mutagen > 0:
			sim.bless(sim.ants[0])
		for a in sim.ants:
			maxd = max(maxd, abs(a.x - ex))
		if sim.shop_pending and sim.hostile_count() == 0:
			sim.open_shop()
			for i in sim.offers.size():
				if sim.offers[i] != "" and sim.food - sim.price(sim.offers[i]) > 60.0:
					sim.buy(i)
					break
		if int(sim.time) % 60 == 0 and sim.time - int(sim.time) < 0.06:
			print("t=%d pop=%d food=%.0f raid=%d piles=%d maxdist=%d deliv=%s mut=%d goals=%d beacons=%d" % [sim.time, sim.ants.size(), sim.food, sim.raid_n, sim.piles.size(), maxd, str(sim.stat_deliv), sim.mutagen, sim.goals_done.size(), sim.beacons.size()])
	var wall = (OS.get_ticks_usec() - w0) / 1000.0
	print("DONE sim_s=%.0f wall_ms_per_simsec=%.1f collapsed=%s blessed_left=%d" % [sim.time, wall / sim.time, str(sim.collapsed), sim.blessed_left])
	var parts = []
	for k in sim.prof.keys():
		parts.append("%s=%.1f" % [k, sim.prof[k] / 1000.0 / sim.time])
	print("PERF ", " ".join(parts))
	for t in sim.toasts:
		print("TOAST ", t["text"])
	quit()
