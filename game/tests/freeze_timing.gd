extends SceneTree
# Times the things that used to freeze a frame: building the world (WorldGrid.new: the whole fixed-width world at once
# when a colony starts), building a chunk's ground images (WorldGrid.chunk_images, at most ~8 ms of it per frame in the
# soil view), repainting them after a dig, and the distance fields. Also prints what the grid holds in memory.
# Run: godot --headless --path game --script res://tests/freeze_timing.gd [-- t=600]
#   t > 0 runs a colony that long first (seed 11) and times the images of its grid, tunnels and all.

const WorldGrid = preload("res://core/world_grid.gd")
const Sim = preload("res://core/colony_sim.gd")


func _ms(us: int) -> String:
	return "%.1f ms" % (us / 1000.0)


func _init() -> void:
	var args := {"t": "0", "seed": "11"}
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var m0 = OS.get_static_memory_usage()
	var t0 = Time.get_ticks_usec()
	var g = WorldGrid.new(260, 225, 12345)
	var build_us = Time.get_ticks_usec() - t0
	var m1 = OS.get_static_memory_usage()
	print("world build: %s for %d columns (%d chunks), %.1f MB" % [_ms(build_us), g.W, g.W / WorldGrid.CHUNK, (m1 - m0) / 1048576.0])
	if float(args["t"]) > 0.0:
		var sim = Sim.new(int(args["seed"]), "well_rounded")
		while sim.time < float(args["t"]) and not sim.collapsed:
			sim.step(0.1)
		g = sim.grid
		g._chunk_img.clear()
		print("colony run to t=%.0f: %d ants, %d cells dug" % [sim.time, sim.ants.size(), g.open_under])
	else:
		# a nest's worth of tunnels in both planes, so the images have digging to show
		var ex = int(g.entrance.x)
		for i in 160:
			var x = ex - 80 + i
			g.carve(x, g.chamber.y + 6 + (i % 9), 1.6, i % 2)
			g.carve(ex + (i % 40) - 20, g.chamber.y + 10 + i / 4, 1.4, 0)
	t0 = Time.get_ticks_usec()
	g.rebuild_nav()
	print("rebuild_nav: %s" % _ms(Time.get_ticks_usec() - t0))
	# ground images of every chunk of the world, cold
	var worst := 0
	var worst_k := 0
	var sum := 0
	var n := 0
	var m2 = OS.get_static_memory_usage()
	for k in range(WorldGrid.chunk_of(g.sim_l()), WorldGrid.chunk_of(g.sim_r()) + 1):
		var s1 = Time.get_ticks_usec()
		g.chunk_images(k)
		var us = Time.get_ticks_usec() - s1
		if us > worst:
			worst = us
			worst_k = k
		sum += us
		n += 1
	var m3 = OS.get_static_memory_usage()
	print("chunk_images: %d chunks, slowest %s (chunk %d, nest is in %d), mean %s, all cached %.1f MB" % [n, _ms(worst), worst_k,
		WorldGrid.chunk_of(int(g.entrance.x)), _ms(sum / n), (m3 - m2) / 1048576.0])
	# beyond the world's edge (only the padding of the edge chunks is ever drawn there)
	var s2 = Time.get_ticks_usec()
	g.chunk_images(WorldGrid.chunk_of(g.sim_r()) + 3)
	print("chunk_images outside the world: %s" % _ms(Time.get_ticks_usec() - s2))
	# a dig repaints the cached images around it
	var worst_dig := 0
	var ey = int(g.chamber.y) + 30
	for i in 40:
		var s3 = Time.get_ticks_usec()
		g.carve(int(g.entrance.x) - 20 + i, ey, 1.6, 0)
		worst_dig = max(worst_dig, Time.get_ticks_usec() - s3)
	print("carve + repaint: slowest %s" % _ms(worst_dig))
	print("static memory in use: %.1f MB" % (OS.get_static_memory_usage() / 1048576.0))
	quit()
