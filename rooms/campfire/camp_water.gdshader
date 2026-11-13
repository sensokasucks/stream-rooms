shader_type spatial;
render_mode unshaded, cull_back;
// Lakeside Campfire: the lake and the stream. One flat sheet each; this shader makes it look
// like water without any costly reflection pass:
//   - small waves are a rippled "which way is up" worked out from drifting noise,
//   - looking along the water it mirrors the sky (the hour's colours, handed over by the room
//     script), the far shore's ridges and trees (the same outline the sky shader draws, from
//     camp_horizon.gdshaderinc), a glitter path under the sun or the moon, and a warm streak
//     from the campfire; looking down into it shows the dark water colour,
//   - rain covers it in small spreading rings,
//   - lightning brightens it for a moment.
// rooms/campfire/campfire_room.gd (_apply_time, _apply_weather) sets the uniforms. It is drawn
// unshaded (the colours here are final), so the room's lamps do not light it.
#include "res://rooms/campfire/camp_horizon.gdshaderinc"

uniform vec3 sky_top : source_color = vec3(0.08, 0.27, 0.72);
uniform vec3 sky_horizon : source_color = vec3(0.5, 0.68, 0.92);
uniform vec3 shore_color : source_color = vec3(0.03, 0.07, 0.05);     // the far ridges and trees, mirrored
uniform vec3 deep_color : source_color = vec3(0.01, 0.05, 0.07);      // looking straight down
// The sun or the moon, whichever is up: a unit vector pointing AT it, and its colour x strength.
uniform vec3 light_dir = vec3(0.0, 0.5, -0.8);
uniform vec3 light_color = vec3(1.0, 0.9, 0.7);
// The campfire: where it is (world space) and its colour x strength (0 = out).
uniform vec3 fire_pos = vec3(0.0, 1.0, 0.0);
uniform vec3 fire_color = vec3(1.0, 0.5, 0.2);
// Which way the water drifts (world x, z metres a second): slow on the lake, quick in the stream.
uniform vec2 flow = vec2(0.05, 0.02);
// Wave size: 1 = the lake on a still evening; wind and rain raise it.
uniform float wave = 1.0;
// 0 = dry, 1 = pouring: rings from the drops.
uniform float rain = 0.0;
// How much the far shore shows in the reflection (the stream has none).
uniform float shore_amount = 1.0;
// Extra light added to everything (lightning).
uniform float flash = 0.0;

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The water's height at a point: two layers of noise drifting across each other.
float height(vec2 p) {
	vec2 a = p * 0.9 + flow * TIME * 6.0;
	vec2 b = p * 2.3 - flow.yx * TIME * 9.0 + vec2(TIME * 0.11, 0.0);
	return noise2(a) * 0.6 + noise2(b) * 0.3 + noise2(p * 6.1 + vec2(0.0, TIME * 0.35)) * 0.1;
}

// Rings from raindrops: the surface is cut into cells, each with one drop that lands at a
// random moment and spreads as a ring that fades. Returns the push on the surface's slope.
vec2 rain_rings(vec2 p) {
	vec2 push = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 q = p * (1.4 + float(k) * 0.9) + vec2(float(k) * 17.3);
		vec2 cell = floor(q);
		vec2 centre = cell + 0.2 + 0.6 * vec2(hash2(cell), hash2(cell + 7.7));
		float age = fract(TIME * (0.7 + 0.5 * hash2(cell + 3.1)) + hash2(cell + 1.3));
		vec2 off = q - centre;
		float dist = length(off);
		float ring = sin((dist - age * 0.45) * 60.0) * smoothstep(0.06, 0.0, abs(dist - age * 0.45)) * (1.0 - age);
		push += normalize(off + vec2(0.0001)) * ring;
	}
	return push;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	// the surface's slope from three height samples, plus the rain's rings
	float e = 0.12;
	float h0 = height(p);
	vec2 slope = vec2(height(p + vec2(e, 0.0)) - h0, height(p + vec2(0.0, e)) - h0) / e;
	slope *= 0.11 * wave;
	if (rain > 0.01) {
		slope += rain_rings(p) * 0.35 * rain;
	}
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view = normalize(cam - world_pos);
	vec3 r = reflect(-view, n);
	r.y = abs(r.y);
	// what the mirror shows: the sky, then the far shore over it
	vec3 mirror = mix(sky_horizon, sky_top, pow(clamp(r.y, 0.0, 1.0), 0.5));
	float az = atan(r.x, -r.z);
	float shore = max(max(hz_far_ridge(az), hz_near_ridge(az)), hz_tree_line(az));
	mirror = mix(mirror, shore_color, smoothstep(shore + 0.02, shore - 0.02, r.y) * shore_amount * 0.9);
	// the glitter path under the sun or the moon: a tight sparkle and a wide soft sheen
	float ld = max(dot(r, normalize(light_dir)), 0.0);
	mirror += light_color * (pow(ld, 420.0) * 6.0 + pow(ld, 48.0) * 0.35);
	// the fire's light on the water: a warm streak toward the camp
	vec3 to_fire = normalize(fire_pos - world_pos);
	float fd = max(dot(r, to_fire), 0.0);
	float near = 1.0 / (1.0 + 0.004 * dot(fire_pos - world_pos, fire_pos - world_pos));
	mirror += fire_color * (pow(fd, 90.0) * 2.2 + pow(fd, 12.0) * 0.12) * near;
	// looking along the water you see the mirror, looking down you see into it
	float fres = 0.03 + 0.97 * pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 5.0);
	vec3 c = mix(deep_color, mirror, clamp(fres, 0.0, 1.0));
	c += vec3(0.35, 0.4, 0.55) * flash * 0.25;
	ALBEDO = c;
}
