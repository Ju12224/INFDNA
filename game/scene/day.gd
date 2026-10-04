extends RefCounted
# Day, night and the year as seen by the views, all a pure function of the colony clock (nothing in the sim reads it).
#   ph: 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset

const Seasons = preload("res://core/seasons.gd")

const DAY_LEN = 420.0                       # sim seconds per day
const START = 0.30                          # a run begins shortly after sunrise
const NIGHT_TINT = Color(0.40, 0.48, 0.80)  # moonlit blue: dark, but the colony stays easy to read
const DUSK_TINT = Color(1.0, 0.80, 0.66)
const RAIN_TINT = Color(0.68, 0.76, 0.88)

var ph := START
var elev := 0.3          # sun height: 1 at noon, -1 at midnight
var night := 0.0         # 0 day .. 1 full night
var warm := 0.0          # 0..1 around sunrise and sunset
var tint := Color.WHITE  # multiply things out in the open air by this
var day_n := 1
var season := 0
var autumn := 0.0
var leaf := 1.0
var snow := 0.0
var cloud := 0.0         # 0..1 how overcast


# force_ph >= 0 pins the time of day (screenshots and tests).
func update(t: float, rain: float, overcast: float, force_ph: float = -1.0) -> void:
	season = Seasons.index(t)
	autumn = Seasons.autumn(t)
	leaf = Seasons.leaf(t)
	snow = Seasons.snow(t)
	cloud = max(rain, overcast * 0.85)
	var d = t / DAY_LEN + START
	day_n = 1 + int(floor(d))
	ph = force_ph if force_ph >= 0.0 else fposmod(d, 1.0)
	elev = -cos(ph * TAU)
	night = smoothstep(0.12, -0.28, elev)
	var h = (elev - 0.02) / 0.22
	warm = exp(-h * h) * (1.0 - night * 0.5)
	var c = Color.WHITE.lerp(NIGHT_TINT, night)
	var w = warm * 0.65 * (1.0 - 0.6 * cloud)
	var wet = Color.WHITE.lerp(RAIN_TINT, cloud)
	var sg = Seasons.grade(t)
	tint = Color(c.r * (1.0 - w + w * DUSK_TINT.r) * wet.r * sg.r, c.g * (1.0 - w + w * DUSK_TINT.g) * wet.g * sg.g,
		c.b * (1.0 - w + w * DUSK_TINT.b) * wet.b * sg.b, 1.0)
