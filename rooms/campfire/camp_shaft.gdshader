shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Lakeside Campfire: one sunbeam slanting down through the trees when the sun is low.
// rooms/campfire/campfire_room.gd (_build_shafts, _apply_shafts) lays a few long flat strips
// along the sun's direction and sets `color` (the sun's colour times how strong the beams are;
// black = nothing drawn). The strip's light is added to the picture: soft at both sides,
// fading out at both ends, with a few brighter streaks along it. It does not move or flash.
// UV.x = across the beam, UV.y = along it (0 = the ground end... 1 = up towards the sun).

uniform vec3 color : source_color = vec3(0.0);

void fragment() {
	float across = sin(UV.x * 3.14159);
	float streaks = 0.65 + 0.35 * sin(UV.x * 23.0 + 1.3) * sin(UV.x * 7.0);
	float ends = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.55, UV.y);
	ALBEDO = color * across * across * streaks * ends;
}
