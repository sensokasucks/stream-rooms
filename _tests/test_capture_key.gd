extends Node
## The capture port only takes the real sender page: the page is served with this run's key,
## a socket without the key is refused (code 4001) and can't put a picture on the big screen,
## a request for another host name (DNS rebinding) gets nothing, and frames with the key still
## reach the screen, newest last.
##   <redot console exe> --path . _tests/test_capture_key.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _http_port: int = 0
var _ws_port: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## Sends a raw HTTP request and returns the whole answer ("" if nothing came back).
func _http(path: String, host: String) -> String:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host("127.0.0.1", _http_port) != OK:
		return ""
	var sent := false
	var got := ""
	for i in 150:
		tcp.poll()
		var st := tcp.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				tcp.put_data(("GET %s HTTP/1.1\r\nHost: %s\r\n\r\n" % [path, host]).to_utf8_buffer())
				sent = true
			var n := tcp.get_available_bytes()
			if n > 0:
				got += tcp.get_utf8_string(n)
		elif st != StreamPeerTCP.STATUS_CONNECTING:
			break
		await _secs(0.02)
	return got


## Opens a socket to the stream port; returns it once open (or closed).
func _open_ws(query: String) -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d/%s" % [_ws_port, query])
	for i in 150:
		ws.poll()
		var st := ws.get_ready_state()
		if st != WebSocketPeer.STATE_CONNECTING:
			break
		await _secs(0.02)
	return ws


func _jpeg(c: Color) -> PackedByteArray:
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(c)
	var out := PackedByteArray([1])
	out.append_array(img.save_jpg_to_buffer(0.9))
	return out


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(2.0)
	_http_port = AppState.get_capture_port("capture_http_port")
	_ws_port = AppState.get_capture_port("capture_ws_port")
	var server: CaptureServer = main.get_node("ScreenFeed").capture_server
	var key := CaptureServer.get_run_key()
	_check(key.length() >= 24, "a random key is made for this run")

	# the page and its key
	var page := await _http("/", "127.0.0.1:%d" % _http_port)
	_check(page.begins_with("HTTP/1.1 200") and page.contains(key) and not page.contains("{{WS_KEY}}"), "the sender page is served with this run's key")
	_check(page.contains("frame-ancestors"), "other sites can't put the sender page in a frame")
	var local := await _http("/", "localhost:%d" % _http_port)
	_check(local.begins_with("HTTP/1.1 200"), "localhost works too")
	var rebind := await _http("/", "evil.example:%d" % _http_port)
	_check(rebind.begins_with("HTTP/1.1 403") and not rebind.contains(key), "another host name (DNS rebinding) gets nothing")
	var key_page := await _http("/key", "127.0.0.1:%d" % _http_port)
	_check(key_page.ends_with(key), "/key gives the key to a page on this PC")
	var rebind_key := await _http("/key", "evil.example")
	_check(not rebind_key.contains(key), "/key refuses another host name")

	# a socket without the key: refused, the screen doesn't change
	var frames: Array[Color] = []
	server.video_frame_ready.connect(func(_img: Image, colors: Array[Color]) -> void:
		frames.append(colors[0] if colors.size() > 0 else Color.BLACK))
	var bad := await _open_ws("")
	for i in 100:
		bad.poll()
		if bad.get_ready_state() == WebSocketPeer.STATE_OPEN:
			bad.send(_jpeg(Color.GREEN))
		if bad.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		await _secs(0.03)
	_check(bad.get_ready_state() == WebSocketPeer.STATE_CLOSED and bad.get_close_code() == CaptureServer.CLOSE_BAD_KEY,
		"a socket without the key is closed with code 4001 (got %d)" % bad.get_close_code())
	var wrong := await _open_ws("?key=nope")
	for i in 100:
		wrong.poll()
		if wrong.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		await _secs(0.03)
	_check(wrong.get_ready_state() == WebSocketPeer.STATE_CLOSED, "a socket with a wrong key is closed")
	await _secs(0.5)
	_check(frames.is_empty() and AppState.get_source_mode() != "capture", "no picture from a socket without the key")
	_check(not server.is_connected_to_sender(), "a refused socket doesn't count as the sender")

	# the real sender page's socket: frames reach the screen, the newest one last
	var good := await _open_ws("?key=" + key)
	_check(good.get_ready_state() == WebSocketPeer.STATE_OPEN, "a socket with the key opens")
	var colors := [Color.BLUE, Color.YELLOW, Color.CYAN, Color.MAGENTA, Color.WHITE, Color.RED]
	for c in colors:
		good.send(_jpeg(c))
		good.poll()
	for i in 100:
		good.poll()
		await _secs(0.03)
		if frames.size() > 0 and frames[-1].r > 0.8 and frames[-1].g < 0.3 and frames[-1].b < 0.3:
			break
	_check(server.is_connected_to_sender(), "the keyed socket is the sender")
	_check(frames.size() >= 1 and frames.size() <= colors.size(), "frames were decoded (%d of %d; extra ones may be skipped)" % [frames.size(), colors.size()])
	_check(frames.size() > 0 and frames[-1].r > 0.8 and frames[-1].g < 0.3, "the newest frame is the one shown last (%s)" % (str(frames[-1]) if frames.size() > 0 else "none"))
	_check(AppState.get_source_mode() == "capture", "the big screen shows the browser tab")
	good.close()

	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
