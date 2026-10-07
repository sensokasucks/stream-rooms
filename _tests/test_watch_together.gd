extends Node
## Streaming together, phase 2: a web video plays in sync on every PC. The host makes a short test
## clip with ffmpeg, serves it over HTTP on 127.0.0.1 (so it's a real web link, downloaded by each
## copy's own yt-dlp), hosts a session and starts two more copies: a guest that joins first and
## one that joins while the video is already playing. Each guest writes its PASS / FAIL lines to a
## file in the output folder; the host prints them at the end.
##   <redot console exe> --path . _tests/test_watch_together.tscn -- C:/temp/sr_tests --mp-profile=test

const SESSION_PORT: int = 7393
const HTTP_PORT: int = 7394
const PASSWORD: String = "watchpass"
const CLIP_SECONDS: int = 90
const MAX_DRIFT: float = 0.35         # SYNC_TOLERANCE_S plus a little for the measurement itself

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _main: Node
var _feed: Node
# tiny HTTP server for the clip
var _http: TCPServer
var _clip: PackedByteArray
var _conns: Array = []          # [{peer: StreamPeerTCP, request: String, sent: int, header: bool}]


func _check(ok: bool, what: String) -> void:
	var line := ("PASS " if ok else "FAIL ") + what
	print(line)
	_lines.append(line)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if bool(cond.call()):
			return true
		await _secs(0.25)
		t += 0.25
	return bool(cond.call())


func _ready() -> void:
	NetSession.auto_confirm = true      # (no "let them in" popups in a test)
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("together_port", SESSION_PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_address", "127.0.0.1:%d" % SESSION_PORT)
	AppState.set_setting("loop_files", false)
	_main = load("res://core/main.tscn").instantiate()
	add_child(_main)
	_feed = _main.get_node("ScreenFeed")
	await _secs(3.0)
	if args.has("--role=guest") or args.has("--role=late"):
		await _guest(args.has("--role=late"))
	else:
		await _host()


func _video_player() -> VideoStreamPlayer:
	return _feed.video_player


func _pos() -> float:
	return _video_player().stream_position


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	set_process(true)
	if not await _make_clip():
		await _finish()
		return
	_http = TCPServer.new()
	_check(_http.listen(HTTP_PORT, "127.0.0.1") == OK, "serving the test clip over HTTP")
	var url := "http://127.0.0.1:%d/clip-%d.ogv" % [HTTP_PORT, Time.get_unix_time_from_system()]   # (a new link: nothing cached)

	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_name", "Host")
	NetSession.host()
	for p in ["watchguest", "watchlate"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_%s.cfg" % p))
		DirAccess.remove_absolute(_out.path_join("together_%s.txt" % p))
	_spawn("watchguest", "--role=guest", "0,0")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0), "the guest joined")
	await _secs(3.0)

	# a web link: every PC downloads it, waits on the first frame, then the host starts them all
	EventBus.file_play_requested.emit(url)
	_check(AppState.get_source_mode() != "file" or _video_player().paused, "the host doesn't start alone")
	_check(await _wait_for(func() -> bool: return bool(NetSession._video.get("started", false)), 150.0),
		"everyone got ready and the host started the video")
	_check(await _wait_for(func() -> bool: return AppState.get_source_mode() == "file" and not _video_player().paused, 5.0),
		"it plays on the host")
	await _secs(8.0)

	# a second guest joins while it plays
	_spawn("watchlate", "--role=late", "980,0")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 3, 90.0), "a late guest joined")
	await _secs(12.0)          # (it downloads, converts, then catches up)

	# pause, then jump, then play on
	AppState.set_react_paused(true)
	_check(_video_player().paused, "paused on the host")
	await _secs(4.0)
	AppState.set_react_paused(false)
	await _secs(1.0)
	_video_player().stream_position = 75.0
	await _secs(6.0)

	# stop: everyone's screen stops
	EventBus.file_stop_requested.emit()
	await _secs(4.0)
	NetSession.leave()
	for p in ["watchguest", "watchlate"]:
		var f := _out.path_join("together_%s.txt" % p)
		await _wait_for(func() -> bool: return FileAccess.file_exists(f), 60.0)
		var text := FileAccess.get_file_as_string(f)
		if text == "":
			_check(false, "%s wrote its results" % p)
		for line in text.split("\n", false):
			_check(line.begins_with("PASS "), "%s: %s" % [p, line.substr(5)])
	await _finish()


func _make_clip() -> bool:
	var ffmpeg := ProjectSettings.globalize_path("res://tools/ffmpeg.exe")
	var path := _out.path_join("watch_clip.ogv")
	var out := []
	var code := OS.execute(ffmpeg, PackedStringArray(["-y", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=duration=%d:size=320x180:rate=30" % CLIP_SECONDS,
		"-f", "lavfi", "-i", "sine=frequency=440:duration=%d" % CLIP_SECONDS,
		"-c:v", "libtheora", "-q:v", "5", "-c:a", "libvorbis", path]), out, true)
	_clip = FileAccess.get_file_as_bytes(path)
	_check(code == 0 and _clip.size() > 10000, "made a %d s test clip with ffmpeg (%d bytes)" % [CLIP_SECONDS, _clip.size()])
	return code == 0 and _clip.size() > 10000


func _process(_delta: float) -> void:
	if _http == null:
		return
	while _http.is_connection_available():
		_conns.append({"peer": _http.take_connection(), "request": "", "sent": 0, "header": false})
	for c: Dictionary in _conns.duplicate():
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		if not bool(c["header"]):
			var n := peer.get_available_bytes()
			if n > 0:
				c["request"] = String(c["request"]) + peer.get_utf8_string(n)
			if not String(c["request"]).contains("\r\n\r\n"):
				continue
			var head := String(c["request"]).begins_with("HEAD")
			peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: video/ogg\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % _clip.size()).to_utf8_buffer())
			c["header"] = true
			if head:
				peer.disconnect_from_host()
				_conns.erase(c)
				continue
		var sent := int(c["sent"])
		if sent < _clip.size():
			var r: Array = peer.put_partial_data(_clip.slice(sent, mini(sent + 262144, _clip.size())))
			c["sent"] = sent + int(r[1])
		else:
			peer.disconnect_from_host()
			_conns.erase(c)


func _spawn(profile: String, role: String, pos: String) -> void:
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", pos, "res://_tests/test_watch_together.tscn", "--", _out, "--mp-profile=" + profile, role])
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the %s copy" % profile)


# ── Guests ───────────────────────────────────────────────────
## Where the host's video should be right now, from the last position it sent.
func _host_pos() -> float:
	var st: Array = NetSession._guest_video.get("state", [])
	if st.is_empty():
		return -1.0
	var p := float(st[0])
	if bool(st[1]):
		p += NetSession._rtt_s() * 0.5 + float(Time.get_ticks_msec() - int(st[2])) / 1000.0
	return p


func _host_playing() -> bool:
	var st: Array = NetSession._guest_video.get("state", [])
	return not st.is_empty() and bool(st[1])


func _in_sync() -> bool:
	return AppState.get_source_mode() == "file" and _host_pos() >= 0.0 and absf(_pos() - _host_pos()) < MAX_DRIFT


func _guest(late: bool) -> void:
	AppState.set_setting("together_name", "Late" if late else "Guest")
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and (NetSession.get_info()["peers"] as Array).size() >= 2, 30.0),
		"joined the host")
	if not late:
		var at_ready: Array = []      # paused / position the moment it was ready (the host starts right after)
		EventBus.file_prepared.connect(func(_i: String) -> void: at_ready.append_array([_video_player().paused, _pos()]))
		_check(await _wait_for(func() -> bool: return not NetSession._guest_video.is_empty(), 30.0), "the host's video link arrived")
		_check(await _wait_for(func() -> bool: return bool(NetSession._guest_video.get("ready", false)), 150.0),
			"downloaded and converted it here")
		_check(at_ready.size() == 2 and bool(at_ready[0]) and float(at_ready[1]) < 0.2, "was ready on the first frame, paused, waiting for the host")
		_check(await _wait_for(func() -> bool: return _host_playing() and not _video_player().paused, 30.0), "started with the host")
	else:
		_check(await _wait_for(func() -> bool: return bool(NetSession._guest_video.get("ready", false)), 150.0),
			"joined mid-video: downloaded and converted it here")
		_check(await _wait_for(func() -> bool: return _host_playing() and not _video_player().paused, 10.0), "plays along")
	await _secs(3.0)
	var drift := absf(_pos() - _host_pos())
	_check(_in_sync(), "within %.2f s of the host (%.2f s apart)" % [MAX_DRIFT, drift])

	# the host pauses
	_check(await _wait_for(func() -> bool: return not _host_playing(), 30.0), "the host paused")
	_check(await _wait_for(func() -> bool: return _video_player().paused, 2.0), "paused here too")
	var held := _pos()
	await _secs(1.0)
	_check(absf(_pos() - held) < 0.05 and absf(_pos() - _host_pos()) < MAX_DRIFT, "held at the host's spot (%.2f vs %.2f)" % [_pos(), _host_pos()])

	# the host plays on and jumps ahead to 75 s
	_check(await _wait_for(func() -> bool: return _host_playing() and _host_pos() > 74.0, 20.0), "the host jumped ahead")
	_check(await _wait_for(_in_sync, 4.0), "followed the jump (%.2f vs %.2f)" % [_pos(), _host_pos()])
	await _secs(3.0)
	_check(_in_sync(), "still in sync a few seconds later (%.2f s apart)" % absf(_pos() - _host_pos()))

	# the host stops
	_check(await _wait_for(func() -> bool: return AppState.get_source_mode() == "none", 20.0), "stopped when the host stopped")
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "noticed the session ending")
	await _finish()


func _finish() -> void:
	var profile := AppState.get_profile()
	if profile != "test":
		var f := FileAccess.open(_out.path_join("together_%s.txt" % profile), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines) + "\n")
			f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
