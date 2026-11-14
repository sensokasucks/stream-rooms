shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Lakeside Campfire: the little stream's water. A thin, clear sheet over the stream's bed
// (the bed is real ground underneath, lit by the room's lamps and seen through the water):
//   - at the waterline the water fades away to nothing, so the edge follows the bank's shape
//     instead of being a cut line; where it is deeper it is tinted and less see-through,
//   - small ripples run down the stream (faster in the middle than at the banks), and they
//     mirror the sky's colour when seen at a low angle,
//   - white streaks of foam where the stream runs steep and along the shallow edges,
//   - the sun or the moon glints on it.
// The mesh is a ribbon made by campfire_builder.gd (_build_stream), which gives every corner:
//   UV.x     metres across from the stream's middle (negative = left bank),
//   UV.y     metres along the stream from the lake, so the ripples follow its bends,
//   COLOR.r  how deep the water is there, 0 (the waterline) .. 1 (25 cm or more),
//   COLOR.g  how steeply the stream runs downhill there, 0 (flat) .. 1 (a little cascade).
// rooms/campfire/campfire_room.gd (_apply_time) sets the sky and light uniforms. It is drawn
// unshaded like the lake (camp_water.gdshader), so `daylight` dims its own colours at night.

uniform vec3 sky_top : source_color = vec3(0.08, 0.27, 0.72);
uniform vec3 sky_horizon : source_color = vec3(0.5, 0.68, 0.92);
// The sun or the moon, whichever is up: a unit vector pointing AT it, and its colour x strength.
uniform vec3 light_dir = vec3(0.0, 0.5, -0.8);
uniform vec3 light_color = vec3(1.0, 0.9, 0.7);
// How bright the day is, 0.08 (night) .. 1 (noon): dims the water's own tint and the foam.
uniform float daylight = 1.0;
// The water's tint where it is shallow and where it is deeper (clear, a little peaty).
uniform vec3 shallow_color : source_color = vec3(0.2, 0.23, 0.15);
uniform vec3 deep_color : source_color = vec3(0.03, 0.085, 0.09);
// How fast the ripples run downstream in the middle (metres a second).
uniform float speed = 0.9;
// The ripple picture, shared with the lake: red = slope along x, green = slope along z,
// 0.5 = flat. Set by campfire_builder.gd (_build_stream).
uniform sampler2D ripples : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = COLOR.r;
	float steep = COLOR.g;
	// the ripples slide down the stream (towards smaller UV.y): two sizes at two speeds,
	// slower near the banks where the water drags
	float run = TIME * speed * (0.55 + 0.45 * depth) * (1.0 + steep);
	vec2 q = vec2(UV.x, UV.y + run);
	vec2 a = texture(ripples, q * vec2(0.55, 0.3)).rg - 0.5;
	vec2 b = texture(ripples, vec2(UV.x, UV.y + run * 1.7) * vec2(1.3, 0.75) + vec2(0.31, 0.57)).gr - 0.5;
	vec2 slope = (a + b * 0.7) * (0.35 + 0.5 * steep);
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view = normalize(cam - world_pos);
	vec3 r = reflect(-view, n);
	r.y = abs(r.y);
	// what it mirrors: only the sky's colour (the trees over it are too close to fake)
	vec3 mirror = mix(sky_horizon, sky_top, pow(clamp(r.y, 0.0, 1.0), 0.5)) * 0.8;
	float ld = max(dot(r, normalize(light_dir)), 0.0);
	mirror += light_color * pow(ld, 180.0) * 2.0;
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 5.0);
	// foam: soft flecks drawn out a little along the flow (two patterns passing through each
	// other, so they form and break up), mostly where it runs steep, a few in the shallows
	float f1 = texture(ripples, vec2(UV.x * 0.9, (UV.y + run * 1.2) * 0.45)).r;
	float f2 = texture(ripples, vec2(UV.x * 1.4 + 0.5, (UV.y + run * 0.8) * 0.7)).g;
	float foam = smoothstep(0.34, 0.46, f1 * f2 + 0.06 * steep) * (0.08 + 0.55 * steep + 0.12 * (1.0 - depth)) * smoothstep(0.0, 0.25, depth);
	vec3 body = mix(shallow_color, deep_color, depth) * daylight;
	vec3 c = mix(body, mirror, fres);
	c = mix(c, vec3(0.85, 0.9, 0.92) * daylight, clamp(foam, 0.0, 0.7));
	ALBEDO = c;
	// see-through in the shallows, more solid where deep, at a low angle and under foam
	float solid = mix(0.38, 0.82, depth);
	solid = max(solid, fres);
	solid = max(solid, foam);
	ALPHA = solid * smoothstep(0.0, 0.3, depth);
}
