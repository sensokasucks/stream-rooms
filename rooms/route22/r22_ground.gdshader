shader_type spatial;
render_mode cull_disabled;
// Route 22: the desert floor. One big flat sheet round the room that never moves; in the Cruise
// its texture slides with `travel` (r22_common.gdshaderinc), so the ground seems to rush past
// the car while the sheet itself stays put.
//   cracked red earth (textures/ground_desert.jpg) mixed with drifts of red sand
//   (textures/ground_sand.jpg) by a large slow noise, a gravel shoulder near the road, and in
//   the Drive-In the packed lot (lot_rect).
// Wet weather darkens it and leaves shining puddles in its low spots. r22_desert.gd sets the
// shared uniforms; r22_drivein_builder.gd sets lot_rect.
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform sampler2D tex_desert : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
// The Drive-In's lot: x0, z0, x1, z1 in metres (world). Zero size = no lot (the Cruise).
uniform vec4 lot_rect = vec4(0.0);
// Half the road's width including the gravel shoulder, metres (the shoulder is drawn here).
uniform float shoulder = 5.2;
// Which way the road runs: 0 = along Z (the Cruise), 1 = along X (the Drive-In's Route 22).
uniform float road_along_x = 0.0;
// Where the road's middle line is, across it (metres): x for a road along Z, z for one along X.
uniform float road_at = 0.0;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	// q: the ground's own coordinates, sliding with the drive (all sizes divide 2048 m)
	vec2 q = vec2(w_pos.x, w_pos.z - travel);
	vec3 cracked = texture(tex_desert, q / 8.0).rgb;
	vec3 sand = texture(tex_sand, q / 4.0).rgb;
	float drift = texture(rock_noise, q / 256.0).b;
	float drifts = smoothstep(0.45, 0.62, drift + 0.1 * texture(rock_noise, q / 32.0).a);
	vec3 col = mix(cracked, sand, drifts);
	// a slow wash of tone so the floor isn't one even colour to the horizon
	col *= 0.85 + 0.3 * texture(rock_noise, q / 512.0).b;
	// the gravel shoulder beside the road: paler, speckled
	float across = mix(abs(w_pos.x - road_at), abs(w_pos.z - road_at), road_along_x);
	float gravel = smoothstep(shoulder + 1.5, shoulder - 0.5, across);
	vec3 stones = vec3(0.55, 0.42, 0.33) * (0.75 + 0.5 * texture(rock_noise, q / 2.0).a);
	col = mix(col, stones, gravel);
	// the Drive-In's lot: packed pale gravel with darker tyre-worn rows
	if (lot_rect.z > lot_rect.x) {
		vec2 lo = lot_rect.xy;
		vec2 hi = lot_rect.zw;
		float inside = smoothstep(lo.x - 1.0, lo.x + 1.0, w_pos.x) * smoothstep(hi.x + 1.0, hi.x - 1.0, w_pos.x)
			* smoothstep(lo.y - 1.0, lo.y + 1.0, w_pos.z) * smoothstep(hi.y + 1.0, hi.y - 1.0, w_pos.z);
		vec3 lot = vec3(0.58, 0.45, 0.36) * (0.8 + 0.4 * texture(rock_noise, q / 3.0).a);
		lot *= 0.9 + 0.1 * sin(w_pos.z * 1.1);
		col = mix(col, lot, inside * 0.9);
	}
	if (detail < 0.5) {
		// the low-poly look: the photos' average colour, without their grain
		col = mix(mix(vec3(0.6, 0.36, 0.24), vec3(0.78, 0.5, 0.32), drifts), col, 0.25);
	}
	col *= r22_cloud_shade(w_pos);
	// wet: darker, with puddles shining in the low spots
	float puddle = smoothstep(0.62, 0.7, texture(rock_noise, q / 48.0).b) * wet * (1.0 - drifts * 0.7);
	col *= 1.0 - 0.4 * wet;
	col = mix(col, col * 0.4, puddle);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.04, puddle);
	SPECULAR = 0.3 + 0.4 * puddle;
}
