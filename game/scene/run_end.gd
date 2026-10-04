extends Control
# The end of a run. colony.gd opens it when the colony collapses, after putting the colony in Run.last_sim. It shows what happened
# (the cause, days lived, the crowd it grew to, raids, winters, how far it took the arc, the queen's best), lets the player hand one
# trait of the champion strain down to the next queen (core/legacy.gd), writes the colony's fall into the Wild (core/wild.gd: its
# strain may come back as the next rival, Run.kin), and pays what the run earned into the Lab's bank (core/shop_items.gd). Then
# the Lab (scene/lab.tscn), or straight back to the title.
# Opened on its own (tests/shot.gd scene=res://scene/run_end.tscn) it plays a short colony to the end first and writes nothing.

const Kit = preload("res://scene/menu_kit.gd")
const Run = preload("res://scene/run.gd")
const Sim = preload("res://core/colony_sim.gd")
const Day = preload("res://scene/day.gd")
const Arc = preload("res://core/arc.gd")
const RunLog = preload("res://core/run_log.gd")
const Legacy = preload("res://core/legacy.gd")
const Wild = preload("res://core/wild.gd")
const ShopItems = preload("res://core/shop_items.gd")
const BugReport = preload("res://core/bug_report.gd")

const PREVIEW_T = 420.0      # sim seconds the stand-alone preview plays

var sim
var _dry := false            # the stand-alone preview: nothing is saved
var _heir_note: Label
var _heir_btns := []


func _ready() -> void:
	get_tree().paused = false
	get_tree().auto_accept_quit = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sim = Run.last_sim
	if sim == null:
		_dry = true
		sim = Sim.new(77, Run.queen_id, {}, {})
		while sim.time < PREVIEW_T and not sim.collapsed:
			sim.step(0.1)
		if not sim.collapsed:
			sim.collapsed = true
			sim.collapse_reason = "The queen has fallen."
	Kit.sky(self, 0.77)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.04, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var settled = _settle()
	_build(settled)
	BugReport.write("colony fell")


# Everything the fall writes, once per colony: the record, the Wild, the bank. Returns what to show.
func _settle() -> Dictionary:
	var qname = str(sim.queen_def.get("name", "The Founder"))
	var arc_best = int(max(int(sim.get_meta("arc_best", 0)), int(sim.arc_stage)))
	var out := {"earn": ShopItems.earnings(sim, arc_best), "arc": arc_best, "wild": [], "record": {}, "bank": 0}
	if sim.has_meta("run_end"):
		return sim.get_meta("run_end")
	if _dry:
		out["record"] = {"new": false, "best": RunLog.load_all().get(sim.queen_def["id"], {"time": sim.time, "raids": sim.raid_n})}
		out["bank"] = ShopItems.lab_load()["bank"] + int(out["earn"].back()[1])
		return out
	out["record"] = RunLog.record(str(sim.queen_def["id"]), sim.time, sim.raid_n, sim.peak_ants)
	if not sim.wild_saved:
		sim.wild_saved = true
		out["wild"] = Wild.finish_run(sim, qname)
	var lab = ShopItems.lab_load()
	lab["bank"] = int(lab["bank"]) + int(out["earn"].back()[1])
	lab["items"] = {}                         # the Lab items went into this colony and fell with it
	lab["raids"] = sim.raid_n
	ShopItems.lab_save(lab)
	out["bank"] = lab["bank"]
	Run.items = {}
	Run.kin = Wild.active()
	sim.set_meta("run_end", out)
	return out


func _build(s: Dictionary) -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var p = Kit.panel("frame_wide", 1.0, Vector2(26, 14))
	cc.add_child(p)
	var v = Kit.vbox(10)
	p.add_child(v)
	# the headline: the queen, how long, why it ended
	var head = Kit.hbox(14)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(head)
	var qi = Kit.icon("ui/queen.png", 70)
	if qi != null:
		head.add_child(qi)
	var hv = Kit.vbox(0)
	head.add_child(hv)
	hv.add_child(Kit.label("The colony has fallen" if sim.collapsed else "The run is over", 40, Kit.GOLD, 7))
	var days = 1 + int(floor(sim.time / Day.DAY_LEN + Day.START))
	hv.add_child(Kit.label("%s.   %s lived %d day%s." % [sim.collapse_reason.trim_suffix(".") if sim.collapse_reason != "" else "The colony is gone",
		sim.queen_def.get("name", "The queen"), days, "" if days == 1 else "s"], 20, Kit.INK, 5))
	var cols = Kit.hbox(30)
	v.add_child(cols)
	cols.add_child(_stats(s, days))
	cols.add_child(_legacy_and_lab(s))
	if _dry:
		v.add_child(Kit.label("Preview: nothing from this colony is saved.", 14, Kit.DIM))
	var br = Kit.hbox(14)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(br)
	var title = Kit.button("Quit to title", 20, 0.7, Vector2(200, 54))
	title.pressed.connect(_to_title)
	br.add_child(title)
	var lab = Kit.button("To the Lab", 24, 0.8, Vector2(260, 54))
	lab.add_theme_color_override("font_color", Kit.GOLD)
	lab.pressed.connect(_to_lab)
	br.add_child(lab)


func _stats(s: Dictionary, days: int) -> Control:
	var v = Kit.vbox(6)
	v.custom_minimum_size = Vector2(430, 0)
	v.add_child(Kit.label("WHAT HAPPENED", 15, Kit.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 3)
	v.add_child(grid)
	var rows = [
		["Days survived", "%d   (%s)" % [days, RunLog.clock(sim.time)]],
		["Peak ants", "%d" % sim.peak_ants],
		["Raids repelled", "%d of %d" % [sim.raids_repelled, sim.raid_n]],
		["Winters lived through", "%d" % sim.winters],
		["Generations", "%d" % sim.max_gen],
		["Raiders slain", "%d" % sim.kills],
		["Food hauled", "%d" % int(sim.delivered_total)],
		["The arc reached", Arc.NAMES[clamp(int(s["arc"]), 0, 3)] + (("   (%d void%s sealed)" % [sim.void_cycles, "" if sim.void_cycles == 1 else "s"]) if sim.void_cycles > 0 else "")],
	]
	for r in rows:
		grid.add_child(Kit.label(r[0], 17, Kit.DIM, 3))
		grid.add_child(Kit.label(r[1], 17, Kit.INK, 3))
	var rec: Dictionary = s.get("record", {})
	if rec.get("new", false):
		v.add_child(Kit.label("A new best for %s!" % sim.queen_def.get("name", "this queen"), 18, Kit.GOLD))
	elif rec.get("best") is Dictionary:
		var b = rec["best"]
		v.add_child(Kit.label("Best with this queen: %s, %d raids" % [RunLog.clock(float(b.get("time", 0.0))), int(b.get("raids", 0))], 16, Kit.GOLD, 3))
	var top = sim.top_genomes(1)
	if not top.is_empty():
		v.add_child(Kit.para("Last dominant body plan: " + top[0]["genome"].describe(), 15, 430, Kit.DIM))
	for line in s.get("wild", []):
		v.add_child(Kit.para(str(line), 15, 430, Kit.BAD))
	return v


func _legacy_and_lab(s: Dictionary) -> Control:
	var v = Kit.vbox(6)
	v.custom_minimum_size = Vector2(470, 0)
	v.add_child(Kit.label("PASS ONE TRAIT DOWN TO YOUR NEXT QUEEN", 15, Kit.GOLD))
	var from = "%s, %s" % [sim.queen_def.get("name", "a past colony"), RunLog.clock(sim.time)]
	var cands = Legacy.candidates(sim.champion, sim.founder_genome, from)
	var grp := ButtonGroup.new()
	for h in cands:
		var b = Kit.button(str(h["label"]), 17, 0.55, Vector2(470, 42))
		b.toggle_mode = true
		b.button_group = grp
		b.clip_text = true
		b.pressed.connect(_pick_heirloom.bind(h))
		v.add_child(b)
		_heir_btns.append(b)
	var cur = Legacy.saved()
	_heir_note = Kit.para("The next queen's founders will be born with what you choose." if cur.is_empty()
		else "Now: %s (choose nothing to keep it)." % str(cur.get("label", "")).to_lower(), 15, 470, Kit.DIM)
	v.add_child(_heir_note)
	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	var lh = Kit.hbox(8)
	v.add_child(lh)
	var fi = Kit.icon("ui/food.png", 28)
	if fi != null:
		lh.add_child(fi)
	lh.add_child(Kit.label("EARNED FOR THE LAB", 15, Kit.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 1)
	v.add_child(grid)
	var earn: Array = s["earn"]
	for i in earn.size() - 1:
		grid.add_child(Kit.label(str(earn[i][0]), 16, Kit.INK, 3))
		grid.add_child(Kit.label("+%d" % int(earn[i][1]), 16, Kit.GOOD, 3))
	v.add_child(Kit.label("%d food to spend in the Lab" % int(s["bank"]), 19, Kit.GOOD))
	return v


func _pick_heirloom(h: Dictionary) -> void:
	if not _dry:
		Legacy.save(h)
		Run.heirloom = Legacy.active()
	_heir_note.text = "Chosen: %s. The next queen's founders will be born with it." % str(h["label"]).to_lower()


func _to_lab() -> void:
	Run.last_sim = null
	get_tree().change_scene_to_file(Run.LAB)


func _to_title() -> void:
	Run.last_sim = null
	get_tree().change_scene_to_file(Run.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_to_lab()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not BugReport.closing():
			BugReport.write("game closed", true)
		get_tree().quit()
