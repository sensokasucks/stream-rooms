shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Lakeside Campfire: mist lying on the lake. rooms/campfire/campfire_room.gd (_build_mist,
// _apply_time) lays a few big flat sheets just above the water, one over another, and sets
// `amount` (the Mist slider, strongest at dawn and dusk) and `color` (the haze's colour for
// the hour). Each sheet shows drifting patches from the sky's noise picture; it thins out
// close to the camera (so the camera never pops through a sheet) and at the sheet's edges.

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.7, 0.75, 0.8);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// two patch patterns drifting through each other (each sheet's height shifts them, so the
	// sheets do not line up)
	vec2 p = world_pos.xz + world_pos.y * 37.0;
	float a = texture(noise, p * 0.011 + TIME * vec2(0.004, 0.0015)).r;
	float b = texture(noise, p * 0.027 - TIME * vec2(0.003, 0.005)).g;
	float patch = smoothstep(0.25, 0.75, a * 0.7 + b * 0.5);
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(cam - world_pos);
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x) * smoothstep(0.0, 0.1, UV.y) * smoothstep(1.0, 0.9, UV.y);
	ALBEDO = color;
	ALPHA = amount * patch * 0.5 * edge * smoothstep(3.0, 14.0, dist);
}
