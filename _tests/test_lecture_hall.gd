extends Node
## Lecture Hall look: the Room tab gets Set detail, Window glass, Light rays, Time of day, Day
## length and Clouds; Set detail swaps the photo-textured materials in and out (and "auto"
## follows Graphics quality); the clock moves the sun, so the beams come through other windows
## in the morning than in the evening, turn moonlit at night and stop at midnight's dark hours;
## the window glass gets the sky and the Window glass choice. Also loads the Lecture Hall
## (Panel), which shares the script.
## Saves screenshots from every camera, and of morning, noon, sunset and night, the three glass
## choices and the simple look into the output folder (look at them: the look is not checked here).
##   <redot console exe> --path . _tests/test_lecture_hall.tscn -- C:/temp/sr_tests --mp-profile=test

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


## The material a named surface shows now (override or the mesh's own), by imported name.
func _first_active(room: Node, mat_name: String) -> Material:
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var own := mi.mesh.surface_get_material(s)
			if own != null and own.resource_name == mat_name:
				return mi.get_active_material(s)
	return null


## Faces in the beam mesh (0 = no beams).
func _beam_faces(room: Node) -> int:
	var shafts := room.find_child("SunShafts", false, false) as MeshInstance3D
	if shafts == null or shafts.mesh == null:
		return 0
	return shafts.mesh.get_faces().size()


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("sun_rays", 1.0)
	AppState.set_setting("graphics_quality", "high")
	AppState.set_setting("lh_detail", "auto")
	AppState.set_setting("lh_time", 16.5)
	AppState.set_setting("lh_day_minutes", 0.0)
	AppState.set_setting("lh_clouds", 1.0)
	AppState.set_setting("lh_glass", "quarries")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("lecture_hall")
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "LectureHallRoom", "the Lecture Hall loaded (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return

	# the Room tab
	var keys: Array[String] = []
	for c in room.get_controls():
		if c.has("key"):
			keys.append(String(c["key"]))
	for k: String in ["lh_detail", "lh_glass", "sun_rays", "lh_time", "lh_day_minutes", "lh_clouds"]:
		_check(keys.has(k), "the Room tab has %s" % k)
	var panel: Node = main.get_node("ControlPanel")
	var schema := {}
	for e: Dictionary in panel.settings_schema():
		schema[String(e["key"])] = String(e["type"])
	_check(schema.get("lh_detail", "") == "choice" and schema.get("lh_glass", "") == "choice" and schema.get("lh_time", "") == "range",
		"the panel built dropdowns for Set detail and Window glass and a slider for Time of day (so Core gets them too)")

	# Set detail
	var oak := _first_active(room, "Oak") as BaseMaterial3D
	_check(room.call("is_detailed") and oak != null and oak.normal_enabled and oak.albedo_texture != null \
		and oak.albedo_texture.resource_path.ends_with("detail/oak.jpg"), "High graphics + Auto: the oak shows its photo texture with a normal map")
	_check(oak != null and oak.clearcoat_enabled, "and keeps the varnish (clear coat)")
	var lea := _first_active(room, "Leather") as BaseMaterial3D
	_check(lea != null and lea.albedo_color == Color.WHITE and lea.albedo_texture != null, "the leather takes its colour from its texture")
	AppState.set_setting("lh_detail", "simple")
	await _secs(0.3)
	oak = _first_active(room, "Oak") as BaseMaterial3D
	_check(not room.call("is_detailed") and oak != null and not oak.normal_enabled, "Simple puts the painted look back")
	await _shot(_out + "/lh_simple.png")
	AppState.set_setting("lh_detail", "auto")
	AppState.set_setting("graphics_quality", "low")
	await _secs(0.3)
	_check(not room.call("is_detailed"), "Auto with Low graphics is Simple")
	AppState.set_setting("graphics_quality", "high")
	await _secs(0.3)
	_check(room.call("is_detailed"), "and back to Detailed with High")

	# the glass gets the sky
	var glass := _first_active(room, "Glass_Lancet") as ShaderMaterial
	_check(glass != null and bool(glass.get_shader_parameter("is_lancet")) and int(glass.get_shader_parameter("glass_mode")) == 1,
		"the lancets show clear diamond panes")
	var rondel := _first_active(room, "Glass_Rondel") as ShaderMaterial
	_check(rondel != null and not bool(rondel.get_shader_parameter("is_lancet")), "the round windows stay stained glass")

	# the clock: the sun moves round, the beams follow
	var faces_evening := _beam_faces(room)
	_check(faces_evening > 0, "at 16:30 sunbeams come in (%d faces)" % faces_evening)
	var sun_evening: Vector3 = glass.get_shader_parameter("sun_to")
	AppState.set_setting("lh_time", 8.5)
	await _secs(0.3)
	var sun_morning: Vector3 = glass.get_shader_parameter("sun_to")
	_check(sun_morning.y > 0.1 and sun_morning.x * sun_evening.x < 0.0, "the morning sun is on the other side of the hall (%s vs %s)" % [sun_morning, sun_evening])
	_check(_beam_faces(room) > 0, "and its beams come in through the other windows (%d faces)" % _beam_faces(room))
	AppState.set_setting("lh_time", 0.5)
	await _secs(0.3)
	_check(float(glass.get_shader_parameter("day")) < 0.05, "half past midnight is night on the glass")
	AppState.set_setting("lh_day_minutes", 1.0)
	var h0: float = room.call("get_hour")
	await _secs(1.0)
	var h1: float = room.call("get_hour")
	_check(h1 > h0 + 0.2, "Day length 1 min runs the clock (%.2f -> %.2f h)" % [h0, h1])
	AppState.set_setting("lh_day_minutes", 0.0)

	# screenshots: every camera at the default hour, then the hours and glass choices
	AppState.set_setting("lh_time", 16.5)
	await _secs(0.3)
	var cams := room.get_camera_markers()
	for i in cams.size():
		EventBus.camera_preset_requested.emit(i)
		await _secs(1.0)
		await _shot(_out + "/lh_%02d_%s.png" % [i + 1, room.get_camera_label(cams[i]).replace(" ", "_")])
	var looks := [[8.0, "quarries", "morning"], [12.5, "quarries", "noon"], [17.8, "quarries", "sunset"], [22.5, "quarries", "night"],
		[12.5, "clear", "noon_clear"], [12.5, "stained", "noon_stained"]]
	for cam in [8, 4]:       # Gallery, Side Right (cameras that see the windows)
		EventBus.camera_preset_requested.emit(cam)
		await _secs(1.0)
		for look: Array in looks:
			AppState.set_setting("lh_time", float(look[0]))
			AppState.set_setting("lh_glass", String(look[1]))
			await _secs(0.5)
			await _shot(_out + "/lh_cam%d_%s.png" % [cam + 1, String(look[2])])
	# close-ups of a pair of lancets from the gallery opposite (a camera of the test's own)
	var marks := room.find_children("GLASS_*", "Node3D", true, false)
	var mk := marks[int(marks.size() * 0.25)] as Node3D
	var cam3 := Camera3D.new()
	cam3.fov = 40.0
	room.add_child(cam3)
	cam3.global_position = mk.global_position + mk.global_basis.z * 5.0 - Vector3.UP * 0.8
	cam3.look_at(mk.global_position, Vector3.UP)
	cam3.make_current()
	for look: Array in looks:
		AppState.set_setting("lh_time", float(look[0]))
		AppState.set_setting("lh_glass", String(look[1]))
		await _secs(0.5)
		await _shot(_out + "/lh_window_%s.png" % String(look[2]))
	cam3.queue_free()
	AppState.set_setting("lh_time", 16.5)
	AppState.set_setting("lh_glass", "quarries")

	# the panel copy uses the same script
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	room = host.get_current_room()
	_check(room != null and room.name == "LectureHallPanelRoom" and room.call("is_detailed") and _beam_faces(room) > 0,
		"the Lecture Hall (Panel) gets the same detail and beams")
	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
