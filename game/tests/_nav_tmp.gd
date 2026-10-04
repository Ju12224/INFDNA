extends SceneTree
# temp: time the distance fields on the full-width world with a dug nest, and print a checksum of them
const WorldGrid = preload("res://core/world_grid.gd")
func _init():
	var g = WorldGrid.new(260, 225, 12345)
	var ex = int(g.entrance.x)
	for i in 160:
		var x = ex - 80 + i
		g.carve(x, g.chamber.y + 6 + (i % 9), 1.6, i % 2)
		g.carve(ex + (i % 40) - 20, g.chamber.y + 10 + i / 4, 1.4, 0)
	for i in 40:
		g.make_link(ex - 60 + i * 3, int(g.chamber.y) + 9, 1)
	var best = 1e9
	var bt = 1e9
	for rep in 6:
		var t0 = Time.get_ticks_usec()
		g.rebuild_nav()
		best = min(best, Time.get_ticks_usec() - t0)
		prints("rep", rep, (Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		var th = g._bfs([Vector3(ex + 300, g.surf_y(ex + 300) - 1, 0), Vector3(ex - 10, int(g.chamber.y) + 8, 1)], 260)
		bt = min(bt, Time.get_ticks_usec() - t0)
	var h = 0
	for f in [g.dist_home, g.dist_exit, g._bfs([Vector3(ex + 300, g.surf_y(ex + 300) - 1, 0), Vector3(ex - 10, int(g.chamber.y) + 8, 1)], 260), g._bfs([Vector2(g.ox, g.surf_y(g.ox) - 1)])]:
		var s = 0
		for i in range(0, f.size(), 1):
			if f[i] >= 0:
				s = (s * 31 + f[i] * 7 + i) % 1000000007
		h = h * 1000003 + s
	print("rebuild_nav best %.2f ms, capped bfs best %.2f ms, checksum %d" % [best / 1000.0, bt / 1000.0, h])
	quit()
