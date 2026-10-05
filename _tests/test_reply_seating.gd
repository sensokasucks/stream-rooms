extends Node
## Lecture hall panel: reply screen above the main screen (Stream Core's command replies)
## and the three audience seating modes.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _chat(who: String) -> void:
	EventBus.chat_message_received.emit({"platform": "twitch", "user_id": who.to_lower(), "name": who, "color": "",
		"text": "hi", "emotes": [], "avatar": "", "timestamp": Time.get_unix_time_from_system(),
		"history": false, "system": false})
func _reply(text: String, who: String = "", history: bool = false, age: float = 0.0) -> void:
	EventBus.core_reply_received.emit({"message": text, "platform": "kick", "reply_to_user": who, "source": "command",
		"timestamp": Time.get_unix_time_from_system() - age, "history": history})
func _rows(names: Array) -> Array:
	var out := []
	for n in names:
		out.append(AudienceManager.get_seat_row(AudienceManager.find_slot_by_name(n)))
	return out
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_screen", true)
	AppState.set_setting("reply_screen", true)
	AppState.set_setting("reply_screen_hold_s", 900.0)   # software rendering runs far slower than the wall clock
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(4.0)
	var room = main.get_node("RoomHost").get_current_room()
	var rs: ChatScreen = room.find_child("ReplyScreen", true, false)
	print("reply marker=", room.get_reply_screen_marker() != null, " reply screen=", rs != null)
	print("reply pos=", rs.global_position.snapped(Vector3.ONE * 0.01), " fwd=", rs.global_basis.z.snapped(Vector3.ONE * 0.01))
	var tv: MeshInstance3D = room.find_screen()
	print("tv aabb=", (tv.global_transform * tv.get_aabb()))
	# replies
	_reply("old one from before we connected", "bob", true, 600.0)
	_reply("recent backlog line", "bob", true, 5.0)
	_reply("@QuietFox you have 1,240 points", "QuietFox")
	_reply("Commands: !points, !tomato, !credits, !help", "LunaWaves")
	_reply("Nobody is on the podium right now.")
	await _secs(1.0)
	print("replies kept=", rs.get_message_count(), " visible=", rs.get_visible_count())
	for i in 3:
		_chat("Viewer%d" % i)
	EventBus.camera_preset_requested.emit(12)
	await _secs(2.5)
	await _shot(out + "/reply_wide.png")
	EventBus.camera_preset_requested.emit(0)
	await _secs(2.5)
	await _shot(out + "/reply_pit.png")
	print("pit: visible=", rs.visible, " quad=", rs.get_child(rs.get_child_count() - 1).visible, " kept=", rs.get_message_count(), " vis=", rs.get_visible_count(), " cam=", get_viewport().get_camera_3d().global_position.snapped(Vector3.ONE * 0.01))
	AppState.set_setting("reply_screen_hold_s", 5.0)    # (the room slider snaps to 5 s steps)
	await get_tree().create_timer(2.5).timeout
	print("after 5 s hold: kept=", rs.get_message_count())
	AppState.set_setting("reply_screen_hold_s", 45.0)
	# seating
	var cap := AudienceManager.get_capacity()
	var rows := {}
	for s in cap:
		rows[AudienceManager.get_seat_row(s)] = true
	print("seats=", cap, " rows=", rows.keys().size())
	for mode in ["front", "front_random", "random"]:
		AudienceManager.clear()
		AppState.set_setting("audience_seating", mode)
		var names := []
		for i in 20:
			names.append("%s_%d" % [mode, i])
			_chat(names[-1])
		var r := _rows(names)
		print(mode, " rows=", r)
		if mode == "front":
			var xs := []
			for n in names.slice(0, 6):
				xs.append(snappedf(main.get_node("RoomHost").get_current_room().find_child("Audience", true, false).get_seat_head(AudienceManager.find_slot_by_name(n)).x, 0.1))
			print("front first 6 seat x=", xs)
	AudienceManager.clear()
	AppState.set_setting("audience_seating", "front_random")
	for i in 30:
		_chat("fill_%d" % i)
	EventBus.camera_preset_requested.emit(12)
	await _secs(2.5)
	await _shot(out + "/seating_front_random.png")
	AppState.set_setting("audience_seating", "random")
	AudienceManager.clear()
	get_tree().quit()
