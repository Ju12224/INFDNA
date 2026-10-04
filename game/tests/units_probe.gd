extends SceneTree
# Throwaway: the old view's on-screen ant length (kit_painter layout * 0.55 paint scale * ANT_SCALE 0.24 * CASTE_SCALE).

const Sim = preload("res://core/colony_sim.gd")
const CS = [0.94, 1.0, 1.12]


func _len(g) -> Array:
	var segs: Array = g.segments
	var ns = segs.size()
	var M = g.morph if "morph" in g else {}
	var major = float(M.get("major", 0.0))
	var repl = float(M.get("replete", 0.0))
	var nodes = int(M.get("petiole", 1))
	var HX := []
	var lmax := 0.0
	for i in ns:
		var r: float = segs[i]["r"]
		if i == ns - 1:
			HX.append(r * 0.98 * (1.0 + 0.5 * major))
		elif i == 0 and ns > 1:
			HX.append(r * 1.12 * (1.0 + 0.5 * repl))
		else:
			HX.append(r * 1.3)
		if segs[i]["limb"] == "leg" and segs[i]["n"] > 0:
			lmax = max(lmax, float(segs[i]["len"]))
	var total: float = ((12.0 + 10.0 * nodes) if ns > 2 else 4.0) + 3.0
	for i in ns:
		total += HX[i] * 2.0
		if i > 0 and i < ns - 1:
			total -= HX[i] * 0.18
	var kk = min(1.0, 310.0 / (total + 120.0)) * 0.55
	return [total * kk * 0.24, total]


func _init() -> void:
	var sim = Sim.new(11, "well_rounded")
	print("founder len, leg height (world px): ", _len(sim.founder_genome))
	while sim.time < 600.0 and not sim.collapsed:
		sim.step(0.1)
	var by := [[], [], []]
	for a in sim.ants:
		var l = _len(a.genome)
		var T = 2.1 * a.ph["size"] + 25.0
		by[a.caste].append([l[0], a.ph["size"], l[1], T, 0.132 * T * min(1.0, 310.0 / (T + 120.0)), a.genome.segments.size()])
	for c in 3:
		var arr: Array = by[c]
		arr.sort()
		if arr.size() > 0:
			for i in range(0, arr.size(), 6):
				print(c, " ", arr[i])
	quit()
