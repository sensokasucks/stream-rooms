shader_type spatial;
render_mode cull_disabled;
// Route 81: the low-poly trees along the highway, drawn in batches (one MultiMesh per kind of
// tree per piece of land, r81_land.gd). Each corner of the tree mesh carries
//   COLOR.rgb  its colour (summer),
//   COLOR.a    how much it sways (0 at the trunk's foot, 1 at the crown's top),
//   UV.x       0 = trunk, 1 = leaves that turn in fall, 2 = needles (green all year).
// The power line's pylons and wires are drawn with this too (r81_pieces.gd power_line): they
// are "trunk" (UV.x 0) with no sway (COLOR.a 0), and as they are not instances their depth is
// in UV.y instead.
// Each tree (instance) carries INSTANCE_CUSTOM: r = its depth (how far it sinks into the
// valley, like the land it stands on, see r81_common.gdshaderinc), g = a number of its own
// 0..1 (its shade of green and its fall colour).
#include "res://rooms/route81/r81_common.gdshaderinc"

// How hard the wind blows (r22_desert.gd: 0.4 calm .. 2.6 gale).
uniform float wind = 1.0;

varying float kind;
varying float pick;

void vertex() {
	kind = UV.x;
	pick = INSTANCE_CUSTOM.g;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w.y -= (INSTANCE_CUSTOM.r + UV.y) * alt_drop;
	float lean = sin(TIME * 0.9 + w.x * 0.11 + w.z * 0.13) + 0.4 * sin(TIME * 2.7 + w.x * 0.6);
	w += vec3(0.8, 0.0, 0.45) * lean * 0.12 * wind * COLOR.a * COLOR.a;
	w = r22_bend(w);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (kind > 0.5) {
		col *= 0.75 + 0.5 * pick;
		col = r81_leaf(col, pick, step(1.5, kind));
	}
	col *= 1.0 - 0.25 * wet;
	ALBEDO = col;
	// leaves let light through: a tree seen against the sun glows instead of going black
	BACKLIGHT = col * 0.7 * step(0.5, kind);
	ROUGHNESS = 0.9;
	SPECULAR = 0.05;
}
