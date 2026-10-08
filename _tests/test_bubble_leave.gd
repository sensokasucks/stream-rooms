extends Node
## A chatter leaves their crowd seat while their speech bubble is still fading out. The fade used
## to be a tween on the audience view whose last step freed the bubble's sprite and viewport, but
## leaving frees the seat (and both nodes with it) first, so the step ran on freed nodes: "Lambda
## capture at index 0 was freed", then a crash in exported builds. The fade belongs to the bubble
## now and goes with it.
##   <redot console exe> --path . _tests/test_bubble_leave.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _log_count(what: String) -> int:
	var path := ProjectSettings.globalize_path(String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))
	return FileAccess.get_file_as_string(path).count(what)


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var room: Room = main.get_node("RoomHost").get_current_room()
	var view: AudienceView = room.find_child("Audience", true, false)
	_check(view != null, "the lecture hall has an audience")
	if view == null:
		AppState.request_quit(1)
		return
	var before := _log_count("Lambda capture") + _log_count("SCRIPT ERROR")

	for round_i in 3:
		var who := "Leaver%d" % round_i
		EventBus.chat_message_received.emit({"platform": "twitch", "user_id": who.to_lower(), "name": who, "color": "",
			"text": "bye all", "emotes": [], "timestamp": Time.get_unix_time_from_system(), "tint": "",
			"history": false, "system": false, "is_mod": false, "is_vip": false, "is_subscriber": false})
		await _secs(0.8)
		var slot := AudienceManager.find_slot_by_name(who)
		if slot >= 0 and bool(view._seats[slot]["pending"]):
			view._show_bubble(slot)         # (a seat the camera can't see waits to draw its bubble)
		_check(slot >= 0 and view._seats[slot]["bubble_sprite"] != null, "%s sits down with a bubble" % who)
		if slot < 0:
			continue
		var spr: Variant = view._seats[slot]["bubble_sprite"]
		view._end_bubble(slot, true)        # the bubble starts fading ...
		await get_tree().process_frame
		view._drop_rich(slot)               # ... and the seat goes before the fade is over
		await _secs(0.6)
		_check(not is_instance_valid(spr), "%s's bubble is gone" % who)

	await _secs(0.5)
	var errors := _log_count("Lambda capture") + _log_count("SCRIPT ERROR") - before
	_check(errors == 0, "no freed-node errors after the seats went (%d)" % errors)
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
