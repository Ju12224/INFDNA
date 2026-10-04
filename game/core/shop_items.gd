extends RefCounted
# Evolution Lab offers. Icons are the owner's drawings in art/items/<id>.png ("icon" is the old Brotato id, kept as a note)
# (the item's original Brotato effect is irrelevant here).
#
# Effect keys (any combination, all stack):
#   bias   - mutation odds: leg claw tentacle armor spike eyes size segment, and the
#            anatomy genes (morph, wings stinger acid major replete glow camo phero hair)
#   trait  - newborn instinct nudges: forage_t dig_t defend_t dig_down explore
#   colony - one-off colony changes: mutation queen_hp hatch egg_cost entrance
#            base_armor tournament double_mut
#   mods   - stacking colony modifiers (see colony_sim.mod()):
#            hp attack speed carry upkeep life dig thorns (multipliers, +x = +x*100%)
#            sense armor regen defend_attack pile_rich pile_near siege_dmg
#            tunnel_dmg interest price_disc reroll_disc corpse_food kill_food raid_size
#            the director's: will_regen (+x = +x*100%) will_max (+flat) cmd_cd cmd_cost (multipliers, -x = x*100% less)
#            rally_power harvest_power surge_power (+x = +x*100% longer, a little stronger) breed_power (+eggs) bird_ward
#            mold_resist (fungus garden mould is rarer and cleared faster)
# Tiers follow Brotato: 1 common, 2 uncommon, 3 rare, 4 legendary.

const ICON = "res://art/items/%s.png"     # the owner's drawing for each item (tools/art/make_item_icons.py)

const ITEMS = {
	# ---- strains (mutation odds)
	"swift": {"name": "Swift Strain", "icon": "wings", "tier": 1, "price": 30, "desc": "Mutations favor legs.", "bias": {"leg": 1.0}},
	"pincer": {"name": "Pincer Strain", "icon": "claw_tree", "tier": 1, "price": 30, "desc": "Mutations favor claws.", "bias": {"claw": 1.0}},
	"tendril": {"name": "Tendril Strain", "icon": "tentacle", "tier": 1, "price": 30, "desc": "Mutations favor tentacles.", "bias": {"tentacle": 1.0}},
	"keen": {"name": "Keen Strain", "icon": "alien_eyes", "tier": 1, "price": 25, "desc": "Mutations favor eyes and longer antennae.", "bias": {"eyes": 1.0}},
	"spider": {"name": "Spider Strain", "icon": "spider", "tier": 1, "price": 30, "desc": "Mutations favor legs and spikes.", "bias": {"leg": 0.6, "spike": 0.5}},
	"chitin": {"name": "Chitin Strain", "icon": "exoskeleton", "tier": 2, "price": 45, "desc": "Mutations favor armor plating.", "bias": {"armor": 1.2}},
	"thorn": {"name": "Thorn Strain", "icon": "hedgehog", "tier": 2, "price": 45, "desc": "Mutations favor spikes that hurt attackers.", "bias": {"spike": 1.2}},
	"giant": {"name": "Giant Strain", "icon": "mammoth", "tier": 2, "price": 45, "desc": "Mutations favor bigger body segments.", "bias": {"size": 1.0}},
	"octopus": {"name": "Octopus Strain", "icon": "octopus", "tier": 2, "price": 50, "desc": "Tentacle limbs and tentacle jaws become far more likely.", "bias": {"tentacle": 1.8}},
	"hox": {"name": "Hox Shift", "icon": "alien_worm", "tier": 3, "price": 70, "desc": "Body segments duplicate far more often.", "bias": {"segment": 1.5}},
	# ---- anatomy strains (M4: new organs, each with a real cost)
	"alate": {"name": "Alate Strain", "icon": "butterfly", "tier": 2, "price": 55, "desc": "Wings evolve more often: fast on the surface, frail, cramped in tunnels.", "bias": {"wings": 1.6, "morph": 0.5}},
	"sting": {"name": "Sting Strain", "icon": "clockwork_wasp", "tier": 2, "price": 45, "desc": "Stingers evolve more often: hit harder, eat a little more.", "bias": {"stinger": 1.6, "morph": 0.5}},
	"formic": {"name": "Formic Strain", "icon": "acid", "tier": 2, "price": 50, "desc": "Acid glands evolve more often: attackers get burned, loads get lighter.", "bias": {"acid": 1.6, "morph": 0.5}},
	"major": {"name": "Soldier Heads", "icon": "head_injury", "tier": 2, "price": 50, "desc": "Big-headed majors evolve more often: strong bite and dig, slow walkers.", "bias": {"major": 1.6, "morph": 0.5}},
	"replete": {"name": "Honeypot Strain", "icon": "honey", "tier": 2, "price": 45, "desc": "Replete gasters evolve more often: carry more food, waddle slower.", "bias": {"replete": 1.6, "morph": 0.5}},
	"glow": {"name": "Glow Strain", "icon": "will_o_the_wisp", "tier": 1, "price": 35, "desc": "Luminous spots evolve more often: sense food farther.", "bias": {"glow": 1.6, "morph": 0.4}},
	"camo": {"name": "Camouflage Strain", "icon": "chameleon", "tier": 2, "price": 45, "desc": "Drab mottled bodies evolve more often: harder to hit.", "bias": {"camo": 1.6, "morph": 0.5}},
	"trail": {"name": "Trail Pheromone", "icon": "peaceful_bee", "tier": 1, "price": 30, "desc": "Stronger trail scent evolves more often: foragers follow each other better.", "bias": {"phero": 1.6, "morph": 0.4}},
	"fuzz": {"name": "Bristle Strain", "icon": "lumberjack_shirt", "tier": 1, "price": 30, "desc": "Body hair evolves more often: a little armor, a little slower.", "bias": {"hair": 1.6, "morph": 0.4}},
	# ---- organ strains (v0.21): push one animal line up its tiers
	"cricket": {"name": "Cricket Song", "icon": "metal_detector", "tier": 2, "price": 45, "desc": "Sound organs evolve more often: chirps rally fighters, then bat ears, then a pistol-shrimp shockwave.", "bias": {"sonic": 1.6, "organ": 0.8}},
	"eel": {"name": "Eel Strain", "icon": "glass_cannon", "tier": 2, "price": 50, "desc": "Electric organs evolve more often: sense prey, shock attackers, then chain lightning.", "bias": {"electric": 1.6, "organ": 0.8}},
	"turtle": {"name": "Shell Strain", "icon": "snail", "tier": 2, "price": 45, "desc": "Shells evolve more often: scutes, a snail shell, then armadillos that curl up when hurt.", "bias": {"shell": 1.6, "organ": 0.8}},
	"orbweaver": {"name": "Silk Strain", "icon": "spider", "tier": 2, "price": 45, "desc": "Silk evolves more often: carry bundles, webs that slow raiders, then bolas snares that stun.", "bias": {"silk": 1.6, "organ": 0.8}},
	"frog": {"name": "Frog Tongue", "icon": "chameleon", "tier": 2, "price": 45, "desc": "Long tongues evolve more often: lap food, bite from farther, then chameleon tongue shots.", "bias": {"tongue": 1.6, "organ": 0.8}},
	"axolotl": {"name": "Axolotl Strain", "icon": "medikit", "tier": 3, "price": 65, "desc": "Regrowth evolves more often: heal over time, then gills, then planarians that split when killed.", "bias": {"regen": 1.6, "organ": 0.8}},
	# ---- instincts (newborn genes)
	"gather": {"name": "Gatherer Pheromone", "icon": "fruit_basket", "tier": 1, "price": 30, "desc": "Newborns start foraging at weaker hunger signals.", "trait": {"forage_t": -0.05}},
	"burrow": {"name": "Burrower Instinct", "icon": "improved_tools", "tier": 1, "price": 25, "desc": "Newborns dig deeper, straighter tunnels.", "trait": {"dig_down": 0.07}},
	"war": {"name": "War Pheromone", "icon": "warrior_helmet", "tier": 2, "price": 40, "desc": "Newborns join fights at weaker alarm signals.", "trait": {"defend_t": -0.06}},
	# ---- body modifiers
	"stomach": {"name": "Extra Stomach", "icon": "extra_stomach", "tier": 1, "price": 35, "desc": "Every ant carries 20% more food.", "mods": {"carry": 0.2}},
	"vest": {"name": "Leather Hide", "icon": "leather_vest", "tier": 1, "price": 30, "desc": "Every ant has 15% more HP.", "mods": {"hp": 0.15}},
	"arms": {"name": "Big Mandibles", "icon": "big_arms", "tier": 1, "price": 35, "desc": "Every ant hits 20% harder.", "mods": {"attack": 0.2}},
	"coffee": {"name": "Caffeine Glands", "icon": "coffee", "tier": 1, "price": 35, "desc": "Ants move 10% faster but eat 10% more.", "mods": {"speed": 0.1, "upkeep": 0.1}},
	"snail": {"name": "Slow Metabolism", "icon": "snail", "tier": 1, "price": 30, "desc": "Ants eat 15% less but move 5% slower.", "mods": {"upkeep": -0.15, "speed": -0.05}},
	"detector": {"name": "Scout Antennae", "icon": "metal_detector", "tier": 1, "price": 25, "desc": "Foragers sense food 6 cells farther.", "mods": {"sense": 6.0}},
	"tools": {"name": "Sharpened Claws", "icon": "whetstone", "tier": 1, "price": 25, "desc": "Ants dig 25% faster.", "mods": {"dig": 0.25}},
	"helmet": {"name": "Hard Heads", "icon": "helmet", "tier": 2, "price": 45, "desc": "Every ant ignores 8% more damage.", "mods": {"armor": 0.08}},
	"sludge": {"name": "Toxic Spines", "icon": "toxic_sludge", "tier": 2, "price": 45, "desc": "Spikes deal double damage back.", "mods": {"thorns": 1.0}},
	"cannon": {"name": "Berserker Brood", "icon": "glass_cannon", "tier": 2, "price": 45, "desc": "Ants hit 35% harder but have 20% less HP.", "mods": {"attack": 0.35, "hp": -0.2}},
	"banner": {"name": "Rally Banner", "icon": "banner", "tier": 2, "price": 45, "desc": "Defenders hit 25% harder.", "mods": {"defend_attack": 0.25}},
	"hourglass": {"name": "Long Lives", "icon": "hourglass", "tier": 2, "price": 50, "desc": "Ants live 25% longer.", "mods": {"life": 0.25}},
	"medikit": {"name": "Nurse Caste", "icon": "medikit", "tier": 2, "price": 50, "desc": "Wounded ants heal 2 HP/s inside the nest.", "mods": {"regen": 2.0}},
	"tardigrade": {"name": "Tardigrade Gene", "icon": "tardigrade", "tier": 4, "price": 150, "desc": "Every ant has 40% more HP and ignores 10% more damage.", "mods": {"hp": 0.4, "armor": 0.1}, "max": 1},
	# ---- economy
	"bait": {"name": "Sweet Bait", "icon": "bait", "tier": 1, "price": 30, "desc": "New food piles are 25% richer.", "mods": {"pile_rich": 0.25}},
	"lure": {"name": "Lure", "icon": "lure", "tier": 2, "price": 40, "desc": "Food appears closer to the nest.", "mods": {"pile_near": 1.0}, "max": 2},
	"piggy": {"name": "Food Cellar", "icon": "piggy_bank", "tier": 2, "price": 50, "desc": "Each repelled raid adds 10% interest to stored food.", "mods": {"interest": 0.1}},
	"flesh": {"name": "Recyclers", "icon": "decomposing_flesh", "tier": 1, "price": 30, "desc": "Fallen ants return 3 food to the stores.", "mods": {"corpse_food": 3.0}},
	"meat": {"name": "Hunters", "icon": "fresh_meat", "tier": 1, "price": 30, "desc": "Raiders drop 30% more food.", "mods": {"kill_food": 0.3}},
	"coupon": {"name": "Coupon", "icon": "coupon", "tier": 2, "price": 40, "desc": "Lab prices are 10% lower.", "mods": {"price_disc": 0.1}, "max": 3},
	"token": {"name": "Gambler's Gland", "icon": "gambling_token", "tier": 1, "price": 25, "desc": "Rerolls cost 2 less.", "mods": {"reroll_disc": 2.0}, "max": 2},
	# ---- the director's items (v0.29): they feed the Will meter and the five commands
	"whisper": {"name": "Queen's Whisper", "icon": "lure", "tier": 1, "price": 35, "desc": "Your Will regenerates 30% faster.", "mods": {"will_regen": 0.3}, "max": 3},
	"reserve": {"name": "Deep Reserve", "icon": "piggy_bank", "tier": 2, "price": 45, "desc": "Your Will bar holds 40 more.", "mods": {"will_max": 40.0}, "max": 2},
	"choir": {"name": "Pheromone Choir", "icon": "peaceful_bee", "tier": 2, "price": 50, "desc": "Every command recharges 25% faster.", "mods": {"cmd_cd": -0.25}, "max": 2},
	"frugal": {"name": "Frugal Orders", "icon": "coupon", "tier": 2, "price": 45, "desc": "Every command costs 20% less Will.", "mods": {"cmd_cost": -0.2}, "max": 2},
	"standard": {"name": "War Standard", "icon": "warrior_helmet", "tier": 2, "price": 45, "desc": "Rally lasts 50% longer and rallied ants bite 10% harder.", "mods": {"rally_power": 0.5}, "max": 2},
	"trail_honey": {"name": "Honey Trail", "icon": "honey", "tier": 2, "price": 45, "desc": "Harvest lasts 50% longer and the ants it sends carry 30% more.", "mods": {"harvest_power": 0.5}, "max": 2},
	"scarecrow": {"name": "Scarecrow", "icon": "lumberjack_shirt", "tier": 2, "price": 45, "desc": "Birds come 40% less often and leave sooner.", "mods": {"bird_ward": 0.5}, "max": 2},
	"adrenal": {"name": "Adrenal Glands", "icon": "injection", "tier": 2, "price": 45, "desc": "Surge lasts 50% longer and runs 15% faster.", "mods": {"surge_power": 0.5}, "max": 2},
	"studbook": {"name": "Stud Book", "icon": "pile_of_books", "tier": 2, "price": 50, "desc": "Breed steers 4 more eggs.", "mods": {"breed_power": 4.0}, "max": 2},
	"hivevoice": {"name": "Hive Voice", "icon": "triangle_of_power", "tier": 4, "price": 150, "desc": "The colony hangs on your word: +50% Will regeneration, commands recharge 20% faster, +30 Will.", "mods": {"will_regen": 0.5, "cmd_cd": -0.2, "will_max": 30.0}, "max": 1},
	"metapleural": {"name": "Metapleural Glands", "icon": "medikit", "tier": 2, "price": 45, "desc": "The antibiotic glands real ants carry: mould in the fungus gardens is rarer and gets weeded out faster.", "mods": {"mold_resist": 1.0}, "max": 2},
	# ---- defenses
	"barricade": {"name": "Thorn Barricade", "icon": "barricade", "tier": 2, "price": 50, "desc": "Raiders sieging the entrance take 4 damage per second.", "mods": {"siege_dmg": 4.0}},
	"landmines": {"name": "Tunnel Traps", "icon": "landmines", "tier": 2, "price": 50, "desc": "Raiders inside the tunnels take 5 damage per second.", "mods": {"tunnel_dmg": 5.0}},
	"flag": {"name": "Pheromone Mask", "icon": "white_flag", "tier": 3, "price": 70, "desc": "Raids bring 15% fewer raiders.", "mods": {"raid_size": -0.15}, "max": 2},
	# ---- black market: strong now, with a side effect you only learn about later.
	#      "hidden" applies at purchase like any effect; its text shows as ??? until noticed.
	"hormone": {"name": "Growth Hormone", "icon": "injection", "tier": 2, "price": 45, "desc": "Every ant has 30% more HP and hits 15% harder.", "mods": {"hp": 0.3, "attack": 0.15},
		"hidden": {"mods": {"upkeep": 0.45}}, "hidden_desc": "ants eat 45% more.", "rumor": "hormone-fed ants are always hungry.", "reveal": 70.0},
	"sugar": {"name": "Sugar Rush", "icon": "candy_bag", "tier": 1, "price": 30, "desc": "New food piles are 60% richer.", "mods": {"pile_rich": 0.6},
		"hidden": {"mods": {"spoilage": 0.4}}, "hidden_desc": "sugary stores rot 0.4% per second.", "rumor": "sugar does not keep.", "reveal": 50.0, "max": 2},
	"purebred": {"name": "Purebred Line", "icon": "pocket_factory", "tier": 3, "price": 60, "desc": "Parents are chosen from the fittest 10 instead of 4.", "colony": {"tournament": 6},
		"hidden": {"mods": {"plague": 1.0}}, "hidden_desc": "clones get sick: plague hits when one body plan passes 35% of the colony.", "rumor": "pure lines sicken together.", "reveal_on": "plague", "max": 1},
	"elixir": {"name": "Queen's Elixir", "icon": "potion", "tier": 2, "price": 50, "desc": "Eggs hatch 30% faster.", "colony": {"hatch": 0.7}, "max": 1,
		"hidden": {"mods": {"queen_drain": 0.8}}, "hidden_desc": "the queen loses 0.8 HP per second (never below 15%).", "rumor": "the elixir takes something from whoever lays the eggs.", "reveal": 80.0},
	"drums": {"name": "War Drums", "icon": "ritual", "tier": 2, "price": 45, "desc": "Every ant hits 25% harder; defenders 30% harder.", "mods": {"attack": 0.25, "defend_attack": 0.3},
		"hidden": {"mods": {"raid_size": 0.35}}, "hidden_desc": "the noise draws 35% bigger raids.", "rumor": "drums carry far. Who else is listening?", "reveal_on": "raid", "max": 2},
	"beacon": {"name": "Scent Beacon", "icon": "candle", "tier": 1, "price": 35, "desc": "Food appears closer and foragers sense 6 cells farther.", "mods": {"pile_near": 1.0, "sense": 6.0},
		"hidden": {"mods": {"raid_haste": 0.4}}, "hidden_desc": "raiders smell it too: raids come 40% sooner.", "rumor": "a beacon calls more than your foragers.", "reveal_on": "raid", "max": 1},
	"dynamite": {"name": "Blasting Caps", "icon": "dynamite", "tier": 2, "price": 40, "desc": "Ants dig 60% faster.", "mods": {"dig": 0.6},
		"hidden": {"mods": {"cave_in": 0.5}}, "hidden_desc": "tunnels cave in now and then, crushing diggers.", "rumor": "blasted tunnels are not stable tunnels.", "reveal_on": "cave_in", "max": 1},
	"idol": {"name": "Cursed Idol", "icon": "goat_skull", "tier": 3, "price": 60, "desc": "Every ant: +40% HP, +40% attack, +20% speed.", "mods": {"hp": 0.4, "attack": 0.4, "speed": 0.2},
		"hidden": {"mods": {"life": -0.45}}, "hidden_desc": "ants live 45% shorter lives.", "rumor": "the idol gives strength and takes years.", "reveal": 120.0, "max": 1},
	"glass": {"name": "Glass Carapace", "icon": "jellyshield", "tier": 2, "price": 40, "desc": "Every ant ignores 15% more damage.", "mods": {"armor": 0.15},
		"hidden": {"mods": {"hp": -0.3}}, "hidden_desc": "shells are brittle: 30% less HP.", "rumor": "glass is hard, and glass breaks.", "reveal_on": "raid", "max": 1},
	"clover": {"name": "Four-Leaf Pheromone", "icon": "clover", "tier": 1, "price": 25, "desc": "The ants seem cheerful.",
		"hidden": {"mods": {"luck": 0.6}}, "hidden_desc": "rare and legendary items show up far more often.", "rumor": "some say the clover is lucky. Some say that is all it is.", "reveal_on": "shop", "max": 1},
	"egg": {"name": "Mystery Egg", "icon": "lost_duck", "tier": 2, "price": 40, "desc": "Something is growing inside. Could be anything.",
		"gamble": [
			{"colony": {"mutation": 0.25, "double_mut": 0.3}, "text": "a mutagenic jackpot (+25% mutation, frequent double mutations)"},
			{"mods": {"hp": -0.25}, "text": "a parasite (every ant has 25% less HP)"},
			{"colony": {"queen_hp": 150.0}, "text": "a royal twin (queen +150 max HP)"},
			{"mods": {"upkeep": 0.3}, "text": "a glutton gene (ants eat 30% more)"},
			{"food": 120.0, "text": "a hidden stash (+120 food)"},
			{"mods": {"speed": 0.2, "carry": 0.2}, "text": "a runner strain (+20% speed and carry)"},
		]},
	"puppet": {"name": "Puppet Strings", "icon": "ritual", "tier": 2, "price": 40, "desc": "Your Will regenerates 60% faster.", "mods": {"will_regen": 0.6},
		"hidden": {"mods": {"upkeep": 0.2}}, "hidden_desc": "ants that wait for orders burn 20% more food.", "rumor": "an ant waiting for orders is an ant that is eating.", "reveal": 90.0, "max": 1},
	"antidote": {"name": "Antidote", "icon": "celery_tea", "tier": 2, "price": 45, "desc": "Cures the side effect of one cursed item you own whose effect you have discovered. Refunds 20 food if there is nothing to cure.", "cleanse": true},
	# ---- colony
	"mutagen": {"name": "Mutagen", "icon": "mutation", "tier": 2, "price": 55, "desc": "+10% chance that each egg mutates.", "colony": {"mutation": 0.10}},
	"jelly": {"name": "Royal Jelly", "icon": "jelly", "tier": 2, "price": 50, "desc": "Queen gains +100 max HP and heals fully.", "colony": {"queen_hp": 100.0}},
	"brood": {"name": "Brood Chamber", "icon": "alien_baby", "tier": 2, "price": 55, "desc": "Eggs hatch 20% faster.", "colony": {"hatch": 0.8}, "max": 3},
	"fertile": {"name": "Fertile Queen", "icon": "fertilizer", "tier": 3, "price": 75, "desc": "Eggs cost 1 less food.", "colony": {"egg_cost": -1.0}, "max": 3},
	"entrance": {"name": "Second Entrance", "icon": "compass", "tier": 3, "price": 90, "desc": "Dig a new shaft far from the main one. A siege can't block both.", "colony": {"entrance": 1}, "max": 2},
	"unstable": {"name": "Unstable Genome", "icon": "alien_magic", "tier": 3, "price": 80, "desc": "+20% mutation chance, and mutations often come in pairs.", "colony": {"mutation": 0.2, "double_mut": 0.35}, "max": 1},
	"crown": {"name": "Queen's Crown", "icon": "crown", "tier": 3, "price": 85, "desc": "Queen +50% max HP and regenerates twice as fast.", "colony": {"queen_hp_pct": 0.5}, "mods": {"queen_regen": 1.0}, "max": 1},
	"carapace": {"name": "Ancestral Carapace", "icon": "stone_skin", "tier": 4, "price": 150, "desc": "Every newborn has at least 1 armor on every segment.", "colony": {"base_armor": 1}, "max": 2},
	"hivemind": {"name": "Hive Mind", "icon": "triangle_of_power", "tier": 4, "price": 140, "desc": "Parents are chosen from the fittest 8 instead of 4.", "colony": {"tournament": 4}, "max": 1},
}

const TIER_COLORS = [Color("#d9d9d9"), Color("#d9d9d9"), Color("#5aa9e6"), Color("#b36be0"), Color("#e8583f")]
const TIER_NAMES = ["", "Common", "Uncommon", "Rare", "Legendary"]


static func icon_path(id: String) -> String:
	return ICON % id


static func tier_weights(raid_n: int) -> Array:
	return [0.0, 1.0, 0.15 + 0.1 * raid_n, 0.03 * raid_n, max(0.0, 0.012 * (raid_n - 3))]


# ------------------------------------------------------------------ the Lab between runs (scene/lab.tscn)
# A fallen colony leaves food to the Lab: what it earned (earnings() below) goes into a bank kept in user://infdna_lab.json, with
# the items bought for the next colony (scene/run.gd hands them over when it starts; the run that carried them uses them up).
# Only items with the owner's icon are offered. Everything is optional: if the file cannot be read or written the bank starts empty.
const LAB_PATH = "user://infdna_lab.json"
const LAB_OFFERS = 5


static func has_icon(id: String) -> bool:
	return ResourceLoader.exists(icon_path(id))


# The items the Lab may offer: those that have their picture.
static func lab_pool() -> Array:
	var out := []
	for id in ITEMS.keys():
		if has_icon(id):
			out.append(id)
	return out


# {"bank": food to spend, "items": {id: count} bought for the next colony, "raids": raids the last colony saw (better tiers),
#  "offers": the Lab's current offers ("" = bought), "rerolls": rerolls since the last colony fell (each costs more)}
static func lab_load() -> Dictionary:
	var d = null
	if FileAccess.file_exists(LAB_PATH):
		d = JSON.parse_string(FileAccess.get_file_as_string(LAB_PATH))
	if not (d is Dictionary):
		d = {}
	var items = d.get("items", {})
	var clean := {}
	if items is Dictionary:
		for id in items.keys():
			if ITEMS.has(id) and int(items[id]) > 0:
				clean[id] = int(items[id])
	var offers := []
	var o = d.get("offers", [])
	if o is Array:
		for id in o:
			offers.append(str(id) if (str(id) == "" or ITEMS.has(str(id))) else "")
	return {"bank": int(max(0, int(d.get("bank", 0)))), "items": clean, "raids": int(d.get("raids", 0)), "offers": offers,
		"rerolls": int(d.get("rerolls", 0))}


# A fresh set of offers from the items with icons, rarer tiers likelier after a colony that saw many raids (`raids`).
static func lab_roll(raids: int, items: Dictionary, rng: RandomNumberGenerator) -> Array:
	var tw = tier_weights(raids)
	var pool := []
	var weights := []
	for id in lab_pool():
		var it = ITEMS[id]
		if it.has("max") and int(items.get(id, 0)) >= int(it["max"]):
			continue
		if tw[it["tier"]] <= 0.0:
			continue
		pool.append(id)
		weights.append(tw[it["tier"]])
	var out := []
	while out.size() < LAB_OFFERS and not pool.is_empty():
		var tot := 0.0
		for w in weights:
			tot += w
		var roll = rng.randf() * tot
		var j = weights.size() - 1
		for k in weights.size():
			roll -= weights[k]
			if roll <= 0.0:
				j = k
				break
		out.append(pool[j])
		pool.remove_at(j)
		weights.remove_at(j)
	return out


static func lab_reroll_cost(rerolls: int) -> int:
	return 5 + 4 * rerolls


static func lab_save(d: Dictionary) -> void:
	var f = FileAccess.open(LAB_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))


# The Lab's price: the item's own price, 15% more for each copy already bought for the same colony.
static func lab_price(id: String, have: int) -> int:
	return int(round(float(ITEMS[id]["price"]) * (1.0 + 0.15 * have)))


# What a colony leaves to the Lab when it falls: [[what, food], ...], the total last. Days lived, raids repelled, food hauled,
# the crowd it grew to, winters, and how far it carried the arc.
static func earnings(sim, arc_best: int = 0) -> Array:
	var out := []
	var days = int(sim.time / 420.0 + 0.30) + 1
	out.append(["%d day%s lived" % [days, "" if days == 1 else "s"], 5 * days])
	if sim.raids_repelled > 0:
		out.append(["%d raid%s repelled" % [sim.raids_repelled, "" if sim.raids_repelled == 1 else "s"], 6 * sim.raids_repelled])
	var hauled = int(sim.delivered_total / 200.0)
	if hauled > 0:
		out.append(["%d food hauled" % int(sim.delivered_total), hauled])
	var crowd = int(sim.peak_ants / 8)
	if crowd > 0:
		out.append(["a peak of %d ants" % sim.peak_ants, crowd])
	if sim.winters > 0:
		out.append(["%d winter%s lived through" % [sim.winters, "" if sim.winters == 1 else "s"], 25 * sim.winters])
	var arc = max(arc_best, int(sim.arc_stage))
	if arc > 0:
		out.append(["the arc reached %s" % ["Growing", "Dominion", "Tremors", "The Void"][clamp(arc, 0, 3)], 40 * arc])
	if sim.void_cycles > 0:
		out.append(["%d void%s sealed" % [sim.void_cycles, "" if sim.void_cycles == 1 else "s"], 80 * sim.void_cycles])
	var total := 0
	for e in out:
		total += int(e[1])
	out.append(["total", total])
	return out
