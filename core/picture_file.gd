class_name PictureFile
extends RefCounted
## Turns a picture file (PNG, JPEG, WebP or GIF, animated GIFs too) into a Texture2D.
## Used for the podium pictures (Presenters tab) and for pictures a host sends to guests.
## Only these formats, checked by their first bytes, and nothing over MAX_BYTES: the bytes may
## have come over the network.

const MAX_BYTES: int = 3 * 1024 * 1024
## Widest / tallest picture decoded. A small file can claim a huge size (a 2 MB PNG of
## 16000 x 16000 pixels needs 1 GB once decoded), so the size is read from the header first.
const MAX_SIDE: int = 4096
const EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "gif"]


## "png" | "jpg" | "webp" | "gif" from the first bytes, or "" for anything else.
static func kind_of(bytes: PackedByteArray) -> String:
	if bytes.size() < 12:
		return ""
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		return "png"
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return "jpg"
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	if GifDecoder.is_gif(bytes):
		return "gif"
	return ""


## The width and height a PNG, JPEG or WebP says it has (from its header, nothing decoded), or
## (-1, -1) when it can't tell.
static func declared_size(bytes: PackedByteArray) -> Vector2i:
	var n := bytes.size()
	if n >= 24 and bytes[0] == 0x89 and bytes[1] == 0x50:            # PNG: IHDR right after the signature
		return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
	if n >= 4 and bytes[0] == 0xFF and bytes[1] == 0xD8:              # JPEG: the first "start of frame" block
		var i := 2
		while i + 8 < n:
			if bytes[i] != 0xFF:
				i += 1              # stray byte (some profile pictures have them)
				continue
			var m := bytes[i + 1]
			if m == 0xFF or m == 0x01 or (m >= 0xD0 and m <= 0xD7):
				i += 1 if m == 0xFF else 2
				continue
			if m >= 0xC0 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC:
				return Vector2i((bytes[i + 7] << 8) | bytes[i + 8], (bytes[i + 5] << 8) | bytes[i + 6])
			if m == 0xDA:
				break
			i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3])
		return Vector2i(-1, -1)
	if n >= 32 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		match bytes.slice(12, 16).get_string_from_ascii():
			"VP8 ":
				return Vector2i(bytes.decode_u16(26) & 0x3FFF, bytes.decode_u16(28) & 0x3FFF)
			"VP8L":
				var b := bytes.decode_u32(21)
				return Vector2i((b & 0x3FFF) + 1, ((b >> 14) & 0x3FFF) + 1)
			"VP8X":
				return Vector2i((bytes.decode_u32(24) & 0xFFFFFF) + 1, (bytes.decode_u32(27) & 0xFFFFFF) + 1)
	return Vector2i(-1, -1)


## True when the header says the picture is bigger than MAX_SIDE either way.
static func too_big(bytes: PackedByteArray) -> bool:
	var sz := declared_size(bytes)
	return sz.x > MAX_SIDE or sz.y > MAX_SIDE


static func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


## A texture from the bytes, or null. GIF decoding runs here on the calling thread
## (use WorkerThreadPool for big ones, see Presenter).
static func texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() > MAX_BYTES:
		return null
	var kind := kind_of(bytes)
	if kind == "gif":
		return _gif_texture(GifDecoder.decode(bytes))
	if too_big(bytes):
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match kind:
		"png": err = img.load_png_from_buffer(bytes)
		"jpg": err = img.load_jpg_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	if img.get_format() == Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The decoded GIF (GifDecoder.decode) as a still or animated texture, or null.
static func _gif_texture(decoded: Dictionary) -> Texture2D:
	var frames: Array = decoded.get("frames", [])
	if frames.is_empty():
		return null
	if frames.size() == 1:
		return ImageTexture.create_from_image(frames[0] as Image)
	var delays: PackedFloat32Array = decoded["delays"]
	var anim := AnimatedTexture.new()
	anim.frames = mini(frames.size(), AnimatedTexture.MAX_FRAMES)
	for i in anim.frames:
		anim.set_frame_texture(i, ImageTexture.create_from_image(frames[i] as Image))
		anim.set_frame_duration(i, delays[i])
	return anim


## The file's bytes if it looks like a picture we can show, else empty.
static func read_file(path: String) -> PackedByteArray:
	if path.strip_edges() == "" or not FileAccess.file_exists(path):
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > MAX_BYTES or kind_of(bytes) == "":
		return PackedByteArray()
	return bytes
