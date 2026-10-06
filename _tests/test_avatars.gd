extends Node
## Streaming together: everyone's avatar on a podium. The host (podium 1) and a guest (podium 2)
## each run their sender page in headless Chrome with "?testshare" (a generated picture stands in
## for the camera). The host's podium-1 picture should show up on the guest's podium 1, and the
## guest's podium-2 picture on the host's podium 2. Needs the internet (VDO.Ninja) and Google
## Chrome, so it isn't in the default set.
##   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Tests test_avatars -TimeLimit 300

const SESSION_PORT: int = 7398
const PASSWORD: String = "avatarpass"
const CHROME: String = "C:/Program Files/Google/Chrome/Application/chrome.exe"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _main: Node
var _chrome_pids: Array[int] = []
var _pres_tex: Dictionary = {}       # presenter -> texture (null when it went away)


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
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	EventBus.presenter_texture_changed.connect(func(n: int, t: Texture2D) -> void: _pres_tex[n] = t)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("together_port", SESSION_PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_address", "127.0.0.1:%d" % SESSION_PORT)
	AppState.set_setting("together_live_feed", false)      # (only the avatars here)
	AppState.set_setting("together_avatars", true)
	_main = load("res://core/main.tscn").instantiate()
	add_child(_main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")       # (podiums)
	await _secs(5.0)
	if not FileAccess.file_exists(CHROME):
		_check(false, "Google Chrome is installed at " + CHROME)
		await _finish()
		return
	if args.has("--role=guest"):
		await _guest()
	else:
		await _host()


func _open_sender() -> void:
	var url := "http://127.0.0.1:%d/?testshare=1" % AppState.get_capture_port("capture_http_port")
	var profile_dir := _out.path_join("chrome_" + AppState.get_profile())
	var pid := OS.create_process(CHROME, PackedStringArray(["--headless=new", "--user-data-dir=" + profile_dir, "--no-first-run",
		"--no-default-browser-check", "--autoplay-policy=no-user-gesture-required", url]))
	_check(pid > 0, "opened the sender page in headless Chrome")
	_chrome_pids.append(pid)


func _has_tex(n: int) -> bool:
	return _pres_tex.get(n) != null


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_name", "AvatarHost")
	AppState.set_setting("together_avatar_height", 240)
	for n in [1, 2]:
		AppState.set_setting(AppState.presenter_key(n, "on"), true)
		AppState.set_setting(AppState.presenter_key(n, "source"), "camera")
		AppState.set_setting(AppState.presenter_key(n, "key"), false)
	NetSession.host()
	_open_sender()
	_check(await _wait_for(func() -> bool: return _has_tex(1), 30.0), "my own avatar (podium 1) shows here, from my sender page")
	# nobody else yet: podium 2 wants a camera too, and this sender page gives it one (its own second feed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_avguest2.cfg"))
	var result := _out.path_join("together_avguest2.txt")
	DirAccess.remove_absolute(result)
	var pargs := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "980,0", "res://_tests/test_avatars.tscn", "--", _out, "--mp-profile=avguest2", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), pargs) > 0, "started the guest copy")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0), "the guest joined")
	var slots: Array = NetSession.avatar_slots()
	_check(slots.size() == 2 and bool(slots[0]["mine"]) and not bool(slots[1]["mine"]), "podium 1 is mine, podium 2 is the guest's")
	# podium 2 is the guest's now: its picture should come from the guest, not from my sender page
	_pres_tex.erase(2)
	await _secs(3.0)
	_check(await _wait_for(func() -> bool: return _has_tex(2) and _pres_tex[2].get_width() > 0, 90.0), "the guest's avatar arrived on podium 2 here")
	await _secs(2.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("avatars_host.png"))
	await _wait_for(func() -> bool: return FileAccess.file_exists(result), 120.0)
	var text := FileAccess.get_file_as_string(result)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		_check(line.begins_with("PASS "), "guest: " + line.substr(5))
	NetSession.leave()
	await _finish()


# ── Guest ────────────────────────────────────────────────────
func _guest() -> void:
	AppState.set_setting("together_name", "AvatarGuest")
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and (NetSession.get_info()["peers"] as Array).size() == 2, 30.0),
		"joined the host")
	_check(await _wait_for(func() -> bool: return NetSession.avatar_slots().size() == 2 and bool(NetSession.avatar_slots()[1]["mine"]), 20.0),
		"podium 2 is mine here")
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting(AppState.presenter_key(1, "source"))) == "camera", 20.0),
		"the host's camera podium stays a camera here (not a silhouette), since the avatar is sent over")
	_open_sender()
	_check(await _wait_for(func() -> bool: return _has_tex(2), 40.0), "my own avatar (podium 2) shows here, from my sender page")
	_check(await _wait_for(func() -> bool: return _has_tex(1) and _pres_tex[1].get_width() > 0, 90.0), "the host's avatar arrived on podium 1 here")
	if _has_tex(1):
		_check(_pres_tex[1].get_height() <= 400, "the host's avatar came at the host's quality setting (%dp)" % _pres_tex[1].get_height())
	await _secs(2.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("avatars_guest.png"))
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
	get_tree().quit(1 if _fails > 0 else 0)
