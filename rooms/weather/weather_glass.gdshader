shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
// Shared weather (rooms/weather/room_weather.gd): window glass that gets wet and frosty.
// The room gives its window panes this material (the Log Cabin: cabin_builder.gd _build_glass);
// RoomWeather.set_glass() feeds it every frame from the weather settings:
//   rain   how hard it is raining on the glass now, 0..1: runners (drops sliding down with a
//          trail) only show while it rains, and slant with `wind`
//   wet    how much water is on the glass, 0..1. Rises while it rains and falls slowly after,
//          so the beads dry a few at a time (the small ones first) instead of vanishing at once.
//          The view through wet glass goes soft and a little darker.
//   frost  0..1, cold weather: frost creeps in from the edges of the panes, most from the
//          bottom. A pane with UVs in metres from its bottom-left corner and its size in UV2
//          (the Log Cabin's, cabin_builder.gd _glass_pane) knows where its edges are; one
//          without (UV2 = 0) frosts up from the bottom by height instead.
//   refract  0 on a slow PC (Low graphics): the drops still show but don't bend or blur the view
// The drop, runner and frost pictures are our own (textures/make_weather_textures.py), not
// noise made up in the shader. Slow on purpose: nothing flickers.
// The drops and the frost picture are mapped by world position: a pane facing along Z uses x and
// y, one facing along X uses z and y.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D drops : filter_linear_mipmap, repeat_enable;
uniform sampler2D runners : filter_linear_mipmap, repeat_enable;
uniform sampler2D frost_tex : filter_linear_mipmap, repeat_enable;
// The dry glass: its colour and how much of it shows (alpha).
uniform vec4 tint : source_color = vec4(0.78, 0.86, 0.9, 0.12);
uniform float rain = 0.0;
uniform float wet = 0.0;
uniform float frost = 0.0;
// sideways lean of the runners, from the wind (0 = straight down)
uniform float wind = 0.0;
uniform float refract = 1.0;
// metres one copy of the bead picture covers (make_weather_textures.py draws the beads for 0.8)
uniform float bead_size = 0.8;
uniform vec3 frost_color : source_color = vec3(0.86, 0.92, 0.98);
// metres of glass one copy of the frost picture covers
uniform float frost_size = 1.3;

varying vec3 w_pos;
varying vec3 w_normal;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(w_normal);
	if (!FRONT_FACING) {
		n = -n;
	}
	bool along_z = abs(n.z) > 0.5;
	vec2 p = along_z ? w_pos.xy : w_pos.zy;
	vec3 eu = along_z ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);

	// How sharp the drops can be drawn here: 1 while one bead-picture pixel covers about one
	// screen pixel or more, falling to 0 when many squeeze into one (a pane far from the camera).
	// Far away the beads and their bends turn into an even soft wetness instead of grey speckle.
	float texels = length(fwidth(p)) / bead_size * 512.0;
	float sharp = 1.0 - smoothstep(1.2, 4.0, texels);

	// beads: each one has its own number (alpha); the wetter the glass, the more of them show
	vec4 d = texture(drops, p / bead_size);
	float bead = smoothstep(0.02, 0.12, d.b) * step(d.a, wet * 1.02 - 0.02);
	vec2 bend = (d.rg - 0.5) * bead * sharp;
	float water = d.b * bead * sharp;

	// runners: two layers sliding down at different speeds, leaning with the wind
	float run_cover = 0.0;
	if (rain > 0.01) {
		for (int k = 0; k < 2; k++) {
			float fk = float(k);
			float scale_x = 0.55 + fk * 0.3;      // metres across one copy
			float scale_y = 2.2 + fk * 0.9;       // metres down one copy
			float speed = 0.09 + fk * 0.05;       // copies per second
			vec2 q = vec2(p.x / scale_x + p.y * wind * 0.12 + fk * 0.37, -p.y / scale_y - TIME * speed);
			vec4 r = texture(runners, q);
			// the trail fades along its length (alpha: 0 at the head)
			float m = smoothstep(0.03, 0.15, r.b) * (1.0 - r.a * 0.75) * smoothstep(0.0, 0.6, rain);
			if (m > run_cover) {
				run_cover = m;
				bend = mix(bend, (r.rg - 0.5) * sharp, m);
				water = max(water, r.b * m);
			}
		}
	}
	run_cover *= mix(0.5, 1.0, sharp);
	float drop_cover = max(bead * smoothstep(0.02, 0.2, d.b) * sharp + wet * 0.25 * (1.0 - sharp), run_cover);

	// frost: creeps in from the pane's edges as it gets colder, furthest from the bottom (the
	// coldest air sinks there), with crystals reaching out ahead of the solid frost. The crystal
	// picture is laid twice (the second copy turned and smaller) and its edge wobbled by the
	// picture's smooth noise, so neither the pattern nor the frost line visibly repeats.
	float frost_cover = 0.0;
	if (frost > 0.001) {
		vec2 q1 = p / frost_size;
		vec2 q2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (frost_size * 0.63) + vec2(0.31, 0.17);
		vec3 f1 = texture(frost_tex, q1).rgb;
		float f2 = texture(frost_tex, q2).r;
		float fr = max(f1.r, f2 * 0.9);
		float wander = texture(frost_tex, p / (frost_size * 2.7) + vec2(0.5, 0.2)).g;
		float lumps = f1.b;
		if (UV2.x > 0.0) {
			// how far in from the nearest edge (metres): the bottom edge counts as nearer, so the
			// frost reaches furthest up from the sill; the top a little nearer too
			float edge = min(min(UV.x, UV2.x - UV.x), min(UV.y * 0.55, (UV2.y - UV.y) * 0.85));
			// how far in the frost has crept: about 0.15 to 0.4 m at full frost (wandering), less
			// on a small pane, so the middle of every pane stays clear to see through
			float reach = frost * min(0.28, 0.25 * min(UV2.x, UV2.y)) * (0.55 + 0.9 * wander) + 0.02 * lumps;
			float solid = 1.0 - smoothstep(reach * 0.35, reach, edge);
			// the crystals reach on ahead of the solid frost, thinning out
			float ahead = 1.0 - smoothstep(reach * 0.7, reach * 1.6, edge);
			float spikes = smoothstep(0.45, 0.7, fr) * ahead;
			frost_cover = max(solid * (0.5 + 0.5 * fr), spikes) * smoothstep(0.0, 0.08, frost);
		} else {
			// a pane without its size (another room's glass): thick near the bottom, thin higher up
			float low = 1.0 - smoothstep(0.0, 3.0, w_pos.y);
			frost_cover = smoothstep(0.5, 0.75, fr * 0.6 + (low * 0.5 + 0.5) * frost - 0.3);
		}
	}

	// the view through the glass: bent by the drops, soft through the wet film
	// the thin film of water between the drops: only a light veil, so the view stays readable
	float film = wet * 0.22;
	float cover = clamp(max(film, drop_cover * 0.95), 0.0, 1.0);
	vec2 suv = SCREEN_UV + bend * 0.06 * refract;
	float lod = refract * (wet * 1.6 + drop_cover * 1.2);
	vec3 behind = textureLod(screen, suv, lod).rgb * (1.0 - 0.18 * wet);

	ALBEDO = mix(tint.rgb * (1.0 - cover), frost_color, frost_cover);
	EMISSION = behind * cover * (1.0 - frost_cover);
	ALPHA = clamp(max(tint.a, cover) + frost_cover * 0.85, 0.0, 1.0);
	ROUGHNESS = mix(0.05, 0.7, frost_cover);
	SPECULAR = 0.6;
	// the drops catch highlights (the fire, the lamps) on their curved faces
	vec3 bent = normalize(n + (eu * bend.x + vec3(0.0, 1.0, 0.0) * bend.y) * 3.0 * water);
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
}
