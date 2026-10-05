shader_type sky;
// Night sky for the drive-in.
//  - Moon: textured sphere with a proper lit/dark side (phase), faint earthshine and a soft halo.
//    Its position follows the room's DirectionalLight (the "Moonlight"), so shadows line up.
//  - Stars: jittered point stars with varied brightness and colour, a faint Milky Way band,
//    dimmed near the moon and the horizon.
//  - Clouds: a few slow-drifting clouds, lit from the moon's side, brighter near the moon.
// Radiance (reflections/ambient) passes get a cheap version without stars and cloud detail.
// Built-ins like TIME / LIGHT0_* are read only inside sky() (the Compatibility renderer requires it).

group_uniforms moon;
uniform sampler2D moon_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float moon_radius_deg : hint_range(0.2, 6.0) = 1.4;
uniform float moon_brightness : hint_range(0.0, 20.0) = 0.95;
/// Direction of the sunlight on the moon, relative to the viewer: x = right, y = up, z = toward viewer.
/// (0,0,1) is a full moon; (1,0,0.3) a gibbous moon lit from the right.
uniform vec3 moon_sun_dir = vec3(0.72, 0.1, 0.68);
uniform float earthshine : hint_range(0.0, 0.2) = 0.03;
uniform vec3 halo_color : source_color = vec3(0.55, 0.62, 0.8);
/// Tint of moonlight after passing through the air (slightly warm).
uniform vec3 moon_tint : source_color = vec3(1.0, 0.96, 0.88);
/// Softens the moon's edge (atmospheric blur), in fractions of its radius.
uniform float moon_edge_softness : hint_range(0.0, 0.3) = 0.1;
/// How much the air washes out surface contrast (0 = crisp, 1 = flat).
uniform float moon_haze : hint_range(0.0, 1.0) = 0.35;
uniform float halo_strength : hint_range(0.0, 2.0) = 0.42;
/// Used only when the room has no DirectionalLight.
uniform vec3 fallback_moon_dir = vec3(-0.37, 0.47, -0.8);

group_uniforms sky;
uniform vec3 zenith_color : source_color = vec3(0.003, 0.006, 0.018);
uniform vec3 horizon_color : source_color = vec3(0.025, 0.035, 0.07);
uniform vec3 glow_color : source_color = vec3(0.09, 0.07, 0.06);   // faint town glow at the horizon
uniform vec3 ground_color : source_color = vec3(0.004, 0.005, 0.007);

group_uniforms stars;
uniform float star_density : hint_range(50.0, 600.0) = 260.0;
uniform float star_brightness : hint_range(0.0, 10.0) = 3.0;
uniform float twinkle : hint_range(0.0, 1.0) = 0.25;
uniform float milky_way : hint_range(0.0, 1.0) = 0.35;
uniform vec3 milky_way_axis = vec3(0.3, 0.45, 0.84);

group_uniforms clouds;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.32;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.18;
uniform float cloud_scale : hint_range(0.1, 5.0) = 1.1;
uniform vec2 cloud_wind = vec2(0.006, 0.002);
uniform vec3 cloud_dark : source_color = vec3(0.012, 0.014, 0.022);
uniform vec3 cloud_lit : source_color = vec3(0.16, 0.17, 0.2);

// ── noise helpers ────────────────────────────────────────────
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s;
}

// ── pieces ───────────────────────────────────────────────────
// Returns the moon's own light in .rgb (added on top of the sky) and its disc mask in .a
// (used only to hide stars behind it). The unlit side adds almost nothing, so it shows
// the sky and glow behind it instead of a dark cut-out.
vec4 draw_moon(vec3 d, vec3 md) {
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), md));
	vec3 up = cross(md, right);
	float t = tan(radians(moon_radius_deg));
	vec2 q = vec2(dot(d, right), dot(d, up)) / max(dot(d, md), 1e-4) / t;
	float r = length(q);
	float soft = max(moon_edge_softness, 0.001);
	if (dot(d, md) <= 0.0 || r > 1.0 + soft) {
		return vec4(0.0);
	}
	float mask = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, r);
	vec2 qc = q / max(r, 1.0);                                  // clamp to the disc for shading
	float r2 = dot(qc, qc);
	vec3 n = vec3(-qc.x, qc.y, sqrt(max(1.0 - r2, 0.0)));     // z toward the viewer
	float ndl = dot(n, normalize(moon_sun_dir));
	float lit = smoothstep(-0.08, 0.16, ndl) * mix(0.8, 1.0, sqrt(max(ndl, 0.0)));
	float lon = atan(n.x, n.z);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	vec3 albedo = texture(moon_texture, vec2(lon / (2.0 * PI) + 0.5, 0.5 - lat / PI)).rgb;
	// atmosphere: wash out contrast toward the average surface brightness
	albedo = mix(albedo, vec3(0.62), moon_haze);
	vec3 light = albedo * moon_tint * (lit * moon_brightness + earthshine);
	return vec4(light * mask, mask);
}

vec3 draw_stars(vec3 d, float fade, float t) {
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float dens = star_density * (layer == 0 ? 1.0 : 2.3);
		vec3 p = d * dens;
		vec3 cell = floor(p);
		vec3 h = hash33(cell + float(layer) * 91.7);
		if (h.x > (layer == 0 ? 0.975 : 0.988)) {
			vec3 star_pos = (cell + 0.2 + 0.6 * hash33(cell + 13.1)) / dens;
			float dist = length(normalize(star_pos) - d) * dens;
			float size = mix(0.12, 0.3, h.y * h.y);
			float core = exp(-dist * dist / (size * size));
			float mag = pow(h.z, 3.0) * (layer == 0 ? 1.0 : 0.45);
			float tw = 1.0 - twinkle * 0.5 * (1.0 + sin(t * (2.0 + h.y * 4.0) + h.z * 40.0));
			vec3 tint = mix(vec3(1.0, 0.82, 0.62), vec3(0.72, 0.82, 1.0), h.y);
			col += tint * core * mag * tw;
		}
	}
	// Milky Way: soft band with dust lanes
	float band = exp(-pow(dot(d, normalize(milky_way_axis)), 2.0) / 0.018);
	vec2 mw_uv = vec2(atan(d.x, d.z), d.y) * 3.0;
	float mw = band * (0.45 + 0.8 * fbm(mw_uv * 2.0)) * (1.0 - 0.7 * smoothstep(0.45, 0.7, fbm(mw_uv * 4.0 + 5.0)));
	col += vec3(0.5, 0.52, 0.6) * mw * milky_way * 0.05;
	return col * star_brightness * fade;
}

// Returns cloud rgb and alpha
vec4 draw_clouds(vec3 d, vec3 md, float t) {
	if (d.y < 0.01) {
		return vec4(0.0);
	}
	vec2 p = d.xz / (d.y + 0.08) * cloud_scale + cloud_wind * t;
	float n = fbm(p);
	float thr = 1.0 - cloud_coverage;
	float a = smoothstep(thr - cloud_softness * 0.5, thr + cloud_softness, n);
	// fake self-shadowing: sample again a little toward the moon
	vec2 toward = normalize(md.xz / (md.y + 0.08) - d.xz / (d.y + 0.08) + 1e-5) * 0.12;
	float n2 = fbm(p + toward);
	float shade = clamp(0.6 + (n - n2) * 5.0, 0.0, 1.0);
	float near_moon = pow(max(dot(d, md), 0.0), 60.0);        // silver lining close to the moon
	float wide_moon = pow(max(dot(d, md), 0.0), 6.0);
	vec3 col = mix(cloud_dark, cloud_lit, shade * (0.35 + 0.65 * wide_moon));
	col += halo_color * near_moon * 0.9 * (1.0 - a * 0.5);
	a *= smoothstep(0.01, 0.12, d.y);                          // fade out toward the horizon
	return vec4(col, a * 0.92);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 md = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(fallback_moon_dir);
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, smoothstep(0.0, 0.55, h));
	col += glow_color * exp(-max(h, 0.0) * 14.0);
	col = mix(col, ground_color, smoothstep(0.0, -0.06, h));

	float cos_m = max(dot(d, md), 0.0);
	vec3 halo = halo_color * halo_strength * (0.6 * pow(cos_m, 300.0) + 0.25 * pow(cos_m, 40.0) + 0.08 * pow(cos_m, 6.0));

	if (AT_CUBEMAP_PASS) {
		// radiance / ambient: gradient + halo only
		COLOR = col + halo * 0.5;
	} else {
		vec4 moon = draw_moon(d, md);
		float star_fade = smoothstep(0.02, 0.25, h) * (1.0 - 0.85 * pow(cos_m, 25.0)) * (1.0 - moon.a);
		col += draw_stars(d, star_fade, TIME);
		col += moon.rgb;          // additive: the dark side shows the sky behind it
		float lit_amount = clamp(dot(moon.rgb, vec3(0.333)) * 1.5, 0.0, 1.0);
		col += halo * (1.0 - 0.6 * lit_amount);   // full glow on the dark side, lighter veil over the lit side
		vec4 cl = draw_clouds(d, md, TIME);
		vec3 cloud_col = cl.rgb + moon.rgb * 0.25;   // moonlight shining through thin cloud
		col = mix(col, cloud_col, cl.a);
		COLOR = col;
	}
}
