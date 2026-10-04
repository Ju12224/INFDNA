extends RefCounted
# Queen roster (M5). Every queen is a Brotato character reinterpreted as the
# founder of a colony: a starting-genome bias plus ONE rule that bends how the
# colony works. No Brotato dependencies here (icon paths are only strings).
#
# Entry keys:
#   name, tag        display name and a one-line identity
#   icon             Brotato character id ("dlc:" prefix = Abyssal Terrors)
#   color            body colour of the founder ants
#   rule_text        what the rule does, in plain words
#   body             founder body ops (see apply_body): armor spikes claws tentacle
#                    legs size jaw eyes antenna segment
#   traits           founder behaviour genes, added to the defaults (see genome.gd)
#   bias/trait/colony/mods   same keys as shop_items.gd, applied at start
#   rule             {key: value} rule keys implemented in colony_sim.gd (see rule())
#                    lifesteal revive blood_eggs growth no_tunnel_penalty rot_mult
#                    lab_offers free_reroll lab_luck twin wounded_fury reach zap
#                    zap_targets farm_boost fruit_boost prey_boost tame dig_jobs
#                    cap_per_chamber caste_bias bloodlust wild_hatch undead
#                    start_food raid_mutation start_entrance

const Genome = preload("res://core/genome.gd")
const ICON = "res://art/queens/%s.png"     # the owner's drawing for each queen (not drawn yet: see docs/icons_needed.md)

static func icon_path(q: Dictionary) -> String:
	return ICON % q["id"]


# id -> entry. Order here is the order on the select screen.
# The eight queens offered on the title screen (owner's call: eight detailed queens, the rest later). Each plays differently:
# the plain baseline, fighting that heals, farming, digging, lightning, armour, evolution and long expeditions.
const FEATURED = ["well_rounded", "vampire", "farmer", "dwarf", "mage", "knight", "mutant", "explorer"]


static func featured() -> Array:
	var r := []
	for id in FEATURED:
		r.append(find(id))
	return r


static func roster() -> Array:
	var r := []
	r.append(_q("well_rounded", "The Founder", "#8a4b2e", "The plain queen. No perks, no flaws.",
		"No rule. The baseline to measure the others against.", {}))
	# ---------------------------------------------------------------- rule-benders
	r.append(_q("vampire", "Bloodmother", "#7a1f2b", "Her brood drinks what it bites.",
		"Defenders heal 35% of the damage they deal.",
		{"rule": {"lifesteal": 0.35}, "mods": {"upkeep": 0.1}}))
	r.append(_q("ghost", "Wraith Queen", "#8fa3c9", "Half in the grave already.",
		"The first time each ant would die in battle, 25% chance it rises with 35% HP.",
		{"rule": {"revive": 0.25}, "mods": {"hp": -0.2}}))
	r.append(_q("demon", "Pact Queen", "#a8322d", "Eggs are cheap if you pay in blood.",
		"When food runs low she lays eggs for 8 of her own HP instead. +100 queen HP.",
		{"rule": {"blood_eggs": 8.0}, "colony": {"queen_hp": 100.0}}))
	r.append(_q("lich", "Bone Queen", "#c9cfa0", "Nothing in her nest stays dead.",
		"40% of ants that fall in battle come back as an egg for free. Ants live 20% shorter.",
		{"rule": {"undead": 0.4}, "mods": {"life": -0.2}}))
	r.append(_q("apprentice", "Apprentice Queen", "#6b5a8e", "Learns from every raid.",
		"Each repelled raid: every ant +4% HP and attack, permanently.",
		{"rule": {"growth": 0.04}}))
	r.append(_q("gladiator", "Arena Queen", "#c9a13b", "The crowd feeds the fighters.",
		"Every kill gives every ant +0.6% attack, up to +50%. Ants eat 10% more.",
		{"rule": {"bloodlust": 0.006}, "mods": {"upkeep": 0.1}}))
	r.append(_q("baby", "Brood Mother", "#e8c9a0", "Twins, always twins.",
		"50% of eggs come as twins for 1.5x the cost. Ants have 15% less HP.",
		{"rule": {"twin": 0.5}, "mods": {"hp": -0.15}}))
	r.append(_q("romantic", "Romantic Queen", "#e07aa8", "She loves her clutch to death.",
		"35% twin eggs, eggs cost 1 less, and hatch 15% faster.",
		{"rule": {"twin": 0.35}, "colony": {"egg_cost": -1.0, "hatch": 0.85}}, true))
	r.append(_q("crazy", "Mad Queen", "#7a3d6b", "Some of her eggs are... unexpected.",
		"12% of eggs hatch as a wild genome (four stacked mutations). +25% mutation chance.",
		{"rule": {"wild_hatch": 0.12}, "colony": {"mutation": 0.25, "double_mut": 0.3}}))
	r.append(_q("mutant", "Chimera Queen", "#3d6b3a", "Her colony is never quite the same twice.",
		"Each repelled raid raises mutation chance by 3%. Starts +25%; favors size, armor, segments.",
		{"rule": {"raid_mutation": 0.03}, "colony": {"mutation": 0.25}, "bias": {"size": 0.8, "armor": 0.8, "segment": 0.8}}))
	r.append(_q("beast_master", "Beast Queen", "#8a6a3a", "Everything in her tunnels is livestock.",
		"35% of raiders killed underground are tamed: a free egg appears.",
		{"rule": {"tame": 0.35}}))
	r.append(_q("mage", "Storm Queen", "#5a7ad0", "The air over her nest crackles.",
		"Every 5 s lightning hits 2 random raiders for 12 damage. Ants have 10% less HP.",
		{"rule": {"zap": 12.0, "zap_targets": 2}, "mods": {"hp": -0.1}}))
	r.append(_q("technomage", "Arc Queen", "#3fa7b8", "Wired into the colony.",
		"Every 5 s lightning hits 3 raiders for 8 damage. +10% mutation chance.",
		{"rule": {"zap": 8.0, "zap_targets": 3}, "colony": {"mutation": 0.1}}))
	r.append(_q("hunter", "Hunt Queen", "#5a7a3a", "Her soldiers strike before they are struck.",
		"Ants hit from 60% farther away. Raiders drop 30% more food.",
		{"rule": {"reach": 1.6}, "mods": {"kill_food": 0.3}}))
	r.append(_q("ranger", "Spitting Queen", "#7aa85a", "Acid at range.",
		"Ants hit from 120% farther away, but 10% weaker. Foragers sense 6 farther.",
		{"rule": {"reach": 2.2}, "mods": {"attack": -0.1, "sense": 6.0}}))
	r.append(_q("saver", "Vault Queen", "#c9a13b", "Nothing is ever wasted.",
		"Surplus food rots 65% slower. +25 storage per chamber. +10% interest per repelled raid.",
		{"rule": {"rot_mult": 0.35, "cap_per_chamber": 25.0}, "mods": {"interest": 0.1}}))
	r.append(_q("builder", "Mason Queen", "#b0794a", "Bigger pantries, sturdier walls.",
		"+35 storage per chamber. Diggers work 15% faster.",
		{"rule": {"cap_per_chamber": 35.0}, "mods": {"dig": 0.15}}, true))
	r.append(_q("engineer", "Engineer Queen", "#e8a13b", "Three tunnels at once.",
		"Three dig jobs run at once, and digging is 40% faster. Ants carry 10% less.",
		{"rule": {"dig_jobs": 3}, "mods": {"dig": 0.4, "carry": -0.1}}))
	r.append(_q("dwarf", "Delver Queen", "#8a5a2a", "The mountain is her mother.",
		"Big bodies move at full speed in tunnels. Dig 60% faster, three jobs at once.",
		{"rule": {"no_tunnel_penalty": 1, "dig_jobs": 3}, "mods": {"dig": 0.6}}, true))
	r.append(_q("bull", "Bull Queen", "#a84a2d", "Nothing fits, so she makes it fit.",
		"Big bodies move at full speed in tunnels. Founders are larger. Ants eat 15% more.",
		{"rule": {"no_tunnel_penalty": 1}, "body": {"size": 8}, "mods": {"upkeep": 0.15}}))
	r.append(_q("diver", "Depth Queen", "#2f6a8a", "At home in the dark.",
		"No tunnel slowdown. Raiders inside tunnels take 5 damage per second.",
		{"rule": {"no_tunnel_penalty": 1}, "mods": {"tunnel_dmg": 5.0, "upkeep": 0.1}}, true))
	r.append(_q("farmer", "Farmer Queen", "#6cc644", "Her fungus gardens are legendary.",
		"Fungus farms make 60% more food. Fruit trees drop twice as often. Ants hit 15% weaker.",
		{"rule": {"farm_boost": 1.6, "fruit_boost": 2.0}, "mods": {"attack": -0.15}}))
	r.append(_q("chef", "Gourmet Queen", "#e8dcc4", "Every scrap becomes a feast.",
		"Fungus farms make double food. +20 storage per chamber.",
		{"rule": {"farm_boost": 2.0, "cap_per_chamber": 20.0}}, true))
	r.append(_q("druid", "Grove Queen", "#4a8a3a", "The trees answer to her.",
		"Fruit trees drop 3x as often. Farms +30%. Wounded ants heal 1 HP/s in the nest.",
		{"rule": {"fruit_boost": 3.0, "farm_boost": 1.3}, "mods": {"regen": 1.0}}, true))
	r.append(_q("fisherman", "Angler Queen", "#3a8ab8", "She lures the wanderers in.",
		"Prey (looters) appear twice as often and give 50% more food. Sense +4.",
		{"rule": {"prey_boost": 2.0}, "mods": {"sense": 4.0}}))
	r.append(_q("sailor", "Tide Queen", "#4a6ab8", "Storms bring wrecks.",
		"Prey appear 1.6x as often and give 30% more food. Raiders sieging the entrance take 3 damage per second.",
		{"rule": {"prey_boost": 1.6}, "mods": {"siege_dmg": 3.0}}, true))
	r.append(_q("buccaneer", "Pirate Queen", "#c93a2d", "Raiders are just deliveries.",
		"Raiders drop 50% more food, prey appear 1.5x as often (25% more food), food piles 25% richer.",
		{"rule": {"prey_boost": 1.5}, "mods": {"kill_food": 0.5, "pile_rich": 0.25}}, true))
	r.append(_q("lucky", "Lucky Queen", "#6cc644", "The Lab likes her.",
		"Better tier odds in the Lab, and the first reroll each visit is free.",
		{"rule": {"lab_luck": 1.0, "free_reroll": 1}}))
	r.append(_q("streamer", "Viral Queen", "#b46be0", "Everyone is watching the reroll button.",
		"Two free rerolls per Lab visit, and rerolls cost 3 less.",
		{"rule": {"free_reroll": 2}, "mods": {"reroll_disc": 3.0}}))
	r.append(_q("arms_dealer", "Arms Dealer", "#6a6a7a", "Six offers on the table.",
		"The Lab shows 6 offers instead of 4, but everything costs 10% more.",
		{"rule": {"lab_offers": 2}, "mods": {"price_disc": -0.1}}))
	r.append(_q("jack", "Jack Queen", "#c9a13b", "Starts rich, spends fast.",
		"Starts with +120 food. The Lab shows 5 offers.",
		{"rule": {"start_food": 120.0, "lab_offers": 1}}))
	r.append(_q("curious", "Curious Queen", "#e8c96a", "She has to press every button.",
		"Better Lab tier odds. +10% mutation chance. Foragers sense 5 farther.",
		{"rule": {"lab_luck": 0.5}, "colony": {"mutation": 0.1}, "mods": {"sense": 5.0}}, true))
	r.append(_q("vagabond", "Wanderer Queen", "#8a7a5a", "Never lives behind one door.",
		"Starts with a second entrance already dug. Sense +3.",
		{"rule": {"start_entrance": 1}, "mods": {"sense": 3.0}}))
	r.append(_q("soldier", "General Queen", "#a83a2d", "Her brood is mostly soldiers.",
		"Far more of the brood is raised as soldiers. Ants hit 15% harder; newborns join fights early.",
		{"rule": {"caste_bias": [0.6, 0.6, 2.0]}, "mods": {"attack": 0.15}, "trait": {"defend_t": -0.05}}))
	r.append(_q("captain", "Captain Queen", "#2f5f7a", "Orders carry down the tunnels.",
		"More soldiers, defenders hit 30% harder, and parents come from the fittest 6.",
		{"rule": {"caste_bias": [0.8, 0.8, 1.6]}, "mods": {"defend_attack": 0.3}, "colony": {"tournament": 2}}, true))
	r.append(_q("king", "Sovereign", "#f2c14e", "The throne room is the strongest room.",
		"Queen +150 HP. Defenders hit 30% harder.",
		{"colony": {"queen_hp": 150.0}, "mods": {"defend_attack": 0.3}}))
	r.append(_q("gangster", "Boss Queen", "#4a3a5a", "Everyone pays their tithe.",
		"Raiders drop 40% more food. Defenders hit 25% harder.",
		{"mods": {"kill_food": 0.4, "defend_attack": 0.25}}, true))
	r.append(_q("wounded", "Scarred Queen", "#8a2d2d", "Pain is a weapon.",
		"Ants below half HP deal double damage. Ants have 25% less HP.",
		{"rule": {"wounded_fury": 1.0}, "mods": {"hp": -0.25}}))
	r.append(_q("masochist", "Thorn Queen", "#7a3d3d", "Hurt me. Go on.",
		"Ants below half HP deal 50% more damage. Spikes hit back 2.5x as hard.",
		{"rule": {"wounded_fury": 0.5}, "mods": {"thorns": 1.5, "hp": -0.1}, "bias": {"spike": 0.8}}))
	# ---------------------------------------------------------------- body/stat queens
	r.append(_q("knight", "Iron Queen", "#8a8a9a", "Plated from the first egg.",
		"Founders have armor on every segment. Ants ignore 14% more damage but move 10% slower.",
		{"body": {"armor": 1}, "mods": {"armor": 0.14, "speed": -0.1}, "colony": {"base_armor": 1}}))
	r.append(_q("cyborg", "Chrome Queen", "#7a9ab8", "Half machine, all appetite.",
		"Every newborn has armor. Ants eat 25% more. Mutations are 10% rarer.",
		{"colony": {"base_armor": 1, "mutation": -0.1}, "mods": {"armor": 0.05, "upkeep": 0.25}}))
	r.append(_q("golem", "Stone Queen", "#a89a8a", "Slow, deep, unmoving.",
		"Queen HP x2. Ants have 30% more HP but move 15% slower.",
		{"colony": {"queen_hp_pct": 1.0}, "mods": {"hp": 0.3, "speed": -0.15}}))
	r.append(_q("chunky", "Heavy Queen", "#b0794a", "Big eaters, big carriers.",
		"Founders are much larger. +40% HP, +20% carry, 10% slower.",
		{"body": {"size": 10}, "mods": {"hp": 0.4, "carry": 0.2, "speed": -0.1}}))
	r.append(_q("ogre", "Ogre Queen", "#6a8a3a", "Nothing small about her.",
		"Founders are huge. +30% attack, +30% carry, 20% slower.",
		{"body": {"size": 12, "spikes": 1}, "mods": {"attack": 0.3, "carry": 0.3, "speed": -0.2}}, true))
	r.append(_q("speedy", "Sprint Queen", "#3fb8a8", "Late for everything.",
		"Ants move 25% faster but have 15% less HP and eat 10% more.",
		{"body": {"legs": 1}, "mods": {"speed": 0.25, "hp": -0.15, "upkeep": 0.1}}))
	r.append(_q("wildling", "Feral Queen", "#8a6a3a", "Lean, fast, half wild.",
		"Ants move 15% faster, sense 6 farther, eat 10% less. HP -10%.",
		{"mods": {"speed": 0.15, "sense": 6.0, "upkeep": -0.1, "hp": -0.1}}))
	r.append(_q("explorer", "Scout Queen", "#c9a13b", "Always over the next hill.",
		"Foragers sense 10 farther and food piles are 35% richer. HP -10%.",
		{"mods": {"sense": 10.0, "pile_rich": 0.35, "hp": -0.1}, "traits": {"explore": 0.2}}))
	r.append(_q("hiker", "Trail Queen", "#7a8a4a", "Long roads, long legs.",
		"Founders have longer legs. Ants move 10% faster and sense 8 farther.",
		{"body": {"legs": 1}, "mods": {"speed": 0.1, "sense": 8.0}}, true))
	r.append(_q("glutton", "Glutton Queen", "#e8a13b", "Eats for the whole colony.",
		"Ants carry 50% more but eat 35% more. Starts with +40 food.",
		{"rule": {"start_food": 40.0}, "mods": {"carry": 0.5, "upkeep": 0.35}}))
	r.append(_q("old", "Elder Queen", "#a89a8a", "Slow to lay, slow to die.",
		"Ants live 50% longer. Eggs hatch 30% slower.",
		{"mods": {"life": 0.5}, "colony": {"hatch": 1.3}}))
	r.append(_q("sick", "Plague Queen", "#8aa84a", "Feverish and fertile.",
		"+30% mutation chance. Ants live 25% shorter and have toxic spines.",
		{"colony": {"mutation": 0.3}, "mods": {"life": -0.25, "thorns": 1.0}, "body": {"spikes": 1}}))
	r.append(_q("pacifist", "Peace Queen", "#a8d0a8", "Raiders find fewer reasons to come.",
		"Raids bring 40% fewer raiders. Ants hit 30% weaker but have 20% more HP.",
		{"mods": {"raid_size": -0.4, "attack": -0.3, "hp": 0.2}}))
	r.append(_q("cryptid", "Shadow Queen", "#3a4a5a", "The nest that isn't there.",
		"Raids bring 30% fewer raiders. Ants carry 10% less.",
		{"mods": {"raid_size": -0.3, "carry": -0.1}}))
	r.append(_q("renegade", "Renegade Queen", "#c93a2d", "Bring more. She'll take it all.",
		"Raids bring 20% more raiders. Raiders drop 60% more food.",
		{"mods": {"raid_size": 0.2, "kill_food": 0.6}}))
	r.append(_q("loud", "Loud Queen", "#e8c93a", "Everything hears her.",
		"Food piles appear close to the nest. Raids bring 15% more raiders.",
		{"mods": {"pile_near": 1.0, "raid_size": 0.15}}))
	r.append(_q("entrepreneur", "Merchant Queen", "#c9a13b", "Food is capital.",
		"+20% interest per repelled raid, Lab prices 10% lower. Ants have 10% less HP.",
		{"mods": {"interest": 0.2, "price_disc": 0.1, "hp": -0.1}}))
	r.append(_q("doctor", "Healer Queen", "#8ad0c9", "Nothing stays wounded.",
		"Wounded ants heal 3 HP/s in the nest. Queen regenerates twice as fast. Ants hit 10% weaker.",
		{"mods": {"regen": 3.0, "queen_regen": 1.0, "attack": -0.1}}))
	r.append(_q("artificer", "Trapper Queen", "#e8a13b", "Every tunnel is a snare.",
		"Raiders in tunnels take 4 damage per second, sieging raiders take 3. Ants hit 10% weaker.",
		{"mods": {"tunnel_dmg": 4.0, "siege_dmg": 3.0, "attack": -0.1}}))
	r.append(_q("brawler", "Brawler Queen", "#c93a2d", "Fists first.",
		"Founders have a claw. Ants hit 30% harder with 10% more HP but carry 15% less.",
		{"body": {"claws": 1}, "mods": {"attack": 0.3, "hp": 0.1, "carry": -0.15}}))
	r.append(_q("one_arm", "Lone Claw", "#a83a2d", "One big claw and a big grudge.",
		"Founders have a claw jaw. Ants dig and hit 25% harder but carry 20% less.",
		{"body": {"jaw": "claw"}, "mods": {"attack": 0.25, "dig": 0.25, "carry": -0.2}}))
	r.append(_q("creature", "Tentacle Queen", "#7a3d9a", "Something is wrong with her children.",
		"Founders have tentacles. Mutations strongly favor tentacles. Ants carry 20% more.",
		{"body": {"tentacle": 1}, "bias": {"tentacle": 1.5}, "mods": {"carry": 0.2}}, true))
	r.append(_q("multitasker", "Swarm Queen", "#6b7a8e", "Every ant does a bit of everything.",
		"Ants carry, dig and move 12% better but have 10% less HP.",
		{"mods": {"carry": 0.12, "dig": 0.12, "speed": 0.12, "hp": -0.1}}))
	r.append(_q("generalist", "Generalist Queen", "#8a8a6a", "Good at everything, great at nothing.",
		"All ant stats +8%.",
		{"mods": {"hp": 0.08, "attack": 0.08, "speed": 0.08, "carry": 0.08, "dig": 0.08}}))
	return r


static func _q(id: String, name: String, color: String, tag: String, rule_text: String, fx: Dictionary, dlc: bool = false) -> Dictionary:
	var q := {"id": id, "name": name, "tag": tag, "rule_text": rule_text, "icon": ("dlc:" + id) if dlc else id,
		"color": color, "dlc": dlc, "body": {}, "traits": {}, "bias": {}, "trait": {}, "colony": {}, "mods": {}, "rule": {}}
	for k in fx.keys():
		q[k] = fx[k]
	return q


static func find(id: String) -> Dictionary:
	for q in roster():
		if q["id"] == id:
			return q
	return roster()[0]


# Founder body tweaks (all ops are relative to the plain ant in genome.gd).
static func apply_body(g, body: Dictionary) -> void:
	var segs: Array = g.segments
	if body.has("size"):
		for s in segs:
			s["r"] = clamp(s["r"] + body["size"], 12.0, 46.0)
	if body.has("armor"):
		for s in segs:
			s["armor"] = int(max(s["armor"], body["armor"]))
	if body.has("spikes"):
		segs[0]["spikes"] = int(segs[0]["spikes"] + body["spikes"])
		segs[1]["spikes"] = int(segs[1]["spikes"] + body["spikes"])
	if body.has("legs"):
		segs[1]["n"] = int(clamp(segs[1]["n"] + body["legs"], 1, 4))
		segs[1]["len"] = clamp(segs[1]["len"] + 8.0 * body["legs"], 25.0, 90.0)
	if body.has("claws"):
		segs[0]["limb"] = "claw"
		segs[0]["n"] = int(body["claws"])
		segs[0]["len"] = 45.0
	if body.has("tentacle"):
		segs[0]["limb"] = "tentacle"
		segs[0]["n"] = int(body["tentacle"]) + 1
		segs[0]["len"] = 50.0
	var h: Dictionary = g.head()
	if body.has("jaw"):
		h["jaw"] = body["jaw"]
	if body.has("eyes"):
		h["eyes"] = int(body["eyes"])
	if body.has("antenna"):
		h["antenna"] = float(body["antenna"])
	if body.has("segment"):
		var dup: Dictionary = segs[0].duplicate(true)
		dup.erase("head")
		dup.erase("crown")
		segs.insert(0, dup)


# The queen's own body, as the select screen and the colony both draw her.
static func make_queen_genome(q: Dictionary):
	var g = Genome.make_queen()
	g.color = Color(q["color"]).darkened(0.12)
	apply_body(g, q["body"])
	return g
