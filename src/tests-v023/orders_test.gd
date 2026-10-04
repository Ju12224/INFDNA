extends SceneTree
const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
const Orders = preload("res://mods-unpacked/Judah-InfDNA/core/orders.gd")
var fails := 0
func ok(c, msg):
	if not c:
		fails += 1
	print(("PASS " if c else "FAIL ") + msg)
func fresh(sim):
	var y = sim.ants.duplicate()
	y.invert()                          # the youngest first: old ants die during a long test
	return y


func run(sim, secs):
	var t = sim.time + secs
	while sim.time < t and not sim.collapsed:
		sim.step(0.1)
		if sim.shop_pending:
			sim.shop_pending = false
func _init():
	var sim = Sim.new(11, "well_rounded")
	run(sim, 420.0)
	sim.raid_timer = 99999.0            # no raids while the orders are tested
	sim._bird_timer = 99999.0
	sim._anteater_timer = 99999.0
	var g = sim.grid
	var ex = int(g.entrance.x)
	print("colony: %d ants, t=%.0f, piles=%d" % [sim.ants.size(), sim.time, sim.piles.size()])
	# ---- guard
	var squad := []
	var young = fresh(sim)
	for a in young:
		if squad.size() < 14 and a.carry <= 0.0 and a.spoil <= 0.0 and a.dig_timer <= 0.0:
			squad.append(a)
	var tx = ex + 40
	var r = Orders.issue(sim, squad, "move", tx, g.surf_y(tx) - 2)
	ok(r["ok"] and r["n"] == squad.size() - r["skipped"], "a guard order is accepted: " + r["msg"])
	run(sim, 110.0)
	var near := 0
	var defend := 0
	for a in squad:
		if sim.ants.has(a) and a.squad != 0:
			if abs(a.x - tx) <= 3 and not g.is_under(a.x, a.y):
				near += 1
			if a.task == sim.Task.DEFEND:
				defend += 1
	var alive_n := 0
	for a in squad:
		if sim.ants.has(a) and a.squad != 0:
			alive_n += 1
	ok(near >= alive_n * 0.8 and alive_n > 0, "the squad walked to the post and holds it (%d of %d within 3 cells)" % [near, alive_n])
	# a foe comes near the post: the guards go for it
	sim._spawn_enemy("charger", 1)
	var foe = sim.enemies.back()
	foe.x = tx + 12
	foe.tx = foe.x
	foe.y = g.surf_y(foe.x) - 1
	foe.ty = foe.y
	var hp0 = foe.hp
	run(sim, 25.0)
	ok(not sim.enemies.has(foe) or foe.hp < hp0 * 0.6, "guards meet a foe that comes near the post (foe hp %.0f of %.0f)" % [foe.hp if sim.enemies.has(foe) else 0.0, hp0])
	# ---- pause while raiders are inside
	var s0 = squad[0]
	sim.recall_t = 5.0
	ok(Orders.paused(sim), "orders give way during a Recall")
	sim.recall_t = 0.0
	# ---- release
	var still_n := 0
	for a in squad:
		if sim.ants.has(a) and a.squad != 0:
			still_n += 1
	var n_rel = Orders.release(sim, squad)
	var free_n := 0
	for a in squad:
		if a.squad == 0:
			free_n += 1
	ok((n_rel > 0 or still_n == 0) and free_n == squad.size(), "releasing sets the ants free (%d released, %d had stood down already)" % [n_rel, squad.size() - still_n])
	run(sim, 30.0)
	var back := 0
	for a in squad:
		if sim.ants.has(a) and abs(a.x - tx) > 6:
			back += 1
	ok(back > 0 or squad.empty(), "released ants go back to their own work")
	# ---- harvest
	var pile = null
	for p in sim.piles:
		if p["amount"] > 40.0 and (pile == null or abs(p["x"] - ex) < abs(pile["x"] - ex)):
			pile = p
	if pile != null:
		var hv := []
		young = fresh(sim)
		for a in young:
			if hv.size() < 10 and a.spoil <= 0.0 and a.dig_timer <= 0.0:
				hv.append(a)
		var amt0 = pile["amount"]
		var deliv0 = sim.delivered_total
		var r2 = Orders.issue(sim, hv, "harvest", int(pile["x"]), 0)
		ok(r2["ok"], "a harvest order is accepted: " + r2["msg"])
		var sites_ok := 0
		for a in hv:
			if a.squad != 0 and a.site == int(pile["x"]):
				sites_ok += 1
		ok(sites_ok >= r2["n"] * 0.8, "harvesters set out for the chosen pile (%d of %d)" % [sites_ok, r2["n"]])
		run(sim, 150.0)
		ok(sim.delivered_total > deliv0, "the harvesters haul food home (%.0f delivered)" % (sim.delivered_total - deliv0))
		Orders.release(sim, hv)
	else:
		print("SKIP no pile near enough")
	# ---- dig
	var chamber = null
	for c in sim.planner.chambers:
		chamber = c
		break
	var dg := []
	young = fresh(sim)
	for a in young:
		if dg.size() < 8 and a.spoil <= 0.0 and a.carry <= 0.0 and a.dig_timer <= 0.0:
			dg.append(a)
	var goal = null
	if not sim.planner.spine.empty():
		for k in 40:
			var s = sim.planner.spine[sim.rng.randi_range(0, sim.planner.spine.size() - 1)]
			var cand = Vector2(int(s.x) + sim.rng.randi_range(-12, 12), int(s.y) + sim.rng.randi_range(4, 12))
			if g.is_solid(int(cand.x), int(cand.y), 0) and g.diggable(int(cand.x), int(cand.y), 0):
				var clear = true
				for dx in range(-3, 4):
					for dy in range(-3, 4):
						if not g.is_solid(int(cand.x) + dx, int(cand.y) + dy, 0):
							clear = false
				if clear:
					goal = cand
					break
	if goal != null:
		var open0 = 0
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				if not g.is_solid(int(goal.x) + dx, int(goal.y) + dy, 0):
					open0 += 1
		var r3 = Orders.issue(sim, dg, "dig", int(goal.x), int(goal.y))
		ok(r3["ok"], "a dig order is accepted: " + r3["msg"])
		run(sim, 240.0)
		var open1 = 0
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				if not g.is_solid(int(goal.x) + dx, int(goal.y) + dy, 0):
					open1 += 1
		ok(open1 > open0, "the diggers bore toward the spot (open cells near it %d -> %d)" % [open0, open1])
		Orders.release(sim, dg)
	else:
		print("SKIP no dig goal")
	# ---- underground move: ants sent to a chamber go there
	if chamber != null:
		var cc = Vector2(int(chamber["center"].x), int(chamber["center"].y))
		var ug := []
		young = fresh(sim)
		for a in young:
			if ug.size() < 8 and a.carry <= 0.0 and a.spoil <= 0.0 and a.dig_timer <= 0.0 and a.squad == 0:
				ug.append(a)
		sim.food = max(sim.food, sim.food_cap * 0.6 + 50.0)     # the "larder is empty" stand-down must not free the squad mid-test
		var ids := {}
		for a in ug:
			ids[a.id] = true
		sim.attn_sel = ids                                       # as if the player had them selected (no off-screen stand-down)
		var r4 = Orders.issue(sim, ug, "move", int(cc.x), int(cc.y), int(chamber.get("z", 0)))
		ok(r4["ok"], "an underground move order is accepted: " + r4["msg"])
		run(sim, 90.0)
		var arrived := 0
		var alive_u := 0
		for a in ug:
			if sim.ants.has(a) and a.squad != 0:
				alive_u += 1
				if abs(a.x - cc.x) <= 6 and abs(a.y - cc.y) <= 6:
					arrived += 1
		ok(alive_u > 0 and arrived >= alive_u * 0.6, "the squad reaches the chamber (%d of %d within 6 cells)" % [arrived, alive_u])
		Orders.release(sim, ug)
	# ---- attack: the squad goes for the foe it was told to
	var atk := []
	young = fresh(sim)
	for a in young:
		if atk.size() < 12 and a.squad == 0 and a.carry <= 0.0 and a.spoil <= 0.0 and a.dig_timer <= 0.0:
			atk.append(a)
	sim._spawn_enemy("helmet", -1)
	var tgt = sim.enemies.back()
	tgt.x = ex - 35
	tgt.tx = tgt.x
	tgt.y = g.surf_y(tgt.x) - 1
	tgt.ty = tgt.y
	tgt.state = 1
	var r5 = Orders.issue(sim, atk, "attack", tgt.x, tgt.y, tgt.z, tgt.id)
	ok(r5["ok"], "an attack order is accepted: " + r5["msg"])
	run(sim, 60.0)
	ok(not sim.enemies.has(tgt), "the squad hunts down the foe it was sent after")
	# ---- a squad sent to the rival's mound is a strike party
	var rv = sim.rival
	rv.found = true
	rv.broken_t = 0.0
	sim.enemies.clear()
	var party := []
	young = fresh(sim)
	for a in young:
		if party.size() < 26 and a.squad == 0 and a.carry <= 0.0 and a.spoil <= 0.0 and a.dig_timer <= 0.0:
			party.append(a)
	sim.food = max(sim.food, 300.0)
	var r6 = Orders.issue(sim, party, "move", rv.x, g.surf_y(rv.x) - 2)
	ok(r6["ok"], "a guard order on the rival's mound is accepted: " + r6["msg"])
	var guards_seen := false
	var tt = sim.time + 240.0
	while sim.time < tt and not sim.collapsed and rv.conquered == 0:
		sim.step(0.1)
		if sim.shop_pending:
			sim.shop_pending = false
		if rv.guards_out:
			guards_seen = true
	ok(guards_seen, "the guards come out to meet a squad at their mound")
	print("  rival conquered=%d hp=%.0f/%.0f broken_t=%.0f" % [rv.conquered, rv.hp, rv.max_hp, rv.broken_t])
	ok(not Orders.issue(sim, [], "move", ex, 0)["ok"], "an empty selection is refused politely")
	var bad = Orders.issue(sim, sim.ants.slice(0, 3), "dig", ex, g.surf_y(ex) - 20)
	ok(not bad["ok"], "digging open air is refused: " + bad["msg"])
	print("RESULT %d failed" % fails)
	quit()
