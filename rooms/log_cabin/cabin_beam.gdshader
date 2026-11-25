shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
// Cabin: Ocean: one of the lighthouse's two beams (cabin_ocean.gd _build_lighthouse): a long
// cone lying flat from the lamp, added to the picture as soft light. Brightest at the lamp,
// fading out along its length, and soft at its edges (where the cone's side is seen edge-on it
// fades, so it reads as light in the air, not as a solid cone). log_cabin_room.gd
// (_apply_ocean) sets `strength`: 0 by day, up at dusk and at night, more in fog (the beam
// shows best when there is something in the air to light).

uniform float strength = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.92, 0.72);

void fragment() {
	// UV.y runs 0 at the cone's narrow end (the lamp) to 1 at its wide end
	float along = pow(1.0 - clamp(UV.y, 0.0, 1.0), 1.6);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = smoothstep(0.0, 0.7, facing);
	ALBEDO = color * strength * along * soft * 0.35;
}
