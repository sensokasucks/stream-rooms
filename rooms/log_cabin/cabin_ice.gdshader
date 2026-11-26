shader_type spatial;
render_mode cull_disabled;
// Cabin: Frozen North: the frozen lake (cabin_north.gd _build_ice, one huge flat sheet). Lit like
// everything else (not unshaded like the lake's water), so the sun, the moon and the sky's
// reflection light it by themselves and the room script sets nothing on it each hour.
// What it draws, by world position:
//   - black ice: dark, glassy and smooth where the wind has swept it clean, so it mirrors the
//     sky (and the aurora) like a dark mirror,
//   - drifts: snow blown across the ice in long soft streaks along the wind (x), white and matt,
//   - cracks: thin pale lines in the clear ice, and a few long pressure ridges,
//   - frosted ice between: grey-blue and a little rough.
// `noise` is the sky's cloud noise picture (rooms/campfire/textures/sky_noise.png; any tiling noise does): its channels at a few
// scales break everything up so it never repeats in sight.

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
// How much of the ice the drifts cover, 0..1.
uniform float drifts : hint_range(0.0, 1.0) = 0.45;
uniform vec3 black_ice : source_color = vec3(0.025, 0.045, 0.06);
uniform vec3 frosted : source_color = vec3(0.42, 0.5, 0.58);
uniform vec3 snow_col : source_color = vec3(0.86, 0.9, 0.95);

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz;
	// streaks along the wind: stretched 5x along x
	float big = texture(noise, p * vec2(0.0035, 0.016)).r;
	float mid = texture(noise, p * vec2(0.011, 0.05) + vec2(0.37, 0.11)).g;
	float fine = texture(noise, p * 0.09 + vec2(0.71, 0.29)).b;
	float drift = smoothstep(0.62 - drifts * 0.4, 0.75 - drifts * 0.4, big * 0.6 + mid * 0.4 + fine * 0.08);
	// the swept, polished parts (where neither drift nor frost)
	float swept = 1.0 - smoothstep(0.35, 0.6, mid * 0.7 + fine * 0.3);
	// cracks: where a noise crosses its middle, a thin line; long ridges from the big scale
	float cn = texture(noise, p * 0.028 + vec2(0.13, 0.57)).r;
	float crack = 1.0 - smoothstep(0.0, 0.012, abs(cn - 0.5));
	float ridge = 1.0 - smoothstep(0.0, 0.004, abs(texture(noise, p * vec2(0.0012, 0.004)).g - 0.5));
	vec3 ice = mix(frosted, black_ice, swept);
	ice = mix(ice, frosted * 1.6, crack * 0.7 * (1.0 - drift));
	ice = mix(ice, snow_col * 0.92, ridge * 0.8);
	ALBEDO = mix(ice, snow_col, drift);
	ROUGHNESS = mix(mix(0.42, 0.04, swept), 0.85, max(drift, ridge * 0.8));
	SPECULAR = mix(0.7, 0.35, drift);
	METALLIC = 0.0;
	// a faint unevenness in the clear ice, so the reflection wavers a little
	vec3 bump = vec3((fine - 0.5) * 0.05, 1.0, (mid - 0.5) * 0.05);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(bump), 0.0)).xyz);
}
