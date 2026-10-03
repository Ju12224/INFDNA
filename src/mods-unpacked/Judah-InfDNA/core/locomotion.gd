extends Reference
# The colony's movement rules, in one place. A task (forage, dig, nurse, defend, an order) only says WHAT an ant wants (be at this pile, go home, reach that
# chamber); how it gets there is decided here, by the same rules for every ant:
#   surface_step  walk along the open ground one column on, hugging the turf, or turn round at a cliff (never through the soil)
#   descend       take the next step down a distance field (a map of "steps to the goal") through the tunnels, crawling along walls, switching tunnel plane
#                 through a hole when that is the shorter way
#   settle        ants that are not told to go anywhere stand still
# Both walking rules cost no allocation per step (the old ones built arrays of neighbour cells), and both can take several cells in one hop. Hops are
# lengthened with the game speed (sim.hop_k: 1 up to 2x, 2 at 4x, 4 at 10x): at speeds where nobody watches single ants, an ant that is nowhere near
# anything of interest covers a few cells for one decision instead of one, so a big colony can still be simulated fast. A long hop never skips what a
# task is waiting for: it stops short of the cell where the task would act (a pile, the goal of a field, a fight), and the final approach is always
# made one cell at a time.
#
# Raiders walk by surface_step too (always one cell at a time).

const NO_LEDGE = -9999
const LEDGE_REACH = 4
const OX = [-1, 0, 1, -1, 1, -1, 0, 1]
const OY = [-1, -1, -1, 0, 0, 1, 1, 1]


# One hop along the open ground in the ant's heading: up to `limit` cells (and never more than the game speed allows). Moves the target cell (tx, ty).
static func surface_step(sim, a, limit: int = 99, macro: bool = false) -> void:
	var g = sim.grid
	var k = 1
	if macro:
		k = int(clamp(min(sim.hop_k, limit), 1, 8))
	var cx: int = a.x
	var cy: int = a.y
	var h: int = a.heading
	var moved := 0
	var path := 0.0
	var ledge := false
	while moved < k:
		var nx = cx + h
		var found := false
		var ny := 0
		# the cell one column on that hugs the ground: first one that is not part of the nest rim (the top row of soil round a shaft), else any
		for pass_n in 2:
			for dy in [1, 0, -1]:
				var yy = cy + dy
				if g.can_walk(nx, yy, 0) and yy <= g.surf_y(nx) and (pass_n == 1 or not g.is_under(nx, yy)):
					found = true
					ny = yy
					break
			if found:
				break
		if not found:
			# no foothold within a step: an ant scrambles up or down a ledge (a heap of spoil, the rim of a shaft) of a few cells rather than turn back
			var ly = _ledge(g, cx, cy, nx)
			if ly == NO_LEDGE:
				break
			path += sqrt(1.0 + (ly - cy) * (ly - cy))
			cx = nx
			cy = ly
			moved += 1
			ledge = true
			continue
		path += 1.4142 if ny != cy else 1.0
		cx = nx
		cy = ny
		moved += 1
	if moved == 0:
		# blocked at once: turn round and take the first open surface cell (the old rule, kept for the rare case)
		a.heading = -h
		for c in g.neighbors(a.x, a.y):
			if g.is_surface_cell(int(c.x), int(c.y)):
				sim._go(a, c)
				return
		return
	sim._go(a, Vector2(cx, cy))
	if (macro and moved > 1) or ledge:
		a.hop = path


# A foothold in column `nx` within LEDGE_REACH rows of `cy` (nearest first, lower ground first), or NO_LEDGE.
static func _ledge(g, cx: int, cy: int, nx: int) -> int:
	var top = g.surf_y(nx)
	for d in range(2, LEDGE_REACH + 1):
		for yy in [cy + d, cy - d]:
			if yy <= top and g.can_walk(nx, yy, 0):
				return yy
	return NO_LEDGE


# One hop down the distance field `f`: the neighbouring cell with the smallest value, preferring cells that touch dirt (ants crawl along surfaces), with a little
# randomness so a crowd does not march in a line. When the goal is more than a hop away and the game is fast, several steps are taken in one.
static func descend(sim, a, f: PoolIntArray, macro: bool = true) -> void:
	var g = sim.grid
	if f.size() != g.PLANES * g.WH:
		_random_step(sim, a)
		return
	var cx: int = a.x
	var cy: int = a.y
	var cz: int = a.z
	var cur = g.field(f, cx, cy, cz)
	var steps = 1
	if macro and sim.hop_k > 1 and cur > 3:
		steps = int(min(sim.hop_k, cur - 1))
	var path := 0.0
	var done := 0
	var W = g.W
	var WH = g.WH
	var ox = g.ox
	var H = g.H
	var walk = g.walk
	var rng = sim.rng
	while done < steps:
		var xl = cx - ox
		if xl < 1 or xl >= W - 1 or cy < 1 or cy >= H - 1:
			break                                     # the edge of the grid: the plain rule below handles it
		var base = cz * WH + cy * W + xl
		var here = f[base]
		if here < 0:
			break
		var best_s = 1 << 30
		var bx = 0
		var by = 0
		var bz = cz
		var have = false
		for i in 8:
			var d = OX[i] + OY[i] * W
			if walk[base + d] != 1:
				continue
			var v = f[base + d]
			if v < 0 or (here >= 0 and v >= here):
				continue
			var nx = cx + OX[i]
			var ny = cy + OY[i]
			var sc = v * 4 + rng.randi_range(0, 2)
			if not g.walled(nx, ny, cz):
				sc += 3
			if sc < best_s:
				best_s = sc
				bx = nx
				by = ny
				bz = cz
				have = true
		# a hole between the planes is one more step (the same cell in the other plane)
		if g.is_link(cx, cy) and g.can_walk(cx, cy, 1 - cz):
			var vz = f[(1 - cz) * WH + cy * W + xl]
			if vz >= 0 and vz < here:
				var scz = vz * 4 + rng.randi_range(0, 2)
				if not g.walled(cx, cy, 1 - cz):
					scz += 3
				if scz < best_s:
					best_s = scz
					bx = cx
					by = cy
					bz = 1 - cz
					have = true
		if not have:
			break
		path += 1.4142 if (bx != cx and by != cy) else 1.0
		cx = bx
		cy = by
		cz = bz
		done += 1
	if done == 0:
		_descend_plain(sim, a, f)
		return
	sim._go(a, Vector3(cx, cy, cz))
	if done > 1:
		a.hop = path


# A nurse's shuffle: one step to a random open cell inside the nest (within `reach` of home, never out on the grass by the hole), cells that touch a wall
# twice as likely. Returns false when there is no such cell (the caller then heads home).
static func shuffle_home(sim, a, reach: int = 8) -> bool:
	var g = sim.grid
	var cx: int = a.x
	var cy: int = a.y
	var cz: int = a.z
	var W = g.W
	var xl = cx - g.ox
	if xl < 1 or xl >= W - 1 or cy < 1 or cy >= g.H - 1:
		return false
	var base = cz * g.WH + cy * W + xl
	var hb = cy * W + xl
	var walk = g.walk
	var home = g.dist_home
	var ok = home.size() == g.PLANES * g.WH
	if not ok:
		return false
	var pick = [0, 0, 0, 0, 0, 0, 0, 0]
	var wt = [0, 0, 0, 0, 0, 0, 0, 0]
	var total := 0
	for i in 8:
		var d = OX[i] + OY[i] * W
		if walk[base + d] != 1:
			continue
		var nx = cx + OX[i]
		var ny = cy + OY[i]
		if ny <= g.surf_y(nx):
			continue
		var v = home[cz * g.WH + hb + d]
		if v < 0 or v > reach:
			continue
		var w = 2 if g.walled(nx, ny, cz) else 1
		wt[i] = w
		total += w
	if total == 0:
		return false
	var r = sim.rng.randi_range(0, total - 1)
	for i in 8:
		r -= wt[i]
		if r < 0:
			sim._go(a, Vector2(cx + OX[i], cy + OY[i]))
			return true
	return false


# The old rule, for the edge of the grid and for an ant that finds no cell closer to the goal: a random neighbour.
static func _descend_plain(sim, a, f: PoolIntArray) -> void:
	var g = sim.grid
	var nb = g.neighbors(a.x, a.y, a.z)
	if g.is_link(a.x, a.y) and g.can_walk(a.x, a.y, 1 - a.z):
		nb.append(Vector3(a.x, a.y, 1 - a.z))
	if nb.empty():
		return
	var cur = g.field(f, a.x, a.y, a.z)
	var best = null
	var best_s = 1 << 30
	var f_ok = f.size() == g.PLANES * g.WH
	for c in nb:
		var cz = int(c.z) if typeof(c) == TYPE_VECTOR3 else a.z
		var d = f[cz * g.WH + int(c.y) * g.W + (int(c.x) - g.ox)] if f_ok else -1
		if d < 0 or (cur >= 0 and d >= cur):
			continue
		var sc = d * 4 + sim.rng.randi_range(0, 2)
		if not g.walled(int(c.x), int(c.y), cz):
			sc += 3
		if sc < best_s:
			best_s = sc
			best = c
	if best == null:
		best = nb[sim.rng.randi_range(0, nb.size() - 1)]
	sim._go(a, best)


static func _random_step(sim, a) -> void:
	var nb = sim.grid.neighbors(a.x, a.y, a.z)
	if not nb.empty():
		sim._go(a, nb[sim.rng.randi_range(0, nb.size() - 1)])
