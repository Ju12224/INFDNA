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
	for i in frames:
		var ts = _t + float(i) / RATE
		var n = randf() * 2.0 - 1.0
		_lp1 += (n - _lp1) * a1
		_lp2 += (_lp1 - _lp2) * a1
		var v = _lp2 * wind_gain * 9.0
		if rain_gain > 0.0:
			_hp += (n - _hp) * 0.35
			v += (n - _hp) * rain_gain
		if cricket_gain > 0.0:
			for q in 3:
				var cyc = fposmod(ts * (1.05 + 0.13 * q) + q * 0.37, 1.0)
				if cyc < 0.3:
					var pulse = 0.5 + 0.5 * sin(TAU * (34.0 + 3.0 * q) * ts)
					v += sin(TAU * (4150.0 + 190.0 * q) * ts) * pulse * pulse * cricket_gain * 0.5
		if bird_on:
			# a run of short chirps: each one glides up in pitch under a smooth envelope
			var cu = fposmod(((_bird_len - _bird_left) + float(i) / RATE) / 0.2, 1.0)
			if cu < 0.62:
				var env = sin(PI * (cu / 0.62))
				_bird_ph += TAU * (_bird_f0 + 650.0 * (cu / 0.62)) / RATE
				v += sin(_bird_ph) * env * env * 0.09
		if rumble_gain > 0.0:
			_lp3 += (n - _lp3) * 0.006
			v += _lp3 * rumble_gain * 4.0
		if _drip_env > 0.002:
			_drip_ph += TAU * (1500.0 - 500.0 * (1.0 - _drip_env)) / RATE
			v += sin(_drip_ph) * _drip_env * 0.07 * _under
			_drip_env *= 0.9993
		v = clamp(v, -0.85, 0.85)
		_pb.push_frame(Vector2(v, v))
