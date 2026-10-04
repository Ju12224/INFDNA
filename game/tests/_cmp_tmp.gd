extends SceneTree
# temp: compare the new world grid with the old one (tests/_old_world_grid.gd) where they overlap
const New = preload("res://core/world_grid.gd")
const Old = preload("res://tests/_old_world_grid.gd")

func _cmp_arrays(a, b, name):
	var lo = max(a.ox, b.ox)
	var hi = min(a.ox + a.W, b.ox + b.W) - 1
	var bad = 0
	var first = ""
	for spec in [["solid", 2], ["walk", 2], ["under", 1], ["mat", 1], ["link", 1]]:
		var A = a.get(spec[0])
		var B = b.get(spec[0])
		for z in spec[1]:
			for y in a.H:
				for x in range(lo, hi + 1):
					var va = A[z * a.WH + y * a.W + x - a.ox]
					var vb = B[z * b.WH + y * b.W + x - b.ox]
					if va != vb:
						bad += 1
						if first == "":
							first = "%s z=%d x=%d y=%d new=%d old=%d" % [spec[0], z, x, y, va, vb]
	print("%s arrays: %d differences %s (cols %d..%d)" % [name, bad, first, lo, hi])

func _cmp_img(a, b, k, name):
	var ia = a.chunk_images(k)
	var ib = b.chunk_images(k)
	var bad = 0
	var first = ""
	for n in 2:
		var da = ia[n].get_data()
		var db = ib[n].get_data()
		if da.size() != db.size():
			print("size mismatch")
			return 1
		for i in da.size():
			if da[i] != db[i]:
				bad += 1
				if first == "":
					var px = i / 4
					first = "img%d ch%d c=%d y=%d new=%d old=%d" % [n, i % 4, px % ia[n].get_width(), px / ia[n].get_width(), da[i], db[i]]
	if bad > 0:
		print("%s chunk %d: %d byte differences, first %s" % [name, k, bad, first])
	return bad

func _init():
	var t0 = Time.get_ticks_usec()
	var a = New.new(260, 225, 12345)
	print("new built in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	var b = Old.new(260, 225, 12345)
	print("old built in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_cmp_arrays(a, b, "fresh")
	var nb = 0
	for k in range(-6, 10):
		nb += _cmp_img(a, b, k, "fresh")
	for k in [40, -40, 26, -23]:
		nb += _cmp_img(a, b, k, "outside")
	print("fresh images: %d byte differences" % nb)
	# dig the same things into both
	var ra = RandomNumberGenerator.new()
	ra.seed = 7
	var rb = RandomNumberGenerator.new()
	rb.seed = 7
	var ex = int(a.entrance.x)
	for i in 60:
		var x = ex - 40 + i
		a.carve(x, a.chamber.y + 6 + (i % 7), 1.6, i % 2)
		b.carve(x, b.chamber.y + 6 + (i % 7), 1.6, i % 2)
	for i in 30:
		a.make_link(ex - 30 + i, int(a.chamber.y) + 8, 1)
		b.make_link(ex - 30 + i, int(b.chamber.y) + 8, 1)
	for i in 20:
		a.deposit(ex + 3, 3.0, ra)
		b.deposit(ex + 3, 3.0, rb)
	a.add_entrance(ex + 60)
	b.add_entrance(ex + 60)
	_cmp_arrays(a, b, "dug")
	nb = 0
	for k in range(-6, 10):
		nb += _cmp_img(a, b, k, "repainted")
	print("repainted images: %d byte differences" % nb)
	a._chunk_img.clear()
	b._chunk_img.clear()
	nb = 0
	for k in range(-6, 10):
		nb += _cmp_img(a, b, k, "rebuilt")
	print("rebuilt images: %d byte differences" % nb)
	quit()
