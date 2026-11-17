shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Lakeside Campfire: one butterfly. rooms/campfire/campfire_room.gd (_build_butterflies) draws
// a few small squares as particles with this; the particle's colour (COLOR) is the wings'
// colour and its alpha fades the butterfly in and out. The square always faces the camera,
// is cut to two rounded wings with a dark body between, and the wings beat by squeezing the
// square's width (each butterfly out of step with the others, by its number).

void vertex() {
	float beat = abs(sin(TIME * 13.0 + float(INSTANCE_ID) * 2.4));
	// face the camera, keeping the particle's place; then bob a little with the wing beat
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	VERTEX.x *= 0.2 + 0.8 * beat;
	VERTEX.y += 0.015 * beat;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;                // -1 .. 1 across the square, the body down the middle
	// each wing: an upper and a smaller lower lobe
	float upper = length((vec2(abs(p.x), p.y) - vec2(0.5, -0.25)) / vec2(0.5, 0.6));
	float lower = length((vec2(abs(p.x), p.y) - vec2(0.38, 0.5)) / vec2(0.36, 0.42));
	float wing = min(upper, lower);
	if (wing > 1.0 && abs(p.x) > 0.07) {
		discard;
	}
	vec3 c = COLOR.rgb * (1.0 - 0.55 * smoothstep(0.6, 1.0, wing));      // darker wing edges
	c = mix(c, vec3(0.05, 0.04, 0.03), step(abs(p.x), 0.07));            // the body
	ALBEDO = c;
	ALPHA = COLOR.a;
}
