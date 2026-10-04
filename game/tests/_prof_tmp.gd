extends SceneTree
const WorldGrid = preload("res://core/world_grid.gd")

func bfs_b(g, sources: Array) -> PackedInt32Array:
	var dist: PackedInt32Array = g._neg.duplicate()
	var queue := PackedInt32Array()
	queue.resize(g.walk.count(1) + sources.size() + 8)
	var tail: int = 0
	for s in sources:
		var si = g._i(int(s.x), int(s.y), 0)
		if dist[si] != 0:
			dist[si] = 0
			queue[tail] = si
			tail += 1
	var wk: PackedByteArray = g.walk
	var lk: PackedByteArray = g.link
	var w: int = g.W
	var wh: int = g.WH
	var head: int = 0
	while head < tail:
		var i: int = queue[head]
		head += 1
		var nd: int = dist[i] + 1
		var r: int = i - wh if i >= wh else i
		var j: int = i - w - 1
		if wk[j] == 1 and dist[j] == -1:
			dist[j] = nd
			queue[tail] = j
			tail += 1
		j += 1
		if wk[j] == 1 and dist[j] == -1:
			dist[j] = nd
			queue[tail] = j
			tail += 1
		j += 1
		if wk[j] == 1 and dist[j] == -1:
			dist[j] = nd
			queue[tail] = j
			tail += 1
		j = i - 1
		if wk[j] == 1 and dist[j] == -1:
			dist[j] = nd
			queue[tail] = j
			tail += 1
		j = i + 1
		if wk[j] == 1 and dist[j] == -1:
			dist[j] = nd
			queue[tail] = j
			tail += 1
		j = i + w - 1
		if wk[j] == 1 and dist[j] == -1:
			dist[j] = nd
			queue[tail] = j
			tail += 1
		j += 1
		if wk[j] == 1 and dist[j] == -1:
			dist[j] = nd
			queue[tail] = j
			tail += 1
		j += 1
		if wk[j] == 1 and dist[j] == -1:
			dist[j] = nd
			queue[tail] = j
			tail += 1
		if lk[r] == 1:
			var j3: int = (wh + r) if i < wh else r
			if wk[j3] == 1 and dist[j3] == -1:
				dist[j3] = nd
				queue[tail] = j3
				tail += 1
	return dist

func _init():
	var g = WorldGrid.new(260, 225, 12345)
	var ex = int(g.entrance.x)
	for i in 160:
		var x = ex - 80 + i
		g.carve(x, g.chamber.y + 6 + (i % 9), 1.6, i % 2)
		g.carve(ex + (i % 40) - 20, g.chamber.y + 10 + i / 4, 1.4, 0)
	for i in 40:
		g.make_link(ex - 60 + i * 3, int(g.chamber.y) + 9, 1)
	print("walk cells ", g.walk.count(1))
	for rep in 3:
		var t0 = Time.get_ticks_usec()
		var a = g._bfs([g.entrance])
		var t1 = Time.get_ticks_usec()
		var b = bfs_b(g, [g.entrance])
		var t2 = Time.get_ticks_usec()
		var t3 = Time.get_ticks_usec()
		var c = g.walk.count(1)
		var t4 = Time.get_ticks_usec()
		print("cur %.2f ms  presized %.2f ms  count %.2f ms  same=%s" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t4 - t3) / 1000.0, str(a == b)])
	quit()
