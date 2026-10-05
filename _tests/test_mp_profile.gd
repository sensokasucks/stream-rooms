extends Node
## Multiplayer launch profile (--mp-profile): own settings file, shifted capture ports and the
## profile name in the window title. Run with a profile, e.g.
##   <redot console exe> --path . _tests/test_mp_profile.tscn -- C:/temp/sr_tests --mp-profile=guest2
## Two copies with different profiles can run at the same time (that's part of what it checks).

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## True when something is listening on 127.0.0.1:port.
func _port_open(port: int) -> bool:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host("127.0.0.1", port) != OK:
		return false
	for i in 50:
		tcp.poll()
		var st := tcp.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			tcp.disconnect_from_host()
			return true
		if st == StreamPeerTCP.STATUS_ERROR:
			return false
		await _secs(0.02)
	return false


func _ready() -> void:
	# name parsing (doesn't depend on how this test was started)
	_check(AppState._parse_profile(PackedStringArray(["--mp-profile=guest1"])) == "guest1", "parses --mp-profile=guest1")
	_check(AppState._parse_profile(PackedStringArray(["C:/temp", "--mp-profile=bob_2"])) == "bob_2", "finds the flag after other args")
	_check(AppState._parse_profile(PackedStringArray(["--mp-profile=../evil"])) == "", "rejects a name with path characters")
	_check(AppState._parse_profile(PackedStringArray(["--mp-profile="])) == "", "rejects an empty name")
	_check(AppState._parse_profile(PackedStringArray(["C:/clip.mp4"])) == "", "no flag = no profile")

	var profile := AppState.get_profile()
	print("profile=", profile, " offset=", AppState.get_port_offset())
	if profile.is_empty():
		_check(false, "this test needs a profile: add --mp-profile=guest2 after the output folder")
		get_tree().quit(1)
		return

	_check(AppState.get_settings_path() == "user://settings_%s.cfg" % profile, "settings file is settings_%s.cfg" % profile)
	_check(AppState.get_port_offset() >= 10, "capture ports are shifted")

	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(2.0)

	_check(get_window().title.ends_with("[%s]" % profile), "window title shows the profile (%s)" % get_window().title)
	var http := AppState.get_capture_port("capture_http_port")
	var ws := AppState.get_capture_port("capture_ws_port")
	_check(await _port_open(http), "sender page listens on %d" % http)
	_check(await _port_open(ws), "stream listens on %d" % ws)

	# settings are written to the profile's own file
	var marker := 0.8 if absf(float(AppState.get_setting("volume")) - 0.8) > 0.01 else 0.7
	AppState.set_setting("volume", marker)
	SaveManager.save_now()
	var cfg := ConfigFile.new()
	_check(cfg.load(AppState.get_settings_path()) == OK and absf(float(cfg.get_value("settings", "volume", -1.0)) - marker) < 0.001,
			"a changed setting lands in settings_%s.cfg" % profile)

	# stay up a moment so a second copy started alongside overlaps with this one
	await _secs(4.0)
	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
