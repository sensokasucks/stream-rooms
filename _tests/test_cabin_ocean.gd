extends Node
## Cabin: Ocean (rooms/cabin_ocean/, log_cabin_room.gd with scene = "ocean", cabin_ocean.gd): the
## room loads with the cabin and the coast round it (the land with the bluff, beach and woods,
## the sea, the surf, the stairs, driftwood and rocks, the lighthouse, the gulls, the near trees
## in both looks, the far forest), the bluff drops to the beach in front and nothing stands in the
## deck's view, the sky draws a flat sea horizon, the wind raises the waves and the surf, the
## lighthouse's beams turn and show at night and in fog (not by day), the gulls fly by day and
## the foghorn sounds in heavy fog. Saves screenshots of the deck's view and the cabin from
## outside by day, at dusk, at night, in fog, in the rain and in the Simple look into the output
## folder (look at them: the look is not checked here).
##   <redot console exe> --path . _tests/test_cabin_ocean.tscn -- C:/temp/sr_tests --mp-profile=test

const Ocean := preload("res://rooms/log_cabin/cabin_ocean.gd")

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
	AppState.set_setting("cabin_view", "great_room")
	AppState.set_setting("curtain_enabled", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("cabin_ocean")
	await _secs(5.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "CabinOceanRoom", "Cabin: Ocean loaded (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return
	var parts: Dictionary = room.get("_parts")

	_check(room.find_screen() != null and room.get_camera_markers().size() >= 10, "the cabin's screen and cameras are there (%d cameras)" % room.get_camera_markers().size())
	var land := room.find_child("Land", true, false) as MeshInstance3D
	_check(land != null and land.mesh.get_surface_count() == 3, "the land is built (grass, sand, woods)")
	for n: String in ["Sea", "Surf", "BeachThings", "Lighthouse", "Gulls"]:
		_check(room.find_child(n, true, false) != null, "%s is there" % n)
	var yard_y := Ocean.height(-2.5, -10.0)
	var beach := Ocean.height(-2.5, Ocean.edge_z(-2.5) - Ocean.BLUFF_W - 5.0)
	var sea := Ocean.height(-2.5, -200.0)
	_check(absf(yard_y - (-0.9)) < 0.05 and beach < yard_y - 8.0 and sea < Ocean.SEA_Y,
		"the yard is flat (%.2f m), the beach lies below the bluff (%.1f m) and the sea beyond (%.1f m)" % [yard_y, beach, sea])
	var far_count := 0
	for n: Node3D in parts["far_trees"]:
		far_count += (n as MultiMeshInstance3D).multimesh.instance_count
	_check(far_count > 800, "the far forest covers the land inland (%d trees)" % far_count)
	var plants := parts["detailed_plants"] as Node3D
	var kinds: Array[String] = []
	for c in plants.get_children():
		kinds.append(String(c.name))
	_check(plants.visible and kinds.has("Pine") and kinds.has("Grass"), "Detailed: pines, scrub and dune grass (%s)" % ", ".join(kinds))
	var blocked := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1912
	for one: Array in Ocean._place_trees(rng):
		var foot: Vector3 = one[0]
		var ahead := (Ocean.YARD.y - foot.z) / maxf(Vector2(foot.x, foot.z).distance_to(Ocean.YARD), 0.01)
		if ahead > 0.35 and foot.y + float(one[1]) * 0.95 > Ocean.VIEW_Y or Ocean.seaward(foot.x, foot.z) > -3.0:
			blocked += 1
		var lean := float(one[3])
		if lean <= 0.0 or lean > 0.4:
			blocked += 1
	_check(blocked == 0, "no tree in the deck's view or on the bluff's face, all bent inland (%d wrong)" % blocked)
	var env: Environment = room.get_world_3d().environment
	var sky := env.sky.sky_material as ShaderMaterial
	await _secs(0.3)
	_check(float(sky.get_shader_parameter("open_sea")) > 0.5 and float(sky.get_shader_parameter("blue_ridges")) < 0.5, "the sky draws a flat sea horizon")
	var has_season := false
	for c: Dictionary in room.get_controls():
		has_season = has_season or String(c.get("key", "")) == "cabin_season"
	_check(not has_season, "no Season on the coast")
	# the wind raises the waves and the surf
	var sea_mat := parts["sea_mat"] as ShaderMaterial
	var surf_mat := parts["surf_mat"] as ShaderMaterial
	var calm := [float(sea_mat.get_shader_parameter("wave")), float(surf_mat.get_shader_parameter("size"))]
	AppState.set_setting("cabin_wind", 1.6)
	await _secs(1.0)
	var rough := [float(sea_mat.get_shader_parameter("wave")), float(surf_mat.get_shader_parameter("size"))]
	_check(rough[0] > calm[0] + 0.5 and rough[1] > calm[1] + 0.3, "the wind raises the waves (%.2f -> %.2f) and the surf (%.2f -> %.2f)" % [calm[0], rough[0], calm[1], rough[1]])
	AppState.set_setting("cabin_wind", 0.4)
	# by day: gulls out, the beams off; and they turn
	var beam_mat := parts["beam_mat"] as ShaderMaterial
	var gulls: Array = parts["gulls"]
	await _secs(0.5)
	_check(float(beam_mat.get_shader_parameter("strength")) < 0.05 and (gulls[0] as Node3D).visible, "by day the gulls fly and the lighthouse's beams are off")
	var beam := parts["beam"] as Node3D
	var turn0 := beam.rotation.y
	await _secs(0.5)
	_check(absf(beam.rotation.y - turn0) > 0.01, "the lighthouse's beams turn")
	_check(room.find_child("Gulls", true, false) is Node3D and (room.find_child("Foghorn", true, false) as AudioStreamPlayer).stream != null, "the gulls' call and the foghorn are ready")

	await _view(5, "ocean_day_deck_view.png")
	await _view(6, "ocean_day_outside.png")
	await _view(2, "ocean_day_sofa.png")
	AppState.set_setting("cabin_time", 18.4)
	await _secs(1.0)
	await _view(5, "ocean_dusk_deck_view.png")

	# night: beams on, no gulls
	AppState.set_setting("cabin_time", 22.0)
	await _secs(1.0)
	_check(float(beam_mat.get_shader_parameter("strength")) > 0.4 and not (gulls[0] as Node3D).visible, "at night the beams show and the gulls are gone")
	await _view(5, "ocean_night_deck_view.png", 2.0)
	await _view(6, "ocean_night_outside.png")
	# heavy fog by day: the beams show only as a dim, spread-out glow, the foghorn sounds
	AppState.set_setting("cabin_time", 13.0)
	AppState.set_setting("cabin_fog", "heavy")
	room.set("_horn_wait", 0.0)
	await _secs(1.0)
	_check(float(beam_mat.get_shader_parameter("strength")) > 0.15 and float(beam_mat.get_shader_parameter("haze")) > 0.9, "in heavy fog the beams show by day, dim and spread out")
	_check(int(room.get("horn_blasts")) > 0, "the foghorn sounds in heavy fog")
	await _view(5, "ocean_fog_deck_view.png")
	AppState.set_setting("cabin_fog", "off")
	AppState.set_setting("cabin_weather", "storm")
	(room.get("_weather")).settle()
	await _secs(1.0)
	await _view(5, "ocean_storm_deck_view.png")
	AppState.set_setting("cabin_weather", "clear")
	AppState.set_setting("cabin_time", 11.0)

	AppState.set_setting("cabin_detail", "low")
	await _secs(0.8)
	_check(not plants.visible and (parts["simple_trees"] as Node3D).visible, "Simple: plain trees instead of the leaf cards")
	await _view(6, "ocean_simple_outside.png")
	AppState.set_setting("cabin_detail", "full")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
