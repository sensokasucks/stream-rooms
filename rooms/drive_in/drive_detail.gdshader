shader_type spatial;
// cull_disabled like the imported two-sided materials it replaces (some .glb faces point inwards).
render_mode cull_disabled;
// Drive-In: wood and cloth in the "Detailed" set look (drive_in_room.gd _apply_detail puts it in
// place of the imported Wood_Fence, Truck_Bed_Wood, Blanket and Canvas_Chair materials; the
// "Simple" look keeps the originals). The object keeps its own colour (`base`, copied from the
// material it replaces) and gains a photo's grain: the texture holds the photo divided by its
// own average, 0.5 = no change (the Lakeside Campfire's detail_planks / detail_fabric.jpg, read
// as plain numbers, not as a colour). Laid on by world position from three sides, so the .glb's
// meshes need no UV map. Planks run up the object: the side views use the height as vertical.

uniform vec3 base : source_color = vec3(0.5);
uniform sampler2D grain_tex : filter_linear_mipmap_anisotropic, repeat_enable;
// Metres one copy of the photo covers.
uniform float tile = 1.3;
uniform float roughness = 0.85;

varying vec3 w_pos;
varying vec3 w_normal;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(w_normal);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 g = texture(grain_tex, w_pos.zy / tile).rgb * w.x + texture(grain_tex, w_pos.xz / tile).rgb * w.y
		+ texture(grain_tex, w_pos.xy / tile).rgb * w.z;
	ALBEDO = base * g * 2.0;
	ROUGHNESS = roughness;
}
