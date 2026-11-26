shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front, fog_disabled;
// Cabin: Ocean: one of the lighthouse's two beams (cabin_ocean.gd _build_lighthouse): a long
// cone lying flat from the lamp, drawn as a shaft of light in the air rather than as a solid
// cone. Only the cone's far side is drawn (cull_front), so each pixel is drawn once, from
// outside the cone or inside it. For each pixel the shader finds where the line of sight passes
// closest to the beam's middle line: right through the middle is brightest, grazing the edge is
// nothing, so the beam has no hard outline. It is brightest at the lamp and fades out along its
// length long before its far end.
// log_cabin_room.gd (_apply_ocean) sets `strength` (0 by day, up at dusk and at night) and
// `haze` (0 clear, 0.5 light fog, 1 heavy fog: in fog the shaft spreads out and goes dim, as a
// far beam does when the fog between scatters it).
// The cone mesh is a CylinderMesh standing along its own Y: the narrow end (at the lamp) is at
// +HALF, the wide end at -HALF. Keep HALF and the radii in step with _build_lighthouse.

uniform float strength = 0.0;
uniform float haze : hint_range(0.0, 1.0) = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.92, 0.72);
// the cone's size (metres): half its length, and its radius at the lamp and at the far end
uniform float half_len = 160.0;
uniform float r_lamp = 0.5;
uniform float r_end = 18.0;

varying vec3 l_pos;

void vertex() {
	l_pos = VERTEX;
}

void fragment() {
	// the camera in the cone's own space (the cone is only turned and moved, never scaled)
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 ray = l_pos - cam;
	float far_t = length(ray);
	vec3 dir = ray / max(far_t, 0.0001);
	// where along the line of sight it passes closest to the middle line (the Y axis), kept
	// between the camera and this far-side pixel
	float dd = dot(dir.xz, dir.xz);
	float t = dd > 0.00001 ? -dot(cam.xz, dir.xz) / dd : 0.0;
	t = clamp(t, 0.0, far_t);
	vec3 q = cam + dir * t;
	// how far along the beam that is: 0 at the lamp, 1 at the far end
	float s = clamp((half_len - q.y) / (2.0 * half_len), 0.0, 1.0);
	float r = mix(r_lamp, r_end, s);
	float edge = clamp(length(q.xz) / r, 0.0, 1.0);
	// across the beam: a soft round falloff; in fog a wider, flatter one
	float across = pow(1.0 - edge, mix(1.7, 0.8, haze));
	// along the beam: strong near the lamp, gone well before the far end (shorter in fog)
	float along = exp(-s * mix(2.2, 5.0, haze)) * (1.0 - smoothstep(0.6, 0.97, s));
	ALBEDO = color * strength * across * along * mix(0.6, 0.2, haze);
}
