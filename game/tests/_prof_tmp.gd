extends SceneTree
# temp: find what makes a single sim step slow (seed 22)
const Sim = preload("res://core/colony_sim.gd")
func _init():
	var sd = 22
	var until = 1600.0
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=")
		if kv[0] == "t": until = float(kv[1])
		if kv[0] == "seed": sd = int(kv[1])
	var sim = Sim.new(sd, "well_rounded")
	sim.prof = {}
	while sim.time < until and not sim.collapsed:
		var before = sim.prof.duplicate()
		var s0 = Time.get_ticks_usec()
		sim.step(0.1)
		var us = Time.get_ticks_usec() - s0
		if sim.shop_pending:
			sim.open_shop()
			var reserve = 30.0 + 0.6 * sim.ants.size()
			var nb = 0
			for i in sim.offers.size():
				if nb < 2 and sim.offers[i] != "" and sim.food - sim.price(sim.offers[i]) >= reserve:
					if sim.buy(i):
						nb += 1
			sim.shop_pending = false
		if us > 40000:
			var d := []
			for k in sim.prof.keys():
				var dv = sim.prof[k] - before.get(k, 0)
				if dv > 2000 and not k.begins_with("n_"):
					d.append("%s=%.1f" % [k, dv / 1000.0])
			print("t=%.1f step %.1f ms: %s" % [sim.time, us / 1000.0, ", ".join(d)])
	quit()
