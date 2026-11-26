extends Node
## Cabin: Appalachian Forest (rooms/cabin_forest/, log_cabin_room.gd with scene = "forest",
## cabin_forest.gd): the room loads with the cabin and the forest round it (the land with its
## valley, the yard fading softly into the forest floor, the creek (flowing downhill), the near trees in both looks, the far forest), the sky draws the blue
## ridges, the trees in front of the deck stay below the view, Season turns the leaves and the
## forest floor, and the fireflies come out on dry summer nights only. Saves screenshots of the
## deck's view and the cabin from outside by day, at dusk, at night, in autumn, in the rain and in
## the Simple look into the output folder (look at them: the look is not checked here).
##   <redot console exe> --path . _tests/test_cabin_forest.tscn -- C:/temp/sr_tests --mp-profile=test

const Forest := preload("res://rooms/log_cabin/cabin_forest.gd")

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
	AppState.request_room("cabin_forest")
	await _secs(5.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "CabinForestRoom", "Cabin: Appalachian Forest loaded (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return
	var parts: Dictionary = room.get("_parts")

	# the cabin is the Log Cabin's: its screen, cameras and seats
	_check(room.find_screen() != null and room.get_camera_markers().size() >= 10, "the cabin's screen and cameras are there (%d cameras)" % room.get_camera_markers().size())
	# the land, the creek, the far forest
	var land := room.find_child("Land", true, false) as MeshInstance3D
	_check(land != null and land.mesh.get_surface_count() == 2, "the land is built (yard and forest floor)")
	if land != null and land.mesh.get_surface_count() == 2:
		# the yard's grass fades into the forest floor (UV2.x = the other photo's share) over a
		# band of corners, instead of the hard zigzag edge there was before round 8
		var u2: PackedVector2Array = land.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
		var between := 0
		for u in u2:
			between += 1 if u.x > 0.05 and u.x < 0.95 else 0
		_check(between > 50, "the yard's edge fades into the forest floor (%d corners in between)" % between)
	var creek := room.find_child("Creek", true, false) as MeshInstance3D
	_check(creek != null and parts.has("stream_mat"), "the creek runs past the cabin")
	if creek != null:
		# camp_stream.gdshader moves the ripples towards smaller UV.y: UV.y must fall going
		# downhill, or the water flows uphill (it did, before round 7)
		var arr := creek.mesh.surface_get_arrays(0)
		var cv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cu: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var hi := 0
		var lo := 0
		for i in cv.size():
			hi = i if cv[i].y > cv[hi].y else hi
			lo = i if cv[i].y < cv[lo].y else lo
		_check(cu[hi].y > cu[lo].y, "the creek flows downhill (UV.y %.0f at the top, %.0f at the bottom)" % [cu[hi].y, cu[lo].y])
	var front_y := Forest.height(-2.0, -90.0)
	var back_y := Forest.height(-2.0, 90.0)
	_check(front_y < -15.0 and back_y > 5.0, "the valley falls away in front of the deck (%.1f m) and the slope rises behind (%.1f m)" % [front_y, back_y])
	var far_count := 0
	for n: Node3D in parts["far_trees"]:
		far_count += (n as MultiMeshInstance3D).multimesh.instance_count
	_check(far_count > 800, "the far forest covers the slopes (%d trees)" % far_count)
	var plants := parts["detailed_plants"] as Node3D
	var kinds: Array[String] = []
	for c in plants.get_children():
		kinds.append(String(c.name))
	_check(plants.visible and kinds.has("Fir") and kinds.has("Oak") and kinds.has("Maple") and kinds.has("Birch") and kinds.has("Fern") and kinds.has("Rhodo"),
		"Detailed: hardwoods, hemlocks, rhododendron, ferns (%s)" % ", ".join(kinds))
	# nothing in the deck's view stands above it
	var blocked := 0
	for one: Array in Forest._place_trees(_rng_1776()):
		var foot: Vector3 = one[0]
		var ahead := (Forest.YARD.y - foot.z) / maxf(Vector2(foot.x, foot.z).distance_to(Forest.YARD), 0.01)
		if String(one[2]) != "rhodo" and ahead > 0.45 and foot.y + float(one[1]) * 0.95 > Forest.VIEW_Y:
			blocked += 1
	_check(blocked == 0, "no tree in front of the deck rises into the view (%d)" % blocked)
	# the sky's Appalachian ridges
	var env: Environment = room.get_world_3d().environment
	var sky := env.sky.sky_material as ShaderMaterial
	await _secs(0.3)
	_check(float(sky.get_shader_parameter("blue_ridges")) > 0.5, "the sky draws the blue ridges")
	# Season sits on the Room tab and is shared
	var has_season := false
	for c: Dictionary in room.get_controls():
		has_season = has_season or String(c.get("key", "")) == "cabin_season"
	_check(has_season and NetSession.SHARED_CABIN.has("cabin_season"), "Season is on the Room tab and shared in a co-stream")

	await _view(5, "forest_day_deck_view.png")
	await _view(6, "forest_day_outside.png")
	await _view(2, "forest_day_sofa.png")
	AppState.set_setting("cabin_time", 18.1)
	await _secs(1.0)
	await _view(5, "forest_dusk_deck_view.png")

	# autumn
	AppState.set_setting("cabin_time", 15.0)
	AppState.set_setting("cabin_season", "autumn")
	await _secs(0.5)
	var oak := (parts["leaf_mats"] as Dictionary)["leaves"] as ShaderMaterial
	var litter := parts["litter_mat"] as ShaderMaterial
	_check(float(oak.get_shader_parameter("autumn")) > 0.5 and (litter.get_shader_parameter("far_tint") as Vector3).x > 1.5,
		"Autumn: the leaves and the far treetops turn")
	await _view(5, "forest_autumn_deck_view.png")
	await _view(6, "forest_autumn_outside.png")
	AppState.set_setting("cabin_season", "summer")
	await _secs(0.5)
	_check(float(oak.get_shader_parameter("autumn")) < 0.5, "Summer: green again")

	# fireflies: a clear summer night yes, rain no
	AppState.set_setting("cabin_time", 22.0)
	await _secs(1.0)
	var flies := room.find_child("Fireflies", true, false) as CPUParticles3D
	_check(flies != null and flies.emitting, "fireflies on a clear summer night")
	await _view(6, "forest_night_outside.png")
	await _view(5, "forest_night_deck_view.png", 2.0)
	AppState.set_setting("cabin_weather", "rain")
	await _secs(0.5)
	_check(flies != null and not flies.emitting, "no fireflies in the rain")
	AppState.set_setting("cabin_time", 13.0)
	(room.get("_weather")).settle()
	await _secs(1.0)
	await _view(5, "forest_rain_deck_view.png")
	AppState.set_setting("cabin_weather", "clear")
	AppState.set_setting("cabin_time", 11.0)

	# Simple look
	AppState.set_setting("cabin_detail", "low")
	await _secs(0.8)
	_check(not plants.visible and (parts["simple_trees"] as Node3D).visible, "Simple: plain trees instead of the leaf cards")
	await _view(6, "forest_simple_outside.png")
	AppState.set_setting("cabin_detail", "full")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)


## The random numbers cabin_forest.gd places its trees with (the same seed as Forest.build).
func _rng_1776() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1776
	return rng
