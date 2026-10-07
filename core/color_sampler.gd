class_name ColorSampler
extends RefCounted
## Static helper: averages the left / centre / right thirds of a video frame.
## Pure function (no state), safe to call from worker threads.

const SAMPLE_W: int = 36
const SAMPLE_H: int = 20


## Returns [left, center, right] as linear-ish intensities (sRGB squared, boosted).
static func sample_thirds(src: Image) -> Array[Color]:
	var out: Array[Color] = [Color.BLACK, Color.BLACK, Color.BLACK]
	if src == null or src.is_empty() or src.is_compressed():
		return out
	var img := src.duplicate() as Image
	img.resize(SAMPLE_W, SAMPLE_H, Image.INTERPOLATE_BILINEAR)
	var sums: Array[Color] = [Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]
	var counts: Array[int] = [0, 0, 0]
	for y in SAMPLE_H:
		for x in SAMPLE_W:
			@warning_ignore("integer_division")
			var col: int = mini(int(x * 3 / SAMPLE_W), 2)
			sums[col] += img.get_pixel(x, y)
			counts[col] += 1
	for i in 3:
		var c: Color = sums[i] / float(counts[i])
		out[i] = Color(c.r * c.r, c.g * c.g, c.b * c.b) * 1.6
	return out
