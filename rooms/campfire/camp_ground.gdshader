shader_type spatial;
// Lakeside Campfire: the ground (one mesh from campfire_builder.gd, build_ground). The mesh's
// vertex colour says what the ground is at each point: red = trodden dirt (round the fire, under
// the benches), green = sand and gravel (the lake shore, the stream's bed), blue = forest floor
// (under the trees); none of them = grass. This shader mixes the four colours by that, breaks
// them up with noise so no patch is flat, and makes everything darker and shinier when it is
// wet (the room script sets `wet` from the rain).
// With `detail` at 1 (the room's Set detail choice, campfire_room.gd _apply_detail) the four
// flat colours are replaced by four photo textures (textures/ground_*.jpg, CC0 from Poly Haven),
// laid over the ground by world position; the same vertex colours and ragged edges mix them.

uniform vec3 grass : source_color = vec3(0.16, 0.27, 0.09);
uniform vec3 grass_dry : source_color = vec3(0.26, 0.3, 0.11);
uniform vec3 dirt : source_color = vec3(0.2, 0.14, 0.09);
uniform vec3 sand : source_color = vec3(0.36, 0.31, 0.22);
uniform vec3 forest_floor : source_color = vec3(0.09, 0.11, 0.06);
// 0 = flat colours (the low-poly look), 1 = the photo textures below.
uniform float detail = 0.0;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_forest : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Metres one copy of a texture covers.
uniform float tile_size = 3.2;
// Tints laid over the photos, so the ground sits with the rest of the set (1 = as photographed).
uniform vec3 photo_tint : source_color = vec3(0.76, 0.8, 0.68);
// 0 = dry, 1 = soaked.
uniform float wet : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float big = noise2(p * 0.23);
	float mid = noise2(p * 1.7 + vec2(9.0, 4.0));
	float fine = noise2(p * 11.0);
	// the edges between ground types are ragged, not a smooth blend
	float ragged = (mid - 0.5) * 0.5 + (fine - 0.5) * 0.25;
	vec3 c;
	if (detail > 0.5) {
		vec2 uv = p / tile_size;
		// a second, bigger copy of the grass mixed in hides the repeat of the first
		vec3 g = mix(texture(tex_grass, uv).rgb, texture(tex_grass, uv * 0.37 + vec2(0.31, 0.17)).rgb, 0.35);
		// big soft patches of drier and lusher grass
		g *= mix(vec3(0.6, 0.84, 0.5), vec3(0.86, 0.98, 0.64), smoothstep(0.3, 0.75, big * 0.7 + mid * 0.3));
		c = g;
		c = mix(c, texture(tex_forest, uv * 1.3).rgb, smoothstep(0.35, 0.65, COLOR.b + ragged));
		c = mix(c, texture(tex_dirt, uv * 1.6).rgb * vec3(0.9, 0.82, 0.74), smoothstep(0.35, 0.65, COLOR.r + ragged));
		c = mix(c, texture(tex_sand, uv * 1.4).rgb, smoothstep(0.35, 0.65, COLOR.g + ragged));
		c *= photo_tint * (0.88 + 0.24 * big);
	} else {
		c = mix(grass, grass_dry, smoothstep(0.35, 0.75, big * 0.7 + mid * 0.3));
		c = mix(c, forest_floor, smoothstep(0.35, 0.65, COLOR.b + ragged));
		c = mix(c, dirt, smoothstep(0.35, 0.65, COLOR.r + ragged));
		c = mix(c, sand, smoothstep(0.35, 0.65, COLOR.g + ragged));
		c *= 0.8 + 0.4 * fine;
	}
	// puddles gather in the dirt first
	float puddle = wet * smoothstep(0.55, 0.75, big * 0.5 + mid * 0.5 + COLOR.r * 0.25);
	ALBEDO = c * (1.0 - 0.35 * wet);
	ROUGHNESS = mix(0.95, 0.35, wet * 0.6) - puddle * 0.3;
	SPECULAR = 0.3 + 0.4 * wet;
}
