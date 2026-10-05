extends Node2D
# The nest's rooms and the anthill, drawn between the soil (z 20) and the ants (z 40), only with the owner's pictures:
#   rooms    - what each chamber of the sim (core/nest_planner.gd chambers, the queen's chamber of world_grid.gd) is for shows in
#              what stands on its floor: food piles in the stores (as many as the larder is full), fungus in the farms, a refuse
#              heap in the middens, and the owner's nest props (art/props, props_manifest.json) as the colony grows. Zoomed out,
#              each room shows its chamber icon (art/ui/chamber_*.png) at a steady size on screen instead.
#   brood    - every egg of the sim where it was laid, in its true colour (never the ants' tint), going through its stages as it
#              counts down to the hatch: a clutch of eggs, a grub that fattens and wriggles, a silk cocoon that twitches near the end
#              (antkit egg_*, larva_*, cocoon_*; a winged cocoon for a winged ant, a grey one for a soldier).
#   anthill  - the owner's mound (art/anthill) over each nest mouth, standing on the top of the spoil heap on the front lip, the floor
#              of its hole on the mouth. The main mouth's mound grows (small, medium, large) with the spoil carried up.
# Ported from the Godot 3 mod (nest_decor.gd: the props and their rules; world_view.gd: the brood stages; layers_view.gd: the chamber
# badges). Its drawn shapes (roots, drips, glowing fungus, light shafts, the lantern glow) have no picture and are left out.
#
# Props rules (deterministic: a room's things and their spots come from fixed lists and a seed made from its position):
#   milestone level 0..5 (_tier): the middle three of four progress measures (peak ants, raids, generations, nest levels open),
#     each counted against five thresholds. It never goes down, so nothing the colony made disappears.
#     1 wood (planks, logs, crates)  2 carpentry (barrels, ladders, frames)  3 iron tools (buckets, anvils, helmets)
#     4 machinery (gears, chains, pulleys, lanterns)  5 foundry (trusses, corrugated sheet, saws)
#   stores: food piles by how full the larder is, crates and barrels from level 1; other rooms: their own kit (ROOM_KIT), one more
#     thing per level; deep rooms (nest level 5+) get iron gear from level 4; nurseries a bucket with the Medikit, armories a riveted
#     helmet with any armour item
#   the entrance hall (the first floors under the main mouth): a palisade after the first raid, a gate after the third, a spike
#     barricade after the fifth (or with the barricade), crossed stakes after the seventh (or with landmines), a cage after the
#     eighth; other mouths get a fence after the first raid
#   shafts: from level 2 a ladder at the foot of the tallest straight shafts; a pickaxe beside some with a digging item from the Lab;
#     from level 4 a pulley hangs over the tallest two
#   the queen's chamber: a barrel and the guards' shield and helmet from level 2, a hanging lantern from level 4
# Nothing floats: each thing stands on floor cells (open, solid under it) that are level within a cell across the middle of its
# width and have the headroom for it (it may shrink to 72% to fit, never more); hanging things hang from a ceiling cell. The list
# is rebuilt only when the rooms, the level, the larder, the raids or the Lab items change; drawing it is one picture per thing in view.

const Art = preload("res://scene/art.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const C = WorldGrid.CELL
const ANT_PX = 25.0            # an ordinary worker underground, nose to tail (units_view.gd: size 74 comes out about 24.7 px)
const PROP_WORKER = 40.0       # props_manifest game sizes are for a worker this long (its worker_ref_px)
const CHECK_EVERY = 0.5        # seconds between checks of what the props depend on
const BUILD_MS = 2.0           # rebuilding furnishing stops for the frame once it has taken this long (after one unit at least)
const REFRESH_EVERY = 20.0     # ... and between rebuilds for tunnels dug through floors since
const MARGIN = 120.0           # world px past the view a room's things can still reach into it

# ---- room contents that are not props: [picture under art/, long side in world px for an ANT_PX worker]
const STOCK = {
	"food_pile": ["ui/food_pile.png", 21.0],
	"fungus": ["ui/fungus.png", 19.0],
	"midden": ["ui/midden.png", 21.0],
}
const PILE_W = 22.0            # floor width (px) one food pile takes in a store
const MAX_PILES = 4
const FUNGUS_W = 22.0
const MAX_FUNGUS = 3

# ---- props
const ITEM_TIER = {
	"plank": 1, "planks": 1, "log": 1, "firewood": 1, "post": 1, "stake": 1, "branch": 1, "stump": 1, "rope_coil": 1, "crate": 1,
	"barrel": 2, "ladder": 2, "cable_spool": 2, "cart": 2, "scaffold": 2, "ramp": 2, "rope_spool": 2, "signpost": 2, "frame": 2,
	"fence": 2, "palisade": 2, "x_stakes": 2, "spike_barricade": 2, "net": 2,
	"bucket": 3, "anvil": 3, "pickaxe_head": 3, "trowel": 3, "crowbar": 3, "pliers": 3, "saw_blade": 3, "helmet": 3,
	"helmet_riveted": 3, "shield": 3, "gate": 3, "cage": 3, "iron_bar": 3, "rusty_plate": 3,
	"gear": 4, "chain": 4, "chain_short": 4, "pulley": 4, "block_hook": 4, "girder": 4, "pipe": 4, "elbow_pipe": 4,
	"wire_coil": 4, "spring": 4, "lantern_cage": 4,
	"truss": 5, "corrugated": 5, "grate": 5, "plate": 5, "circular_saw": 5,
}
const ROOM_KIT = {
	"food": ["crate", "barrel", "crate", "bucket", "barrel", "crate", "barrel"],
	"brood": ["planks", "frame", "bucket", "rope_coil"],
	"farm": ["plank", "bucket", "trowel", "firewood"],
	"midden": ["branch", "stump", "rusty_plate", "saw_blade", "corrugated"],
	"armory": ["stake", "shield", "helmet", "anvil", "helmet_riveted"],
	"cistern": ["barrel", "bucket", "pipe", "elbow_pipe"],
	"venom": ["barrel", "bucket", "pipe", "wire_coil"],
	"battery": ["stake", "x_stakes", "crowbar", "spike_barricade"],
	"architects": ["planks", "signpost", "scaffold", "frame", "truss"],
	"queen": ["barrel", "shield", "helmet"],
}
const WORKSHOPS = ["armory", "cistern", "venom", "battery", "architects"]
const DEEP_IRON = ["gear", "chain", "girder", "wire_coil", "spring", "circular_saw"]
const LAB_KEYS = ["barricade", "landmines", "piggy", "tools", "dynamite", "burrow", "helmet", "glass", "vest", "tardigrade", "medikit"]
const PROP_OVERLAP = 0.25      # share of the narrower of two neighbours they may overlap
const MAX_LADDERS = 7
const LADDER_RUN = 7           # straight open cells above a floor that make a shaft worth a ladder

# ---- brood: [antkit piece, long side in world px at the start of the stage, at its end]
const EGG = [["egg_cluster", 10.0, 11.0], ["egg_mass", 9.5, 10.5]]
const LARVA = [["larva_curled", 8.5, 10.5], ["larva_fat", 10.5, 12.5]]
const PUPA = {"cream": ["cocoon_cream", 12.5], "grey": ["cocoon_grey", 13.0], "winged": ["cocoon_winged", 14.5]}
const EGG_END = 0.34           # share of the countdown spent as an egg ...
const LARVA_END = 0.76         # ... and as a grub; the rest in the cocoon
const BACK_SCALE = 0.8         # brood in the back tunnel plane: further away (as units_view draws the ants there)
const BACK_SHADE = 0.5
const HIDDEN_SHADE = 0.7       # ... and where front dirt stands in front of it, darker still and see-through
const HIDDEN_ALPHA = 0.55

# ---- chamber badges (zoomed out)
const ICONS = {"brood": "ui/chamber_brood.png", "food": "ui/chamber_food.png", "farm": "ui/chamber_farm.png",
	"armory": "ui/chamber_armory.png", "midden": "ui/chamber_midden.png", "queen": "ui/chamber_queen.png"}
const BADGE_Z0 = 1.1           # the badges fade in from this camera zoom ...
const BADGE_Z1 = 0.7           # ... and are full from this one out
const BADGE_PX = 44.0          # their size on screen ...
const BADGE_Z_ABOVE = 25       # z above this view's own (30 + 25: over the ants at 40 and the effects at 50, under the interface)
const BADGE_MAX = 84.0         # ... but never wider than this many world px (zoomed far out the rooms are close together)

# ---- the anthill
const MOUND_K = 0.28           # world px per picture px at the least (the small mound's hole comes out about as tall as an ant on the surface)
const MOUND_GROW = [0, 220, 900]   # spoil grains on the surface (world_grid.mound_cells) from which the small, medium and large mound are used ...
const MOUND_FIT = 1.6          # ... or a bigger one while the smaller would have to be drawn more than this much over MOUND_K to cover its heap
const MOUND_COVER = 1.1        # the anthill is at least this much wider than the spoil heap it sits on

var colony
var _grid                      # the grid the caches were built for (a new colony brings a new one)
var _t := 0.0                  # animation clock (stops while the game is paused)
var _pman := {}                # props manifest items
var _specs := {}               # name -> spec (null: no such picture): {tex, src, w, h, base, top} (w, h, base, top in world px at scale 1)
var _brood := {}               # antkit piece name -> {tex, w, h, base (picture px), long}
var _icons := {}               # purpose -> texture
var _mounds := []              # [{tex, w, h, hole: Vector2 (picture px, the middle of the entrance)}], small to large
var _units := {}               # unit name -> {key, props, occ}: the furnishing of one room (or the hall, the shafts ...), see _props_check
var _want := {}                # unit name -> [key it should have, its chamber or null]
var _order := []               # unit names in the order they are furnished and drawn
var _stale := []               # unit names waiting to be rebuilt
var _drawn := []               # every unit's props, gathered: [{tex, src (picture px), rect (world px), mirror, mod}]
var _props := []               # the props of the unit being built
var _epoch := 0                # bumps when enough has been dug that floors are looked at again
var _tier_now := 0
var _occ := []                 # footprints placed so far in a rebuild
var _check_t := 0.0
var _refresh_t := 0.0
var _open_ver := -1
var _food_lv := 0
var _lo := 0                   # columns the nest spans (props and shafts are looked for only there)
var _hi := 0
var _egg_floor := {}           # Vector3(egg pos, plane) -> world y of the drawn floor under it (cleared on every props check)
var _badges: Node2D            # the chamber badges: a child drawn above the ants (zoomed out they are what the view is for)
var _heap_w := 0.0             # width of the spoil heap round the main mouth, world px
var _heap_ws := []             # the same for every mouth (_heap_w is the first)
var _mound_ws := []            # how wide the anthill is drawn at every mouth, world px (surface_view.gd clears the grass round it)
var props_rebuilds := 0
var props_ms := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_badges = Node2D.new()
	_badges.name = "badges"
	_badges.z_index = BADGE_Z_ABOVE
	_badges.draw.connect(_draw_badges)
	add_child(_badges)
	_pman = Art.manifest("props_manifest.json").get("items", {})
	var kit = Art.manifest("antkit_manifest.json").get("pieces", {})
	var names := []
	for e in EGG + LARVA:
		names.append(e[0])
	for k in PUPA:
		names.append(PUPA[k][0])
	for n in names:
		var p = kit.get(n)
		var tex = Art.tex(p["file"]) if p != null else null
		if tex != null:
			var w = float(p["w"])
			var h = float(p["h"])
			_brood[n] = {"tex": _mipmapped(tex), "w": w, "h": h, "base": Vector2(w * 0.5, h - 3.0), "long": max(w, h)}
	for k in ICONS:
		var t = Art.tex(ICONS[k])
		if t != null:
			_icons[k] = _mipmapped(t)
	for m in Art.manifest("anthill/anthill_manifest.json").get("mounds", []):
		var tex = Art.tex(m["file"])
		if tex == null:
			continue
		_mounds.append({"tex": _mipmapped(tex), "w": float(m["w"]), "h": float(m["h"]), "hole": Vector2(m["hole"][0], m["hole"][1])})


# The pictures are imported without mipmaps; drawn at a fifth of their size or less they sparkle without them.
static func _mipmapped(tex: Texture2D) -> Texture2D:
	var img = tex.get_image()
	if img == null or img.is_empty() or img.has_mipmaps():
		return tex
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func reset() -> void:
	_grid = null


func _process(delta: float) -> void:
	if colony == null or colony.sim == null:
		return
	if not colony.paused:
		_t += delta
	var g = colony.grid
	if g != _grid:
		_grid = g
		_units = {}
		_want = {}
		_order = []
		_stale = []
		_props = []
		_occ = []
		_food_lv = 0
		_open_ver = -1
		_epoch = 0
		_check_t = 0.0
		_refresh_t = REFRESH_EVERY
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		_egg_floor.clear()
		_props_check()
		_heap_ws.clear()
		for en in g.entrances:
			_heap_ws.append(_heap_width(g, int(en.x)))
		_heap_w = _heap_ws[0] if not _heap_ws.is_empty() else 0.0
	if not _stale.is_empty():
		_build_some()
	queue_redraw()
	_badges.queue_redraw()


func _draw() -> void:
	var sim = colony.sim
	if sim == null:
		return
	var vr = colony.view_rect(MARGIN)
	_draw_props(vr)
	_draw_brood(vr)
	_draw_mounds(vr)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------------------------------------------------ props: when
static func _steps(v: float, th: Array) -> int:
	var n := 0
	for t in th:
		if v >= t:
			n += 1
	return n


# The colony's milestone level, 0..5 (see the rules at the top).
func _tier() -> int:
	var sim = colony.sim
	var v = [_steps(sim.peak_ants, [25, 50, 90, 150, 230]), _steps(sim.raid_n, [1, 3, 6, 10, 15]),
		_steps(sim.max_gen, [3, 6, 10, 15, 22]), _steps(sim.planner.open_levels(), [4, 6, 8, 10, 12])]
	v.sort()
	return int(round((v[1] + v[2] + v[3]) / 3.0))


# Twice a second: what should each part of the nest hold now? The furnishing is kept in units (a room, the queen's chamber, the
# entrance hall, the other mouths, the shafts), each with a key made of what it depends on; a unit whose key changed is rebuilt, a
# few a frame (_build_some), so a fuller larder refurnishes only the stores. (The larder level has a little hysteresis, so stores
# hovering at a step do not refurnish back and forth.) When enough has been dug since the last look, every unit is looked at again,
# one after another: a tunnel may have gone through a floor.
func _props_check() -> void:
	var sim = colony.sim
	var g = colony.grid
	var f = clamp(sim.food / max(1.0, sim.food_cap), 0.0, 1.0) * 6.0
	if f > _food_lv + 1.15 or f < _food_lv - 0.15:
		_food_lv = int(clamp(floor(f), 0.0, 6.0))
	var crumbs = 1 if sim.food > 1.0 else 0
	var lab := 0
	for i in LAB_KEYS.size():
		if sim.owned.has(LAB_KEYS[i]):
			lab |= 1 << i
	_refresh_t -= CHECK_EVERY
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH_EVERY
		if abs(g.open_under - _open_ver) >= 30:
			_open_ver = g.open_under
			_epoch += 1
	_lo = int(g.entrance.x) - 70
	_hi = int(g.entrance.x) + 70
	for en in g.entrances:
		_lo = min(_lo, int(en.x) - 45)
		_hi = max(_hi, int(en.x) + 45)
	for c in sim.planner.chambers:
		_lo = min(_lo, int(c["center"].x - c["rx"]) - 25)
		_hi = max(_hi, int(c["center"].x + c["rx"]) + 25)
	_tier_now = _tier()
	var tier = _tier_now
	var want := {}
	var order := []
	for c in sim.planner.chambers:
		if int(c.get("z", 0)) != 0:
			continue
		var n = "room:%d,%d" % [int(c["center"].x * 10.0), int(c["center"].y * 10.0)]
		var food = str(c["purpose"]) == "food"
		want[n] = ["%s|%d|%d|%d|%d|%d" % [c["purpose"], tier, _food_lv if food else 0, crumbs if food else 0, lab, _epoch], c]
		order.append(n)
	var raid_steps = _steps(sim.raid_n, [1, 3, 5, 7, 8])
	want["queen"] = ["%d|%d" % [tier, _epoch], null]
	want["hall"] = ["%d|%d|%d" % [raid_steps, lab, _epoch], null]
	want["mouths"] = ["%d|%d|%d" % [g.entrances.size(), raid_steps, _epoch], null]
	want["shafts"] = ["%d|%d|%d|%d|%d|%d|%d|%d" % [tier, lab, _epoch, sim.planner.chambers.size(), sim.planner.open_levels(), g.entrances.size(), _lo, _hi], null]
	order += ["queen", "hall", "mouths", "shafts"]
	var gone := false
	for n in _units.keys():
		if not want.has(n):
			_units.erase(n)
			gone = true
	for n in order:
		if (not _units.has(n) or _units[n]["key"] != want[n][0]) and not n in _stale:
			_stale.append(n)
	_want = want
	_order = order
	if gone:
		_flatten()


# Rebuild stale units until BUILD_MS is spent (at least one), then gather what is drawn.
func _build_some() -> void:
	var t0 = Time.get_ticks_usec()
	var built := false
	while not _stale.is_empty() and (not built or Time.get_ticks_usec() - t0 < BUILD_MS * 1000.0):
		var n = _stale.pop_front()
		if not _want.has(n):
			continue
		_build_unit(n)
		built = true
	props_ms = (Time.get_ticks_usec() - t0) / 1000.0
	props_rebuilds += 1
	if built:
		_flatten()


func _flatten() -> void:
	var out := []
	for n in _order:
		if _units.has(n):
			out.append_array(_units[n]["props"])
	_drawn = out


# Furnish one unit: everything else that stands is in the way (_occ), what this unit adds becomes its props and footprints.
func _build_unit(n: String) -> void:
	_occ = []
	for m in _order:
		if m != n and _units.has(m):
			_occ.append_array(_units[m]["occ"])
	var occ0 = _occ.size()
	_props = []
	var w = _want[n]
	if n.begins_with("room:"):
		_furnish_room(w[1])
	else:
		match n:
			"queen":
				_furnish_queen()
			"hall":
				_furnish_hall()
			"mouths":
				_furnish_mouths()
			"shafts":
				if _tier_now >= 2:
					var own = colony.sim.owned
					_ladders(_tier_now, own.has("tools") or own.has("dynamite") or own.has("burrow"))
	_units[n] = {"key": w[0], "props": _props, "occ": _occ.slice(occ0)}
	_props = []
	_occ = []


# A room: what it is for first, in the middle of the floor, then its kit from the walls in.
func _furnish_room(c: Dictionary) -> void:
	var own = colony.sim.owned
	var tier = _tier_now
	var armour = own.has("helmet") or own.has("glass") or own.has("vest") or own.has("tardigrade")
	var p = str(c["purpose"])
	var cx = float(c["center"].x)
	var rx = float(c["rx"])
	var sd = cx * 7.13 + float(c["center"].y) * 3.71
	var fl = _floors(int(cx - rx) - 1, int(cx + rx) + 1, int(c["center"].y - c["ry"]) - 1, int(c["center"].y + c["ry"] * 1.5) + 3, int(c["floor"]) + 1)
	var mid = int(round(cx))
	var floor_w = fl.size() * C
	match p:
		"food":
			_furnish(fl, _piles(floor_w), sd + 1.0, [], mid)
		"farm":
			var nf = int(clamp(floor(floor_w * 0.6 / FUNGUS_W), 1, MAX_FUNGUS))
			var fu := []
			for i in nf:
				fu.append(["fungus", 0.85 + 0.25 * _h(sd + i * 3.3)])
			_furnish(fl, fu, sd + 2.0, [], mid)
		"midden":
			_furnish(fl, [["midden", 1.0]] + ([["midden", 0.7]] if floor_w > 70.0 else []), sd + 3.0, [], mid)
	var kit: Array = ROOM_KIT.get(p, [])
	var items := []
	if p == "food":
		if tier >= 1:
			var n = int(round(_food_lv / 6.0 * (1 + tier))) + (1 if own.has("piggy") and _food_lv > 0 else 0)
			for i in int(min(n, kit.size())):
				items.append(kit[i] if ITEM_TIER.get(kit[i], 0) <= tier else "crate")
	else:
		var n2 = tier + (1 if p in WORKSHOPS or p == "midden" else 0) - (1 if p == "brood" or p == "farm" else 0)
		for i in int(clamp(n2, 0, kit.size())):
			if ITEM_TIER.get(kit[i], 0) <= tier:
				items.append(kit[i])
		if p == "brood" and own.has("medikit") and not "bucket" in items:
			items.append("bucket")
		if p == "armory" and armour and not "helmet_riveted" in items:
			items.append("helmet_riveted")
	if tier >= 4 and int(c.get("level", 0)) >= 4:
		items.append(DEEP_IRON[int(_h(sd + 11.0) * DEEP_IRON.size()) % DEEP_IRON.size()])
		if tier >= 5:
			items.append(DEEP_IRON[int(_h(sd + 13.0) * DEEP_IRON.size()) % DEEP_IRON.size()])
	_furnish(fl, items, sd, [])
	if tier >= 4 and p == "architects":
		_hang_lantern(c["center"], rx, sd)


# The queen's chamber: her middle stays clear (she lies there).
func _furnish_queen() -> void:
	var g = colony.grid
	var tier = _tier_now
	if tier < 2:
		return
	var qc = g.chamber
	var qr = g.chamber_r
	var qk: Array = ROOM_KIT["queen"]
	var qi := []
	for i in int(clamp(tier - 1, 0, qk.size())):
		if ITEM_TIER.get(qk[i], 0) <= tier:
			qi.append(qk[i])
	var keep = [Vector2((qc.x + 0.5 - qr.x * 0.45) * C, (qc.x + 0.5 + qr.x * 0.45) * C)]
	_furnish(_floors(int(qc.x - qr.x) - 1, int(qc.x + qr.x) + 1, int(qc.y - qr.y) - 1, int(qc.y + qr.y) + 3, int(qc.y + qr.y)), qi, qc.x * 5.3 + qc.y, keep)
	if tier >= 4:
		_hang_lantern(qc, qr.x, qc.x * 5.3 + 4.0)


# The entrance hall: the first floors under the main mouth, above the queen's chamber.
func _furnish_hall() -> void:
	var sim = colony.sim
	var g = colony.grid
	var raids = sim.raid_n
	var own = sim.owned
	var hall := []
	if raids >= 1:
		hall.append("palisade")
	if raids >= 3:
		hall.append("gate")
	if raids >= 5 or own.has("barricade"):
		hall.append("spike_barricade")
	if raids >= 7 or own.has("landmines"):
		hall.append("x_stakes")
	if raids >= 8:
		hall.append("cage")
	if hall.is_empty():
		return
	var ex = int(g.entrance.x)
	var esy = g.surf_y(ex)
	var yb = esy + 26
	if abs(g.chamber.x - ex) < g.chamber_r.x + 6:
		yb = min(yb, int(g.chamber.y - g.chamber_r.y) - 1)
	_furnish(_floors(ex - 26, ex + 26, esy + 3, yb, esy + 3), hall, ex * 7.1, [Vector2(ex - 1.5, ex + 2.5) * C], ex)


# The other mouths: a fence after the first raid.
func _furnish_mouths() -> void:
	var g = colony.grid
	if colony.sim.raid_n < 1:
		return
	for i in range(1, g.entrances.size()):
		var en = g.entrances[i]
		var sy2 = g.surf_y(int(en.x))
		_furnish(_floors(int(en.x) - 16, int(en.x) + 16, sy2 + 3, sy2 + 22, sy2 + 3), ["fence"], en.x * 3.3, [Vector2(en.x - 1.5, en.x + 2.5) * C], int(en.x))


# The food piles of one store: as many as the larder is full (all the stores show the same fill), the last one smaller; a few
# crumbs of food make one small pile.
func _piles(floor_w: float) -> Array:
	var k = int(clamp(floor(floor_w * 0.8 / PILE_W), 1, MAX_PILES))
	var f = _food_lv / 6.0 * k
	var out := []
	for i in int(floor(f)):
		out.append(["food_pile", 1.0])
	var rest = f - floor(f)
	if rest > 0.25 and out.size() < k:
		out.append(["food_pile", 0.55 + 0.45 * rest])
	if out.is_empty() and colony.sim.food > 1.0:
		out.append(["food_pile", 0.5])
	return out


# Floor columns of a box: for every column, the open cell with solid ground under it nearest to row pref_y, and the open headroom
# above it in cells: {x: [floor_row, headroom]}.
func _floors(xa: int, xb: int, ya: int, yb: int, pref_y: int) -> Dictionary:
	var g = colony.grid
	var out := {}
	var W: int = g.W
	var ox: int = g.ox
	var solid = g.solid
	var under = g.under
	var y0 = max(ya, 1)
	var y1 = min(yb, g.H - 3)
	for x in range(max(xa, ox + 2), min(xb, ox + W - 3) + 1):
		var best = -1
		var bd = 1 << 20
		for y in range(y0, y1 + 1):
			var j = y * W + (x - ox)
			if solid[j] == 0 and under[j] == 1 and solid[j + W] != 0 and abs(y - pref_y) < bd:
				best = y
				bd = abs(y - pref_y)
		if best < 0:
			continue
		var head = 0
		var j2 = best * W + (x - ox)
		while head < 16 and j2 >= 0 and solid[j2] == 0 and under[j2] == 1:
			head += 1
			j2 -= W
		out[x] = [best, head]
	return out


# A picture's size in world px at scale 1, its texture and the part of it to draw, and its base (and hanging) point. Props come
# from the props manifest (sized next to a worker), the room stock from STOCK (trimmed to what is drawn on the picture).
func _spec(name: String):
	if _specs.has(name):
		return _specs[name]
	var out = null
	var e = _pman.get(name)
	if e is Dictionary:
		var t = Art.tex(str(e.get("file", "")))
		if t != null:
			var w = float(e["w"])
			var h = float(e["h"])
			var k = float(e.get("game_size", 30.0)) * ANT_PX / PROP_WORKER / max(w, h)
			out = {"tex": _mipmapped(t), "src": Rect2(0, 0, t.get_width(), t.get_height()), "w": w * k, "h": h * k,
				"base": Vector2(e["base"][0], e["base"][1]) * k, "top": Vector2(e["top"][0], e["top"][1]) * k}
	elif STOCK.has(name):
		var t2 = Art.tex(STOCK[name][0])
		if t2 != null:
			var src = Rect2(0, 0, t2.get_width(), t2.get_height())
			var img = t2.get_image()
			if img != null and not img.is_empty():
				if img.is_compressed():
					img.decompress()
				var used = img.get_used_rect()
				if used.size.x > 0 and used.size.y > 0:
					src = Rect2(used)
			var k2 = float(STOCK[name][1]) / max(src.size.x, src.size.y)
			out = {"tex": _mipmapped(t2), "src": src, "w": src.size.x * k2, "h": src.size.y * k2,
				"base": Vector2(src.size.x * 0.5, src.size.y - 2.0) * k2, "top": Vector2(src.size.x * 0.5, 0.0)}
	_specs[name] = out
	return out


# Put each item of the list (a name, or [name, scale]) on the floor columns fl, in turn on the left and on the right (which side
# first is seeded by sd): from the walls inwards, or outwards from column `around` (a room's middle, the entrance hall). clear:
# [Vector2(x0, x1)] px spans to keep free. An item that fits nowhere is left out.
func _furnish(fl: Dictionary, items: Array, sd: float, clear: Array, around = null) -> void:
	if fl.is_empty() or items.is_empty():
		return
	var xs = fl.keys()
	xs.sort()
	# the two orders the columns are tried in (left side first, right side first), worked out once
	var orders := []
	if around == null:
		var rev = xs.duplicate()
		rev.reverse()
		orders = [xs, rev]
	else:
		var a: int = around
		var lft := []
		var rgt := []
		for x in xs:
			if x > a:
				rgt.append(x)
			else:
				lft.append(x)
		lft.sort_custom(func(p, q): return abs(p - a) < abs(q - a))
		rgt.sort_custom(func(p, q): return abs(p - a) < abs(q - a))
		orders = [lft + rgt, rgt + lft]
	# only what already stands near these floors can be in the way
	var x0 = xs[0] * C - 60.0
	var x1 = (xs[xs.size() - 1] + 1) * C + 60.0
	var near := []
	for o in _occ:
		if o.end.x > x0 and o.position.x < x1:
			near.append(o)
	var first = 0 if _h(sd) < 0.5 else 1
	for k in items.size():
		var it = items[k]
		var name: String = it if it is String else str(it[0])
		var scale: float = 1.0 if it is String else float(it[1])
		var sp = _spec(name)
		if sp == null:
			continue
		var jit = (0.94 + 0.12 * _h(sd + k * 2.3)) * scale
		var w = sp["w"] * jit
		var h = sp["h"] * jit
		var cand: Array = orders[(k + first) % 2]
		var placed = false
		for min_s in [0.97, 0.72]:
			for x in cand:
				var r = _fit(fl, x, w, h, clear, min_s, near)
				if r == null:
					continue
				_add_prop(sp, r[0], r[1], r[2] * jit, _h(sd + k * 1.7) < 0.5)
				near.append(_occ[_occ.size() - 1])
				placed = true
				break
			if placed:
				break


# Can an item w x h px stand centred on column x? Returns [centre x, floor y, scale] or null. occ: the footprints it must not hit.
func _fit(fl: Dictionary, x: int, w: float, h: float, clear: Array, min_s: float, occ: Array):
	var cx = (x + 0.5) * C
	var a = int(floor((cx - w * 0.4) / C))
	var b = int(floor((cx + w * 0.4) / C))
	var lo = 1 << 20
	var hi = -1
	var ceil_y = -1e9
	for xx in range(a, b + 1):
		var f = fl.get(xx)
		if f == null:
			return null
		lo = min(lo, f[0])
		hi = max(hi, f[0])
		ceil_y = max(ceil_y, (f[0] - f[1] + 1) * C)
	if hi - lo > 1:
		return null
	for z in clear:
		if cx + w * 0.4 > z.x and cx - w * 0.4 < z.y:
			return null
	var base = (hi + 1) * C + 1.0
	var s = min(1.0, (base - ceil_y - 3.0) / h)
	if s < min_s:
		return null
	var foot = Rect2(cx - w * s * 0.5, base - h * s, w * s, h * s)
	for o in occ:
		if _overlap(foot, o):
			return null
	return [cx, base, s]


static func _overlap(a: Rect2, b: Rect2) -> bool:
	var ox = min(a.end.x, b.end.x) - max(a.position.x, b.position.x)
	var oy = min(a.end.y, b.end.y) - max(a.position.y, b.position.y)
	return ox > PROP_OVERLAP * min(a.size.x, b.size.x) and oy > 2.0


# A thing standing with its base point on (cx, base), drawn at scale s (sx: a different width scale, for ladders).
func _add_prop(sp: Dictionary, cx: float, base: float, s: float, mirror: bool, sx: float = -1.0) -> void:
	if sx < 0.0:
		sx = s
	var w = sp["w"] * sx
	var h = sp["h"] * s
	var bx = sp["base"].x * sx
	var by = sp["base"].y * s
	var pos = Vector2(cx - (w - bx if mirror else bx), base - by)
	var r = Rect2(pos, Vector2(w, h))
	_occ.append(r)
	_push(sp, r, mirror, _shade(base))


func _push(sp: Dictionary, r: Rect2, mirror: bool, mod: Color) -> void:
	_props.append({"tex": sp["tex"], "src": sp["src"], "rect": r, "mirror": mirror, "mod": mod})


# A little darker than the ants, more so deeper down: the room's things stand back against its rear wall.
func _shade(y: float) -> Color:
	var g = colony.grid
	var d = clamp((y / C - g.surf_y(int(g.entrance.x))) / 150.0, 0.0, 1.0)
	var k = 0.9 * (1.0 - 0.3 * d)
	return Color(k, k, k)


# Hang a lantern cage from the ceiling of a room, a little off its middle.
func _hang_lantern(center: Vector2, rx: float, sd: float) -> void:
	var sp = _spec("lantern_cage")
	if sp == null:
		return
	var g = colony.grid
	for tries in 3:
		var x = int(round(center.x + (_h(sd + tries * 3.1) - 0.5) * rx * 0.9))
		if not g.inb(x, int(center.y)) or g.is_solid(x, int(center.y)):
			continue
		var y = int(center.y)
		while y > 1 and not g.is_solid(x, y - 1) and g.is_under(x, y - 1):
			y -= 1
		if not g.is_solid(x, y - 1):
			continue
		var top = y * C - 1.0
		var pos = Vector2((x + 0.5) * C - sp["top"].x, top - sp["top"].y)
		var r = Rect2(pos, Vector2(sp["w"], sp["h"]))
		var clash = false
		for o in _occ:
			if _overlap(r, o):
				clash = true
		if clash:
			continue
		_occ.append(r)
		_push(sp, r, false, _shade(top).lightened(0.15))
		return


# Shafts: straight vertical runs of open cells at least LADDER_RUN tall that end on a floor and are narrow (a shaft, not a room),
# one per shaft (the tallest column of it), tallest first: [[x, floor row, run, open cells left, right]].
func _shaft_spots() -> Array:
	var sim = colony.sim
	var g = colony.grid
	var W: int = g.W
	var ox: int = g.ox
	var solid = g.solid
	var under = g.under
	var deepest = g.surf_y(int(g.entrance.x)) + 20
	for i in sim.planner.levels.size():
		if sim.planner.level_open[i]:
			deepest = max(deepest, sim.planner.levels[i] + 12)
	var spots := []
	for x in range(max(_lo, ox + 8), min(_hi, ox + W - 9) + 1):
		var sy = g.surf_y(x)
		var run = 0
		for y in range(sy + 1, min(deepest, g.H - 3)):
			var j = y * W + (x - ox)
			if solid[j] != 0 or under[j] == 0:
				run = 0
				continue
			run += 1
			if run < LADDER_RUN or solid[j + W] == 0:
				continue
			var jm = (y - int(run / 2.0)) * W + (x - ox)
			var l = 0
			while l < 6 and solid[jm - l - 1] == 0:
				l += 1
			var r = 0
			while r < 6 and solid[jm + r + 1] == 0:
				r += 1
			if l + r + 1 <= 5:
				spots.append([x, y, run, l, r])
	var groups := []
	for sp in spots:
		var merged = false
		for gr in groups:
			if abs(gr[0] - sp[0]) <= 2 and abs(gr[1] - sp[1]) <= 2:
				if sp[2] > gr[2]:
					for i in 5:
						gr[i] = sp[i]
				merged = true
				break
		if not merged:
			groups.append(sp.duplicate())
	groups.sort_custom(func(a, b): return a[2] > b[2])
	return groups


# The tallest shafts get a ladder standing at the foot, squeezed to the shaft's width.
func _ladders(tier: int, digging: bool) -> void:
	var g = colony.grid
	var W: int = g.W
	var ox: int = g.ox
	var solid = g.solid
	var lad = _spec("ladder")
	var pick = _spec("pickaxe_head")
	var hoist = _spec("pulley")
	if lad == null:
		return
	var n := 0
	var hung := 0
	for s in _shaft_spots():
		if n >= MAX_LADDERS:
			break
		var x: int = s[0]
		var y: int = s[1]
		var run: int = s[2]
		var wid = s[3] + s[4] + 1
		var cx = (x - s[3]) * C + wid * C * 0.5
		var base = (y + 1) * C + 1.0
		var h = clamp(run * C - 6.0, 20.0, 40.0)
		var s_h = h / lad["h"]
		var s_w = min(s_h, (wid * C - 1.0) / lad["w"])
		var foot = Rect2(cx - lad["w"] * s_w * 0.5, base - h, lad["w"] * s_w, h)
		var clash = false
		for o in _occ:
			if _overlap(foot, o):
				clash = true
		if clash:
			continue
		_add_prop(lad, cx, base, s_h, false, s_w)
		n += 1
		if digging and pick != null and n % 2 == 1:
			_furnish(_floors(x - 9, x + 9, y - 2, y + 2, y), ["pickaxe_head"], x * 1.3 + y, [], x)
		if tier >= 4 and hoist != null and hung < 2 and run >= 15:
			var yt = y - run + 1
			if solid[(yt - 1) * W + (x - ox)] != 0:
				var top = yt * C - 1.0
				var hs = 0.9
				var pos = Vector2(cx - hoist["top"].x * hs, top - hoist["top"].y * hs)
				var hr = Rect2(pos, Vector2(hoist["w"], hoist["h"]) * hs)
				_occ.append(hr)
				_push(hoist, hr, false, _shade(top))
				hung += 1


static func _h(x: float) -> float:
	var s = sin(x * 12.9898 + 78.233) * 43758.5453
	return s - floor(s)


func _draw_props(vr: Rect2) -> void:
	for p in _drawn:
		var r: Rect2 = p["rect"]
		if not vr.intersects(r):
			continue
		if p["mirror"]:
			draw_set_transform(Vector2(r.end.x, r.position.y), 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect_region(p["tex"], Rect2(Vector2.ZERO, r.size), p["src"], p["mod"])
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(p["tex"], r, p["src"], p["mod"])


# ------------------------------------------------------------------------------------------------------------ brood
# Every egg where it was laid, resting on the floor under it, at the stage its countdown has reached. Cocoons go behind grubs and
# grubs behind eggs, so a nursery reads as a heap of brood rather than a jumble.
func _draw_brood(vr: Rect2) -> void:
	if _brood.is_empty():
		return
	var sim = colony.sim
	var g = colony.grid
	var items := []
	for e in sim.eggs:
		var pos: Vector2 = e["pos"]
		var wx = (pos.x + 0.5) * C
		var wy = (pos.y + 0.5) * C
		if wx < vr.position.x or wx > vr.end.x or wy < vr.position.y or wy > vr.end.y:
			continue
		var prog = clamp(1.0 - float(e["t"]) / max(float(e.get("t0", 14.0)), 0.1), 0.0, 1.0)
		items.append([prog, e])
	items.sort_custom(func(a, b): return a[0] > b[0])
	for it in items:
		_draw_egg(g, it[1], it[0])


func _draw_egg(g, e: Dictionary, prog: float) -> void:
	var pos: Vector2 = e["pos"]
	var z = int(e.get("z", 0))
	var x = int(floor(pos.x + 0.5))
	var sd = pos.x * 13.7 + pos.y * 5.1
	var piece = ""
	var size := 0.0
	var rot := 0.0
	var squash := 1.0
	if prog < EGG_END:
		var eg = EGG[0] if _h(sd) < 0.7 or not _brood.has(EGG[1][0]) else EGG[1]
		piece = eg[0]
		size = lerp(float(eg[1]), float(eg[2]), prog / EGG_END)
		squash = 1.0 + 0.03 * sin(_t * 2.0 + sd)
	elif prog < LARVA_END:
		var k = (prog - EGG_END) / (LARVA_END - EGG_END)
		var lv = LARVA[0] if k < 0.5 else LARVA[1]
		piece = lv[0]
		size = lerp(float(lv[1]), float(lv[2]), fmod(k, 0.5) * 2.0)
		rot = sin(_t * 2.4 + sd) * 0.08                     # a grub wriggles
		squash = 1.0 + 0.05 * sin(_t * 3.1 + sd * 1.3)
	else:
		var k2 = (prog - LARVA_END) / (1.0 - LARVA_END)
		var kind = "cream"
		var gen = e.get("genome")
		if gen != null and int(gen.m("wings")) == 1:
			kind = "winged"
		elif int(e.get("caste", 0)) == 2:
			kind = "grey"
		piece = PUPA[kind][0]
		size = PUPA[kind][1]
		var twitch = clamp((k2 - 0.75) / 0.25, 0.0, 1.0)
		rot = sin(_t * 22.0 + sd) * 0.12 * twitch          # about to break out
	var b = _brood.get(piece)
	if b == null:
		return
	# the floor under it (it was laid a little above the room's floor line, which is not where every floor is)
	var y = int(floor(pos.y + 0.5))
	var n := 0
	while n < 4 and g.is_solid(x, y, z):
		y -= 1
		n += 1
	var wx = (pos.x + 0.5) * C
	var fk = Vector3(pos.x, pos.y, z)
	var fy = _egg_floor.get(fk)
	if fy == null:
		fy = _floor_y(g, wx, y, z)
		_egg_floor[fk] = fy
	var feet = Vector2(wx, fy + 0.5)
	var shade := 1.0
	var alpha := 1.0
	if z == 1:
		size *= BACK_SCALE
		shade = BACK_SHADE
		if g.is_solid(x, y, 0):
			shade *= HIDDEN_SHADE
			alpha = HIDDEN_ALPHA
	var s = size / b["long"]
	var flip = -1.0 if _h(sd + 3.0) < 0.5 else 1.0
	draw_set_transform(feet, rot, Vector2(s * flip, s * squash))
	draw_texture(b["tex"], -b["base"], Color(shade, shade, shade, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# World y of the floor as the soil draws it, under world x, from row `row` down (at most 8 rows). The soil shader's edge is the 0.5
# contour of its mask, and the mask (world_grid._paint) is the solid cells blurred 1-2-1 both ways, a texel per cell, filtered between
# cell centres: flat floors stay on the cell line, but steps and corners are rounded off, so the top of the solid cell is not where
# the drawn floor is on a slope.
static func _floor_y(g, wx: float, row: int, z: int) -> float:
	var fx = wx / C - 0.5
	var x0 = int(floor(fx))
	var tx = fx - x0
	var prev = lerp(_mask(g, x0, row, z), _mask(g, x0 + 1, row, z), tx)
	for r in range(row, row + 8):
		var v = lerp(_mask(g, x0, r + 1, z), _mask(g, x0 + 1, r + 1, z), tx)
		if prev < 0.5 and v >= 0.5:
			return (r + (0.5 - prev) / (v - prev) + 0.5) * C
		prev = v
	return (row + 1) * C


# The soil mask's value at a cell (see _floor_y).
static func _mask(g, x: int, y: int, z: int) -> float:
	var acc := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if g.is_solid(x + dx, y + dy, z):
				acc += (2 - abs(dx)) * (2 - abs(dy))
	return acc / 16.0


# ------------------------------------------------------------------------------------------------------------ the anthill
func _draw_mounds(vr: Rect2) -> void:
	if _mounds.is_empty():
		return
	var g = colony.grid
	var grow = 0
	for i in MOUND_GROW.size():
		if g.mound_cells >= MOUND_GROW[i]:
			grow = i
	var tint = colony.day.tint
	tint.a = 1.0
	_mound_ws.resize(g.entrances.size())
	for i in g.entrances.size():
		var en = g.entrances[i]
		var ex = int(en.x)
		# the heap: its apex over the mouth (the shaft's chimney rises with the heap, so this follows it as it grows), and its base, the
		# original ground, where the lowest of it is
		var top = float(min(g.surf_y(ex), min(g.surf_y(ex - 1), g.surf_y(ex + 1)))) * C
		var hw: float = _heap_ws[i] if i < _heap_ws.size() else _heap_width(g, ex)
		var ground = _heap_ground(g, ex, hw) * C
		# The anthill covers the whole heap above the ground: its bottom on the ground, the middle of its entrance over the mouth at the apex
		# (the ants climb out of the painted cave and walk down its front), wide enough that no bare dirt shows round it. The smallest
		# picture that fits without being blown up much is used, never a smaller one than the spoil carried up calls for.
		var pick = min(grow if i == 0 else 0, _mounds.size() - 1)
		var s = 0.0
		for k in range(pick, _mounds.size()):
			pick = k
			s = _mound_scale(_mounds[k], ground - top, hw)
			if s <= MOUND_K * MOUND_FIT:
				break
		var m = _mounds[pick]
		var hole: Vector2 = m["hole"]
		var r = Rect2(Vector2((en.x + 0.5) * C - hole.x * s, ground - m["h"] * s), Vector2(m["w"], m["h"]) * s)
		_mound_ws[i] = r.size.x
		if not vr.intersects(r):
			continue
		draw_texture_rect(m["tex"], r, false, tint)


# The scale (world px per picture px) at which anthill picture m covers a heap `heap_h` high (world px, from the ground to the apex) and
# `heap_w` wide: the middle of its entrance at the apex with its bottom on the ground, and wider than the heap.
func _mound_scale(m: Dictionary, heap_h: float, heap_w: float) -> float:
	var below: float = m["h"] - m["hole"].y            # picture px from the entrance's middle down to the picture's bottom
	return maxf(MOUND_K, maxf(heap_h / maxf(below, 1.0), MOUND_COVER * heap_w / float(m["w"])))


# The y (cells) of the ground the heap round column ex stands on: the lowest of the original ground across it (the anthill's bottom goes
# there, so no gap shows under it on the low side).
func _heap_ground(g, ex: int, heap_w: float) -> float:
	var half = int(ceil(heap_w / C * 0.5)) + 1
	var y = g.base_y(ex)
	for d in range(-half, half + 1, 2):
		y = max(y, g.base_y(ex + d))
	return float(y)


# Width of the spoil heap round the mouth at column ex: the columns either side of it with dirt piled on the original ground.
static func _heap_width(g, ex: int = -99999) -> float:
	if ex == -99999:
		ex = int(g.entrance.x)
	var l = ex
	while l > ex - 150 and (g.mound_h(l - 1) > 0 or g.chimneys.has(l - 1)):
		l -= 1
	var r = ex
	while r < ex + 150 and (g.mound_h(r + 1) > 0 or g.chimneys.has(r + 1)):
		r += 1
	return (r - l + 1) * C


# ------------------------------------------------------------------------------------------------------------ chamber badges
# Zoomed out, each room shows what it is: the owner's chamber icon over its middle, at a steady size on screen.
func _draw_badges() -> void:
	if colony == null or colony.sim == null:
		return
	var vr = colony.view_rect(MARGIN)
	var z = colony.zoom()
	var a = smoothstep(BADGE_Z0, BADGE_Z1, z)
	if a <= 0.01 or _icons.is_empty():
		return
	var g = colony.grid
	var sz = min(BADGE_PX / z, BADGE_MAX)
	var items = [["queen", g.chamber, 0]]
	for c in colony.sim.planner.chambers:
		if _icons.has(c["purpose"]):
			items.append([c["purpose"], c["center"], int(c.get("z", 0))])
	for it in items:
		var p: Vector2 = (it[1] + Vector2(0.5, 0.5)) * C
		if not vr.has_point(p) or not _icons.has(it[0]):
			continue
		var k = 1.0 if it[2] == 0 else 0.7
		_badges.draw_texture_rect(_icons[it[0]], Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(k, k, k, a))
