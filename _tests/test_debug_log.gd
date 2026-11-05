extends Node
## The troubleshooting log (autoload/debug_log.gd): a file is written in user://logs_to_share
## (a "test" sub-folder for this profile), it has the header, engine errors and app events, and
## private details are swapped for tags: IP addresses, user folders, the user and computer name,
## tunnel names, keys in links, e-mail addresses. Clock times and 127.0.0.1 stay as they are.
##   <redot console exe> --path . _tests/test_debug_log.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _ready() -> void:
	AppState.set_setting("debug_log", true)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout

	# cleaning, straight
	var c := func(s: String) -> String: return DebugLog.clean(s)
	_check(c.call("joining ws://100.101.102.103:7350") == "joining ws://<ip-tailscale#1>:7350", "a Tailscale address gets a tag (%s)" % c.call("joining ws://100.101.102.103:7350"))
	_check(c.call("again 100.101.102.103") == "again <ip-tailscale#1>", "the same address keeps the same tag all run")
	_check(c.call("from 192.168.1.20 and 8.8.4.4") == "from <ip-home#2> and <ip#3>", "home network and internet addresses are told apart (%s)" % c.call("from 192.168.1.20 and 8.8.4.4"))
	_check(c.call("Core at ws://127.0.0.1:3850/ws") == "Core at ws://127.0.0.1:3850/ws", "this PC's own address (127.0.0.1) stays")
	_check(c.call("at 18:12:09 the room") == "at 18:12:09 the room", "a clock time isn't mistaken for an address")
	_check(c.call("v6 fe80::1c2b:3d4e:5f60:7a8b%12 up").begins_with("v6 <ip6#"), "an IPv6 address gets a tag (%s)" % c.call("v6 fe80::1c2b:3d4e:5f60:7a8b%12 up"))
	_check(c.call("Redot 26.2.0.stable") == "Redot 26.2.0.stable", "a version number isn't an address")
	var p := String(c.call("C:\\Users\\Jonathan Smith\\Documents\\clip.mp4"))
	_check(not p.contains("Jonathan") and not p.contains("Smith") and p.contains("<user>"), "a Windows user folder loses the user name (%s)" % p)
	p = c.call("D:/Users/someone/OneDrive/x.png and /home/pat/x")
	_check(not p.contains("someone") and not p.contains("pat/"), "other user folders too, either slash (%s)" % p)
	p = c.call(OS.get_user_data_dir().path_join("settings.cfg"))
	_check(p.begins_with("<app data>"), "the app's own folder becomes <app data> (%s)" % p)
	p = c.call("wss://brave-lion-fancy-hat.trycloudflare.com/?key=abc123&x=1 token=zzz oauth:q1w2e3 Bearer abc.def")
	_check(not p.contains("brave-lion") and not p.contains("abc123") and not p.contains("zzz") and not p.contains("q1w2e3")
		and not p.contains("abc.def") and p.contains("x=1"), "tunnel names and keys / tokens are hidden, other link parts stay (%s)" % p)
	_check(c.call("mail me@example.com ok") == "mail <email> ok", "e-mail addresses are hidden")
	var user := OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else OS.get_environment("USER")
	if user.length() >= 3:
		p = c.call("hello %s." % user)
		_check(not p.contains(user), "this PC's user name is hidden on its own too (%s)" % p)

	# the file
	var path := DebugLog.get_log_path()
	_check(path != "" and FileAccess.file_exists(path), "a log file is written (%s)" % DebugLog.clean(path))
	_check(path.get_base_dir().ends_with("logs_to_share/test") or path.get_base_dir().ends_with("logs_to_share\\test"),
		"a test profile writes into its own sub-folder")
	print("pretend friend at 203.0.113.9 said hi from C:\\Users\\Pat\\Desktop")
	push_error("pretend error for the log")
	DebugLog.note("net", "peer #5 connected from 198.51.100.7")
	EventBus.status_message.emit("A status message.", true)
	for i in 5:
		print("same line again")
	print("different line")
	await get_tree().process_frame
	var text := FileAccess.get_file_as_string(path)
	_check(text.begins_with("=== Stream Rooms log for troubleshooting ==="), "the file starts with the header")
	_check(text.contains("Graphics:") and text.contains("Settings changed from the defaults:"), "the header has the graphics card and changed settings")
	_check(text.contains("pretend friend at <ip#") and text.contains("C:\\Users\\<user>\\Desktop") and not text.contains("203.0.113.9"), "printed lines are cleaned in the file")
	_check(text.contains("ERROR: pretend error for the log") and text.contains("test_debug_log.gd"), "engine errors are caught, with where they came from")
	_check(text.contains("[net] peer #5 connected from <ip#") and not text.contains("198.51.100.7"), "app notes are cleaned too")
	_check(text.contains("[message] ERROR A status message."), "status messages are logged")
	_check(text.contains("(the line above repeated 4 more times)"), "a repeated line is counted, not written again")
	_check(not text.contains(user) or user.length() < 3, "the user name appears nowhere in the file")

	# after a run that didn't close normally: a note and the end of the engine's log from then
	var report := String(DebugLog._crash_report())
	_check(report.contains("didn't close normally"), "the crash report says the last run didn't close normally")
	_check(not report.contains(user) or user.length() < 3, "and the engine log lines in it are cleaned")

	# turning it off closes the file; on again starts a new one
	AppState.set_setting("debug_log", false)
	_check(DebugLog.get_log_path() == "", "unticking stops the log")
	AppState.set_setting("debug_log", true)
	_check(DebugLog.get_log_path() != "", "ticking it again starts a log")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
