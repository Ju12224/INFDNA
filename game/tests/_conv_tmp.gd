extends SceneTree
func _init():
	var im = Image.create_empty(17, 1, false, Image.FORMAT_RGBA8)
	for v in 17:
		im.set_pixel(v, 0, Color(v / 16.0, 0, 0, 1.0 - v / 16.0))
	var d = im.get_data()
	var r = []
	var a = []
	for v in 17:
		r.append(d[v * 4])
		a.append(d[v * 4 + 3])
	print("R ", r)
	print("A ", a)
	var r8 = Image.create_empty(4, 1, false, Image.FORMAT_R8)
	r8.fill_rect(Rect2i(0, 0, 1, 1), Color(1.0 / 255.0, 0, 0))
	r8.fill_rect(Rect2i(1, 0, 1, 1), Color(1.25 / 255.0, 0, 0))
	r8.fill_rect(Rect2i(2, 0, 1, 1), Color(1, 1, 1, 1))
	r8.fill_rect(Rect2i(3, 0, 1, 1), Color(7.25 / 255.0, 0, 0))
	print("R8 ", r8.get_data())
	var p = PackedByteArray([1, 2, 3, 4])
	print("i32 ", p.to_int32_array()[0], " expect ", 1 | 2 << 8 | 3 << 16 | 4 << 24)
	quit()
