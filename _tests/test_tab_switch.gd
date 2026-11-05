extends Node
## Streaming together: whose shared tab is on everyone's big screen (Together tab > "Big screen tab",
## setting screen_tab_peer). Run as the host; it starts a guest copy itself. Checks what NetSession
## tells each sender page (EventBus.live_feed_changed) as the host switches from its own tab to the
## guest's and back:
##   host's tab (default): host publishes, guest views
##   guest's tab: guest publishes under its own stream name, host views it (and follows by itself),
##     "live" follows whether the guest is actually sharing (the guest's sender status "own")
##   back to the host's: host publishes again, guest views the host's feed again
## No browser and no VDO.Ninja: test_live_feed covers the video itself.
##   <redot console exe> --path . _tests/test_tab_switch.tscn -- C:/temp/sr_tests --mp-profile=test
## The guest writes its PASS / FAIL lines to a file the host prints at the end.

const PORT: int = 7393                # not the default, so a real session on this PC isn't disturbed
const PASSWORD: String = "testpass"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _main: Node
var _live: Dictionary = {}            # the last live_feed_changed on this copy


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
	DirAccess.make_dir_recursive_absolute(_out)     # (the guest's result file goes in here)
	EventBus.live_feed_changed.connect(func(info: Dictionary) -> void: _live = info.duplicate())
	NetSession.auto_confirm = true       # (no "let them in" / "right host?" popups)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("together_port", PORT)
	AppState.set_setting("together_live_feed", true)
	AppState.set_setting("screen_tab_peer", "")
	AppState.set_setting("together_password", PASSWORD)
	if args.has("--role=guest"):
		await _guest()
	else:
		await _host()


func _start_main() -> void:
	_main = load("res://core/main.tscn").instantiate()
	add_child(_main)
	await _secs(3.0)


## What the sender page would report while sharing its own tab (or {} pieces when not).
func _pretend_sharing(on: bool) -> void:
	EventBus.capture_status_changed.emit({"connected": true, "capturing": on, "own": on, "fps": 0, "url": "", "presenters": []})


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_name", "TabHost")
	await _start_main()
	NetSession.host()
	_check(NetSession.get_role() == "host", "hosting started")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_tabguest.cfg"))
	DirAccess.remove_absolute(_out.path_join("tabswitch_tabguest.txt"))
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"res://_tests/test_tab_switch.tscn", "--", _out, "--mp-profile=tabguest", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the guest copy")
	var joined := await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0)
	_check(joined, "the guest joined")
	if not joined:
		await _finish()
		return
	_pretend_sharing(true)
	_check(String(_live.get("role", "")) == "publish", "the host's own tab goes out by default (role %s)" % _live.get("role"))
	var host_id := String(_live.get("id", ""))
	await _secs(3.0)        # (the guest checks that it views the host's feed)

	# the guest's tab on the big screen
	AppState.set_setting("screen_tab_peer", "TabGuest")
	_check(String(_live.get("role", "")) == "view" and String(_live.get("id", "")) != host_id and String(_live.get("id", "")) != "",
		"switched to the guest: the host views the guest's own stream")
	_check(bool(_live.get("auto", false)) and String(_live.get("from_name", "")) == "TabGuest",
		"the host's page follows by itself and knows whose tab it is")
	_check(await _wait_for(func() -> bool: return bool(_live.get("live", false)), 30.0),
		"goes live once the guest shares a tab")
	_check(await _wait_for(func() -> bool: return not bool(_live.get("live", true)), 30.0),
		"and stops being live when the guest stops sharing")
	await _secs(2.0)

	# a name that isn't in the session falls back to the host's tab
	AppState.set_setting("screen_tab_peer", "Nobody")
	_check(String(_live.get("role", "")) == "publish" and String(_live.get("id", "")) == host_id, "someone who isn't here: the host's tab again")
	AppState.set_setting("screen_tab_peer", "")
	_check(String(_live.get("role", "")) == "publish", "switched back: the host publishes again")
	_check(await _wait_for(func() -> bool: return FileAccess.file_exists(_out.path_join("tabswitch_tabguest.txt")), 60.0),
		"the guest finished")
	var f := FileAccess.open(_out.path_join("tabswitch_tabguest.txt"), FileAccess.READ)
	if f:
		for line in f.get_as_text().split("\n", false):
			print(line.replace("PASS ", "PASS guest: ").replace("FAIL ", "FAIL guest: "))
			if line.begins_with("FAIL"):
				_fails += 1
	await _finish()


# ── Guest ────────────────────────────────────────────────────
func _guest() -> void:
	AppState.set_setting("together_address", "127.0.0.1:%d" % PORT)
	AppState.set_setting("together_name", "TabGuest")
	await _start_main()
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and (NetSession.get_info()["peers"] as Array).size() == 2, 60.0),
		"joined the host")
	_check(await _wait_for(func() -> bool: return String(_live.get("role", "")) == "view" and bool(_live.get("live", false)), 20.0),
		"views the host's tab at first")
	_check(String(_live.get("from_name", "x")) == "" and NetSession.live_from() == "" and NetSession.is_host_live(),
		"knows it's the host's tab")
	var host_id := String(_live.get("id", ""))
	_check(await _wait_for(func() -> bool: return String(_live.get("role", "")) == "publish", 30.0),
		"the host put this guest's tab on: this copy's sender page publishes")
	_check(String(_live.get("id", "")) != host_id and String(_live.get("id", "")) != "", "under its own stream name, not the host's")
	_check(NetSession.live_from() == "me" and not NetSession.is_host_live(), "the panel says everyone sees this guest's tab")
	await _secs(1.0)
	_pretend_sharing(true)      # the guest presses Share in its sender page
	await _secs(3.0)
	_pretend_sharing(false)     # ... and Stop
	_check(await _wait_for(func() -> bool: return String(_live.get("role", "")) == "view" and String(_live.get("id", "")) == host_id, 30.0),
		"switched back: views the host's tab again")
	await _finish()


func _finish() -> void:
	var role := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mp-profile="):
			role = a.trim_prefix("--mp-profile=")
	if role != "test":
		var f := FileAccess.open(_out.path_join("tabswitch_%s.txt" % role), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines) + "\n")
			f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
