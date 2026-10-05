extends Node
## Chat windows by platform, platform colours, seating sections + plan, the seating chart,
## and the control panel's scrolling tabs.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _b2g(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)
func _chat(name: String, plat: String, text: String = "hello") -> void:
	EventBus.chat_message_received.emit({"name": name, "platform": plat, "user_id": name.to_lower(), "text": text,
		"color": "#ff8800", "timestamp": Time.get_unix_time_from_system()})
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("seating_by_platform", false)
	AppState.set_setting("seating_plan", "")
	AppState.set_setting("audience_color_by", "chat")
	AppState.set_setting("chat_left", true)
	AppState.set_setting("chat_right", true)
	AppState.set_setting("chat_left_chat", "twitch")
	AppState.set_setting("chat_right_chat", "kick,youtube,other")
	AppState.set_setting("chat_left_replies", "fallback")
	AppState.set_setting("chat_right_replies", "fallback")
	AppState.set_setting("reply_screen", true)
	AppState.set_setting("chat_screen", true)
	AppState.set_setting("audience_fill_main", false)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall")
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var room = main.get_node("RoomHost").get_current_room()
	var side: SideChats = room.find_child("SideChats", false, false)
	var left: ChatScreen = side.get_chat_window("chat_left")
	var right: ChatScreen = side.get_chat_window("chat_right")
	print("side windows: left=", left != null, " right=", right != null, " reply screen in room=", AppState.room_has_reply_screen(),
		" left shows replies (fallback, no reply screen)=", left.is_showing_replies())
	# sections
	var secs := AudienceManager.get_sections()
	var names := secs.map(func(x: Dictionary) -> String: return "%s:%d" % [x["id"], x["count"]])
	print("sections (", secs.size(), "): ", ", ".join(PackedStringArray(names)))
	# chat split
	_chat("TwitchTom", "twitch", "hi from twitch")
	_chat("KickKate", "kick", "hi from kick")
	_chat("TubeTina", "youtube", "hi from youtube")
	EventBus.core_reply_received.emit({"message": "@TwitchTom you have 50 points", "platform": "twitch", "reply_to_user": "TwitchTom",
		"source": "command", "timestamp": Time.get_unix_time_from_system(), "history": false})
	EventBus.core_reply_received.emit({"message": "@KickKate you have 20 points", "platform": "kick", "reply_to_user": "KickKate",
		"source": "command", "timestamp": Time.get_unix_time_from_system(), "history": false})
	await _secs(0.3)
	var lc: Array = left._cards.map(func(c: Dictionary) -> String: return String(c["name"]))
	var rc: Array = right._cards.map(func(c: Dictionary) -> String: return String(c["name"]))
	print("left cards=", lc, "  right cards=", rc)
	# platform colours
	AppState.set_setting("audience_color_by", "platform")
	await _secs(0.2)
	var aud: AudienceView = room.find_child("Audience", false, false)
	var ts := AudienceManager.find_slot_for_user("twitch", "twitchtom")
	print("color by platform: twitch member colour=", AudienceManager.get_seat_member(ts)["color"], " want ", AppState.get_setting("platform_color_twitch"),
		" seat colour=", aud._seats[ts]["color"], " (x1.25 while speaking)")
	# seating plan: twitch apart
	AudienceManager.clear()
	AudienceManager.apply_preset("twitch_apart")
	await _secs(0.2)
	var cap := AudienceManager.get_platform_capacity()
	print("twitch_apart capacity=", cap)
	for n in 30:
		_chat("T%02d" % n, "twitch")
		_chat("K%02d" % n, "kick")
	await _secs(0.3)
	var bad := 0
	var where: Dictionary = {}
	for i in aud.get_seat_count():
		if aud.is_seat_taken(i):
			var g := AudienceManager._group_of(AudienceManager._members[AudienceManager._slots[i]])
			var sec := AudienceManager.get_section(i)
			where[g + "@" + sec] = int(where.get(g + "@" + sec, 0)) + 1
			if not AudienceManager.slot_allows(i, g):
				bad += 1
	print("seated by section: ", where, " misplaced=", bad)
	# a swap across the divide is refused
	var t0 := AudienceManager.find_slot_for_user("twitch", "t00")
	var k0 := AudienceManager.find_slot_for_user("kick", "k00")
	print("swap twitch<->kick refused=", not AudienceManager.swap_seats(t0, k0))
	# chart + panel
	var panel = main.get_node("ControlPanel")
	panel._tabs.current_tab = 6
	panel._chart.selected = "Q1"
	panel._on_section_picked("Q1")
	panel._chart.queue_redraw()
	var cam: CameraRig = main.get_node("CameraRig")
	cam.global_position = _b2g(Vector3(0, -8, 4.0))
	cam.look_at(_b2g(Vector3(0, 4, 4.0)), Vector3.UP)
	await _secs(1.5)
	await _shot(out + "/p1_seating_tab.png")
	print("tabs=", panel._tabs.get_tab_count(), " tab height=", panel._tabs.size.y, " viewport=", get_viewport().get_visible_rect().size)
	panel._tabs.current_tab = 4
	await _secs(0.8)
	await _shot(out + "/p2_chat_tab.png")
	panel.visible = false
	for n in 8:
		_chat("Tw%d" % n, "twitch", "twitch message %d PogChamp" % n)
		_chat("Kk%d" % n, "kick", "kick message %d" % n)
	await _secs(1.5)
	await _shot(out + "/p3_room_windows.png")
	AudienceManager.apply_preset("anyone")
	get_tree().quit()
