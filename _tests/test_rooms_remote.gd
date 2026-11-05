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

	remote.run_command("room", "theater")
	await _secs(4.0)
	_check(String(AppState.get_setting("room_id")) == "theater", "the room picker changes the room")
	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
