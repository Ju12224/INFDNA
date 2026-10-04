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
# How it looks (the gait, colony_sim._step_ant applies it): an ant keeps its line. Among the cells that lead closer it takes the one that turns least
# from its last step, so it does not zig-zag down a shaft or step back and forth; it walks on the floor rather than upside down on the roof when it
# can; it prefers a cell no other ant is about to enter (a crowd spreads over floor, walls and the other plane instead of piling into one spot); it
# sets off from standing slowly and gets up to speed in a fraction of a second, slows for a sharp turn, and squeezes through a hole to the other tunnel
# plane at a crawl. A long hop at high game speed stays a straight walk (two neighbouring directions at most), so the line drawn from its start to
# its end never cuts through the rock at a bend. Nurses potter: a short walk one way along the floor, a stand, another walk (shuffle_home).
#
# Raiders walk by surface_step too (always one cell at a time).

const NO_LEDGE = -9999
const LEDGE_REACH = 4
const OX = [-1, 0, 1, -1, 1, -1, 0, 1]
const OY = [-1, -1, -1, 0, 0, 1, 1, 1]
# Gait memory, packed into Ant.scout (an int nothing else uses): bits 0-3 the last step (0 none, 1-8 a neighbour index + 1, 9 a crossing to the
# other plane), bits 4-11 how far the ant has got up to speed since it last stood still (0 standing .. 255 full speed), bits 12-23 the ground it has
# lost to pauses, setting off and slowing down, in 1/64 cells (it makes it up by walking a little faster afterwards: colony_sim._step_ant).
const DIR_MASK = 15
const PLANE_STEP = 9
const RAMP_SHIFT = 4
const RAMP_MASK = 255 << 4
const NO_RAMP = ~(255 << 4)
const DEBT_SHIFT = 12
const DEBT_MASK = 4095 << 12
# DIR_OF[(sy + 1) * 3 + (sx + 1)]: the step code of a unit step
const DIR_OF = [1, 2, 3, 4, 0, 5, 6, 7, 8]
# TURN[a * 9 + b]: how sharply step b turns from step a, in eighths of a circle (0 straight on .. 4 straight back; 0 when either is unknown)
const TURN = [0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 1, 2, 1, 3, 2, 3, 4,
	0, 1, 0, 1, 2, 2, 3, 4, 3,
	0, 2, 1, 0, 3, 1, 4, 3, 2,
	0, 1, 2, 3, 0, 4, 1, 2, 3,
	0, 3, 2, 1, 4, 0, 3, 2, 1,
	0, 2, 3, 4, 1, 3, 0, 1, 2,
	0, 3, 4, 3, 2, 2, 1, 0, 1,
	0, 4, 3, 2, 3, 1, 2, 1, 0]
# score added to a candidate step for how sharply it turns from the last one (one step of the distance field is worth 16, so this only ever chooses
# between cells that are equally close to the goal: progress is never given up)
const TURN_PEN = [0, 2, 5, 9, 14]
const CROWD_PEN = 5           # ... and for a cell another ant is about to walk into
const ROOF_PEN = 4            # ... and for a cell with more rock above it than below (given the choice an ant walks on the floor, not upside down on the
                              # roof: it used to flip over every second or so in a sloping tunnel)
const PLANE_HOP = 2.2         # a crossing to the other tunnel plane takes as long as walking this many cells (the ant squeezes through the hole)
const NURSE_W = [6, 4, 1, 0, 0]   # a nurse's next step, weighted by how sharply it turns: on along the floor, never straight back mid-walk



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


# One hop down the distance field `f`: of the neighbouring cells that are closer to the goal, the one that turns least from the last step, preferring
# cells that touch dirt (ants crawl along surfaces) and cells no other ant is about to enter, with a little randomness so a crowd does not march in a
# line. When the goal is more than a hop away and the game is fast, several steps are taken in one (`ant`: an Ant, which has a gait memory).
static func descend(sim, a, f: PoolIntArray, macro: bool = true, ant: bool = false) -> void:
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
	var solid = g.solid
	var rng = sim.rng
	var prev := 0
	var occ = sim.occ
	var crowd := false
	var qnow := 0
	var me := 0
	if ant:
		prev = a.scout & DIR_MASK
		if prev == PLANE_STEP:
			prev = 0
		crowd = occ.size() == g.PLANES * WH
		qnow = int(sim.time * 10.0)
		me = a.id & 4095
	var c0 := 0
	var c1 := 0
	var zsw := false
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
		var bc = 0
		var pt = prev * 9 + 1
		for i in 8:
			var d = OX[i] + OY[i] * W
			if walk[base + d] != 1:
				continue
			var v = f[base + d]
			if v < 0 or v >= here:
				continue
			var nx = cx + OX[i]
			var ny = cy + OY[i]
			var sc = v * 16 + rng.randi_range(0, 3)
			if prev != 0:
				sc += TURN_PEN[TURN[pt + i]]
			if sc >= best_s:
				continue                # the penalties below only add: it cannot win
			if not g.walled(nx, ny, cz):
				sc += 6
			if ny + 1 < H:
				var c = base + d
				var up = solid[c - W - 1] + solid[c - W] + solid[c - W + 1]
				var dn = solid[c + W - 1] + solid[c + W] + solid[c + W + 1]
				if up > dn:
					sc += ROOF_PEN
				elif up == dn:
					sc += 1
			if crowd:
				var o = occ[base + d]
				if (o >> 12) > qnow and (o & 4095) != me:
					sc += CROWD_PEN
			if sc < best_s:
				best_s = sc
				bx = nx
				by = ny
				bz = cz
				bc = i + 1
		# a hole between the planes is one more step (the same cell in the other plane)
		if g.is_link(cx, cy) and g.can_walk(cx, cy, 1 - cz):
			var bz2 = (1 - cz) * WH + cy * W + xl
			var vz = f[bz2]
			if vz >= 0 and vz < here:
				var scz = vz * 16 + rng.randi_range(0, 3) + 2
				if not g.walled(cx, cy, 1 - cz):
					scz += 6
				if crowd:
					var o2 = occ[bz2]
					if (o2 >> 12) > qnow and (o2 & 4095) != me:
						scz += CROWD_PEN
				if scz < best_s:
					best_s = scz
					bx = cx
					by = cy
					bz = 1 - cz
					bc = PLANE_STEP
		if bc == 0:
			break
		# a long hop stays a straight walk: at most two neighbouring directions in it, and a crossing to the other plane is a hop of its own
		if done > 0:
			if bc == PLANE_STEP or zsw:
				break
			if bc != c0:
				if c1 == 0 and TURN[c0 * 9 + bc] == 1:
					c1 = bc
				elif bc != c1:
					break
		else:
			c0 = bc
		if bc == PLANE_STEP:
			path += PLANE_HOP
			zsw = true
		else:
			path += 1.4142 if (bx != cx and by != cy) else 1.0
		cx = bx
		cy = by
		cz = bz
		prev = bc if bc != PLANE_STEP else 0
		done += 1
	if done == 0:
		_descend_plain(sim, a, f)
		return
	sim._go(a, Vector3(cx, cy, cz))
	if done > 1 or zsw:
		a.hop = path


# A nurse's walk: one step to an open cell inside the nest (within `reach` of home, never out on the grass by the hole), going on the way it was going
# (a turn is likelier the gentler it is, and it never doubles straight back mid-walk), floor cells three times and other cells that touch a wall twice as
# likely as open ones. Only at a dead end does it turn round. Returns false when there is no such cell (the caller then heads home).
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
	var prev = a.scout & DIR_MASK
	if prev == PLANE_STEP:
		prev = 0
	var occ = sim.occ
	var crowd = occ.size() == g.PLANES * g.WH
	var qnow = int(sim.time * 10.0)
	var me = a.id & 4095
	var wt = [0, 0, 0, 0, 0, 0, 0, 0]
	var total := 0
	for pass_n in 2:
		var pt = prev * 9 + 1
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
			var w = 3 if g.is_solid(nx, ny + 1, cz) else (2 if g.walled(nx, ny, cz) else 1)
			if prev != 0:
				w *= NURSE_W[TURN[pt + i]]
			if crowd:
				var o = occ[base + d]
				if (o >> 12) > qnow and (o & 4095) != me:
					w = (w + 2) / 3        # a cell another ant stands in or is entering
			wt[i] = w
			total += w
		if total > 0 or prev == 0:
			break
		prev = 0          # a dead end: turn round
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
