shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Dusty sunbeams from the sunlit lancets. LectureHallRoom builds each beam as an open box:
// the window's outline pushed along the sun's direction. UV.x runs across each side face,
// UV.y from the window (0) to the far end (1). The beam is brightest near the glass, fades
// out along its length and at its edges, never shows a hard line where it meets the pews or
// the floor, and has a few specks of dust drifting through it.

uniform vec3 color : source_color = vec3(1.0, 0.84, 0.6);
uniform float intensity = 0.35;
uniform float light_level = 1.0;          // from the room (house lights); 0 = no beams
uniform float soft_depth = 1.5;           // metres over which the beam fades into geometry
uniform float dust_amount = 0.9;
uniform float shimmer_speed = 0.25;

uniform bool depth_fade = true;
// keep the picture clean: beams lying between the camera and the main screen fade out
uniform vec3 screen_c = vec3(0.0);        // screen centre (world)
uniform vec3 screen_x = vec3(0.0);        // half width, along the screen (world)
uniform vec3 screen_y = vec3(0.0);        // half height, up the screen (world)
uniform float screen_guard = 0.9;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 w_pos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float along = UV.y;
	float fade_len = smoothstep(0.0, 0.15, along) * pow(1.0 - along, 1.3);   // builds up past the glass
	float across = UV.x;
	float edge = smoothstep(0.0, 0.4, across) * smoothstep(1.0, 0.6, across);
	// side faces seen edge-on would show as lines: fade them by the view angle
	float view = pow(abs(dot(NORMAL, VIEW)), 0.7);
	// slow shimmer as the air moves
	float shimmer = 0.8 + 0.4 * noise2(vec2(across * 3.0 + TIME * shimmer_speed, along * 6.0 - TIME * shimmer_speed * 0.6));

	float soft = 1.0;
	if (depth_fade) {
		float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
		vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		vec4 vp = INV_PROJECTION_MATRIX * ndc;
		float scene_d = -vp.z / vp.w;
		soft = clamp((scene_d + VERTEX.z) / soft_depth, 0.0, 1.0);
	}

	float guard = 1.0;
	vec3 sn = cross(screen_x, screen_y);
	if (screen_guard > 0.0 && dot(sn, sn) > 1e-6) {
		vec3 cam = CAMERA_POSITION_WORLD;
		vec3 dir = w_pos - cam;
		float den = dot(dir, sn);
		if (abs(den) > 1e-6) {
			float t = dot(screen_c - cam, sn) / den;
			if (t > 1.0) {              // the screen lies beyond this bit of beam
				vec3 hit = cam + dir * t - screen_c;
				float u = abs(dot(hit, screen_x) / dot(screen_x, screen_x));
				float v = abs(dot(hit, screen_y) / dot(screen_y, screen_y));
				float inside = (1.0 - smoothstep(0.95, 1.25, u)) * (1.0 - smoothstep(0.95, 1.25, v));
				guard = 1.0 - screen_guard * inside;
			}
		}
	}

	// dust: one speck per 20 cm cell, drifting slowly upward, twinkling as it turns
	vec3 p = w_pos * 5.0 + vec3(0.0, TIME * 0.12, TIME * 0.05);
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 spot = vec3(hash3(cell), hash3(cell + 17.0), hash3(cell + 31.0)) * 0.6 + 0.2;
	float speck = smoothstep(0.07, 0.0, length(f - spot));
	float twinkle = 0.5 + 0.5 * sin(TIME * (1.5 + hash3(cell + 5.0) * 3.0) + hash3(cell) * 6.283);
	float dust = speck * twinkle * dust_amount * step(0.55, hash3(cell + 9.0));

	float a = intensity * fade_len * edge * view * soft * shimmer * guard * clamp(light_level, 0.0, 1.0);
	ALBEDO = color * a * (1.0 + dust * 14.0);
}
