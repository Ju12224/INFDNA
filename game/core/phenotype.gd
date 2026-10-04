extends RefCounted

const ORGAN_UPKEEP_K = 1.0   # organ upkeep scale (tuning knob; 1.0 = the 10-seed A/B config)
# Genome -> performance stats. This is where body parts start to matter:
# selection acts on these numbers, so bodies drift toward what works.

static func compute(g) -> Dictionary:
	var legs := 0
	var leg_len := 0.0
	var tent := 0
	var claws := 0
	var fins := 0
	var size := 0.0
	var armor := 0
	var spikes := 0
	for s in g.segments:
		size += s["r"]
		armor += s["armor"]
		spikes += s["spikes"]
		match s["limb"]:
			"leg":
				legs += s["n"]
				leg_len += s["len"] * s["n"]
			"tentacle":
				tent += s["n"]
			"claw":
				claws += s["n"]
			"fin":
				fins += s["n"]
	var h: Dictionary = g.head()
	var jaw: String = h.get("jaw", "")
	var eyes: int = h.get("eyes", 1)
	var antenna: float = h.get("antenna", 0.0)
	var avg_leg = leg_len / legs if legs > 0 else 0.0

	var speed = 2.2 + legs * 1.3 * (avg_leg / 55.0) + tent * 0.45 - (size - 74.0) / 45.0 - armor * 0.12
	var carry = 2.0 + size / 50.0 + claws * 1.2 + tent * 1.0
	var dig = 0.7 + claws * 0.45 + legs * 0.06
	match jaw:
		"mandible":
			carry += 2.0
			dig += 0.5
		"claw":
			carry += 1.0
			dig += 1.0
		"tentacle":
			carry += 3.0
	var attack = 1.0 + size / 45.0 + claws * 1.3 + spikes * 0.35
	match jaw:
		"mandible":
			attack += 1.2
		"claw":
			attack += 2.2
		"tentacle":
			attack += 0.4
	var limb_count = legs + tent + claws + fins
	var mg = g.morph if "morph" in g else {}
	var wings = int(mg.get("wings", 0))
	var sting = int(mg.get("stinger", 0))
	var acid = int(mg.get("acid", 0))
	var glow = int(mg.get("glow", 0))
	var major = float(mg.get("major", 0.0))
	var repl = float(mg.get("replete", 0.0))
	var hair = float(mg.get("hair", 0.0))
	var camo = float(mg.get("camo", 0.0))
	var two_node = int(mg.get("petiole", 1)) == 2
	speed += wings * 1.6 - major * 1.0 - repl * 1.2 - hair * 0.25 + (0.2 if two_node else 0.0)
	attack += sting * 1.6 + acid * 0.6 + major * 2.0
	dig += major * 0.6
	carry += repl * 3.0 - acid * 0.5
	# --- part forms (v0.20): each specialisation trades one stat for another ---
	var f_sense := 0.0
	var f_thorns := 0.0
	var f_red := 0.0
	var f_hp := 0.0
	var f_upkeep := 0.0
	var f_tunnel := 0.0
	var f_life := 0.0
	var f_phero := 0.0
	var fm = g.forms if "forms" in g else {}
	if spikes > 0:
		match int(fm.get("spike", 0)):
			1:  # thorns: hurt attackers more, snag on the move
				f_thorns += 0.25 * spikes
				speed -= 0.05 * spikes
			2:  # hooked barbs: tear into what they hit, catch on tunnel walls
				attack += 0.25 * spikes
				f_tunnel -= 0.02 * spikes
			3:  # dorsal ridge: a sawtooth crest that deflects bites, costly to grow
				f_red += 0.02 * spikes
				f_upkeep += 0.0006 * spikes
			4:  # propodeal spines: guard the waist, get in the way of loads
				f_red += 0.01 * spikes
				f_thorns += 0.15 * spikes
				carry -= 0.15 * spikes
	if acid == 1:
		match int(fm.get("acid", 0)):
			1:  # venom sacs: burn attackers harder, heavy and fragile
				f_thorns += 0.6
				f_hp -= 4.0
				carry -= 0.5
			2:  # venom-dripping jaws: poisoned bite instead of a defensive burn
				attack += 1.0
				f_thorns -= 0.4
				f_upkeep += 0.001
			3:  # spray nozzle: hits harder in a scrum, a heavy turret to haul around
				attack += 0.8
				speed -= 0.3
				f_upkeep += 0.0015
	if legs > 0:
		match int(fm.get("leg", 0)):
			1:  # digging forelegs: rake soil fast, slow on the trail
				dig += 0.6
				speed -= 0.4
			2:  # jumping hind legs: quick bursts, hungry muscles, less room for loads
				speed += 0.8
				f_upkeep += 0.0015
				carry -= 0.5
			3:  # raptorial forelegs: grab and stab, useless for carrying or digging
				attack += 1.2
				carry -= 1.0
				dig -= 0.2
			4:  # stilt legs: fast and see over the grass, cramped and spindly underground
				speed += 0.6
				f_sense += 2.0
				f_tunnel -= 0.1
				f_hp -= 4.0
	if antenna > 0.0:
		match int(fm.get("antenna", 0)):
			1:  # clubbed: denser sensors at the tip
				f_sense += 3.0
				f_upkeep += 0.0005
			2:  # feathered: huge sensing area, fragile
				f_sense += 5.0
				f_hp -= 3.0
				f_upkeep += 0.0008
			3:  # whip: long reach, drags in tunnels
				f_sense += 4.0
				f_tunnel -= 0.05
			4:  # forked: reads trails in stereo
				f_sense += 2.0
				f_phero += 0.15
				f_upkeep += 0.0006
	if sting == 1:
		match int(fm.get("sting", 0)):
			1:  # barbed: deeper wounds, the sting tears out and shortens life
				attack += 0.8
				f_life -= 20.0
			2:  # scorpion tail: strikes over the head and back at attackers, top-heavy
				attack += 0.6
				f_thorns += 0.4
				speed -= 0.3
			3:  # twin stingers: two venom glands to feed
				attack += 1.2
				f_upkeep += 0.0015
	# --- organ lines (v0.21): tiers are cumulative; tier 3 and fusions are live abilities ---
	var og = g.organs if "organs" in g else {}
	var t_son = int(og.get("sonic", 0))
	var t_ele = int(og.get("electric", 0))
	var t_she = int(og.get("shell", 0))
	var t_sil = int(og.get("silk", 0))
	var t_ton = int(og.get("tongue", 0))
	var t_reg = int(og.get("regen", 0))
	var o_up := 0.0        # organ upkeep, trimmed below (v0.21 A/B: +11% per-ant upkeep untrimmed)
	var ab := {"rally": 0.0, "reach2": 1.0, "web": 0.0, "regen": 0.0, "curl": false, "curl_cd": 10.0, "curl_heal": 0.0,
		"pulse": 0.0, "pulse_r": 0.0, "pulse_cd": 4.0, "arc": 0.0, "arc_n": 0, "arc_r": 0.0, "arc_cd": 5.0,
		"snipe": 0.0, "snipe_r": 0.0, "snipe_cd": 3.0, "snipe_stun": 0.0, "snare_r": 0.0, "snare_t": 0.0, "snare_cd": 6.0,
		"split": 0.0, "sonarweb": false, "thunder": false}
	# sonic: cricket stridulation rallies nearby fighters -> bat echolocation -> pistol-shrimp shockwave
	if t_son >= 1:
		ab["rally"] = 0.15
		o_up += 0.0008
	if t_son >= 2:
		ab["rally"] = 0.25
		f_sense += 6.0
		o_up += 0.0008
		f_hp -= 2.0
	if t_son >= 3:
		ab["pulse"] = 6.0
		ab["pulse_r"] = 3.5
		o_up += 0.002
		speed -= 0.3
	# electric: platypus electroreception -> eel shock on contact -> torpedo-ray chain arc
	if t_ele >= 1:
		f_sense += 4.0
		o_up += 0.0005
	if t_ele >= 2:
		f_thorns += 0.9
		o_up += 0.001
	if t_ele >= 3:
		ab["arc"] = 5.0
		ab["arc_n"] = 3
		ab["arc_r"] = 5.0
		o_up += 0.002
		f_life -= 20.0
	# shell: turtle scutes -> snail shell -> armadillo roll (curls up when badly hurt)
	if t_she >= 1:
		f_red += 0.06
		speed -= 0.3
	if t_she >= 2:
		f_hp += 10.0
		f_red += 0.04
		speed -= 0.4
		f_tunnel -= 0.06
	if t_she >= 3:
		ab["curl"] = true
		dig -= 0.2
	# silk: spinnerets bundle loads -> orb-weaver web slows what it fights -> bolas snare stuns
	if t_sil >= 1:
		carry += 0.8
		o_up += 0.0006
	if t_sil >= 2:
		ab["web"] = 0.45
		o_up += 0.0008
	if t_sil >= 3:
		ab["snare_r"] = 4.0
		ab["snare_t"] = 2.0
		o_up += 0.0015
		attack -= 0.3
	# tongue: anteater lapping -> frog sticky reach -> chameleon ballistic shot
	if t_ton >= 1:
		carry += 1.0
		attack += 0.2
		dig -= 0.1
	if t_ton >= 2:
		ab["reach2"] = 1.6 * 1.6
		o_up += 0.0008
	if t_ton >= 3:
		ab["snipe"] = 7.0
		ab["snipe_r"] = 6.0
		speed -= 0.2
		o_up += 0.0015
	# regen: starfish regrowth -> axolotl gills -> planarian split on death
	if t_reg >= 1:
		ab["regen"] = 0.4
		o_up += 0.0008
	if t_reg >= 2:
		ab["regen"] = 1.2
		f_life += 30.0
		o_up += 0.001
		speed -= 0.2
	if t_reg >= 3:
		ab["split"] = 0.3
		o_up += 0.0015
	f_upkeep += o_up * ORGAN_UPKEEP_K
	# fusions (both lines at tier 2+): new abilities built from the two parents
	var fus = g.fusions() if g.has_method("fusions") else []
	if "thunderclap" in fus:
		ab["thunder"] = true
		if ab["pulse"] <= 0.0:     # no cannon yet: the ears + eel organ still crack a small clap
			ab["pulse"] = 3.0
			ab["pulse_r"] = 2.5
			ab["pulse_cd"] = 6.0
		ab["pulse"] *= 1.5
	if "slingshot" in fus:
		if ab["snipe"] <= 0.0:     # silk line flings the sticky tongue
			ab["snipe"] = 4.0
			ab["snipe_r"] = 5.0
			ab["snipe_cd"] = 4.0
		ab["snipe_r"] *= 1.6
		ab["snipe_stun"] = 1.0
	if "fortress" in fus:
		ab["curl"] = true
		ab["curl_heal"] = 4.0
		ab["curl_cd"] = 7.0
	if "sonarweb" in fus:
		ab["sonarweb"] = true
		f_sense += 6.0
	ab["abil"] = ab["regen"] > 0.0 or ab["curl"] or ab["pulse"] > 0.0 or ab["arc"] > 0.0 or ab["snipe"] > 0.0 or ab["snare_r"] > 0.0
	var extra_upkeep = f_upkeep + 0.004 * wings + 0.0015 * sting + 0.002 * acid + 0.002 * major + 0.001 * glow + 0.001 * camo + 0.0008 * repl
	var hp_mod = -6.0 * wings + 8.0 * repl + 4.0 * major + f_hp
	var red_mod = 0.04 * hair + 0.08 * camo + f_red
	var out = {
		"phero": float(mg.get("phero", 0.0)) + f_phero,
		"wings": wings,
		"speed": clamp(speed, 1.2, 11.0),          # cells / second
		"carry": max(0.5, carry),                  # food per trip
		"dig": max(0.2, dig),                      # cells / second of digging
		"sense": 8.0 + eyes * 6.0 + antenna / 8.0 + glow * 4.0 + f_sense, # cells
		"upkeep": 0.0003 * size + 0.002 * armor + 0.001 * spikes + 0.0005 * limb_count + extra_upkeep,
		"hp": max(6.0, size * 0.6 + armor * 12.0 + hp_mod),
		"attack": attack,                          # damage / second in melee
		"thorns": max(0.0, spikes * 0.6 + acid * 0.8 + f_thorns),  # damage / second returned to attackers
		"armor_red": min(0.65, armor * 0.09 + red_mod), # fraction of damage ignored
		"life": 240.0 + size * 1.0 - wings * 40.0 + f_life, # seconds
		"size": size,
		# big bodies squeeze slowly through tunnels: the key trade-off that splits
		# small nest castes from big surface castes
		"tunnel_mult": clamp(1.5 - size / 140.0 - wings * 0.12 - major * 0.08 + f_tunnel, 0.4, 1.0),
	}
	for k in ab.keys():
		out[k] = ab[k]
	return out
