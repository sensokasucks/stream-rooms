// Lakeside Campfire: the soft change between the detailed trees' levels of detail
// (campfire_forest.gd), shared by camp_foliage.gdshader (the leaf and needle cards) and
// camp_impostor.gdshader (the far pictures). camp_prop.gdshader (the trunks) keeps a plain
// switch at the band's edge: trunks are thin, and two trunks drawn at once would flicker.
//
// Each tree carries its level's band in its MultiMesh custom data (INSTANCE_CUSTOM.g = from,
// .b = to, metres from `lod_eye`, the camera; .b = 0 = no band, always drawn). Round each edge
// of a band both levels are drawn over `lod_fade` metres, and each keeps the other's missing
// pixels of a fine screen pattern: the nearer level keeps the pixels whose pattern value is
// below its share, the farther one the rest, so a tree crossing the edge dissolves from one
// level into the other with no hole and no doubled leaves. (Sen, round 2: the change was sudden.)
//
// Use (Redot only lets vertex() and fragment() themselves write varyings and discard):
//   vertex():   lod_keep = lod_vertex(VERTEX, INSTANCE_CUSTOM, MODEL_MATRIX[3].xyz);   (at the end)
//   fragment(): if (lod_drop(FRAGCOORD.xy, lod_keep)) { discard; }                     (at the start)

uniform vec3 lod_eye = vec3(0.0);
// Metres over which two levels share a tree (campfire_forest.gd LOD_FADE sets it).
uniform float lod_fade = 8.0;

// The pattern values this level draws: from lod_keep.x up to lod_keep.y (0..1).
varying vec2 lod_keep;

vec2 lod_vertex(inout vec3 vtx, vec4 custom, vec3 origin) {
	vec2 keep = vec2(0.0, 1.0);
	if (custom.b <= 0.0) {
		return keep;
	}
	float d = distance(origin, lod_eye);
	float h = lod_fade * 0.5;
	if (d < custom.g - h || d >= custom.b + h) {
		vtx = vec3(0.0);           // outside the band: folded to a point, nothing drawn
		return keep;
	}
	// near edge: none of it at custom.g - h, all of it at custom.g + h (the first band has no near edge)
	if (custom.g > 0.0) {
		keep.x = clamp((custom.g + h - d) / lod_fade, 0.0, 1.0);
	}
	// far edge: all of it at custom.b - h, none at custom.b + h; the same share the next level
	// takes as its keep.x, so the two add up to one whole tree
	keep.y = clamp((custom.b + h - d) / lod_fade, 0.0, 1.0);
	return keep;
}

bool lod_drop(vec2 frag, vec2 keep) {
	if (keep.x <= 0.0 && keep.y >= 1.0) {
		return false;
	}
	// interleaved gradient noise: an even, fine pattern of values 0..1 across the screen
	float n = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	return n < keep.x || n >= keep.y;
}
