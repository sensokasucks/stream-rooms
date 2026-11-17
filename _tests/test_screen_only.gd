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
	# the clean look must not change the picture: the red disc in the middle keeps its colour
	await RenderingServer.frame_post_draw
	var mid := get_viewport().get_texture().get_image()
	var mid_px := mid.get_pixel(mid.get_width() / 2, mid.get_height() / 2)
	_check(absf(mid_px.r - 0.9) < 0.05 and absf(mid_px.g - 0.2) < 0.05, "the clean look shows the picture at full brightness (%s)" % mid_px)
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

	# Extra screens: sources of their own, placed by the layout
	var asked: Dictionary = {}      # slot -> [kind, address], as the set asks ExtraFeeds
	var ask_cb := func(slot: String, kind: String, address: String) -> void: asked[slot] = [kind, address]
	EventBus.extra_feed_requested.connect(ask_cb)
	var win := get_viewport().get_visible_rect().size
	var ex1 := room.find_child("Extra1", true, false) as ColorRect
	var ex2 := room.find_child("Extra2", true, false) as ColorRect
	_check(ex1 != null and ex2 != null and not ex1.visible, "extra screens exist and start off")
	var pic_path := OS.get_user_data_dir().path_join("so_test_extra.png")
	var pic := Image.create(320, 240, false, Image.FORMAT_RGBA8)     # 4:3, so the inset's shape can be told apart
	pic.fill(Color(0.1, 0.6, 0.9))
	pic.fill_rect(Rect2i(110, 70, 100, 100), Color(1.0, 0.85, 0.1))
	pic.save_png(pic_path)
	AppState.set_setting("so_extra_layout", "free")
	AppState.set_setting("so_extra_frame", 0.25)
	AppState.set_setting("so_extra_1_picture", pic_path)
	AppState.set_setting("so_extra_1_size", 0.25)
	AppState.set_setting("so_extra_1_x", 1.0)
	AppState.set_setting("so_extra_1_y", 1.0)
	AppState.set_setting("so_extra_1_source", "picture")
	await _secs(0.3)
	var m1 := ex1.material as ShaderMaterial
	_check(ex1.visible and bool(m1.get_shader_parameter("has_video")), "a picture file shows on extra screen 1")
	_check(absf(ex1.size.x - win.x * 0.25) < 2.0 and absf(ex1.size.x / ex1.size.y - 4.0 / 3.0) < 0.02, "the inset has its size and its picture's shape (%s)" % ex1.size)
	_check(absf(ex1.position.x + ex1.size.x - win.x) < 1.5 and absf(ex1.position.y + ex1.size.y - win.y) < 1.5, "and stays inside the window (%s)" % ex1.position)
	_check(rect.size.is_equal_approx(win), "insets leave the main picture filling the window")
	AppState.set_setting("so_extra_2_address", "rtmp://127.0.0.1:9/live/none")
	AppState.set_setting("so_extra_2_source", "stream")
	AppState.set_setting("so_extra_3_source", "tab")
	await _secs(0.3)
	_check(asked.get("so_extra_2", []) == ["stream", "rtmp://127.0.0.1:9/live/none"], "a stream address is asked from ExtraFeeds (%s)" % [asked.get("so_extra_2", [])])
	_check(asked.get("so_extra_3", []) == ["tab", "Extra screen 3"], "a browser tab is asked for by the screen's name")
	_check(asked.get("so_extra_1", ["x"]) == ["", ""], "a picture file needs no feed")
	_check(ex2.visible and not bool((ex2.material as ShaderMaterial).get_shader_parameter("has_video")), "a feed with no picture yet shows between videos")
	EventBus.extra_feed_texture_changed.emit("so_extra_2", tex)
	await _secs(0.2)
	_check(bool((ex2.material as ShaderMaterial).get_shader_parameter("has_video")), "ExtraFeeds' picture lands on its screen")
	AppState.set_setting("so_preset", "crt_tv")
	await _secs(0.2)
	_check(float(m1.get_shader_parameter("curve")) > 0.5, "extra screens wear the Look too")
	await _shot("extras_insets")
	AppState.set_setting("so_extra_fx", false)
	await _secs(0.2)
	_check(float(m1.get_shader_parameter("curve")) == 0.0 and float(mat.get_shader_parameter("curve")) > 0.5, "or stay clean while the main picture keeps it")
	AppState.set_setting("so_extra_layout", "side")
	await _secs(0.3)
	_check(absf(rect.size.x - win.x * 0.75) < 2.0 and ex1.position.x >= rect.size.x - 1.0, "Column on the right: the main picture moves left (%s)" % rect.size)
	_check(absf(ex1.size.y - ex2.size.y) < 1.0 and ex2.position.y > ex1.position.y, "the extra screens stack in the column")
	await _shot("extras_side")
	AppState.set_setting("so_extra_layout", "grid")
	await _secs(0.3)
	_check(rect.size.is_equal_approx(win * 0.5) and ex1.position.x >= win.x * 0.5 and ex2.position.y >= win.y * 0.5, "Two by two: four quarters")
	await _shot("extras_grid")
	get_window().size = Vector2i(900, 900)
	await _secs(0.4)
	_check(rect.size.is_equal_approx(get_viewport().get_visible_rect().size * 0.5), "the layout follows a resized window")
	get_window().size = Vector2i(1280, 720)
	for n in [1, 2, 3]:
		AppState.set_setting("so_extra_%d_source" % n, "off")
	AppState.set_setting("so_extra_fx", true)
	AppState.set_setting("so_extra_layout", "free")
	AppState.set_setting("so_preset", "clean")
	await _secs(0.4)
	_check(not ex1.visible and not ex2.visible and rect.size.is_equal_approx(get_viewport().get_visible_rect().size), "all off: the main picture has the window again")
	_check(asked.get("so_extra_2", ["x"]) == ["", ""], "and the feeds are stopped")
	EventBus.extra_feed_requested.disconnect(ask_cb)
	DirAccess.remove_absolute(pic_path)

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
