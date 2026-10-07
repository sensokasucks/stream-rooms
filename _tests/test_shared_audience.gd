extends Node
## Streaming together, phase 4: one audience for everyone's chat. The host seats its own viewer
## and the guest's (the guest sends its chat over), gives each streamer's viewers their own side,
## and the guest shows exactly the same seats, speech bubbles included, also after a room change.
## The guest writes its results (and the seats it saw) to a file; the host compares and prints.
##   <redot console exe> --path . _tests/test_shared_audience.tscn -- C:/temp/sr_tests --mp-profile=test

const SESSION_PORT: int = 7396
const PASSWORD: String = "audpass"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _spoke: Dictionary = {}          # slot -> times a speech bubble came


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


func _chat(platform: String, who: String, text: String) -> void:
	EventBus.chat_message_received.emit({"platform": platform, "user_id": who, "name": who, "username": who,
		"color": "", "text": text, "emotes": [], "timestamp": Time.get_unix_time_from_system(),
		"history": false, "system": false})


func _slot(platform: String, who: String) -> int:
	return AudienceManager.find_slot_for_user(platform, who)


func _ready() -> void:
	NetSession.auto_confirm = true      # (no "let them in" popups in a test)
	_out = OS.get_cmdline_user_args()[0]
	EventBus.audience_spoke.connect(func(slot: int, _p: Array) -> void: _spoke[slot] = int(_spoke.get(slot, 0)) + 1)
	AppState.set_setting("chat_enabled", false)                       # (never the real Stream Core)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("together_port", SESSION_PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_address", "127.0.0.1:%d" % SESSION_PORT)
	AppState.request_room("theater")
	add_child(load("res://core/main.tscn").instantiate())
	await _secs(5.0)
	if OS.get_cmdline_user_args().has("--role=guest"):
		await _guest()
	else:
		await _host()


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_shared_audience", true)
	AppState.set_setting("together_audience_areas", true)
	NetSession.host()
	_chat("twitch", "hostfan1", "hi from the host's chat")
	_check(await _wait_for(func() -> bool: return _slot("twitch", "hostfan1") >= 0, 5.0), "the host's viewer sits down")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_audguest.cfg"))
	DirAccess.remove_absolute(_out.path_join("together_audguest.txt"))
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "980,0", "res://_tests/test_shared_audience.tscn", "--", _out, "--mp-profile=audguest", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the guest copy")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0), "the guest joined")

	_check(await _wait_for(func() -> bool: return _slot("kick", "guestfan1") >= 0, 40.0), "the guest's viewer sits in the host's audience")
	var areas_ok := AudienceManager._area_of_section(AudienceManager.get_section(_slot("twitch", "hostfan1"))) in [-1, 0] \
		and AudienceManager._area_of_section(AudienceManager.get_section(_slot("kick", "guestfan1"))) in [-1, 1]
	_check(areas_ok, "each streamer's viewer sits on their own side (%s, %s)" % [
		AudienceManager.get_section(_slot("twitch", "hostfan1")), AudienceManager.get_section(_slot("kick", "guestfan1"))])
	var a := "A twitch=%d kick=%d" % [_slot("twitch", "hostfan1"), _slot("kick", "guestfan1")]
	await _secs(3.0)
	_chat("twitch", "hostfan1", "can everyone see this bubble?")
	await _secs(4.0)

	AppState.request_room("lecture_hall")
	await _secs(14.0)
	_check(_slot("twitch", "hostfan1") >= 0 and _slot("kick", "guestfan1") >= 0, "both still seated after a room change")
	var b := "B twitch=%d kick=%d" % [_slot("twitch", "hostfan1"), _slot("kick", "guestfan1")]
	await _secs(2.0)
	NetSession.leave()

	var f := _out.path_join("together_audguest.txt")
	await _wait_for(func() -> bool: return FileAccess.file_exists(f), 40.0)
	var text := FileAccess.get_file_as_string(f)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		if line.begins_with("A ") or line.begins_with("B "):
			_check(line == (a if line.begins_with("A ") else b), "the guest sees the same seats (host %s, guest %s)" % [a if line.begins_with("A ") else b, line])
		else:
			_check(line.begins_with("PASS "), "guest: " + line.substr(5))
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)


# ── Guest ────────────────────────────────────────────────────
func _both_seated_in_new_room() -> bool:
	return String(AppState.get_setting("room_id")) == "lecture_hall" and _slot("twitch", "hostfan1") >= 0 and _slot("kick", "guestfan1") >= 0


func _guest() -> void:
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and AudienceManager.is_mirror(), 30.0),
		"joined, and shows the host's audience")
	_check(await _wait_for(func() -> bool: return _slot("twitch", "hostfan1") >= 0, 15.0), "the host's viewer is already seated here")
	_chat("kick", "guestfan1", "hi from the guest's chat")
	_check(await _wait_for(func() -> bool: return _slot("kick", "guestfan1") >= 0, 15.0),
		"this PC's own viewer sits down once the host seats them")
	await _secs(1.0)
	_lines.append("A twitch=%d kick=%d" % [_slot("twitch", "hostfan1"), _slot("kick", "guestfan1")])
	var host_slot := _slot("twitch", "hostfan1")
	_check(await _wait_for(func() -> bool: return int(_spoke.get(host_slot, 0)) >= 1, 15.0), "the host's viewer's speech bubble shows here")
	_check(await _wait_for(_both_seated_in_new_room, 40.0), "after the room change, the same people are seated")
	await _secs(3.0)
	_lines.append("B twitch=%d kick=%d" % [_slot("twitch", "hostfan1"), _slot("kick", "guestfan1")])
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "noticed the session ending")
	_check(not AudienceManager.is_mirror(), "and has its own audience again")
	var f := FileAccess.open(_out.path_join("together_audguest.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
