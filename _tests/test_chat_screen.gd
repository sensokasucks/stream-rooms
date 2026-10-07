extends Node
## Panel room: no webcam monitor, chat screen under the main screen fed by chat messages.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _msg(who: String, text: String, emotes: Array = [], avatar: String = "", color: String = "") -> void:
	EventBus.chat_message_received.emit({"platform": "twitch", "user_id": who.to_lower(), "name": who, "color": color,
		"text": text, "emotes": emotes, "avatar": avatar, "timestamp": Time.get_unix_time_from_system(),
		"history": false, "system": false})
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_screen", true)
	AppState.set_setting("chat_screen_columns", 2.0)
	AppState.set_setting("chat_screen_text", 1.0)
	AppState.set_setting("chat_screen_bg", 0.75)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(4.0)
	var room = main.get_node("RoomHost").get_current_room()
	print("webcam marker=", room.get_webcam_marker(), " monitor=", room.find_child("Webcam_Monitor", true, false), " chat marker=", room.get_chat_screen_marker())
	var cs: ChatScreen = room.find_child("ChatScreen", true, false)
	print("chat screen=", cs != null, " global=", cs.global_position.snapped(Vector3.ONE * 0.01), " fwd(+Z)=", cs.global_basis.z.snapped(Vector3.ONE * 0.01))
	var tv: MeshInstance3D = room.find_screen()
	print("tv aabb=", (tv.global_transform * tv.get_aabb()))
	var E := "http://127.0.0.1:8899/"
	for i in 22:
		_msg("Viewer%d" % i, "message number %d with a bit of text so it wraps sometimes %s" % [i, "and a little more text here".repeat(i % 3)])
	_msg("PixelPirate", "hello from the pit! Kappa", [{"start": 20, "end": 24, "url": E + "kappa.png"}], E + "av_kick.png", "#FF4500")
	_msg("nightbot", "this is a bot and should be hidden")
	_msg("QuietFox", "!points")
	_msg("LunaWaves", "that transition was so smooth, how did you set up the podium lights?", [], E + "av_yt.jpg")
	_msg("BeeFan", "beeBobble beeBobble", [{"start": 0, "end": 8, "url": E + "anim.gif"}, {"start": 10, "end": 18, "url": E + "anim_opt.gif"}])
	_msg("gr8m8", "LUL LUL", [{"start": 0, "end": 2, "url": E + "lul.png"}, {"start": 4, "end": 6, "url": E + "lul.png"}])
	await _secs(2.5)
	print("messages kept=", cs.get_message_count(), " visible=", cs.get_visible_count())
	EventBus.camera_preset_requested.emit(12)
	await _secs(2.0)
	await _shot(out + "/chat_wide.png")
	EventBus.camera_preset_requested.emit(0)
	await _secs(2.0)
	await _shot(out + "/chat_pit.png")
	await _secs(0.17)
	await _shot(out + "/chat_pit_b.png")
	AppState.set_setting("chat_screen_columns", 1.0)
	AppState.set_setting("chat_screen_text", 1.6)
	AppState.set_setting("chat_screen_bg", 0.2)
	await _secs(1.0)
	print("1 col: visible=", cs.get_visible_count())
	await _shot(out + "/chat_pit_1col.png")
	AppState.set_setting("chat_screen", false)
	await _secs(0.5)
	print("toggle off visible=", cs.visible)
	await _shot(out + "/chat_off.png")
	AppState.set_setting("chat_screen_columns", 2.0)
	AppState.set_setting("chat_screen_text", 1.0)
	AppState.set_setting("chat_screen_bg", 0.75)
	print("DONE")
	AppState.request_quit()
