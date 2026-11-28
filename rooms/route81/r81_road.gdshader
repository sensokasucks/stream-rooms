shader_type spatial;
render_mode cull_disabled;
// Route 81: one side of the divided highway (two lanes going the same way). A long flat strip
// (r81_land.gd road_strip) whose own X runs across (0 = the dashed line between the lanes,
// +X = the right-hand shoulder) and own Z along. Like Route 22's road it never moves: its
// picture slides with `travel`. The other direction's road is the same strip turned round
// (flow = -1), standing across the median.
//   asphalt photo, darker wheel tracks, a dashed white line between the lanes (4 m of every
//   16 m), a solid yellow line on the left (median) edge and a solid white one on the right,
//   rumble strips outside both lines, wet weather shine and puddles,
//   and inside a tunnel (world Z between tunnel_a and tunnel_b) no daylight: pools of lamp
//   light instead (lamp_color; one lamp every 8 m, like r81_tunnel.gdshader's),
//   and at night pools of light under the streetlights.
// r22_desert.gd sets the shared uniforms and night; r81_trip.gd sets the tunnel span.
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform sampler2D tex_asphalt : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_asphalt_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
// 0 = day, 1 = night.
uniform float night = 0.0;
// 1 = the picture slides back as we drive (our road), -1 = the strip is turned round (the other road).
uniform float flow = 1.0;
// The tunnel in view: it covers the road from world z = tunnel_a to tunnel_b (a > b; equal = none).
uniform float tunnel_a = 0.0;
uniform float tunnel_b = 0.0;
uniform vec3 lamp_color : source_color = vec3(1.0, 0.62, 0.25);
// Streetlights (r81_trip.gd lit_at and _apply): a pole stands in the median halfway along
// every lit place (places are 80 m; the lit ones are the 8 before a tunnel's first place and
// the 6th to 13th after it, repeating every street_period places). street_a = the colour of
// the poles with even place numbers, street_b the odd ones'; street_on = 0 by day or with
// the lights off .. 1 at night.
uniform float street_period = 88.0;
uniform vec3 street_a : source_color = vec3(1.0, 0.62, 0.25);
uniform vec3 street_b : source_color = vec3(1.0, 0.62, 0.25);
uniform float street_on = 0.0;
// `travel` is wrapped (r22_common.gdshaderinc), so it cannot say which place a spot is in:
// route_base = the metres to add to (travel - z) to get the true distance along the route,
// itself wrapped at a length the streetlights' pattern divides (r81_trip.gd _apply).
uniform float route_base = 0.0;
// How strongly the tunnel's light pools stand out as they slide by: 1 = full, less in
// photosensitive-safe mode (r81_trip.gd), so the road never pulses hard.
uniform float pulse = 1.0;

varying vec3 o_pos;
varying vec3 w_pos;

void vertex() {
	o_pos = VERTEX;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

float stripe(float x, float a, float b) {
	return smoothstep(a - 0.01, a + 0.01, x) * smoothstep(b + 0.01, b - 0.01, x);
}

void fragment() {
	float x = o_pos.x;
	float along = o_pos.z - flow * travel;
	vec2 q = vec2(x, along);
	vec3 col = texture(tex_asphalt, q / 4.0).rgb * 0.8;
	if (detail < 0.5) {
		col = mix(vec3(0.17, 0.17, 0.18), col, 0.3);
	}
	// wheel tracks down each lane (lane middles at -1.8 and +1.8)
	float lane = abs(abs(x) - 1.8);
	col *= 1.0 - 0.14 * smoothstep(0.8, 0.35, abs(lane - 0.75)) * step(abs(x), 3.6);
	// the shoulders are paler, older asphalt
	col = mix(col, col * 1.2 + 0.02, smoothstep(3.7, 4.0, abs(x)));
	float wear = smoothstep(0.2, 0.55, texture(rock_noise, q / vec2(2.0, 8.0)).a);
	float dash = stripe(abs(x), -0.01, 0.07) * step(fract(along / 16.0), 0.25);
	float yellow = stripe(x, -3.78, -3.63);
	float white = stripe(x, 3.63, 3.78);
	col = mix(col, vec3(0.86, 0.86, 0.83), (dash + white) * wear * 0.92);
	col = mix(col, vec3(0.86, 0.64, 0.12), yellow * wear * 0.92);
	// rumble strips: short grooves across, just outside each edge line
	float rumble = (stripe(x, -4.45, -4.05) + stripe(x, 4.05, 4.5)) * step(fract(along / 0.4), 0.45);
	col *= 1.0 - 0.3 * rumble;
	col *= r22_cloud_shade(w_pos);
	float puddle = smoothstep(0.62, 0.72, texture(rock_noise, q / 16.0).b) * wet * smoothstep(2.5, 4.5, abs(x));
	col *= 1.0 - 0.45 * wet;
	float rough = mix(0.8, 0.2, wet);
	rough = mix(rough, 0.03, puddle);
	if (detail > 0.5) {
		vec3 nt = texture(tex_asphalt_nor, q / 4.0).rgb * 2.0 - 1.0;
		vec3 on = normalize(vec3(nt.x, nt.z, -nt.y));
		on = normalize(mix(on, vec3(0.0, 1.0, 0.0), clamp(puddle + dash + white + yellow + wet * 0.5, 0.0, 1.0)));
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(on, 0.0)).xyz);
	}
	// inside the tunnel: lamp light only (the sun's shadow map doesn't reach that far in)
	float inside = smoothstep(tunnel_a + 2.0, tunnel_a - 4.0, w_pos.z) * smoothstep(tunnel_b - 2.0, tunnel_b + 4.0, w_pos.z);
	inside *= step(tunnel_b + 0.5, tunnel_a);
	float pool = mix(0.72, 0.45 + 0.55 * smoothstep(4.0, 0.0, abs(fract(along / 8.0) - 0.5) * 8.0), pulse);
	ALBEDO = col * (1.0 - 0.97 * inside);
	EMISSION = col * lamp_color * pool * inside * 0.9;
	// a streetlight's pool: brightest under the lamp (which hangs over the left lane, x = -3
	// on both roads), fading along and across; evened out in photosensitive-safe mode.
	// Each spot gets the light of its own place's pole and of the poles of the places either
	// side, so the light runs on past the first and last pole of a lit stretch and fades out
	// over about 40 m into the dark instead of stopping at the place's edge (Sen, round 7).
	// (The even part is a smoothstep ramp 80 m either side of each pole: two neighbouring
	// ramps add up to exactly 1, so between lit poles it stays even.)
	float route = -flow * along + route_base;
	float place = floor(route / 80.0);
	float across = exp(-(x + 3.0) * (x + 3.0) / 90.0);
	vec3 street = vec3(0.0);
	for (int i = -1; i <= 1; i++) {
		float p = place + float(i);
		float nth = mod(p, street_period);
		float lit = max(step(street_period - 8.0, nth), step(6.0, nth) * step(nth, 13.0));
		float from_pole = route - (p + 0.5) * 80.0;
		float even = smoothstep(80.0, 0.0, abs(from_pole));
		float glow = mix(0.45 * even, exp(-from_pole * from_pole / 900.0), pulse);
		street += mix(street_a, street_b, mod(p, 2.0)) * glow * lit;
	}
	EMISSION += col * street * across * street_on * (1.0 - inside) * 2.4;
	ROUGHNESS = rough;
	SPECULAR = 0.4 + 0.3 * wet;
}
