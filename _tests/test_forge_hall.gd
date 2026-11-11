extends Node
## Forge Hall: the room loads with everything its markers promise (screen, ten cameras, four
## podiums, chat and reply screens, reaction targets, 30 bench seats in three stepped rows, the
## fire, the sunbeams, five art frames) and the Room tab's controls do their job: Fire, Light
## strips, Light rays, the alcove art's frame / style / picture, the LED dots and the screen's
## bend, size and place (which reload the room). Saves one screenshot per camera and a few of
## the bent screen and hologram art into the output folder (look at them: the look is not
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
	AppState.set_setting("led_look", 1.0)
	AppState.set_setting("holo_amount", 0.0)
	AppState.set_setting("holo_transparency", 0.0)
	AppState.set_setting("forge_screen_x", 0.0)
	AppState.set_setting("forge_screen_y", 0.0)
	AppState.set_setting("forge_screen_size", 1.0)
	AppState.set_setting("forge_screen_bend", 0.0)
	AppState.set_setting("forge_art_frame", "brass")
	AppState.set_setting("forge_art_style", "picture")
	for n in range(1, 6):
		AppState.set_setting("forge_art_%d" % n, "")
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
	_check(keys.has("forge_screen_bend") and keys.has("forge_screen_size") and keys.has("forge_screen_x") and keys.has("forge_screen_y"),
		"the Room tab gets the screen's Bend, Size and Move sliders")
	_check(keys.has("forge_art_frame") and keys.has("forge_art_style") and keys.has("forge_art_1") and keys.has("forge_art_5"),
		"the Room tab gets the alcove art's Frame, Art style and five picture boxes")
	_check(room.reload_keys().has("forge_screen_bend") and room.reload_keys().has("forge_screen_x"), "the screen's shape settings ask for a room reload")
	# the control panel builds all of them (dropdowns and picture boxes are new kinds of room control)
	var panel: Node = main.get_node("ControlPanel")
	var schema_keys := {}
	for e: Dictionary in panel.settings_schema():
		schema_keys[String(e["key"])] = String(e["type"])
	_check(schema_keys.get("forge_art_frame", "") == "choice" and schema_keys.get("forge_art_1", "") == "text" and schema_keys.get("forge_screen_bend", "") == "range",
		"the panel built a dropdown, a picture box and a slider for them")
	_check(schema_keys.has("led_look") and schema_keys.has("holo_amount"), "the Room tab also gets LED dots and the Hologram screen sliders")

	# the art frames: one per alcove, each with a built-in poster and four frame bars
	var frames := fx.find_children("ArtFrame*", "Node3D", false, false) if fx else []
	var canvases := 0
	for f in frames:
		var cv := f.get_node_or_null("Canvas") as MeshInstance3D
		if cv != null and cv.visible and cv.material_override is StandardMaterial3D and (cv.material_override as StandardMaterial3D).albedo_texture != null \
				and (f.get_node("Bar0") as MeshInstance3D).visible:
			canvases += 1
	_check(frames.size() == 5 and canvases == 5, "five framed posters in the wall alcoves (%d / %d)" % [frames.size(), canvases])

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

	# alcove art: hologram style, another frame, a picture file of the owner's
	var canvas1 := frames[0].get_node("Canvas") as MeshInstance3D if frames.size() > 0 else null
	if canvas1:
		var pic := _out + "/forge_test_art.png"
		var img := Image.create(200, 100, false, Image.FORMAT_RGBA8)     # twice as wide as high
		img.fill(Color(0.9, 0.3, 0.1))
		img.save_png(pic)
		AppState.set_setting("forge_art_1", pic)
		await _secs(1.0)
		var qsize := (canvas1.mesh as QuadMesh).size
		_check(absf(qsize.x / qsize.y - 2.0) < 0.01 and qsize.x <= 1.41, "a picture file shows in frame 1 in its own shape (%.2f x %.2f m)" % [qsize.x, qsize.y])
		AppState.set_setting("forge_art_1", "")
		await _secs(0.3)
		_check((canvas1.mesh as QuadMesh).size.y > 1.5, "blank brings the built-in poster back")
		AppState.set_setting("forge_art_style", "hologram")
		AppState.set_setting("forge_art_frame", "neon")
		await _secs(0.3)
		var bar := frames[0].get_node("Bar0") as MeshInstance3D
		_check(canvas1.material_override is ShaderMaterial and canvas1.position.z > 0.05, "Art style Hologram floats a see-through picture off the wall")
		_check((bar.material_override as StandardMaterial3D).emission_enabled, "Frame Light strip glows")
		EventBus.camera_preset_requested.emit(5)
		await _secs(1.0)
		await _shot(_out + "/forge_art_hologram.png")
		AppState.set_setting("forge_art_frame", "none")
		await _secs(0.2)
		_check(not bar.visible, "Frame No frame hides the bars")
		AppState.set_setting("forge_art_frame", "brass")
		AppState.set_setting("forge_art_style", "picture")

	# LED dots: the slider scales the room's own dot strength on the screen material
	var smat := room.find_screen().material_override as ShaderMaterial
	var led_full := float(smat.get_shader_parameter("led_amount")) if smat else -1.0
	AppState.set_setting("led_look", 0.0)
	await _secs(0.2)
	_check(led_full > 0.1 and smat != null and is_zero_approx(float(smat.get_shader_parameter("led_amount"))), "LED dots 0%% gives a smooth picture (%.2f -> 0)" % led_full)
	AppState.set_setting("led_look", 1.0)

	# the screen's shape: it bends at once, then the room reloads with the new shape
	var flat_box := room.find_screen().get_aabb()
	AppState.set_setting("forge_screen_bend", 0.8)
	AppState.set_setting("forge_screen_size", 0.8)
	AppState.set_setting("forge_screen_x", 3.0)      # further than the alcove allows
	await _secs(0.2)
	var bent := room.find_screen().get_aabb()
	_check(flat_box.size.z < 0.01 and bent.size.z > 0.5 and is_equal_approx(bent.position.z, flat_box.position.z),
		"Bend 80%% wraps the screen's edges forward, never into the wall (%.2f m deep)" % bent.size.z)
	_check(bent.end.x <= 4.96 and bent.end.x > 4.5 and bent.size.x < flat_box.size.x, "smaller and moved right, it stops at the alcove's edge (right edge at %.2f m)" % bent.end.x)
	await _secs(8.0)                                  # RoomHost reloads the room 0.8 s after the last change
	var room2: Room = host.get_current_room()
	_check(room2 != null and room2 != room and room2.find_screen().get_aabb().size.z > 0.5, "the room reloaded with the bent screen")
	AppState.set_curtain(false, "instant")
	for shot: Array in [[0, "forge_screen_concave"], [1, "forge_screen_concave_side"]]:
		EventBus.camera_preset_requested.emit(int(shot[0]))
		await _secs(1.0)
		await _shot(_out + "/%s.png" % String(shot[1]))
	AppState.set_setting("forge_screen_bend", -0.8)
	AppState.set_setting("forge_screen_size", 1.0)
	AppState.set_setting("forge_screen_x", 0.0)
	await _secs(0.2)
	var bulge := room2.find_screen().get_aabb()
	_check(bulge.size.z > 0.5 and is_equal_approx(bulge.position.z, flat_box.position.z), "Bend -80%% bulges the middle forward (%.2f m deep)" % bulge.size.z)
	await _secs(6.0)
	AppState.set_curtain(false, "instant")
	EventBus.camera_preset_requested.emit(1)
	await _secs(1.0)
	await _shot(_out + "/forge_screen_convex_side.png")
	AppState.set_setting("forge_screen_bend", 0.0)
	await _secs(0.2)
	var room3: Room = host.get_current_room()
	_check(room3 != null and room3.find_screen().get_aabb().size.is_equal_approx(flat_box.size), "Bend 0% is the flat screen again")
	await _secs(5.0)

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
