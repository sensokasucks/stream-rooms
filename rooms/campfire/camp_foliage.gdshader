shader_type spatial;
render_mode cull_disabled;
// Lakeside Campfire: the leaves and needles of the detailed trees, the grass tufts and the
// ferns (campfire_trees.gd builds them out of flat cards). Each card shows a see-through
// picture of a bough, a spray of leaves, a tuft or a frond (textures/card_*.png, put together
// from CC0 photos by textures/make_textures.py). Pixels below `cut` in the picture's alpha are
// not drawn at all (no blending, so thousands of cards stay cheap and sort themselves).
//   COLOR.rgb  a tint: the card's own shade (darker inside the crown) times the tree's
//              (a MultiMesh instance colour); 1 = as photographed
//   COLOR.a    how far the wind moves this corner (0 at the trunk, 1 at the tips and the top)
// `wind` and `sway` work as in camp_prop.gdshader.

uniform sampler2D card : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float cut = 0.33;
// Laid over every card of this material (the species' colour).
uniform vec3 tint : source_color = vec3(1.0);
uniform float sway = 0.02;
uniform float wind = 1.0;
// Autumn (campfire_room.gd _apply_autumn, the "camp_autumn" setting): 0 = summer green,
// 1 = every tree of this material turns a colour of its own between fall_a and fall_b
// (birches yellow, maples red to orange, oaks russet). The firs' materials leave it at 0.
uniform float autumn = 0.0;
uniform vec3 fall_a : source_color = vec3(0.9, 0.6, 0.1);
uniform vec3 fall_b : source_color = vec3(0.85, 0.3, 0.08);
// How much light comes through a leaf from behind (0 = none).
uniform float see_through = 0.35;

varying float tree_pick;       // 0..1, fixed for each tree (its number in the MultiMesh)

void vertex() {
	tree_pick = fract(float(INSTANCE_ID) * 0.61803);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// the same slow lean as the trunks (camp_prop.gdshader), plus a quick flutter of each card
	float lean = sin(TIME * 0.7 + w.x * 0.13 + w.z * 0.09) + 0.4 * sin(TIME * 1.9 + w.x * 0.7 + w.z * 0.5);
	float flutter = sin(TIME * 3.1 + w.x * 2.3 + w.y * 1.7 + w.z * 2.9);
	vec3 push = (vec3(1.0, 0.0, 0.35) * lean + vec3(0.2, 0.35, 0.3) * flutter * 0.25) * sway * wind * COLOR.a * COLOR.a;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
}

void fragment() {
	vec4 t = texture(card, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = cut;
	ALBEDO = t.rgb * COLOR.rgb * tint;
	if (autumn > 0.0) {
		// the leaf photo's light and dark, in the tree's autumn colour instead of its green
		float light = dot(t.rgb, vec3(0.3, 0.6, 0.1)) * 2.6;
		ALBEDO = mix(ALBEDO, mix(fall_a, fall_b, tree_pick) * light * COLOR.rgb, autumn);
	}
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
	BACKLIGHT = ALBEDO * see_through;
	// The cards' normals point out of the crown, the same on both faces: undo the flip the
	// renderer gives a back face, or the far side of every tree would be lit inside out.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
