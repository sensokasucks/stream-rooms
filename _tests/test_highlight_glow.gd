extends Node
## Highlighted message glow: when Stream Core puts a chat line on its Highlighted message overlay
## it sends {"type": "highlight"} (core/highlights.py there). That chatter's seat gets a purple
## light while the line is on screen; it moves when the highlight changes, goes when Core clears
## it, and the "audience_highlight_glow" tick box turns it off.
##   <redot console exe> --path . _tests/test_highlight_glow.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _say(platform: String, id: String, who: String, text: String) -> void:
	ChatFeed._handle(JSON.stringify({"type": "chat", "data": {"platform": platform, "message": text,
		"timestamp": Time.get_unix_time_from_system(),
		"user": {"id": id, "username": who.to_lower(), "display_name": who}}}))


## Core's highlight packet with one chatter on screen ("" id = nobody).
func _highlight(platform: String, id: String, who: String) -> void:
	var cur: Variant = null
	if id != "":
		cur = {"id": 1, "platform": platform, "message": "look at this",
			"user": {"id": id, "username": who.to_lower(), "display_name": who}}
	ChatFeed._handle(JSON.stringify({"type": "highlight", "data": {"current": cur, "queue": [], "queue_len": 0}}))


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("audience_ignore", "")
	AppState.set_setting("audience_highlight_glow", true)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var room: Node = main.get_node("RoomHost").get_current_room()
	var view: AudienceView = null
	for n in room.find_children("*", "", true, false):
		if n is AudienceView:
			view = n
			break
	_check(view != null, "the room has an audience")
	if view == null:
		AppState.request_quit(1)
		return

	_say("kick", "1", "Amy", "hello everyone")
	_say("twitch", "9", "Bob", "hi there")
	await _secs(1.0)
	var amy := AudienceManager.find_slot_for_user("kick", "1")
	var bob := AudienceManager.find_slot_for_user("twitch", "9")
	_check(amy >= 0 and bob >= 0, "Amy and Bob have seats")

	_highlight("kick", "1", "Amy")
	await _secs(0.6)
	_check(view._hl_slot == amy and is_instance_valid(view._hl_light), "Amy's seat glows while she is highlighted")
	_highlight("twitch", "9", "Bob")
	await _secs(0.3)
	_check(view._hl_slot == bob and is_instance_valid(view._hl_light), "the glow moves to Bob")
	_highlight("", "", "")
	await _secs(0.3)
	_check(view._hl_slot == -1 and not is_instance_valid(view._hl_light), "Clear in Core takes the glow away")

	# by name only (no matching account id): still found
	_highlight("kick", "999", "Amy")
	await _secs(0.3)
	_check(view._hl_slot == amy, "a highlight found by name")
	AppState.set_setting("audience_highlight_glow", false)
	await _secs(0.3)
	_check(view._hl_slot == -1, "the tick box turns the glow off")
	AppState.set_setting("audience_highlight_glow", true)
	await _secs(0.3)
	_check(view._hl_slot == amy, "and back on")
	# someone not seated: nothing glows, nothing breaks
	_highlight("youtube", "UCnobody", "Nobody")
	await _secs(0.3)
	_check(view._hl_slot == -1, "a chatter without a seat makes nothing glow")

	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
