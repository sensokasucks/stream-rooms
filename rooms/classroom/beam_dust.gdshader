shader_type spatial;
// Dust specks for the projector beam. Particles fill a box around the beam; only the
// ones inside the cone of light show, and they twinkle as they tumble.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 beam_origin;
uniform vec3 beam_dir = vec3(0.0, 0.0, -1.0);
/// tan(half angle) of the beam cone.
uniform float beam_tan = 0.15;
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.85, 0.5);
uniform float intensity = 1.0;

varying float seed;

void vertex() {
	// camera-facing billboard at the particle's position
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec3 p = MODEL_MATRIX[3].xyz;
	seed = fract(sin(dot(p.xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// world position of this pixel (robust to how particle transforms are passed in)
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rel = wpos - beam_origin;
	float t = dot(rel, beam_dir);
	float r = length(rel - beam_dir * t);
	float cone = step(0.0, t) * (1.0 - smoothstep(t * beam_tan * 0.75, t * beam_tan, r));
	float round_mask = 1.0 - smoothstep(0.2, 0.5, length(UV - 0.5));
	float twinkle = 0.4 + 0.6 * abs(sin(TIME * (1.0 + seed * 3.0) + seed * 20.0));
	// additive: black adds nothing, so everything outside the beam / the round speck vanishes
	ALBEDO = color.rgb * intensity * twinkle * 2.0 * color.a * cone * round_mask;
}
