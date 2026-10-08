extends Node
## Chatter pictures from Stream Core: Core sends its own saved copy (user.avatar_local, a path on
## Core's port) next to the platform's link. Seats and chat windows use Core's copy; guests get the
## platform's https link (Core's copy only exists on the host's PC); a name Core hides loses its
## picture; an older Core without avatar_local works as before.
##   <redot console exe> --path . _tests/test_core_pictures.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:3850/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("chat_screen", true)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("audience_avatars", true)
	AppState.set_setting("audience_hide_avatars", "")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)

	var feed: Node = ChatFeed
	_check(feed._core_file_url("/avatars/kick/5.png?v=1") == "http://127.0.0.1:3850/avatars/kick/5.png?v=1", "Core's path becomes an address on Core's port")
	_check(feed._core_file_url("") == "", "no path, no address")

	var web := "https://files.kick.com/images/user/5/profile_image/conversion/bob-fullsize.webp"
	var norm: Dictionary = feed._normalize({"platform": "kick", "message": "hello", "user": {"id": "5", "username": "bob",
		"display_name": "Bob", "profile_image_url": web, "avatar_local": "/avatars/kick/5.png?v=1"}}, false)
	_check(String(norm.get("avatar")) == "http://127.0.0.1:3850/avatars/kick/5.png?v=1", "the message uses Core's saved copy")
	_check(String(norm.get("avatar_web")) == web, "the platform's link is kept as well")
	var old: Dictionary = feed._normalize({"platform": "kick", "message": "hi", "user": {"id": "6", "username": "ann",
		"display_name": "Ann", "profile_image_url": web.replace("bob", "ann"), "avatar_local": null}}, false)
	_check(String(old.get("avatar")) == web.replace("bob", "ann"), "an older Core (no saved copy) still gives the platform's link")
	var none: Dictionary = feed._normalize({"platform": "youtube", "message": "yo", "user": {"id": "7", "username": "cat", "profile_image_url": null}}, false)
	_check(String(none.get("avatar")) == "" and String(none.get("avatar_web")) == "", "no picture at all: both empty")

	EventBus.chat_message_received.emit(norm)
	EventBus.chat_message_received.emit(old)
	await _secs(1.0)
	var bob := AudienceManager.find_slot_for_user("kick", "5")
	_check(bob >= 0, "Bob got a seat")
	_check(String(AudienceManager.get_seat_member(bob).get("avatar")) == String(norm["avatar"]), "Bob's seat shows Core's copy")
	_check(String(AudienceManager.wire_member(bob).get("avatar")) == web, "guests get the platform's https link, not Core's copy")

	# Core's copy is saved a moment later: a user_update with avatar_local
	var updates: Array = []
	var grab := func(info: Dictionary) -> void: updates.append(info)
	EventBus.chat_user_updated.connect(grab)
	feed._handle(JSON.stringify({"type": "user_update", "data": {"platform": "kick", "id": "6",
		"profile_image_url": web.replace("bob", "ann"), "avatar_local": "/avatars/kick/6.png?v=2"}}))
	var ann := AudienceManager.find_slot_for_user("kick", "6")
	_check(updates.size() == 1 and String(updates[0].get("avatar")) == "http://127.0.0.1:3850/avatars/kick/6.png?v=2", "a late saved copy is passed on")
	_check(ann >= 0 and String(AudienceManager.get_seat_member(ann).get("avatar")).ends_with("/avatars/kick/6.png?v=2"), "Ann's seat switches to Core's copy")
	_check(ann >= 0 and String(AudienceManager.wire_member(ann).get("avatar")) == web.replace("bob", "ann"), "Ann's guests still get the https link")

	# a name put on Core's hide list
	feed._handle(JSON.stringify({"type": "user_update", "data": {"platform": "kick", "id": "5", "hidden": true,
		"profile_image_url": "", "avatar_local": ""}}))
	_check(updates.size() == 2 and bool(updates[1].get("hidden")), "Core's hide notice is passed on")
	_check(String(AudienceManager.get_seat_member(bob).get("avatar")) == "" and String(AudienceManager.wire_member(bob).get("avatar")) == "",
		"a hidden chatter has no picture here or on guests' PCs")
	# a user_update with nothing useful is ignored
	feed._handle(JSON.stringify({"type": "user_update", "data": {"platform": "kick", "id": "6", "profile_image_url": null}}))
	_check(updates.size() == 2, "an empty user_update changes nothing")
	EventBus.chat_user_updated.disconnect(grab)

	await _secs(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/core_pictures.png")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
