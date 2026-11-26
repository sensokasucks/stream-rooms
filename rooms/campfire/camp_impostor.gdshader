shader_type spatial;
render_mode cull_disabled;
// Lakeside Campfire: the far detailed trees as "impostors" (campfire_forest.gd). A far tree is
// one flat square (two triangles) that turns round its own up axis to face the camera and
// shows a picture of the real tree taken from that side: models/make_trees.py rendered every
// species from IMPOSTOR_FRAMES sides into textures/impostor_color.png (colour, unlit) and
// textures/impostor_normal.png (which way each pixel's surface faces, so the sun and the
// fire light it like a real tree; its alpha marks the leaves). Each picture covers x from
// -half_size to +half_size and y from 0 to 2 * half_size in tree units (the tree is 1 tall).
//   INSTANCE_CUSTOM.r  the species' row in the sheets (campfire_forest.gd SPECIES order)
//   INSTANCE_CUSTOM.gb the level's band (metres from lod_eye), as in camp_prop.gdshader
//   COLOR.rgb          the tree's tint (its MultiMesh instance colour), as on the near trees
// The far trees' band starts where the light level's ends; round that edge the two share each
// tree for a few metres (camp_lod.gdshaderinc), so a tree dissolves from one into the other.
// Autumn: as in camp_foliage.gdshader, but per row (leafy[] says which rows turn colour,
// fall_a[] / fall_b[] their range); campfire_room.gd _apply_autumn sets them.
// Keep frames, rows and half_size equal to make_trees.py IMPOSTOR_FRAMES, len(SPECIES), IMP_HALF.

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
uniform float autumn = 0.0;
uniform float leafy[6];
uniform vec3 fall_a[6];
uniform vec3 fall_b[6];

#include "res://rooms/campfire/camp_lod.gdshaderinc"

varying flat float frame;
varying flat float row;
varying float tree_pick;

void vertex() {
	row = INSTANCE_CUSTOM.r;
	tree_pick = fract(float(INSTANCE_ID) * 0.61803);
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
	VERTEX = right * c.x + vec3(0.0, c.y, 0.0);
	NORMAL = to_cam;
	lod_keep = lod_vertex(VERTEX, INSTANCE_CUSTOM, MODEL_MATRIX[3].xyz);
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
	ALBEDO = c.rgb * COLOR.rgb * self_shade * mix(bark_shade, 1.0, n.a);
	int r = int(row + 0.5);
	if (autumn > 0.0 && leafy[r] > 0.5) {
		float light = dot(c.rgb, vec3(0.3, 0.6, 0.1)) * 2.6;
		vec3 fall = mix(fall_a[r], fall_b[r], tree_pick) * light * COLOR.rgb;
		ALBEDO = mix(ALBEDO, fall, autumn * n.a);
	}
	// the picture's surface direction: tree space -> world -> view
	vec3 nt = n.rgb * 2.0 - 1.0;
	vec3 nw = normalize(mat3(MODEL_MATRIX) * nt);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
	BACKLIGHT = ALBEDO * see_through * n.a;
}
