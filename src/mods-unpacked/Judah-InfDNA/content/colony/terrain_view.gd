extends Node2D
# Terrain in two stacked layers, streamed in CHUNK-wide pieces around the camera:
#   back  - the recessed rear wall of every tunnel and room: darker dirt that drifts
#           slightly with the camera (parallax), receding side walls lit from above,
#           and the drop shadow the front dirt casts into the tunnel;
#   front - the cut face of the soil: strata (humus, clay, sand/gravel, red clay,
#           bedrock), roots, pebbles, fossils, bevelled tunnel rims, ink outline.
#           Open cells are transparent so the back layer shows through.
# Anything placed between the two (see world_view.gd) reads as "inside" the nest.
#
# M2: strata come from the sim (the seam wave is per column in surf_tex.b, the original
# ground in surf_tex.g), so what you see is what digs slowly or fast. aux_tex carries the
# back tunnel plane (shown through the dirt as dark ghosted tunnels), stones and fossils
# (real obstacles) and the holes that join the planes (dark openings in a rear wall).
# Dirt above the original ground is the spoil mound: loose pellets, no turf.

const SHADER_COMMON = """
shader_type canvas_item;
uniform vec2 origin;
uniform vec2 tsize;
uniform sampler2D surf_tex;
uniform sampler2D aux_tex;
uniform vec2 cam;
uniform vec4 ink : hint_color = vec4(0.082, 0.071, 0.102, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.03 + 11.0; a *= 0.5; }
	return v;
}
// the per-column strip is read with a hand-made linear blend between the two nearest columns: on its own the
// sampler can step from column to column, which showed as a staircase in the soil layers up close
vec4 surf_at(float ux) {
	float px = ux * tsize.x - 0.5;
	float i0 = floor(px);
	float f = px - i0;
	float inv = 1.0 / tsize.x;
	return mix(texture(surf_tex, vec2((i0 + 0.5) * inv, 0.5)), texture(surf_tex, vec2((i0 + 1.5) * inv, 0.5)), f);
}
float wave_off(vec2 uv) { return surf_at(uv.x).b * 16.0 - 8.0; }
float base_y(vec2 uv) { return surf_at(uv.x).g * 255.0; }
float layer_depth(float d, float off) { return d + off; }
vec3 strata(float dd) {
	vec3 c = vec3(0.36, 0.23, 0.14);                                  // humus
	c = mix(c, vec3(0.62, 0.40, 0.22), smoothstep(9.0, 11.0, dd));      // subsoil clay
	c = mix(c, vec3(0.74, 0.57, 0.36), smoothstep(30.0, 32.5, dd));     // sand + gravel
	c = mix(c, vec3(0.55, 0.31, 0.22), smoothstep(55.0, 58.0, dd));     // red clay
	c = mix(c, vec3(0.70, 0.66, 0.55), smoothstep(84.0, 88.0, dd));     // limestone
	c = mix(c, vec3(0.33, 0.33, 0.37), smoothstep(120.0, 124.0, dd));   // shale
	c = mix(c, vec3(0.24, 0.22, 0.24), smoothstep(156.0, 160.0, dd));   // bedrock
	float seam = 0.0;
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 10.0));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 31.2));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 56.5));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 86.0));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 122.0));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 158.0));
	// thin bedding planes inside limestone and shale
	seam += 0.5 * (1.0 - smoothstep(0.0, 0.25, abs(fract(dd * 0.2) - 0.5) - 0.2)) * smoothstep(88.0, 90.0, dd) * (1.0 - smoothstep(156.0, 158.0, dd));
	return c * (1.0 - 0.22 * clamp(seam, 0.0, 1.0));
}
"""

const FRONT_SHADER = SHADER_COMMON + """
void fragment() {
	vec4 m = texture(TEXTURE, UV);
	float s = m.r;
	vec2 wc = origin + UV * tsize;
	vec4 ax = texture(aux_tex, UV);
	float d = wc.y - base_y(UV);
	float dd = layer_depth(d, wave_off(UV));
	vec3 col = strata(dd);
	col *= 0.84 + 0.3 * fbm(wc * 0.33);
	col = mix(col, col * 1.13, smoothstep(0.7, 0.8, vnoise(wc * 0.9 + 13.0)));
	vec2 gp = wc * 3.0;
	vec2 gid = floor(gp);
	vec2 gf = fract(gp) - 0.5 - (vec2(hash(gid + 2.3), hash(gid + 5.9)) - 0.5) * 0.5;
	float grain = 1.0 - smoothstep(0.12, 0.3, length(gf));
	float g1 = hash(gid);
	if (g1 > 0.93) { col *= 1.0 - 0.17 * grain; } else if (g1 < 0.05) { col *= 1.0 + 0.11 * grain; }
	// roots hanging through the humus
	if (dd < 17.0) {
		float rn = vnoise(vec2(wc.x * 0.75, wc.y * 0.17));
		float root = (1.0 - smoothstep(0.012, 0.03, abs(rn - 0.5))) * (1.0 - smoothstep(5.0, 17.0, dd));
		col = mix(col, vec3(0.23, 0.14, 0.09), root * 0.9);
	}
	// pebbles: sparse in soil, dense in the gravel band, big in bedrock. Each kind sits on its own fixed grid and fades out
	// pebble by pebble (a grid whose scale changes with depth gets sheared into thin streaks where two kinds meet)
	float sandy = smoothstep(30.0, 33.0, dd) * (1.0 - smoothstep(55.0, 58.0, dd));
	float rocky = smoothstep(156.0, 160.0, dd);
	float soily = (1.0 - sandy) * (1.0 - rocky);
	for (int pk = 0; pk < 3; pk++) {
		float wgt = pk == 0 ? soily : (pk == 1 ? sandy : rocky);
		if (wgt <= 0.001) { continue; }
		float gs = pk == 0 ? 0.5 : (pk == 1 ? 1.0 : 0.275);
		float thr = pk == 0 ? 0.972 : (pk == 1 ? 0.9 : 0.93);
		float rad = pk == 1 ? 0.26 : 0.33;
		vec2 sc = wc * gs + float(pk) * 17.3;
		vec2 cid = floor(sc);
		vec2 f = fract(sc) - 0.5 - (vec2(hash(cid + 3.1), hash(cid + 7.7)) - 0.5) * 0.3;
		float r = length(f * vec2(1.0, 1.25));
		if (hash(cid + 1.3) > thr && hash(cid + 5.5) < wgt && r < rad) {
			vec3 stone = mix(vec3(0.58, 0.55, 0.53), vec3(0.76, 0.66, 0.52), hash(cid + 9.1));
			stone = r < rad - 0.08 ? mix(stone, stone * 1.28, step(f.y, -0.06) * step(f.x, 0.05)) : ink.rgb;
			col = stone;
		}
	}
	// stones and fossils: real obstacles, drawn from the sim's own map
	float st = smoothstep(0.42, 0.58, ax.g);
	if (st > 0.0) {
		vec3 stone = mix(vec3(0.5, 0.49, 0.5), vec3(0.66, 0.62, 0.58), vnoise(wc * 0.3 + 4.0));
		stone *= 0.9 + 0.2 * vnoise(wc * 1.3);
		vec2 sg = vec2(texture(aux_tex, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).g - texture(aux_tex, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).g,
			texture(aux_tex, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).g - texture(aux_tex, UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y)).g);
		float sl = length(sg) > 0.01 ? dot(normalize(sg), vec2(0.45, 0.89)) : 0.0;
		stone *= 1.0 - 0.25 * max(sl, 0.0) * (1.0 - smoothstep(0.6, 0.9, ax.g));
		stone = mix(stone, stone * 1.3, max(-sl, 0.0) * (1.0 - smoothstep(0.6, 0.9, ax.g)));
		if (ax.a < 0.6) {
			// fossil: ribbed bone, the ribs are contour lines of the mask
			vec3 bone = vec3(0.9, 0.84, 0.7);
			stone = mix(bone, bone * 0.72, step(0.55, fract(ax.g * 5.0 + 0.2)));
		}
		col = mix(col, stone, st);
		col = mix(col, ink.rgb, (1.0 - smoothstep(0.03, 0.08, abs(ax.g - 0.5))) * 0.9);
	}
	// the spoil mound: loose pellets piled above the original ground
	// (jittered cells: each pellet gets its own centre, size, and tint, so no grid shows)
	if (d < 0.0) {
		vec2 pc = wc * 1.35;
		vec2 pid = floor(pc);
		float best = 9.0;
		vec2 bid = pid;
		vec2 bf = vec2(0.0);
		for (int i = -1; i <= 1; i++) {
			for (int j = -1; j <= 1; j++) {
				vec2 c = pid + vec2(float(i), float(j));
				vec2 o = vec2(hash(c + 1.7), hash(c + 4.3)) * 0.8 + 0.1;
				float rr = 0.42 + 0.26 * hash(c + 8.1);
				vec2 q = (pc - c - o) * vec2(1.0, 1.25);
				float dist = length(q) / rr;
				if (dist < best) { best = dist; bid = c; bf = q; }
			}
		}
		vec3 sp = mix(vec3(0.47, 0.31, 0.18), vec3(0.72, 0.53, 0.33), hash(bid + 2.9));
		sp = mix(sp, sp * vec3(0.9, 0.95, 1.05), step(0.8, hash(bid + 6.6)));
		sp *= 0.8 + 0.3 * (1.0 - smoothstep(0.2, 1.0, best));
		sp = mix(sp, sp * 1.2, step(bf.y, -0.1) * step(best, 0.75));
		sp = mix(sp, vec3(0.2, 0.12, 0.07), smoothstep(0.92, 1.12, best));
		col = mix(sp, col, smoothstep(-0.6, 0.4, d));
	}
	// turf rows just under the band
	if (m.b > 0.5) { col = mix(vec3(0.27, 0.45, 0.17), vec3(0.2, 0.33, 0.13), smoothstep(0.6, 1.0, s)); }
	// tunnels of the back plane, seen through the dirt: dark ghosted channels
	float bo = 1.0 - smoothstep(0.32, 0.62, ax.r);
	if (m.g > 0.5 && bo > 0.0) {
		col = mix(col, col * 0.27 + vec3(0.012, 0.008, 0.006), bo * 0.92);
		col = mix(col, ink.rgb, (1.0 - smoothstep(0.03, 0.08, abs(ax.r - 0.5))) * 0.4);
	}
	// bevel: tunnel floors catch light, ceilings fall into shade
	vec2 ps = TEXTURE_PIXEL_SIZE;
	vec2 grad = vec2(texture(TEXTURE, UV + vec2(ps.x, 0.0)).r - texture(TEXTURE, UV - vec2(ps.x, 0.0)).r,
		texture(TEXTURE, UV + vec2(0.0, ps.y)).r - texture(TEXTURE, UV - vec2(0.0, ps.y)).r);
	float rim = smoothstep(0.5, 0.56, s) * (1.0 - smoothstep(0.6, 0.9, s));
	// (not on the mound's outer face: its cell stairs would light up step by step)
	if (m.g > 0.5 && length(grad) > 0.01 && d > 0.5) {
		float lit = dot(normalize(grad), vec2(0.35, 0.94));
		col = lit > 0.0 ? mix(col, col * 1.45 + 0.05, rim * lit * 0.8) : mix(col, col * 0.55, rim * -lit * 0.8);
		// soft occlusion on the dirt face around every hole
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.55, 0.95, s)) * step(0.5, s);
	}
	col *= 1.0 - 0.3 * smoothstep(25.0, 190.0, d);
	float k = 1.0 - smoothstep(0.055, 0.1, abs(s - 0.5));
	float a = smoothstep(0.47, 0.5, s);
	COLOR = vec4(mix(col, ink.rgb, k), max(a, k));
}
"""

const BACK_SHADER = SHADER_COMMON + """
void fragment() {
	vec4 m = texture(TEXTURE, UV);
	float s = m.r;
	if (m.g < 0.5 || s > 0.6) {
		COLOR = vec4(0.0);
	} else {
		vec2 wc = origin + UV * tsize;
		vec4 ax = texture(aux_tex, UV);
		float d = wc.y - base_y(UV);
		float off = wave_off(UV);
		vec2 pw = wc + cam * 0.24;
		vec3 wall = strata(layer_depth(d, off)) * 0.44;
		wall *= 0.8 + 0.34 * fbm(pw * 0.27);
		// pores and old burrows in the rear wall
		vec2 pc = floor(pw * 0.6);
		vec2 pf = fract(pw * 0.6) - 0.5;
		if (hash(pc + 2.2) > 0.86 && length(pf * vec2(1.0, 1.5)) < 0.2) { wall *= 0.5; }
		// root hairs through the rear wall near the top
		if (d < 20.0) {
			float rn = vnoise(vec2(pw.x * 1.1, pw.y * 0.12));
			wall = mix(wall, vec3(0.12, 0.07, 0.05), (1.0 - smoothstep(0.01, 0.03, abs(rn - 0.5))) * 0.7 * (1.0 - smoothstep(8.0, 20.0, d)));
		}
		// side walls receding into the back, lit from above
		vec2 ps = TEXTURE_PIXEL_SIZE;
		vec2 grad = vec2(texture(TEXTURE, UV + vec2(ps.x, 0.0)).r - texture(TEXTURE, UV - vec2(ps.x, 0.0)).r,
			texture(TEXTURE, UV + vec2(0.0, ps.y)).r - texture(TEXTURE, UV - vec2(0.0, ps.y)).r);
		float e = smoothstep(0.12, 0.5, s);
		float lit = length(grad) > 0.01 ? dot(normalize(grad), vec2(0.35, 0.94)) : 0.0;
		vec3 side = strata(layer_depth(d, off)) * (0.6 + 0.25 * lit);
		vec3 col = mix(wall, side, e * e);
		// the front dirt casts a shadow down-right into the tunnel
		float sh = texture(TEXTURE, UV - vec2(1.3, 1.9) * ps).r;
		col *= 1.0 - 0.5 * smoothstep(0.35, 0.8, sh) * (1.0 - e);
		col *= 1.0 - 0.32 * smoothstep(20.0, 190.0, d);
		// depth layers in the rear wall: cracks open onto a deeper, slower-parallax layer
		vec2 pw2 = wc + cam * 0.5;
		float rid = abs(fbm(pw2 * 0.09) - 0.5);
		float crack = (1.0 - smoothstep(0.015, 0.05, rid)) * (1.0 - e);
		vec3 deep2 = strata(layer_depth(d, off)) * 0.16 + vec3(0.0, 0.004, 0.012);
		deep2 *= 0.75 + 0.5 * fbm(pw2 * 0.5);
		col = mix(col, deep2, crack * 0.85);
		col = mix(col, col * 1.35, (1.0 - smoothstep(0.05, 0.09, rid)) * (1.0 - crack) * (1.0 - e) * 0.35);
		// pebbles set into the rear wall, lit from above
		vec2 pc2 = pw * 0.42;
		vec2 pid2 = floor(pc2);
		vec2 pf2 = fract(pc2) - 0.5 - (vec2(hash(pid2 + 5.5), hash(pid2 + 8.8)) - 0.5) * 0.4;
		float pr2 = length(pf2 * vec2(1.0, 1.3));
		if (hash(pid2 + 3.3) > 0.9 && pr2 < 0.2 && e < 0.5) {
			vec3 peb = mix(vec3(0.3, 0.28, 0.27), vec3(0.4, 0.34, 0.27), hash(pid2)) * 0.8;
			peb = mix(peb, peb * 1.6, step(pf2.y, -0.05) * step(pr2, 0.14));
			col = mix(col, pr2 > 0.16 ? col * 0.5 : peb, 0.9);
		}
		// open air is lit in the middle of a tunnel and falls off toward the walls
		col *= 0.8 + 0.36 * (1.0 - smoothstep(0.0, 0.42, s));
		// a warm pool of light down the middle of the tunnel: it reads as a rounded tube, not a flat cut-out
		col = mix(col, col * 1.35 + vec3(0.05, 0.03, 0.008), (1.0 - smoothstep(0.0, 0.3, s)) * 0.45 * (1.0 - smoothstep(30.0, 150.0, d)));
		// a back-plane tunnel runs right behind this wall: it reads a shade darker
		col *= 1.0 - 0.28 * (1.0 - smoothstep(0.32, 0.62, ax.r)) * (1.0 - e);
		// a hole through the rear wall into the back plane
		float hole = smoothstep(0.35, 0.75, ax.b + 0.34 * (vnoise(wc * 1.3 + 9.0) - 0.5));
		if (hole > 0.0) {
			vec2 hg = vec2(texture(aux_tex, UV + vec2(ps.x, 0.0)).b - texture(aux_tex, UV - vec2(ps.x, 0.0)).b,
				texture(aux_tex, UV + vec2(0.0, ps.y)).b - texture(aux_tex, UV - vec2(0.0, ps.y)).b);
			float hl = length(hg) > 0.01 ? dot(normalize(hg), vec2(0.35, 0.94)) : 0.0;
			vec3 deep = vec3(0.035, 0.025, 0.02);
			col = mix(col, deep, hole * 0.92);
			col = mix(col, col * 1.9 + 0.08, (1.0 - smoothstep(0.0, 0.25, abs(ax.b - 0.45))) * max(hl, 0.0) * 0.6);
		}
		COLOR = vec4(col, 1.0);
	}
}
"""

var sim
var cam
var _front_sh: Shader
var _back_sh: Shader
var _back: Node2D
var _front: Node2D
var _chunks := {}     # k -> {"tex", "stex", "back", "front"}
var _layout := -1


# perf.gd: quality 1 swaps in a cheaper shader (two noise octaves instead of four, no rear-wall cracks).
func set_quality(q: int) -> void:
	if _front_sh == null:
		return
	if q >= 1:
		_front_sh.code = FRONT_SHADER.replace("i < 4", "i < 2")
		_back_sh.code = BACK_SHADER.replace("i < 4", "i < 2").replace("float crack = (1.0 - smoothstep(0.015, 0.05, rid)) * (1.0 - e);", "float crack = 0.0;")
	else:
		_front_sh.code = FRONT_SHADER
		_back_sh.code = BACK_SHADER


func _ready() -> void:
	_front_sh = Shader.new()
	_front_sh.code = FRONT_SHADER
	_back_sh = Shader.new()
	_back_sh.code = BACK_SHADER
	_back = Node2D.new()
	add_child(_back)
	_front = Node2D.new()
	add_child(_front)


# The world_view inserts its "inside the nest" layer between back and front.
func back_layer() -> Node2D:
	return _back


func front_layer() -> Node2D:
	return _front


func _process(_delta: float) -> void:
	if cam == null:
		return
	var g = sim.grid
	var vp = get_viewport_rect().size
	var z = cam.zoom.x
	var c = cam.get_camera_screen_center()
	var k0 = g.chunk_of(int(floor((c.x - vp.x * z * 0.5) / g.CELL))) - 1
	var k1 = g.chunk_of(int(floor((c.x + vp.x * z * 0.5) / g.CELL))) + 1
	for k in range(k0, k1 + 1):
		if not _chunks.has(k):
			_make_chunk(k)
	for k in _chunks.keys():
		if k < k0 - 4 or k > k1 + 4:
			_drop_chunk(k)
	for k in g.dirty_chunks.keys():
		if _chunks.has(k):
			var ch = _chunks[k]
			var imgs = g.chunk_images(k)
			ch["tex"].set_data(imgs[0])
			ch["atex"].set_data(imgs[1])
			ch["stex"].set_data(g.chunk_surf_image(k))
	g.dirty_chunks.clear()
	var camc = c / g.CELL
	for k in _chunks.keys():
		_chunks[k]["back"].material.set_shader_param("cam", camc)


func _make_chunk(k: int) -> void:
	var g = sim.grid
	var cw = g.CHUNK + 2 * g.PAD
	var imgs = g.chunk_images(k)
	var tex = ImageTexture.new()
	tex.create_from_image(imgs[0], Texture.FLAG_FILTER)
	var atex = ImageTexture.new()
	atex.create_from_image(imgs[1], Texture.FLAG_FILTER)
	var stex = ImageTexture.new()
	stex.create_from_image(g.chunk_surf_image(k), Texture.FLAG_FILTER)
	var ch = {"tex": tex, "atex": atex, "stex": stex}
	for which in ["back", "front"]:
		var sp = Sprite.new()
		sp.centered = false
		sp.texture = tex
		sp.region_enabled = true
		sp.region_rect = Rect2(g.PAD, 0, g.CHUNK, g.H)
		sp.scale = Vector2(g.CELL, g.CELL)
		sp.position = Vector2(k * g.CHUNK * g.CELL, 0)
		var mat = ShaderMaterial.new()
		mat.shader = _back_sh if which == "back" else _front_sh
		mat.set_shader_param("origin", Vector2(k * g.CHUNK - g.PAD, 0))
		mat.set_shader_param("tsize", Vector2(cw, g.H))
		mat.set_shader_param("surf_tex", stex)
		mat.set_shader_param("aux_tex", atex)
		sp.material = mat
		(_back if which == "back" else _front).add_child(sp)
		ch[which] = sp
	_chunks[k] = ch


func _drop_chunk(k: int) -> void:
	var ch = _chunks[k]
	ch["back"].queue_free()
	ch["front"].queue_free()
	_chunks.erase(k)
