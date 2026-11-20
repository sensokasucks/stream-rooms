shader_type spatial;
render_mode cull_disabled;
// Log Cabin: the surfaces cabin_builder.gd builds out of plain shapes (logs, chinking, floor,
// ceiling, stone, roof, deck, leather, wool, fleece, bark, the rug...). One material per kind of
// surface (cabin_builder.gd SURFACES / _surface_material); the colour comes from each corner of
// the mesh (its vertex colour), so the Simple look is just those colours.
// With `detail` at 1 (Set detail = Detailed, the room script's _apply_detail) the colour is
// multiplied by a photo "detail" texture and the surface gets the photo's bumps:
//   tex_grain  the photo divided by its own average colour, 0.5 = no change (times 2 here), so
//              every object keeps its own colour and gains the grain (textures/make_textures.py)
//   tex_nor    the photo's normal map (OpenGL style)
// How the picture is laid on (`mapping`):
//   0  by world position from three sides (no UV mapping needed): `tile` = metres one copy
//      covers; `vertical_axis` (0 = x, 1 = y, 2 = z, -1 = none) is the world direction the
//      picture's up-and-down follows wherever it can (the ceiling boards run along the ridge,
//      the roof's rows of shakes along the eaves)
//   1  once over the shape, by the mesh's UV2 (0..1 across the rug)
//   2  end grain: rings drawn from UV2, which holds each log end's corner as a point on a unit
//      circle (0 at the heart, 1 at the bark)
// With `photo` at 1 the texture is a plain colour photo (the campfire's grass and dirt, laid on
// the ground outside): Detailed shows the photo itself (times `photo_tint`) instead of tinting
// the mesh's colour.

uniform float detail = 0.0;
uniform sampler2D tex_grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int mapping = 0;
uniform float tile = 1.0;
uniform int vertical_axis = -1;
// how strong the bumps are (1 = as in the normal map)
uniform float bump = 1.0;
uniform float roughness = 0.85;
// darker grain is rougher, lighter smoother, by up to this much
uniform float rough_vary = 0.15;
uniform float specular = 0.5;
uniform float metallic = 0.0;
uniform float photo = 0.0;
// what a colour photo is multiplied by (cabin_builder.gd PHOTO_TINTS: the grass made greener)
uniform vec3 photo_tint : source_color = vec3(1.0);
// how strongly the grain shows: 1 = as in the photo, 0 = flat (cabin_builder.gd GRAIN_STRENGTH)
uniform float grain_strength = 1.0;

varying vec3 w_pos;
varying vec3 w_normal;

// The picture's coordinates on one of the three planes (axis = the world axis it looks along),
// and the world directions of the picture's right (eu) and up (ev).
void plane_uv(int axis, vec3 p, out vec2 uv, out vec3 eu, out vec3 ev) {
	if (axis == 0) {
		uv = p.zy;
		eu = vec3(0.0, 0.0, 1.0);
		ev = vec3(0.0, 1.0, 0.0);
	} else if (axis == 1) {
		uv = p.xz;
		eu = vec3(1.0, 0.0, 0.0);
		ev = vec3(0.0, 0.0, 1.0);
	} else {
		uv = p.xy;
		eu = vec3(1.0, 0.0, 0.0);
		ev = vec3(0.0, 1.0, 0.0);
	}
	if (vertical_axis >= 0 && eu[vertical_axis] > 0.5) {
		uv = uv.yx;
		vec3 keep = eu;
		eu = ev;
		ev = keep;
	}
	uv /= tile;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(w_normal);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 grain = vec3(0.5);
	vec3 bent = n;
	if (detail > 0.5) {
		if (mapping == 0) {
			vec3 w = pow(abs(n), vec3(6.0));
			w /= (w.x + w.y + w.z);
			vec3 col = vec3(0.0);
			vec3 sum = vec3(0.0);
			for (int a = 0; a < 3; a++) {
				if (w[a] < 0.01) {
					continue;
				}
				vec2 uv;
				vec3 eu;
				vec3 ev;
				plane_uv(a, w_pos, uv, eu, ev);
				col += texture(tex_grain, uv).rgb * w[a];
				vec2 t = (texture(tex_nor, uv).rg * 2.0 - 1.0) * bump;
				// "UDN" blend: the bumps tip the surface normal within this plane
				sum += (n + eu * t.x + ev * t.y) * w[a];
			}
			grain = col;
			bent = normalize(sum);
		} else if (mapping == 1) {
			grain = texture(tex_grain, UV2).rgb;
		} else {
			// end grain: growth rings, wobbled by the log photo, a dark bark rim and a few cracks
			float r = length(UV2);
			float wob = texture(tex_grain, UV2 * 0.35 + w_pos.xz * 0.05).r;
			float ring = 0.5 + 0.5 * sin(r * 46.0 + wob * 5.0);
			grain = vec3(0.5) * mix(1.12, 0.86, ring * ring);
			grain *= mix(1.0, 0.62, smoothstep(0.82, 0.97, r));
			float a = atan(UV2.y, UV2.x);
			float crack = smoothstep(0.985, 1.0, sin(a * 3.0 + wob * 2.0)) * smoothstep(0.15, 0.6, r);
			grain *= 1.0 - 0.35 * crack;
		}
	}
	if (photo < 0.5) {
		grain = mix(vec3(0.5), grain, grain_strength);
	}
	ALBEDO = (detail > 0.5 && photo > 0.5) ? grain * photo_tint : COLOR.rgb * grain * 2.0;
	ROUGHNESS = clamp(roughness + (0.5 - (grain.r + grain.g + grain.b) / 3.0) * rough_vary * 2.0, 0.04, 1.0);
	SPECULAR = specular;
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
}
