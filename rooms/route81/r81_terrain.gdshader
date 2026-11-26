shader_type spatial;
render_mode cull_disabled;
// Route 81: the land beside the highway (r81_land.gd builds it, one mesh per side of each road
// piece). Each corner of the mesh carries
//   COLOR.r  how much bare rock (road cuts, tunnel faces),
//   COLOR.g  how much mown grass (shoulders, the median),
//   COLOR.b  how much forest (leaf litter up close, a sea of tree tops far away),
//   UV.x     its depth: 0 = stays at road height, 1 = sinks all the way to the valley floor,
//   UV.y     how fast that depth changes across the road (per metre of X), to tilt the normal,
//   UV2.x    how much crop field (farm country): strips of corn, hay, alfalfa and bare earth
//            running along the road, each some tens of metres wide,
//   UV2.y    how much river (r81_land.gd water_share): at 1 the ground is the river's surface
//            under a bridge; on the way there it is the bank falling to it.
// Close to the camera the forest is its floor (the trees standing on it are real meshes, see
// r81_tree.gdshader); from about 150 m out, where the real trees stop, it turns into canopy:
// lumpy tree tops in patches of lighter and darker green (or fall colours).
// Texture sizes are whole fractions of a piece's 80 m, so pieces meet without a seam, except
// the second, turned layers that break up the repeats (below), which are smooth enough that a
// seam does not show.
// Repeats: one noise picture laid on every 20 m made the tree tops (and the grass photo every
// 4 m) into regular rows that, on a hillside seen from afar, read as stripes ("watermelon",
// Sen round 5). So the tree tops mix two layers of different sizes, one turned, and the fine
// detail fades out with distance, where only the big patches are left.
// r22_desert.gd writes the shared uniforms; r81_trip.gd writes alt_drop and season.
#include "res://rooms/route81/r81_common.gdshaderinc"

uniform sampler2D tex_rock : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_grass : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_leaves : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;

varying vec3 o_pos;
varying vec3 w_pos;
varying vec3 o_nrm;
varying float field;
varying float river;

void vertex() {
	o_pos = VERTEX;
	field = UV2.x;
	river = UV2.y;
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

// The same spot turned by about 37 degrees (for a second layer whose repeats do not line up).
vec2 turned(vec2 q) {
	return mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * q;
}

void fragment() {
	vec2 q = o_pos.xz;
	vec2 qt = turned(q);
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	// how much of the fine detail is left at this distance (1 near .. 0 from about 600 m)
	float fine = 1.0 - smoothstep(150.0, 600.0, dist);
	// (two layers, 20 m and 33 m, the second turned; stretched back to the first's contrast)
	vec4 lumps = (texture(rock_noise, q / 20.0) + texture(rock_noise, qt / 33.0 + vec2(0.37, 0.71))) * 0.5;
	lumps = mix(vec4(0.5), clamp((lumps - 0.5) * 1.6 + 0.5, 0.0, 1.0), fine);
	vec4 patches = (texture(rock_noise, q / 80.0) + texture(rock_noise, qt / 190.0 + vec2(0.13, 0.52))) * 0.5;
	patches = clamp((patches - 0.5) * 1.5 + 0.5, 0.0, 1.0);
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
	// (the photo's light and dark only close up: further out its 4 m repeat shows as rows)
	float grass_shade = mix(0.5, dot(grass_photo, vec3(0.333)), 1.0 - smoothstep(30.0, 140.0, dist));
	vec3 grass = vec3(0.26, 0.4, 0.12) * (0.45 + 1.6 * grass_shade);
	if (detail < 0.5) {
		grass = vec3(0.2, 0.3, 0.1);
	}
	grass = mix(grass, grass * vec3(1.25, 1.05, 0.7), season * 0.5);
	grass *= 0.85 + 0.3 * patches.b;
	col = mix(col, grass, COLOR.g);
	// ── crop fields: contour strips along the road, each its own crop ──
	if (field > 0.001) {
		// (strips of uneven width: the strip number steps along X, nudged by slow noise)
		float strip = floor(o_pos.x / 46.0 + 0.6 * texture(rock_noise, vec2(o_pos.x / 700.0, 0.37)).b);
		float pick = fract(sin(strip * 12.9898) * 43758.5453);
		vec3 crop = vec3(0.2, 0.36, 0.1);                               // corn
		crop = mix(crop, vec3(0.52, 0.45, 0.2), step(0.3, pick));       // ripe hay or wheat
		crop = mix(crop, vec3(0.13, 0.3, 0.1), step(0.55, pick));       // alfalfa
		crop = mix(crop, vec3(0.27, 0.19, 0.12), step(0.82, pick));     // bare ploughed earth
		// the rows, close up, and blotches of better and poorer growth
		float rows = 0.85 + 0.15 * sin(o_pos.x * 8.0) * (1.0 - smoothstep(30.0, 90.0, dist));
		crop *= rows * (0.8 + 0.4 * patches.a);
		if (detail > 0.5) {
			crop *= 0.6 + 1.2 * grass_shade;
		}
		// fall: the corn and hay stand dry and gold
		crop = mix(crop, crop * vec3(1.5, 1.1, 0.6), season * 0.6 * step(pick, 0.55));
		col = mix(col, crop, field);
	}
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
	// ── the river: dark, slow water, its surface broken by ripples drifting downstream ──
	// (it was long, even lighter streaks over a mirror-flat surface, which read as corrugated
	// sheet metal: Sen, round 5. The river flows across the road, along X.)
	// a ragged edge where the bank meets the water, not a ruled line
	float water = smoothstep(0.9, 0.99, river + 0.08 * (texture(rock_noise, q / 37.0).g - 0.5));
	if (water > 0.001) {
		vec2 flow = vec2(TIME * 0.7, 0.0);
		float slow = texture(rock_noise, (q + flow * 0.3) / 160.0 + vec2(0.21, 0.63)).b;
		vec3 stream = mix(vec3(0.03, 0.06, 0.055), vec3(0.075, 0.11, 0.095), slow);
		col = mix(col, stream * r22_cloud_shade(w_pos), water);
		// the ripples tilt the surface (two layers drifting at different speeds and sizes,
		// fading with distance, where they would only shimmer)
		vec2 a = texture(rock_noise, (q + flow) / 9.0).rg - 0.5;
		vec2 b = texture(rock_noise, (qt - flow * 0.6) / 23.0 + vec2(0.4, 0.1)).gb - 0.5;
		vec2 tilt = (a * 0.35 + b * 0.45) * (1.0 - 0.75 * smoothstep(80.0, 900.0, dist));
		vec3 wn = normalize(vec3(tilt.x, 1.0, tilt.y));
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wn, 0.0)).xyz, water));
	}
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.95, 0.7, wet * COLOR.r), 0.1, water);
	SPECULAR = mix(0.08 + 0.25 * wet * COLOR.r, 0.45, water);
}
