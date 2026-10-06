extends Node
## Presenter name tags and podium pictures: the tag shows above the picture, a PNG and an animated
## GIF show on the podium front with the right shape, clearing hides it, and a bad file is refused
## with a message.
##   <redot console exe> --path . _tests/test_presenter_extras.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _statuses: PackedStringArray = []


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if bool(cond.call()):
			return true
		await _secs(0.25)
		t += 0.25
	return bool(cond.call())


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	EventBus.status_message.connect(func(t: String, _e: bool) -> void: _statuses.append(t))
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("curtain_start_closed", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(6.0)
	var stage: Node = main.get_node("RoomHost").get_current_room().find_child("Presenters", true, false)
	var p: Presenter = stage.get_presenter(2)
	_check(p != null, "presenter 2 exists in the lecture hall")
	AppState.set_setting(AppState.presenter_key(2, "on"), true)

	# name tag
	_check(not p._tag.visible, "no name tag until one is typed")
	AppState.set_setting(AppState.presenter_key(2, "name"), "  Sen  ")
	_check(p._tag.visible and p._tag.text == "Sen", "the name tag shows the typed name, trimmed (%s)" % p._tag.text)
	_check(p._tag.position.y > p._plane_size.y, "the tag sits above the picture")

	# podium picture: a 64x32 PNG
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0.3, 0.1))
	var png := out.path_join("badge.png")
	img.save_png(png)
	AppState.set_setting(AppState.presenter_key(2, "picture"), png)
	_check(await _wait_for(func() -> bool: return p._badge.visible and p._badge_mat.albedo_texture != null, 5.0), "the PNG shows on the podium")
	var q: QuadMesh = p._badge.mesh
	_check(absf(q.size.x / q.size.y - 2.0) < 0.05, "the podium picture keeps the picture's shape (%.2f:1)" % (q.size.x / q.size.y))
	var podium_mesh: MeshInstance3D = p._podium_mesh()
	var podium_centre: Vector3 = podium_mesh.global_transform * podium_mesh.get_aabb().get_center() if podium_mesh else Vector3.ZERO
	_check(podium_mesh != null and p.to_local(p._badge.global_position).z > p.to_local(podium_centre).z,
		"the picture sits on the podium's front (towards the audience)")
	# a look at the podium without the panel in the way: a camera right in front of it
	main.get_node("ControlPanel").visible = false
	var cam: Camera3D = get_viewport().get_camera_3d()
	var podium_pos: Vector3 = p.global_position
	cam.global_position = podium_pos + Vector3(0.0, 1.0, 3.2)
	cam.look_at(podium_pos + Vector3(0.0, 0.9, 0.0), Vector3.UP)
	await _secs(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/presenter_extras.png")
	main.get_node("ControlPanel").visible = true

	# an animated GIF (2 frames, kept in _tests/assets)
	var gif := ProjectSettings.globalize_path("res://_tests/assets/badge_anim.gif")
	if FileAccess.file_exists(gif):
		AppState.set_setting(AppState.presenter_key(2, "picture"), gif)
		_check(await _wait_for(func() -> bool: return p._badge_mat.albedo_texture is AnimatedTexture, 8.0), "an animated GIF becomes an animated podium picture")
	else:
		print("(no _tests/assets/badge_anim.gif: animated GIF check skipped)")

	# bad file: refused with a message, nothing shown
	var bad := out.path_join("badge.txt")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("not a picture")
	f.close()
	_statuses.clear()
	AppState.set_setting(AppState.presenter_key(2, "picture"), bad)
	await _secs(1.0)
	var said := false
	for t in _statuses:
		if t.contains("couldn't read that picture"):
			said = true
	_check(said and not p._badge.visible, "a file that isn't a picture is refused with a message")

	# cleared
	AppState.set_setting(AppState.presenter_key(2, "picture"), "")
	await _secs(0.5)
	_check(not p._badge.visible, "clearing the picture hides it")
	AppState.set_setting(AppState.presenter_key(2, "name"), "")
	_check(not p._tag.visible, "clearing the name hides the tag")
	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
