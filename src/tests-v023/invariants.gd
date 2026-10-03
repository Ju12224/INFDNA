extends SceneTree
# Robustness harness: runs the sim for a long time while a random "player" gives orders and powers, and checks things that must always
# hold: nothing outside the world or inside the soil, no NaN, no ant or raider stuck in one place for no reason, a bird that actually
# moves, squads that refer to real orders. Prints counts by category and an example of each.
# usage: SEED=11 MINS=25 godot --no-window --path . -s invariants.gd      (project dir holding mods-unpacked/ and this file)
const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
const Orders = preload("res://mods-unpacked/Judah-InfDNA/core/orders.gd")

var found := {}
var examples := {}
var _last := {}        # unit key -> [x, y, z, since]
var _trace_id := -1
var _trace_until := 0.0
var _bird_x := -1.0
var _bird_kills := 0
var _bird_since := 0.0


func _env(k, d):
	var v = OS.get_environment(k)
	return d if v == "" else v


func note(cat: String, msg: String) -> void:
	found[cat] = found.get(cat, 0) + 1
	if not examples.has(cat):
		examples[cat] = msg


func _init():
	var seed_v = int(_env("SEED", "11"))
	var sim = Sim.new(seed_v, "well_rounded")
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + 7
	var end_t = float(_env("MINS", "25")) * 60.0
	var next_check = 1.0
	var next_player = 15.0
	var g = sim.grid
	var ex = int(g.entrance.x)
	while sim.time < end_t and not sim.collapsed:
		sim.step(0.1)
		if sim.shop_pending and sim.hostile_count() == 0:
			sim.open_shop()
			var n_buy = 0
			for i in sim.offers.size():
				if n_buy < 2 and sim.offers[i] != "" and sim.food - sim.price(sim.offers[i]) >= 30.0 + 0.6 * sim.ants.size():
					if sim.buy(i):
						n_buy += 1
			sim.shop_pending = false
		if OS.get_environment("BREED") != "" and not sim.apex.empty() and sim.blessed_left <= 0:
			sim.will = 100.0
			sim.cmd_cd.clear()
			sim.food = max(sim.food, 100.0)
			sim.cast("breed", 0, sim.apex[0])
		if sim.time >= next_player:
			next_player = sim.time + rng.randf_range(10.0, 25.0)
			_player(sim, rng, ex)
		if _trace_id >= 0 and sim.time < _trace_until:
			for a in sim.ants:
				if a.id == _trace_id:
					print("TRACE t=%.2f pos=%d,%d tgt=%d,%d t=%.2f task=%d dig_timer=%.2f curl=%.1f squad=%d hurt=%.2f flee=%d off_t=%.2f spd=%.2f" % [sim.time, a.x, a.y, a.tx, a.ty, a.t, a.task, a.dig_timer, a.curl_t, a.squad, a.hurt, a.flee, a.off_t, a.ph["speed"]])
		if sim.time >= next_check:
			next_check = sim.time + 1.0
			_check(sim, ex)
	print("INVARIANTS seed=%d t=%.0f ants=%d raids=%d collapsed=%s squads=%d arc=%d cycles=%d peak_ms=%.0f" % [seed_v, sim.time, sim.ants.size(), sim.raid_n, str(sim.collapsed), sim.squads.size(), sim.arc_stage, sim.void_cycles, sim.peak_ms])
	var cats = found.keys()
	cats.sort()
	for c in cats:
		print("  %-26s %5d   e.g. %s" % [c, found[c], examples[c]])
	if cats.empty():
		print("  all clear")
	quit()


# A random player: now and then a squad with a random order, a release, a power.
func _player(sim, rng, ex: int) -> void:
	var g = sim.grid
	var roll = rng.randf()
	if roll < 0.55 and sim.ants.size() > 12:
		var list := []
		var n = rng.randi_range(6, 24)
		for k in n:
			list.append(sim.ants[rng.randi_range(0, sim.ants.size() - 1)])
		var kind = ["move", "move", "harvest", "attack", "dig"][rng.randi_range(0, 4)]
		var x = ex + rng.randi_range(-160, 160)
		match kind:
			"move":
				if rng.randf() < 0.75:
					Orders.issue(sim, list, "move", x, g.surf_y(x) - 2)
				else:
					var y = g.surf_y(ex) + rng.randi_range(8, 60)
					Orders.issue(sim, list, "move", ex + rng.randi_range(-8, 8), y, 0)
			"harvest":
				if not sim.piles.empty():
					var p = sim.piles[rng.randi_range(0, sim.piles.size() - 1)]
					Orders.issue(sim, list, "harvest", int(p["x"]), 0)
			"attack":
				if not sim.enemies.empty():
					var e = sim.enemies[rng.randi_range(0, sim.enemies.size() - 1)]
					Orders.issue(sim, list, "attack", e.x, e.y, e.z, e.id)
			"dig":
				var y2 = g.surf_y(ex) + rng.randi_range(10, 70)
				Orders.issue(sim, list, "dig", ex + rng.randi_range(-30, 30), y2, 0)
	elif roll < 0.75:
		var rel := []
		for a in sim.ants:
			if a.squad != 0 and rng.randf() < 0.5:
				rel.append(a)
		Orders.release(sim, rel)
	else:
		sim.will = 100.0
		sim.cmd_cd.clear()
		var id = ["rally", "recall", "surge", "harvest", "breed"][rng.randi_range(0, 4)]
		sim.cast(id, ex + rng.randi_range(-120, 120), null)


func _check(sim, ex: int) -> void:
	var g = sim.grid
	var now = sim.time
	if is_nan(sim.food) or is_inf(sim.food):
		note("food NaN", "food=%s" % str(sim.food))
	if is_nan(sim.queen_hp):
		note("queen hp NaN", "")
	var seen := {}
	for a in sim.ants:
		var key = a.id
		seen[key] = true
		if not g.inb(a.x, a.y):
			note("ant outside the world", "ant %d at %d,%d" % [a.id, a.x, a.y])
			continue
		if g.is_solid(a.x, a.y, a.z) and a.dig_timer <= 0.0 and a.t < 0.1:
			note("ant inside solid soil", "ant %d at %d,%d z%d task %d" % [a.id, a.x, a.y, a.z, a.task])
		if a.squad != 0 and not sim.squads.has(a.squad):
			note("ant under a missing squad", "ant %d squad %d" % [a.id, a.squad])
		var l = _last.get(key)
		if l == null or l[0] != a.x or l[1] != a.y or l[2] != a.z or l.size() < 5 or l[4] != a.squad or l[5] != a.task:
			_last[key] = [a.x, a.y, a.z, now, a.squad, a.task]      # standing still counts from the moment its order or task last changed
		else:
			var still = now - l[3]
			var ok = a.task == sim.Task.NURSE or a.dig_timer > 0.0 or a.hauling or a.timer < 0.0
			if a.squad != 0 and sim.squads.has(a.squad) and sim.squads[a.squad]["kind"] in ["move", "attack"]:
				ok = true
			if a.task == sim.Task.DEFEND and (sim.hostile_count() > 0 or sim.rally_t > 0.0):
				ok = true
			if still > 60.0 and not ok:
				note("ant stuck 60s task %d" % a.task, "ant %d at %d,%d z%d squad %d state: carry %.1f spoil %.1f" % [a.id, a.x, a.y, a.z, a.squad, a.carry, a.spoil])
				if OS.get_environment("DETAIL") != "" and not examples.has("detail"):
					examples["detail"] = "x"
					var info = "STUCK DETAIL ant %d task %d t=%.2f tx,ty=%d,%d tz=%d walk=%s home_field=%d exit_field=%d is_under=%s dist_home.size=%d carry=%.1f timer=%.1f job=%d quota=%d" % [a.id, a.task, a.t, a.tx, a.ty, a.tz, str(g.can_walk(a.x, a.y, a.z)), g.field(g.dist_home, a.x, a.y, a.z), g.field(g.dist_exit, a.x, a.y, a.z), str(g.is_under(a.x, a.y)), g.dist_home.size(), a.carry, a.timer, a.job_id, a.quota]
					print(info)
					_trace_id = a.id
					_trace_until = now + 2.0
					for dy in range(-1, 2):
						var row = ""
						for dx in range(-2, 3):
							row += " [%d,%d solid=%s walk=%s h=%d]" % [a.x + dx, a.y + dy, str(g.is_solid(a.x + dx, a.y + dy, a.z)), str(g.can_walk(a.x + dx, a.y + dy, a.z)), g.field(g.dist_home, a.x + dx, a.y + dy, a.z)]
						print(row)
				_last[key][3] = now
	for e in sim.enemies:
		var key2 = -e.id
		seen[key2] = true
		if not g.inb(e.x, e.y):
			note("raider outside the world", "%s at %d,%d" % [e.kind, e.x, e.y])
			continue
		var l2 = _last.get(key2)
		if l2 == null or l2[0] != e.x or l2[1] != e.y:
			_last[key2] = [e.x, e.y, e.z, now]
		else:
			var still2 = now - l2[3]
			if still2 > 40.0 and e.state == 0 and not e.engaged and e.stun_t <= 0.0 and e.guard_x == 0 and e.kind != "looter" and e.cls != "prey":
				note("raider stuck approaching", "%s id %d at %d,%d (%d from the nest) hp %.0f" % [e.kind, e.id, e.x, e.y, e.x - ex, e.hp])
				_last[key2][3] = now
	for k in _last.keys():
		if not seen.has(k):
			_last.erase(k)
	if sim.bird != null:
		if abs(float(sim.bird["x"]) - _bird_x) < 0.01 and int(sim.bird["kills"]) == _bird_kills:
			if now - _bird_since > 12.0:
				note("bird frozen", "bird at %.1f for %.0f s, t left %.1f" % [sim.bird["x"], now - _bird_since, sim.bird["t"]])
				_bird_since = now
		else:
			_bird_x = float(sim.bird["x"])
			_bird_kills = int(sim.bird["kills"])
			_bird_since = now
	else:
		_bird_x = -1.0
		_bird_since = now
	if sim.ants.size() > 0 and sim.food < -0.5:
		note("negative food", "%.1f" % sim.food)
