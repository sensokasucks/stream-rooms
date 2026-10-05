extends Node
## Side chat windows in front of the curtain, presenters moved forward, window headers,
## and the Lecture Hall's light-rays slider.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _chat(name: String, plat: String, text: String) -> void:
	EventBus.chat_message_received.emit({"name": name, "platform": plat, "user_id": name.to_lower(), "text": text,
		"color": "#ff8800", "timestamp": Time.get_unix_time_from_system()})
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_left", true)
	AppState.set_setting("chat_right", true)
	AppState.set_setting("chat_left_chat", "twitch")
	AppState.set_setting("chat_right_chat", "kick,youtube,other")
	AppState.set_setting("chat_left_header_on", true)
	AppState.set_setting("chat_right_header_on", true)
	AppState.set_setting("chat_left_header", "")
	AppState.set_setting("chat_right_header", "")
	AppState.set_setting("sun_rays", 1.0)
	for n in range(1, 5):
		AppState.set_setting(AppState.presenter_key(n, "on"), true)     # (turned back off at the end)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	AppState.set_curtain(false, "instant")
	var room = main.get_node("RoomHost").get_current_room()
	var screen: MeshInstance3D = room.find_screen()
	var cur = room.find_child("StageCurtain", false, false)
	var side: SideChats = room.find_child("SideChats", false, false)
	var left := side.get_chat_window("chat_left")
	var right := side.get_chat_window("chat_right")
	print("screen z=", screen.global_position.z, " curtain z=", cur.global_position.z, " left z=", left.global_position.z, " right z=", right.global_position.z)
	for s in room.get_presenter_setups():
		print(" presenter ", s["n"], " marker=", (s["marker"] as Node3D).global_position)
	print("headers: left='", left._header.text, "' visible=", left._header.visible, "  right='", right._header.text, "'")
	for n in 6:
		_chat("Tw%d" % n, "twitch", "twitch says hi %d" % n)
		_chat("Kk%d" % n, "kick", "kick says hi %d" % n)
	AppState.set_setting("chat_right_header", "Kick + YouTube")
	await _secs(0.3)
	print("custom header right='", right._header.text, "'")
	var panel = main.get_node("ControlPanel")
	panel.visible = false
	var cam: CameraRig = main.get_node("CameraRig")
	cam.global_position = Vector3(0, 3.2, 7.5)
	cam.look_at(Vector3(0, 4.5, -3.8), Vector3.UP)
	await _secs(1.5)
	await _shot(out + "/f1_front.png")
	cam.global_position = Vector3(-3.0, 6.0, 0.5)
	cam.look_at(Vector3(-6.0, 2.5, -3.2), Vector3.UP)
	await _secs(1.0)
	await _shot(out + "/f2_side.png")
	# light rays
	AppState.request_room("lecture_hall")
	await _secs(5.0)
	room = main.get_node("RoomHost").get_current_room()
	var shafts: MeshInstance3D = room.find_child("SunShafts", false, false)
	print("room controls=", room.get_controls().map(func(c): return c.get("key", c.get("heading", ""))))
	AppState.set_setting("sun_rays", 0.0)
	await _secs(0.1)
	print("rays 0%: visible=", shafts.visible)
	AppState.set_setting("sun_rays", 2.0)
	await _secs(0.1)
	print("rays 200%: visible=", shafts.visible, " intensity=", (shafts.material_override as ShaderMaterial).get_shader_parameter("intensity"))
	AppState.set_setting("sun_rays", 1.0)
	# leave the saved settings as the other tests expect them (presenters 2 + 3 on set)
	AppState.set_setting(AppState.presenter_key(1, "on"), false)
	AppState.set_setting(AppState.presenter_key(4, "on"), false)
	AppState.set_setting("chat_right_header", "")
	await _secs(0.3)
	get_tree().quit()
