shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Forge Hall: heat haze and a little smoke over the forge (the "Detailed" look only).
// rooms/forge_hall/forge_hall_room.gd (_build_haze, _apply_fire) stands a few upright sheets in
// front of and above the firebox and sets `amount` from the Fire slider (0 = fire out = hidden).
// Each sheet:
//   - wobbles what is behind it (the room picture read back from the screen), as hot air
//     shimmers: two noise patterns drift up through each other and push the picture sideways a
//     little. Strongest low down near the flames, gone at the top.
//   - shows thin, warm grey smoke drifting up, from the same noise picture as the sky's clouds
//     (textures/sky_noise.png, made by rooms/campfire/textures/make_textures.py, sky_noise()).
// It fades at the sheet's edges and when the sheet is seen edge-on, so it never shows a line.
// Everything moves at one speed everywhere (TIME is never multiplied by something that
// changes across the sheet, which would smear it more the longer the app runs).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
// 0 = nothing, 1 = Fire 100%, 2 = roaring
uniform float amount : hint_range(0.0, 2.0) = 1.0;
// how far the shimmer pushes the picture, as a share of the screen's width at amount 1
uniform float shimmer = 0.006;
// 0 = no smoke, 1 = the room's look
uniform float smoke = 1.0;
uniform vec3 smoke_color : source_color = vec3(0.42, 0.36, 0.32);
// moves each sheet's pattern so neighbouring sheets do not match
uniform float seed = 0.0;

varying vec3 w_nrm;
varying vec3 w_pos;

void vertex() {
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = 1.0 - UV.y;                                    // 0 at the sheet's foot, 1 at its top
	// soft edges all round; the haze is strongest in the lower third
	float edge = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x) * smoothstep(0.0, 0.12, h) * smoothstep(1.0, 0.55, h);
	// seen edge-on a sheet would show as a line: fade it out
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - w_pos);
	float facing = smoothstep(0.15, 0.6, abs(dot(to_cam, w_nrm)));
	float k = clamp(amount, 0.0, 2.0) * edge * facing;
	// two patterns rising through each other (hot air moves up fast)
	vec2 p1 = vec2(UV.x * 0.55 + seed, h * 0.9 - TIME * 0.22);
	vec2 p2 = vec2(UV.x * 1.3 - seed * 0.7, h * 2.1 - TIME * 0.37);
	vec2 wob = vec2(texture(noise, p1).g, texture(noise, p2).g) - 0.5;
	float heat = (1.0 - smoothstep(0.1, 0.8, h));            // most shimmer just over the flames
	vec2 push = wob * shimmer * k * (0.4 + heat);
	vec3 behind = textureLod(screen_tex, SCREEN_UV + push, 0.0).rgb;
	// thin smoke: slow, soft patches that thicken a little as they rise
	float s = texture(noise, vec2(UV.x * 0.4 + seed * 1.3, h * 0.5 - TIME * 0.06)).r;
	s = smoothstep(0.5, 0.85, s) * smoothstep(0.1, 0.6, h) * smoke;
	ALBEDO = mix(behind, smoke_color, s * 0.35);
	ALPHA = clamp(k, 0.0, 1.0);
}
