extends Node2D
# Draws the bird (colony_sim.bird): a soft shadow on the open ground, then the bird itself high above the meadow, stooping
# as it closes on an ant. Drawn before the light pass so dusk and night tint it like everything else.

const CreatureArt = preload("res://mods-unpacked/Judah-InfDNA/content/colony/creature_art.gd")
const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")

var sim
var cam
var ground
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if sim != null and sim.bird != null:
		update()


func _draw() -> void:
	if sim == null or ground == null or sim.bird == null:
		return
	var b = sim.bird
	var C = sim.grid.CELL
	var x = int(b["x"])
	var lane = 0.5
	var gy = GroundView.lane_y(ground.smooth_px(x), lane)
	var ps = GroundView.persp(lane)
	var alt = float(b["alt"])
	var height = (34.0 + 230.0 * alt) * ps
	var pos = Vector2((b["x"] + 0.5) * C, gy - height)
	var fade = clamp(b["t"] / 2.0, 0.0, 1.0)
	# shadow
	draw_set_transform(Vector2(pos.x, gy), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, (95.0 - 25.0 * alt) * ps, Color(0.04, 0.07, 0.03, 0.28 * (1.0 - 0.5 * alt) * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fold = clamp(float(b["dive"]) * 1.2 + (1.0 - alt) * 0.45, 0.0, 1.0)
	CreatureArt.bird(self, pos, 0.95 * ps, _t, int(b["face"]), fold, fade)
