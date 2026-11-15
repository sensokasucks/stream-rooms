shader_type sky;
// Forge Hall: the sky seen through the slanted windows, for every time of day, with a dark
// fantasy look: the hall stands high in the mountains. Built in layers from the back to the front:
//   1. the sky's own colour for the hour (deep blue day, warm band at sunrise and sunset, near
//      black night with a trace of violet),
//   2. night: purple and blue nebula clouds with dark dust lanes, and stars: a fine field,
//      brighter ones and a few round bright ones with a soft glow. Every star flickers at its own
//      speed. With `twinkle` at 0 (photosensitive-safe mode) they are steady,
//   3. the sun (disc, glow, faint rays) and the moon (a pale disc with marks, a halo),
//   4. high, thin, streaky cloud that drifts slowly, then low, puffy cloud that drifts faster and
//      slowly changes shape, lit from the sun's or the moon's side,
//   5. snow-capped mountains all round: a pale, hazy range far off and a closer, taller one in
//      front, each peak lit on one side, snow from a ragged line upwards,
//   6. below them a sea of cloud filling the valleys (the hall is above it).
// rooms/forge_hall/forge_hall_room.gd (_apply_time) sets every uniform from the Time of day
// setting and the room's Clouds / Nebula / Stars / Mountains sliders.
// The clouds and the cloud sea read their shapes from a noise picture
// (textures/sky_noise.png: r = a cloud's body, g = crumbly detail, b = long streaks; made by
// rooms/campfire/textures/make_textures.py, sky_noise(), and shared in look with the Lakeside
// Campfire's sky). Reading a picture is far cheaper than working noise out for every pixel (the
// old version of this sky did that) and looks the same on every graphics card.
// Cost: a handful of texture reads per sky pixel; the nebula (night only) is layered maths noise,
// the dearest part. Clouds, nebula and stars are each skipped when their amount is 0, which is
// the cheap setting for a slow graphics card.

// Unit vectors pointing AT the sun and the moon, in world space.
uniform vec3 sun_dir = vec3(-0.6, 0.7, -0.3);
uniform vec3 moon_dir = vec3(0.6, -0.7, 0.3);
// 0 = night, 1 = full day.
uniform float day : hint_range(0.0, 1.0) = 1.0;
// 0..1: how much sunrise / sunset colour the horizon has.
uniform float dusk : hint_range(0.0, 1.0) = 0.0;
uniform float star_amount : hint_range(0.0, 2.0) = 1.0;
// 0 = steady stars (photosensitive-safe mode), 1 = they twinkle.
uniform float twinkle : hint_range(0.0, 1.0) = 1.0;
// The shapes of the clouds, the nebula and the cloud sea (textures/sky_noise.png).
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
// How much of the sky the clouds cover: 0 = none (and no cost), 1 = the room's look, 2 = heavy.
uniform float cloud_amount : hint_range(0.0, 2.0) = 1.0;
// How fast the clouds drift (0 = they stand still).
uniform float cloud_speed : hint_range(0.0, 4.0) = 1.0;
// How strong the night's nebula clouds are: 0 = none (and no cost), 1 = the room's look.
uniform float nebula_amount : hint_range(0.0, 2.0) = 1.0;
// How tall the mountains stand: 0 = none (only the cloud sea), 1 = the room's look, 2 = towering.
uniform float mountain_amount : hint_range(0.0, 2.0) = 1.0;
// Overall brightness (the room lowers it a little so the windows don't wash the room out).
uniform float exposure = 1.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// A random number 0..1 for a whole number n (no sin(): that repeats badly on some graphics cards).
float hash1(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

// Smooth value noise (the sun's rays, the moon's marks and, through fbm, the nebula).
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Layered noise (each layer twice as fine and half as strong), 0..1. The nebula's wisps.
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

// Smooth noise round the compass. az: the direction's angle in radians; freq: bumps per turn
// (a whole number, so the outline joins up where the angle wraps).
float ring_noise(float az, float freq, float seed) {
	float x = (az / 6.2831853 + 0.5) * freq;
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(mod(i, freq) + seed * 7.13), hash1(mod(i + 1.0, freq) + seed * 7.13), f);
}

// A mountain range's outline: how far up (the true view direction's y) the rock reaches in the
// direction az. Creased noise gives sharp, jagged peaks; `massif` raises whole groups of them
// and leaves gaps between. seed picks a different range; base and tall are its foot and how far
// its highest peaks rise above that.
float range_height(float az, float seed, float base, float tall) {
	float crease_a = 1.0 - abs(2.0 * ring_noise(az, 13.0, seed + 1.0) - 1.0);
	float crease_b = 1.0 - abs(2.0 * ring_noise(az, 37.0, seed + 2.0) - 1.0);
	float crease_c = 1.0 - abs(2.0 * ring_noise(az, 97.0, seed + 3.0) - 1.0);
	float massif = ring_noise(az, 5.0, seed + 4.0);
	return base + tall * (0.25 + 0.75 * massif) * (0.62 * crease_a + 0.28 * crease_b + 0.1 * crease_c);
}

// Draws one mountain range over the colour c and hands the result back. az: the compass
// direction (moved by a different amount for each range, so they don't line up); seed, base,
// tall: as range_height; rock: the bare rock's colour in full daylight; snow_depth: how far
// down from the outline the snow reaches on the highest peaks (in view-direction y); haze_col
// and haze: the air in front of the range (more for the far one); light_side: which side of a
// slope faces the sun or the moon. Uses the sky's day, dusk and cloud_noise uniforms.
vec3 draw_range(vec3 c, vec3 v, float az, float seed, float base, float tall, vec3 rock, float snow_depth, vec3 haze_col, float light_side, float haze) {
	float h = range_height(az, seed, base, tall);
	if (v.y > h + 0.004) {
		return c;
	}
	// which way the slope faces here: compare the outline a little either side. Further down
	// from the outline the slope is read over a wider stretch (az +- depth), so each peak's
	// lit and shaded faces spread out and soften towards its foot instead of running straight
	// down as stripes.
	// (two outline reads per pixel: this runs for every pixel of rock, also when the sky's
	// lighting picture is redrawn)
	float w = 0.012 + max(h - v.y, 0.0) * 0.9;
	float lean = (range_height(az + w, seed, base, tall) - range_height(az - w, seed, base, tall)) / (2.0 * w) * 0.528;
	float lit = clamp(0.5 - lean * light_side * 1.6, 0.0, 1.0);
	// the rock's own blotches and ledges (the noise picture, the same scale both ways)
	vec2 rp = vec2(az * 3.0 + seed, v.y * 3.0);
	float grain = textureLod(cloud_noise, rp, 0.0).g * 0.6 + textureLod(cloud_noise, rp * 3.1, 0.0).r * 0.4;
	// gullies running down the faces: the streak noise, stretched upright
	float gully = textureLod(cloud_noise, vec2(rp.y * 0.5, rp.x * 2.0), 0.0).b;
	grain = grain * (0.85 + 0.3 * gully);
	vec3 col = rock * mix(0.45, 1.15, lit) * (0.75 + 0.5 * grain);
	// snow from a ragged line down from each peak's top, deeper on the tall peaks, patchy where
	// the rock's blotches are dark (steep ledges hold less snow)
	float tallness = clamp((h - base) / max(tall, 0.001), 0.0, 1.0);
	float snow_line = h - snow_depth * (0.25 + 0.75 * tallness) * (0.7 + 0.6 * ring_noise(az, 71.0, seed + 9.0));
	float snow = smoothstep(snow_line - 0.01, snow_line + 0.01, v.y + (grain - 0.5) * 0.05);
	col = mix(col, mix(vec3(0.5, 0.57, 0.76), vec3(0.97, 0.97, 1.0), lit), snow);
	// the time of day: dark blue-grey at night, warm at dusk
	col *= mix(vec3(0.09, 0.1, 0.17), vec3(1.0), day);
	col = mix(col, col * vec3(1.0, 0.62, 0.52), dusk * 0.6 * day);
	// air in front, thicker towards the foot of the range (it stands in the valley haze)
	float foot = 1.0 - smoothstep(base, base + 0.12, v.y);
	col = mix(col, haze_col, clamp(haze + foot * 0.45, 0.0, 1.0));
	return mix(c, col, smoothstep(h + 0.002, h - 0.002, v.y));
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

// How much a star's light flickers right now, around 1: two sine waves at speeds of its own
// (h = the star's random number), as air shimmer does. `amount` 0 = steady.
// t = TIME (handed in: the simple renderer only knows TIME inside sky() itself).
float flicker(float h, float amount, float t) {
	float a = sin(t * (2.1 + h * 3.7) + h * 311.0);
	float b = sin(t * (5.3 + fract(h * 17.0) * 4.0) + h * 97.0);
	return 1.0 + amount * (0.38 * a + 0.22 * b);
}

void sky() {
	// v: the true view direction (the sun, the moon and the mountains use it). d: the same
	// direction with the horizon pushed down about 30 degrees, used for the sky's colours, stars,
	// nebula and clouds: the hall's windows are high and its cameras often look level or down
	// through them, so the sky has to carry on well below eye level, as if the hall stood on a peak.
	vec3 v = normalize(EYEDIR);
	vec3 d = normalize(vec3(v.x, v.y + 0.5, v.z));
	float up = clamp(d.y, 0.0, 1.0);
	float night = 1.0 - day;
	float az = atan(v.x, -v.z);

	// ── 1: the sky's own colour ──
	vec3 top = mix(vec3(0.006, 0.004, 0.022), vec3(0.07, 0.25, 0.72), day);
	vec3 hor = mix(vec3(0.02, 0.018, 0.06), vec3(0.42, 0.62, 0.9), day);
	// sunrise / sunset: the horizon warms, most of all on the sun's side
	vec2 flat_d = normalize(d.xz + vec2(0.0001));
	vec2 flat_s = normalize(sun_dir.xz + vec2(0.0001));
	float toward = pow(max(dot(flat_d, flat_s), 0.0), 2.0);
	hor = mix(hor, mix(vec3(0.85, 0.45, 0.5), vec3(1.0, 0.42, 0.16), toward), dusk * (0.35 + 0.65 * toward));
	top = mix(top, vec3(0.26, 0.16, 0.42), dusk * 0.4);
	vec3 c = mix(hor, top, pow(up, 0.45));
	float above = smoothstep(0.0, 0.15, d.y);       // fades everything in the sky out at the horizon

	float sd = dot(v, sun_dir);
	float sun_up = clamp(sun_dir.y * 6.0 + 0.4, 0.0, 1.0);
	vec3 sun_col = mix(vec3(1.0, 0.5, 0.2), vec3(1.0, 0.95, 0.85), clamp(sun_dir.y * 2.5, 0.0, 1.0));
	float md = dot(v, moon_dir);
	float moon_up = clamp(moon_dir.y * 6.0 + 0.4, 0.0, 1.0);
	// where this direction meets a flat sheet high overhead (the clouds and the nebula are
	// drawn on it); the +0.22 flattens it toward the horizon
	vec2 sheet = d.xz / (d.y + 0.22);
	// near the horizon the sheet is seen at a grazing angle: read the noise picture blurred
	// there (a mip level) instead of sparkling
	float soft = 3.0 * (1.0 - smoothstep(0.0, 0.45, d.y));

	// ── 2: night: nebula and stars ──
	if (night > 0.01 && d.y > 0.0) {
		vec3 glow = vec3(0.0);
		float dust = 0.0;
		if (nebula_amount > 0.001) {
			// wispy clouds: noise bent by more noise, kept only where it is strongest, in
			// two colours that drift into each other; a second noise cuts dark dust lanes.
			// (Worked out per pixel, not read from the cloud picture: drawn from that picture
			// it looked like the clouds in purple. Night only, and skipped at Nebula 0%.)
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
		vec3 stars = vec3(0.0);
		if (star_amount > 0.001) {
			vec2 s1 = star_layer(d, 420.0, 0.972);
			vec2 s2 = star_layer(d, 190.0, 0.991);
			// every star flickers at its own speed; near the horizon (more air) more
			float air = twinkle * (0.55 + 0.45 * (1.0 - up));
			float tw1 = flicker(s1.y, air * 0.8, TIME);
			float tw = flicker(s2.y, air, TIME);
			vec3 tint = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.86, 0.78), fract(s2.y * 91.0));
			tint = mix(tint, vec3(0.7, 0.85, 1.0), clamp((tw - 1.0) * 0.8, 0.0, 0.5));   // bluer as it flares
			stars = vec3(0.8, 0.82, 1.0) * s1.x * (0.25 + 0.5 * fract(s1.y * 57.0)) * tw1 + tint * s2.x * 1.7 * tw;
			// a few brighter stars: a small round point with a faint soft glow
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
				float r2 = a * a + b * b;
				float core = exp(-r2 * 2600.0);
				float halo = exp(-r2 * 260.0);
				float tb = flicker(hb, air * 0.6, TIME);
				vec3 big = mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.82, 0.6), step(0.975, hb));
				stars += big * (core * 2.2 + halo * 0.22) * tb;
			}
		}
		c += (stars * 1.6 * (1.0 - dust * 0.7) * star_amount + glow) * night * above;
	}

	// ── 3: the sun: a bright disc, a wide soft glow and faint rays fanning out, fading as it sets ──
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
	// the moon: a pale disc with darker marks, and a halo
	float disc = smoothstep(0.9989, 0.9993, md);
	float marks = 0.75 + 0.25 * noise3((v - moon_dir) * 140.0);
	c = mix(c, vec3(0.85, 0.88, 0.95) * marks * 1.3, disc * moon_up);
	c += vec3(0.45, 0.45, 0.8) * pow(max(md, 0.0), 220.0) * 0.25 * moon_up * (1.0 - disc);
	c += vec3(0.3, 0.25, 0.6) * pow(max(md, 0.0), 24.0) * 0.06 * moon_up * night;

	// which light the clouds and the mountains are lit by
	vec2 lflat = normalize(mix(moon_dir.xz, sun_dir.xz, step(0.0, sun_dir.y)) + vec2(0.0001));

	// ── 4: clouds, drawn over the sun, the moon and the stars ──
	if (cloud_amount > 0.001 && d.y > 0.0) {
		float wind = TIME * cloud_speed;
		// high, thin, streaky cloud
		vec2 uvh = d.xz / (d.y + 0.12);
		float wisps = textureLod(cloud_noise, uvh * vec2(0.035, 0.09) + vec2(wind * 0.0002, wind * 0.00045), soft).b;
		wisps = wisps * 0.75 + 0.25 * textureLod(cloud_noise, uvh * 0.21 + vec2(wind * 0.0005, 0.3), soft).g;
		float high = smoothstep(0.5, 0.82, wisps) * min(cloud_amount, 1.0) * 0.5;
		vec3 high_col = mix(vec3(0.06, 0.065, 0.11), vec3(1.0), day);
		high_col = mix(high_col, vec3(1.0, 0.62, 0.55), dusk * 0.85);
		c = mix(c, high_col, high * smoothstep(0.03, 0.25, d.y));
		// low, puffy cloud: two copies of the body noise at different sizes drift at different
		// speeds, so the clouds slowly change shape as they cross the sky; the detail noise
		// eats their edges into puffs
		vec2 cp = sheet * 0.085 + vec2(wind * 0.0009, wind * 0.00035);
		vec2 cp2 = sheet * 0.17 + vec2(0.37, 0.11) + vec2(wind * 0.0014, -wind * 0.0003);
		float n = textureLod(cloud_noise, cp, soft).r * 0.62 + textureLod(cloud_noise, cp2, soft).r * 0.38;
		float crumbs = textureLod(cloud_noise, sheet * 0.5 + vec2(wind * 0.003, wind * 0.0012), soft).g;
		// fewer clouds at night, so the nebula shows between them
		float cover = 0.64 - 0.28 * cloud_amount * mix(0.6, 1.0, day);
		n -= (1.0 - crumbs) * 0.13 * (1.0 - smoothstep(cover, cover + 0.3, n));
		float dens = smoothstep(cover, cover + 0.06, n);
		if (dens > 0.001) {
			// lit side: denser here than a step towards the light = this side faces it
			float n2 = textureLod(cloud_noise, cp + lflat * 0.02, soft).r * 0.62 + textureLod(cloud_noise, cp2 + lflat * 0.02, soft).r * 0.38;
			float lit = clamp(0.62 + (n - n2) * 11.0, 0.0, 1.0);
			float thick = smoothstep(cover + 0.05, cover + 0.35, n);
			vec3 bright = mix(vec3(0.075, 0.07, 0.13), vec3(1.0, 1.0, 1.0), day);
			vec3 shade = mix(vec3(0.012, 0.012, 0.03), vec3(0.36, 0.42, 0.56), day);
			// sunset: peach tops on the sun's side, pink away from it, lavender undersides
			bright = mix(bright, mix(vec3(1.0, 0.6, 0.62), vec3(1.0, 0.62, 0.32), toward), dusk * 0.85);
			shade = mix(shade, vec3(0.36, 0.2, 0.38), dusk * 0.85);
			vec3 cc = mix(shade, bright, lit * (1.0 - thick * 0.45));
			cc += bright * (1.0 - smoothstep(0.0, 0.5, thick)) * 0.18;           // bright thin rims
			cc += sun_col * pow(max(sd, 0.0), 14.0) * (1.0 - thick) * 0.7 * sun_up;
			cc += vec3(0.25, 0.27, 0.4) * pow(max(md, 0.0), 30.0) * (1.0 - thick) * moon_up * night;
			c = mix(c, cc, dens * smoothstep(0.02, 0.2, d.y) * 0.95);
		}
	}

	// ── 5: the mountains (true view direction: they rise round the hall's own peak) ──
	vec3 haze_col = mix(hor, vec3(0.6, 0.66, 0.76) * (0.05 + 0.95 * day), 0.4);
	float light_az = day > 0.3 ? atan(sun_dir.x, -sun_dir.z) : atan(moon_dir.x, -moon_dir.z);
	float light_side = sin(light_az - az);
	// (below -0.05 the sea of cloud covers them completely: skip the work there)
	if (mountain_amount > 0.001 && v.y > -0.05) {
		// back range: far off and pale, its peaks reach about 12 degrees up
		c = draw_range(c, v, az, 11.0, -0.02, 0.24 * mountain_amount, vec3(0.26, 0.29, 0.4), 0.075, haze_col, light_side, 0.42);
		// front range: closer, taller and darker, peaks up to about 25 degrees
		c = draw_range(c, v, az + 2.1, 23.0, -0.06, 0.5 * mountain_amount, vec3(0.24, 0.23, 0.25), 0.13, haze_col, light_side, 0.15);
	}

	// ── 6: the sea of cloud filling the valleys below ──
	float sea_top = -0.03;
	if (v.y < sea_top + 0.04) {
		// a flat sheet of cloud below: where this direction meets it; read blurred (a mip
		// level) towards the horizon, where the sheet is seen at a grazing angle
		vec2 suv = v.xz / (0.08 - v.y);
		float sea_soft = 3.5 * (1.0 - smoothstep(0.0, 0.5, -v.y));
		vec2 drift = vec2(TIME * cloud_speed * 0.0004, TIME * cloud_speed * 0.00015);
		float puff = textureLod(cloud_noise, suv * 0.022 + drift, sea_soft).r * 0.75 + textureLod(cloud_noise, suv * 0.08 + drift * 1.6, sea_soft).g * 0.25;
		vec3 sea_lit = mix(vec3(0.08, 0.09, 0.15), vec3(0.95, 0.95, 1.0), day);
		sea_lit = mix(sea_lit, mix(vec3(0.9, 0.6, 0.65), vec3(1.0, 0.62, 0.35), toward), dusk * 0.8);
		// tops of the billows lit, the dips between them in shade
		vec3 sea = mix(sea_lit * vec3(0.5, 0.54, 0.64), sea_lit, smoothstep(0.3, 0.8, puff));
		sea = mix(sea, haze_col, 0.35 * (1.0 - smoothstep(0.0, 0.4, -v.y)));
		c = mix(c, sea, smoothstep(sea_top + 0.04, sea_top - 0.02, v.y));
	}
	COLOR = c * exposure;
}
