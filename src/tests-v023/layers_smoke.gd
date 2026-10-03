extends SceneTree
# Runs the real colony scene headless until a raider is fighting, then drives the view layers (scene API,
# HUD buttons, camera parked away from the raiders) and prints PASS/FAIL lines. Look for SCRIPT ERROR too.
# usage (project dir holding mods-unpacked/ and this file):  godot --no-window --path . -s layers_smoke.gd
# Godot 3.5 headless may segfault inside quit(), after the results have printed; the lines above it count.
const Scene = preload("res://mods-unpacked/Judah-InfDNA/content/colony/colony_scene.gd")
var s
var started := false
var frames := 0
var fails := 0
var max_pairs := 0
var max_fighting := 0


func _init():
	s = Scene.new()
	root.add_child(s)


func _menu_pick(s, wp: Vector2, label_start: String) -> bool:
	s.open_context_menu(s.get_canvas_transform().xform(wp))
	for i in s.cmenu.items.size():
		var it = s.cmenu.items[i]
		if it["t"] == "item" and it["ok"] and str(it["label"]).begins_with(label_start):
			s.cmenu._choose(i)
			return true
	s.cmenu.close()
	return false


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _idle(_delta):
	var sim = s.sim
	if not started:
		started = true
		s.speed = 0.0
		var hit = false
		while not hit and sim.time < 1500.0 and not sim.collapsed:
			sim.step(0.05)
			for e in sim.enemies:
				if e.engaged and e.cls != "prey":
					hit = true
		_check(hit, "reached a fight (t=%.0f, %d ants, %d raiders)" % [sim.time, sim.ants.size(), sim.hostile_count()])
		_check(s.layer_state["fights"] and not s.layer_state["tasks"], "defaults: fights on, tasks off")
		s.set_layer("tasks", true)
		s.set_layer("health", true)
		_check(s.layers_view.show_tasks and s.layers_view.show_health, "set_layer reaches the layers view")
		_check(s.hud._task_legend.visible, "task legend shows with the Tasks layer")
		return false
	frames += 1
	if frames < 120:
		sim.step(0.05)       # keep fighting; the camera follows the first raider
		for e in sim.enemies:
			if e.cls != "prey":
				s.cam.position = sim.enemy_pos(e)
				break
		max_pairs = max(max_pairs, s.layers_view._pairs.size())
		max_fighting = max(max_fighting, s.layers_view._fighting.size())
	elif frames == 120:
		_check(max_pairs > 0 and max_fighting > 0, "fight links found (%d pairs, %d ants fighting)" % [max_pairs, max_fighting])
		for k in s.layer_state.keys():
			var before = s.layer_state[k]
			s.toggle_layer(k)
			s.toggle_layer(k)
			_check(s.layer_state[k] == before and s.hud._layer_btns[k].pressed == before, "toggle round trip: " + k)
		s.hud._layer_btns["fights"].pressed = false
		_check(not s.layer_state["fights"] and not s.layers_view.show_fights, "HUD button turns Fights off")
		s.hud._layer_btns["fights"].pressed = true
		_check(s.layer_state["fights"] and s.layers_view.show_fights, "HUD button turns Fights on")
		s.cam.position = Vector2(sim.grid.entrance.x * 6.0 + 20000.0, 200.0)   # raiders now off screen: arrows get drawn
	elif frames == 125:
		# director commands: Will, cooldowns, effects, the HUD panel and click-to-place arming
		var ex = int(sim.grid.entrance.x)
		sim.will = 100.0
		sim.cmd_cd.clear()
		_check(s.hud._dir_btns.size() == 6, "director panel has six command buttons")
		_check(sim.cast("surge") and sim.surge_t > 0.0, "Surge goes out")
		_check(sim.cast("recall") and sim.recall_t > 0.0, "Recall goes out")
		var any_cover = false
		for a in sim.ants:
			if a.shelter_t > 0.0:
				any_cover = true
		_check(any_cover or sim.ants.empty(), "Recall puts surface ants in cover")
		var pile = null
		for p in sim.piles:
			if p["amount"] > 8.0:
				pile = p
				break
		if pile != null:
			sim.will = 100.0
			_check(sim.cast("harvest", pile["x"]) and sim.harvest_x == pile["x"], "Harvest picks the pile at the cursor")
		sim.will = 100.0
		sim.cmd_cd.clear()
		_check(sim.cast("rally", ex + 20) or sim._inside_n > 0, "Rally goes out (or is refused while raiders are inside)")
		sim.will = 100.0
		sim.cmd_cd.clear()
		_check(sim.cast("breed", 0, sim.ants[0]) and sim.blessed_left == 8, "Breed steers the next eggs from the selected ant")
		sim.will = 100.0
		sim.cast("surge")
		var before = sim.will
		_check(not sim.cast("surge") and sim.will == before, "a command on cooldown costs nothing")
		sim.food = max(sim.food, 300.0)
		sim.will = 100.0
		sim.cmd_cd.clear()
		s.command("rally")
		_check(s.armed == "rally", "a button arms rally for a click")
		s.set_armed("")
		s.hud._on_caste(2)
		_check(sim.caste_order == 2, "caste order lever reaches the sim")
		sim.caste_order = 0
		sim.bird = {"x": float(ex + 60), "t": 20.0, "cd": 0.0, "dive": 0.0, "alt": 1.0, "face": 1, "kills": 0}
		sim.ants[0].shelter_t = 0.0
		for i in 120:
			sim._step_bird(0.1)
		_check(sim.bird == null or sim.bird["t"] < 20.0, "the bird hunts and gives up without errors")
		sim.bird = null
	elif frames == 126:
		# the director's items: Will regeneration and cap, command cost / recharge / strength
		var ex2 = int(sim.grid.entrance.x)
		var saved = sim.mods.duplicate()
		_check(abs(sim.cmd_cost("rally") - float(sim.COMMANDS["rally"]["cost"]) * max(0.4, 1.0 + saved.get("cmd_cost", 0.0))) < 0.01, "commands cost their base price (less any items)")
		sim.mods["will_regen"] = 1.0
		sim.mods["will_max"] = 50.0
		sim.mods["cmd_cost"] = -0.2
		sim.mods["cmd_cd"] = -0.25
		sim.mods["surge_power"] = 0.5
		sim.mods["breed_power"] = 4.0
		sim.mods["rally_power"] = 0.5
		sim.mods["bird_ward"] = 0.5
		_check(abs(sim.will_max() - (sim.WILL_MAX + 50.0)) < 0.01, "Deep Reserve raises the Will cap")
		sim.will = 60.0
		sim._step_director(1.0)
		_check(abs(sim.will - (60.0 + sim.WILL_REGEN * 2.0)) < 0.01, "Queen's Whisper speeds up Will regeneration")
		sim.will = 100.0
		sim.cmd_cd.clear()
		var w0 = sim.will
		_check(sim.cast("surge") and abs((w0 - sim.will) - 25.0 * 0.8) < 0.01, "Frugal Orders cut a command's cost")
		_check(abs(sim.cmd_cd["surge"] - 30.0 * 0.75) < 0.01, "Pheromone Choir shortens the recharge")
		_check(abs(sim.surge_t - 15.0) < 0.01, "Adrenal Glands lengthen Surge")
		sim.will = 100.0
		sim.cmd_cd.clear()
		_check(sim.cast("breed", 0, sim.ants[0]) and sim.blessed_left == 12, "Stud Book adds eggs to Breed")
		if sim._inside_n == 0:
			sim.will = 100.0
			sim.cmd_cd.clear()
			_check(sim.cast("rally", ex2 + 20) and abs(sim.rally_t - sim.RALLY_LEN * 1.5) < 0.01, "War Standard lengthens Rally")
		sim.mods = saved
		sim.surge_t = 0.0
		sim.rally_t = 0.0
		sim.blessed_left = 0
		sim.will = 50.0
		sim.cmd_cd.clear()
	elif frames == 127:
		# seasons: the year changes what the colony gets and eats, and the views follow it
		var Se = sim.Seasons
		var L = Se.SEASON_LEN
		_check(Se.index(0.0) == 0 and Se.index(L * 1.5) == 1 and Se.index(L * 2.5) == 2 and Se.index(L * 3.5) == 3 and Se.index(L * 4.5) == 0, "seasons follow each other")
		_check(Se.snow(L * 3.5) > 0.99 and Se.snow(L * 1.5) == 0.0 and Se.leaf(L * 3.5) == 0.0 and Se.leaf(L * 1.5) == 1.0, "snow and bare trees in winter, leaves in summer")
		_check(Se.food_k(L * 2.5) > 1.2 and Se.food_k(L * 3.5) < 0.6 and Se.upkeep_k(L * 3.5) > 1.1, "autumn is a glut, winter is lean")
		var w_keep = sim.winters
		sim.food = max(sim.food, 300.0)
		sim.time = L * 3.0 - 2.0
		for i in 60:
			sim.step(0.1)
		_check(sim.season == 3 and sim._s_upkeep > 1.0 and sim._s_food < 1.0, "the sim notices winter: ants eat more, less food appears")
		s.day.update(sim.time, 0.0, 0.0)
		_check(s.day.season == 3 and s.day.snow > 0.0 and s.day.stage >= 12, "the day cycle carries the winter to the views")
		sim.time = Se.YEAR_LEN - 2.0
		for i in 80:
			sim.step(0.1)
		_check(sim.season == 0 and sim.winters == w_keep + 1, "living through a winter is counted")
		for i in 25:
			sim.step(0.1)
		_check(sim.goals_done.has("winter1"), "the winter goal is reached")
	elif frames == 128:
		# legacy: choices from the champion strain, born into the next colony's founders
		var Lg = sim.Legacy
		var champ = sim.founder_genome.copy()
		champ.morph["acid"] = 1
		champ.organs["sonic"] = 1
		var cands = Lg.candidates(champ, sim.founder_genome, "test")
		_check(cands.size() >= 2 and cands[0]["kind"] == "organ", "the champion's organs head the heirloom choices")
		var plain = Lg.candidates(sim.founder_genome, sim.founder_genome, "test")
		_check(plain.size() == 1 and plain[0]["kind"] == "mods", "a plain strain still leaves veteran stock")
		var SimC = load("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
		var heir = {"kind": "morph", "key": "acid", "value": 1, "label": "Born with acid glands", "from": "test"}
		var s2 = SimC.new(5, "well_rounded", heir)
		_check(int(s2.founder_genome.m("acid")) == 1 and int(sim.founder_genome.m("acid")) == 0, "the heirloom is born into the next colony's founders")
		var s3 = SimC.new(5, "well_rounded", {"kind": "mods", "key": "", "value": 0.06, "label": "x", "from": "t"})
		_check(abs(s3.mod("hp") - 0.06) < 0.001 and abs(s3.mod("attack") - 0.06) < 0.001, "veteran stock raises hp and attack")
		Lg.save(heir)
		_check(Lg.active().get("key", "") == "acid", "the heirloom is saved")
		Lg.set_use(false)
		_check(Lg.active().empty() and not Lg.saved().empty(), "switching it off keeps it but starts plain")
		Lg.clear()
		_check(Lg.saved().empty(), "clearing forgets it")
		sim.champion = champ
		s.hud._offer_heirlooms(sim)
		_check(s.hud._legacy_row.get_child_count() >= 2, "the run summary offers heirloom choices")
		Lg.clear()
	elif frames == 129:
		# the anteater: it licks ants off the ground near it, and its death pays out
		var n0 = sim.enemies.size()
		sim._spawn_enemy("anteater", 1)
		_check(sim.enemies.size() == n0 + 1 and sim.enemies.back().kind == "anteater", "an anteater can lumber in")
		var at = sim.enemies.back()
		at.x = int(sim.grid.entrance.x) + 3
		at.tx = at.x
		at.y = sim.grid.surf_y(at.x) - 1
		at.ty = at.y
		var near_n = 0
		for a in sim.ants:
			if near_n < 10:
				a.x = at.x + (near_n % 5) - 2
				a.tx = a.x
				a.y = at.y
				a.ty = a.y
				a.z = at.z
				near_n += 1
		var before = sim.ants.size()
		at.tongue_cd = 0.0
		sim._anteater_tongue(at, 0.1)
		_check(sim.ants.size() < before and sim.deaths["anteater"] > 0, "its tongue licks ants off the ground")
		var slain = sim.anteaters_slain
		sim._enemy_die(at)
		_check(sim.anteaters_slain == slain + 1 and not sim.enemies.has(at), "killing it is counted")
		# the rival colony: found by foragers, raids out of its own mound, a strike that breaks it
		var rv = sim.rival
		_check(rv.x > sim.grid.arena_l and rv.x < sim.grid.arena_r and abs(rv.x - int(sim.grid.entrance.x)) >= 80, "a rival nest sits out on the meadow")
		rv.found = false
		sim.will = 100.0
		sim.cmd_cd.clear()
		var wbefore = sim.will
		_check(not sim.cast("strike") and sim.will == wbefore, "Strike needs the rival found, and costs nothing until then")
		sim.ants[0].x = rv.x
		sim.ants[0].tx = rv.x
		sim.ants[0].y = sim.grid.surf_y(rv.x) - 1
		sim.ants[0].ty = sim.ants[0].y
		rv.step(sim, 0.1)
		_check(rv.found, "a forager near the mound finds it")
		sim.will = 100.0
		sim.cmd_cd.clear()
		sim._inside_n = 0
		sim.queen_hp = sim.queen_max
		_check(sim.cast("strike") and sim.strike_t > 0.0 and sim.rally_x == rv.x, "Strike sends the party to the mound")
		var party := 0
		for a in sim.ants:
			if a.task == sim.Task.DEFEND and party < 24:
				a.x = rv.x + (party % 7) - 3
				a.tx = a.x
				a.y = sim.grid.surf_y(a.x) - 1
				a.ty = a.y
				a.z = 0
				party += 1
		rv.step(sim, 0.1)
		var guards := 0
		for e in sim.enemies:
			if e.guard_x == rv.x:
				guards += 1
		_check(rv.guards_out and guards >= 6, "the guards come out when the party arrives (%d)" % guards)
		for e in sim.enemies.duplicate():
			if e.guard_x != 0:
				sim.enemies.erase(e)
		var food0 = sim.food
		for i in 400:
			rv.step(sim, 0.1)
			if rv.broken_t > 0.0:
				break
		_check(rv.conquered == 1 and rv.broken_t > 0.0 and sim.food > food0 and sim.strike_t == 0.0, "with the guards down the party storms the mound: loot, peace, strike over")
		sim.raid_n = 5
		sim._launch_raid()
		_check(not sim._raid_rival, "a broken rival sends no raids")
		rv.broken_t = 0.0
		sim.raid_n = 8
		sim.raid_queue.clear()
		sim._launch_raid()
		var from_rival := 0
		for q in sim.raid_queue:
			if q.get("from_x", 0) == rv.x:
				from_rival += 1
		_check(sim._raid_rival and from_rival > 0, "every third raid marches out of the rival's mound")
		sim.raid_queue.clear()
		# fungus gardens: mould that nurses weed out (the antibiotic item helps), and a garden that matures
		var farm = null
		for c in sim.planner.chambers:
			if c["purpose"] == "farm":
				farm = c
				break
		if farm != null:
			var fk = sim.farm_key(farm)
			var nfarms = sim.planner.count("farm")
			sim.farm_born[fk] = sim.time - 400.0
			sim.farm_mold[fk] = 0.5
			var h_moldy = sim._step_gardens(0.1, nfarms)
			sim.farm_mold.erase(fk)
			var h_clean = sim._step_gardens(0.1, nfarms)
			_check(h_moldy < h_clean, "a mouldy garden gives less")
			sim.farm_mold[fk] = 0.5
			sim._step_gardens(5.0, 0)
			_check(sim.mold_of(farm) > 0.5, "an unattended garden is overgrown")
			sim.farm_mold[fk] = 0.5
			sim._step_gardens(5.0, nfarms * 3)
			_check(sim.mold_of(farm) < 0.5, "nurses weed the mould out")
			sim.farm_mold[fk] = 0.5
			sim._step_gardens(5.0, nfarms)
			var thin = sim.mold_of(farm)
			sim.mods["mold_resist"] = 1.0
			sim.farm_mold[fk] = 0.5
			sim._step_gardens(5.0, nfarms)
			_check(thin > 0.5 and sim.mold_of(farm) < 0.5, "the antibiotic glands turn a losing fight into a won one")
			sim.mods.erase("mold_resist")
			sim.farm_mold.clear()
	elif frames == 130:
		# watch mode (V): HUD hidden, busy layers off, camera directed; leaving restores everything
		sim.strain_events.append({"uid": sim.ants[0].genome.uid, "text": "test strain", "t": sim.time})
		s.show_new_strain()
		_check(s.selected != null and s.selected.genome.uid == sim.ants[0].genome.uid, "N jumps to the newest strain's ant")
		var saved = s.layer_state.duplicate()
		var bar_was = s.hud._bar_panel.visible
		s.set_watch(true)
		_check(s.watch_mode and s.watch.active, "watch mode on")
		_check(not s.hud._bar_panel.visible and not s.hud._mm_panel.visible and not s.hud._left_col.visible, "watch mode hides the HUD panels")
		_check(not s.layer_state["castes"] and not s.layer_state["tasks"] and not s.layer_state["health"], "watch mode switches the busy layers off")
		for i in 40:
			s.watch._process(0.5)
		_check(s.watch._kind != "", "watch camera picked a shot (%s)" % s.watch._kind)
		s.watch.note_input()
		var cam_before = s.cam.position
		s.watch._process(0.5)
		_check(s.cam.position == cam_before, "manual input holds the camera")
		s.set_watch(false)
		var same = true
		for k in saved:
			if s.layer_state[k] != saved[k]:
				same = false
		_check(not s.watch_mode and same and s.hud._bar_panel.visible == bar_was, "leaving watch mode restores the layers and HUD")
	elif frames == 131:
		# the Wild (wild.gd): a fallen colony's champion becomes the next rival: evolved, drawn as your old ants, and worth taking back
		var Wd = load("res://mods-unpacked/Judah-InfDNA/core/wild.gd")
		var Gn = load("res://mods-unpacked/Judah-InfDNA/core/genome.gd")
		var SimC = load("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
		var d0 = Directory.new()
		if d0.file_exists(Wd.PATH):
			d0.copy(Wd.PATH, Wd.PATH + ".bak")
		Wd.clear()
		var wr = RandomNumberGenerator.new()
		wr.seed = 5
		var cg = Gn.make_ant()
		for i in 40:
			cg = cg.mutated(wr, {"armor": 1.0, "organ": 1.5, "morph": 1.0})
		var cg_back = Wd.genome_from_dict(JSON.parse(JSON.print(Wd.genome_to_dict(cg))).result)
		_check(cg_back.describe() == cg.describe(), "a champion survives the trip through the Wild's file format")
		sim.champion = cg
		sim.wild_saved = false
		s.hud._write_wild(sim)
		_check(Wd.lines().size() == 1 and s.hud._wild_label.text != "", "the collapse screen writes the fall into the Wild")
		s.hud._write_wild(sim)
		_check(Wd.lines().size() == 1, "...only once")
		var kin_rec = Wd.active()
		_check(not kin_rec.empty() and Wd.active().get("title", "") == Wd.species_name(cg), "the Wild's strongest line is the next rival's ancestor")
		var ksim = SimC.new(7, "well_rounded", {}, kin_rec)
		_check(ksim.rival.is_kin() and ksim.rival.name == kin_rec["title"] and ksim.rival.evolved >= 3, "the rival descends from it and has evolved (%d steps)" % ksim.rival.evolved)
		var kd = ksim.rival.kin_def("redsoldier")
		_check(kd["kin"] and kd["hp"] > 100.0 and kd["armor"] >= 0.0 and kd["armor"] <= 0.25, "its soldiers fight with their evolved body (hp %.0f, armor %.2f)" % [kd["hp"], kd["armor"]])
		ksim._spawn_enemy("redant", 1)
		_check(ksim.enemies.back().genome != null and ksim.enemies.back().def.get("kin", false), "its raiders carry the genome they are drawn from")
		# the organs the line evolved become the soldiers' abilities (and the small ants do not carry them)
		ksim.rival.genome.organs["electric"] = 2
		ksim.rival.genome.organs["regen"] = 1
		ksim.rival._defs.clear()
		_check(ksim.rival.kin_def("redant")["abil"].empty() and ksim.rival.kin_def("redsoldier")["abil"].empty() and ksim.rival.kin_def("redmajor")["abil"].has("arc") and ksim.rival.kin_def("redmajor")["abil"].has("regen"), "only its majors carry the line's organs as abilities")
		ksim._spawn_enemy("redmajor", 1)
		var ke = ksim.enemies.back()
		ke.x = int(ksim.grid.entrance.x) + 5
		ke.y = ksim.grid.surf_y(ke.x) - 1
		var hp0 := 0.0
		for u in ksim.ants:
			u.x = ke.x + 1
			u.tx = u.x
			u.y = ke.y
			u.ty = u.y
			u.z = ke.z
			hp0 += u.hp
		ke.abil_t["arc"] = 0.0
		ke.hp = ke.max_hp * 0.5
		var kfx = ksim.fx.size()
		ksim._kin_abilities(ke, 0.1)
		var hp1 := 0.0
		for u in ksim.ants:
			hp1 += u.hp
		_check(hp1 < hp0 and ksim.fx.size() > kfx and ke.hp > ke.max_hp * 0.5, "a kin soldier's arc burns the ants beside it, and its flesh regrows")
		var plain = SimC.new(7, "well_rounded")
		plain._spawn_enemy("redant", 1)
		_check(not plain.rival.is_kin() and plain.enemies.back().genome == null, "without a Wild line the rival is the plain red ants")
		ksim.rival._conquer(ksim)
		_check(ksim.blessed != null and ksim.blessed_left > 0, "breaking them takes their best trait back as a batch of eggs")
		ksim.collapsed = true
		ksim.champion = ksim.founder_genome
		ksim.rival.conquered = 1
		var kmsgs = Wd.finish_run(ksim, "Next")
		_check(Wd.lines().size() == 1 and Wd.lines()[0]["id"] != kin_rec["id"] and kmsgs.size() == 2, "a broken line ends; the new fall becomes the next line")
		# a kin raider in the live scene, so the next frames draw one (an error would show above)
		sim.rival.genome = cg
		sim.rival.genome.uid = Wd.KIN_UID
		sim.rival._mods = Wd.kin_mods(cg)
		sim._spawn_enemy("redmajor", 1)
		var live = sim.enemies.back()
		live.x = int(sim.grid.entrance.x) + 6
		live.tx = live.x
		live.y = sim.grid.surf_y(live.x) - 1
		live.ty = live.y
		s.cam.position = sim.grid.center(live.x, live.y)
		Wd.set_use(false)
		_check(Wd.active().empty(), "switching the Wild off starts plain")
		Wd.clear()
		if d0.file_exists(Wd.PATH + ".bak"):
			d0.copy(Wd.PATH + ".bak", Wd.PATH)
			d0.remove(Wd.PATH + ".bak")
	elif frames == 132:
		# direct control: drag a box over ants, right-click to order them, Q to free them, Tab for the full screen
		var Od = load("res://mods-unpacked/Judah-InfDNA/core/orders.gd")
		sim.raid_queue.clear()
		for e in sim.enemies.duplicate():
			sim.enemies.erase(e)
		var ex2 = int(sim.grid.entrance.x)
		s.cam.position = sim.grid.center(ex2, int(sim.grid.entrance.y)) + Vector2(0, -60)
		s.cam.zoom = Vector2.ONE * 0.5
		s.cam.force_update_scroll()
		for i in 3:
			sim.step(0.05)
		var vp = s.get_viewport().get_visible_rect().size
		var press = InputEventMouseButton.new()
		press.button_index = BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(4, 4)
		s._unhandled_input(press)
		var drag = InputEventMouseMotion.new()
		drag.position = vp - Vector2(4, 4)
		s._unhandled_input(drag)
		_check(s.boxing, "dragging more than a few pixels draws a selection box")
		var rel = InputEventMouseButton.new()
		rel.button_index = BUTTON_LEFT
		rel.pressed = false
		rel.position = vp - Vector2(4, 4)
		s._unhandled_input(rel)
		_check(not s.boxing and s.selection.size() > 0, "releasing the box selects the ants inside it (%d)" % s.selection.size())
		_check(s.ant_view.sel_ids.size() == s.selection.size(), "every selected ant gets a ring")
		s.hud._refresh_squad()
		_check(s.hud.mode == 0 and s.hud._tag_panel.visible and s.hud._tag_label.text.find("selected") >= 0 and not s.hud._squad_panel.visible, "view mode: a small tag (not a bar) says how many ants are selected")
		var ordered_before = Od.count(sim)
		var gwp = sim.grid.center(ex2 + 30, sim.grid.surf_y(ex2 + 30) - 10)
		s.open_context_menu(s.get_canvas_transform().xform(gwp))
		_check(s.cmenu.is_open and s.cmenu.items.size() >= 8, "a right-click opens the options menu (%d rows)" % s.cmenu.items.size())
		var labels := []
		for it in s.cmenu.items:
			labels.append(it["label"])
		_check(" | ".join(labels).find("Guard here") >= 0 and " | ".join(labels).find("Rally here") >= 0 and " | ".join(labels).find("Recall") >= 0, "...with orders for the selection and the powers: " + " | ".join(labels))
		s.cmenu.close()
		_check(_menu_pick(s, gwp, "Guard here"), "the menu offers 'Guard here' on open ground")
		_check(Od.count(sim) > ordered_before, "choosing it gives the selection a guard order (%d under orders)" % Od.count(sim))
		var pile_x = -1
		for p in sim.piles:
			if p["amount"] > 10.0:
				pile_x = int(p["x"])
				break
		if pile_x >= 0:
			var wp = sim.grid.center(pile_x, sim.grid.surf_y(pile_x) - 10)
			_check(_menu_pick(s, wp, "Harvest this pile"), "the menu offers 'Harvest this pile' over a food pile")
			var harvesters := 0
			for a in s.selection:
				if a.squad != 0 and sim.squads.has(a.squad) and sim.squads[a.squad]["kind"] == "harvest":
					harvesters += 1
			_check(harvesters > 0, "a right-click on a food pile sends the selection to harvest it (%d)" % harvesters)
		sim.step(0.1)
		var q = InputEventKey.new()
		q.scancode = KEY_Q
		q.pressed = true
		s._unhandled_input(q)
		_check(Od.count(sim) == 0, "Q frees the selected ants")
		# the menu: keys, Esc, quick order, power casting
		s.open_context_menu(s.get_canvas_transform().xform(gwp))
		var esc0 = InputEventKey.new()
		esc0.scancode = KEY_ESCAPE
		esc0.pressed = true
		s.cmenu._input(esc0)
		_check(not s.cmenu.is_open, "Esc closes the menu")
		sim.food = 300.0
		var ob2 = Od.count(sim)
		s._set_selection(s.ant_view.pick_rect(Rect2(s._to_world(Vector2.ZERO), s._to_world(vp) - s._to_world(Vector2.ZERO)).abs()), false)
		s.open_context_menu(s.get_canvas_transform().xform(gwp), true)
		_check(not s.cmenu.is_open and Od.count(sim) > ob2, "Shift + right-click gives the first order without opening the menu")
		sim.will = 100.0
		sim.cmd_cd = {}
		var rt0 = sim.rally_t
		_check(_menu_pick(s, gwp, "Rally here"), "the menu offers Rally")
		_check(sim.rally_t > rt0 and sim.will < 100.0, "choosing Rally plants the flag and spends Will")
		s.open_context_menu(s.get_canvas_transform().xform(gwp))
		var key1 = InputEventKey.new()
		key1.scancode = KEY_1
		key1.pressed = true
		s.cmenu._input(key1)
		_check(not s.cmenu.is_open, "a number key picks the numbered option")
		# orders and powers cost a little food; a hungry colony refuses them; guards nobody is looking at go back to work
		sim.food = 300.0
		sim.will = 100.0
		sim.cmd_cd = {}
		var f0 = sim.food
		sim.cast("surge", 0, null)
		_check(sim.food < f0 and abs((f0 - sim.food) - sim.food_cost("surge")) < 0.01, "a power costs food as well as Will (%.1f)" % (f0 - sim.food))
		sim.food = 6.0
		sim.cmd_cd = {}
		_check(not sim.cast("rally", 0, null), "a power is refused when the larder cannot pay for it")
		var ord_n = Od.count(sim)
		var rr = Od.issue(sim, s.selection, "move", ex2 + 20, sim.grid.surf_y(ex2 + 20) - 2)
		_check(not rr["ok"] and Od.count(sim) == ord_n, "an order is refused when the larder cannot pay for it")
		sim.food = 300.0
		s.release_selection()
		var chosen = s.selection.slice(0, 4)
		var rg = Od.issue(sim, chosen, "move", ex2 + 25, sim.grid.surf_y(ex2 + 25) - 2)
		_check(rg["ok"] and sim.food < 300.0, "a guard order costs food (%.1f)" % (300.0 - sim.food))
		sim.attn_rect = Rect2(-5000.0, -5000.0, 10.0, 10.0)      # the player is looking somewhere else
		sim.attn_sel = {}
		sim.time += Od.LEFT_BEHIND + 5.0
		sim._squad_t = 0.0
		Od.step(sim, 0.1)
		_check(Od.count(sim) == 0, "guards the player has left behind go back to work by themselves")
		sim.attn_rect = Rect2(-10000000.0, -10000000.0, 20000000.0, 20000000.0)
		# the three screens: view (bare), standard, full
		_check(s.hud.mode == 0 and not s.hud._left_col.visible and s.hud._strip.visible and not s.hud._dir_panel.visible and not s.hud._layers_panel.visible, "view mode is bare: no colony card, no panels, just the status line")
		s.hud._edge_reveal(1.0)
		s.hud._edge_reveal(1.0)
		_check(s.hud._mm_panel.visible and not s.hud._bar_panel.visible, "the mouse at the top edge slides the minimap in (and only that)")
		s.hud.cycle_mode()
		_check(s.hud.mode == 1 and s.hud._left_col.visible and s.hud._bar_panel.visible and s.hud._mm_panel.visible and not s.hud._strip.visible and not s.hud._dir_panel.visible, "Tab: the standard screen (colony card, minimap, speed bar)")
		s.hud.cycle_mode()
		_check(s.hud.mode == 2 and s.hud._dir_panel.visible and s.hud._layers_panel.visible, "Tab again: every panel")
		s.hud.cycle_mode()
		_check(s.hud.mode == 0 and not s.hud._dir_panel.visible and not s.hud._bar_panel.visible, "...and back to the bare view")
		_check(s.ug.bare and not s.layer_state["castes"], "view mode also drops the depth gauge, room labels and caste badges")
		var esc = InputEventKey.new()
		esc.scancode = KEY_ESCAPE
		esc.pressed = true
		s._unhandled_input(esc)
		_check(s.selection.empty(), "Esc clears the selection")
		# a bird and a rally flag leave nothing behind on the canvas
		sim.bird = {"x": float(ex2), "t": 0.1, "cd": 9.0, "dive": 0.0, "alt": 0.5, "face": 1, "kills": 0}
		s.pview._process(0.05)
		_check(s.pview._was, "a bird in the air is drawn")
		sim.bird = null
		s.pview._process(0.05)
		_check(not s.pview._was, "the frame after the bird leaves is drawn once more (so it does not stay frozen on screen)")
	elif frames == 140:
		print("RESULT %d failed" % fails)
		quit(1 if fails > 0 else 0)
	return false
