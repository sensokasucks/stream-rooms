shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Backlit stained glass for the lecture hall's windows (lancets, rose rondels, door fanlights).
// The glass texture is painted with dark lead cames between the pieces. Here the glass gets:
//   - light coming through it (emission), brightest in windows that face the sun,
//   - clouds drifting across the sun, so the windows slowly breathe,
//   - a slight wobble when seen at an angle, as hand-rolled glass has,
//   - lead that stays dark, a little metallic and rough, with shiny glass between.
// The room sets light_level from the house lights; when they go down for a video the windows
// fall to night_glow, a faint glow from outside.

uniform sampler2D glass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float light_level = 1.0;
uniform float night_glow = 0.18;
uniform float emission_strength = 2.2;
uniform vec3 sun_dir = vec3(-0.62, -0.3, -0.4);   // the way sunlight travels (world space)
uniform float sun_boost = 1.4;                   // extra light in windows facing the sun
uniform vec3 sky_tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float ripple = 0.004;                    // glass wobble (UV units)
uniform float cloud_speed = 0.035;
uniform float cloud_depth = 0.3;                 // how much the clouds dim the sun

varying vec3 w_pos;
varying vec3 w_nrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float facing_view = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float grazing = 1.0 - facing_view;
	vec2 wob = vec2(noise(w_pos.xz * 3.1 + w_pos.y * 2.3), noise(w_pos.zy * 2.7 + 7.0)) - 0.5;
	vec2 uv = UV + wob * ripple * (0.4 + grazing * 1.6);
	vec3 g = texture(glass_tex, uv).rgb;
	float lum = dot(g, vec3(0.299, 0.587, 0.114));
	float lead = 1.0 - smoothstep(0.05, 0.12, lum);

	// sunlight: the inward normal faces along the sun's travel for sunlit windows
	float sun = clamp(dot(w_nrm, normalize(sun_dir)), 0.0, 1.0);
	vec2 drift = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.37);
	float cloud = 1.0 - cloud_depth * smoothstep(0.35, 0.8, noise(w_pos.xz * 0.06 + w_pos.y * 0.03 + drift));
	float day = mix(night_glow, 1.0, clamp(light_level, 0.0, 1.0));
	float strength = emission_strength * (0.5 + sun_boost * sun * cloud) * day;
	// looking straight through a window toward the light is brightest
	float through = mix(0.6, 1.0, sqrt(facing_view));

	vec3 glass = pow(g, vec3(1.1)) * sky_tint;
	ALBEDO = mix(g * 0.2, vec3(0.025, 0.022, 0.02), lead);
	EMISSION = glass * strength * through * (1.0 - lead);
	ROUGHNESS = mix(0.06, 0.55, lead);
	METALLIC = lead * 0.4;
	SPECULAR = 0.65;
}
