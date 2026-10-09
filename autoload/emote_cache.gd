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
## Busy chat: the round profile pictures are made on worker threads from the picture's bytes (no
## read-back from the graphics card, no per-pixel work on the main thread), a few finished ones
## per frame; and both caches have a size budget (MAX_CACHE_BYTES): the pictures used longest ago
## are dropped, except ones a seat, bubble or chat window still shows (they'd come back as a copy).

const CACHE_DIR: String = "user://emote_cache/"
const MAX_PARALLEL: int = 4
const MAX_BYTES: int = 6 * 1024 * 1024   # reaction pictures from Stream Core can be up to 5 MB
## Pictures and emotes kept in memory (and on the graphics card), estimated with mipmaps.
const MAX_CACHE_BYTES: int = 256 * 1024 * 1024
## When over budget, drop pictures until the cache is down to this share of it.
const TRIM_TO: float = 0.8
## Round profile pictures turned into textures per frame (each one is an upload to the graphics card).
const CIRCLES_PER_FRAME: int = 6
## Forget failed addresses after this many (they'd be retried, which is fine).
const MAX_FAILED: int = 5000

var _textures: Dictionary = {}     # url -> Texture2D
var _failed: Dictionary = {}       # url -> true (don't retry this session)
var _queue: Array[String] = []
var _active: Dictionary = {}       # url -> HTTPRequest
var _circles: Dictionary = {}      # url -> round Texture2D (profile pictures)
var _decoding: Dictionary = {}     # url -> {id, out: Array, body, save} while a GIF decodes on a worker thread
var _fallback: Dictionary = {}     # url -> still picture to load instead when url can't be shown
var _fetch: Dictionary = {}        # url -> the address downloaded for it (its fallback, after url failed)
var _circle_jobs: Dictionary = {}  # url -> {id, out: Array} while a round picture is made on a worker thread
var _sizes: Dictionary = {}        # cache key (url, or CIRCLE + url) -> estimated bytes
var _used: Dictionary = {}         # cache key -> Time.get_ticks_msec() when last asked for
var _total_bytes: int = 0
## The budget in use (MAX_CACHE_BYTES; tests lower it).
var max_cache_bytes: int = MAX_CACHE_BYTES
static var _masks: Dictionary = {} # size -> {"mask": Image, "edge": PackedInt32Array, "alpha": PackedFloat32Array}
const CIRCLE := "○"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	set_process(false)


# ── Public API ───────────────────────────────────────────────
func get_texture(url: String) -> Texture2D:
	if url == "" or _failed.has(url):
		return null
	if _textures.has(url):
		_used[url] = Time.get_ticks_msec()
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
				_store(url, disk)
				return disk
		_queue.append(url)
		_pump()
	return null


## True for textures that change over time (animated emotes).
func is_animated(tex: Texture2D) -> bool:        # (not static: callers reach it through the autoload)
	return tex is AnimatedTexture


## The image cropped to a centred circle (soft edge), for profile pictures.
## null until it's ready: listen for EventBus.emote_ready (it fires again for the round one).
func get_circle_texture(url: String, size: int = 128) -> Texture2D:
	if url == "":
		return null
	if _circles.has(url):
		_used[CIRCLE + url] = Time.get_ticks_msec()
		return _circles[url]
	if _circle_jobs.has(url):
		return null
	var tex := get_texture(url)
	if tex == null:
		return null
	# the picture's own bytes from the disk copy: decoded again on the worker thread, so nothing
	# is read back from the graphics card. No copy (or a GIF): its first frame, read back once.
	var body := PackedByteArray()
	var path := _disk_path(url)
	if FileAccess.file_exists(path):
		body = FileAccess.get_file_as_bytes(path)
	var img: Image = null
	if body.is_empty() or GifDecoder.is_gif(body):
		var still: Texture2D = (tex as AnimatedTexture).get_frame_texture(0) if tex is AnimatedTexture else tex
		img = still.get_image() if still else null
		if img == null or img.is_empty():
			return null
		body = PackedByteArray()
	var mask := _circle_mask(size)
	var out: Array = [null]
	var id := WorkerThreadPool.add_task(func() -> void: out[0] = _round_image(body, img, size, mask), false, "round picture")
	_circle_jobs[url] = {"id": id, "out": out}
	set_process(true)
	return null


## How many pictures are in memory (for tests and the busy-chat check).
func get_cache_stats() -> Dictionary:
	return {"textures": _textures.size(), "circles": _circles.size(), "bytes": _total_bytes, "jobs": _circle_jobs.size()}


## (worker thread) The picture cropped to a centred square, scaled to size and cut round.
static func _round_image(body: PackedByteArray, img: Image, size: int, mask: Dictionary) -> Image:
	if img == null:
		img = _image_from(body)
		if img == null:
			return null
	else:
		img = img.duplicate()
	if img.has_mipmaps():
		img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var side := mini(img.get_width(), img.get_height())
	if side <= 0:
		return null
	@warning_ignore("integer_division")
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	# inside the circle: copied as it is (native code); the soft rim: its alpha scaled down
	var round_img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	round_img.blit_rect_mask(img, mask["mask"], Rect2i(0, 0, size, size), Vector2i.ZERO)
	var data := round_img.get_data()
	var edge: PackedInt32Array = mask["edge"]
	var alpha: PackedFloat32Array = mask["alpha"]
	for k in edge.size():
		var a := edge[k] * 4 + 3
		data[a] = int(data[a] * alpha[k])
	round_img.set_data(size, size, false, Image.FORMAT_RGBA8, data)
	round_img.generate_mipmaps()
	return round_img


## The round mask for this size (made once, on the main thread): the mask image and the rim
## pixels with their alpha.
static func _circle_mask(size: int) -> Dictionary:
	if _masks.has(size):
		return _masks[size]
	var mask := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var edge := PackedInt32Array()
	var alpha := PackedFloat32Array()
	var r := size * 0.5
	for y in size:
		for x in size:
			var a := clampf(r - Vector2(x + 0.5 - r, y + 0.5 - r).length(), 0.0, 1.0)
			if a > 0.0:
				mask.set_pixel(x, y, Color(1, 1, 1, 1))
				if a < 1.0:
					edge.append(y * size + x)
					alpha.append(a)
	var d := {"mask": mask, "edge": edge, "alpha": alpha}
	_masks[size] = d
	return d


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
		_store(url, tex)
		var f := FileAccess.open(_disk_path(url), FileAccess.WRITE)
		if f:
			f.store_buffer(body)
		EventBus.emote_ready.emit(url)
	elif not _try_fallback(url):
		_fail(url)
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
	if _decoding.is_empty() and _circle_jobs.is_empty():
		set_process(false)
		return
	var made := 0
	for url: String in _circle_jobs.keys():
		if made >= CIRCLES_PER_FRAME:
			break           # (the rest next frame: each one is an upload)
		var cj: Dictionary = _circle_jobs[url]
		if not WorkerThreadPool.is_task_completed(int(cj["id"])):
			continue
		WorkerThreadPool.wait_for_task_completion(int(cj["id"]))
		_circle_jobs.erase(url)
		var round_img: Image = (cj["out"] as Array)[0]
		if round_img:
			_circles[url] = ImageTexture.create_from_image(round_img)
			_account(CIRCLE + url, _circles[url])
			made += 1
			EventBus.emote_ready.emit(url)
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
	for job: Dictionary in _circle_jobs.values():
		WorkerThreadPool.wait_for_task_completion(int(job["id"]))
	_circle_jobs.clear()


func _gif_done(url: String, result: Dictionary, body: PackedByteArray, save: bool) -> void:
	var frames: Array = result.get("frames", [])
	if frames.is_empty():
		if _try_fallback(url):
			_pump()
			return
		_fail(url)
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
	_store(url, tex)
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
	var img := _image_from(body)
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## (any thread) A PNG / JPEG / still WebP as an RGBA image, or null.
static func _image_from(body: PackedByteArray) -> Image:
	if body.size() < 12 or PictureFile.too_big(body):     # (a small file can claim a huge size)
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
	return img


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


# ── Size budget ──────────────────────────────────────────────
func _store(url: String, tex: Texture2D) -> void:
	_textures[url] = tex
	_account(url, tex)


func _account(key: String, tex: Texture2D) -> void:
	_total_bytes -= int(_sizes.get(key, 0))
	var b := _texture_bytes(tex)
	_sizes[key] = b
	_used[key] = Time.get_ticks_msec()
	_total_bytes += b
	if _total_bytes > max_cache_bytes:
		_trim()


static func _texture_bytes(tex: Texture2D) -> int:
	if tex is AnimatedTexture:
		var anim := tex as AnimatedTexture
		var sum := 0
		for i in anim.frames:
			var f := anim.get_frame_texture(i)
			if f:
				sum += f.get_width() * f.get_height() * 4
		return sum
	return int(tex.get_width() * tex.get_height() * 4 * 4.0 / 3.0)     # (with mipmaps)


## Over budget: the pictures asked for longest ago go, until the cache is at TRIM_TO of the budget.
## A picture still shown somewhere (a seat's head, a bubble, a chat window) holds a reference of
## its own and is kept: dropping it would only load a second copy next time it's asked for.
func _trim() -> void:
	var keys: Array = _sizes.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(_used.get(a, 0)) < int(_used.get(b, 0)))
	var target := int(max_cache_bytes * TRIM_TO)
	for key: String in keys:
		if _total_bytes <= target:
			break
		var is_circle := key.begins_with(CIRCLE)
		var url := key.substr(CIRCLE.length()) if is_circle else key
		var store: Dictionary = _circles if is_circle else _textures
		if not store.has(url) or _in_use(store, url):
			continue
		store.erase(url)
		_total_bytes -= int(_sizes[key])
		_sizes.erase(key)
		_used.erase(key)


## True when something besides this cache holds the texture.
static func _in_use(store: Dictionary, url: String) -> bool:
	# (the dictionary holds one reference and this typed local a second; anything above that is a
	# node or a chat window showing it. Checked in test_busy_chat.)
	var tex: Texture2D = store[url]
	return tex.get_reference_count() > 2


func _fail(url: String) -> void:
	if _failed.size() >= MAX_FAILED:
		_failed.clear()
	_failed[url] = true


func _disk_path(url: String) -> String:
	return CACHE_DIR + url.md5_text() + ".img"
