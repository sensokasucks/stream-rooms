extends Node
## Forge Hall: the room loads with everything its markers promise (screen, ten cameras, four
## podiums, chat and reply screens, reaction targets, 30 bench seats in three stepped rows, the
## fire, the sunbeams, thirteen art frames, three small live screens) and the Room tab's
## controls do their job: Fire, Inlay brightness and Inlay glow, Light rays, Time of day and
## Day length (sky, sun and moon beams), the "please stand by" card that replaces the curtain,
## the floor screen rising, the small screens' sources (with an NDI mock and, when ffmpeg is
## there, a stream address read through core/extra_feeds.gd), the alcove art's frame / style /
## picture, the LED dots and the big screen's bend, size and place (which reload the room).
## Saves one screenshot per camera and a few of the other looks into the output folder (look
## at them: the look is not checked here).
##   <redot console exe> --path . _tests/test_forge_hall.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
## The room's script, for its constants (it has no class name).
const FH := preload("res://rooms/forge_hall/forge_hall_room.gd")
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
	AppState.set_setting("forge_neon_bloom", true)
	AppState.set_setting("forge_time", 9.5)
	AppState.set_setting("forge_day_minutes", 0.0)
	AppState.set_setting("forge_clouds", 1.0)
	AppState.set_setting("forge_nebula", 1.0)
	AppState.set_setting("forge_stars", 1.0)
	AppState.set_setting("forge_lift_up", false)
	AppState.set_setting("forge_live_1_source", "webcam")
	AppState.set_setting("forge_live_2_source", "off")
	AppState.set_setting("forge_live_3_source", "off")
	AppState.set_setting("forge_live_2_picture", "")
	for n in range(1, 4):
		AppState.set_setting("forge_live_%d_address" % n, "")
	for n in [2, 3]:
		for part: String in ["x", "y", "tilt", "turn"]:
			AppState.set_setting("forge_live_%d_%s" % [n, part], 0.0)
		AppState.set_setting("forge_live_%d_size" % n, 1.0)
	AppState.set_setting("forge_live_align", true)
	NdiReceiver.mock_finder = load("res://_tests/mock_ndi/mock_finder.gd")     # stands in for the NDI plugin
	AppState.set_setting("curtain_enabled", true)
	AppState.set_setting("curtain_sign", "")
	AppState.set_setting("curtain_speed", 1.0)
	AppState.set_setting("holo_amount", 0.0)
	AppState.set_setting("holo_transparency", 0.0)
	AppState.set_setting("forge_screen_x", 0.0)
	AppState.set_setting("forge_screen_y", 0.0)
	AppState.set_setting("forge_screen_size", 1.0)
	AppState.set_setting("forge_screen_bend", 0.0)
	AppState.set_setting("forge_art_frame", "brass")
	AppState.set_setting("forge_art_style", "picture")
	for n in range(1, 14):
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
	var sparks := fx.get_node_or_null("FireSparks") as CPUParticles3D if fx else null
	_check(flames.size() == 10 and fire_light != null and fire_light.visible, "ten flames (seven in the firebox, three in the slot) and the fire's light (%d)" % flames.size())
	_check(sparks != null and sparks.emitting, "sparks rise from the firebox")
	_check(beams != null and beams.visible and beams.mesh != null and beams.mesh.get_faces().size() == 120,
		"at 9:30 the sun shines through the five left windows, each beam an open box (%d vertices)" % (beams.mesh.get_faces().size() if beams and beams.mesh else -1))
	_check(patches != null and patches.visible, "the patches of sunlight on the floor")
	_check(beams != null and not room.get_static_meshes().has(beams) and not room.get_static_meshes().has(flames[0] if flames.size() > 0 else null),
		"the beams and flames are not counted as the room's own meshes")
	var keys: Array[String] = []
	for c in room.get_controls():
		if c.has("key"):
			keys.append(String(c["key"]))
	_check(keys.has("forge_fire") and keys.has("forge_neon") and keys.has("sun_rays"), "the Room tab gets Fire, Inlay brightness and Light rays (%s)" % str(keys))
	_check(keys.has("forge_neon_bloom") and keys.has("forge_time") and keys.has("forge_day_minutes"), "and Inlay glow, Time of day and Day length")
	_check(keys.has("forge_lift_up") and keys.has("forge_live_1_source") and keys.has("forge_live_3_picture"), "and the small live screens' controls")
	_check(keys.has("forge_screen_bend") and keys.has("forge_screen_size") and keys.has("forge_screen_x") and keys.has("forge_screen_y"),
		"the Room tab gets the screen's Bend, Size and Move sliders")
	_check(keys.has("forge_art_frame") and keys.has("forge_art_style") and keys.has("forge_art_1") and keys.has("forge_art_13"),
		"the Room tab gets the alcove art's Frame, Art style and thirteen picture boxes")
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
	_check(frames.size() == 13 and canvases == 13, "thirteen framed posters in the wall alcoves (%d / %d)" % [frames.size(), canvases])

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
	_check(neon_full > 0.5 and is_zero_approx(_glow_of(room, "Neon_Cyan")), "Inlay brightness 0%% turns the inlays off (%.2f -> %.2f)" % [neon_full, _glow_of(room, "Neon_Cyan")])
	_check(embers_full > 0.5 and is_zero_approx(_glow_of(room, "Embers")) and not (flames[0] as MeshInstance3D).visible and not fire_light.visible,
		"Fire 0% puts the fire out (flames, embers and light)")
	_check(sparks != null and not sparks.emitting, "and stops the sparks")
	_check(not beams.visible and not patches.visible, "Light rays 0% hides the sunbeams and patches")
	EventBus.camera_preset_requested.emit(1)
	await _secs(1.0)
	await _shot(_out + "/forge_all_off.png")
	AppState.set_setting("forge_neon", 1.0)
	AppState.set_setting("forge_fire", 1.0)
	AppState.set_setting("sun_rays", 1.0)
	await _secs(0.3)
	_check(is_equal_approx(_glow_of(room, "Neon_Cyan"), neon_full) and (flames[0] as MeshInstance3D).visible and beams.visible, "back at 100% everything is on again")

	# Inlay glow off: the bloom starts higher and the inlays stay under it, however high the slider
	AppState.set_setting("forge_neon_bloom", false)
	AppState.set_setting("forge_neon", 3.0)
	await _secs(0.3)
	var capped := _glow_of(room, "Neon_Cyan")
	var env_now: Environment = get_viewport().get_world_3d().environment
	_check(capped > 1.5 and capped <= FH.NO_BLOOM_GLOW + 0.01 and env_now != null and env_now.glow_hdr_threshold > FH.NO_BLOOM_GLOW,
		"Inlay glow off: bright lines, still under where the bloom starts, even at 300%% (%.2f)" % capped)
	EventBus.camera_preset_requested.emit(1)
	await _secs(1.0)
	await _shot(_out + "/forge_no_bloom.png")
	AppState.set_setting("forge_neon_bloom", true)
	await _secs(0.2)
	_check(_glow_of(room, "Neon_Cyan") > neon_full * 4.9 and is_equal_approx(env_now.glow_hdr_threshold, FH.BLOOM_THRESHOLD),
		"with the glow back on, 300% is five times as bright and the bloom starts where it did")
	AppState.set_setting("forge_neon", 1.0)

	# time of day: the sky, and which windows the light comes through
	var sky_env := get_viewport().world_3d.environment
	var sky := sky_env.sky.sky_material as ShaderMaterial if sky_env and sky_env.sky else null
	_check(sky != null and float(sky.get_shader_parameter("day")) > 0.9, "the room has its own sky, and at 9:30 it is day")
	AppState.set_setting("forge_time", 12.0)
	await _secs(0.3)
	_check(not beams.visible, "at noon the sun is overhead: no beams through the side windows")
	AppState.set_setting("forge_time", 15.0)
	await _secs(0.3)
	_check(beams.visible and beams.mesh.get_faces().size() == 72, "at 15:00 the sun shines through the three right windows (%d vertices)" % (beams.mesh.get_faces().size() if beams.mesh else -1))
	AppState.set_setting("forge_time", 18.2)
	await _secs(0.3)
	EventBus.camera_preset_requested.emit(4)
	await _secs(1.0)
	await _shot(_out + "/forge_sunset.png")
	AppState.set_setting("forge_time", 22.0)
	await _secs(0.3)
	_check(sky != null and float(sky.get_shader_parameter("day")) < 0.05, "at 22:00 it is night")
	# the sky's own sliders reach the shader
	AppState.set_setting("forge_clouds", 0.0)
	AppState.set_setting("forge_nebula", 1.6)
	AppState.set_setting("forge_stars", 0.5)
	await _secs(0.3)
	_check(sky != null and is_zero_approx(float(sky.get_shader_parameter("cloud_amount"))) and is_equal_approx(float(sky.get_shader_parameter("nebula_amount")), 1.6)
		and is_equal_approx(float(sky.get_shader_parameter("star_amount")), 0.5), "Clouds, Nebula and Stars set the sky")
	AppState.set_setting("forge_clouds", 1.0)
	AppState.set_setting("forge_nebula", 1.0)
	AppState.set_setting("forge_stars", 1.0)
	await _secs(0.3)
	_check(beams.visible and beams.mesh.get_faces().size() == 120, "and moonbeams come through the left windows")
	for shot: Array in [[4, "forge_night_windows"], [1, "forge_night"]]:
		EventBus.camera_preset_requested.emit(int(shot[0]))
		await _secs(1.0)
		await _shot(_out + "/%s.png" % String(shot[1]))
	AppState.set_setting("forge_day_minutes", 1.0)        # a whole day in a minute: 0.4 hours a second
	await _secs(1.5)
	var ran: float = fposmod(room.get_hour() - 22.0, 24.0)
	_check(ran > 0.3 and ran < 1.2, "Day length 1 min lets the clock run (%.2f hours in 1.5 s)" % ran)
	AppState.set_setting("forge_day_minutes", 0.0)
	AppState.set_setting("forge_time", 9.5)
	await _secs(0.3)

	# the "please stand by" card stands in for the curtain
	var card := room.find_child("StandbyCard", false, false) as StandbyCard
	_check(card != null and room.find_child("StageCurtain", false, false) == null, "the room has a stand-by card and no curtain")
	if card:
		AppState.set_curtain(true)
		await _secs(1.5)
		_check(is_equal_approx(card.get_shown_amount(), 1.0) and AppState.is_curtain_covering(), "closing the curtain fades the card in over the screen")
		EventBus.camera_preset_requested.emit(0)
		await _secs(1.0)
		await _shot(_out + "/forge_standby.png")
		AppState.set_curtain(false)
		await _secs(1.5)
		_check(is_zero_approx(card.get_shown_amount()) and not AppState.is_curtain_covering(), "opening it fades the card away")

	# the small live screens
	var lives := fx.find_children("LiveScreen*", "Node3D", false, false) if fx else []
	_check(lives.size() == 3, "three small live screens (%d)" % lives.size())
	if lives.size() == 3:
		var body := lives[0].get_node("Body") as Node3D
		_check(lives[0].visible and body.position.y < -2.0, "the floor screen starts down in the floor (%.2f m)" % body.position.y)
		_check(not lives[1].visible and not lives[2].visible, "the two upper screens are off until given a source")
		AppState.set_setting("forge_lift_up", true)
		await _secs(3.2)
		_check(is_zero_approx(body.position.y), "Raise the floor screen brings it up")
		var pic2 := _out + "/forge_test_live.png"
		var img2 := Image.create(160, 120, false, Image.FORMAT_RGBA8)     # 4:3
		img2.fill(Color(0.2, 0.7, 0.3))
		img2.save_png(pic2)
		AppState.set_setting("forge_live_2_picture", pic2)
		AppState.set_setting("forge_live_2_source", "picture")
		AppState.set_setting("forge_live_3_source", "screen")
		await _secs(1.0)
		var panel2 := lives[1].get_node("Picture") as MeshInstance3D
		var psize := (panel2.mesh as QuadMesh).size
		_check(lives[1].visible and (panel2.material_override as StandardMaterial3D).albedo_texture != null and absf(psize.x / psize.y - 4.0 / 3.0) < 0.01,
			"an upper screen shows a picture file in its own shape (%.2f x %.2f m)" % [psize.x, psize.y])
		_check(lives[2].visible, "the other upper screen is on as a copy of the big screen")
		EventBus.camera_preset_requested.emit(0)
		await _secs(1.0)
		await _shot(_out + "/forge_live_screens.png")
		AppState.set_setting("forge_live_2_source", "off")
		AppState.set_setting("forge_live_3_source", "off")
		AppState.set_setting("forge_lift_up", false)
		await _secs(0.3)
		_check(not lives[1].visible, "Off hides it again")

		# a small screen with a feed of its own: an NDI source found by part of its name
		var feeds := main.get_node("ScreenFeed/ExtraFeeds") as ExtraFeeds
		var pic3 := lives[2].get_node("Picture") as MeshInstance3D
		var finder: Node = main.get_node("ScreenFeed/NdiReceiver/NDIFinder")
		AppState.set_setting("forge_live_3_address", "cam 2")
		AppState.set_setting("forge_live_3_source", "ndi")
		await _secs(0.5)
		_check(lives[2].visible and (pic3.material_override as StandardMaterial3D).albedo_texture == null,
			"an NDI source that isn't on the network yet shows a dark panel")
		finder.call("set_sources", ["STUDIO-PC (Cam 2)", "STUDIO-PC (OBS)"])
		await _secs(1.0)
		_check((pic3.material_override as StandardMaterial3D).albedo_texture != null, "it shows as soon as the source appears (found by part of its name)")
		_check(ExtraFeeds.match_name("obs", PackedStringArray(["A (Cam)", "B (OBS)"])) == "B (OBS)" and ExtraFeeds.match_name("x", PackedStringArray(["A"])) == "",
			"names match on a part, whatever the letter case")
		# the Pick button beside an address box lists the sources found and fills the box
		var cp: Node = main.get_node("ControlPanel")
		var box1 := (cp.get("_texts") as Dictionary).get("forge_live_1_address") as LineEdit
		var pick: MenuButton = null
		if box1:
			for c in box1.get_parent().get_children():
				if c is MenuButton:
					pick = c
		_check(pick != null, "each small screen's address box has a Pick button")
		if pick:
			pick.about_to_popup.emit()
			var pop := pick.get_popup()
			var at := -1
			for i in pop.item_count:
				if pop.get_item_text(i) == "STUDIO-PC (OBS)":
					at = i
			_check(at >= 0, "Pick lists the NDI sources found right now")
			if at >= 0:
				pop.index_pressed.emit(at)
				await _secs(1.0)
				_check(String(AppState.get_setting("forge_live_1_address")) == "STUDIO-PC (OBS)" and String(AppState.get_setting("forge_live_1_source")) == "ndi"
					and box1.text == "STUDIO-PC (OBS)", "picking one fills the box and switches the screen to NDI")
			# an address with a login in it shows as dots while the box isn't being edited
			AppState.set_setting("forge_live_1_address", "rtsp://name:secret@10.0.0.9/live")
			await _secs(0.2)
			_check(box1.secret, "an address with a login shows as dots")
			AppState.set_setting("forge_live_1_address", "")
			AppState.set_setting("forge_live_1_source", "off")
			await _secs(0.2)
			_check(not box1.secret, "a box without a login shows its text")
		finder.call("set_sources", [])
		await _secs(0.5)
		_check((pic3.material_override as StandardMaterial3D).albedo_texture == null, "and goes dark again when the source leaves")
		AppState.set_setting("forge_live_3_source", "off")
		# a browser tab of its own: the sender page gets an "Extra screens" row for it, and the
		# row's pictures (podium-style packets with a slot past the avatar's) land on the screen
		var sf := main.get_node("ScreenFeed")
		AppState.set_setting("forge_live_3_source", "tab")
		await _secs(0.3)
		var wishes: Array = feeds.tab_wishes()
		_check(wishes.size() == CaptureServer.MAX_EXTRA_TABS and String((wishes[0] as Dictionary).get("kind")) == "tab"
			and String((wishes[0] as Dictionary).get("name")) == "Upper right screen" and String((wishes[1] as Dictionary).get("kind")) == "off",
			"Browser tab asks the sender page for a row named after the screen")
		_check((pic3.material_override as StandardMaterial3D).albedo_texture == null, "and shows a dark panel until a tab is picked")
		var frame := Image.create(320, 180, false, Image.FORMAT_RGB8)
		frame.fill(Color(0.1, 0.8, 0.3))
		sf.call("_on_presenter_frame", CaptureServer.EXTRA_SLOT0, frame)
		await _secs(0.2)
		var ttex := (pic3.material_override as StandardMaterial3D).albedo_texture
		_check(ttex != null and Vector2i(ttex.get_size()) == Vector2i(320, 180), "the picked tab's picture shows on that screen")
		sf.call("_on_presenter_frame", CaptureServer.EXTRA_SLOT0 + 1, frame)      # a row nobody asked for
		_check(not (feeds.get("_slots") as Dictionary).has("forge_live_2"), "a picture for a row no screen asked for is dropped")
		# a second screen takes the next row; the first keeps its row and its picture
		AppState.set_setting("forge_live_2_source", "tab")
		await _secs(0.3)
		wishes = feeds.tab_wishes()
		_check(String((wishes[1] as Dictionary).get("name")) == "Upper left screen" and (pic3.material_override as StandardMaterial3D).albedo_texture == ttex,
			"a second screen gets the next row without disturbing the first")
		EventBus.room_changed.emit("forge_hall")
		await _secs(ExtraFeeds.STALE_S + 0.6)
		_check((feeds.get("_slots") as Dictionary).has("forge_live_3") and (pic3.material_override as StandardMaterial3D).albedo_texture == ttex,
			"the tab keeps showing through a room change that still wants it")
		# with a real sender page (run by hand or by a browser script: add --sender-wait after
		# the output folder): wait for a tab picked on the page's "Upper left screen" row
		if OS.get_cmdline_user_args().has("--sender-wait"):
			EventBus.camera_preset_requested.emit(0)
			var mat_l := (lives[1].get_node("Picture") as MeshInstance3D).material_override as StandardMaterial3D
			var page_wait := 0.0
			print("WAITING for the sender page at %s" % main.get_node("ScreenFeed/CaptureServer").call("get_sender_url"))
			while mat_l.albedo_texture == null and page_wait < 90.0:
				await _secs(0.5)
				page_wait += 0.5
			_check(mat_l.albedo_texture != null, "a tab picked on the real sender page shows on the upper left screen (after %.1f s)" % page_wait)
			await _secs(1.0)
			await _shot(_out + "/forge_tab_screen.png")
		# the page says the row stopped sharing (or it disconnected): the screen goes dark
		var none: Array[bool] = []
		feeds.tabs_status(none)
		await _secs(0.2)
		_check((pic3.material_override as StandardMaterial3D).albedo_texture == null, "the screen goes dark when the page stops sharing")
		AppState.set_setting("forge_live_2_source", "off")
		AppState.set_setting("forge_live_3_source", "off")
		await _secs(0.3)
		_check(String((feeds.tab_wishes()[0] as Dictionary).get("kind")) == "off", "Off takes the row away again")
		# a stream address: ffmpeg reads it (here a short test clip it makes itself, which loops)
		var clip := _out + "/forge_test_clip.mp4"
		var made := OS.execute("ffmpeg" if feeds.call("_find_ffmpeg") == "ffmpeg" else String(feeds.call("_find_ffmpeg")),
			PackedStringArray(["-y", "-loglevel", "quiet", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=20", "-t", "2", "-pix_fmt", "yuv420p", clip])) \
			if String(feeds.call("_find_ffmpeg")) != "" else -1
		if made != 0:
			print("SKIP the stream address checks: no ffmpeg here (tools/get_tools.ps1 fetches it)")
		else:
			AppState.set_setting("forge_live_2_address", clip)
			AppState.set_setting("forge_live_2_source", "stream")
			var mat2 := (lives[1].get_node("Picture") as MeshInstance3D).material_override as StandardMaterial3D
			var waited := 0.0
			while mat2.albedo_texture == null and waited < 12.0:
				await _secs(0.25)
				waited += 0.25
			var stex := mat2.albedo_texture
			_check(stex != null and Vector2i(stex.get_size()) == ExtraFeeds.STREAM_SIZE, "a stream address shows on its screen (after %.1f s)" % waited)
			var before := stex.get_image().get_pixel(600, 20) if stex else Color.BLACK
			await _secs(0.7)
			var after := stex.get_image().get_pixel(600, 20) if stex else Color.BLACK
			_check(stex != null and stex.get_image().get_pixel(320, 180).get_luminance() > 0.02, "the picture isn't black")
			print("stream pixel before %s after %s" % [before, after])
			EventBus.camera_preset_requested.emit(0)
			await _secs(0.6)
			await _shot(_out + "/forge_stream_screen.png")
			# after a room change ExtraFeeds drops feeds nobody asks for again: the room asks again
			EventBus.room_changed.emit("forge_hall")
			await _secs(ExtraFeeds.STALE_S + 0.6)
			_check(feeds.get("_slots").has("forge_live_2") and (feeds.get("_slots")["forge_live_2"] as Dictionary)["tex"] == stex,
				"the stream keeps running through a room change that still wants it")
			AppState.set_setting("forge_live_2_source", "off")
			await _secs(0.5)
			_check(not feeds.get("_slots").has("forge_live_2"), "Off stops the stream")
		# the wall screens' place sliders; aligned, the right one mirrors the left one
		var l0: Vector3 = lives[1].global_position
		var r0: Vector3 = lives[2].global_position
		AppState.set_setting("forge_live_2_x", -0.5)
		AppState.set_setting("forge_live_2_y", 0.4)
		AppState.set_setting("forge_live_2_size", 1.5)
		AppState.set_setting("forge_live_2_tilt", 20.0)
		AppState.set_setting("forge_live_2_turn", 30.0)
		AppState.set_setting("forge_live_3_y", -1.0)       # ignored while aligned
		await _secs(0.3)
		var l1: Vector3 = lives[1].global_position
		var r1: Vector3 = lives[2].global_position
		_check((l1 - l0).is_equal_approx(Vector3(-0.5, 0.4, 0.0)), "the upper left screen moves with its sliders (%s)" % str(l1 - l0))
		_check((r1 - r0).is_equal_approx(Vector3(0.5, 0.4, 0.0)), "aligned, the upper right screen mirrors it (%s)" % str(r1 - r0))
		var lz: Vector3 = lives[1].global_basis.z.normalized()
		var rz: Vector3 = lives[2].global_basis.z.normalized()
		_check(absf(lives[1].global_basis.get_scale().x - 1.5) < 0.01 and lz.y < -0.2 and lz.x > 0.2 and absf(rz.x + lz.x) < 0.01 and absf(rz.y - lz.y) < 0.01,
			"size, tilt and turn apply, mirrored on the right (left faces %s, right %s)" % [str(lz.snappedf(0.01)), str(rz.snappedf(0.01))])
		AppState.set_setting("forge_live_2_source", "screen")
		AppState.set_setting("forge_live_3_source", "screen")
		EventBus.camera_preset_requested.emit(0)
		await _secs(0.8)
		await _shot(_out + "/forge_wall_screens_moved.png")
		AppState.set_setting("forge_live_align", false)
		await _secs(0.3)
		_check((lives[2].global_position - r0).is_equal_approx(Vector3(0.0, -1.0, 0.0)), "unticked, the right screen uses its own sliders")
		AppState.set_setting("forge_live_2_source", "off")
		AppState.set_setting("forge_live_3_source", "off")
		for part: String in ["x", "y", "tilt", "turn"]:
			AppState.set_setting("forge_live_2_%s" % part, 0.0)
		AppState.set_setting("forge_live_3_y", 0.0)
		AppState.set_setting("forge_live_2_size", 1.0)
		AppState.set_setting("forge_live_align", true)
		await _secs(0.3)
		# the upper screens sit lower on the wall than in round 3 (their middle under 9.6 m)
		_check(lives[1].global_position.y < 9.6 and lives[1].global_position.y > 8.9, "the upper screens sit lower (%.2f m)" % lives[1].global_position.y)

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
	NdiReceiver.mock_finder = null
	AppState.request_quit(0 if _fails == 0 else 1)
