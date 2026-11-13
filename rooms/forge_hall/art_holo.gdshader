shader_type spatial;
// Forge Hall: an alcove art picture shown as a hologram (Room tab > Alcove art > Art style =
// Hologram). The picture is drawn see-through and glowing, tinted towards one colour, with fine
// scan lines drifting up it and a brighter band that travels down now and then. Set up by
// rooms/forge_hall/forge_hall_room.gd (_apply_art), which also sets `level` from the house
// lights and `flicker` to 0 in photosensitive-safe mode.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform sampler2D picture : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.45, 0.95, 1.0);
// 0 = the picture's own colours, 1 = one colour only
uniform float tint_amount : hint_range(0.0, 1.0) = 0.45;
// scan lines down the picture
uniform float lines = 90.0;
// 1 = the slight waver in brightness, 0 = steady (photosensitive-safe mode)
uniform float flicker : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;
// the house light level (0..1): the hologram dims a little with the room
uniform float level = 1.0;

void fragment() {
	vec4 p = texture(picture, UV);
	float lum = dot(p.rgb, vec3(0.3, 0.59, 0.11));
	vec3 c = mix(p.rgb, tint * (0.25 + lum * 1.2), tint_amount);
	float scan = 0.75 + 0.25 * sin((UV.y * lines - TIME * 1.5) * 6.2831);
	// a soft bright band that travels down the picture every eight seconds or so
	float band = 1.0 + 0.5 * smoothstep(0.05, 0.0, abs(fract(TIME * 0.12) * 1.3 - 0.15 - UV.y));
	// a slow, shallow waver (4 percent): never a strobe
	float waver = 1.0 + flicker * 0.04 * sin(TIME * 7.0);
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.03, min(e.x, e.y));     // soft outer edge
	ALBEDO = c * scan * band * waver * 1.4 * mix(0.6, 1.0, level);
	ALPHA = p.a * opacity * edge * (0.55 + 0.45 * scan);
}
