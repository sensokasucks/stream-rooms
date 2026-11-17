shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap, specular_disabled;
// Route 22: one puff of airborne dust. Every dust effect's particles wear it (r22_geo.gd
// dust_material): the blowing sand of a dust storm or a gale (r22_desert.gd), the dust devils
// (r22_extras.gd) and the trail behind the Cruise's car (r22_car.gd).
// Each particle is a square that turns to face the camera. Instead of a hard square or a round
// blob it shows a ragged wisp: a soft round falloff eaten into by drifting noise, more and more
// as the particle ages, so a puff frays and thins out rather than popping. It fades where it
// meets the ground or a wall (no hard line), and fades out right in front of the camera.
// It takes the sun's and the sky's light, so dust is dim at night and warm at sunset.
//   COLOR            from the particles' colour ramp: the dust's colour and how thick it is,
//   INSTANCE_CUSTOM  x = the particle's turn (radians), y = its age 0..1 (the engine fills both).

// soft lumpy noise in .b and fine speckle in .a (textures/rock_noise.png)
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// How the noise is laid on the square: (1, 1) for a round puff; (0.25, 1) stretches it along
// the square's width into streaks (blowing sand).
uniform vec2 grain = vec2(1.0, 1.0);
// How ragged the edge is, 0 = a plain soft ball, 1 = torn wisps.
uniform float ragged = 0.8;
// Metres over which a puff fades into the ground or a wall behind it.
uniform float soften = 0.8;

varying vec2 seed;
varying float age;

void vertex() {
	// face the camera, keep the particle's own turn and size (what a StandardMaterial3D set to
	// "particle billboard" does)
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float c = cos(INSTANCE_CUSTOM.x);
	float s = sin(INSTANCE_CUSTOM.x);
	world = world * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * world * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// every particle its own patch of the noise (the golden ratio spreads the patches evenly)
	float id = float(INSTANCE_ID);
	seed = vec2(fract(id * 0.61803), fract(id * 0.41421));
	age = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 p = UV - 0.5;
	// 1 in the middle, 0 at the rim, with a long soft shoulder (no edge to see)
	float ball = clamp(1.0 - dot(p, p) * 4.0, 0.0, 1.0);
	ball = ball * ball * (3.0 - 2.0 * ball);
	// three sizes of noise, sliding slowly past each other so the wisp churns
	vec2 q = p * grain;
	float lumps = texture(rock_noise, q * 0.5 + seed + vec2(TIME * 0.02, 0.0)).b;
	float fine = texture(rock_noise, q * 1.3 + seed.yx - vec2(0.0, TIME * 0.03)).b;
	float tiny = texture(rock_noise, q * 3.1 - seed + vec2(TIME * 0.025)).b;
	float n = lumps * 0.5 + fine * 0.32 + tiny * 0.18;
	// the noise thins the whole puff into strands and holes (not only its rim, or it would
	// still read as a ball); the middle holds out longest, and with age more of it goes
	float eat = mix(0.34, 0.6, age);
	float wisp = smoothstep(eat - 0.22, eat + 0.3, n + (ball - 0.5) * 0.45);
	float a = ball * mix(1.0, wisp, ragged);
	// soft where it meets what is behind it, and gone before it reaches the camera
	float depth = texture(depth_tex, SCREEN_UV).r;
	// (the two renderers store depth differently: the Compatibility one needs it spread to -1..1)
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 behind = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, depth) * 2.0 - 1.0, 1.0);
#else
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	behind.xyz /= behind.w;
	a *= clamp((VERTEX.z - behind.z) / soften, 0.0, 1.0);
	a *= smoothstep(0.4, 2.5, -VERTEX.z);
	// a little lighter in its thin parts, like real dust against the light
	ALBEDO = COLOR.rgb * mix(1.12, 0.9, a);
	ALPHA = COLOR.a * a;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.45);
}
