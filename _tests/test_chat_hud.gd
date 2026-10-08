extends Node
## The chat box on the picture (ChatHud, Chat tab > Chat box on the picture): Always / Never /
## Auto (only while no chat window in the room shows chat), its platforms, corner, replies and
## boards (the corner boards step aside while it shows them). Saves screenshots.
##   <redot console exe> --path . _tests/test_chat_hud.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _chat(plat: String, n: int, text: String, extra: Dictionary = {}) -> void:
	var m := {"platform": plat, "user_id": "%s%d" % [plat, n], "name": "%sFan%d" % [plat.capitalize(), n],
		"username": "%sfan%d" % [plat, n], "color": "", "text": text, "emotes": [], "avatar": "",
		"timestamp": Time.get_unix_time_from_system(), "history": false, "system": false}
	m.merge(extra, true)
	EventBus.chat_message_received.emit(m)


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_left", true)
	AppState.set_setting("chat_right", true)
	AppState.set_setting("chat_hud", "on")
	AppState.set_setting("chat_hud_chat", "kick,twitch,youtube,other")
	AppState.set_setting("chat_hud_replies", "off")
	AppState.set_setting("chat_hud_corner", "bottom_left")
	AppState.set_setting("board_hud", "auto")
	var main = load("res://core/main.tscn").instantiate()
	main.get_node("ControlPanel").visible = false
	add_child(main)
	await _secs(0.5)
	AppState.request_room("theater")
	await _secs(4.0)
	var hud = main.get_node("ChatHud")
	var win: ChatScreen = hud.get_chat_window()
	for i in 6:
		_chat(["twitch", "kick", "youtube"][i % 3], i, "hello from the chat box test number %d" % i)
	await _secs(1.0)
	_check(win.get_message_count() == 6, "the box takes every platform's chat (%d)" % win.get_message_count())
	_check(hud.is_box_visible(), "Always: the box is on the picture")
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var r: TextureRect = hud._rect
	_check(r.position.x < vs.x * 0.5 and r.position.y > vs.y * 0.3, "bottom left corner (%s)" % r.position)
	await _shot(out + "/chat_hud_on.png")

	AppState.set_setting("chat_hud", "off")
	await _secs(0.7)
	_check(not hud.is_box_visible(), "Never: no box")

	AppState.set_setting("chat_hud", "auto")
	await _secs(0.7)
	_check(hud.room_shows_chat(), "the side chat windows show chat in this room")
	_check(not hud.is_box_visible(), "Auto: no box while a window in the room shows chat")
	AppState.set_setting("chat_left", false)
	AppState.set_setting("chat_right", false)
	AppState.set_setting("chat_screen", false)
	await _secs(0.7)
	_check(not hud.room_shows_chat(), "with the windows off, no window shows chat")
	_check(hud.is_box_visible(), "Auto: the box comes up when no window shows chat")

	# platforms, and a YouTube reply to a Super Chat
	AppState.set_setting("chat_hud_chat", "youtube")
	await _secs(0.3)
	var before := win.get_message_count()
	_check(before == 2, "only YouTube's messages stay when it shows YouTube (%d)" % before)
	_chat("twitch", 9, "a twitch line the box shouldn't take")
	_chat("youtube", 7, "She'll love the Pinata people", {"reply_to": "@postalnate6631", "reply_quote": "[$5.00] Mario sunshine now lol"})
	await _secs(0.5)
	_check(win.get_message_count() == before + 1, "it takes the YouTube reply, not the Twitch line")

	AppState.set_setting("chat_hud_corner", "top_right")
	await _secs(0.7)
	_check(r.position.x > vs.x * 0.5 and r.position.y < vs.y * 0.3, "top right corner (%s)" % r.position)
	AppState.set_setting("chat_hud_corner", "bottom_right")

	# boards: with replies on, the box shows them and the corner boards step aside
	AppState.set_setting("chat_hud_replies", "on")
	var boards = main.get_node("BoardHud")
	EventBus.board_changed.emit({"id": "hype", "kind": "meter", "title": "🔥 Hype", "state": "open",
		"lines": [{"label": "Level 1", "pct": 0.4, "note": "7 chatting", "value": 7}], "footer": "Level 2 at 10 people"})
	await _secs(1.0)
	_check(not boards.visible, "the corner boards step aside while the chat box shows them")
	await _shot(out + "/chat_hud_boards.png")
	AppState.set_setting("chat_hud_replies", "off")
	await _secs(0.8)
	_check(boards.visible, "the corner boards come back when the box doesn't show them")

	AppState.set_setting("chat_hud", "off")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
