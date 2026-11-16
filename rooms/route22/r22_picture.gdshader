shader_type spatial;
render_mode cull_back;
// Route 22: the picture on a billboard (r22_billboards.gd). A plain rectangle with UVs, its own
// material per board so each shows its own picture.
//   picture   the picture from the Billboard pictures set, or a made-up roadside ad
//             (textures/ad_*.png) when the set is empty and Filler ads is on,
//   crop      which part of the picture fills the board (x, y offset, w, h of the UV), so a
//             picture of another shape is cut to fill the board rather than squashed
//             (r22_billboards.gd _fit),
//   lit       the lamps on the board at night (the "Lit at night" tick box): 0 = off,
//   faded     sun-bleached and peeling, for the old wooden sign (0 = fresh).
// The picture also catches the day's light like paint would, bends with the road and darkens
// in the wet (r22_common.gdshaderinc).
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 crop = vec4(0.0, 0.0, 1.0, 1.0);
uniform float lit = 0.0;
uniform float faded = 0.0;
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec2 uv = crop.xy + UV * crop.zw;
	vec3 col = texture(picture, uv).rgb;
	if (faded > 0.0) {
		float peel = smoothstep(0.62, 0.7, texture(rock_noise, UV * vec2(3.0, 1.5)).b) * faded;
		col = mix(col, vec3(dot(col, vec3(0.33))) * 0.9 + 0.1, faded * 0.45);
		col = mix(col, vec3(0.5, 0.42, 0.32), peel);
	}
	col *= r22_cloud_shade(w_pos);
	col *= 1.0 - 0.15 * wet;
	// the lamps light the board from below: brightest at the bottom edge
	float lamp = lit * (0.55 + 0.45 * (1.0 - UV.y));
	ALBEDO = col * 0.92;
	EMISSION = col * lamp * 0.9;
	ROUGHNESS = mix(0.7, 0.35, wet);
}
