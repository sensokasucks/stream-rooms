shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, world_vertex_coords;
// The filler crowd (CrowdLayer): one MultiMesh of the audience silhouette, one instance per
// crowd seat. Everything that would cost script time per person happens here instead:
//   - each silhouette turns to face the camera (upright, like the chat audience's sprites),
//   - a slow idle sway, different for everyone (INSTANCE_CUSTOM.x = phase),
//   - crowd-wide motions (dance, cheer, wiggle, jump) with a random start per person,
//   - the stadium wave, rolling across the room with the same timing as the chat audience,
//   - fading out (dithered) when the camera is right next to someone,
//   - dimming with the house lights.
// INSTANCE_COLOR = tint; alpha 0 hides that person (an empty seat or a chatter's seat, which
// the chat audience draws itself).

uniform sampler2D silhouette : source_color, filter_linear_mipmap;
uniform vec2 quad_size = vec2(0.624, 0.78);    // bust width, height (metres at scale 1)
uniform float lift = 0.18;                     // bust bottom above the seat
uniform float brightness = 1.0;
uniform float near_fade_start = 1.2;
uniform float near_fade_end = 2.6;
uniform float sway = 1.0;
uniform float fill_lift = 0.12;                // lifts the dark fill a little toward the tint
uniform int motion_style = 0;                  // 1 dance, 2 cheer, 3 wiggle, 4 jump
uniform float motion_t = -1.0;                 // seconds since the motion started (-1 = none)
uniform float motion_len = 0.0;
uniform float wave_t = -1.0;                   // seconds since the wave started (-1 = none)
uniform vec3 wave_across = vec3(1.0, 0.0, 0.0);
uniform float wave_lo = 0.0;
uniform float wave_speed = 1.0;

varying vec3 v_tint;
varying float v_near;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	v_tint = COLOR.rgb;
	if (COLOR.a < 0.5) {
		VERTEX = origin;           // hidden: collapse the quad
		v_near = 0.0;
	} else {
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 to_cam = cam - origin;
		to_cam.y = 0.0;
		to_cam = length(to_cam) > 0.0001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
		float ph = INSTANCE_CUSTOM.x * 6.2831853;
		vec3 off = right * sin(TIME * 0.6 + ph) * 0.012 * sway;
		if (motion_t >= 0.0 && motion_t < motion_len) {
			float t = motion_t - INSTANCE_CUSTOM.x * 0.25;
			float ease = smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(motion_len - 0.3, motion_len, motion_t));
			if (t > 0.0) {
				if (motion_style == 1) {          // dance: bob and sway on a 0.3 s beat
					float b = t / 0.3 * 3.14159265;
					off += (right * sin(b) * 0.09 + vec3(0.0, abs(sin(b)) * 0.1, 0.0)) * ease;
				} else if (motion_style == 2) {   // cheer: up, bouncing
					off.y += (0.32 + 0.08 * abs(sin(t * 10.5))) * ease;
				} else if (motion_style == 3) {   // wiggle
					off += right * sin(t * 31.4) * 0.07 * ease;
				} else if (motion_style == 4) {   // jump
					off.y += abs(sin(t * 7.0)) * 0.22 * ease;
				}
			}
		}
		if (wave_t >= 0.0) {
			float head = dot(origin, wave_across);
			float tt = wave_t - (head - wave_lo) / (4.0 * wave_speed);
			if (tt > 0.0 && tt < 0.4) {
				off.y += sin(tt / 0.4 * 3.14159265) * 0.3;
			}
		}
		float x = (UV.x - 0.5) * quad_size.x;
		float y = lift + (1.0 - UV.y) * quad_size.y;
		VERTEX = origin + (right * x + vec3(0.0, y, 0.0) + off) * sc;
		NORMAL = to_cam;
		vec3 head_pos = origin + vec3(0.0, (lift + quad_size.y) * sc, 0.0);
		v_near = smoothstep(near_fade_start * sc, near_fade_end * sc, distance(cam, head_pos));
	}
}

void fragment() {
	vec4 tex = texture(silhouette, UV);
	if (tex.a < 0.5) {
		discard;
	}
	// dithered fade next to the camera (no sorting needed, unlike real transparency)
	const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	ivec2 cell = ivec2(mod(floor(FRAGCOORD.xy), 4.0));
	float bayer = (BAYER[cell.x + cell.y * 4] + 0.5) / 16.0;
	if (v_near < 0.999 && bayer > v_near * 0.92 + 0.08) {
		discard;
	}
	ALBEDO = (tex.rgb + fill_lift) * v_tint * brightness;
}
