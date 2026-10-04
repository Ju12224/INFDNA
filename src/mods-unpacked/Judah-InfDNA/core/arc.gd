extends Reference
# The long arc of a run, the reason to breed: Monstrosity -> Dominion -> Tremors -> Collapse -> Void -> sealed, and round again, harder.
#
#   GROWING   the colony's strangest ants (the Monstrosity meter, colony_sim._step_apex) have not yet come far from a plain ant.
#   DOMINION  the meter has stayed near full for a while: the meadow belongs to the colony, raiders come less often.
#   TREMORS   it holds: the ground starts to shudder. If the monsters are lost (the meter falls) the ground settles again.
#   VOID      after the last tremor the ground collapses into a crater out in the meadow, and Void Maws claw out of the pit one after
#             another (one the first time, up to three later), each stronger than the last.
#   SEALED    when the last one falls the pit seals over: a reward, the meter must now climb higher (x1.5 each time) and there is a
#             long calm before the next Dominion.
# All of the state is on the sim (arc_*). A colony that is not bred hard never leaves GROWING, so everything else is untouched.

const GROWING = 0
const DOMINION = 1
const TREMORS = 2
const VOID = 3
const NAMES = ["Growing", "Dominion", "Tremors", "The Void"]

const ENTER_AT = 95.0            # meter needed to take the meadow
const ENTER_HOLD = 20.0          # seconds it must hold
const DOMINION_LEN = 150.0       # seconds of Dominion before the ground starts to shake
const TREMORS_N = 8
const COOLDOWN = 240.0           # calm after a sealed void
const TREMOR_WORDS = [
	"The ground shudders.", "Dust trickles from the tunnel roofs.", "Something deep below answers the colony.", "The soil of the meadow splits in long cracks.",
	"The ants stop, antennae raised: the earth is humming.", "Far under the nest, a hollow boom.", "The mound sags and settles.", "The whole meadow lurches.",
]


static func step(sim, dt: float) -> void:
	if sim.arc_cool > 0.0:
		sim.arc_cool = max(0.0, sim.arc_cool - dt)
	match sim.arc_stage:
		GROWING:
			if sim.arc_cool <= 0.0 and sim.monstrosity >= ENTER_AT:
				sim.arc_hold += dt
				if sim.arc_hold >= ENTER_HOLD:
					_enter(sim, DOMINION)
			else:
				sim.arc_hold = max(0.0, sim.arc_hold - dt * 2.0)
		DOMINION:
			sim.raid_timer += dt * 0.4           # raiders keep away from a meadow of monsters
			if sim.monstrosity < 40.0:
				sim.arc_t = 0.0
				sim.toasts.append({"text": "The monsters are gone. The meadow is only a meadow again.", "t": 6.0})
				_enter(sim, GROWING)
				return
			sim.arc_t += dt if sim.monstrosity >= 70.0 else -dt
			sim.arc_t = max(0.0, sim.arc_t)
			if sim.arc_t >= DOMINION_LEN:
				_enter(sim, TREMORS)
		TREMORS:
			sim.raid_timer += dt * 0.4
			sim.arc_t += dt
			if sim.monstrosity < 55.0:
				sim.arc_calm += dt
				if sim.arc_calm > 30.0:
					sim.toasts.append({"text": "The ground settles. Without its monsters the colony is no longer shaking the world.", "t": 6.0})
					sim.arc_tremors = 0
					_enter(sim, DOMINION)
					sim.arc_t = DOMINION_LEN * 0.5
					return
			else:
				sim.arc_calm = 0.0
			var gap = lerp(22.0, 8.0, float(sim.arc_tremors) / TREMORS_N)
			if sim.arc_t >= gap:
				sim.arc_t = 0.0
				_tremor(sim)
				if sim.arc_tremors >= TREMORS_N:
					_enter(sim, VOID)
		VOID:
			sim.arc_t += dt
			if sim.void_left > 0:
				sim.void_next_t -= dt
				if sim.void_next_t <= 0.0:
					_release(sim)
			else:
				for e in sim.enemies:
					if e.kind == "voidmaw" and e.void_born:
						return
				_seal(sim)


static func _enter(sim, stage: int) -> void:
	sim.arc_stage = stage
	sim.arc_t = 0.0
	sim.arc_hold = 0.0
	match stage:
		DOMINION:
			sim.banner = "DOMINION: the meadow belongs to your monsters"
			sim.banner_t = 6.0
			sim.toasts.append({"text": "Dominion! Raiders keep away. Keep the monsters alive: the ground is listening.", "t": 8.0})
			sim._sfx("boss")
		TREMORS:
			sim.arc_tremors = 0
			sim.arc_calm = 0.0
			sim.banner = "The ground begins to shake..."
			sim.banner_t = 5.0
		VOID:
			_collapse(sim)


static func _tremor(sim) -> void:
	var n = sim.arc_tremors
	sim.arc_tremors += 1
	sim.shake = max(sim.shake, 0.45 + 0.07 * n)
	sim.toasts.append({"text": TREMOR_WORDS[int(min(n, TREMOR_WORDS.size() - 1))], "t": 5.0})
	sim._sfx("boss")
	var g = sim.grid
	var ex = int(g.entrance.x)
	for i in 3 + n:
		var x = ex + sim.rng.randi_range(-70, 70)
		sim.fx.append({"kind": "puff", "pos": g.center(x, g.surf_y(x) - 1), "t": 0.0, "color": Color("#8a7458")})
	if n >= 3:
		sim.banner = "TREMOR %d of %d" % [sim.arc_tremors, TREMORS_N]
		sim.banner_t = 2.5


# The ground gives way, out in the meadow, and the pit is where the bosses come from.
static func _collapse(sim) -> void:
	var g = sim.grid
	var ex = int(g.entrance.x)
	var side = 1 if sim.rng.randf() < 0.5 else -1
	var cx = int(clamp(ex + side * sim.rng.randi_range(55, 95), g.arena_l + 20, g.arena_r - 20))
	var top = g.surf_y(cx)
	for k in 5:
		g.carve(cx, top + 3 + k * 3, 7.5 - k * 0.8, 0)
	sim.void_x = cx
	sim.void_left = 1 + int(min(2, sim.void_cycles))
	sim.void_next_t = 6.0
	sim.shake = 1.2
	sim.banner = "THE GROUND COLLAPSES"
	sim.banner_t = 7.0
	sim.toasts.append({"text": "A pit has opened in the meadow, %d cells %s of the nest. Something is climbing out." % [abs(cx - ex), "west" if cx < ex else "east"], "t": 9.0})
	sim._sfx("boss")
	for i in 14:
		var x = cx + sim.rng.randi_range(-12, 12)
		sim.fx.append({"kind": "puff", "pos": g.center(x, g.surf_y(x) - 1), "t": 0.0, "color": Color("#6a4f78")})


static func _release(sim) -> void:
	sim.void_left -= 1
	sim.void_next_t = 55.0
	var before = sim.enemies.size()
	sim._spawn_enemy("voidmaw", -1 if sim.void_x < int(sim.grid.entrance.x) else 1, sim.void_x, 0)
	if sim.enemies.size() > before:
		var e = sim.enemies.back()
		e.void_born = true
		e.max_hp = (700.0 + 5.0 * sim.ants.size() + 2.5 * sim.peak_ms) * sim.fate.raider_hp_mult * (1.0 + 0.35 * sim.void_cycles)
		e.hp = e.max_hp
		sim.toasts.append({"text": "A Void Maw claws out of the pit!%s" % (("  (%d more to come)" % sim.void_left) if sim.void_left > 0 else ""), "t": 6.0})


static func _seal(sim) -> void:
	sim.void_cycles += 1
	var food = 160.0 + 60.0 * sim.void_cycles
	sim.food += food
	sim.ledger["other_in"] += food
	if sim.mutagen < 3:
		sim.mutagen += 1
	sim.arc_cool = COOLDOWN
	sim.banner = "THE VOID IS SEALED  (%d)" % sim.void_cycles
	sim.banner_t = 7.0
	sim.toasts.append({"text": "The pit seals over. +%d food, +1 mutagen. The ground will not break again until the monsters grow stranger still." % int(food), "t": 9.0})
	sim.shake = 0.6
	sim._sfx("repelled")
	_enter(sim, GROWING)


static func label(sim) -> String:
	return NAMES[int(clamp(sim.arc_stage, 0, NAMES.size() - 1))]


# 0..1: how far along the current stage is, for a bar in the HUD.
static func progress(sim) -> float:
	match sim.arc_stage:
		GROWING:
			return clamp(sim.arc_hold / ENTER_HOLD, 0.0, 1.0) if sim.monstrosity >= ENTER_AT else clamp(sim.monstrosity / 100.0, 0.0, 1.0)
		DOMINION:
			return clamp(sim.arc_t / DOMINION_LEN, 0.0, 1.0)
		TREMORS:
			return clamp(float(sim.arc_tremors) / TREMORS_N, 0.0, 1.0)
		VOID:
			var left = sim.void_left
			for e in sim.enemies:
				if e.kind == "voidmaw" and e.void_born:
					left += 1
			return 1.0 - clamp(float(left) / max(1.0, 1.0 + min(2, sim.void_cycles)), 0.0, 1.0)
	return 0.0
