// Shared body of the screen material (see screen.gdshader and screen_holo.gdshader).
// The picture is emitted (it glows). The surface itself is black glass by default,
// or white fabric (screen_matte) for projection screens.
// Optional LED look for big outdoor billboards: the picture is split into round
// LED dots. The dots fade out with distance so they don't shimmer (moire).
// Optional old-film look for projector rooms: faded colour, grain, dust and hairs,
// scratches, gate weave, flicker, and a projector hot-spot vignette.
// Optional hologram look (scan lines, colour shift, noise) and glitch effect.
// Define SCREEN_TRANSPARENT before including to write ALPHA (holo_alpha).

uniform sampler2D screen_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform vec3 idle_color : source_color = vec3(0.06, 0.08, 0.16);
uniform float brightness = 1.6;
/// 0 = plain screen, 1 = full LED-dot look.
uniform float led_amount : hint_range(0.0, 1.0) = 0.0;
/// Number of LEDs across and down the screen.
uniform vec2 led_count = vec2(320.0, 180.0);
/// How much of each cell the LED fills (smaller = more visible gaps).
uniform float led_size : hint_range(0.2, 1.0) = 0.78;
/// 0 = clean, 1 = full old-film look (faded stock, tint, hot-spot).
uniform float film_amount : hint_range(0.0, 1.0) = 0.0;
/// Dirt part of the film look: grain, dust, hairs, scratches, flicker, weave (can go above 1).
uniform float film_dirt : hint_range(0.0, 2.0) = 0.0;
/// Colour cast of the faded film stock.
uniform vec3 film_tint : source_color = vec3(1.0, 0.92, 0.78);
/// Film frames per second (dirt, flicker and weave change once per frame).
uniform float film_fps = 18.0;
/// Surface albedo: 0 = black glass (TVs, LED walls), ~0.7 = white projection fabric.
uniform float screen_matte : hint_range(0.0, 1.0) = 0.0;

// Hologram look, after "Hologram Simple CanvasItem Shader" by Vaquers (godotshaders.com, CC0),
// ported to a 3D screen, plus a glitch effect and a separate opacity.
/// How strongly the scan-line colours take over the picture (the original's effect_factor).
uniform float holo_amount : hint_range(0.0, 1.0) = 0.0;
/// Number of scan lines down the screen.
uniform int holo_lines = 100;
uniform vec4 holo_color1 : source_color = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 holo_color2 : source_color = vec4(1.0, 0.0, 0.0, 1.0);
/// Scan-line scroll speed.
uniform float holo_speed : hint_range(0.0, 2.0, 0.01) = 0.4;
/// Static noise mixed into the picture.
uniform float holo_noise : hint_range(0.0, 1.0, 0.01) = 0.05;
/// Screen opacity (only the transparent screen variant uses it).
uniform float holo_alpha : hint_range(0.0, 1.0, 0.01) = 1.0;
/// Digital glitches: torn bands, RGB split, jumps and dropouts.
uniform float holo_glitch : hint_range(0.0, 1.0, 0.01) = 0.0;

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

/// Dust, hairs and scratches for one film frame. Returns a multiplier (dark dirt < 1,
/// light dirt / scratches > 1).
float dirt_mask(vec2 uv, float fr, float amount) {
	float m = 1.0;
	vec2 asp = vec2(16.0 / 9.0, 1.0);
	// specks: a few per frame, only on some frames
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		if (h11(fr * 1.37 + fi * 7.1) > 0.45 * amount + 0.1) {
			continue;
		}
		vec2 c = vec2(h11(fr * 3.1 + fi * 13.7), h11(fr * 5.3 + fi * 3.9));
		float r = 0.002 + 0.007 * h11(fr + fi * 17.3);
		vec2 d = (uv - c) * asp;
		float wob = 0.6 + 0.8 * vnoise(d * 180.0 + fi);
		float s = 1.0 - smoothstep(r * 0.4, r, length(d) * wob);
		bool bright = h11(fr * 9.7 + fi) < 0.3;          // "negative" dirt shows as white
		m *= bright ? 1.0 + s * 1.2 : 1.0 - s * 0.85;
	}
	// a hair now and then, lasting a few frames
	float hair_slot = floor(fr / 5.0);
	if (h11(hair_slot * 2.9) < 0.22 * amount) {
		vec2 c = vec2(h11(hair_slot * 4.1), h11(hair_slot * 6.7));
		float y = (uv.y - c.y) / 0.18;
		if (abs(y) < 1.0) {
			float x = c.x + 0.025 * sin(y * 5.0 + hair_slot) + 0.01 * y * y;
			float w = 0.0012 + 0.0008 * (1.0 - y * y);
			m *= 1.0 - 0.8 * (1.0 - smoothstep(w * 0.4, w, abs(uv.x - x)));
		}
	}
	// long vertical scratch that drifts, for a couple of seconds at a time
	float scr_slot = floor(fr / 40.0);
	if (h11(scr_slot * 1.7 + 3.0) < 0.6 * amount) {
		float sx = h11(scr_slot * 8.3) + 0.004 * sin(fr * 0.7);
		float line = 1.0 - smoothstep(0.0004, 0.0012, abs(uv.x - sx));
		m *= 1.0 + line * (0.5 + 0.5 * h11(fr)) * 0.9;
	}
	return m;
}

void fragment() {
	vec2 uv = UV;
	float fr = floor(TIME * film_fps);
	if (film_dirt > 0.0) {
		// gate weave: the frame jitters slightly, mostly up and down
		uv += (vec2(h11(fr), h11(fr + 7.3)) - 0.5) * vec2(0.0012, 0.0035) * film_dirt;
	}
	// ── glitch: bursts of torn bands, a jumping frame and RGB split ──
	float burst = 0.0;
	float split = 0.0;
	if (holo_glitch > 0.0) {
		float g = holo_glitch;
		float slot = floor(TIME * 14.0);
		// bursts come and go; more glitch = more often and longer
		burst = step(h11(floor(TIME * 3.0) * 1.71 + 0.3), 0.12 + 0.6 * g);
		float band = floor(UV.y * (10.0 + 30.0 * h11(slot * 0.37)) + h11(slot) * 13.0);
		float torn = step(h11(band * 3.71 + slot * 1.31), 0.35 * g) * burst;
		uv.x += (h11(band * 7.3 + slot) - 0.5) * 0.18 * g * torn;
		// the whole frame jumps now and then
		uv.y += (h11(slot * 2.9) - 0.5) * 0.06 * g * burst * step(h11(slot * 5.3), 0.3);
		// thin wobble all the time, stronger in bursts
		uv.x += sin(UV.y * 220.0 + TIME * 40.0) * 0.0015 * g * (0.3 + burst);
		split = (0.002 + 0.012 * burst) * g;
	}
	// hologram colour shift (the original shifts the image along the scan lines)
	float line_phase = (UV.y - TIME * holo_speed) * float(holo_lines);
	float smooth_line_grade = abs(sin(line_phase));
	vec2 shift = vec2(1.0, 0.0) * smooth_line_grade / 240.0 * holo_amount;
	vec3 col = idle_color;
	if (has_texture) {
		col = texture(screen_texture, uv - shift).rgb;
		if (split > 0.0) {
			col.r = texture(screen_texture, uv - shift + vec2(split, 0.0)).r;
			col.b = texture(screen_texture, uv - shift - vec2(split, 0.0)).b;
		}
	}
	if (led_amount > 0.0 && has_texture) {
		vec2 grid = UV * led_count;
		// fade the dot pattern out when a cell gets smaller than ~1.5 pixels
		float cell_px = 1.0 / max(fwidth(grid.x), 1e-4);
		float led = led_amount * smoothstep(1.5, 4.0, cell_px);
		vec2 cell_center = (floor(grid) + 0.5) / led_count;
		vec3 quantized = texture(screen_texture, cell_center).rgb;
		float d = length(fract(grid) - 0.5) * 2.0;
		float dot_mask = 1.0 - smoothstep(led_size - 0.15, led_size + 0.05, d);
		// dots are brighter than the average so overall brightness stays about the same
		vec3 led_col = quantized * dot_mask * 1.7;
		col = mix(col, led_col, led);
	}
	if ((film_amount > 0.0 || film_dirt > 0.0) && has_texture) {
		float a = film_amount;
		float d = film_dirt;
		// faded stock: less saturation, warm cast, lifted blacks, softer highlights
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(lum), 0.22 * a);
		col = mix(col, col * film_tint, a);
		col = mix(col, col * 0.94 + 0.02, a);
		// grain (changes every frame)
		float g = h21(floor(UV * vec2(900.0, 520.0)) + fr * 17.0) - 0.5;
		col += g * 0.09 * d * (0.4 + lum);
		// dust, hairs, scratches (more dirt = more often; strength capped so it stays film-like)
		col *= mix(1.0, dirt_mask(uv, fr, d), min(d, 1.0));
		// shutter flicker
		col *= 1.0 - min(d, 1.5) * 0.1 * h11(fr + 3.1);
		// projector hot-spot + soft, slightly rounded gate edges
		vec2 q = (UV - 0.5) * 2.0;
		col *= 1.0 - a * 0.45 * pow(length(q * vec2(0.85, 0.95)), 2.4);
		vec2 e = abs(q);
		float corner = length(max(e - vec2(0.94, 0.9), 0.0)) / 0.1;
		col *= 1.0 - a * smoothstep(0.6, 1.0, max(corner, max(e.x - 0.985, 0.0) * 60.0));
	}
	float alpha = 1.0;
	if (holo_amount > 0.0) {
		// static noise, then the scan-line colours (as in the original)
		float n = fract(sin(dot(UV, vec2(12.9898, 78.233) * TIME)) * 438.5453) * 1.9;
		col = mix(col, vec3(n), holo_noise);
		float line_grade = abs(sin(floor(line_phase) * PI / 4.0));
		vec4 line_color = mix(holo_color1, holo_color2, line_grade);
		col = mix(col, line_color.rgb, holo_amount);
		alpha *= mix(1.0, line_color.a * (0.75 + 0.25 * smooth_line_grade), holo_amount);
	}
	if (holo_glitch > 0.0) {
		// occasional dropout lines and a bright tear during bursts
		float slot = floor(TIME * 14.0);
		float row = floor(UV.y * 90.0);
		col *= 1.0 - 0.8 * step(h11(row * 1.9 + slot * 3.1), 0.04 * holo_glitch) * burst;
		float tear = 1.0 - smoothstep(0.0, 0.004, abs(UV.y - fract(TIME * 0.37 + h11(slot))));
		col += tear * 0.6 * holo_glitch * burst;
		alpha *= 1.0 - 0.5 * holo_glitch * burst * step(h11(slot * 9.1), 0.25);
	}
	ALBEDO = vec3(screen_matte);
	ROUGHNESS = screen_matte > 0.0 ? 0.95 : 0.35;
	SPECULAR = screen_matte > 0.0 ? 0.1 : 0.2;
	EMISSION = max(col, vec3(0.0)) * brightness;
#ifdef SCREEN_TRANSPARENT
	ALPHA = clamp(alpha * holo_alpha, 0.0, 1.0);
#endif
}
