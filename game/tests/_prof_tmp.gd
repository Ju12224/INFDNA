extends SceneTree
const WorldGrid = preload("res://core/world_grid.gd")
func _init():
	var g = WorldGrid.new(260, 225, 12345)
	var keep = []
	for rep in 8:
		var t0 = Time.get_ticks_usec()
		var d = g._neg.duplicate()
		d[0] = 5
		var t1 = Time.get_ticks_usec()
		var e = PackedInt32Array()
		e.resize(g._neg.size())
		var t2 = Time.get_ticks_usec()
		e.fill(-1)
		var t3 = Time.get_ticks_usec()
		e.fill(-1)
		var t4 = Time.get_ticks_usec()
		print("dup+write %.2f  resize %.2f  fill(first) %.2f  fill(again) %.2f" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0])
		if rep % 2 == 0:
			keep.append(d)
	quit()
