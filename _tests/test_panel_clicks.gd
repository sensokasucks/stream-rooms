extends Node
## Control panel: mouse clicks on tick boxes, camera buttons and "?" buttons work.
## (They broke when the panel dropped keyboard focus on the mouse *press*: a button that loses
## focus mid-press cancels its click. Focus is now dropped on the release.)
##   <redot console exe> --path . _tests/test_panel_clicks.tscn -- C:/temp/sr_tests --mp-profile=test
## Docked: real clicks through the main window. Own window (F9): a test can't move the OS mouse
## into a second window, so it checks the focus timing that caused the bug instead.

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## A left click in the middle of a control, as the OS would send it to the main window.
func _click(c: Control) -> void:
	# (the panel can be scaled, so go through the canvas transform, not get_global_rect)
	var pos := c.get_global_transform_with_canvas() * (c.size * 0.5)
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	Input.parse_input_event(move)
	await get_tree().process_frame
	for down in [true, false]:
		Input.parse_input_event(_button_event(pos, down))
		await get_tree().process_frame
	await get_tree().process_frame


func _button_event(pos: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	return e


func _start(windowed: bool) -> Node:
	AppState.set_setting("panel_window", windowed)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(5.0)
	var panel: Node = main.get_node("ControlPanel")
	panel.visible = true
	if windowed and not panel.is_in_window():
		panel._apply_window_mode()      # (normally done a moment after start)
	await _secs(1.0)
	return main


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)

	# ── docked: real clicks ──
	var main: Node = await _start(false)
	var panel: Node = main.get_node("ControlPanel")
	var tabs: TabContainer = panel._tabs
	tabs.current_tab = 1          # Room tab: tick boxes, camera buttons, "?" buttons
	await _secs(0.3)
	var see: CheckBox = panel._checks["camera_see_through"]
	var before := bool(AppState.get_setting("camera_see_through"))
	await _click(see)
	_check(bool(AppState.get_setting("camera_see_through")) != before, "clicking a tick box changes its setting")
	await _click(see)
	_check(bool(AppState.get_setting("camera_see_through")) == before, "clicking it again changes it back")

	var cam_btn: Button = null
	for c in (panel._camera_box as Node).get_children():
		if c is Button and (c as Button).is_visible_in_tree():
			cam_btn = c
	var picked: Array[int] = []
	var on_preset := func(i: int) -> void: picked.append(i)
	EventBus.camera_preset_requested.connect(on_preset)
	if cam_btn:
		await _click(cam_btn)
	EventBus.camera_preset_requested.disconnect(on_preset)
	_check(cam_btn != null and picked.size() == 1, "clicking a camera button picks that camera")

	var q: Button = null
	for b in tabs.get_current_tab_control().find_children("*", "Button", true, false):
		if b.has_meta("help_q") and (b as Button).is_visible_in_tree():
			q = b
			break
	var hint: Label = q.get_parent().get_meta("help_label") if q and q.get_parent().has_meta("help_label") else null
	if q:
		await _click(q)
	_check(hint != null and hint.visible, "clicking a ? shows its help")

	# every tick box on every tab, on and off again (a crash here shows as a non-zero exit)
	var clicked := 0
	var stuck: Array[String] = []
	for t in tabs.get_tab_count():
		tabs.current_tab = t
		await _secs(0.3)
		for c in tabs.get_current_tab_control().find_children("*", "CheckBox", true, false):
			var cb := c as CheckBox
			if not cb.is_visible_in_tree() or cb.disabled:
				continue
			(tabs.get_current_tab_control() as ScrollContainer).ensure_control_visible(cb)   # (long tabs scroll)
			await get_tree().process_frame
			await get_tree().process_frame   # (the previous box may still be showing / hiding rows)
			var was := cb.button_pressed
			await _click(cb)
			if cb.button_pressed == was:
				# the layout moved under the mouse (the test clicks faster than a person): aim again
				await _secs(0.3)
				(tabs.get_current_tab_control() as ScrollContainer).ensure_control_visible(cb)
				await get_tree().process_frame
				await _click(cb)
			var changed := cb.button_pressed != was
			await get_tree().process_frame      # (a tick box can show / hide rows: let the layout settle)
			(tabs.get_current_tab_control() as ScrollContainer).ensure_control_visible(cb)
			await get_tree().process_frame
			await _click(cb)
			clicked += 1
			if not changed or cb.button_pressed != was:
				stuck.append("%s: %s (first click %s)" % [tabs.get_tab_title(t), cb.text, "changed it" if changed else "did nothing"])
	# every "?" on every tab, open and closed again
	var helps := 0
	var help_stuck := 0
	for t in tabs.get_tab_count():
		tabs.current_tab = t
		await _secs(0.3)
		for b in tabs.get_current_tab_control().find_children("*", "Button", true, false):
			if not b.has_meta("help_q") or not (b as Button).is_visible_in_tree():
				continue
			var h: Label = b.get_parent().get_meta("help_label") if b.get_parent().has_meta("help_label") else null
			(tabs.get_current_tab_control() as ScrollContainer).ensure_control_visible(b)
			await get_tree().process_frame
			var shown_before := h != null and h.visible
			await _click(b)
			var opened := h != null and h.visible != shown_before
			await get_tree().process_frame
			(tabs.get_current_tab_control() as ScrollContainer).ensure_control_visible(b)
			await get_tree().process_frame
			await _click(b)
			helps += 1
			if not opened or h.visible != shown_before:
				help_stuck += 1
				var hov: Control = get_viewport().gui_get_hovered_control()
				print("  ? stuck on ", tabs.get_tab_title(t), ": opened=", opened, " hint=", (h.text.left(60) if h else "none"),
					" at ", (b as Control).get_global_transform_with_canvas() * ((b as Control).size * 0.5), " hovered=", hov, " ", hov.get("text") if hov else "",
					" panel rect=", (panel._panel as Control).get_global_rect())
	_check(helps > 30 and help_stuck == 0, "every ? opens and closes its help (%d, %d didn't)" % [helps, help_stuck])
	# every camera button
	tabs.current_tab = 1
	await _secs(0.3)
	var cam_clicks := 0
	picked.clear()
	EventBus.camera_preset_requested.connect(on_preset)
	for c in (panel._camera_box as Node).get_children():
		if c is Button and (c as Button).is_visible_in_tree():
			(tabs.get_current_tab_control() as ScrollContainer).ensure_control_visible(c)
			await get_tree().process_frame
			await _click(c)
			cam_clicks += 1
	EventBus.camera_preset_requested.disconnect(on_preset)
	_check(cam_clicks > 0 and picked.size() == cam_clicks, "every camera button works (%d of %d)" % [picked.size(), cam_clicks])
	print("tick boxes clicked: ", clicked)
	_check(clicked > 20 and stuck.is_empty(), "every tick box clicks on and off (%d; stuck: %s)" % [clicked, ", ".join(stuck)])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/clicks_docked.png")
	main.queue_free()
	await _secs(1.0)

	# ── own window: focus stays through the press, goes after the release ──
	main = await _start(true)
	panel = main.get_node("ControlPanel")
	_check(panel.is_in_window(), "the panel opened in its own window")
	var win: Window = panel._window
	var box: CheckBox = panel._checks["camera_see_through"]
	box.grab_focus()
	win.window_input.emit(_button_event(Vector2.ZERO, true))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(box.has_focus(), "own window: a mouse press doesn't take the focus away mid-click")
	win.window_input.emit(_button_event(Vector2.ZERO, false))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not box.has_focus(), "own window: the focus goes after the release (Space still pauses)")
	main.queue_free()
	await _secs(1.0)

	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
