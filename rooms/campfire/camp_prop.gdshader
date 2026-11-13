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

uniform float glow = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float sway = 0.0;
// How hard the wind blows (1 = a light breeze; a storm raises it).
uniform float wind = 1.0;
uniform float roughness = 0.85;

void vertex() {
	if (sway > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		// a slow lean that travels across the forest, plus a quicker shiver
		float lean = sin(TIME * 0.7 + w.x * 0.13 + w.z * 0.09) + 0.4 * sin(TIME * 1.9 + w.x * 0.7 + w.z * 0.5);
		vec3 push = vec3(1.0, 0.0, 0.35) * lean * sway * wind * COLOR.a * COLOR.a;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * (1.0 - 0.3 * wet);
	ROUGHNESS = mix(roughness, 0.4, wet * 0.6);
	EMISSION = COLOR.rgb * glow;
}
