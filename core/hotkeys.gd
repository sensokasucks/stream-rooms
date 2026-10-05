extends Node
## Global hotkeys. Turns key presses into AppState calls / EventBus requests.
## Ignored while typing in a text box (Esc leaves the text box).
##   Space      pause to react        F     focus view (flat, full-frame video)
##   1-9, 0     camera presets (0 = 10th)        F10   clean feed (hide all UI)
##   PgUp/PgDn  previous/next room    F11   fullscreen
##   C          chat screen on/off (rooms with one)
##   B          stage curtain close / open      Shift+B  curtain reveal (lights, drum roll)
##   F9         control panel in its own window / back in the main window (handled by the panel)
## (Tab for the control panel is handled by the panel itself.)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or _in_keyboard_panel(focus):
		# typing, or moving through the control panel with the keyboard (F6): the key is the
		# control's. Esc leaves the box / the panel.
		if key.keycode == KEY_ESCAPE:
			focus.release_focus()
			get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_B and key.shift_pressed:
		AppState.reveal_curtain()
		get_viewport().set_input_as_handled()
		return
	if _handle(key.keycode):
		get_viewport().set_input_as_handled()


func _in_keyboard_panel(n: Node) -> bool:
	while n != null:
		if n.is_in_group("keyboard_panel"):
			return true
		n = n.get_parent()
	return false


func _handle(keycode: Key) -> bool:
	match keycode:
		KEY_SPACE:
			AppState.toggle_react_pause()
		KEY_F:
			AppState.toggle_focus_view()
		KEY_C:
			AppState.set_setting("chat_screen", not bool(AppState.get_setting("chat_screen")))
		KEY_R:
			AppState.set_setting("reply_screen", not bool(AppState.get_setting("reply_screen")))
		KEY_B:
			AppState.toggle_curtain()
		KEY_F10:
			AppState.toggle_clean_feed()
		KEY_PAGEUP:
			AppState.cycle_room(-1)
		KEY_PAGEDOWN:
			AppState.cycle_room(1)
		KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if keycode >= KEY_1 and keycode <= KEY_9:
				EventBus.camera_preset_requested.emit(int(keycode - KEY_1))
			elif keycode == KEY_0:
				EventBus.camera_preset_requested.emit(9)
			else:
				return false
	return true
