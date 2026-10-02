extends Reference
# The colony. Every ant decides for itself; the player only nudges the
# stimuli ants respond to (focus) and the queen's brood policy.
#
# Task choice uses the response-threshold model from real ant biology:
#   P(take task) = s^2 / (s^2 + t^2)
# where s = colony-wide stimulus (hunger, crowding) and t = the ant's own
# genetic threshold. Castes emerge from threshold differences.
#
# Evolution: new ants inherit from workers chosen by tournament on
# fitness rate (food delivered + digging per second alive), then mutate.

const Genome = preload("res://mods-unpacked/Judah-InfDNA/core/genome.gd")
const Phenotype = preload("res://mods-unpacked/Judah-InfDNA/core/phenotype.gd")
const WorldGrid = preload("res://mods-unpacked/Judah-InfDNA/core/world_grid.gd")
const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")
const ShopItems = preload("res://mods-unpacked/Judah-InfDNA/core/shop_items.gd")
const Fate = preload("res://mods-unpacked/Judah-InfDNA/core/fate.gd")
const City = preload("res://mods-unpacked/Judah-InfDNA/core/city.gd")
const NestPlanner = preload("res://mods-unpacked/Judah-InfDNA/core/nest_planner.gd")
const Queens = preload("res://mods-unpacked/Judah-InfDNA/core/queens.gd")
const WF = preload("res://mods-unpacked/Judah-InfDNA/core/world_features.gd")

enum Task { NURSE, FORAGE, DIG, HOME, DEFEND }
enum Focus { FORAGE, BALANCED, DIG, DEFEND }
enum Brood { LOW, NORMAL, HIGH }

const TASK_NAMES = ["Nursing", "Foraging", "Digging", "Heading home", "Defending"]
const CASTES = ["Forager", "Digger", "Soldier"]
const EGG_COST = 6.0
const HATCH_TIME = 14.0
const MAX_ANTS = 350
const MUTATION_CHANCE = 0.55
const MAX_PILES = 7
# --- foraging (v0.22): route memory, trails, scouting legs, long range
const NO_SITE = -999999
const RANGE_BASE = 110           # first search radius of a trip (cells from the nest)
const RANGE_GROW = 1.7           # radius multiplier after each empty-handed trip
const RANGE_MAX = 1500           # farthest a trip may reach (cells; 1 cell = 6 px, an ant is ~7 cells long)
const SURFACE_K = 3.0            # ants run this much faster over open ground than their tunnel speed (v0.23: long expeditions)
const LEG_MEAN = 70.0            # mean length of a straight scouting leg (cells)
const DEFEND_WEIGHT = {"small": 0.5, "burrower": 1.0, "brute": 2.0, "elite": 4.0, "boss": 8.0}
const RAID_SIZE_REF = 90.0         # colony size at which a raid is its normal size
const RAID_LATE = 0.09             # extra raid size per raid after the sixth
const RAID_HP_LATE = 0.02          # raiders toughen faster after raid 8 (quadratic), so a thriving colony is eventually outgrown
const RAID_BITE_LATE = 0.015
const PHER_TAU = 50.0            # trail half-life scale (s): long routes need trails that last
const TRAIL_BOOST = 0.25         # ants run up to 25% faster on a well-used trail
const FIRST_RAID = 180.0
const SIEGE_TIME = 30.0
const BOSS_EVERY = 8
const QUEEN_HP = 300.0
const SPOIL_KEEP = 0.12          # share of dug cells that ends up on the mound (the rest is tamped into walls)


class Ant:
	var id: int
	var genome
	var ph: Dictionary
	var x: int
	var y: int
	var tx: int
	var ty: int
	var t := 0.0
	var task: int = 0
	var carry := 0.0
	var heading := 1
	var age := 0.0
	var life := 180.0
	var fitness := 0.0
	var dug := 0
	var delivered := 0.0
	var gen := 0
	var quota := 0
	var timer := 0.0
	var dig_timer := 0.0
	var dig_cell := Vector2()
	var rot := 0.0
	var facing := 1
	var hp := 10.0
	var scout := 0
	var lane := 0.5          # depth lane on the surface (0 back, 1 front) - visual 2.5D
	var caste := 0           # 0 forager, 1 digger, 2 soldier (set at birth)
	var f_food := 0.0
	var f_dig := 0.0
	var f_fight := 0.0
	var job_id := 0
	var revived := false
	var hurt := 0.0
	var off_t := 0.0         # seconds spent without footing (see _footing_fix)
	var z := 0               # tunnel plane: 0 front, 1 back
	var tz := 0
	var dig_z := 0
	var spoil := 0.0         # dug cells carried as a dirt pellet
	var rot_key := -999999   # cell the cached tilt was computed for
	var trot := 0.0          # cached target tilt
	var hauling := false
	var dump_x := 0
	var dump_set := false
	# organ abilities (v0.21)
	var rally_k := 1.0
	var cd_pulse := 0.0
	var cd_arc := 0.0
	var cd_snipe := 0.0
	var cd_snare := 0.0
	var curl_t := 0.0
	var curl_cd := 0.0
	# foraging memory (v0.22)
	var site := -999999      # x of the last pile this ant loaded from (route memory)
	var search_r := 90       # how far out this trip may search (grows after empty trips)
	var empty_trips := 0
	var leg := 0             # cells left in the current straight scouting leg
	var local_t := 0         # hops of tight area-restricted search around a lost site
	var flee := 0            # hops left of running from a raider (so a threat edge does not make it dither)
	var far := 0             # farthest distance from the nest this trip
	var rich := 0.5          # fullness of the pile it loaded from (trail strength)
	var jack := false        # carrying jackpot food


class Raider:
	var id: int
	var kind: String
	var def: Dictionary
	var cls: String
	var x: int
	var y: int
	var tx: int
	var ty: int
	var t := 0.0
	var hp := 1.0
	var max_hp := 1.0
	var heading := 1
	var facing := 1
	var state := 0          # 0 approach, 1 siege, 2 retreat
	var timer := 0.0
	var flash := 0.0
	var engaged := false
	var chase_id := 0       # the ant it is going after, kept for a few hops so it does not zig-zag between neighbours
	var chase_t := 0
	var turn_t := 0         # hops before it may reverse again
	var lane := 0.5
	var dest := Vector2()   # burrowers: the cell they are boring toward
	var spark := 0.0
	var off_t := 0.0
	var z := 0
	var tz := 0
	var slow_t := 0.0      # webbed: moves slower
	var stun_t := 0.0      # snared: cannot move or bite


var grid
var rng := RandomNumberGenerator.new()
var seed_base := 0               # common random numbers: Lab offers and raid rosters are drawn
                                 # from (seed, raid, visit), so A/B runs see the same shops/rosters
var ants: Array = []
var eggs: Array = []             # [{"t": time_left, "genome": g, "gen": n, "pos": Vector2}]
var piles: Array = []            # [{"x": int, "amount": float, "max": float}]
var queen_genome
var founder_genome

var food := 60.0
var focus: int = Focus.BALANCED
var brood: int = Brood.NORMAL
var time := 0.0
var day := 1
var max_gen := 0
var born := 0
var died := 0
var delivered_total := 0.0
var history: Array = []          # [{"pop": n, "food": f}] every 5 s
# M4 evolution log, every EVO_EVERY s: {"t", "gen", "pop", "top", "share": {trait: 0..1}}
var evo_log: Array = []
var _evo_timer := 0.0
var _swept := {}                 # trait -> true once it has swept past half the colony
const EVO_EVERY = 15.0
const EVO_TRAITS = ["wings", "stinger", "acid", "glow", "major", "replete", "camo", "armor", "claws", "spikes", "legform", "antform", "venom",
	"sonic", "electric", "shell", "silk", "tongue", "regen", "fusion"]
const ORGAN_TRAITS = ["sonic", "electric", "shell", "silk", "tongue", "regen"]
var _fusion_seen := {}
# M3 borer pacing (see _borer_plan). 0 = v0.17 rules, 1 = count + start scale with
# colony size, 2 = 1 + HP scales with colony size. Default 0: v0.18.1 CRN A/B showed
# levers 1-2 do not help (late avg 39 -> 41, +1 queen collapse); see README.
var borer_lever := 0
# M3 forager reserve during raids. 0 = v0.17 (only forager-caste ants are held back),
# 1 = any non-soldier ant is held back while foragers are under the reserve, and the
# reserve rises from 20% to 35% when the larder is under a quarter of its target.
var reserve_mode := 0
var collapsed := false
var collapse_reason := ""

# raids / combat
var enemies: Array = []
var raid_n := 0
var raid_timer := FIRST_RAID
var raid_queue: Array = []
var banner := ""
var banner_t := 0.0
var queen_hp := QUEEN_HP
var queen_max := QUEEN_HP
var kills := 0
var died_combat := 0
var deaths := {"old": 0, "starve": 0, "combat": 0, "other": 0}   # by cause (harness/HUD)
var dist_threat := PoolIntArray()
var fx: Array = []               # view effects: {"kind", "pos", "text", "color", "t"}
var _threat_timer := 0.0
var _alarm_timer := 0.0
var _queen_calm := 0.0
var queen_def := {}
var shake := 0.0                 # camera kick requested by the sim (view consumes it)
var _heal_fx_t := 0.0
var rules := {}
var bloodlust_bonus := 0.0
var _r_reach := 1.0
var _r_fury := 0.0
var _r_steal := 0.0
var free_rerolls := 0
var _zap_t := 5.0
var _bl_applied := 0.0
var borer_start := 4             # first raid that can bring tunnel borers (tuning/test knob)
var queen_flash := 0.0           # >0 while the queen is being hurt (view + HUD)
var queen_hits := 0              # raids that have hurt the queen (stats)
var _queen_warned := 0.0
var _next_enemy_id := 1
var _defender_cap := 1000
var _stim_defend := 0.0
# shop / Evolution Lab
var owned := {}
var mut_bias := {}
# v0.23 directed adaptation: when the colony is tested, the caste that was tested breeds a run of eggs
# whose mutations lean toward what helped. caste -> {"left": eggs still to breed, "bias": mutation weights}
var adapt := {}
var _adapt_cd := 0.0
var trait_bias := {}
var mutation_chance := MUTATION_CHANCE
var egg_cost := EGG_COST
var hatch_time := HATCH_TIME
var base_armor := 0
var tournament := 4
var city = City.new()               # workshops, reach, outposts (city.gd)
var fate = Fate.new()               # hidden side effects, synergies, events (fate.gd)
var mods := {}                   # stacking modifiers from the Lab (see shop_items.gd)
var double_mut := 0.4
var sfx: Array = []              # sound events for the view: "hit", "ant_die", "kill", ...
var shop_pending := false
var offers: Array = []
var rerolls := 0
var _raid_active := false
var _shop_visits := 0
# food ledger (harness): where food came from and went, cumulative
var ledger := {"forage": 0.0, "kills": 0.0, "farm": 0.0, "other_in": 0.0, "upkeep": 0.0, "eggs": 0.0, "lab": 0.0, "rot": 0.0, "other_out": 0.0}
var toasts: Array = []           # [{"text", "t"}] evolution milestones for the HUD
var _announced := {}
var _toast_timer := 5.0
var planner
var trees: Array = []            # [{"x", "lane", "t"}] Brotato fruit trees on the surface
var rocks: Array = []            # decorative [{"x", "lane", "s"}]
var food_cap := 80.0
var rot_rate := 0.0              # food/s currently rotting (HUD)
var farm_rate := 0.0             # food/s from fungus farms (HUD)
var _prey_timer := 30.0
var legacy: Array = []           # fallen defenders: [{"genome", "score", "gen"}]
var spoil_dug := 0.0             # dug cells picked up as spoil
var spoil_hauled := 0.0          # spoil carried out and dropped by a mouth
var spoil_trips := 0
const BORER_MIN_ANTS = 40
const NAV_INTERVAL = 1.5         # s between distance-field rebuilds while digging
const FORAGER_RESERVE = 0.3      # share of ants that stay on food runs during raids
const FORAGER_RESERVE_LOW = 0.35 # reserve_mode 1: share held back while the larder is low
var _food_target := 40.0
var _trail_l := 0.0              # trail scent left / right of the nest (cached each second)
var _trail_r := 0.0
var _trail_t := 0.0
var _scouting := false
var _pher_acc := 0.0
var _inside_n := 0               # raiders inside the nest right now
var stat_deliv := [0.0, 0.0, 0.0, 0.0]   # food hauled by trip reach: <100, 100-250, 250-400, 400+ cells
var stat_far := 0
var peak_ants := 0
# --- play layer (v0.22): goals, mutagen, beacons, jackpots
var goals_done := {}
var raids_repelled := 0
var mutagen := 1
var blessed = null
var blessed_left := 0
var beacons: Array = []          # [{"x": int, "t": time_left}]
var _beacon_cd := 0.0
var _goal_t := 2.0
var jackpot_t := 150.0
var jackpot_hauled := 0.0
const GOALS = [
	{"id": "pop50", "name": "A real colony: 50 ants", "food": 25, "mut": 0},
	{"id": "far_haul", "name": "Far haul: food from 400+ cells out", "food": 35, "mut": 1},
	{"id": "explore3", "name": "Explorer: discover 3 landmarks", "food": 40, "mut": 1},
	{"id": "raid5", "name": "Survive 5 raids", "food": 40, "mut": 1},
	{"id": "cave", "name": "Cave diver: find a cave hoard", "food": 60, "mut": 1},
	{"id": "pop100", "name": "A city: 100 ants", "food": 50, "mut": 0},
	{"id": "soldiers12", "name": "A standing guard: 12 soldiers", "food": 30, "mut": 0},
	{"id": "jackpot", "name": "Jackpot: haul 100 food from a windfall", "food": 60, "mut": 1},
	{"id": "gen10", "name": "Deep roots: a tenth generation", "food": 60, "mut": 0},
	{"id": "epic_haul", "name": "Epic haul: food from 800+ cells out", "food": 90, "mut": 1},
	{"id": "explore8", "name": "Cartographer: discover 8 landmarks", "food": 90, "mut": 1},
	{"id": "raid10", "name": "Survive 10 raids", "food": 80, "mut": 1},
	{"id": "pop150", "name": "A metropolis: 150 ants", "food": 80, "mut": 1},
	{"id": "raid15", "name": "Survive 15 raids", "food": 120, "mut": 1},
]
var _n_foragers := 0
var _n_defenders := 0

var _next_id := 1
var _next_uid := 1
var _lay_timer := 0.0
var _pile_timer := 0.0
var _hist_timer := 0.0
var _nav_timer := 0.0
var _grow_timer := 0.0
var _starve_timer := 0.0
var _stim_forage := 0.0
var _stim_dig := 0.0
var _ph_cache := {}              # genome uid -> phenotype


func _init(seed_value: int = 0, queen_id: String = "well_rounded") -> void:
	if seed_value == 0:
		rng.randomize()
		seed_base = int(rng.seed & 0x7fffffff)
	else:
		rng.seed = seed_value
		seed_base = seed_value
	grid = WorldGrid.new(260, 225, rng.randi())   # deep world: limestone and shale below the red clay
	queen_def = Queens.find(queen_id)
	rules = queen_def["rule"]
	queen_genome = Genome.make_queen()
	var founder = Genome.make_ant()
	var qc = Color(queen_def["color"])
	founder.color = qc
	queen_genome.color = qc.darkened(0.12)
	Queens.apply_body(founder, queen_def["body"])
	Queens.apply_body(queen_genome, queen_def["body"])
	for k in queen_def["traits"].keys():
		founder.traits[k] = clamp(founder.traits[k] + queen_def["traits"][k], 0.02, 1.0)
	register_genome(queen_genome)
	register_genome(founder)
	founder_genome = founder
	for i in 14:
		var g = founder
		if i >= 8:
			g = founder.mutated(rng)
			register_genome(g)
		var a = _spawn_ant(g, 0, _random_home_cell())
		a.age = rng.randf_range(0.0, 0.6) * a.life
	for i in 3:
		_spawn_pile()
	planner = NestPlanner.new(grid, rng)
	_apply_queen()
	var ex = int(grid.entrance.x)
	_sync_trees(0.0, true)
	# the founding dig (queen chamber + shaft) already left a small mound
	for i in 8:
		grid.deposit(ex + (i % 2 * 2 - 1) * rng.randi_range(2, 5), grid.open_under * SPOIL_KEEP / 8.0, rng)
	grid.rebuild_nav()
	toasts.append({"text": "B: scout beacon at the cursor   G: bless the selected ant (mutagen)   1-4: speed", "t": 12.0})


func register_genome(g, gen: int = -1) -> void:
	if g.uid == 0:
		g.uid = _next_uid
		_next_uid += 1
		g.born_t = time
		if gen >= 0:
			g.born_gen = gen
		if fate != null:
			fate.on_new_genome(self, g)
		_note_strain(g)


# Evolution spotlight: a body plan the colony has never had before is announced (toast + `strain_events`, which
# the N key and watch mode use to look at the first ant that wears it). Rate-limited, and quiet while the
# founders are still settling.
var strain_seen := {}
var strain_events: Array = []     # [{"uid", "text", "t"}], newest last
var _strain_t := -99.0


func _note_strain(g) -> void:
	var d = g.describe()
	if strain_seen.has(d):
		return
	strain_seen[d] = true
	var notable = false
	for w in ["winged", "stinger", "acid", "glowing", "big-headed", "replete", "camouflaged"]:
		if d.find(w) >= 0:
			notable = true
	# a new limb count is worth a toast now and then; a new ability or organ is worth one soon
	if time < 40.0 or time - _strain_t < (12.0 if notable else 35.0):
		return
	_strain_t = time
	var parts = d.split(", ")
	var feats := []
	for i in range(parts.size() - 1, 0, -1):         # abilities and organs come last in describe()
		if parts[i].ends_with(" jaw") and parts[i] == "mandible jaw":
			continue                                  # every ant has one
		feats.append(parts[i])
		if feats.size() == 3:
			break
	feats.invert()
	var txt = PoolStringArray(feats).join(", ") if not feats.empty() else d
	strain_events.append({"uid": g.uid, "text": txt, "t": time})
	if strain_events.size() > 12:
		strain_events.pop_front()
	toasts.append({"text": "New strain: %s   (N to look)" % txt, "t": 7.0})


func rule(key: String, default_value = 0.0):
	return rules.get(key, default_value)


# The queen's starting perks: same effect keys as Lab items, plus her rule.
func _apply_queen() -> void:
	_r_reach = float(rule("reach", 1.0))
	_r_fury = float(rule("wounded_fury"))
	_r_steal = float(rule("lifesteal"))
	_apply_effects(queen_def)
	food += float(rule("start_food"))
	if float(rule("start_entrance")) > 0.0:
		_apply_effects({"colony": {"entrance": 1}})
	if int(rule("dig_jobs")) > 0:
		planner.max_jobs = int(rule("dig_jobs"))
	_refresh_phenotypes()


func mod(key: String, default_value: float = 0.0) -> float:
	return mods.get(key, default_value)


func phenotype(g) -> Dictionary:
	if not _ph_cache.has(g.uid):
		var ph = Phenotype.compute(g)
		ph["hp"] *= max(0.2, 1.0 + mod("hp"))
		ph["attack"] *= max(0.2, 1.0 + mod("attack") + bloodlust_bonus)
		if float(rule("no_tunnel_penalty")) > 0.0:
			ph["tunnel_mult"] = 1.0
		ph["speed"] = clamp(ph["speed"] * (1.0 + mod("speed")), 1.0, 13.0)
		ph["carry"] *= 1.0 + mod("carry")
		ph["upkeep"] *= max(0.2, 1.0 + mod("upkeep"))
		ph["life"] *= 1.0 + mod("life")
		ph["dig"] *= 1.0 + mod("dig")
		ph["thorns"] *= 1.0 + mod("thorns")
		ph["sense"] += mod("sense")
		ph["armor_red"] = min(0.75, ph["armor_red"] + mod("armor"))
		_ph_cache[g.uid] = ph
	return _ph_cache[g.uid]


func _refresh_phenotypes() -> void:
	_ph_cache.clear()
	for a in ants:
		var old_max = a.ph["hp"]
		a.ph = phenotype(a.genome)
		a.hp = clamp(a.hp * a.ph["hp"] / max(1.0, old_max), 1.0, a.ph["hp"])


func _sfx(name: String) -> void:
	if sfx.size() < 40:
		sfx.append(name)


# ------------------------------------------------------------------ step
# Optional profiler: set prof = {} and each step section accumulates microseconds.
var prof = null
var _pt := 0
var _tick_n := 0


func _pb() -> void:
	if prof != null:
		_pt = OS.get_ticks_usec()


func _pe(k: String) -> void:
	if prof != null:
		prof[k] = prof.get(k, 0) + OS.get_ticks_usec() - _pt


func step(dt: float) -> void:
	if collapsed:
		return
	time += dt
	day = int(time / 60.0) + 1
	_pb()
	_update_stimuli()
	_pe("stimuli")
	_tick_n += 1

	_pb()
	for a in ants.duplicate():
		_step_ant(a, dt)
	_pe("ants")

	_pb()
	_step_queen(dt)
	_pe("queen")
	_pb()
	_step_eggs(dt)
	_pe("eggs")
	_pb()
	_step_food(dt)
	_pe("food")
	_pb()
	_step_raids(dt)
	_pe("raids")
	_pb()
	planner.update(_stim_dig > 0.05)
	_pe("planner")
	for ev in planner.events:
		toasts.append({"text": ev, "t": 6.0})
	planner.events.clear()
	_pb()
	_step_economy(dt)
	_pe("economy")
	_pb()
	fate.step(self, dt)
	_pe("fate")
	_pb()
	city.step(self, dt)
	_pe("city")
	_pb()
	_step_prey(dt)
	_pe("prey")
	_pb()
	for e in enemies.duplicate():
		_step_enemy(e, dt)
	_pe("enemies")
	_pb()
	_combat(dt)
	_pe("combat")
	_pb()
	_step_abilities(dt)
	_pe("abilities")
	_pb()
	_step_zap(dt)
	_pe("zap")
	_pb()
	_step_threat(dt)
	_pe("threat")

	_step_extras(dt)

	_toast_timer -= dt
	if _toast_timer <= 0.0:
		_toast_timer = 5.0
		for e in top_genomes(5):
			var g = e["genome"]
			if e["count"] >= 6 and not _announced.has(g.uid) and g.uid > 2:
				_announced[g.uid] = true
				toasts.append({"text": "New body plan thriving (%s): %s" % [genome_caste(g.uid), g.describe()], "t": 7.0})
	for t in toasts.duplicate():
		t["t"] -= dt
		if t["t"] <= 0.0:
			toasts.erase(t)

	_grow_timer -= dt
	if _grow_timer <= 0.0:
		_grow_timer = 1.0
		_pb()
		_grow_world()
		_pe("grow")

	_nav_timer -= dt
	if grid.nav_dirty and _nav_timer <= 0.0:
		_pb()
		grid.rebuild_nav()
		_pe("nav")
		_nav_timer = NAV_INTERVAL

	peak_ants = int(max(peak_ants, ants.size()))
	_hist_timer -= dt
	if _hist_timer <= 0.0:
		_hist_timer = 5.0
		history.append({"pop": ants.size(), "food": food})
		if history.size() > 120:
			history.pop_front()
	_evo_timer -= dt
	if _evo_timer <= 0.0:
		_evo_timer = EVO_EVERY
		_sample_evolution()

	if ants.empty() and eggs.empty() and food < egg_cost:
		collapsed = true
		collapse_reason = "The colony starved."
	if queen_hp <= 0.0:
		collapsed = true
		collapse_reason = "The queen has fallen."


# Weather: now and then it rains. Rain washes the scent trails away (they lose strength ~4x faster while it pours), so
# foragers fall back on route memory and the colony has to re-lay its roads. The views add streaks, splashes and grey light.
var rain := 0.0
var _rain_goal := 0.0
var _rain_timer := 170.0


func _step_weather(dt: float) -> void:
	_rain_timer -= dt
	if _rain_timer <= 0.0:
		if _rain_goal > 0.0:
			_rain_goal = 0.0
			_rain_timer = rng.randf_range(150.0, 300.0)
			toasts.append({"text": "The rain stops. The scent trails will need re-laying.", "t": 5.0})
		else:
			_rain_goal = rng.randf_range(0.55, 1.0)
			_rain_timer = rng.randf_range(35.0, 70.0)
			toasts.append({"text": "Rain! The scent trails are washing away.", "t": 5.0})
	rain = move_toward(rain, _rain_goal, dt / 6.0)


func _step_extras(dt: float) -> void:
	_step_weather(dt)
	_trail_t -= dt
	if _trail_t <= 0.0:
		_trail_t = 1.0
		_update_trails()
	_beacon_cd = max(0.0, _beacon_cd - dt)
	_adapt_cd = max(0.0, _adapt_cd - dt)
	for b in beacons.duplicate():
		b["t"] -= dt
		if b["t"] <= 0.0:
			beacons.erase(b)
	jackpot_t -= dt
	if jackpot_t <= 0.0:
		jackpot_t = rng.randf_range(140.0, 220.0)
		_spawn_jackpot()
	_goal_t -= dt
	if _goal_t <= 0.0:
		_goal_t = 2.0
		_check_goals()


func _goal_met(id: String) -> bool:
	match id:
		"pop50":
			return ants.size() >= 50
		"pop100":
			return ants.size() >= 100
		"pop150":
			return ants.size() >= 150
		"far_haul":
			return stat_deliv[3] > 0.0
		"explore3":
			return discovered >= 3
		"explore8":
			return discovered >= 8
		"cave":
			return caves_found >= 1
		"gen10":
			return max_gen >= 10
		"epic_haul":
			return stat_far >= 800
		"raid5":
			return raids_repelled >= 5
		"raid10":
			return raids_repelled >= 10
		"raid15":
			return raids_repelled >= 15
		"soldiers12":
			return caste_counts()[2] >= 12
		"jackpot":
			return jackpot_hauled >= 100.0
	return false


func _check_goals() -> void:
	for g in GOALS:
		if goals_done.has(g["id"]) or not _goal_met(g["id"]):
			continue
		goals_done[g["id"]] = true
		food += g["food"]
		ledger["other_in"] += g["food"]
		var extra = ""
		if g["mut"] > 0 and mutagen < 3:
			mutagen += g["mut"]
			extra = ", +1 mutagen"
		toasts.append({"text": "Goal: %s  (+%d food%s)" % [g["name"], g["food"], extra], "t": 8.0})
		banner = "Goal reached: %s" % g["name"]
		banner_t = 3.5
		_sfx("repelled")


# Player power 1: a scent beacon. Foragers leaving the nest are drawn to it, search around it,
# and lay a trail if they find food. Two at a time, 25 s recharge.
func place_beacon(x: int) -> bool:
	if _beacon_cd > 0.0:
		toasts.append({"text": "Beacon recharging (%d s)." % int(ceil(_beacon_cd)), "t": 2.5})
		return false
	var ex = int(grid.entrance.x)
	x = int(clamp(x, ex - RANGE_MAX + 30, ex + RANGE_MAX - 30))
	_beacon_cd = 25.0
	beacons.append({"x": x, "t": 90.0})
	while beacons.size() > 2:
		beacons.pop_front()
	fx.append({"kind": "ring", "pos": grid.center(x, grid.surf_y(x) - 3), "t": 0.0, "color": Color("#7ed957")})
	fx.append({"kind": "text", "pos": grid.center(x, grid.surf_y(x) - 7), "t": 0.0, "text": "SCOUT HERE", "color": Color("#7ed957")})
	toasts.append({"text": "Scent beacon set %d cells %s of the nest." % [abs(x - ex), "west" if x < ex else "east"], "t": 4.0})
	return true


# Player power 2: mutagen. The queen breeds the next 8 eggs from the chosen ant, each mutated.
func bless(a) -> bool:
	if a == null:
		toasts.append({"text": "Click an ant first, then press G.", "t": 3.0})
		return false
	if mutagen <= 0:
		toasts.append({"text": "No mutagen. Repel raids and reach goals to earn it.", "t": 3.5})
		return false
	mutagen -= 1
	blessed = a.genome
	blessed_left = 8
	toasts.append({"text": "Mutagen: the next 8 eggs are bred from this ant, each with a fresh mutation. (%d left)" % mutagen, "t": 7.0})
	fx.append({"kind": "ring", "pos": ant_pos(a), "t": 0.0, "color": Color("#b58cff")})
	fx.append({"kind": "text", "pos": ant_pos(a) + Vector2(0, -30), "t": 0.0, "text": "MUTAGEN", "color": Color("#b58cff")})
	return true


# The world is infinite: keep the simulated columns ahead of every unit.
func _grow_world() -> void:
	var lo = grid.sim_r()
	var hi = grid.sim_l()
	for a in ants:
		lo = min(lo, min(a.x, a.tx))
		hi = max(hi, max(a.x, a.tx))
	for e in enemies:
		lo = min(lo, min(e.x, e.tx))
		hi = max(hi, max(e.x, e.tx))
	if lo <= hi:
		grid.ensure_cols(lo, hi)


func _update_stimuli() -> void:
	var n = max(1, ants.size())
	var food_target = 20.0 + n * 2.5
	_food_target = food_target
	_stim_forage = clamp(1.0 - food / food_target, 0.0, 1.0) * 0.9 + 0.15
	_n_foragers = 0
	_n_defenders = 0
	for a0 in ants:
		if a0.task == Task.FORAGE:
			_n_foragers += 1
		elif a0.task == Task.DEFEND:
			_n_defenders += 1
	var capacity = max(1.0, grid.open_under / 22.0)
	_stim_dig = clamp(n / capacity - 0.55, 0.0, 1.2)
	_stim_defend = 0.0
	# how many non-soldiers a raid is worth: a handful of small raiders does not need half the colony off the food runs
	var threat := 0.0
	for e0 in enemies:
		if e0.cls != "prey" and e0.state != 2:
			threat += DEFEND_WEIGHT.get(e0.cls, 1.0)
	_defender_cap = 6 + int(5.0 * threat)
	var hostiles = hostile_count()
	_inside_n = 0
	if hostiles > 0:
		var inside := 0
		for e in enemies:
			if e.cls != "prey" and grid.is_under(e.x, e.y):
				inside += 1
		_inside_n = inside
		_stim_defend = 0.3 + 0.06 * hostiles + (0.5 if inside > 0 else 0.0) \
			+ (0.4 if queen_hp < queen_max * 0.6 else 0.0)
		if focus == Focus.DEFEND:
			_stim_defend += 0.45
	# starvation guard: when the larder runs dry, food wins over everything except a
	# breach of the nest itself (this is what broke the raid 8-12 spiral)
	if food < food_target * 0.25:
		_stim_forage += 0.5
		_stim_dig *= 0.4
		if queen_hp >= queen_max * 0.6:
			_stim_defend *= 0.6
	match focus:
		Focus.DEFEND:
			_stim_forage *= 0.7
			_stim_dig *= 0.5
		Focus.FORAGE:
			_stim_forage += 0.35
			_stim_dig *= 0.5
		Focus.DIG:
			_stim_dig += 0.35
			_stim_forage *= 0.8
	# the city keeps growing: while the larder is healthy a standing crew digs new
	# rooms even when the nest isn't crowded (more when workshops are waiting)
	# (only for an established colony with a surplus: v0.16 playtest showed a crew pulled
	#  from a small colony starves it)
	if ants.size() >= 60 and food > food_target and hostile_count() == 0:
		_stim_dig = max(_stim_dig, 0.14 + 0.04 * planner.wanted_rooms.size())


func _p(s: float, t: float) -> float:
	return s * s / (s * s + t * t + 0.0001)


func _choose_task(a) -> void:
	a.timer = 0.0
	# a digger holding a pellet finishes the trip instead of dropping it in the tunnel
	if a.spoil > 0.0 and a.task == Task.DIG and _stim_defend < 0.9:
		a.hauling = true
		a.dump_set = false
		return
	var pd = _p(_stim_defend, a.genome.traits.get("defend_t", 0.6))
	# foragers and diggers only drop everything for a breach or a wounded queen; otherwise the
	# soldier caste holds the line (v0.22: stops 80-90% of the colony leaving the larder in a raid)
	if a.caste != 2 and ants.size() >= 20 and _inside_n == 0 and queen_hp >= queen_max * 0.6:
		pd *= 0.55
	if _stim_defend > 0.0 and rng.randf() < pd:
		# forager reserve: foragers keep a floor of the workforce on food runs
		var reserve = max(3, int(ants.size() * FORAGER_RESERVE))
		var keep = a.caste == 0 and _n_foragers < reserve and queen_hp >= queen_max * 0.5
		if reserve_mode >= 1:
			var share = FORAGER_RESERVE_LOW if food < _food_target * 0.25 else FORAGER_RESERVE
			reserve = max(3, int(ants.size() * share))
			keep = a.caste != 2 and _n_foragers < reserve and queen_hp >= queen_max * 0.5
		if not keep and a.caste != 2 and _inside_n == 0 and a.task != Task.DEFEND and _n_defenders >= _defender_cap:
			keep = true          # enough ants are already on it; this one stays on the food
		if not keep:
			if a.task != Task.DEFEND:
				_n_defenders += 1
				if a.task == Task.FORAGE:
					_n_foragers -= 1
			a.task = Task.DEFEND
			a.spoil = 0.0
			a.hauling = false
			return
		if a.task != Task.FORAGE:
			_n_foragers += 1
		a.task = Task.FORAGE
		_start_trip(a)
		a.spoil = 0.0
		a.hauling = false
		return
	if rng.randf() < _p(_stim_forage, a.genome.traits["forage_t"]):
		if a.task != Task.FORAGE:
			_n_foragers += 1
		a.task = Task.FORAGE
		_start_trip(a)
	elif rng.randf() < _p(_stim_dig, a.genome.traits["dig_t"]):
		a.task = Task.DIG
		a.quota = rng.randi_range(4, 10)
	else:
		a.task = Task.NURSE
	if a.task != Task.DIG:
		a.spoil = 0.0
		a.hauling = false


# ------------------------------------------------------------------ ants
func _spawn_ant(g, gen: int, cell: Vector2, caste: int = -1):
	var a = Ant.new()
	a.lane = rng.randf()
	a.caste = caste if caste >= 0 else rng.randi_range(0, 1)
	a.id = _next_id
	_next_id += 1
	a.genome = g
	a.ph = phenotype(g)
	a.x = int(cell.x)
	a.y = int(cell.y)
	a.tx = a.x
	a.ty = a.y
	a.gen = gen
	a.life = a.ph["life"] * rng.randf_range(0.85, 1.15)
	a.hp = a.ph["hp"]
	a.heading = 1 if rng.randf() < 0.5 else -1
	ants.append(a)
	born += 1
	max_gen = int(max(max_gen, gen))
	_choose_task(a)
	if a.task == Task.NURSE and _stim_defend <= 0.0:
		a.task = [Task.FORAGE, Task.DIG, Task.NURSE][a.caste]
		if a.task == Task.FORAGE:
			_start_trip(a)
		elif a.task == Task.DIG:
			a.quota = rng.randi_range(4, 10)
	return a


func kill(a, reason: String = "") -> void:
	ants.erase(a)
	died += 1
	deaths[reason if deaths.has(reason) else "other"] += 1
	# the view plays a fall animation from this (ant_view._draw_corpses)
	fx.append({"kind": "corpse", "pos": ant_pos(a) + Vector2(-sin(a.rot), cos(a.rot)) * grid.CELL * 0.5, "t": 0.0,
		"color": Color(1, 1, 1), "genome": a.genome, "id": a.id, "lane": a.lane, "caste": a.caste,
		"face": a.facing, "rot": a.rot, "old": reason == "old", "carry": a.carry > 0.0})
	if mod("corpse_food") > 0.0:
		food += mod("corpse_food")
	if reason == "combat":
		_sfx("ant_die")
		died_combat += 1
		if a.fitness > 1.0:
			legacy.append({"genome": a.genome, "score": a.fitness / (a.age + 30.0) * 1.5, "gen": a.gen})
			if legacy.size() > 30:
				legacy.pop_front()
		fx.append({"kind": "puff", "pos": ant_pos(a), "t": 0.0, "color": Color("#c9a37a")})
		fx.append({"kind": "burst", "pos": ant_pos(a), "t": 0.0, "color": Color("#ffb08a")})


func queen_fx_pos() -> Vector2:
	return grid.center(int(grid.chamber.x), int(grid.chamber.y + grid.chamber_r.y)) + Vector2(0, -50)


func ant_pos(a) -> Vector2:
	var p0 = grid.center(a.x, a.y)
	var p1 = grid.center(a.tx, a.ty)
	return p0.linear_interpolate(p1, a.t)


# Digging removes the dirt an ant was touching, so it can end up in open air. Falling one
# cell per hop recovers, but in a room that is still being excavated the chain can last
# seconds. Cap it: after 0.5 s without footing, move to the nearest cell that has some.
func _footing_fix(u, dt: float) -> void:
	if grid.can_walk(u.x, u.y, u.z):
		u.off_t = 0.0
		return
	u.off_t += dt
	if u.off_t < 0.5:
		return
	u.off_t = 0.0
	var best = null
	var bd = 1e9
	for pz in ([u.z, 0] if u.z == 1 else [0]):
		for r in range(1, 5):
			for yy in range(u.y - r, u.y + r + 1):
				for xx in range(u.x - r, u.x + r + 1):
					if max(abs(xx - u.x), abs(yy - u.y)) != r or not grid.can_walk(xx, yy, pz):
						continue
					var d = (xx - u.x) * (xx - u.x) + (yy - u.y) * (yy - u.y)
					if d < bd:
						bd = d
						best = Vector3(xx, yy, pz)
			if best != null:
				break
		if best != null:
			break
	if best != null:
		u.x = int(best.x)
		u.y = int(best.y)
		u.z = int(best.z)
		u.tx = u.x
		u.ty = u.y
		u.tz = u.z
		u.t = 0.0


func _step_ant(a, dt: float) -> void:
	a.age += dt
	a.hurt = max(0.0, a.hurt - dt)
	a.timer += dt
	if a.age > a.life:
		kill(a, "old")
		return
	# footing check staggered over 5 ticks (the rescue itself waits 0.5 s anyway)
	if (_tick_n + a.id) % 5 == 0:
		_footing_fix(a, dt * 5.0)

	# smooth body rotation toward the local ground normal
	# (in a narrow tunnel floor and ceiling nearly cancel; one extra ceiling cell used to
	# flip the normal and turn the ant upside down. A floor under the feet wins.)
	# (cached per target cell: the normal only changes when the ant enters a new cell)
	var rk = a.tx * 7919 + a.ty * 31 + a.tz
	if rk != a.rot_key:
		a.rot_key = rk
		if grid.is_surface_cell(a.tx, a.ty):
			a.trot = grid.surface_tilt(a.tx)      # open ground: follow the smoothed hill, not the 6 px stair steps
		else:
			var n = grid.ground_normal(a.tx, a.ty, a.tz)
			a.trot = atan2(-n.x, n.y)
			if grid.is_solid(a.tx, a.ty + 1, a.tz) or grid.is_solid(a.x, a.y + 1, a.z):
				a.trot = clamp(a.trot, -1.1, 1.1)
	a.rot = lerp_angle(a.rot, a.trot, clamp(dt * 8.0, 0.0, 1.0))

	if a.dig_timer > 0.0:
		a.dig_timer -= dt
		if a.dig_timer <= 0.0:
			_finish_dig(a)
		return

	var dist = 1.4142 if (a.tx != a.x and a.ty != a.y) else 1.0
	if a.tx == a.x and a.ty == a.y and a.tz == a.z:
		dist = 1.0
		a.t = 1.0
	else:
		var und = grid.is_under(a.x, a.y)
		var sp = a.ph["speed"] * (a.ph["tunnel_mult"] if und else SURFACE_K)
		if not und and a.task == Task.FORAGE:
			sp *= 1.0 + TRAIL_BOOST * min(1.0, grid.pher_at(a.x) / 1.2)   # ants run faster on a used trail
		a.t += sp * dt / dist
	# Arrival carries the overshoot into the next hop (v0.22). Before, the remainder was thrown
	# away, so ants walked 9% slower than their speed at 1x and 19% slower at 4x-sized steps.
	var hops = 0
	while a.t >= 1.0 and hops < 3:
		hops += 1
		var over = (a.t - 1.0) * dist      # cells already walked past this cell centre
		a.x = a.tx
		a.y = a.ty
		a.z = a.tz
		a.t = 0.0
		_on_arrive(a)
		var moved = a.tx != a.x or a.ty != a.y
		if moved:
			var move = Vector2(a.tx - a.x, a.ty - a.y)
			var tangent = Vector2(cos(a.rot), sin(a.rot))
			var d = move.dot(tangent)
			if grid.is_surface_cell(a.x, a.y):
				d = move.x       # open ground: left/right is simply the screen direction, and a vertical step (hill, shaft mouth) keeps facing
			elif move.x == 0.0 and abs(tangent.y) < 0.7:
				d = 0.0          # a plain vertical step on near-level ground must not turn the ant round
			if abs(d) > 0.1:
				a.facing = 1 if d > 0 else -1
		if (moved or a.tz != a.z) and a.dig_timer <= 0.0:
			dist = 1.4142 if (a.tx != a.x and a.ty != a.y) else 1.0
			a.t = min(over / dist, 1.6)
		else:
			break


func _on_arrive(a) -> void:
	if not grid.is_under(a.x, a.y):
		a.lane = clamp(a.lane + rng.randf_range(-0.02, 0.02), 0.0, 1.0)      # small steps: ants hop 18 cells a second now, and big ones made them shimmer
		if a.task == Task.FORAGE and grid.pher_at(a.x) > 0.8:
			a.lane = lerp(a.lane, 0.68 if a.carry > 0.0 else 0.32, 0.12)   # two-lane trail: laden ants on one side
	# lost footing (terrain changed, or the ant ended up in open space): grab the
	# nearest foothold, otherwise fall one cell
	if not grid.can_walk(a.x, a.y, a.z):
		var nb = grid.neighbors(a.x, a.y, a.z)
		if nb.size() > 0:
			_go(a, nb[rng.randi_range(0, nb.size() - 1)])
		elif not grid.is_solid(a.x, a.y + 1, a.z):
			_go(a, Vector2(a.x, a.y + 1))
		return

	match a.task:
		Task.FORAGE:
			_forage(a)
		Task.DIG:
			_dig(a)
		Task.NURSE:
			_nurse(a)
		Task.DEFEND:
			_defend(a)
		Task.HOME:
			if grid.field(grid.dist_home, a.x, a.y, a.z) <= 1:
				_choose_task(a)
			else:
				_descend(a, grid.dist_home)


func _go(a, c) -> void:
	a.tx = int(c.x)
	a.ty = int(c.y)
	a.tz = int(c.z) if typeof(c) == TYPE_VECTOR3 else a.z


# Step down a distance field. Only strictly-closer cells are candidates (guaranteed
# progress); among those, prefer cells touching dirt so ants crawl along surfaces.
# Holes between the planes are one more step (the same cell in the other plane).
func _descend(a, f: PoolIntArray) -> void:
	var nb = grid.neighbors(a.x, a.y, a.z)
	if grid.is_link(a.x, a.y) and grid.can_walk(a.x, a.y, 1 - a.z):
		nb.append(Vector3(a.x, a.y, 1 - a.z))
	if nb.empty():
		return
	var cur = grid.field(f, a.x, a.y, a.z)
	var best = null
	var best_s = 1 << 30
	var f_ok = f.size() == grid.PLANES * grid.WH
	var gw = grid.W
	var gwh = grid.WH
	var gox = grid.ox
	for c in nb:
		var cz = int(c.z) if typeof(c) == TYPE_VECTOR3 else a.z
		var cx = int(c.x)
		var cy = int(c.y)
		# neighbours are always inside the grid; direct read of grid.field()
		var d = f[cz * gwh + cy * gw + (cx - gox)] if f_ok else -1
		if d < 0 or (cur >= 0 and d >= cur):
			continue
		var sc = d * 4 + rng.randi_range(0, 2)
		if not grid.walled(int(c.x), int(c.y), cz):
			sc += 3
		if sc < best_s:
			best_s = sc
			best = c
	if best == null:
		best = nb[rng.randi_range(0, nb.size() - 1)]
	_go(a, best)


func _forage(a) -> void:
	var here_under = grid.is_under(a.x, a.y)
	if a.carry > 0.0:
		if not here_under:
			# trail strength follows how rich the pile was: good finds recruit harder
			grid.pher_add(a.x, (0.25 + 0.9 * a.rich) * (1.0 + 0.8 * a.ph.get("phero", 0.0)), 4.0)
		if grid.field(grid.dist_home, a.x, a.y, a.z) <= 1:
			food += a.carry
			ledger["forage"] += a.carry
			delivered_total += a.carry
			a.delivered += a.carry
			a.fitness += a.carry
			a.f_food += a.carry
			var fb = 0 if a.far < 100 else (1 if a.far < 250 else (2 if a.far < 400 else 3))
			stat_deliv[fb] += a.carry
			stat_far = int(max(stat_far, a.far))
			if a.far >= 350 and _adapt_cd <= 0.0:
				_adapt_cd = 90.0
				adapt[0] = {"left": 8, "bias": {"leg": 1.6, "morph": 0.8, "eyes": 0.6, "size": 0.3}}
				toasts.append({"text": "The long expeditions favour fast, long-legged scouts.", "t": 6.0})
			if a.jack:
				jackpot_hauled += a.carry
			a.carry = 0.0
			_choose_task(a)
		else:
			_descend(a, grid.dist_home)
		return

	if a.timer > _trip_limit(a):
		# out of time: head home empty-handed and look farther next trip
		a.empty_trips += 1
		a.task = Task.HOME
		_descend(a, grid.dist_home)
		return

	if here_under:
		if grid.field(grid.dist_exit, a.x, a.y, a.z) == 0:
			_walk_surface(a)          # at the mouth itself: step out along its heading (a random neighbour made it shuffle)
		else:
			_descend(a, grid.dist_exit)
		return

	var ex = int(grid.entrance.x)
	var off = a.x - ex
	if abs(off) > a.far:
		a.far = abs(off)

	# on the surface: run from nearby raiders, and keep running for a few hops after (hops are 1/18 s, so
	# re-deciding at the edge of the danger zone made ants flip back and forth in front of the raider)
	if a.flee > 0:
		a.flee -= 1
		_walk_surface(a)
		return
	var threat = _nearest_surface_enemy(a.x, 5)
	if threat != null:
		a.heading = -1 if threat.x > a.x else 1
		a.flee = 10
		_walk_surface(a)
		return
	# food in reach?
	for p in piles:
		if p["amount"] > 0.0 and abs(p["x"] - a.x) <= 1:
			var take = min(a.ph["carry"], p["amount"])
			a.rich = clamp(p["amount"] / max(1.0, p["max"]), 0.0, 1.0)
			a.jack = p.get("kind", "") == "jackpot"
			p["amount"] -= take
			# far piles are richer: seeds, honeydew, whole carcasses. The load is worth more the farther it came
			# from (up to x2.2 past 720 cells), which pays for the long walk home.
			a.carry = take * (1.0 + clamp(abs(p["x"] - ex) / 600.0, 0.0, 1.2))
			a.site = p["x"]          # route memory: it will come straight back here
			a.empty_trips = 0
			if not p.get("found", false):
				p["found"] = true
				if abs(p["x"] - ex) >= 250:
					var pxy = grid.center(p["x"], grid.surf_y(p["x"]) - 5)
					fx.append({"kind": "text", "pos": pxy, "t": 0.0, "text": "FOUND!", "color": Color("#ffd86b")})
					toasts.append({"text": "A scout found a %d-food pile %d cells %s of the nest." % [int(p["max"]), abs(p["x"] - ex), "west" if p["x"] < ex else "east"], "t": 6.0})
			_descend(a, grid.dist_home)
			return
	var sense = a.ph["sense"]
	var nearest = null
	var nd = 1e9
	for p in piles:
		var d = abs(p["x"] - a.x)
		if p["amount"] > 0.0 and d <= sense and d < nd:
			nd = d
			nearest = p
	for e in enemies:
		if e.cls == "prey" and abs(e.x - a.x) <= sense * 0.6 and (nearest == null or abs(e.x - a.x) < nd):
			nearest = {"x": e.x}
			nd = abs(e.x - a.x)
	if nearest != null:
		if nd <= 1:
			return          # on top of it: stand and fight (the combat step is range-based) instead of stepping back and forth
		a.heading = 1 if nearest["x"] > a.x else -1
		a.leg = 0
		a.local_t = 0
	elif _search(a, ex, off):
		return
	_walk_surface(a)


# Searching with nothing in sense range. Returns true if the ant gave up (and turned for home).
# Real-ant ingredients: area-restricted search around a lost site, route memory, trail
# following, then long persistent scouting legs out to this trip's search radius.
func _search(a, ex: int, off: int) -> bool:
	if a.local_t > 0:
		a.local_t -= 1
		a.leg -= 1
		if a.leg <= 0:          # short sweeps, not a coin flip every hop: the ant visibly casts about instead of vibrating
			a.heading = -a.heading
			a.leg = rng.randi_range(14, 24)
		return false
	if a.site != NO_SITE:
		if abs(a.site - a.x) <= 2:
			a.site = NO_SITE         # got there: the pile is gone, circle the spot
			a.local_t = 40
			a.leg = rng.randi_range(10, 18)
		else:
			a.heading = 1 if a.site > a.x else -1
		return false
	var rmax = _range_cap(a)
	if abs(off) >= rmax and (off > 0) == (a.heading > 0):
		a.empty_trips += 1
		a.task = Task.HOME
		_descend(a, grid.dist_home)
		return true
	if off != 0 and grid.pher_at(a.x) > 0.35:
		a.heading = 1 if off > 0 else -1     # on a trail: follow it out, away from the nest
		return false
	a.leg -= 1
	if a.leg <= 0:
		a.leg = 25 + int(-log(max(0.001, rng.randf())) * LEG_MEAN)
		if rng.randf() < 0.4:
			a.heading = -a.heading
	return false


# Farthest this ant may search: the trip radius, trimmed so an old ant does not set out
# for somewhere it cannot get back from.
func _range_cap(a) -> int:
	var left = max(0.0, a.life - a.age)
	return int(min(a.search_r, max(40.0, 0.4 * a.ph["speed"] * SURFACE_K * left)))


func _trip_limit(a) -> float:
	return 40.0 + 2.4 * min(a.search_r, RANGE_MAX) / max(2.0, a.ph["speed"] * SURFACE_K)


func _start_trip(a) -> void:
	a.far = 0
	a.leg = 0
	a.local_t = 0
	a.search_r = int(min(RANGE_MAX, RANGE_BASE * pow(RANGE_GROW, a.empty_trips)))
	if a.site == NO_SITE and not beacons.empty() and rng.randf() < 0.65:
		a.site = beacons[rng.randi_range(0, beacons.size() - 1)]["x"]   # the player's scent flag
	if a.site == NO_SITE and rng.randf() < 0.7:
		a.site = _recruit_site()                                         # nestmates' news of a pile somebody already found
	if a.site != NO_SITE:
		var ex = int(grid.entrance.x)
		a.search_r = int(min(RANGE_MAX, max(a.search_r, abs(a.site - ex) + 60)))
		a.heading = 1 if a.site > a.x else -1
	else:
		a.heading = _pick_heading(a)
		if _scouting:
			# scouts range far whether or not nearer food exists: long-tailed radius, 150..RANGE_MAX
			a.search_r = int(min(RANGE_MAX, max(a.search_r, 150 + int(-log(max(0.001, rng.randf())) * 420.0))))


# Recruitment: a forager setting out is often told about a pile some nestmate has already found and that still holds
# food (nearer ones likelier, a few at random so one pile is not mobbed). Without it, once the food frontier moved past
# what a young forager's own search radius covers, only scouts ever found anything and the colony starved.
func _recruit_site() -> int:
	var ex = int(grid.entrance.x)
	var items := []
	var weights := []
	for p in piles:
		if p.get("found", false) and p["amount"] > 8.0:
			items.append(p["x"])
			weights.append(1.0 / (1.0 + abs(p["x"] - ex) / 250.0))
	if items.empty():
		return NO_SITE
	return _weighted(items, weights)


func _pher_at(x: int) -> float:
	return grid.pher_at(x)


# Scouts and recruits: most ants leaving the nest follow the stronger trail side; a minority
# strike out on their own.
func _pick_heading(a) -> int:
	var left = _trail_l
	var right = _trail_r
	_scouting = false
	if left + right < 0.5 or rng.randf() < 0.15:
		_scouting = true     # a scout: strikes out on its own, picks a side at random
		return 1 if rng.randf() < 0.5 else -1
	return -1 if rng.randf() < left / (left + right) else 1


func _update_trails() -> void:
	var ex = int(grid.entrance.x)
	var l = 0.0
	var r = 0.0
	if grid.pher_hi >= grid.pher_lo:
		var ph = grid.pher
		var lo = max(max(grid.pher_lo, ex - RANGE_MAX), grid.ox)
		var hi = min(min(grid.pher_hi, ex + RANGE_MAX), grid.ox + grid.W - 1)
		for x in range(lo, hi + 1):
			var v = ph[x - grid.ox]
			if x < ex:
				l += v
			elif x > ex:
				r += v
	_trail_l = l
	_trail_r = r


func _walk_surface(a) -> void:
	var best = null
	# Walk on the open ground, never along the top row of the soil where it is marked as nest ("under") around a shaft:
	# an ant standing on such a cell is treated as underground and sent back down the way out, so a forager could shuffle
	# in and out of an outpost mouth for ever (every forager from that mouth, with the colony starving). Only if there is
	# no other way on is an "under" cell accepted.
	for pass_n in 2:
		for c in grid.neighbors(a.x, a.y):
			if int(c.x) - a.x == a.heading and grid.is_surface_cell(int(c.x), int(c.y)) and (pass_n == 1 or not grid.is_under(int(c.x), int(c.y))):
				# prefer the cell hugging the ground
				if best == null or c.y > best.y:
					best = c
		if best != null:
			break
	if best == null:
		a.heading = -a.heading
		for c in grid.neighbors(a.x, a.y):
			if grid.is_surface_cell(int(c.x), int(c.y)):
				best = c
				break
	if best != null:
		_go(a, best)


func _dig(a) -> void:
	if a.hauling:
		_haul(a)
		return
	if a.quota <= 0 or a.timer > 60.0:
		a.job_id = 0
		if a.spoil > 0.0:
			# carry the spoil up and out
			a.hauling = true
			a.dump_set = false
			a.timer = 0.0
			_haul(a)
			return
		a.task = Task.HOME
		_descend(a, grid.dist_home)
		return
	var job = planner.job_by_id(a.job_id) if a.job_id != 0 else null
	if job == null:
		job = planner.pick_job(a.genome.traits["dig_down"])
		if job == null:
			a.task = Task.NURSE
			return
		a.job_id = job["id"]
	var t = planner.target(job)
	if t == null:
		a.job_id = 0
		return
	var jz = job["z"]
	var f = planner.dist_for(job, t, time)
	if f.size() == 0:
		a.job_id = 0
		return
	var fh = grid.field(f, a.x, a.y, a.z)
	if fh == 0 or (a.z == jz and abs(t.x - a.x) <= 1 and abs(t.y - a.y) <= 1):
		a.dig_cell = t
		a.dig_z = jz
		# soft ground digs fast, clay and red clay slowly
		a.dig_timer = 1.0 / (a.ph["dig"] * max(0.3, grid.dig_rate(int(t.x), int(t.y))))
		return
	if fh < 0:
		_descend(a, grid.dist_home)
	else:
		_descend(a, f)


func _finish_dig(a) -> void:
	var job = planner.job_by_id(a.job_id)
	var r = planner.radius_for(job) if job != null else 1.25
	var n = grid.carve(a.dig_cell.x, a.dig_cell.y, r, a.dig_z)
	if job != null:
		planner.note_dug(job, n)
		planner.after_carve(job, a.dig_cell)
	if n > 0:
		a.dug += n
		a.fitness += 0.12 * n
		a.f_dig += 0.12 * n
		a.quota -= 1
		a.spoil += n
		spoil_dug += n
		if a.dig_z == a.z and grid.can_walk(int(a.dig_cell.x), int(a.dig_cell.y), a.z):
			_go(a, a.dig_cell)


# Spoil run: up the nearest way out, a few steps off the mouth, drop the pellet.
func _haul(a) -> void:
	if a.timer > 90.0 or a.spoil <= 0.0:
		a.spoil = 0.0
		a.hauling = false
		_choose_task(a)
		return
	if a.z == 1 or grid.is_under(a.x, a.y):
		_descend(a, grid.dist_exit)
		return
	if not a.dump_set:
		var mouth = grid.nearest_entrance_x(a.x)
		a.dump_x = mouth + (-1 if rng.randf() < 0.5 else 1) * rng.randi_range(2, 5)
		a.dump_set = true
	if a.x == a.dump_x or _nearest_surface_enemy(a.x, 5) != null:
		_dump(a)
		return
	a.heading = 1 if a.dump_x > a.x else -1
	_walk_surface(a)


func _dump(a) -> void:
	var cols = grid.deposit(a.x, a.spoil * SPOIL_KEEP, rng)
	spoil_hauled += a.spoil
	spoil_trips += 1
	a.spoil = 0.0
	a.hauling = false
	if not cols.empty():
		_unbury(cols)
		fx.append({"kind": "puff", "pos": grid.center(a.x, grid.surf_y(a.x)), "t": 0.0, "color": Color("#a67c52")})
	_choose_task(a)


# A grain landed where a unit stood: lift it onto the new ground.
func _unbury(cols: Array) -> void:
	var units = ants + enemies
	for u in units:
		if u.z != 0 or not (u.x in cols or u.tx in cols):
			continue
		if grid.is_solid(u.x, u.y):
			u.y = grid.surf_y(u.x) - 1
			u.tx = u.x
			u.ty = u.y
			u.t = 0.0
		elif grid.is_solid(u.tx, u.ty):
			u.tx = u.x
			u.ty = u.y
			u.t = 0.0


func _nurse(a) -> void:
	if a.timer > rng.randf_range(5.0, 9.0):
		_choose_task(a)
		if a.task != Task.NURSE:
			return
	var nb := []
	for c in grid.neighbors(a.x, a.y, a.z):
		if grid.is_surface_cell(int(c.x), int(c.y)):
			continue          # nurses shuffle about inside the nest, not out on the grass beside the hole
		var d = grid.field(grid.dist_home, int(c.x), int(c.y), a.z)
		if d >= 0 and d <= 8:
			nb.append(c)
			if grid.walled(int(c.x), int(c.y), a.z):
				nb.append(c)   # double weight for wall cells
	if nb.empty():
		_descend(a, grid.dist_home)
	else:
		_go(a, nb[rng.randi_range(0, nb.size() - 1)])


func _weighted(items: Array, weights: Array):
	var total := 0.0
	for w in weights:
		total += w
	var r = rng.randf() * total
	for i in items.size():
		r -= weights[i]
		if r <= 0.0:
			return items[i]
	return items[items.size() - 1]


func _random_home_cell() -> Vector2:
	var cells := []
	for y in range(int(grid.chamber.y - 6), int(grid.chamber.y + 6)):
		for x in range(int(grid.chamber.x - 10), int(grid.chamber.x + 11)):
			if grid.can_walk(x, y) and grid.field(grid.dist_home, x, y) == 0:
				cells.append(Vector2(x, y))
	return cells[rng.randi_range(0, cells.size() - 1)] if cells.size() > 0 else grid.chamber


# ------------------------------------------------------------------ queen, brood, food
func _step_queen(dt: float) -> void:
	var interval = [9.0, 5.0, 2.5][brood]
	var reserve = [30.0, 14.0, 5.0][brood] + min(ants.size(), 60) * [0.8, 0.4, 0.15][brood]   # v0.22: size term capped, big colonies kept laying too rarely
	var surplus = food - reserve
	if surplus > 150.0:
		interval *= 0.35
	elif surplus > 60.0:
		interval *= 0.55
	_lay_timer -= dt
	if _lay_timer > 0.0:
		return
	_lay_timer = max(interval + _lay_timer, interval * 0.5)   # keep the overshoot: dt-independent laying rate
	if ants.size() + eggs.size() >= MAX_ANTS:
		return
	var twin = float(rule("twin")) > 0.0 and rng.randf() < float(rule("twin"))
	var cost = egg_cost * (1.5 if twin else 1.0)
	if food < cost + reserve:
		var bl = float(rule("blood_eggs"))
		if bl > 0.0 and queen_hp > queen_max * 0.4:
			queen_hp -= bl * (1.5 if twin else 1.0)   # she pays in blood
			queen_flash = 0.4
		else:
			return
	else:
		food -= cost
		ledger["eggs"] += cost
	for n in (2 if twin else 1):
		_lay_egg()


# Where an egg is laid: (x, y, plane). Nursery floors first, else the queen chamber.
func _egg_pos(broods: Array) -> Vector3:
	if broods.size() > 0 and rng.randf() < 0.75:
		var b = broods[rng.randi_range(0, broods.size() - 1)]
		var bx = rng.randf_range(-b["rx"] * 0.6, b["rx"] * 0.6)
		var fy = b["floor"] if b.has("floor") else b["center"].y + b["ry"] * sqrt(max(0.0, 1.0 - pow(bx / b["rx"], 2)))
		return Vector3(b["center"].x + bx, fy - 0.7, b.get("z", 0))
	var ex = rng.randf_range(-8.2, -5.0)
	var p = grid.chamber + Vector2(ex, grid.chamber_r.y * sqrt(max(0.0, 1.0 - pow(ex / grid.chamber_r.x, 2))) - 0.7)
	return Vector3(p.x, p.y, 0)


func _lay_egg() -> void:
	var caste = _needed_caste()
	var parent = _select_parent(caste)
	var g = queen_genome
	var gen = 0
	if parent is Dictionary:
		g = parent["genome"]
		gen = parent["gen"] + 1
	elif parent != null:
		g = parent.genome
		gen = parent.gen + 1
	if blessed_left > 0 and blessed != null:
		blessed_left -= 1
		g = blessed.mutated(rng, mut_bias)     # mutagen: bred from the chosen ant, always mutated
		register_genome(g, gen)
	elif float(rule("wild_hatch")) > 0.0 and rng.randf() < float(rule("wild_hatch")):
		g = founder_genome
		for i in 4:
			g = g.mutated(rng, mut_bias)
		register_genome(g, gen)
	elif adapt.has(caste) and adapt[caste]["left"] > 0:
		var ad = adapt[caste]
		ad["left"] -= 1
		var b2 = mut_bias.duplicate()
		for k in ad["bias"].keys():
			b2[k] = b2.get(k, 0.0) + ad["bias"][k]
		g = g.mutated(rng, b2)
		register_genome(g, gen)
	elif rng.randf() < mutation_chance:
		g = g.mutated(rng, mut_bias)
		if rng.randf() < double_mut:
			g = g.mutated(rng, mut_bias)
		register_genome(g, gen)
	if fate.ray_eggs > 0:
		fate.ray_eggs -= 1
		g = g.mutated(rng, mut_bias).mutated(rng, mut_bias)
		register_genome(g, gen)
	g = _apply_instincts(g)
	var broods := []
	for c in planner.chambers:
		if c["purpose"] == "brood":
			broods.append(c)
	var ht = hatch_time / (1.0 + 0.15 * min(3, broods.size()))
	var ep = _egg_pos(broods)
	eggs.append({"t": ht, "genome": g, "gen": gen, "pos": Vector2(ep.x, ep.y), "z": int(ep.z), "caste": caste})


# The queen raises the caste the colony needs most right now.
func _needed_caste() -> int:
	var threat = 0.2 + 0.3 * min(1.0, raid_n / 4.0) + _stim_defend
	var cb = rule("caste_bias", [1.0, 1.0, 1.0])
	return _weighted([0, 1, 2], [max(0.25, _stim_forage) * cb[0], max(0.1, _stim_dig + 0.1) * cb[1], threat * cb[2]])


func _caste_fitness(a, caste: int) -> float:
	match caste:
		0:
			return a.f_food
		1:
			return a.f_dig * 3.0
		_:
			return a.f_fight * 2.0


# Parent = best of a tournament scored on the needed caste's fitness, so each
# caste breeds from its own best performers and lineages specialize.
func _select_parent(caste: int = 0):
	if caste == 2 and not legacy.empty() and rng.randf() < 0.4:
		var best_l = null
		for i in 3:
			var l = legacy[rng.randi_range(0, legacy.size() - 1)]
			if best_l == null or l["score"] > best_l["score"]:
				best_l = l
		return {"genome": best_l["genome"], "gen": best_l["gen"]}
	if ants.empty():
		return null
	var best = null
	var best_score = -1.0
	for i in tournament:
		var a = ants[rng.randi_range(0, ants.size() - 1)]
		var f = _caste_fitness(a, caste) + (0.3 * a.fitness if a.caste == caste else 0.0)
		var score = f / (a.age + 30.0) / max(0.02, a.ph["upkeep"] * 20.0)
		if score > best_score:
			best_score = score
			best = a
	return best


func caste_counts() -> Array:
	var c = [0, 0, 0]
	for a in ants:
		c[a.caste] += 1
	return c


# Badge pulse: soldiers pulse while actually defending
func fx_caste_pulse(a) -> bool:
	return a.task == Task.DEFEND and a.caste == 2 and int(time * 4.0) % 2 == 0


# Dominant caste among living ants of a genome (for the HUD).
func genome_caste(uid: int) -> String:
	var c = [0, 0, 0]
	for a in ants:
		if a.genome.uid == uid:
			c[a.caste] += 1
	var bi = 0
	for i in 3:
		if c[i] > c[bi]:
			bi = i
	return CASTES[bi]


func _step_eggs(dt: float) -> void:
	for e in eggs.duplicate():
		e["t"] -= dt
		if e["t"] <= 0.0:
			eggs.erase(e)
			_sfx("hatch")
			fx.append({"kind": "hatch", "pos": e["pos"] * grid.CELL + Vector2(grid.CELL * 0.5, grid.CELL * 0.5 - 6.0), "t": 0.0, "color": Color("#fff4cf")})
			_spawn_ant(e["genome"], e["gen"], _random_home_cell(), e.get("caste", -1))


func _step_food(dt: float) -> void:
	var upkeep := 0.0
	for a in ants:
		upkeep += a.ph["upkeep"]
	food -= upkeep * dt
	ledger["upkeep"] += min(upkeep * dt, max(0.0, food + upkeep * dt))
	if food < 0.0:
		food = 0.0
		_starve_timer += dt
		if _starve_timer > 8.0 and not ants.empty():
			_starve_timer = 0.0
			kill(ants[rng.randi_range(0, ants.size() - 1)], "starve")
	else:
		_starve_timer = 0.0

	_pher_acc += dt
	if _pher_acc >= 0.5:
		grid.pher_decay(exp(-_pher_acc * (1.0 + 3.0 * rain) / PHER_TAU))
		_pher_acc = 0.0

	for l in legacy:
		l["score"] *= exp(-dt / 240.0)
	for p in piles.duplicate():
		if p["amount"] <= 0.0:
			piles.erase(p)
	_pile_timer -= dt
	var gem_piles := 0
	for p in piles:
		if p.get("kind", "") == "":
			gem_piles += 1
	if gem_piles < MAX_PILES + ants.size() / 60 and _pile_timer <= 0.0:
		_spawn_pile()
		_pile_timer = rng.randf_range(8.0, 20.0)


# Food ecology: new piles appear at least `lo` cells out, and `lo` grows with time and colony size (up to RANGE_MAX).
# Near piles get eaten down, so a growing colony has to send ants farther.
func _pile_distance(near: int) -> int:
	if piles.size() < 3 or time < 90.0:
		return rng.randi_range(near, 130)    # an early colony must be able to find its first meals
	# The near ground has been picked over: after the first minutes new food only appears beyond a minimum
	# distance that keeps growing, so the colony has to send ants on longer and longer expeditions.
	# the frontier follows the colony's strength, not just the clock: a colony that has dwindled finds food nearer again
	var lo = int(clamp(60.0 + min(0.9 * time, 14.0 * ants.size()) + 0.5 * ants.size(), 60.0, 1000.0))
	if mod("pile_near") > 0.0:
		lo = int(lo * 0.6)
	var hi = int(min(RANGE_MAX - 60, lo + 450))
	if rng.randf() < 0.2:
		hi = RANGE_MAX - 60                  # now and then a very far pile
	return rng.randi_range(min(lo, hi - 40), hi)


func _spawn_pile() -> void:
	var ex = int(grid.entrance.x)
	var left := 0
	for p in piles:
		if p["x"] < ex:
			left += 1
	var want_left = left * 2 < piles.size() or (left * 2 == piles.size() and rng.randf() < 0.5)
	var near = 12 if mod("pile_near") > 0.0 else 22
	for attempt in 24:
		var d = _pile_distance(near)
		var x = ex - d if want_left else ex + d
		var ok = true
		for p in piles:
			if abs(p["x"] - x) < 14:
				ok = false
		if not ok:
			continue
		var amount = (rng.randf_range(20.0, 40.0) + d * 0.35) * (1.0 + mod("pile_rich"))
		piles.append({"x": x, "amount": amount, "max": amount})
		return


# A windfall far from the nest: huge, and worth a beacon.
func _spawn_jackpot() -> void:
	for p in piles:
		if p.get("kind", "") == "jackpot":
			return
	var ex = int(grid.entrance.x)
	var side = -1 if rng.randf() < 0.5 else 1
	var d = rng.randi_range(600, RANGE_MAX - 60)
	var amount = (110.0 + d * 0.9) * (1.0 + mod("pile_rich"))
	piles.append({"x": ex + side * d, "amount": amount, "max": amount, "kind": "jackpot"})
	toasts.append({"text": "JACKPOT: about %d food, %d cells %s of the nest. Press B over it to send scouts." % [int(amount), d, "west" if side < 0 else "east"], "t": 10.0})
	banner = "A windfall lies %d cells %s" % [d, "west" if side < 0 else "east"]
	banner_t = 4.0
	_sfx("repelled")


# ------------------------------------------------------------------ stats for the HUD
func task_counts() -> Array:
	var c = [0, 0, 0, 0, 0]
	for a in ants:
		c[a.task] += 1
	return c


func average_traits() -> Dictionary:
	var keys = ["speed", "carry", "dig", "sense", "upkeep"]
	var out := {}
	for k in keys:
		out[k] = 0.0
	if ants.empty():
		return out
	for a in ants:
		for k in keys:
			out[k] += a.ph[k]
	for k in keys:
		out[k] /= ants.size()
	return out


# ------------------------------------------------------------------ M4 evolution log
# Does this ant carry the trait? Bool organs, continuous traits past 0.4, and three
# body features (any armor plate, any claw limb or claw jaw, 2+ spikes).
static func has_trait(g, k: String) -> bool:
	if k in ORGAN_TRAITS:
		return g.organ(k) >= 1
	if k == "fusion":
		return not g.fusions().empty()
	match k:
		"legform":
			return g.form("leg") != 0 and g.form_visible("leg")
		"antform":
			return g.form("antenna") != 0 and g.form_visible("antenna")
		"venom":
			return g.form("acid") != 0 and g.form_visible("acid")
		"wings", "stinger", "acid", "glow":
			return int(g.m(k)) == 1
		"major", "replete", "camo":
			return float(g.m(k)) >= 0.4
		"armor":
			for sg in g.segments:
				if sg["armor"] > 0:
					return true
			return false
		"claws":
			if g.head().get("jaw", "") == "claw":
				return true
			for sg in g.segments:
				if sg["limb"] == "claw":
					return true
			return false
		"spikes":
			var n := 0
			for sg in g.segments:
				n += sg["spikes"]
			return n >= 2
	return false


func _sample_evolution() -> void:
	if ants.empty():
		return
	var cnt := {}
	for k in EVO_TRAITS:
		cnt[k] = 0
	var by_uid := {}
	var gsum := 0
	for a in ants:
		gsum += a.gen
		var u = a.genome.uid
		if not by_uid.has(u):
			by_uid[u] = [a.genome, 0]
		by_uid[u][1] += 1
	# trait checks once per body plan, weighted by headcount
	for u in by_uid.keys():
		var g = by_uid[u][0]
		for k in EVO_TRAITS:
			if has_trait(g, k):
				cnt[k] += by_uid[u][1]
	var top := 0
	for u in by_uid.keys():
		top = max(top, by_uid[u][1])
		# a fusion's first appearance is an evolutionary event: name it and its two parents
		if by_uid[u][1] >= 2:
			for fid in by_uid[u][0].fusions():
				if not _fusion_seen.has(fid):
					_fusion_seen[fid] = true
					var fd = Genome.FUSIONS[fid]
					toasts.append({"text": "Evolution: %s emerged - %s fused (gen %d)." % [fd["name"], fd["why"], max_gen], "t": 8.0})
	var n = float(ants.size())
	var share := {}
	for k in EVO_TRAITS:
		share[k] = cnt[k] / n
		# a trait sweeping past half the colony is an evolutionary event worth a toast
		if share[k] >= 0.5 and not _swept.get(k, false) and ants.size() >= 12:
			_swept[k] = true
			toasts.append({"text": "Evolution: %s now in %d%% of the colony (gen %d)." % [TRAIT_LABELS.get(k, k), int(share[k] * 100.0), max_gen], "t": 7.0})
		elif share[k] < 0.15 and _swept.get(k, false):
			_swept[k] = false
			toasts.append({"text": "Evolution: %s is dying out." % TRAIT_LABELS.get(k, k), "t": 6.0})
	evo_log.append({"t": time, "gen": gsum / n, "pop": ants.size(), "top": top / n, "plans": by_uid.size(), "share": share})
	if evo_log.size() > 240:
		evo_log.pop_front()


const TRAIT_LABELS = {"wings": "Wings", "stinger": "Stingers", "acid": "Acid glands", "glow": "Glow spots",
	"major": "Big heads", "replete": "Repletes", "camo": "Camouflage", "armor": "Armor plates",
	"claws": "Claws", "spikes": "Spines", "legform": "Special legs", "antform": "Special antennae", "venom": "Venom organs",
	"sonic": "Sound organs", "electric": "Electric organs", "shell": "Shells", "silk": "Silk", "tongue": "Long tongues",
	"regen": "Regrowth", "fusion": "Fused abilities"}


# Top body plans by headcount: [{"genome": g, "count": n}]
func top_genomes(n: int) -> Array:
	var counts := {}
	var by_uid := {}
	for a in ants:
		counts[a.genome.uid] = counts.get(a.genome.uid, 0) + 1
		by_uid[a.genome.uid] = a.genome
	var list := []
	for uid in counts.keys():
		list.append({"genome": by_uid[uid], "count": counts[uid]})
	list.sort_custom(self, "_by_count")
	return list.slice(0, min(n, list.size()) - 1) if list.size() > 0 else []


func _by_count(a, b) -> bool:
	return a["count"] > b["count"]


func ant_at(world_pos: Vector2, radius: float):
	var best = null
	var bd = radius * radius
	for a in ants:
		var d = ant_pos(a).distance_squared_to(world_pos)
		if d < bd:
			bd = d
			best = a
	return best


# ================================================================== raids
func _step_raids(dt: float) -> void:
	banner_t -= dt
	raid_timer -= dt * (1.0 + mod("raid_haste"))
	if raid_timer <= 0.0:
		_launch_raid()
		fate.on_raid(self)
		raid_timer = max(75.0, 125.0 - raid_n * 4.0)
	if _raid_active and hostile_count() == 0 and raid_queue.empty():
		_raid_active = false
		shop_pending = true
		if mod("interest") > 0.0:
			food += food * mod("interest")
		if float(rule("growth")) > 0.0:
			mods["hp"] = min(1.0, mods.get("hp", 0.0) + float(rule("growth")))
			mods["attack"] = min(1.0, mods.get("attack", 0.0) + float(rule("growth")))
			_refresh_phenotypes()
		if float(rule("raid_mutation")) > 0.0:
			mutation_chance = min(0.9, mutation_chance + float(rule("raid_mutation")))
		_sfx("repelled")
		banner = "Raid %d repelled" % raid_n
		banner_t = 3.0
		raids_repelled += 1
		adapt[2] = {"left": 8, "bias": {"armor": 1.6, "spike": 1.0, "claw": 1.2, "size": 1.0}}
		toasts.append({"text": "The survivors breed hardier soldiers: armor, spikes, claws.", "t": 6.0})
		if raids_repelled % 2 == 0 and mutagen < 3:
			mutagen += 1
			toasts.append({"text": "Mutagen +1 (%d). Select an ant and press G." % mutagen, "t": 6.0})
	for q in raid_queue.duplicate():
		q["delay"] -= dt
		if q["delay"] <= 0.0:
			raid_queue.erase(q)
			_spawn_enemy(q["kind"], q["side"])


func _launch_raid() -> void:
	raid_n += 1
	var rr = sub_rng("raid", raid_n)
	var side = -1 if rr.randf() < 0.5 else 1
	var budget = (3.0 + 5.5 * pow(raid_n - 1, 0.8)) * max(0.3, 1.0 + mod("raid_size"))
	# a strong colony draws a bigger raid, and the later raids keep climbing, so a healthy colony is tested rather than coasting
	budget *= clamp(ants.size() / RAID_SIZE_REF, 0.85, 1.7) * (1.0 + RAID_LATE * max(0, raid_n - 6))
	var pool = EnemyDefs.SMALL.duplicate()
	pool += EnemyDefs.SMALL      # tunnel raiders stay common so the queen feels pressure
	if raid_n >= 2:
		pool += EnemyDefs.BRUTE
	if raid_n >= 6:
		pool += EnemyDefs.ELITE
	var kinds := []
	if raid_n % BOSS_EVERY == 0:
		kinds.append("butcher")
		budget -= EnemyDefs.DEFS["butcher"]["cost"]
	# tunnel borers: from raid 4, every other raid (never on a Butcher raid), one at a time
	# until raid 12, then two. They dig their own way to the queen, so they ARE the queen threat.
	var borers := _borer_plan(budget)
	budget = max(0.0, budget - EnemyDefs.DEFS["borer"]["cost"] * borers)
	for i in borers:
		kinds.append("borer")
	var guard := 0
	var n_elite := 0
	var elite_cap = 1 if raid_n < 12 else 2     # v0.22: raids 9-10 stacked 2-3 elites on top of a borer
	while budget >= 1.0 and guard < 80:
		guard += 1
		var k = pool[rr.randi_range(0, pool.size() - 1)]
		if EnemyDefs.ELITE.has(k) and n_elite >= elite_cap:
			continue
		if EnemyDefs.DEFS[k]["cost"] <= budget:
			kinds.append(k)
			budget -= EnemyDefs.DEFS[k]["cost"]
			if EnemyDefs.ELITE.has(k):
				n_elite += 1
	_raid_active = true
	# Raiders arrive in waves, not one every 0.9 s: a trickle was killed one by one as it came, so even a 70-raider raid
	# never put more than ~15 on the field and a big colony coasted. A wave walks in together and has to be fought as a mass.
	var wave = int(max(5.0, ceil(kinds.size() / 5.0)))
	for i in kinds.size():
		var dly = i * 0.9                                                      # small raids keep the old trickle
		if kinds.size() > 10:
			dly = (i / wave) * 7.0 + (i % wave) * 0.25
		raid_queue.append({"kind": kinds[i], "side": side, "delay": dly})
	banner = "Raid %d  -  %d raiders from the %s" % [raid_n, kinds.size(), "west" if side < 0 else "east"]
	if borers > 0:
		banner += "  -  %d BORING toward the queen!" % borers
	_sfx("boss" if kinds.has("butcher") else "raid")
	banner_t = 6.0


# How many tunnel borers this raid brings.
# lever 0 (v0.17): from borer_start, every other non-Butcher raid, once the colony has
#   BORER_MIN_ANTS; 1 borer, 2 from raid 12.
# lever 1+: borers answer colony size, not the raid clock. The first one comes at the
#   first even raid >= borer_start with 50+ ants, or at raid 10 whatever the size (so
#   the queen threat never vanishes). Count = 1 per 60 ants, capped at 1 before raid 12
#   and 3 after. Small colonies get skipped raids to regrow.
func _borer_plan(budget: float) -> int:
	if raid_n < borer_start or raid_n % 2 != 0 or raid_n % BOSS_EVERY == 0:
		return 0
	var n = ants.size()
	if borer_lever <= 0:
		if n < BORER_MIN_ANTS:
			return 0
		var b0 = 1 if raid_n < 12 else 2
		return int(min(b0, max(1.0, budget / 8.0)))
	if n < BORER_SCALE_MIN and raid_n < BORER_FORCE_RAID:
		return 0
	var b = int(clamp(floor(n / BORER_PER_ANTS), 1, 1 if raid_n < 12 else 3))
	return int(min(b, max(1.0, budget / 8.0)))


const BORER_SCALE_MIN = 50
const BORER_FORCE_RAID = 10
const BORER_PER_ANTS = 60.0


func _spawn_enemy(kind: String, side: int) -> void:
	var d = EnemyDefs.DEFS[kind]
	var e = Raider.new()
	e.id = _next_enemy_id
	_next_enemy_id += 1
	e.kind = kind
	e.def = d
	e.cls = d["cls"]
	e.x = grid.arena_l + rng.randi_range(2, 8) if side < 0 else grid.arena_r + 1 - rng.randi_range(3, 9)
	if d["cls"] == "burrower":
		# breaks ground 22-44 cells from the main shaft, on the raid's side
		e.x = int(clamp(int(grid.entrance.x) + side * rng.randi_range(22, 44), grid.arena_l + 14, grid.arena_r - 14))
		e.dest = grid.chamber + Vector2(rng.randi_range(-3, 3), -grid.chamber_r.y + 1)
		fx.append({"kind": "puff", "pos": grid.center(e.x, grid.surf_y(e.x) - 1), "t": 0.0, "color": Color("#b58a5c")})
		fx.append({"kind": "text", "pos": grid.center(e.x, grid.surf_y(e.x) - 4), "t": 0.0, "text": "DIGGING!", "color": Color("#ff8a5c")})
	e.y = grid.surf_y(e.x) - 1
	e.tx = e.x
	e.ty = e.y
	e.max_hp = d["hp"] * (1.0 + (0.06 if d["cls"] == "burrower" else 0.095) * (raid_n - 1) + RAID_HP_LATE * pow(max(0, raid_n - 8), 2.0)) * fate.raider_hp_mult
	if d["cls"] == "burrower":
		if borer_lever >= 2:
			# lever 2: borer HP follows colony size both ways (small colony: weak borer,
			# city: a borer that needs a real defence)
			e.max_hp *= clamp(ants.size() / 80.0, 0.45, 1.35)
		else:
			e.max_hp *= clamp(ants.size() / 70.0, 0.55, 1.0)   # a small colony faces a weaker borer
	e.hp = e.max_hp
	e.heading = -side
	e.facing = e.heading
	e.lane = rng.randf_range(0.1, 0.9)
	enemies.append(e)
	if kind == "butcher":
		shake = max(shake, 0.7)
		fx.append({"kind": "ring", "pos": grid.center(e.x, e.y - 2), "t": 0.0, "color": Color("#ff8a5c")})


func enemy_pos(e) -> Vector2:
	return grid.center(e.x, e.y).linear_interpolate(grid.center(e.tx, e.ty), e.t)


func _step_enemy(e, dt: float) -> void:
	if e.cls != "burrower":
		_footing_fix(e, dt)
	e.flash = max(0.0, e.flash - dt)
	e.spark = max(0.0, e.spark - dt)
	e.slow_t = max(0.0, e.slow_t - dt)
	if e.stun_t > 0.0:
		e.stun_t -= dt     # snared: frozen in place
		return
	e.timer += dt
	var dist = 1.4142 if (e.tx != e.x and e.ty != e.y) else 1.0
	if e.tx == e.x and e.ty == e.y and e.tz == e.z:
		e.t = 1.0
		dist = 1.0
	else:
		var spd = e.def["speed"] * (0.8 if e.cls == "burrower" and e.state == 3 else 1.0) * (0.55 if e.slow_t > 0.0 else 1.0)
		e.t += spd * dt / dist * (0.3 if e.engaged and e.state != 2 else 1.0)
	var hops = 0
	while e.t >= 1.0 and hops < 3:
		hops += 1
		var over = (e.t - 1.0) * dist
		e.x = e.tx
		e.y = e.ty
		e.z = e.tz
		e.t = 0.0
		_enemy_arrive(e)
		if not enemies.has(e):
			return      # escaped or died during the arrival step
		if e.tx != e.x:
			e.facing = 1 if e.tx > e.x else -1
		if e.tx != e.x or e.ty != e.y or e.tz != e.z:
			dist = 1.4142 if (e.tx != e.x and e.ty != e.y) else 1.0
			e.t = min(over / dist, 1.6)
		else:
			break


func _enemy_arrive(e) -> void:
	var ex = int(grid.entrance.x)
	var under = grid.is_under(e.x, e.y)
	if e.state == 2:
		if e.x <= grid.arena_l + 2 or e.x >= grid.arena_r - 2:
			enemies.erase(e)   # escaped
			return
		if under:
			_descend(e, grid.dist_exit)
			return
		e.heading = -1 if e.x < ex else 1
		_walk_surface(e)
		return

	if e.cls == "prey":
		var near = _nearest_surface_ant(e.x, 6)
		if near != null:
			_set_heading(e, -1 if near.x > e.x else 1)
		elif rng.randf() < 0.04:
			e.heading = -e.heading
		if e.x <= grid.arena_l + 3 or e.x >= grid.arena_r - 3:
			e.heading = 1 if e.x <= grid.arena_l + 3 else -1
		_walk_surface(e)
		return
	if e.cls == "burrower":
		_burrower_arrive(e)
		return
	if e.cls == "small":
		ex = grid.nearest_entrance_x(e.x)
		if under or abs(e.x - ex) <= 2:
			if grid.field(grid.dist_home, e.x, e.y, e.z) > 1:
				_descend(e, grid.dist_home)
			else:
				_go(e, Vector2(e.x, e.y))
			return
		var prey = _chase_target(e, 6)
		if prey != null and abs(prey.x - e.x) <= 1:
			_go(e, Vector2(e.x, e.y))        # on top of its target: stand and fight, do not shuffle back and forth
			return
		_set_heading(e, _dir_to(e.x, prey.x if prey != null else ex))
		_walk_surface(e)
		return

	# surface siegers
	if e.state == 0 and abs(e.x - ex) <= 4:
		e.state = 1
		e.timer = 0.0
	if e.state == 1 and e.timer > SIEGE_TIME:
		e.state = 2
		banner = "The %s retreats" % e.def["name"]
		banner_t = 3.0
	var prey = _chase_target(e, 10 if e.state == 1 else 14)
	var goal = ex
	if prey != null:
		goal = prey.x
	elif e.state == 1:
		goal = ex + rng.randi_range(-5, 5)
	var d = _dir_to(e.x, goal)
	if d == 0 or (prey != null and abs(goal - e.x) <= 1):
		_go(e, Vector2(e.x, e.y))
		return
	_set_heading(e, d)
	_walk_surface(e)


# A raider reverses at most every few hops, so a runner weaving past it does not make it flip left and right
# (hops are short, and the squash-turn would read as a shiver).
func _set_heading(e, d: int) -> void:
	if e.turn_t > 0:
		e.turn_t -= 1
	if d == 0 or d == e.heading or e.turn_t > 0:
		return
	e.heading = d
	e.turn_t = 5


# Borers: brief surface wind-up (ants can hit them), then bore a fresh tunnel toward
# the queen chamber, carving as they go. The tunnel stays open, so ants can follow it.
func _burrower_arrive(e) -> void:
	if e.state == 0:
		if e.timer < 2.2:
			_go(e, Vector2(e.x, e.y))
			return
		e.state = 3
	var cur = Vector2(e.x, e.y)
	if cur.distance_to(e.dest) <= 1.6 or (grid.is_under(e.x, e.y) and grid.field(grid.dist_home, e.x, e.y) >= 0 and grid.field(grid.dist_home, e.x, e.y) <= 1):
		_go(e, cur)   # arrived: gnaws at the queen (see _combat)
		return
	var best = null
	var bs = 1e9
	for d in grid.N8:
		var c = cur + d
		if not grid.inb(int(c.x), int(c.y)) or c.y < cur.y:
			continue
		var sc = c.distance_to(e.dest) + (0.3 if d.x != 0 and d.y != 0 else 0.0)
		if sc < bs:
			bs = sc
			best = c
	if best == null:
		return
	grid._carve_raw(best.x, best.y, 1.35, true, 0, true)   # borers chew through anything but the world floor
	fx.append({"kind": "puff", "pos": grid.center(int(best.x), int(best.y)), "t": 0.0, "color": Color("#8a6a48")})
	e.facing = 1 if best.x > cur.x else (-1 if best.x < cur.x else e.facing)
	_go(e, best)


func burrowers_active() -> int:
	var n := 0
	for e in enemies:
		if e.cls == "burrower":
			n += 1
	return n


func _dir_to(from_x: int, to_x: int) -> int:
	if to_x > from_x:
		return 1
	if to_x < from_x:
		return -1
	return 0


# The ant a raider is chasing: the same one for ~12 hops (so a runner weaving among neighbours does not make the
# raider flip left and right every hop), then the nearest again.
func _chase_target(e, max_d: int):
	if e.chase_t > 0:
		e.chase_t -= 1
		for a in ants:
			if a.id == e.chase_id:
				if not grid.is_under(a.x, a.y) and abs(a.x - e.x) <= max_d + 4:
					return a
				break
	var t = _nearest_surface_ant(e.x, max_d)
	if t != null:
		e.chase_id = t.id
		e.chase_t = 12
	return t


func _nearest_surface_ant(x: int, max_d: int):
	var best = null
	var bd = max_d + 1
	for a in ants:
		if not grid.is_under(a.x, a.y):
			var d = abs(a.x - x)
			if d < bd:
				bd = d
				best = a
	return best


func _nearest_surface_enemy(x: int, max_d: int):
	var best = null
	var bd = max_d + 1
	for e in enemies:
		if e.cls != "small" and e.cls != "prey" and e.cls != "burrower" and not grid.is_under(e.x, e.y):
			var d = abs(e.x - x)
			if d < bd:
				bd = d
				best = e
	return best


func _combat(dt: float) -> void:
	var scale = 1.0 + 0.065 * (raid_n - 1) + RAID_BITE_LATE * pow(max(0, raid_n - 8), 2.0)
	var queen_hit := false
	_update_rally()
	# ant positions once per tick (was recomputed for every raider x ant pair); `apos` stays
	# index-aligned with `ants` and is rebuilt if a death changes the array mid-loop
	var apos := PoolVector2Array()
	var max_k2 := 1.0
	var apos_n := -1
	for e in enemies.duplicate():
		e.engaged = false
		if e.state == 2:
			continue
		if apos_n != ants.size():
			apos_n = ants.size()
			apos = PoolVector2Array()
			max_k2 = 1.0
			for a0 in ants:
				apos.append(ant_pos(a0))
				max_k2 = max(max_k2, a0.ph.get("reach2", 1.0))
		var ep = enemy_pos(e)
		var reach = EnemyDefs.REACH[e.cls] * grid.CELL
		var r2 = reach * reach
		var ar = reach * _r_reach
		var ar2 = ar * ar
		var far = ar * sqrt(max_k2) + 0.01   # no ant can be hit from farther than this
		var target = null
		var td = 1e12
		var dmg_in := 0.0
		for ai in apos_n:
			var a = ants[ai]
			if a.z != e.z:
				continue   # a wall of dirt between them
			var apx = apos[ai]
			if abs(apx.x - ep.x) > far:
				continue
			var d = apx.distance_squared_to(ep)
			if d <= ar2 * a.ph.get("reach2", 1.0):
				var w = (1.0 + mod("defend_attack")) if a.task == Task.DEFEND else (0.8 if e.cls == "prey" else 0.3)
				var hit = a.ph["attack"] * w * dt * a.rally_k
				if a.ph.get("sonarweb", false) and (e.slow_t > 0.0 or e.stun_t > 0.0):
					hit *= 1.3    # sonar web: feels exactly where the trapped raider is
				if _r_fury > 0.0 and a.hp < a.ph["hp"] * 0.5:
					hit *= 1.0 + _r_fury
				if _r_steal > 0.0:
					a.hp = min(a.ph["hp"], a.hp + hit * _r_steal)
				dmg_in += hit
				a.fitness += hit * 0.08
				a.f_fight += hit * 0.08
				a.lane = lerp(a.lane, clamp(e.lane + (a.id % 3 - 1) * 0.12, 0.0, 1.0), clamp(dt * 6.0, 0.0, 1.0))   # fighters line up with their raider quickly
				if d <= r2 and d < td:
					td = d
					target = a
		if e.stun_t > 0.0:
			e.engaged = true
			target = null     # snared raiders take hits but cannot bite
		if target != null:
			e.engaged = true
			if target.ph.get("web", 0.0) > 0.0:
				e.slow_t = 1.2
			if target.ph.get("curl", false) and target.curl_t <= 0.0 and target.curl_cd <= 0.0 and target.hp < target.ph["hp"] * 0.4:
				target.curl_t = 3.0
				target.curl_cd = target.ph.get("curl_cd", 10.0)
				fx.append({"kind": "text", "pos": ant_pos(target) + Vector2(0, -24), "t": 0.0, "text": "CURL", "color": Color("#d9c08a")})
			var curl_k = 0.3 if target.curl_t > 0.0 else 1.0
			target.hp -= e.def["dmg"] * e.def.get("ant_mult", 1.0) * scale * dt * (1.0 - target.ph["armor_red"] * (1.0 - fate.raider_pierce)) * curl_k
			target.hurt = 0.12
			dmg_in += target.ph["thorns"] * dt * (1.0 - fate.raider_hide)
			if target.hp <= 0.0:
				_ant_falls(target)
		elif e.stun_t <= 0.0 and (e.cls == "small" or e.cls == "burrower") and grid.is_under(e.x, e.y) and grid.field(grid.dist_home, e.x, e.y, e.z) >= 0 and grid.field(grid.dist_home, e.x, e.y, e.z) <= 2:
			e.engaged = true
			queen_hp -= e.def["dmg"] * scale * dt
			queen_hit = true
		if e.state == 1:
			dmg_in += mod("siege_dmg") * dt
		elif grid.is_under(e.x, e.y):
			dmg_in += mod("tunnel_dmg") * dt
		if dmg_in > 0.0:
			if e.flash <= 0.0 and target != null:
				_sfx("hit")
			if e.spark <= 0.0 and dmg_in > 0.0:
				e.spark = 0.25
				fx.append({"kind": "spark", "pos": enemy_pos(e) + Vector2(rng.randf_range(-14.0, 14.0), -rng.randf_range(8.0, 30.0)), "t": 0.0, "color": Color("#ffe08a")})
			e.hp -= dmg_in
			e.flash = 0.1
		if e.hp <= 0.0:
			_enemy_die(e)

	queen_flash = max(0.0, queen_flash - dt)
	_queen_warned -= dt
	if queen_hit:
		_queen_calm = 0.0
		queen_flash = 0.6
		if _queen_warned <= 0.0:
			_queen_warned = 6.0
			queen_hits += 1
			shake = max(shake, 0.55)
			banner = "THE QUEEN IS UNDER ATTACK!"
			banner_t = 3.0
			_sfx("queen_hit")
	else:
		_queen_calm += dt
		if _queen_calm > 5.0:
			queen_hp = min(queen_max, queen_hp + 3.0 * (1.0 + mod("queen_regen")) * dt)
			_heal_fx_t -= dt
			if queen_hp < queen_max - 1.0 and _heal_fx_t <= 0.0:
				_heal_fx_t = 1.0
				fx.append({"kind": "heal", "pos": queen_fx_pos(), "t": 0.0, "color": Color("#7ed957")})
	if mod("regen") > 0.0:
		for a in ants:
			if a.hp < a.ph["hp"] and grid.is_under(a.x, a.y) and grid.field(grid.dist_home, a.x, a.y, a.z) <= 12:
				a.hp = min(a.ph["hp"], a.hp + mod("regen") * dt)


func _ant_falls(a) -> void:
	if float(rule("revive")) > 0.0 and not a.revived and rng.randf() < float(rule("revive")):
		a.revived = true
		a.hp = a.ph["hp"] * 0.35
		fx.append({"kind": "text", "pos": ant_pos(a) + Vector2(0, -24), "t": 0.0, "text": "RISES", "color": Color("#b8c8ff")})
		return
	if float(rule("undead")) > 0.0 and rng.randf() < float(rule("undead")):
		var broods := []
		for c in planner.chambers:
			if c["purpose"] == "brood":
				broods.append(c)
		var ep = _egg_pos(broods)
		eggs.append({"t": 5.0, "genome": a.genome, "gen": a.gen + 1, "pos": Vector2(ep.x, ep.y), "z": int(ep.z), "caste": a.caste})
		fx.append({"kind": "text", "pos": ant_pos(a) + Vector2(0, -24), "t": 0.0, "text": "RETURNS", "color": Color("#d8e8a0")})
	elif a.ph.get("split", 0.0) > 0.0 and rng.randf() < a.ph["split"]:
		# planarian split: the torn body regrows as a fresh egg of the same plan
		var broods2 := []
		for c in planner.chambers:
			if c["purpose"] == "brood":
				broods2.append(c)
		var ep2 = _egg_pos(broods2)
		eggs.append({"t": 6.0, "genome": a.genome, "gen": a.gen + 1, "pos": Vector2(ep2.x, ep2.y), "z": int(ep2.z), "caste": a.caste})
		fx.append({"kind": "text", "pos": ant_pos(a) + Vector2(0, -24), "t": 0.0, "text": "SPLITS", "color": Color("#ffb3c8")})
	kill(a, "combat")


# Stridulating ants (sonic tier 1+) that are fighting rally every ant within 4 cells on
# their plane: attack x (1 + rally), strongest source only. Cheap: sources are few.
func _update_rally() -> void:
	var src := []
	var any_e = not enemies.empty()
	for a in ants:
		a.rally_k = 1.0
		if any_e and src.size() < 24 and a.ph.get("rally", 0.0) > 0.0 and (a.task == Task.DEFEND or a.hurt > 0.0):
			src.append(a)
	if src.empty():
		return
	var r2 = pow(4.0 * grid.CELL, 2)
	for s in src:
		var sp = ant_pos(s)
		for a in ants:
			if a.z == s.z and ant_pos(a).distance_squared_to(sp) <= r2:
				a.rally_k = max(a.rally_k, 1.0 + s.ph["rally"])


# Live organ abilities (v0.21): regrowth and curl timers every tick; ranged abilities
# fire on cooldown at raiders on the same tunnel plane. Damage scales with the raid like
# the Lab zap does. Prey are left to the foragers.
func _step_abilities(dt: float) -> void:
	var hostile := []
	for e in enemies:
		if e.cls != "prey":
			hostile.append(e)
	var C = grid.CELL
	var dscale = 1.0 + 0.04 * (raid_n - 1)
	for a in ants:
		var ph = a.ph
		if not ph.get("abil", false):
			continue
		a.curl_t = max(0.0, a.curl_t - dt)
		a.curl_cd = max(0.0, a.curl_cd - dt)
		var heal = ph["regen"] + (ph["curl_heal"] if a.curl_t > 0.0 else 0.0)
		if heal > 0.0 and a.hp < ph["hp"]:
			a.hp = min(ph["hp"], a.hp + heal * dt)
		if hostile.empty():
			continue
		var ap = ant_pos(a)
		if ph["pulse"] > 0.0:
			a.cd_pulse -= dt
			if a.cd_pulse <= 0.0:
				var hits = _in_range(hostile, ap, a.z, ph["pulse_r"] * C, 99)
				a.cd_pulse = ph["pulse_cd"] if not hits.empty() else 0.5
				if not hits.empty():
					fx.append({"kind": "wave", "pos": ap + Vector2(0, -10), "t": 0.0, "r": ph["pulse_r"] * C, "color": Color("#9ff0ff") if ph["thunder"] else Color("#ffe9a8")})
					for e in hits:
						_ability_hit(a, e, ph["pulse"] * dscale)
						if ph["thunder"]:
							fx.append({"kind": "arc", "pos": ap + Vector2(0, -14), "to": enemy_pos(e) + Vector2(0, -14), "t": 0.0, "color": Color("#9ff0ff")})
					_sfx("hit")
		if ph["arc"] > 0.0:
			a.cd_arc -= dt
			if a.cd_arc <= 0.0:
				var chain = _in_range(hostile, ap, a.z, ph["arc_r"] * C, ph["arc_n"])
				a.cd_arc = ph["arc_cd"] if not chain.empty() else 0.5
				var prev = ap + Vector2(0, -14)
				for e in chain:
					var to = enemy_pos(e) + Vector2(0, -14)
					fx.append({"kind": "arc", "pos": prev, "to": to, "t": 0.0, "color": Color("#8ab8ff")})
					prev = to
					_ability_hit(a, e, ph["arc"] * dscale)
		if ph["snipe"] > 0.0:
			a.cd_snipe -= dt
			if a.cd_snipe <= 0.0:
				var tg = _in_range(hostile, ap, a.z, ph["snipe_r"] * C, 1)
				a.cd_snipe = ph["snipe_cd"] if not tg.empty() else 0.5
				for e in tg:
					fx.append({"kind": "beam", "pos": ap + Vector2(0, -12), "to": enemy_pos(e) + Vector2(0, -12), "t": 0.0, "color": Color("#ff8fb1")})
					if ph["snipe_stun"] > 0.0:
						e.stun_t = max(e.stun_t, ph["snipe_stun"])
					_ability_hit(a, e, ph["snipe"] * dscale)
		if ph["snare_r"] > 0.0:
			a.cd_snare -= dt
			if a.cd_snare <= 0.0:
				var tg2 = _in_range(hostile, ap, a.z, ph["snare_r"] * C, 1)
				a.cd_snare = ph["snare_cd"] if not tg2.empty() else 0.5
				for e in tg2:
					e.stun_t = max(e.stun_t, ph["snare_t"] if e.cls != "boss" else ph["snare_t"] * 0.4)
					fx.append({"kind": "web", "pos": enemy_pos(e) + Vector2(0, -16), "t": 0.0, "color": Color("#f2f2f2")})
					fx.append({"kind": "beam", "pos": ap + Vector2(0, -12), "to": enemy_pos(e) + Vector2(0, -16), "t": 0.0, "color": Color("#f2f2f2")})


# Up to n raiders within radius on the same plane, nearest first.
func _in_range(pool: Array, p: Vector2, z: int, radius: float, n: int) -> Array:
	var r2 = radius * radius
	var found := []
	for e in pool:
		if e.z != z or e.hp <= 0.0:
			continue
		var d = enemy_pos(e).distance_squared_to(p)
		if d <= r2:
			found.append([d, e])
	found.sort_custom(self, "_by_first")
	var out := []
	for i in min(n, found.size()):
		out.append(found[i][1])
	return out


func _by_first(a, b) -> bool:
	return a[0] < b[0]


func _ability_hit(a, e, dmg: float) -> void:
	if not enemies.has(e):
		return
	e.hp -= dmg
	e.flash = 0.15
	a.fitness += dmg * 0.08
	a.f_fight += dmg * 0.08
	if e.hp <= 0.0:
		_enemy_die(e)


func _step_zap(dt: float) -> void:
	var z = float(rule("zap"))
	if z <= 0.0 or hostile_count() == 0:
		return
	_zap_t -= dt
	if _zap_t > 0.0:
		return
	_zap_t = 5.0
	var pool := []
	for e in enemies:
		if e.cls != "prey":
			pool.append(e)
	for i in int(min(int(rule("zap_targets", 1)), pool.size())):
		var e = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(e)
		e.hp -= z * (1.0 + 0.04 * (raid_n - 1))
		e.flash = 0.2
		fx.append({"kind": "puff", "pos": enemy_pos(e), "t": 0.0, "color": Color("#8ab8ff")})
		fx.append({"kind": "text", "pos": enemy_pos(e) + Vector2(0, -30), "t": 0.0, "text": "ZAP", "color": Color("#8ab8ff")})
		if e.hp <= 0.0:
			_enemy_die(e)
	_sfx("hit")


func _enemy_die(e) -> void:
	enemies.erase(e)
	kills += 1
	var p = enemy_pos(e)
	var amount = e.def["food"] * (1.0 + 0.1 * (raid_n - 1)) * (1.0 + mod("kill_food"))
	if e.cls == "prey":
		amount *= 1.0 + 0.5 * (float(rule("prey_boost", 1.0)) - 1.0)
	elif float(rule("bloodlust")) > 0.0:
		bloodlust_bonus = min(0.5, bloodlust_bonus + float(rule("bloodlust")))
		if bloodlust_bonus - _bl_applied >= 0.03:
			_bl_applied = bloodlust_bonus
			_refresh_phenotypes()
	if e.cls != "prey" and float(rule("tame")) > 0.0 and grid.is_under(e.x, e.y) and rng.randf() < float(rule("tame")):
		_lay_egg()
		fx.append({"kind": "text", "pos": p + Vector2(0, -50), "t": 0.0, "text": "TAMED", "color": Color("#f2c14e")})
	_sfx("kill")
	fx.append({"kind": "puff", "pos": p, "t": 0.0, "color": Color("#7ed957")})
	fx.append({"kind": "burst", "pos": p + Vector2(0, -12), "t": 0.0, "color": Color("#c8ff9a")})
	if e.cls == "boss" or e.cls == "elite":
		fx.append({"kind": "ring", "pos": p + Vector2(0, -12), "t": 0.0, "color": Color("#c8ff9a")})
		shake = max(shake, 0.5 if e.cls == "boss" else 0.25)
	fx.append({"kind": "text", "pos": p + Vector2(0, -30), "t": 0.0, "text": "+%d" % int(amount), "color": Color("#a8ec74")})
	if grid.is_under(e.x, e.y):
		food += amount   # killed inside: hauled straight to the stores
		ledger["kills"] += amount
	else:
		ledger["other_in"] += 0.0   # surface kills drop a pile; foragers bring it in as "forage"
		_drop_food(e.x, amount)


func _drop_food(x: int, amount: float) -> void:
	x = int(clamp(x, grid.arena_l + 3, grid.arena_r - 3))
	for p in piles:
		if abs(p["x"] - x) <= 3:
			p["amount"] += amount
			p["max"] = max(p["max"], p["amount"])
			return
	piles.append({"x": x, "amount": amount, "max": amount})


func _cap_fx() -> void:
	while fx.size() > 150:
		fx.pop_front()


func _step_threat(dt: float) -> void:
	_cap_fx()
	_threat_timer -= dt
	if _threat_timer <= 0.0:
		_threat_timer = 0.7
		var src := []
		for e in enemies:
			if e.cls != "prey" and grid.can_walk(e.x, e.y, e.z):   # passive prey is not a threat
				src.append(Vector3(e.x, e.y, e.z))
		dist_threat = grid._bfs(src, 260) if not src.empty() else PoolIntArray()
	# alarm: idle and digging ants reconsider quickly while raiders are present
	_alarm_timer -= dt
	if hostile_count() > 0 and _alarm_timer <= 0.0:
		_alarm_timer = 2.0
		for a in ants:
			if a.task == Task.NURSE or a.task == Task.DIG or (a.task == Task.FORAGE and a.carry == 0.0 and grid.is_under(a.x, a.y)):
				if rng.randf() < 0.5:
					_choose_task(a)


func _defend(a) -> void:
	if hostile_count() == 0 or a.timer > 70.0 or dist_threat.size() == 0:
		a.task = Task.HOME
		_descend(a, grid.dist_home)
		return
	var d = grid.field(dist_threat, a.x, a.y, a.z)
	if d >= 0 and d <= 1:
		_go(a, Vector2(a.x, a.y))   # hold and fight
	elif d < 0:
		_descend(a, grid.dist_exit)
	else:
		_descend(a, dist_threat)


# ================================================================== Evolution Lab
func _apply_instincts(g):
	var need_copy = false
	for k in trait_bias.keys():
		if trait_bias[k] != 0.0:
			need_copy = true
	if base_armor > 0:
		for seg in g.segments:
			if seg["armor"] < base_armor:
				need_copy = true
	if not need_copy or rng.randf() > 0.5:
		return g
	var c = g.copy()
	for k in trait_bias.keys():
		c.traits[k] = clamp(c.traits.get(k, 0.5) + trait_bias[k], 0.02, 1.0)
	for seg in c.segments:
		seg["armor"] = int(max(seg["armor"], base_armor))
	register_genome(c)
	return c


func price(id: String) -> int:
	var it = ShopItems.ITEMS[id]
	return int(round(it["price"] * (1.0 + 0.08 * raid_n) * (1.0 + 0.15 * owned.get(id, 0)) * max(0.4, 1.0 - mod("price_disc"))))


func reroll_cost() -> int:
	if free_rerolls > 0:
		return 0
	return int(max(1.0, 5.0 - mod("reroll_disc"))) + 4 * rerolls


func open_shop() -> void:
	shop_pending = false
	rerolls = 0
	_shop_visits += 1
	free_rerolls = int(rule("free_reroll"))
	_roll_offers()
	fate.on_shop(self)


func reroll() -> bool:
	var c = reroll_cost()
	if food < c:
		return false
	food -= c
	ledger["lab"] += c
	if free_rerolls > 0:
		free_rerolls -= 1
	else:
		rerolls += 1
	_roll_offers()
	return true


# Independent stream for one draw site: same (tag, a, b) -> same numbers in every run of
# this seed, whatever happened in between (borers, deaths, behaviour).
func sub_rng(tag: String, a: int, b: int = 0) -> RandomNumberGenerator:
	var r = RandomNumberGenerator.new()
	r.seed = hash([seed_base, tag, a, b])
	return r


func _roll_offers() -> void:
	offers.clear()
	var srng = sub_rng("lab", raid_n, rerolls * 16 + _shop_visits)
	var tw = ShopItems.tier_weights(raid_n)
	var luck = float(rule("lab_luck")) + mod("luck")
	if luck > 0.0:
		tw[2] *= 1.0 + luck
		tw[3] = (tw[3] + 0.04 * luck) * (1.0 + luck)
		tw[4] = (tw[4] + 0.01 * luck) * (1.0 + luck)
	var pool := []
	var weights := []
	for id in ShopItems.ITEMS.keys():
		var it = ShopItems.ITEMS[id]
		if it.has("max") and owned.get(id, 0) >= it["max"]:
			continue
		if tw[it["tier"]] <= 0.0:
			continue
		pool.append(id)
		weights.append(tw[it["tier"]])
	for i in 4 + int(rule("lab_offers")) + fate.take_bonus_offers():
		if pool.empty():
			break
		var tot := 0.0
		for w in weights:
			tot += w
		var roll = srng.randf() * tot
		var j = weights.size() - 1
		for k in weights.size():
			roll -= weights[k]
			if roll <= 0.0:
				j = k
				break
		var pick = pool[j]
		offers.append(pick)
		pool.remove(j)
		weights.remove(j)


func buy(slot: int) -> bool:
	if slot < 0 or slot >= offers.size() or offers[slot] == "":
		return false
	var id = offers[slot]
	var cost = price(id)
	if food < cost:
		return false
	food -= cost
	ledger["lab"] += cost
	owned[id] = owned.get(id, 0) + 1
	_apply_item(id)
	offers[slot] = ""
	return true


func _apply_item(id: String) -> void:
	_apply_effects(ShopItems.ITEMS[id])
	fate.on_buy(self, id)


func _apply_effects(it: Dictionary) -> void:
	for k in it.get("bias", {}).keys():
		mut_bias[k] = mut_bias.get(k, 0.0) + it["bias"][k]
	for k in it.get("trait", {}).keys():
		trait_bias[k] = trait_bias.get(k, 0.0) + it["trait"][k]
	var c = it.get("colony", {})
	if c.has("mutation"):
		mutation_chance = min(0.9, mutation_chance + c["mutation"])
	if c.has("queen_hp"):
		queen_max += c["queen_hp"]
		queen_hp = queen_max
	if c.has("hatch"):
		hatch_time *= c["hatch"]
	if c.has("egg_cost"):
		egg_cost = max(2.0, egg_cost + c["egg_cost"])
	if c.has("base_armor"):
		base_armor += c["base_armor"]
	if c.has("tournament"):
		tournament += c["tournament"]
	if c.has("queen_hp_pct"):
		queen_max *= 1.0 + c["queen_hp_pct"]
		queen_hp = queen_max
	if c.has("double_mut"):
		double_mut = min(0.9, double_mut + c["double_mut"])
	var m = it.get("mods", {})
	for k in m.keys():
		mods[k] = mods.get(k, 0.0) + m[k]
	if not m.empty():
		_refresh_phenotypes()
	if c.has("entrance"):
		var main_x = int(grid.entrance.x)
		var side = 1 if grid.entrances.size() % 2 == 1 else -1
		grid.add_entrance(main_x + side * rng.randi_range(50, 80))


# ================================================================== economy: storage, rot, farms, trees
func hostile_count() -> int:
	var n := 0
	for e in enemies:
		if e.cls != "prey":
			n += 1
	return n


func _step_economy(dt: float) -> void:
	food_cap = 80.0 + (45.0 + float(rule("cap_per_chamber"))) * planner.count("food")
	rot_rate = 0.0
	if food > food_cap:
		rot_rate = (food - food_cap) * 0.012 * float(rule("rot_mult", 1.0))
		food -= rot_rate * dt
		ledger["rot"] += rot_rate * dt
	var nurses := 0
	for a in ants:
		if a.task == Task.NURSE:
			nurses += 1
	var farms = planner.count("farm")
	# fungus farms ferment scraps (and part of what rots) back into food
	farm_rate = farms * 0.14 * float(rule("farm_boost", 1.0)) * (0.5 + 0.5 * min(1.0, nurses / max(1.0, farms * 3.0))) + rot_rate * (0.4 if farms > 0 else 0.0)
	food += farm_rate * dt
	ledger["farm"] += farm_rate * dt
	_sync_trees(dt)
	_check_landmarks(dt)
	for tr in trees:
		tr["t"] -= dt * float(rule("fruit_boost", 1.0))
		if tr["t"] <= 0.0:
			tr["t"] = rng.randf_range(22.0, 34.0)       # the giant fruit trees are the landscape's oases (a few feed a small colony; a big one must range)
			_drop_fruit(tr["x"])


# The giant trees of the landscape (world_features.gd) are the fruit sources, everywhere out to RANGE_MAX.
var _tree_ids := {}
var _tree_sync := 0.0
# v0.23 exploration: landmarks out in the world (giant trees, caves, cliff vistas) that ants discover by walking up to them
var landmarks: Array = []        # [{"id", "kind", "x", "found"}]
var discovered := 0
var caves_found := 0
var _lm_t := 0.0


func _sync_trees(dt: float, force: bool = false) -> void:
	_tree_sync -= dt
	if _tree_sync > 0.0 and not force:
		return
	_tree_sync = 5.0
	var ex = int(grid.entrance.x)
	for f in WF.in_range(seed_base, ex - RANGE_MAX, ex + RANGE_MAX, ex):
		if abs(f["x"] - ex) > RANGE_MAX - 30 or _tree_ids.has(f["id"]):
			continue
		match f["kind"]:
			"tree":
				_tree_ids[f["id"]] = true
				trees.append({"x": f["x"], "lane": f["lane"], "t": rng.randf_range(5.0, 25.0), "id": f["id"]})
				landmarks.append({"id": f["id"], "kind": "tree", "x": f["x"], "found": false})
			"cliff":
				_tree_ids[f["id"]] = true
				var cx = f["x"]
				var kind = "vista"
				if f.get("cave", false):
					kind = "cave"
					cx = f["x"] + int((f["cave_at"] - 0.5) * f["w"] / grid.CELL)
				landmarks.append({"id": f["id"], "kind": kind, "x": cx, "found": false})


# An ant that walks up to a landmark discovers it: a reward, a toast, and a ring on the world.
func _check_landmarks(dt: float) -> void:
	_lm_t -= dt
	if _lm_t > 0.0 or landmarks.empty() or ants.empty():
		return
	_lm_t = 0.7
	for lm in landmarks:
		if lm["found"]:
			continue
		for a in ants:
			if abs(a.x - lm["x"]) <= 16 and not grid.is_under(a.x, a.y):
				_discover(lm)
				break


func _discover(lm: Dictionary) -> void:
	lm["found"] = true
	discovered += 1
	var ex = int(grid.entrance.x)
	var d = abs(lm["x"] - ex)
	var side = "west" if lm["x"] < ex else "east"
	var pos = grid.center(lm["x"], grid.surf_y(lm["x"]) - 8)
	fx.append({"kind": "ring", "pos": pos, "t": 0.0, "color": Color("#ffd86b")})
	fx.append({"kind": "text", "pos": pos + Vector2(0, -34), "t": 0.0, "text": "DISCOVERED", "color": Color("#ffd86b")})
	match lm["kind"]:
		"tree":
			var gain = 15.0 + d * 0.04
			food += gain
			ledger["other_in"] += gain
			for i in 3:
				_drop_fruit(lm["x"])
			toasts.append({"text": "A giant fruit tree, %d cells %s! Its fruit is yours (+%d food)." % [d, side, int(gain)], "t": 7.0})
		"cave":
			caves_found += 1
			var amount = 110.0 + d * 0.5
			piles.append({"x": lm["x"], "amount": amount, "max": amount, "kind": "jackpot"})
			var extra = ""
			if mutagen < 3:
				mutagen += 1
				extra = " +1 mutagen."
			var txt = "A cave %d cells %s: a hoard of about %d food!%s" % [d, side, int(amount), extra]
			if time > 200.0 and rng.randf() < 0.5:
				_spawn_enemy("spider", 1 if lm["x"] > ex else -1)
				var e = enemies[enemies.size() - 1]
				e.x = lm["x"] + 3
				e.tx = e.x
				e.y = grid.surf_y(e.x) - 1
				e.ty = e.y
				e.t = 0.0
				e.lane = 0.5
				txt += " Something stirred in the dark and follows your scouts home."
			toasts.append({"text": txt, "t": 9.0})
		_:
			food += 10.0
			ledger["other_in"] += 10.0
			toasts.append({"text": "A cliff vista, %d cells %s: the scouts report the land beyond (+10 food)." % [d, side], "t": 6.0})
	banner = "Discovered: %s" % {"tree": "a giant fruit tree", "cave": "a cave hoard", "vista": "a cliff vista"}.get(lm["kind"], "a landmark")
	banner_t = 3.0
	_sfx("repelled")


func _drop_fruit(x: int) -> void:
	for p in piles:
		if p.get("kind", "") == "fruit" and abs(p["x"] - x) <= 2:
			p["amount"] = min(p["amount"] + 9.0, 36.0)
			return
	piles.append({"x": x, "amount": 9.0, "max": 36.0, "kind": "fruit"})


func _step_prey(dt: float) -> void:
	_prey_timer -= dt
	if _prey_timer > 0.0:
		return
	var pb = float(rule("prey_boost", 1.0))
	_prey_timer = rng.randf_range(35.0, 70.0) / pb
	var n := 0
	for e in enemies:
		if e.cls == "prey":
			n += 1
	if n < 2 + int(pb - 1.0 + 0.5):
		_spawn_enemy("looter", -1 if rng.randf() < 0.5 else 1)
