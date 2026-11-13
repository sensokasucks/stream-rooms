shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The Forge Hall's flames. ForgeHallRoom (_add_flame) stands several upright rectangles in each
// fire, and this shader paints one flame on each. Every rectangle turns to face the camera
// round its upright axis, so a flame never shows as a flat card from the side.
// The flame: a teardrop that leans and curls more the higher it gets (the picture is pushed
// sideways by slow noise), with fast fine noise eating into its edge so tongues split off and
// rise. Its heat (1 in the core, 0 at the edge) picks the colour: deep red at the tips,
// orange, yellow, and near white at the base. Colours go above 1.0 on purpose, so the room's
// bloom makes the fire glow. Added onto the picture: the black parts are see-through.
// (fog_disabled: the Lakeside Campfire uses this shader too, outdoors in fog, and fog on a
// picture that is added on would show the whole rectangle as a pale square.)

uniform float amount = 1.0;               // the Room tab's Fire slider (0 = out, 1 = normal, 2 = roaring)
uniform float seed = 0.0;                 // a different number per rectangle, so they don't move alike
uniform float speed = 1.0;                // how fast the flames rise (1 = a wood fire)
uniform float brightness = 2.6;           // colour multiplier at Fire 100% (above 1 = blooms)
uniform vec3 white_hot : source_color = vec3(1.0, 0.93, 0.72);
uniform vec3 yellow : source_color = vec3(1.0, 0.66, 0.16);
uniform vec3 orange : source_color = vec3(1.0, 0.30, 0.03);
uniform vec3 red : source_color = vec3(0.45, 0.04, 0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// four layers of noise, each finer and fainter: soft, cloud-like detail (0..1)
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v / 0.9375;
}

void vertex() {
	// face the camera, turning only round the upright axis (the rectangle's own turn is dropped)
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + vec3(0.0, 0.0, 0.0001));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(to_cam, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// p: x from -1 (left edge) to 1, y from 0 at the logs to 1 at the rectangle's top
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float t = TIME * speed + seed * 13.7;
	float reach = mix(0.55, 1.0, clamp(amount * 0.5, 0.0, 1.0));      // a bigger fire reaches higher
	float y = p.y / reach;
	// the flame sways and curls: slow noise pushes it sideways, more towards the top
	float sway = fbm(vec2(p.x * 1.3 + seed * 3.1, p.y * 1.6 - t * 1.1)) - 0.5;
	p.x += sway * (0.15 + 1.1 * y);
	// teardrop outline: full width just above the logs, a point at the top
	float width = 0.7 * pow(max(1.0 - y, 0.0), 0.7) * smoothstep(-0.05, 0.18, y);
	float core = 1.0 - abs(p.x) / max(width, 0.001);                  // 1 on the centre line, 0 at the outline
	// rising detail: a coarse layer for the tongues, a fine fast one for the ragged edge
	float tongues = fbm(vec2(p.x * 2.6 + seed * 5.0, p.y * 2.2 - t * 2.4));
	float ragged = fbm(vec2(p.x * 6.5 - seed * 2.0, p.y * 4.5 - t * 4.2));
	float heat = core * 0.85 + (tongues - 0.5) * 1.5 + (ragged - 0.5) * 0.55 - y * 0.55;
	heat *= smoothstep(0.0, 0.07, p.y) * step(y, 1.0);
	float a = smoothstep(0.02, 0.45, heat);
	vec3 c = mix(red, orange, smoothstep(0.05, 0.38, heat));
	c = mix(c, yellow, smoothstep(0.32, 0.68, heat));
	c = mix(c, white_hot, smoothstep(0.7, 1.15, heat));
	ALBEDO = c * a * a * brightness * clamp(amount, 0.0, 1.6);
}
