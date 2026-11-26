// Route 81 (rooms/route81): what its own shaders share, on top of Route 22's
// (r22_common.gdshaderinc: the road's bend and hill, travel, wet, cloud shadows, detail).
//
// The one thing Route 81 adds is the valley. The land beside the road is built at road height;
// every corner of it carries a "depth" (0 at the road, 1 at the valley floor), and the shader
// lowers it by depth * alt_drop. r81_trip.gd eases alt_drop up and down as the road climbs and
// falls, so the same pieces of land are a gentle field at the bottom of the valley and a
// ridge-top overlook an hour later. Trees and the far backdrop follow the same number.
#include "res://rooms/route22/r22_common.gdshaderinc"

// Metres the valley floor lies below the road right now (r81_trip.gd: altitude).
uniform float alt_drop = 0.0;
// 0 = summer greens, 1 = fall colour (the Season choice, r81_season).
uniform float season = 0.0;

// The leaf colour of a tree or a patch of canopy. green = its summer colour, pick = a number
// 0..1 that differs from tree to tree (which fall colour it turns), evergreen = 1 for conifers,
// which stay green.
vec3 r81_leaf(vec3 green, float pick, float evergreen) {
	vec3 fall = mix(vec3(0.62, 0.42, 0.08), vec3(0.58, 0.2, 0.05), smoothstep(0.25, 0.6, pick));
	fall = mix(fall, vec3(0.42, 0.09, 0.06), smoothstep(0.65, 0.9, pick));
	// a few trees turn late and stay green
	float turned = season * (1.0 - evergreen) * step(0.12, pick);
	return mix(green, fall * (0.7 + 0.6 * green.g / 0.3), turned);
}
