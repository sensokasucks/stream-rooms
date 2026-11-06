extends Node
## Core's Live page "Stream Rooms" card, the game side (core/rooms_remote.gd): the summary it sends
## Core (build_state) has the room list, camera views, big screen line and sound levels, and each
## card button (run_command) does what the panel does: pause, focus view, clean feed, room, camera
## view, volume, presenters. An unknown action is refused.
##   <redot console exe> --path . _tests/test_rooms_remote.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("volume", 0.8)
	AppState.set_setting("camera_glide", 0.0)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var remote := ChatFeed.get_remote()
	_check(remote != null, "ChatFeed has the RoomsRemote child")
	var st := remote.build_state()
	_check(String(st.get("room", "")) == "lecture_hall_panel", "the state names the room")
	_check((st.get("rooms", []) as Array).size() >= 3, "and lists the rooms (%d)" % (st.get("rooms", []) as Array).size())
	_check((st.get("views", []) as Array).size() >= 1, "and the room's camera views (%d)" % (st.get("views", []) as Array).size())
	_check(String((st.get("screen", {}) as Dictionary).get("text", "")) != "", "and a big screen line")
	_check(is_equal_approx(float(st.get("volume", 0)), 0.8), "and the stream volume")
	_check((st.get("presenters", []) as Array).size() == 4, "the panel lecture hall has podiums, so presenters are listed")
	_check(JSON.stringify(st).length() < 8000, "the packet stays small (%d chars)" % JSON.stringify(st).length())

	AppState.set_source_mode("file")
	remote.run_command("pause", "on")
	_check(AppState.is_react_paused(), "pause on")
	remote.run_command("pause", "toggle")
	_check(not AppState.is_react_paused(), "pause toggled off")
	remote.run_command("focus", "on")
	_check(AppState.is_focus_view(), "focus view on")
	remote.run_command("focus", "on")
	_check(AppState.is_focus_view(), "focus view on twice stays on")
	remote.run_command("focus", "off")
	remote.run_command("clean", "toggle")
	_check(AppState.is_clean_feed(), "clean feed toggled on")
	remote.run_command("clean", "off")
	_check(not AppState.is_clean_feed(), "clean feed off")
	remote.run_command("volume", 0.3)
	_check(is_equal_approx(float(AppState.get_setting("volume")), 0.3), "volume 0.3")
	remote.run_command("presenter", "1:on")
	_check(bool(AppState.get_setting("presenter_1_on")), "presenter 1 on set")
	remote.run_command("presenter", "1:off")
	_check(not bool(AppState.get_setting("presenter_1_on")), "presenter 1 off")

	var rig: CameraRig = main.get_node("CameraRig")
	var views: Array = rig.get_views()
	var last: Dictionary = views[views.size() - 1]
	rig.global_transform = Transform3D.IDENTITY.translated(Vector3(0, 30, 0))
	var before := rig.global_position
	remote.run_command("view", String(last["id"]))
	await _secs(0.5)
	_check(rig.global_position.distance_to(before) > 1.0, "a camera view button moves the camera (%s)" % str(rig.global_position))
	_check(not remote.run_command("format_disk", "now"), "an unknown action is refused")

	# Setup > Stream Rooms pages: the panel's settings, described for Core
	var data := remote.refresh_schema()
	var schema: Array = data.get("schema", [])
	# a copy for looking at Core's pages with the real list (outside the project folder)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		var f := FileAccess.open(args[0].path_join("rooms_settings.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(data))
			f.close()
	_check(schema.size() >= 150, "the panel describes its settings for Core (%d)" % schema.size())
	var tabs := {}
	var no_tip: Array = []
	var by_key := {}
	for e: Dictionary in schema:
		tabs[e["tab"]] = true
		by_key[e["key"]] = e
		if String(e["tip"]) == "":
			no_tip.append(e["key"])
	_check(tabs.has("Room") and tabs.has("Audience") and tabs.has("Co-stream"), "grouped by panel tab (%s)" % ", ".join(PackedStringArray(tabs.keys())))
	_check(no_tip.is_empty(), "every one has its help text (%s)" % ", ".join(PackedStringArray(no_tip)))
	var vol: Dictionary = by_key.get("volume", {})
	_check(String(vol.get("type", "")) == "range" and is_equal_approx(float(vol.get("max", 0)), 1.0), "Volume is a 0..1 slider (%s)" % str(vol))
	var gq: Dictionary = by_key.get("graphics_quality", {})
	_check(String(gq.get("type", "")) == "choice" and (gq.get("options", []) as Array).size() >= 3, "Graphics quality lists its choices")
	_check(data["values"].has("volume") and data["defaults"].has("volume"), "values and defaults come along")
	var adv := 0
	for e: Dictionary in schema:
		if bool(e["adv"]):
			adv += 1
	_check(adv > 20 and adv < schema.size(), "Advanced ▸ settings are marked (%d)" % adv)
	_check(JSON.stringify(data).length() < 900000, "the packet fits the socket buffer (%d chars)" % JSON.stringify(data).length())
	_check(remote.set_from_core("volume", 0.55) and is_equal_approx(float(AppState.get_setting("volume")), 0.55), "Core sets a slider")
	_check(not by_key.has("together_password") and not by_key.has("together_address"), "the co-stream password and address stay on this PC")
	_check(not remote.set_from_core("together_password", "x"), "and Core can't set them")
	_check(not remote.set_from_core("panel_advanced", "x"), "Core can't set a setting the panel has no control for")
	var color_key := ""
	for e: Dictionary in schema:
		if String(e["type"]) == "color":
			color_key = String(e["key"])
			break
	if color_key != "":
		_check(remote.set_from_core(color_key, "#ff0000") and AppState.get_setting(color_key) == Color(1, 0, 0), "a colour comes over as #rrggbb (%s)" % color_key)
	_check(not remote.set_from_core("volume_typo", 1), "an unknown key is refused")

	remote.run_command("room", "theater")
	await _secs(4.0)
	_check(String(AppState.get_setting("room_id")) == "theater", "the room picker changes the room")
	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
