extends Node
## Cabin: Frozen North (rooms/cabin_north/, log_cabin_room.gd with scene = "north",
## cabin_north.gd): the room loads with the cabin and the frozen lake round it (the land, the
## ice, the sled, snowshoes and rocks, the spruces in both looks, the far forest), the slope in
## front of the deck runs down to the ice and nothing stands in the deck's view, the ground is
## under snow even with "Snow on the ground" at 0, the sky keeps its own mountains, the Room tab
## has Aurora and no Season, the aurora shows on a clear night and hides in snow, and the ice
## sounds. Saves screenshots of the deck's view and the cabin from outside by day, at dusk, on
## an aurora night, in falling snow, in fog and in the Simple look into the output folder (look
## at them: the look is not checked here).
##   <redot console exe> --path . _tests/test_cabin_north.tscn -- C:/temp/sr_tests --mp-profile=test

const North := preload("res://rooms/log_cabin/cabin_north.gd")
const Builder := preload("res://rooms/log_cabin/cabin_builder.gd")

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
	AppState.set_setting("cabin_clouds", 0.3)
	AppState.set_setting("cabin_stars", 1.0)
	AppState.set_setting("cabin_aurora", 1.0)
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
	AppState.request_room("cabin_north")
	await _secs(5.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "CabinNorthRoom", "Cabin: Frozen North loaded (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return
	var parts: Dictionary = room.get("_parts")

	# the cabin is the Log Cabin's: its screen, cameras and seats
	_check(room.find_screen() != null and room.get_camera_markers().size() >= 10, "the cabin's screen and cameras are there (%d cameras)" % room.get_camera_markers().size())
	var land := room.find_child("Land", true, false) as MeshInstance3D
	_check(land != null and land.mesh.get_surface_count() == 3, "the land is built (yard, shore, woods)")
	_check(room.find_child("Ice", true, false) != null and parts.has("ice_mat"), "the frozen lake is there")
	_check(room.find_child("SnowThings", true, false) != null and room.find_child("Path", true, false) != null, "the sled, snowshoes, rocks and the trodden path are there")
	var yard_y := North.height(-2.5, -10.0)
	var ice_front := North.height(-2.5, -50.0)
	var behind := North.height(-2.5, 90.0)
	_check(absf(yard_y - (-0.9)) < 0.05 and ice_front < North.ICE_Y and behind > 5.0,
		"the yard is flat (%.2f m), the ice lies in front (%.1f m) and the slope rises behind (%.1f m)" % [yard_y, ice_front, behind])
	var far_count := 0
	for n: Node3D in parts["far_trees"]:
		far_count += (n as MultiMeshInstance3D).multimesh.instance_count
	_check(far_count > 800, "the far forest covers the shores (%d trees)" % far_count)
	var plants := parts["detailed_plants"] as Node3D
	var kinds: Array[String] = []
	for c in plants.get_children():
		kinds.append(String(c.name))
	_check(plants.visible and kinds.has("Fir") and kinds.has("Pine") and kinds.has("YoungFir") and not kinds.has("Grass") and not kinds.has("Birch"),
		"Detailed: spruces, pines and young spruces, no grass or birches (%s)" % ", ".join(kinds))
	var blocked := 0
	var on_ice := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1896
	for one: Array in North._place_trees(rng):
		var foot: Vector3 = one[0]
		var ahead := (North.YARD.y - foot.z) / maxf(Vector2(foot.x, foot.z).distance_to(North.YARD), 0.01)
		if ahead > 0.45 and foot.y + float(one[1]) * 0.95 > North.VIEW_Y:
			blocked += 1
		if foot.y < North.ICE_Y + 0.5:
			on_ice += 1
	_check(blocked == 0 and on_ice == 0, "no tree in the deck's view (%d) or on the ice (%d)" % [blocked, on_ice])
	# always under snow
	var weather: Node = room.get("_weather")
	await _secs(0.5)
	_check(float(weather.call("snow_cover")) >= North.SNOW_FLOOR - 0.01, "the ground is under snow with the slider at 0 (%.2f)" % float(weather.call("snow_cover")))
	var grass := (parts["surface_mats"] as Dictionary)[Builder.S_GRASS] as ShaderMaterial
	_check(float(grass.get_shader_parameter("snow")) >= North.SNOW_FLOOR - 0.01, "the snow lies on the ground's material")
	var env: Environment = room.get_world_3d().environment
	var sky := env.sky.sky_material as ShaderMaterial
	_check(float(sky.get_shader_parameter("blue_ridges")) < 0.5 and float(sky.get_shader_parameter("open_sea")) < 0.5, "the sky draws its own mountains")
	var has_season := false
	var has_aurora := false
	for c: Dictionary in room.get_controls():
		has_season = has_season or String(c.get("key", "")) == "cabin_season"
		has_aurora = has_aurora or String(c.get("key", "")) == "cabin_aurora"
	_check(has_aurora and not has_season, "the Room tab has Aurora and no Season")
	room.call("ice_sound", 0.8)
	var ice_player: AudioStreamPlayer = null
	for c in room.get_children():
		if c is AudioStreamPlayer and c.name == "Ice":
			ice_player = c
	_check(ice_player != null and int(room.get("ice_calls")) > 0 and ice_player.bus == AudioManager.AMBIENCE_BUS, "the ice sounds (on the Ambience bus)")

	await _secs(0.8)
	await _view(5, "north_day_deck_view.png")
	await _view(6, "north_day_outside.png")
	await _view(2, "north_day_sofa.png")
	AppState.set_setting("cabin_time", 18.4)
	await _secs(1.0)
	await _view(5, "north_dusk_deck_view.png")

	# an aurora night; then snow hides it
	AppState.set_setting("cabin_time", 23.0)
	await _secs(1.0)
	var aurora_clear := float(sky.get_shader_parameter("aurora_amount"))
	_check(aurora_clear > 0.5, "the aurora shows on a clear night (%.2f)" % aurora_clear)
	await _view(5, "north_night_deck_view.png", 2.0)
	await _view(6, "north_night_outside.png")
	AppState.set_setting("cabin_weather", "snow")
	await _secs(1.0)
	_check(float(sky.get_shader_parameter("aurora_amount")) < 0.01, "no aurora while it snows")
	AppState.set_setting("cabin_time", 13.0)
	weather.call("settle")
	await _secs(1.5)
	await _view(5, "north_snowing_deck_view.png")
	AppState.set_setting("cabin_weather", "clear")
	AppState.set_setting("cabin_fog", "heavy")
	await _secs(1.0)
	await _view(6, "north_fog_outside.png")
	AppState.set_setting("cabin_fog", "off")
	AppState.set_setting("cabin_time", 11.0)

	# Simple look
	AppState.set_setting("cabin_detail", "low")
	await _secs(0.8)
	_check(not plants.visible and (parts["simple_trees"] as Node3D).visible, "Simple: plain trees instead of the leaf cards")
	await _view(6, "north_simple_outside.png")
	AppState.set_setting("cabin_detail", "full")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
