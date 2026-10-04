extends Node
# Watch mode: a slow, self-directing camera for sitting back and watching the colony like a fish tank.
# It cuts between "shots" - a fight at the nest, the farthest forager on its expedition, the traffic at
# the hole, a single ant on its job, a digger underground, the queen's chamber - and never lingers
# on an empty patch. Any manual camera input (pan keys, wheel, drag, a click on an ant, a jump key)
# hands the camera back to the player for a few seconds. Purely visual: nothing here touches the sim.

const SHOT_MIN = 11.0
const SHOT_MAX = 19.0
const FIGHT_HOLD = 3.0        # a fight shot stays this long after the last blow
const MAX_FIGHT = 28.0        # a long siege does not pin the camera forever
const HAND_BACK = 6.0         # seconds the camera stays put after the player touches it
const RANK = {"small": 1, "burrower": 2, "brute": 3, "elite": 4, "boss": 5}
const ORDER = ["far", "gate", "ant", "dig", "queen", "ant"]

var scene
var active := false
var _hold := 0.0              # manual-input pause
var _left := 0.0              # time left on this shot
var _quiet := 0.0             # time since the current fight shot last saw a blow
var _since_cut := 0.0
var _kind := ""
var _target := Vector2.ZERO
var _zoom := 0.7
var _unit = null              # ant the shot follows, or null
var focus_enemy = null        # the raider of the fight being shown, or null (meadow_depth.gd parts the grass in front of it)
var _next := 0
var _strain_done := -1.0    # newest strain event already shown
var _fight_block := 0.0     # after a long fight shot the camera looks elsewhere for a while, even if the siege goes on
var _fight_for := 0.0


func set_active(on: bool) -> void:
	active = on
	_hold = 0.0
	_left = 0.0
	_unit = null
	_kind = ""


# The player took the camera.
func note_input(extra: float = 0.0) -> void:
	_hold = HAND_BACK + extra
	_unit = null


func follow(a) -> void:
	_unit = a
	_kind = "pick"
	_left = 14.0
	_hold = 0.0
	_zoom = 0.62


func _process(delta: float) -> void:
	if not active or scene == null:
		return
	if _hold <= 0.0 and (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W)
			or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT)
			or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN)):
		note_input()
	if _hold > 0.0:
		_hold -= delta
		return
	var sim = scene.sim
	_left -= delta
	_since_cut += delta
	_fight_block = max(0.0, _fight_block - delta)
	var fight = _fight_focus() if _fight_block <= 0.0 else null
	if _kind == "fight":
		_fight_for += delta
		if _fight_for > MAX_FIGHT:
			_fight_block = 14.0
			_left = 0.0
			fight = null
	if fight == null and _kind != "strain" and _since_cut > 4.0:
		var sa = scene.newest_strain_ant(_strain_done)
		if sa != null:
			_strain_done = sim.time
			_cut("strain")
			_unit = sa
			_left = 9.0
	if fight != null:
		_quiet = 0.0
		if _kind != "fight" and _since_cut > 2.0:
			_cut("fight")
	elif _kind == "fight":
		_quiet += delta
		if _quiet > FIGHT_HOLD:
			_left = 0.0
	if _left <= 0.0 or (_unit != null and not sim.ants.has(_unit)):
		_cut(_next_kind())
	_aim(delta, fight)


# The raider to watch: the most dangerous one actually fighting; else the nearest hostile near the nest.
func _fight_focus():
	var sim = scene.sim
	var best = null
	var rank = -1
	var nest_x = (sim.grid.entrance.x + 0.5) * sim.grid.CELL
	for e in sim.enemies:
		if e.cls == "prey" or e.state == 2:
			continue
		var r = RANK.get(e.cls, 0) + (10 if e.engaged else 0)
		if not e.engaged and abs(sim.enemy_pos(e).x - nest_x) > 700.0:
			continue
		if r > rank:
			rank = r
			best = e
	return best


func _next_kind() -> String:
	for i in ORDER.size():
		var k = ORDER[(_next + i) % ORDER.size()]
		if _can(k):
			_next = (_next + i + 1) % ORDER.size()
			return k
	return "gate"


func _can(kind: String) -> bool:
	var sim = scene.sim
	match kind:
		"far":
			return _far_forager() != null
		"dig":
			return _digger() != null
		"ant":
			return not sim.ants.empty()
	return true


func _far_forager():
	var sim = scene.sim
	var nest_x = sim.grid.entrance.x
	var best = null
	var bd = 40.0               # cells: closer than this is just "at the gate"
	for a in sim.ants:
		if a.y > sim.grid.surf_y(int(a.x)) + 2:
			continue          # underground
		if a.task != 1 and a.carry <= 0.0:
			continue
		var d = abs(a.x - nest_x)
		if d > bd:
			bd = d
			best = a
	return best


func _digger():
	var sim = scene.sim
	var best = null
	var by = -1
	for a in sim.ants:
		if a.task == 2 and a.y > by:
			by = a.y
			best = a
	return best


func _cut(kind: String) -> void:
	var sim = scene.sim
	var C = sim.grid.CELL
	_kind = kind
	_since_cut = 0.0
	_quiet = 0.0
	_left = rand_range(SHOT_MIN, SHOT_MAX)
	_unit = null
	match kind:
		"fight":
			_zoom = 0.62
			_left = 30.0
			_fight_for = 0.0
		"strain":
			_zoom = 0.45
		"far":
			_unit = _far_forager()
			_zoom = 0.72
		"dig":
			_unit = _digger()
			_zoom = 0.55
		"ant":
			if not sim.ants.empty():
				_unit = sim.ants[randi() % sim.ants.size()]
			_zoom = rand_range(0.5, 0.7)
		"queen":
			_target = Vector2((sim.grid.chamber.x + 0.5) * C, (sim.grid.chamber.y + 0.5) * C)
			_zoom = 0.62
		_:
			_target = Vector2((sim.grid.entrance.x + 0.5) * C, (sim.grid.entrance.y - 7.0) * C)
			_zoom = 0.8


func _aim(delta: float, fight) -> void:
	var sim = scene.sim
	var cam = scene.cam
	var tgt = cam.position
	var rate = 1.7
	focus_enemy = fight if (_kind == "fight" and fight != null) else null
	if _kind == "fight" and fight != null:
		var p = sim.enemy_pos(fight)
		var d = scene.ant_view._depth(-fight.id, scene.ant_view.lane_of(fight, -fight.id))
		tgt = p + Vector2(0, d[0] - 30.0)
		rate = 2.6
	elif _unit != null and sim.ants.has(_unit):
		var d2 = scene.ant_view._depth(_unit.id, scene.ant_view.lane_of(_unit, _unit.id))
		tgt = sim.ant_pos(_unit) + Vector2(0, d2[0] - 30.0)
		rate = 2.2
	elif _kind in ["queen", "gate"]:
		tgt = _target
	else:
		return
	cam.position = cam.position.linear_interpolate(tgt, clamp(1.0 - exp(-rate * delta), 0.0, 1.0))
	var z = clamp(_zoom, cam.min_zoom, cam.max_zoom)
	cam.zoom = cam.zoom.linear_interpolate(Vector2.ONE * z, clamp(1.0 - exp(-1.3 * delta), 0.0, 1.0))
