extends SceneTree
# Runs colonies with no screen and prints how they do. A simple bot buys Lab offers so the run goes like a real one.
# Run: godot --headless --path game --script res://tests/sim_run.gd -- seeds=1,2,3 t=1800 queen=well_rounded
# Prints a line per colony every 300 sim seconds, then a summary with the slowest single step (a freeze shows up there).

const Sim = preload("res://core/colony_sim.gd")


func _init() -> void:
	var args := {"seeds": "11,22,33", "t": "1800", "queen": "well_rounded", "every": "300"}
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	for k in args.keys():                     # or as environment variables (SEEDS=1,2 T=600)
		if OS.get_environment(k.to_upper()) != "":
			args[k] = OS.get_environment(k.to_upper())
	var until = float(args["t"])
	var every = float(args["every"])
	for sd in str(args["seeds"]).split(","):
		var t0 = Time.get_ticks_usec()
		var sim = Sim.new(int(sd), args["queen"])
		var made_us = Time.get_ticks_usec() - t0
		var worst_us := 0
		var worst_at := 0.0
		var steps := 0
		var total_us := 0
		var next_report: float = every
		while sim.time < until and not sim.collapsed:
			var s0 = Time.get_ticks_usec()
			sim.step(0.1)
			var us = Time.get_ticks_usec() - s0
			total_us += us
			steps += 1
			if us > worst_us:
				worst_us = us
				worst_at = sim.time
			_bot(sim)
			if sim.time >= next_report:
				next_report += every
				_report(sd, sim)
		_report(sd, sim)
		print("seed %s done: %s at %.0fs | made in %.0f ms | steps %d avg %.2f ms, slowest %.0f ms at %.0fs" % [sd, "COLLAPSED" if sim.collapsed else "alive", sim.time, made_us / 1000.0, steps, total_us / 1000.0 / max(steps, 1), worst_us / 1000.0, worst_at])
	quit()


func _report(sd, sim) -> void:
	print("seed %s t=%5.0f ants=%4d eggs=%3d food=%6.0f raids=%2d enemies=%3d apex=%2d monstrosity=%5.1f arc=%s cols=%d" % [sd, sim.time, sim.ants.size(), sim.eggs.size(), sim.food, sim.raid_n, sim.enemies.size(), sim.apex.size(), sim.monstrosity, str(sim.arc_stage), sim.grid.W])


func _bot(sim) -> void:
	if sim.shop_pending:
		sim.open_shop()
		var reserve = 30.0 + 0.6 * sim.ants.size()
		var nb = 0
		for i in sim.offers.size():
			if nb < 2 and sim.offers[i] != "" and sim.food - sim.price(sim.offers[i]) >= reserve:
				if sim.buy(i):
					nb += 1
		sim.shop_pending = false
