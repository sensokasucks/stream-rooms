// Screen Only set: the whole picture effect stack, drawn over the full window.
//
// Used by rooms/screen_only/screen_only_room.gd on one full-window ColorRect. The room script
// sets every uniform below from the so_* settings (AppState.DEFAULTS, "Screen Only" block) and
// hands in the big screen's picture (EventBus.screen_texture_changed). Keep the uniform names in
// step with screen_only_room.gd _apply_all() / UNIFORMS.
//
// Resizing: everything here works from UV (0..1 across the window) and FRAGCOORD (real window
// pixels). Curvature, bezel and fit follow the window's shape through rect_px (its size, any
// unit, only the ratio matters); scanlines, the RGB mask, pixel and halftone sizes are counted
// in real pixels, so they stay crisp when the window is dragged bigger or smaller.
//
// Order of the stack (top to bottom of fragment()): bezel shrink -> CRT glass curve / cinema bend
// -> tape wobble and film weave -> pixelate / LED cells -> fit the video into the window ->
// sample with colour fringing, colour bleed and glow -> bars around the video -> colour (grade,
// sepia, palette + dither, fun looks) -> hologram -> scanlines, mask, LED dots -> vignette,
// flicker, rolling bar, grain, scratches, tape noise -> rounded corners and the bezel.
// "Between videos" (no picture, or the curtain closed) replaces the video with idle_mode.
shader_type canvas_item;

// ── the picture ──
uniform sampler2D video : filter_linear, repeat_disable;
uniform vec2 video_size = vec2(1920.0, 1080.0);  // pixels of the current picture (aspect only)
uniform vec2 rect_px = vec2(1920.0, 1080.0);     // the window's drawable size (aspect only)
uniform bool has_video = false;                  // false = draw the "between videos" picture
uniform int idle_mode = 0;                       // 0 static snow, 1 colour bars, 2 black, 3 stand-by (dark blue)
uniform int fit_mode = 0;                        // 0 fit with bars, 1 fill and crop, 2 stretch
uniform int bars_mode = 0;                       // 0 black, 1 colour, 2 glow from the picture
uniform vec4 bar_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// ── CRT tube ──
uniform float curve = 0.0;        // 0..1 glass curvature (bent corners)
uniform float corner = 0.0;       // 0..1 rounded picture corners
uniform float scanlines = 0.0;    // 0..1 strength
uniform float scan_px = 3.0;      // one scanline every this many window pixels
uniform float mask = 0.0;         // 0..1 RGB phosphor mask strength
uniform int mask_type = 0;        // 0 aperture grille (stripes), 1 shadow mask (dots), 2 slot mask
uniform float glow = 0.0;         // 0..1 phosphor glow / bloom
uniform float vignette = 0.0;     // 0..1 darker edges
uniform float fringe = 0.0;       // 0..1 colour fringing (red / blue edges drift apart)
uniform float flicker = 0.0;      // 0..1 brightness flicker (already scaled down in safe mode)
uniform float roll = 0.0;         // 0..1 slow bright bar rolling down (already scaled in safe mode)
uniform float bezel = 0.0;        // 0..1 plastic frame around the glass, with a reflection

// ── brought over from the rooms ──
uniform float led = 0.0;          // 0..1 LED wall dots
uniform float led_count = 160.0;  // LEDs across the window
uniform float holo = 0.0;         // 0..1 hologram look
uniform float bend = 0.0;         // 0..1 cinema screen bend (left / right edges curve away)

// ── tape and film ──
uniform float vhs = 0.0;          // 0..1 tracking band, line wobble, tape noise
uniform float bleed = 0.0;        // 0..1 colour bleed (colour smears sideways)
uniform float grain = 0.0;        // 0..1 film grain
uniform float scratches = 0.0;    // 0..1 dust, scratches and gate weave
uniform float sepia = 0.0;        // 0..1 faded brown film colour

// ── retro and fun ──
uniform float pixelate = 0.0;     // 0..1 chunky pixels (0 = off, 1 = 24-pixel blocks)
uniform int palette = 0;          // 0 off, 1 handheld green, 2 amber monitor, 3 green monitor, 4 grey, 5 four-colour retro
uniform float dither = 0.0;       // 0..1 ordered dither (used with a palette)
uniform int fun_mode = 0;         // 0 off, 1 night vision, 2 thermal, 3 comic halftone, 4 ASCII, 5 posterize, 6 invert
uniform float fun = 1.0;          // 0..1 how much of the fun look
uniform float saturation = 1.0;   // 0..2
uniform float brightness = 1.0;   // 0.5..1.5
uniform float contrast = 1.0;     // 0.5..1.5
uniform float motion_scale = 1.0; // 1 normal; lower in photosensitive-safe mode (slows static, glitches)

// ── small helpers ──
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash12(vec2(i, 1.7)), hash12(vec2(i + 1.0, 1.7)), f * f * (3.0 - 2.0 * f));
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Window position (0..1) -> picture UV for the chosen fit. Outside 0..1 = no picture there.
vec2 fit_uv(vec2 p, int mode) {
	float r_scr = rect_px.x / max(rect_px.y, 1.0);
	float r_vid = video_size.x / max(video_size.y, 1.0);
	vec2 s = vec2(1.0);
	if (mode == 0) {
		s = vec2(max(1.0, r_scr / r_vid), max(1.0, r_vid / r_scr));
	} else if (mode == 1) {
		s = vec2(min(1.0, r_scr / r_vid), min(1.0, r_vid / r_scr));
	}
	return (p - 0.5) * s + 0.5;
}

bool inside01(vec2 uv) {
	return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

// The picture at uv with fringing and colour bleed.
vec3 sample_video(vec2 uv) {
	vec2 d = (uv - 0.5) * fringe * 0.012 + vec2(fringe * 0.0015, 0.0);
	vec3 c;
	c.r = texture(video, uv + d).r;
	c.g = texture(video, uv).g;
	c.b = texture(video, uv - d).b;
	if (bleed > 0.001) {
		// keep the sharp brightness, smear the colour sideways (like composite video / tape)
		vec3 smear = vec3(0.0);
		float w = 0.004 * bleed;
		for (int i = -3; i <= 3; i++) {
			smear += texture(video, uv + vec2(float(i) * w, 0.0)).rgb;
		}
		smear /= 7.0;
		c = luma(c) + (smear - luma(smear));
	}
	return c;
}

// A soft blur of the picture around uv (glow and glowing bars).
vec3 blur_video(vec2 uv, float r) {
	vec3 acc = vec3(0.0);
	acc += texture(video, uv + vec2(r, 0.0)).rgb;
	acc += texture(video, uv - vec2(r, 0.0)).rgb;
	acc += texture(video, uv + vec2(0.0, r)).rgb;
	acc += texture(video, uv - vec2(0.0, r)).rgb;
	acc += texture(video, uv + vec2(r, r) * 0.7).rgb;
	acc += texture(video, uv - vec2(r, r) * 0.7).rgb;
	acc += texture(video, uv + vec2(r, -r) * 0.7).rgb;
	acc += texture(video, uv - vec2(r, -r) * 0.7).rgb;
	return acc / 8.0;
}

// "Between videos": static snow, colour bars, black, or a dark stand-by blue (the room puts its
// stand-by text on top).
vec3 idle_picture(vec2 p, vec2 px) {
	if (idle_mode == 0) {
		float t = floor(TIME * 30.0 * motion_scale);
		float n = hash12(floor(px / 2.0) + t * 17.0);
		return vec3(n * (0.35 + 0.4 * motion_scale));
	} else if (idle_mode == 1) {
		// classic seven colour bars over a dark strip (original drawing, no channel logo)
		vec3 bars[7] = vec3[](vec3(0.75), vec3(0.75, 0.75, 0.0), vec3(0.0, 0.75, 0.75), vec3(0.0, 0.75, 0.0),
			vec3(0.75, 0.0, 0.75), vec3(0.75, 0.0, 0.0), vec3(0.0, 0.0, 0.75));
		int i = clamp(int(floor(p.x * 7.0)), 0, 6);
		if (p.y > 0.75) {
			return vec3(p.x < 0.18 ? 0.0 : (p.x < 0.36 ? 1.0 : 0.08));
		}
		return bars[i];
	} else if (idle_mode == 2) {
		return vec3(0.0);
	}
	return mix(vec3(0.02, 0.04, 0.10), vec3(0.06, 0.10, 0.22), 1.0 - length(p - 0.5));
}

vec3 apply_palette(vec3 c, vec2 px) {
	float l = luma(c);
	if (dither > 0.001) {
		// 4x4 ordered (Bayer) dither in window pixels
		int bx = int(mod(px.x, 4.0));
		int by = int(mod(px.y, 4.0));
		int idx = by * 4 + bx;
		float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		l += (bayer[idx] / 16.0 - 0.5) * 0.25 * dither;
	}
	if (palette == 1) {
		vec3 shades[4] = vec3[](vec3(0.06, 0.22, 0.06), vec3(0.19, 0.38, 0.19), vec3(0.55, 0.67, 0.06), vec3(0.61, 0.74, 0.06));
		return shades[clamp(int(floor(l * 4.0)), 0, 3)];
	} else if (palette == 2) {
		float q = floor(clamp(l, 0.0, 1.0) * 6.0) / 5.0;
		return vec3(1.0, 0.65, 0.15) * q;
	} else if (palette == 3) {
		float q = floor(clamp(l, 0.0, 1.0) * 6.0) / 5.0;
		return vec3(0.25, 1.0, 0.35) * q;
	} else if (palette == 4) {
		return vec3(floor(clamp(l, 0.0, 1.0) * 8.0) / 7.0);
	} else if (palette == 5) {
		// four-colour home-computer look: black, cyan, magenta, white by brightness and hue
		if (l < 0.2) { return vec3(0.0); }
		if (l > 0.8) { return vec3(1.0); }
		return c.b + c.g > c.r * 1.6 ? vec3(0.33, 1.0, 1.0) : vec3(1.0, 0.33, 1.0);
	}
	return c;
}

vec3 fun_look(vec3 c, vec2 p, vec2 px) {
	float l = luma(c);
	if (fun_mode == 1) {
		// night vision: bright green, grainy, round eyepiece
		float n = hash12(px + floor(TIME * 24.0 * motion_scale) * 13.0);
		vec3 g = vec3(0.1, 1.0, 0.2) * (l * 1.6 + n * 0.12);
		float ring = smoothstep(0.62, 0.48, length((p - 0.5) * vec2(rect_px.x / rect_px.y, 1.0)));
		return g * ring;
	} else if (fun_mode == 2) {
		// thermal camera: dark blue -> purple -> red -> yellow -> white
		vec3 a = vec3(0.0, 0.0, 0.25);
		vec3 b = vec3(0.55, 0.0, 0.6);
		vec3 r = vec3(1.0, 0.1, 0.0);
		vec3 y = vec3(1.0, 0.9, 0.0);
		if (l < 0.33) { return mix(a, b, l / 0.33); }
		if (l < 0.66) { return mix(b, r, (l - 0.33) / 0.33); }
		if (l < 0.9) { return mix(r, y, (l - 0.66) / 0.24); }
		return mix(y, vec3(1.0), (l - 0.9) / 0.1);
	} else if (fun_mode == 3) {
		// comic halftone: dots on a 7-pixel grid, bigger where darker, colours kept bold
		float cell = 7.0;
		vec2 g = mod(px, cell) - cell * 0.5;
		float rad = (1.0 - l) * cell * 0.62;
		float dot_on = step(length(g), rad);
		vec3 ink = floor(c * 3.0 + 0.5) / 3.0;
		return mix(vec3(1.0, 0.97, 0.88), ink * 0.6, dot_on);
	} else if (fun_mode == 4) {
		// ASCII: an 8x12 pixel cell per character, picked by brightness, drawn as simple strokes
		vec2 cell = vec2(8.0, 12.0);
		vec2 q = mod(px, cell) / cell;   // 0..1 inside the character cell
		float lev = floor(l * 6.0);
		float ink = 0.0;
		if (lev >= 1.0) { ink = max(ink, step(length(q - vec2(0.5, 0.75)), 0.12)); }                 // .
		if (lev >= 2.0) { ink = max(ink, step(abs(q.y - 0.5), 0.06) * step(abs(q.x - 0.5), 0.32)); } // -
		if (lev >= 3.0) { ink = max(ink, step(abs(q.x - 0.5), 0.07) * step(abs(q.y - 0.5), 0.32)); } // +
		if (lev >= 4.0) { ink = max(ink, step(abs(q.x - q.y), 0.08) * step(abs(q.y - 0.5), 0.36)); } // x
		if (lev >= 5.0) { ink = max(ink, step(abs(q.x - 0.5), 0.36) * step(abs(q.y - 0.5), 0.40)); } // block
		return vec3(0.3, 1.0, 0.45) * ink;
	} else if (fun_mode == 5) {
		return floor(c * 4.0 + 0.5) / 4.0;
	} else if (fun_mode == 6) {
		return 1.0 - c;
	}
	return c;
}

void fragment() {
	vec2 px = FRAGCOORD.xy;             // real window pixels: scanlines, masks, pixel sizes
	vec2 p = UV;
	float aspect = rect_px.x / max(rect_px.y, 1.0);

	// bezel: the glass sits inside a plastic frame
	float frame = bezel * 0.07;
	vec2 frame_xy = vec2(frame / aspect, frame);
	vec2 g = (p - frame_xy) / (1.0 - 2.0 * frame_xy);

	// CRT glass: barrel curve, stronger towards the corners; cinema bend: edges curve away
	vec2 c = g - 0.5;
	if (curve > 0.001) {
		vec2 k = vec2(c.y * c.y, c.x * c.x) * curve * 0.55;
		c += c * k;
	}
	if (bend > 0.001) {
		c.y *= 1.0 + bend * 0.35 * (c.x * c.x * 4.0);
	}
	g = c + 0.5;
	bool on_glass = inside01(g);

	// tape wobble (each line slides sideways a little) and the film gate weave
	float tm = TIME * motion_scale;
	if (vhs > 0.001) {
		g.x += sin(g.y * 90.0 + tm * 4.0) * 0.0012 * vhs;
		float band = fract(tm * 0.07);
		float in_band = smoothstep(0.03, 0.0, abs(g.y - (1.0 - band)));
		g.x += (hash12(vec2(floor(g.y * 240.0), floor(tm * 20.0))) - 0.5) * 0.03 * vhs * in_band;
	}
	if (scratches > 0.001) {
		g += vec2(noise1(tm * 8.0) - 0.5, noise1(tm * 6.0 + 4.0) - 0.5) * 0.004 * scratches;
	}

	// chunky pixels and LED cells: snap where the picture is read (window pixels / LED grid)
	vec2 read = g;
	if (pixelate > 0.001) {
		float block = mix(1.0, 24.0, pixelate);
		vec2 glass_px = rect_px * (1.0 - 2.0 * frame_xy);
		read = (floor(read * glass_px / block) + 0.5) * block / glass_px;
	}
	vec2 cells = vec2(led_count, led_count / aspect);
	vec2 led_q = fract(read * cells);
	if (led > 0.001) {
		read = (floor(read * cells) + 0.5) / cells;
	}

	// the picture, fitted into the window
	vec2 uv = fit_uv(read, fit_mode);
	vec3 col;
	if (!has_video) {
		col = idle_picture(read, px);
	} else if (inside01(uv)) {
		col = sample_video(uv);
		if (glow > 0.001) {
			col += blur_video(uv, 0.006) * glow * 0.6 + blur_video(uv, 0.018) * glow * 0.35;
		}
	} else if (bars_mode == 1) {
		col = bar_color.rgb;
	} else if (bars_mode == 2) {
		// glow from the picture: the same picture filled out, heavily blurred and dimmed
		vec2 fill = clamp(fit_uv(read, 1), vec2(0.0), vec2(1.0));
		col = (blur_video(fill, 0.05) + blur_video(fill, 0.11)) * 0.5 * 0.45;
	} else {
		col = vec3(0.0);
	}

	// colour: grade, sepia film, palette, fun looks
	col = (col - 0.5) * contrast + 0.5;
	col *= brightness;
	col = mix(vec3(luma(col)), col, saturation);
	if (sepia > 0.001) {
		vec3 sep = vec3(luma(col)) * vec3(1.07, 0.88, 0.66);
		col = mix(col, sep, sepia);
	}
	if (palette > 0) {
		col = apply_palette(col, px);
	}
	if (fun_mode > 0) {
		col = mix(col, fun_look(col, g, px), fun);
	}

	// hologram: cyan wash, drifting lines, a tearing glitch now and then
	if (holo > 0.001) {
		float lines = 0.6 + 0.4 * sin((g.y * 260.0 - tm * 3.0) * 3.14159);
		float tear = step(0.97, hash12(vec2(floor(tm * 3.0), 2.0))) * step(abs(g.y - hash12(vec2(floor(tm * 3.0), 5.0))), 0.04);
		vec3 h = vec3(0.25, 0.9, 1.0) * (luma(col) * 1.3 + 0.05) * lines;
		h += vec3(0.4, 1.0, 1.0) * tear * 0.5;
		col = mix(col, h, holo);
	}

	// scanlines in real pixels: one dark gap every scan_px rows
	if (scanlines > 0.001) {
		float s = 0.5 + 0.5 * cos(px.y / max(scan_px, 1.0) * 6.28318);
		col *= mix(1.0, 0.45 + 0.55 * s, scanlines);
		col *= 1.0 + scanlines * 0.2;   // win back some of the lost brightness
	}

	// RGB phosphor mask in real pixels
	if (mask > 0.001) {
		vec3 m = vec3(1.0);
		float x = px.x;
		if (mask_type == 1) {
			x += mod(floor(px.y / 2.0), 2.0) * 1.5;   // shadow mask: rows offset like a dot triad
		}
		int i = int(mod(floor(x), 3.0));
		m = i == 0 ? vec3(1.0, 0.3, 0.3) : (i == 1 ? vec3(0.3, 1.0, 0.3) : vec3(0.3, 0.3, 1.0));
		if (mask_type == 2) {
			// slot mask: a dark break every 4 rows, staggered per column triad
			float row = mod(px.y + floor(px.x / 3.0) * 2.0, 4.0);
			m *= row < 1.0 ? 0.35 : 1.0;
		}
		col *= mix(vec3(1.0), m * 1.6, mask);
	}

	// LED dots: a round light per cell, dark between
	if (led > 0.001) {
		float d = length(led_q - 0.5);
		col *= mix(1.0, smoothstep(0.5, 0.32, d) * 1.5, led);
	}

	// vignette, flicker, rolling bar
	if (vignette > 0.001) {
		vec2 v = g - 0.5;
		col *= mix(1.0, clamp(1.0 - dot(v, v) * 2.6, 0.0, 1.0), vignette);
	}
	if (flicker > 0.001) {
		col *= 1.0 - flicker * 0.1 * noise1(TIME * 28.0);
	}
	if (roll > 0.001) {
		float y = fract(TIME * 0.12);
		col *= 1.0 + roll * 0.14 * smoothstep(0.12, 0.0, abs(g.y - y));
	}

	// film grain, dust and scratches; tape noise
	if (grain > 0.001) {
		float n = hash12(px * 0.7 + floor(tm * 24.0) * 31.0) - 0.5;
		col += n * 0.16 * grain;
	}
	if (scratches > 0.001) {
		float f = floor(tm * 12.0);
		float sx = hash12(vec2(f, 3.0));
		col += step(abs(g.x - sx), 0.0012) * step(0.6, hash12(vec2(f, 9.0))) * 0.35 * scratches;
		float dust = step(0.9993, hash12(floor(px / 3.0) + f * 7.0));
		col = mix(col, vec3(0.05), dust * scratches);
	}
	if (vhs > 0.001) {
		float band = fract(tm * 0.07);
		float in_band = smoothstep(0.04, 0.0, abs(g.y - (1.0 - band)));
		col += (hash12(px + floor(tm * 30.0)) - 0.5) * (0.06 + 0.4 * in_band) * vhs;
	}

	// rounded corners and the bezel
	vec2 pix = (g - 0.5) * rect_px;                 // glass position in window units
	vec2 half_size = rect_px * 0.5;
	float rad = corner * min(rect_px.x, rect_px.y) * 0.08;
	vec2 q = abs(pix) - (half_size - rad);
	// signed distance to the rounded box: the min() term makes it negative inside. Without it a
	// square corner (rad 0) gave 0 everywhere inside, and the smoothstep below halved the picture.
	float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
	float glass = on_glass ? smoothstep(1.5, -1.5, sdf) : 0.0;
	vec3 frame_col = vec3(0.0);
	if (bezel > 0.001) {
		// dark plastic, a little lighter towards the top, with a soft reflection of the picture
		frame_col = mix(vec3(0.035), vec3(0.09), 1.0 - UV.y);
		if (has_video) {
			frame_col += blur_video(clamp(fit_uv(UV, 1), vec2(0.0), vec2(1.0)), 0.08) * 0.07;
		}
	}
	col = mix(frame_col, col, glass);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
