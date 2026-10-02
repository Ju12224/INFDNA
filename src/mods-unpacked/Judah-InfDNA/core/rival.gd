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

const NAMES = ["Red Pharaohs", "Black Raiders", "Fire Legion", "Thorn Clan", "Stone Marchers"]
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


func setup(sim) -> void:
	var rr = sim.sub_rng("rival", 1)
	side = -1 if rr.randf() < 0.5 else 1
	var ex = int(sim.grid.entrance.x)
	x = int(clamp(ex + side * rr.randi_range(82, 112), sim.grid.arena_l + 16, sim.grid.arena_r - 16))
	name = NAMES[rr.randi_range(0, NAMES.size() - 1)]


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
				sim.toasts.append({"text": "The %s live %d cells %s of the nest. They will raid you; Strike (Y) when you are ready to break them." % [name, d, where(sim)], "t": 10.0})
				sim._sfx("boss")
				break
	if sim.strike_t > 0.0:
		_strike(sim, dt)
	elif guards_out and not _guards_alive(sim):
		guards_out = false


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
		sim.banner = "The %s's guards pour out of the mound!" % name
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
	sim.fx.append({"kind": "ring", "pos": sim.grid.center(x, sim.grid.surf_y(x) - 4), "t": 0.0, "color": Color("#ffd86b")})
	sim.fx.append({"kind": "text", "pos": sim.grid.center(x, sim.grid.surf_y(x) - 9), "t": 0.0, "text": "CONQUERED", "color": Color("#ffd86b")})
	sim.shake = max(sim.shake, 0.6)
	sim._sfx("repelled")
