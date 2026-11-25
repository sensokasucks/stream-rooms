shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// Cabin: Ocean: the surf. A strip along the beach (cabin_ocean.gd _build_surf) laid over the sea
// and up the sand, drawn see-through on top of them. Waves roll in towards the beach one after
// another: each is a band of foam that is thin far out, thickens and turns white where the wave
// breaks, leaves a trail of broken foam behind it, then runs up the sand as a thin sheet of
// wash and fades. Nothing here is real geometry: it is all foam painted on the strip.
// The strip's UV: x = metres along the beach, y = metres out to sea from the waterline (below 0
// = up the sand). log_cabin_room.gd (_apply_ocean) sets `daylight`, `light_color`, `size` and
// `foam_tint`.

// How bright the foam is: 0.08 at night .. 1 in full sun (the sky's light on white water).
uniform float daylight = 1.0;
// The colour of the light on the foam (warm at dusk); multiplied in.
uniform vec3 light_color = vec3(1.0);
// How big the waves are: 1 = an ordinary day, 2 = a storm (more foam, further up the sand).
uniform float size = 1.0;
// Seconds between one wave and the next.
uniform float period = 8.0;
// Noise (the sky's cloud noise picture), which breaks the foam into lace.
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

// Where wave k's front is now (metres out from the waterline), and how far through its life it
// is (0 = just appeared far out, 1 = gone up the sand).
vec2 wave_front(float k, float along) {
	float life = fract(TIME / (period * 3.0) + k / 3.0 + 0.04 * sin(along * 0.011 + k * 2.1));
	// it comes in fast while far out, slows as it climbs the sand
	float front = mix(94.0, -9.0 * size, pow(life, 0.8));
	return vec2(front, life);
}

void fragment() {
	float along = UV.x;
	float out_m = UV.y;
	// the waterline wanders a little along the beach
	out_m += 1.5 * sin(along * 0.023) + 0.8 * sin(along * 0.061 + 1.0);
	float lace = texture(noise, vec2(along, out_m) * 0.045 + vec2(TIME * 0.004, 0.0)).r;
	float fine = texture(noise, vec2(along, out_m) * 0.17 + vec2(0.0, TIME * 0.01)).g;
	float foam = 0.0;
	for (int i = 0; i < 3; i++) {
		float k = float(i);
		vec2 w = wave_front(k, along);
		float d = out_m - w.x;                          // above 0 = behind the front (seaward)
		// breaking: none far out, building from 65 m in, strongest from 25 m in, then the wash
		// on the sand (a gently shelving beach: the waves break well out)
		float breaking = smoothstep(65.0, 25.0, w.x);
		float crest_w = mix(0.6, 2.2, breaking) * size;
		float crest = exp(-d * d / (crest_w * crest_w)) * mix(0.25, 1.0, breaking);
		// the broken foam left behind the front, thinning out seaward
		float trail = d > 0.0 ? exp(-d / (9.0 * size)) * breaking * 0.75 : 0.0;
		// on the sand (front below 0) the wave is a thin sheet that fades as it climbs
		float wash = smoothstep(2.0, -1.0, w.x) * (1.0 - w.y) * 2.2;
		float sheet = (out_m < 3.0 && d > 0.0) ? wash * exp(-d / 6.0) : 0.0;
		foam = max(foam, max(crest, trail * (0.4 + 0.8 * lace)) + sheet * (0.5 + 0.5 * fine));
	}
	// a little foam always clings to the waterline
	foam = max(foam, exp(-out_m * out_m / 4.0) * 0.35 * (0.6 + 0.6 * lace));
	foam *= smoothstep(0.25, 0.6, lace * 0.6 + fine * 0.6);         // lace, not a solid band
	// fade out far from the beach, past where the strip ends, and at its two ends
	foam *= smoothstep(96.0, 75.0, out_m) * smoothstep(-12.0 * size, -4.0, out_m);
	foam *= smoothstep(0.0, 0.08, UV2.x) * smoothstep(1.0, 0.92, UV2.x);
	ALBEDO = vec3(0.93, 0.96, 0.98) * light_color * daylight;
	ALPHA = clamp(foam, 0.0, 0.92);
}
