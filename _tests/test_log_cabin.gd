extends Node
## Log Cabin (first layout pass): the room loads with everything its markers promise (the screen
## on the chimney, ten cameras with a Reaction one, four podium armchairs, 30 chat seats on the
## main floor, in the loft and on the deck, seven lamps, three reaction targets, two fires), and
## the Room tab's four controls do their job: Fire (flames, coals, the fires' light), Lamps (the
## house lights go out), Light outside (day / dusk / night: sun or moon, sky colours) and Gather
## in (Den reloads the room with the presenters on the den's sofa and armchair, the den's screen
## as the main one and its cameras first).
## Saves one screenshot per camera, the dusk / night / day looks and the den's cameras into the output folder (look
## at them: the look is not checked here).
##   <redot console exe> --path . _tests/test_log_cabin.tscn -- C:/temp/sr_tests --mp-profile=test

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


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("audience_seat_gap", 1.0)
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("cabin_fire", 1.0)
	AppState.set_setting("cabin_lamps", true)
	AppState.set_setting("cabin_light", "dusk")
	AppState.set_setting("cabin_view", "great_room")
	AppState.set_setting("curtain_enabled", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("log_cabin")
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "LogCabinRoom", "the Log Cabin loaded (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return

	# the markers
	var screen := room.find_screen()
	_check(screen != null, "TVScreen is there")
	_check(screen != null and screen.global_position.z > 0.5 and screen.global_position.y > 2.0,
		"the screen hangs on the chimney's room side, above the mantel (%s)" % (str(screen.global_position) if screen else "-"))
	var cams := room.get_camera_markers()
	var reaction := false
	for c in cams:
		if String(c.name).contains("Reaction"):
			reaction = true
	_check(cams.size() == 10 and reaction, "ten camera presets, one of them the Reaction camera (%d)" % cams.size())
	_check(cams.size() > 0 and room.get_camera_label(cams[0]) == "Loft", "the first camera is the Loft (%s)" % (room.get_camera_label(cams[0]) if cams.size() > 0 else "-"))
	var pres := room.get_presenter_setups()
	var podiums := 0
	for p in pres:
		podiums += 1 if p["podium"] != null else 0
	_check(pres.size() == 4 and podiums == 4, "four presenter spots, each with its armchair (%d / %d)" % [pres.size(), podiums])
	_check(room.find_children("TARGET_*", "Node3D", true, false).size() == 3, "three reaction targets (fireplace, chandelier, deck)")
	_check(room.get_webcam_marker() == null, "no webcam frame (the webcam uses the corner overlay)")
	var lamps := room.find_child("LIGHTS_House", false, false)
	_check(lamps != null and lamps.find_children("*", "OmniLight3D", true, false).size() == 7, "seven lamps under LIGHTS_House (five in the great room, two in the den)")

	# the audience: 30 seats, 18 on the main floor, 5 in the loft, 7 on the deck
	var seats := room.get_audience_seats()
	var floor_n := 0
	var loft_n := 0
	var deck_n := 0
	for t in seats:
		var p := room.to_local(t.origin)
		if p.y > 2.5:
			loft_n += 1
		elif p.z < 0.0:
			deck_n += 1
		else:
			floor_n += 1
	_check(seats.size() == 30, "30 chat seats at the default seat spacing (%d)" % seats.size())
	_check(floor_n == 18 and loft_n == 5 and deck_n == 7, "18 on the main floor, 5 in the loft, 7 on the deck (%d / %d / %d)" % [floor_n, loft_n, deck_n])

	# the fire
	var fx := room.find_child("SunShafts", false, false)
	var flames := fx.find_children("FireFlame*", "MeshInstance3D", false, false) if fx else []
	var fire_light: OmniLight3D = room.call("get_fire_light")
	var fire_lights: Array = room.call("get_fire_lights")
	_check(flames.size() == 10 and fire_lights.size() == 2 and fire_light != null and fire_light.visible, "two fires (great room, den): ten flames and two lights (%d / %d)" % [flames.size(), fire_lights.size()])
	_check(fire_lights.size() == 2 and (fire_lights[1] as OmniLight3D).global_position.x < -10.0, "the den's fire light is in the den (%s)" % (str((fire_lights[1] as OmniLight3D).global_position) if fire_lights.size() == 2 else "-"))
	_check(not room.get_static_meshes().has(flames[0] if flames.size() > 0 else null), "the flames are not counted as the room's own meshes")
	var keys: Array[String] = []
	for c in room.get_controls():
		if c.has("key"):
			keys.append(String(c["key"]))
	_check(keys == ["cabin_fire", "cabin_lamps", "cabin_light", "cabin_view"], "the Room tab gets Fire, Lamps, Light outside and Gather in (%s)" % str(keys))
	_check(room.reload_keys().has("cabin_view"), "Gather in reloads the room")
	_check(room.get_mirror_screens().size() == 1, "the den's screen mirrors the big one (%d mirror)" % room.get_mirror_screens().size())
	var energy := fire_light.light_energy
	AppState.set_setting("cabin_fire", 2.0)
	await _secs(0.3)
	_check(fire_light.light_energy > energy * 1.4, "Fire 200%% makes the light stronger (%.2f -> %.2f)" % [energy, fire_light.light_energy])
	AppState.set_setting("cabin_fire", 0.0)
	await _secs(0.3)
	_check(not fire_light.visible and not (flames[0] as MeshInstance3D).visible, "Fire 0 puts the fire out")
	AppState.set_setting("cabin_fire", 1.0)
	await _secs(0.3)

	# the lamps (house lights) go out with their tick box
	var lamp := lamps.find_children("*", "OmniLight3D", true, false)[0] as OmniLight3D
	await _secs(2.0)
	_check(lamp.visible and lamp.light_energy > 0.1, "the lamps are lit at dusk (%.2f)" % lamp.light_energy)
	AppState.set_setting("cabin_lamps", false)
	await _secs(2.5)
	_check(not lamp.visible or lamp.light_energy < 0.02, "Lamps off puts them out (%.2f)" % lamp.light_energy)
	AppState.set_setting("cabin_lamps", true)
	await _secs(2.5)

	# the screenshots: every camera at dusk
	for i in cams.size():
		EventBus.camera_preset_requested.emit(i)
		await _secs(1.2)
		await _shot(_out.path_join("cabin_%02d_%s.png" % [i + 1, room.get_camera_label(cams[i]).replace(" ", "_")]))

	# the light outside
	var sun: DirectionalLight3D = room.call("get_sun")
	var dusk_energy := sun.light_energy
	AppState.set_setting("cabin_light", "night")
	await _secs(0.5)
	var env: Environment = room.get_world_3d().environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial if env and env.sky else null
	_check(sun.light_energy < dusk_energy * 0.5, "Night: the moon is much weaker than the dusk sun (%.2f -> %.2f)" % [dusk_energy, sun.light_energy])
	_check(sky != null and sky.sky_top_color.v < 0.1, "Night: the sky is dark (%s)" % (str(sky.sky_top_color) if sky else "no sky"))
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_night_loft.png"))
	EventBus.camera_preset_requested.emit(6)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_night_outside.png"))
	AppState.set_setting("cabin_light", "day")
	await _secs(2.5)
	_check(sun.light_energy > dusk_energy and sky != null and sky.sky_top_color.b > 0.6, "Day: a strong sun and a blue sky")
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_day_loft.png"))
	EventBus.camera_preset_requested.emit(6)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_day_outside.png"))
	EventBus.camera_preset_requested.emit(4)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_day_deck.png"))
	AppState.set_setting("cabin_light", "dusk")

	# Gather in: Den. The room reloads; fetch the new one.
	AppState.set_setting("cabin_view", "den")
	await _secs(6.0)
	AppState.set_curtain(false, "instant")
	var den: Room = host.get_current_room()
	_check(den != null and den != room, "Gather in: Den reloads the room")
	if den != null and den != room:
		var dscreen := den.find_screen()
		_check(dscreen != null and dscreen.global_position.x < -11.0, "Den: the main screen is the den's, above its mantel (%s)" % (str(dscreen.global_position) if dscreen else "-"))
		_check(den.get_mirror_screens().size() == 1, "Den: the great room's screen mirrors it")
		var dcams := den.get_camera_markers()
		var dreact := 0
		for c in dcams:
			dreact += 1 if String(c.name).contains("Reaction") else 0
		_check(dcams.size() == 14 and dreact == 1, "Den: fourteen cameras, one Reaction camera (%d / %d)" % [dcams.size(), dreact])
		_check(dcams.size() > 0 and den.get_camera_label(dcams[0]) == "Den Fireside", "Den: the first camera is Den Fireside (%s)" % (den.get_camera_label(dcams[0]) if dcams.size() > 0 else "-"))
		var dpres := den.get_presenter_setups()
		var in_den := 0
		var with_podium := 0
		for p in dpres:
			var m := p["marker"] as Node3D if p.has("marker") else null
			in_den += 1 if m != null and m.global_position.x < -7.0 and m.global_position.y > 0.3 else 0
			with_podium += 1 if p["podium"] != null else 0
		_check(dpres.size() == 4 and in_den == 4 and with_podium == 0, "Den: four presenters on the sofa and armchair, no podium chairs (%d / %d / %d)" % [dpres.size(), in_den, with_podium])
		_check(den.get_audience_seats().size() == 30, "Den: chat keeps its 30 seats (%d)" % den.get_audience_seats().size())
		for i in 4:
			EventBus.camera_preset_requested.emit(i)
			await _secs(1.2)
			await _shot(_out.path_join("den_%02d_%s.png" % [i + 1, den.get_camera_label(dcams[i]).replace(" ", "_")]))
		EventBus.camera_preset_requested.emit(10)
		await _secs(1.2)
		await _shot(_out.path_join("den_outside_gable.png"))
	AppState.set_setting("cabin_view", "great_room")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
