extends Reference
# Raid roster. Stats only; textures are candidate paths (first one that exists
# wins), so Abyssal Terrors crustaceans are used when the DLC is installed and
# base-game aliens otherwise.
#
# Classes:
#   small - runners: go down the shaft and attack the queen
#   burrower - bores its OWN tunnel from the surface straight to the queen chamber
#   brute / elite / boss - surface siegers: camp the entrance, then leave

const DEFS = {
	"baby": {"name": "Baby Alien", "hp": 30.0, "dmg": 2.0, "speed": 3.4, "cls": "small", "food": 6.0, "cost": 1,
		"tex": ["res://entities/units/enemies/baby_alien/baby_alien.png"]},
	"fly": {"name": "Fly", "hp": 20.0, "dmg": 1.6, "speed": 5.2, "cls": "small", "food": 4.0, "cost": 1,
		"tex": ["res://entities/units/enemies/fly/fly.png"]},
	"shrimp": {"name": "Shrimp", "hp": 36.0, "dmg": 2.2, "speed": 4.2, "cls": "small", "food": 7.0, "cost": 1,
		"tex": ["res://dlcs/dlc_1/enemies/shrimp/shrimp.png", "res://entities/units/enemies/chaser/chaser.png"]},
	"charger": {"name": "Charger", "hp": 90.0, "dmg": 4.5, "speed": 4.4, "cls": "brute", "food": 16.0, "cost": 3,
		"tex": ["res://entities/units/enemies/charger/charger.png"]},
	"helmet": {"name": "Helmet Alien", "hp": 130.0, "dmg": 4.0, "speed": 2.6, "cls": "brute", "food": 18.0, "cost": 3,
		"tex": ["res://entities/units/enemies/helmet_alien/helmet_alien.png"]},
	"crab": {"name": "Crab", "hp": 150.0, "dmg": 5.0, "speed": 2.8, "cls": "brute", "food": 20.0, "cost": 3,
		"tex": ["res://dlcs/dlc_1/enemies/crab/crab.png", "res://entities/units/enemies/slasher/slasher.png"]},
	"bruiser": {"name": "Bruiser", "hp": 280.0, "dmg": 8.0, "speed": 2.0, "cls": "elite", "food": 40.0, "cost": 7,
		"tex": ["res://entities/units/enemies/bruiser/bruiser.png"]},
	"isopod": {"name": "Giant Isopod", "hp": 380.0, "dmg": 7.5, "speed": 1.5, "cls": "elite", "food": 50.0, "cost": 8,
		"tex": ["res://dlcs/dlc_1/enemies/giant_isopod/giant_isopod.png", "res://entities/units/enemies/horned_bruiser/horned_bruiser.png"]},
	"borer": {"name": "Tunnel Borer", "hp": 190.0, "dmg": 7.0, "ant_mult": 0.3, "speed": 2.8, "cls": "burrower", "food": 24.0, "cost": 4, "spine": "worm_strip.png",
		"tex": ["res://entities/units/enemies/lamprey/lamprey.png", "res://dlcs/dlc_1/enemies/impaled_worm/impaled_worm.png"]},
	"butcher": {"name": "Butcher", "hp": 700.0, "dmg": 15.0, "speed": 1.7, "cls": "boss", "food": 140.0, "cost": 18,
		"tex": ["res://entities/units/enemies/butcher/butcher.png"]},

	# v0.23 wildlife: drawn procedurally (content/colony/creature_art.gd), so no textures needed
	"spider": {"name": "Spider", "hp": 170.0, "dmg": 5.5, "speed": 3.0, "cls": "brute", "food": 24.0, "cost": 3, "tex": [], "art": "spider"},
	"bee": {"name": "Bee", "hp": 22.0, "dmg": 1.7, "speed": 5.8, "cls": "small", "food": 5.0, "cost": 1, "tex": [], "art": "bee", "art_scale": 0.55, "fly": true},
	"hornet": {"name": "Hornet", "hp": 300.0, "dmg": 7.0, "speed": 4.6, "cls": "elite", "food": 46.0, "cost": 7, "tex": [], "art": "hornet", "art_scale": 0.85, "fly": true},

	# v0.29: the anteater is not part of a raid roster. It lumbers in now and then (colony_sim._step_anteater): slow, shaggy
	# and huge, it sieges the entrance and licks ants off the ground with its tongue.
	# v0.34: the Void Maw, the owner's drawn boss (art in content/art, rigged in content/colony/rig_art.gd). From the second boss raid on it comes in place of the Butcher.
	"voidmaw": {"name": "Void Maw", "hp": 1000.0, "dmg": 10.0, "ant_mult": 0.5, "speed": 1.4, "cls": "boss", "food": 260.0, "cost": 22, "tex": [], "art": "voidmaw", "art_scale": 1.0, "h": 215.0},

	"anteater": {"name": "Anteater", "hp": 1000.0, "dmg": 6.5, "ant_mult": 0.3, "speed": 1.5, "cls": "boss", "food": 190.0, "cost": 18, "tex": [], "art": "anteater"},

	# v0.29: the rival colony's ants (drawn procedurally, bigger for the heavier castes)
	"redant": {"name": "Red Ant", "hp": 34.0, "dmg": 2.4, "speed": 4.2, "cls": "small", "food": 7.0, "cost": 1, "tex": [], "art": "redant", "art_scale": 0.46},
	"redsoldier": {"name": "Red Soldier", "hp": 140.0, "dmg": 4.8, "speed": 2.8, "cls": "brute", "food": 18.0, "cost": 3, "tex": [], "art": "redant", "art_scale": 0.62},
	"redmajor": {"name": "Red Major", "hp": 330.0, "dmg": 7.5, "speed": 2.0, "cls": "elite", "food": 44.0, "cost": 7, "tex": [], "art": "redant", "art_scale": 0.84},

	# passive prey (not raiders): wanders the surface, flees ants, big food when hunted
	"looter": {"name": "Looter", "hp": 45.0, "dmg": 0.0, "speed": 3.0, "cls": "prey", "food": 24.0, "cost": 0,
		"tex": ["res://dlcs/dlc_1/enemies/looting_pig/looting_pig.png", "res://entities/units/enemies/looter/looter.png"]},
}

const SMALL = ["baby", "fly", "shrimp", "bee"]
const BRUTE = ["charger", "helmet", "crab", "spider"]
const ELITE = ["bruiser", "isopod", "hornet"]

# Reach in cells, by class
const REACH = {"small": 1.6, "burrower": 1.9, "brute": 2.4, "elite": 3.0, "boss": 3.6, "prey": 1.8}
# On-screen height in pixels, by class
const HEIGHT = {"small": 34.0, "burrower": 50.0, "brute": 58.0, "elite": 96.0, "boss": 140.0, "prey": 42.0}


# A raider's height: its own "h" when its definition has one (the Void Maw is far bigger than the Butcher), else its class's.
static func height_of(e) -> float:
	return float(e.def.get("h", HEIGHT[e.cls]))
