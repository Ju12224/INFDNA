extends Reference
# Day and night as a pure function of the colony clock, shared by every view that lights the surface
# (sky, ground band, units, fireflies). Purely visual: nothing in the sim reads it. The tunnels keep their
# own warm light, so only the open air changes.
#   phase: 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset

const Seasons = preload("res://mods-unpacked/Judah-InfDNA/core/seasons.gd")

const DAY_LEN = 420.0                       # sim seconds per day
const START = 0.30                          # a run begins shortly after sunrise
const NIGHT_TINT = Color(0.40, 0.48, 0.80)  # moonlit blue: dark, but a fight stays easy to read
const DUSK_TINT = Color(1.0, 0.80, 0.66)

var force := -1.0        # >= 0 pins the phase (screenshots and tests)
var locked := false      # the Night layer is off: it stays midday (rain still falls)
var ph := START
var elev := 0.3          # sun height: 1 at noon, -1 at midnight
var night := 0.0         # 0 day .. 1 full night
var warm := 0.0          # 0..1 around sunrise and sunset
var tint := Color.white  # multiply surface colours by this
var day_n := 1
var rain := 0.0          # 0..1, from the sim's weather
var cloud := 0.0         # 0..1 how overcast the sky is: the clouds that gather before the rain and linger after it count, as does the rain itself
var wet := 0.0           # 0..1, how wet the ground still is
# the year (seasons.gd), as the views want it
var season_force := -1.0 # >= 0 pins the year phase (screenshots and tests)
var sea_t := 0.0         # the colony clock the seasons are read from
var season := 0
var snow := 0.0          # snow lying on the ground
var leaf := 1.0          # how much leaf the trees carry
var autumn := 0.0        # how far the leaves have turned
var bloom := 1.0         # flowers in the meadow
var stage := 0           # changes every ~75 s of the year: cached scenery is rebuilt when it does
var snowing := false     # precipitation falls as snow
const RAIN_TINT = Color(0.68, 0.76, 0.88)


func update(t: float, rain_k: float = 0.0, wet_k: float = 0.0, over_k: float = 0.0) -> void:
	rain = rain_k
	wet = wet_k
	cloud = max(rain_k, over_k * 0.85)
	sea_t = season_force * Seasons.YEAR_LEN if season_force >= 0.0 else t
	season = Seasons.index(sea_t)
	snow = Seasons.snow(sea_t)
	leaf = Seasons.leaf(sea_t)
	autumn = Seasons.autumn(sea_t)
	bloom = Seasons.bloom(sea_t)
	stage = Seasons.stage(sea_t)
	snowing = snow > 0.3
	var d = t / DAY_LEN + START
	day_n = 1 + int(floor(d))
	ph = force if force >= 0.0 else (0.5 if locked else fposmod(d, 1.0))
	elev = -cos(ph * TAU)
	night = smoothstep(0.12, -0.28, elev)
	var h = (elev - 0.02) / 0.22
	warm = exp(-h * h) * (1.0 - night * 0.5)
	var c = Color.white.linear_interpolate(NIGHT_TINT, night)
	var w = warm * 0.65
	w *= 1.0 - 0.6 * cloud
	var wet = Color.white.linear_interpolate(RAIN_TINT, cloud)
	var sg = Seasons.grade(sea_t)
	tint = Color(c.r * (1.0 - w + w * DUSK_TINT.r) * wet.r * sg.r, c.g * (1.0 - w + w * DUSK_TINT.g) * wet.g * sg.g, c.b * (1.0 - w + w * DUSK_TINT.b) * wet.b * sg.b, 1.0)


# Colour multiplier for something that is `k` of the way outside (1 = on the surface, 0 = underground).
func tint_at(k: float) -> Color:
	if k >= 0.999:
		return tint
	return Color.white.linear_interpolate(tint, clamp(k, 0.0, 1.0))


func label() -> String:
	if rain > 0.35:
		return "snow" if snowing else "rain"
	if elev < -0.28:
		return "night"
	if elev < 0.2:
		return "dawn" if ph < 0.5 else "dusk"
	return "sunny"
