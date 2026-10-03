extends Node
# Procedural ambience: wind over the meadow (stronger in winter and in rain), rain and snow hush, birdsong by day, crickets
# after dark, and a low murmur of earth with the odd drip once the camera is underground. Synthesised sample by sample
# as it plays (no sound files needed), mixed quietly into Brotato's "Sound" bus, so the game's volume settings apply.
# The Sound layer (O) mutes it. Purely cosmetic: nothing in the sim reads it.

const RATE = 22050.0

var sim
var cam
var day
var ground
var enabled := true
var _player: AudioStreamPlayer
var _pb
var _t := 0.0
var _lp1 := 0.0
var _lp2 := 0.0
var _lp3 := 0.0
var _hp := 0.0
var _under := 0.0                 # 0 above ground .. 1 well below it
var _bird_t := 4.0
var _bird_left := 0.0
var _bird_len := 0.0
var _bird_f0 := 2800.0
var _bird_ph := 0.0
var _drip_t := 2.0
var _drip_env := 0.0
var _drip_ph := 0.0


func _ready() -> void:
	var gen = AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = "Sound" if AudioServer.get_bus_index("Sound") != -1 else "Master"
	_player.volume_db = -12.0
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback()


func set_enabled(on: bool) -> void:
	enabled = on
	if _player != null:
		_player.stream_paused = not on


func _process(delta: float) -> void:
	if _pb == null or not enabled or day == null or cam == null:
		return
	_t += delta
	var frames = int(min(_pb.get_frames_available(), 3000))
	if frames <= 0:
		return
	var surf = ground.smooth_px(int(cam.get_camera_screen_center().x / sim.grid.CELL)) if ground != null else 0.0
	var depth = cam.get_camera_screen_center().y - surf
	_under = lerp(_under, clamp(depth / 260.0, 0.0, 1.0), clamp(delta * 2.0, 0.0, 1.0))
	var open = 1.0 - _under
	var rain = day.rain
	var snow = day.snow
	var night = day.night
	var gust = 0.55 + 0.45 * sin(_t * 0.31) * sin(_t * 0.17 + 1.0)
	var wind_gain = (0.07 + 0.08 * gust) * (1.0 + 0.9 * snow + 0.7 * rain) * (0.35 + 0.65 * open)
	var a1 = (0.03 + 0.03 * rain + 0.02 * snow * 0.0) * (1.0 - 0.45 * _under) * (1.0 - 0.3 * snow)
	var rain_gain = 0.16 * rain * (1.0 - snow) * (0.25 + 0.75 * open)
	var cricket_gain = 0.075 * night * open * (1.0 - snow) * (1.0 - rain)
	var rumble_gain = 0.35 * _under
	# birdsong by day, in the mild seasons, never in rain
	_bird_t -= delta
	if _bird_left > 0.0:
		_bird_left -= delta
	elif _bird_t <= 0.0:
		_bird_t = rand_range(5.0, 14.0)
		if night < 0.35 and open > 0.6 and rain < 0.3 and snow < 0.4:
			_bird_len = rand_range(0.8, 1.9)
			_bird_left = _bird_len
			_bird_f0 = rand_range(2300.0, 3300.0)
	# a drip underground now and then
	_drip_t -= delta
	if _drip_t <= 0.0:
		_drip_t = rand_range(1.5, 6.0)
		if _under > 0.5:
			_drip_env = 1.0
	var bird_on = _bird_left > 0.0
	# The sample loop runs ~22000 times a second, so it is kept lean: the filter states live in locals, every per-sample constant
	# is worked out once, the cricket voices are unrolled, and the samples go to the player in one push_buffer (same sound as
	# the old per-sample loop; about half the cost, measured).
	var inv = 1.0 / RATE
	var t0 = _t
	var lp1 = _lp1
	var lp2 = _lp2
	var lp3 = _lp3
	var hp = _hp
	var wind9 = wind_gain * 9.0
	var rain_on = rain_gain > 0.0
	var crick = cricket_gain > 0.0
	var ch = cricket_gain * 0.5
	var rum_on = rumble_gain > 0.0
	var rum4 = rumble_gain * 4.0
	var b0 = (_bird_len - _bird_left) / 0.2
	var binv = inv / 0.2
	var bph = _bird_ph
	var bf = TAU * _bird_f0 * inv
	var bk = TAU * 650.0 * inv
	var denv = _drip_env
	var dph = _drip_ph
	var dk = 0.07 * _under
	var buf := PoolVector2Array()
	buf.resize(frames)
	for i in frames:
		var n = randf() * 2.0 - 1.0
		lp1 += (n - lp1) * a1
		lp2 += (lp1 - lp2) * a1
		var v = lp2 * wind9
		if rain_on:
			hp += (n - hp) * 0.35
			v += (n - hp) * rain_gain
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
			# a run of short chirps: each one glides up in pitch under a smooth envelope
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
		if v > 0.85:
			v = 0.85
		elif v < -0.85:
			v = -0.85
		buf[i] = Vector2(v, v)
	_pb.push_buffer(buf)
	_lp1 = lp1
	_lp2 = lp2
	_lp3 = lp3
	_hp = hp
	_bird_ph = bph
	_drip_env = denv
	_drip_ph = dph
