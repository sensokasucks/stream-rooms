extends Node
## The sender page keeps its frame rate when its tab is in the background. It opens the sender page
## in a real (visible) Chrome that captures the first monitor by itself ("?autoshare" plus Chrome's
## --auto-select-desktop-capture-source), waits for the frames, then opens another tab in front of
## it and watches the frame rate for a while. The game's own camera keeps breathing so the captured
## screen keeps changing (a screen capture only sends frames when something moves).
## Needs Google Chrome; it takes over part of the screen for a few minutes.
##   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Tests test_sender_background -TimeLimit 600
## "--long" after the profile (run the exe directly) keeps the tab in the background for 5.5 minutes:
## Chrome slows a tab down much more after 5 minutes.

const CHROME: String = "C:/Program Files/Google/Chrome/Application/chrome.exe"
const BACKGROUND_S: float = 90.0
const BACKGROUND_LONG_S: float = 330.0

var _fails: int = 0
var _fps: float = 0.0
var _pump: String = ""
var _pids: Array[int] = []
var _t: float = 0.0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
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


func _chrome(url: String) -> void:
	var profile_dir := OS.get_cmdline_user_args()[0].path_join("chrome_bg_" + AppState.get_profile())
	var pid := OS.create_process(CHROME, PackedStringArray(["--user-data-dir=" + profile_dir, "--no-first-run",
		"--no-default-browser-check", "--auto-select-desktop-capture-source=Screen 1",
		"--window-size=800,600", "--window-position=20,20", url]))
	_check(pid > 0, "opened %s in Chrome" % url)
	_pids.append(pid)


## Average frame rate over the next `secs` seconds.
func _average_fps(secs: int) -> float:
	var total := 0.0
	for i in secs:
		await _secs(1.0)
		total += _fps
	return total / secs


func _process(delta: float) -> void:
	_t += delta
	AppState.set_setting("camera_fov", 65.0 + 8.0 * sin(_t * 1.5))


func _ready() -> void:
	EventBus.capture_status_changed.connect(func(i: Dictionary) -> void:
		_fps = float(i.get("fps", 0.0))
		if String(i.get("pump", "")) != "":
			_pump = String(i["pump"]))
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	var long := OS.get_cmdline_user_args().has("--long")
	add_child(load("res://core/main.tscn").instantiate())
	await _secs(3.0)
	if not FileAccess.file_exists(CHROME):
		_check(false, "Google Chrome is installed at " + CHROME)
		_finish()
		return
	var base := "http://127.0.0.1:%d/" % AppState.get_capture_port("capture_http_port")
	_chrome(base + "?autoshare=1")
	_check(await _wait_for(func() -> bool: return AppState.get_source_mode() == "capture", 30.0), "the sender page shares the screen")
	await _secs(5.0)
	var front := await _average_fps(8)
	_check(front >= 15.0, "frames arrive with the page in front (%d a second; the worker gets %s)" % [int(front), _pump])

	# another tab in front of it, in the same window (same profile, so Chrome adds a tab)
	_chrome(base + "backdrop?url=about:blank&bg=202020")
	var wait := BACKGROUND_LONG_S if long else BACKGROUND_S
	await _secs(wait)
	var back := await _average_fps(10)
	_check(back >= 15.0 and back >= front * 0.6, "still %d frames a second after %d s in a background tab (was %d in front; want 15+)" % [int(back), int(wait) + 10, int(front)])
	_finish()


func _finish() -> void:
	for pid in _pids:
		OS.kill(pid)
	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
