shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Forge Hall: the hall's stone with close-up photo detail (the "Detailed" stone look).
// rooms/forge_hall/forge_hall_room.gd (_build_stone_detail, _apply_stone_detail) puts one of
// these in place of each imported stone material (Stone_Slab, Pillar_Marble, Forge_Granite) while
// Room tab > Forge Hall > Stone detail is Detailed, and copies the imported material's own
// picture, colour, roughness and metallic into the base_* uniforms, so from a distance the stone
// looks exactly as before. Close to the camera a CC0 rock photo (textures/stone_*_grain.jpg and
// stone_*_normal.jpg, made by textures/make_stone_detail.py) is laid over it:
//   - the grain picture darkens the pits and cracks and brightens the crystals (128 grey = no
//     change, so the stone's own colour stays),
//   - the normal picture bends the light, so lamps and the fire catch the surface's relief,
//   - pits are a little rougher (less shiny) than the polished face.
// The photos are laid on by world position from three sides (triplanar), so they need no UVs
// and never stretch, and they fade out between fade_start and fade_end metres from the camera,
// which also hides that they repeat.
// Cost: six extra texture reads per stone pixel; Simple puts the imported materials back.

// ── the imported material's own look (copied by forge_hall_room.gd) ──
uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.2;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float base_specular : hint_range(0.0, 1.0) = 0.5;
// the imported material's uv1_scale / uv1_offset (the model's UVs: one picture per 6 m)
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);

// ── the close-up photo detail ──
// grey grain, 0.5 = no change (read as plain numbers, not as a colour)
uniform sampler2D grain_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// how many metres one copy of the photo covers
uniform float tile_metres = 1.6;
// 0 = no grain, 1 = the photo's full grain
uniform float grain_strength : hint_range(0.0, 2.0) = 1.0;
// 0 = flat, 1 = the photo's full relief
uniform float bump_strength : hint_range(0.0, 2.0) = 0.6;
// how much rougher the darkest pits are than the polished face
uniform float rough_vary : hint_range(0.0, 1.0) = 0.25;
// metres from the camera where the detail starts to fade, and where it is gone
uniform float fade_start = 7.0;
uniform float fade_end = 24.0;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 base = texture(base_tex, UV * uv_scale.xy + uv_offset.xy) * base_color;
	float near = 1.0 - smoothstep(fade_start, fade_end, length(w_pos - CAMERA_POSITION_WORLD));
	float rough = base_roughness;
	vec3 albedo = base.rgb;
	if (near > 0.001) {
		// which of the three sides each pixel takes its photo from: mostly the one the
		// surface faces, blended where it is at an angle
		vec3 w = pow(abs(w_nrm), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec2 uv_x = w_pos.zy / tile_metres;
		vec2 uv_y = w_pos.xz / tile_metres;
		vec2 uv_z = w_pos.xy / tile_metres;
		float g = texture(grain_tex, uv_x).r * w.x + texture(grain_tex, uv_y).r * w.y + texture(grain_tex, uv_z).r * w.z;
		g *= 2.0;                                   // 0.5 stored = 1.0, no change
		albedo *= mix(1.0, g, grain_strength * near);
		rough = clamp(rough + (1.0 - min(g, 1.0)) * rough_vary * near, 0.0, 1.0);
		// relief: each side's normal picture, turned to that side and added onto the
		// surface's own normal ("UDN" triplanar blend), then handed over in view space
		float k = bump_strength * near;
		vec2 tx = (texture(normal_tex, uv_x).xy * 2.0 - 1.0) * k;
		vec2 ty = (texture(normal_tex, uv_y).xy * 2.0 - 1.0) * k;
		vec2 tz = (texture(normal_tex, uv_z).xy * 2.0 - 1.0) * k;
		// (side x reads the picture across z and y, side y across x and z, side z across x and y)
		vec3 n = normalize(w_nrm
			+ vec3(0.0, tx.y, tx.x) * w.x
			+ vec3(ty.x, 0.0, ty.y) * w.y
			+ vec3(tz.x, tz.y, 0.0) * w.z);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = base_metallic;
	SPECULAR = base_specular;
}
