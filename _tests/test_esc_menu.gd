extends Node
## The Esc game menu (ui/esc_menu.gd, work list item 4): Esc opens it in its own window (never in
## the captured room picture) and closes it again; Esc while typing doesn't; each page builds; its
## controls change the same settings as the panel; Display's window mode, monitor and size move the
## room window (core/display_mode.gd); Co-stream shows the session; Keys lists the shortcuts.
##   <redot console exe> --path . _tests/test_esc_menu.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## A key press (and release) as if typed on the room window.
func _press(code: Key) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = down
		Input.parse_input_event(k)
		await get_tree().process_frame


## Every Button / CheckBox / OptionButton / HSlider under n.
func _controls(n: Node, out: Array) -> Array:
	for c in n.get_children():
		if c is BaseButton or c is Range:
			out.append(c)
		_controls(c, out)
	return out


func _button(n: Node, text: String) -> Button:
	for c: Variant in _controls(n, []):
		if c is Button and (c as Button).text == text:
			return c
	return null


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("window_mode", "")
	AppState.set_setting("window_screen", -1)
	AppState.set_setting("window_size", "")
	AppState.set_setting("graphics_quality", "high")
	GraphicsQuality.set_level("high")
	AppState.set_setting("volume", 0.8)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(2.0)
	var menu: EscMenu = null
	for c in main.get_children():
		if c is EscMenu:
			menu = c
	_check(menu != null, "the room has an Esc menu")
	if menu == null:
		print("DONE fails=", _fails)
		AppState.request_quit(1)
		return

	# Esc opens it, in its own window
	_check(not menu.is_open(), "the menu starts closed")
	await _press(KEY_ESCAPE)
	await _secs(0.3)
	_check(menu.is_open(), "Esc opens the menu")
	var win: Window = menu._win
	_check(win.force_native or not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS), "the menu is its own window, not drawn in the captured picture")
	_check(menu._page == "Display", "it opens on Display")

	# every page builds, and every control explains itself
	for p: String in EscMenu.PAGES:
		menu._show_page(p)
		await get_tree().process_frame
		var missing: Array = []
		for c: Variant in _controls(menu._page_box, []):
			if String((c as Control).tooltip_text) == "" and not (c is Range and (c as Control).get_parent() is ScrollContainer):
				missing.append((c as Control).get_class())
		_check(missing.is_empty(), "%s page builds and every control has a tooltip %s" % [p, missing])
		await RenderingServer.frame_post_draw
		win.get_texture().get_image().save_png(_out.path_join("esc_menu_%s.png" % p.to_lower().replace("-", "")))
	for c: Variant in _controls(menu._win, []):
		if c is Button and String((c as Button).tooltip_text) == "":
			_check(false, "a menu button has no tooltip (%s)" % (c as Button).text)

	# Keys lists the shortcuts
	menu._show_page("Keys")
	var keys_text := ""
	for l in menu._page_box.find_children("*", "Label", true, false):
		keys_text += (l as Label).text + "\n"
	_check(keys_text.contains("Pause to react") and keys_text.contains("F11"), "Keys lists the shortcuts")

	# Sound: the slider is the panel's volume setting
	menu._show_page("Sound")
	var sliders: Array = menu._page_box.find_children("*", "HSlider", true, false)
	_check(sliders.size() == 3, "Sound has three sliders (%d)" % sliders.size())
	(sliders[0] as HSlider).value = 0.4
	_check(absf(float(AppState.get_setting("volume")) - 0.4) < 0.001, "the volume slider sets Video volume")
	AppState.set_setting("volume", 0.7)
	await get_tree().process_frame
	await get_tree().process_frame
	sliders = menu._page_box.find_children("*", "HSlider", true, false)
	_check(absf((sliders[0] as HSlider).value - 0.7) < 0.001, "a change from the panel shows in the open menu")

	# Display: graphics quality and frame rate are the panel's settings
	menu._show_page("Display")
	_button(menu._page_box, "Medium").pressed.emit()
	_check(String(AppState.get_setting("graphics_quality")) == "medium" and not bool(AppState.get_setting("gfx_gi")), "Graphics quality Medium picks the Medium preset")
	_button(menu._page_box, "30").pressed.emit()
	_check(int(AppState.get_setting("fps_cap")) == 30, "Frame rate cap 30")
	AppState.set_setting("fps_cap", 60)
	GraphicsQuality.set_level("high")

	# Display: the window itself
	var room_win := get_window()
	var screen := room_win.current_screen
	var full := DisplayServer.screen_get_size(screen)
	await get_tree().process_frame
	menu._show_page("Display")
	_button(menu._page_box, "Borderless").pressed.emit()
	await _secs(0.5)
	_check(String(AppState.get_setting("window_mode")) == "borderless", "Borderless is saved")
	_check(room_win.borderless and room_win.size == full, "Borderless covers the monitor (%s, screen %s)" % [room_win.size, full])
	AppState.set_setting("window_size", "1280x720")
	await _secs(0.5)
	_check(room_win.borderless and room_win.size == Vector2i(mini(1280, full.x), mini(720, full.y)), "a picked size keeps Borderless at that size (%s)" % room_win.size)
	AppState.set_setting("window_mode", "windowed")
	await _secs(0.5)
	_check(not room_win.borderless and room_win.mode == Window.MODE_WINDOWED, "Windowed has a frame again")
	_check(room_win.size.x <= 1280 and room_win.size.y <= 720 and room_win.size.x >= 1000, "Windowed uses the picked size (%s)" % room_win.size)
	_check(DisplayMode.parse_size("1920x1080") == Vector2i(1920, 1080) and DisplayMode.parse_size("") == Vector2i.ZERO and DisplayMode.parse_size("12x9") == Vector2i.ZERO, "window sizes are read safely")
	AppState.set_setting("window_size", "")
	AppState.set_setting("window_mode", "")

	# Co-stream: off -> Host / Join; Join waits for an address
	AppState.set_setting("together_address", "")
	menu._show_page("Co-stream")
	await get_tree().process_frame
	var host_btn := _button(menu._page_box, "Host a session")
	var join_btn := _button(menu._page_box, "Join")
	_check(host_btn != null and join_btn != null and join_btn.disabled, "Co-stream offers Host and Join (Join needs the host's address first)")
	var labels := ""
	for l in menu._page_box.find_children("*", "Label", true, false):
		labels += (l as Label).text + "\n"
	_check(labels.contains("Not in a co-stream") and labels.contains("Everyone follows the host's"), "it says you're not in a co-stream and shows what guests follow")

	# Esc while typing in a box doesn't open the menu
	menu.close()
	_check(not menu.is_open(), "Resume closes it")
	var box := LineEdit.new()
	add_child(box)
	box.grab_focus()
	await _press(KEY_ESCAPE)
	await _secs(0.2)
	_check(not menu.is_open(), "Esc while typing leaves the box instead of opening the menu")
	box.queue_free()
	await _press(KEY_ESCAPE)
	await _secs(0.2)
	_check(menu.is_open(), "Esc opens it again")
	menu.toggle()
	_check(not menu.is_open(), "and Esc (toggle) closes it")

	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
