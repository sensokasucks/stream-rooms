extends Node
## Lakeside Campfire: the room loads with everything its markers promise (screen, ten cameras,
## four camp chairs, 30 bench seats in three rows, three reaction targets) and the Room tab's
## controls do their job: Fire, Big screen (hides the screen and what hangs on it), String
## lights, Time of day and Day length (sky, sun and moon), Clouds / Stars / Aurora / Mist.
## The fire games: roasting a marshmallow (browning, the golden s'more, catching fire),
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
	AppState.set_setting("camp_close_woods", false)
	# the low-poly set for everything but the "Set detail" part below: the detailed one takes
	# the software renderer of the pull request check about ten seconds a frame
	AppState.set_setting("camp_detail", "low")
	AppState.set_setting("graphics_quality", "high")
	AppState.set_setting("camp_string_lights", true)
	AppState.set_setting("camp_fireflies", true)
	AppState.set_setting("camp_butterflies", true)
	AppState.set_setting("camp_autumn", false)
	AppState.set_setting("sun_rays", 1.0)
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
	var wanted: Array[String] = ["camp_fire", "camp_screen", "camp_close_woods", "camp_detail", "camp_string_lights", "camp_fireflies", "camp_butterflies", "camp_autumn", "sun_rays", "camp_games", "camp_time", "camp_day_minutes",
		"camp_clouds", "camp_stars", "camp_aurora", "camp_mist"]
	var all_there := true
	for k in wanted:
		all_there = all_there and keys.has(k) and AppState.DEFAULTS.has(k)
	_check(all_there, "the Room tab gets every camp_ control, each with a default (%s)" % str(keys))
	var shared := true
	for k: String in ["camp_fire", "camp_screen", "camp_time", "camp_clouds", "camp_close_woods"]:
		shared = shared and NetSession.is_shared(k)
	_check(shared and not NetSession.is_shared("camp_games") and not NetSession.is_shared("camp_detail"),
		"the fire, screen, hour and sky are shared in a co-stream; the games tick box and Set detail are each PC's own")

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

	# ── Set detail: the low-poly set, the detailed one near the fire, or everywhere ──
	var parts: Dictionary = room.get("_parts")
	var firs_near := room.find_child("FirsNear", true, false) as MultiMeshInstance3D
	var detail_near := room.find_child("DetailNear", true, false) as Node3D
	var detail_far := room.find_child("DetailFar", true, false) as Node3D
	var close_detail := room.find_child("CloseWoodsDetail", true, false) as Node3D
	var undergrowth := room.find_child("Undergrowth", true, false) as Node3D
	var ground_mat := parts["ground_mat"] as ShaderMaterial
	_check(String(AppState.DEFAULTS["camp_detail"]) == "auto", "Set detail starts on Auto")
	_check(firs_near != null and detail_near != null and detail_far != null and close_detail != null and undergrowth != null,
		"the detailed trees, close woods and undergrowth are built")
	_check(firs.visible and firs_near.visible and not detail_near.visible and not detail_far.visible and not undergrowth.visible
		and is_zero_approx(float(ground_mat.get_shader_parameter("detail"))),
		"Low-poly: the simple trees everywhere, flat colours, no undergrowth")
	_check(ground_mat.get_shader_parameter("tex_grass") is Texture2D and (parts["prop_mat"] as ShaderMaterial).get_shader_parameter("tex_bark") is Texture2D
		and (parts["plant_mats"]["fir"] as ShaderMaterial).get_shader_parameter("card") is Texture2D, "the photo textures loaded (ground, bark, leaf cards)")
	var species: Dictionary = parts["species_counts"]
	var mixed := true
	for kind: String in ["fir", "pine", "oak", "birch", "maple"]:
		mixed = mixed and int(species.get(kind, 0)) >= 40
	_check(mixed, "the detailed forest mixes firs, pines, oaks, birches and maples (%s)" % str(species))
	var as_many := 0
	for holder: Node3D in [detail_near, detail_far]:
		for kid in holder.get_children():
			as_many += (kid as MultiMeshInstance3D).multimesh.instance_count
	_check(as_many == int(parts["tree_count"]), "one detailed tree for every low-poly one (%d / %d)" % [as_many, int(parts["tree_count"])])
	AppState.set_setting("camp_detail", "near")
	await _secs(0.3)
	_check(firs.visible and not firs_near.visible and detail_near.visible and not detail_far.visible and undergrowth.visible
		and float(ground_mat.get_shader_parameter("detail")) > 0.5,
		"Detailed near the fire: detailed trees, textures and undergrowth close by, the far hills keep the simple trees")
	await _shot("camp_detail_near")
	AppState.set_setting("camp_detail", "full")
	AppState.set_setting("camp_close_woods", true)
	await _secs(0.3)
	_check(not firs.visible and not firs_near.visible and detail_near.visible and detail_far.visible, "Detailed everywhere: no simple tree is left")
	_check(close_detail.visible and not close_firs.visible and not close_round.visible, "with the close woods on, their detailed trees show instead of the simple ones")
	await _shot("camp_detail_full_woods")
	AppState.set_setting("camp_close_woods", false)
	await _secs(0.3)
	_check(not close_detail.visible, "and the close woods off hides those too")
	AppState.set_setting("camp_time", 12.0)
	EventBus.camera_preset_requested.emit(4)
	await _secs(1.0)
	await _shot("camp_detail_full_noon")
	EventBus.camera_preset_requested.emit(0)
	AppState.set_setting("camp_time", 18.6)
	# Auto follows the Graphics quality
	AppState.set_setting("camp_detail", "auto")
	var auto_ok := String(room.call("detail_level")) == "full"
	AppState.set_setting("graphics_quality", "medium")
	await _secs(0.3)
	auto_ok = auto_ok and String(room.call("detail_level")) == "near" and firs.visible and detail_near.visible
	AppState.set_setting("graphics_quality", "low")
	await _secs(0.3)
	auto_ok = auto_ok and String(room.call("detail_level")) == "low" and firs_near.visible and not detail_near.visible
	_check(auto_ok, "Auto follows Graphics quality: High = everywhere, Medium = near the fire, Low = low-poly")
	AppState.set_setting("graphics_quality", "high")
	AppState.set_setting("camp_detail", "low")
	await _secs(0.5)

	# ── the hour ──
	var env := room.get_world_3d().environment
	var sky := env.sky.sky_material as ShaderMaterial
	var sun := room.find_child("SunMoon", false, false) as DirectionalLight3D
	_check(sky != null and sky.shader == CF.SKY_SHADER, "the room's own sky shader is in use")
	_check(sky.get_shader_parameter("cloud_noise") is Texture2D, "the sky has its cloud shapes picture")
	_check((room.get("_parts")["lake_mat"] as ShaderMaterial).get_shader_parameter("ripples") is Texture2D
		and (room.get("_parts")["stream_mat"] as ShaderMaterial).get_shader_parameter("ripples") is Texture2D, "the lake and the stream have their ripple picture")
	var bed := room.find_child("StreamBed", true, false) as MeshInstance3D
	var brook := room.find_child("Stream", true, false) as MeshInstance3D
	_check(bed != null and brook != null and (brook.material_override as ShaderMaterial).shader.resource_path.ends_with("camp_stream.gdshader"),
		"the stream has its own bed and its own clear-water shader")
	var mid := CF.Builder.STREAM[4]
	_check(CF.Builder.ground_height(mid.x, mid.z) < mid.y - 0.1 and CF.Builder.ground_height(mid.x + 4.0, mid.z) > mid.y,
		"the stream's bed lies under its water and the bank beside it above")
	# round 11: little cascades with rocks in the brook, and Pebble by the fire ring
	var in_water: Array = CF.Builder.stream_rocks().filter(func(r: Vector4) -> bool: return r.w > 0.5)
	_check(in_water.size() > 10 and CF.Builder.stream_steps(1.0) > 0.0 and CF.Builder.stream_steps(2.0) > CF.Builder.stream_steps(1.0),
		"the brook comes down in steps and has rocks standing in it")
	_check(sin(TAU * float(CF.Builder.PEBBLE_STONE) / 11.0) > 0.8, "Pebble is the fire ring's stone on the audience's side")
	_check(CF.Builder.stream_half_width(CF.Builder.STREAM[3].x, CF.Builder.STREAM[3].z) >= CF.Builder.STREAM_NARROW,
		"the stream runs free where the footbridge was")
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
	var wings := fx.get_node_or_null("Butterflies") as CPUParticles3D
	_check(wings != null and not wings.emitting, "the butterflies stay in at night")
	# round 13: sunbeams only with a low sun, mist sheets on the lake, autumn colours
	var beams := fx.get_node_or_null("Shafts")
	_check(beams != null and beams.get_child_count() == 10 and not (beams.get_child(0) as Node3D).visible, "no sunbeams at midnight")
	_check(fx.get_node_or_null("Mist") != null and fx.get_node("Mist").get_child_count() == 3, "three sheets of mist lie on the lake")
	var maple_leaves := (room.get("_parts")["plant_mats"] as Dictionary)["leaves_maple"] as ShaderMaterial
	var fir_needles := (room.get("_parts")["plant_mats"] as Dictionary)["fir"] as ShaderMaterial
	AppState.set_setting("camp_autumn", true)
	await get_tree().process_frame
	_check(is_equal_approx(float(maple_leaves.get_shader_parameter("autumn")), 1.0) and fir_needles.get_shader_parameter("autumn") == null,
		"Autumn colours turns the maples and leaves the firs green")
	AppState.set_setting("camp_autumn", false)
	await get_tree().process_frame
	_check(is_equal_approx(float(maple_leaves.get_shader_parameter("autumn")), 0.0), "and back to summer")
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

	# ── flash safety: a flare never jumps in photosensitive-safe mode ──
	AppState.set_setting("camp_time", 18.6)
	AppState.set_setting("photosensitive_safe", true)
	room.call("flare", 1.0)
	await _secs(0.2)
	_check(float(room.call("get_fire_amount")) < float(AppState.get_setting("camp_fire")) + CF.SAFE_FLASH_CAP, "in safe mode a flare grows slowly")
	AppState.set_setting("photosensitive_safe", false)
	await _secs(6.0)       # (the flare dies down)

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
