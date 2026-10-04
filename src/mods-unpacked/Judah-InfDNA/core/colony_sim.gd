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
const Arc = preload("res://mods-unpacked/Judah-InfDNA/core/arc.gd")
const UG = preload("res://mods-unpacked/Judah-InfDNA/core/underground.gd")
const Phenotype = preload("res://mods-unpacked/Judah-InfDNA/core/phenotype.gd")
const WorldGrid = preload("res://mods-unpacked/Judah-InfDNA/core/world_grid.gd")
const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")
const ShopItems = preload("res://mods-unpacked/Judah-InfDNA/core/shop_items.gd")
const Fate = preload("res://mods-unpacked/Judah-InfDNA/core/fate.gd")
const City = preload("res://mods-unpacked/Judah-InfDNA/core/city.gd")
const NestPlanner = preload("res://mods-unpacked/Judah-InfDNA/core/nest_planner.gd")
const Queens = preload("res://mods-unpacked/Judah-InfDNA/core/queens.gd")
const WF = preload("res://mods-unpacked/Judah-InfDNA/core/world_features.gd")
const Seasons = preload("res://mods-unpacked/Judah-InfDNA/core/seasons.gd")
const Legacy = preload("res://mods-unpacked/Judah-InfDNA/core/legacy.gd")
const Orders = preload("res://mods-unpacked/Judah-InfDNA/core/orders.gd")
const Loco = preload("res://mods-unpacked/Judah-InfDNA/core/locomotion.gd")
const Rival = preload("res://mods-unpacked/Judah-InfDNA/core/rival.gd")

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
	var hop := 0.0           # length (in cells) of the hop in progress when it covers several cells at once (locomotion.gd); 0 = one cell
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
	var squad := 0           # the player's order this ant is under (orders.gd): 0 = free
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
	var shelter_t := 0.0     # in cover (after a Recall): a bird cannot pick it out
	var flee := 0            # hops left of running from a raider (so a threat edge does not make it dither)
	var far := 0             # farthest distance from the nest this trip
	var rich := 0.5          # fullness of the pile it loaded from (trail strength)
	var jack := false        # carrying jackpot food


class Raider:
	var hop := 0.0
	var void_born := false      # a Void Maw that climbed out of the collapse pit (arc.gd)
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
	var tongue_cd := 2.0   # anteater: seconds to its next lick
	var guard_x := 0       # a rival's guard: the column of the mound it defends (0 = an ordinary raider)
	var genome = null      # a rival's kin ant: the body plan it is drawn from (and whose numbers it fights with)
	var abil_t := {}       # kin soldiers: seconds to each of their line's organ abilities


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
var deaths := {"old": 0, "starve": 0, "combat": 0, "bird": 0, "anteater": 0, "other": 0}   # by cause (harness/HUD)
var dist_threat := PoolIntArray()
var fx: Array = []               # view effects: {"kind", "pos", "text", "color", "t"}
var _threat_timer := 0.0
var _alarm_timer := 0.0
var _alert_n := 0                 # hostiles the colony answers right now (see _alerts)
const ALERT_RANGE = 240           # cells from the entrance: the threat field reaches 260, and a hostile further out is no reason to leave the food runs
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
var ledger := {"forage": 0.0, "kills": 0.0, "farm": 0.0, "other_in": 0.0, "upkeep": 0.0, "eggs": 0.0, "lab": 0.0, "rot": 0.0, "other_out": 0.0, "orders": 0.0}
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

# ---- The director's commands. The colony alone is only competent; the player is its voice. Will fills over time and is spent on
# commands, each with a cooldown. See cast().
const CASTE_ORDER = [[1.0, 1.0, 1.0], [1.8, 1.3, 0.45], [0.6, 0.6, 2.6]]   # mixed, workers, soldiers
const WILL_MAX = 100.0
const WILL_REGEN = 1.5             # per second: a full bar in about a minute
const COMMANDS = {
	"rally": {"name": "Rally", "cost": 30.0, "cd": 10.0, "key": "R", "target": true,
		"tip": "Plant a flag: defenders and soldiers hold it for 25 s and bite 35% harder near it"},
	"harvest": {"name": "Harvest", "cost": 20.0, "cd": 12.0, "key": "E", "target": true,
		"tip": "Send foragers to the pile at the cursor for 60 s: they carry 30% more"},
	"recall": {"name": "Recall", "cost": 15.0, "cd": 20.0, "key": "Z", "target": false,
		"tip": "Everyone on the surface without a load runs home and stays in for 12 s"},
	"surge": {"name": "Surge", "cost": 25.0, "cd": 30.0, "key": "J", "target": false,
		"tip": "Surface ants run 45% faster for 10 s"},
	"breed": {"name": "Breed", "cost": 40.0, "cd": 45.0, "key": "M", "target": false,
		"tip": "The next 8 eggs are bred from the selected ant (or mutate hard if none) - steer evolution"},
	"strike": {"name": "Strike", "cost": 35.0, "cd": 75.0, "key": "Y", "target": false,
		"tip": "Send a strike party (soldiers first, half the colony) to the rival nest: beat its guards, then storm the mound for its food and five quiet minutes. Needs the nest found"},
}
# Doing things costs a little food as well: the colony feeds the ants it sends out and the brood it is told to hurry. Small next to a
# larder, but it adds up if you spam. Orders (orders.gd) cost by how many ants and what kind; a refusal never takes the larder under the reserve.
const FOOD_COST = {"rally": 6.0, "harvest": 4.0, "recall": 3.0, "surge": 5.0, "breed": 10.0, "strike": 12.0}
const BEACON_FOOD = 2.0
const FOOD_RESERVE = 5.0
var will := 50.0
var hop_k := 1                    # cells an ant covers in one hop when nothing needs it nearby (1 = every cell; the scene raises it with the game speed: locomotion.gd)
var rot_every := 1                # ants turn their bodies to the ground's slope every this many ticks (a few at high speed, where nobody sees)
var cmd_cd := {}                  # command id -> seconds left
var rally_x := 0
var rally_t := 0.0
var strike_t := 0.0               # a strike party is out (the rally flag is planted at the rival's mound)
var rival                         # rival.gd: the neighbouring colony
var _raid_rival := false          # the raid now in progress is the rival's
var harvest_x := 0
var harvest_t := 0.0
var surge_t := 0.0
var recall_t := 0.0
var caste_order := 0              # 0 mixed, 1 workers, 2 soldiers: what the queen's brood leans toward
const RALLY_LEN = 25.0
const HARVEST_LEN = 60.0
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
	{"id": "winter1", "name": "Live through a winter", "food": 70, "mut": 1},
	{"id": "winter3", "name": "Hardened: live through three winters", "food": 140, "mut": 1},
	{"id": "ms40", "name": "Strange: breed an ant of mutation 40", "food": 45, "mut": 1},
	{"id": "ms90", "name": "Aberration: breed an ant of mutation 90", "food": 90, "mut": 1},
	{"id": "ms150", "name": "Monstrosity: breed an ant of mutation 150", "food": 160, "mut": 1},
]
# ---- The point of the game: breed monstrosities. Every body has a mutation score (genome.gd); the colony's Apex ants are the
# most mutated ones alive, and the Monstrosity meter (0..100) is how far its strangest ants have come from a plain ant.
var apex: Array = []              # the five most mutated ants alive, most first
var apex_ids := {}                # id -> rank (0 = the most mutated), for the views
var monstrosity := 0.0            # 0..100: mean score of the top eight, against Genome.MS_MONSTER (smoothed)
var peak_ms := 0.0                # the highest mutation score any ant of this run has had
var arc_stage := 0                # arc.gd: 0 growing, 1 dominion, 2 tremors, 3 the void
var arc_t := 0.0
var arc_hold := 0.0
var arc_calm := 0.0
var arc_tremors := 0
var arc_cool := 0.0
var void_left := 0                # Void Maws still to climb out of the pit
var void_next_t := 0.0
var void_x := 0
var void_cycles := 0              # voids sealed this run
var _apex_t := 0.0
const MONSTROSITY_STAGES = [[0.0, "Ordinary"], [20.0, "Unusual"], [45.0, "Aberrant"], [70.0, "Monstrous"], [95.0, "Dominion"]]
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


# Legacy (legacy.gd): the heirloom a past colony handed down, born into every founder ant; the champion is the body plan
# that most outnumbered the rest, whose traits the run summary offers to pass on.
var heirloom := {}
var champion = null
var _champ_n := 0
# The Wild (wild.gd): the line of an earlier colony that this colony's rival descends from ({} = the plain red ants), and whether
# this colony's own fall has been written into the Wild yet (the collapse screen does that once).
var kin := {}
var wild_saved := false
# Squad orders (orders.gd): id -> {"kind", "x", "y", "z", "ref", "job", "field", "under"}
var squads := {}
var squad_seq := 1
# What the player is looking at, for the squads' stand-down (orders.gd): the view in cells and the ids of the selected ants. The scene keeps
# them current; a sim running without a view counts everything as watched.
var attn_rect := Rect2(-10000000.0, -10000000.0, 20000000.0, 20000000.0)
var attn_sel := {}
var _squad_t := 1.0
var _squad_warned := false


func _init(seed_value: int = 0, queen_id: String = "well_rounded", heirloom_in: Dictionary = {}, kin_in: Dictionary = {}) -> void:
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
	kin = kin_in
	rival = Rival.new()
	rival.setup(self)
	heirloom = heirloom_in
	if not heirloom.empty():
		if heirloom.get("kind", "") == "mods":
			mods["hp"] = mods.get("hp", 0.0) + float(heirloom["value"])
			mods["attack"] = mods.get("attack", 0.0) + float(heirloom["value"])
		else:
			Legacy.apply(heirloom, founder)
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
	toasts.append({"text": "Drag a box over ants to select them, then right-click for orders: guard, harvest, attack, dig.", "t": 16.0})
	toasts.append({"text": "Right-click the ground for powers: rally, recall, surge, breed. Tab shows more panels.", "t": 16.0})
	if not heirloom.empty():
		toasts.append({"text": "Heirloom from %s: %s." % [heirloom.get("from", "a past colony"), str(heirloom.get("label", "")).to_lower()], "t": 12.0})


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


# Finer profiling inside the ant step (only when `prof` is set): _qb() starts a timer, _qe(key, t0) adds the time to prof[key].
func _qb() -> int:
	return OS.get_ticks_usec() if prof != null else 0


func _qe(k: String, t0: int) -> void:
	if prof != null:
		prof[k] = prof.get(k, 0) + OS.get_ticks_usec() - t0


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


# ---- Seasons (seasons.gd): the year shapes how much food appears, what the colony eats, how fast the queen lays and how fast ants
# walk over open ground. Autumn is the glut, winter the lean time; living through a winter earns a reward.
var season := 0
var winters := 0                   # winters lived through
var winter_low := 1e9              # the lowest the larder got this winter
var _s_food := 1.0
var _s_rich := 1.0
var _s_fruit := 1.0
var _s_upkeep := 1.0
var _s_lay := 1.0
var _s_walk := 1.0
var _s_raid := 1.0
var _s_age := 1.0
var _s_warned := false


func _step_seasons(_dt: float) -> void:
	_s_food = Seasons.food_k(time)
	_s_rich = Seasons.rich_k(time)
	_s_fruit = Seasons.fruit_k(time)
	_s_upkeep = Seasons.upkeep_k(time)
	_s_lay = Seasons.lay_k(time)
	_s_walk = Seasons.walk_k(time)
	_s_raid = Seasons.raid_k(time)
	_s_age = Seasons.age_k(time)
	var idx = Seasons.index(time)
	if idx != season:
		var was = season
		season = idx
		_s_warned = false
		toasts.append({"text": Seasons.NOTES[idx], "t": 9.0})
		banner = "%s begins" % Seasons.NAMES[idx]
		banner_t = 3.5
		if idx == 3:
			winter_low = food
		if idx == 0 and was == 3:
			winters += 1
			toasts.append({"text": "You lived through winter %d (it dipped to %d food)." % [winters, int(winter_low)], "t": 9.0})
	if season == 3:
		winter_low = min(winter_low, food)
	elif season == 2 and not _s_warned and Seasons.to_next(time) <= 60.0:
		_s_warned = true
		toasts.append({"text": "Winter is one minute away. The larder is %d%% full." % int(100.0 * food / max(1.0, food_cap)), "t": 8.0})


# Weather: now and then it rains. Rain washes the scent trails away (they lose strength ~4x faster while it pours), so
# foragers fall back on route memory and the colony has to re-lay its roads. The views add streaks, splashes and grey light.
var rain := 0.0
var overcast := 0.0                # cloud cover: it builds before the rain, and lingers after it (0..1)
var wet := 0.0                     # the ground stays wet (puddles) for a while after rain
# Weather moves through phases, never in a jump: clear -> the clouds gather (30-45 s) -> rain that builds to its peak over about half a minute
# -> it eases off -> the sky clears slowly. `rain` and `overcast` follow their goals along a smooth curve, so a drizzle comes before the shower
# and the shower thins out before it stops.
var _wx := 0                       # 0 clear, 1 gathering, 2 raining, 3 clearing
var _rain_goal := 0.0              # the rain the current phase is heading for
var _rain_timer := 170.0           # seconds left in the current phase
var _rain_peak := 0.8


func _step_weather(dt: float) -> void:
	_rain_timer -= dt
	var over_goal := 0.0
	_rain_goal = 0.0
	match _wx:
		0:
			if _rain_timer <= 0.0:
				_wx = 1
				_rain_timer = rng.randf_range(30.0, 45.0)
				_rain_peak = rng.randf_range(0.55, 1.0)
		1:
			over_goal = 0.8
			if _rain_timer <= 0.0:
				_wx = 2
				_rain_timer = rng.randf_range(45.0, 85.0)
				toasts.append({"text": "Rain! The scent trails are washing away.", "t": 5.0})
		2:
			over_goal = 1.0
			_rain_goal = _rain_peak
			if _rain_timer <= 0.0:
				_wx = 3
				_rain_timer = rng.randf_range(40.0, 60.0)
				toasts.append({"text": "The rain eases. The scent trails will need re-laying.", "t": 5.0})
		3:
			over_goal = 0.35
			if _rain_timer <= 0.0 and rain < 0.02:
				_wx = 0
				_rain_timer = rng.randf_range(150.0, 300.0)
	rain += (_rain_goal - rain) * (1.0 - exp(-dt / 16.0))
	if _rain_goal <= 0.0 and rain < 0.004:
		rain = 0.0
	overcast += (over_goal - overcast) * (1.0 - exp(-dt / 14.0))
	wet = clamp(wet + (dt / 22.0 if rain > 0.3 else -dt / 100.0), 0.0, 1.0)


func _step_extras(dt: float) -> void:
	Orders.step(self, dt)
	rival.step(self, dt)
	_step_seasons(dt)
	_step_weather(dt)
	_step_director(dt)
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
		jackpot_t = rng.randf_range(140.0, 220.0) / clamp(_s_food * 1.5, 0.25, 1.5)
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
		"winter1":
			return winters >= 1
		"winter3":
			return winters >= 3
		"ms40":
			return peak_ms >= 40.0
		"ms90":
			return peak_ms >= 90.0
		"ms150":
			return peak_ms >= 150.0
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
	if food < BEACON_FOOD + FOOD_RESERVE:
		toasts.append({"text": "Not enough food for a scent flag (%d needed)." % int(ceil(BEACON_FOOD + FOOD_RESERVE)), "t": 2.5})
		return false
	food -= BEACON_FOOD
	ledger["orders"] += BEACON_FOOD
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


# What the director's items do to the Will meter and the commands (the base numbers live in COMMANDS).
func will_max() -> float:
	return WILL_MAX + mod("will_max")


func food_cost(id: String) -> float:
	return float(FOOD_COST.get(id, 0.0))


func cmd_cost(id: String) -> float:
	return float(COMMANDS[id]["cost"]) * max(0.4, 1.0 + mod("cmd_cost"))


func cmd_recharge(id: String) -> float:
	return float(COMMANDS[id]["cd"]) * max(0.3, 1.0 + mod("cmd_cd"))


# The director's voice. `x` is the world column the cursor is over (rally, harvest), `sel` the selected ant (breed).
# Returns true if the command went out.
func cast(id: String, x: int = 0, sel = null) -> bool:
	if collapsed or not COMMANDS.has(id):
		return false
	var c = COMMANDS[id]
	if cmd_cd.get(id, 0.0) > 0.0:
		toasts.append({"text": "%s is recharging (%d s)." % [c["name"], int(ceil(cmd_cd[id]))], "t": 2.0})
		return false
	var cost = cmd_cost(id)
	if will < cost:
		toasts.append({"text": "Not enough Will for %s (%d needed)." % [c["name"], int(ceil(cost))], "t": 2.0})
		return false
	var fcost = food_cost(id)
	if food < fcost + FOOD_RESERVE:
		toasts.append({"text": "Not enough food for %s (%d needed)." % [c["name"], int(ceil(fcost + FOOD_RESERVE))], "t": 2.5})
		return false
	var ex = int(grid.entrance.x)
	x = int(clamp(x, ex - RANGE_MAX + 20, ex + RANGE_MAX - 20))
	match id:
		"rally":
			if _inside_n > 0:
				toasts.append({"text": "Raiders are inside the nest: the colony will not leave it to rally.", "t": 3.0})
				return false
			rally_x = x
			rally_t = RALLY_LEN * (1.0 + mod("rally_power"))
			_call_up(0.45)
			fx.append({"kind": "ring", "pos": grid.center(x, grid.surf_y(x) - 3), "t": 0.0, "color": Color("#ff6a4a")})
			fx.append({"kind": "text", "pos": grid.center(x, grid.surf_y(x) - 8), "t": 0.0, "text": "RALLY!", "color": Color("#ff6a4a")})
		"harvest":
			var best = null
			var bd = 90
			for p in piles:
				var d = abs(p["x"] - x)
				if p["amount"] > 8.0 and d < bd:
					bd = d
					best = p
			if best == null:
				toasts.append({"text": "No pile near the cursor: put it over a food pile (they show on the minimap).", "t": 3.0})
				return false
			harvest_x = best["x"]
			harvest_t = HARVEST_LEN * (1.0 + mod("harvest_power"))
			best["found"] = true
			var sent := 0
			for a in ants:
				if a.task == Task.FORAGE and a.carry <= 0.0 and not grid.is_under(a.x, a.y) and sent < 60:
					a.site = harvest_x
					a.search_r = int(min(RANGE_MAX, max(a.search_r, abs(harvest_x - ex) + 60)))
					a.heading = 1 if harvest_x > a.x else -1
					sent += 1
			fx.append({"kind": "ring", "pos": grid.center(harvest_x, grid.surf_y(harvest_x) - 3), "t": 0.0, "color": Color("#ffd86b")})
			fx.append({"kind": "text", "pos": grid.center(harvest_x, grid.surf_y(harvest_x) - 8), "t": 0.0, "text": "HARVEST", "color": Color("#ffd86b")})
		"strike":
			if not rival.found:
				toasts.append({"text": "No rival nest found yet: your foragers will come across it as they range farther.", "t": 3.5})
				return false
			if not rival.alive():
				toasts.append({"text": "The %s are broken for now (%d s)." % [rival.name, int(rival.broken_t)], "t": 3.0})
				return false
			if _inside_n > 0 or queen_hp < queen_max * 0.5:
				toasts.append({"text": "Raiders are inside or the queen is hurt: the colony will not march out to strike.", "t": 3.0})
				return false
			rally_x = rival.x
			rally_t = Rival.STRIKE_LEN
			strike_t = Rival.STRIKE_LEN
			_call_up(0.5)
			fx.append({"kind": "ring", "pos": grid.center(rival.x, grid.surf_y(rival.x) - 3), "t": 0.0, "color": Color("#ff3a3a")})
			fx.append({"kind": "text", "pos": grid.center(rival.x, grid.surf_y(rival.x) - 8), "t": 0.0, "text": "STRIKE!", "color": Color("#ff3a3a")})
			banner = "Strike party marching on the %s" % rival.name
			banner_t = 4.0
		"recall":
			recall_t = 12.0
			for a in ants:
				if grid.is_under(a.x, a.y):
					continue
				a.shelter_t = 14.0          # everyone outside scatters into cover while they run for home
				if a.carry <= 0.0 and a.task != Task.DEFEND:
					a.task = Task.HOME
					a.spoil = 0.0
					a.hauling = false
			banner = "Recall: the colony runs for home"
			banner_t = 3.0
		"surge":
			surge_t = 10.0 * (1.0 + mod("surge_power"))
			fx.append({"kind": "ring", "pos": grid.center(ex, grid.surf_y(ex) - 3), "t": 0.0, "color": Color("#7fe0c4")})
			toasts.append({"text": "Surge: surface ants sprint for %d s." % int(round(surge_t)), "t": 3.0})
		"breed":
			if sel != null and ants.has(sel):
				var nb = 8 + int(mod("breed_power"))
				blessed = sel.genome
				blessed_left = nb
				fx.append({"kind": "ring", "pos": ant_pos(sel), "t": 0.0, "color": Color("#b58cff")})
				toasts.append({"text": "Breed: the next %d eggs come from the selected ant, each with a fresh mutation." % nb, "t": 5.0})
			else:
				var nb2 = 8 + int(mod("breed_power"))
				fate.ray_eggs += nb2
				toasts.append({"text": "Breed: the next %d eggs mutate hard. (Select an ant first to breed from it.)" % nb2, "t": 5.0})
	will -= cost
	food -= fcost
	ledger["orders"] += fcost
	cmd_cd[id] = cmd_recharge(id)
	return true


# ---- Predators. A bird now and then hunts the foragers far from the nest: it drifts toward the nearest ant on the open
# ground and picks one off every few seconds (two when they bunch up). Ants underground are safe, so Recall is the answer;
# the bird gives up when nothing is left outside, or after half a minute. The view draws it (predator_view.gd).
var bird = null                    # {"x": float, "t": seconds left, "cd": strike cooldown, "dive": 0..1, "alt": 0..1, "face": 1|-1, "kills": int}
var _bird_timer := 170.0
const BIRD_LEN = 32.0
const BIRD_SPEED = 38.0            # cells per second
const BIRD_STRIKE_CD = 3.6
const BIRD_HP = 90.0
const BIRD_REACH = 90              # winged ants this close (cells) fly out to meet it
const BIRD_BITE = 14.0             # and bite it from this close
const CARCASS_FOOD = 45.0          # what a dead bird is worth to the colony
const CARCASS_LIFE = 110.0         # seconds until the rest of it has dissolved
var bird_fall = null               # a bird just shot down: {"x", "alt", "face", "t", "spin"}; the view draws it dropping, then it lands as a carcass pile


func _step_bird(dt: float) -> void:
	_step_bird_fall(dt)
	if bird == null:
		_bird_timer -= dt
		if _bird_timer <= 0.0 and time > 150.0:
			var ex = int(grid.entrance.x)
			var far := []
			for a in ants:
				if not grid.is_under(a.x, a.y) and abs(a.x - ex) > 90:
					far.append(a)
			if far.size() >= 6:
				var t = far[rng.randi_range(0, far.size() - 1)]
				bird = {"x": float(t.x) + rng.randf_range(-60.0, 60.0), "t": BIRD_LEN * clamp(ants.size() / 120.0, 0.5, 1.0) * max(0.3, 1.0 - 0.5 * mod("bird_ward")), "cd": 2.0, "dive": 0.0, "alt": 1.0, "face": 1, "kills": 0, "hp": BIRD_HP + 0.5 * ants.size(), "hit": 0.0}
				bird["hp0"] = bird["hp"]
				bird["x"] = clamp(bird["x"], float(ex - RANGE_MAX + 20), float(ex + RANGE_MAX - 20))
				banner = "A bird is hunting over the %s meadow!  (Recall brings the foragers home)" % ("west" if bird["x"] < ex else "east")
				banner_t = 5.0
				_sfx("boss")
			else:
				_bird_timer = 30.0
		return
	if not bird.has("hp"):
		bird["hp"] = BIRD_HP + 0.5 * ants.size()      # a bird made by older code or a test has no hit points yet
		bird["hp0"] = bird["hp"]
	if not bird.has("hit"):
		bird["hit"] = 0.0
	bird["t"] -= dt
	bird["cd"] = max(0.0, bird["cd"] - dt)
	bird["dive"] = max(0.0, bird["dive"] - dt * 1.4)
	var target = null
	var bd = 1e9
	var bite := 0.0
	bird["hit"] = max(0.0, bird["hit"] - dt)
	for a in ants:
		if not grid.is_under(a.x, a.y) and a.shelter_t <= 0.0:
			var d = abs(a.x - bird["x"])
			if d < bd:
				bd = d
				target = a
			if d <= BIRD_BITE and a.ph["wings"] > 0:
				bite += a.ph["attack"] * 0.9
	if bite > 0.0:
		# winged ants fly up and tear at it
		bird["hp"] -= bite * dt
		bird["hit"] = 0.3
		if bird["hp"] <= 0.0:
			_bird_down()
			return
	if target == null or bd > 500.0 or bird["t"] <= 0.0:
		toasts.append({"text": "The bird flies off.", "t": 3.0})
		bird = null
		_bird_timer = rng.randf_range(150.0, 260.0) * (1.0 + 0.8 * mod("bird_ward"))
		return
	var dir = 1.0 if target.x > bird["x"] else -1.0
	var alt_goal = 1.0 if bird["dive"] > 0.2 else clamp(bd / 55.0, 0.08, 1.0)      # stoops as it closes in, climbs away after a strike
	bird["alt"] = lerp(bird["alt"], alt_goal, 1.0 - exp(-4.0 * dt))
	if bd > 4.0:
		bird["x"] += dir * min(bd, BIRD_SPEED * dt)
		bird["face"] = int(dir)
	if bd <= 10.0 and bird["cd"] <= 0.0:
		bird["cd"] = BIRD_STRIKE_CD
		bird["dive"] = 1.0
		var near := []
		for a in ants:
			if not grid.is_under(a.x, a.y) and a.shelter_t <= 0.0 and abs(a.x - bird["x"]) <= 12.0:
				near.append(a)
		var victims := near.slice(0, 1 if near.size() < 9 else 2)         # one ant, or two when they bunch up
		for a in victims:
			fx.append({"kind": "puff", "pos": ant_pos(a), "t": 0.0, "color": Color("#c9a37a")})
			kill(a, "bird")
			bird["kills"] += 1
		if not victims.empty():
			shake = max(shake, 0.25)


func ms_of(a) -> float:
	return a.genome.mutation_score()


func is_apex(a) -> bool:
	return apex_ids.has(a.id)


func monstrosity_stage() -> String:
	var name = MONSTROSITY_STAGES[0][1]
	for st in MONSTROSITY_STAGES:
		if monstrosity >= st[0]:
			name = st[1]
	return name


# Every second or so: who are the most mutated ants alive, and how monstrous is the colony.
func _step_apex(dt: float) -> void:
	_apex_t -= dt
	if _apex_t > 0.0:
		return
	_apex_t = 1.2
	var top := []          # [score, ant], at most 8, best first
	for a in ants:
		var v = a.genome.mutation_score()
		if top.size() < 8 or v > top[top.size() - 1][0]:
			var i = top.size()
			while i > 0 and top[i - 1][0] < v:
				i -= 1
			top.insert(i, [v, a])
			if top.size() > 8:
				top.pop_back()
	apex.clear()
	apex_ids.clear()
	var sum := 0.0
	for i in top.size():
		sum += top[i][0]
		if i < 5:
			apex.append(top[i][1])
			apex_ids[top[i][1].id] = i
	if not top.empty():
		var best = top[0][0]
		if best > peak_ms:
			if int(best / 10.0) > int(peak_ms / 10.0) and best >= 20.0:
				toasts.append({"text": "A new most-mutated ant: mutation %d. Breed from it (right-click it, Breed)." % int(best), "t": 6.0})
			peak_ms = best
	var target = clamp(sum / max(1, top.size()) / (Genome.MS_MONSTER * (1.0 + 0.5 * void_cycles)) * 100.0, 0.0, 100.0) if top.size() >= 3 else 0.0
	monstrosity = lerp(monstrosity, target, 0.3)


# The bird is dead: it drops out of the sky (bird_fall, drawn by the view), lands as a carcass pile the foragers carry off, and what is left dissolves.
func _bird_down() -> void:
	bird_fall = {"x": float(bird["x"]), "alt": float(bird["alt"]), "face": int(bird["face"]), "t": 0.0, "spin": rng.randf_range(-1.0, 1.0)}
	toasts.append({"text": "The bird is down! The colony will eat well.", "t": 5.0})
	banner = "A winged ant brought the bird down!"
	banner_t = 4.0
	_sfx("repelled")
	shake = max(shake, 0.35)
	bird = null
	_bird_timer = rng.randf_range(200.0, 320.0) * (1.0 + 0.8 * mod("bird_ward"))


func _step_bird_fall(dt: float) -> void:
	for p in piles:
		if p.get("kind", "") == "carcass":
			p["amount"] -= dt * p["max"] / CARCASS_LIFE      # it dissolves whether or not it is eaten
			p["rot"] = clamp(p["amount"] / max(1.0, p["max"]), 0.0, 1.0)
	if bird_fall == null:
		return
	bird_fall["t"] += dt
	if bird_fall["t"] < 1.3:
		return
	var x = int(clamp(bird_fall["x"], grid.sim_l() + 3, grid.sim_r() - 3))     # where it fell (the bird hunts far beyond the arena)
	for p in piles:
		if p.get("kind", "") == "carcass" and abs(p["x"] - x) <= 2:
			p["amount"] += CARCASS_FOOD
			p["max"] = max(p["max"], p["amount"])
			bird_fall = null
			return
	piles.append({"x": x, "amount": CARCASS_FOOD, "max": CARCASS_FOOD, "kind": "carcass", "rot": 1.0, "face": bird_fall["face"], "spin": bird_fall["spin"]})
	fx.append({"kind": "puff", "pos": grid.center(x, grid.surf_y(x) - 1), "t": 0.0, "color": Color("#c9a37a")})
	bird_fall = null


# ---- Predator two: the anteater. Every ten minutes or so one lumbers in from the edge of the meadow (enemy kind "anteater": slow,
# shaggy, a huge pile of hit points that grows with the colony). It sieges the entrance like the other bosses, and every couple of
# seconds its long tongue licks up to three ants off the ground near it. Rally the soldiers to the entrance; Recall keeps the rest
# below. Killing one earns food and a mutagen.
var _anteater_timer := 600.0
var anteaters_slain := 0
const ANTEATER_CD = 3.2


func _step_anteater_spawn(dt: float) -> void:
	_anteater_timer -= dt
	if _anteater_timer > 0.0:
		return
	for e in enemies:
		if e.kind == "anteater":
			_anteater_timer = 60.0
			return
	if ants.size() < 70 or _inside_n > 0 or collapsed:
		_anteater_timer = 30.0
		return
	_anteater_timer = rng.randf_range(520.0, 760.0)
	var side = -1 if rng.randf() < 0.5 else 1
	_spawn_enemy("anteater", side)
	banner = "An anteater lumbers in from the %s!  Hold the entrance: Rally the soldiers (R)." % ("west" if side < 0 else "east")
	banner_t = 6.0
	_sfx("boss")


func _anteater_tongue(e, dt: float) -> void:
	e.tongue_cd -= dt
	if e.tongue_cd > 0.0 or e.state == 2 or e.stun_t > 0.0:
		return
	var near := []
	for a in ants:
		if a.z == e.z and abs(a.x - e.x) <= 16 and abs(a.y - e.y) <= 6:
			near.append(a)
	if near.empty():
		e.tongue_cd = 0.4
		return
	e.tongue_cd = ANTEATER_CD * rng.randf_range(0.85, 1.15)
	var n = 1 + (1 if near.size() >= 10 else 0) + (1 if near.size() >= 24 else 0)
	var mouth = enemy_pos(e) + Vector2(e.facing * 150.0, -55.0)
	for i in n:
		if near.empty():
			break
		var a = near[rng.randi_range(0, near.size() - 1)]
		near.erase(a)
		fx.append({"kind": "beam", "pos": mouth, "to": ant_pos(a), "t": 0.0, "color": Color("#e8728f")})
		fx.append({"kind": "puff", "pos": ant_pos(a), "t": 0.0, "color": Color("#c9a37a")})
		kill(a, "anteater")
	shake = max(shake, 0.2)


# Call up to `frac` of the colony to the flag: soldiers first, then idle hands; never an ant carrying food.
func _call_up(frac: float) -> void:
	var want = int(ants.size() * frac)
	var order := []
	for a in ants:
		if a.carry <= 0.0 and a.squad == 0:          # an ant under the player's own order is not called away by a flag
			order.append(a)
	order.sort_custom(self, "_rally_order")
	var n := 0
	for a in order:
		if n >= want:
			break
		if a.task != Task.DEFEND:
			if a.task == Task.FORAGE:
				_n_foragers = max(0, _n_foragers - 1)
			a.task = Task.DEFEND
			a.timer = 0.0
			a.spoil = 0.0
			a.hauling = false
		n += 1


func _rally_order(a, b) -> bool:
	var ka = 0 if a.caste == 2 else (1 if a.task != Task.FORAGE else 2)
	var kb = 0 if b.caste == 2 else (1 if b.task != Task.FORAGE else 2)
	return ka < kb


func _step_director(dt: float) -> void:
	_step_bird(dt)
	_step_apex(dt)
	Arc.step(self, dt)
	if grid.ug != null:
		grid.ug.step(self, dt)
	_step_anteater_spawn(dt)
	strike_t = max(0.0, strike_t - dt)
	will = min(will_max(), will + WILL_REGEN * (1.0 + mod("will_regen")) * dt)
	for k in cmd_cd.keys():
		cmd_cd[k] = max(0.0, cmd_cd[k] - dt)
	rally_t = max(0.0, rally_t - dt)
	harvest_t = max(0.0, harvest_t - dt)
	surge_t = max(0.0, surge_t - dt)
	recall_t = max(0.0, recall_t - dt)


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
	var hostiles := 0
	for e0 in enemies:
		if _alerts(e0):
			hostiles += 1
			if e0.state != 2:
				threat += DEFEND_WEIGHT.get(e0.cls, 1.0)
	_alert_n = hostiles
	_defender_cap = 6 + int(5.0 * threat)
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
	if ants.size() >= 60 and food > food_target and _alert_n == 0:
		_stim_dig = max(_stim_dig, 0.14 + 0.04 * planner.wanted_rooms.size())


func _p(s: float, t: float) -> float:
	return s * s / (s * s + t * t + 0.0001)


func _choose_task(a) -> void:
	if a.squad != 0 and Orders.choose(self, a):
		return
	a.timer = 0.0
	if recall_t > 0.0 and a.caste != 2 and _stim_defend <= 0.0:
		a.task = Task.NURSE      # recalled: stay in the nest until the order lapses
		a.spoil = 0.0
		a.hauling = false
		return
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
	if apex_ids.has(a.id):
		apex_ids.erase(a.id)
		apex.erase(a)
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


# A walkable cell that no tunnel leads out of (a gap in the rim of a big chamber cuts a pocket off) holds an ant for ever: it cannot reach the
# way out, so it never forages, digs or fights. Such an ant is carried to the nearest cell that is connected. (Found by the invariants test: three
# of thirteen ants near the queen's chamber were in a pocket.)
var rescued := 0


func _rescue(u) -> void:
	if grid.nav_dirty or grid.dist_exit.size() != grid.PLANES * grid.WH:
		return
	if not grid.can_walk(u.x, u.y, u.z) or grid.field(grid.dist_exit, u.x, u.y, u.z) >= 0:
		return
	var best = null
	var bd = 1e9
	for pz in [u.z, 1 - u.z]:
		for r in range(1, 17):
			for yy in range(u.y - r, u.y + r + 1):
				for xx in range(u.x - r, u.x + r + 1):
					if max(abs(xx - u.x), abs(yy - u.y)) != r or not grid.can_walk(xx, yy, pz) or grid.field(grid.dist_exit, xx, yy, pz) < 0:
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
		rescued += 1


# ---- gait: how an ant walks (the rules of where it may step are locomotion.gd's). It pauses now and then, sets off slowly and gets up to speed
# (the ramp is kept in the gait word, see Loco.DIR_MASK), slows for a sharp turn or behind another ant, carries a load a little slower than it walks
# out light, turns its body smoothly, and takes its time squeezing through to the other tunnel plane. None of it costs the colony anything: a working
# ant (anything but a nurse) keeps count of the ground it lost and walks CATCH_K faster until it has made it up, so a forager's round trip takes as
# long as it did before the gait existed.
const ROT_RATE = 7.0           # rad/s: the fastest a body turns (a quarter turn takes about a quarter of a second)
const RAMP_T = 0.3             # s from standing to full speed
const RAMP_MIN = 0.3           # share of full speed it sets off at
const RAMP_CAP = [255, 235, 175, 110, 70]   # speed kept through a turn of 0..4 eighths (straight on .. straight back), out of 255
const LADEN_K = 0.93           # on open ground a forager with a load walks this much slower ...
const OUT_K = 1.08             # ... and one going out light this much faster, so a round trip takes as long as before
const SPOIL_K = 0.95           # a digger with a dirt pellet
const CATCH_K = 0.2            # how much faster a working ant walks while it makes up lost ground
const HOLD_T = 0.1             # an ant that decided to stay where it is (holding a line, biting prey) thinks again after this long, not every tick
const CLIMB_K = 0.45           # up or down the open chimney through the mound an ant climbs at this share of its running speed (it used to shoot up it)
var _pause_req := 0.0          # a pause the deciding ant's task asked for (_on_arrive applies it once the task has chosen where to go)
var occ := PoolIntArray()      # tunnel cells (both planes) an ant is about to enter or stands in: (taken until, in tenths of a sim second) << 12 | id & 4095


func _step_ant(a, dt: float) -> void:
	a.age += dt * _s_age
	a.hurt = max(0.0, a.hurt - dt)
	a.shelter_t = max(0.0, a.shelter_t - dt)
	a.timer += dt
	if a.age > a.life:
		kill(a, "old")
		return
	# footing check staggered over 5 ticks (the rescue itself waits 0.5 s anyway)
	var q0 = _qb()
	if (_tick_n + a.id) % 5 == 0:
		_footing_fix(a, dt * 5.0)
	if (_tick_n + a.id) % 40 == 0:
		_rescue(a)
	_qe("a_misc", q0)

	# the body turns smoothly toward the tilt _orient chooses for the step it is on (worked out once per step, and at high game speed only every
	# rot_every ticks), never faster than ROT_RATE (it used to swing a quarter turn in two ticks)
	if rot_every <= 1 or (_tick_n + a.id) % rot_every == 0:
		var rk = a.tx * 7919 + a.ty * 31 + a.tz
		if rk != a.rot_key:
			a.rot_key = rk
			if a.tx != a.x or a.ty != a.y:
				_orient(a)
		if a.rot != a.trot:
			var dr = wrapf(a.trot - a.rot, -PI, PI)
			if abs(dr) < 0.01:
				a.rot = a.trot          # settled (and then this costs nothing until the next turn)
			else:
				var kr = dt * rot_every
				var lim = ROT_RATE * kr
				a.rot = wrapf(a.rot + clamp(dr * min(1.0, kr * 9.0), -lim, lim), -PI, PI)

	if a.dig_timer > 0.0:
		a.dig_timer -= dt
		if a.dig_timer <= 0.0:
			_finish_dig(a)
		return

	# a pause: the ant stands where it is for a moment (looking about, antennae out) and decides nothing until it is over. Being bitten, being
	# given an order or (but for the last HOLD_T) being called to defend ends it at once.
	if a.t < 0.0:
		if a.hurt > 0.0 or a.squad != 0 or (a.task == Task.DEFEND and a.t < -HOLD_T - 0.01) or a.tx != a.x or a.ty != a.y or a.tz != a.z:
			a.t = 0.0
		else:
			a.t += dt
			if a.t < 0.0:
				return
			a.t = 0.0

	var dist = a.hop if a.hop > 0.0 else (1.4142 if (a.tx != a.x and a.ty != a.y) else 1.0)
	var und := false
	if a.tx == a.x and a.ty == a.y and a.tz == a.z:
		dist = 1.0
		a.t = 1.0
	else:
		und = grid.is_under(a.x, a.y)
		var sp = a.ph["speed"] * (a.ph["tunnel_mult"] if und else SURFACE_K * _s_walk)
		if surge_t > 0.0 and not und:
			sp *= 1.45 + 0.3 * mod("surge_power")
		if not und and a.task == Task.FORAGE:
			sp *= 1.0 + TRAIL_BOOST * min(1.0, grid.pher_at(a.x) / 1.2)   # ants run faster on a used trail
			sp *= LADEN_K if a.carry > 0.0 else OUT_K
		elif a.spoil > 0.0:
			sp *= SPOIL_K
		var climb = false
		if not und and a.tx == a.x and a.ty != a.y:
			climb = true
			var lost = sp * (1.0 - CLIMB_K)
			sp -= lost
			if a.task != Task.NURSE:
				var dg = a.scout
				a.scout = (dg & 4095) | (int(min(4095, ((dg >> Loco.DEBT_SHIFT) & 4095) + int(lost * dt * 64.0 + 0.5))) << Loco.DEBT_SHIFT)
		# getting up to speed: the mean of the ramp over this tick, so the step size does not change how far an ant gets. The ground lost (here and
		# on a climb) is owed, but not by nurses, whose walking gets nothing done; it is made up at full speed on the level.
		var gait = a.scout
		if (gait & Loco.RAMP_MASK) != Loco.RAMP_MASK:
			var r0 = ((gait >> Loco.RAMP_SHIFT) & 255) / 255.0
			var r1 = r0 + dt / RAMP_T
			var avg = (r0 + r1) * 0.5
			if r1 >= 1.0:
				var tr = (1.0 - r0) * RAMP_T
				avg = ((r0 + 1.0) * 0.5 * tr + (dt - tr)) / dt
				r1 = 1.0
			var fac = RAMP_MIN + (1.0 - RAMP_MIN) * avg
			var debt = (gait >> Loco.DEBT_SHIFT) & 4095
			if a.task != Task.NURSE:
				debt = int(min(4095, debt + int(sp * dt * (1.0 - fac) * 64.0 + 0.5)))
			sp *= fac
			a.scout = (gait & Loco.DIR_MASK) | (int(r1 * 255.0) << Loco.RAMP_SHIFT) | (debt << Loco.DEBT_SHIFT)
		elif gait >= (1 << Loco.DEBT_SHIFT) and not climb:
			var debt2 = (gait >> Loco.DEBT_SHIFT) & 4095
			var extra = sp * CATCH_K * clamp(debt2 / 128.0, 0.25, 1.0)     # eases off over the last two cells owed
			debt2 = int(max(0, debt2 - max(1, int(extra * dt * 64.0 + 0.5))))
			sp += extra
			a.scout = (gait & 4095) | (debt2 << Loco.DEBT_SHIFT)
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
		a.hop = 0.0
		var q1 = _qb()
		_on_arrive(a)
		if prof != null:
			_qe("a_arrive", q1)
			prof["n_hops"] = prof.get("n_hops", 0) + 1
		if a.t < 0.0:
			break                  # it stopped for a pause
		var moved = a.tx != a.x or a.ty != a.y
		if moved:
			# note the step in the gait word, and slow down for a sharp turn
			var sx = 1 if a.tx > a.x else (-1 if a.tx < a.x else 0)
			var sy = 1 if a.ty > a.y else (-1 if a.ty < a.y else 0)
			var code = Loco.DIR_OF[(sy + 1) * 3 + sx + 1]
			var gait = a.scout
			var last = gait & Loco.DIR_MASK
			var r = (gait >> Loco.RAMP_SHIFT) & 255
			if last != 0 and last != Loco.PLANE_STEP:
				r = int(min(r, RAMP_CAP[Loco.TURN[last * 9 + code]]))
			a.scout = (gait & Loco.DEBT_MASK) | code | (r << Loco.RAMP_SHIFT)
			a.rot_key = -1          # its body is turned for the new step on the next rotation tick
		elif a.tz != a.z:
			a.scout = (a.scout & Loco.DEBT_MASK) | Loco.PLANE_STEP | (int(min((a.scout >> Loco.RAMP_SHIFT) & 255, 60)) << Loco.RAMP_SHIFT)   # through the hole at a crawl
		if (moved or a.tz != a.z) and a.dig_timer <= 0.0:
			dist = a.hop if a.hop > 0.0 else (1.4142 if (a.tx != a.x and a.ty != a.y) else 1.0)
			a.t = min(over / dist, 1.6)
			if und and occ.size() > 0:
				_mark_step(a)
		else:
			a.scout = a.scout & Loco.NO_RAMP      # standing: it will set off slowly
			if a.dig_timer <= 0.0 and a.squad == 0 and a.tx == a.x and a.ty == a.y and a.tz == a.z:
				a.t = -HOLD_T
			break


# The body's target tilt and the way the ant faces, for the step it is on. On open ground: the smoothed hill, and left/right is the screen direction.
# In the tunnels: the floor under its feet (the nearest solid ground), facing the way the step goes along the body. Where the walls of a shaft or crack
# cancel out, or it climbs a chimney or scrambles a ledge, the body lies along the way it is going (it used to go up a shaft lying flat, like a lift).
# A plain vertical step on level ground never turns it round.
func _orient(a) -> void:
	var mx = a.tx - a.x
	var my = a.ty - a.y
	var f = a.facing
	var th = a.trot
	var g = grid
	var W = g.W
	var xl = a.tx - g.ox
	var deep = xl >= 1 and xl < W - 1 and a.ty >= 2 and a.ty < g.H - 1 and g.under[a.ty * W + xl] == 1 and g.under[(a.ty - 1) * W + xl] == 1
	if not deep and g.is_surface_cell(a.tx, a.ty):
		if abs(my) <= abs(mx):
			th = g.surface_tilt(a.tx)
			f = 1 if mx > 0 else -1
		else:
			th = atan2(f * my, f * mx)
	else:
		# the rock round the cell behind, this cell and the next together (so one odd cell at a bend does not turn the ant over and back):
		# nx, ny the sum of the offsets of the solid cells round them (the ground normal), nc how many there are
		var s = g.solid
		var WH = g.WH
		var nx := 0
		var ny := 0
		var nc := 0
		var roof := 0.0                 # how much more rock above than below makes a real roof (2 per cell counted)
		var lc = a.scout & Loco.DIR_MASK
		for k in 3:
			var cx = a.tx
			var cy = a.ty
			var cz = a.tz
			if k == 1:
				if a.tz != a.z:
					break
				cx = a.x
				cy = a.y
				cz = a.z
			elif k == 2:
				if lc < 1 or lc > 8:
					break
				cx = a.x - Loco.OX[lc - 1]
				cy = a.y - Loco.OY[lc - 1]
				cz = a.z
			var cl = cx - g.ox
			if cl < 1 or cl >= W - 1 or cy < 1 or cy >= g.H - 1:
				continue
			var b = cz * WH + cy * W + cl
			var ul = s[b - W - 1]
			var u = s[b - W]
			var ur = s[b - W + 1]
			var l = s[b - 1]
			var r = s[b + 1]
			var dl = s[b + W - 1]
			var dd = s[b + W]
			var dr = s[b + W + 1]
			nx += ur + r + dr - ul - l - dl
			ny += dl + dd + dr - ul - u - ur
			nc += ul + u + ur + l + r + dl + dd + dr
			roof -= 2.0
		var nl = nx * nx + ny * ny
		var along = nl * 3 < nc or nl == 0
		if not along:
			th = atan2(-nx, ny)
			if g.is_solid(a.tx, a.ty + 1, a.tz) or g.is_solid(a.x, a.y + 1, a.z):
				th = clamp(th, -1.1, 1.1)       # a floor under the feet wins (a ceiling cell must not turn it upside down)
			elif abs(th) > 2.0 and mx != 0 and abs(a.trot) <= 2.0 and (ny > roof or abs(nx) > -ny):
				along = true                    # it turns upside down only under a real roof (round an overhang at a bend it stays upright),
				                                # and once on a roof it stays there until the roof ends
			if not along:
				var d = mx * cos(th) + my * sin(th)
				if d * d > 0.1225 * (mx * mx + my * my):
					f = 1 if d > 0 else -1
		if along:
			if abs(mx) >= abs(my) and mx * f < 0:
				f = -f                                 # a level step against its facing: turn round rather than walk on upside down
			th = atan2(f * my, f * mx)
	a.trot = th
	a.facing = f


# Crowding in the tunnels. An ant marks the cell it is about to enter as taken by it for a moment (or the cell it stands in, for as long as it stands);
# others then choose a free cell beside it where there is one (Loco.descend), and one that has to follow into a taken cell slows down behind it, or
# squeezes past it slowly, instead of walking on through it.
func _mark_step(a) -> void:
	var g = grid
	var xl = a.tx - g.ox
	if xl < 0 or xl >= g.W or a.ty < 0 or a.ty >= g.H:
		return
	var j = a.ty * g.W + xl
	if g.under[j] != 1:
		return
	var i = a.tz * g.WH + j
	if i >= occ.size():
		return                  # (the world has just grown: _descend makes a new map)
	var q = int(time * 10.0)
	var o = occ[i]
	var me = a.id & 4095
	if (o >> 12) > q and (o & 4095) != me:
		var gait = a.scout
		a.scout = (gait & Loco.NO_RAMP) | (int(min((gait >> Loco.RAMP_SHIFT) & 255, 115)) << Loco.RAMP_SHIFT)
	occ[i] = ((q + 3) << 12) | me


# Is the tunnel cell (x, y, z) taken by an ant other than `a` (see _mark_step)?
func _taken(x: int, y: int, z: int, a) -> bool:
	if occ.size() != grid.PLANES * grid.WH or not grid.inb(x, y):
		return false
	var o = occ[z * grid.WH + y * grid.W + (x - grid.ox)]
	return (o >> 12) > int(time * 10.0) and (o & 4095) != (a.id & 4095)


func _occupy(a, tenths: int) -> void:
	if occ.size() != grid.PLANES * grid.WH or not grid.inb(a.x, a.y):
		return
	var j = a.y * grid.W + (a.x - grid.ox)
	if grid.under[j] == 1:
		occ[a.z * grid.WH + j] = ((int(time * 10.0) + tenths) << 12) | (a.id & 4095)


# The ant stands where it is for `secs` (see _step_ant).
func _pause(a, secs: float) -> void:
	a.hop = 0.0
	a.tx = a.x
	a.ty = a.y
	a.tz = a.z
	a.t = -secs
	var gait = a.scout & Loco.NO_RAMP
	if a.task != Task.NURSE:
		# a working ant makes up the time afterwards
		var und = grid.is_under(a.x, a.y)
		var sp = a.ph["speed"] * (a.ph["tunnel_mult"] if und else SURFACE_K * _s_walk)
		var debt = ((gait >> Loco.DEBT_SHIFT) & 4095) + int(sp * secs * 64.0)
		gait = (gait & 4095) | (int(min(4095, debt)) << Loco.DEBT_SHIFT)
	a.scout = gait
	_occupy(a, int(secs * 10.0) + 1)


func _on_arrive(a) -> void:
	_pause_req = 0.0
	if not grid.is_under(a.x, a.y):
		a.lane = clamp(a.lane + rng.randf_range(-0.02, 0.02), 0.0, 1.0)      # small steps: ants hop 18 cells a second now, and big ones made them shimmer
		if a.task == Task.FORAGE:
			var ph = grid.pher_at(a.x)
			if ph > 0.3:
				# two-lane trail, the clearer the stronger the trail: laden ants on one side, ants going out on the other, each a little apart
				a.lane = lerp(a.lane, (0.68 if a.carry > 0.0 else 0.32) + (a.id % 5 - 2) * 0.025, 0.12 * min(1.0, ph / 0.8))
	# lost footing (terrain changed, or the ant ended up in open space): grab the
	# nearest foothold, otherwise fall one cell
	if not grid.can_walk(a.x, a.y, a.z):
		var nb = grid.neighbors(a.x, a.y, a.z)
		if nb.size() > 0:
			_go(a, nb[rng.randi_range(0, nb.size() - 1)])
		elif not grid.is_solid(a.x, a.y + 1, a.z):
			_go(a, Vector2(a.x, a.y + 1))
		return

	if a.squad != 0 and Orders.obey(self, a):
		return
	var c0 = a.carry
	var task0 = a.task
	var q2 = _qb()
	match a.task:
		Task.FORAGE:
			_forage(a)
			_qe("t_forage", q2)
		Task.DIG:
			_dig(a)
			_qe("t_dig", q2)
		Task.NURSE:
			_nurse(a)
			_qe("t_nurse", q2)
		Task.DEFEND:
			_defend(a)
			_qe("t_defend", q2)
		Task.HOME:
			if grid.field(grid.dist_home, a.x, a.y, a.z) <= 1:
				_choose_task(a)
			else:
				_descend(a, grid.dist_home)
	# moments an ant stands still: at the pile with its mandibles full, at home having handed the food over, having just taken up a new job, and
	# (sometimes) with its head out of the nest mouth before it steps out
	if _pause_req <= 0.0 and a.carry == c0 and a.task == task0 and a.ty >= a.y:
		return                  # (nothing of the kind: most steps)
	if a.task == Task.DEFEND or a.squad != 0 or a.dig_timer > 0.0:
		return
	if a.carry > 0.0 and c0 <= 0.0:
		_pause_req = max(_pause_req, rng.randf_range(0.3, 0.45))
	elif c0 > 0.0 and a.carry <= 0.0:
		_pause_req = max(_pause_req, rng.randf_range(0.25, 0.5))
	elif a.task != task0:
		_pause_req = max(_pause_req, rng.randf_range(0.15, 0.4))
	elif a.task == Task.FORAGE and a.carry <= 0.0 and a.ty < a.y and not grid.is_under(a.tx, a.ty) and grid.is_under(a.x, a.y) and rng.randf() < 0.4:
		_pause_req = max(_pause_req, rng.randf_range(0.2, 0.35))
	if _pause_req > 0.0:
		_pause(a, _pause_req)
		_pause_req = 0.0


func _go(a, c) -> void:
	a.hop = 0.0
	a.tx = int(c.x)
	a.ty = int(c.y)
	a.tz = int(c.z) if typeof(c) == TYPE_VECTOR3 else a.z


# Step down a distance field. Only strictly-closer cells are candidates (guaranteed
# progress); among those, the one that turns least from the last step, preferring cells touching dirt (ants crawl along surfaces) and cells no other
# ant is about to enter. Holes between the planes are one more step (the same cell in the other plane).
func _descend(a, f: PoolIntArray) -> void:
	var ant = a is Ant
	if ant and occ.size() != grid.PLANES * grid.WH:
		occ = grid._neg           # all -1 (free); the first mark copies it
	Loco.descend(self, a, f, ant, ant)


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
	var threat = _nearest_surface_enemy(a.x, 5 + hop_k)
	if threat != null:
		a.heading = -1 if threat.x > a.x else 1
		a.flee = max(3, 10 / hop_k)
		_walk_surface(a)
		return
	# a winged ant that is not carrying anything goes for a bird in reach
	if bird != null and a.carry <= 0.0 and a.ph["wings"] > 0:
		var bdx = int(bird["x"]) - a.x
		if abs(bdx) <= BIRD_REACH and abs(bdx) > 2:
			a.heading = 1 if bdx > 0 else -1
			_walk_surface_k(a, max(1, abs(bdx) - 2))
			return
		elif abs(bdx) <= 2:
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
			a.carry = take * (1.0 + clamp(abs(p["x"] - ex) / 600.0, 0.0, 1.2)) * ((1.3 + 0.6 * mod("harvest_power")) if (harvest_t > 0.0 and p["x"] == harvest_x) else 1.0)
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
			if e.def.has("critter"):
				# the meadow's critters: only some foragers hunt (one in three, or any that knows no pile yet, or one it nearly
				# steps on), so the colony does not drop its food runs to chase snails; butterflies only for winged ants
				if e.def.get("fly", false) and a.ph["wings"] <= 0:
					continue
				if not (a.id % 3 == 0 or a.site == NO_SITE or abs(e.x - a.x) <= sense * 0.2):
					continue
			nearest = {"x": e.x}
			nd = abs(e.x - a.x)
	var lim = 99
	if nearest != null:
		if nd <= 1:
			return          # on top of it: stand and fight (the combat step is range-based) instead of stepping back and forth
		a.heading = 1 if nearest["x"] > a.x else -1
		a.leg = 0
		a.local_t = 0
		lim = max(1, int(nd) - 1)
	elif _search(a, ex, off):
		return
	else:
		lim = max(1, int(sense) - 2)
		if a.site != NO_SITE:
			lim = min(lim, max(1, abs(a.site - a.x) - 2))
	_walk_surface_k(a, lim)


# Searching with nothing in sense range. Returns true if the ant gave up (and turned for home).
# Real-ant ingredients: area-restricted search around a lost site, route memory, trail
# following, then long persistent scouting legs out to this trip's search radius.
func _search(a, ex: int, off: int) -> bool:
	if a.local_t > 0:
		a.local_t -= hop_k
		a.leg -= hop_k
		if a.leg <= 0:          # short sweeps, not a coin flip every hop: the ant visibly casts about instead of vibrating
			a.heading = -a.heading
			a.leg = rng.randi_range(14, 24)
			if rng.randf() < 0.6:
				_pause_req = rng.randf_range(0.12, 0.25)     # stops, feels about with its antennae, turns
		return false
	if a.site != NO_SITE:
		if abs(a.site - a.x) <= 2:
			a.site = NO_SITE         # got there: the pile is gone, circle the spot
			a.local_t = 40
			a.leg = rng.randi_range(10, 18)
			_pause_req = rng.randf_range(0.3, 0.5)          # nothing here any more: a moment at a loss
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
	a.leg -= hop_k
	if a.leg <= 0:
		a.leg = 25 + int(-log(max(0.001, rng.randf())) * LEG_MEAN)
		if rng.randf() < 0.4:
			a.heading = -a.heading
			_pause_req = rng.randf_range(0.15, 0.3)        # a scout that turns back stops to think about it first
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
	if a.site == NO_SITE and (harvest_t > 0.0 or rng.randf() < 0.7):
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
	if a.squad != 0:
		Orders.trip(self, a)


# Recruitment: a forager setting out is often told about a pile some nestmate has already found and that still holds
# food (nearer ones likelier, a few at random so one pile is not mobbed). Without it, once the food frontier moved past
# what a young forager's own search radius covers, only scouts ever found anything and the colony starved.
func _recruit_site() -> int:
	var ex = int(grid.entrance.x)
	if harvest_t > 0.0 and rng.randf() < 0.9:
		for p in piles:
			if p["x"] == harvest_x and p["amount"] > 8.0:
				return harvest_x
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
	Loco.surface_step(self, a)


# A walking hop that may cover several cells (never farther than `limit`): for foragers out on the open ground.
func _walk_surface_k(a, limit: int) -> void:
	Loco.surface_step(self, a, limit, true)


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
		if a.squad != 0 and Orders.is_dig(self, a):
			job = planner.job_by_id(Orders.job_of(self, a))          # a squad digs its own tunnel, and is let go when it is done
			if job == null:
				Orders.complete(self, a.squad, "The dig is done: the diggers are free.")
				return
		else:
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
	if n > 0:
		if grid.ug != null:
			grid.ug.on_carve(self, int(a.dig_cell.x), int(a.dig_cell.y), a.dig_z)
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
	# nurses potter about: a short walk along the floor of the nest (Loco.shuffle_home keeps it going one way), a moment standing over the brood,
	# another walk (they used to step to a random neighbour five times a second, and vibrated)
	if a.leg > 8:
		a.leg = 0                 # (left over from a foraging leg)
	if occ.size() != grid.PLANES * grid.WH:
		occ = grid._neg
	if a.leg <= 0 and _taken(a.x, a.y, a.z, a):
		a.leg = 1                 # somebody is standing here already: one more step
	if a.leg <= 0:
		a.leg = rng.randi_range(2, 7)
		a.scout = 0               # after standing it may set off either way
		var stand = rng.randf_range(0.5, 2.2)
		# never past the time it would think about another job (nursing spells keep their length, and with them the colony's share of nurses)
		stand = min(stand, 5.05 - a.timer) if a.timer < 5.0 else min(stand, 0.3)
		if stand > 0.05:
			_pause_req = stand
			return
	a.leg -= 1
	if a.leg == 0:
		a.scout = (a.scout & Loco.NO_RAMP) | (int(min((a.scout >> Loco.RAMP_SHIFT) & 255, 120)) << Loco.RAMP_SHIFT)   # the last step of a walk slows into the stop
	if Loco.shuffle_home(self, a):
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
			if grid.can_walk(x, y) and grid.field(grid.dist_home, x, y) == 0 and (grid.dist_exit.empty() or grid.field(grid.dist_exit, x, y) >= 0):
				cells.append(Vector2(x, y))
	return cells[rng.randi_range(0, cells.size() - 1)] if cells.size() > 0 else grid.chamber


# ------------------------------------------------------------------ queen, brood, food
func _step_queen(dt: float) -> void:
	var interval = [9.0, 5.0, 2.5][brood] / _s_lay
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
	eggs.append({"t": ht, "t0": ht, "genome": g, "gen": gen, "pos": Vector2(ep.x, ep.y), "z": int(ep.z), "caste": caste})


# The queen raises the caste the colony needs most right now.
func _needed_caste() -> int:
	var threat = 0.2 + 0.3 * min(1.0, raid_n / 4.0) + _stim_defend
	var cb = rule("caste_bias", [1.0, 1.0, 1.0])
	var co = CASTE_ORDER[caste_order]
	return _weighted([0, 1, 2], [max(0.25, _stim_forage) * cb[0] * co[0], max(0.1, _stim_dig + 0.1) * cb[1] * co[1], threat * cb[2] * co[2]])


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
	upkeep *= _s_upkeep
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
	if gem_piles < int((MAX_PILES + ants.size() / 60) * clamp(_s_food, 0.35, 1.2)) and _pile_timer <= 0.0:
		_spawn_pile()
		_pile_timer = rng.randf_range(8.0, 20.0) / max(0.05, _s_food)


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
		var amount = (rng.randf_range(20.0, 40.0) + d * 0.35) * (1.0 + mod("pile_rich")) * _s_rich
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
		if by_uid[u][1] > _champ_n:
			_champ_n = by_uid[u][1]
			champion = by_uid[u][0]
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
	raid_timer -= dt * (1.0 + mod("raid_haste")) * _s_raid
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
		if _raid_rival:
			_raid_rival = false
			rival.power = max(1.0, rival.power - 5.0)
			toasts.append({"text": "The %s raid broke against your defenders: they have lost heart." % (rival.name + ("'" if rival.name.ends_with("s") else "'s")), "t": 6.0})
		adapt[2] = {"left": 8, "bias": {"armor": 1.6, "spike": 1.0, "claw": 1.2, "size": 1.0}}
		toasts.append({"text": "The survivors breed hardier soldiers: armor, spikes, claws.", "t": 6.0})
		if raids_repelled % 2 == 0 and mutagen < 3:
			mutagen += 1
			toasts.append({"text": "Mutagen +1 (%d). Select an ant and press G." % mutagen, "t": 6.0})
	for q in raid_queue.duplicate():
		q["delay"] -= dt
		if q["delay"] <= 0.0:
			raid_queue.erase(q)
			_spawn_enemy(q["kind"], q["side"], int(q.get("from_x", 0)))


func _launch_raid() -> void:
	raid_n += 1
	var rr = sub_rng("raid", raid_n)
	var side = -1 if rr.randf() < 0.5 else 1
	var budget = (3.0 + 5.5 * pow(raid_n - 1, 0.8)) * max(0.3, 1.0 + mod("raid_size"))
	# every third raid is the rival colony's: its ants march out of its own mound, so they are seen coming
	_raid_rival = rival.alive() and raid_n >= 3 and raid_n % 3 == 0
	if _raid_rival:
		budget *= 0.8 + rival.power / 80.0
		rival.evolve(self)         # kin only: another step of evolution between its raids
	# a strong colony draws a bigger raid, and the later raids keep climbing, so a healthy colony is tested rather than coasting
	budget *= clamp(ants.size() / RAID_SIZE_REF, 0.85, 1.7) * (1.0 + RAID_LATE * max(0, raid_n - 6))
	var pool = EnemyDefs.SMALL.duplicate()
	pool += EnemyDefs.SMALL      # tunnel raiders stay common so the queen feels pressure
	if raid_n >= 2:
		pool += EnemyDefs.BRUTE
	if raid_n >= 6:
		pool += EnemyDefs.ELITE
	var kinds := []
	var boss_kind = "voidmaw" if raid_n >= BOSS_EVERY * 2 else "butcher"
	if raid_n % BOSS_EVERY == 0:
		kinds.append(boss_kind)
		budget -= EnemyDefs.DEFS[boss_kind]["cost"]
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
	var from_x := 0
	if _raid_rival:
		side = rival.side
		from_x = rival.x
		rival.raids += 1
		var conv = {"small": "redant", "brute": "redsoldier", "elite": "redmajor"}
		for i in kinds.size():
			var kc = EnemyDefs.DEFS[kinds[i]]["cls"]
			if conv.has(kc):
				kinds[i] = conv[kc]
	_raid_active = true
	# Raiders arrive in waves, not one every 0.9 s: a trickle was killed one by one as it came, so even a 70-raider raid
	# never put more than ~15 on the field and a big colony coasted. A wave walks in together and has to be fought as a mass.
	var wave = int(max(5.0, ceil(kinds.size() / 5.0)))
	for i in kinds.size():
		var dly = i * 0.9                                                      # small raids keep the old trickle
		if kinds.size() > 10:
			dly = (i / wave) * 7.0 + (i % wave) * 0.25
		raid_queue.append({"kind": kinds[i], "side": side, "delay": dly, "from_x": from_x})
	banner = "Raid %d  -  %d raiders from the %s" % [raid_n, kinds.size(), "west" if side < 0 else "east"]
	if _raid_rival:
		banner = "Raid %d  -  the %s attack from the %s!  (%d raiders)" % [raid_n, rival.name, "west" if side < 0 else "east", kinds.size()]
		if rival.is_kin():
			banner = "Raid %d  -  your own descendants, the %s, attack from the %s!  (%d)" % [raid_n, rival.name, "west" if side < 0 else "east", kinds.size()]
	if borers > 0:
		banner += "  -  %d BORING toward the queen!" % borers
	if kinds.has("voidmaw"):
		banner = "Raid %d  -  something climbs up out of the void!  (%d raiders)" % [raid_n, kinds.size()]
	_sfx("boss" if (kinds.has("butcher") or kinds.has("voidmaw")) else "raid")
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


func _spawn_enemy(kind: String, side: int, from_x: int = 0, guard_at: int = 0) -> void:
	var is_kin = rival.is_kin() and Rival.KIN_KINDS.has(kind)
	var d = rival.kin_def(kind) if is_kin else EnemyDefs.DEFS[kind]
	var e = Raider.new()
	if is_kin:
		e.genome = rival.genome
	e.id = _next_enemy_id
	_next_enemy_id += 1
	e.kind = kind
	e.def = d
	e.cls = d["cls"]
	e.x = grid.arena_l + rng.randi_range(2, 8) if side < 0 else grid.arena_r + 1 - rng.randi_range(3, 9)
	if from_x != 0:
		e.x = int(clamp(from_x + rng.randi_range(-4, 4), grid.arena_l + 3, grid.arena_r - 3))
	e.guard_x = guard_at
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
	if kind == "anteater":
		e.max_hp = (400.0 + 6.5 * ants.size()) * fate.raider_hp_mult      # it grows with the colony, not with the raid count
	if d.has("critter"):
		e.max_hp = d["hp"]                    # meadow critters stay small whatever the raid count
	e.hp = e.max_hp
	e.heading = -side
	e.facing = e.heading
	e.lane = rng.randf_range(0.45, 0.9)
	enemies.append(e)
	if kind == "butcher" or kind == "anteater" or kind == "voidmaw":
		shake = max(shake, 0.7)
		fx.append({"kind": "ring", "pos": grid.center(e.x, e.y - 2), "t": 0.0, "color": Color("#ff8a5c")})


func enemy_pos(e) -> Vector2:
	return grid.center(e.x, e.y).linear_interpolate(grid.center(e.tx, e.ty), e.t)


func _step_enemy(e, dt: float) -> void:
	if e.kind == "anteater":
		_anteater_tongue(e, dt)
	if e.genome != null and e.state != 2 and not e.def.get("abil", {}).empty():
		_kin_abilities(e, dt)
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


# A kin major uses the organs its line evolved: bolts, shockwaves, a lashing tongue, regrowth. The ants it hits take a gentler version of the raid's bite scale.
func _kin_abilities(e, dt: float) -> void:
	var ab = e.def["abil"]
	if e.stun_t > 0.0:
		return
	if ab.has("regen") and e.hp < e.max_hp:
		e.hp = min(e.max_hp, e.hp + e.max_hp * float(ab["regen"]["rate"]) * dt)
	var sc = 1.0 + 0.04 * (raid_n - 1)
	for k in ["arc", "pulse", "lash"]:
		if not ab.has(k):
			continue
		var a = ab[k]
		if not e.abil_t.has(k):
			e.abil_t[k] = float(a["cd"]) * rng.randf_range(0.4, 1.0)
		var t = float(e.abil_t[k]) - dt
		if t > 0.0:
			e.abil_t[k] = t
			continue
		var near := []
		for u in ants:
			if u.z == e.z and abs(u.x - e.x) <= int(a["r"]) and abs(u.y - e.y) <= 4:
				near.append(u)
		if near.empty():
			e.abil_t[k] = 0.5
			continue
		e.abil_t[k] = float(a["cd"]) * rng.randf_range(0.85, 1.15)
		var from = enemy_pos(e) + Vector2(e.facing * 20.0, -40.0)
		var hits := 0
		var fallen := []
		while hits < int(a["n"]) and not near.empty():
			var u2 = near[rng.randi_range(0, near.size() - 1)]
			near.erase(u2)
			hits += 1
			u2.hp -= float(a["dmg"]) * sc * (1.0 - u2.ph["armor_red"] * (1.0 - fate.raider_pierce))
			u2.hurt = 0.12
			if u2.hp <= 0.0:
				fallen.append(u2)
			if k == "arc":
				fx.append({"kind": "arc", "pos": from, "to": ant_pos(u2), "t": 0.0, "color": Color("#8ab8ff")})
			elif k == "lash":
				fx.append({"kind": "beam", "pos": from, "to": ant_pos(u2), "t": 0.0, "color": Color("#e8728f")})
		if k == "pulse":
			fx.append({"kind": "wave", "pos": enemy_pos(e) + Vector2(0, -20.0), "t": 0.0, "r": float(a["r"]) * grid.CELL, "color": Color("#ffe08a")})
		for u3 in fallen:
			if ants.has(u3):
				_ant_falls(u3)


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
		var near = _nearest_surface_ant(e.x, 4 if e.def.has("critter") else 6)
		if near != null:
			_set_heading(e, -1 if near.x > e.x else 1)
		elif rng.randf() < (0.02 if e.def.has("critter") else 0.04):
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

	if e.guard_x != 0:
		# a rival's guard: holds its own mound, goes for any ant that comes near, then goes back
		var gp = _chase_target(e, 10)
		var gg = e.guard_x if gp == null else gp.x
		var gd = _dir_to(e.x, gg)
		if gd == 0 or (gp != null and abs(gg - e.x) <= 1) or (gp == null and abs(e.x - e.guard_x) <= 3):
			_go(e, Vector2(e.x, e.y))
			return
		_set_heading(e, gd)
		_walk_surface(e)
		return
	# surface siegers
	if e.state == 0 and abs(e.x - ex) <= 4:
		e.state = 1
		e.timer = 0.0
	if e.state == 1 and e.timer > SIEGE_TIME and not e.void_born:      # a Void Maw from the pit never gives up: the pit seals only when it dies
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
		# it dives in: the soil it throws up lands beside the hole
		var cols = grid.deposit(e.x - e.facing * 2, 2.0, rng)
		if not cols.empty():
			_unbury(cols)
		fx.append({"kind": "puff", "pos": grid.center(e.x, grid.surf_y(e.x) - 1), "t": 0.0, "color": Color("#8a6a48")})
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


const COMBAT_BUCKET = 96.0         # px: ants are bucketed by x for the combat step
const FIGHT_LANE = 0.78            # the depth lane an engaged raider is drawn in, and the ants fighting it with it


func _combat(dt: float) -> void:
	var scale = 1.0 + 0.065 * (raid_n - 1) + RAID_BITE_LATE * pow(max(0, raid_n - 8), 2.0)
	var queen_hit := false
	_update_rally()
	# ant positions once per tick (was recomputed for every raider x ant pair); `apos` stays
	# index-aligned with `ants` and is rebuilt if a death changes the array mid-loop
	var apos := PoolVector2Array()
	var max_k2 := 1.0
	var apos_n := -1
	var buckets := {}
	for e in enemies.duplicate():
		e.engaged = false
		if e.state == 2:
			continue
		if apos_n != ants.size():
			apos_n = ants.size()
			apos = PoolVector2Array()
			max_k2 = 1.0
			buckets = {}
			var bi := 0
			for a0 in ants:
				var p0 = ant_pos(a0)
				apos.append(p0)
				max_k2 = max(max_k2, a0.ph.get("reach2", 1.0))
				var bk0 = int(floor(p0.x / COMBAT_BUCKET))
				if buckets.has(bk0):
					buckets[bk0].append(bi)
				else:
					buckets[bk0] = [bi]
				bi += 1
		var ep = enemy_pos(e)
		var reach = EnemyDefs.REACH[e.cls] * grid.CELL
		var r2 = reach * reach
		var ar = reach * _r_reach
		var ar2 = ar * ar
		var far = ar * sqrt(max_k2) + 0.01   # no ant can be hit from farther than this
		var target = null
		var td = 1e12
		var dmg_in := 0.0
		# only the ants in the stretches of ground within reach (ants bucketed by x once per tick), not the whole colony
		var near_idx := []
		for bk in range(int(floor((ep.x - far) / COMBAT_BUCKET)), int(floor((ep.x + far) / COMBAT_BUCKET)) + 1):
			if buckets.has(bk):
				near_idx += buckets[bk]
		for ai in near_idx:
			var a = ants[ai]
			if a.z != e.z:
				continue   # a wall of dirt between them
			var apx = apos[ai]
			if abs(apx.x - ep.x) > far:
				continue
			if e.def.get("fly", false) and e.cls == "prey" and a.ph["wings"] <= 0:
				continue   # a butterfly is out of reach of anything without wings
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
				dmg_in += hit * (1.0 - float(e.def.get("armor", 0.0)))     # evolved kin shrug off a share of every bite
				a.fitness += hit * 0.08
				a.f_fight += hit * 0.08
				a.lane = lerp(a.lane, clamp(e.lane + (a.id % 3 - 1) * 0.05, 0.0, 1.0), clamp(dt * 6.0, 0.0, 1.0))   # fighters line up with their raider quickly
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
		if e.engaged and e.cls != "prey":
			e.lane = lerp(e.lane, FIGHT_LANE, clamp(dt * 1.5, 0.0, 1.0))      # fights happen in one readable lane, near the front, not scattered through the depth
		if dmg_in > 0.0:
			if e.flash <= 0.0 and target != null:
				_sfx("hit")
			if e.spark <= 0.0 and dmg_in > 0.0:
				e.spark = 0.4
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
		eggs.append({"t": 5.0, "t0": 5.0, "genome": a.genome, "gen": a.gen + 1, "pos": Vector2(ep.x, ep.y), "z": int(ep.z), "caste": a.caste})
		fx.append({"kind": "text", "pos": ant_pos(a) + Vector2(0, -24), "t": 0.0, "text": "RETURNS", "color": Color("#d8e8a0")})
	elif a.ph.get("split", 0.0) > 0.0 and rng.randf() < a.ph["split"]:
		# planarian split: the torn body regrows as a fresh egg of the same plan
		var broods2 := []
		for c in planner.chambers:
			if c["purpose"] == "brood":
				broods2.append(c)
		var ep2 = _egg_pos(broods2)
		eggs.append({"t": 6.0, "t0": 6.0, "genome": a.genome, "gen": a.gen + 1, "pos": Vector2(ep2.x, ep2.y), "z": int(ep2.z), "caste": a.caste})
		fx.append({"kind": "text", "pos": ant_pos(a) + Vector2(0, -24), "t": 0.0, "text": "SPLITS", "color": Color("#ffb3c8")})
	kill(a, "combat")


# Stridulating ants (sonic tier 1+) that are fighting rally every ant within 4 cells on
# their plane: attack x (1 + rally), strongest source only. Cheap: sources are few.
func _update_rally() -> void:
	var src := []
	var any_e = not enemies.empty()
	for a in ants:
		a.rally_k = (1.35 + 0.2 * mod("rally_power")) if (rally_t > 0.0 and abs(a.x - rally_x) <= 16) else 1.0
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
	if e.cls != "prey":
		kills += 1          # critters and other prey are not raiders slain
	if e.kind == "anteater":
		anteaters_slain += 1
		var xtra = ""
		if mutagen < 3:
			mutagen += 1
			xtra = " +1 mutagen"
		toasts.append({"text": "The anteater is dead!%s  (a pile of food is left where it fell)" % xtra, "t": 8.0})
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
			if _alerts(e) and grid.can_walk(e.x, e.y, e.z):   # passive prey and far-off wanderers are not a threat
				src.append(Vector3(e.x, e.y, e.z))
		dist_threat = grid._bfs(src, 260) if not src.empty() else PoolIntArray()
	# alarm: idle and digging ants reconsider quickly while raiders are present
	_alarm_timer -= dt
	if _alert_n > 0 and _alarm_timer <= 0.0:
		_alarm_timer = 2.0
		for a in ants:
			if a.task == Task.NURSE or a.task == Task.DIG or (a.task == Task.FORAGE and a.carry == 0.0 and grid.is_under(a.x, a.y)):
				if rng.randf() < 0.5:
					_choose_task(a)


func _defend(a) -> void:
	if rally_t > 0.0 and _inside_n == 0 and queen_hp >= queen_max * 0.7:
		# the flag is up: walk to it and hold it, whatever is or is not attacking on the surface. Never while raiders are
		# inside the nest or the queen is hurt: then everyone defends the nest as usual.
		if grid.is_under(a.x, a.y):
			_descend(a, grid.dist_exit)
		elif abs(a.x - rally_x) > 3:
			a.heading = 1 if rally_x > a.x else -1
			_walk_surface(a)
		else:
			_go(a, Vector2(a.x, a.y))
		return
	if _alert_n == 0 or a.timer > 70.0 or dist_threat.size() == 0:
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


# A hostile the colony has a reason to answer: near the nest, or in it. A cave spider still 600 cells out used to keep most of the
# colony standing guard (and off the food runs) for the minutes it took to walk home.
func _alerts(e) -> bool:
	return e.cls != "prey" and (abs(e.x - int(grid.entrance.x)) <= ALERT_RANGE or grid.is_under(e.x, e.y))


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
	# fungus farms ferment scraps (and part of what rots) back into food; a mouldy garden gives much less
	var healthy := float(farms)
	if farms > 0:
		healthy = _step_gardens(dt, nurses)
	farm_rate = healthy * 0.14 * float(rule("farm_boost", 1.0)) * (0.5 + 0.5 * min(1.0, nurses / max(1.0, farms * 3.0))) + rot_rate * (0.4 if farms > 0 else 0.0)
	food += farm_rate * dt
	ledger["farm"] += farm_rate * dt
	_sync_trees(dt)
	_check_landmarks(dt)
	for tr in trees:
		tr["t"] -= dt * float(rule("fruit_boost", 1.0)) * _s_fruit
		if tr["t"] <= 0.0:
			tr["t"] = rng.randf_range(22.0, 34.0)       # the giant fruit trees are the landscape's oases (a few feed a small colony; a big one must range)
			_drop_fruit(tr["x"])


# ---- Fungus gardens, the way leafcutters really keep them: the garden grows in stages after the room is dug (spores, then white
# hyphae, then the mature sponge with its food bulbs), and a rival fungus (mould) now and then gets into one. Nurses weed it out
# (more nurses per garden, faster); a neglected garden is overgrown and gives little. The Metapleural Glands item (the antibiotic
# gland real ants carry) makes outbreaks rarer and the weeding quicker.
var farm_born := {}                # garden key -> the time its room was first seen
var farm_mold := {}                # garden key -> 0..1, how much of the garden the mould holds
var mold_events := 0
var _mold_timer := 240.0


func farm_key(c) -> int:
	return int(c["center"].x) * 1000 + int(c["center"].y)


func farm_age(c) -> float:
	return time - float(farm_born.get(farm_key(c), time))


func mold_of(c) -> float:
	return float(farm_mold.get(farm_key(c), 0.0))


# Returns the number of gardens' worth of healthy fungus.
func _step_gardens(dt: float, nurses: int) -> float:
	var list := []
	for c in planner.chambers:
		if c["purpose"] == "farm":
			list.append(c)
			if not farm_born.has(farm_key(c)):
				farm_born[farm_key(c)] = time
	if list.empty():
		return 0.0
	_mold_timer -= dt
	if _mold_timer <= 0.0:
		_mold_timer = rng.randf_range(200.0, 360.0) * (1.0 + 0.8 * mod("mold_resist"))
		var pick = list[rng.randi_range(0, list.size() - 1)]
		if mold_of(pick) <= 0.0 and farm_age(pick) > 60.0:
			farm_mold[farm_key(pick)] = 0.12
			mold_events += 1
			toasts.append({"text": "Mould in a fungus garden! The nurses will weed it out (more nurses, faster).", "t": 6.0})
	var care = min(3.0, nurses / float(list.size()))             # nurses per garden
	var healthy := 0.0
	for c in list:
		var k = farm_key(c)
		var m = float(farm_mold.get(k, 0.0))
		if m > 0.0:
			m = clamp(m + dt * (0.018 - 0.014 * care * (1.0 + mod("mold_resist"))), 0.0, 1.0)
			if m <= 0.0:
				farm_mold.erase(k)
				toasts.append({"text": "The garden is clean again.", "t": 4.0})
			else:
				farm_mold[k] = m
		var grown = clamp(farm_age(c) / 150.0, 0.25, 1.0)        # a young garden gives less
		healthy += grown * (1.0 - 0.8 * m)
	return healthy


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


# The meadow's small life: ladybirds, snails, caterpillars, grasshoppers and butterflies are real prey now (v0.35), not scenery, so any
# of them can be attacked (by an order or by a forager that comes across it). They never bite back; they run from ants and wander.
# The population follows the size of the explored meadow, the season (none in winter, snails in the rain, butterflies in summer).
var _critter_t := 8.0


func _step_critters(dt: float) -> void:
	_critter_t -= dt
	if _critter_t > 0.0:
		return
	_critter_t = rng.randf_range(4.0, 9.0)
	var n := 0
	for e in enemies:
		if e.def.has("critter"):
			n += 1
	var winter = Seasons.snow(time) > 0.5
	if winter or rain > 0.5:
		# winter sends every critter to ground, rain the fliers: one leaves now and then (never one that is being fought)
		for e in enemies:
			if e.def.has("critter") and not e.engaged and (winter or e.def.get("fly", false)):
				enemies.erase(e)
				break
	var width = 0
	for a in ants:
		if not grid.is_under(a.x, a.y):
			width = max(width, abs(a.x - int(grid.entrance.x)))
	var want = 0 if winter else int(clamp((width * 2 + 260) / 70, 3, 14))
	if n >= want:
		return
	var w = [3.0, 1.0 + 6.0 * rain, 2.0, 2.5, 2.0 * (1.0 - rain), 1.5 * (1.0 - rain)]
	var kind = _weighted(EnemyDefs.CRITTERS, w)
	var ex = int(grid.entrance.x)
	var x = ex
	var reach = max(130, width + 40)          # where the colony goes: critters live along its trails, not only by the nest
	for tries in 6:
		x = int(clamp(ex + rng.randi_range(-reach, reach), grid.sim_l() + 6, grid.sim_r() - 6))
		if abs(x - ex) > 18:
			break
	_spawn_enemy(kind, -1 if rng.randf() < 0.5 else 1, x)
	var c = enemies.back()
	c.heading = -1 if rng.randf() < 0.5 else 1
	c.facing = c.heading
	c.lane = rng.randf_range(0.15, 0.95)


func _step_prey(dt: float) -> void:
	_step_critters(dt)
	_prey_timer -= dt
	if _prey_timer > 0.0:
		return
	var pb = float(rule("prey_boost", 1.0))
	_prey_timer = rng.randf_range(35.0, 70.0) / pb
	var n := 0
	for e in enemies:
		if e.cls == "prey" and not e.def.has("critter"):
			n += 1
	if n < 2 + int(pb - 1.0 + 0.5):
		_spawn_enemy("looter", -1 if rng.randf() < 0.5 else 1)
