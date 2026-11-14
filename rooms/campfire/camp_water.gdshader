shader_type spatial;
render_mode unshaded, cull_back;
// Lakeside Campfire: the lake and the stream. One flat sheet each; this shader makes it look
// like water without any costly reflection pass:
//   - small waves are a rippled "which way is up" read from a ripple picture
//     (textures/water_normal.png, made by textures/make_textures.py) that is laid over the
//     water three times at different sizes, each copy sliding its own way, so the pattern
//     never repeats to the eye. (It used to be worked out from maths noise on the spot; on a
//     real graphics card that broke up into square blocks far from the camp.)
//   - looking along the water it mirrors the sky (the hour's colours, handed over by the room
//     script), the far shore's ridges and trees (the same outline the sky shader draws, from
//     camp_horizon.gdshaderinc), a glitter path under the sun or the moon, and a warm streak
//     from the campfire; looking down into it shows the dark water colour,
// rooms/campfire/campfire_room.gd (_apply_time) sets the uniforms. It is drawn
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
// Wave size: 1 = the lake on a still evening; the stream runs rougher.
uniform float wave = 1.0;
// How much the far shore shows in the reflection (the stream has none).
uniform float shore_amount = 1.0;

// The ripple picture: red = slope along x, green = slope along z, 0.5 = flat. Set by
// campfire_builder.gd (_build_water).
uniform sampler2D ripples : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;

// The water's slope (x, z) at a point: three copies of the ripple picture.
//   long swells, 22 m to a copy, drifting with the flow
//   middling waves, 9 m, turned a quarter and drifting against them
//   fine ripples, 3 m, sliding sideways; `fine` fades them out far away, where they would
//   only shimmer
vec2 ripple_slope(vec2 p, float fine) {
	vec2 drift = flow * TIME;
	vec2 a = texture(ripples, (p + drift * 5.0) * 0.045).rg - 0.5;
	vec2 b = texture(ripples, (p.yx - drift.yx * 8.0) * 0.11 + vec2(0.37, 0.61)).gr - 0.5;
	vec2 c = texture(ripples, p * 0.31 + vec2(TIME * 0.013, -TIME * 0.019)).rg - 0.5;
	return a * 1.3 + b * 0.9 + c * 0.7 * fine;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(cam - world_pos);
	float near_water = 1.0 / (1.0 + dist * 0.02);          // 1 at the camera, 1/3 at 100 m
	// the surface's slope from the ripple picture
	// (gentler far away: seen at a grazing angle, steep far ripples only make hard patches)
	vec2 slope = ripple_slope(p, near_water) * mix(0.2, 0.4, near_water) * wave;
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 view = normalize(cam - world_pos);
	vec3 r = reflect(-view, n);
	r.y = abs(r.y);
	// what the mirror shows: the sky, then the far shore over it
	vec3 mirror = mix(sky_horizon, sky_top, pow(clamp(r.y, 0.0, 1.0), 0.5));
	float az = atan(r.x, -r.z);
	float shore = max(max(hz_far_ridge(az), hz_near_ridge(az)), hz_tree_line(az));
	// (a soft edge: a ripple smears the shore's outline, it does not cut it out)
	mirror = mix(mirror, shore_color, smoothstep(shore + 0.1, shore - 0.05, r.y) * shore_amount * 0.9);
	// starlight: on the darkest night the ripples still catch a faint sheen, so the lake is
	// never a flat black hole (it only shows when the mirrored sky itself is near black)
	mirror = max(mirror, vec3(0.022, 0.034, 0.07) * (0.4 + 3.0 * clamp(r.y, 0.0, 1.0)));
	// the glitter path under the sun or the moon: a tight sparkle and a wide soft sheen
	float ld = max(dot(r, normalize(light_dir)), 0.0);
	// (the sparkle is tight close by and wider far off, where a pixel covers many ripples)
	mirror += light_color * (pow(ld, mix(140.0, 420.0, near_water)) * mix(2.5, 6.0, near_water) + pow(ld, 48.0) * 0.35);
	// the fire's light on the water: a warm streak toward the camp
	vec3 to_fire = normalize(fire_pos - world_pos);
	float fd = max(dot(r, to_fire), 0.0);
	float near = 1.0 / (1.0 + 0.004 * dot(fire_pos - world_pos, fire_pos - world_pos));
	mirror += fire_color * (pow(fd, 90.0) * 2.2 + pow(fd, 12.0) * 0.12) * near;
	// looking along the water you see the mirror, looking down you see into it
	float fres = 0.03 + 0.97 * pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 5.0);
	// the water's own colour: dark looking down, a little greener and lighter on the slopes
	// that face the camera (light coming through the wave)
	vec3 body = deep_color + vec3(0.0, 0.035, 0.03) * clamp(dot(slope, view.xz) * 4.0, 0.0, 1.0) * (0.3 + 0.7 * clamp(light_dir.y * 3.0, 0.0, 1.0));
	vec3 c = mix(body, mirror, clamp(fres, 0.0, 1.0));
	ALBEDO = c;
}
