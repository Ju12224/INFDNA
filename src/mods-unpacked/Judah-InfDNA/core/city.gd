extends Reference
# The underground city. As the colony grows it unlocks workshops; each built workshop
# slowly produces upgrades while nurses tend it (up to a cap per workshop kind).
# The colony also reaches farther: the nest may spread wider, frontier food appears
# beyond the old playfield, and outposts (new entrances) are dug far from the main shaft.
# No Brotato dependencies.

const WORKSHOPS = {
	"armory": {"name": "Armory", "unlock": 45, "every": 80.0,
		"fx": {"armor": 0.012}, "cap": {"armor": 0.18},
		"msg": "The armory hardened a batch of chitin plates: +1.2% damage ignored."},
	"cistern": {"name": "Cistern", "unlock": 55, "every": 90.0,
		"fx": {"regen": 0.15}, "cap": {"regen": 2.0},
		"msg": "The cistern filled: wounded ants drink and heal faster."},
	"venom": {"name": "Venom Works", "unlock": 65, "every": 80.0,
		"fx": {"attack": 0.03, "thorns": 0.06}, "cap": {"attack": 0.4, "thorns": 0.8},
		"msg": "The venom works brewed poison: +3% attack, +6% thorns."},
	"battery": {"name": "Sting Battery", "unlock": 75, "every": 70.0,
		"fx": {"tunnel_dmg": 0.6, "siege_dmg": 0.5}, "cap": {"tunnel_dmg": 8.0, "siege_dmg": 6.0},
		"msg": "The sting battery fletched more darts: raiders in the tunnels and at the gates take more damage."},
	"architects": {"name": "Architects' Hall", "unlock": 90, "every": 100.0,
		"fx": {"dig": 0.04}, "cap": {"dig": 0.6},
		"msg": "The architects drew new plans: +4% dig speed, and the city may spread wider."},
}
const ORDER = ["armory", "cistern", "venom", "battery", "architects"]
const PER_KIND = 2            # workshops of each kind the planner will build
const BASE_SPREAD = 170
const MAX_OUTPOSTS = 4

var unlocked := {}
var progress := {}            # kind -> seconds of tended work
var given := {}               # mod key -> total the city has added (for caps)
var batches := 0
var outposts := 0
var _outpost_t := 150.0
var _tick := 0.0


func wanted(sim) -> Array:
	var out := []
	for k in ORDER:
		if unlocked.get(k, false) and sim.planner.count(k) < PER_KIND:
			out.append(k)
	return out


func step(sim, dt: float) -> void:
	_tick -= dt
	if _tick > 0.0:
		return
	var step_dt = 1.0 - _tick
	_tick = 1.0
	var n = sim.ants.size()
	# unlocks
	for k in ORDER:
		if not unlocked.get(k, false) and n >= WORKSHOPS[k]["unlock"]:
			unlocked[k] = true
			sim.toasts.append({"text": "The colony has grown: it can now build a %s." % WORKSHOPS[k]["name"], "t": 8.0})
	sim.planner.wanted_rooms = wanted(sim)
	# reach: the nest spreads wider as the colony grows
	var arch = sim.planner.count("architects")
	sim.planner.max_spread = int(min(520, BASE_SPREAD + n * 1.2 + arch * 60))
	sim.planner.max_jobs = max(sim.planner.max_jobs, 3 + arch)
	# production: tended by nurses
	var nurses = 0
	for a in sim.ants:
		if a.task == 0:
			nurses += 1
	var staff = clamp(nurses / 8.0, 0.25, 1.5)
	var changed = false
	for k in ORDER:
		var built = sim.planner.count(k)
		if built <= 0:
			continue
		progress[k] = progress.get(k, 0.0) + step_dt * staff * built
		var w = WORKSHOPS[k]
		if progress[k] >= w["every"]:
			progress[k] -= w["every"]
			var gave = false
			for key in w["fx"].keys():
				var room = w["cap"][key] - given.get(key, 0.0)
				var add = min(w["fx"][key], room)
				if add > 0.0:
					sim.mods[key] = sim.mods.get(key, 0.0) + add
					given[key] = given.get(key, 0.0) + add
					gave = true
			if gave:
				batches += 1
				changed = true
				sim.toasts.append({"text": w["msg"], "t": 6.0})
	if changed:
		sim._refresh_phenotypes()
	_step_outposts(sim, step_dt)


# Outposts: far entrances that give foragers a second front door and a siege a second target.
func _step_outposts(sim, dt: float) -> void:
	var n = sim.ants.size()
	if n < 70 or outposts >= MAX_OUTPOSTS or outposts >= 1 + n / 60:
		return
	_outpost_t -= dt
	if _outpost_t > 0.0:
		return
	_outpost_t = 180.0
	outposts += 1
	var side = 1 if outposts % 2 == 1 else -1
	var ex = int(sim.grid.entrance.x)
	var x = ex + side * (70 + 35 * outposts)
	sim.grid.add_entrance(x)
	sim.toasts.append({"text": "Outpost %d dug %s of the main nest." % [outposts, "east" if side > 0 else "west"], "t": 8.0})


# Share of new food piles that appear on the frontier, beyond the old playfield.
func frontier_share(sim) -> float:
	return clamp((sim.ants.size() - 40) / 160.0, 0.0, 0.45)


func frontier_reach(sim) -> int:
	return int(min(320, 40 + sim.ants.size() * 1.4))
