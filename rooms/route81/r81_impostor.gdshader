shader_type spatial;
render_mode cull_disabled;
// Route 81: the far detailed trees as "impostors" (the Detailed look; r81_land.gd card_mesh,
// the "_far" level). A far tree is one flat square that turns round its own up axis to face
// the camera and shows a picture of the real tree taken from that side. The pictures are the
// campfire's (rooms/campfire/textures/impostor_color.png and impostor_normal.png, made by
// rooms/campfire/models/make_trees.py: every species from `frames` sides; the normal sheet
// says which way each pixel's surface faces, and its alpha marks the leaves). Each picture
// covers x from -half_size to +half_size and y from 0 to 2 * half_size in tree units (the
// tree is 1 tall).
// This is the campfire's camp_impostor.gdshader plus what a Route 81 thing needs: the road's
// bend, the valley's depth, the Season choice and the wet look.
//   INSTANCE_CUSTOM.r  the tree's depth into the valley, .g a number of its own 0..1,
//   INSTANCE_CUSTOM.b / .a  the band of distances from `lod_eye` in which it is drawn
//                      (as in r81_foliage.gdshader; the soft change is camp_lod.gdshaderinc)
//   COLOR.a            the species' row in the sheets, as (row + 0.5) / ROW_STEPS
//                      (r81_land.gd tree_batches, IMPOSTOR_ROW_STEPS: keep the two the same)
// Keep frames, rows and half_size equal to make_trees.py IMPOSTOR_FRAMES, len(SPECIES), IMP_HALF
// (r81_land.gd add_materials sets them from campfire_forest.gd).
#include "res://rooms/route81/r81_common.gdshaderinc"
#include "res://rooms/campfire/camp_lod.gdshaderinc"

const float ROW_STEPS = 8.0;

uniform sampler2D color_sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_sheet : filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform float rows = 6.0;
uniform float half_size = 0.6;
uniform float cut = 0.45;
uniform float see_through = 0.35;
// The pictures are flat: they miss the shade a real crown casts on itself (and a trunk gets
// from it). These darken them to match the trees nearer by (1 = as rendered).
uniform float self_shade = 0.8;
uniform float bark_shade = 0.7;
// Per row of the sheets: 1 = a leafy tree (turns colour in fall), 0 = a conifer.
uniform float leafy[6];

varying flat float frame;
varying flat float row;
varying float pick;

void vertex() {
	row = floor(COLOR.a * ROW_STEPS);
	pick = INSTANCE_CUSTOM.g;
	// which way the camera is, seen from the tree (in the tree's own space, flat): the view's
	// "backwards" axis, so every far tree turns the same way and the shadow pass (where the
	// "camera" is the sun) turns them to the sun
	vec3 to_cam = inverse(mat3(MODEL_MATRIX)) * INV_VIEW_MATRIX[2].xyz;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 0.0001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	// frame k was taken from the direction (sin a, 0, cos a), a = k / frames of a turn
	float a = atan(to_cam.x, to_cam.z);
	frame = mod(round(a / TAU * frames) + frames, frames);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec2 c = vec2((UV.x - 0.5) * 2.0 * half_size, (1.0 - UV.y) * 2.0 * half_size);
	vec3 local = right * c.x + vec3(0.0, c.y, 0.0);
	NORMAL = to_cam;
	// into the world, down into the valley and round the road's bend, like the near trees
	vec3 w = (MODEL_MATRIX * vec4(local, 1.0)).xyz;
	w.y -= INSTANCE_CUSTOM.r * alt_drop;
	// (and down with the ground where the drawn land runs out: r81_common r81_tree_taper)
	w.y += r81_tree_taper(MODEL_MATRIX[3].xyz - vec3(0.0, INSTANCE_CUSTOM.r * alt_drop, 0.0));
	w = r22_bend(w);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	lod_keep = lod_vertex(VERTEX, vec4(0.0, INSTANCE_CUSTOM.b, INSTANCE_CUSTOM.a, 0.0), MODEL_MATRIX[3].xyz);
}

void fragment() {
	if (lod_drop(FRAGCOORD.xy, lod_keep)) {
		discard;
	}
	vec2 uv = vec2((frame + UV.x) / frames, (row + UV.y) / rows);
	vec4 c = texture(color_sheet, uv);
	vec4 n = texture(normal_sheet, uv);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = cut;
	vec3 col = c.rgb * self_shade * mix(bark_shade, 1.0, n.a);
	// the leaves (n.a) take each tree's own shade of green and its fall colour, as in
	// r81_foliage.gdshader; the trunk keeps its bark
	int r = int(row + 0.5);
	vec3 leaf = r81_leaf(col * (0.8 + 0.4 * pick), pick, 1.0 - leafy[r]);
	col = mix(col, leaf, n.a);
	col *= 1.0 - 0.25 * wet;
	ALBEDO = col;
	// the picture's surface direction: tree space -> world -> view
	vec3 nt = n.rgb * 2.0 - 1.0;
	vec3 nw = normalize(mat3(MODEL_MATRIX) * nt);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
	BACKLIGHT = col * see_through * n.a;
}
