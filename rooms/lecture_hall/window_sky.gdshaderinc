// The sky outside the Lecture Hall's windows, for stained_glass.gdshader: what you see through
// the clear panes, and how much daylight reaches each window. Everything comes from uniforms the
// room script (lecture_hall_room.gd, _apply_time) sets from the hour ("lh_time", "lh_day_minutes")
// and the Clouds slider ("lh_clouds"). Directions are world space, y up.
//
// The view is drawn per pixel only on the window glass, so a big, empty sky costs nothing.
// Clouds come from sky_noise.png (made by detail/make_detail_textures.py), not from sin() hashes:
// those turn blocky on real graphics cards (found in the Lakeside Campfire).

uniform sampler2D sky_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_to = vec3(0.85, 0.3, 0.42);      // pointing AT the sun (normalised)
uniform vec3 moon_to = vec3(-0.85, 0.3, -0.42);   // pointing AT the moon
uniform float day = 1.0;                          // 0 = night, 1 = day (from the sun's height)
uniform float dusk = 0.0;                         // 1 while the sun is near the horizon
uniform float cloud_amount = 1.0;                 // the Clouds slider, 0..2
uniform float star_amount = 1.0;                  // 0 in photosensitive-safe mode: no twinkle
uniform float cloud_drift = 0.004;                // how fast the clouds move (texture repeats per second)

const vec3 DAY_ZENITH = vec3(0.16, 0.36, 0.78);
const vec3 DAY_HORIZON = vec3(0.68, 0.80, 0.93);
const vec3 DUSK_HORIZON = vec3(1.0, 0.48, 0.2);
const vec3 DUSK_ZENITH = vec3(0.22, 0.24, 0.48);
const vec3 NIGHT_ZENITH = vec3(0.006, 0.01, 0.03);
const vec3 NIGHT_HORIZON = vec3(0.03, 0.045, 0.09);

// How high the town's skyline reaches (dir.y) for a compass angle: rooftops, chimneys and a
// few trees, in blocks so the roofs read as buildings. Low, so most windows (high on the walls)
// only show sky; it shows when you look out level from the gallery.
float lh_skyline(float az) {
	float u = az / 6.2831853 + 0.5;
	float block = floor(u * 90.0);
	float roof = textureLod(sky_noise, vec2(block * 17.3 / 256.0, 0.13), 0.0).r;     // far-apart pixels: houses differ
	float f = fract(u * 90.0);
	float gable = 1.0 - abs(f - 0.5) * 2.0;                      // pitched roof on each house
	float h = 0.012 + roof * 0.03 + gable * 0.008;
	float chimney = step(0.7, textureLod(sky_noise, vec2(block * 17.3 / 256.0, 0.61), 0.0).g) * step(0.62, f) * step(f, 0.7);
	float spire = step(0.93, roof) * max(0.0, 1.0 - abs(f - 0.5) * 6.0) * 0.06;  // now and then a church spire
	float trees = textureLod(sky_noise, vec2(u * 3.0, 0.4), 0.0).b;
	return max(h + chimney * 0.012 + spire, 0.01 + trees * 0.045 * step(0.6, trees));
}

// The colour of the sky (and the skyline) seen in direction dir, before the glass. HDR: about 1
// for the midday sky, more in the sun.
vec3 lh_sky(vec3 dir, float time) {
	float h = dir.y;
	float az = atan(dir.x, dir.z);
	// the sky's gradient: day, dusk, night
	float up = clamp(h, 0.0, 1.0);
	vec3 day_c = mix(DAY_HORIZON, DAY_ZENITH, pow(up, 0.6));
	vec3 dusk_c = mix(DUSK_HORIZON, DUSK_ZENITH, pow(up, 0.45));
	vec3 night_c = mix(NIGHT_HORIZON, NIGHT_ZENITH, pow(up, 0.5));
	vec3 sky = mix(night_c, day_c, day);
	// the sunset glow is strongest on the sun's side of the sky
	float sun_side = 0.4 + 0.6 * clamp(dot(normalize(vec3(dir.x, 0.0, dir.z)), normalize(vec3(sun_to.x, 0.0, sun_to.z))) * 0.5 + 0.5, 0.0, 1.0);
	sky = mix(sky, dusk_c, dusk * sun_side);
	// the sun and its halo, the moon
	float s = max(dot(dir, sun_to), 0.0);
	float sun_up = smoothstep(-0.05, 0.02, sun_to.y);
	vec3 sun_col = mix(vec3(1.0, 0.55, 0.25), vec3(1.0, 0.95, 0.85), smoothstep(0.05, 0.4, sun_to.y));
	sky += sun_col * (pow(s, 900.0) * 30.0 + pow(s, 40.0) * 0.5 + pow(s, 6.0) * 0.15) * sun_up;
	float m = max(dot(dir, moon_to), 0.0);
	float moon_up = smoothstep(-0.02, 0.05, moon_to.y) * (1.0 - day);
	sky += vec3(0.8, 0.85, 1.0) * (smoothstep(0.9993, 0.9996, m) * 2.0 + pow(m, 60.0) * 0.08) * moon_up;
	// stars: one in some cells of a grid over the sky, fading in after dusk
	if (star_amount > 0.0 && day < 0.6) {
		vec3 p = dir * 220.0;
		vec3 cell = floor(p);
		vec4 rnd = textureLod(sky_noise, (cell.xz * 17.3 + cell.y * 7.31) / 256.0, 0.0);   // scattered: neighbouring cells read far-apart pixels
		float star = step(0.82, rnd.b) * smoothstep(0.35, 0.0, length(fract(p) - 0.5));
		sky += vec3(0.9, 0.92, 1.0) * star * star_amount * (1.0 - day / 0.6) * 0.9 * step(0.0, h);
	}
	// clouds on a flat layer above the town: big shapes from r, detail from g and b
	if (h > 0.0 && cloud_amount > 0.0) {
		vec2 p = dir.xz / (h + 0.08) * 0.12 + vec2(time * cloud_drift, time * cloud_drift * 0.4);
		vec3 n = texture(sky_noise, p).rgb;
		vec3 n2 = texture(sky_noise, p * 3.1 + 0.37).rgb;
		float shape = n.r * 0.6 + n2.g * 0.3 + n2.b * 0.1;
		float cover = 0.72 - 0.25 * cloud_amount;
		float dens = smoothstep(cover, cover + 0.22, shape) * smoothstep(0.0, 0.15, h) * min(cloud_amount, 1.0);
		vec3 lit = mix(vec3(0.06, 0.07, 0.09), vec3(1.0), day);
		lit = mix(lit, vec3(1.0, 0.62, 0.42), dusk * 0.85);
		lit *= 0.75 + 0.35 * pow(s, 4.0) * sun_up;           // brighter round the sun
		sky = mix(sky, lit * (0.8 + 0.25 * n2.b), dens * 0.92);
	}
	// the skyline: dark roofs and trees, lit a little by the sky behind
	float edge = lh_skyline(az);
	if (h < edge) {
		// far away, so the roofs take on the haze of the sky above the horizon (bluish by day,
		// orange at sunset); at night a few lit windows
		vec3 haze = mix(mix(NIGHT_HORIZON, DAY_HORIZON, day), DUSK_HORIZON, dusk * 0.7);
		vec3 town = mix(vec3(0.008, 0.008, 0.012), haze * 0.55, 0.15 + 0.6 * day);
		vec2 win = vec2(az * 900.0, h * 900.0);
		float lit = step(0.8, textureLod(sky_noise, floor(win) * 0.071, 0.0).b) * step(0.25, fract(win.x)) * step(0.3, fract(win.y));
		town += vec3(1.0, 0.7, 0.35) * lit * 0.6 * (1.0 - day) * step(h, edge - 0.006);
		sky = town;
	}
	return sky;
}

// How much daylight reaches a window that looks out along `out_dir` (horizontal, outward):
// about 1 on a clear midday, a little more facing a low sun, near 0 at night.
float lh_daylight(vec3 out_dir) {
	float sky_light = mix(0.03, 1.0, day) + dusk * 0.6;     // the glow of a sunset sky lingers after the sun is down
	float facing = max(dot(normalize(out_dir), normalize(vec3(sun_to.x, max(sun_to.y, 0.0), sun_to.z))), 0.0);
	return sky_light + facing * 0.9 * smoothstep(-0.02, 0.1, sun_to.y);
}
