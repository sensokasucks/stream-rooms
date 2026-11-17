shader_type spatial;
render_mode cull_disabled;
// Route 22: everything built from plain shapes in r22_geo.gd / r22_vehicles.gd that isn't rock:
// signs, poles, fences, buildings, the drive-in's screen and booth, the other vehicles, brush.
// One material covers a whole group of objects; each corner of the mesh carries
//   COLOR.rgb  its colour,
//   COLOR.a    how much it sways in the wind (0 at a bush's foot, 1 at its tips; 0 for solid things),
//   UV.x       what it is made of, one of r22_geo.gd's MAT_ numbers:
//     0 plain paint    1 wood (grain, textures from the Lakeside Campfire)    2 rock
//     3 rusty metal    4 cloth    5 a light (neon, a lit window, a lamp: glows by `glow`)
//     6 chrome          7 glass (dark and glossy)    8 sand (a red sand drift)
//     9 car paint (glossy, a little metallic: the vehicle models' bodies)
// With `detail` at 1 wood, rock, rust, cloth and sand get a photo or noise grain (laid on from
// three sides by object position, 0.5 = no change). Lights glow with `glow` (r22_desert.gd sets
// it from the hour and the Neon tick box) and buzz faintly unless `flicker` is 0 (photosensitive-
// safe mode). Everything bends with the road and darkens / shines in the wet
// (r22_common.gdshaderinc).
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform sampler2D tex_wood : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_fabric : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
// rusty painted metal (textures/prop_rust.jpg): the rust blotches' colour on the Detailed look
uniform sampler2D tex_rust : filter_linear_mipmap_anisotropic, repeat_enable;
// How strongly the lights (MAT 5) glow: 0 by day with the neon off, up to about 4 at night.
uniform float glow = 0.0;
// 1 = the neon buzzes (a slight, slow waver), 0 = steady (photosensitive-safe mode).
uniform float flicker = 1.0;
// How far (metres) the swaying parts move in a light breeze; `wind` scales it (the Wind slider).
uniform float sway = 0.12;
uniform float wind = 1.0;

varying vec3 o_pos;
varying vec3 w_pos;
varying vec3 o_normal;
varying float mat_id;

vec3 three_sides(sampler2D tex, vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy / tile).rgb * w.x + texture(tex, p.xz / tile).rgb * w.y + texture(tex, p.xy / tile).rgb * w.z;
}

// rock_noise seen from three sides (all four channels; a sampler can't be passed to three_sides
// with a different filter from the photo textures, so it has its own helper)
vec4 noise_sides(vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(rock_noise, p.zy / tile) * w.x + texture(rock_noise, p.xz / tile) * w.y + texture(rock_noise, p.xy / tile) * w.z;
}

void vertex() {
	o_pos = VERTEX;
	o_normal = NORMAL;
	mat_id = UV.x;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (COLOR.a > 0.01) {
		// a slow lean that travels across the brush, plus a quicker shiver, scaled by the wind
		float lean = sin(TIME * 1.1 + w_pos.x * 0.21 + w_pos.z * 0.17) + 0.45 * sin(TIME * 3.3 + w_pos.x * 0.9);
		vec3 push = vec3(0.8, 0.0, 0.45) * lean * sway * wind * COLOR.a * COLOR.a;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * push;
	}
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec3 n = normalize(o_normal);
	vec3 col = COLOR.rgb;
	float rough = 0.8;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	int m = int(mat_id + 0.5);
	if (m == 1) {
		if (detail > 0.5) {
			col *= three_sides(tex_wood, o_pos, n, 1.3) * 2.0;
		}
		rough = 0.75;
	} else if (m == 2) {
		if (detail > 0.5) {
			col *= three_sides(tex_rock, o_pos, n, 3.0) * 2.0;
		}
		rough = 0.9;
	} else if (m == 3) {
		// rust: orange-brown blotches over the paint, rough
		float r = noise_sides(o_pos * 0.6, n, 1.0).b;
		vec3 rust = vec3(0.42, 0.2, 0.09) * (0.7 + 0.6 * noise_sides(o_pos, n, 0.5).a);
		if (detail > 0.5) {
			// the photo: real flaking rust, and a little of its grime over the paint too
			vec3 photo = three_sides(tex_rust, o_pos, n, 1.5);
			rust = photo * vec3(0.95, 0.85, 0.8);
			col *= 0.75 + 0.25 * photo / max(dot(photo, vec3(0.333)), 0.05) * 0.5;
		}
		col = mix(col, rust, smoothstep(0.4, 0.6, r));
		rough = 0.92;
	} else if (m == 4) {
		if (detail > 0.5) {
			col *= three_sides(tex_fabric, o_pos, n, 0.5) * 2.0;
		}
		rough = 0.95;
	} else if (m == 5) {
		float buzz = 1.0 + flicker * 0.06 * sin(TIME * 7.0 + o_pos.x * 3.0) * sin(TIME * 2.3);
		emit = col * glow * buzz;
		rough = 0.4;
	} else if (m == 6) {
		metal = 1.0;
		rough = 0.18;
		col = mix(col, vec3(0.8), 0.3);
	} else if (m == 7) {
		rough = 0.05;
		col *= 0.4;
	} else if (m == 9) {
		rough = 0.3;
		metal = 0.12;
	} else if (m == 8) {
		if (detail > 0.5) {
			col *= three_sides(tex_sand, o_pos, n, 4.0) * 2.0;
		}
		rough = 0.95;
	}
	col *= r22_cloud_shade(w_pos);
	// the wet: darker, and the upward faces shine
	float up = smoothstep(0.3, 0.9, n.y);
	col *= 1.0 - 0.3 * wet;
	rough = mix(rough, min(rough, 0.25), wet * up);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
