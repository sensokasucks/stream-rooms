class_name CurtainSounds
extends RefCounted
## Sounds for the stage curtain, made in code (no audio files): a cloth swish, a snare drum
## roll that swells, and a cymbal crash with a bass hit. Built once and cached.

const RATE: int = 44100

static var _cache: Dictionary = {}


static func swish(seconds: float) -> AudioStreamWAV:
	var key := "swish%.2f" % seconds
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / float(n)
		# the sweep: brighter in the middle of the move, soft at both ends
		var env := sin(PI * t)
		env = env * env * (0.75 + 0.25 * sin(t * 37.0) * sin(t * 13.0))
		var cut := 0.04 + 0.22 * env
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * cut
		lp2 += (lp - lp2) * cut
		out[i] = (lp - lp2 * 0.6) * env * 1.8
	var s := _to_wav(out)
	_cache[key] = s
	return s


## A drum roll that swells for `seconds`, ending on a bass hit and a cymbal crash.
static func drum_roll(seconds: float) -> AudioStreamWAV:
	var key := "roll%.2f" % seconds
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var crash_len := 2.2
	var n := int((seconds + crash_len) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var roll_n := int(seconds * RATE)
	# snare roll: rapid strokes, each a short burst of noise plus a little body tone
	var t := 0.0
	var stroke := 0
	while t < seconds:
		var rate := lerpf(14.0, 22.0, t / seconds)
		var gain := lerpf(0.18, 0.85, pow(t / seconds, 1.6)) * (0.85 if stroke % 2 else 1.0)
		var start := int(t * RATE)
		var length := int(0.07 * RATE)
		for k in length:
			var i := start + k
			if i >= roll_n:
				break
			var e := exp(-float(k) / (0.018 * RATE))
			var tone := sin(TAU * 190.0 * float(k) / RATE) * 0.35
			out[i] += (rng.randf_range(-1.0, 1.0) * 0.8 + tone) * e * gain
		t += 1.0 / rate
		stroke += 1
	# bass hit + crash
	var lp := 0.0
	for k in n - roll_n:
		var i := roll_n + k
		var tt := float(k) / RATE
		var boom := sin(TAU * (55.0 + 40.0 * exp(-tt * 20.0)) * tt) * exp(-tt * 5.0) * 0.9
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.5
		var shimmer := (white - lp) * exp(-tt * 1.6) * 0.75      # high-passed noise, long decay
		out[i] += boom + shimmer
	var s := _to_wav(out)
	_cache[key] = s
	return s


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var scale := 0.9 / peak
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * scale, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
