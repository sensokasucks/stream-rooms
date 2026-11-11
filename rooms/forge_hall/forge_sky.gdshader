shader_type sky;
// Forge Hall: the sky seen through the slanted windows, for every time of day. A blue day sky,
// a warm band toward the sun at sunrise and sunset, a dark night sky with stars and a soft
// milky band, and the sun and the moon as discs. rooms/forge_hall/forge_hall_room.gd
// (_apply_time) sets every uniform from the Time of day setting; nothing here moves on its own
// except a slow twinkle of the stars (set `twinkle` to 0 in photosensitive-safe mode).

// Unit vectors pointing AT the sun and the moon, in world space.
uniform vec3 sun_dir = vec3(-0.6, 0.7, -0.3);
uniform vec3 moon_dir = vec3(0.6, -0.7, 0.3);
// 0 = night, 1 = full day.
uniform float day : hint_range(0.0, 1.0) = 1.0;
// 0..1: how much sunrise / sunset colour the horizon has.
uniform float dusk : hint_range(0.0, 1.0) = 0.0;
uniform float star_amount : hint_range(0.0, 2.0) = 1.0;
uniform float twinkle : hint_range(0.0, 1.0) = 1.0;
// Overall brightness (the room lowers it a little so the windows don't wash the room out).
uniform float exposure = 1.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise, for the milky band and the marks on the moon.
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 top = mix(vec3(0.004, 0.007, 0.028), vec3(0.16, 0.4, 0.85), day);
	vec3 hor = mix(vec3(0.02, 0.03, 0.075), vec3(0.62, 0.78, 0.95), day);
	// sunrise / sunset: the horizon warms, most of all on the sun's side
	vec2 flat_d = normalize(d.xz + vec2(0.0001));
	vec2 flat_s = normalize(sun_dir.xz + vec2(0.0001));
	float toward = pow(max(dot(flat_d, flat_s), 0.0), 2.0);
	hor = mix(hor, vec3(1.0, 0.42, 0.16), dusk * (0.3 + 0.7 * toward));
	top = mix(top, vec3(0.3, 0.22, 0.42), dusk * 0.35);
	vec3 c = mix(hor, top, pow(up, 0.45));
	if (d.y < 0.0) {
		c = mix(hor * 0.5, vec3(0.012), clamp(-d.y * 5.0, 0.0, 1.0));    // below the horizon: dark ground
	}
	// stars: one in a few hundred cells of a fine grid over the sky, each a small soft dot
	float night = 1.0 - day;
	if (night > 0.01 && d.y > 0.0) {
		vec3 p = d * 190.0;
		vec3 cell = floor(p);
		float h = hash3(cell);
		float dot_ = smoothstep(0.42, 0.05, length(fract(p) - 0.5));
		float tw = 1.0 - twinkle * 0.35 * (0.5 + 0.5 * sin(TIME * (0.6 + h * 1.7) + h * 40.0));
		float star = step(0.9962, h) * dot_ * tw;
		vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.75), fract(h * 91.0));
		// the milky band: a soft bright streak across the sky
		float band = smoothstep(0.35, 0.0, abs(dot(d, normalize(vec3(0.5, 0.35, 0.8)))));
		float milk = band * (0.35 + 0.65 * noise3(d * 9.0)) * 0.05;
		c += (tint * star * 1.6 + vec3(0.5, 0.55, 0.8) * milk) * night * star_amount * smoothstep(0.0, 0.15, d.y);
	}
	// the sun: a bright disc with a wide soft glow, fading as it sets
	float sd = dot(d, sun_dir);
	float sun_up = clamp(sun_dir.y * 6.0 + 0.4, 0.0, 1.0);
	vec3 sun_col = mix(vec3(1.0, 0.5, 0.2), vec3(1.0, 0.95, 0.85), clamp(sun_dir.y * 2.5, 0.0, 1.0));
	c += sun_col * smoothstep(0.9990, 0.9995, sd) * 5.0 * sun_up;
	c += sun_col * pow(max(sd, 0.0), 48.0) * 0.5 * sun_up;
	// the moon: a pale disc with darker marks, and a faint halo
	float md = dot(d, moon_dir);
	float moon_up = clamp(moon_dir.y * 6.0 + 0.4, 0.0, 1.0);
	float disc = smoothstep(0.9989, 0.9993, md);
	float marks = 0.75 + 0.25 * noise3((d - moon_dir) * 140.0);
	c = mix(c, vec3(0.85, 0.88, 0.95) * marks * 1.3, disc * moon_up);
	c += vec3(0.4, 0.5, 0.7) * pow(max(md, 0.0), 220.0) * 0.25 * moon_up * (1.0 - disc);
	COLOR = c * exposure;
}
