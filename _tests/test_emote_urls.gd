extends Node
## Which picture a chat emote uses: Twitch's animated emotes (PopNemo...) and animated 7TV emotes
## play as GIFs, the rest use the still picture, and when the animated one can't be shown (an
## animated WebP, a broken GIF) EmoteCache loads the still one in its place. A tiny local web
## server stands in for the emote sites. No room is loaded.
##   <redot console exe> --path . _tests/test_emote_urls.tscn -- C:/temp/sr_tests --mp-profile=test

const PORT: int = 8897

var _fails: int = 0
var _server := TCPServer.new()
var _files: Dictionary = {}       # path -> bytes the server answers with (others: 404)
var _peers: Array = []            # [StreamPeerTCP, request text so far]


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	await get_tree().process_frame
	var T := "https://static-cdn.jtvnw.net/emoticons/v2/emotesv2_x/"
	var seven := "https://cdn.7tv.app/emote/01ABC"

	# which link is picked
	var tw := {"provider": "twitch", "url": T + "default/dark/2.0", "static_url": T + "static/dark/2.0"}
	_check(AudienceManager.emote_url(tw) == T + "default/dark/2.0", "Twitch emotes use the default (animated when it is) picture")
	var st_anim := {"provider": "7tv", "url": seven + "/2x.webp", "static_url": seven + "/2x_static.webp", "animated": true}
	_check(AudienceManager.emote_url(st_anim) == seven + "/2x.gif", "animated 7TV emotes use the GIF")
	var st_still := {"provider": "7tv", "url": seven + "/2x.webp", "static_url": seven + "/2x_static.webp", "animated": false}
	_check(AudienceManager.emote_url(st_still) == seven + "/2x_static.webp", "still 7TV emotes use the still WebP")
	var ffz := {"provider": "ffz", "url": "https://cdn.ffz/emote/1/animated/2", "static_url": "https://cdn.ffz/emote/1/2", "animated": true}
	_check(AudienceManager.emote_url(ffz) == "https://cdn.ffz/emote/1/animated/2.gif", "animated FrankerFaceZ emotes use the GIF")
	var ffz_still := {"provider": "ffz", "url": "https://cdn.ffz/emote/2/2", "static_url": "https://cdn.ffz/emote/2/2", "animated": false}
	_check(AudienceManager.emote_url(ffz_still) == "https://cdn.ffz/emote/2/2", "still FrankerFaceZ emotes use the still one")
	var bttv := {"provider": "bttv", "url": "https://cdn.betterttv.net/emote/9/2x", "static_url": "", "animated": true}
	_check(AudienceManager.emote_url(bttv) == "https://cdn.betterttv.net/emote/9/2x", "animated BetterTTV emotes use their GIF")

	# message_parts hands the still link along (guests need it too)
	var parts := AudienceManager.message_parts("hi PopNemo", [{"provider": "twitch", "start": 3, "end": 9,
		"url": T + "default/dark/2.0", "static_url": T + "static/dark/2.0"}])
	var emote: Dictionary = parts[parts.size() - 1] if parts.size() > 0 and parts[parts.size() - 1] is Dictionary else {}
	_check(String(emote.get("url", "")) == T + "default/dark/2.0" and String(emote.get("still", "")) == T + "static/dark/2.0",
		"the bubble gets the animated link with the still one as a fallback (%s)" % str(emote))

	# downloads: a stand-in emote site
	if _server.listen(PORT, "127.0.0.1") != OK:
		_check(false, "local test server on port %d" % PORT)
		_finish()
		return
	var gif := FileAccess.get_file_as_bytes("res://_tests/assets/badge_anim.gif")
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color.ORANGE)
	var png := img.save_png_to_buffer()
	# RIFF/WEBP with a VP8X header saying "animated": the engine can't read it
	var webp := "RIFF".to_ascii_buffer() + PackedByteArray([30, 0, 0, 0]) + "WEBPVP8X".to_ascii_buffer() + PackedByteArray([10, 0, 0, 0, 0x02, 0, 0, 0]) + PackedByteArray([27, 0, 0, 27, 0, 0])
	_files = {"/anim.gif": gif, "/still.png": png, "/anim.webp": webp, "/broken.gif": "GIF89a".to_ascii_buffer() + PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])}
	set_process(true)
	var B := "http://127.0.0.1:%d" % PORT
	var tag := str(Time.get_ticks_usec())        # fresh links: nothing from an earlier run's disk cache
	var cases: Array = [
		["an animated GIF emote plays", B + "/anim.gif?" + tag, B + "/still.png?" + tag, true],
		["an animated WebP falls back to the still picture", B + "/anim.webp?" + tag, B + "/still.png?a" + tag, false],
		["a broken GIF falls back to the still picture", B + "/broken.gif?" + tag, B + "/still.png?b" + tag, false],
		["a missing picture falls back to the still picture", B + "/gone.gif?" + tag, B + "/still.png?c" + tag, false],
	]
	if gif.is_empty():
		cases.pop_front()
		print("(no _tests/assets/badge_anim.gif: animated GIF check skipped)")
	for c: Array in cases:
		var url := String(c[1])
		EmoteCache.set_fallback(url, String(c[2]))
		EmoteCache.get_texture(url)
		var t0 := Time.get_ticks_msec()
		while EmoteCache.get_texture(url) == null and not EmoteCache.is_failed(url) and Time.get_ticks_msec() - t0 < 8000:
			await get_tree().process_frame
		var tex := EmoteCache.get_texture(url)
		var ok := tex != null and EmoteCache.is_animated(tex) == bool(c[3])
		if ok and not bool(c[3]):
			ok = tex.get_image().get_pixel(10, 10).is_equal_approx(Color.ORANGE)
		_check(ok, String(c[0]))
	var lone := B + "/anim.webp?lone" + tag
	EmoteCache.get_texture(lone)
	var t1 := Time.get_ticks_msec()
	while not EmoteCache.is_failed(lone) and Time.get_ticks_msec() - t1 < 8000:
		await get_tree().process_frame
	_check(EmoteCache.is_failed(lone), "an animated WebP with no still picture still gives up (shown as its name)")
	_finish()


func _finish() -> void:
	set_process(false)
	_server.stop()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)


## Answers one request per connection: the file, or 404. (Across frames: the HTTPRequest that
## is asking runs on this same thread.)
func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_peers.append([_server.take_connection(), ""])
	for pair: Array in _peers.duplicate():
		var peer: StreamPeerTCP = pair[0]
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			pair[1] = String(pair[1]) + peer.get_utf8_string(n)
		if not String(pair[1]).contains("\r\n\r\n"):
			continue
		_peers.erase(pair)
		var path := String(pair[1]).get_slice(" ", 1).get_slice("?", 0)
		var body: PackedByteArray = _files.get(path, PackedByteArray())
		var status := "200 OK" if _files.has(path) else "404 Not Found"
		peer.put_data(("HTTP/1.1 %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, body.size()]).to_ascii_buffer())
		if body.size() > 0:
			peer.put_data(body)
		peer.disconnect_from_host()
