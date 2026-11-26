extends Node
## Log Cabin (first layout pass): the room loads with everything its markers promise (the screen
## on the chimney, ten cameras with a Reaction one, four podium armchairs, 46 chat seats on the
## main floor, in the loft and on the deck, seven lamps, three reaction targets, two fires), and
## the Room tab's four controls do their job: Fire (flames, coals, the fires' light), Lamps (the
## house lights go out), Light outside (day / dusk / night: sun or moon, sky colours) and Gather
## in (Den reloads the room with the presenters on the den's sofa and armchair, the den's screen
## as the main one and its cameras first). The weather: rain, a storm (soft lightning in safe
## mode), snow (the outside panes frost, the windows into the den stay clear), the snow that fell
## melts within a minute of clearing, and fog.
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
	AppState.set_setting("cabin_time", 17.5)
	AppState.set_setting("cabin_day_minutes", 0.0)
	AppState.set_setting("cabin_clouds", 0.5)
	AppState.set_setting("cabin_stars", 1.0)
	AppState.set_setting("cabin_detail", "full")
	AppState.set_setting("cabin_weather", "clear")
	AppState.set_setting("cabin_fog", "off")
	AppState.set_setting("cabin_wind", 0.4)
	AppState.set_setting("cabin_snow", 0.0)
	AppState.set_setting("cabin_weather_fx", 1.0)
	AppState.set_setting("flash_strength", 1.0)
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

	# the audience: 46 seats, 18 on the main floor, 21 in the loft (three rows), 7 on the deck
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
	_check(seats.size() == 46, "46 chat seats at the default seat spacing (%d)" % seats.size())
	_check(floor_n == 18 and loft_n == 21 and deck_n == 7, "18 on the main floor, 21 in the loft, 7 on the deck (%d / %d / %d)" % [floor_n, loft_n, deck_n])

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
	_check(keys == ["cabin_detail", "cabin_fire", "cabin_lamps", "cabin_view", "cabin_time", "cabin_day_minutes", "cabin_clouds", "cabin_stars",
		"cabin_weather", "cabin_fog", "cabin_wind", "cabin_snow", "cabin_weather_fx"],
		"the Room tab gets Set detail, Fire, Lamps, Gather in, the time, the sky and the weather (%s)" % str(keys))
	var shared_ok := true
	for k in keys:
		shared_ok = shared_ok and (NetSession.SHARED_CABIN.has(k) != (k in ["cabin_detail", "cabin_weather_fx"]))
	_check(shared_ok, "every cabin setting but Set detail and Rain and snow amount is shared in a co-stream")
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
	var smoke := fx.find_children("ChimneySmoke*", "CPUParticles3D", false, false) if fx else []
	_check(smoke.size() == 2 and (smoke[0] as CPUParticles3D).emitting and (smoke[0] as CPUParticles3D).global_position.y > 10.0, "smoke rises from both chimney tops while the fire burns (%d)" % smoke.size())

	# Set detail: Detailed shows the photo textures and the leaf-card forest, Simple the cone trees
	var plants := room.find_child("DetailedPlants", true, false) as Node3D
	var cones := room.find_child("SimpleTrees", true, false) as Node3D
	var mats: Array = room.get("_parts")["detail_mats"]
	_check(plants != null and plants.visible and cones != null and not cones.visible and mats.size() > 10
		and float((mats[0] as ShaderMaterial).get_shader_parameter("detail")) > 0.5, "Detailed: photo textures on and the leaf-card forest showing (%d textured materials)" % mats.size())
	_check(plants != null and plants.find_children("*", "MultiMeshInstance3D", true, false).size() >= 4, "Detailed: trees, ferns and grass are planted round the clearing")
	AppState.set_setting("cabin_detail", "low")
	await _secs(0.5)
	_check(plants != null and not plants.visible and cones.visible and float((mats[0] as ShaderMaterial).get_shader_parameter("detail")) < 0.5, "Simple: flat colours and the plain cone trees")
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.2)
	await _shot(_out.path_join("cabin_simple_look.png"))
	AppState.set_setting("cabin_detail", "full")
	await _secs(0.5)

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

	# the time of day (the campfire's sky)
	var sun: DirectionalLight3D = room.call("get_sun")
	var dusk_energy := sun.light_energy
	var env: Environment = room.get_world_3d().environment
	var sky := env.sky.sky_material as ShaderMaterial if env and env.sky else null
	_check(sky != null and sky.shader == load("res://rooms/campfire/camp_sky.gdshader"), "the sky is the campfire's time-of-day sky")
	AppState.set_setting("cabin_time", 22.0)
	await _secs(0.5)
	_check(sun.light_energy < dusk_energy * 0.5 and float(room.call("get_daylight")) < 0.05, "22:00: night, the moon is much weaker than the evening sun (%.2f -> %.2f)" % [dusk_energy, sun.light_energy])
	_check(sky != null and float(sky.get_shader_parameter("day")) < 0.05, "22:00: the sky is drawn for night")
	EventBus.camera_preset_requested.emit(0)
	await _secs(2.5)
	await _shot(_out.path_join("cabin_night_loft.png"))
	EventBus.camera_preset_requested.emit(6)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_night_outside.png"))
	AppState.set_setting("cabin_time", 12.0)
	await _secs(2.5)
	_check(sun.light_energy > dusk_energy and float(room.call("get_daylight")) > 0.9, "Noon: a strong sun and full daylight")
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_day_loft.png"))
	EventBus.camera_preset_requested.emit(6)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_day_outside.png"))
	EventBus.camera_preset_requested.emit(4)
	await _secs(1.5)
	await _shot(_out.path_join("cabin_day_deck.png"))
	AppState.set_setting("cabin_day_minutes", 1.0)
	var h0: float = room.call("get_hour")
	await _secs(1.0)
	_check(float(room.call("get_hour")) > h0 + 0.1, "Day length: the clock runs (%.2f -> %.2f)" % [h0, float(room.call("get_hour"))])
	AppState.set_setting("cabin_day_minutes", 0.0)
	AppState.set_setting("cabin_time", 17.5)

	# the weather (rooms/weather/room_weather.gd)
	var weather: Node = fx.find_child("Weather", false, false) if fx else null
	_check(weather != null, "the weather module is in the room")
	if weather != null:
		var glass := room.get("_parts")["glass_mat"] as ShaderMaterial
		var surf0 := mats[0] as ShaderMaterial
		AppState.set_setting("cabin_weather", "rain")
		await _secs(0.3)
		weather.call("settle")
		await _secs(1.0)
		var rain_p := weather.call("get_rain") as GPUParticles3D
		_check(rain_p.emitting and float(glass.get_shader_parameter("wet")) > 0.4 and float(surf0.get_shader_parameter("wet")) > 0.4,
			"Rain: it rains, the glass and the outside get wet (%.2f / %.2f)" % [float(glass.get_shader_parameter("wet")), float(surf0.get_shader_parameter("wet"))])
		_check(float(sky.get_shader_parameter("cloud_amount")) >= 1.69, "Rain: the sky clouds over (%.2f)" % float(sky.get_shader_parameter("cloud_amount")))
		EventBus.camera_preset_requested.emit(2)
		await _secs(2.0)
		await _shot(_out.path_join("weather_rain_sofa.png"))
		EventBus.camera_preset_requested.emit(6)
		await _secs(1.5)
		await _shot(_out.path_join("weather_rain_outside.png"))
		# a stormy night: lightning, strong wind; soft and capped in photosensitive-safe mode
		AppState.set_setting("cabin_time", 21.5)
		AppState.set_setting("cabin_weather", "storm")
		await _secs(0.5)
		_check(float(weather.call("wind")) >= 1.4, "Storm: the wind blows at least 140%% (%.2f)" % float(weather.call("wind")))
		weather.call("strike")
		await _secs(0.1)
		var full_flash := float(weather.call("flash"))
		_check(full_flash > 0.5, "Storm: lightning flashes (%.2f)" % full_flash)
		AppState.set_setting("photosensitive_safe", true)
		await _secs(1.5)
		weather.call("strike")
		await _secs(0.1)
		_check(float(weather.call("flash")) <= 0.31, "Photosensitive-safe: the lightning stays soft (%.2f)" % float(weather.call("flash")))
		AppState.set_setting("photosensitive_safe", false)
		EventBus.camera_preset_requested.emit(1)
		await _secs(2.0)
		await _shot(_out.path_join("weather_storm_night_hearth.png"))
		EventBus.camera_preset_requested.emit(2)
		await _secs(1.5)
		await _shot(_out.path_join("weather_storm_night_sofa.png"))
		# snow by day, with snow lying
		AppState.set_setting("cabin_time", 11.0)
		AppState.set_setting("cabin_weather", "snow")
		AppState.set_setting("cabin_snow", 0.8)
		await _secs(0.3)
		weather.call("settle")
		await _secs(1.5)
		var snow_p := weather.call("get_snow") as GPUParticles3D
		_check(snow_p.emitting and not rain_p.emitting, "Snow: flakes fall, the rain has stopped")
		_check(float(surf0.get_shader_parameter("snow")) >= 0.79 and float(glass.get_shader_parameter("frost")) > 0.9,
			"Snow: snow lies outside and the glass frosts (%.2f / %.2f)" % [float(surf0.get_shader_parameter("snow")), float(glass.get_shader_parameter("frost"))])
		# the windows between the great room and the den are indoors: never frosted or wet
		var inside_glass := room.get("_parts")["inside_glass_mat"] as ShaderMaterial
		# (a value never set reads back as null: count that as 0)
		var in_frost: Variant = inside_glass.get_shader_parameter("frost")
		var in_wet: Variant = inside_glass.get_shader_parameter("wet")
		var in_f := float(in_frost) if in_frost != null else 0.0
		var in_w := float(in_wet) if in_wet != null else 0.0
		_check(in_f < 0.01 and in_w < 0.01, "Snow: the windows into the den stay clear (frost %.2f)" % in_f)
		EventBus.camera_preset_requested.emit(6)
		await _secs(2.0)
		await _shot(_out.path_join("weather_snow_outside.png"))
		EventBus.camera_preset_requested.emit(0)
		await _secs(1.5)
		await _shot(_out.path_join("weather_snow_loft.png"))
		EventBus.camera_preset_requested.emit(4)
		await _secs(1.5)
		await _shot(_out.path_join("weather_snow_deck.png"))
		# heavy fog at dusk
		AppState.set_setting("cabin_weather", "cloudy")
		AppState.set_setting("cabin_snow", 0.0)
		AppState.set_setting("cabin_fog", "heavy")
		AppState.set_setting("cabin_time", 17.5)
		await _secs(1.0)
		_check(env.fog_mode == Environment.FOG_MODE_DEPTH and env.fog_depth_end < 40.0, "Heavy fog: fog by distance, the inside stays clear (ends at %.0f m)" % env.fog_depth_end)
		EventBus.camera_preset_requested.emit(6)
		await _secs(1.5)
		await _shot(_out.path_join("weather_fog_outside.png"))
		EventBus.camera_preset_requested.emit(0)
		await _secs(1.5)
		await _shot(_out.path_join("weather_fog_loft.png"))
		AppState.set_setting("cabin_fog", "off")
		AppState.set_setting("cabin_weather", "clear")
		await _secs(0.5)
		# the snow that fell melts within about a minute once the weather clears (it once took ten)
		AppState.set_setting("cabin_weather", "snow")
		weather.call("settle")
		AppState.set_setting("cabin_weather", "clear")
		for i in 65:
			weather.call("run", 1.0)
		_check(float(weather.call("snow_cover")) < 0.02, "Clear: the snow that fell has melted a minute later (%.2f)" % float(weather.call("snow_cover")))
		# (fog_density too: switching fog_mode resets it to 1.0, which once drowned clear days in fog)
		_check(env.fog_mode == Environment.FOG_MODE_EXPONENTIAL and env.fog_density < 0.01,
			"Clear: the fog is back to the room's own thin haze (density %.4f)" % env.fog_density)

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
		_check(den.get_audience_seats().size() == 46, "Den: chat keeps its 46 seats (%d)" % den.get_audience_seats().size())
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
