extends RefCounted
# Underground structures (v0.35): the soil is more than strata and stones. Each kind of structure is its own module, a script in
# core/ug/<name>.gd, and draws itself with content/colony/ug/<name>_view.gd. This file finds the modules that exist and calls them;
# a missing module is simply skipped, so modules can be added one at a time.
#
# A module script (all functions static, all optional except features):
#   features(grid, xa: int, xb: int) -> Array
#       Every structure that overlaps world columns xa..xb, as dictionaries with at least "x0" and "x1" (the columns it spans) and
#       "kind". It must be a pure function of the world seed and the columns (use grid._ih(a, b, c) for hashing, never a shared rng),
#       so the same structure comes out whether the columns are generated now or later, simulated or only drawn.
#   stamp(grid, f: Dictionary, xa: int, xb: int) -> void
#       Write the structure into the grid arrays for the sim columns xa..xb (grid.solid / grid.mat / grid.under, index
#       y * grid.W + (x - grid.ox), plane 1 at + grid.WH). Called while columns are generated, before walkability is computed.
#       Rules: never touch rows above grid.surf_y(x) + 3, the bottom 3 rows, or the nest area (abs(x - grid._nest_x) < 20 and
#       y < grid._nest_y + 12); only use the existing materials (grid.M_*) so the terrain shader draws them; open cells (solid = 0)
#       are pockets the colony can break into later.
#   on_carve(sim, x: int, y: int, z: int, f: Dictionary) -> void
#       The colony just dug at (x, y) inside or next to this structure (called for structures within 3 cells of the dug cell).
#   step(sim, dt: float, feats: Array) -> void
#       Called about twice a second with the structures inside the sim range (water rising after rain, things growing...).
# A view script (content/colony/ug/<name>_view.gd, static):
#   draw(ci: CanvasItem, sim, feats: Array, t: float, zoom: float) -> void   draw the visible structures (world coordinates)
#   animated() -> bool                                                       true if it changes every frame (else drawn on demand)

const MODULES = ["roots", "caverns", "buried", "veins", "ruins"]
const CORE = "res://core/ug/%s.gd"
const VIEW = "res://views/ug/%s_view.gd"
const CHUNK = 64

var _mods := {}          # name -> script
var _fns := {}           # script path -> {function name: true} (what each module defines)
var _views := {}         # name -> script
var _cache := {}         # "name:chunk" -> features overlapping that chunk
var _step_t := 0.0


# One registry per world: the grid owns it (world_grid.ug), so it is freed with the world. (A registry kept in Engine metadata
# outlived the script engine at quit and crashed the game on exit.)
static func make():
	var r = load("res://core/underground.gd").new()
	r._load()
	return r


func _load() -> void:
	for n in MODULES:
		var p = CORE % n
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			var s = load(p)
			if s != null:
				_mods[n] = s
		var v = VIEW % n
		if ResourceLoader.exists(v) or FileAccess.file_exists(v):
			var sv = load(v)
			if sv != null:
				_views[n] = sv


# Does this module (or view) script define the function? (Godot 3 has no has_method for a script's own static functions.)
func has_fn(script, fn: String) -> bool:
	var key = script.resource_path
	if not _fns.has(key):
		var d := {}
		for m in script.get_script_method_list():
			d[m["name"]] = true
		_fns[key] = d
	return _fns[key].has(fn)


func modules() -> Dictionary:
	return _mods


func views() -> Dictionary:
	return _views


# A new world (a new run) must not reuse the last world's structures.
func reset() -> void:
	_cache.clear()


# The structures of one module overlapping columns xa..xb (cached per 64-column chunk; duplicates across chunks removed).
func features(name: String, grid, xa: int, xb: int) -> Array:
	if not _mods.has(name):
		return []
	var out := []
	var seen := {}
	for k in range(int(floor(float(xa) / CHUNK)), int(floor(float(xb) / CHUNK)) + 1):
		var key = "%s:%d:%d" % [name, grid._seed, k]
		if not _cache.has(key):
			if _cache.size() > 4000:
				_cache.clear()
			_cache[key] = _mods[name].features(grid, k * CHUNK, k * CHUNK + CHUNK - 1)
		for f in _cache[key]:
			var id = "%d:%d:%s" % [int(f["x0"]), int(f["x1"]), str(f.get("kind", ""))] + str(f.get("y", ""))
			if seen.has(id):
				continue
			if int(f["x1"]) < xa or int(f["x0"]) > xb:
				continue
			seen[id] = true
			out.append(f)
	return out


# Called by world_grid after it generates sim columns xa..xb (and after its own stones).
func stamp_range(grid, xa: int, xb: int) -> void:
	for n in _mods.keys():
		var m = _mods[n]
		if not has_fn(m, "stamp"):
			continue
		for f in features(n, grid, xa, xb):
			m.stamp(grid, f, xa, xb)


# Called by the sim after ants dig around (x, y).
func on_carve(sim, x: int, y: int, z: int) -> void:
	for n in _mods.keys():
		var m = _mods[n]
		if not has_fn(m, "on_carve"):
			continue
		for f in features(n, sim.grid, x - 3, x + 3):
			if f.has("y0") and f.has("y1") and (y < int(f["y0"]) - 3 or y > int(f["y1"]) + 3):
				continue
			m.on_carve(sim, x, y, z, f)


func step(sim, dt: float) -> void:
	_step_t -= dt
	if _step_t > 0.0:
		return
	_step_t = 0.5
	for n in _mods.keys():
		var m = _mods[n]
		if has_fn(m, "step"):
			m.step(sim, 0.5, features(n, sim.grid, sim.grid.sim_l(), sim.grid.sim_r()))
