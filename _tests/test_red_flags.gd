extends Node
## Red flags from Stream Core: when Core red-flags a chatter it sends chat_user_hidden once (and no
## more of their chat). Their seat goes, their lines leave the chat window, and a name flagged on
## every platform ("platform": "") goes on all of them. Other chatters stay.
##   <redot console exe> --path . _tests/test_red_flags.tscn -- C:/temp/sr_tests --mp-profile=test

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


func _lines(cs: ChatScreen, who: String) -> int:
	var n := 0
	for c: Dictionary in cs._cards:
		if String(c.get("name", "")) == who:
			n += 1
	return n


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("chat_screen", true)
	AppState.set_setting("chat_screen_hide_commands", true)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("audience_ignore", "")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var room: Node = main.get_node("RoomHost").get_current_room()
	var cs: ChatScreen = room.find_child("ChatScreen", true, false)
	_check(cs != null, "the room has a chat window")
	if cs == null:
		AppState.request_quit(1)
		return

	_say("kick", "1", "Amy", "hello everyone")
	_say("kick", "42", "Spammer", "nice stream")
	_say("kick", "42", "Spammer", "my second line")
	_say("twitch", "9", "TrollFace", "hi from twitch")
	_say("youtube", "UCx", "TrollFace", "hi from youtube")
	await _secs(1.0)
	_check(AudienceManager.find_slot_for_user("kick", "42") >= 0, "Spammer got a seat")
	_check(_lines(cs, "Spammer") == 2, "Spammer's two lines are on the chat window")

	var hidden: Array = []
	var grab := func(info: Dictionary) -> void: hidden.append(info)
	EventBus.chat_user_hidden.connect(grab)
	ChatFeed._handle(JSON.stringify({"type": "chat_user_hidden", "data": {"platform": "kick", "id": "42",
		"username": "spammer", "display_name": "Spammer"}}))
	await _secs(0.5)
	_check(hidden.size() == 1 and String(hidden[0].get("user_id")) == "42", "Core's notice is passed on")
	_check(AudienceManager.find_slot_for_user("kick", "42") < 0, "Spammer left their seat")
	_check(_lines(cs, "Spammer") == 0, "Spammer's lines left the chat window")
	_check(AudienceManager.find_slot_for_user("kick", "1") >= 0 and _lines(cs, "Amy") == 1, "Amy is still there")

	# flagged by hand on every platform: by name, no account id
	ChatFeed._handle(JSON.stringify({"type": "chat_user_hidden", "data": {"platform": "", "id": "",
		"username": "trollface", "display_name": "trollface"}}))
	await _secs(0.5)
	_check(AudienceManager.find_slot_for_user("twitch", "9") < 0 and AudienceManager.find_slot_for_user("youtube", "UCx") < 0,
		"a name flagged everywhere leaves every platform's seat")
	_check(_lines(cs, "TrollFace") == 0, "and every platform's lines")
	# a different platform with the same id is someone else
	_say("twitch", "42", "Other", "same number, other platform")
	ChatFeed._handle(JSON.stringify({"type": "chat_user_hidden", "data": {"platform": "kick", "id": "42",
		"username": "spammer", "display_name": "Spammer"}}))
	await _secs(0.5)
	_check(AudienceManager.find_slot_for_user("twitch", "42") >= 0, "Twitch user 42 is not Kick user 42")
	EventBus.chat_user_hidden.disconnect(grab)

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/red_flags.png")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
