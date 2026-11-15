extends Node
## Screen Only set (rooms/screen_only): it loads as a flat set (no curtain, no side chat windows,
## no audience), draws the big screen's picture over the whole window, every Look writes its
## values, the picture re-fits when the window changes size, and "between videos" shows while
## nothing plays. Also the two Stream Core hooks for video requests in core/rooms_remote.gd: the
## "video_prep" action and the state's "video" {now, ended, ended_n} line.
## Saves a screenshot per Look (and two window sizes) into the output folder.
##   <redot console exe> --path . _tests/test_screen_only.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## A colourful test picture (gradients, a grid and a white circle) so every effect has something to show.
func _test_texture() -> ImageTexture:
	var img := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	for y in 360:
		for x in 640:
			var c := Color(float(x) / 640.0, float(y) / 360.0, 1.0 - float(x) / 640.0)
			if x % 64 < 3 or y % 64 < 3:
				c = Color(0.95, 0.95, 0.95)
			if Vector2(x - 320, y - 180).length() < 70.0:
				c = Color(1, 1, 1) if Vector2(x - 320, y - 180).length() > 60.0 else Color(0.9, 0.2, 0.1)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	if _out != "":
		get_viewport().get_texture().get_image().save_png(_out.path_join("screen_only_%s.png" % name))


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 and not String(args[0]).begins_with("--") else ""
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", true)    # the panel in its own window keeps the screenshots clean
	AppState.set_setting("so_idle", "static")
	AppState.set_setting("so_fit", "fit")
	AppState.set_setting("photosensitive_safe", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("screen_only")
	await _secs(5.0)

	var host := main.get_node("RoomHost")
	var room: Room = host.call("get_current_room")
	_check(room != null and room.get_script() == load("res://rooms/screen_only/screen_only_room.gd"), "the Screen Only set loads")
	if room == null:
		print("DONE fails=%d" % (_fails + 1))
		AppState.request_quit(1)
		return
	_check(room.find_child("StageCurtain", true, false) == null, "no stage curtain in a flat set")
	_check(room.find_child("SideChats", true, false) == null, "no side chat windows")
	_check(room.find_child("Audience", true, false) == null, "no audience")
	var rect := room.find_child("Picture", true, false) as ColorRect
	_check(rect != null, "a full-window picture is built")
	var mat := rect.material as ShaderMaterial
	_check(mat != null and mat.shader != null, "with the effect shader")
	_check(rect.size.is_equal_approx(get_viewport().get_visible_rect().size), "covering the whole window (%s)" % rect.size)

	# nothing playing: between videos
	await _secs(0.3)
	_check(not bool(mat.get_shader_parameter("has_video")), "no picture yet: between videos shows")
	await _shot("idle_static")
	AppState.set_setting("so_idle", "standby")
	await _secs(0.2)
	var standby_shown := false
	for l in room.find_children("*", "Label", true, false):
		if (l as Label).visible and (l as Label).text == "Please stand by":
			standby_shown = true
	_check(standby_shown, "stand-by text shows with Between videos = Please stand by")
	await _shot("idle_standby")

	# a picture arrives (as if a video played)
	var tex := _test_texture()
	AppState.set_source_mode("file")
	EventBus.screen_texture_changed.emit(tex)
	await _secs(0.3)
	_check(bool(mat.get_shader_parameter("has_video")), "a picture on the big screen shows")
	_check(Vector2(mat.get_shader_parameter("video_size")).is_equal_approx(Vector2(640, 360)), "the shader knows the picture size")

	# every Look writes its values; take a picture of each
	var presets: Dictionary = room.get("PRESETS")
	for id: String in presets:
		AppState.set_setting("so_preset", id)
		await _secs(0.25)
		var values: Dictionary = (presets[id] as Array)[1]
		var ok := true
		for key: String in values:
			if AppState.get_setting(key) != values[key]:
				ok = false
		_check(ok, "Look '%s' sets its values" % id)
		await _shot("look_" + id)
	AppState.set_setting("so_preset", "clean")
	await _secs(0.2)
	_check(is_zero_approx(float(AppState.get_setting("so_curve"))) and String(AppState.get_setting("so_fun")) == "none",
		"Clean picture puts every effect back")

	# the curtain covers the picture: between videos again
	AppState.set_setting("curtain_enabled", true)
	AppState.set_curtain(true)
	await _secs(0.3)
	_check(AppState.is_curtain_covering(), "the curtain covers at once (no curtain to animate)")
	_check(not bool(mat.get_shader_parameter("has_video")), "and the set shows between videos")
	AppState.set_curtain(false)
	await _secs(0.3)
	_check(bool(mat.get_shader_parameter("has_video")), "curtain open: the picture is back")

	# resizing: the picture follows the window and the shader gets the new shape
	AppState.set_setting("so_preset", "crt_tv")
	AppState.set_setting("so_bars", "glow")
	await _secs(0.3)
	await _shot("crt_wide")
	get_window().size = Vector2i(900, 900)
	await _secs(0.6)
	var r := Vector2(mat.get_shader_parameter("rect_px"))
	_check(absf(r.x / r.y - 1.0) < 0.05, "a square window reaches the shader as a square (%s)" % r)
	await _shot("crt_square")
	get_window().size = Vector2i(1280, 720)
	await _secs(0.4)

	# photosensitive-safe cuts the flicker and rolling bar
	AppState.set_setting("photosensitive_safe", true)
	await _secs(0.1)
	_check(float(mat.get_shader_parameter("flicker")) <= float(AppState.get_setting("so_flicker")) * 0.26, "safe mode cuts the flicker")
	AppState.set_setting("photosensitive_safe", false)

	# Stream Core hooks: video_prep and the "video" line
	var remote := ChatFeed.get_remote()
	var prepped: Array = []
	var cb := func(input: String) -> void: prepped.append(input)
	EventBus.file_ready_requested.connect(cb)
	_check(remote.run_command("video_prep", "https://youtu.be/example"), "video_prep is accepted")
	_check(prepped == ["https://youtu.be/example"], "and asks for Just get it ready")
	_check(not remote.run_command("video_prep", "  "), "an empty video_prep is refused")
	EventBus.file_ready_requested.disconnect(cb)
	EventBus.file_started.emit("https://youtu.be/one")
	var st: Dictionary = remote.build_state()
	_check(String((st.get("video", {}) as Dictionary).get("now", "")) == "https://youtu.be/one", "the state names the video playing")
	EventBus.file_finished.emit("https://youtu.be/one")
	st = remote.build_state()
	var v: Dictionary = st.get("video", {})
	_check(String(v.get("ended", "")) == "https://youtu.be/one" and int(v.get("ended_n", 0)) == 1, "and the one that ended (count 1)")
	AppState.set_source_mode("none")
	st = remote.build_state()
	_check(String((st.get("video", {}) as Dictionary).get("now", "x")) == "", "no file on screen: nothing playing")

	# leave the test profile in a normal room, so the next test (same settings_test.cfg when run
	# by hand or by ci_tests.sh) doesn't start in a set without seats
	AppState.set_setting("room_id", "lecture_hall_panel")
	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
