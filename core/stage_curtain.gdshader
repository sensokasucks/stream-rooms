shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// One panel of the stage curtain (StageCurtain builds two). The mesh is a flat grid; UV.x runs
// from the outer edge (0) to the inner edge (1), UV.y from the hem (0) to the track (1).
// The shader lays it out: velvet folds, gathering to the side as it opens (the hem trails a
// little behind the top), a slow sway at rest and a ripple while it moves.

uniform float open_amount = 0.0;     // 0 closed .. 1 open (a little over 1 while overshooting)
uniform float half_width = 4.0;      // metres: the panel's closed width
uniform float height = 5.0;
uniform float side = 1.0;            // +1 right panel, -1 left panel (as seen from the audience)
uniform float gather = 0.14;         // share of the closed width left when fully open
uniform float overlap = 0.08;        // metres the inner edges cross the middle when closed
uniform float folds = 14.0;
uniform float fold_depth = 0.07;
uniform float hem_lag = 0.35;        // how far the hem trails the top while it moves
uniform float motion = 0.0;          // 0..1, how fast it's moving right now (ripples)
uniform vec3 velvet : source_color = vec3(0.5, 0.02, 0.05);
uniform vec3 trim : source_color = vec3(0.85, 0.66, 0.25);

varying float v_shade;
varying float v_open;

float panel_open(float v) {
	float o = clamp(open_amount * (1.0 + hem_lag) - hem_lag * (1.0 - v), 0.0, 1.08);
	return o * o * (3.0 - 2.0 * min(o, 1.0));
}

void vertex() {
	float s = UV.x;
	float v = UV.y;
	float o = panel_open(v);
	float g = mix(1.0, gather, o);
	float x = side * (half_width - s * (half_width + overlap) * g);
	float phase = s * folds * 6.2831853;
	// gathered cloth bunches into deeper folds; the free inner edge flattens out a little
	float amp = fold_depth * mix(1.0, 2.3, o) * (1.0 - 0.35 * smoothstep(0.85, 1.0, s));
	float z = amp * sin(phase);
	// hem sways slowly at rest; ripples while moving
	float loose = (1.0 - v) * (1.0 - v);
	z += loose * (0.015 * sin(TIME * 1.1 + s * 5.0) + motion * 0.09 * sin(TIME * 7.0 + s * 11.0 - v * 4.0));
	x += side * loose * motion * 0.05 * sin(TIME * 5.0 + v * 3.0);
	// a small swing in towards the middle at the hem while it closes (heavier cloth)
	VERTEX = vec3(x, v * height, z);
	float dzds = amp * cos(phase) * folds * 6.2831853;
	float dxds = -side * (half_width + overlap) * g;
	float slope = dzds / (abs(dxds) > 0.0001 ? dxds : 0.0001);
	NORMAL = normalize(vec3(-slope, 0.0, 1.0));
	v_shade = 0.5 + 0.5 * sin(phase);
	v_open = o;
}

void fragment() {
	// darker in the troughs of the folds, a fine vertical pile in the velvet
	float pile = 0.9 + 0.1 * sin(UV.x * folds * 6.2831853 * 9.0 + UV.y * 3.0);
	vec3 col = velvet * mix(0.45, 1.05, v_shade) * pile;
	float hem = 1.0 - step(0.025, UV.y);
	ALBEDO = mix(col, trim, hem);
	METALLIC = hem * 0.8;
	ROUGHNESS = mix(0.82, 0.35, hem);
	SPECULAR = 0.25;
	RIM = 0.65 * (1.0 - hem);        // velvet sheen at grazing angles
	RIM_TINT = 0.55;
	EMISSION = velvet * 0.06 * v_shade;   // never quite black, even in a dark room
}
