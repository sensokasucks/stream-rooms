class_name ColorSampler
extends RefCounted
## Static helper: averages the left / centre / right thirds of a video frame.
## Pure function (no state), safe to call from worker threads.
## Used by CaptureServer (browser frames, on its thread) and GpuFrameSampler (video / NDI / Spout).
## ScreenFeed sends the result out as EventBus.screen_colors_changed, which ScreenLights uses to
## light the room in the screen's colours.

## Size in pixels the frame is shrunk to before averaging. Small on purpose: this runs for every
## frame. GpuFrameSampler sizes its viewport from these too.
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
			# which third this column falls in: 0 left, 1 centre, 2 right
			@warning_ignore("integer_division")
			var col: int = mini(int(x * 3 / SAMPLE_W), 2)
			sums[col] += img.get_pixel(x, y)
			counts[col] += 1
	for i in 3:
		var c: Color = sums[i] / float(counts[i])
		# squaring is a cheap sRGB-to-linear step; the 1.6 makes the room lights bright enough
		out[i] = Color(c.r * c.r, c.g * c.g, c.b * c.b) * 1.6
	return out
