shader_type spatial;
// cull_disabled: the .glb's parking ramps face down (their imported material is two-sided), so
// with back faces culled they vanished (the renderer turns a back face's normal round itself).
render_mode cull_disabled;
// Drive-In: the ground in the "Detailed" set look (drive_in_room.gd _apply_detail puts it on
// the imported Grass, Asphalt and Gravel_Ramp materials; the "Simple" look keeps the original
// flat colours). One photo is laid over the ground by world position (the .glb's ground has no
// UV map), read at two sizes and mixed so its repeat doesn't show, and darkened and lightened
// in big soft patches from a noise picture so no stretch of ground is flat.
// The grass material also turns into forest floor (fallen leaves and needles) under the belt of
// trees round the lot: `forest_from` metres outside the fence it starts, fully so 12 m further.
// Noise comes from a picture (the campfire's textures/sky_noise.png), never from a sin() hash:
// those break up into blocks far from the middle of the world on a real graphics card.

uniform sampler2D photo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// The forest floor photo (grass material only; see use_forest).
uniform sampler2D forest : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Seamless noise: r = big soft blobs, g = finer crumbs (rooms/campfire/textures/sky_noise.png).
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
// Metres one copy of the photo covers.
uniform float tile_size = 4.0;
// Laid over the photo so it sits with the rest of the set (1 = as photographed).
uniform vec3 tint : source_color = vec3(1.0);
// How much the big patches darken / lighten the ground (0 = none).
uniform float patchiness = 0.3;
uniform float roughness = 0.9;
// 1 = this is the grass: mix in the forest floor under the trees round the lot.
uniform float use_forest = 0.0;
// The fence round the lot in world metres: x min, z min, x max, z max (from the .glb's Fence).
uniform vec4 fence_rect = vec4(-70.0, -76.0, 70.0, 48.0);
// Metres outside the fence where the forest floor starts.
uniform float forest_from = 4.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv = p / tile_size;
	float blobs = texture(noise, p * 0.006).r;
	float crumbs = texture(noise, p * 0.05 + vec2(0.3, 0.7)).g;
	// a second, bigger copy of the photo mixed in hides the repeat of the first
	vec3 c = mix(texture(photo, uv).rgb, texture(photo, uv * 0.31 + vec2(0.17, 0.41)).rgb, 0.4);
	if (use_forest > 0.5) {
		// how far outside the fence this point is (0 inside it), with a ragged edge
		vec2 outside = max(max(fence_rect.xy - p, p - fence_rect.zw), vec2(0.0));
		float out_m = length(outside) + (crumbs - 0.5) * 6.0;
		float f = smoothstep(forest_from, forest_from + 12.0, out_m);
		vec3 floor_col = texture(forest, uv * 1.3).rgb * vec3(0.62, 0.6, 0.62);
		c = mix(c, floor_col, f);
	}
	c *= tint * (1.0 - patchiness * 0.5 + patchiness * (blobs * 0.7 + crumbs * 0.3));
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
}
