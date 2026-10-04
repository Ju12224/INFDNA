extends Node2D
# Terrain in two stacked layers, streamed in CHUNK-wide pieces around the camera:
#   back  - the recessed rear wall of every tunnel and room: darker dirt that drifts
#           slightly with the camera (parallax), receding side walls lit from above,
#           and the drop shadow the front dirt casts into the tunnel;
#   front - the cut face of the soil: the owner's dirt (content/art/terrain/dirt_soil.png, from the seamless dirt
#           tiles; tools/art/make_dirt_atlas.py) tinted by stratum (humus, clay, sand/gravel, red clay, limestone,
#           shale, bedrock), the sim's stones and fossils, bevelled tunnel rims, ink outline.
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
uniform sampler2D dirt_tex;
uniform vec3 dirt_avg = vec3(0.29, 0.235, 0.2);
const vec2 SOIL = vec2(80.0, 64.0);      // cells the dirt picture covers before it repeats (5 x 5 of the owner's tiles, 96 x 77 px each)

// the owner's dirt, tinted to a stratum's colour (the top soil is the tile as drawn)
vec3 dirt(vec2 wc, vec3 tint) { return texture(dirt_tex, wc / SOIL).rgb * tint / dirt_avg; }

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
	vec3 c = vec3(0.30, 0.24, 0.205);                                 // humus (the owner's dirt as drawn)
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
	vec3 col = dirt(wc, strata(dd));
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
	// the spoil mound: dug-out earth piled above the original ground, the owner's dirt a little lighter and warmer
	if (d < 0.0) {
		vec3 sp = dirt(wc * 1.35 + 7.0, vec3(0.44, 0.31, 0.2));
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
		vec3 wall = dirt(pw, strata(layer_depth(d, off))) * 0.44;
		// side walls receding into the back, lit from above
		vec2 ps = TEXTURE_PIXEL_SIZE;
		vec2 grad = vec2(texture(TEXTURE, UV + vec2(ps.x, 0.0)).r - texture(TEXTURE, UV - vec2(ps.x, 0.0)).r,
			texture(TEXTURE, UV + vec2(0.0, ps.y)).r - texture(TEXTURE, UV - vec2(0.0, ps.y)).r);
		float e = smoothstep(0.12, 0.5, s);
		float lit = length(grad) > 0.01 ? dot(normalize(grad), vec2(0.35, 0.94)) : 0.0;
		vec3 side = dirt(pw, strata(layer_depth(d, off))) * (0.6 + 0.25 * lit);
		vec3 col = mix(wall, side, e * e);
		// the front dirt casts a shadow down-right into the tunnel
		float sh = texture(TEXTURE, UV - vec2(1.3, 1.9) * ps).r;
		col *= 1.0 - 0.5 * smoothstep(0.35, 0.8, sh) * (1.0 - e);
		col *= 1.0 - 0.32 * smoothstep(20.0, 190.0, d);
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
var _camc := Vector2(INF, INF)
var _new_chunk := true
var _dirt: ImageTexture = null
const DIRT_FILE = "res://mods-unpacked/Judah-InfDNA/content/art/terrain/dirt_soil.png"


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
	var img = Image.new()
	if img.load(DIRT_FILE) == OK:
		_dirt = ImageTexture.new()
		_dirt.create_from_image(img, Texture.FLAG_MIPMAPS | Texture.FLAG_REPEAT | Texture.FLAG_FILTER)
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
	if camc != _camc or _new_chunk:      # (a still camera leaves the rear-wall parallax where it is)
		_camc = camc
		_new_chunk = false
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
		if _dirt != null:
			mat.set_shader_param("dirt_tex", _dirt)
		sp.material = mat
		(_back if which == "back" else _front).add_child(sp)
		ch[which] = sp
	_chunks[k] = ch
	_new_chunk = true


func _drop_chunk(k: int) -> void:
	var ch = _chunks[k]
	ch["back"].queue_free()
	ch["front"].queue_free()
	_chunks.erase(k)
