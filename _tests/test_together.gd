extends Node
## Streaming together (NetSession): password / version checks, then a real session between
## copies on this PC. Run as the host (tools/run_tests.ps1 does this); it starts two more copies
## itself: a guest that joins and checks what arrives, and one with the wrong password.
##   <redot console exe> --path . _tests/test_together.tscn -- C:/temp/sr_tests --mp-profile=test
## The guests write their PASS / FAIL lines to files in the output folder, which the host prints
## at the end as "PASS guest: ...", so one run shows everything.

const PORT: int = 7391                # not the default, so a real session on this PC isn't disturbed
const PASSWORD: String = "testpass"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _main: Node
var _remote_reactions: int = 0
var _statuses: PackedStringArray = []


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
	EventBus.reaction_play.connect(func(d: Dictionary) -> void:
		if bool(d.get("net_remote", false)):
			_remote_reactions += 1)
	EventBus.status_message.connect(func(t: String, _e: bool) -> void: _statuses.append(t))
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("reactions_enabled", true)
	AppState.set_setting("together_port", PORT)
	if args.has("--role=guest"):
		await _guest()
	elif args.has("--role=badguest"):
		await _bad_guest()
	else:
		await _host()


func _start_main() -> void:
	_main = load("res://core/main.tscn").instantiate()
	add_child(_main)
	await _secs(3.0)


func _markers() -> NetMarkers:
	for c in _main.get_children():
		if c is NetMarkers:
			return c
	return null


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	_unit_checks()
	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_name", "TestHost")
	AppState.set_setting("house_lights", 1.0)
	await _start_main()

	# hosting refuses a too-short password
	AppState.set_setting("together_password", "ab")
	NetSession.host()
	_check(NetSession.get_role() == "off", "hosting needs a password of 4+ characters")
	AppState.set_setting("together_password", PASSWORD)
	NetSession.host()
	_check(NetSession.get_role() == "host", "hosting started (%s)" % NetSession.get_info()["status"])

	for p in ["testguest", "testbad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_%s.cfg" % p))
		DirAccess.remove_absolute(_out.path_join("together_%s.txt" % p))
	_spawn("testguest", "--role=guest", "0,0")

	var joined := await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0)
	_check(joined, "the guest joined")
	if not joined:
		await _finish()
		return
	var guest_id := 0
	for p: Dictionary in NetSession.get_info()["peers"]:
		if int(p["id"]) != 1:
			guest_id = int(p["id"])
			_check(String(p["name"]) == "TestGuest", "the guest's name arrived (%s)" % p["name"])
	await _secs(4.0)

	# shared state the guest checks
	AppState.set_setting("house_lights", 0.37)
	AppState.set_setting(AppState.presenter_key(2, "source"), "camera")       # only on this PC: guests show a silhouette
	AppState.set_setting(AppState.presenter_key(2, "url"), "file:///C:/Windows/win.ini")   # never reaches a guest
	AppState.request_room("lecture_hall_panel")
	await _secs(6.0)
	AppState.set_curtain(true)
	await _secs(2.0)
	Reactions.play_test("confetti")
	await _secs(6.0)

	# the guest becomes a co-host and changes the house lights; then sends a reaction
	NetSession.set_cohost(guest_id, true)
	_check(await _wait_for(func() -> bool: return absf(float(AppState.get_setting("house_lights")) - 0.62) < 0.001, 30.0),
		"a co-host's change reached the host")
	_check(await _wait_for(func() -> bool: return _remote_reactions > 0, 30.0), "the guest's reaction played on the host")
	_check(await _wait_for(func() -> bool: return _markers() != null and _markers().get_marker_count() >= 1, 15.0),
		"the guest's camera shows on the host")

	# someone with the wrong password
	_spawn("testbad", "--role=badguest", "980,0")
	_check(await _wait_for(func() -> bool:
		for t in _statuses:
			if t.contains("Wrong session password"):
				return true
		return false, 90.0), "a wrong password was refused")
	await _secs(2.0)
	_check((NetSession.get_info()["peers"] as Array).size() == 2, "the refused copy isn't in the session")

	# the guests finish after the session ends
	await _secs(2.0)
	NetSession.leave()
	_check(NetSession.get_role() == "off", "stopped hosting")
	for p in ["testguest", "testbad"]:
		var f := _out.path_join("together_%s.txt" % p)
		await _wait_for(func() -> bool: return FileAccess.file_exists(f), 40.0)
		var text := FileAccess.get_file_as_string(f)
		if text == "":
			_check(false, "%s wrote its results" % p)
		for line in text.split("\n", false):
			var ok := line.begins_with("PASS ")
			_check(ok, "%s: %s" % [p, line.substr(5)])
	await _finish()


func _spawn(profile: String, role: String, pos: String) -> void:
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", pos, "res://_tests/test_together.tscn", "--", _out, "--mp-profile=" + profile, role])
	var pid := OS.create_process(OS.get_executable_path(), args)
	_check(pid > 0, "started the %s copy" % profile)


func _unit_checks() -> void:
	var nonce := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	var v := "2026.10.1"
	var hello := {"t": "hello", "protocol": NetSession.PROTOCOL, "version": v, "proof": NetSession.proof(nonce, PASSWORD)}
	_check(NetSession.check_hello(hello, nonce, PASSWORD, v) == "", "the right password and version are let in")
	_check(NetSession.check_hello(hello, nonce, "other", v) == "Wrong session password.", "a wrong password is refused")
	_check(NetSession.check_hello(hello, PackedByteArray([9]), PASSWORD, v) != "", "an answer to another challenge is refused")
	var why := NetSession.check_hello(hello, nonce, PASSWORD, "2026.11.0")
	_check(why.contains("Different Stream Rooms versions") and why.contains("2026.11.0") and why.contains(v),
		"a different version is refused in plain words")
	var old := hello.duplicate()
	old["protocol"] = NetSession.PROTOCOL + 1
	_check(NetSession.check_hello(old, nonce, PASSWORD, v) != "", "a different protocol is refused")
	_check(NetSession.is_web_address("https://vdo.ninja/?view=abc") and NetSession.is_web_address(""), "web addresses are allowed")
	_check(not NetSession.is_web_address("file:///C:/x.html") and not NetSession.is_web_address("C:/x.html")
		and not NetSession.is_web_address("https://a b"), "file paths and odd addresses are refused")
	var r := NetSession._shareable_reaction({"id": "abc", "effect": "throw", "count": 999,
		"params": {"object": "🍅", "object_image": {"url": "/reactions/images/x.png"}},
		"target": {"type": "user", "name": "bob", "extra": 1}, "from": {"display_name": "Al", "token": "x"}})
	_check(String(r["id"]) == "net-abc" and int(r["count"]) == 50 and not (r["params"] as Dictionary).has("object_image")
		and (r["params"] as Dictionary).has("object") and not (r["target"] as Dictionary).has("extra")
		and not (r["from"] as Dictionary).has("token"), "a shared reaction carries only what it needs")
	_check(NetSession.is_shared("house_lights") and NetSession.is_shared("presenter_3_url")
		and not NetSession.is_shared("presenter_3_camera") and not NetSession.is_shared("volume"), "the shared settings list")


# ── Guest ────────────────────────────────────────────────────
func _guest() -> void:
	AppState.set_setting("together_address", "127.0.0.1:%d" % PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_name", "TestGuest")
	AppState.set_setting("graphics_quality", "high")
	AppState.set_setting("house_lights", 1.0)
	await _start_main()
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and (NetSession.get_info()["peers"] as Array).size() == 2, 30.0),
		"joined the host")
	_check(bool(NetSession.get_info()["suggest_medium"]), "suggests Medium graphics on High")
	_check(await _wait_for(func() -> bool: return absf(float(AppState.get_setting("house_lights")) - 0.37) < 0.001, 30.0),
		"the host's house lights arrived")
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting(AppState.presenter_key(2, "source"))) == "silhouette", 10.0),
		"the host's camera presenter shows as a silhouette")
	_check(not String(AppState.get_setting(AppState.presenter_key(2, "url"))).begins_with("file:"), "a file address from the host was ignored")
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting("room_id")) == "lecture_hall_panel", 30.0),
		"the host's room change arrived")
	_check(await _wait_for(func() -> bool: return AppState.is_curtain_closed(), 20.0), "the host's curtain closed here too")
	_check(await _wait_for(func() -> bool: return _remote_reactions > 0, 20.0), "the host's reaction played here")
	_check(await _wait_for(func() -> bool: return _markers() != null and _markers().get_marker_count() >= 1, 10.0),
		"the host's camera shows here")
	await _secs(0.5)
	var mk: Node3D = _markers().get_marker(1) if _markers() else null
	var near := mk != null and mk.global_position.distance_to(get_viewport().get_camera_3d().global_position) <= NetMarkers.HIDE_NEAR_M
	_check(mk != null and mk.visible != near, "a camera marker on top of this camera hides (near=%s)" % near)

	# not a co-host yet: shared things are locked
	var panel: Node = _main.get_node("ControlPanel")
	AppState.set_setting("house_lights", 0.9)
	_check(absf(float(AppState.get_setting("house_lights")) - 0.37) < 0.001, "a guest can't change the house lights alone")
	_check(not (panel._sliders["house_lights"] as HSlider).editable and (panel._room_select as OptionButton).disabled,
		"shared controls are locked for a guest")
	_check((panel._sliders["volume"] as HSlider).editable, "personal controls stay unlocked")

	_check(await _wait_for(func() -> bool: return bool(NetSession.get_info()["cohost"]), 60.0), "became a co-host")
	_check((panel._sliders["house_lights"] as HSlider).editable, "a co-host's shared controls unlock")
	AppState.set_setting("house_lights", 0.62)
	_check(await _wait_for(func() -> bool: return absf(float(AppState.get_setting("house_lights")) - 0.62) < 0.001, 10.0),
		"a co-host's change came back from the host")
	Reactions.play_test("confetti")
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 120.0), "noticed the session ending")
	await _finish()


func _bad_guest() -> void:
	AppState.set_setting("together_address", "127.0.0.1:%d" % PORT)
	AppState.set_setting("together_password", "wrongpass")
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 30.0), "the wrong password was turned away")
	_check(String(NetSession.get_info()["status"]).contains("Wrong session password"),
		"it says why (%s)" % NetSession.get_info()["status"])
	await _finish()


func _finish() -> void:
	var role := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mp-profile="):
			role = a.trim_prefix("--mp-profile=")
	if role != "test":
		var f := FileAccess.open(_out.path_join("together_%s.txt" % role), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines) + "\n")
			f.close()
	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
