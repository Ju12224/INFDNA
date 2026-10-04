extends SceneTree
const Sim = preload("res://core/colony_sim.gd")
func _init() -> void:
	for sd in [11, 22]:
		var sim = Sim.new(sd, "well_rounded")
		var nxt = 300.0
		while sim.time < 2400.0 and not sim.collapsed:
			sim.step(0.1)
			if sim.time >= nxt:
				nxt += 300.0
				print("seed %d t=%.0f deliv=%.0f repelled=%d raids=%d peak=%d kills=%d gen=%d winters=%d ms=%.0f arc=%d food=%.0f" % [sd, sim.time, sim.delivered_total, sim.raids_repelled, sim.raid_n, sim.peak_ants, sim.kills, sim.max_gen, sim.winters, sim.monstrosity, sim.arc_stage, sim.food])
		print("seed %d end collapsed=%s %s" % [sd, sim.collapsed, sim.collapse_reason])
	quit()
