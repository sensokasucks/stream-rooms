shader_type spatial;
render_mode cull_disabled;
// Log Cabin: the glowing coals under the logs in each fireplace (cabin_builder.gd makes the bed of
// coals; log_cabin_room.gd _run_fire sets `amount` from the Fire setting every frame).
// Patches of the bed glow and fade slowly and on their own (two layers of the campfire's cloud
// noise drifting past each other), with dark crusts in between, the way a real bed of coals
// breathes. Slow on purpose: nothing in the room should flicker fast (photosensitive-safe).

// 0 = out (dark ash), 1 = a cozy fire, 2 = roaring
uniform float amount = 1.0;
// cloud noise (rooms/campfire/textures/sky_noise.png: three noise fields in r, g, b)
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 hot : source_color = vec3(1.0, 0.42, 0.1);
uniform vec3 cool : source_color = vec3(0.55, 0.08, 0.02);

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz * 2.2 + w_pos.y;
	float a = texture(noise, p * 0.5 + vec2(TIME * 0.011, TIME * 0.007)).r;
	float b = texture(noise, p * 0.9 - vec2(TIME * 0.009, -TIME * 0.013)).g;
	float heat = smoothstep(0.35, 0.75, a * 0.6 + b * 0.55);
	float crust = smoothstep(0.55, 0.3, b);
	float lit = clamp(amount, 0.0, 2.0);
	vec3 glow = mix(cool, hot, heat) * (0.35 + 1.4 * heat) * (1.0 - 0.75 * crust);
	ALBEDO = mix(vec3(0.05, 0.045, 0.04), vec3(0.12, 0.04, 0.02), heat);
	ROUGHNESS = 1.0;
	EMISSION = glow * 2.2 * lit;
}
