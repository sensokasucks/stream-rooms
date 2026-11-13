shader_type sky;
// Forge Hall: the sky seen through the slanted windows, for every time of day, with a dark
// fantasy look. By day a deep blue sky with billowing clouds lit by the sun (bright tops, grey
// undersides, a silver edge near the sun) and soft rays fanning out from it; a warm band and
// pink-orange clouds at sunrise and sunset; by night a field of stars with a few bright ones
// that sparkle, and purple and blue nebula clouds with dark dust lanes. The sun and the moon
// are discs. rooms/forge_hall/forge_hall_room.gd (_apply_time) sets every uniform from the
// Time of day setting and the room's Clouds / Nebula / Stars sliders. Nothing here moves on its
// own except the clouds' slow drift (cloud_speed) and a slow twinkle of the stars (`twinkle`,
// set to 0 in photosensitive-safe mode).
// Cost: the clouds and the nebula are layered noise, worked out for every sky pixel on
// screen. Each is skipped entirely when its amount is 0, which is the cheap setting for a
// slow graphics card.

// Unit vectors pointing AT the sun and the moon, in world space.
uniform vec3 sun_dir = vec3(-0.6, 0.7, -0.3);
uniform vec3 moon_dir = vec3(0.6, -0.7, 0.3);
// 0 = night, 1 = full day.
uniform float day : hint_range(0.0, 1.0) = 1.0;
// 0..1: how much sunrise / sunset colour the horizon has.
uniform float dusk : hint_range(0.0, 1.0) = 0.0;
uniform float star_amount : hint_range(0.0, 2.0) = 1.0;
uniform float twinkle : hint_range(0.0, 1.0) = 1.0;
// How much of the sky the clouds cover: 0 = none (and no cost), 1 = the room's look, 2 = heavy.
uniform float cloud_amount : hint_range(0.0, 2.0) = 1.0;
// How fast the clouds drift (0 = they stand still).
uniform float cloud_speed : hint_range(0.0, 4.0) = 1.0;
// How strong the night's nebula clouds are: 0 = none (and no cost), 1 = the room's look.
uniform float nebula_amount : hint_range(0.0, 2.0) = 1.0;
// Overall brightness (the room lowers it a little so the windows don't wash the room out).
uniform float exposure = 1.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise.
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Layered noise (each layer twice as fine and half as strong), 0..1.
float fbm(vec3 p, int layers) {
	float sum = 0.0;
	float amp = 0.5;
	float total = 0.0;
	for (int i = 0; i < layers; i++) {
		sum += noise3(p) * amp;
		total += amp;
		p = p * 2.03 + vec3(11.7, 3.1, 7.9);
		amp *= 0.5;
	}
	return sum / total;
}

// One layer of stars: a grid of cells over the sky (`scale` cells across a unit of direction),
// a soft dot in the few cells whose random number is above `rare`. Returns brightness in x and
// the cell's random number in y (for the tint and the twinkle).
vec2 star_layer(vec3 d, float scale, float rare) {
	vec3 p = d * scale;
	float h = hash3(floor(p));
	float dot_ = smoothstep(0.42, 0.05, length(fract(p) - 0.5));
	return vec2(step(rare, h) * dot_, h);
}

void sky() {
	// v: the true view direction (the sun and the moon use it). d: the same direction with the
	// horizon pushed down about 30 degrees, used for the sky's colours, stars, nebula and
	// clouds: the hall's windows are high and its cameras often look level or down through
	// them, so the sky has to carry on well below eye level, as if the hall stood on a peak.
	vec3 v = normalize(EYEDIR);
	vec3 d = normalize(vec3(v.x, v.y + 0.5, v.z));
	float up = clamp(d.y, 0.0, 1.0);
	float night = 1.0 - day;
	// the day sky is a deeper, moodier blue than a postcard's; the night is near black with a
	// trace of violet
	vec3 top = mix(vec3(0.006, 0.004, 0.022), vec3(0.07, 0.25, 0.72), day);
	vec3 hor = mix(vec3(0.02, 0.018, 0.06), vec3(0.42, 0.62, 0.9), day);
	// sunrise / sunset: the horizon warms, most of all on the sun's side
	vec2 flat_d = normalize(d.xz + vec2(0.0001));
	vec2 flat_s = normalize(sun_dir.xz + vec2(0.0001));
	float toward = pow(max(dot(flat_d, flat_s), 0.0), 2.0);
	hor = mix(hor, vec3(1.0, 0.38, 0.14), dusk * (0.3 + 0.7 * toward));
	top = mix(top, vec3(0.26, 0.16, 0.42), dusk * 0.4);
	vec3 c = mix(hor, top, pow(up, 0.45));
	if (d.y < 0.0) {
		c = mix(hor * 0.5, vec3(0.012), clamp(-d.y * 5.0, 0.0, 1.0));    // below the horizon: dark ground
	}
	float above = smoothstep(0.0, 0.15, d.y);       // fades everything in the sky out at the horizon

	float sd = dot(v, sun_dir);
	float sun_up = clamp(sun_dir.y * 6.0 + 0.4, 0.0, 1.0);
	vec3 sun_col = mix(vec3(1.0, 0.5, 0.2), vec3(1.0, 0.95, 0.85), clamp(sun_dir.y * 2.5, 0.0, 1.0));
	float md = dot(v, moon_dir);
	float moon_up = clamp(moon_dir.y * 6.0 + 0.4, 0.0, 1.0);

	// ── night: nebula and stars ──
	if (night > 0.01 && d.y > 0.0) {
		vec3 glow = vec3(0.0);
		float dust = 0.0;
		if (nebula_amount > 0.001) {
			// wispy clouds: noise bent by more noise, kept only where it is strongest, in
			// two colours that drift into each other; a second noise cuts dark dust lanes
			vec3 q = d * 2.1;
			vec3 bend = vec3(fbm(q + vec3(3.1, 0.0, 1.7), 3), fbm(q + vec3(8.3, 2.8, 0.0), 3), fbm(q + vec3(0.0, 5.2, 9.1), 3)) - 0.5;
			float n = fbm(q + bend * 2.4, 5);
			float wisp = pow(smoothstep(0.42, 0.78, n), 1.6);
			float veil = smoothstep(0.3, 0.75, n) * 0.25;                 // a faint haze round the wisps
			float which = fbm(d * 1.3 + vec3(40.0, 17.0, 5.0), 3);
			vec3 neb = mix(vec3(0.42, 0.16, 0.9), vec3(0.1, 0.24, 0.95), smoothstep(0.38, 0.62, which));
			neb = mix(neb, vec3(0.85, 0.6, 1.0), wisp * wisp * 0.5);      // the brightest threads go pale
			dust = smoothstep(0.52, 0.72, fbm(q * 1.9 + bend * 1.5 + vec3(21.0, 4.0, 13.0), 4)) * 0.8;
			glow = neb * (wisp * 1.2 + veil * 0.35) * (1.0 - dust) * nebula_amount;
		}
		// stars: a dense fine layer, a sparser brighter one, and a few big ones with a cross of
		// light (four points); fewer show through the dust lanes
		vec2 s1 = star_layer(d, 420.0, 0.975);
		vec2 s2 = star_layer(d, 190.0, 0.992);
		float tw = 1.0 - twinkle * 0.35 * (0.5 + 0.5 * sin(TIME * (0.6 + s2.y * 1.7) + s2.y * 40.0));
		vec3 tint = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.86, 0.78), fract(s2.y * 91.0));
		vec3 stars = vec3(0.8, 0.82, 1.0) * s1.x * (0.25 + 0.5 * fract(s1.y * 57.0)) + tint * s2.x * 1.7 * tw;
		vec3 p = d * 9.0;
		vec3 cell = floor(p);
		float hb = hash3(cell + vec3(5.0));
		if (hb > 0.9) {
			// where the star sits in its cell, and how far this pixel is from it across the sky
			vec3 off = fract(p) - 0.5 - (vec3(hash3(cell + vec3(1.0)), hash3(cell + vec3(2.0)), hash3(cell + vec3(3.0))) - 0.5) * 0.5;
			vec3 t1 = normalize(cross(d, vec3(0.0, 1.0, 0.001)));
			vec3 t2 = cross(d, t1);
			float a = dot(off, t1);
			float b = dot(off, t2);
			float core = exp(-(a * a + b * b) * 900.0);
			float cross_ = exp(-abs(a) * 90.0) * exp(-abs(b) * 9.0) + exp(-abs(b) * 90.0) * exp(-abs(a) * 9.0);
			float tb = 1.0 - twinkle * 0.3 * (0.5 + 0.5 * sin(TIME * (0.4 + hb * 1.3) + hb * 60.0));
			vec3 big = mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.82, 0.6), step(0.975, hb));
			stars += big * (core * 3.0 + cross_ * 0.7) * tb;
		}
		c += (stars * 1.6 * (1.0 - dust * 0.7) * star_amount + glow) * night * above;
	}

	// ── the sun: a bright disc, a wide soft glow and faint rays fanning out, fading as it sets ──
	c += sun_col * smoothstep(0.9990, 0.9995, sd) * 5.0 * sun_up;
	c += sun_col * pow(max(sd, 0.0), 260.0) * 0.6 * sun_up;
	c += sun_col * pow(max(sd, 0.0), 30.0) * 0.16 * sun_up;
	c += sun_col * pow(max(sd, 0.0), 6.0) * 0.05 * sun_up * day;
	if (sd > 0.55 && sun_up > 0.0) {
		// rays: brightness that changes with the angle round the sun
		vec3 s1v = normalize(cross(sun_dir, vec3(0.0, 1.0, 0.001)));
		vec3 s2v = cross(sun_dir, s1v);
		float ang = atan(dot(v, s2v), dot(v, s1v));
		float ray = noise3(vec3(ang * 7.0, 3.0, 0.0)) * noise3(vec3(ang * 19.0, 9.0, 4.0));
		c += sun_col * ray * smoothstep(0.55, 0.98, sd) * (1.0 - smoothstep(0.985, 0.999, sd)) * 0.32 * sun_up * day;
	}
	// ── the moon: a pale disc with darker marks, and a halo ──
	float disc = smoothstep(0.9989, 0.9993, md);
	float marks = 0.75 + 0.25 * noise3((v - moon_dir) * 140.0);
	c = mix(c, vec3(0.85, 0.88, 0.95) * marks * 1.3, disc * moon_up);
	c += vec3(0.45, 0.45, 0.8) * pow(max(md, 0.0), 220.0) * 0.25 * moon_up * (1.0 - disc);
	c += vec3(0.3, 0.25, 0.6) * pow(max(md, 0.0), 24.0) * 0.06 * moon_up * night;

	// ── clouds: a layer high overhead, drawn over the sun, the moon and the stars ──
	if (cloud_amount > 0.001 && d.y > 0.0) {
		// where this direction meets the layer (the +0.22 flattens it toward the horizon)
		vec2 uv = d.xz / (d.y + 0.22);
		vec3 cp = vec3(uv * 1.15, 0.0) + vec3(TIME * 0.004 * cloud_speed, 0.0, TIME * 0.0015 * cloud_speed);
		// big shapes, with finer noise eating into their edges so they billow instead of blur
		float n = fbm(cp, 5) + (fbm(cp * 4.3 + vec3(7.0, 2.0, 0.0), 3) - 0.5) * 0.14;
		// fewer clouds at night, so the nebula shows between them
		float cover = 0.62 - 0.17 * cloud_amount * mix(0.55, 1.0, day);
		float dens = smoothstep(cover, cover + 0.07, n);
		if (dens > 0.001) {
			// lit from the sun's (or the moon's) side: compare with the cloud a step toward it
			vec2 lflat = normalize(mix(moon_dir.xz, sun_dir.xz, step(0.0, sun_dir.y)) + vec2(0.0001));
			float n2 = fbm(cp + vec3(lflat * 0.09, 0.0), 5);
			float lit = clamp(0.6 + (n - n2) * 5.0, 0.0, 1.0);
			float thick = smoothstep(cover + 0.05, cover + 0.35, n);          // the deep middle of a cloud is darker
			vec3 bright = mix(vec3(0.075, 0.07, 0.13), vec3(1.0, 1.0, 1.0), day);
			vec3 shade = mix(vec3(0.012, 0.012, 0.03), vec3(0.3, 0.36, 0.5), day);
			bright = mix(bright, vec3(1.0, 0.55, 0.3), dusk * 0.8);
			shade = mix(shade, vec3(0.3, 0.14, 0.26), dusk * 0.8);
			vec3 cc = mix(shade, bright, lit * (1.0 - thick * 0.45));
			// a bright edge on thin cloud near the sun, a pale one near the moon
			cc += sun_col * pow(max(sd, 0.0), 14.0) * (1.0 - thick) * 0.7 * sun_up;
			cc += vec3(0.25, 0.27, 0.4) * pow(max(md, 0.0), 30.0) * (1.0 - thick) * moon_up * night;
			c = mix(c, cc, dens * smoothstep(0.02, 0.2, d.y) * 0.95);
		}
	}
	COLOR = c * exposure;
}
