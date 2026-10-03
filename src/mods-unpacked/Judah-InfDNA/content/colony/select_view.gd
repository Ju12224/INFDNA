extends Control
# The player's drag-box, drawn in screen space above the world (colony_scene owns the state: `boxing`, `box_a`, `box_b`).

var scene


func _process(_delta: float) -> void:
	if scene != null and scene.boxing:
		update()
	elif _was:
		update()
	_was = scene != null and scene.boxing


var _was := false


func _draw() -> void:
	if scene == null or not scene.boxing:
		return
	var r = Rect2(scene.box_a, scene.box_b - scene.box_a).abs()
	draw_rect(r, Color(0.45, 0.8, 1.0, 0.14))
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.55), false, 4.0)
	draw_rect(r, Color(0.7, 0.92, 1.0, 0.95), false, 2.0)
