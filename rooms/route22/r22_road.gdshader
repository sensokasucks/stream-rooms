shader_type spatial;
render_mode cull_disabled;
// Route 22: the two-lane highway. A long flat strip (r22_geo.gd road_strip) whose own X runs
// across the road (0 = the middle) and own Z along it. It never moves: its picture slides with
// `travel` (r22_common.gdshaderinc), which is what makes the road rush under the car.
//   asphalt photo (textures/road_asphalt.jpg), darker worn wheel tracks in each lane,
//   a double yellow line down the middle and a white line at each edge, both a little worn,
//   amber reflectors (cat's eyes) on the middle line every 16 m that catch headlights at night,
//   a mirage: on a hot day the far road shines like water (it shows the sky's horizon colour),
//   wet weather: dark, glossy asphalt (screen-space reflections on Detailed) and puddles.
// r22_desert.gd sets the shared uniforms and sky_horizon / heat / night.
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform sampler2D tex_asphalt : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
// The colour of the sky at the horizon right now (what the mirage shows).
uniform vec3 sky_horizon = vec3(0.8, 0.7, 0.6);
// Heat shimmer, 0..1 (the Heat slider times daylight): how strong the mirage is.
uniform float heat = 0.0;
// 0 = day, 1 = night (the reflectors glow at night, as if a car's lights caught them).
uniform float night = 0.0;
// Half the paved width, metres (lanes are 3.6 m; the white lines sit just inside this).
uniform float half_width = 3.75;

varying vec3 o_pos;
varying vec3 w_pos;

void vertex() {
	o_pos = VERTEX;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

// 1 inside a painted line from a to b across the road (metres), soft by 1 cm.
float stripe(float x, float a, float b) {
	return smoothstep(a - 0.01, a + 0.01, x) * smoothstep(b + 0.01, b - 0.01, x);
}

void fragment() {
	float x = o_pos.x;
	float along = o_pos.z - travel;
	vec2 q = vec2(x, along);
	vec3 col = texture(tex_asphalt, q / 4.0).rgb * 0.9;
	if (detail < 0.5) {
		col = mix(vec3(0.2, 0.19, 0.19), col, 0.3);
	}
	// the wheel tracks: a darker, smoother band down each lane
	float lane = abs(abs(x) - 1.8);
	float track = smoothstep(0.75, 0.35, abs(lane - 0.0)) * 0.15;
	col *= 1.0 - track;
	// the sun-bleached edges
	col = mix(col, col * 1.25 + 0.03, smoothstep(half_width - 0.4, half_width, abs(x)));
	// paint: double yellow middle, white edges, worn by noise
	float wear = smoothstep(0.25, 0.6, texture(rock_noise, q / vec2(2.0, 8.0)).a);
	float yellow = stripe(abs(x), 0.07, 0.17) * wear;
	float white = stripe(abs(x), half_width - 0.27, half_width - 0.15) * wear;
	col = mix(col, vec3(0.85, 0.62, 0.12), yellow * 0.9);
	col = mix(col, vec3(0.85, 0.85, 0.82), white * 0.9);
	// cat's eyes on the middle line, one every 16 m
	float eye_z = abs(fract(along / 16.0) - 0.5) * 16.0;
	float eye = step(eye_z, 0.06) * step(abs(x), 0.05);
	col = mix(col, vec3(0.9, 0.55, 0.1), eye);
	vec3 glow = vec3(1.0, 0.55, 0.1) * eye * night * 3.0;
	// past the paint, the shoulder's edge crumbles into the gravel the ground draws
	col *= r22_cloud_shade(w_pos);
	// wet: darker and glossy, with puddles
	float puddle = smoothstep(0.6, 0.7, texture(rock_noise, q / 24.0).b) * wet;
	col *= 1.0 - 0.45 * wet;
	float rough = mix(0.82, 0.22, wet);
	rough = mix(rough, 0.03, puddle);
	// the mirage: far away and at a grazing look, a hot road mirrors the sky
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float graze = 1.0 - abs(dot(normalize(w_pos - CAMERA_POSITION_WORLD), vec3(0.0, 1.0, 0.0)));
	float mirage = heat * smoothstep(45.0, 140.0, dist) * smoothstep(0.985, 0.998, graze);
	mirage *= 0.6 + 0.4 * texture(rock_noise, vec2(x / 6.0, along / 40.0 + TIME * 0.05)).b;
	ALBEDO = col * (1.0 - mirage);
	EMISSION = glow + sky_horizon * mirage * 0.9;
	ROUGHNESS = rough;
	SPECULAR = 0.4 + 0.3 * wet;
}
