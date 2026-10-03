extends Reference
# The neighbours. A rival ant colony keeps a nest on the open ground 80-110 cells from yours, east or west. Every third raid
# is theirs: their ants march out of their own mound and across the meadow (so you can see them coming, and what you do to
# the raid matters to them). Their strength grows with time and falls when their raids break against you.
#
# Once your foragers have found the mound you can Strike (a Director command): a strike party, soldiers first, goes to the
# nest, fights the guards that come out, then storms the mound. If it wins the colony is broken for five minutes (no raids from
# it) and you carry off its stores.
#
# Pure data plus a step; the sim owns the ants and the raiders, the view (rival_view.gd) draws the mound.
#
# The Descendants (wild.gd): when an earlier colony of yours fell, its champion strain went into the Wild, and the strongest such line
# IS this rival: `genome` is that body plan evolved a few more steps, its raiders and guards are drawn as your old ants and get their
# stats from its body (kin_def), and it keeps evolving between its raids. Beat it and you take its best trait back (_reclaim).

const Wild = preload("res://mods-unpacked/Judah-InfDNA/core/wild.gd")
const Legacy = preload("res://mods-unpacked/Judah-InfDNA/core/legacy.gd")
const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")
const NAMES = ["Red Pharaohs", "Black Raiders", "Fire Legion", "Thorn Clan", "Stone Marchers"]
const KIN_KINDS = ["redant", "redsoldier", "redmajor"]
const EVOLVE_BIAS = {"armor": 0.8, "spike": 0.6, "claw": 0.6, "size": 0.5, "leg": 0.4, "organ": 1.0}
const RECLAIM_EGGS = 12
const STRIKE_LEN = 55.0
const PEACE = 300.0

var x := 0                    # world column of its mound
var side := 1                 # +1 east of your nest, -1 west
var name := "Red Pharaohs"
var power := 4.0              # grows over time, falls when its raids fail and when you break it
var hp := 140.0               # the mound's health during a strike
var max_hp := 140.0
var food := 150.0             # what a conquest carries off
var found := false            # your foragers have seen it
var broken_t := 0.0           # seconds of peace left after a conquest
var guards_out := false       # this strike's guards have come out
var conquered := 0
var raids := 0                # raids it has sent
var hit_t := 0.0              # the view flashes the mound while it is being hit
var guards_total := 0         # how many guards came out (for the view's bar)
var kin := {}                 # the Wild line this rival descends from ({} = the plain red ants)
var genome = null             # its body plan, evolved (kin only)
var evolved := 0              # evolution steps taken
var _mods := {}
var _defs := {}


func setup(sim) -> void:
	var rr = sim.sub_rng("rival", 1)
	side = -1 if rr.randf() < 0.5 else 1
	var ex = int(sim.grid.entrance.x)
	x = int(clamp(ex + side * rr.randi_range(82, 112), sim.grid.arena_l + 16, sim.grid.arena_r - 16))
	name = NAMES[rr.randi_range(0, NAMES.size() - 1)]
	kin = sim.kin
	if not kin.empty() and kin.has("genome"):
		genome = Wild.genome_from_dict(kin["genome"])
		genome.uid = Wild.KIN_UID
		name = str(kin.get("title", name))
		_mods = Wild.kin_mods(genome)
		# while you were away it kept evolving: a few steps, more for a line that has survived runs and for a colony that went far
		var steps = 3 + 2 * int(kin.get("runs", 0)) + int(float(kin.get("raids", 0)) / 6.0)
		for i in int(clamp(steps, 3, 14)):
			evolve(sim)


func is_kin() -> bool:
	return genome != null


# One step of evolution: of three mutants of the current body the strongest lives. The same rule runs between its raids.
func evolve(sim) -> void:
	if genome == null:
		return
	var rr = sim.sub_rng("kin", evolved + 1)
	var best = null
	var bp := -1.0
	for i in 3:
		var c = genome.mutated(rr, EVOLVE_BIAS)
		var p = Wild.power(c)
		if p > bp:
			bp = p
			best = c
	evolved += 1
	best.uid = Wild.KIN_UID + evolved
	genome = best
	_mods = Wild.kin_mods(genome)
	_defs.clear()


# The raider definition for one of the rival's castes: the red ant's numbers bent by the body the line has evolved.
func kin_def(kind: String) -> Dictionary:
	if not _defs.has(kind):
		var d = EnemyDefs.DEFS[kind].duplicate()
		d["hp"] = float(d["hp"]) * float(_mods["hp_k"])
		d["dmg"] = float(d["dmg"]) * float(_mods["dmg_k"])
		d["speed"] = float(d["speed"]) * float(_mods["speed_k"])
		d["armor"] = float(_mods["armor"])
		d["art"] = ""
		d["kin"] = true
		d["abil"] = abilities() if d["cls"] == "elite" else {}      # only the rare majors carry the line's organs into a fight (a first test with every soldier doing it wiped the colony out)
		_defs[kind] = d
	return _defs[kind]


# What the kin's majors do with the organs their line has evolved: your own abilities, turned on you. Each organ line from tier 1 up gives
# the matching one, stronger with every tier (your own ants only get theirs at tier 3). {name: {cd, dmg, r, n}}
func abilities() -> Dictionary:
	var out := {}
	if genome == null:
		return out
	var t = genome.organ("electric")
	if t >= 1:
		out["arc"] = {"cd": 5.5 - 0.5 * t, "dmg": 5.0 + 3.5 * t, "r": 6, "n": min(t, 2)}     # an electric bolt into one or two ants
	t = genome.organ("sonic")
	if t >= 1:
		out["pulse"] = {"cd": 8.0 - 0.7 * t, "dmg": 2.5 + 1.5 * t, "r": 3 + t, "n": 6}    # a shockwave over the six nearest
	t = genome.organ("tongue")
	if t >= 1:
		out["lash"] = {"cd": 5.5 - 0.5 * t, "dmg": 4.0 + 3.5 * t, "r": 6 + t, "n": 1}      # a tongue that snaps out and back
	t = genome.organ("regen")
	if t >= 1:
		out["regen"] = {"rate": 0.004 * t}                                                   # a share of its health back every second
	return out


func ability_text() -> String:
	var names := []
	var a = abilities()
	if a.has("arc"):
		names.append("electric arcs")
	if a.has("pulse"):
		names.append("sonic pulses")
	if a.has("lash"):
		names.append("a lashing tongue")
	if a.has("regen"):
		names.append("regrowing flesh")
	return PoolStringArray(names).join(", ")


func flag_color() -> Color:
	return genome.color.lightened(0.15) if genome != null else Color("#b32424")


func alive() -> bool:
	return broken_t <= 0.0


func can_strike() -> bool:
	return found and alive()


func where(sim) -> String:
	return "west" if x < int(sim.grid.entrance.x) else "east"


func step(sim, dt: float) -> void:
	hit_t = max(0.0, hit_t - dt)
	if broken_t > 0.0:
		broken_t = max(0.0, broken_t - dt)
		if broken_t <= 0.0:
			hp = max_hp
			sim.toasts.append({"text": "The %s have rebuilt their nest in the %s." % [name, where(sim)], "t": 7.0})
		return
	power += dt * 0.011
	max_hp = 120.0 + power * 2.5
	if sim.strike_t <= 0.0:
		hp = min(max_hp, hp + dt * 1.2)
	if not found:
		for a in sim.ants:
			if abs(a.x - x) <= 42 and not sim.grid.is_under(a.x, a.y):
				found = true
				var d = abs(x - int(sim.grid.entrance.x))
				sim.banner = "Foragers found a rival nest: the %s, %d cells %s." % [name, d, where(sim)]
				sim.banner_t = 5.0
				if genome != null:
					sim.toasts.append({"text": "The %s, %d cells %s: the descendants of your own colony #%d. They kept evolving without you." % [name, d, where(sim), int(kin.get("id", 0))], "t": 12.0})
					if ability_text() != "":
						sim.toasts.append({"text": "Their majors have evolved %s: your own organs, turned on you." % ability_text(), "t": 12.0})
				else:
					sim.toasts.append({"text": "The %s live %d cells %s of the nest. They will raid you; Strike (Y) when you are ready to break them." % [name, d, where(sim)], "t": 10.0})
				sim._sfx("boss")
				break
	if sim.strike_t > 0.0 or _party_at_mound(sim) >= 5:
		_strike(sim, dt)
	elif guards_out and not _guards_alive(sim):
		guards_out = false


# Five or more ants under the player's own guard or attack order standing at the mound are a strike party just as the Strike power's is: the guards
# come out and, with them down, the party storms the mound (no Will needed: sending them is the player's call).
func _party_at_mound(sim) -> int:
	if sim.squads.empty():
		return 0
	var n := 0
	for a in sim.ants:
		if a.squad != 0 and abs(a.x - x) <= 26 and not sim.grid.is_under(a.x, a.y):
			var sq = sim.squads.get(a.squad)
			if sq != null and (sq["kind"] == "move" or sq["kind"] == "attack"):
				n += 1
	return n


func _guards_alive(sim) -> bool:
	for e in sim.enemies:
		if e.guard_x != 0:
			return true
	return false


# While the strike party is out: its arrival brings the guards out; with the guards down the party storms the mound.
func _strike(sim, dt: float) -> void:
	var near := 0
	var arrived := false
	for a in sim.ants:
		if sim.grid.is_under(a.x, a.y):
			continue
		var d = abs(a.x - x)
		if d <= 26 and a.task == sim.Task.DEFEND:
			arrived = true
		if d <= 9 and a.task == sim.Task.DEFEND:
			near += 1
	var alive_g = _guards_alive(sim)
	if arrived and not guards_out:
		guards_out = true
		var soldiers = int(clamp(2 + int(power / 9.0), 2, 8))
		guards_total = soldiers * 3
		for i in soldiers:
			sim._spawn_enemy("redsoldier", side, x + sim.rng.randi_range(-5, 5), x)
		for i in soldiers * 2:
			sim._spawn_enemy("redant", side, x + sim.rng.randi_range(-6, 6), x)
		sim.banner = "The %s guards pour out of the mound!" % (name + ("'" if name.ends_with("s") else "'s"))
		sim.banner_t = 4.0
		sim._sfx("raid")
		return
	if guards_out and not alive_g and near > 0:
		hp -= min(near, 30) * 0.5 * dt
		hit_t = 0.4
		if sim.rng.randf() < dt * 3.0:
			sim.fx.append({"kind": "puff", "pos": sim.grid.center(x + sim.rng.randi_range(-4, 4), sim.grid.surf_y(x) - 2), "t": 0.0, "color": Color("#9a8470")})
		if hp <= 0.0:
			_conquer(sim)


func _conquer(sim) -> void:
	conquered += 1
	broken_t = PEACE
	var loot = food + 40.0 + power * 3.0
	sim.food += loot
	sim.ledger["other_in"] += loot
	var extra = ""
	if sim.mutagen < 3:
		sim.mutagen += 1
		extra = " +1 mutagen"
	power = max(2.0, power * 0.5)
	food = 120.0 + power * 4.0
	sim.strike_t = 0.0
	sim.rally_t = 0.0
	guards_out = false
	sim.banner = "The %s are broken!" % name
	sim.banner_t = 5.0
	sim.toasts.append({"text": "You stormed the %s: +%d food%s. No raids from them for %d minutes." % [name, int(loot), extra, int(PEACE / 60.0)], "t": 10.0})
	if genome != null:
		_reclaim(sim)
	sim.fx.append({"kind": "ring", "pos": sim.grid.center(x, sim.grid.surf_y(x) - 4), "t": 0.0, "color": Color("#ffd86b")})
	sim.fx.append({"kind": "text", "pos": sim.grid.center(x, sim.grid.surf_y(x) - 9), "t": 0.0, "text": "CONQUERED", "color": Color("#ffd86b")})
	sim.shake = max(sim.shake, 0.6)
	sim._sfx("repelled")


# The kin's best trait comes home: the next eggs are bred from your champion strain with it grafted on (the mutagen mechanism).
func _reclaim(sim) -> void:
	var base = sim.champion if sim.champion != null else sim.founder_genome
	var cands = Legacy.candidates(genome, base, "the " + name)
	var h = cands[0]
	if str(h.get("kind", "")) == "mods":
		sim.toasts.append({"text": "Their bodies held nothing your ants lack, but the stores are yours.", "t": 7.0})
		return
	var hybrid = base.copy()
	Legacy.apply(h, hybrid)
	hybrid._set_link(base.node(), "", "reclaimed from the " + name + ": " + str(h["label"]).to_lower())
	sim.register_genome(hybrid, sim.max_gen)
	sim.blessed = hybrid
	sim.blessed_left = RECLAIM_EGGS
	sim.toasts.append({"text": "You took it back: %s. The next %d eggs carry it." % [str(h["label"]).to_lower(), RECLAIM_EGGS], "t": 10.0})
