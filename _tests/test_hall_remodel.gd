extends Node
## Lecture hall remodel: tiers, doors, stained glass + set shaders.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _b2g(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	var room_id: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "lecture_hall"
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("camera_fov", 75.0)
	AppState.set_setting("house_lights", 1.0)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room(room_id)
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var room = main.get_node("RoomHost").get_current_room()
	print("room=", room.name, " set shaders=", room._set_shaders.size())
	var glass := 0
	var polished := 0
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var o = mi.get_surface_override_material(s)
			if o is ShaderMaterial and String(o.resource_name).begins_with("Glass_"):
				glass += 1
			elif o is BaseMaterial3D and (o.clearcoat_enabled or o.rim_enabled):
				polished += 1
	print("glass surfaces=", glass, " polished surfaces=", polished)
	var markers = room.find_children("GLASS_*", "Node3D", true, false)
	var bad := 0
	for m in markers:
		var to_mid: Vector3 = Vector3(0, m.global_position.y, 3.0) - m.global_position
		to_mid.y = 0
		if m.global_basis.z.dot(to_mid.normalized()) < 0.3:
			bad += 1
	print("GLASS markers=", markers.size(), " facing out=", bad)
	var sh = room.find_child("SunShafts", false, false)
	print("shafts verts=", sh.mesh.get_faces().size() if sh else -1, " (", (sh.mesh.get_faces().size() / 24) if sh else 0, " beams)")
	print("static meshes skip shafts=", not room.get_static_meshes().has(sh))
	var cam: CameraRig = main.get_node("CameraRig")
	var views := [
		["r1_pit_back", Vector3(0, -2, 2.0), Vector3(0, -12, 2.8)],
		["r2_stage", Vector3(0, 1.8, 3.6), Vector3(0, -10, 1.2)],
		["r3_door", Vector3(7.5, -1.5, 2.2), Vector3(14, -2.4, 2.4)],
		["r4_sun", Vector3(-6, 0.0, 2.2), Vector3(8, -8, 9.0)],
		["r5_balcony", Vector3(-10.8, -7, 8.8), Vector3(6, -2, 6.0)],
		["r6_windows", Vector3(0, -3, 7.0), Vector3(12, -9, 12.5)],
	]
	for v in views:
		cam.global_position = _b2g(v[1])
		cam.look_at(_b2g(v[2]), Vector3.UP)
		await _secs(1.2)
		await _shot(out + "/%s.png" % v[0])
	AppState.set_setting("house_lights", 0.12)
	await _secs(4.0)
	print("dimmed level=", snappedf(room._level, 0.01), " shaft level=", snappedf(float(room._set_shaders[0].get_shader_parameter("light_level")), 0.01))
	cam.global_position = _b2g(Vector3(0, 1.8, 3.6))
	cam.look_at(_b2g(Vector3(0, -10, 1.2)), Vector3.UP)
	await _secs(1.0)
	await _shot(out + "/r7_dimmed.png")
	print("DONE")
	AppState.request_quit()
