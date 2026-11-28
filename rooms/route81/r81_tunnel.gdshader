shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Route 81: the inside of a tunnel (r81_pieces.gd builds the lining: two side walls and an
// arched roof per road). It is drawn without the sun or the sky (unshaded): all its light is
// worked out here from the row of lamps along the roof, one every 8 m of the mesh's own Z
// (tunnel pieces are 80 m long, so the rows carry on from piece to piece).
//   UV.x  0 = the lower wall (pale tiles), 1 = the concrete arch, 2 = a lamp, 3 = the dark
//         outside of the tube (seen only by a camera that ends up inside the hill),
//   UV.y  height above the road, metres.
// No distance fog either: the sky-coloured haze does not belong inside a mountain.
// lamp_color: the Streetlights choice's colour (r81_trip.gd _apply: orange sodium or white LED).
#include "res://rooms/route22/r22_common.gdshaderinc"

uniform sampler2D tex_concrete : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 lamp_color : source_color = vec3(1.0, 0.62, 0.25);
// How much brighter the lining is next to a lamp than between two: 1 = full, less in
// photosensitive-safe mode (r81_trip.gd), so the walls sliding by never pulse hard.
uniform float pulse = 1.0;

varying vec3 o_pos;
varying float kind;
varying float height;

void vertex() {
	o_pos = VERTEX;
	kind = UV.x;
	height = UV.y;
	VERTEX = r22_bend_vertex(VERTEX, MODEL_MATRIX);
}

void fragment() {
	// how close this spot is to a lamp, along the tunnel (1 under one, 0 halfway between)
	float near = mix(0.5, smoothstep(4.0, 0.0, abs(fract(o_pos.z / 8.0) - 0.5) * 8.0), pulse);
	float grain = detail > 0.5 ? texture(tex_concrete, vec2(o_pos.z, height + o_pos.x) / 4.0).r * 2.0 : 1.0;
	vec3 col;
	if (kind > 2.5) {
		col = vec3(0.02);
	} else if (kind > 1.5) {
		col = lamp_color * 3.5;
	} else if (kind > 0.5) {
		// the arch: grey concrete, brightest round the lamps, soot-dark between
		col = vec3(0.3, 0.29, 0.27) * grain * lamp_color * (0.25 + 0.9 * near);
	} else {
		// the walls: pale tiles in rows, a dark kerb stripe at the bottom
		vec2 tile = fract(vec2(o_pos.z / 0.4, height / 0.2));
		float joint = step(0.06, tile.x) * step(0.1, tile.y);
		vec3 wall = mix(vec3(0.28), vec3(0.72, 0.7, 0.64), joint) * (0.85 + 0.15 * grain);
		wall = mix(vec3(0.08), wall, smoothstep(0.25, 0.3, height));
		col = wall * lamp_color * (0.35 + 0.55 * near) * (1.0 - 0.3 * smoothstep(1.0, 4.5, height));
	}
	ALBEDO = col;
}
