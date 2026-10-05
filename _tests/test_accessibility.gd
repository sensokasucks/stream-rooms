extends Node
## Panel size, keyboard mode, typed slider values, "?" help, colour-blind colours + chart letters,
## chat text outline + small-text warning, flash strength / photosensitive-safe mode.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _key(code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.shift_pressed = shift
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_scale", 1.0)
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("flash_strength", 1.0)
	# don't depend on the saved settings: the panel sits in the main window, the left chat window shows Twitch
	AppState.set_setting("panel_window", false)
	AppState.set_setting("chat_left", true)
	AppState.set_setting("chat_left_chat", "twitch")
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	AppState.set_curtain(false, "instant")
	var panel = main.get_node("ControlPanel")
	panel.visible = true
	# help buttons
	var qs: Array = panel._panel.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("help_q"))
	print("help '?' buttons: ", qs.size())
	# typed value
	var vol: HSlider = panel._sliders["volume"]
	var num: LineEdit = vol.get_parent().get_child(2)
	panel._apply_typed(vol, num, "%d%%", "55 %")
	await _secs(0.1)
	print("typed 55% -> volume=", AppState.get_setting("volume"), " box='", num.text, "'")
	panel._apply_typed(vol, num, "%d%%", "999")
	print("typed 999 -> volume=", AppState.get_setting("volume"), " (clamped)")
	AppState.set_setting("volume", 0.8)
	# keyboard mode
	var chat0 := bool(AppState.get_setting("chat_screen"))
	panel.focus_panel()
	await _secs(0.1)
	print("F6: panel has focus=", panel.has_keyboard_focus(), " owner=", get_viewport().gui_get_focus_owner())
	await _key(KEY_C)
	print("C (chat screen hotkey) in keyboard mode fired? ", bool(AppState.get_setting("chat_screen")) != chat0, " (want false)")
	var before = get_viewport().gui_get_focus_owner()
	await _key(KEY_TAB)
	print("Tab moved focus: ", get_viewport().gui_get_focus_owner() != before, " panel still shown=", panel._panel.visible)
	await _key(KEY_ESCAPE)
	print("Esc: panel focus=", panel.has_keyboard_focus())
	await _key(KEY_C)
	print("C after Esc fired? ", bool(AppState.get_setting("chat_screen")) != chat0, " (want true)")
	AppState.set_setting("chat_screen", chat0)
	# panel size
	AppState.set_setting("panel_scale", 1.5)
	await _secs(0.6)
	print("panel scale=", panel._panel.scale)
	panel._tabs.current_tab = 7
	await _secs(0.4)
	await _shot(out + "/a1_games_150.png")
	AppState.set_setting("panel_scale", 1.0)
	await _secs(0.6)
	# colour-blind + chart letters
	for b in panel._panel.find_children("*", "Button", true, false):
		if b.text == "Colour-blind safe colours":
			b.pressed.emit()
	print("kick colour=", AppState.get_setting("platform_color_kick").to_html(false), " youtube=", AppState.get_setting("platform_color_youtube").to_html(false))
	AudienceManager.apply_preset("quadrant_each")
	panel._tabs.current_tab = 6
	await _secs(0.8)
	await _shot(out + "/a2_seating_letters.png")
	AudienceManager.apply_preset("anyone")
	for g in AudienceManager.PLATFORMS:
		AppState.set_setting("platform_color_" + g, AppState.DEFAULTS["platform_color_" + g])
	# chat text: outline + small-text warning
	var side: SideChats = main.get_node("RoomHost").get_current_room().find_child("SideChats", false, false)
	var left := side.get_chat_window("chat_left")
	EventBus.chat_message_received.emit({"name": "TwitchTom", "platform": "twitch", "user_id": "tt", "text": "can you read this?", "color": "#9146ff", "timestamp": Time.get_unix_time_from_system()})
	AppState.set_setting("chat_left_outline", 1.0)
	await _secs(0.3)
	if left._cards.is_empty():
		print("FAIL the left chat window got no card for a Twitch message")
	else:
		print("outline px=", left._cards[-1]["rtl"].get_theme_constant("outline_size"))
	print("t step cam ", Time.get_ticks_msec())
	var cam: CameraRig = main.get_node("CameraRig")
	cam.global_position = Vector3(0, 4.5, 9)
	cam.look_at(Vector3(0, 5, -3.8), Vector3.UP)
	AppState.set_setting("chat_left_text", 0.6)
	print("t before tab4 ", Time.get_ticks_msec())
	panel._tabs.current_tab = 4
	await get_tree().process_frame
	print("t after tab4 frame ", Time.get_ticks_msec(), " est=", left.estimate_text_px())
	await _secs(1.5)
	print("estimated px=", snappedf(left.estimate_text_px(), 0.1), " warning shown=", panel._size_warnings["chat_left"].visible, " text='", panel._size_warnings["chat_left"].text.left(90), "'")
	await _shot(out + "/a3_chat_warning.png")
	AppState.set_setting("chat_left_text", 1.0)
	AppState.set_setting("chat_left_outline", 0.0)
	# flashes
	var layer = main.get_node("RoomHost").get_current_room().find_child("Reactions", true, false)
	AppState.set_setting("flash_strength", 0.5)
	print("flash k=", layer._flash_k(), " step=", layer._strobe_step(0.09))
	AppState.set_setting("photosensitive_safe", true)
	print("safe: flash k=", layer._flash_k(), " step=", layer._strobe_step(0.09), " police step=", layer._strobe_step(0.25))
	cam._shake_left = 0.0
	cam.shake(1.0, 1.0)
	print("safe: shake started=", cam._shake_left > 0.0, " (want false)")
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("flash_strength", 1.0)
	get_tree().quit()
