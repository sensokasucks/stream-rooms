extends Node
## Filler crowd, overflow seating, presenter chat links, bubble visibility.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _b2g(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)
func _chat(name: String, text: String, uid: String = "") -> void:
	EventBus.chat_message_received.emit({"name": name, "username": name.to_lower(), "platform": "kick",
		"user_id": uid if uid != "" else name.to_lower(), "text": text, "timestamp": Time.get_unix_time_from_system()})
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("camera_fov", 75.0)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("audience_hide_commands", false)
	AppState.set_setting("presenter_2_chat", "HostGuy, twitch:othername")
	AppState.set_setting("presenter_2_on", true)
	AppState.set_setting("presenter_3_on", true)
	AppState.set_setting("presenter_2_source", "silhouette")
	AppState.set_setting("presenter_2_chat_look", true)
	AppState.set_setting("presenter_2_chat_bubbles", true)
	AppState.set_setting("audience_crowd", true)
	AppState.set_setting("audience_crowd_fill", 0.6)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var room = main.get_node("RoomHost").get_current_room()
	var aud: AudienceView = room.find_child("Audience", false, false)
	var kinds := {0: 0, 1: 0, 2: 0}
	for i in aud.get_seat_count():
		kinds[AudienceManager.get_slot_kind(i)] += 1
	print("slots=", aud.get_seat_count(), " kinds=", kinds, " fillers=", aud.get_filler_count(), " rich=", aud._rich.size())
	print("presenter slots=", aud._presenter_slots)
	# perf: the per-frame audience work with a still camera, then a moving one
	var cam: CameraRig = main.get_node("CameraRig")
	cam.global_position = _b2g(Vector3(0, -6, 3.0))
	cam.look_at(_b2g(Vector3(0, 4, 3.0)), Vector3.UP)
	await _secs(0.5)
	var t0 := Time.get_ticks_usec()
	for k in 200:
		aud._process(0.016)
	var still := (Time.get_ticks_usec() - t0) / 200.0
	t0 = Time.get_ticks_usec()
	for k in 200:
		cam.global_position.x = 0.001 * k
		aud._process(0.016)
	var moving := (Time.get_ticks_usec() - t0) / 200.0
	print("audience _process: still %.1f us, camera moving %.1f us (rich seats %d)" % [still, moving, aud._rich.size()])
	# overflow: 100 chatters -> the main seats fill, the rest go to the crowd
	for n in 100:
		_chat("Viewer%03d" % n, "hi %d" % n)
	await _secs(0.3)
	var in_crowd := 0
	var in_main := 0
	for i in aud.get_seat_count():
		if aud.is_seat_taken(i):
			match AudienceManager.get_slot_kind(i):
				0: in_main += 1
				1: in_crowd += 1
	print("after 100 chatters: main=", in_main, " crowd=", in_crowd, " fillers=", aud.get_filler_count(), " rich=", aud._rich.size())
	t0 = Time.get_ticks_usec()
	for k in 200:
		cam.global_position.x = 0.001 * k
		aud._process(0.016)
	print("audience _process with 100 chatters, camera moving: %.1f us" % ((Time.get_ticks_usec() - t0) / 200.0))
	t0 = Time.get_ticks_usec()
	for k in 200:
		aud._process(0.016)
	print("audience _process with 100 chatters, still: %.1f us" % ((Time.get_ticks_usec() - t0) / 200.0))
	# the linked presenter
	var hg_before := AudienceManager.find_slot_for_user("kick", "hostguy")
	_chat("HostGuy", "hello from the podium")
	await _secs(0.3)
	var hs := AudienceManager.find_slot_for_user("kick", "hostguy")
	print("hostguy slot before=", hg_before, " now=", hs, " kind=", AudienceManager.get_slot_kind(hs), " presenter=", AudienceManager.get_slot_presenter(hs))
	var p2 = room.find_child("Presenter2", true, false)
	print("presenter2 picture visible=", p2.get_picture().visible, " look=", aud._seats[hs]["look"], " sprite visible=", aud._seats[hs]["sprite"].visible)
	var rl = room.find_child("Reactions", false, false)
	var o: Dictionary = rl._origin({"platform": "kick", "id": "hostguy", "username": "hostguy"})
	print("throw origin slot=", o["slot"], " dist to presenter head=", snappedf((o["pos"] as Vector3).distance_to(aud.get_seat_head(hs)), 0.01),
		" dist to picture=", snappedf((o["pos"] as Vector3).distance_to(p2.get_picture().global_position), 0.01))
	print("seat move for presenter=", AudienceManager.move_to_row(hs, "front"), " swap=", AudienceManager.swap_seats(hs, 0))
	# a jump on the presenter spot moves the live picture too
	var pic_y0: float = p2.get_picture().global_position.y
	aud.play_motion(hs, "jump", 0.5)
	var top := 0.0
	for k in 20:
		await get_tree().process_frame
		top = maxf(top, p2.get_picture().global_position.y - pic_y0)
	print("picture follows jump: max dy=", snappedf(top, 0.01))
	await _secs(0.6)
	# other platform with the same name does not match the platform-limited link
	print("twitch:othername links=", AudienceManager.linked_presenter("twitch", "OtherName", ""), " kick:othername=", AudienceManager.linked_presenter("kick", "othername", ""))
	# bubble visibility: a crowd chatter speaks while the camera looks away
	var crowd_slot := -1
	for i in aud.get_seat_count():
		if aud.is_seat_taken(i) and AudienceManager.get_slot_kind(i) == 1:
			crowd_slot = i
			break
	cam.global_position = _b2g(Vector3(0, 2, 3.0))
	cam.look_at(_b2g(Vector3(0, 8, 3.0)), Vector3.UP)      # towards the stage
	await _secs(0.3)
	var who := String(AudienceManager.get_seat_member(crowd_slot)["name"])
	_chat(who, "can you see me? KEKW")
	await _secs(0.5)
	var cs: Dictionary = aud._seats[crowd_slot]
	print("unseen bubble: active=", cs["active"], " pending=", cs["pending"], " built=", cs["viewport"] != null)
	var head := aud.get_seat_head(crowd_slot)
	cam.global_position = _b2g(Vector3(0, -3, 2.5))
	cam.look_at(head, Vector3.UP)
	await _secs(0.5)
	print("seen bubble: pending=", cs["pending"], " built=", cs["viewport"] != null, " vis=", cs["vis"],
		" mode=", (cs["viewport"] as SubViewport).render_target_update_mode if cs["viewport"] else -1)
	await _shot(out + "/c1_crowd_bubble.png")
	cam.look_at(head + _b2g(Vector3(0, 0, 30)), Vector3.UP)   # straight up
	await _secs(0.5)
	print("looking away: vis=", cs["vis"], " mode=", (cs["viewport"] as SubViewport).render_target_update_mode if cs["viewport"] else -1)
	# views
	var views := [
		["c2_from_stage", Vector3(0, 1.8, 3.8), Vector3(0, -10, 2.0)],
		["c3_back_corner", Vector3(-9, -9, 4.5), Vector3(4, 2, 3.0)],
		["c4_presenters", Vector3(0, -5, 3.2), Vector3(0, 2.5, 2.8)],
	]
	_chat("HostGuy", "welcome everyone!")
	for n in 12:
		_chat("Viewer%03d" % (79 + n), "woo %d" % n)
	for v in views:
		cam.global_position = _b2g(v[1])
		cam.look_at(_b2g(v[2]), Vector3.UP)
		await _secs(1.2)
		await _shot(out + "/%s.png" % v[0])
	# crowd-wide dance: the filler crowd joins in
	EventBus.reaction_play.emit({"id": "cm", "effect": "crowd_motion", "params": {"who": "all", "style": "cheer", "duration_sec": 3.0}})
	cam.global_position = _b2g(Vector3(0, 1.8, 3.8))
	cam.look_at(_b2g(Vector3(0, -10, 2.0)), Vector3.UP)
	await _secs(0.8)
	var cl: CrowdLayer = aud.find_child("Crowd", false, false)
	print("crowd motion t=", snappedf(float(cl._mat.get_shader_parameter("motion_t")), 0.01), " style=", cl._mat.get_shader_parameter("motion_style"))
	await _shot(out + "/c5_cheer.png")
	# unlink: the presenter becomes a regular chatter again
	AppState.set_setting("presenter_2_chat", "")
	await _secs(0.3)
	print("after unlink: hostguy slot=", AudienceManager.find_slot_for_user("kick", "hostguy"), " picture visible=", p2.get_picture().visible)
	_chat("HostGuy", "back in the crowd")
	await _secs(0.3)
	var hs2 := AudienceManager.find_slot_for_user("kick", "hostguy")
	print("after unlink + chat: slot=", hs2, " kind=", AudienceManager.get_slot_kind(hs2))
	AppState.set_setting("audience_crowd_fill", 0.2)
	await _secs(0.2)
	print("fill 20%: fillers=", aud.get_filler_count())
	print("DONE")
	AppState.request_quit()
