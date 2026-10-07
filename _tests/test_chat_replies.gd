extends Node
## Chat replies: a message sent with the platform's reply button (Stream Core sends reply_to) shows
## "replying to Name" on the chat window under the screen and in the speaker's bubble, and a plain
## message doesn't. Also: the reply marker survives the shared-audience mirror copy.
##   <redot console exe> --path . _tests/test_chat_replies.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _spoken: Dictionary = {}       # slot -> last parts


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	EventBus.audience_spoke.connect(func(slot: int, parts: Array) -> void: _spoken[slot] = parts)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("chat_screen", true)
	AppState.set_setting("audience_enabled", true)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var room: Room = main.get_node("RoomHost").get_current_room()
	var cs: ChatScreen = room.find_child("ChatScreen", true, false)
	_check(cs != null, "the lecture hall has a chat window under the screen")

	# what ChatFeed makes of Stream Core's payload
	var feed: Node = ChatFeed
	var norm: Dictionary = feed._normalize({"platform": "kick", "message": "local is the future", "message_id": "m2",
		"user": {"id": "5", "username": "bob", "display_name": "Bob"},
		"reply_to": {"user": "Sensoka_FlaVR", "message": "cloud gaming is a scam", "message_id": "m1"}}, false)
	_check(norm.get("reply_to") == "Sensoka_FlaVR" and norm.get("reply_quote") == "cloud gaming is a scam", "the feed keeps who a reply answers and a quote")
	var plain: Dictionary = feed._normalize({"platform": "kick", "message": "hi", "user": {"id": "6", "username": "ann"}}, false)
	_check(plain.get("reply_to") == "" and plain.get("reply_quote") == "", "a plain message has no reply fields")

	EventBus.chat_message_received.emit(norm)
	EventBus.chat_message_received.emit(plain)
	await _secs(1.5)
	var texts: Array[String] = []
	for c in cs._cards:
		texts.append((c["rtl"] as RichTextLabel).get_parsed_text())
	_check(texts.size() == 2, "both messages are on the chat window (%d)" % texts.size())
	_check(texts.size() == 2 and texts[0].contains("replying to Sensoka_FlaVR") and texts[0].contains("cloud gaming is a scam") and texts[0].contains("local is the future"),
		"the reply card says who it answers, quotes them, then the message")
	_check(texts.size() == 2 and not texts[1].contains("replying"), "the plain card has no reply line")

	var bob := AudienceManager.find_slot_by_name("Bob")
	_check(bob >= 0 and _spoken.has(bob), "Bob got a seat and spoke")
	if bob >= 0 and _spoken.has(bob):
		var parts: Array = _spoken[bob]
		_check(parts[0] is Dictionary and String(parts[0].get("reply_to", "")) == "Sensoka_FlaVR", "the bubble's parts start with who it answers")
		var view: AudienceView = room.find_child("Audience", true, false)
		view._show_bubble(bob)        # (drawn whether or not the camera happens to see the seat)
		var bubble: SpeechBubble = view._seats[bob]["bubble"]
		_check(bubble != null and bubble._rtl.get_parsed_text().contains("replying to Sensoka_FlaVR"), "the bubble shows the replying-to line")
	var ann := AudienceManager.find_slot_by_name("ann")
	_check(ann >= 0 and _spoken.has(ann) and not (_spoken[ann][0] is Dictionary), "a plain message's parts start with its text")

	# the mirror copy (shared audience) keeps the marker and drops anything else odd
	_spoken.erase(bob)
	AudienceManager._mirror = true
	AudienceManager.mirror_speak(AudienceManager._capacity_room, bob, [{"reply_to": "Sen", "quote": "q"}, "text", {"url": "http://x/y.png", "name": "bad"}, {"url": "https://x/y.png", "name": "ok"}])
	AudienceManager._mirror = false
	var mirrored: Array = _spoken.get(bob, [])
	_check(mirrored.size() == 3 and String(mirrored[0].get("reply_to", "")) == "Sen" and mirrored[1] == "text" and String(mirrored[2].get("name", "")) == "ok",
		"the mirror copy keeps the reply marker and https emotes only (%s)" % str(mirrored))

	EventBus.camera_preset_requested.emit(12)
	await _secs(1.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/chat_replies.png")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
