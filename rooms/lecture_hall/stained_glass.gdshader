shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Backlit stained glass for the lecture hall's windows (lancets, rose rondels, door fanlights).
// The glass texture is painted with dark lead cames between the pieces. Here the glass gets:
//   - daylight coming through it (emission): from the hour's sky (window_sky.gdshaderinc), so
//     it glows at noon, turns warm at sunset and goes dark blue at night; brightest in windows
//     facing the sun, with clouds drifting across it so the windows slowly breathe,
//   - in the tall lancets, a real view out (glass_mode, the Room tab's "Window glass"): the
//     pale diamond panes (1) or every pane (2) are clear glass showing the sky, its clouds, the
//     sun or moon and the town's roofs, seen through slightly wavy old glass,
//   - a slight wobble when seen at an angle, as hand-rolled glass has,
//   - lead that stays dark, a little metallic and rough, with shiny glass between.
// The room (lecture_hall_room.gd) sets light_level from the house lights; when they go down for
// a video the windows fall to night_glow, as if blinds were drawn. It sets the sky uniforms
// (window_sky.gdshaderinc) from the hour.

#include "res://rooms/lecture_hall/window_sky.gdshaderinc"

uniform sampler2D glass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float light_level = 1.0;
uniform float night_glow = 0.18;
uniform float emission_strength = 2.2;
uniform float sun_boost = 1.4;                   // extra light in windows facing the sun
uniform vec3 sky_tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float ripple = 0.004;                    // glass wobble (UV units)
uniform float cloud_depth = 0.3;                 // how much passing clouds dim the sun
// 0 = all stained glass, 1 = the lancets' pale diamond panes are clear, 2 = every lancet pane
// is clear (the border and lead stay). Only used when is_lancet is on.
uniform int glass_mode = 1;
uniform bool is_lancet = false;
uniform float view_exposure = 1.6;               // how bright the view through clear panes is

varying vec3 w_pos;
varying vec3 w_nrm;

// Soft noise from the sky texture (not a sin() hash: see window_sky.gdshaderinc).
float tex_noise(vec2 p) {
	return texture(sky_noise, p * 0.05).g;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Which part of the lancet picture (blender/make_hall_textures.py lancet()) a UV is on:
// 1 inside the pale diamond-pane background, 0 on the border, the medallions, the trefoil and
// the base blocks. u runs 0..1 across, v 0..2 up in window widths (UV.y is 0 at the top).
float quarry_mask(vec2 uv) {
	float u = uv.x;
	float v = (1.0 - uv.y) * 2.0;
	float hs = 2.0 - sqrt(3.0) / 2.0;            // the arch's spring line
	float b = 0.075 + 0.012;                     // the border's width (plus its lead)
	float side = step(b, u) * step(u, 1.0 - b) * step(b, v);
	float arch = step(length(vec2(u - 1.0, v - hs)), 1.0 - b) * step(length(vec2(u, v - hs)), 1.0 - b);
	float inside = side * max(step(v, hs), arch);
	float base = step(v, 0.215);
	float foil = step(length(vec2(u - 0.5, v - 0.52)), 0.31);
	float med = step(length(vec2(u - 0.5, v - 1.12)), 0.375);
	float tre = step(length(vec2(u - 0.5, v - hs - 0.42)), 0.2);
	return inside * (1.0 - base) * (1.0 - foil) * (1.0 - med) * (1.0 - tre);
}

// The whole lancet inside its border (mode 2 clears everything here).
float inner_mask(vec2 uv) {
	float u = uv.x;
	float v = (1.0 - uv.y) * 2.0;
	float hs = 2.0 - sqrt(3.0) / 2.0;
	float b = 0.087;
	float side = step(b, u) * step(u, 1.0 - b) * step(b, v);
	float arch = step(length(vec2(u - 1.0, v - hs)), 1.0 - b) * step(length(vec2(u, v - hs)), 1.0 - b);
	return side * max(step(v, hs), arch);
}

void fragment() {
	float facing_view = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float grazing = 1.0 - facing_view;
	vec2 wob = vec2(tex_noise(w_pos.xz * 3.1 + w_pos.y * 2.3), tex_noise(w_pos.zy * 2.7 + 7.0)) - 0.5;
	vec2 uv = UV + wob * ripple * (0.4 + grazing * 1.6);
	vec3 g = texture(glass_tex, uv).rgb;
	float lum = dot(g, vec3(0.299, 0.587, 0.114));
	float lead = 1.0 - smoothstep(0.05, 0.12, lum);

	// daylight on this window: the sky's light from where it looks out, the sun when it faces it
	vec3 out_dir = -w_nrm;                       // the window's normal points into the hall
	float sun_face = clamp(dot(w_nrm, -sun_to), 0.0, 1.0) * smoothstep(-0.02, 0.1, sun_to.y);
	vec2 drift = vec2(TIME * 0.035, TIME * 0.013);
	float cloud = 1.0 - cloud_depth * min(cloud_amount, 1.0) * smoothstep(0.35, 0.8, texture(sky_noise, w_pos.xz * 0.004 + w_pos.y * 0.002 + drift * 0.05).r);
	float blinds = mix(night_glow, 1.0, clamp(light_level, 0.0, 1.0));
	float daylight = lh_daylight(out_dir) * (0.6 + 0.4 * cloud);
	float strength = emission_strength * (0.45 * daylight + sun_boost * sun_face * cloud) * blinds;
	// looking straight through a window toward the light is brightest
	float through = mix(0.6, 1.0, sqrt(facing_view));
	// warm at sunset, cold blue at night, as the light outside is
	vec3 light_col = mix(vec3(0.45, 0.55, 0.9), sky_tint, smoothstep(0.0, 0.5, day));
	light_col = mix(light_col, vec3(1.0, 0.7, 0.45), dusk * 0.6);
	vec3 glass = pow(g, vec3(1.1)) * light_col;
	vec3 emit = glass * strength * through;

	// clear panes: the view out, through slightly wavy glass with a faint green tint
	float clear = 0.0;
	if (is_lancet && glass_mode > 0) {
		clear = glass_mode == 1 ? quarry_mask(UV) : inner_mask(UV);
		if (glass_mode == 1) {
			clear *= 1.0 - smoothstep(1.6, 2.2, g.r / max(g.g, 0.02));   // the small red jewels where the leads cross stay
		}
		if (clear > 0.0) {
			vec3 ray = normalize(w_pos - CAMERA_POSITION_WORLD);
			ray = normalize(ray + vec3(wob.x, wob.y * 0.5, -wob.x) * 0.025);
			vec3 view = lh_sky(ray, TIME) * vec3(0.92, 0.97, 0.93) * view_exposure * blinds;
			emit = mix(emit, view, clear);
			// the diamond leads, drawn here as well as in the texture: far away the texture's
			// thin leads blur into the glass (mipmaps), and the clear panes would look empty
			vec2 q = vec2(UV.x + (1.0 - UV.y) * 2.0, UV.x - (1.0 - UV.y) * 2.0) / 0.145;
			vec2 dq = abs(q - round(q));
			vec2 w = fwidth(q) + 0.035;
			float came = max(1.0 - smoothstep(w.x * 0.6, w.x, dq.x), 1.0 - smoothstep(w.y * 0.6, w.y, dq.y));
			lead = max(lead, came * clear);
		}
	}
	ALBEDO = mix(mix(g * 0.2, vec3(0.03), clear), vec3(0.025, 0.022, 0.02), lead);
	EMISSION = emit * (1.0 - lead);
	ROUGHNESS = mix(0.06, 0.55, lead);
	METALLIC = lead * 0.4;
	SPECULAR = 0.65;
}
