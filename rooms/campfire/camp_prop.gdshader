shader_type spatial;
render_mode cull_disabled;
// Lakeside Campfire: everything campfire_builder.gd builds out of plain shapes (tents, benches,
// chairs, the dock, rocks, the screen's posts...) and the trees. The colour comes from each
// corner of the mesh (its vertex colour), so one material covers a whole group of objects.
//   glow   makes the colour shine by itself (the tents, lit from inside at night),
//   wet    darkens it and adds shine (rain),
//   sway   bends the mesh in the wind: how far (metres) the parts whose vertex alpha is 1 move.
//          Alpha runs from 0 at a tree's foot to 1 at its top; everything else has sway 0.
// The room script (campfire_room.gd) sets glow, wet and wind.
// With `detail` at 1 (the room's Set detail choice) the colour is also multiplied by a photo
// "detail" texture: bark, rock, planks or cloth, picked by the number in the mesh's UV.x (the
// MAT_ constants in campfire_builder.gd; 0 = plain, no texture). The texture is laid on by
// world position from three sides (no UV mapping needed), and holds the photo divided by its
// average colour with 0.5 = no change, so an object keeps its own colour and gains the grain.
// textures/make_textures.py makes them (CC0 photos from Poly Haven).

uniform float glow = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float sway = 0.0;
// How hard the wind blows (1 = a light breeze; a storm raises it).
uniform float wind = 1.0;
uniform float roughness = 0.85;
// 0 = plain colours (the low-poly look), 1 = with the detail textures.
uniform float detail = 0.0;
uniform sampler2D tex_bark : filter_linear_mipmap_anisotropic, repeat_enable;        // 1
uniform sampler2D tex_rock : filter_linear_mipmap_anisotropic, repeat_enable;        // 2
uniform sampler2D tex_planks : filter_linear_mipmap_anisotropic, repeat_enable;      // 3
uniform sampler2D tex_fabric : filter_linear_mipmap_anisotropic, repeat_enable;      // 4
uniform sampler2D tex_bark_oak : filter_linear_mipmap_anisotropic, repeat_enable;    // 5
uniform sampler2D tex_bark_birch : filter_linear_mipmap_anisotropic, repeat_enable;  // 6

varying vec3 w_pos;      // world position before the wind moves it (so the grain doesn't swim)
varying vec3 w_normal;
varying float mat_id;

// One texture seen from the three axes and blended by which way the surface faces.
// `tile` = metres one copy covers. Bark and planks run up the object: the side views use the
// height as the picture's vertical.
vec3 three_sides(sampler2D tex, vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 x = texture(tex, p.zy / tile).rgb;
	vec3 y = texture(tex, p.xz / tile).rgb;
	vec3 z = texture(tex, p.xy / tile).rgb;
	return x * w.x + y * w.y + z * w.z;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mat_id = UV.x;
	if (sway > 0.0) {
		vec3 w = w_pos;
		// a slow lean that travels across the forest, plus a quicker shiver
		float lean = sin(TIME * 0.7 + w.x * 0.13 + w.z * 0.09) + 0.4 * sin(TIME * 1.9 + w.x * 0.7 + w.z * 0.5);
		vec3 push = vec3(1.0, 0.0, 0.35) * lean * sway * wind * COLOR.a * COLOR.a;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
	}
}

void fragment() {
	vec3 grain = vec3(0.5);
	if (detail > 0.5 && mat_id > 0.5) {
		vec3 n = normalize(w_normal);
		if (mat_id < 1.5) {
			grain = three_sides(tex_bark, w_pos, n, 0.9);
		} else if (mat_id < 2.5) {
			grain = three_sides(tex_rock, w_pos, n, 1.4);
		} else if (mat_id < 3.5) {
			grain = three_sides(tex_planks, w_pos, n, 1.3);
		} else if (mat_id < 4.5) {
			grain = three_sides(tex_fabric, w_pos, n, 0.45);
		} else if (mat_id < 5.5) {
			grain = three_sides(tex_bark_oak, w_pos, n, 1.6);
		} else {
			grain = three_sides(tex_bark_birch, w_pos, n, 1.1);
		}
	}
	ALBEDO = COLOR.rgb * grain * 2.0 * (1.0 - 0.3 * wet);
	ROUGHNESS = mix(roughness, 0.4, wet * 0.6);
	EMISSION = COLOR.rgb * grain * 2.0 * glow;
}
