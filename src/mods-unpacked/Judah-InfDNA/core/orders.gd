extends Reference
# Squad orders: the player's direct hand on the colony. Ants picked out with a box (colony_scene) are given an order with a right-click:
#   move    walk to a spot and guard it: fight what comes within reach of it, hold the ground otherwise
#   attack  go for one foe, then guard where it fell
#   harvest take food from one pile, trip after trip, until it is empty
#   dig     bore a tunnel toward a spot in the soil (a planner job the squad works on; other diggers help)
# Orders last until released (or finished). They give way, ant by ant and automatically, while raiders are inside the nest, the
# queen is badly hurt or a Recall is running, then come back on their own. Free to give: the Will meter pays for the colony-wide
# powers (Rally, Recall, Surge, Breed, Strike), not for telling your own ants where to go.
#
# The sim owns the ants (`Ant.squad` is the squad id, 0 = free) and `sim.squads`; this module is the rules.

const LEASH = 26            # how far a guard strays from its post to meet a foe (columns)
const SIGHT = 14            # how far a guard sees a foe
const KINDS = ["move", "attack", "harvest", "dig"]
const LABELS = {"move": "GUARD", "attack": "ATTACK", "harvest": "HARVEST", "dig": "DIG"}
const COLORS = {"move": Color("#6ec1ff"), "attack": Color("#ff5a4a"), "harvest": Color("#ffd86b"), "dig": Color("#c79a5a")}


static func paused(sim) -> bool:
	return sim._inside_n > 0 or sim.queen_hp < sim.queen_max * 0.5 or sim.recall_t > 0.0


# Give `list` (ants) an order. Returns {"ok", "n", "skipped", "msg"}. Ants that are carrying food or dirt are skipped by orders that would
# make them drop it (a harvest takes food-carriers, a dig takes dirt-carriers).
static func issue(sim, list: Array, kind: String, x: int, y: int, z: int = 0, ref: int = 0) -> Dictionary:
	var res = {"ok": false, "n": 0, "skipped": 0, "msg": ""}
	var ants := []
	for a in list:
		if sim.ants.has(a):
			ants.append(a)
	if ants.empty():
		res["msg"] = "Nobody selected."
		return res
	var g = sim.grid
	var sq = {"id": sim.squad_seq, "kind": kind, "x": x, "y": y, "z": z, "ref": ref, "job": 0, "field": PoolIntArray(), "field_t": -99.0, "under": false}
	match kind:
		"harvest":
			var best = null
			for p in sim.piles:
				if p["amount"] > 4.0 and abs(p["x"] - x) <= 4 and (best == null or abs(p["x"] - x) < abs(best["x"] - x)):
					best = p
			if best == null:
				res["msg"] = "No food to harvest there."
				return res
			sq["x"] = int(best["x"])
		"dig":
			if not g.is_solid(x, y, z) or not g.diggable(x, y, z):
				res["msg"] = "That ground cannot be dug."
				return res
			var jid = sim.planner.add_dig_order(Vector2(x, y))
			if jid == 0:
				res["msg"] = "No way to dig there from the nest."
				return res
			sq["job"] = jid
		"attack":
			var found = false
			for e in sim.enemies:
				if e.id == ref:
					found = true
					sq["x"] = e.x
			if not found:
				res["msg"] = "That target is gone."
				return res
		_:
			sq["kind"] = "move"
			if g.is_under(x, y) or y > g.surf_y(x) + 1:
				if not g.can_walk(x, y, z):
					var near = null
					for dy in range(-3, 4):
						for dx in range(-3, 4):
							if g.can_walk(x + dx, y + dy, z) and (near == null or abs(dx) + abs(dy) < abs(near.x - x) + abs(near.y - y)):
								near = Vector2(x + dx, y + dy)
					if near == null:
						res["msg"] = "There is no room to stand there."
						return res
					sq["x"] = int(near.x)
					sq["y"] = int(near.y)
				sq["under"] = true
	sim.squad_seq += 1
	sim.squads[sq["id"]] = sq
	for a in ants:
		var busy = kind != "harvest" and a.carry > 0.0 or (kind != "dig" and (a.spoil > 0.0 or a.dig_timer > 0.0))
		if busy:
			res["skipped"] += 1
			continue
		a.squad = sq["id"]
		a.timer = 0.0
		a.flee = 0
		a.curl_t = 0.0
		match kind:
			"harvest":
				a.task = sim.Task.FORAGE
				a.spoil = 0.0
				a.hauling = false
				sim._start_trip(a)
			"dig":
				a.task = sim.Task.DIG
				a.quota = 10
				a.job_id = int(sq["job"])
			_:
				a.task = sim.Task.DEFEND
				a.hauling = false
		res["n"] += 1
	if res["n"] == 0:
		sim.squads.erase(sq["id"])
		res["msg"] = "Those ants are all busy carrying; try again in a moment."
		return res
	res["ok"] = true
	var where = Vector2(sq["x"], sq["y"]) if (kind == "dig" or sq["under"]) else Vector2(sq["x"], g.surf_y(int(sq["x"])) - 2)
	var col: Color = COLORS[sq["kind"]]
	sim.fx.append({"kind": "ring", "pos": g.center(int(where.x), int(where.y)), "t": 0.0, "color": col})
	sim.fx.append({"kind": "text", "pos": g.center(int(where.x), int(where.y) - 4), "t": 0.0, "text": LABELS[sq["kind"]], "color": col})
	res["msg"] = "%s: %d ant%s%s" % [LABELS[sq["kind"]].capitalize(), res["n"], "" if res["n"] == 1 else "s", (" (%d busy, skipped)" % res["skipped"]) if res["skipped"] > 0 else ""]
	return res


# Set ants free: they go home and choose their own work again.
static func release(sim, list: Array) -> int:
	var n := 0
	for a in list:
		if a.squad != 0 and sim.ants.has(a):
			_free(sim, a)
			n += 1
	return n


static func _free(sim, a) -> void:
	a.squad = 0
	a.task = sim.Task.HOME
	a.timer = 0.0
	a.job_id = 0
	a.hauling = false


# An order that has run its course (pile empty, tunnel dug or blocked): everyone in the squad is let go.
static func complete(sim, id: int, why: String = "") -> void:
	var n := 0
	for a in sim.ants:
		if a.squad == id:
			_free(sim, a)
			n += 1
	sim.squads.erase(id)
	if n > 0 and why != "":
		sim.toasts.append({"text": why, "t": 4.0})


# The ant's action on arriving in a cell. True when the order handled it. Harvest and dig orders work through the ordinary forage and
# dig code (see choose and trip), so only move and attack are handled here.
static func obey(sim, a) -> bool:
	var sq = sim.squads.get(a.squad)
	if sq == null:
		a.squad = 0
		return false
	if paused(sim):
		return false
	if sq["kind"] == "harvest" or sq["kind"] == "dig":
		return false
	a.task = sim.Task.DEFEND
	var g = sim.grid
	if sq["under"]:
		var f = _field(sim, sq)
		if f.size() == 0:
			return false
		var d = g.field(f, a.x, a.y, a.z)
		if d >= 0 and d <= 1:
			sim._go(a, Vector2(a.x, a.y))
		elif d < 0:
			sim._descend(a, g.dist_home)
		else:
			sim._descend(a, f)
		return true
	if g.is_under(a.x, a.y) or a.z == 1:
		sim._descend(a, g.dist_exit)          # climb out first
		return true
	var tx = int(sq["x"])
	var foe = _foe(sim, a, sq)
	if foe != null:
		tx = foe.x
	if abs(a.x - tx) > (1 if foe != null else 2):
		a.heading = 1 if tx > a.x else -1
		sim._walk_surface(a)
	else:
		sim._go(a, Vector2(a.x, a.y))        # hold the ground; the fight itself is the combat step's
	return true


# The order's own say in what the ant does next (called first by _choose_task). True when handled.
static func choose(sim, a) -> bool:
	var sq = sim.squads.get(a.squad)
	if sq == null:
		a.squad = 0
		return false
	if paused(sim):
		return false
	a.timer = 0.0
	match sq["kind"]:
		"harvest":
			a.task = sim.Task.FORAGE
			a.spoil = 0.0
			a.hauling = false
			sim._start_trip(a)
		"dig":
			a.task = sim.Task.DIG
			a.quota = sim.rng.randi_range(6, 12)
			a.job_id = int(sq["job"])
		_:
			a.task = sim.Task.DEFEND
	return true


# Called at the end of _start_trip: a harvester sets out for its pile, however far.
static func trip(sim, a) -> void:
	var sq = sim.squads.get(a.squad)
	if sq == null or sq["kind"] != "harvest" or paused(sim):
		return
	a.site = int(sq["x"])
	var ex = int(sim.grid.entrance.x)
	a.search_r = int(min(sim.RANGE_MAX, max(a.search_r, abs(a.site - ex) + 60)))
	a.heading = 1 if a.site > a.x else -1


static func is_dig(sim, a) -> bool:
	var sq = sim.squads.get(a.squad)
	return sq != null and sq["kind"] == "dig" and not paused(sim)


static func job_of(sim, a) -> int:
	return int(sim.squads[a.squad]["job"])


# Once a second: forget squads nobody belongs to, finish orders that have nothing left to do, warn about an empty larder.
static func step(sim, dt: float) -> void:
	sim._squad_t -= dt
	if sim._squad_t > 0.0:
		return
	sim._squad_t = 1.0
	if sim.squads.empty():
		return
	var counts := {}
	for a in sim.ants:
		if a.squad != 0:
			counts[a.squad] = counts.get(a.squad, 0) + 1
	var ordered := 0
	for id in sim.squads.keys():
		var sq = sim.squads[id]
		if not counts.has(id):
			sim.squads.erase(id)
			continue
		ordered += counts[id]
		match sq["kind"]:
			"harvest":
				var left = false
				for p in sim.piles:
					if p["amount"] > 4.0 and abs(p["x"] - int(sq["x"])) <= 3:
						left = true
						break
				if not left:
					complete(sim, id, "The pile is empty: the harvesters are free.")
			"dig":
				if sim.planner.job_by_id(int(sq["job"])) == null:
					complete(sim, id, "The dig is done: the diggers are free.")
			"attack":
				var alive = false
				for e in sim.enemies:
					if e.id == int(sq.get("ref", 0)):
						alive = true
						sq["x"] = e.x
						break
				if not alive:
					sq["kind"] = "move"        # the foe has fallen: the squad guards the spot
					sq["ref"] = 0
	if ordered > 0 and sim.food < sim._food_target * 0.1 and not sim._squad_warned:
		sim._squad_warned = true
		sim.toasts.append({"text": "The larder is nearly empty and %d ants are under orders. Select them and press Q to free them." % ordered, "t": 7.0})
	elif sim.food > sim._food_target * 0.3:
		sim._squad_warned = false


static func count(sim) -> int:
	var n := 0
	for a in sim.ants:
		if a.squad != 0:
			n += 1
	return n


# The foe a guard goes to meet: the squad's own target if it has one, else the nearest hostile near the ant on the open ground and
# not too far from the post.
static func _foe(sim, a, sq):
	if sq["kind"] == "attack" and int(sq.get("ref", 0)) != 0:
		for e in sim.enemies:
			if e.id == int(sq["ref"]):
				sq["x"] = e.x
				return e if (e.z == a.z and not sim.grid.is_under(e.x, e.y)) else null
		return null
	var best = null
	var bd = SIGHT + 1
	for e in sim.enemies:
		if e.cls == "prey" or e.state == 2 or e.z != a.z or sim.grid.is_under(e.x, e.y):
			continue
		var d = abs(e.x - a.x)
		if d < bd and abs(e.x - int(sq["x"])) <= LEASH:
			bd = d
			best = e
	return best


static func _field(sim, sq) -> PoolIntArray:
	if sq["field"].size() == 0 or sim.time - float(sq["field_t"]) > 6.0:
		sq["field"] = sim.grid._bfs([Vector3(int(sq["x"]), int(sq["y"]), int(sq["z"]))])
		sq["field_t"] = sim.time
	return sq["field"]
