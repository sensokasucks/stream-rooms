shader_type sky;
// Lakeside Campfire: the whole sky, built in layers from the back to the front so it has depth:
//   1. the sky's own colour for the hour (deep blue day, warm band at sunrise and sunset, near
//      black night),
//   2. stars: a fine field, brighter ones that twinkle, a few with a cross of light, the Milky
//      Way as a hazy band, and a shooting star now and then,
//   3. an aurora (green and violet curtains in the north, over the lake; optional),
//   4. the sun and the moon with their glow,
//   5. high, thin, streaky cloud that drifts slowly,
//   6. low, puffy cloud that drifts faster, lit from the sun's or the moon's side; in rain it
//      thickens into a dark storm deck, which lightning lights up from inside,
//   7. two mountain ridges with haze between them, and
//   8. the dark tree line on the far shore of the lake.
// rooms/campfire/campfire_room.gd (_apply_time, _apply_weather) sets every uniform from the
// Time of day setting, the Clouds / Stars / Aurora sliders and the weather. The outline of the
// ridges and the tree line comes from camp_horizon.gdshaderinc, which the lake's shader uses
// too, so the water mirrors the same shore.
// Cost: the clouds and the aurora are layered noise for every sky pixel on screen. Each is
// skipped when its amount is 0, which is the cheap setting for a slow graphics card.
#include "res://rooms/campfire/camp_horizon.gdshaderinc"

// Unit vectors pointing AT the sun and the moon, in world space.
uniform vec3 sun_dir = vec3(0.6, 0.7, 0.3);
uniform vec3 moon_dir = vec3(-0.3, 0.6, -0.7);
// 0 = night, 1 = full day.
uniform float day : hint_range(0.0, 1.0) = 1.0;
// 0..1: how much sunrise / sunset colour the horizon has.
uniform float dusk : hint_range(0.0, 1.0) = 0.0;
uniform float star_amount : hint_range(0.0, 2.0) = 1.0;
// 0 = steady stars and no shooting stars (photosensitive-safe mode), 1 = they twinkle.
uniform float twinkle : hint_range(0.0, 1.0) = 1.0;
// How much of the sky the clouds cover: 0 = none (and no cost), 1 = fair weather, 2 = overcast.
uniform float cloud_amount : hint_range(0.0, 2.0) = 1.0;
// How fast the clouds drift (the wind; a storm raises it).
uniform float cloud_speed : hint_range(0.0, 6.0) = 1.0;
// 0 = fair weather clouds, 1 = a dark storm deck (rain and thunderstorm).
uniform float storm : hint_range(0.0, 1.0) = 0.0;
// Lightning right now, 0..1: lights the clouds from inside and lifts the whole sky a little.
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// Where in the sky the lightning is (a unit vector).
uniform vec3 flash_dir = vec3(0.0, 0.4, -0.9);
// The aurora's strength: 0 = none (and no cost).
uniform float aurora_amount : hint_range(0.0, 2.0) = 0.0;
// The haze over the lake and between the ridges (the room's Mist slider).
uniform float haze : hint_range(0.0, 1.0) = 0.4;
// Overall brightness.
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
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	float night = 1.0 - day;
	float az = atan(d.x, -d.z);                       // 0 = north (over the lake)

	// ── layer 1: the sky's own colour ──
	vec3 top = mix(vec3(0.004, 0.006, 0.02), vec3(0.08, 0.27, 0.72), day);
	vec3 hor = mix(vec3(0.015, 0.02, 0.05), vec3(0.5, 0.68, 0.92), day);
	// sunrise / sunset: the horizon warms, most of all on the sun's side
	vec2 flat_d = normalize(d.xz + vec2(0.0001));
	vec2 flat_s = normalize(sun_dir.xz + vec2(0.0001));
	float toward = pow(max(dot(flat_d, flat_s), 0.0), 2.0);
	hor = mix(hor, vec3(1.0, 0.42, 0.16), dusk * (0.3 + 0.7 * toward));
	top = mix(top, vec3(0.2, 0.14, 0.4), dusk * 0.45);
	// under storm cloud the open sky is grey
	float grey = storm * clamp(cloud_amount, 0.0, 1.0);
	top = mix(top, vec3(0.1, 0.11, 0.13) * (0.12 + 0.88 * day), grey);
	hor = mix(hor, vec3(0.3, 0.32, 0.35) * (0.1 + 0.9 * day), grey);
	vec3 c = mix(hor, top, pow(up, 0.5));
	float above = smoothstep(0.0, 0.12, d.y);         // fades the things in the sky out at the horizon

	float sd = dot(d, sun_dir);
	float sun_up = clamp(sun_dir.y * 6.0 + 0.4, 0.0, 1.0);
	vec3 sun_col = mix(vec3(1.0, 0.5, 0.2), vec3(1.0, 0.95, 0.85), clamp(sun_dir.y * 2.5, 0.0, 1.0));
	float md = dot(d, moon_dir);
	float moon_up = clamp(moon_dir.y * 6.0 + 0.4, 0.0, 1.0);

	// ── layer 2: stars, the Milky Way, shooting stars ──
	if (night > 0.01 && d.y > 0.0 && star_amount > 0.001) {
		vec2 s1 = star_layer(d, 420.0, 0.972);
		vec2 s2 = star_layer(d, 190.0, 0.991);
		float tw = 1.0 - twinkle * 0.35 * (0.5 + 0.5 * sin(TIME * (0.6 + s2.y * 1.7) + s2.y * 40.0));
		vec3 tint = mix(vec3(0.72, 0.8, 1.0), vec3(1.0, 0.86, 0.78), fract(s2.y * 91.0));
		vec3 stars = vec3(0.8, 0.82, 1.0) * s1.x * (0.25 + 0.5 * fract(s1.y * 57.0)) + tint * s2.x * 1.7 * tw;
		// a few big stars with a cross of light
		vec3 p = d * 9.0;
		vec3 cell = floor(p);
		float hb = hash3(cell + vec3(5.0));
		if (hb > 0.9) {
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
		// the Milky Way: a hazy band across the sky, clumpy, with dark dust lanes, and more
		// small stars inside it
		vec3 axis = normalize(vec3(0.55, 0.35, 0.76));
		float band = exp(-pow(dot(d, axis) * 3.6, 2.0));
		float clump = fbm(d * 5.0 + vec3(3.0, 9.0, 1.0), 4);
		float lanes = smoothstep(0.45, 0.65, fbm(d * 9.0 + vec3(21.0, 4.0, 13.0), 3));
		vec3 milk = mix(vec3(0.32, 0.36, 0.6), vec3(0.75, 0.62, 0.55), clump) * band * (0.25 + clump) * (1.0 - lanes * 0.7) * 0.42;
		vec2 s3 = star_layer(d, 640.0, 0.93);
		stars += vec3(0.85, 0.87, 1.0) * s3.x * band * 0.45;
		// a shooting star every several seconds: a short streak that fades (none in safe mode)
		if (twinkle > 0.5) {
			float slot = floor(TIME / 7.0);
			float t = fract(TIME / 7.0) * 7.0;
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
		c += (stars * 1.6 * star_amount + milk * min(star_amount, 1.3)) * night * above * (1.0 - grey);
	}

	// ── layer 3: the aurora, curtains hanging in the north ──
	if (aurora_amount > 0.001 && night > 0.05 && d.y > 0.02) {
		// where this direction meets a sheet high overhead; the curtains are stripes in it
		vec2 uv = d.xz / (d.y + 0.35);
		float north = smoothstep(0.3, -0.5, d.z);                       // only over the lake
		float fold = fbm(vec3(uv.x * 0.7 + TIME * 0.012, uv.y * 0.25, TIME * 0.02), 3);
		float curtain = pow(max(1.0 - abs(sin(uv.x * 2.2 + fold * 7.0 + TIME * 0.05)), 0.0), 3.0);
		float rays = 0.55 + 0.45 * noise3(vec3(uv.x * 26.0 + fold * 30.0, 2.0, TIME * 0.15));
		float height = smoothstep(0.03, 0.2, d.y) * smoothstep(0.85, 0.3, d.y);
		vec3 acol = mix(vec3(0.1, 1.0, 0.45), vec3(0.55, 0.25, 0.95), smoothstep(0.25, 0.7, d.y));
		c += acol * curtain * rays * height * north * 0.5 * aurora_amount * night * (1.0 - grey);
	}

	// ── layer 4: the sun and the moon ──
	float clear_sky = 1.0 - grey * 0.9;
	c += sun_col * smoothstep(0.9990, 0.9995, sd) * 5.0 * sun_up * clear_sky;
	c += sun_col * pow(max(sd, 0.0), 260.0) * 0.6 * sun_up * clear_sky;
	c += sun_col * pow(max(sd, 0.0), 30.0) * 0.16 * sun_up * clear_sky;
	c += sun_col * pow(max(sd, 0.0), 6.0) * 0.05 * sun_up * day * clear_sky;
	float disc = smoothstep(0.9987, 0.9992, md);
	float marks = 0.75 + 0.25 * noise3((d - moon_dir) * 140.0);
	c = mix(c, vec3(0.9, 0.92, 0.98) * marks * 1.4, disc * moon_up * clear_sky);
	c += vec3(0.5, 0.52, 0.85) * pow(max(md, 0.0), 220.0) * 0.3 * moon_up * (1.0 - disc) * clear_sky;
	c += vec3(0.3, 0.3, 0.6) * pow(max(md, 0.0), 24.0) * 0.07 * moon_up * night * clear_sky;

	// which light the clouds are lit by
	vec2 lflat = normalize(mix(moon_dir.xz, sun_dir.xz, step(0.0, sun_dir.y)) + vec2(0.0001));
	float fd = max(dot(d, normalize(flash_dir)), 0.0);

	if (cloud_amount > 0.001 && d.y > 0.0) {
		// ── layer 5: high, thin, streaky cloud ──
		vec2 uvh = d.xz / (d.y + 0.12);
		vec3 hp = vec3(uvh.x * 0.5, uvh.y * 1.7, 0.0) + vec3(TIME * 0.0012 * cloud_speed, TIME * 0.0005 * cloud_speed, 5.0);
		float wisps = fbm(hp, 4);
		float high = smoothstep(0.52, 0.8, wisps) * min(cloud_amount, 1.0) * 0.5;
		vec3 high_col = mix(vec3(0.06, 0.065, 0.11), vec3(1.0), day);
		high_col = mix(high_col, vec3(1.0, 0.6, 0.42), dusk * 0.85);
		c = mix(c, high_col, high * smoothstep(0.03, 0.25, d.y) * (1.0 - grey));

		// ── layer 6: low, puffy cloud; a storm deck in bad weather ──
		vec2 uv = d.xz / (d.y + 0.22);
		vec3 cp = vec3(uv * 1.15, 0.0) + vec3(TIME * 0.004 * cloud_speed, 0.0, TIME * 0.0015 * cloud_speed);
		float n = fbm(cp, 5) + (fbm(cp * 4.3 + vec3(7.0, 2.0, 0.0), 3) - 0.5) * 0.14;
		float cover = 0.66 - 0.19 * cloud_amount * mix(0.6, 1.0, day) - 0.12 * storm;
		float dens = smoothstep(cover, cover + 0.07, n);
		if (dens > 0.001) {
			float n2 = fbm(cp + vec3(lflat * 0.09, 0.0), 5);
			float lit = clamp(0.6 + (n - n2) * 5.0, 0.0, 1.0);
			float thick = smoothstep(cover + 0.05, cover + 0.35, n);
			vec3 bright = mix(vec3(0.075, 0.075, 0.13), vec3(1.0, 1.0, 1.0), day);
			vec3 shade = mix(vec3(0.012, 0.013, 0.03), vec3(0.32, 0.38, 0.52), day);
			bright = mix(bright, vec3(1.0, 0.55, 0.3), dusk * 0.8);
			shade = mix(shade, vec3(0.3, 0.14, 0.26), dusk * 0.8);
			// storm: both ends go slate grey and darker
			bright = mix(bright, vec3(0.34, 0.36, 0.4) * (0.1 + 0.9 * day), storm);
			shade = mix(shade, vec3(0.07, 0.075, 0.09) * (0.1 + 0.9 * day), storm);
			vec3 cc = mix(shade, bright, lit * (1.0 - thick * 0.45));
			cc += sun_col * pow(max(sd, 0.0), 14.0) * (1.0 - thick) * 0.7 * sun_up * (1.0 - storm);
			cc += vec3(0.25, 0.27, 0.4) * pow(max(md, 0.0), 30.0) * (1.0 - thick) * moon_up * night * (1.0 - storm);
			// lightning inside the cloud: brightest round where it struck
			cc += vec3(0.75, 0.82, 1.0) * flash * (0.25 + 1.6 * pow(fd, 6.0)) * (0.5 + 0.5 * n);
			c = mix(c, cc, dens * smoothstep(0.02, 0.2, d.y) * 0.96);
		}
	}
	c += vec3(0.35, 0.4, 0.55) * flash * 0.12;        // the whole sky lifts a little in a flash

	// ── layers 7 and 8: the ridges and the far shore's trees, each paler the further away ──
	vec3 haze_col = mix(hor, vec3(0.6, 0.66, 0.74) * (0.06 + 0.94 * day), 0.4) + vec3(0.35, 0.4, 0.55) * flash * 0.1;
	float far_h = hz_far_ridge(az);
	float near_h = hz_near_ridge(az);
	float tree_h = hz_tree_line(az);
	vec3 far_col = mix(vec3(0.16, 0.22, 0.34), vec3(0.01, 0.012, 0.03), night);
	far_col = mix(far_col, vec3(0.3, 0.16, 0.26), dusk * 0.6);
	// snow on the highest peaks catches the light
	float snow = smoothstep(0.13, 0.19, d.y) * smoothstep(far_h - 0.035, far_h, d.y + 0.02 * hz_noise(az, 140.0, 2.0));
	far_col = mix(far_col, mix(vec3(0.1, 0.11, 0.18), vec3(0.85, 0.88, 0.95), day), snow * 0.7);
	far_col = mix(far_col, haze_col, 0.35 + 0.45 * haze);
	c = mix(c, far_col, smoothstep(far_h + 0.002, far_h - 0.002, d.y));
	vec3 near_col = mix(vec3(0.09, 0.15, 0.17), vec3(0.006, 0.008, 0.016), night);
	near_col = mix(near_col, vec3(0.16, 0.09, 0.14), dusk * 0.5);
	near_col = mix(near_col, haze_col, 0.15 + 0.4 * haze);
	c = mix(c, near_col, smoothstep(near_h + 0.002, near_h - 0.002, d.y));
	// mist lying on the water in front of the ridges
	c = mix(c, haze_col, haze * 0.75 * smoothstep(0.07, 0.0, d.y));
	vec3 tree_col = mix(vec3(0.03, 0.07, 0.05), vec3(0.003, 0.005, 0.007), night);
	tree_col = mix(tree_col, haze_col, 0.25 * haze);
	c = mix(c, tree_col, smoothstep(tree_h + 0.0015, tree_h - 0.0015, d.y));
	if (d.y < 0.0) {
		c = mix(tree_col, vec3(0.01, 0.012, 0.012), clamp(-d.y * 6.0, 0.0, 1.0));     // below the horizon: dark ground
	}
	COLOR = c * exposure;
}
