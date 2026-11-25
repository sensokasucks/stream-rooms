extends Node
## Cabin: Lakeside (rooms/cabin_lake/, log_cabin_room.gd with scene = "lake", cabin_lake.gd): the
## room loads with the cabin and the lake round it (the land with its lawn, beach and woods, the
## lake's water, the dock, the canoe, the reeds and lily pads, the near trees in both looks, the
## far forest), the lawn in front of the deck runs down to the water and nothing stands in the
## deck's view, the sky keeps its own mountains (no blue ridges), Season turns the birches, the
## wind raises waves, the fireflies come out on dry summer nights and the loons can call. Saves
## screenshots of the deck's view and the cabin from outside by day, at dusk, at night, in
## autumn, in the rain and in the Simple look into the output folder (look at them: the look is
## not checked here).
##   <redot console exe> --path . _tests/test_cabin_lake.tscn -- C:/temp/sr_tests --mp-profile=test

const Lake := preload("res://rooms/log_cabin/cabin_lake.gd")

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


## Points the camera at preset i (the room's camera markers, in order) and saves a picture.
func _view(i: int, file: String, wait: float = 1.2) -> void:
	EventBus.camera_preset_requested.emit(i)
	await _secs(wait)
	await _shot(_out.path_join(file))


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("cabin_fire", 1.0)
	AppState.set_setting("cabin_lamps", true)
	AppState.set_setting("cabin_time", 11.0)
	AppState.set_setting("cabin_day_minutes", 0.0)
	AppState.set_setting("cabin_clouds", 0.5)
	AppState.set_setting("cabin_stars", 1.0)
	AppState.set_setting("cabin_detail", "full")
	AppState.set_setting("cabin_weather", "clear")
	AppState.set_setting("cabin_fog", "off")
	AppState.set_setting("cabin_wind", 0.4)
	AppState.set_setting("cabin_snow", 0.0)
	AppState.set_setting("cabin_weather_fx", 1.0)
	AppState.set_setting("cabin_season", "summer")
	AppState.set_setting("cabin_view", "great_room")
	AppState.set_setting("curtain_enabled", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("cabin_lake")
	await _secs(5.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "CabinLakeRoom", "Cabin: Lakeside loaded (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return
	var parts: Dictionary = room.get("_parts")

	# the cabin is the Log Cabin's: its screen, cameras and seats
	_check(room.find_screen() != null and room.get_camera_markers().size() >= 10, "the cabin's screen and cameras are there (%d cameras)" % room.get_camera_markers().size())
	# the land, the lake, the things on the shore
	var land := room.find_child("Land", true, false) as MeshInstance3D
	_check(land != null and land.mesh.get_surface_count() == 3, "the land is built (grass, beach, woods)")
	_check(room.find_child("Lake", true, false) != null and parts.has("lake_mat"), "the lake is there")
	_check(room.find_child("ShoreThings", true, false) != null, "the dock, canoe, reeds and lily pads are there")
	var yard_y := Lake.height(-2.5, -10.0)
	var water_front := Lake.height(-2.5, -45.0)
	var behind := Lake.height(-2.5, 90.0)
	_check(absf(yard_y - (-0.9)) < 0.05 and water_front < Lake.WATER_Y and behind > 5.0,
		"the yard is flat (%.2f m), the lake lies in front (%.1f m) and the slope rises behind (%.1f m)" % [yard_y, water_front, behind])
	var root := Lake.dock_root()
	_check(root.distance_to(Lake.YARD) > 25.0 and root.distance_to(Lake.YARD) < 45.0, "the dock starts at the beach (%.1f m out)" % root.distance_to(Lake.YARD))
	var far_count := 0
	for n: Node3D in parts["far_trees"]:
		far_count += (n as MultiMeshInstance3D).multimesh.instance_count
	_check(far_count > 800, "the far forest covers the shores (%d trees)" % far_count)
	var plants := parts["detailed_plants"] as Node3D
	var kinds: Array[String] = []
	for c in plants.get_children():
		kinds.append(String(c.name))
	_check(plants.visible and kinds.has("Pine") and kinds.has("Fir") and kinds.has("Birch") and kinds.has("Grass"),
		"Detailed: pines, firs, birches and grass (%s)" % ", ".join(kinds))
	# nothing in front of the deck stands above the view, and no tree stands in the water
	var blocked := 0
	var wet := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1867
	for one: Array in Lake._place_trees(rng):
		var foot: Vector3 = one[0]
		var ahead := (Lake.YARD.y - foot.z) / maxf(Vector2(foot.x, foot.z).distance_to(Lake.YARD), 0.01)
		if ahead > 0.45 and foot.y + float(one[1]) * 0.95 > Lake.VIEW_Y:
			blocked += 1
		if foot.y < Lake.WATER_Y + 0.5:
			wet += 1
	_check(blocked == 0 and wet == 0, "no tree in the deck's view (%d) or in the water (%d)" % [blocked, wet])
	# the sky keeps its own mountains (the lake mirrors them)
	var env: Environment = room.get_world_3d().environment
	var sky := env.sky.sky_material as ShaderMaterial
	await _secs(0.3)
	_check(float(sky.get_shader_parameter("blue_ridges")) < 0.5, "the sky draws its own mountains, not the forest's blue ridges")
	var has_season := false
	for c: Dictionary in room.get_controls():
		has_season = has_season or String(c.get("key", "")) == "cabin_season"
	_check(has_season, "Season is on the Room tab")
	# the wind raises waves
	var lake := parts["lake_mat"] as ShaderMaterial
	var calm := float(lake.get_shader_parameter("wave"))
	AppState.set_setting("cabin_wind", 1.6)
	await _secs(1.0)
	var rough := float(lake.get_shader_parameter("wave"))
	_check(rough > calm + 0.3, "the wind raises waves on the lake (%.2f -> %.2f)" % [calm, rough])
	AppState.set_setting("cabin_wind", 0.4)
	# the loons
	room.call("call_loon", 0.8)
	var loons := room.find_child("Loons", true, false) as AudioStreamPlayer
	_check(loons != null and loons.playing and loons.bus == AudioManager.AMBIENCE_BUS, "a loon calls (on the Ambience bus)")

	await _secs(0.8)
	await _view(5, "lake_day_deck_view.png")
	await _view(6, "lake_day_outside.png")
	await _view(2, "lake_day_sofa.png")
	AppState.set_setting("cabin_time", 18.4)
	await _secs(1.0)
	await _view(5, "lake_dusk_deck_view.png")

	# autumn
	AppState.set_setting("cabin_time", 15.0)
	AppState.set_setting("cabin_season", "autumn")
	await _secs(0.5)
	var birch := (parts["leaf_mats"] as Dictionary)["leaves_birch"] as ShaderMaterial
	_check(float(birch.get_shader_parameter("autumn")) > 0.5, "Autumn: the birches turn")
	await _view(5, "lake_autumn_deck_view.png")
	await _view(6, "lake_autumn_outside.png")
	AppState.set_setting("cabin_season", "summer")
	await _secs(0.5)

	# night: fireflies and the cabin's glow on the water; then rain
	AppState.set_setting("cabin_time", 22.0)
	await _secs(1.0)
	var flies := room.find_child("Fireflies", true, false) as CPUParticles3D
	_check(flies != null and flies.emitting, "fireflies on a clear summer night")
	await _view(6, "lake_night_outside.png")
	await _view(5, "lake_night_deck_view.png", 2.0)
	AppState.set_setting("cabin_weather", "rain")
	await _secs(0.5)
	_check(flies != null and not flies.emitting, "no fireflies in the rain")
	AppState.set_setting("cabin_time", 13.0)
	(room.get("_weather")).settle()
	await _secs(1.0)
	await _view(5, "lake_rain_deck_view.png")
	AppState.set_setting("cabin_weather", "clear")
	AppState.set_setting("cabin_time", 11.0)

	# Simple look
	AppState.set_setting("cabin_detail", "low")
	await _secs(0.8)
	_check(not plants.visible and (parts["simple_trees"] as Node3D).visible, "Simple: plain trees instead of the leaf cards")
	await _view(6, "lake_simple_outside.png")
	AppState.set_setting("cabin_detail", "full")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
