// Shared by camp_sky.gdshader and camp_water.gdshader (the Lakeside Campfire room), so the lake
// mirrors the same far shore the sky draws: the outline of the mountains, two ridges of hills and of the tree
// line across the lake, as a height above the horizon for each compass direction.
// Heights are "how far up the view direction's y must be" (0 = the horizon, 1 = straight up).

float hz_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// Smooth noise round the compass. az: the direction's angle in radians; freq: bumps per turn
// (a whole number, so the outline joins up where the angle wraps).
float hz_noise(float az, float freq, float seed) {
	float x = (az / 6.2831853 + 0.5) * freq;
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hz_hash(mod(i, freq) + seed), hz_hash(mod(i + 1.0, freq) + seed), f);
}

// The mountains behind everything: sharp, jagged peaks (creased noise gives the points), tallest
// to the north over the lake and lower round the sides and behind the camp. camp_sky.gdshader
// puts snow on their tops; the lake mirrors their outline.
float hz_peaks(float az) {
	float crease_a = 1.0 - abs(2.0 * hz_noise(az, 17.0, 51.0) - 1.0);
	float crease_b = 1.0 - abs(2.0 * hz_noise(az, 43.0, 71.0) - 1.0);
	float crease_c = 1.0 - abs(2.0 * hz_noise(az, 101.0, 13.0) - 1.0);
	float north = 0.55 + 0.45 * cos(az);                 // 1 over the lake, 0.1 behind the camp
	float range = 0.5 + 0.5 * hz_noise(az, 5.0, 60.0);     // whole massifs and the gaps between them
	return 0.07 + north * (0.04 * range + (0.4 + 0.6 * range) * (0.15 * crease_a + 0.06 * crease_b + 0.02 * crease_c));
}

// The far ridge: tall, soft hills in front of the mountains.
float hz_far_ridge(float az) {
	return 0.045 + 0.075 * hz_noise(az, 9.0, 3.0) + 0.035 * hz_noise(az, 23.0, 11.0) + 0.012 * hz_noise(az, 61.0, 7.0);
}

// The near ridge: lower, rougher hills in front of it.
float hz_near_ridge(float az) {
	return 0.03 + 0.06 * hz_noise(az, 13.0, 31.0) + 0.03 * hz_noise(az, 37.0, 17.0) + 0.008 * hz_noise(az, 97.0, 5.0);
}

// The tree line on the far shore: a low band with a spiky top (pointed firs).
float hz_tree_line(float az) {
	float spikes = abs(fract((az / 6.2831853 + 0.5) * 520.0) - 0.5) * 2.0;        // 0 at a tree's tip side, 1 between
	float tall = hz_noise(az, 173.0, 41.0);
	return 0.012 + 0.012 * hz_noise(az, 29.0, 23.0) + (1.0 - spikes) * (0.006 + 0.012 * tall);
}
