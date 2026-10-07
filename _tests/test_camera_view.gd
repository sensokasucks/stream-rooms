extends Node
## Taller reply screen (lecture hall), camera FOV setting, and seeing into the room from outside.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("camera_fov", 65.0)
	AppState.set_setting("camera_see_through", true)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(4.0)
	var room = main.get_node("RoomHost").get_current_room()
	var cam: CameraRig = main.get_node("CameraRig")
	var screens = get_tree().get_nodes_in_group("reply_screen")
	var rs = screens[0]
	print("reply size=", rs._size, " local y=", rs.position.y)
	for i in 4:
		EventBus.core_reply_received.emit({"message": "Commands: !boot, !confetti, !help, !highfive, !phone, !points, !rose, !sign, !sleep, !snack, !tomato, !wiggle (%d)" % i,
			"platform": "kick", "reply_to_user": "Sensoka_FlaVR", "source": "command", "timestamp": Time.get_unix_time_from_system(), "history": false})
	await _secs(1.0)
	await _shot(out + "/cam_default.png")
	AppState.set_setting("camera_fov", 95.0)
	await _secs(0.5)
	print("fov=", cam.fov)
	await _shot(out + "/cam_fov95.png")
	AppState.set_setting("camera_fov", 65.0)
	# back the camera out through the back wall, looking at the stage
	var screen: MeshInstance3D = room.find_screen()
	var stage := screen.global_transform * screen.get_aabb().get_center()
	var start: Vector3 = room.get_camera_markers()[0].global_position
	var away := start - stage
	away.y = 0
	away = away.normalized()
	# back out step by step until the camera is behind the back wall
	var d := 0.0
	cam.global_position = start
	cam.look_at(stage, Vector3.UP)
	for i in 60:
		d += 1.0
		cam.global_position = start + away * d
		cam.look_at(stage, Vector3.UP)
		await get_tree().physics_frame
		await get_tree().process_frame
		if cam.near > 0.1:
			break
	cam.global_position += away * 1.5
	await _secs(0.8)
	print("backed out ", d + 1.5, " m, near=", snappedf(cam.near, 0.01))
	await _shot(out + "/cam_outside_seethrough.png")
	AppState.set_setting("camera_see_through", false)
	await _secs(0.5)
	print("near off=", cam.near)
	await _shot(out + "/cam_outside_off.png")
	print("DONE")
	AppState.request_quit()
