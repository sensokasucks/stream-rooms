shader_type sky;
// Smoggy megacity night sky: no stars, a heavy low cloud deck lit from below by the
// city (warm orange near the horizon, magenta/teal patches), dark violet overhead.
// TIME is read only inside sky() (the Compatibility renderer requires it).

uniform vec3 zenith_color : source_color = vec3(0.012, 0.01, 0.025);
uniform vec3 horizon_glow : source_color = vec3(0.32, 0.14, 0.12);
uniform vec3 cloud_base : source_color = vec3(0.05, 0.035, 0.06);
uniform vec3 cloud_lit_warm : source_color = vec3(0.45, 0.2, 0.12);
uniform vec3 cloud_lit_neon : source_color = vec3(0.35, 0.08, 0.3);
uniform vec3 cloud_lit_cool : source_color = vec3(0.05, 0.22, 0.3);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.62;
uniform float cloud_scale : hint_range(0.1, 4.0) = 0.9;
uniform vec2 cloud_wind = vec2(0.004, 0.0015);
uniform vec3 ground_color : source_color = vec3(0.02, 0.012, 0.02);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return s;
}

vec3 clouds(vec3 d, float t, out float alpha) {
	alpha = 0.0;
	if (d.y < 0.0) {
		return vec3(0.0);
	}
	vec2 p = d.xz / (d.y + 0.12) * cloud_scale + cloud_wind * t;
	float n = fbm(p);
	float thr = 1.0 - cloud_coverage;
	alpha = smoothstep(thr - 0.12, thr + 0.2, n);
	// underside lighting: stronger toward the horizon (closer to the city lights)
	float low = 1.0 - smoothstep(0.0, 0.45, d.y);
	float patch_n = fbm(p * 0.35 + 3.0);
	vec3 lit = mix(cloud_lit_warm, cloud_lit_neon, smoothstep(0.45, 0.7, patch_n));
	lit = mix(lit, cloud_lit_cool, smoothstep(0.62, 0.8, fbm(p * 0.3 - 5.0)));
	float thickness = smoothstep(thr, thr + 0.35, n);
	vec3 col = mix(cloud_base, lit, (0.25 + 0.75 * low) * (1.0 - 0.5 * thickness));
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_glow, zenith_color, smoothstep(-0.02, 0.5, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	if (!AT_CUBEMAP_PASS) {
		float a;
		vec3 cl = clouds(d, TIME, a);
		col = mix(col, cl, a * smoothstep(0.0, 0.06, h));
	}
	COLOR = col;
}
