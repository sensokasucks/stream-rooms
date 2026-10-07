extends Node
## Streaming together, phase 3: the host's shared tab reaches a guest's big screen through VDO.Ninja.
## Needs the internet (VDO.Ninja's signalling server) and Google Chrome, so it isn't in the default
## regression set. The host's sender page runs in headless Chrome with "?testshare" (a colour-cycling
## picture and a tone instead of a real tab); a guest copy joins and its sender page, also in
## headless Chrome, uses "?autowatch" (no click needed). The guest writes its PASS / FAIL lines to a
## file in the output folder; the host prints them at the end.
##   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Tests test_live_feed -TimeLimit 300
## With "--relay" after the profile (run the exe directly) the feed is relayed (addresses hidden).
## With "--manual-watch" after the profile (run the exe directly), the guest doesn't open Chrome:
## open its sender page (the address is printed) in a normal browser and click "Watch" yourself.

const SESSION_PORT: int = 7395
const PASSWORD: String = "livepass"
const CHROME: String = "C:/Program Files/Google/Chrome/Application/chrome.exe"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _main: Node
var _chrome_pids: Array[int] = []
var _capture_info: Dictionary = {}
var _colors: Array[Color] = []
var _loud_chunks: int = 0           # sound chunks from the sender page that aren't silent
var _audio_chunks: int = 0


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
	EventBus.capture_status_changed.connect(func(i: Dictionary) -> void: _capture_info = i)
	EventBus.screen_colors_changed.connect(func(_l: Color, c: Color, _r: Color) -> void:
		_colors.append(c)
		if _colors.size() > 40:
			_colors.pop_front())
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("together_port", SESSION_PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_address", "127.0.0.1:%d" % SESSION_PORT)
	AppState.set_setting("together_live_feed", true)
	# "--relay" after the profile: the feed goes through VDO.Ninja's relay servers (hide addresses)
	AppState.set_setting("together_live_relay", args.has("--relay"))
	_main = load("res://core/main.tscn").instantiate()
	add_child(_main)
	(_main.get_node("ScreenFeed").capture_server as Node).audio_received.connect(func(frames: PackedVector2Array) -> void:
		_audio_chunks += 1
		var peak := 0.0
		for f in frames:
			peak = maxf(peak, absf(f.x))
		if peak > 0.01:
			_loud_chunks += 1)
	await _secs(3.0)
	if not FileAccess.file_exists(CHROME):
		_check(false, "Google Chrome is installed at " + CHROME)
		await _finish()
		return
	if args.has("--role=guest"):
		await _guest()
	else:
		await _host()


## The sender page of this copy in a headless Chrome of its own (its own profile folder).
func _open_sender(query: String) -> void:
	var url := "http://127.0.0.1:%d/%s" % [AppState.get_capture_port("capture_http_port"), query]
	var profile_dir := _out.path_join("chrome_" + AppState.get_profile())
	# (a headless page can't be clicked, so here it may play sound without a click; --manual-watch checks
	# the real rule: a browser only lets sound through after a click, so Watch starts the sound engine)
	var flags := PackedStringArray(["--headless=new", "--user-data-dir=" + profile_dir, "--no-first-run",
		"--no-default-browser-check", "--autoplay-policy=no-user-gesture-required", url])
	var pid := OS.create_process(CHROME, flags)
	_check(pid > 0, "opened the sender page in headless Chrome (%s)" % url)
	_chrome_pids.append(pid)


func _colors_change() -> bool:
	if _colors.size() < 10:
		return false
	var a := _colors[0]
	var b := _colors[_colors.size() - 1]
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.2


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	AppState.set_setting("together_bind", "local")
	NetSession.host()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_liveguest2.cfg"))
	DirAccess.remove_absolute(_out.path_join("together_liveguest2.txt"))
	_open_sender("?testshare=1")
	_check(await _wait_for(func() -> bool: return AppState.get_source_mode() == "capture", 30.0),
		"the host's sender page shares its test picture")
	_check(await _wait_for(func() -> bool: return bool(_capture_info.get("has_audio", false)), 10.0), "with sound")
	_check(await _wait_for(func() -> bool: return _loud_chunks > 20, 10.0), "and the tone is really there (%d of %d chunks not silent)" % [_loud_chunks, _audio_chunks])

	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "980,0", "res://_tests/test_live_feed.tscn", "--", _out, "--mp-profile=liveguest2", "--role=guest"]
		+ (["--relay"] if OS.get_cmdline_user_args().has("--relay") else [])
		+ (["--manual-watch"] if OS.get_cmdline_user_args().has("--manual-watch") else []))
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the guest copy")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0), "the guest joined")

	var f := _out.path_join("together_liveguest2.txt")
	await _wait_for(func() -> bool: return FileAccess.file_exists(f), 150.0)
	var text := FileAccess.get_file_as_string(f)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		_check(line.begins_with("PASS "), "guest: " + line.substr(5))
	NetSession.leave()
	await _finish()


# ── Guest ────────────────────────────────────────────────────
func _guest() -> void:
	AppState.set_setting("together_name", "LiveGuest")
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and (NetSession.get_info()["peers"] as Array).size() >= 2, 30.0),
		"joined the host")
	_check(await _wait_for(func() -> bool: return NetSession.is_host_live(), 15.0), "knows the host is sharing a tab")
	var manual := OS.get_cmdline_user_args().has("--manual-watch")
	if manual:
		# (a person, or the in-app browser, opens the page and really clicks Watch: the real autoplay rules)
		print("MANUAL: open http://127.0.0.1:%d/ and click Watch" % AppState.get_capture_port("capture_http_port"))
	else:
		_open_sender("?autowatch=1")
	_check(await _wait_for(func() -> bool: return AppState.get_source_mode() == "capture", 150.0 if manual else 60.0),
		"the host's live feed is on this big screen")
	_check(await _wait_for(_colors_change, 15.0), "the picture moves (the host's colours keep changing)")
	_check(await _wait_for(func() -> bool: return bool(_capture_info.get("has_audio", false)), 15.0), "the host's sound track arrives too")
	_loud_chunks = 0
	_audio_chunks = 0
	await _secs(4.0)
	_check(_loud_chunks > 20, "and it's really the host's tone, not silence (%d of %d chunks not silent)" % [_loud_chunks, _audio_chunks])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("live_feed_guest.png"))
	await _finish()


func _finish() -> void:
	for pid in _chrome_pids:
		OS.kill(pid)
	var profile := AppState.get_profile()
	if profile != "test":
		var f := FileAccess.open(_out.path_join("together_%s.txt" % profile), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines) + "\n")
			f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
