extends Node
## EmoteCache: downloads chat emote images once and keeps them as textures.
##   get_texture(url)  -> the texture if it's ready, else null (and starts the download).
##   EventBus.emote_ready(url) fires when a download finishes, so bubbles can redraw.
## Files are also cached on disk (user://emote_cache/) so the next session starts warm.
## PNG, JPEG and still WebP load with the engine. GIFs (Kick / BetterTTV animated emotes)
## are decoded by GifDecoder on a worker thread and become an AnimatedTexture.
## Animated WebP can't be decoded, so those stay as their text name.
##   is_animated(tex): viewports showing it must redraw every frame to play it.
##   set_fallback(url, still): if url can't be shown (e.g. animated WebP), load still in its place.

const CACHE_DIR: String = "user://emote_cache/"
const MAX_PARALLEL: int = 4
const MAX_BYTES: int = 6 * 1024 * 1024   # reaction pictures from Stream Core can be up to 5 MB

var _textures: Dictionary = {}     # url -> Texture2D
var _failed: Dictionary = {}       # url -> true (don't retry this session)
var _queue: Array[String] = []
var _active: Dictionary = {}       # url -> HTTPRequest
var _circles: Dictionary = {}      # url -> round Texture2D (profile pictures)
var _decoding: Dictionary = {}     # url -> {id, out: Array, body, save} while a GIF decodes on a worker thread
var _fallback: Dictionary = {}     # url -> still picture to load instead when url can't be shown
var _fetch: Dictionary = {}        # url -> the address downloaded for it (its fallback, after url failed)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	set_process(false)


# ── Public API ───────────────────────────────────────────────
func get_texture(url: String) -> Texture2D:
	if url == "" or _failed.has(url):
		return null
	if _textures.has(url):
		return _textures[url]
	if not _active.has(url) and not _queue.has(url) and not _decoding.has(url):
		var path := _disk_path(url)
		if FileAccess.file_exists(path):
			var body := FileAccess.get_file_as_bytes(path)
			if GifDecoder.is_gif(body):
				_decode_gif(url, body, false)
				return null
			var disk := _decode(body)
			if disk:
				_textures[url] = disk
				return disk
		_queue.append(url)
		_pump()
	return null


## True for textures that change over time (animated emotes).
func is_animated(tex: Texture2D) -> bool:        # (not static: callers reach it through the autoload)
	return tex is AnimatedTexture


## The image cropped to a centred circle (soft edge), for profile pictures.
## null until the download is done (listen for EventBus.emote_ready).
func get_circle_texture(url: String, size: int = 128) -> Texture2D:
	if _circles.has(url):
		return _circles[url]
	var tex := get_texture(url)
	if tex is AnimatedTexture:
		tex = (tex as AnimatedTexture).get_frame_texture(0)     # animated picture: its first frame
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	img = img.duplicate()
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var side := mini(img.get_width(), img.get_height())
	@warning_ignore("integer_division")
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			if a < 1.0:
				var c := img.get_pixel(x, y)
				c.a *= a
				img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var disc := ImageTexture.create_from_image(img)
	_circles[url] = disc
	return disc


## Still picture to show under url's name if url doesn't load or can't be decoded.
func set_fallback(url: String, still: String) -> void:
	if url != "" and still != "" and still != url and not _fallback.has(url):
		_fallback[url] = still


func is_failed(url: String) -> bool:
	return _failed.has(url)


# ── Private ──────────────────────────────────────────────────
func _pump() -> void:
	while _active.size() < MAX_PARALLEL and not _queue.is_empty():
		var url: String = _queue.pop_front()
		var req := HTTPRequest.new()
		req.timeout = 15.0
		req.body_size_limit = MAX_BYTES
		add_child(req)
		_active[url] = req
		req.request_completed.connect(_on_done.bind(url, req))
		if req.request(String(_fetch.get(url, url))) != OK:
			_finish(url, req, PackedByteArray())


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, url: String, req: HTTPRequest) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		body = PackedByteArray()
	_finish(url, req, body)


func _finish(url: String, req: HTTPRequest, body: PackedByteArray) -> void:
	_active.erase(url)
	req.queue_free()
	if GifDecoder.is_gif(body):
		_decode_gif(url, body, true)
		_pump()
		return
	var tex := _decode(body)
	if tex:
		_textures[url] = tex
		var f := FileAccess.open(_disk_path(url), FileAccess.WRITE)
		if f:
			f.store_buffer(body)
		EventBus.emote_ready.emit(url)
	elif not _try_fallback(url):
		_failed[url] = true
		if body.size() > 0:
			push_warning("Emote image not supported (%s): %s" % [_kind(body), url])
	_pump()


## url didn't work: download its still picture under url's name. False when there's none left to try.
func _try_fallback(url: String) -> bool:
	if not _fallback.has(url) or _fetch.has(url):
		return false
	_fetch[url] = _fallback[url]
	_queue.append(url)
	return true


## GIF -> frames on a worker thread; _process collects the result and makes the texture.
func _decode_gif(url: String, body: PackedByteArray, save: bool) -> void:
	var out: Array = [{}]
	var id := WorkerThreadPool.add_task(func() -> void: out[0] = GifDecoder.decode(body), false, "gif decode")
	_decoding[url] = {"id": id, "out": out, "body": body, "save": save}
	set_process(true)


func _process(_delta: float) -> void:
	if _decoding.is_empty():
		set_process(false)
		return
	for url: String in _decoding.keys():
		var job: Dictionary = _decoding[url]
		if WorkerThreadPool.is_task_completed(int(job["id"])):
			WorkerThreadPool.wait_for_task_completion(int(job["id"]))
			_decoding.erase(url)
			_gif_done(url, (job["out"] as Array)[0], job["body"], bool(job["save"]))


func _exit_tree() -> void:
	for job: Dictionary in _decoding.values():
		WorkerThreadPool.wait_for_task_completion(int(job["id"]))
	_decoding.clear()


func _gif_done(url: String, result: Dictionary, body: PackedByteArray, save: bool) -> void:
	var frames: Array = result.get("frames", [])
	if frames.is_empty():
		if _try_fallback(url):
			_pump()
			return
		_failed[url] = true
		push_warning("Couldn't decode GIF emote: %s" % url)
		return
	var tex: Texture2D
	if frames.size() == 1:
		var img: Image = frames[0]
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	else:
		var delays: PackedFloat32Array = result["delays"]
		var anim := AnimatedTexture.new()
		anim.frames = mini(frames.size(), AnimatedTexture.MAX_FRAMES)
		for i in anim.frames:
			anim.set_frame_texture(i, ImageTexture.create_from_image(frames[i] as Image))
			anim.set_frame_duration(i, delays[i])
		tex = anim
	_textures[url] = tex
	if save:
		var f := FileAccess.open(_disk_path(url), FileAccess.WRITE)
		if f:
			f.store_buffer(body)
	EventBus.emote_ready.emit(url)


static func _kind(body: PackedByteArray) -> String:
	if body.size() >= 12 and body.slice(0, 4).get_string_from_ascii() == "RIFF":
		return "animated WebP" if body.slice(12, 16).get_string_from_ascii() == "VP8X" and (body[20] & 0x02) != 0 else "WebP"
	return "first bytes %s" % body.slice(0, 4).hex_encode()


func _decode(body: PackedByteArray) -> Texture2D:
	if body.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if body[0] == 0x89 and body[1] == 0x50:                      # PNG
		err = img.load_png_from_buffer(body)
	elif body[0] == 0xFF and body[1] == 0xD8:                    # JPEG
		err = img.load_jpg_from_buffer(_tidy_jpeg(body))
	elif body.slice(0, 4).get_string_from_ascii() == "RIFF" and body.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(body)
	if err != OK or img.is_empty():
		return null
	if img.get_format() == Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)     # (RGB8 isn't supported on every graphics card: avoids a warning per picture)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Redot's JPEG loader turns down a picture over small flaws that libjpeg only warns about (some
## Twitch profile pictures have them). Fixes the two common ones: stray bytes between the header
## blocks, and a missing end marker. Returns the bytes unchanged when there's nothing to fix.
static func _tidy_jpeg(body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([0xFF, 0xD8])
	var stray := false
	var whole := false
	var i := 2
	var n := body.size()
	while i + 3 < n:
		if body[i] != 0xFF:            # not a block start: stray byte
			stray = true
			i += 1
			continue
		var marker := body[i + 1]
		if marker == 0xFF:             # fill byte
			i += 1
			continue
		if marker == 0xDA:             # start of the picture data: the rest is kept as it is
			out.append_array(body.slice(i))
			whole = true
			break
		var block := 2 + ((body[i + 2] << 8) | body[i + 3])
		out.append_array(body.slice(i, i + block))
		i += block
	if not (stray and whole):
		out = body
	if out[out.size() - 2] != 0xFF or out[out.size() - 1] != 0xD9:
		out = out.duplicate()        # (packed arrays are shared: don't change the caller's)
		out.append_array(PackedByteArray([0xFF, 0xD9]))
	return out


func _disk_path(url: String) -> String:
	return CACHE_DIR + url.md5_text() + ".img"
