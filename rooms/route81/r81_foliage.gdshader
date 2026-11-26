shader_type spatial;
render_mode cull_disabled;
// Route 81: the leaves and needles of the detailed trees beside the highway (the Detailed
// look; r81_land.gd card_mesh: the campfire's Blender trees, rooms/campfire/models/trees.glb).
// A tree's leaves are flat "cards", each showing a see-through photo of a bough or a spray
// of leaves (rooms/campfire/textures/card_*.png, CC0). Pixels below `cut` in the photo's
// alpha are not drawn at all, so thousands of cards stay cheap and need no sorting.
// This is the campfire's camp_foliage.gdshader plus what a Route 81 thing needs: the road's
// bend, the valley's depth and the Season choice.
//   COLOR.rgb  the card's own shade (darker inside the crown); 1 = as photographed
//   COLOR.a    how far the wind moves this corner (0 at the trunk, 1 at the tips and the top)
// Each tree (MultiMesh instance) carries INSTANCE_CUSTOM like the low-poly trees
// (r81_tree.gdshader): r = its ground's depth, g = a number of its own 0..1; and b = from,
// a = to: the band of distances from the camera (metres from `lod_eye`, which r81_trip.gd
// keeps on the camera) in which this level of detail of the tree is drawn (r81_land.gd
// CARD_BANDS). Round a band's edges two levels share the tree and dissolve into each other:
// the campfire's camp_lod.gdshaderinc, used as it is (it wants the band in .g and .b).
#include "res://rooms/route81/r81_common.gdshaderinc"
#include "res://rooms/campfire/camp_lod.gdshaderinc"

uniform sampler2D card : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float cut = 0.33;
// Laid over every card of this material (the species' colour).
uniform vec3 tint : source_color = vec3(1.0);
// 1 = a conifer: stays green in fall.
uniform float evergreen = 0.0;
// How hard the wind blows (r22_desert.gd: 0.4 calm .. 2.6 gale).
uniform float wind = 1.0;

varying float pick;

void vertex() {
	pick = INSTANCE_CUSTOM.g;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w.y -= INSTANCE_CUSTOM.r * alt_drop;
	// a slow lean of the whole tree (the same as its trunk, r81_bark.gdshader) and a quick
	// flutter of each card
	float lean = sin(TIME * 0.9 + w.x * 0.11 + w.z * 0.13) + 0.4 * sin(TIME * 2.7 + w.x * 0.6);
	float flutter = sin(TIME * 3.1 + w.x * 2.3 + w.y * 1.7 + w.z * 2.9);
	w += (vec3(0.8, 0.0, 0.45) * lean * 0.12 + vec3(0.2, 0.35, 0.3) * flutter * 0.04) * wind * COLOR.a * COLOR.a;
	w = r22_bend(w);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	lod_keep = lod_vertex(VERTEX, vec4(0.0, INSTANCE_CUSTOM.b, INSTANCE_CUSTOM.a, 0.0), MODEL_MATRIX[3].xyz);
}

void fragment() {
	if (lod_drop(FRAGCOORD.xy, lod_keep)) {
		discard;
	}
	vec4 t = texture(card, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = cut;
	// each tree its own shade of green, then its fall colour when the season says so
	vec3 green = t.rgb * tint * (0.8 + 0.4 * pick);
	vec3 col = r81_leaf(green, pick, evergreen) * COLOR.rgb;
	col *= 1.0 - 0.25 * wet;
	ALBEDO = col;
	ROUGHNESS = 0.7;
	SPECULAR = 0.2;
	// leaves let light through: a tree seen against the sun glows instead of going black
	BACKLIGHT = col * 0.5;
	// The cards' normals point out of the crown, the same on both faces: undo the flip the
	// renderer gives a back face, or the far side of every tree would be lit inside out.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
