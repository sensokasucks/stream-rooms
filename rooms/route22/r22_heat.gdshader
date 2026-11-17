shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Route 22: heat shimmer. A tall see-through sheet standing across the road (and over the far
// desert) that wobbles whatever is behind it, the way hot air over asphalt does. r22_desert.gd
// puts a few of them out (_build_heat) and sets `amount` from the Heat slider, the daylight
// and the weather (none at night, in rain or in a dust storm).
// The wobble is strongest at the sheet's foot and fades out towards its top and its ends, so
// the sheet itself never shows as a shape. It reads the picture drawn so far (the screen
// texture), so it only bends things further away than itself.
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D rock_noise : filter_linear_mipmap, repeat_enable;
// 0 = no shimmer (the sheet isn't drawn at all then: r22_desert.gd hides it), 1 = a hot day.
uniform float amount = 0.0;

void fragment() {
	// UV.y is 0 at the sheet's top and 1 at its foot
	float ends = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	vec2 n = texture(rock_noise, vec2(UV.x * 6.0, UV.y * 1.5 + TIME * 0.35)).bb - 0.5;
	n.y = texture(rock_noise, vec2(UV.x * 5.0 + 0.4, UV.y * 2.0 + TIME * 0.5)).b - 0.5;
	vec2 offset = n * 0.006 * amount * pow(UV.y, 1.5) * ends;
	ALBEDO = textureLod(screen, SCREEN_UV + offset, 0.0).rgb;
	ALPHA = clamp(amount * ends * 4.0, 0.0, 1.0) * smoothstep(0.0, 0.5, UV.y);
}
