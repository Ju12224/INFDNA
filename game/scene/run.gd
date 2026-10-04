extends RefCounted
# What carries from one screen to the next within a play session: the queen picked on the title screen, what the last colony
# passed on, the Lab items bought for the next colony, and the colony that just ended (for the end-of-run screen). Static, so every
# screen reads the same values.
#
# A run goes: title (scene/title.tscn: pick a queen) -> colony (scene/colony.tscn) -> collapse -> end of run (scene/run_end.tscn:
# what happened, the heirloom pick, the Wild) -> the Lab (scene/lab.tscn: spend what the run earned) -> title again for the next queen.

const ShopItems = preload("res://core/shop_items.gd")

const TITLE = "res://scene/title.tscn"
const COLONY = "res://scene/colony.tscn"
const RUN_END = "res://scene/run_end.tscn"
const LAB = "res://scene/lab.tscn"

static var queen_id := "well_rounded"
static var heirloom := {}     # legacy trait carried into the next colony (core/legacy.gd)
static var kin := {}          # the lost colony that comes back as a rival (core/wild.gd)
static var last_sim = null    # the colony that just collapsed or finished
static var items := {}        # Lab item id -> count, bought between runs for the colony being played or the next one (core/shop_items.gd)


# Hands the Lab items to a new colony, as if it had bought them on its first second. Call it right after Sim.new(); it does
# nothing the second time for the same colony, so more than one caller is safe.
static func equip(sim) -> void:
	if sim == null or sim.has_meta("run_equipped"):
		return
	sim.set_meta("run_equipped", true)
	for id in items.keys():
		if not ShopItems.ITEMS.has(id):
			continue
		for i in int(items[id]):
			sim.owned[id] = int(sim.owned.get(id, 0)) + 1
			sim._apply_item(id)
	if not items.is_empty():
		var names := []
		for id in items.keys():
			if ShopItems.ITEMS.has(id):
				names.append(ShopItems.ITEMS[id]["name"] + ("" if int(items[id]) == 1 else " x%d" % int(items[id])))
		sim.toasts.append({"text": "From the Lab: %s." % ", ".join(PackedStringArray(names)), "t": 8.0})
