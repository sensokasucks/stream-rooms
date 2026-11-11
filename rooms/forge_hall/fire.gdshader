shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// The Forge Hall's flames. ForgeHallRoom builds a few upright rectangles at each FIRE_ marker
// (UV.x across, UV.y 0 at the logs and 1 at the top) and this shader paints a flame on each:
// rising noise shaped into tongues that narrow towards the top, white-yellow at the base and
// orange to red at the tips. Added onto the picture, so the black parts are see-through.

uniform float amount = 1.0;               // the Room tab's Fire slider (0 = out, 1 = normal, 2 = roaring)
uniform float seed = 0.0;                 // a different number per rectangle, so they don't move alike
uniform float speed = 1.4;                // how fast the flames rise
uniform vec3 hot : source_color = vec3(1.0, 0.9, 0.55);
uniform vec3 mid : source_color = vec3(1.0, 0.45, 0.06);
uniform vec3 cool : source_color = vec3(0.7, 0.08, 0.01);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	// two layers of noise sliding upward, the finer one faster
	float n = noise(vec2(uv.x * 4.0 + seed * 7.3, uv.y * 3.0 - t)) * 0.6
			+ noise(vec2(uv.x * 9.0 - seed * 3.1, uv.y * 6.0 - t * 1.7)) * 0.4;
	// a flame is widest at the bottom and comes to a ragged point: the noise eats into the edge
	float reach = clamp(0.55 + 0.25 * amount, 0.3, 1.0);          // a bigger fire reaches higher
	float side = 1.0 - abs(uv.x - 0.5) * 2.0;
	float body = side * (1.0 - uv.y / reach) + (n - 0.5) * (0.5 + uv.y);
	float a = smoothstep(0.0, 0.35, body) * smoothstep(0.0, 0.06, uv.y);
	vec3 c = mix(cool, mid, smoothstep(0.05, 0.4, body));
	c = mix(c, hot, smoothstep(0.4, 0.85, body));
	ALBEDO = c * a * clamp(amount, 0.0, 2.0);
}
