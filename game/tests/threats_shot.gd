extends SceneTree
# Screenshot of the threats (scene/creatures_view.gd, scene/effects_view.gd): runs the colony like tests/shot.gd, then puts creatures in
# view and saves a picture. Needs a display (xvfb-run on a server).
# Run: xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --resolution 1920x1057 --script res://tests/threats_shot.gd -- \
#        out=/tmp/t.png t=300 zoom=1.0 spawn=charger,crab,spider dx=40 gap=22 bird=1 fx=1 piles=1 paused=1
#   spawn  raider kinds (core/enemy_defs.gd), placed on the surface from dx cells right of the entrance, gap cells apart
#   bird   1 = a bird over the spawned row; fall = 1 a bird falling there; carcass = 1 a carcass pile
#   fx     1 = one of every fight effect over the row; piles = 1 = one pile of every kind; stun = 1 snares every raider
#   under  kinds put in the tunnels instead (at the queen chamber)
#   hive   0..3: look at the hive nearest the nest at that stage (whole, dripping, torn open, fallen); lift = camera height over its tree

var _frames := 0
var _node
var _args := {"scene": "res://scene/colony.tscn", "frames": "40", "out": "user://threats.png", "dx": "40", "gap": "22"}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_node = load(_args["scene"]).instantiate()
	root.add_child(_node)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_node.debug_setup(_args)
		_setup()
	if _frames == int(_args["frames"]) - 12 and _args.has("fx"):
		_fx()
	if _frames == int(_args["frames"]):
		var img = root.get_texture().get_image()
		img.save_png(_args["out"])
		print("saved ", _args["out"], " ", img.get_size(), " enemies ", _node.sim.enemies.size())
		quit()
	return false


func _setup() -> void:
	var sim = _node.sim
	var g = sim.grid
	var ex = int(g.entrance.x)
	var x = ex + int(_args["dx"])
	var gap = int(_args["gap"])
	sim.enemies.clear()
	if _args.has("spawn"):
		for kind in str(_args["spawn"]).split(","):
			sim._spawn_enemy(kind, 1, x)
			var e = sim.enemies.back()
			e.x = x
			e.tx = x
			e.y = g.surf_y(x) - 1
			e.ty = e.y
			e.t = 0.0
			e.lane = 0.75
			e.facing = -1
			if _args.has("stun"):
				e.stun_t = 30.0
			x += gap
	if _args.has("under"):
		var cx = int(g.chamber.x) - 8
		for kind in str(_args["under"]).split(","):
			sim._spawn_enemy(kind, 1, cx)
			var e = sim.enemies.back()
			e.x = cx
			e.tx = cx
			e.y = int(g.chamber.y + g.chamber_r.y) - 1
			e.ty = e.y
			e.t = 0.0
			cx += 8
	var mid = (ex + int(_args["dx"]) + x - gap) / 2
	if _args.has("bird"):
		sim.bird = {"x": float(mid), "t": 30.0, "cd": 2.0, "dive": 0.0, "alt": 0.6, "face": -1, "kills": 0, "hp": 90.0, "hp0": 90.0, "hit": 0.0}
	if _args.has("fall"):
		sim.bird_fall = {"x": float(mid), "alt": 0.6, "face": 1, "t": 0.8, "spin": 0.4}
	if _args.has("carcass"):
		sim.piles.append({"x": mid + 30, "amount": 45.0, "max": 45.0, "kind": "carcass", "rot": 0.9, "face": 1, "spin": 0.3})
	if _args.has("piles"):
		sim.piles.append({"x": mid - 30, "amount": 40.0, "max": 40.0})
		sim.piles.append({"x": mid - 15, "amount": 30.0, "max": 36.0, "kind": "fruit"})
		sim.piles.append({"x": mid, "amount": 30.0, "max": 48.0, "kind": "honey"})
		sim.piles.append({"x": mid + 15, "amount": 110.0, "max": 110.0, "kind": "jackpot"})
	if _args.has("rival"):
		sim.rival.x = mid
	if _args.has("look"):
		_node.cam.position = g.center(mid, g.surf_y(mid)) + Vector2(0, float(_args.get("lift", "-60")))
	if _args.has("hive"):
		# the hive nearest the nest, at stage hive=0..3 (whole, dripping, torn, fallen), in the middle of the view
		var best = null
		for id in sim.hives:
			if best == null or abs(sim.hives[id]["x"] - ex) < abs(best["x"] - ex):
				best = sim.hives[id]
		if best != null:
			var stg = int(_args["hive"])
			best["taken"] = [0.0, 80.0, 160.0, 230.0][stg]
			best["fallen"] = stg == 3
			_node.cam.position = g.center(int(best["x"]), g.surf_y(int(best["x"]))) + Vector2(0, float(_args.get("lift", "-300")))
			print("hive at ", best["x"], " (nest ", ex, ")")
	if _args.has("paused"):
		_node.paused = true


func _fx() -> void:
	var sim = _node.sim
	var g = sim.grid
	var x = int(g.entrance.x) + int(_args["dx"])
	var gap = int(_args["gap"])
	var p = g.center(x, g.surf_y(x) - 1)
	var step = Vector2(gap * g.CELL, 0)
	var kinds = ["puff", "spark", "burst", "wave", "arc", "web", "acid"]
	var life = [1.0, 0.45, 0.8, 0.6, 0.28, 1.4, 0.9]
	var k = float(_args.get("fxk", "0.3"))     # how far through its life each effect is (a paused shot holds it there)
	for i in kinds.size():
		var f = {"kind": kinds[i], "pos": p + step * i + Vector2(0, -16), "t": k * life[i], "color": Color("#ffe08a"), "r": 40.0}
		if kinds[i] == "arc":
			f["to"] = f["pos"] + Vector2(70, -10)
		sim.fx.append(f)
	sim.fx.append({"kind": "text", "pos": p + Vector2(0, -70), "t": k * 1.2, "text": "+24", "color": Color("#a8ec74")})
	if not sim.ants.is_empty():
		var a = sim.ants[0]
		sim.fx.append({"kind": "corpse", "pos": p + step * 3.5, "t": k * 0.9, "color": Color(1, 1, 1), "genome": a.genome, "id": a.id, "lane": 0.75,
			"caste": a.caste, "face": 1, "rot": 0.0, "old": false, "carry": false})
