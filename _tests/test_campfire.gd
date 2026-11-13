extends Node
## Lakeside Campfire: the room loads with everything its markers promise (screen, ten cameras,
## four camp chairs, 30 bench seats in three rows, three reaction targets) and the Room tab's
## controls do their job: Fire, Big screen (hides the screen and what hangs on it), String
## lights, Time of day and Day length (sky, sun and moon), Clouds / Stars / Aurora / Mist, Rain
## and Thunderstorm (clouds roll in, rain falls, lightning strikes within the flash-safety
## limits). The fire games: roasting a marshmallow (browning, the golden s'more, catching fire),
## tossing a stick (the fire flares), the same arriving from a co-stream guest
## (EventBus.net_room_event), and a chat reaction thrown at the campfire.
## Saves one screenshot per camera and a few of the other looks into the output folder (look at
## them: the look is not checked here).
##   <redot console exe> --path . _tests/test_campfire.tscn -- C:/temp/sr_tests --mp-profile=test

## The room's and the games' scripts, for their constants and static functions (no class names).
const CF := preload("res://rooms/campfire/campfire_room.gd")
const GAMES := preload("res://rooms/campfire/campfire_games.gd")
var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/" + shot_name + ".png")


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("audience_seat_gap", 1.0)
	AppState.set_setting("curtain_enabled", true)
	AppState.set_setting("flash_strength", 1.0)
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("reactions_enabled", true)
	AppState.set_setting("camp_fire", 1.0)
	AppState.set_setting("camp_screen", true)
	AppState.set_setting("camp_time", 18.6)
	AppState.set_setting("camp_day_minutes", 0.0)
	AppState.set_setting("camp_clouds", 0.7)
	AppState.set_setting("camp_stars", 1.0)
	AppState.set_setting("camp_aurora", 0.0)
	AppState.set_setting("camp_mist", 0.4)
	AppState.set_setting("camp_rain", 0.0)
	AppState.set_setting("camp_storm", false)
	AppState.set_setting("camp_close_woods", false)
	AppState.set_setting("camp_string_lights", true)
	AppState.set_setting("camp_fireflies", true)
	AppState.set_setting("camp_games", true)
	for n in range(1, 5):
		AppState.set_setting(AppState.presenter_key(n, "on"), n <= 2)
		AppState.set_setting(AppState.presenter_key(n, "source"), "silhouette")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("campfire")
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "CampfireRoom", "the Lakeside Campfire loaded (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return

	# ── the markers ──
	var screen := room.find_screen()
	_check(screen != null and screen.visible, "TVScreen is there and showing")
	var cams := room.get_camera_markers()
	var reaction := false
	for c in cams:
		if String(c.name).contains("Reaction"):
			reaction = true
	_check(cams.size() == 10 and reaction, "ten camera views, one of them the Reaction camera (%d)" % cams.size())
	_check(room.get_camera_label(cams[0]) == "Campfire", "the first camera is Campfire (%s)" % room.get_camera_label(cams[0]))
	var pres := room.get_presenter_setups()
	var chairs := 0
	for p in pres:
		chairs += 1 if p["podium"] != null else 0
	_check(pres.size() == 4 and chairs == 4, "four presenter spots, each with a camp chair (%d / %d)" % [pres.size(), chairs])
	var fire_marker := room.find_child("FIRE_Camp", true, false) as Node3D
	var far_side := true
	for p in pres:
		var m := p["marker"] as Node3D
		far_side = far_side and m.global_position.z < fire_marker.global_position.z and m.global_basis.z.z > 0.3
	_check(far_side, "the chairs are on the far side of the fire, facing the main camera")
	_check(room.find_children("TARGET_*", "Node3D", true, false).size() == 3, "three reaction targets (campfire, lake, tent)")
	var seats := room.get_audience_seats()
	_check(seats.size() == 30, "30 chat seats at the default seat spacing (%d)" % seats.size())
	var near_side := true
	for t in seats:
		near_side = near_side and t.origin.z > fire_marker.global_position.z + 1.0
	_check(near_side, "every bench seat is on the near side of the fire")
	_check(room.get_static_meshes().size() >= 8, "the built set counts as the room's own meshes (%d)" % room.get_static_meshes().size())
	var firs := room.find_child("Firs", true, false) as MultiMeshInstance3D
	_check(firs != null and firs.multimesh.instance_count > 150, "a forest of firs (%d)" % (firs.multimesh.instance_count if firs else 0))

	# ── the Room tab ──
	var keys: Array[String] = []
	for c in room.get_controls():
		if c.has("key"):
			keys.append(String(c["key"]))
	var wanted: Array[String] = ["camp_fire", "camp_screen", "camp_close_woods", "camp_string_lights", "camp_fireflies", "camp_games", "camp_time", "camp_day_minutes",
		"camp_clouds", "camp_stars", "camp_aurora", "camp_mist", "camp_rain", "camp_storm"]
	var all_there := true
	for k in wanted:
		all_there = all_there and keys.has(k) and AppState.DEFAULTS.has(k)
	_check(all_there, "the Room tab gets every camp_ control, each with a default (%s)" % str(keys))
	var shared := true
	for k: String in ["camp_fire", "camp_screen", "camp_time", "camp_rain", "camp_storm", "camp_close_woods"]:
		shared = shared and NetSession.is_shared(k)
	_check(shared and not NetSession.is_shared("camp_games"), "the fire, screen, hour and weather are shared in a co-stream; the games tick box is each PC's own")

	# ── the fire ──
	var fx := room.find_child("SunShafts", false, false)
	var flames := fx.find_children("FireFlame*", "MeshInstance3D", false, false)
	var fire_light := room.find_child("FireLight", false, false) as OmniLight3D
	var sparks := fx.get_node_or_null("FireSparks") as CPUParticles3D
	_check(flames.size() == 7 and fire_light != null and fire_light.visible and sparks != null and sparks.emitting, "seven flames, the fire's light and sparks (%d)" % flames.size())
	_check(not room.get_static_meshes().has(flames[0]), "the flames are not counted as the room's own meshes")
	_check(is_equal_approx(float(room.call("get_fire_amount")), 1.0), "Fire 100%% on a dry evening burns at 1.0 (%.2f)" % float(room.call("get_fire_amount")))
	AppState.set_setting("camp_fire", 0.0)
	await _secs(0.3)
	_check(not (flames[0] as MeshInstance3D).visible and not fire_light.visible and not sparks.emitting, "Fire 0% puts it out: no flames, light or sparks")
	room.call("flare", 1.0)
	_check(is_zero_approx(float(room.call("get_flare"))), "a stick on a dead fire does nothing")
	AppState.set_setting("camp_fire", 1.0)
	await _secs(0.3)

	# ── screenshots of every camera at dusk ──
	for i in cams.size():
		EventBus.camera_preset_requested.emit(i)
		await _secs(1.2)
		await _shot("camp_%s" % String(cams[i].name).trim_prefix("CAM_"))
	EventBus.camera_preset_requested.emit(0)

	# ── the big screen ──
	var lights := room.get_node_or_null("ScreenLights") as Node3D
	_check(lights != null and lights.visible, "the screen's lights are on with the screen")
	AppState.set_setting("camp_screen", false)
	await _secs(0.5)
	_check(not screen.visible and not lights.visible, "Big screen off hides the screen and its lights")
	AppState.set_curtain(true, "instant")
	await _secs(0.5)
	var curtain := room.get_node_or_null("StageCurtain") as Node3D
	_check(curtain == null or not curtain.visible, "closing the curtain while the screen is off shows nothing")
	AppState.set_curtain(false, "instant")
	await _secs(1.0)
	await _shot("camp_screen_off")
	AppState.set_setting("camp_screen", true)
	await _secs(0.5)
	_check(screen.visible and lights.visible, "Big screen on brings them back")

	# ── the close woods ──
	var close_firs := room.find_child("CloseFirs", true, false) as MultiMeshInstance3D
	var close_round := room.find_child("CloseRoundTrees", true, false) as MultiMeshInstance3D
	_check(close_firs != null and close_round != null and not close_firs.visible and not close_round.visible,
		"the close woods are built and hidden by default")
	AppState.set_setting("camp_close_woods", true)
	await _secs(0.3)
	_check(close_firs.visible and close_round.visible, "Woods close around the camp shows them")
	_check(close_firs.multimesh.instance_count > 120, "the close woods are dense (%d firs, %d round trees)" % [close_firs.multimesh.instance_count, close_round.multimesh.instance_count])
	# no trunk stands on a camera, and behind the screen the wall has no gap wider than 1.2 m
	# (young firs, under 4 m, are left out of the count: the tall ones must do it alone)
	var clear := true
	var wall_xs: Array[float] = []
	for i in close_firs.multimesh.instance_count:
		var at := close_firs.multimesh.get_instance_transform(i).origin
		for cam in cams:
			if Vector2(at.x - cam.position.x, at.z - cam.position.z).length() < 1.2:
				clear = false
		if at.z < -7.0 and absf(at.x) < 6.0 and close_firs.multimesh.get_instance_transform(i).basis.get_scale().y > 4.0:
			wall_xs.append(at.x)
	_check(clear, "no close tree stands on a camera")
	wall_xs.sort()
	var widest := 0.0
	for i in wall_xs.size() - 1:
		widest = maxf(widest, wall_xs[i + 1] - wall_xs[i])
	_check(wall_xs.size() > 15 and widest < 1.2, "a wall of firs behind the screen hides the lake (%d trees, widest gap %.2f m)" % [wall_xs.size(), widest])
	# the horseshoe: tall firs stand down both sides, between the screen and the benches' ends
	var sides := [0, 0]
	for i in close_firs.multimesh.instance_count:
		var xf := close_firs.multimesh.get_instance_transform(i)
		var from_fire := Vector2(xf.origin.x, xf.origin.z).length()
		if xf.basis.get_scale().y > 4.0 and xf.origin.z > -6.5 and xf.origin.z < 6.5 and from_fire < 10.2 and absf(xf.origin.x) > 5.0:
			sides[0 if xf.origin.x < 0.0 else 1] += 1
	_check(sides[0] > 10 and sides[1] > 10, "trees wall in both sides of the fire, a cul-de-sac (%d left, %d right)" % sides)
	await _shot("camp_woods")
	AppState.set_setting("camp_screen", false)
	await _secs(0.5)
	await _shot("camp_woods_screen_off")
	AppState.set_setting("camp_screen", true)
	AppState.set_setting("camp_time", 12.0)
	await _secs(2.5)
	for i in cams.size():
		EventBus.camera_preset_requested.emit(i)
		await _secs(1.2)
		await _shot("camp_woods_noon_%s" % String(cams[i].name).trim_prefix("CAM_"))
	EventBus.camera_preset_requested.emit(0)
	AppState.set_setting("camp_time", 18.6)
	AppState.set_setting("camp_close_woods", false)
	await _secs(0.5)
	_check(not close_firs.visible, "and off hides them again")

	# ── the hour ──
	var env := room.get_world_3d().environment
	var sky := env.sky.sky_material as ShaderMaterial
	var sun := room.find_child("SunMoon", false, false) as DirectionalLight3D
	_check(sky != null and sky.shader == CF.SKY_SHADER, "the room's own sky shader is in use")
	_check(float(sky.get_shader_parameter("day")) < 0.05 and float(sky.get_shader_parameter("dusk")) > 0.2,
		"18.6 h is dusk: night sky with a sunset glow (day %.2f, dusk %.2f)" % [float(sky.get_shader_parameter("day")), float(sky.get_shader_parameter("dusk"))])
	AppState.set_setting("camp_time", 12.0)
	await _secs(2.5)
	_check(is_equal_approx(float(sky.get_shader_parameter("day")), 1.0) and sun.visible and sun.light_energy > 1.0 and sun.global_basis.z.y > 0.8,
		"noon: full day, the sun high overhead (energy %.2f)" % sun.light_energy)
	var lamp := room.find_child("LAMP_String_1", true, false).get_child(0) as OmniLight3D
	var lamp_noon := lamp.light_energy
	await _shot("camp_noon")
	EventBus.camera_preset_requested.emit(5)
	await _secs(1.2)
	await _shot("camp_noon_lake")
	AppState.set_setting("camp_time", 0.0)
	AppState.set_setting("camp_aurora", 1.0)
	await _secs(3.0)
	_check(is_zero_approx(float(sky.get_shader_parameter("day"))) and sun.visible and sun.light_color.b > sun.light_color.r and sun.light_energy < 0.4,
		"midnight: night, lit by a blue moon (energy %.2f)" % sun.light_energy)
	_check((sky.get_shader_parameter("moon_dir") as Vector3).z < -0.3, "the moon stands over the lake")
	_check(lamp.light_energy > lamp_noon * 2.0, "the string lights burn brighter at night than at noon (%.2f / %.2f)" % [lamp.light_energy, lamp_noon])
	_check(is_equal_approx(float(sky.get_shader_parameter("aurora_amount")), 1.0), "the Aurora slider reaches the sky")
	var flies := fx.get_node_or_null("Fireflies") as CPUParticles3D
	_check(flies != null and flies.emitting, "fireflies are out on a dry night")
	await _shot("camp_midnight_lake")
	EventBus.camera_preset_requested.emit(9)
	await _secs(1.2)
	await _shot("camp_midnight_sky")
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.2)
	await _shot("camp_midnight")
	AppState.set_setting("camp_string_lights", false)
	await _secs(3.0)
	_check(lamp.light_energy < 0.01 or not lamp.visible, "String lights off puts the lamps out")
	AppState.set_setting("camp_string_lights", true)
	AppState.set_setting("camp_aurora", 0.0)
	# the clock runs
	AppState.set_setting("camp_time", 6.0)
	AppState.set_setting("camp_day_minutes", 1.0)        # a day a minute: 0.4 h a second
	await _secs(2.0)
	var hour := float(room.call("get_hour"))
	_check(hour > 6.5 and hour < 7.3, "Day length 1 min moves the clock about 0.8 h in 2 s (%.2f)" % hour)
	AppState.set_setting("camp_day_minutes", 0.0)
	await _shot("camp_sunrise")
	AppState.set_setting("camp_time", 17.6)
	await _secs(0.5)
	EventBus.camera_preset_requested.emit(5)
	await _secs(1.2)
	await _shot("camp_sunset_lake")
	EventBus.camera_preset_requested.emit(0)

	# ── the weather ──
	AppState.set_setting("camp_time", 15.0)
	room.set("weather_seconds", 1.0)          # (roll in fast for the test)
	AppState.set_setting("camp_rain", 0.6)
	await _secs(2.0)
	var rain := fx.get_node_or_null("Rain") as GPUParticles3D
	_check(rain != null and rain.emitting and is_equal_approx(rain.amount_ratio, 0.6), "Rain 60%% shows 60%% of the drops (%.2f)" % (rain.amount_ratio if rain else -1.0))
	_check(float(room.call("get_gloom")) > 0.6 and float(sky.get_shader_parameter("storm")) > 0.6, "the clouds close in with the rain (%.2f)" % float(room.call("get_gloom")))
	_check(float(room.call("get_fire_amount")) < 0.8, "rain takes the fire down (%.2f)" % float(room.call("get_fire_amount")))
	var ground := (room.find_child("Ground", true, false) as MeshInstance3D).material_override as ShaderMaterial
	_check(is_equal_approx(float(ground.get_shader_parameter("wet")), 0.6), "the ground is wet")
	await _shot("camp_rain_day")
	AppState.set_setting("camp_rain", 0.0)
	AppState.set_setting("camp_storm", true)
	AppState.set_setting("camp_time", 21.0)
	await _secs(2.0)
	_check(float(room.call("get_rain")) >= 0.79 and is_equal_approx(float(room.call("get_gloom")), 1.0), "a thunderstorm brings heavy rain and full storm cloud by itself (%.2f)" % float(room.call("get_rain")))
	room.call("strike")
	await get_tree().process_frame
	await get_tree().process_frame
	var bolt := room.find_child("Lightning", false, false) as DirectionalLight3D
	var peak := float(room.call("get_flash"))
	_check(peak > 0.5 and bolt.visible and float(sky.get_shader_parameter("flash")) > 0.5, "lightning lights the sky and the camp (%.2f)" % peak)
	await _shot("camp_lightning")
	await _secs(1.0)
	_check(is_zero_approx(float(room.call("get_flash"))) and not bolt.visible, "and is gone within a second")
	AppState.set_setting("flash_strength", 0.25)
	room.call("strike")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(float(room.call("get_flash")) <= 0.25, "Flash strength 25%% caps the flash (%.2f)" % float(room.call("get_flash")))
	await _secs(1.0)
	AppState.set_setting("flash_strength", 1.0)
	AppState.set_setting("photosensitive_safe", true)
	room.call("strike")
	var safe_peak := 0.0
	var safe_first := -1.0
	for i in 90:
		await get_tree().process_frame
		if safe_first < 0.0:
			safe_first = float(room.call("get_flash"))
		safe_peak = maxf(safe_peak, float(room.call("get_flash")))
	_check(safe_peak <= CF.SAFE_FLASH_CAP + 0.001 and safe_first < 0.1, "in safe mode a strike is a slow swell, never above 30%% (starts %.2f, peaks %.2f)" % [safe_first, safe_peak])
	room.call("flare", 1.0)
	await _secs(0.2)
	_check(float(room.call("get_fire_amount")) < float(AppState.get_setting("camp_fire")) + CF.SAFE_FLASH_CAP, "and a flare grows slowly too")
	AppState.set_setting("photosensitive_safe", false)
	await _secs(3.0)
	await _shot("camp_storm_night")
	AppState.set_setting("camp_storm", false)
	AppState.set_setting("camp_time", 18.6)
	await _secs(2.5)
	_check(not rain.emitting and is_zero_approx(float(room.call("get_gloom"))), "the storm clears")
	await _secs(6.0)       # (the last flare dies down)

	# ── the fire games ──
	var games := fx.get_node_or_null("FireGames")
	_check(games != null, "the fire games are there")
	games.call("set_roasting", true)
	await _secs(1.2)
	var me: Dictionary = games.call("get_person", 0)
	var rig := me["root"] as Node3D
	var mallow := me["mallow"] as MeshInstance3D
	_check(rig.visible and int(me["n"]) == 1 and float(me["out"]) > 0.95, "holding M puts a stick out from podium 1's avatar")
	_check(Vector2(mallow.global_position.x, mallow.global_position.z).length() < 0.6 and mallow.global_position.y > 0.5,
		"the marshmallow hangs over the fire (%s)" % str(mallow.global_position))
	_check(float(me["toast"]) > 0.05 and float(me["toast"]) < 0.3, "it has started to brown (%.2f)" % float(me["toast"]))
	EventBus.camera_preset_requested.emit(7)
	games.call("set_toast", 0.8)
	await _secs(1.2)
	await _shot("camp_roasting_golden")
	games.call("set_roasting", false)
	await _secs(0.3)
	var word := me["word"] as Label3D
	_check(int(me["smores"]) == 1 and word.visible and word.text.begins_with("Golden"), "letting go while it is golden makes a s'more (%s)" % word.text)
	await _shot("camp_smore")
	await _secs(1.5)
	games.call("set_roasting", true)
	await _secs(1.0)
	_check(float(me["toast"]) < 0.3, "the next one starts white again (%.2f)" % float(me["toast"]))
	games.call("set_toast", 1.35)
	await _secs(0.3)
	_check(bool(me["flaming"]) and (me["flame"] as MeshInstance3D).visible, "left too long it catches fire")
	await _shot("camp_roasting_on_fire")
	games.call("set_roasting", false)
	await _secs(0.3)
	_check(int(me["smores"]) == 1 and word.text.begins_with("Burnt"), "and that is no s'more (%s)" % word.text)
	_check(GAMES.result_word(0.1) == "Still cold" and GAMES.result_word(1.1).begins_with("A bit burnt"), "the other results have their words")
	# tossing a stick
	games.call("toss_stick")
	games.call("toss_stick")
	await _secs(0.3)
	_check(fx.find_children("TossedStick*", "MeshInstance3D", true, false).size() == 1, "T sends a stick flying, and a second press straight after is held back")
	await _shot("camp_stick_flying")
	await _secs(0.7)
	var flared := float(room.call("get_flare"))
	_check(flared > 0.4 and float(room.call("get_fire_amount")) > 1.2, "the fire flares when it lands (%.2f)" % flared)
	await _shot("camp_flare")
	await _secs(5.5)
	_check(float(room.call("get_flare")) < 0.05, "the flare dies down again")
	# a co-stream guest's (the checked packets NetSession hands on)
	_check(NetSession.room_event_ok("roast", [2, true, 0.5, false]) and NetSession.room_event_ok("stick", [2]), "the games' packets pass the network's shape check")
	_check(not NetSession.room_event_ok("bad name!", []) and not NetSession.room_event_ok("x", [[1]]) and not NetSession.room_event_ok("x", [1, 2, 3, 4, 5, 6, 7, 8, 9])
		and not NetSession.room_event_ok("x", [NAN]), "and odd ones do not")
	EventBus.net_room_event.emit(77, "Guest", "roast", [2, true, 0.9, false])
	await _secs(1.0)
	var guest: Dictionary = games.call("get_person", 77)
	_check(not guest.is_empty() and (guest["root"] as Node3D).visible and int(guest["n"]) == 2, "a guest's stick shows at their podium")
	EventBus.net_room_event.emit(77, "Guest", "roast", [2, false, 0.9, false])
	await _secs(0.2)
	_check(int(guest["smores"]) == 1, "and their golden marshmallow counts as a s'more here too")
	EventBus.net_room_event.emit(77, "Guest", "roast", [2, true, 0.2, false])
	await _secs(2.6)
	_check(not bool(guest["held"]), "a guest who goes quiet mid-roast has their stick pulled back")
	EventBus.net_room_event.emit(77, "Guest", "stick", [2])
	await _secs(1.0)
	_check(float(room.call("get_flare")) > 0.4, "a guest's tossed stick flares the fire here")
	EventBus.net_peer_left.emit(77)
	await _secs(0.2)
	_check((games.call("get_person", 77) as Dictionary).is_empty(), "a guest who leaves takes their stick along")
	await _secs(6.0)
	# chat throws something at the campfire
	Reactions.play_test("throw", {"type": "stage", "name": "campfire"})
	await _secs(1.4)
	_check(float(room.call("get_flare")) > 0.1, "a chat reaction thrown at the campfire feeds the fire (%.2f)" % float(room.call("get_flare")))
	await _secs(6.0)
	Reactions.play_test("throw", {"type": "stage", "name": "lake"})
	await _secs(1.4)
	_check(float(room.call("get_flare")) < 0.05, "one thrown at the lake does not")
	AppState.set_setting("camp_games", false)
	games.call("set_roasting", true)
	games.call("toss_stick")
	await _secs(1.0)
	_check(not bool(me["held"]) and float(room.call("get_flare")) < 0.05, "with Fire games off, M and T do nothing")
	AppState.set_setting("camp_games", true)

	# ── leaving for another room and coming back ──
	AppState.request_room("studio")
	await _secs(5.0)
	AppState.request_room("campfire")
	await _secs(5.0)
	var again: Room = host.get_current_room()
	_check(again != null and again != room and again.name == "CampfireRoom" and again.get_audience_seats().size() == 30, "the room survives a swap away and back")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
