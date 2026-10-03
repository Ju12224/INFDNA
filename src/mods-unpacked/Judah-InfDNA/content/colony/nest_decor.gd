extends Reference
# The inside of the nest, layered: between the rear wall and the front dirt (so it only shows where the
# tunnels are open) hang roots, dirt drips, pebbles, crumbs and glowing fungus, and light falls down
# the shafts from the entrances. Built once per 32-column chunk into a cached mesh (mesh_kit.gd) from the
# open cells that have a ceiling or a floor, and rebuilt (throttled) when the tunnels change.
#
# Props (the owner's drawn nest props, content/art/props, cut by tools/art/make_props.py): the things a colony
# would put to use in its nest as it grows. They stand on real floor cells (open, solid underneath, with the
# headroom to fit), scaled to the ants (a worker is about 40 px long, a barrel about 30 px tall), a little darker
# than the ants like everything else on the back wall, and chosen per room from fixed lists so the same room
# always gets the same things in the same places (seeded by its position). See _props_rebuild for the rules.
# The list is rebuilt only when the rooms, the colony's milestone level, the larder level, the raid stage or a
# relevant Lab purchase change; drawing it is one textured quad per visible prop.

const MK = preload("res://mods-unpacked/Judah-InfDNA/content/colony/mesh_kit.gd")
const Lib = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
const PROPS_MANIFEST = "res://mods-unpacked/Judah-InfDNA/content/art/props_manifest.json"

const INK = Color("#15121a")
const CH = 32
const MAX_ROWS = 175

var sim
var g
var _chunks := {}            # chunk index -> {mesh, t}
var _vis := []
var _t := 0.0
var _open_ver := -999
var _stale := false
var _lo := 0
var _hi := 0
var _range_t := 0.0
var _cols := [0, 0]


func _init(sim_) -> void:
	sim = sim_
	g = sim_.grid


func prepare(cols: Array, t: float) -> void:
	_t = t
	_range_t -= 0.016
	if _range_t <= 0.0:
		_range_t = 1.0
		_lo = int(g.entrance.x) - 70
		_hi = int(g.entrance.x) + 70
		for en in g.entrances:
			_lo = min(_lo, int(en.x) - 45)
			_hi = max(_hi, int(en.x) + 45)
		for c in sim.planner.chambers:
			_lo = min(_lo, int(c["center"].x - c["rx"]) - 25)
			_hi = max(_hi, int(c["center"].x + c["rx"]) + 25)
		if abs(g.open_under - _open_ver) >= 6:
			_open_ver = g.open_under
			_stale = true
	var c_lo = int(floor(float(max(cols[0], _lo)) / CH))
	var c_hi = int(floor(float(min(cols[1], _hi)) / CH))
	var budget = 6 if _chunks.empty() else 1
	_vis = []
	for ci in range(c_lo, c_hi + 1):
		var ch = _chunks.get(ci)
		if ch == null or (_stale and t - ch["t"] > 3.0):
			if budget > 0:
				budget -= 1
				ch = _build(ci)
				_chunks[ci] = ch
		if ch != null and ch["mesh"] != null:
			_vis.append(ch["mesh"])
	if _stale:
		var all_fresh = true
		for ci2 in range(c_lo, c_hi + 1):
			var c2 = _chunks.get(ci2)
			if c2 == null or t - c2["t"] > 3.0:
				all_fresh = false
		if all_fresh:
			_stale = false
	_cols = cols
	_props_check()


func draw(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_shafts(ci)
	for m in _vis:
		ci.draw_mesh(m, null)
	_draw_props(ci)


# Daylight falling down each shaft, leaning with the sun.
func _shafts(ci: CanvasItem) -> void:
	var C = g.CELL
	for en in g.entrances:
		var x = (en.x + 0.5) * C
		var y = g.surf_y(int(en.x)) * C
		var wob = sin(_t * 0.4 + x * 0.01) * 6.0
		var warm = Color(1.0, 0.93, 0.7, 0.2)
		var none = Color(1.0, 0.93, 0.7, 0.0)
		ci.draw_polygon(PoolVector2Array([Vector2(x - 16, y), Vector2(x + 16, y), Vector2(x - 50 + wob, y + 380), Vector2(x - 190 + wob, y + 380)]),
			PoolColorArray([warm, warm, none, none]))


func _build(ci: int) -> Dictionary:
	var mk = MK.new()
	var C = g.CELL
	var W = g.W
	var ox = g.ox
	var solid = g.solid
	var under = g.under
	var c0 = ci * CH
	for x in range(c0, c0 + CH):
		if x < ox + 2 or x >= ox + W - 2:
			continue
		var sy = g.surf_y(x)
		for y in range(sy + 2, min(sy + MAX_ROWS, g.H - 2)):
			var j = y * W + (x - ox)
			if solid[j] != 0 or under[j] == 0:
				continue
			var up = solid[j - W]
			var dn = solid[j + W]
			if up == 0 and dn == 0:
				continue
			var h = MK.hash1(x * 7.31 + y * 3.17)
			var sd = x * 1.7 + y * 0.9
			var shade = 1.0 - 0.45 * clamp(float(y - sy) / 150.0, 0.0, 1.0)
			if up != 0:
				if h < 0.075:
					_root(mk, (x + 0.2 + 0.6 * MK.hash1(sd)) * C, y * C, sd, shade)
				elif h < 0.1:
					var dx = (x + 0.5) * C
					var dl = 6.0 + 8.0 * MK.hash1(sd + 2.0)
					mk.tri(Vector2(dx - 3.5, y * C), Vector2(dx + 3.5, y * C), Vector2(dx + (MK.hash1(sd) - 0.5) * 2.0, y * C + dl), Color(0.3 * shade + 0.1, 0.2 * shade + 0.07, 0.12 * shade + 0.04))
			if dn != 0:
				var fy = (y + 1) * C
				var fx = (x + 0.15 + 0.7 * MK.hash1(sd + 4.0)) * C
				if h < 0.04:
					var rr = 2.4 + 3.4 * MK.hash1(sd + 5.0)
					mk.ellipse_ink(Vector2(fx, fy - rr * 0.5), rr, rr * 0.65, Color(0.52 * shade + 0.1, 0.5 * shade + 0.08, 0.46 * shade + 0.08), 1.2, 9)
				elif h < 0.062:
					_fungus(mk, fx, fy, sd, shade)
				elif h < 0.085:
					for k in 3:
						mk.ellipse(Vector2(fx + (k - 1) * 3.2, fy - 1.0), 1.6, 1.1, Color(0.36 * shade + 0.1, 0.25 * shade + 0.07, 0.15 * shade + 0.05), 6)
	return {"mesh": mk.build(), "t": _t}


func _root(mk, x0: float, y0: float, sd: float, shade: float) -> void:
	var n = 5
	var ln = 8.0 + 22.0 * MK.hash1(sd + 1.0)
	var pts := PoolVector2Array()
	var wid := PoolRealArray()
	var wink := PoolRealArray()
	var side = (MK.hash1(sd + 3.0) - 0.5) * 8.0
	for i in n:
		var t = float(i) / (n - 1)
		pts.append(Vector2(x0 + sin(t * 3.0 + sd) * 2.5 * t + side * t * t, y0 + ln * t))
		wid.append(3.2 * (1.0 - t) + 0.9)
		wink.append(3.2 * (1.0 - t) + 3.2)
	var rc = Color(0.34 * shade + 0.06, 0.22 * shade + 0.04, 0.12 * shade + 0.03)
	mk.ribbon(pts, wink, INK)
	mk.ribbon(pts, wid, rc, rc.lightened(0.18))
	if MK.hash1(sd + 6.0) > 0.45:
		var p2 = pts[2]
		var tp := PoolVector2Array([p2, p2 + Vector2(side * 0.5 + 4.0, 4.0), p2 + Vector2(side * 0.8 + 8.0, 9.0)])
		mk.ribbon(tp, PoolRealArray([1.8, 1.3, 0.8]), rc)


func _fungus(mk, fx: float, fy: float, sd: float, shade: float) -> void:
	var cols = [Color("#7fe9d0"), Color("#ffcf6a"), Color("#b9a0ff")]
	var gc = cols[int(MK.hash1(sd + 7.0) * 2.99)]
	var n = 1 + int(MK.hash1(sd + 8.0) * 2.99)
	for i in n:
		var px = fx + (i - (n - 1) * 0.5) * 6.0
		var hh = 5.0 + 6.0 * MK.hash1(sd + i * 3.0)
		var cr = 3.0 + 2.6 * MK.hash1(sd + i * 5.0)
		mk.ellipse(Vector2(px, fy - hh), cr * 4.4, cr * 3.4, Color(gc.r, gc.g, gc.b, 0.07), 12)
		mk.ellipse(Vector2(px, fy - hh), cr * 2.4, cr * 1.9, Color(gc.r, gc.g, gc.b, 0.14), 12)
		mk.quad(Vector2(px - 1.1, fy), Vector2(px + 1.1, fy), Vector2(px + 0.8, fy - hh), Vector2(px - 0.8, fy - hh), Color(0.9 * shade + 0.1, 0.88 * shade + 0.1, 0.8 * shade + 0.1))
		mk.ellipse_ink(Vector2(px, fy - hh), cr, cr * 0.62, gc, 1.2, 10)
		mk.ellipse(Vector2(px - cr * 0.25, fy - hh - cr * 0.2), cr * 0.35, cr * 0.2, Color(1, 1, 1, 0.55), 6)


# ------------------------------------------------------------------------------------------------------------ props
# Rules (all deterministic: a room's things and their spots come from fixed lists and a seed made from its position):
#   milestone level 0..5 (_tier): the middle three of four progress measures (peak ants, raids, generations, nest levels
#     open), each counted against five thresholds. It never goes down, so nothing the colony made disappears.
#     1 wood (planks, logs, crates)  2 carpentry (barrels, ladders, frames)  3 iron tools (buckets, anvils, helmets)
#     4 machinery (gears, chains, pulleys, lanterns)  5 foundry (trusses, corrugated sheet, saws)
#   larders: crates, barrels and buckets, as many as the stores are full (up to 2 + level, +1 with the Food Cellar)
#   other rooms: their own kit (ROOM_KIT), one more thing per level; deep rooms (level 5+ of the nest) get iron gear
#     from level 4; nurseries get a bucket with the Nurse Caste, armories a riveted helmet with any armour item
#   the entrance hall (the first floors under the main mouth): a palisade after the first raid, a gate after the third,
#     a spike barricade after the fifth (or with the Thorn Barricade), crossed stakes after the seventh (or with Tunnel
#     Traps), a cage after the eighth; outpost mouths get a fence after the first raid
#   shafts: from level 2 a ladder at the foot of every tall straight shaft (the tallest MAX_LADDERS); digging gear
#     beside some of them with a digging item from the Lab; from level 4 a pulley hangs over the tallest two
#   the queen's chamber: a barrel of jelly and the guards' shield and helmet from level 2, a hanging lantern from 4
# Items never float: each stands on floor cells (open, solid under it) that are level within a cell across the
# middle of its width and have the headroom for it (it may shrink to 72% to fit, never more); hanging things hang
# from a ceiling cell.

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
# Lab purchases that change the props (bit i of the cache key)
const LAB_KEYS = ["barricade", "landmines", "piggy", "tools", "dynamite", "burrow", "helmet", "glass", "vest", "tardigrade", "medikit"]
const PROP_OVERLAP = 0.25      # share of the narrower of two neighbours they may overlap
const MAX_LADDERS = 7
const LADDER_RUN = 7           # straight open cells above a floor that make a shaft worth a ladder
const GLOW_TEX = "res://particles/sprites/particle_28.png"

var _pman = null               # props manifest: name -> entry
var _specs := {}               # name -> _spec() result (null: no such item / no picture)
var _props := []               # [{"tex", "rect": Rect2 (world px, negative width = mirrored), "mod": Color, "x0", "x1", "glow"?}]
var _occ := []                 # footprints placed so far in a rebuild
var _prop_key := ""
var _prop_next := 0.0
var _food_lv := 0
var _glow = null
var props_rebuilds := 0
var props_ms := 0.0
var props_tier := 0
var _geo_key := ""          # the nest's layout (rooms, levels, mouths): floors and shafts are cached per layout
var _floor_cache := {}
var _shaft_key := "-"
var _shaft_list := []
var _dbg_t := {}


func _manifest() -> Dictionary:
	if _pman == null:
		_pman = {}
		var f = File.new()
		if f.open(PROPS_MANIFEST, File.READ) == OK:
			var res = JSON.parse(f.get_as_text())
			f.close()
			if res.error == OK and res.result is Dictionary and res.result.get("items") is Dictionary:
				_pman = res.result["items"]
	return _pman


static func _steps(v: float, th: Array) -> int:
	var n := 0
	for t in th:
		if v >= t:
			n += 1
	return n


# The colony's milestone level, 0..5 (see the rules above).
func _tier() -> int:
	var v = [_steps(sim.peak_ants, [25, 50, 90, 150, 230]), _steps(sim.raid_n, [1, 3, 6, 10, 15]),
		_steps(sim.max_gen, [3, 6, 10, 15, 22]), _steps(sim.planner.open_levels(), [4, 6, 8, 10, 12])]
	v.sort()
	return int(round((v[1] + v[2] + v[3]) / 3.0))


# Every half second: has anything the props depend on changed? (The larder level has a little hysteresis, so stores
# hovering at a step do not refurnish the room back and forth.)
func _props_check() -> void:
	if _t < _prop_next:
		return
	_prop_next = _t + 0.5
	var f = clamp(sim.food / max(1.0, sim.food_cap), 0.0, 1.0) * 6.0
	if f > _food_lv + 1.15 or f < _food_lv - 0.15:
		_food_lv = int(clamp(floor(f), 0.0, 6.0))
	var lab := 0
	for i in LAB_KEYS.size():
		if sim.owned.has(LAB_KEYS[i]):
			lab |= 1 << i
	var key = "%d|%d|%d|%d|%d|%d|%d" % [sim.planner.chambers.size(), _tier(), _food_lv, _steps(sim.raid_n, [1, 3, 5, 7, 8]), lab,
		sim.planner.open_levels(), g.entrances.size()]
	if key == _prop_key:
		return
	_prop_key = key
	var t0 = OS.get_ticks_usec()
	_props_rebuild()
	props_ms = (OS.get_ticks_usec() - t0) / 1000.0
	props_rebuilds += 1


func _draw_props(ci: CanvasItem) -> void:
	if _props.empty():
		return
	var C = g.CELL
	var xa = _cols[0] * C
	var xb = _cols[1] * C
	for p in _props:
		if p["x1"] < xa or p["x0"] > xb:
			continue
		if p.has("glow") and _glow != null:
			var gr: Rect2 = p["glow"]
			ci.draw_texture_rect(_glow, gr, false, Color(1.0, 0.8, 0.45, 0.32))
		ci.draw_texture_rect(p["tex"], p["rect"], false, p["mod"])


func debug_info() -> Dictionary:
	var t0 = OS.get_ticks_usec()
	_props_rebuild()
	var ms2 = (OS.get_ticks_usec() - t0) / 1000.0
	var kinds := {}
	for c in sim.planner.chambers:
		if c["purpose"] == "food" and c["z"] == 0:
			var cx = c["center"].x
			var rx = c["rx"]
			print("FOODFLOORS c=", c["center"], " floor=", c["floor"], " ", _floors(int(cx - rx) - 1, int(cx + rx) + 1, int(c["center"].y - c["ry"]) - 1, int(c["center"].y + c["ry"] * 1.5) + 3, int(c["floor"]) + 1))
	for p in _props:
		kinds[p["name"]] = kinds.get(p["name"], 0) + 1
	return {"tier": props_tier, "props": _props.size(), "rebuilds": props_rebuilds, "ms": props_ms, "food_lv": _food_lv, "kinds": kinds, "t": _dbg_t, "ms_again": ms2}


func _props_rebuild() -> void:
	_props = []
	_occ = []
	var gk = "%d|%d|%d|%d|%d" % [sim.planner.chambers.size(), sim.planner.open_levels(), g.entrances.size(), _lo, _hi]
	if gk != _geo_key:
		_geo_key = gk
		_floor_cache = {}
	if _manifest().empty():
		return
	if _glow == null and ResourceLoader.exists(GLOW_TEX):
		_glow = load(GLOW_TEX)
	var tier = _tier()
	props_tier = tier
	var raids = sim.raid_n
	var own = sim.owned
	var C = g.CELL
	var ex = int(g.entrance.x)
	var esy = g.surf_y(ex)
	# the entrance hall: the first floors under the main mouth, above the queen's chamber
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
	if not hall.empty():
		var yb = esy + 26
		if abs(g.chamber.x - ex) < g.chamber_r.x + 6:
			yb = min(yb, int(g.chamber.y - g.chamber_r.y) - 1)
		_furnish(_floors(ex - 26, ex + 26, esy + 3, yb, esy + 3), hall, ex * 7.1, [Vector2(ex - 1.5, ex + 2.5) * C], ex)
	for i in range(1, g.entrances.size()):
		if raids >= 1:
			var en = g.entrances[i]
			var sy2 = g.surf_y(int(en.x))
			_furnish(_floors(int(en.x) - 16, int(en.x) + 16, sy2 + 3, sy2 + 22, sy2 + 3), ["fence"], en.x * 3.3, [Vector2(en.x - 1.5, en.x + 2.5) * C], int(en.x))
	# shafts: ladders at the foot of the tall straight ones, a hoist over the tallest
	var tq0 = OS.get_ticks_usec()
	if tier >= 2:
		_ladders(tier, own.has("tools") or own.has("dynamite") or own.has("burrow"))
	_dbg_t["ladders"] = (OS.get_ticks_usec() - tq0) / 1000.0
	tq0 = OS.get_ticks_usec()
	# the rooms
	var piggy = own.has("piggy")
	var armour = own.has("helmet") or own.has("glass") or own.has("vest") or own.has("tardigrade")
	for c in sim.planner.chambers:
		if c.get("z", 0) != 0:
			continue
		var p = c["purpose"]
		var kit: Array = ROOM_KIT.get(p, [])
		var items := []
		if p == "food":
			if tier >= 1:
				var n = int(round(_food_lv / 6.0 * (2 + tier))) + (1 if piggy and _food_lv > 0 else 0)
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
		var sd = c["center"].x * 7.13 + c["center"].y * 3.71
		if tier >= 4 and c.get("level", 0) >= 4:
			items.append(DEEP_IRON[int(MK.hash1(sd + 11.0) * DEEP_IRON.size()) % DEEP_IRON.size()])
			if tier >= 5:
				items.append(DEEP_IRON[int(MK.hash1(sd + 13.0) * DEEP_IRON.size()) % DEEP_IRON.size()])
		if items.empty():
			continue
		var cx = c["center"].x
		var rx = c["rx"]
		var clear := []
		match p:
			"farm":
				clear = [Vector2((cx + 0.5 - rx * 0.5) * C, (cx + 0.5 + rx * 0.5) * C)]
			"midden":
				clear = [Vector2((cx + 0.5 - rx * 0.35) * C, (cx + 0.5 + rx * 0.35) * C)]
			"cistern":
				clear = [Vector2((cx + 0.5 - rx * 0.7) * C, (cx + 0.5 + rx * 0.7) * C)]
		var fr = int(c["floor"]) + 1
		_furnish(_floors(int(cx - rx) - 1, int(cx + rx) + 1, int(c["center"].y - c["ry"]) - 1, int(c["center"].y + c["ry"] * 1.5) + 3, fr), items, sd, clear)
		if tier >= 4 and p == "architects":
			_hang_lantern(c["center"], rx, sd)
	_dbg_t["rooms"] = (OS.get_ticks_usec() - tq0) / 1000.0
	# the queen's chamber
	if tier >= 2:
		var qk: Array = ROOM_KIT["queen"]
		var qi := []
		for i in int(clamp(tier - 1, 0, qk.size())):
			if ITEM_TIER.get(qk[i], 0) <= tier:
				qi.append(qk[i])
		var qc = g.chamber
		var qr = g.chamber_r
		_furnish(_floors(int(qc.x - qr.x) - 1, int(qc.x + qr.x) + 1, int(qc.y - qr.y) - 1, int(qc.y + qr.y) + 3, int(qc.y + qr.y)), qi, qc.x * 5.3 + qc.y, [])
		if tier >= 4:
			_hang_lantern(qc, qr.x, qc.x * 5.3 + 4.0)


# Floor columns of a box: for every column, the open cell with solid ground under it nearest to row pref_y, and the
# open headroom above it in cells: {x: [floor_row, headroom]}. Cached per box until the nest's layout changes.
func _floors(xa: int, xb: int, ya: int, yb: int, pref_y: int) -> Dictionary:
	var ck = "%d,%d,%d,%d,%d" % [xa, xb, ya, yb, pref_y]
	if _floor_cache.has(ck):
		return _floor_cache[ck]
	var out := {}
	_floor_cache[ck] = out
	var W = g.W
	var ox = g.ox
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


# Size of an item in world px at scale 1 (from the manifest's game size), with its texture and its base and top points.
func _spec(name: String):
	if _specs.has(name):
		return _specs[name]
	var e = _manifest().get(name)
	var out = null
	if e is Dictionary:
		var t = Lib.get_lib().tex_mip(str(e.get("file", "")))
		if t != null:
			var w = float(e["w"])
			var h = float(e["h"])
			var k = float(e.get("game_size", 30.0)) / max(w, h)
			out = {"tex": t, "w": w * k, "h": h * k, "base": Vector2(e["base"][0], e["base"][1]) * k, "top": Vector2(e["top"][0], e["top"][1]) * k}
	_specs[name] = out
	return out


# Put each item of the list on the floor columns fl, in turn on the left and on the right (which side first is seeded by
# sd): from the walls inwards, or outwards from column `around` (the entrance hall, a ladder). clear: [Vector2(x0, x1)]
# px spans to keep free (the larder's gems, the garden's fungus). An item that fits nowhere is left out.
func _furnish(fl: Dictionary, items: Array, sd: float, clear: Array, around = null) -> void:
	if fl.empty() or items.empty():
		return
	var xs = fl.keys()
	xs.sort()
	var first = 0 if MK.hash1(sd) < 0.5 else 1
	for k in items.size():
		var sp = _spec(items[k])
		if sp == null:
			continue
		var jit = 0.94 + 0.12 * MK.hash1(sd + k * 2.3)
		var w = sp["w"] * jit
		var h = sp["h"] * jit
		var cand := []
		var right = (k + first) % 2 == 1
		if around == null:
			cand = xs.duplicate()
			if right:
				cand.invert()
		else:
			for x in xs:
				if (x > around) == right:
					cand.append(x)
			cand.sort_custom(NearSorter.new(around), "less")
			var other := []
			for x in xs:
				if (x > around) != right:
					other.append(x)
			other.sort_custom(NearSorter.new(around), "less")
			cand += other
		var placed = false
		for min_s in [0.97, 0.72]:
			for x in cand:
				var r = _fit(fl, x, w, h, clear, min_s)
				if r == null:
					continue
				_add_prop(items[k], sp, r[0], r[1], r[2], MK.hash1(sd + k * 1.7) < 0.5)
				placed = true
				break
			if placed:
				break


# Can an item w x h px stand centred on column x? Returns [centre x, floor y, scale] or null.
func _fit(fl: Dictionary, x: int, w: float, h: float, clear: Array, min_s: float):
	var C = g.CELL
	var cx = (x + 0.5) * C
	var a = int(floor((cx - w * 0.4) / C))
	var b = int(floor((cx + w * 0.4) / C))
	var lo = 1 << 20
	var hi = -1
	var ceil_y = -1e9
	for xx in range(a, b + 1):
		if not fl.has(xx):
			return null
		var f = fl[xx]
		lo = min(lo, f[0])
		hi = max(hi, f[0])
		ceil_y = max(ceil_y, (f[0] - f[1] + 1) * C)
	if hi - lo > 1:
		return null
	for z in clear:
		if cx + w * 0.4 > z.x and cx - w * 0.4 < z.y:
			return null
	var base = (hi + 1) * C + 1.5
	var s = min(1.0, (base - ceil_y - 3.0) / h)
	if s < min_s:
		return null
	var foot = Rect2(cx - w * s * 0.5, base - h * s, w * s, h * s)
	for o in _occ:
		if _overlap(foot, o):
			return null
	return [cx, base, s]


static func _overlap(a: Rect2, b: Rect2) -> bool:
	var ox = min(a.end.x, b.end.x) - max(a.position.x, b.position.x)
	var oy = min(a.end.y, b.end.y) - max(a.position.y, b.position.y)
	return ox > PROP_OVERLAP * min(a.size.x, b.size.x) and oy > 2.0


# A prop standing with its base point on (cx, base), drawn at scale s (sx: a different width scale, for ladders).
func _add_prop(name: String, sp: Dictionary, cx: float, base: float, s: float, mirror: bool, sx: float = -1.0) -> void:
	if sx < 0.0:
		sx = s
	var w = sp["w"] * sx
	var h = sp["h"] * s
	var bx = sp["base"].x * sx
	var by = sp["base"].y * s
	var pos = Vector2(cx - (w - bx if mirror else bx), base - by)
	_occ.append(Rect2(pos, Vector2(w, h)))
	_props.append({"name": name, "tex": sp["tex"], "rect": Rect2(pos, Vector2(-w if mirror else w, h)), "mod": _shade(base), "x0": pos.x, "x1": pos.x + w})


# Back-wall darkening: a little darker than the ants, more so deeper down (as the roots and pebbles are).
func _shade(y: float) -> Color:
	var d = clamp((y / g.CELL - g.surf_y(int(g.entrance.x))) / 150.0, 0.0, 1.0)
	var k = 0.9 * (1.0 - 0.3 * d)
	return Color(k, k, k)


# Hang a lantern cage from the ceiling of a room, a little off its middle, with a warm glow round it.
func _hang_lantern(center: Vector2, rx: float, sd: float) -> void:
	var sp = _spec("lantern_cage")
	if sp == null:
		return
	var C = g.CELL
	var W = g.W
	for tries in 3:
		var x = int(round(center.x + (MK.hash1(sd + tries * 3.1) - 0.5) * rx * 0.9))
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
		var gc = r.position + r.size * 0.5 + Vector2(0, 4)
		_props.append({"name": "lantern_cage", "tex": sp["tex"], "rect": r, "mod": _shade(top).lightened(0.15), "x0": gc.x - 40.0, "x1": gc.x + 40.0,
			"glow": Rect2(gc - Vector2(40, 32), Vector2(80, 64))})
		return


# Shafts: straight vertical runs of open cells at least LADDER_RUN tall that end on a floor and are narrow (a shaft, not
# a room), one per shaft (the tallest column of it), tallest first: [[x, floor row, run, open cells left, right]].
# Cached until the nest's layout changes (rooms, levels, mouths).
func _shaft_spots() -> Array:
	if _geo_key == _shaft_key:
		return _shaft_list
	_shaft_key = _geo_key
	var W = g.W
	var ox = g.ox
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
			# narrow? count the open cells beside the middle of the run
			var jm = (y - run / 2) * W + (x - ox)
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
	groups.sort_custom(self, "_taller")
	_shaft_list = groups
	return groups


# The tallest shafts get a ladder standing at the foot, squeezed to the shaft's width.
func _ladders(tier: int, digging: bool) -> void:
	var W = g.W
	var ox = g.ox
	var solid = g.solid
	var C = g.CELL
	var groups = _shaft_spots()
	var lad = _spec("ladder")
	var pick = _spec("pickaxe_head")
	var hoist = _spec("pulley")
	var n := 0
	var hung := 0
	for s in groups:
		if n >= MAX_LADDERS or lad == null:
			break
		var x = s[0]
		var y = s[1]
		var run = s[2]
		var wid = s[3] + s[4] + 1
		var cx = (x - s[3]) * C + wid * C * 0.5
		var base = (y + 1) * C + 1.5
		var h = clamp(run * C - 6.0, 30.0, 58.0)
		var s_h = h / lad["h"]
		var s_w = min(s_h, (wid * C - 1.0) / lad["w"])
		var foot = Rect2(cx - lad["w"] * s_w * 0.5, base - h, lad["w"] * s_w, h)
		var clash = false
		for o in _occ:
			if _overlap(foot, o):
				clash = true
		if clash:
			continue
		_add_prop("ladder", lad, cx, base, s_h, false, s_w)
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
				_props.append({"name": "pulley", "tex": hoist["tex"], "rect": hr, "mod": _shade(top), "x0": pos.x, "x1": pos.x + hr.size.x})
				hung += 1


func _taller(a, b) -> bool:
	return a[2] > b[2]


class NearSorter:
	var o: int
	func _init(origin: int) -> void:
		o = origin
	func less(a, b) -> bool:
		return abs(a - o) < abs(b - o)
