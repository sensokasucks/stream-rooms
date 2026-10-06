class_name PictureFile
extends RefCounted
## Turns a picture file (PNG, JPEG, WebP or GIF, animated GIFs too) into a Texture2D.
## Used for the podium pictures (Presenters tab) and for pictures a host sends to guests.
## Only these formats, checked by their first bytes, and nothing over MAX_BYTES: the bytes may
## have come over the network.

const MAX_BYTES: int = 3 * 1024 * 1024
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


## A texture from the bytes, or null. GIF decoding runs here on the calling thread
## (use WorkerThreadPool for big ones, see Presenter).
static func texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() > MAX_BYTES:
		return null
	var kind := kind_of(bytes)
	if kind == "gif":
		return _gif_texture(GifDecoder.decode(bytes))
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
