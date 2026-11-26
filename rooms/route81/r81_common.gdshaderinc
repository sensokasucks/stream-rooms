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

// Where the drawn land ends. r81_trip.gd only dresses the places from BEHIND (640 m) behind the
// car to AHEAD (960 m) ahead of it. A side that falls to the valley ends out of sight, but a
// climbing side (the mountainside, the hill over a tunnel) is up to 250 m tall, and where its
// last place ended it stood cut off like a wall (Sen's PC screenshots, round 5: a flat pale
// face in the distance from the side cameras). So over the last stretch before either end the
// high ground is lowered toward the road's level: the mountain runs down into the distance
// and rises again as the car comes nearer, far off in the haze.
// wz = the spot's world Z before the road's bend (the car is at 0, ahead is negative).
// The numbers must stay inside r81_trip.gd BEHIND / AHEAD.
float r81_far_taper(float wz) {
	return (1.0 - smoothstep(600.0, 940.0, -wz)) * (1.0 - smoothstep(360.0, 620.0, wz));
}

// A height y (metres above the road) with that lowering. The first TAPER_KEEP metres stay as
// they are, so rock cuts' feet, tunnel mouths and everything standing beside the road keep
// their place; only what is above shrinks.
const float TAPER_KEEP = 14.0;
float r81_taper_y(float y, float wz) {
	return y <= TAPER_KEEP ? y : TAPER_KEEP + (y - TAPER_KEEP) * r81_far_taper(wz);
}

// How far a tree standing at world position `base` (its foot, already sunk into the valley)
// moves down with the ground under it: add this to every corner's height.
float r81_tree_taper(vec3 base) {
	return r81_taper_y(base.y, base.z) - base.y;
}

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
