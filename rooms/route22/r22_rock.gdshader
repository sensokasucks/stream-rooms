shader_type spatial;
render_mode cull_disabled;
// Route 22: the red sandstone. Every rock r22_geo.gd builds (road cuts, fins, arches, hoodoos,
// domes, walls, boulders, buttes) uses this one material; what makes each one different rides
// in its mesh:
//   COLOR.rgb  a tint, 0.5 = no change (a cream cap rock is paler, a far butte a little bluer),
//   COLOR.a    desert varnish: dark streaks running down steep faces (0 = none, 1 = heavy),
//   UV.x       how steeply the layers tilt (-1..1; road cuts show tilted layers),
//   UV.y       honeycomb weathering (tafoni): small pits on steep faces (0 = none, 1 = deep).
// The colour bands are the rock's layers: cream, orange, red and purple, picked by height
// (warped by noise so they wander, tilted by UV.x). They are worked out from the object's own
// position, so the layers stay put on a rock that slides past the car.
// With `detail` at 1 a photo of sandstone (textures/detail_sandstone.jpg, 0.5 = no change) adds
// grain from three sides. Wet weather darkens the rock and makes it shine; cloud shadows drift
// over it. r22_desert.gd sets the shared uniforms (r22_common.gdshaderinc).
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform sampler2D tex_detail : filter_linear_mipmap_anisotropic, repeat_enable;
// textures/rock_noise.png: r = honeycomb pits, g = vertical varnish streaks, b = soft warp, a = speckle.
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
// Metres one layer band is thick, on average.
uniform float band_size = 1.6;
// How bright the rock looks overall (the room may dim it for night fog).
uniform float brightness = 1.0;

varying vec3 o_pos;      // object-space position (the layers are fixed to it)
varying vec3 w_pos;      // world position before the bend (for the cloud shadows)
varying vec3 o_normal;
varying float tilt;
varying float honeycomb;

// The rock's colour at layer height h: a soft ramp through the Valley-of-Fire palette, chosen by
// the warp noise along h so the band order never repeats exactly.
vec3 layer_colour(float h) {
	float pick = texture(rock_noise, vec2(h / (band_size * 16.0), 0.37)).b;
	pick = clamp((pick - 0.25) * 2.0, 0.0, 1.0);
	vec3 cream = vec3(0.86, 0.71, 0.52);
	vec3 orange = vec3(0.84, 0.45, 0.22);
	vec3 red = vec3(0.62, 0.21, 0.11);
	vec3 purple = vec3(0.45, 0.22, 0.24);
	vec3 c = mix(cream, orange, smoothstep(0.0, 0.3, pick));
	c = mix(c, red, smoothstep(0.3, 0.6, pick));
	c = mix(c, purple, smoothstep(0.75, 1.0, pick));
	// fine lines inside each band (the bedding planes)
	float fine = texture(rock_noise, vec2(h / (band_size * 1.3), 0.71)).b;
	return c * (0.88 + 0.24 * fine);
}

vec3 three_sides(sampler2D tex, vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy / tile).rgb * w.x + texture(tex, p.xz / tile).rgb * w.y + texture(tex, p.xy / tile).rgb * w.z;
}

void vertex() {
	o_pos = VERTEX;
	o_normal = NORMAL;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tilt = UV.x;
	honeycomb = UV.y;
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec3 n = normalize(o_normal);
	float steep = 1.0 - abs(n.y);
	// the layer height: wandering (warp), tilted, then coloured
	float warp = texture(rock_noise, o_pos.xz / 64.0).b - 0.5;
	float h = o_pos.y + warp * 3.0 + (o_pos.x * 0.8 + o_pos.z * 0.6) * tilt * 0.35;
	vec3 col = layer_colour(h) * COLOR.rgb * 2.0;
	// sand collects on the flat tops and at the foot
	float sandy = smoothstep(0.75, 0.95, n.y) * 0.5 + smoothstep(0.6, 0.0, o_pos.y) * 0.4;
	col = mix(col, vec3(0.8, 0.5, 0.3), clamp(sandy, 0.0, 0.7));
	// honeycomb pits on steep faces: darker hollows with a lit rim
	float rough = 0.85;
	if (honeycomb > 0.01) {
		vec2 hp = vec2(o_pos.x + o_pos.z, o_pos.y) / 6.0;
		float pits = texture(rock_noise, hp).r;
		float hole = smoothstep(0.55, 0.25, pits) * honeycomb * steep;
		col *= 1.0 - 0.55 * hole;
		col += vec3(0.08, 0.04, 0.02) * smoothstep(0.3, 0.45, pits) * smoothstep(0.6, 0.45, pits) * honeycomb * steep;
	}
	// desert varnish: dark streaks hanging down the steep faces
	if (COLOR.a > 0.01) {
		vec2 vp = vec2((o_pos.x + o_pos.z) / 18.0, o_pos.y / 40.0);
		float streak = texture(rock_noise, vp).g;
		float varnish = smoothstep(0.45, 0.75, streak) * COLOR.a * smoothstep(0.3, 0.8, steep);
		col = mix(col, vec3(0.16, 0.09, 0.07), varnish * 0.8);
		rough -= varnish * 0.25;
	}
	// speckle so a big face never reads as a flat fill
	col *= 0.92 + 0.16 * texture(rock_noise, o_pos.xy / 3.0 + o_pos.zz / 5.0).a;
	if (detail > 0.5) {
		col *= three_sides(tex_detail, o_pos, n, 4.0) * 2.0;
	}
	col *= r22_cloud_shade(w_pos);
	// wet: darker, and shiny on the slopes the rain runs down
	col *= 1.0 - 0.38 * wet;
	rough = mix(rough, 0.35, wet * 0.8);
	ALBEDO = col * brightness;
	ROUGHNESS = rough;
	SPECULAR = 0.35 + 0.3 * wet;
}
