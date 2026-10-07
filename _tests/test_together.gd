extends Node
## Streaming together (NetSession): password / version checks, then a real session between
## copies on this PC. Run as the host (tools/run_tests.ps1 does this); it starts two more copies
## itself: a guest that joins and checks what arrives, one with the wrong password, and one the host
## declines in the "wants to join" popup.
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
var _confirms: Array = []             # [{side, id, name}] from EventBus.net_confirm_needed


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
	EventBus.net_confirm_needed.connect(func(side: String, id: int, who: String) -> void:
		_confirms.append({"side": side, "id": id, "name": who}))
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("reactions_enabled", true)
	AppState.set_setting("together_port", PORT)
	if args.has("--role=guest"):
		await _guest()
	elif args.has("--role=badguest"):
		await _bad_guest()
	elif args.has("--role=declined"):
		await _declined_guest()
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
	_check(not String(NetSession.get_info()["status"]).contains("127.0.0.1"), "the status never shows an address")

	for p in ["testguest", "testbad", "testno"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_%s.cfg" % p))
		DirAccess.remove_absolute(_out.path_join("together_%s.txt" % p))
	_spawn("testguest", "--role=guest", "0,0")

	# both sides confirm first: the host sees "TestGuest wants to join" and nothing is shared yet
	var asked := await _wait_for(func() -> bool: return _confirms.size() > 0, 90.0)
	_check(asked, "the host is asked before a guest gets in")
	if not asked:
		await _finish()
		return
	var ask: Dictionary = _confirms[0]
	_check(String(ask["side"]) == "host" and String(ask["name"]) == "TestGuest", "the popup names the guest (%s)" % ask["name"])
	var panel: Node = _main.get_node("ControlPanel")
	_check((panel._net_dialogs as Dictionary).has(int(ask["id"])) and (panel._net_dialogs[int(ask["id"])] as Window).visible,
		"a popup is open on the host")
	await _secs(2.0)
	_check((NetSession.get_info()["peers"] as Array).size() == 1 and (NetSession.get_info()["pending"] as Array).size() == 1,
		"the guest is waiting, not in the session, until both say yes")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("together_popup.png"))
	NetSession.approve(int(ask["id"]), true)

	var joined := await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0)
	_check(joined, "the guest joined once both confirmed")
	_check(not (panel._net_dialogs as Dictionary).has(int(ask["id"])), "the host's popup closed by itself")
	_check((NetSession.get_info()["pending"] as Array).is_empty(), "nobody is waiting any more")
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
	AppState.set_setting(AppState.presenter_key(2, "source"), "peer")         # podium 2 shows the guest's avatar
	AppState.set_setting(AppState.presenter_key(2, "peer"), "TestGuest")
	AppState.set_setting(AppState.presenter_key(4, "source"), "camera")       # podium 4: a camera on this PC: guests show a silhouette
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

	# a podium picture travels to the guest as bytes; un-sharing presenters frees the guest's own
	var img := Image.create(48, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.9, 0.3))
	var png := _out.path_join("host_badge.png")
	img.save_png(png)
	AppState.set_setting(AppState.presenter_key(3, "picture"), png)
	AppState.set_setting(AppState.presenter_key(3, "name"), "HostName")
	await _secs(8.0)
	AppState.set_setting("together_share_presenters", false)
	await _secs(14.0)          # (the guest changes its own presenter meanwhile)
	_check(String(AppState.get_setting(AppState.presenter_key(3, "source"))) != "green", "a guest's own presenter change stays on the guest once presenters aren't shared")
	AppState.set_setting("together_share_presenters", true)
	await _secs(3.0)

	# someone with the wrong password
	_spawn("testbad", "--role=badguest", "980,0")
	_check(await _wait_for(func() -> bool:
		for t in _statuses:
			if t.contains("Wrong session password"):
				return true
		return false, 90.0), "a wrong password was refused")
	await _secs(2.0)
	_check((NetSession.get_info()["peers"] as Array).size() == 2, "the refused copy isn't in the session")
	_check(_confirms.size() == 1, "a wrong password never reaches the popup")

	# someone with the right password whom the host declines
	_spawn("testno", "--role=declined", "980,300")
	_check(await _wait_for(func() -> bool: return _confirms.size() >= 2, 90.0), "the host is asked about the next guest")
	if _confirms.size() >= 2:
		var no: Dictionary = _confirms[1]
		_check(String(no["name"]) == "TestNo", "the popup names them (%s)" % no["name"])
		NetSession.approve(int(no["id"]), false)
		_check(await _wait_for(func() -> bool: return (NetSession.get_info()["pending"] as Array).is_empty(), 10.0), "declining clears the wait")
		await _secs(3.0)
		_check((NetSession.get_info()["peers"] as Array).size() == 2, "a declined guest isn't in the session")

	# the guests finish after the session ends
	await _secs(2.0)
	NetSession.leave()
	_check(NetSession.get_role() == "off", "stopped hosting")
	for p in ["testguest", "testbad", "testno"]:
		var f := _out.path_join("together_%s.txt" % p)
		await _wait_for(func() -> bool: return FileAccess.file_exists(f), 120.0)
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
	_check(NetSession.join_url("100.1.2.3", 7350) == "ws://100.1.2.3:7350" and NetSession.join_url("100.1.2.3:7400", 7350) == "ws://100.1.2.3:7400"
		and NetSession.join_url("abc-def.trycloudflare.com", 7350) == "wss://abc-def.trycloudflare.com"
		and NetSession.join_url(" https://abc.trycloudflare.com/ ", 7350) == "https://abc.trycloudflare.com"
		and NetSession.join_url("", 7350) == "", "typed addresses turn into the right connection address")
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
	# the host introduces itself; this copy confirms it's the right person before anything is shared
	_check(await _wait_for(func() -> bool: return _confirms.size() > 0, 30.0), "asked whether this is the right host")
	if _confirms.size() > 0:
		_check(String(_confirms[0]["side"]) == "guest" and String(_confirms[0]["name"]) == "TestHost",
			"the popup names the host (%s)" % _confirms[0]["name"])
	var panel: Node = _main.get_node("ControlPanel")
	_check((panel._net_dialogs as Dictionary).has(1), "a popup is open on the guest")
	_check(bool(NetSession.get_info()["waiting"]) and (NetSession.get_info()["peers"] as Array).is_empty(),
		"nothing is shared while waiting")
	NetSession.confirm(true)
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and (NetSession.get_info()["peers"] as Array).size() == 2, 30.0),
		"joined the host")
	_check(String(NetSession.get_info()["status"]).contains("TestHost"), "the status says whose session this is (%s)" % NetSession.get_info()["status"])
	_check(not (panel._net_dialogs as Dictionary).has(1), "the guest's popup closed by itself")
	_check(bool(NetSession.get_info()["suggest_medium"]), "suggests Medium graphics on High")
	_check(await _wait_for(func() -> bool: return absf(float(AppState.get_setting("house_lights")) - 0.37) < 0.001, 30.0),
		"the host's house lights arrived")
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting(AppState.presenter_key(4, "source"))) == "silhouette", 10.0),
		"a camera podium with nobody on it shows as a silhouette here")
	_check(String(AppState.get_setting(AppState.presenter_key(2, "source"))) == "peer"
		and String(AppState.get_setting(AppState.presenter_key(2, "peer"))) == "TestGuest", "a podium set to someone's avatar arrives as it is (mine, here)")
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
	# the host's podium picture and name tag arrive; the picture is a copy in this PC's user folder
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting(AppState.presenter_key(3, "picture"))).begins_with("user://podium_pictures/"), 20.0),
		"the host's podium picture arrived as a copy here (%s)" % AppState.get_setting(AppState.presenter_key(3, "picture")))
	_check(String(AppState.get_setting(AppState.presenter_key(3, "name"))) == "HostName", "the host's name tag arrived")
	var stage: Node = _main.get_node("RoomHost").get_current_room().find_child("Presenters", true, false)
	var p3: Presenter = stage.get_presenter(3) if stage else null
	_check(await _wait_for(func() -> bool: return p3 != null and p3._badge_mat.albedo_texture != null and p3._badge_mat.albedo_texture.get_width() == 48, 10.0),
		"and shows on podium 3 here")
	# the host stops sharing presenters: this PC's presenters are its own again
	_check(await _wait_for(func() -> bool: return not NetSession.group_shared("presenters"), 20.0), "heard that presenters aren't shared any more")
	# (this guest is a co-host by now, so nothing is locked for it anyway: check the groups themselves)
	_check(not NetSession.group_shared("presenters") and NetSession.group_shared("room"), "presenters are this PC's own while the room stays the host's")
	AppState.set_setting(AppState.presenter_key(3, "source"), "green")
	await _secs(0.5)
	_check(String(AppState.get_setting(AppState.presenter_key(3, "source"))) == "green", "this PC can set its own presenter source now")
	_check(await _wait_for(func() -> bool: return NetSession.group_shared("presenters"), 20.0), "heard that presenters are shared again")
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting(AppState.presenter_key(3, "source"))) != "green", 10.0), "and the host's presenter state came back")
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 120.0), "noticed the session ending")
	await _finish()


func _declined_guest() -> void:
	AppState.set_setting("together_address", "127.0.0.1:%d" % PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_name", "TestNo")
	await _start_main()
	NetSession.join()
	_check(await _wait_for(func() -> bool: return _confirms.size() > 0, 30.0), "asked whether this is the right host")
	NetSession.confirm(true)
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "the host's decline ended the connection")
	_check(String(NetSession.get_info()["status"]).contains("declined"), "it says the host declined (%s)" % NetSession.get_info()["status"])
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
	AppState.request_quit(1 if _fails > 0 else 0)
