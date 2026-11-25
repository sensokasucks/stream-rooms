shader_type spatial;
render_mode cull_disabled;
// Log Cabin: the lit lampshades, the chandelier's candles and the lantern (cabin_builder.gd
// _build_lamps makes them; log_cabin_room.gd sets `level` from the house lights every time they
// change). A cloth shade glows brightest where you look straight through it and dims towards its
// rim, where the light crosses more cloth; with `detail` at 1 (Set detail = Detailed) the weave of
// the wool photo shows in the glow. Nothing moves or flickers here (photosensitive-safe).

// how brightly the lamps burn: 0 = off, 1 = full (the room's house light level)
uniform float level = 1.0;
uniform float detail = 0.0;
// the wool photo (textures/wool.jpg, divided by its own average: 0.5 = no change)
uniform sampler2D weave : filter_linear_mipmap, repeat_enable;
uniform vec3 cloth : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 light : source_color = vec3(1.0, 0.66, 0.36);

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// facing = 1 looking straight through the cloth, 0 at the rim
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float through = mix(0.45, 1.0, facing * facing);
	float grain = 1.0;
	if (detail > 0.5) {
		grain = texture(weave, vec2(atan(w_pos.x, w_pos.z) * 0.6 + w_pos.x * 3.0, w_pos.y * 6.0)).r * 2.0;
	}
	ALBEDO = cloth * mix(0.35, 1.0, level);
	ROUGHNESS = 0.9;
	EMISSION = light * 2.4 * level * through * mix(1.0, grain, 0.6);
}
