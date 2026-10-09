class_name CaptureServer
extends Node
## Local link to the browser sender page.
##   http://127.0.0.1:<http_port>/  serves web/sender.html (localhost counts as a
##                                 secure context, which getDisplayMedia requires)
##   /backdrop?url=..&bg=00ff00    web/backdrop.html: a web page over a solid key colour
##   /vdoninja-sdk.min.js          the VDO.Ninja SDK (MPL-2.0) for the live feed while streaming together
##   ws://127.0.0.1:<ws_port>       receives the stream
##
## Binary packets: first byte = type
##   1  video frame, JPEG
##   2  audio, float32 interleaved stereo @ 48 kHz
##   3  webcam frame, JPEG
##   4  presenter feed frame: byte 1 = presenter slot (0..3), then JPEG
## Text packets: JSON {"type": "status", ...} from the sender.
## JPEG decoding + colour sampling run on worker threads; only the newest
## pending frame per channel is decoded, older ones are dropped.
##
## Locked to the sender page: any web page open in the browser could otherwise connect to the
## stream port, put its own picture and sound on the big screen and read the live-feed key.
##   - A random key is made each run and written into the sender page when it is served
##     (ws://127.0.0.1:<ws_port>/?key=...). A socket without it is closed (code 4001).
##   - The page is only served when the browser asked for 127.0.0.1 / localhost (blocks
##     "DNS rebinding", where a web page renames itself to read the page and its key), and
##     other sites can't frame it. Other origins can't read the page or /key (no CORS headers).
##   - A sender page left open from the last run reads the new key from /key and reconnects.

signal video_frame_ready(image: Image, colors: Array[Color])
signal webcam_frame_ready(image: Image)
signal presenter_frame_ready(slot: int, image: Image)
signal audio_received(frames: PackedVector2Array)
signal sender_status_changed(info: Dictionary)

const PKT_VIDEO: int = 1
const PKT_AUDIO: int = 2
const PKT_WEBCAM: int = 3
const PKT_PRESENTER: int = 4
const MAX_PRESENTERS: int = 4
## Decode channel ids for presenter feeds (PRESENTER_CHANNEL + slot).
const PRESENTER_CHANNEL: int = 100
const WS_BUFFER_BYTES: int = 8 * 1024 * 1024
## Close code for a socket with a wrong or missing key (the sender page then fetches /key).
const CLOSE_BAD_KEY: int = 4001
## How long a socket may take to open before it is dropped.
const PENDING_TIMEOUT_MS: int = 5000
## At most this many sockets waiting to open at once.
const MAX_PENDING: int = 8

## This run's key for the stream port (random each start of the app).
static var run_key: String = ""

@export_file("*.html") var sender_html_path: String = "res://web/sender.html"
## Treat the sender as gone if no packet arrives for this long.
@export var timeout_s: float = 3.0

var _http: TCPServer = TCPServer.new()
var _ws_listener: TCPServer = TCPServer.new()
var _http_clients: Array[Dictionary] = []
var _pending_ws: Array[Dictionary] = []    # {ws: WebSocketPeer, t: msec}
var _closing_ws: Array[WebSocketPeer] = []   # refused sockets finishing their close handshake
var _ws: WebSocketPeer
var _http_port: int = 0
var _ws_port: int = 0

var _last_packet_time: float = -1000.0
var _connected: bool = false
var _sender_info: Dictionary = {}

# Decode bookkeeping, per channel (PKT_VIDEO / PKT_WEBCAM)
var _busy: Dictionary = {PKT_VIDEO: false, PKT_WEBCAM: false}
var _pending: Dictionary = {PKT_VIDEO: PackedByteArray(), PKT_WEBCAM: PackedByteArray()}
var _task_ids: Dictionary = {PKT_VIDEO: -1, PKT_WEBCAM: -1}
var _mutex: Mutex = Mutex.new()
var _frames_this_second: int = 0
var _fps: float = 0.0
var _fps_timer: float = 0.0


# ── Public API ───────────────────────────────────────────────
## This run's key, made on first use.
static func get_run_key() -> String:
	if run_key.is_empty():
		var crypto := Crypto.new()
		run_key = crypto.generate_random_bytes(18).hex_encode()
	return run_key


func start(http_port: int, ws_port: int) -> bool:
	stop()
	_http_port = http_port
	_ws_port = ws_port
	var ok := true
	if _http.listen(http_port, "127.0.0.1") != OK:
		EventBus.status_message.emit("Couldn't open port %d for the sender page." % http_port, true)
		ok = false
	if _ws_listener.listen(ws_port, "127.0.0.1") != OK:
		EventBus.status_message.emit("Couldn't open port %d for the stream." % ws_port, true)
		ok = false
	return ok


func stop() -> void:
	_http.stop()
	_ws_listener.stop()
	if _ws:
		_ws.close()
	_ws = null
	_pending_ws.clear()
	_closing_ws.clear()
	_http_clients.clear()
	_set_connected(false)


func get_sender_url() -> String:
	return "http://127.0.0.1:%d/" % _http_port


## Sends a JSON message to the sender page (e.g. start a presenter's camera). False if no sender.
func send_to_sender(data: Dictionary) -> bool:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _ws.send_text(JSON.stringify(data)) == OK


func is_connected_to_sender() -> bool:
	return _connected


func get_fps() -> float:
	return _fps


# ── Lifecycle ────────────────────────────────────────────────
func _process(delta: float) -> void:
	_poll_http()
	_poll_ws_accept()
	_poll_ws()
	_fps_timer += delta
	if _fps_timer >= 1.0:
		_fps = _frames_this_second / _fps_timer
		_frames_this_second = 0
		_fps_timer = 0.0
	if _connected and Time.get_ticks_msec() / 1000.0 - _last_packet_time > timeout_s:
		_set_connected(false)


func _exit_tree() -> void:
	for ch in _task_ids.keys():
		if int(_task_ids[ch]) != -1:
			WorkerThreadPool.wait_for_task_completion(int(_task_ids[ch]))
			_task_ids[ch] = -1
	stop()


# ── HTTP (tiny, GET only) ────────────────────────────────────
func _poll_http() -> void:
	while _http.is_listening() and _http.is_connection_available():
		_http_clients.append({"peer": _http.take_connection(), "buf": "", "t": Time.get_ticks_msec()})
	for c in _http_clients.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(c["t"]) > 5000:
			_http_clients.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			c["buf"] += peer.get_utf8_string(n)
		if String(c["buf"]).contains("\r\n\r\n"):
			_respond_http(peer, String(c["buf"]))
			peer.disconnect_from_host()
			_http_clients.erase(c)


func _respond_http(peer: StreamPeerTCP, request: String) -> void:
	var first_line := request.get_slice("\r\n", 0)
	var path := first_line.get_slice(" ", 1)
	if not _host_ok(request):
		# a page that renamed itself to reach this port (DNS rebinding) gets nothing
		_send_http(peer, "403 Forbidden", "text/plain", ("Open this page as http://127.0.0.1:%d/" % _http_port).to_utf8_buffer())
		return
	if first_line.begins_with("GET ") and path == "/key":
		# a sender page left open from the last run asks for the new key; other origins can't read it
		_send_http(peer, "200 OK", "text/plain; charset=utf-8", get_run_key().to_utf8_buffer())
		return
	if path == "/favicon.ico":
		_send_http(peer, "204 No Content", "text/plain", PackedByteArray())
		return
	if first_line.begins_with("GET ") and (path == "/backdrop" or path.begins_with("/backdrop?")):
		# a web page shown over a solid key colour, so a see-through page can be shared and keyed
		var page := FileAccess.get_file_as_string(sender_html_path.get_base_dir().path_join("backdrop.html"))
		if page == "":
			_send_http(peer, "404 Not Found", "text/plain", "Missing web/backdrop.html".to_utf8_buffer())
		else:
			_send_http(peer, "200 OK", "text/html; charset=utf-8", page.to_utf8_buffer())
		return
	if first_line.begins_with("GET ") and path == "/vdoninja-sdk.min.js":
		var js := FileAccess.get_file_as_bytes(sender_html_path.get_base_dir().path_join("vdoninja-sdk.min.js"))
		if js.is_empty():
			_send_http(peer, "404 Not Found", "text/plain", "Missing web/vdoninja-sdk.min.js".to_utf8_buffer())
		else:
			_send_http(peer, "200 OK", "text/javascript; charset=utf-8", js)
		return
	if not first_line.begins_with("GET ") or not (path == "/" or path.begins_with("/?") or path == "/sender.html"):
		_send_http(peer, "404 Not Found", "text/plain", "Not found".to_utf8_buffer())
		return
	var html := FileAccess.get_file_as_string(sender_html_path)
	if html == "":
		_send_http(peer, "500 Internal Server Error", "text/plain",
			("Missing %s. When exporting, add web/* to the export resource filters." % sender_html_path).to_utf8_buffer())
		return
	html = html.replace("{{WS_PORT}}", str(_ws_port)).replace("{{WS_KEY}}", get_run_key())
	_send_http(peer, "200 OK", "text/html; charset=utf-8", html.to_utf8_buffer())


func _send_http(peer: StreamPeerTCP, status: String, ctype: String, body: PackedByteArray) -> void:
	# nosniff + no framing by other sites: another page can't load these as a script or inside a frame
	var head := ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\n"
		+ "X-Content-Type-Options: nosniff\r\nX-Frame-Options: SAMEORIGIN\r\n"
		+ "Content-Security-Policy: frame-ancestors 'self'\r\nConnection: close\r\n\r\n") % [status, ctype, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)


## True when the request's Host header names this PC by its loopback name (any port or none).
func _host_ok(request: String) -> bool:
	for line in request.split("\r\n"):
		if line.to_lower().begins_with("host:"):
			var host := line.substr(5).strip_edges().to_lower()
			if host.begins_with("["):   # [::1]:8765
				host = host.substr(0, host.find("]") + 1)
			elif host.contains(":"):
				host = host.get_slice(":", 0)
			return host in ["127.0.0.1", "localhost", "[::1]"]
	return false


## True when a socket asked for ws://...?key=<this run's key>.
static func key_ok(requested_url: String) -> bool:
	var q := requested_url.get_slice("?", 1) if requested_url.contains("?") else ""
	for part in q.split("&", false):
		if part.begins_with("key=") and part.substr(4) == get_run_key():
			return true
	return false


# ── WebSocket ────────────────────────────────────────────────
func _poll_ws_accept() -> void:
	while _ws_listener.is_listening() and _ws_listener.is_connection_available():
		var conn := _ws_listener.take_connection()
		if _pending_ws.size() >= MAX_PENDING:
			conn.disconnect_from_host()    # something is opening sockets in a loop
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = WS_BUFFER_BYTES
		ws.max_queued_packets = 1024
		if ws.accept_stream(conn) == OK:
			_pending_ws.append({"ws": ws, "t": Time.get_ticks_msec()})
	for p in _pending_ws.duplicate():
		var ws: WebSocketPeer = p["ws"]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_pending_ws.erase(p)
				if not key_ok(ws.get_requested_url()):
					# not our sender page: refuse it before it can replace the real one
					ws.close(CLOSE_BAD_KEY, "Wrong key: reload the sender page")
					_closing_ws.append(ws)
					continue
				if _ws:  # newest sender wins
					_ws.close(1000, "Replaced by a new sender")
				_ws = ws
			WebSocketPeer.STATE_CLOSED:
				_pending_ws.erase(p)
			_:
				if Time.get_ticks_msec() - int(p["t"]) > PENDING_TIMEOUT_MS:
					ws.close()
					_pending_ws.erase(p)
	for ws in _closing_ws.duplicate():
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_closing_ws.erase(ws)


func _poll_ws() -> void:
	if _ws == null:
		return
	_ws.poll()
	if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_ws = null
		_set_connected(false)
		return
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		var is_text := _ws.was_string_packet()
		_last_packet_time = Time.get_ticks_msec() / 1000.0
		_set_connected(true)
		if is_text:
			_handle_text(pkt.get_string_from_utf8())
		elif pkt.size() > 1:
			_handle_binary(pkt)


func _handle_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.get("type", "") == "status":
		_sender_info = data
		sender_status_changed.emit(data)


func _handle_binary(pkt: PackedByteArray) -> void:
	var kind := pkt[0]
	match kind:
		PKT_VIDEO, PKT_WEBCAM:
			_frames_this_second += 1 if kind == PKT_VIDEO else 0
			_queue_decode(kind, pkt.slice(1))
		PKT_PRESENTER:
			if pkt.size() > 2 and pkt[1] < MAX_PRESENTERS:
				_queue_decode(PRESENTER_CHANNEL + pkt[1], pkt.slice(2))
		PKT_AUDIO:
			var samples := pkt.slice(1).to_float32_array()
			@warning_ignore("integer_division")
			var n := samples.size() / 2
			var frames := PackedVector2Array()
			frames.resize(n)
			for i in n:
				frames[i] = Vector2(samples[i * 2], samples[i * 2 + 1])
			audio_received.emit(frames)


# ── Threaded JPEG decode ─────────────────────────────────────
func _queue_decode(channel: int, jpeg: PackedByteArray) -> void:
	_mutex.lock()
	if not _busy.has(channel):
		_busy[channel] = false
		_pending[channel] = PackedByteArray()
		_task_ids[channel] = -1
	_pending[channel] = jpeg
	var begin: bool = not _busy[channel]
	if begin:
		_busy[channel] = true
	_mutex.unlock()
	if begin:
		_start_task(channel)


func _start_task(channel: int) -> void:
	_mutex.lock()
	var data: PackedByteArray = _pending[channel]
	_pending[channel] = PackedByteArray()
	_mutex.unlock()
	var id := WorkerThreadPool.add_task(_decode_task.bind(channel, data), false, "jpeg decode")
	_mutex.lock()
	_task_ids[channel] = id
	_mutex.unlock()


func _decode_task(channel: int, data: PackedByteArray) -> void:
	var img := Image.new()
	var colors: Array[Color] = []
	if img.load_jpg_from_buffer(data) == OK:
		if channel == PKT_VIDEO:
			colors = ColorSampler.sample_thirds(img)
		# JPEGs decode as RGB8, which some graphics cards can't take: the engine would convert every
		# frame itself and warn each time. Converting here (still on the worker thread) is quiet.
		if img.get_format() == Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGBA8)
	else:
		img = null
	_on_decoded.call_deferred(channel, img, colors)


func _on_decoded(channel: int, img: Image, colors: Array[Color]) -> void:
	# only one decode per channel runs at a time (_busy), so the stored id is this task's own
	_mutex.lock()
	var id := int(_task_ids[channel])
	_task_ids[channel] = -1
	_mutex.unlock()
	if id != -1:
		WorkerThreadPool.wait_for_task_completion(id)
	if img:
		if channel == PKT_VIDEO:
			video_frame_ready.emit(img, colors)
		elif channel == PKT_WEBCAM:
			webcam_frame_ready.emit(img)
		else:
			presenter_frame_ready.emit(channel - PRESENTER_CHANNEL, img)
	_mutex.lock()
	var more: bool = not (_pending[channel] as PackedByteArray).is_empty()
	if not more:
		_busy[channel] = false
	_mutex.unlock()
	if more:
		_start_task(channel)


# ── Private ──────────────────────────────────────────────────
func _set_connected(on: bool) -> void:
	if on == _connected:
		return
	_connected = on
	if not on:
		_sender_info = {}
	sender_status_changed.emit(_sender_info)
