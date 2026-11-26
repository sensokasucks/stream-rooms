shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Route 81: the far view (r81_land.gd build_backdrop): the valley floor and the long parallel
// ridges 1 to 12 km away. Too far for the scene's fog and shadows to make sense, so it lights
// and hazes itself here:
//   forest canopy colour in patches (fall colours with `season`), fields on the valley floor,
//   plain sun light from sun_dir (the same sun as everything else), dimmed by `day`,
//   and blue distance haze: the further a point is, the more it takes the horizon's colour
//   (sky_horizon). That fading is what makes the ridges read as rows, one behind the other.
// COLOR.r = 1 on the valley floor (fields mixed in), 0 on ridges. r81_trip.gd moves and turns
// the whole backdrop (altitude, heading); route81_room.gd writes the light uniforms.
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform float day = 1.0;
uniform vec3 sky_horizon = vec3(0.62, 0.66, 0.78);
uniform float season = 0.0;
// Metres over which the haze takes about two thirds of the colour.
uniform float haze_length = 4500.0;

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec3 o_pos;

void vertex() {
	o_pos = VERTEX;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec2 q = o_pos.xz;
	float big = texture(rock_noise, q / 2400.0).b;
	float mid = texture(rock_noise, q / 600.0).b;
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	// (the fine speckle only close by: far off, on a slope seen edge-on, it smears into stripes)
	float fine = mix(0.5, texture(rock_noise, q / 150.0).a, exp(-dist / 1800.0));
	vec3 green = mix(vec3(0.05, 0.11, 0.035), vec3(0.11, 0.19, 0.06), smoothstep(0.3, 0.7, mid));
	green *= 0.75 + 0.5 * big;
	green *= 0.8 + 0.4 * fine;
	vec3 fall = mix(vec3(0.5, 0.3, 0.06), vec3(0.45, 0.14, 0.05), smoothstep(0.35, 0.65, texture(rock_noise, q / 300.0).g));
	vec3 col = mix(green, fall, season * smoothstep(0.25, 0.4, fine + mid * 0.5));
	// the valley floor: fields in blocks among the woods
	if (COLOR.r > 0.5) {
		vec2 cell = floor(q / 180.0);
		float pick = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec3 field = mix(vec3(0.3, 0.36, 0.12), vec3(0.5, 0.45, 0.2), fract(pick * 7.0));
		float open = smoothstep(0.5, 0.56, big + 0.3 * mid) * step(0.35, pick);
		col = mix(col, field, open);
	}
	float lit = 0.35 + 0.75 * max(dot(normalize(w_nrm), normalize(sun_dir)), 0.0);
	col *= lit * (0.03 + 0.97 * day);
	float haze = 1.0 - exp(-dist / haze_length);
	ALBEDO = mix(col, sky_horizon, clamp(haze, 0.0, 0.97));
}
