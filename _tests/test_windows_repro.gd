extends Node
## The user's chat window settings in the panel room: every window shows, replies go where asked.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _chat(name: String, plat: String, text: String) -> void:
	EventBus.chat_message_received.emit({"name": name, "platform": plat, "user_id": name.to_lower(), "text": text,
		"color": "#ff8800", "timestamp": Time.get_unix_time_from_system()})
func _state(w: ChatScreen) -> String:
	return "%s vis=%s intree=%s quad=%s cards=%d plats=%s replies=%s hdr=%s" % [w.get_window_key(), w.visible, w.is_visible_in_tree(),
		w._quad.visible, w._cards.size(), w._platforms, w._showing_replies, w._header.text if w._header.visible else "-"]
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	var s := {"chat_enabled": false, "chat_screen": true, "chat_screen_text": 1.6, "chat_screen_columns": 1.0,
		"chat_screen_chat": "youtube,other", "chat_screen_replies": "on", "reply_screen": true, "reply_screen_text": 1.65,
		"reply_screen_hold_s": 300.0, "reply_screen_chat": "other", "reply_screen_replies": "on",
		"chat_left_chat": "twitch", "chat_left_replies": "off", "chat_right_chat": "kick,youtube", "chat_right_replies": "off",
		"reply_screen_header_on": true, "reply_screen_header": "ww", "chat_screen_header_on": false,
		"chat_screen_replies_for": "all", "reply_screen_replies_for": "all"}
	for k in s:
		AppState.set_setting(k, s[k])
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	AppState.set_curtain(false, "instant")
	var room = main.get_node("RoomHost").get_current_room()
	var chat: ChatScreen = room.find_child("ChatScreen", true, false)
	var rep: ChatScreen = room.find_child("ReplyScreen", true, false)
	var side: SideChats = room.find_child("SideChats", false, false)
	var ws: Array = [chat, rep, side.get_chat_window("chat_left"), side.get_chat_window("chat_right")]
	for w in ws: print("start ", _state(w))
	_chat("TubeTina", "youtube", "hi from youtube")
	_chat("Oscar", "other", "hi from other")
	_chat("TwitchTom", "twitch", "hi from twitch")
	_chat("KickKate", "kick", "hi from kick")
	for p in ["twitch", "kick", "youtube"]:
		EventBus.core_reply_received.emit({"message": "@X you have points (%s)" % p, "platform": p, "reply_to_user": "X",
			"source": "command", "timestamp": Time.get_unix_time_from_system(), "history": false})
	await _secs(0.5)
	for w in ws: print("after ", _state(w), " names=", w._cards.map(func(c): return c["name"]))
	# a replies-only window that gets chat ticked must show up (it was hidden while empty)
	rep.clear()
	AppState.set_setting("reply_screen_chat", "")
	await _secs(0.3)
	print("replies-only + empty: quad=", rep._quad.visible)
	AppState.set_setting("reply_screen_chat", "other")
	await _secs(0.3)
	print("chat ticked again: quad=", rep._quad.visible, " (want true)")
	# only this window's platforms
	AppState.set_setting("chat_screen_replies_for", "chat")
	await _secs(0.3)
	print("chat_screen replies_for=chat names=", chat._cards.map(func(c): return c["name"] + ":" + String(c.get("platform", ""))))
	AppState.set_setting("chat_screen_replies_for", "all")
	# seating chart floors
	var panel = main.get_node("ControlPanel")
	panel._tabs.current_tab = 6
	await _secs(0.5)
	print("chart has top floor=", panel._chart.has_top_floor())
	await _shot(out + "/w2_bottom_floor.png")
	panel._chart.show_floor(SeatingChart.TOP)
	await _secs(0.5)
	await _shot(out + "/w3_top_floor.png")
	panel._chart.show_floor(SeatingChart.BOTTOM)
	main.get_node("ControlPanel").visible = false
	var cam: CameraRig = main.get_node("CameraRig")
	cam.global_position = Vector3(0, 4.0, 9.0)
	cam.look_at(Vector3(0, 5.5, -3.8), Vector3.UP)
	await _secs(1.5)
	await _shot(out + "/w1.png")
	for k in s:        # leave the saved settings as the other tests expect them
		AppState.set_setting(k, AppState.DEFAULTS[k])
	AppState.set_setting("chat_screen_replies_for", AppState.DEFAULTS["chat_screen_replies_for"])
	await _secs(0.3)
	print("DONE")
	AppState.request_quit()
