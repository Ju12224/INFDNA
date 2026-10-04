extends SceneTree
const WorldGrid = preload("res://core/world_grid.gd")
func _t(name, f):
	var t0 = Time.get_ticks_usec()
	f.call()
	print("%s %.1f ms" % [name, (Time.get_ticks_usec() - t0) / 1000.0])
func _init():
	var g = WorldGrid.new(260, 225, 12345)
	var ox = g.ox
	var W = g.W
	_t("fresh_rows", func():
		for y in g.H:
			g._fresh_row(ox + W, ox + W + 64, y, 2))
	_t("stones", func(): g._stamp_stones(ox, ox + 63))
	_t("make_neg", func(): g._make_neg())
	_t("refresh_walk64", func(): g._refresh_walk(ox, 0, ox + 64, g.H - 1))
	_t("nav", func(): g.rebuild_nav())
	_t("extend", func(): g._extend(0, 64))
	quit()
