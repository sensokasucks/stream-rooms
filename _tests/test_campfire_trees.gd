extends Node
## Lakeside Campfire's Blender trees (rooms/campfire/campfire_forest.gd, models/trees.glb):
## the detailed looks use them, every tree is drawn at exactly one of three levels of detail
## (full tree, light tree, far picture) by its distance from the camera, the levels follow the
## camera, and the "Set detail" choices still show the right lots. Prints what one frame costs
## (triangles and draw calls) for each Set detail choice from the main camera, and saves
## pictures of each look, every species side by side at each level and a high view into the
## output folder.
##   <redot console exe> --path . _tests/test_campfire_trees.tscn -- C:/temp/sr_tests --mp-profile=test
## Slow under a software renderer (every picture is a detailed frame): run it on the PC.

const CF := preload("res://rooms/campfire/campfire_room.gd")
const FOREST := preload("res://rooms/campfire/campfire_forest.gd")
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


## What a frame costs: "triangles" and "draws" (draw calls) the renderer sent, all passes
## (shadows too), and "ms" = the average milliseconds of the next FRAMES frames. Only compare
## these between runs on the same PC: under a software renderer ms is mostly the CPU drawing.
const FRAMES: int = 20
func _cost() -> Dictionary:
	for i in 4:
		await RenderingServer.frame_post_draw
	var out := {"triangles": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	var start := Time.get_ticks_usec()
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	out["ms"] = float(Time.get_ticks_usec() - start) / 1000.0 / float(FRAMES)
	return out


func _print_cost(what: String, c: Dictionary) -> void:
	print("COST %s: %d triangles, %d draw calls, %.1f ms a frame" % [what, int(c["triangles"]), int(c["draws"]), float(c["ms"])])


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("curtain_enabled", false)
	AppState.set_setting("camp_fire", 1.0)
	AppState.set_setting("camp_screen", true)
	AppState.set_setting("camp_time", 12.0)
	AppState.set_setting("camp_day_minutes", 0.0)
	AppState.set_setting("camp_clouds", 0.5)
	AppState.set_setting("camp_mist", 0.0)
	AppState.set_setting("camp_close_woods", false)
	AppState.set_setting("camp_detail", "full")
	AppState.set_setting("graphics_quality", "high")
	AppState.set_setting("camp_autumn", false)
	AppState.set_setting("camp_butterflies", false)
	AppState.set_setting("camp_fireflies", false)
	AppState.set_setting("sun_rays", 0.0)
	for n in range(1, 5):
		AppState.set_setting(AppState.presenter_key(n, "on"), false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("campfire")
	await _secs(4.0)
	var room: Room = main.get_node("RoomHost").get_current_room()
	_check(room != null and room.name == "CampfireRoom", "the Lakeside Campfire loaded")
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return
	var parts: Dictionary = room.get("_parts")
	_check(bool(parts.get("forest_lod", false)), "the detailed trees are the Blender ones (models/trees.glb loaded)")
	var mats: Dictionary = parts["plant_mats"]
	_check(mats.get("impostor") is ShaderMaterial and (mats["impostor"] as ShaderMaterial).get_shader_parameter("color_sheet") is Texture2D,
		"the far trees' picture sheets loaded")
	_check((mats["leaves"] as ShaderMaterial).get_shader_parameter("card").resource_path.ends_with("twig_oak.png"), "oaks wear the new twig picture")

	# ── every tree in exactly one level ──
	var holders: Array[Node3D] = [parts["detail_near"], parts["detail_far"], parts["close_woods_detail"]]
	var levels_ok := true
	var counts := [0, 0, 0]                  # trees in the Full, Light and Far levels
	for holder in holders:
		for cell in holder.get_children():
			var level := ["Full", "Light", "Far"].find(String(cell.name).get_slice("_", 0))
			levels_ok = levels_ok and level >= 0
			for mmi: MultiMeshInstance3D in cell.get_children():
				var band: Vector2 = mmi.get_meta("lod_band")
				var want := Vector2(float(FOREST.LEVELS[level][2]), float(FOREST.LEVELS[level][3]))
				counts[level] += mmi.multimesh.instance_count
				levels_ok = levels_ok and band == want and mmi.visibility_range_end > band.y and mmi.visibility_range_begin < maxf(band.x, 0.001)
				levels_ok = levels_ok and (level < 2 or mmi.material_override != null)
				# every tree carries its level's band (the shaders read it from the custom data)
				var c := mmi.multimesh.get_instance_custom_data(0)
				if not (is_equal_approx(c.g, band.x) and is_equal_approx(c.b, band.y)) and levels_ok:
					print("  %s/%s carries the band %s instead of %s" % [cell.name, mmi.name, str(Vector2(c.g, c.b)), str(band)])
				levels_ok = levels_ok and is_equal_approx(c.g, band.x) and is_equal_approx(c.b, band.y)
	var expected := int(parts["tree_count"]) + int(parts["close_tree_count"])
	_check(levels_ok, "the three levels meet without a gap or an overlap (full to %d m, light to %d m, pictures beyond)" % [FOREST.LOD1_FROM, FOREST.IMPOSTOR_FROM])
	_check(counts[0] == expected and counts[1] == expected and counts[2] == expected,
		"every tree is in every level once (full %d, light %d, pictures %d, trees %d)" % [counts[0], counts[1], counts[2], expected])

	# ── the levels follow the camera ──
	var cam := get_viewport().get_camera_3d()
	await _secs(0.5)
	var eye: Vector3 = (mats["trunk"] as ShaderMaterial).get_shader_parameter("lod_eye")
	_check(eye.distance_to(cam.global_position) < 1.5, "the levels count from the camera (%s / %s)" % [str(eye), str(cam.global_position)])

	# ── what a frame costs from the main camera, per Set detail choice ──
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.5)
	for level: String in ["low", "near", "full"]:
		AppState.set_setting("camp_detail", level)
		await _secs(0.5)
		_print_cost(level, await _cost())
		await _shot("trees_main_%s" % level)
	AppState.set_setting("camp_close_woods", true)
	await _secs(0.5)
	_print_cost("full + close woods", await _cost())
	await _shot("trees_main_full_woods")
	AppState.set_setting("camp_close_woods", false)

	# ── pictures: every camera at noon, autumn, dusk ──
	var cams := room.get_camera_markers()
	for i in cams.size():
		EventBus.camera_preset_requested.emit(i)
		await _secs(1.2)
		await _shot("trees_cam_%s" % String(cams[i].name).trim_prefix("CAM_"))
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.2)
	AppState.set_setting("camp_autumn", true)
	await _secs(0.5)
	await _shot("trees_autumn")
	AppState.set_setting("camp_autumn", false)
	AppState.set_setting("camp_time", 18.8)
	await _secs(0.8)
	await _shot("trees_dusk")
	AppState.set_setting("camp_time", 12.0)

	# ── close-ups and a far view, from a camera of our own ──
	var own := Camera3D.new()
	own.fov = 60.0
	room.add_child(own)
	own.make_current()
	# every species side by side in the clearing, once per level (full, light, far picture),
	# so the levels can be compared; these stand in for the test only
	var kit: Dictionary = FOREST.meshes(mats)
	own.look_at_from_position(Vector3(0.0, 3.4, 22.0), Vector3(0.0, 3.2, -2.0))
	for level in 3:
		var row := Node3D.new()
		room.add_child(row)
		for i in FOREST.SPECIES.size():
			var species := FOREST.SPECIES[i]
			var tall := 6.0 if species != "young_fir" else 3.5
			var wide := tall * (0.95 if species in ["oak", "maple"] else 0.8)
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(wide, tall, wide)), Vector3(-11.0 + 4.4 * float(i), 0.0, -2.0))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = (kit[species] as Array)[level] if level < 2 else FOREST.impostor_mesh()
			mm.instance_count = 1
			mm.set_instance_transform(0, xf)
			mm.set_instance_color(0, Color.WHITE)
			mm.set_instance_custom_data(0, Color(float(i), 0.0, 0.0, 0.0))     # no band: always drawn
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if level == 2:
				mmi.material_override = mats["impostor"]
			row.add_child(mmi)
		await _secs(1.0)
		await _shot("trees_lineup_%s" % ["full", "light", "far_picture"][level])
		row.queue_free()
	await _secs(0.3)
	own.look_at_from_position(Vector3(0.0, 14.0, 34.0), Vector3(0.0, 4.0, -20.0))
	await _secs(1.0)
	_print_cost("full, high view over the forest", await _cost())
	await _shot("trees_high_view")
	own.queue_free()

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
