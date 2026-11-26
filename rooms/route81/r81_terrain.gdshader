shader_type spatial;
render_mode cull_disabled;
// Route 81: the land beside the highway (r81_land.gd builds it, one mesh per side of each road
// piece). Each corner of the mesh carries
//   COLOR.r  how much bare rock (road cuts, tunnel faces),
//   COLOR.g  how much mown grass (shoulders, the median),
//   COLOR.b  how much forest (leaf litter up close, a sea of tree tops far away),
//   UV.x     its depth: 0 = stays at road height, 1 = sinks all the way to the valley floor,
//   UV.y     how fast that depth changes across the road (per metre of X), to tilt the normal.
// Close to the camera the forest is its floor (the trees standing on it are real meshes, see
// r81_tree.gdshader); from about 150 m out, where the real trees stop, it turns into canopy:
// lumpy tree tops in patches of lighter and darker green (or fall colours).
// Texture sizes are whole fractions of a piece's 80 m, so pieces meet without a seam.
// r22_desert.gd writes the shared uniforms; r81_trip.gd writes alt_drop and season.
#include "res://rooms/route81/r81_common.gdshaderinc"

uniform sampler2D tex_rock : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_leaves : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;

varying vec3 o_pos;
varying vec3 w_pos;
varying vec3 o_nrm;

void vertex() {
	o_pos = VERTEX;
	vec3 v = VERTEX;
	v.y -= UV.x * alt_drop;
	// the valley's extra slope tilts the surface: rebuild the normal from the two slopes
	float up = max(NORMAL.y, 0.05);
	vec3 n = normalize(vec3(NORMAL.x / up + UV.y * alt_drop, 1.0, NORMAL.z / up));
	o_nrm = NORMAL;
	NORMAL = n;
	w_pos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	VERTEX = r22_bend_vertex(v, MODEL_MATRIX);
}

vec3 rock_sides(vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex_rock, p.zy / tile).rgb * w.x + texture(tex_rock, p.xz / tile).rgb * w.y + texture(tex_rock, p.xy / tile).rgb * w.z;
}

void fragment() {
	vec2 q = o_pos.xz;
	vec4 lumps = texture(rock_noise, q / 20.0);
	vec4 patches = texture(rock_noise, q / 80.0);
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	// ── forest: its floor near, its canopy far ──
	// (the floor: last year's leaves with green undergrowth coming through in patches)
	vec3 floor_col = texture(tex_leaves, q / 5.0).rgb * vec3(0.55, 0.6, 0.45);
	floor_col = mix(floor_col, vec3(0.08, 0.15, 0.045) * (0.7 + 0.6 * lumps.a), smoothstep(0.35, 0.6, lumps.b));
	vec3 green = mix(vec3(0.07, 0.15, 0.04), vec3(0.17, 0.31, 0.08), smoothstep(0.3, 0.7, lumps.b));
	green *= 0.7 + 0.6 * patches.b;
	// dark gaps between the crowns
	green *= 0.55 + 0.45 * smoothstep(0.2, 0.45, lumps.a + lumps.b * 0.5);
	// about one patch in six is conifers: darker, and green all year
	float conifer = smoothstep(0.62, 0.7, patches.a);
	green = mix(green, green * vec3(0.55, 0.7, 0.75), conifer);
	vec3 canopy = r81_leaf(green, fract(lumps.g * 3.0 + patches.g), conifer);
	float far = smoothstep(120.0, 280.0, dist);
	if (detail < 0.5) {
		floor_col = vec3(0.1, 0.15, 0.06);
	}
	vec3 col = mix(floor_col, canopy, far);
	// ── mown grass ──
	// (the photo is of dry, sparse grass: keep its light and dark, in a mown summer green)
	vec3 grass_photo = texture(tex_grass, q / 4.0).rgb;
	vec3 grass = vec3(0.26, 0.4, 0.12) * (0.45 + 1.6 * dot(grass_photo, vec3(0.333)));
	if (detail < 0.5) {
		grass = vec3(0.2, 0.3, 0.1);
	}
	grass = mix(grass, grass * vec3(1.25, 1.05, 0.7), season * 0.5);
	grass *= 0.85 + 0.3 * patches.b;
	col = mix(col, grass, COLOR.g);
	// ── rock: grey layered stone, darker in the cracks, stained down the face ──
	vec3 n = normalize(o_nrm);
	vec3 rock = rock_sides(o_pos, n, 8.0);
	if (detail < 0.5) {
		rock = vec3(0.34, 0.33, 0.32);
	}
	float bands = texture(rock_noise, vec2(o_pos.z / 40.0 + lumps.b * 0.05, o_pos.y / 5.0)).b;
	rock *= 0.7 + 0.5 * bands;
	rock *= 1.0 - 0.3 * smoothstep(0.5, 0.8, texture(rock_noise, vec2(o_pos.z / 10.0, o_pos.y / 40.0)).g);
	col = mix(col, rock, COLOR.r);
	col *= r22_cloud_shade(w_pos);
	col *= 1.0 - 0.3 * wet;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.7, wet * COLOR.r);
	SPECULAR = 0.08 + 0.25 * wet * COLOR.r;
}
