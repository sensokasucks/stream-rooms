shader_type spatial;
// Route 81: the trunks and limbs of the detailed trees (the Detailed look; r81_land.gd
// card_mesh: the campfire's Blender trees). A bark photo is laid on from three sides, so
// the limbs need no UV mapping (the campfire's bark photos, CC0).
//   COLOR.rgb  the bark's colour, COLOR.a how far the wind moves this corner
//   UV.x       which bark: 1 = pine and fir, 5 = oak and maple, 6 = birch
//              (campfire_trees.gd MAT_BARK...)
// INSTANCE_CUSTOM.r = the tree's depth into the valley, as in r81_foliage.gdshader, and the
// lean in vertex() must stay the same as there or the leaves leave their limbs.
// INSTANCE_CUSTOM.b / .a = the band of distances from `lod_eye` (the camera) in which this
// level of detail is drawn, as in r81_foliage.gdshader. Trunks switch at the band's edge
// without the leaves' soft change: they are thin, and two trunks drawn at once would flicker
// (the same choice as the campfire's camp_prop.gdshader).
#include "res://rooms/route81/r81_common.gdshaderinc"

// The camera's place (r81_trip.gd writes it to every material in kit["r81_lod"]).
uniform vec3 lod_eye = vec3(0.0);

uniform sampler2D tex_bark : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_bark_oak : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_bark_birch : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind = 1.0;

varying float bark;
varying vec3 at;       // this point on the tree, in metres from its foot
varying vec3 out_dir;  // which way the bark faces, in the tree's own directions

// A photo laid on from three sides, mixed by which way the surface faces. The photos hold the
// bark divided by its average colour times 0.5, so 0.5 = the corner colour unchanged.
vec3 three_sides(sampler2D tex, vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy / tile).rgb * w.x + texture(tex, p.xz / tile).rgb * w.y + texture(tex, p.xy / tile).rgb * w.z;
}

void vertex() {
	bark = UV.x;
	// (the tree mesh is 1 unit tall; its instance scale is its height in metres)
	at = VERTEX * length(MODEL_MATRIX[1].xyz);
	out_dir = NORMAL;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w.y -= INSTANCE_CUSTOM.r * alt_drop;
	float lean = sin(TIME * 0.9 + w.x * 0.11 + w.z * 0.13) + 0.4 * sin(TIME * 2.7 + w.x * 0.6);
	w += vec3(0.8, 0.0, 0.45) * lean * 0.12 * wind * COLOR.a * COLOR.a;
	w = r22_bend(w);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	if (INSTANCE_CUSTOM.a > 0.0) {
		float d = distance(MODEL_MATRIX[3].xyz, lod_eye);
		if (d < INSTANCE_CUSTOM.b || d >= INSTANCE_CUSTOM.a) {
			VERTEX = vec3(0.0);        // outside the band: folded to a point, nothing drawn
		}
	}
}

void fragment() {
	vec3 n = normalize(out_dir);
	vec3 grain;
	if (bark < 1.5) {
		grain = three_sides(tex_bark, at, n, 0.9);
	} else if (bark < 5.5) {
		grain = three_sides(tex_bark_oak, at, n, 1.6);
	} else {
		grain = three_sides(tex_bark_birch, at, n, 1.1);
	}
	// (kept darker than the photo: trunks stand in their own crowns' shade)
	ALBEDO = COLOR.rgb * grain * 1.15 * (1.0 - 0.3 * wet);
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
