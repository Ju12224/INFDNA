extends RefCounted
# Colony blueprint, grown organically. Diggers take jobs from here; genes decide which
# jobs they prefer (dig_down: shafts vs everything else).
#
# The nest has LEVELS (depth bands below the entrance). Shafts wind down to open the next
# level; galleries wander roughly along a level and end in a room. Every tunnel is traced
# by a steering walker that drifts, gets pulled toward its goal, and turns away from
# stones, fossils and bedrock, so galleries wind and fork. Other job kinds:
#   scout - short narrow dead-end probe
#   loop  - links two tunnels that are close in space but far apart through the nest
#           (also happens when a gallery runs into an existing tunnel)
#   back  - a tunnel in the BACK plane, entered through a hole in the rear wall of a front
#           tunnel. It can cross behind front tunnels without touching them, end in a
#           room, or come back out through a second hole.
# Rooms have a shape per purpose:
#   food  - granary: wide and low with a flat floor (storage capacity; excess rots)
#   brood - nursery: three joined lobes (eggs are laid here and hatch faster)
#   farm  - fungus garden: tall dome with a flat floor (ferments scraps into food)

const PURPOSES = ["food", "brood", "farm", "food", "farm", "brood", "midden", "food", "farm", "brood", "food", "farm"]
const MAX_JOBS = 2
const LEVEL_DEPTHS = [13, 22, 32, 42, 52, 62, 72, 81, 95, 110, 125, 140]   # rows below the entrance ground (12 levels, down into the shale)
const LEVEL_PREF = {
	"food": [1.0, 0.8, 0.5, 0.3, 0.2],
	"brood": [0.2, 1.0, 0.9, 0.5, 0.3],
	"farm": [0.1, 0.5, 0.9, 1.0, 1.0],
	"midden": [0.05, 0.2, 0.5, 0.9, 1.0],   # refuse far from the brood
	"armory": [0.2, 0.7, 1.0, 0.7, 0.4],
	"cistern": [0.1, 0.3, 0.6, 0.9, 1.0],
	"venom": [0.1, 0.4, 0.8, 1.0, 0.8],
	"battery": [1.0, 0.8, 0.4, 0.2, 0.1],   # near the gates
	"architects": [0.4, 0.9, 1.0, 0.6, 0.3],
}
const MAX_SPREAD = 170      # starting spread; city.gd widens max_spread as the colony grows
var max_spread := MAX_SPREAD
var wanted_rooms := []      # unlocked workshops still to build (set by city.gd)
const ROOMS_PER_LEVEL = 11

var grid
var rng
var max_jobs := MAX_JOBS
var jobs := []
var chambers := []
var spine := []                 # Vector3 (x, y, plane): tunnel cells new branches can start from
var levels := []                # absolute y of each level
var level_open := []
var stats := {"gallery": 0, "scout": 0, "loop": 0, "shaft": 0, "back": 0, "holes": 0, "blocked": 0, "merged": 0, "detours": 0}
var events := []                # short texts for the sim to toast
var _purpose_i := 0
var _next_id := 1
var _ex := 0
var _fails := 0
var _said_back := false
var last_fail := ""            # why the last room attempt failed (tests)


func _init(g, r) -> void:
	grid = g
	rng = r
	_ex = int(grid.entrance.x)
	var sy = grid.base_y(_ex)
	for d in LEVEL_DEPTHS:
		levels.append(sy + d)
		level_open.append(false)
	level_open[0] = true
	level_open[1] = true
	for y in range(sy + 8, int(grid.chamber.y - grid.chamber_r.y)):
		var wig = 0 if y < sy + 5 else int(round(sin(y * 0.35) * 2.0))
		if not grid.is_solid(_ex + wig, y):
			spine.append(Vector3(_ex + wig, y, 0))
	var cx = grid.chamber.x
	var cy = grid.chamber.y
	for p in [Vector2(cx - grid.chamber_r.x + 1, cy + 1), Vector2(cx + grid.chamber_r.x - 1, cy + 1), Vector2(cx + 3, cy + 3), Vector2(cx - 3, cy + 3)]:
		if not grid.is_solid(int(p.x), int(p.y)):
			spine.append(Vector3(int(p.x), int(p.y), 0))


func count(purpose: String) -> int:
	var n := 0
	for c in chambers:
		if c["purpose"] == purpose:
			n += 1
	return n


func open_levels() -> int:
	var n := 0
	for o in level_open:
		if o:
			n += 1
	return n


func update(need_space: bool) -> void:
	if jobs.size() < (max_jobs if need_space else 2):
		_new_job()


func pick_job(dig_down: float):
	if jobs.is_empty():
		return null
	var w := []
	for j in jobs:
		w.append(max(0.05, dig_down if j["kind"] == "shaft" else 1.0 - dig_down) * (4.0 if j["kind"] == "order" else 1.0))   # the player's dig orders come first
	var total := 0.0
	for x in w:
		total += x
	var r = rng.randf() * total
	for i in jobs.size():
		r -= w[i]
		if r <= 0.0:
			return jobs[i]
	return jobs[0]


# A tunnel the player asked for: from the nearest open tunnel cell of the nest toward `goal` (a solid cell). Returns the job id, 0 if there is
# no way (nothing to start from, or rock in the way at once).
func add_dig_order(goal: Vector2) -> int:
	var best = null
	var bd = 1e12
	for s in spine:
		if int(s.z) != 0:
			continue
		var d = goal.distance_squared_to(Vector2(s.x, s.y))
		if d < bd:
			bd = d
			best = s
	if best == null:
		return 0
	var start = Vector2(best.x, best.y)
	var length = int(clamp(start.distance_to(goal) * 1.3 + 6.0, 4.0, 140.0))
	var w = _walk(start, {"kind": "goal", "goal": goal}, length, 0, false)
	if w["cells"].size() < 1:
		return 0
	var job = _job("order", w["cells"], 0, 1.3)
	job["id"] = _next_id
	_next_id += 1
	job["dist"] = PackedInt32Array()
	job["src"] = Vector2(-99, -99)
	job["built"] = -99.0
	job["idx"] = 0
	job["linked"] = []
	jobs.append(job)
	return job["id"]


func job_by_id(id: int):
	for j in jobs:
		if j["id"] == id:
			return j
	return null


# Next still-solid cell of the job, or null when finished. Cells that turned out not
# to dig (a stone the walker missed) are skipped.
func target(job):
	var z = job["z"]
	while job["idx"] < job["cells"].size():
		var c = job["cells"][job["idx"]]
		if grid.is_solid(int(c.x), int(c.y), z) and grid.diggable(int(c.x), int(c.y), z):
			return c
		job["idx"] += 1
	_finish(job)
	return null


func note_dug(job, n: int) -> void:
	job["dug"] = job.get("dug", 0) + n


func radius_for(job) -> float:
	return job["room_r"] if job["idx"] >= job["split"] else job["r"]


# After a carve: open the hole(s) between the planes once the back tunnel reaches them.
func after_carve(job, cell: Vector2) -> void:
	for h in job.get("holes", []):
		if not h in job["linked"] and cell.distance_to(h) <= 1.6:
			if grid.make_link(int(h.x), int(h.y), 1) > 0:
				job["linked"].append(h)
				stats["holes"] += 1


# Distance field toward the job's current dig face (throttled rebuild). A back-plane face
# with nothing open around it yet is dug from the front tunnel, through the rear wall.
func dist_for(job, t: Vector2, now: float) -> PackedInt32Array:
	var z = job["z"]
	if job["dist"].size() != grid.PLANES * grid.WH or job["src"].distance_to(t) > 3.0 or now - job["built"] > 4.0:
		var src := []
		for d in grid.N8:
			var c = t + d
			if grid.can_walk(int(c.x), int(c.y), z):
				src.append(Vector3(c.x, c.y, z))
		if src.is_empty() and z == 1:
			for d in [Vector2.ZERO] + grid.N8:
				var c = t + d
				if grid.can_walk(int(c.x), int(c.y), 0):
					src.append(Vector3(c.x, c.y, 0))
		if src.is_empty():
			for i in range(job["idx"] - 1, -1, -1):
				var c2 = job["cells"][i]
				if grid.can_walk(int(c2.x), int(c2.y), z):
					src.append(Vector3(c2.x, c2.y, z))
					break
		if src.is_empty():
			jobs.erase(job)   # unreachable dig face: abandon so the blueprint never stalls
			stats["blocked"] += 1
			return PackedInt32Array()
		job["dist"] = grid._bfs(src, -1, job.get("dist", PackedInt32Array()))
		job["src"] = t
		job["built"] = now
	return job["dist"]


func _finish(job) -> void:
	jobs.erase(job)
	var z = job["z"]
	var kind = job["kind"]
	stats[kind] = stats.get(kind, 0) + 1
	var tunnel_end = min(job["split"], job["cells"].size())
	for i in range(0, tunnel_end, 3):
		var c = job["cells"][i]
		if not grid.is_solid(int(c.x), int(c.y), z):
			spine.append(Vector3(c.x, c.y, z))
	while spine.size() > 500:
		spine.remove_at(rng.randi_range(0, spine.size() - 1))
	match kind:
		"shaft":
			if not level_open[job["level"]]:
				level_open[job["level"]] = true
				events.append("Nest level %d opened, down in the %s" % [job["level"] + 1, grid.MAT_NAMES[grid.strata_at(_ex, levels[job["level"]])]])
		"loop":
			events.append("Tunnel loop closed: a shortcut through the nest")
		"back":
			if not _said_back:
				_said_back = true
				events.append("Diggers broke through the rear wall: a second tunnel layer")
	if job.has("center") and job.get("dug", 0) >= 6:
		chambers.append({"center": job["center"], "rx": job["rx"], "ry": job["ry"], "purpose": job["purpose"],
			"z": z, "floor": job["floor"], "shape": job["shape"], "level": job.get("level", 1)})
		# the new room's far wall becomes a branching point for more galleries
		var far = job["center"] + Vector2(sign(job["center"].x - job["cells"][0].x) * (job["rx"] - 1.0), job["ry"] * 0.3)
		if not grid.is_solid(int(far.x), int(far.y), z):
			spine.append(Vector3(int(far.x), int(far.y), z))


func _pending_rooms() -> int:
	var n := 0
	for j in jobs:
		if j.has("center"):
			n += 1
	return n


func _new_job() -> void:
	var shaft_active = false
	var back_active = false
	for j in jobs:
		if j["kind"] == "shaft":
			shaft_active = true
		if j["z"] == 1:
			back_active = true
	var rooms = chambers.size() + _pending_rooms()
	var deepest = -1
	for i in levels.size():
		if level_open[i]:
			deepest = i
	var kinds := ["room", "scout"]
	var w := [1.0, 0.2]
	if rooms >= 2:
		kinds.append("loop")
		w.append(0.22)
	# a new level only once the deepest one is being lived in (or rooms keep failing)
	if not shaft_active and deepest + 1 < levels.size() and (_rooms_on(deepest) >= 2 or _fails >= 8):
		kinds.append("shaft")
		w.append(0.35)
	if rooms >= 3 and not back_active:
		kinds.append("back")
		w.append(0.45)
	for attempt in 10:
		var kind = _weighted(kinds, w)
		var job = null
		match kind:
			"room":
				job = _make_room(0)
			"scout":
				job = _make_scout()
			"loop":
				job = _make_loop()
			"shaft":
				job = _make_shaft(deepest)
			"back":
				job = _make_back()
		if job != null:
			job["id"] = _next_id
			_next_id += 1
			job["dist"] = PackedInt32Array()
			job["src"] = Vector2(-99, -99)
			job["built"] = -99.0
			job["idx"] = 0
			job["linked"] = []
			jobs.append(job)
			if kind == "room":
				_fails = 0
			return
		if kind == "room":
			_fails += 1


func _weighted(items: Array, weights: Array):
	var total := 0.0
	for x in weights:
		total += x
	var r = rng.randf() * total
	for i in items.size():
		r -= weights[i]
		if r <= 0.0:
			return items[i]
	return items[items.size() - 1]


func _rooms_on(level: int) -> int:
	var n := 0
	for c in chambers:
		if c.get("level", -1) == level:
			n += 1
	for j in jobs:
		if j.has("center") and j.get("level", -1) == level:
			n += 1
	return n


func _spine_near(y: float, band: float, z: int = 0) -> Array:
	var out := []
	for c in spine:
		if int(c.z) == z and abs(c.y - y) <= band and not grid.is_solid(int(c.x), int(c.y), z):
			out.append(c)
	return out


# ---------- the tunnel walker ----------
# Cells a tunnel would pass through here: blocked by undiggable material, the surface
# skin, the world floor, or the far edge of the nest.
func _blocked(p: Vector2, z: int) -> bool:
	var x = int(round(p.x))
	var y = int(round(p.y))
	if y < grid.surf_y(x) + 5 or y > grid.H - 8 or abs(x - _ex) > max_spread:
		return true
	for d in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if grid.dig_rate(x + int(d.x), y + int(d.y)) <= 0.0 and grid.is_solid(x + int(d.x), y + int(d.y), z):
			return true
	return false


static func _wrap(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


# Trace a winding tunnel from start. mode: {"kind": "level", "dir", "ty"} runs sideways
# along a level, {"kind": "goal", "goal"} heads for a point, {"kind": "down", "ty"} winds
# down to a depth, {"kind": "free", "hd"} keeps a rough heading. Returns
# {"cells", "merged", "reached", "blocked"}; merged = ran into an open tunnel of its plane.
func _walk(start: Vector2, mode: Dictionary, length: int, z: int, allow_merge: bool) -> Dictionary:
	var p = start
	var hd = _desired(p, mode, 0.0, start)
	var cells := []
	var last = Vector2(round(p.x), round(p.y))
	var res = {"cells": cells, "merged": false, "reached": false, "blocked": false}
	var solid_run := 0     # only count a merge after the tunnel has cut through fresh dirt
	for i in length * 3:
		var want = _desired(p, mode, hd, start)
		hd += _wrap(want - hd) * 0.22 + rng.randf_range(-0.32, 0.32)
		if abs(_wrap(hd - want)) > 1.0:
			hd = want + sign(_wrap(hd - want)) * 1.0
		var dirv = Vector2(cos(hd), sin(hd))
		if _blocked(p + dirv * 2.2, z):
			var turned = false
			var sgn = 1.0 if rng.randf() < 0.5 else -1.0
			for tr in [0.6, -0.6, 1.1, -1.1, 1.6, -1.6]:
				var h2 = hd + tr * sgn
				if not _blocked(p + Vector2(cos(h2), sin(h2)) * 2.2, z):
					hd = h2
					turned = true
					stats["detours"] += 1
					break
			if not turned:
				res["blocked"] = true
				break
			dirv = Vector2(cos(hd), sin(hd))
		p += dirv * 0.75
		var c = Vector2(round(p.x), round(p.y))
		if c == last:
			continue
		last = c
		var open_here = not grid.is_solid(int(c.x), int(c.y), z)
		if allow_merge and solid_run >= 3 and open_here and grid.is_under(int(c.x), int(c.y)):
			res["merged"] = true
			break
		if not open_here:
			solid_run += 1
		cells.append(c)
		if mode["kind"] == "goal" and c.distance_to(mode["goal"]) <= 1.5:
			res["reached"] = true
			break
		if mode["kind"] == "down" and c.y >= mode["ty"]:
			res["reached"] = true
			break
		if cells.size() >= length:
			break
	return res


func _desired(p: Vector2, mode: Dictionary, hd: float, start: Vector2) -> float:
	match mode["kind"]:
		"level":
			return Vector2(mode["dir"], clamp((mode["ty"] - p.y) * 0.08, -0.6, 0.6)).angle()
		"goal":
			return (mode["goal"] - p).angle()
		"down":
			return Vector2(clamp((start.x + mode.get("drift", 0.0) - p.x) * 0.06, -0.5, 0.5), 1.0).angle()
		_:
			return mode["hd"]


# ---------- job kinds ----------
func _job(kind: String, cells: Array, z: int, r: float) -> Dictionary:
	return {"kind": kind, "cells": cells, "z": z, "split": cells.size(), "r": r, "room_r": 1.7}


func _pick_level(purpose: String) -> int:
	var w := []
	var ids := []
	for i in levels.size():
		if not level_open[i]:
			continue
		var n = _rooms_on(i)
		if n >= ROOMS_PER_LEVEL:
			continue
		ids.append(i)
		w.append(_pref(purpose, i) / (1.0 + 0.35 * n))
	if ids.is_empty():
		return -1
	return _weighted(ids, w)


# LEVEL_PREF rows have 5 samples from shallow to deep; stretch them over any number of levels.
func _pref(purpose: String, i: int) -> float:
	var p = LEVEL_PREF.get(purpose, [1.0, 1.0, 1.0, 1.0, 1.0])
	var f = float(i) / max(1, levels.size() - 1) * (p.size() - 1)
	var a = int(floor(f))
	var b = min(a + 1, p.size() - 1)
	return lerp(p[a], p[b], f - a)


func _make_room(z: int, anchor = null, level: int = -1):
	var purpose = PURPOSES[_purpose_i % PURPOSES.size()]
	if not wanted_rooms.is_empty() and rng.randf() < 0.45:
		purpose = wanted_rooms[rng.randi_range(0, wanted_rooms.size() - 1)]
	if level < 0:
		level = _pick_level(purpose)
	if level < 0:
		last_fail = "level"
		return null
	var ly = levels[level]
	if anchor == null:
		var near = _spine_near(ly, 5.0, 0)
		if near.is_empty():
			last_fail = "anchor"
			return null
		anchor = near[rng.randi_range(0, near.size() - 1)]
	var a2 = Vector2(anchor.x, anchor.y)
	var dir = -1 if rng.randf() < 0.5 else 1
	var w = _walk(a2, {"kind": "level", "dir": dir, "ty": ly + rng.randf_range(-2.0, 2.0)}, rng.randi_range(7, 20), z, true)
	var cells: Array = w["cells"]
	if cells.size() < 4:
		last_fail = "short"
		return null
	if w["merged"] and z == 0 and rng.randf() < 0.35:
		# ran into another tunnel: keep it as a loop instead of a room
		var lj = _job("loop", cells, z, 1.2)
		stats["merged"] += 1
		return lj
	if w["merged"] or w["blocked"] and cells.size() < 7:
		last_fail = "merge/block"
		return null
	var end = cells[cells.size() - 1]
	var go = sign(end.x - a2.x)
	if go == 0:
		go = dir
	var room = _room_shape(purpose, end, go)
	var center: Vector2 = room["center"]
	if abs(center.x - _ex) > max_spread or center.y + room["ry"] > grid.H - 6:
		last_fail = "bounds"
		return null
	if center.y - room["ry"] < grid.surf_y(int(center.x)) + 7:
		last_fail = "shallow"
		return null
	for c in chambers + _pending_list():
		var gap = 3.0 if c["z"] == z else -2.0   # rooms in different planes may overlap a little
		if center.distance_to(c["center"]) < room["rx"] + c["rx"] + gap:
			last_fail = "overlap"
			return null
	if center.distance_to(grid.chamber) < room["rx"] + grid.chamber_r.x + 4:
		last_fail = "queen"
		return null
	var stone := 0
	for rc in room["cells"]:
		if grid.dig_rate(int(rc.x), int(rc.y)) <= 0.0:
			stone += 1
	if stone > room["cells"].size() * 0.3:
		last_fail = "stone"
		return null
	var job = _job("back" if z == 1 else "gallery", cells + room["cells"], z, 1.25)
	job["split"] = cells.size()
	job["center"] = center
	job["rx"] = room["rx"]
	job["ry"] = room["ry"]
	job["floor"] = room["floor"]
	job["shape"] = room["shape"]
	job["purpose"] = purpose
	job["level"] = level
	_purpose_i += 1
	return job


func _pending_list() -> Array:
	var out := []
	for j in jobs:
		if j.has("center"):
			out.append({"center": j["center"], "rx": j["rx"], "z": j["z"]})
	return out


# Room cells per purpose, sorted outward from the gallery end.
func _room_shape(purpose: String, end: Vector2, dir: float) -> Dictionary:
	var cells := []
	var center: Vector2
	var rx: float
	var ry: float
	var floor_y: float
	match purpose:
		"food", "cistern":
			rx = rng.randf_range(6.0, 8.5)
			ry = rng.randf_range(2.3, 2.9)
			center = end + Vector2(dir * (rx - 1.0), -ry * 0.25)
			floor_y = center.y + ry * 0.55
			for yy in range(int(center.y - ry) - 1, int(center.y + ry) + 2):
				for xx in range(int(center.x - rx) - 1, int(center.x + rx) + 2):
					var dx = (xx - center.x) / rx
					var dy = (yy - center.y) / ry
					if dx * dx + dy * dy <= 1.0 and dy <= 0.6:
						cells.append(Vector2(xx, yy))
		"farm":
			rx = rng.randf_range(4.8, 6.2)
			ry = rng.randf_range(3.6, 4.4)
			center = end + Vector2(dir * (rx - 1.0), -ry * 0.35)
			floor_y = center.y + ry * 0.6
			for yy in range(int(center.y - ry) - 1, int(center.y + ry) + 2):
				for xx in range(int(center.x - rx) - 1, int(center.x + rx) + 2):
					var dx = (xx - center.x) / rx
					var dy = (yy - center.y) / ry
					if dx * dx + dy * dy <= 1.0 and dy <= 0.65:
						cells.append(Vector2(xx, yy))
		_:
			var r = rng.randf_range(2.3, 2.9)
			rx = 2.1 * r
			ry = r
			center = end + Vector2(dir * (rx - 0.5), -r * 0.2)
			floor_y = center.y + r * 0.8
			var lobes = [[Vector2(-1.1 * r, 0.15 * r), r], [Vector2(0, -0.2 * r), r * 0.95], [Vector2(1.1 * r, 0.1 * r), r * 0.9]]
			for yy in range(int(center.y - ry * 1.4) - 1, int(center.y + ry * 1.3) + 2):
				for xx in range(int(center.x - rx * 1.1) - 1, int(center.x + rx * 1.1) + 2):
					for lb in lobes:
						var o = center + lb[0]
						if Vector2(xx, yy).distance_to(o) <= lb[1]:
							cells.append(Vector2(xx, yy))
							break
	cells.sort_custom(Callable(DistSorter.new(end), "less"))
	return {"cells": cells, "center": center, "rx": rx, "ry": ry, "floor": floor_y, "shape": purpose}


func _make_scout():
	if spine.is_empty():
		return null
	var a = spine[rng.randi_range(0, spine.size() - 1)]
	if int(a.z) != 0:
		return null
	var hd = rng.randf_range(-0.6, 0.6) if rng.randf() < 0.5 else PI + rng.randf_range(-0.6, 0.6)
	hd += rng.randf_range(0.0, 0.5)   # scouts lean downward
	var w = _walk(Vector2(a.x, a.y), {"kind": "free", "hd": hd}, rng.randi_range(6, 14), 0, true)
	if w["cells"].size() < 4:
		return null
	if w["merged"]:
		stats["merged"] += 1
		return _job("loop", w["cells"], 0, 1.2)
	return _job("scout", w["cells"], 0, 1.0)


# Two tunnel cells that are close in space but far apart through the nest.
func _make_loop():
	if grid.dist_home.size() != grid.PLANES * grid.WH:
		return null
	var front := []
	for c in spine:
		if int(c.z) == 0 and c.y > grid.surf_y(int(c.x)) + 8:
			front.append(c)
	if front.size() < 4:
		return null
	for attempt in 30:
		var a = front[rng.randi_range(0, front.size() - 1)]
		var b = front[rng.randi_range(0, front.size() - 1)]
		var e = Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))
		if e < 8.0 or e > 28.0:
			continue
		var da = grid.field(grid.dist_home, int(a.x), int(a.y))
		var db = grid.field(grid.dist_home, int(b.x), int(b.y))
		if da < 0 or db < 0 or abs(da - db) < e * 1.6 + 10.0:
			continue
		var w = _walk(Vector2(a.x, a.y), {"kind": "goal", "goal": Vector2(b.x, b.y)}, int(e * 1.8) + 4, 0, true)
		if (w["reached"] or w["merged"]) and w["cells"].size() >= 3:
			return _job("loop", w["cells"], 0, 1.2)
	return null


func _make_shaft(deepest: int):
	if deepest < 0 or deepest + 1 >= levels.size():
		return null
	var near = _spine_near(levels[deepest], 4.0, 0)
	if near.is_empty():
		return null
	var a = near[rng.randi_range(0, near.size() - 1)]
	var ty = levels[deepest + 1]
	var w = _walk(Vector2(a.x, a.y), {"kind": "down", "ty": ty, "drift": rng.randf_range(-6.0, 6.0)}, int(ty - a.y) + 12, 0, false)
	if not w["reached"] or w["cells"].size() < 4:
		return null
	var job = _job("shaft", w["cells"], 0, 1.25)
	job["level"] = deepest + 1
	return job


# A tunnel in the back plane, entered through a hole in a front tunnel's rear wall.
func _make_back():
	var cands := []
	for c in spine:
		if int(c.z) == 0 and c.y > grid.surf_y(int(c.x)) + 9 and Vector2(c.x, c.y).distance_to(grid.chamber) > grid.chamber_r.x + 2:
			cands.append(c)
	if cands.is_empty():
		return null
	var a = cands[rng.randi_range(0, cands.size() - 1)]
	var a2 = Vector2(a.x, a.y)
	var job = null
	if rng.randf() < 0.75:   # mostly back-plane rooms, the rest crossing tunnels
		# a room behind the nest, at the hole's level
		for attempt in 4:
			a = cands[rng.randi_range(0, cands.size() - 1)]
			a2 = Vector2(a.x, a.y)
			var best = 0
			for i in levels.size():
				if abs(levels[i] - a.y) < abs(levels[best] - a.y):
					best = i
			job = _make_room(1, Vector3(a.x, a.y, 1), best)
			if job != null:
				break
		if job == null:
			return null
		job["cells"].push_front(a2)
		job["split"] += 1
		job["holes"] = [a2]
	else:
		# a crossing tunnel: out through the rear wall, behind other tunnels, back out
		var goals := []
		for c in cands:
			var e = a2.distance_to(Vector2(c.x, c.y))
			if e >= 12.0 and e <= 32.0:
				goals.append(c)
		if goals.is_empty():
			return null
		var g = goals[rng.randi_range(0, goals.size() - 1)]
		var g2 = Vector2(g.x, g.y)
		var w = _walk(a2, {"kind": "goal", "goal": g2}, int(a2.distance_to(g2) * 1.8) + 4, 1, false)
		if not w["reached"] or w["cells"].size() < 6:
			return null
		var cells = [a2] + w["cells"]
		if cells[cells.size() - 1] != g2:
			cells.append(g2)
		job = _job("back", cells, 1, 1.2)
		job["holes"] = [a2, cells[cells.size() - 1]]
	return job


class DistSorter:
	var o: Vector2
	func _init(origin: Vector2) -> void:
		o = origin
	func less(a, b) -> bool:
		return a.distance_squared_to(o) < b.distance_squared_to(o)
