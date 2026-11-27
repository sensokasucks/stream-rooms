// Route 22 (the Drive-In and the Cruise rooms): what every moving or weather-touched surface
// shares. Included by r22_rock, r22_ground, r22_road, r22_prop, r22_picture and r22_glow.
//
// The Cruise's car never moves: the scenery slides past it along +Z instead (r22_trip.gd), so
// the car stays at the world's origin and nothing ever gets far from it (no far-coordinate
// jitter). Two tricks sell the drive on top of that:
//   - the bend: the road and everything beside it curve sideways and over hills the further
//     they are from the car (r22_bend). bend and hill are tiny numbers (metres of shift per
//     metre squared) that r22_desert.gd eases about slowly while driving; 0 in the Drive-In.
//   - travel: how far the car has driven, wrapped at TRAVEL_WRAP metres, for the things that do
//     not move as nodes (the ground's and the road's texture, the cloud shadows). Every texture
//     size that scrolls with it must divide 2048 m so the wrap never shows.
// r22_desert.gd (set_shared) writes these uniforms on every Route 22 material each frame.

// Sideways curve and hill: metres of shift per (metre beyond bend_start)^2.
uniform float bend = 0.0;
uniform float hill = 0.0;
// Metres round the car (along Z) that stay straight, so the car and the guests never bend.
uniform float bend_start = 18.0;
// Metres driven, wrapped at 2048 (r22_desert.gd TRAVEL_WRAP).
uniform float travel = 0.0;
// 0 = dry, 1 = soaked (the Thunderstorm and After rain weather).
uniform float wet = 0.0;
// How dark the drifting cloud shadows are (0 = none: clear sky or night).
uniform float cloud_shadow = 0.0;
// Metres the cloud shadows have blown along (the wind), from r22_desert.gd.
uniform vec2 cloud_drift = vec2(0.0);
// The sky's noise picture (rooms/campfire/textures/sky_noise.png): r = cloud bodies.
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
// 0 = the plain low-poly look, 1 = with the photo detail textures (the room's Set detail).
uniform float detail = 1.0;

// Route 81's far land (out to nearly 3 km, rooms/route81/r81_trip.gd FAR_AHEAD): beyond
// BEND_EXACT metres the distance the bend is worked out from grows more and more slowly and
// levels off about bend_far metres further, so the far road curves away instead of swinging
// kilometres sideways or into the sky. 0 (Route 22) = the plain bend at every distance.
uniform float bend_far = 0.0;
const float BEND_EXACT = 900.0;

// Where a world point is drawn once the road bends and climbs away from the car.
vec3 r22_bend(vec3 world) {
	float d = max(abs(world.z) - bend_start, 0.0);
	if (bend_far > 0.0 && d > BEND_EXACT) {
		d = BEND_EXACT + bend_far * tanh((d - BEND_EXACT) / bend_far);
	}
	world.x += bend * d * d;
	world.y += hill * d * d;
	return world;
}

// Moves a vertex (object space, as vertex() gets it) by the bend. model = MODEL_MATRIX.
vec3 r22_bend_vertex(vec3 v, mat4 model) {
	vec3 w = (model * vec4(v, 1.0)).xyz;
	vec3 shift = r22_bend(w) - w;
	if (dot(shift, shift) < 1e-8) {
		return v;
	}
	return v + inverse(mat3(model)) * shift;
}

// 1 = in sunlight, down to about 0.5 under a passing cloud's shadow. world = the point before
// the bend (the shadow lies on the ground the point belongs to). 1 / 1024 = one noise picture
// per 1024 m, which divides the travel wrap.
float r22_cloud_shade(vec3 world) {
	if (cloud_shadow <= 0.001) {
		return 1.0;
	}
	vec2 p = (vec2(world.x, world.z - travel) + cloud_drift) / 1024.0;
	float n = texture(cloud_noise, p).r * 0.7 + texture(cloud_noise, p * 2.0 + 0.31).r * 0.3;
	return 1.0 - cloud_shadow * smoothstep(0.46, 0.6, n) * 0.5;
}
