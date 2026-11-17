shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Route 22: the soft glare round a headlight, a tail light or a neon tube at night. A small
// square (QuadMesh) that turns to face the camera and adds a round glow to the picture. Made
// by r22_vehicles.gd (headlights and tail lights) and r22_geo.gd (neon signs).
//   color      the light's colour (bright: above 1 makes the bloom pick it up),
//   strength   how much it shows right now (r22_desert.gd: night = 1, broad day = 0, and the
//              Neon tick box for signs),
//   size       metres across.
// It bends with the road like everything else beside it (r22_common.gdshaderinc), so a far
// car's lights stay on the far car.
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform vec3 color = vec3(1.0, 0.9, 0.7);
uniform float strength = 1.0;
uniform float size = 0.8;

void vertex() {
	// the square's centre, bent with the road, then the corners spread out facing the camera
	vec3 centre = r22_bend((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	vec4 view = VIEW_MATRIX * vec4(centre, 1.0);
	view.xy += VERTEX.xy * size;
	// a hair towards the camera so the light shows in front of its own lamp's glass
	view.z += 0.15;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float g = exp(-r * r * 5.0) * 0.85 + exp(-r * r * 40.0) * 1.5;
	ALBEDO = color * g * strength;
	ALPHA = 1.0;
}
