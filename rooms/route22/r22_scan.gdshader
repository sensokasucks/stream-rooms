shader_type spatial;
// Route 22: the photo-scanned props (barrels, a dead quiver-tree trunk, dry branches) from CC0
// Poly Haven scans, cut down by models/make_models.py. Each model has its own material from
// r22_geo.gd scan_prop(), with its three photo maps:
//   tex_albedo   the colour (prop_<name>_diff.jpg)
//   tex_normal   the bumps (prop_<name>_nor.jpg, OpenGL style); only on the Detailed look
//   tex_arm      r = ambient occlusion, g = roughness, b = metal (prop_<name>_arm.jpg)
// Like every Route 22 material it bends with the road, lies under the cloud shadows and darkens
// / shines in the wet (r22_common.gdshaderinc; r22_desert.gd writes those uniforms each frame).
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_arm : filter_linear_mipmap_anisotropic, repeat_enable;
// A colour the photo is multiplied by (r22_geo.gd scan_prop's tint, 1 = as photographed).
uniform vec3 tint = vec3(1.0);
// The rest of the shared set (r22_geo.gd _note gives every material these two textures; this
// shader does not use rock_noise, but declares it so the shared setter has somewhere to write).
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	vec3 col = texture(tex_albedo, UV).rgb * tint;
	vec3 arm = texture(tex_arm, UV).rgb;
	float rough = arm.g;
	if (detail > 0.5) {
		NORMAL_MAP = texture(tex_normal, UV).rgb;
		AO = arm.r;
		AO_LIGHT_AFFECT = 0.4;
	}
	col *= r22_cloud_shade(w_pos);
	// the wet: darker, and the faces turned up shine (the same as r22_prop.gdshader)
	float up = smoothstep(0.3, 0.9, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	col *= 1.0 - 0.3 * wet;
	rough = mix(rough, min(rough, 0.25), wet * up);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = arm.b;
}
