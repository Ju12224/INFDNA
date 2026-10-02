extends Node
# Brotato sounds for colony events. Uses Brotato's "Sound" bus so the game's
# volume settings apply. Missing files are skipped silently.

const S = {
	"buy": ["res://ui/sounds/buy.wav"],
	"cant_buy": ["res://ui/sounds/cant_buy.wav"],
	"reroll": ["res://ui/sounds/diceroll.wav"],
	"button": ["res://ui/sounds/button_press.wav"],
	"legendary": ["res://resources/sounds/level_up.wav"],
	"hit": ["res://entities/units/unit/hurt_sounds/punch_general_body_impact_01.wav",
		"res://entities/units/unit/hurt_sounds/punch_general_body_impact_03.wav",
		"res://entities/units/unit/hurt_sounds/punch_general_body_impact_05.wav",
		"res://entities/units/unit/hurt_sounds/punch_general_body_impact_07.wav"],
	"ant_die": ["res://projectiles/flesh_explosion/bullet_impact_body_flesh_01.wav",
		"res://projectiles/flesh_explosion/bullet_impact_body_flesh_02.wav"],
	"kill": ["res://projectiles/flesh_explosion/punch_grit_wet_impact_01.wav",
		"res://projectiles/flesh_explosion/punch_grit_wet_impact_02.wav",
		"res://projectiles/flesh_explosion/punch_grit_wet_impact_03.wav"],
	"queen_hit": ["res://projectiles/flesh_explosion/bullet_impact_body_flesh_01.wav"],
	"raid": ["res://resources/sounds/zombie_voice_attack_grunt_01.wav"],
	"boss": ["res://entities/units/enemies/boss/zombie_voice_general_emote_05.wav"],
	"repelled": ["res://ui/sounds/end_wave.wav"],
	"hatch": ["res://entities/birth/birth_end_sound.wav"],
}
const VOL = {"queen_hit": -2.0, "hit": -13.0, "ant_die": -11.0, "kill": -4.0, "hatch": -18.0, "raid": -2.0, "boss": 0.0}
const GAP = {"queen_hit": 0.8, "hit": 0.09, "ant_die": 0.15, "kill": 0.08, "hatch": 0.6}

var sim
var _streams := {}
var _players := []
var _next := 0
var _last := {}
var _time := 0.0


func _ready() -> void:
	for k in S.keys():
		var list := []
		for p in S[k]:
			if ResourceLoader.exists(p):
				list.append(load(p))
		if list.size() > 0:
			_streams[k] = list
	var bus = "Sound" if AudioServer.get_bus_index("Sound") != -1 else "Master"
	for i in 10:
		var pl = AudioStreamPlayer.new()
		pl.bus = bus
		add_child(pl)
		_players.append(pl)


func _process(delta: float) -> void:
	_time += delta
	if sim == null:
		return
	for name in sim.sfx:
		play(name)
	sim.sfx.clear()


func play(name: String) -> void:
	if not _streams.has(name):
		return
	if _time - _last.get(name, -10.0) < GAP.get(name, 0.0):
		return
	_last[name] = _time
	var list = _streams[name]
	var pl: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	pl.stream = list[randi() % list.size()]
	pl.volume_db = VOL.get(name, -6.0)
	pl.pitch_scale = rand_range(0.92, 1.08)
	pl.play()
