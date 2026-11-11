extends Node
## Forge Hall: the room loads with everything its markers promise (screen, ten cameras, four
## podiums, chat and reply screens, reaction targets, 30 bench seats in three stepped rows, the
## fire, the sunbeams) and the Room tab's Fire, Light strips and Light rays sliders do their
## job. Saves one screenshot per camera into the output folder (look at them: the look is not
## checked here).
##   <redot console exe> --path . _tests/test_forge_hall.tscn -- C:/temp/sr_tests --mp-profile=test

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


## The glow (emission energy) of the first mesh surface in the room using the material `mat_name`.
func _glow_of(room: Room, mat_name: String) -> float:
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m != null and m.resource_name == mat_name:
				return m.emission_energy_multiplier
	return -1.0


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("audience_seat_gap", 1.0)
	AppState.set_setting("forge_fire", 1.0)
	AppState.set_setting("forge_neon", 1.0)
	AppState.set_setting("sun_rays", 1.0)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("forge_hall")
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "ForgeHallRoom", "the Forge Hall loaded (%s)" % (room.name if room else "no room"))
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
	_check(room.get_camera_label(cams[0]) == "Centre Aisle", "the first camera is Centre Aisle (%s)" % room.get_camera_label(cams[0]))
	var pres := room.get_presenter_setups()
	var podiums := 0
	var lamps := 0
	for p in pres:
		podiums += 1 if p["podium"] != null else 0
		lamps += 1 if p["lamp"] != null else 0
	_check(pres.size() == 4 and podiums == 4 and lamps == 4, "four presenter spots with podiums and lamps (%d / %d / %d)" % [pres.size(), podiums, lamps])
	_check(room.get_chat_screen_marker() != null and room.get_reply_screen_marker() != null, "CHAT_Screen and REPLY_Screen markers")
	_check(room.find_children("TARGET_*", "Node3D", true, false).size() == 4, "four reaction targets (forge, lantern, anvil, boiler)")
	_check(room.get_webcam_marker() == null, "no webcam frame (the webcam uses the corner overlay)")

	# the audience: 30 seats on three rows of benches, each row a step higher
	var seats := room.get_audience_seats()
	var heights := {}
	for t in seats:
		heights[snappedf(room.to_local(t.origin).y, 0.01)] = true
	_check(seats.size() == 30, "30 chat seats at the default seat spacing (%d)" % seats.size())
	_check(heights.size() == 3, "three rows at three heights (%s)" % str(heights.keys()))

	# the fire, the sunbeams and the room's own controls
	var fx := room.find_child("SunShafts", false, false)
	var flames := fx.find_children("FireFlame*", "MeshInstance3D", false, false) if fx else []
	var beams := fx.get_node_or_null("Beams") as MeshInstance3D if fx else null
	var patches := fx.get_node_or_null("Patches") as MeshInstance3D if fx else null
	var fire_light := room.find_child("FireLight", false, false) as OmniLight3D
	_check(flames.size() == 4 and fire_light != null and fire_light.visible, "four flame rectangles (three in the firebox, one in the slot) and the fire's light (%d)" % flames.size())
	_check(beams != null and beams.visible and beams.mesh.get_faces().size() == 48, "two sunbeams, each an open box (%d vertices)" % (beams.mesh.get_faces().size() if beams else -1))
	_check(patches != null and patches.visible, "the patches of sunlight on the floor")
	_check(beams != null and not room.get_static_meshes().has(beams) and not room.get_static_meshes().has(flames[0] if flames.size() > 0 else null),
		"the beams and flames are not counted as the room's own meshes")
	var keys: Array[String] = []
	for c in room.get_controls():
		if c.has("key"):
			keys.append(String(c["key"]))
	_check(keys.has("forge_fire") and keys.has("forge_neon") and keys.has("sun_rays"), "the Room tab gets Fire, Light strips and Light rays (%s)" % str(keys))

	# screenshots from every camera
	for i in cams.size():
		EventBus.camera_preset_requested.emit(i)
		await _secs(1.0)
		await _shot(_out + "/forge_%02d_%s.png" % [i + 1, room.get_camera_label(cams[i]).replace(" ", "_")])

	# the sliders
	var neon_full := _glow_of(room, "Neon_Cyan")
	var embers_full := _glow_of(room, "Embers")
	AppState.set_setting("forge_neon", 0.0)
	AppState.set_setting("forge_fire", 0.0)
	AppState.set_setting("sun_rays", 0.0)
	await _secs(0.3)
	_check(neon_full > 0.5 and is_zero_approx(_glow_of(room, "Neon_Cyan")), "Light strips 0%% turns the strips off (%.2f -> %.2f)" % [neon_full, _glow_of(room, "Neon_Cyan")])
	_check(embers_full > 0.5 and is_zero_approx(_glow_of(room, "Embers")) and not (flames[0] as MeshInstance3D).visible and not fire_light.visible,
		"Fire 0% puts the fire out (flames, embers and light)")
	_check(not beams.visible and not patches.visible, "Light rays 0% hides the sunbeams and patches")
	EventBus.camera_preset_requested.emit(1)
	await _secs(1.0)
	await _shot(_out + "/forge_all_off.png")
	AppState.set_setting("forge_neon", 1.0)
	AppState.set_setting("forge_fire", 1.0)
	AppState.set_setting("sun_rays", 1.0)
	await _secs(0.3)
	_check(is_equal_approx(_glow_of(room, "Neon_Cyan"), neon_full) and (flames[0] as MeshInstance3D).visible and beams.visible, "back at 100% everything is on again")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
