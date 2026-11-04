extends Node
## Throne Hall: the room loads with everything its markers promise (screen, ten cameras, four
## podiums, chat and reply screens, reaction targets, standing chat lines along the carpet, the
## gallery crowd, the beam of light on the throne) and the Benches tick box shows the benches and
## re-seats the audience at bench height after the room reloads. Saves one screenshot per camera
## into the output folder (look at them: the look is not checked here).
##   <redot console exe> --path . _tests/test_throne_hall.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


## Lowest and highest Y of the chat seats (room space): all standing or all sitting.
func _seat_heights(room: Room) -> Vector2:
	var lo := 1e9
	var hi := -1e9
	for t in room.get_audience_seats():
		var y := room.to_local(t.origin).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(lo, hi)


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("throne_benches", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("throne_hall")
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "ThroneHallRoom", "the Throne Hall loaded (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return

	# the markers
	_check(room.find_screen() != null, "TVScreen is there")
	var cams := room.get_camera_markers()
	var reaction := false
	for c in cams:
		if String(c.name).contains("Reaction"):
			reaction = true
	_check(cams.size() == 10 and reaction, "ten camera presets, one of them the Reaction camera (%d)" % cams.size())
	_check(room.get_camera_label(cams[0]) == "Carpet Entrance", "the first camera is Carpet Entrance (%s)" % room.get_camera_label(cams[0]))
	var pres := room.get_presenter_setups()
	var podiums := 0
	var lamps := 0
	for p in pres:
		podiums += 1 if p["podium"] != null else 0
		lamps += 1 if p["lamp"] != null else 0
	_check(pres.size() == 4 and podiums == 4 and lamps == 4, "four presenter spots with podiums and lamps (%d / %d / %d)" % [pres.size(), podiums, lamps])
	_check(room.get_chat_screen_marker() != null and room.get_reply_screen_marker() != null, "CHAT_Screen and REPLY_Screen markers")
	_check(room.find_children("TARGET_*", "Node3D", true, false).size() == 4, "four reaction targets (throne, chandelier, two banners)")
	_check(room.get_webcam_marker() == null, "no webcam frame (the webcam uses the corner overlay)")

	# the audience: standing lines along the carpet, the gallery crowd
	var seats := room.get_audience_seats()
	var h := _seat_heights(room)
	_check(seats.size() >= 150, "the chat lines give at least 150 places (%d)" % seats.size())
	_check(absf(h.x - room.standing_height) < 0.05 and absf(h.y - room.standing_height) < 0.05, "everyone stands (seat markers %.2f..%.2f m up)" % [h.x, h.y])
	var crowd := room.get_crowd_seat_info()
	var levels := {}
	for e in crowd:
		levels[int(e["level"])] = true
	# (624 seats 0.6 m apart in the .json; the default Seat spacing of 1 m keeps every other one)
	_check(crowd.size() >= 300 and levels.has(2) and levels.has(3), "the gallery crowd fills two tiers (%d seats, levels %s)" % [crowd.size(), levels.keys()])
	var benches := room.find_child("BENCHES", true, false) as Node3D
	_check(benches != null and not benches.visible, "the benches are hidden by default")

	# the beam on the throne and the room's own controls
	var shaft := room.find_child("SunShafts", false, false) as MeshInstance3D
	_check(shaft != null and shaft.visible and shaft.mesh.get_faces().size() == 24, "the throne light is one open box (%d vertices)" % (shaft.mesh.get_faces().size() if shaft else -1))
	_check(shaft != null and not room.get_static_meshes().has(shaft), "the beam is not one of the room's static meshes")
	var keys: Array[String] = []
	for c in room.get_controls():
		if c.has("key"):
			keys.append(String(c["key"]))
	_check(keys.has("throne_benches") and keys.has("throne_beam"), "the Room tab gets Benches and Throne light (%s)" % str(keys))
	_check(room.reload_keys().has("throne_benches"), "the benches setting asks for a room reload")
	AppState.set_setting("throne_beam", 0.0)
	await get_tree().process_frame
	_check(shaft != null and not shaft.visible, "Throne light 0% hides the beam")
	AppState.set_setting("throne_beam", 1.0)

	# screenshots from every camera
	for i in cams.size():
		EventBus.camera_preset_requested.emit(i)
		await _secs(1.0)
		await _shot(_out + "/throne_%02d_%s.png" % [i + 1, room.get_camera_label(cams[i]).replace(" ", "_")])

	# Benches on: shown at once, the room reloads, everyone sits
	AppState.set_setting("throne_benches", true)
	await get_tree().process_frame
	_check(benches != null and benches.visible, "ticking Benches shows them at once")
	await _secs(5.0)
	var room2: Room = host.get_current_room()
	_check(room2 != null and room2 != room, "the room reloaded for the new seat heights")
	if room2:
		var h2 := _seat_heights(room2)
		_check(absf(h2.x - room2.bench_height) < 0.05 and absf(h2.y - room2.bench_height) < 0.05, "everyone sits on the benches (seat markers %.2f..%.2f m up)" % [h2.x, h2.y])
		var b2 := room2.find_child("BENCHES", true, false) as Node3D
		_check(b2 != null and b2.visible, "the benches are shown in the reloaded room")
		EventBus.camera_preset_requested.emit(0)
		await _secs(1.0)
		await _shot(_out + "/throne_benches.png")
	AppState.set_setting("throne_benches", false)

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
