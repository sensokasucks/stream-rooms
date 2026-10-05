shader_type spatial;
// A presenter's picture behind a podium: a live feed (camera / tab) with an optional
// chroma key, a plain key-colour "green screen", or a standing silhouette.
// Self-lit = glows like a light panel; otherwise the room and the podium lamp light it.
render_mode blend_mix, depth_prepass_alpha, cull_disabled, shadows_disabled;

uniform sampler2D feed : source_color, filter_linear, repeat_disable;
uniform sampler2D silhouette : source_color, filter_linear_mipmap, repeat_disable;
/// 0 silhouette, 1 plain key colour, 2 live feed, 3 waiting for a feed
uniform int mode = 0;
uniform bool key_on = true;
uniform vec4 key_color : source_color = vec4(0.0, 1.0, 0.0, 1.0);
/// Chroma distance (CbCr) that still counts as background.
uniform float similarity : hint_range(0.0, 1.0) = 0.28;
/// Width of the soft edge beyond `similarity`.
uniform float smoothness : hint_range(0.0, 0.5) = 0.08;
/// How much of the key colour's cast to remove from the kept pixels.
uniform float spill : hint_range(0.0, 1.0) = 0.6;
uniform float zoom : hint_range(0.2, 4.0) = 1.0;
uniform float offset_y : hint_range(-1.0, 1.0) = 0.0;
/// width / height of this plane and of the feed picture (for a "cover" fit).
uniform float plane_aspect = 1.04;
uniform float feed_aspect = 1.7778;
uniform bool self_lit = false;
uniform float glow = 1.2;

vec2 cbcr(vec3 c) {
	return vec2(-0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b, 0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b);
}

vec3 from_ycbcr(float y, vec2 cc) {
	return vec3(y + 1.402 * cc.y, y - 0.344136 * cc.x - 0.714136 * cc.y, y + 1.772 * cc.x);
}

void fragment() {
	vec3 col = vec3(0.0);
	float alpha = 1.0;
	if (mode == 0) {
		vec4 s = texture(silhouette, UV);
		col = s.rgb;
		alpha = s.a;
	} else if (mode == 1) {
		col = key_color.rgb;
	} else if (mode == 2) {
		// cover-fit the feed into the plane, then zoom / shift
		vec2 p = UV - 0.5;
		float r = plane_aspect / max(feed_aspect, 0.01);
		vec2 s = r < 1.0 ? vec2(r, 1.0) : vec2(1.0, 1.0 / r);
		vec2 uv = p * s / max(zoom, 0.05) + vec2(0.5, 0.5 + offset_y);
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			discard;
		}
		vec4 f = texture(feed, uv);
		col = f.rgb;
		alpha = f.a;     // NDI sources can carry real transparency; JPEG feeds are opaque
		if (key_on) {
			vec2 kc = cbcr(key_color.rgb);
			vec2 pc = cbcr(col);
			float d = distance(pc, kc);
			alpha *= smoothstep(similarity, similarity + smoothness, d);
			// spill: pull the key colour's tint out of what's left
			float kl = length(kc);
			if (kl > 0.001) {
				vec2 kd = kc / kl;
				float along = max(dot(pc, kd), 0.0);
				float near_key = 1.0 - smoothstep(similarity, similarity * 2.0 + 0.2, d);
				pc -= kd * along * spill * mix(0.35, 1.0, near_key);
				float y = dot(col, vec3(0.299, 0.587, 0.114));
				col = clamp(from_ycbcr(y, pc), 0.0, 1.0);
			}
		}
	} else {
		// waiting for the feed: a dim panel with slow scan lines
		float line = 0.5 + 0.5 * sin(UV.y * 180.0 - TIME * 3.0);
		col = vec3(0.05, 0.06, 0.08) + vec3(0.02) * line;
		alpha = 0.55;
	}
	if (alpha < 0.01) {
		discard;
	}
	if (self_lit) {
		ALBEDO = vec3(0.0);
		EMISSION = col * glow;
	} else {
		ALBEDO = col;
		ROUGHNESS = 0.85;
		SPECULAR = 0.15;
	}
	ALPHA = alpha;
}
