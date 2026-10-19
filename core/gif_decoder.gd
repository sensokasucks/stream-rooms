class_name GifDecoder
extends RefCounted
## Decodes GIF images (the engine can't) into full RGBA frames, for animated chat emotes.
## Pure GDScript, so call it from a worker thread (EmoteCache does).
##   decode(bytes) -> {"frames": Array[Image], "delays": PackedFloat32Array} or {} on failure.
## Handles GIF87a/89a, global/local colour tables, transparency, interlacing and the
## disposal methods (keep / clear to transparent / restore previous).
## Also used by PictureFile for GIF podium pictures. GIFs wider or taller than 2048 px are refused.

## Most frames kept; the rest of a longer GIF is dropped.
const MAX_FRAMES: int = 200
## Stop decoding past this many pixels in total (frames x width x height), to bound time and memory.
const MAX_TOTAL_PIXELS: int = 12_000_000
## Shortest frame time in seconds. A delay of 0 or 1 (hundredths) becomes 0.1 s, as browsers do.
const MIN_DELAY: float = 0.02


## True when the bytes start with "GIF" and are long enough to hold the header.
static func is_gif(bytes: PackedByteArray) -> bool:
	return bytes.size() > 13 and bytes[0] == 0x47 and bytes[1] == 0x49 and bytes[2] == 0x46   # "GIF"


## Decodes every frame onto a full-size canvas, so each returned Image is a complete picture
## (delays in seconds). See the file header for the result format.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if not is_gif(bytes):
		return {}
	var n := bytes.size()
	var w := bytes[6] | (bytes[7] << 8)
	var h := bytes[8] | (bytes[9] << 8)
	if w <= 0 or h <= 0 or w > 2048 or h > 2048:
		return {}
	# header byte 10: bit 7 = has a global colour table, low 3 bits = its size (2^(n+1) colours)
	var packed := bytes[10]
	var pos := 13
	var global_pal := PackedByteArray()
	if packed & 0x80:
		var gsize := 3 * (1 << ((packed & 7) + 1))
		if pos + gsize > n:
			return {}
		global_pal = bytes.slice(pos, pos + gsize)
		pos += gsize

	# the picture so far as RGBA bytes; each frame is drawn over it
	var canvas := PackedByteArray()
	canvas.resize(w * h * 4)
	canvas.fill(0)
	var frames: Array[Image] = []
	var delays := PackedFloat32Array()
	var delay := 0.1
	var transparent := -1
	var disposal := 0
	var total := 0

	while pos < n:
		var block := bytes[pos]
		pos += 1
		if block == 0x3B:          # trailer
			break
		elif block == 0x21:        # extension
			if pos >= n:
				break
			var label := bytes[pos]
			pos += 1
			# graphic control extension: disposal, delay and transparent colour for the next image
			if label == 0xF9 and pos + 5 < n and bytes[pos] >= 4:
				var p := bytes[pos + 1]
				disposal = (p >> 2) & 7
				var d := bytes[pos + 2] | (bytes[pos + 3] << 8)
				delay = 0.1 if d <= 1 else maxf(float(d) / 100.0, MIN_DELAY)
				transparent = bytes[pos + 4] if (p & 1) else -1
			pos = _skip_sub_blocks(bytes, pos)
		elif block == 0x2C:        # image
			if pos + 9 > n:
				break
			var fx := bytes[pos] | (bytes[pos + 1] << 8)
			var fy := bytes[pos + 2] | (bytes[pos + 3] << 8)
			var fw := bytes[pos + 4] | (bytes[pos + 5] << 8)
			var fh := bytes[pos + 6] | (bytes[pos + 7] << 8)
			var fp := bytes[pos + 8]
			pos += 9
			var pal := global_pal
			if fp & 0x80:
				var lsize := 3 * (1 << ((fp & 7) + 1))
				if pos + lsize > n:
					break
				pal = bytes.slice(pos, pos + lsize)
				pos += lsize
			if pos >= n:
				break
			var min_code := bytes[pos]
			pos += 1
			var data := PackedByteArray()
			while pos < n:
				var sz := bytes[pos]
				pos += 1
				if sz == 0:
					break
				data.append_array(bytes.slice(pos, mini(pos + sz, n)))
				pos += sz
			if min_code < 2 or min_code > 11 or pal.is_empty() or fw <= 0 or fh <= 0:
				continue
			# disposal 3 ("restore previous") needs the canvas as it was before this frame
			var saved := canvas.duplicate() if disposal == 3 else PackedByteArray()
			var idx := _lzw(data, min_code, fw * fh)
			_draw(canvas, w, h, idx, pal, fx, fy, fw, fh, transparent, (fp & 0x40) != 0)
			frames.append(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, canvas))
			delays.append(delay)
			total += w * h
			if frames.size() >= MAX_FRAMES or total >= MAX_TOTAL_PIXELS:
				break
			# get the canvas ready for the next frame
			if disposal == 2:
				_clear_rect(canvas, w, h, fx, fy, fw, fh)
			elif disposal == 3:
				canvas = saved
			delay = 0.1
			transparent = -1
			disposal = 0
		else:
			break
	if frames.is_empty():
		return {}
	return {"frames": frames, "delays": delays}


## Skips a chain of GIF data sub-blocks (length byte + data, ended by a 0 length) and returns
## the position after it.
static func _skip_sub_blocks(bytes: PackedByteArray, pos: int) -> int:
	var n := bytes.size()
	while pos < n:
		var sz := bytes[pos]
		pos += 1 + sz
		if sz == 0:
			break
	return pos


## LZW -> colour indices (npix of them; short data leaves the rest 0).
## Standard GIF LZW: a code table of up to 4096 entries stored as prefix / last byte / first
## byte / length, codes read least-significant bit first, code size growing up to 12 bits.
static func _lzw(data: PackedByteArray, min_code: int, npix: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(npix)
	var prefix := PackedInt32Array()
	prefix.resize(4096)
	var suffix := PackedByteArray()
	suffix.resize(4096)
	var first := PackedByteArray()
	first.resize(4096)
	var lengths := PackedInt32Array()
	lengths.resize(4096)
	var clear := 1 << min_code
	var eoi := clear + 1
	for i in clear:
		prefix[i] = -1
		suffix[i] = i
		first[i] = i
		lengths[i] = 1
	var code_size := min_code + 1
	var next := eoi + 1
	var prev := -1
	var bitbuf := 0
	var bits := 0
	var pos := 0
	var op := 0
	var n := data.size()
	while op < npix:
		while bits < code_size and pos < n:
			bitbuf |= data[pos] << bits
			pos += 1
			bits += 8
		if bits < code_size:
			break
		var code := bitbuf & ((1 << code_size) - 1)
		bitbuf >>= code_size
		bits -= code_size
		if code == clear:
			code_size = min_code + 1
			next = eoi + 1
			prev = -1
			continue
		if code == eoi:
			break
		if prev == -1:
			if code >= clear:
				break
			out[op] = code
			op += 1
			prev = code
			continue
		if code < next:
			if next < 4096:
				prefix[next] = prev
				suffix[next] = first[code]
				first[next] = first[prev]
				lengths[next] = lengths[prev] + 1
				next += 1
		elif code == next and next < 4096:
			prefix[next] = prev
			suffix[next] = first[prev]
			first[next] = first[prev]
			lengths[next] = lengths[prev] + 1
			next += 1
		else:
			break          # corrupt stream
		# write the code's string back to front by walking its prefix chain
		var length := lengths[code]
		var p := op + length - 1
		var k := code
		while k != -1:
			if p < npix:
				out[p] = suffix[k]
			p -= 1
			k = prefix[k]
		op += length
		prev = code
		if next == (1 << code_size) and code_size < 12:
			code_size += 1
	return out


## Paints one frame's colour indices onto the canvas at (fx, fy), skipping the transparent
## index. Interlaced frames store their rows in four passes (every 8th row from 0, every 8th
## from 4, every 4th from 2, every 2nd from 1); `rows` maps the stored row to the real one.
static func _draw(canvas: PackedByteArray, w: int, h: int, idx: PackedByteArray, pal: PackedByteArray,
		fx: int, fy: int, fw: int, fh: int, transparent: int, interlaced: bool) -> void:
	var rows := PackedInt32Array()
	rows.resize(fh)
	if interlaced:
		var r := 0
		for pass_def: Array in [[0, 8], [4, 8], [2, 4], [1, 2]]:
			var y: int = pass_def[0]
			while y < fh:
				rows[r] = y
				r += 1
				y += int(pass_def[1])
	else:
		for y in fh:
			rows[y] = y
	@warning_ignore("integer_division")
	var ncol := pal.size() / 3
	for r in fh:
		var cy := fy + rows[r]
		if cy < 0 or cy >= h:
			continue
		var src := r * fw
		var row_base := cy * w
		for x in fw:
			var c := idx[src + x]
			if c == transparent or c >= ncol:
				continue
			var cx := fx + x
			if cx >= w:
				break
			var o := (row_base + cx) * 4
			var pc := c * 3
			canvas[o] = pal[pc]
			canvas[o + 1] = pal[pc + 1]
			canvas[o + 2] = pal[pc + 2]
			canvas[o + 3] = 255


## Disposal 2: makes a frame's rectangle fully transparent again.
static func _clear_rect(canvas: PackedByteArray, w: int, h: int, fx: int, fy: int, fw: int, fh: int) -> void:
	for y in range(maxi(fy, 0), mini(fy + fh, h)):
		for x in range(maxi(fx, 0), mini(fx + fw, w)):
			var o := (y * w + x) * 4
			canvas[o] = 0
			canvas[o + 1] = 0
			canvas[o + 2] = 0
			canvas[o + 3] = 0
