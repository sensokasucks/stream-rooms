extends Node
## Streaming together, "Viewers keep their streamer's looks" (together_streamer_looks): in the one
## shared audience, each chatter is drawn in the looks of the streamer whose chat they came from.
## The host's looks here are blue silhouettes with light bubbles, the guest's red with dark bubbles;
## a chatter from the guest's chat must be red (with a dark bubble) on both PCs, the host's blue.
## Unticking the option puts everyone back in the host's looks.
## No Stream Core: the looks are set straight into each copy's settings (as CoreLooks would), and the
## guest's chat line is emitted on its EventBus. The guest writes its results to a file; the host prints them.
##   <redot console exe> --path . _tests/test_streamer_looks.tscn -- C:/temp/sr_tests --mp-profile=test

const SESSION_PORT: int = 7397
const PASSWORD: String = "streamerlooks"
const HOST_COLOR: String = "2050ffff"   # blue
const GUEST_COLOR: String = "ff3020ff"  # red

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []


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


## The silhouette colour a chatter from streamer `index` gets on this PC.
func _color_for(index: int) -> String:
	return String(AudienceStyle.figure_for({"name": "someone", "platform": "twitch", "roles": "", "streamer": index})["color"])


## The seat of the first chatter called `who` (-1 if they aren't seated).
func _slot_of(who: String) -> int:
	for i in AudienceManager.get_capacity():
		if String(AudienceManager.get_seat_member(i).get("name", "")) == who:
			return i
	return -1


func _ready() -> void:
	NetSession.auto_confirm = true      # (no "let them in" popups in a test)
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
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
	AppState.set_setting("audience_silhouette", JSON.stringify({"shape": "classic", "paint": "fixed", "color": HOST_COLOR}))
	AppState.set_setting("audience_bubble_theme", "light")
	AppState.set_setting("audience_style_groups", "")
	AppState.set_setting("audience_saved_styles", "")
	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_shared_audience", true)
	AppState.set_setting("together_streamer_looks", false)     # (a change below, so it's heard)
	AppState.set_setting("together_streamer_looks", true)
	NetSession.host()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_looksguest3.cfg"))
	DirAccess.remove_absolute(_out.path_join("together_looksguest.txt"))
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "980,0", "res://_tests/test_streamer_looks.tscn", "--", _out, "--mp-profile=looksguest3", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the guest copy")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0), "the guest joined")

	_check(await _wait_for(func() -> bool: return AudienceStyle.streamer_looks.has(1), 30.0), "the guest's own looks arrived")
	_check(_color_for(1) == GUEST_COLOR, "the guest's viewers are red here (%s)" % _color_for(1))
	_check(_color_for(0) == HOST_COLOR, "the host's viewers stay blue (%s)" % _color_for(0))
	var dark: Dictionary = AudienceStyle.merge_bubble(AudienceStyle.BUBBLE_PRESETS["Dark"])
	_check(AudienceStyle.bubble_for({"name": "x", "streamer": 1}) == dark, "and get the guest's dark bubbles")
	_check(AudienceStyle.bubble_for({"name": "x", "streamer": 0}).is_empty(), "the host's viewers keep the main bubble")
	# a real chat line from the guest's chat is seated here as streamer 1
	_check(await _wait_for(func() -> bool: return _slot_of("RedViewer") >= 0, 30.0), "the guest's chatter is seated")
	var slot := _slot_of("RedViewer")
	if slot >= 0:
		var m := AudienceManager.get_seat_member(slot)
		_check(int(m.get("streamer", -1)) == 1 and String(AudienceStyle.figure_for(m)["color"]) == GUEST_COLOR,
			"and drawn in the guest's red")
	# a few of the host's own chatters next to the guest's, for a picture of the mix
	for i in 6:
		EventBus.chat_message_received.emit({"name": "BlueViewer%d" % i, "username": "blueviewer%d" % i, "platform": "twitch",
			"user_id": "blue%d" % i, "color": "", "text": "hi from the host's chat", "timestamp": Time.get_unix_time_from_system()})
	await _secs(2.0)
	var panel: Node = get_child(0).get_node_or_null("ControlPanel")
	if panel:
		panel.visible = false        # (the picture is of the room, not the panel)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("streamer_looks_mix.png"))

	await _secs(4.0)               # (the guest checks the same on its side)
	AppState.set_setting("together_streamer_looks", false)
	_check(AudienceStyle.streamer_looks.is_empty() and _color_for(1) == HOST_COLOR, "unticked: everyone in the host's blue again")
	await _secs(6.0)
	NetSession.leave()

	var f := _out.path_join("together_looksguest.txt")
	await _wait_for(func() -> bool: return FileAccess.file_exists(f), 40.0)
	var text := FileAccess.get_file_as_string(f)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		_check(line.begins_with("PASS "), "guest: " + line.substr(5))
	AppState.set_setting("audience_silhouette", "")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)


# ── Guest ────────────────────────────────────────────────────
func _guest() -> void:
	AppState.set_setting("audience_silhouette", JSON.stringify({"shape": "classic", "paint": "fixed", "color": GUEST_COLOR}))
	AppState.set_setting("audience_bubble_theme", "dark")
	AppState.set_setting("audience_style_groups", "")
	AppState.set_setting("audience_saved_styles", "")
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and AudienceManager.is_mirror(), 30.0),
		"joined, and shows the host's audience")
	_check(await _wait_for(func() -> bool: return AudienceStyle.streamer_looks.has(1), 30.0), "every streamer's looks arrived")
	_check(_color_for(1) == GUEST_COLOR, "this PC's viewers are red (%s)" % _color_for(1))
	_check(_color_for(0) == HOST_COLOR, "the host's viewers are the host's blue (%s)" % _color_for(0))
	# one line of this PC's chat goes to the host's audience and comes back seated as streamer 1
	for i in 5:
		EventBus.chat_message_received.emit({"name": "RedViewer" if i == 0 else "RedViewer%d" % i, "username": "redviewer%d" % i,
			"platform": "twitch", "user_id": "red%d" % i, "color": "", "text": "hello from the guest's chat",
			"timestamp": Time.get_unix_time_from_system()})
	_check(await _wait_for(func() -> bool: return _slot_of("RedViewer") >= 0, 30.0), "this PC's chatter is seated in the shared audience")
	var slot := _slot_of("RedViewer")
	if slot >= 0:
		var m := AudienceManager.get_seat_member(slot)
		_check(int(m.get("streamer", -1)) == 1 and String(AudienceStyle.figure_for(m)["color"]) == GUEST_COLOR,
			"and drawn in this PC's red here too")
	_check(await _wait_for(func() -> bool: return AudienceStyle.streamer_looks.is_empty(), 30.0), "the host unticked it: the table is gone")
	_check(_color_for(1) == HOST_COLOR, "and everyone shows in the host's blue")
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "noticed the session ending")
	var f := FileAccess.open(_out.path_join("together_looksguest.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
