extends Node
# The optimizer: adaptive quality. It watches the real frame time and trades detail for smoothness, then
# wins the detail back once the game has been smooth for a while. The player can also lock a tier
# (Quality button in the Layers panel: Auto / High / Medium / Low).
#
# Tier 3 = everything. Each lower tier drops the costliest detail first:
#   shadows   0 none | 1 one soft ellipse | 2 full soft shadows
#   backdrop  0 sky + nearest hills | 1 + farmland and pines | 2 + mountains and clouds | 3 + birds, sun rays, wisps
#   scenery   0 landmarks only | 1 half the ground clutter | 2 all of it
#   ants      0 no pose animation, no dust | 1 no dust | 2 full
#   fx        cap on combat effects drawn per frame
#   budget    sim milliseconds allowed per rendered frame (microseconds here)
#   shader    0 full terrain shader | 1 cheaper terrain shader (fewer noise octaves)

const NAMES = ["Minimal", "Low", "Medium", "High"]
const MODE_NAMES = ["Auto", "High", "Medium", "Low"]
const TABLE = [
	{"shadows": 0, "backdrop": 0, "scenery": 0, "ants": 0, "fx": 40, "budget": 5000, "pairs": 0.3, "baker": 3, "shader": 1},
	{"shadows": 1, "backdrop": 1, "scenery": 1, "ants": 1, "fx": 90, "budget": 6500, "pairs": 0.2, "baker": 3, "shader": 1},
	{"shadows": 2, "backdrop": 2, "scenery": 2, "ants": 2, "fx": 160, "budget": 8000, "pairs": 0.12, "baker": 4, "shader": 0},
	{"shadows": 2, "backdrop": 3, "scenery": 2, "ants": 2, "fx": 400, "budget": 9000, "pairs": 0.08, "baker": 6, "shader": 0},
]

var scene
var tier := 3
var mode := 0                # 0 = auto; 1..3 = locked to High / Medium / Low
var ft := 0.0167             # smoothed frame time, seconds
var shadows := 2
var backdrop := 3
var scenery := 2
var ants := 2
var fx := 400
var budget := 9000
var pairs := 0.08
var baker_batch := 6
var shader := 0
var _bad := 0.0
var _good := 0.0
var _hold := 0.0
var _since_up := 99.0
var _applied_shader := -1


func _ready() -> void:
	apply()


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	ft = lerp(ft, min(delta, 0.25), 0.06)
	_since_up += delta
	_hold = max(0.0, _hold - delta)
	if mode != 0:
		return
	if scene != null and (scene.shop_open or scene.speed == 0.0):
		_bad = 0.0                   # a paused or menu frame says nothing about the load
		return
	if ft > 0.0235:                  # under about 42 fps
		_good = 0.0
		_bad += delta
		if _bad > 1.5 and tier > 0:
			_bad = 0.0
			if _since_up < 10.0:
				_hold = 120.0        # the last step up did not hold: do not try again soon
			set_tier(tier - 1)
	elif ft < 0.0185:                # near or above 54 fps: there may be room
		_bad = 0.0
		_good += delta
		if _good > 25.0 and tier < 3 and _hold <= 0.0:
			_good = 0.0
			_since_up = 0.0
			set_tier(tier + 1)
	else:
		_bad = max(0.0, _bad - delta)
		_good = 0.0


func cycle_mode() -> void:
	mode = (mode + 1) % 4
	_bad = 0.0
	_good = 0.0
	if mode != 0:
		set_tier(4 - mode)       # High -> 3, Medium -> 2, Low -> 1
	else:
		set_tier(3)


func label() -> String:
	if mode == 0:
		return "Quality: Auto (%s)" % NAMES[tier]
	return "Quality: %s" % MODE_NAMES[mode]


func set_tier(t: int) -> void:
	tier = int(clamp(t, 0, 3))
	apply()


func apply() -> void:
	var T = TABLE[tier]
	shadows = T["shadows"]
	backdrop = T["backdrop"]
	scenery = T["scenery"]
	ants = T["ants"]
	fx = T["fx"]
	budget = T["budget"]
	pairs = T["pairs"]
	baker_batch = T["baker"]
	shader = T["shader"]
	if scene != null:
		if scene.world_view != null and scene.world_view.terrain != null and _applied_shader != shader:
			_applied_shader = shader
			scene.world_view.terrain.set_quality(shader)
		if scene.baker != null:
			scene.baker.batch = baker_batch
		if scene.layers_view != null:
			scene.layers_view.pair_every = pairs
		if scene.hud != null:
			scene.hud.sync_quality()
