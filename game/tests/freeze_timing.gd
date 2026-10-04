extends SceneTree
# Times the two things that used to freeze a frame: growing the sim range (WorldGrid.ensure_cols, spread over
# grow_step()) and building a chunk's ground images (WorldGrid.chunk_images). Prints the slowest single call of each.
# Run: godot --headless --path game --script res://tests/freeze_timing.gd

const WorldGrid = preload("res://core/world_grid.gd")


func _init() -> void:
	var g = WorldGrid.new(260, 225, 12345)
	var t0 = Time.get_ticks_usec()
	g.rebuild_nav()
	print("rebuild_nav: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	# growth: walk a unit out to the right and the left, one cell per call, as the sim would every second
	var worst := 0
	var calls := 0
	for side in [1, -1]:
		var x = g.sim_r() - 200 if side == 1 else g.sim_l() + 200
		for i in 400:
			x += side
			var s0 = Time.get_ticks_usec()
			if g.has_method("grow_step"):
				g.grow_step()
			g.ensure_cols(min(x, 130), max(x, 130))
			if g.nav_dirty:
				g.rebuild_nav()
			var us = Time.get_ticks_usec() - s0
			worst = max(worst, us)
			calls += 1
			if x < g.sim_l() + WorldGrid.MARGIN or x > g.sim_r() - WorldGrid.MARGIN:
				print("ERROR: x=%d outside the sim range %d..%d" % [x, g.sim_l(), g.sim_r()])
	print("growth: cols=%d, slowest step %.1f ms over %d calls (rebuild_nav included when dirty)" % [g.W, worst / 1000.0, calls])
	# ground images: chunks in the sim range and far outside it
	var worst_in := 0
	var worst_far := 0
	var sum := 0
	var n := 0
	for k in range(-30, 40):
		var s1 = Time.get_ticks_usec()
		g.chunk_images(k)
		var us = Time.get_ticks_usec() - s1
		var x0 = k * WorldGrid.CHUNK
		if x0 + WorldGrid.CHUNK > g.sim_l() and x0 < g.sim_r():
			worst_in = max(worst_in, us)
		else:
			worst_far = max(worst_far, us)
		sum += us
		n += 1
	print("chunk_images: slowest in sim %.1f ms, far %.1f ms, mean %.1f ms" % [worst_in / 1000.0, worst_far / 1000.0, sum / 1000.0 / n])
	quit()
