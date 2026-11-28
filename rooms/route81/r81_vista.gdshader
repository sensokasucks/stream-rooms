shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Route 81: the distant views (r81_vistas.gd): a river, a town, a viaduct, a ski hill, a wind
// farm... one to three kilometres from the road, on the far view's valley floor and ridges.
// Like the ridges themselves (r81_backdrop.gdshader) they are too far for the scene's fog and
// shadows, so they are lit and hazed here with the same numbers (r22_desert.gd writes them to
// both): sun_dir, day, sky_horizon, haze_length. `season` comes from r81_trip.gd.
//   COLOR.rgb  the corner's colour
//   UV.x       what it is (r81_vistas.gd K_ numbers):
//              0 plain   1 water (takes the sky's colour)   2 a light (window, street lamp:
//              dull by day, glowing at night)   3 a red warning light on a mast (glows at
//              night, swelling slowly)   4 tree tops (turn in fall)   5 bare stones (speckled)
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);
uniform float day = 1.0;
uniform vec3 sky_horizon = vec3(0.62, 0.66, 0.78);
uniform float season = 0.0;
uniform float haze_length = 4500.0;
// 1 = the warning lights hold steady instead of swelling (photosensitive-safe mode; they are
// slow and tiny either way).
uniform float steady = 0.0;

varying vec3 w_pos;
varying vec3 w_nrm;
varying vec3 o_pos;
varying float kind;

void vertex() {
	kind = UV.x;
	o_pos = VERTEX;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	// Drawn a touch nearer than it is: these lie right on the far view's ground, and at
	// kilometres the depth buffer could not tell which of the two is in front.
	POSITION = PROJECTION_MATRIX * vec4((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * 0.996, 1.0);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	// (both faces are drawn; a face seen from behind is lit as if it faced us, so a shape
	// built inside out still catches the sun)
	vec3 n = normalize(w_nrm) * (FRONT_FACING ? 1.0 : -1.0);
	float lit = 0.35 + 0.75 * max(dot(n, normalize(sun_dir)), 0.0);
	float night = 1.0 - smoothstep(0.1, 0.45, day);
	vec3 glow = vec3(0.0);
	if (kind > 4.5) {
		// a field of bare stones: light and dark speckle
		col *= 0.7 + 0.6 * texture(rock_noise, o_pos.xz / 40.0).a;
	} else if (kind > 3.5) {
		float pick = texture(rock_noise, o_pos.xz / 300.0).g;
		float fine = texture(rock_noise, o_pos.xz / 90.0).a;
		col *= 0.75 + 0.5 * fine;
		vec3 fall = mix(vec3(0.5, 0.3, 0.06), vec3(0.45, 0.14, 0.05), smoothstep(0.35, 0.65, pick));
		col = mix(col, fall, season * smoothstep(0.3, 0.45, fine));
	} else if (kind > 2.5) {
		float swell = mix(0.5 + 0.5 * sin(TIME * 1.6), 0.8, steady);
		glow = vec3(3.0, 0.15, 0.08) * swell * night;
		col = vec3(0.35, 0.05, 0.04);
	} else if (kind > 1.5) {
		glow = col * 2.2 * night;
		col *= 0.45;
	} else if (kind > 0.5) {
		// water lies flat and shows the sky near the horizon
		col = mix(col, sky_horizon * 0.9, 0.6);
		lit = 1.0;
	}
	col *= lit * (0.03 + 0.97 * day);
	float haze = 1.0 - exp(-dist / haze_length);
	// (lights carry further through haze than what they stand on)
	ALBEDO = mix(col, sky_horizon, clamp(haze, 0.0, 0.97)) + glow * (1.0 - 0.6 * haze);
}
