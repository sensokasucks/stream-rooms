extends Node
## NDI integration with a mock NDIFinder / VideoStreamNDI: main screen, auto-reconnect, presenter with alpha.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	NdiReceiver.mock_finder = load("res://_tests/mock_ndi/mock_finder.gd")
	EventBus.status_message.connect(func(t, e): print("STATUS ", t, " err=", e))
	EventBus.source_changed.connect(func(m): print("SOURCE ", m))
	var colors := [0]
	EventBus.screen_colors_changed.connect(func(l, c, r): colors[0] += 1; if colors[0] % 20 == 0: print("COLORS ", colors[0], " centre=", c))
	AppState.set_setting("ndi_source", "")
	for n in range(1, 5):
		AppState.set_setting(AppState.presenter_key(n, "on"), n == 2)
	AppState.set_setting(AppState.presenter_key(2, "source"), "ndi")
	AppState.set_setting(AppState.presenter_key(2, "ndi"), "PC (Avatar)")
	AppState.set_setting(AppState.presenter_key(2, "key"), false)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(4.0)
	var finder = main.get_node("ScreenFeed/NdiReceiver/NDIFinder")
	finder.set_sources(["PC (OBS)"])
	await _secs(0.5)
	var panel = main.get_node("ControlPanel")
	print("menu items=", panel._ndi_menu.item_count, " label=", panel._ndi_label.text)
	EventBus.ndi_connect_requested.emit("PC (OBS)")
	await _secs(1.0)
	var feed = main.get_node("ScreenFeed")
	print("mode=", AppState.get_source_mode(), " tex=", feed.get_texture(), " size=", feed.get_texture().get_size() if feed.get_texture() else null, " active=", AppState.is_playback_active())
	# a capture frame must not take over from NDI
	feed._on_capture_frame(Image.create(64, 64, false, Image.FORMAT_RGB8), [] as Array[Color])
	await _secs(0.3)
	print("after capture frame mode=", AppState.get_source_mode())
	EventBus.camera_preset_requested.emit(12)
	await _secs(2.0)
	await _shot(out + "/ndi_screen.png")
	# source goes away, then comes back with the avatar too: auto reconnect + presenter
	finder.set_sources([])
	await _secs(0.5)
	print("gone: mode=", AppState.get_source_mode())
	var s_obs = load("res://_tests/mock_ndi/mock_stream.gd").new(); s_obs.name = "PC (OBS)"
	var s_av = load("res://_tests/mock_ndi/mock_stream.gd").new(); s_av.name = "PC (Avatar)"; s_av.alpha = true
	finder.sources = [s_obs, s_av]
	finder.sources_changed.emit()
	await _secs(1.5)
	print("back: mode=", AppState.get_source_mode(), " presenters=", feed._ndi_presenters.keys(), " label2=", panel._pres_feed_labels[1].text)
	await _shot(out + "/ndi_presenter.png")
	EventBus.ndi_stop_requested.emit()
	await _secs(0.3)
	print("stopped: mode=", AppState.get_source_mode())
	AppState.set_setting(AppState.presenter_key(2, "source"), "camera")
	AppState.set_setting(AppState.presenter_key(2, "ndi"), "")
	AppState.set_setting(AppState.presenter_key(2, "key"), true)
	AppState.set_setting(AppState.presenter_key(3, "on"), true)
	AppState.set_setting("ndi_source", "")
	NdiReceiver.mock_finder = null
	print("DONE")
	AppState.request_quit()
