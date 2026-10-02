extends Reference
# Fate: the part of the run you don't fully control.
#  - Lab items with hidden side effects (real from the moment you buy, revealed later)
#  - gamble items that roll their outcome on purchase
#  - synergies between owned items (some with a price of their own)
#  - random colony events, and the monoculture plague that punishes cloning one winner
#  - milestone toasts the first time a new organ evolves
# No Brotato dependencies; talks to the sim through its public fields and methods.

const DIG_TASK = 2        # ColonySim.Task.DIG
const ShopItems = preload("res://mods-unpacked/Judah-InfDNA/core/shop_items.gd")

const SYNERGIES = [
	{"id": "venom", "name": "Venom Lance", "need": ["sting", "formic"], "desc": "stingers carry acid: +100% thorns, +20% attack", "fx": {"mods": {"thorns": 1.0, "attack": 0.2}}},
	{"id": "firefly", "name": "Firefly Swarm", "need": ["alate", "glow"], "desc": "glowing alates light the way: +8 sense, +10% speed", "fx": {"mods": {"sense": 8.0, "speed": 0.1}}},
	{"id": "fortress", "name": "Honey Fortress", "need": ["replete", "chitin"], "desc": "armored honeypots: +25% HP", "fx": {"mods": {"hp": 0.25}}},
	{"id": "titans", "name": "Army of Titans", "need": ["major", "giant"], "desc": "huge soldiers: +30% attack, but they eat 15% more", "fx": {"mods": {"attack": 0.3, "upkeep": 0.15}}},
	{"id": "plague_engine", "name": "Plague Engine", "need": ["purebred", "flesh"], "desc": "the sick feed the healthy: +4 food per fallen ant", "fx": {"mods": {"corpse_food": 4.0}}},
	{"id": "berserk", "name": "Berserk Tide", "need": ["drums", "cannon"], "desc": "+30% attack, -10% HP", "fx": {"mods": {"attack": 0.3, "hp": -0.1}}},
	{"id": "sugar_econ", "name": "Sugar Economy", "need": ["sugar", "piggy"], "desc": "the cellar keeps sugar fresh: spoilage halved", "fx": {"mods": {"spoilage": -0.2}}},
	{"id": "overdrive", "name": "Hive Overdrive", "need": ["coffee", "elixir"], "desc": "eggs hatch 15% faster, ants eat 10% more", "fx": {"colony": {"hatch": 0.85}, "mods": {"upkeep": 0.1}}},
	{"id": "trailblaze", "name": "Trailblazers", "need": ["trail", "detector"], "desc": "scent + antennae: food piles appear closer", "fx": {"mods": {"pile_near": 1.0}}},
	{"id": "ghosts", "name": "Ghost Colony", "need": ["camo", "flag"], "desc": "raiders barely find you: raids 15% smaller", "fx": {"mods": {"raid_size": -0.15}}},
	{"id": "idol_pact", "name": "Blood Pact", "need": ["idol", "drums"], "desc": "the idol drinks the war: +25% attack, ants live 10% shorter", "fx": {"mods": {"attack": 0.25, "life": -0.1}}},
]

# Milestone names for the first ant carrying each organ.
const FIRSTS = {
	"wings": "First winged alate hatched!",
	"stinger": "First ant with a stinger!",
	"acid": "First acid gland evolved!",
	"glow": "First glowing ant lights the tunnels!",
	"major": "First big-headed major!",
	"replete": "First honeypot replete!",
	"camo": "First camouflaged ant!",
}

var revealed := {}        # item id -> true once its side effect is known
var gamble_text := {}     # item id -> what the gamble rolled (latest)
var pending := []         # [{id, t, trigger}] side effects not yet noticed
var synergy_on := {}
var firsts := {}
var ray_eggs := 0         # eggs that will mutate twice (cosmic ray event)
var bonus_offers := 0     # extra Lab slots next visit (trader event)
var event_timer := 200.0
var events_seen := 0
var _plague_t := 75.0
var _cave_t := 50.0
var _drain_warned := false


# Shop text: hidden side effects show as ??? until noticed.
func item_desc(sim, id: String) -> String:
	var it = ShopItems.ITEMS[id]
	var d: String = it["desc"]
	if it.has("gamble"):
		if gamble_text.has(id):
			d += "\nLast roll: " + gamble_text[id]
		return d
	for syn in SYNERGIES:
		if synergy_on.get(syn["id"], false) or not (id in syn["need"]):
			continue
		var rest = 0
		for need in syn["need"]:
			if need != id and sim.owned.get(need, 0) <= 0:
				rest += 1
		if rest == 0:
			d += "\nCompletes combo: " + syn["name"]
	if it.has("hidden"):
		if cleansed.get(id, false):
			d += "\nSide effect: cured"
		elif revealed.get(id, false):
			d += "\nSide effect: " + it["hidden_desc"]
		else:
			d += "\nSide effect: ???"
	return d


func on_buy(sim, id: String) -> void:
	var it = ShopItems.ITEMS[id]
	if it.has("hidden"):
		sim._apply_effects(it["hidden"])
		if not revealed.get(id, false):
			pending.append({"id": id, "t": float(it.get("reveal", 60.0)), "trigger": it.get("reveal_on", "time")})
	if it.get("cleanse", false):
		cleanse(sim)
	if it.has("gamble"):
		var rolls: Array = it["gamble"]
		var r = rolls[sim.rng.randi_range(0, rolls.size() - 1)]
		sim._apply_effects(r)
		if r.has("food"):
			sim.food += float(r["food"])
		gamble_text[id] = r["text"]
		pending.append({"id": id, "t": 20.0, "trigger": "gamble"})
	_check_synergies(sim)


func _check_synergies(sim) -> void:
	for s in SYNERGIES:
		if synergy_on.get(s["id"], false):
			continue
		var ok = true
		for need in s["need"]:
			if sim.owned.get(need, 0) <= 0:
				ok = false
				break
		if ok:
			synergy_on[s["id"]] = true
			sim._apply_effects(s["fx"])
			sim.toasts.append({"text": "SYNERGY - %s: %s" % [s["name"], s["desc"]], "t": 9.0})
			sim.banner = "Synergy: " + s["name"]
			sim.banner_t = 3.0


func synergy_names() -> Array:
	var out := []
	for s in SYNERGIES:
		if synergy_on.get(s["id"], false):
			out.append(s["name"])
	return out


func _reveal(sim, p: Dictionary) -> void:
	var id: String = p["id"]
	var it = ShopItems.ITEMS[id]
	pending.erase(p)
	if p["trigger"] == "gamble":
		sim.toasts.append({"text": "%s hatched: %s" % [it["name"], gamble_text.get(id, "?")], "t": 9.0})
		return
	revealed[id] = true
	sim.toasts.append({"text": "SIDE EFFECT - %s: %s" % [it["name"], it["hidden_desc"]], "t": 10.0})


func _trigger(sim, kind: String) -> void:
	for p in pending.duplicate():
		if p["trigger"] == kind:
			_reveal(sim, p)


func on_raid(sim) -> void:
	_trigger(sim, "raid")
	_adapt_raiders(sim)


# Raiders counter-evolve: the stronger your ants' evolved bodies (not Lab buffs),
# the tougher the next raiders. Evolution buys time, it doesn't win the run alone.
var raider_hp_mult := 1.0
# M4 trait counters (counter_mode 1): raiders answer what the colony evolved.
#   pierce: share of ant armor raiders ignore (answers armor plates, hair, camo)
#   hide:   share of thorn/acid damage raiders shrug off (answers spines, acid)
# Each point of specific counter replaces some flat HP, so total threat stays similar
# but the counter hits the trait you leaned on. counter_mode 0 = v0.17 flat HP only.
var counter_mode := 0
var raider_pierce := 0.0
var raider_hide := 0.0

func _adapt_raiders(sim) -> void:
	if sim.ants.empty():
		return
	var base = sim.phenotype(sim.founder_genome)
	var att := 0.0
	var hp := 0.0
	var red := 0.0
	var thorns := 0.0
	for a in sim.ants:
		att += a.ph["attack"]
		hp += a.ph["hp"]
		red += a.ph["armor_red"]
		thorns += a.ph["thorns"]
	var n = float(sim.ants.size())
	att /= n
	hp /= n
	red /= n
	thorns /= n
	var ratio = 0.5 * att / max(0.1, base["attack"]) + 0.5 * hp / max(1.0, base["hp"])
	var spec := 0.0
	if counter_mode >= 1:
		var p_target = clamp((red - base["armor_red"]) / 0.3, 0.0, 1.0) * 0.5
		var h_target = clamp((thorns - base["thorns"]) / 3.0, 0.0, 1.0) * 0.5
		if p_target > raider_pierce + 0.08:
			sim.toasts.append({"text": "Raiders evolved piercing jaws: your armor stops %d%% less." % int(round(p_target * 100.0)), "t": 7.0})
		if h_target > raider_hide + 0.08:
			sim.toasts.append({"text": "Raiders grew thick hides: spines and acid hurt them %d%% less." % int(round(h_target * 100.0)), "t": 7.0})
		raider_pierce = lerp(raider_pierce, p_target, 0.6)
		raider_hide = lerp(raider_hide, h_target, 0.6)
		spec = raider_pierce + raider_hide
	var target = clamp(1.0 + 0.5 * (ratio - 1.0) * (1.0 - 0.5 * spec), 1.0, 1.8)
	if target > raider_hp_mult + 0.05:
		sim.toasts.append({"text": "Raiders are adapting to your soldiers: +%d%% raider HP." % int(round((target - 1.0) * 100.0)), "t": 7.0})
	raider_hp_mult = lerp(raider_hp_mult, target, 0.6)


# Short HUD line for the raid card ("" when raiders have no specific counters).
func counter_note() -> String:
	var parts := []
	if raider_pierce >= 0.05:
		parts.append("piercing %d%%" % int(raider_pierce * 100.0))
	if raider_hide >= 0.05:
		parts.append("thick hide %d%%" % int(raider_hide * 100.0))
	return "Raiders adapted: " + PoolStringArray(parts).join(", ") if not parts.empty() else ""


func on_shop(sim) -> void:
	_trigger(sim, "shop")
	# Lab rumor: one unrevealed side effect on offer gets a hint (not always the full truth)
	var cands := []
	for id in sim.offers:
		if id != "" and ShopItems.ITEMS[id].has("hidden") and not revealed.get(id, false):
			cands.append(id)
	if not cands.empty():
		var id2 = cands[sim.rng.randi_range(0, cands.size() - 1)]
		var it = ShopItems.ITEMS[id2]
		var hint = it.get("rumor", "")
		if hint == "":
			hint = "the old workers whisper that %s has a price." % it["name"]
		sim.toasts.append({"text": "Lab rumor: " + hint, "t": 12.0})


# Starving colonies eat their own brood (real ant behaviour): an egg every 1.5 s
# while the larder is empty. Buys time, costs the future.
var _famine_t := 0.0
var _famine_on := false

func _step_famine(sim, dt: float) -> void:
	if sim.food > 1.0 or sim.eggs.empty():
		if sim.food > 20.0:
			_famine_on = false
		return
	_famine_t -= dt
	if _famine_t > 0.0:
		return
	_famine_t = 1.5
	var e = sim.eggs[sim.eggs.size() - 1]
	sim.eggs.erase(e)
	sim.food += sim.egg_cost * 0.8
	if not _famine_on:
		_famine_on = true
		sim.toasts.append({"text": "FAMINE: the colony is eating its own brood to survive.", "t": 8.0})
		sim.banner = "Famine!"
		sim.banner_t = 3.0


# Antidote: undoes the side effect of one revealed cursed item you own.
func cleanse(sim) -> void:
	var cands := []
	for id in sim.owned.keys():
		if revealed.get(id, false) and ShopItems.ITEMS[id].has("hidden") and not cleansed.get(id, false):
			cands.append(id)
	if cands.empty():
		sim.toasts.append({"text": "The antidote found nothing to cure (reveal a side effect first).", "t": 7.0})
		sim.food += 20.0
		return
	var id2 = cands[sim.rng.randi_range(0, cands.size() - 1)]
	cleansed[id2] = true
	var hm = ShopItems.ITEMS[id2]["hidden"].get("mods", {})
	var neg := {}
	for k in hm.keys():
		neg[k] = -hm[k] * sim.owned.get(id2, 1)
	sim._apply_effects({"mods": neg})
	sim.toasts.append({"text": "Antidote: %s is cured (%s gone)." % [ShopItems.ITEMS[id2]["name"], ShopItems.ITEMS[id2]["hidden_desc"]], "t": 9.0})

var cleansed := {}


func take_bonus_offers() -> int:
	var b = bonus_offers
	bonus_offers = 0
	return b


func on_new_genome(sim, g) -> void:
	if not ("morph" in g):
		return
	for k in FIRSTS.keys():
		if firsts.get(k, false):
			continue
		var v = g.m(k)
		if (k in ["major", "replete", "camo"] and float(v) >= 0.4) or (not (k in ["major", "replete", "camo"]) and int(v) == 1):
			firsts[k] = true
			sim.toasts.append({"text": FIRSTS[k], "t": 7.0})


# ------------------------------------------------------------------ per tick
func step(sim, dt: float) -> void:
	for p in pending.duplicate():
		if p["trigger"] == "time" or p["trigger"] == "gamble":
			p["t"] -= dt
			if p["t"] <= 0.0:
				_reveal(sim, p)
	# spoilage: sugar-rich stores rot even under the cap (%/s of stores)
	var sp = sim.mod("spoilage")
	if sp > 0.0 and sim.food > 10.0:
		sim.food -= sim.food * sp * 0.01 * dt
	# queen drain: the elixir burns her out, never below 15%
	var qd = sim.mod("queen_drain")
	if qd > 0.0:
		sim.queen_hp = max(min(sim.queen_hp, sim.queen_max * 0.15), sim.queen_hp - qd * dt)
		if not _drain_warned and sim.queen_hp < sim.queen_max * 0.4:
			_drain_warned = true
			sim.toasts.append({"text": "The queen looks exhausted...", "t": 6.0})
	_step_famine(sim, dt)
	_step_plague(sim, dt)
	_step_cave_in(sim, dt)
	_step_events(sim, dt)


# Monoculture sickness. Every colony risks it when one body plan dominates; the
# Purebred Line makes it much worse. Diversity is insurance.
func _step_plague(sim, dt: float) -> void:
	_plague_t -= dt
	if _plague_t > 0.0:
		return
	_plague_t = 75.0
	var n = sim.ants.size()
	if n < 30:
		return
	var top = sim.top_genomes(1)
	if top.empty():
		return
	var share = float(top[0]["count"]) / n
	var pl = sim.mod("plague")
	var threshold = 0.35 if pl > 0.0 else 0.6
	if share < threshold or (pl <= 0.0 and n < 60):
		return
	var frac = min(0.6, 0.12 + 0.25 * pl) * share
	if sim.planner.count("midden") > 0:
		frac *= 0.5   # a midden keeps the dead away from the living
	var uid = top[0]["genome"].uid
	var victims := []
	for a in sim.ants:
		if a.genome.uid == uid and sim.rng.randf() < frac * 1.6:
			victims.append(a)
	if victims.empty():
		return
	for a in victims:
		sim.kill(a, "plague")
	sim.toasts.append({"text": "PLAGUE: %d clones of your top body plan died. Diversity (and a midden) is insurance." % victims.size(), "t": 9.0})
	sim.banner = "Plague!"
	sim.banner_t = 3.0
	_trigger(sim, "plague")


func _step_cave_in(sim, dt: float) -> void:
	var ci = sim.mod("cave_in")
	if ci <= 0.0:
		return
	_cave_t -= dt
	if _cave_t > 0.0:
		return
	_cave_t = 50.0
	if sim.rng.randf() > min(0.9, ci):
		return
	var diggers := []
	for a in sim.ants:
		if a.task == DIG_TASK and sim.grid.is_under(a.x, a.y):
			diggers.append(a)
	if diggers.empty():
		return
	var k = min(diggers.size(), sim.rng.randi_range(1, 3))
	for i in k:
		sim.kill(diggers[i], "cave_in")
	sim.toasts.append({"text": "Cave-in! %d digger%s crushed." % [k, "" if k == 1 else "s"], "t": 6.0})
	_trigger(sim, "cave_in")


# ------------------------------------------------------------------ colony events
const EVENTS = ["honeydew", "flood", "cosmic", "nuptial", "trader", "bloom", "heat", "windfall"]
const EVENT_W = [1.2, 0.9, 1.0, 1.0, 0.8, 1.0, 0.8, 0.7]


func _step_events(sim, dt: float) -> void:
	event_timer -= dt
	if event_timer > 0.0:
		return
	event_timer = sim.rng.randf_range(140.0, 220.0)
	var kinds := []
	var w := []
	for i in EVENTS.size():
		var k = EVENTS[i]
		if k == "nuptial" and _count_morph(sim, "wings") < 4:
			continue
		if k == "bloom" and sim.planner.count("farm") == 0:
			continue
		kinds.append(k)
		w.append(EVENT_W[i])
	var pick = sim._weighted(kinds, w)
	events_seen += 1
	var txt := ""
	match pick:
		"honeydew":
			var f = 15.0 + sim.ants.size() * 0.4
			sim.food += f
			for i in 2:
				sim._spawn_pile()
			txt = "Honeydew rain! +%d food and two fresh piles." % int(f)
		"flood":
			var drowned := 0
			for a in sim.ants.duplicate():
				if drowned >= 4:
					break
				if sim.grid.is_under(a.x, a.y) and a.y < sim.grid.base_y(a.x) + 12 and sim.rng.randf() < (0.12 if sim.planner.count("cistern") > 0 else 0.35):
					sim.kill(a, "flood")
					drowned += 1
			sim.food -= sim.food * (0.03 if sim.planner.count("cistern") > 0 else 0.1)
			txt = "Flash flood in the upper tunnels: %d drowned%s." % [drowned, " (the cistern drank most of it)" if sim.planner.count("cistern") > 0 else ", 10% of stores soaked"]
		"cosmic":
			ray_eggs += 10
			txt = "Cosmic ray storm: the next 10 eggs mutate twice."
		"nuptial":
			var flyers := []
			for a in sim.ants:
				if int(a.genome.m("wings")) == 1:
					flyers.append(a)
			var gone = int(flyers.size() * 0.5)
			for i in gone:
				sim.kill(flyers[i], "flight")
			sim.food += gone * 8.0
			sim.mutation_chance = min(0.9, sim.mutation_chance + 0.05)
			txt = "Nuptial flight! %d alates flew off to found colonies (+%d food, +5%% mutation)." % [gone, gone * 8]
		"trader":
			bonus_offers += 2
			txt = "A beetle trader visits: the next Lab has 2 extra offers."
		"bloom":
			var f2 = 20.0 * sim.planner.count("farm")
			sim.food += f2
			txt = "Fungus bloom in the farms: +%d food." % int(f2)
		"heat":
			var hurt := 0
			for a in sim.ants:
				if not sim.grid.is_under(a.x, a.y):
					a.hp = max(1.0, a.hp * (0.88 if sim.planner.count("cistern") > 0 else 0.75))
					hurt += 1
			txt = "Heat wave: %d ants on the surface scorched (-25%% HP)." % hurt
		"windfall":
			sim.food += 40.0
			txt = "A dead beetle near the nest: +40 food."
	if txt != "":
		sim.toasts.append({"text": txt, "t": 8.0})


func _count_morph(sim, key: String) -> int:
	var n := 0
	for a in sim.ants:
		if "morph" in a.genome and int(a.genome.m(key)) == 1:
			n += 1
	return n
