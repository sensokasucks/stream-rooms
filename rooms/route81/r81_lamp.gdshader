shader_type spatial;
// Route 81: the lamp heads of the streetlights in the median (r81_pieces.gd light_heads).
// A head is grey by day and shines at night in the Streetlights choice's colour: r81_trip.gd
// (_apply) writes lamp_color and glow (0 = off or daytime .. 1 = full night). There are
// two of these materials, for the poles with even and odd place numbers, so "Mixed" can make
// every other pole LED.
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform vec3 lamp_color : source_color = vec3(1.0, 0.62, 0.25);
uniform float glow = 0.0;

void vertex() {
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	ALBEDO = mix(vec3(0.7, 0.71, 0.7), lamp_color, 0.25);
	// (well over 1: the Detailed look's glow post-effect turns it into a glare round the lamp)
	EMISSION = lamp_color * glow * 5.0;
	ROUGHNESS = 0.4;
}
