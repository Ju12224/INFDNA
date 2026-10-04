extends Node
# Procedural ambience, made sample by sample as it plays (no sound files): wind over the meadow (stronger in winter and in rain), the
# hush of rain and of snow, birdsong by day in the mild seasons, crickets after dark, and a low murmur of earth with the odd drip once
# the camera is underground. The sim's own sound events (colony_sim.sfx: "hit", "kill", "raid", ...) are played as short synthesized
# voices on top. Everything goes to the "Master" bus. M mutes and unmutes (and stays that way for the next colony).
# Purely cosmetic: nothing in the sim reads it, apart from emptying sim.sfx once the sounds have been taken.

const RATE = 22050.0
const MAXV = 6                     # sound-effect voices at once
# sfx name -> [length s, start Hz, end Hz, noise share, second harmonic, gain, cooldown s]
const SFX = {
	"hit": [0.09, 170.0, 60.0, 0.45, 0.0, 0.26, 0.07],
	"kill": [0.20, 420.0, 140.0, 0.25, 0.3, 0.28, 0.12],
	"ant_die": [0.14, 640.0, 220.0, 0.10, 0.0, 0.13, 0.10],
	"queen_hit": [0.28, 120.0, 55.0, 0.30, 0.6, 0.36, 0.15],
	"repelled": [0.35, 520.0, 780.0, 0.0, 0.4, 0.20, 1.0],
	"hatch": [0.10, 380.0, 820.0, 0.0, 0.0, 0.15, 0.15],
	"raid": [0.65, 196.0, 175.0, 0.05, 0.9, 0.28, 2.0],
	"boss": [1.10, 62.0, 44.0, 0.35, 0.8, 0.42, 2.0],
}

static var muted := false          # kept across colonies (the screen is rebuilt for each)

var colony
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _st := 0.0                     # seconds of sound made so far (the crickets' clock)
var _lp1 := 0.0
var _lp2 := 0.0
var _lp3 := 0.0
var _lp4 := 0.0
var _hp := 0.0
var _under := 0.0                  # 0 above ground .. 1 well below it
var _bird_t := 4.0
var _bird_left := 0.0
var _bird_len := 0.0
var _bird_f0 := 2800.0
var _bird_sweep := 650.0
var _bird_cyc := 0.2
var _bird_ph := 0.0
var _drip_t := 2.0
var _drip_env := 0.0
var _drip_ph := 0.0
var _vlen := PackedFloat32Array()  # voices: length in samples (a voice is live while its age is below it)
var _vage := PackedFloat32Array()
var _vf0 := PackedFloat32Array()
var _vf1 := PackedFloat32Array()
var _vph := PackedFloat32Array()
var _vnz := PackedFloat32Array()
var _vh := PackedFloat32Array()
var _vg := PackedFloat32Array()
var _cool := {}                    # sfx name -> seconds until it may sound again


func _ready() -> void:
	for a in [_vlen, _vage, _vf0, _vf1, _vph, _vnz, _vh, _vg]:
		a.resize(MAXV)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.15
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = &"Master"
	_player.volume_db = -12.0
	add_child(_player)
	_player.play()
	_player.stream_paused = muted
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M \
			and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
		muted = not muted
		if _player != null:
			_player.stream_paused = muted
		if colony != null and colony.sim != null:
			colony.sim.toasts.append({"text": "Sound off (M)" if muted else "Sound on (M)", "t": 2.0})
		get_viewport().set_input_as_handled()


# The sim's sound events: take them all (so the list never fills), play the ones not on cooldown.
func _take_sfx(delta: float) -> void:
	for k in _cool.keys():
		_cool[k] -= delta
		if _cool[k] <= 0.0:
			_cool.erase(k)
	var list: Array = colony.sim.sfx
	if list.is_empty():
		return
	if not muted:
		for name in list:
			if SFX.has(name) and not _cool.has(name):
				_cool[name] = SFX[name][6]
				_voice(SFX[name])
	list.clear()


func _voice(d: Array) -> void:
	var j := 0                     # the voice nearest its end is the one to give up
	var best := 1e30
	for i in MAXV:
		var left: float = _vlen[i] - _vage[i]
		if left < best:
			best = left
			j = i
	var pitch = randf_range(0.92, 1.08)
	_vlen[j] = d[0] * RATE
	_vage[j] = 0.0
	_vf0[j] = d[1] * pitch
	_vf1[j] = d[2] * pitch
	_vph[j] = 0.0
	_vnz[j] = d[3]
	_vh[j] = d[4]
	_vg[j] = d[5]


func _process(delta: float) -> void:
	if colony == null or colony.sim == null or colony.day == null:
		return
	_take_sfx(delta)
	if _pb == null or muted:
		return
	var frames = mini(_pb.get_frames_available(), 2200)
	if frames < 128:
		return
	_push(frames, delta)


# The world as the ears need it: how far underground the camera is, the weather, the time of day.
func _push(frames: int, delta: float) -> void:
	var sim = colony.sim
	var day = colony.day
	var cam = colony.cam_center()
	var surf = colony.views.get("surface")
	var wx = colony.views.get("weather")
	var gy: float = surf.ground_y(cam.x) if surf != null else colony.ground_y()
	_under = lerpf(_under, clampf((cam.y - gy) / 260.0, 0.0, 1.0), clampf(delta * 2.0, 0.0, 1.0))
	var open = 1.0 - _under
	var winter = day.season == 3
	var rain: float = sim.rain
	var cover: float = day.snow                          # snow lying on the ground
	var night: float = day.night
	var gust: float = wx.gust if wx != null else 0.4
	var fall: float = wx._precip if wx != null else rain
	var snowfall = fall if winter else 0.0               # in winter whatever falls is snow
	var rainfall = 0.0 if winter else rain
	var wind_gain = (0.05 + 0.10 * gust) * (1.0 + 0.8 * cover + 0.7 * rain) * (0.35 + 0.65 * open)
	var a1 = (0.03 + 0.03 * rain) * (1.0 - 0.45 * _under) * (1.0 - 0.3 * cover)
	var rain_gain = 0.16 * rainfall * (0.25 + 0.75 * open)
	var snow_gain = 0.10 * snowfall * (0.25 + 0.75 * open)
	var season_k = [0.7, 1.0, 0.6, 0.0][day.season]
	var cricket_gain = 0.075 * night * open * (1.0 - cover) * (1.0 - rain) * season_k
	var rumble_gain = 0.35 * _under
	# birdsong by day, in the mild seasons, never in rain
	_bird_t -= delta
	if _bird_left > 0.0:
		_bird_left -= delta
	elif _bird_t <= 0.0:
		_bird_t = randf_range(4.0, 10.0) * (2.0 if day.season == 2 else 1.0)
		if night < 0.35 and open > 0.6 and rain < 0.3 and cover < 0.4 and not winter:
			_bird_len = randf_range(0.8, 1.9)
			_bird_left = _bird_len
			_bird_f0 = randf_range(2300.0, 3300.0)
			_bird_sweep = randf_range(450.0, 800.0) * (1.0 if randf() < 0.7 else -0.7)
			_bird_cyc = randf_range(0.14, 0.26)
	# a drip underground now and then
	_drip_t -= delta
	if _drip_t <= 0.0:
		_drip_t = randf_range(1.5, 6.0)
		if _under > 0.5:
			_drip_env = 1.0
	# The sample loop runs ~22000 times a second, so it is kept lean: filter states live in locals, every per-sample constant is
	# worked out once, and the samples go to the player in one push_buffer.
	var bird_on = _bird_left > 0.0
	var inv = 1.0 / RATE
	var t0 = _st
	var lp1 = _lp1
	var lp2 = _lp2
	var lp3 = _lp3
	var lp4 = _lp4
	var hp = _hp
	var wind9 = wind_gain * 9.0
	var rain_on = rain_gain > 0.0
	var snow_on = snow_gain > 0.0
	var snow4 = snow_gain * 3.0
	var crick = cricket_gain > 0.0
	var ch = cricket_gain * 0.5
	var rum_on = rumble_gain > 0.0
	var rum4 = rumble_gain * 4.0
	var b0 = (_bird_len - _bird_left) / _bird_cyc
	var binv = inv / _bird_cyc
	var bph = _bird_ph
	var bf = TAU * _bird_f0 * inv
	var bk = TAU * _bird_sweep * inv
	var denv = _drip_env
	var dph = _drip_ph
	var dk = 0.07 * _under
	var voices = false
	for j in MAXV:
		if _vage[j] < _vlen[j]:
			voices = true
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		var n = randf() * 2.0 - 1.0
		lp1 += (n - lp1) * a1
		lp2 += (lp1 - lp2) * a1
		var v = lp2 * wind9
		if rain_on:
			hp += (n - hp) * 0.35
			v += (n - hp) * rain_gain
		if snow_on:
			lp4 += (n - lp4) * 0.15                     # snow: a soft, dull hush
			v += lp4 * snow4
		if crick:
			# three voices: chirp rate 1.05 / 1.18 / 1.31 Hz, trill 34 / 37 / 40 Hz, pitch 4150 / 4340 / 4530 Hz
			var ts = t0 + i * inv
			if fposmod(ts * 1.05, 1.0) < 0.3:
				var pulse = 0.5 + 0.5 * sin(213.62830044410595 * ts)
				v += sin(26075.219024795285 * ts) * pulse * pulse * ch
			if fposmod(ts * 1.18 + 0.37, 1.0) < 0.3:
				var pulse2 = 0.5 + 0.5 * sin(232.4778563656447 * ts)
				v += sin(27269.024233159467 * ts) * pulse2 * pulse2 * ch
			if fposmod(ts * 1.31 + 0.74, 1.0) < 0.3:
				var pulse3 = 0.5 + 0.5 * sin(251.32741228718345 * ts)
				v += sin(28462.829441523654 * ts) * pulse3 * pulse3 * ch
		if bird_on:
			# a run of short chirps: each one glides in pitch under a smooth envelope
			var cu = fposmod(b0 + i * binv, 1.0)
			if cu < 0.62:
				var cn = cu / 0.62
				var env = sin(PI * cn)
				bph += bf + bk * cn
				v += sin(bph) * env * env * 0.09
		if rum_on:
			lp3 += (n - lp3) * 0.006
			v += lp3 * rum4
		if denv > 0.002:
			dph += TAU * (1500.0 - 500.0 * (1.0 - denv)) * inv
			v += sin(dph) * denv * dk
			denv *= 0.9993
		if voices:
			for j in MAXV:
				var ln = _vlen[j]
				var ag = _vage[j]
				if ag < ln:
					var a = ag / ln
					_vage[j] = ag + 1.0
					var e = (1.0 - a) * (1.0 - a) * minf(a * 60.0, 1.0)
					var ph = _vph[j] + TAU * (_vf0[j] + (_vf1[j] - _vf0[j]) * a) * inv
					_vph[j] = ph
					var s = sin(ph) + _vh[j] * sin(ph * 2.0)
					v += (s * (1.0 - _vnz[j]) + n * _vnz[j]) * e * _vg[j]
		if v > 0.85:
			v = 0.85
		elif v < -0.85:
			v = -0.85
		buf[i] = Vector2(v, v)
	_pb.push_buffer(buf)
	_st += frames * inv
	_lp1 = lp1
	_lp2 = lp2
	_lp3 = lp3
	_lp4 = lp4
	_hp = hp
	_bird_ph = bph
	_drip_env = denv
	_drip_ph = dph
