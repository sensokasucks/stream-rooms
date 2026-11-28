shader_type sky;
// Route 22 (the Drive-In and the Cruise): the whole desert sky, in layers from the back to the
// front. Layers 1, 2 and 4-6 are the Lakeside Campfire's sky (rooms/campfire/camp_sky.gdshader;
// keep fixes in step), the rest is the desert's own:
//   1. the sky's colour for the hour, warm at sunrise and sunset,
//   2. stars, the Milky Way and shooting stars (none while `twinkle` is 0: photosensitive-safe),
//   3. a rainbow opposite the sun after rain (`rainbow`),
//   4. the sun and the moon,
//   5. high streaky cloud and 6. the low puffy cloud deck (`cloud_amount`; the Cloud deck
//      weather is the reference photo's orange sunset ceiling), darker in a storm (`storm`) and
//      lit from inside by lightning (`flash`, with a bolt at `bolt_az`),
//   7. far mesas, blue with distance, 8. nearer red buttes and mesas with layered cliffs, the
//      side towards the sun lit,
//   9. the desert floor below the horizon, and the dust (`dust`: the Dust storm weather browns
//      everything out from the horizon up).
// rooms/route22/r22_desert.gd (_apply_sky) sets every uniform from the Time of day, the
// Weather, the Clouds / Stars sliders and the lightning. In the Cruise the real rocks beside the
// road slide past in front of this; the skyline itself is far enough away to stay put.
// "Ahead" is -Z: the Cruise drives that way and the Drive-In's screen faces back from it, so the
// sun sets ahead of the car and behind the drive-in screen.

uniform vec3 sun_dir = vec3(0.6, 0.7, 0.3);
uniform vec3 moon_dir = vec3(-0.3, 0.6, -0.7);
uniform float day : hint_range(0.0, 1.0) = 1.0;
uniform float dusk : hint_range(0.0, 1.0) = 0.0;
uniform float star_amount : hint_range(0.0, 2.0) = 1.0;
uniform float twinkle : hint_range(0.0, 1.0) = 1.0;
// The clouds' shapes (rooms/campfire/textures/sky_noise.png; r = bodies, g = crumbs, b = streaks).
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_amount : hint_range(0.0, 2.0) = 1.0;
uniform float cloud_speed = 1.0;
// 0..1: a thunderstorm's dark, heavy cloud.
uniform float storm : hint_range(0.0, 1.0) = 0.0;
// 0..1: lightning lighting the clouds right now (r22_desert.gd: capped in safe mode).
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// Where the lightning bolt comes down (radians round the horizon, 0 = ahead).
uniform float bolt_az = 0.6;
// 0..1: the rainbow after rain.
uniform float rainbow : hint_range(0.0, 1.0) = 0.0;
// 0..1: dust in the air (Dust storm) and its colour.
uniform float dust : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dust_color = vec3(0.62, 0.38, 0.22);
// The ordinary desert haze low on the horizon (0..1).
uniform float haze : hint_range(0.0, 1.0) = 0.35;
uniform float exposure = 1.0;
// 0 = the desert (far mesas and buttes on the horizon, a red desert floor below it).
// 1 = green country (Route 81, rooms/route81): no mesas, and blue-grey distance haze where the
// desert floor was; that room draws its own far ridges as a mesh (r81_land.gd build_backdrop).
uniform float land : hint_range(0.0, 1.0) = 0.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

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

vec2 star_layer(vec3 d, float scale, float rare) {
	vec3 p = d * scale;
	float h = hash3(floor(p));
	float dot_ = smoothstep(0.42, 0.05, length(fract(p) - 0.5));
	return vec2(step(rare, h) * dot_, h);
}

float flicker(float h, float amount, float t) {
	float a = sin(t * (2.1 + h * 3.7) + h * 311.0);
	float b = sin(t * (5.3 + fract(h * 17.0) * 4.0) + h * 97.0);
	return 1.0 + amount * (0.38 * a + 0.22 * b);
}

// Smooth noise round the compass: az in radians, freq = bumps per turn (whole, so it joins up).
float ring_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}
float ring_noise(float az, float freq, float seed) {
	float x = (az / 6.2831853 + 0.5) * freq;
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(ring_hash(mod(i, freq) + seed), ring_hash(mod(i + 1.0, freq) + seed), f);
}

// The far mesas: long flat tops with steep sides (a noise cut off sharply) on a low rolling base.
float far_mesas(float az) {
	float base = 0.012 + 0.012 * ring_noise(az, 19.0, 4.0);
	float n = ring_noise(az, 13.0, 8.0) * 0.75 + ring_noise(az, 41.0, 2.0) * 0.25;
	float top = 0.03 + 0.022 * ring_noise(az, 5.0, 9.0) + 0.002 * ring_noise(az, 150.0, 3.0);
	return base + smoothstep(0.52, 0.56, n) * top;
}

// The nearer buttes: narrower, taller blocks with a sloping skirt (talus) round their feet.
float near_buttes(float az) {
	float n = ring_noise(az, 29.0, 31.0) * 0.8 + ring_noise(az, 87.0, 12.0) * 0.2;
	float tall = 0.045 + 0.04 * ring_noise(az, 7.0, 17.0);
	float block = smoothstep(0.64, 0.67, n) * tall;
	float skirt = smoothstep(0.5, 0.67, n) * 0.022;
	return 0.006 + max(block, skirt) + 0.005 * ring_noise(az, 61.0, 5.0);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	float night = 1.0 - day;
	float az = atan(d.x, -d.z);                       // 0 = straight ahead down the road (-Z)

	// ── layer 1: the sky's own colour ──
	vec3 top = mix(vec3(0.004, 0.006, 0.02), vec3(0.08, 0.27, 0.72), day);
	vec3 hor = mix(vec3(0.015, 0.02, 0.05), vec3(0.5, 0.68, 0.92), day);
	// sunrise / sunset: the horizon warms, most of all on the sun's side
	vec2 flat_d = normalize(d.xz + vec2(0.0001));
	vec2 flat_s = normalize(sun_dir.xz + vec2(0.0001));
	float toward = pow(max(dot(flat_d, flat_s), 0.0), 2.0);
	hor = mix(hor, mix(vec3(0.85, 0.5, 0.55), vec3(1.0, 0.5, 0.2), toward), dusk * (0.45 + 0.55 * toward));
	top = mix(top, vec3(0.34, 0.27, 0.6), dusk * 0.6);
	vec3 c = mix(hor, top, pow(up, 0.5));
	float above = smoothstep(0.0, 0.12, d.y);         // fades the things in the sky out at the horizon

	float sd = dot(d, sun_dir);
	float sun_up = clamp(sun_dir.y * 6.0 + 0.4, 0.0, 1.0);
	vec3 sun_col = mix(vec3(1.0, 0.5, 0.2), vec3(1.0, 0.95, 0.85), clamp(sun_dir.y * 2.5, 0.0, 1.0));
	float md = dot(d, moon_dir);
	float moon_up = clamp(moon_dir.y * 6.0 + 0.4, 0.0, 1.0);

	// ── layer 2: stars, the Milky Way, shooting stars ──
	if (night > 0.01 && d.y > 0.0 && star_amount > 0.001) {
		// The whole star field turns slowly round the pole star (north, behind the car), as the
		// real sky does, only faster: once round in about 50 minutes, so the stars are seen to
		// drift within a minute. sd3 = this pixel's direction in the turning star field; the
		// stars, the big stars and the Milky Way all use it.
		vec3 pole = normalize(vec3(0.0, 0.62, 0.78));
		float turn_a = TIME * 0.0021;
		vec3 sd3 = d * cos(turn_a) + cross(pole, d) * sin(turn_a) + pole * dot(pole, d) * (1.0 - cos(turn_a));
		vec2 s1 = star_layer(sd3, 420.0, 0.972);
		vec2 s2 = star_layer(sd3, 190.0, 0.991);
		// every star flickers at its own speed; near the horizon (more air) twice as much
		float air = twinkle * (0.55 + 0.45 * (1.0 - up));
		float tw1 = flicker(s1.y, air * 0.8, TIME);
		float tw = flicker(s2.y, air, TIME);
		vec3 tint = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.86, 0.78), fract(s2.y * 91.0));
		// a bright star's colour wavers with its light, bluer as it flares
		tint = mix(tint, vec3(0.7, 0.85, 1.0), clamp((tw - 1.0) * 0.8, 0.0, 0.5));
		vec3 stars = vec3(0.8, 0.82, 1.0) * s1.x * (0.25 + 0.5 * fract(s1.y * 57.0)) * tw1 + tint * s2.x * 1.7 * tw;
		// a few brighter stars: a small round point with a faint soft glow (no cross of light:
		// that looked drawn-on next to the soft clouds)
		vec3 p = sd3 * 9.0;
		vec3 cell = floor(p);
		float hb = hash3(cell + vec3(5.0));
		if (hb > 0.9) {
			vec3 off = fract(p) - 0.5 - (vec3(hash3(cell + vec3(1.0)), hash3(cell + vec3(2.0)), hash3(cell + vec3(3.0))) - 0.5) * 0.5;
			vec3 t1 = normalize(cross(sd3, vec3(0.0, 1.0, 0.001)));
			vec3 t2 = cross(sd3, t1);
			float a = dot(off, t1);
			float b = dot(off, t2);
			float r2 = a * a + b * b;
			float core = exp(-r2 * 2600.0);
			float halo = exp(-r2 * 260.0);
			float tb = flicker(hb, air * 0.6, TIME);
			vec3 big = mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.82, 0.6), step(0.975, hb));
			stars += big * (core * 2.2 + halo * 0.22) * tb;
		}
		// the Milky Way: a hazy band across the sky, clumpy, with dark dust lanes, and more
		// small stars inside it
		vec3 axis = normalize(vec3(0.55, 0.35, 0.76));
		float band = exp(-pow(dot(sd3, axis) * 3.6, 2.0));
		float clump = fbm(sd3 * 5.0 + vec3(3.0, 9.0, 1.0), 4);
		float lanes = smoothstep(0.45, 0.65, fbm(sd3 * 9.0 + vec3(21.0, 4.0, 13.0), 3));
		vec3 milk = mix(vec3(0.32, 0.36, 0.6), vec3(0.75, 0.62, 0.55), clump) * band * (0.25 + clump) * (1.0 - lanes * 0.7) * 0.42;
		vec2 s3 = star_layer(sd3, 640.0, 0.93);
		stars += vec3(0.85, 0.87, 1.0) * s3.x * band * 0.45 * flicker(s3.y, air * 0.8, TIME);
		// a shooting star in most 5-second slots: a short streak that fades (none in safe mode)
		if (twinkle > 0.5) {
			float slot = floor(TIME / 5.0);
			float t = fract(TIME / 5.0) * 5.0;
			if (t < 0.9 && hash3(vec3(slot, 4.0, 9.0)) > 0.35) {
				vec3 from = normalize(vec3(hash3(vec3(slot, 1.0, 0.0)) * 2.0 - 1.0, 0.45 + 0.5 * hash3(vec3(slot, 2.0, 0.0)), hash3(vec3(slot, 3.0, 0.0)) * 2.0 - 1.0));
				vec3 dir = normalize(cross(from, vec3(0.3, 1.0, 0.2)));
				vec3 head = normalize(from + dir * (t / 0.9) * 0.35 + vec3(0.0, -0.08, 0.0) * (t / 0.9));
				vec3 rel = d - head;
				float along = dot(rel, -dir);                 // behind the head = the tail
				float side = length(rel + dir * along);
				float streak = smoothstep(0.004, 0.0, side) * smoothstep(0.1, 0.0, along) * step(0.0, along);
				stars += vec3(1.0, 0.97, 0.9) * streak * 2.5 * sin(t / 0.9 * 3.14159);
			}
		}
		c += (stars * 1.6 * star_amount + milk * min(star_amount, 1.3)) * night * above * (1.0 - dust);
	}

	// ── layer 4: the sun and the moon ──
	c += sun_col * smoothstep(0.9990, 0.9995, sd) * 5.0 * sun_up * (1.0 - 0.8 * dust);
	c += sun_col * pow(max(sd, 0.0), 260.0) * 0.6 * sun_up;
	c += sun_col * pow(max(sd, 0.0), 30.0) * 0.16 * sun_up;
	c += sun_col * pow(max(sd, 0.0), 6.0) * 0.05 * sun_up * day;
	float disc = smoothstep(0.9987, 0.9992, md);
	float marks = 0.75 + 0.25 * noise3((d - moon_dir) * 140.0);
	c = mix(c, vec3(0.9, 0.92, 0.98) * marks * 1.4, disc * moon_up);
	c += vec3(0.5, 0.52, 0.85) * pow(max(md, 0.0), 220.0) * 0.3 * moon_up * (1.0 - disc);
	c += vec3(0.3, 0.3, 0.6) * pow(max(md, 0.0), 24.0) * 0.07 * moon_up * night;

	// which light the clouds are lit by
	vec2 lflat = normalize(mix(moon_dir.xz, sun_dir.xz, step(0.0, sun_dir.y)) + vec2(0.0001));

	if (cloud_amount > 0.001 && d.y > 0.0) {
		// The clouds are a flat sheet high overhead: uv = where this pixel's direction meets it.
		// Near the horizon the sheet is seen at a grazing angle, so the noise picture is read
		// blurred there (`soft`, a mip level) instead of sparkling.
		float soft = 3.0 * (1.0 - smoothstep(0.0, 0.45, d.y));
		float wind = TIME * cloud_speed;
		// ── layer 5: high, thin, streaky cloud ──
		vec2 uvh = d.xz / (d.y + 0.12);
		float wisps = textureLod(cloud_noise, uvh * vec2(0.035, 0.09) + vec2(wind * 0.0002, wind * 0.00045), soft).b;
		wisps = wisps * 0.75 + 0.25 * textureLod(cloud_noise, uvh * 0.21 + vec2(wind * 0.0005, 0.3), soft).g;
		float high = smoothstep(0.5, 0.82, wisps) * min(cloud_amount, 1.0) * 0.5;
		vec3 high_col = mix(vec3(0.06, 0.065, 0.11), vec3(1.0), day);
		high_col = mix(high_col, vec3(1.0, 0.66, 0.6), dusk * 0.85);
		c = mix(c, high_col, high * smoothstep(0.03, 0.25, d.y));

		// ── layer 6: low, puffy cloud ──
		// Two copies of the body noise at different sizes drift at different speeds, so the
		// clouds slowly change shape as they cross the sky; the detail noise eats their edges
		// into puffs (more at the thin rim than in the thick middle).
		vec2 uv = d.xz / (d.y + 0.22);
		vec2 cp = uv * 0.085 + vec2(wind * 0.0009, wind * 0.00035);
		vec2 cp2 = uv * 0.17 + vec2(0.37, 0.11) + vec2(wind * 0.0014, -wind * 0.0003);
		float n = textureLod(cloud_noise, cp, soft).r * 0.62 + textureLod(cloud_noise, cp2, soft).r * 0.38;
		float crumbs = textureLod(cloud_noise, uv * 0.5 + vec2(wind * 0.003, wind * 0.0012), soft).g;
		float cover = 0.64 - 0.28 * cloud_amount * mix(0.75, 1.0, day);
		n -= (1.0 - crumbs) * 0.13 * (1.0 - smoothstep(cover, cover + 0.3, n));
		float dens = smoothstep(cover, cover + 0.06, n);
		if (dens > 0.001) {
			// lit side: denser here than a step towards the light = this side faces it
			float n2 = textureLod(cloud_noise, cp + lflat * 0.02, soft).r * 0.62 + textureLod(cloud_noise, cp2 + lflat * 0.02, soft).r * 0.38;
			float lit = clamp(0.62 + (n - n2) * 11.0, 0.0, 1.0);
			float thick = smoothstep(cover + 0.05, cover + 0.35, n);
			vec3 bright = mix(vec3(0.075, 0.075, 0.13), vec3(1.0, 1.0, 1.0), day) * (1.0 - 0.6 * storm);
			vec3 shade = mix(vec3(0.012, 0.013, 0.03), vec3(0.5, 0.56, 0.68), day) * (1.0 - 0.7 * storm);
			// sunset: peach tops on the sun's side, pink away from it, lavender undersides
			bright = mix(bright, mix(vec3(1.0, 0.6, 0.62), vec3(1.0, 0.68, 0.36), toward), dusk * 0.85);
			shade = mix(shade, vec3(0.42, 0.3, 0.52), dusk * 0.85);
			vec3 cc = mix(shade, bright, lit * (1.0 - thick * 0.45));
			// lightning inside the cloud deck lights it from within
			cc += vec3(0.75, 0.78, 1.0) * flash * (0.4 + 0.6 * thick);
			// a bright rim where the cloud is thin and the sun or moon is behind it
			cc += bright * (1.0 - smoothstep(0.0, 0.5, thick)) * 0.18;
			cc += sun_col * pow(max(sd, 0.0), 14.0) * (1.0 - thick) * 0.7 * sun_up;
			cc += vec3(0.25, 0.27, 0.4) * pow(max(md, 0.0), 30.0) * (1.0 - thick) * moon_up * night;
			c = mix(c, cc, dens * smoothstep(0.02, 0.2, d.y) * 0.96);
		}
	}


	// ── layer 3 (drawn here, over the clouds' gaps): a rainbow opposite the sun ──
	if (rainbow > 0.001 && sun_dir.y > -0.02 && d.y > 0.0) {
		float ang = degrees(acos(clamp(dot(d, -sun_dir), -1.0, 1.0)));
		float t = (ang - 40.5) / 2.2;                // 0 = violet inside .. 1 = red outside
		if (t > -0.3 && t < 1.3) {
			vec3 bow = clamp(vec3(abs(t * 6.0 - 3.0) - 1.0, 2.0 - abs(t * 6.0 - 2.0), 2.0 - abs(t * 6.0 - 4.0)), 0.0, 1.0);
			bow = bow.bgr;
			float edge = smoothstep(-0.3, 0.1, t) * smoothstep(1.3, 0.9, t);
			c += bow * edge * rainbow * 0.22 * smoothstep(0.0, 0.1, d.y) * day;
		}
	}

	// ── lightning: a jagged bolt from the cloud base to the horizon ──
	if (flash > 0.4) {
		float da = az - bolt_az;
		da = mod(da + 3.14159, 6.28318) - 3.14159;
		float wiggle = (noise3(vec3(d.y * 40.0, bolt_az * 7.0, 0.0)) - 0.5) * 0.03 + (noise3(vec3(d.y * 140.0, bolt_az, 3.0)) - 0.5) * 0.008;
		float line = smoothstep(0.0025, 0.0, abs(da - wiggle)) * step(d.y, 0.22) * step(0.0, d.y);
		c += vec3(0.85, 0.88, 1.0) * line * (flash - 0.4) * 6.0;
	}
	c += vec3(0.5, 0.52, 0.7) * flash * 0.25 * (0.3 + 0.7 * up);

	// ── layers 7 and 8: the far mesas and the nearer buttes ──
	vec3 haze_col = mix(hor, mix(vec3(0.78, 0.6, 0.48), vec3(0.66, 0.72, 0.8), land) * (0.06 + 0.94 * day), 0.35);
	float light_az = day > 0.3 ? atan(sun_dir.x, -sun_dir.z) : atan(moon_dir.x, -moon_dir.z);
	float far_h = far_mesas(az);
	if (d.y < far_h + 0.003 && land < 0.5) {
		vec3 far_col = mix(vec3(0.03, 0.025, 0.05), vec3(0.5, 0.42, 0.52), day);
		far_col = mix(far_col, vec3(0.5, 0.3, 0.4), dusk * 0.6);
		far_col = mix(far_col, haze_col, 0.35 + 0.4 * haze);
		c = mix(c, far_col, smoothstep(far_h + 0.0015, far_h - 0.0015, d.y));
	}
	float near_h = near_buttes(az);
	if (d.y < near_h + 0.003 && land < 0.5) {
		float side = sin(light_az - az);
		float lean = (near_buttes(az + 0.006) - near_buttes(az - 0.006)) * 40.0;
		float lit = clamp(0.55 - lean * side * 1.2, 0.0, 1.0);
		// layered cliffs: bands by height, cream caps over red, darker purple at the foot
		float band = fract(d.y * 160.0 + ring_noise(az, 53.0, 1.0) * 0.8);
		vec3 rock = mix(vec3(0.5, 0.2, 0.11), vec3(0.74, 0.42, 0.24), smoothstep(0.2, 0.8, band));
		rock = mix(rock, vec3(0.82, 0.66, 0.5), smoothstep(near_h - 0.008, near_h - 0.002, d.y) * 0.6);
		rock = mix(rock * 0.55, rock, lit);
		rock = mix(rock * mix(vec3(0.04, 0.04, 0.07), vec3(1.0), day), rock * vec3(1.05, 0.6, 0.45), dusk * 0.6 * day);
		rock = mix(rock, haze_col, 0.15 + 0.3 * haze);
		c = mix(c, rock, smoothstep(near_h + 0.0015, near_h - 0.0015, d.y));
	}

	// ── layer 9: the desert floor below the horizon, and the dust ──
	if (d.y < 0.0) {
		vec3 floor_col = mix(vec3(0.02, 0.016, 0.02), vec3(0.62, 0.38, 0.25), day);
		floor_col = mix(floor_col, vec3(0.55, 0.3, 0.22), dusk * 0.4);
		// green country: below the horizon is only ever a sliver under the far ridges, so haze
		floor_col = mix(floor_col, haze_col, land);
		c = mix(mix(haze_col, floor_col, 0.6), floor_col, clamp(-d.y * 5.0, 0.0, 1.0));
	}
	c = mix(c, haze_col, haze * 0.5 * smoothstep(0.06, 0.0, abs(d.y)));
	vec3 dust_now = dust_color * (0.05 + 0.95 * day) + vec3(0.25, 0.15, 0.1) * dusk * day;
	c = mix(c, dust_now, dust * (0.55 + 0.45 * smoothstep(0.6, 0.0, abs(d.y))));
	COLOR = c * exposure;
}
