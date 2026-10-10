extends CanvasLayer
## Control panel (Tab to hide/show). Thin UI: it shows AppState / EventBus data
## and forwards user input to AppState setters or EventBus requests. No logic.

@export var panel_width: float = 580.0

var _panel: PanelContainer
var _url: LineEdit
var _capture_label: Label
var _capture_url: String = ""
var _room_select: OptionButton
var _camera_box: HFlowContainer
var _react_btn: Button
var _mic_bar: ProgressBar
var _duck_label: Label
var _dialog: FileDialog
var _sliders: Dictionary = {}     # setting key -> HSlider
var _checks: Dictionary = {}      # setting key -> CheckBox
var _colors: Dictionary = {}      # setting key -> ColorPickerButton
var _room_box: VBoxContainer      # this room's own controls (rebuilt on every room change)
var _room_keys: Array[String] = []
var _chat_label: Label
var _options: Dictionary = {}          # setting key -> OptionButton (values in item metadata)
var _pres_count_label: Label
var _pres_details: Array[Control] = []
var _size_warnings: Dictionary = {}       # chat window key -> Label ("text too small on stream")
var _size_check: float = 1.0
var _scale_pending: float = 0.0           # panel size change waiting for the slider to settle
var _pres_rows: Array[Dictionary] = []    # per presenter: {camera, ndi, url, key, picture[]} rows shown by source
var _pres_feed_labels: Array[Label] = []
var _pres_camera_menus: Array[OptionButton] = []
var _pres_edit_buttons: Array[Button] = []
var _last_cams_json: String = "[]"
var _seat_label: Label
var _ndi_menu: OptionButton
var _ndi_label: Label
var _ndi_names: PackedStringArray = []
var _ndi_available: bool = false
var _pres_ndi_menus: Array[OptionButton] = []
var _spout_menu: OptionButton
var _spout_label: Label
var _spout_names: PackedStringArray = []
var _spout_available: bool = false
var _pres_spout_menus: Array[OptionButton] = []
var _user_hidden: bool = false
var _window: Window               # the panel's own OS window (F9), null while docked
var _window_btn: Button
var _panel_style: StyleBoxFlat
var _pos_check: float = 0.0
var _curtain_label: Label
var _gfx_hint: Label
var _tabs: TabContainer
var _platform_boxes: Dictionary = {}      # "<window>_chat" -> {group: CheckBox}
var _mix_warnings: Dictionary = {}        # "<window>_chat" -> Label (Twitch mixed with others)
var _chart: SeatingChart
var _section_label: Label
var _section_boxes: Dictionary = {}       # group -> CheckBox (the picked section's platforms)
var _capacity_label: Label
var _texts: Dictionary = {}               # setting key -> LineEdit (text settings)
var _syncing: bool = false                # a control is being set to match a setting (don't write it back)
var _curtain_buttons: Array[Button] = []
var _net_status: Label
var _net_pw_hint: Label          # Together: "this password is short"
var _net_peers: VBoxContainer
var _net_host_btn: Button
var _net_join_btn: Button
var _net_leave_btn: Button
var _net_medium: HBoxContainer
var _net_live: HBoxContainer
var _net_live_label: Label
var _net_copy_btn: Button
var _pic_dialog: FileDialog
var _pic_target: String = ""              # the presenter_<n>_picture setting the picture dialog is for
var _net_addr_label: Label
var _net_dialogs: Dictionary = {}       # peer id -> ConfirmationDialog (someone wants in / is this the right host)
var _peer_menus: Dictionary = {}        # setting key -> OptionButton listing the people in the session (whose avatar)
var _avatar_camera: OptionButton        # Together tab: the camera for my avatar
var _avatar_rows: Dictionary = {}       # Together tab: "camera" / "url" rows, shown by My avatar's source
var _size_marks: Dictionary = {}        # chat window key -> small ⚠ Label in the window's summary row
var _size_need: Dictionary = {}         # chat window key -> text size (as the setting) that would be readable
var _source_pick: OptionButton          # Source tab: which source's controls show
var _source_sections: Dictionary = {}   # source mode -> its VBox on the Source tab
## "What's going on", on every tab: the status strip above the tabs and the message line below them.
const MESSAGE_HISTORY: int = 10
var _strip: Dictionary = {}             # "core" / "screen" / "together" -> Button in the status strip
var _msg_btn: Button                    # footer: the latest message
var _msg_fold: VBoxContainer            # footer: the last few messages, and the "on the picture" tick
var _msg_list: VBoxContainer
var _messages: Array[Dictionary] = []   # newest first: {time, text, error}
var _core_was_connected: bool = false
var _now_label: Label                   # Source tab: "On the big screen now: ..."
var _capture_info: Dictionary = {}      # the sender page's last status
var _video_status: Label                # File section: download / convert progress or the reason it failed
var _video_retry: Button
var _video_details: Label
var _video_details_fold: VBoxContainer
var _video_state: String = ""           # "", "downloading", "converting", "ready", "failed"
var _video_started_ms: int = 0
var _video_tick: float = 0.0
var _last_video_input: String = ""      # what Play was last asked to load (for Try again)


func _ready() -> void:
	_ndi_available = NdiReceiver.is_available()
	_spout_available = SpoutReceiver.is_available()
	_build()
	EventBus.capture_status_changed.connect(_on_capture_status)
	EventBus.camera_presets_changed.connect(_on_camera_presets)
	EventBus.room_changed.connect(_on_room_changed)
	EventBus.room_controls_changed.connect(_on_room_controls)
	EventBus.react_pause_changed.connect(_on_react_pause_changed)
	EventBus.mic_level_changed.connect(_on_mic_level)
	EventBus.ducking_changed.connect(_on_ducking)
	EventBus.clean_feed_changed.connect(func(_c: bool) -> void: _refresh_visible())
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.chat_status_changed.connect(_on_chat_status)
	EventBus.audience_count_changed.connect(_on_audience_count)
	EventBus.room_presenters_changed.connect(_on_room_presenters)
	EventBus.ndi_sources_changed.connect(_on_ndi_sources)
	EventBus.source_changed.connect(func(_m: String) -> void:
		_refresh_ndi_label()
		_refresh_spout_label())
	EventBus.spout_senders_changed.connect(_on_spout_senders)
	EventBus.status_message.connect(_on_status_message)
	EventBus.source_changed.connect(func(_m: String) -> void: _refresh_now())
	EventBus.video_job_changed.connect(_on_video_job)
	EventBus.file_play_requested.connect(func(input: String) -> void:
		if input.strip_edges() != "":
			_last_video_input = input)
	_core_was_connected = bool(ChatFeed.get_status().get("connected", false))
	_on_chat_status(ChatFeed.get_status())
	_refresh_now()
	EventBus.curtain_changed.connect(func(_c: bool, _s: String) -> void: _refresh_curtain_label())
	EventBus.net_state_changed.connect(_on_net_state)
	EventBus.net_confirm_needed.connect(_on_net_confirm_needed)
	EventBus.net_confirm_closed.connect(_on_net_confirm_closed)
	_on_net_state(NetSession.get_info())
	if bool(AppState.get_setting("panel_window")):
		_apply_window_mode.call_deferred()


func _input(event: InputEvent) -> void:
	# on the button's release, not its press: losing focus mid-press cancels a button's click
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_drop_mouse_focus.call_deferred(get_viewport())
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F6:
		focus_panel()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F9:
		toggle_window()
		get_viewport().set_input_as_handled()
	elif has_keyboard_focus():
		# keyboard mode: Tab / Shift+Tab move between controls, Esc leaves (hotkeys come back)
		if key.keycode == KEY_ESCAPE:
			_release_panel_focus()
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_TAB:
		_user_hidden = not _user_hidden
		_refresh_visible()
		get_viewport().set_input_as_handled()


## Keyboard mode (F6): the first control of the open tab gets focus; Tab / Shift+Tab move,
## arrows change sliders / tabs, Space / Enter press, Esc leaves.
func focus_panel() -> void:
	_user_hidden = false
	_refresh_visible()
	if _window:
		_window.grab_focus()
	var bar := _tabs.get_tab_bar()
	bar.focus_mode = Control.FOCUS_ALL
	bar.grab_focus()
	EventBus.status_message.emit("Keyboard: Tab / Shift+Tab move, arrows change, Space / Enter press, Esc leaves.", false)


## Does a control in the panel have the keyboard focus (so keys belong to it, not the hotkeys)?
func has_keyboard_focus() -> bool:
	var vp: Viewport = _window if _window else get_viewport()
	var f := vp.gui_get_focus_owner()
	return f != null and _panel.is_ancestor_of(f)


func _release_panel_focus() -> void:
	var vp: Viewport = _window if _window else get_viewport()
	var f := vp.gui_get_focus_owner()
	if f:
		f.release_focus()


## A mouse click leaves no focus behind (so Space still pauses instead of pressing the last button
## clicked); text boxes keep it so you can type.
func _drop_mouse_focus(vp: Viewport) -> void:
	if not is_instance_valid(vp):
		return
	var f := vp.gui_get_focus_owner()
	if f and _panel.is_ancestor_of(f) and not (f is LineEdit or f is TextEdit):
		f.release_focus()


func _process(delta: float) -> void:
	if _video_state == "downloading" or _video_state == "converting":
		_video_tick -= delta
		if _video_tick <= 0.0:
			_video_tick = 1.0
			_show_video_status()
	_size_check -= delta
	if _size_check <= 0.0:
		_size_check = 1.0
		_check_text_sizes()
	if _scale_pending > 0.0:
		_scale_pending -= delta
		if _scale_pending <= 0.0:
			_apply_scale()
	# remember where the panel window sits
	if _window == null:
		return
	_pos_check -= delta
	if _pos_check <= 0.0:
		_pos_check = 2.0
		_save_window_pos()


# ── Own window (F9) ──────────────────────────────────────────
## Moves the panel into its own OS window (so a window capture of the main window never shows
## it) or back into the main window.
func toggle_window() -> void:
	AppState.set_setting("panel_window", not bool(AppState.get_setting("panel_window")))
	_apply_window_mode()


func is_in_window() -> bool:
	return _window != null


func _apply_window_mode() -> void:
	var want := bool(AppState.get_setting("panel_window"))
	if want and _window == null:
		if not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
			EventBus.status_message.emit("This system can't open a second window; the panel stays here.", true)
			AppState.set_setting("panel_window", false)
			return
		get_tree().root.gui_embed_subwindows = false
		_window = Window.new()
		_window.title = AppState.with_profile("Stream Rooms — controls")
		_window.wrap_controls = false
		var w := int((maxf(panel_width, _panel.get_combined_minimum_size().x) + 20.0) * _panel_scale())     # (every tab name fits)
		_window.min_size = Vector2i(w, 360)
		_window.transient = false
		_window.close_requested.connect(func() -> void:
			_save_window_pos()
			_user_hidden = true
			_refresh_visible())
		_window.window_input.connect(_on_window_input)
		add_child(_window)
		_panel.reparent(_window, false)
		_panel.position = Vector2.ZERO
		_panel_style.bg_color.a = 1.0
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		_window.size = Vector2i(w, mini(900, usable.size.y - 80))
		_window.size_changed.connect(_fit_height)
		var saved := String(AppState.get_setting("panel_window_pos")).split(",")
		if saved.size() == 2 and saved[0].is_valid_int() and saved[1].is_valid_int():
			_window.position = Vector2i(int(saved[0]), int(saved[1]))
		else:
			_window.position = DisplayServer.window_get_position() + Vector2i(40, 40)
		_user_hidden = false
		EventBus.status_message.emit("Control panel in its own window (F9 puts it back).", false)
	elif not want and _window != null:
		_save_window_pos()
		_panel.reparent(self, false)
		_panel.position = Vector2(16, 16)
		_panel_style.bg_color.a = 0.88
		_window.hide()
		_window.queue_free()
		_window = null
		(func() -> void: get_tree().root.gui_embed_subwindows = true).call_deferred()
	_fit_height.call_deferred()
	_window_btn.text = "Back in the main window (F9)" if _window else "Own window (F9)"
	_refresh_visible()


## The tabs take the height that's there (the main window's, or the panel window's); each tab
## scrolls inside it.
func _fit_height() -> void:
	if _tabs == null:
		return
	var avail: float
	var k := _panel_scale()
	if _window:
		avail = float(_window.size.y) / k
		_panel.size = Vector2(_window.size) / k
	else:
		avail = (get_viewport().get_visible_rect().size.y - 32.0) / k
	var extra := 0.0
	for c in _tabs.get_parent().get_children():
		if c != _tabs and (c as Control).visible:
			extra += (c as Control).get_combined_minimum_size().y + 4.0
	_tabs.custom_minimum_size.y = maxf(avail - extra - 24.0, 240.0)
	if not _window:
		_panel.size.y = 0.0       # shrink to fit the new minimum


func _save_window_pos() -> void:
	if _window == null:
		return
	var p := "%d,%d" % [_window.position.x, _window.position.y]
	if p != String(AppState.get_setting("panel_window_pos")):
		AppState.set_setting("panel_window_pos", p)


## Keys pressed in the panel window still work as hotkeys (unless you're typing in a box).
func _on_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_drop_mouse_focus.call_deferred(_window)     # (on release, see _input)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F6:
		focus_panel()
		_window.set_input_as_handled()
		return
	var focus := _window.gui_get_focus_owner()
	if focus != null and key.keycode != KEY_F9:
		if key.keycode == KEY_ESCAPE:
			focus.release_focus()
			_window.set_input_as_handled()
		return      # typing, or keyboard mode: the key belongs to the control
	if key.keycode == KEY_TAB:
		_user_hidden = true
		_refresh_visible()
	elif key.keycode == KEY_F9:
		toggle_window()
	else:
		Input.parse_input_event(event.duplicate())     # (a fresh event: the engine won't parse one twice a frame)
	if _window:        # (F9 just closed the panel's window)
		_window.set_input_as_handled()


# ── Build ────────────────────────────────────────────────────
func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 16)
	_panel.custom_minimum_size = Vector2(panel_width, 0)
	var style := StyleBoxFlat.new()
	_panel_style = style
	style.bg_color = Color(0.05, 0.05, 0.07, 0.88)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.theme = _focus_theme()
	_panel.add_to_group("keyboard_panel")
	add_child(_panel)
	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	outer.add_child(_build_status_strip())
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(panel_width - 20, 0)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.clip_tabs = false      # every tab name stays in view (the panel widens a little instead)
	outer.add_child(_tabs)
	# every tab scrolls, so nothing is cut off at the bottom of a small screen / window
	for page: Control in [_build_source_tab(), _build_room_tab(), _build_react_tab(), _build_audio_tab(),
			_build_chat_tab(), _build_audience_tab(), _build_seating_tab(), _build_games_tab(), _build_presenters_tab(),
			_build_together_tab()]:
		var sc := ScrollContainer.new()
		sc.name = page.name
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(page)
		_tabs.add_child(sc)
	get_viewport().size_changed.connect(_fit_height)
	_fit_height.call_deferred()
	var hint := Label.new()
	hint.text = "Tab panel | F6 keyboard (Esc leaves) | F9 own window | Space react pause | F focus | B curtain (Shift+B reveal) | 1-9, 0 cameras | PgUp/PgDn rooms | F10 clean feed | right-drag look"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(panel_width - 20, 0)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	outer.add_child(hint)
	var bottom := HBoxContainer.new()
	outer.add_child(bottom)
	_window_btn = _button("Own window (F9)", toggle_window)
	_window_btn.tooltip_text = "Move this panel into its own window, so a window capture of the room never shows it."
	bottom.add_child(_window_btn)
	var size_row := _slider("panel_scale", "Panel size", 0.75, 2.0, 0.05, "%d%%", 100.0)
	size_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(size_row.get_child(0) as Label).custom_minimum_size = Vector2(80, 0)
	size_row.tooltip_text = "Makes everything in this panel bigger or smaller (text, buttons, sliders). Ctrl+= / Ctrl+- also work."
	bottom.add_child(size_row)
	_build_message_line(outer)
	_add_help_buttons(_panel)
	_apply_scale.call_deferred()

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.title = "Choose a video"
	_dialog.filters = PackedStringArray(["*.ogv, *.mp4, *.mkv, *.webm, *.mov, *.avi, *.m4v ; Videos", "* ; All files"])
	_dialog.file_selected.connect(func(p: String) -> void:
		_url.text = p
		EventBus.file_play_requested.emit(p))
	add_child(_dialog)
	_pic_dialog = FileDialog.new()
	_pic_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_pic_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_pic_dialog.use_native_dialog = true
	_pic_dialog.title = "Choose a podium picture"
	_pic_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.gif ; Pictures"])
	_pic_dialog.file_selected.connect(func(p: String) -> void:
		if _pic_target != "":
			AppState.set_setting(_pic_target, p))
	add_child(_pic_dialog)


func _build_source_tab() -> Control:
	var v := _tab("Source")
	# one source at a time: pick what the big screen shows, see only that source's controls
	var pick_row := HBoxContainer.new()
	v.add_child(pick_row)
	var pl := _heading("Big screen shows")
	pl.custom_minimum_size = Vector2(120, 0)
	pick_row.add_child(pl)
	_source_pick = OptionButton.new()
	_source_pick.focus_mode = Control.FOCUS_ALL
	_source_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_pick.tooltip_text = "Which kind of source the controls below are for: a browser tab from the sender page, an NDI source, a Spout program, a video file or web link, or someone's avatar from a Streaming together session. It follows whatever starts playing.\nPicking one here doesn't change the screen: press Share / Show / Play in that section."
	for it: Array in [["capture", "Browser tab (sender page)"], ["ndi", "NDI (OBS / NDI Tools)"], ["spout", "Spout (programs on this PC)"],
			["file", "File or URL"], ["peer", "Someone's avatar (Streaming together)"]]:
		_source_pick.add_item(String(it[1]))
		_source_pick.set_item_metadata(_source_pick.item_count - 1, it[0])
	_source_pick.item_selected.connect(func(i: int) -> void:
		AppState.set_setting("source_tab_pick", String(_source_pick.get_item_metadata(i)))
		_show_source_section(String(_source_pick.get_item_metadata(i))))
	pick_row.add_child(_source_pick)
	_now_label = _hint("")
	_now_label.tooltip_text = "What the big screen shows right now, whichever source controls are open below."
	_now_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_now_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_now_label)
	var cap := VBoxContainer.new()
	cap.add_theme_constant_override("separation", 6)
	v.add_child(cap)
	_source_sections["capture"] = cap
	var ndi_box := VBoxContainer.new()
	ndi_box.add_theme_constant_override("separation", 6)
	v.add_child(ndi_box)
	_source_sections["ndi"] = ndi_box
	var spout_box := VBoxContainer.new()
	spout_box.add_theme_constant_override("separation", 6)
	v.add_child(spout_box)
	_source_sections["spout"] = spout_box
	var file_box := VBoxContainer.new()
	file_box.add_theme_constant_override("separation", 6)
	v.add_child(file_box)
	_source_sections["file"] = file_box
	var peer_box := VBoxContainer.new()
	peer_box.add_theme_constant_override("separation", 6)
	v.add_child(peer_box)
	_source_sections["peer"] = peer_box

	v = cap
	v.add_child(_heading("Browser tab (live)"))
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_button("Open sender page", func() -> void:
		if _capture_url != "": OS.shell_open(_capture_url)))
	_capture_label = Label.new()
	_capture_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_capture_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capture_label.text = "Not connected."
	row.add_child(_capture_label)
	var how := Label.new()
	how.text = "Open the sender page in Brave, click Share, pick the YouTube tab and keep \"Share tab audio\" on."
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_fold(v, "source_capture").add_child(how)

	v = peer_box
	v.add_child(_heading("Someone's avatar (Streaming together)"))
	var sp := _peer_menu("screen_peer", "Whose avatar")
	(sp.get_child(1) as Control).tooltip_text = "In a Streaming together session: put a person's avatar (their My avatar from the Together tab) on the big screen, at the avatar quality. Pick (nobody) to go back to your own shared tab. The host's choice goes to every PC in the session."
	v.add_child(sp)

	v = ndi_box
	v.add_child(_heading("NDI (OBS / NDI Tools)"))
	var nr := HBoxContainer.new()
	v.add_child(nr)
	_ndi_menu = OptionButton.new()
	_ndi_menu.focus_mode = Control.FOCUS_ALL
	_ndi_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ndi_menu.fit_to_longest_item = false
	_ndi_menu.tooltip_text = "NDI sources on your network: OBS (DistroAV > NDI main output, or an NDI filter on a source), NDI Tools, other PCs."
	nr.add_child(_ndi_menu)
	var show_ndi := _button("Show", func() -> void:
		if _ndi_menu.selected >= 0 and _ndi_menu.get_item_metadata(_ndi_menu.selected) != null:
			EventBus.ndi_connect_requested.emit(String(_ndi_menu.get_item_metadata(_ndi_menu.selected))))
	show_ndi.tooltip_text = "Show the picked NDI source on the big screen, with its sound."
	nr.add_child(show_ndi)
	var stop_ndi := _button("Stop", func() -> void: EventBus.ndi_stop_requested.emit())
	stop_ndi.tooltip_text = "Stop showing the NDI source."
	nr.add_child(stop_ndi)
	# the status line stays out of the fold: it says why the list is empty (plugin, runtime, OBS)
	_ndi_label = Label.new()
	_ndi_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ndi_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	v.add_child(_ndi_label)
	var ndi_adv := _fold(v, "source_ndi")
	ndi_adv.add_child(_check("ndi_auto", "Reconnect to the last source by itself"))
	var nb := _slider("ndi_audio_buffer_ms", "Sound buffer", 50.0, 1500.0, 10.0, "%d ms")
	nb.tooltip_text = "How much NDI sound is queued before it plays. More rides out hiccups on the network / OBS side,\nbut the sound runs that much behind the picture. Needs the patched NDI plugin."
	ndi_adv.add_child(nb)
	_fill_ndi_menu(_ndi_menu, String(AppState.get_setting("ndi_source")), "(pick a source)")
	_refresh_ndi_label()

	v = spout_box
	v.add_child(_heading("Spout (programs on this PC)"))
	var sr := HBoxContainer.new()
	v.add_child(sr)
	_spout_menu = OptionButton.new()
	_spout_menu.focus_mode = Control.FOCUS_ALL
	_spout_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spout_menu.fit_to_longest_item = false
	_spout_menu.tooltip_text = "Programs on this PC sharing their picture over Spout: VTube Studio, OBS (with the Spout2 plugin), TouchDesigner, some games. The picture goes straight from the graphics card, with no delay or blur."
	sr.add_child(_spout_menu)
	var show_spout := _button("Show", func() -> void:
		if _spout_menu.selected >= 0 and _spout_menu.get_item_metadata(_spout_menu.selected) != null:
			EventBus.spout_connect_requested.emit(String(_spout_menu.get_item_metadata(_spout_menu.selected))))
	show_spout.tooltip_text = "Show the picked Spout sender on the big screen."
	sr.add_child(show_spout)
	var stop_spout := _button("Stop", func() -> void: EventBus.spout_stop_requested.emit())
	stop_spout.tooltip_text = "Stop showing the Spout sender."
	sr.add_child(stop_spout)
	_spout_label = Label.new()
	_spout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spout_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	v.add_child(_spout_label)      # (status, not help: stays out of the fold)
	var spout_adv := _fold(v, "source_spout")
	var sauto := _check("spout_auto", "Show the last sender again by itself")
	sauto.tooltip_text = "When the last Spout sender you showed starts again (and nothing else is on the screen), show it without clicking."
	spout_adv.add_child(sauto)
	_fill_name_menu(_spout_menu, _spout_names, String(AppState.get_setting("spout_source")), "(pick a sender)")
	_refresh_spout_label()

	v = file_box
	v.add_child(_heading("File or URL"))
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	_url = LineEdit.new()
	_url.placeholder_text = "YouTube URL or path to a video file"
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url.text_submitted.connect(func(t: String) -> void:
		_url.release_focus()
		EventBus.file_play_requested.emit(t))
	r1.add_child(_url)
	r1.add_child(_button("Play", func() -> void: EventBus.file_play_requested.emit(_url.text)))
	r1.add_child(_button("Browse...", func() -> void: _dialog.popup_centered_ratio(0.6)))
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	r2.add_child(_button("Pause / resume", func() -> void: EventBus.file_pause_toggle_requested.emit()))
	r2.add_child(_button("Stop", func() -> void: EventBus.file_stop_requested.emit()))
	r2.add_child(_check("loop_files", "Loop"))
	var q := OptionButton.new()
	for h in [480, 720, 1080]:
		q.add_item("%dp" % h, h)
	q.select(q.get_item_index(int(AppState.get_setting("max_height"))))
	q.tooltip_text = "Resolution for downloads/conversion. Lower converts faster."
	q.item_selected.connect(func(i: int) -> void: AppState.set_setting("max_height", q.get_item_id(i)))
	r2.add_child(q)
	# download / convert progress, or why it failed (plain words; the tool's own log under Details)
	var r3 := HBoxContainer.new()
	v.add_child(r3)
	_video_status = _hint("")
	_video_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_status.visible = false
	r3.add_child(_video_status)
	_video_retry = _button("Try again", func() -> void:
		if _last_video_input != "":
			EventBus.file_play_requested.emit(_last_video_input))
	_video_retry.tooltip_text = "Load the same file or link again (for example after updating yt-dlp with tools\\get_tools.ps1)."
	_video_retry.visible = false
	r3.add_child(_video_retry)
	_video_details_fold = _fold(v, "source_video_details", "Details")
	(_video_details_fold.get_meta("fold_head") as Control).visible = false
	_video_details = _hint("")
	_video_details.tooltip_text = "What yt-dlp / ffmpeg printed last. Useful when asking for help."
	_video_details_fold.add_child(_video_details)
	# start on what plays now, else the last pick, else the browser tab
	var pick := String(AppState.get_setting("source_tab_pick"))
	var playing := AppState.get_source_mode()
	if _source_sections.has(playing):
		pick = playing
	elif not _source_sections.has(pick):
		pick = "capture"
	_show_source_section(pick)
	EventBus.source_changed.connect(func(mode: String) -> void:
		if _source_sections.has(mode):
			_show_source_section(mode))
	return _source_sections["capture"].get_parent() as Control


## Source tab: show one source's controls, and point the picker at it.
func _show_source_section(mode: String) -> void:
	for m: String in _source_sections:
		(_source_sections[m] as Control).visible = m == mode
	for i in _source_pick.item_count:
		if String(_source_pick.get_item_metadata(i)) == mode:
			_source_pick.select(i)
	_fit_height.call_deferred()


func _build_room_tab() -> Control:
	var v := _tab("Room")
	v.add_child(_heading("Room"))
	_room_select = OptionButton.new()
	for id in RoomCatalog.get_ids():
		_room_select.add_item(RoomCatalog.get_info(id).display_name)
		_room_select.set_item_metadata(_room_select.item_count - 1, id)
	_room_select.item_selected.connect(func(i: int) -> void:
		AppState.request_room(String(_room_select.get_item_metadata(i))))
	v.add_child(_room_select)
	v.add_child(_slider("house_lights", "House lights", 0.0, 1.0, 0.01, "%d%%", 100.0))
	_build_curtain_controls(v)
	v.add_child(_heading("Cameras (keys 1-9, 0 = 10th)"))
	_camera_box = HFlowContainer.new()
	v.add_child(_camera_box)
	v.add_child(_slider("camera_fov", "Field of view", 25.0, 110.0, 1.0, "%d°"))
	# set-up-once settings: curtain options, this room's own looks, the camera's see-through, performance
	var adv := _fold(v, "room")
	_build_curtain_options(adv)
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 6)
	adv.add_child(_room_box)
	adv.add_child(_heading("Camera"))
	adv.add_child(_check("camera_see_through", "See into the room from outside (instead of black)"))
	_build_performance_controls(adv)
	return v


## Graphics quality preset + its switches, and the frame-rate cap (core/graphics_quality.gd).
func _build_performance_controls(v: VBoxContainer) -> void:
	v.add_child(_heading("Performance (this PC)"))
	var q := _option("graphics_quality", "Graphics quality", [["low", "Low"], ["medium", "Medium"], ["high", "High"], ["custom", "Custom"]])
	q.tooltip_text = "One switch for the expensive effects. Applies right away. Remembered on this PC, not per room."
	v.add_child(q)
	_gfx_hint = _hint(GraphicsQuality.describe(String(AppState.get_setting("graphics_quality"))))
	v.add_child(_gfx_hint)
	var sw := HFlowContainer.new()
	v.add_child(sw)
	var gi := _check("gfx_gi", "Bounce light (SDFGI)")
	gi.tooltip_text = "Light bouncing off walls and floors. The most expensive effect; rooms get a little extra ambient light when it's off."
	sw.add_child(gi)
	var ao := _check("gfx_ssao", "Ambient occlusion")
	ao.tooltip_text = "Soft shading in corners and under seats."
	sw.add_child(ao)
	var ssr := _check("gfx_ssr", "Reflections")
	ssr.tooltip_text = "Screen-space reflections (Neon City's wet street)."
	sw.add_child(ssr)
	var fog := _option("gfx_fog", "Fog", [["off", "Off"], ["low", "Low res"], ["full", "Full"]])
	fog.tooltip_text = "Volumetric fog and light beams (projector beam, stage lights). Low res is coarser but much cheaper."
	v.add_child(fog)
	var sh := _option("gfx_shadows", "Shadows", [["low", "Low"], ["medium", "Medium"], ["high", "High"]])
	sh.tooltip_text = "Soft shadow quality and shadow map size."
	v.add_child(sh)
	var aa := _option("gfx_msaa", "Anti-aliasing", [[0, "Off (FXAA)"], [2, "MSAA 2x"], [4, "MSAA 4x"]])
	aa.tooltip_text = "Smooths jagged 3D edges. Off uses cheap FXAA instead."
	v.add_child(aa)
	var rs := _slider("gfx_render_scale", "3D resolution", 0.5, 1.0, 0.05, "%d%%", 100.0)
	rs.tooltip_text = "Draws the 3D room at a lower resolution and scales it up with AMD FSR. Text, chat windows and this panel stay sharp. 75% is a big saving on a laptop."
	v.add_child(rs)
	var fps := _option("fps_cap", "Frame rate cap", [[30, "30 fps"], [60, "60 fps"], [0, "Unlimited"]])
	fps.tooltip_text = "Most frames drawn per second. Set it to the frame rate you stream at: a 144-165 Hz laptop screen otherwise makes the GPU draw 2-3 times the frames the stream needs."
	v.add_child(fps)
	var vs := _check("vsync", "V-Sync")
	vs.tooltip_text = "Wait for the display refresh: no tearing on your screen. OBS captures the same frames either way. If 60 fps stutters on a 144 Hz screen, try V-Sync off."
	v.add_child(vs)


func _build_curtain_controls(v: VBoxContainer) -> void:
	v.add_child(_heading("Stage curtain (B, Shift+B = reveal)"))
	var row := HFlowContainer.new()
	v.add_child(row)
	_curtain_buttons = [_button("Close", func() -> void: AppState.set_curtain(true)),
		_button("Open", func() -> void: AppState.set_curtain(false)),
		_button("Reveal", func() -> void: AppState.reveal_curtain()),
		_button("Be right back", func() -> void:
			AppState.set_setting("curtain_sign", "Be right back")
			AppState.set_curtain(true))]
	for b in _curtain_buttons:
		row.add_child(b)
	_curtain_label = Label.new()
	_curtain_label.modulate = Color(1, 1, 1, 0.7)
	row.add_child(_curtain_label)
	_refresh_curtain_label()
	v.add_child(_text_setting("curtain_sign", "Sign", "shown on the closed curtain (blank = none)"))


## The curtain's set-up-once options (Room tab > Advanced).
func _build_curtain_options(v: VBoxContainer) -> void:
	v.add_child(_heading("Curtain options"))
	var r2 := HFlowContainer.new()
	v.add_child(r2)
	r2.add_child(_check("curtain_enabled", "Curtain in rooms"))
	r2.add_child(_check("curtain_start_closed", "Start closed"))
	r2.add_child(_check("curtain_mute", "Mute stream sound while closed"))
	r2.add_child(_check("curtain_show_lights", "Reveal dims the lights"))
	v.add_child(_color("curtain_color", "Curtain colour"))
	v.add_child(_slider("curtain_speed", "Curtain speed", 0.25, 3.0, 0.05, "%d%%", 100.0))
	v.add_child(_slider("curtain_sound", "Curtain sounds", 0.0, 1.0, 0.01, "%d%%", 100.0))


func _refresh_curtain_label() -> void:
	if _curtain_label:
		_curtain_label.text = "closed" if AppState.is_curtain_closed() else "open"


func _build_react_tab() -> Control:
	var v := _tab("React")
	var row := HBoxContainer.new()
	v.add_child(row)
	_react_btn = _button("Pause to react (Space)", func() -> void: AppState.toggle_react_pause())
	row.add_child(_react_btn)
	row.add_child(_button("Focus view (F)", func() -> void: AppState.toggle_focus_view()))
	row.add_child(_button("Clean feed (F10)", func() -> void: AppState.toggle_clean_feed()))
	v.add_child(_check("react_lights_up", "Raise the lights while paused"))
	v.add_child(_check("react_camera", "Jump to the Reaction camera while paused"))
	v.add_child(_check("auto_dim_house", "Dim room lights while playing"))
	v.add_child(_check("webcam_in_room", "Show webcam in the room (off = corner overlay)"))

	v.add_child(_heading("Auto-duck when I talk"))
	v.add_child(_check("duck_enabled", "Lower the video while the mic hears me"))
	var meter := HBoxContainer.new()
	v.add_child(meter)
	var ml := Label.new()
	ml.text = "Mic"
	ml.custom_minimum_size = Vector2(120, 0)
	meter.add_child(ml)
	_mic_bar = ProgressBar.new()
	_mic_bar.min_value = -60.0
	_mic_bar.max_value = 0.0
	_mic_bar.show_percentage = false
	_mic_bar.custom_minimum_size = Vector2(0, 14)
	_mic_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_child(_mic_bar)
	_duck_label = Label.new()
	_duck_label.custom_minimum_size = Vector2(80, 0)
	meter.add_child(_duck_label)
	v.add_child(_slider("duck_threshold_db", "Talk threshold", -60.0, -10.0, 1.0, "%d dB"))
	v.add_child(_slider("duck_amount_db", "Duck by", -30.0, -3.0, 1.0, "%d dB"))
	return v


func _build_audio_tab() -> Control:
	var v := _tab("Sound")
	v.add_child(_slider("volume", "Video volume", 0.0, 1.0, 0.01, "%d%%", 100.0))
	v.add_child(_slider("ambience_volume", "Room ambience", 0.0, 1.0, 0.01, "%d%%", 100.0))
	v.add_child(_slider("room_acoustics", "Room acoustics", 0.0, 2.0, 0.01, "%d%%", 100.0))
	v.add_child(_slider("room_speaker", "Speaker FX", 0.0, 1.0, 0.01, "%d%%", 100.0))
	v.add_child(_slider("audio_delay_ms", "Audio delay", 0.0, 800.0, 10.0, "%d ms"))
	v.add_child(_slider("video_delay_ms", "Video delay", 0.0, 800.0, 10.0, "%d ms"))
	var tip := Label.new()
	tip.text = "Lip-sync: if the sound is early, raise Audio delay. If the picture is early, raise Video delay."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	v.add_child(tip)
	v.add_child(_slider("screen_light", "Screen light", 0.0, 4.0, 0.05, "%.2f"))
	v.add_child(_slider("screen_glow", "Screen glow", 0.2, 4.0, 0.05, "%.2f"))
	return v


func _build_chat_tab() -> Control:
	var v := _tab("Chat")
	v.add_child(_heading("Chat (Fridge Stream Core)"))
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_check("chat_enabled", "Connect"))
	_chat_label = Label.new()
	_chat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_chat_label)
	row.add_child(_button("Retry now", func() -> void: ChatFeed.reconnect()))
	v.add_child(_text_setting("chat_core_url", "Core address", "ws://127.0.0.1:3850/ws"))
	var test_row := HBoxContainer.new()
	v.add_child(test_row)
	test_row.add_child(_button("Test chat", func() -> void: ChatFeed.send_test_chat()))
	var tl := _hint("Made-up chatters on Kick, Twitch and YouTube.")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_row.add_child(tl)

	v.add_child(_heading("Chat windows"))
	v.add_child(_hint("One line per window: tick Show, then tick the platforms it shows. One platform per window keeps chats apart (Twitch asks for its chat to be kept separate); several tick mixes them. Advanced ▸ has replies, header, text size, looks and position."))
	var shared := HFlowContainer.new()
	v.add_child(shared)
	shared.add_child(_check("chat_screen_pictures", "Chatter pictures"))
	var hc := _check("chat_screen_hide_commands", "Hide !commands")
	hc.tooltip_text = "Leave !commands (like !tomato) out of the chat windows. The audience bubbles have their own setting."
	shared.add_child(hc)
	var hold := _slider("reply_screen_hold_s", "Keep each reply", 0.0, 300.0, 5.0, "%d s")
	hold.tooltip_text = "How long a Stream Core reply stays up. 0 = until newer ones push it off."
	v.add_child(hold)
	_chat_window(v, "chat_left", "Left of the screen", "Tall window beside the main screen, every room with a screen.", true)
	_chat_window(v, "chat_right", "Right of the screen", "Tall window beside the main screen, every room with a screen.", true)
	_chat_window(v, "chat_screen", "Under the screen (C)", "Rooms with a chat panel under the screen (Lecture Hall (Panel)).", false)
	_chat_window(v, "reply_screen", "Above the screen (R)", "Rooms with a reply screen above the main screen (Lecture Hall (Panel)).", false)

	v.add_child(_heading("Chat games boards"))
	var r6 := HBoxContainer.new()
	v.add_child(r6)
	var bl := Label.new()
	bl.text = "Boards in the corner"
	bl.custom_minimum_size = Vector2(120, 0)
	r6.add_child(bl)
	var hud := OptionButton.new()
	hud.focus_mode = Control.FOCUS_ALL
	var modes := [["auto", "Auto (when no chat window shows them)"], ["on", "Always"], ["off", "Never"]]
	for m: Array in modes:
		hud.add_item(String(m[1]))
		if String(m[0]) == String(AppState.get_setting("board_hud")):
			hud.select(hud.item_count - 1)
	hud.item_selected.connect(func(i: int) -> void: AppState.set_setting("board_hud", String(modes[i][0])))
	hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r6.add_child(hud)
	v.add_child(_slider("board_hud_scale", "Board size", 0.5, 2.5, 0.05, "%d%%", 100.0))

	v.add_child(_heading("Chat box on the picture"))
	var ch := _option("chat_hud", "Chat box", [["auto", "Auto (when no chat window shows chat)"], ["on", "Always"], ["off", "Never"]])
	(ch.get_child(1) as Control).tooltip_text = "A chat box in a corner of the picture, like the chat games boards. Auto shows it only in rooms where no chat window shows chat."
	(ch.get_child(1) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(ch)
	var hud_row := HBoxContainer.new()
	v.add_child(hud_row)
	var hl := Label.new()
	hl.text = "Shows"
	hl.custom_minimum_size = Vector2(120, 0)
	hud_row.add_child(hl)
	var hud_chips := _platform_chips("chat_hud_chat")
	hud_chips.tooltip_text = "Which platforms' chat the chat box shows."
	hud_row.add_child(hud_chips)
	var hud_spacer := Control.new()
	hud_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_row.add_child(hud_spacer)
	var hud_adv := _fold(v, "chat_hud", "Advanced", hud_row)
	var corner := _option("chat_hud_corner", "Corner", [["bottom_left", "Bottom left"], ["bottom_right", "Bottom right"], ["top_left", "Top left"], ["top_right", "Top right (shares it with the boards)"]])
	(corner.get_child(1) as Control).tooltip_text = "Which corner of the picture the chat box sits in."
	hud_adv.add_child(corner)
	var hw := _slider("chat_hud_width", "Box width", 0.1, 0.9, 0.01, "%d%%", 100.0)
	hw.tooltip_text = "How wide the chat box is, as a share of the picture."
	hud_adv.add_child(hw)
	var hh := _slider("chat_hud_height", "Box height", 0.1, 0.95, 0.01, "%d%%", 100.0)
	hh.tooltip_text = "How tall the chat box is, as a share of the picture."
	hud_adv.add_child(hh)
	_chat_window_options(hud_adv, "chat_hud", "A box on the picture (not in the room), so it shows from every camera.", false)
	return v


## One chat window's settings: show it, its platforms, replies, looks (and, beside the
## screen, its size and position).
func _chat_window(v: VBoxContainer, key: String, title: String, where: String, side: bool) -> void:
	# the summary row: Show, the window's name, its platforms, a ⚠ when the text is too small, Advanced
	var head := HBoxContainer.new()
	v.add_child(head)
	var show_box := _check(key, "")
	show_box.tooltip_text = "Show this window. " + where
	head.add_child(show_box)
	var t := _heading(title)
	t.add_theme_font_size_override("font_size", 14)
	t.custom_minimum_size = Vector2(150, 0)
	head.add_child(t)
	head.add_child(_platform_chips(key + "_chat"))
	var mark := Label.new()
	mark.text = "⚠"
	mark.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	mark.visible = false
	head.add_child(mark)
	_size_marks[key] = mark
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_chat_window_options(_fold(v, "chat_" + key, "Advanced", head), key, where, side)


## A chat window's Advanced options: replies, header, text size, looks (and, beside the screen,
## its size and position).
func _chat_window_options(v: VBoxContainer, key: String, where: String, side: bool) -> void:
	v.add_child(_hint(where))
	v.add_child(_mix_warning(key + "_chat"))
	v.add_child(_option(key + "_replies", "Stream Core replies", [["off", "Off"], ["on", "Always"], ["fallback", "When there's no reply screen"]]))
	if AppState.DEFAULTS.has(key + "_replies_for"):
		var rf := _option(key + "_replies_for", "Replies to", [["all", "Every platform's chatters"], ["chat", "Only this window's platforms"]])
		rf.tooltip_text = "Which chatters' Stream Core replies this window shows. A window with no chat ticked shows them all."
		v.add_child(rf)
	if AppState.DEFAULTS.has(key + "_header_on"):
		var hh := _text_setting(key + "_header", "Header", "Automatic (e.g. \"Twitch chat\")")
		var hc := _check(key + "_header_on", "Show")
		hc.tooltip_text = "A header line across the top of the window. Leave the text empty to name it after what it shows."
		hh.add_child(hc)
		v.add_child(hh)
	v.add_child(_slider(key + "_text", "Text size", 0.5, 3.0, 0.05, "%d%%", 100.0))
	var warn_row := HBoxContainer.new()
	var warn := _hint("")
	warn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warn_row.add_child(warn)
	var fix := _button("Make readable", func() -> void:
		if _size_need.has(key):
			AppState.set_setting(key + "_text", float(_size_need[key])))
	fix.tooltip_text = "Set this window's Text size to the smallest that reads well on a 1080p stream from the camera in use."
	warn_row.add_child(fix)
	warn_row.visible = false
	v.add_child(warn_row)
	_size_warnings[key] = warn
	warn.set_meta("row", warn_row)
	warn.set_meta("fix", fix)
	v.add_child(_slider(key + "_bg", "Background", 0.0, 1.0, 0.01, "%d%%", 100.0))
	var ol := _slider(key + "_outline", "Text outline", 0.0, 1.0, 0.05, "%d%%", 100.0)
	ol.tooltip_text = "A dark edge round every letter, so the text stays readable over the room when the background is see-through (low Background)."
	v.add_child(ol)
	if AppState.DEFAULTS.has(key + "_columns") and not side:
		v.add_child(_slider(key + "_columns", "Columns", 1.0, 4.0, 1.0, "%d"))
	if side:
		v.add_child(_slider(key + "_width", "Width", 0.8, 6.0, 0.05, "%.2f m"))
		v.add_child(_slider(key + "_height", "Height", 0.3, 1.6, 0.01, "%d%%", 100.0))
		v.add_child(_slider(key + "_gap", "Gap to screen", -1.0, 4.0, 0.05, "%.2f m"))
		v.add_child(_slider(key + "_lift", "Up / down", -4.0, 4.0, 0.05, "%.2f m"))


## Kick / Twitch / YouTube / Other ticks bound to a comma-separated platforms setting.
func _platform_row(key: String, label: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	var h := HBoxContainer.new()
	box.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	h.add_child(_platform_chips(key))
	box.add_child(_mix_warning(key))
	return box


## The platform ticks on their own (a chat window's summary row).
func _platform_chips(key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.tooltip_text = "Which platforms' chat this window shows."
	var boxes: Dictionary = {}
	var have := String(AppState.get_setting(key)).split(",", false)
	for g in AudienceManager.PLATFORMS:
		var c := CheckBox.new()
		c.text = String(AudienceManager.PLATFORM_LABELS[g])
		c.focus_mode = Control.FOCUS_ALL
		c.button_pressed = have.has(g)
		c.add_theme_color_override("font_color", AudienceManager.platform_color(g).lightened(0.3))
		c.toggled.connect(func(_on: bool) -> void:
			var picked := PackedStringArray()
			for g2: String in boxes.keys():
				if (boxes[g2] as CheckBox).button_pressed:
					picked.append(g2)
			AppState.set_setting(key, ",".join(picked)))
		h.add_child(c)
		boxes[g] = c
	_platform_boxes[key] = boxes
	return h


func _mix_warning(key: String) -> Label:
	var warn := _hint("⚠ Twitch chat mixed with other platforms in this window.")
	warn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	_mix_warnings[key] = warn
	_refresh_mix_warning(key)
	return warn


func _refresh_mix_warning(key: String) -> void:
	var have := String(AppState.get_setting(key)).split(",", false)
	(_mix_warnings[key] as Label).visible = have.has("twitch") and have.size() > 1


func _build_audience_tab() -> Control:
	var v := _tab("Audience")
	v.add_child(_heading("Virtual audience"))
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	r2.add_child(_check("audience_enabled", "Show audience"))
	_seat_label = Label.new()
	_seat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seat_label.text = "No seats in this room."
	r2.add_child(_seat_label)
	r2.add_child(_button("Test chat", func() -> void: ChatFeed.send_test_chat()))
	r2.add_child(_button("Clear", func() -> void: AudienceManager.clear()))
	v.add_child(_option("audience_seating", "New chatters sit", [
		["random", "Anywhere (random)"],
		["front", "Front row first, from the middle"],
		["front_random", "Front row first, random seat in the row"],
	]))
	var idle := _slider("audience_idle_min", "Idle timeout", 1.0, 60.0, 1.0, "%d min")
	idle.tooltip_text = "Minutes without chatting before someone gives up a main seat."
	v.add_child(idle)
	var gap := _slider("audience_seat_gap", "Seat spacing", 0.5, 1.6, 0.05, "%.2f m")
	gap.tooltip_text = "Room between seated chatters along a row. Seats closer than this to a taken one stay empty, so people don't sit shoulder to shoulder; the room has fewer seats then. 0.50 m uses every seat. The room reloads when you change it."
	v.add_child(gap)
	v.add_child(_slider("audience_bubble_s", "Bubble time", 2.0, 20.0, 0.5, "%.1f s"))
	v.add_child(_slider("audience_bubble_size", "Bubble size", 0.4, 2.5, 0.05, "%d%%", 100.0))
	var bubble_colours := _option("audience_bubble_theme", "Bubble colours", [
		["light", "Light (white bubbles, dark text)"],
		["dark", "Dark (dark bubbles, light text)"],
	])
	bubble_colours.tooltip_text = "The colour of the audience's speech bubbles. The outline keeps each chatter's colour either way."
	v.add_child(bubble_colours)
	var tints := _check("audience_bubble_tints", "Colour paid and highlighted messages")
	tints.tooltip_text = "Super Chats, Kicks and Bits get a gold bubble and chat-window card; Twitch messages highlighted with channel points get a purple one; a gigantified emote is drawn big. Off: they look like any other message."
	v.add_child(tints)
	var r3 := HFlowContainer.new()
	v.add_child(r3)
	r3.add_child(_check("audience_names", "Name tags"))
	r3.add_child(_check("audience_show_empty", "Show empty seats"))
	r3.add_child(_check("audience_hide_commands", "Hide !commands in bubbles"))
	var pics := _check("audience_avatars", "Chatter pictures")
	pics.tooltip_text = "Chatters' profile pictures (Kick, Twitch, YouTube) as their heads and in the chat windows. Stream Core finds and saves the pictures; for Twitch it needs Connect Twitch in Core's dashboard."
	r3.add_child(pics)
	v.add_child(_check("audience_titles", "Regulars' titles on name tags"))
	v.add_child(_text_setting("audience_ignore", "Ignore names", "bots, comma separated"))
	var hide_row := _text_setting("audience_hide_avatars", "Hide pictures of", "names, comma separated")
	(hide_row.get_child(1) as Control).tooltip_text = "People whose picture is never shown. The names are also added to Stream Core's list (Chatter profile pictures card), so Core's chat overlay hides them too. To show someone again, take them off here and in Core's dashboard."
	v.add_child(hide_row)

	v.add_child(_heading("Colours"))
	var cb := _option("audience_color_by", "Colour chatters by", [
		["chat", "Their chat colour (else from their name)"],
		["name", "Picked from their name"],
		["platform", "Their platform"],
	])
	cb.tooltip_text = "Silhouettes, name tags, bubbles and chat windows. \"Their platform\" makes it easy to see who's on which platform."
	v.add_child(cb)
	var pc := HFlowContainer.new()
	v.add_child(pc)
	for g in AudienceManager.PLATFORMS:
		var c := _color("platform_color_" + g, String(AudienceManager.PLATFORM_LABELS[g]))
		(c.get_child(0) as Label).custom_minimum_size = Vector2(56, 0)
		(c.get_child(1) as Control).custom_minimum_size = Vector2(60, 24)
		pc.add_child(c)
	var pr := HBoxContainer.new()
	v.add_child(pr)
	var safe := _button("Colour-blind safe colours", func() -> void:
		for g: String in COLOR_SAFE.keys():
			AppState.set_setting("platform_color_" + g, Color(String(COLOR_SAFE[g]))))
	safe.tooltip_text = "Kick bluish green, Twitch reddish purple, YouTube orange, other sky blue: colours that stay apart for the common kinds of colour blindness (Okabe-Ito palette). The seating chart also marks sections with letters."
	pr.add_child(safe)
	pr.add_child(_button("Brand colours", func() -> void:
		for g in AudienceManager.PLATFORMS:
			AppState.set_setting("platform_color_" + g, AppState.DEFAULTS["platform_color_" + g])))

	v.add_child(_heading("Crowd (Lecture Hall tiers, balcony, gallery)"))
	var crowd_row := HBoxContainer.new()
	v.add_child(crowd_row)
	var crowd_check := _check("audience_crowd", "Filler crowd")
	crowd_check.tooltip_text = "Rooms with a big crowd fill it with filler people. When the main seats are full, chatters take their places."
	crowd_row.add_child(crowd_check)
	var fill := _slider("audience_crowd_fill", "Crowd fullness", 0.0, 1.0, 0.01, "%d%%", 100.0)
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crowd_row.add_child(fill)
	var crowd_idle := _slider("audience_crowd_idle_min", "Crowd timeout", 1.0, 60.0, 1.0, "%d min")
	crowd_idle.tooltip_text = "Minutes without chatting before a chatter gives up a crowd seat. Presenters linked to chat never time out."
	v.add_child(crowd_idle)
	var crowd_max := _slider("audience_crowd_max", "Most chatters in crowd", 0.0, 400.0, 10.0, "%d")
	crowd_max.tooltip_text = "How many chatters can sit in the crowd seats at once. 0 = no limit. Every seat stays and filler people fill the rest, so the room looks the same; each chatter in the crowd costs a little CPU and GPU (picture, name tag, bubble), filler people cost nothing. When it's reached, a new chatter takes the seat of whoever has been quiet the longest. Try 100-150 on a laptop."
	v.add_child(crowd_max)
	var crowd_opts := HFlowContainer.new()
	v.add_child(crowd_opts)
	var down := _check("audience_crowd_move_down", "Crowd chatters move down")
	down.tooltip_text = "When a main seat frees up, the most recently active chatter in the crowd moves down into it."
	crowd_opts.add_child(down)
	var fm := _check("audience_fill_main", "Filler people in empty main seats")
	fm.tooltip_text = "Empty main seats show filler people too (the same share as Crowd fullness). Chatters take their places as they arrive."
	crowd_opts.add_child(fm)
	return v


func _build_seating_tab() -> Control:
	var v := _tab("Seating")
	v.add_child(_heading("Seating by platform"))
	v.add_child(_hint("Keep each platform's chatters physically apart. The main seats are four quadrants (as the audience faces the stage); the Lecture Hall's crowd seats are stadium sections: 101… lower tier, 201… balcony, 301… gallery, numbered from the audience's left round to the right. Click a section on the chart, then tick who may sit there (no ticks = anyone)."))
	var r := HFlowContainer.new()
	v.add_child(r)
	r.add_child(_check("seating_by_platform", "Seat chatters by platform"))
	var strict := _check("seating_strict", "Keep platforms apart when their seats are full")
	strict.tooltip_text = "On: a chatter whose sections are full takes the seat of the idlest chatter there (or waits). Off: they sit anywhere that's free."
	r.add_child(strict)
	var pr := HFlowContainer.new()
	v.add_child(pr)
	pr.add_child(_button("Anyone anywhere", func() -> void: AudienceManager.apply_preset("anyone")))
	var b1 := _button("Twitch apart (left)", func() -> void: AudienceManager.apply_preset("twitch_apart"))
	b1.tooltip_text = "Twitch on the audience's left (front + back left, the left half of every crowd level); Kick, YouTube and others on the right. Matches the default chat windows (Twitch left)."
	pr.add_child(b1)
	var b2 := _button("A quadrant each", func() -> void: AudienceManager.apply_preset("quadrant_each"))
	b2.tooltip_text = "Kick front left, Twitch front right, YouTube back left, other back right; crowd sections take turns."
	pr.add_child(b2)
	pr.add_child(_button("Re-seat everyone now", func() -> void: AudienceManager.reseat_by_plan()))
	# floors: the chart shows one at a time (downstairs, or the balcony + gallery upstairs)
	var fr := HBoxContainer.new()
	v.add_child(fr)
	var fl := Label.new()
	fl.text = "Floor"
	fl.custom_minimum_size = Vector2(120, 0)
	fr.add_child(fl)
	var fg := ButtonGroup.new()
	var floor_buttons: Dictionary = {}
	for f: Array in [[SeatingChart.BOTTOM, "Bottom floor"], [SeatingChart.TOP, "Top floor (balcony + gallery)"]]:
		var fb := Button.new()
		fb.text = f[1]
		fb.toggle_mode = true
		fb.button_group = fg
		fb.focus_mode = Control.FOCUS_ALL
		fb.button_pressed = f[0] == SeatingChart.BOTTOM
		var which: String = f[0]
		fb.pressed.connect(func() -> void: _chart.show_floor(which))
		fr.add_child(fb)
		floor_buttons[which] = fb
	_chart = SeatingChart.new()
	_chart.section_picked.connect(_on_section_picked)
	_chart.floors_changed.connect(func(has_top: bool) -> void:
		fr.visible = has_top
		if not has_top:
			(floor_buttons[SeatingChart.BOTTOM] as Button).button_pressed = true)
	v.add_child(_chart)
	fr.visible = _chart.has_top_floor()
	_section_label = Label.new()
	_section_label.text = "Click a section on the chart."
	v.add_child(_section_label)
	var sr := HBoxContainer.new()
	v.add_child(sr)
	var sl := Label.new()
	sl.text = "May sit here"
	sl.custom_minimum_size = Vector2(120, 0)
	sr.add_child(sl)
	for g in AudienceManager.PLATFORMS:
		var c := CheckBox.new()
		c.text = String(AudienceManager.PLATFORM_LABELS[g])
		c.focus_mode = Control.FOCUS_ALL
		c.disabled = true
		c.add_theme_color_override("font_color", AudienceManager.platform_color(g).lightened(0.3))
		c.toggled.connect(func(_on: bool) -> void: _save_section())
		sr.add_child(c)
		_section_boxes[g] = c
	_capacity_label = Label.new()
	_capacity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_capacity_label)
	EventBus.seating_changed.connect(_refresh_capacity)
	_refresh_capacity()
	return v


func _on_section_picked(id: String) -> void:
	var label := id
	for sec in AudienceManager.get_sections():
		if String(sec["id"]) == id:
			label = "%s — %d seats" % [String(sec["label"]), int(sec["count"])]
	_section_label.text = label
	var allowed := AudienceManager.get_section_platforms(id)
	for g: String in _section_boxes.keys():
		var c: CheckBox = _section_boxes[g]
		c.disabled = false
		c.set_pressed_no_signal(allowed.has(g))


func _save_section() -> void:
	if _chart == null or _chart.selected == "":
		return
	var picked := PackedStringArray()
	for g: String in _section_boxes.keys():
		if (_section_boxes[g] as CheckBox).button_pressed:
			picked.append(g)
	AudienceManager.set_section_platforms(_chart.selected, picked)


## Seats each platform may use in this room, with a warning for one that has none.
func _refresh_capacity() -> void:
	if _capacity_label == null:
		return
	var cap := AudienceManager.get_platform_capacity()
	var parts := PackedStringArray()
	var none := PackedStringArray()
	for g in AudienceManager.PLATFORMS:
		parts.append("%s %d" % [String(AudienceManager.PLATFORM_LABELS[g]), int(cap.get(g, 0))])
		if int(cap.get(g, 0)) == 0:
			none.append(String(AudienceManager.PLATFORM_LABELS[g]))
	var text := "Seats each platform may use here: " + " · ".join(parts)
	if bool(AppState.get_setting("seating_by_platform")) and not none.is_empty():
		text += "\n⚠ No seats for %s: with \"Keep platforms apart\" on, they won't get a seat." % ", ".join(none)
	_capacity_label.text = text
	if _chart and _chart.selected != "":
		_on_section_picked(_chart.selected)


func _build_games_tab() -> Control:
	var v := _tab("Games")
	v.add_child(_heading("Chat reactions"))
	v.add_child(_hint("🍅 / !tomato @name from chat. Set them up in Stream Core: Admin → Config → Reactions."))
	var r4 := HFlowContainer.new()
	v.add_child(r4)
	r4.add_child(_check("reactions_enabled", "Play reactions"))
	r4.add_child(_check("reaction_camera_shake", "Allow camera shake"))
	v.add_child(_slider("reaction_size", "Reaction size", 0.3, 3.0, 0.05, "%d%%", 100.0))
	v.add_child(_heading("Flashing lights (photosensitive viewers)"))
	var fs := _slider("flash_strength", "Flash strength", 0.0, 1.0, 0.05, "%d%%", 100.0)
	fs.tooltip_text = "How bright flashing reactions get: FLASHBANG, police lights, flicker, fireworks and fire. 0% = no flashes at all; the rest of each reaction still plays."
	v.add_child(fs)
	var safe := _check("photosensitive_safe", "Photosensitive-safe mode")
	safe.tooltip_text = "Caps flashes at 30% (whatever Flash strength says), slows strobing lights to under 3 flashes a second (the WCAG limit), turns a FLASHBANG into a soft swell, and turns camera shake off."
	v.add_child(safe)
	var r5 := HBoxContainer.new()
	v.add_child(r5)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in Reactions.get_effect_ids():
		if id != "meter":
			pick.add_item(id)
	r5.add_child(pick)
	r5.add_child(_button("Test here", func() -> void:
		Reactions.play_test(pick.get_item_text(pick.selected))))
	v.add_child(_heading("Chat games"))
	v.add_child(_hint("Polls, predictions, trivia, the hype meter ... from Stream Core: Admin → Chat games. Where their boards show: Chat tab."))
	return v


## Okabe-Ito colours: tell apart with red-green colour blindness (Kick green vs YouTube red don't).
const COLOR_SAFE: Dictionary = {"kick": "009e73", "twitch": "cc79a7", "youtube": "e69f00", "other": "56b4e9"}

const PRESENTER_SOURCES: Array = [["silhouette", "Silhouette"], ["green", "Green screen"],
	["camera", "Camera"], ["tab", "Tab / window"], ["web", "Web page (transparent)"], ["ndi", "NDI source"], ["spout", "Spout (this PC)"],
	["peer", "Someone's avatar (Together)"]]


func _build_presenters_tab() -> Control:
	var v := _tab("Presenters")
	_pres_count_label = Label.new()
	_pres_count_label.text = "This room has no podiums."
	_pres_count_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	v.add_child(_pres_count_label)
	var on_row := HBoxContainer.new()
	v.add_child(on_row)
	var l := Label.new()
	l.text = "On set"
	l.custom_minimum_size = Vector2(120, 0)
	on_row.add_child(l)
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		on_row.add_child(_check(AppState.presenter_key(n, "on"), str(n)))
	var edit_row := HBoxContainer.new()
	v.add_child(edit_row)
	var l2 := Label.new()
	l2.text = "Edit presenter"
	l2.custom_minimum_size = Vector2(120, 0)
	edit_row.add_child(l2)
	var group := ButtonGroup.new()
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var b := Button.new()
		b.text = " %d " % n
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_ALL
		var idx := n - 1
		b.toggled.connect(func(on: bool) -> void:
			if on:
				for i in _pres_details.size():
					_pres_details[i].visible = i == idx)
		edit_row.add_child(b)
		_pres_edit_buttons.append(b)
	var hint := Label.new()
	hint.text = "Podiums are numbered left to right as the audience sees them."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	edit_row.add_child(hint)
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var d := _build_presenter_detail(n)
		d.visible = n == 1
		v.add_child(d)
		_pres_details.append(d)
	_pres_edit_buttons[0].button_pressed = true
	return v


func _build_presenter_detail(n: int) -> VBoxContainer:
	var k := func(f: String) -> String: return AppState.presenter_key(n, f)
	var d := VBoxContainer.new()
	d.add_theme_constant_override("separation", 5)
	d.add_child(_heading("Presenter %d" % n))
	var show_row := _option(k.call("source"), "Show", PRESENTER_SOURCES)
	(show_row.get_child(1) as Control).tooltip_text = "What this podium shows. Someone's avatar: the picture a person in your Streaming together session set up as My avatar (Together tab), yours included."
	d.add_child(show_row)
	var rows: Dictionary = {"picture": []}
	_pres_rows.append(rows)
	var peer_row := _peer_menu(k.call("peer"), "Whose avatar")
	rows["peer"] = peer_row
	d.add_child(peer_row)
	var cam_row := HBoxContainer.new()
	rows["camera"] = cam_row
	var cl := Label.new()
	cl.text = "Camera"
	cl.custom_minimum_size = Vector2(120, 0)
	cam_row.add_child(cl)
	var cam := OptionButton.new()
	cam.focus_mode = Control.FOCUS_ALL
	cam.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cam.fit_to_longest_item = false
	cam.item_selected.connect(func(i: int) -> void: AppState.set_setting(k.call("camera"), String(cam.get_item_metadata(i))))
	cam_row.add_child(cam)
	d.add_child(cam_row)
	_pres_camera_menus.append(cam)
	_fill_camera_menu(n, [])
	var ndi_row := HBoxContainer.new()
	rows["ndi"] = ndi_row
	var nl := Label.new()
	nl.text = "NDI source"
	nl.custom_minimum_size = Vector2(120, 0)
	ndi_row.add_child(nl)
	var ndi := OptionButton.new()
	ndi.focus_mode = Control.FOCUS_ALL
	ndi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ndi.fit_to_longest_item = false
	ndi.tooltip_text = "An NDI source (e.g. an OBS browser source with an NDI filter). Transparency in the source is kept, so you may not need the chroma key."
	ndi.item_selected.connect(func(i: int) -> void:
		if ndi.get_item_metadata(i) != null:
			AppState.set_setting(k.call("ndi"), String(ndi.get_item_metadata(i))))
	ndi_row.add_child(ndi)
	d.add_child(ndi_row)
	_pres_ndi_menus.append(ndi)
	_fill_ndi_menu(ndi, String(AppState.get_setting(k.call("ndi"))), "(none)")
	var spout_row := HBoxContainer.new()
	rows["spout"] = spout_row
	var sl := Label.new()
	sl.text = "Spout sender"
	sl.custom_minimum_size = Vector2(120, 0)
	spout_row.add_child(sl)
	var spm := OptionButton.new()
	spm.focus_mode = Control.FOCUS_ALL
	spm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spm.fit_to_longest_item = false
	spm.tooltip_text = "A program on this PC sharing its picture over Spout, e.g. VTube Studio (Settings > Spout2 output). Transparency is kept, so turn off the chroma key for a see-through avatar."
	spm.item_selected.connect(func(i: int) -> void:
		if spm.get_item_metadata(i) != null:
			AppState.set_setting(k.call("spout"), String(spm.get_item_metadata(i))))
	spout_row.add_child(spm)
	d.add_child(spout_row)
	_pres_spout_menus.append(spm)
	_fill_name_menu(spm, _spout_names, String(AppState.get_setting(k.call("spout"))), "(none)")
	var url := _text_setting(k.call("url"), "Web page", "https://... (for \"Web page\")")
	url.tooltip_text = "For pages with a see-through background (e.g. a reactive PNGTuber page). The sender page shows it over the key colour, you share that, and the chroma key cuts the colour out again."
	rows["url"] = url
	d.add_child(url)
	var feed := Label.new()
	feed.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	feed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.add_child(feed)
	_pres_feed_labels.append(feed)
	var r := HFlowContainer.new()
	r.add_child(_check(k.call("self_lit"), "Self-lit (light panel)"))
	var keybox := _check(k.call("key"), "Chroma key")
	r.add_child(keybox)
	r.add_child(_color(k.call("key_color"), "Key colour"))
	d.add_child(r)
	rows["picture"].append(r)
	d.add_child(_slider(k.call("light"), "Podium light", 0.0, 3.0, 0.01, "%d%%", 100.0))
	for key_row: Control in [_slider(k.call("key_similarity"), "Key similarity", 0.0, 0.8, 0.005, "%.3f"),
			_slider(k.call("key_smoothness"), "Key smoothness", 0.0, 0.3, 0.005, "%.3f"),
			_slider(k.call("key_spill"), "Spill removal", 0.0, 1.0, 0.01, "%d%%", 100.0)]:
		d.add_child(key_row)
		rows["picture"].append(key_row)
	rows["keybox"] = keybox
	_refresh_presenter_rows(n)
	d.add_child(_slider(k.call("zoom"), "Zoom", 0.3, 3.0, 0.01, "%.2fx"))
	d.add_child(_slider(k.call("offset_y"), "Move up/down", -0.5, 0.5, 0.01, "%.2f"))
	var tag := _text_setting(k.call("name"), "Name tag", "shown above the picture (blank = none)")
	tag.tooltip_text = "A name shown above this presenter's picture, for example their channel name."
	d.add_child(tag)
	var pic := _text_setting(k.call("picture"), "Podium picture", "a png, jpg, webp or gif (animated gifs play)")
	pic.tooltip_text = "A picture on the front of the podium: a logo, an avatar, a badge. PNG, JPG, WebP or GIF (animated GIFs play), up to 3 MB. When streaming together, guests get a copy of it."
	var browse := _button("Browse...", func() -> void:
		_pic_target = k.call("picture")
		_pic_dialog.popup_centered_ratio(0.7))
	browse.tooltip_text = "Pick the picture file."
	pic.add_child(browse)
	var clear_pic := _button("Clear", func() -> void: AppState.set_setting(k.call("picture"), ""))
	clear_pic.tooltip_text = "No podium picture."
	pic.add_child(clear_pic)
	d.add_child(pic)
	var pic_rows: Array = []
	var ps := _slider(k.call("picture_scale"), "Picture size", 0.2, 3.0, 0.05, "%d%%", 100.0)
	ps.tooltip_text = "How big the podium picture is. 100% fits the front of the podium."
	pic_rows.append(ps)
	var plit := _check(k.call("picture_self_lit"), "Picture self-lit")
	plit.tooltip_text = "Show the podium picture in its own colours, however dark or coloured the room's light is."
	pic_rows.append(plit)
	var px := _slider(k.call("picture_x"), "Move left/right", -0.5, 0.5, 0.01, "%.2f m")
	px.tooltip_text = "Slide the podium picture sideways, as the audience sees it (right is +)."
	pic_rows.append(px)
	var py := _slider(k.call("picture_y"), "Move up/down", -0.5, 0.5, 0.01, "%.2f m")
	py.tooltip_text = "Slide the podium picture up (+) or down (-)."
	pic_rows.append(py)
	var pic_adv := _fold(d, "presenter_%d_picture" % n)
	for pr in pic_rows:
		pic_adv.add_child(pr)
	rows["picture_rows"] = pic_rows
	rows["picture_fold"] = [pic_adv.get_meta("fold_head"), pic_adv]
	var chat := _text_setting(k.call("chat"), "Chat name", "their chat name(s), e.g. sensoka, kick:sensoka")
	chat.tooltip_text = "Link this presenter to their chat name. They sit on this podium instead of taking an audience seat, and their chat commands (throws, signs, !highfive ...) come from here. Several names: comma separated. \"kick:name\" only matches on that platform."
	d.add_child(chat)
	var cr := HFlowContainer.new()
	var look := _check(k.call("chat_look"), "Chat-style silhouette")
	look.tooltip_text = "When showing a silhouette: use the linked chatter's colour, picture and name tag, like the chat audience."
	cr.add_child(look)
	var bub := _check(k.call("chat_bubbles"), "Chat bubbles")
	bub.tooltip_text = "Their chat messages pop up as speech bubbles over the podium."
	cr.add_child(bub)
	d.add_child(cr)
	_refresh_presenter_rows(n)        # (now that every row, the picture fold included, exists)
	return d


## Camera menu for presenter n: "Default camera" + the cameras the sender page reports.
func _fill_camera_menu(n: int, cameras: Array) -> void:
	_fill_camera_items(_pres_camera_menus[n - 1], String(AppState.get_setting(AppState.presenter_key(n, "camera"))), cameras)


func _fill_camera_items(menu: OptionButton, want: String, cameras: Array) -> void:
	menu.clear()
	menu.add_item("Default camera")
	menu.set_item_metadata(0, "")
	var found := want == ""
	for c: Variant in cameras:
		if not c is Dictionary:
			continue
		menu.add_item(String(c.get("label", "Camera")))
		menu.set_item_metadata(menu.item_count - 1, String(c.get("id", "")))
		if String(c.get("id", "")) == want:
			menu.select(menu.item_count - 1)
			found = true
	if not found:
		menu.add_item("(saved camera, not connected)")
		menu.set_item_metadata(menu.item_count - 1, want)
		menu.select(menu.item_count - 1)
	elif want == "":
		menu.select(0)


## A dropdown bound to a String setting. items: [[value, text], ...]
func _option(key: String, label: String, items: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_ALL
	for it: Array in items:
		o.add_item(String(it[1]))
		o.set_item_metadata(o.item_count - 1, it[0])
		if it[0] == AppState.get_setting(key):
			o.select(o.item_count - 1)
	o.item_selected.connect(func(i: int) -> void: AppState.set_setting(key, o.get_item_metadata(i)))
	h.add_child(o)
	_options[key] = o
	return h


## A text box bound to a String setting. Applies on Enter or when it loses focus.
func _text_setting(key: String, label: String, placeholder: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var e := LineEdit.new()
	e.text = String(AppState.get_setting(key))
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var apply := func() -> void: AppState.set_setting(key, e.text.strip_edges())
	e.text_submitted.connect(func(_t: String) -> void:
		apply.call()
		e.release_focus())
	e.focus_exited.connect(apply)
	h.add_child(e)
	_texts[key] = e
	return h


## Streaming together (autoload/net_session.gd, docs/MULTIPLAYER.md).
func _build_together_tab() -> Control:
	var v := _tab("Together")
	v.add_child(_heading("Streaming together"))
	v.add_child(_hint("Up to four people in the same room. The host runs the show (room, curtain, presenters); guests fly their own camera and stream their own view. Chat reactions from every channel play for everyone. Connect over Tailscale: guests type the host's 100.x address."))
	var name_row := _text_setting("together_name", "Your name", "shown to the others")
	(name_row.get_child(1) as Control).tooltip_text = "The name the others see next to your camera and in the list below."
	v.add_child(name_row)
	var pw_row := _text_setting("together_password", "Password", "everyone types the same one")
	var pw := pw_row.get_child(1) as LineEdit
	pw.secret = true
	pw.tooltip_text = "The session password. The host picks it (at least %d characters) and tells the guests. It stays on this PC; only a scrambled check of it is sent." % NetSession.MIN_PASSWORD
	v.add_child(pw_row)
	_net_pw_hint = _hint("")
	_net_pw_hint.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	v.add_child(_net_pw_hint)
	_update_pw_hint()

	v.add_child(_heading("Host"))
	var bind := _option("together_bind", "Listen on", [["auto", "Tailscale (else this PC only)"], ["tunnel", "Cloudflare tunnel (hide my address)"],
		["all", "Any network"], ["local", "This PC only"]])
	bind.tooltip_text = "Where guests can reach you. Tailscale: only your Tailscale network can connect. Cloudflare tunnel: a one-off trycloudflare.com address that hides your real address from everyone (needs cloudflared.exe in the tools folder; no Tailscale or router setup). Any network also lets PCs on your home network in. This PC only is for testing two copies side by side."
	v.add_child(bind)
	var host_row := HBoxContainer.new()
	v.add_child(host_row)
	_net_host_btn = _button("Host a session", func() -> void: NetSession.host())
	_net_host_btn.tooltip_text = "Start a session others can join. Then click Copy address and give it to your guests."
	host_row.add_child(_net_host_btn)
	# the address never shows on screen (an OBS window capture would put it on the stream): copy it instead
	_net_copy_btn = _button("Copy address", func() -> void:
		var a := String(NetSession.get_info().get("address", ""))
		if a != "":
			DisplayServer.clipboard_set(a)
			EventBus.status_message.emit("Address copied. Paste it to your guests.", false))
	_net_copy_btn.tooltip_text = "Copies the address guests need to the clipboard. It isn't shown on screen, so it can't end up on your stream."
	host_row.add_child(_net_copy_btn)
	_net_addr_label = Label.new()
	_net_addr_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	host_row.add_child(_net_addr_label)

	v.add_child(_heading("Join"))
	var addr := _text_setting("together_address", "Host address", "paste what the host sent you")
	(addr.get_child(1) as LineEdit).secret = true      # (hidden, like the password: it could be on your stream)
	(addr.get_child(1) as Control).tooltip_text = "The address the host copied for you: a 100.x Tailscale address (add :port if it isn't 7350), or a trycloudflare.com address. It shows as dots so it can't end up on your stream."
	v.add_child(addr)
	_net_join_btn = _button("Join", func() -> void: NetSession.join())
	_net_join_btn.tooltip_text = "Connect to the host. Your room, curtain and presenters then follow theirs."
	v.add_child(_net_join_btn)

	_net_leave_btn = _button("Leave / stop hosting", func() -> void: NetSession.leave())
	_net_leave_btn.tooltip_text = "End your part in the session. Everything stays as it is now."
	v.add_child(_net_leave_btn)
	_net_status = _hint("")
	v.add_child(_net_status)
	# guest: the host is sharing a tab, watch it through your own sender page
	_net_live = HBoxContainer.new()
	_net_live_label = _hint("")
	_net_live_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_net_live.add_child(_net_live_label)
	var open_sender := _button("Open sender page", func() -> void:
		if _capture_url != "": OS.shell_open(_capture_url))
	open_sender.tooltip_text = "Opens the sender page in your browser. Click \"Watch the host's live feed\" there and the host's tab shows on your big screen."
	_net_live.add_child(open_sender)
	v.add_child(_net_live)
	_net_medium = HBoxContainer.new()
	var mh := _hint("Every guest draws the whole room while streaming. Medium graphics keeps it smooth.")
	mh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_net_medium.add_child(mh)
	var use_med := _button("Use Medium", func() -> void: AppState.set_setting("graphics_quality", "medium"))
	use_med.tooltip_text = "Switch this PC to Medium graphics (Room tab > Performance)."
	_net_medium.add_child(use_med)
	var keep := _button("No thanks", func() -> void: NetSession.dismiss_medium())
	keep.tooltip_text = "Keep your graphics setting."
	_net_medium.add_child(keep)
	v.add_child(_net_medium)

	v.add_child(_heading("My avatar"))
	v.add_child(_hint("What the others can show of you: your sender page captures it and sends it to everyone in the session. The host puts it on a podium (Presenters tab > Show > Someone's avatar) or on the big screen (Source tab)."))
	var av_src := _option("together_avatar_source", "My avatar", [["off", "Off"], ["camera", "Camera"], ["tab", "Tab / window"], ["web", "Web page (transparent)"]])
	(av_src.get_child(1) as Control).tooltip_text = "Where your avatar comes from, captured by your sender page: a camera, a tab or window you pick there, or a web page with a see-through background (a PNGTuber page, for example). NDI and Spout can't be sent this way: send them to OBS and from there to a VDO.Ninja page."
	v.add_child(av_src)
	var av_cam_row := HBoxContainer.new()
	var av_cl := Label.new()
	av_cl.text = "Camera"
	av_cl.custom_minimum_size = Vector2(120, 0)
	av_cam_row.add_child(av_cl)
	_avatar_camera = OptionButton.new()
	_avatar_camera.focus_mode = Control.FOCUS_ALL
	_avatar_camera.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_avatar_camera.fit_to_longest_item = false
	_avatar_camera.tooltip_text = "The camera for your avatar (the list comes from your sender page)."
	_avatar_camera.item_selected.connect(func(i: int) -> void: AppState.set_setting("together_avatar_camera", String(_avatar_camera.get_item_metadata(i))))
	av_cam_row.add_child(_avatar_camera)
	_fill_camera_items(_avatar_camera, String(AppState.get_setting("together_avatar_camera")), [])
	v.add_child(av_cam_row)
	_avatar_rows["camera"] = av_cam_row
	var av_url := _text_setting("together_avatar_url", "Web page", "https://... (for \"Web page\")")
	av_url.tooltip_text = "The page with your avatar on a see-through background. The sender page shows it over a key colour; the podium's chroma key cuts the colour out again."
	v.add_child(av_url)
	_avatar_rows["url"] = av_url
	_refresh_avatar_rows()
	var quality := _fold(v, "together_quality")
	v = quality
	v.add_child(_heading("Quality"))
	v.add_child(_hint("Quality of what travels between the PCs (the host decides for everyone). Lower it on a slow upload: everything is sent once per viewer."))
	var sh := _option("together_screen_height", "Big screen to guests", [[480, "480p"], [540, "540p"], [720, "720p"], [1080, "1080p"]])
	sh.tooltip_text = "The size of the shared tab as the guests get it. Your own game keeps the sender page's quality."
	v.add_child(sh)
	var sf := _option("together_screen_fps", "Big screen frame rate", [[15, "15 fps"], [30, "30 fps"], [60, "60 fps"]])
	sf.tooltip_text = "Frames a second of the shared tab as the guests get it."
	v.add_child(sf)
	var sk := _slider("together_screen_kbps", "Big screen bitrate", 500.0, 10000.0, 100.0, "%d kbps")
	sk.tooltip_text = "Upload spent on the shared tab per guest. 3000 to 6000 is normal for 720p; 1500 to 2500 for 540p."
	v.add_child(sk)
	var ah := _option("together_avatar_height", "Avatars", [[240, "240p"], [360, "360p"], [480, "480p"], [720, "720p"]])
	ah.tooltip_text = "The size of everyone's avatar as the others get it. Avatars are small on the podiums: 360p or 480p is plenty, 240p saves the most. An avatar on the big screen uses this too, so pick 720p for that."
	v.add_child(ah)
	var af := _option("together_avatar_fps", "Avatar frame rate", [[15, "15 fps"], [20, "20 fps"], [30, "30 fps"]])
	af.tooltip_text = "Frames a second for the avatars."
	v.add_child(af)
	var ak := _slider("together_avatar_kbps", "Avatar bitrate", 100.0, 3000.0, 50.0, "%d kbps")
	ak.tooltip_text = "Upload spent on your avatar per viewer. 500 to 1000 is normal for 480p; 200 to 400 for 240p."
	v.add_child(ak)
	v = quality.get_parent() as VBoxContainer

	v.add_child(_heading("In the session"))
	_net_peers = VBoxContainer.new()
	v.add_child(_net_peers)
	var relay := _check("together_live_relay", "Relay the live feed (hide addresses)")
	relay.tooltip_text = "Host: send the live feed through VDO.Ninja's relay servers instead of straight between browsers, so you and your guests never see each other's addresses. Adds a little delay and can lower the quality."
	v.add_child(relay)
	var live := _check("together_live_feed", "Send my shared tab to the guests")
	live.tooltip_text = "Host: the tab or window you share in the sender page also goes to your guests' big screens, with its sound, through VDO.Ninja (peer to peer, about 0.2 to 1 second behind). Each guest costs you roughly 3 to 6 Mbps of upload."
	v.add_child(live)
	v.add_child(_heading("Shared with guests"))
	v.add_child(_hint("Host: untick a part and every PC keeps its own. For example, untick Presenters to let each guest pick their own presenter sources."))
	var share_row := HFlowContainer.new()
	v.add_child(share_row)
	var sr_room := _check("together_share_room", "Room")
	sr_room.tooltip_text = "Everyone sees the room the host picks."
	share_row.add_child(sr_room)
	var sr_curtain := _check("together_share_curtain", "Curtain and house lights")
	sr_curtain.tooltip_text = "The curtain (and its look) and the house lights follow the host."
	share_row.add_child(sr_curtain)
	var sr_pres := _check("together_share_presenters", "Presenters")
	sr_pres.tooltip_text = "Who's on set and what each podium shows (name tags and podium pictures too) follow the host. Untick it to let guests set up their own presenters."
	share_row.add_child(sr_pres)
	var shared_aud := _check("together_shared_audience", "One audience for everyone's chat")
	shared_aud.tooltip_text = "Host: your guests' chat sits in your audience too, and every stream shows the same people in the same seats with the same speech bubbles. Your seating settings decide who sits where. Off: each of you has your own audience."
	v.add_child(shared_aud)
	var areas := _check("together_audience_areas", "Each streamer's viewers sit together")
	areas.tooltip_text = "Host: with one audience, each streamer's viewers get their own part of it. Two of you: left and right halves; four: a quarter each. The big crowd sections are shared out the same way."
	v.add_child(areas)
	var cams := _check("together_show_cameras", "Show the others' cameras")
	cams.tooltip_text = "A small floating camera with a name shows where each of the others is looking."
	v.add_child(cams)
	return v


## Streaming together: a popup each side answers before a connection completes. Host: "<guest>
## wants to join" with Let them in / Decline. Guest: "you're connected to <host>" with Yes / Leave.
## Nothing is shared until both have said yes (NetSession keeps the guest waiting).
func _on_net_confirm_needed(side: String, peer_id: int, who: String) -> void:
	_on_net_confirm_closed(peer_id)
	var d := ConfirmationDialog.new()
	d.exclusive = false
	d.unresizable = true
	d.min_size = Vector2i(420, 0)
	if side == "host":
		d.title = "Someone wants to join"
		# (the name is whatever the joiner typed, and they got the password right: say so, so the
		# host checks with the friend they expect before letting "them" in)
		d.dialog_text = "Someone calling themselves \"%s\" wants to join your session.\nThey know the password, but anyone can type any name: if you're not sure it's them, ask them first (for example on Discord).\nLet them in? Nothing is shared until you do." % who
		d.ok_button_text = "Let them in"
		d.cancel_button_text = "Decline"
		d.confirmed.connect(func() -> void:
			if not d.has_meta("done"):
				NetSession.approve(peer_id, true))
		d.canceled.connect(func() -> void:
			if not d.has_meta("done"):
				NetSession.approve(peer_id, false))
	else:
		d.title = "Is this the right host?"
		d.dialog_text = "You're connected to %s.\nIs that who you meant to join?" % who
		d.ok_button_text = "Yes, join"
		d.cancel_button_text = "No, leave"
		d.confirmed.connect(func() -> void:
			if not d.has_meta("done"):
				NetSession.confirm(true))
		d.canceled.connect(func() -> void:
			if not d.has_meta("done"):
				NetSession.confirm(false))
	d.get_ok_button().tooltip_text = "Complete the connection."
	d.get_cancel_button().tooltip_text = "Close the connection without sharing anything."
	for b in [d.get_ok_button(), d.get_cancel_button()]:
		b.add_to_group("keyboard_panel")        # (hotkeys stay off while the popup has focus)
	_net_dialogs[peer_id] = d
	# its own OS window even while the panel is docked: inside the main window (the one OBS
	# captures) it would show the guest's name on stream, even with clean feed on
	if _window == null and DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		d.force_native = true
	add_child(d)
	d.popup_centered()


func _on_net_confirm_closed(peer_id: int) -> void:
	if _net_dialogs.has(peer_id):
		var d: ConfirmationDialog = _net_dialogs[peer_id]
		_net_dialogs.erase(peer_id)
		if is_instance_valid(d):
			d.set_meta("done", true)       # (hiding a dialog counts as cancelling it: not here)
			d.queue_free()


## A dropdown bound to a String setting that names a person in the Streaming together session
## (whose avatar). It lists everyone in the session and keeps a saved name that isn't there.
func _peer_menu(key: String, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_ALL
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	o.tooltip_text = "Whose avatar: a person in the session (what they set up under My avatar in their Together tab)."
	o.item_selected.connect(func(i: int) -> void:
		var v: Variant = o.get_item_metadata(i)
		AppState.set_setting(key, String(v) if v != null else ""))
	h.add_child(o)
	_peer_menus[key] = o
	_options[key] = o          # (locked for guests like the other shared controls)
	_fill_peer_menu(key)
	return h


func _fill_peer_menu(key: String) -> void:
	var menu: OptionButton = _peer_menus[key]
	if menu.get_popup().visible:
		return
	var want := String(AppState.get_setting(key))
	menu.clear()
	menu.add_item("(nobody)")
	menu.set_item_metadata(0, null)
	menu.select(0)
	var found := want == ""
	for p: Dictionary in NetSession.get_info().get("peers", []):
		var n := String(p["name"])
		menu.add_item(n + (" (you)" if bool(p.get("me", false)) else ""))
		menu.set_item_metadata(menu.item_count - 1, n)
		if n == want:
			menu.select(menu.item_count - 1)
			found = true
	if not found:
		menu.add_item("%s (not in the session)" % want)
		menu.set_item_metadata(menu.item_count - 1, want)
		menu.select(menu.item_count - 1)


func _refresh_avatar_rows() -> void:
	if _avatar_rows.is_empty():
		return
	var src := String(AppState.get_setting("together_avatar_source"))
	(_avatar_rows["camera"] as Control).visible = src == "camera"
	(_avatar_rows["url"] as Control).visible = src == "web"


func _on_net_state(info: Dictionary) -> void:
	_refresh_strip()
	if _net_status == null:
		return
	for key: String in _peer_menus:
		_fill_peer_menu(key)
	var role := String(info.get("role", "off"))
	_net_status.text = String(info.get("status", ""))
	_net_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if bool(info.get("error", false)) else Color(1, 1, 1, 0.78))
	_net_host_btn.disabled = role != "off"
	var has_addr := role == "host" and String(info.get("address", "")) != ""
	_net_copy_btn.visible = has_addr
	_net_addr_label.text = ("tunnel: ••••••.trycloudflare.com" if NetSession.is_tunnel() else "••••••••") if has_addr else ""
	_net_join_btn.disabled = role != "off"
	_net_leave_btn.disabled = role == "off"
	_net_medium.visible = bool(info.get("suggest_medium", false))
	_net_live.visible = role == "guest"
	_net_live_label.text = ("The host is sharing a live tab. Open your sender page and click \"Watch the host's live feed\"."
		if bool(info.get("host_live", false)) else "The host isn't sharing a live tab right now.")
	for c in _net_peers.get_children():
		c.queue_free()
	var peers: Array = info.get("peers", [])
	if peers.is_empty():
		_net_peers.add_child(_hint("Nobody yet."))
	for p: Dictionary in peers:
		var row := HBoxContainer.new()
		var l := Label.new()
		var id := int(p["id"])
		var text := String(p["name"])
		if id == 1:
			text += " (host)"
		if bool(p["me"]):
			text += " (you)"
		if id != 1 and bool(p["cohost"]) and role != "host":
			text += " - co-host"
		l.text = text
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if role == "host" and id != 1:
			var co := CheckBox.new()
			co.text = "Co-host"
			co.button_pressed = bool(p["cohost"])
			co.tooltip_text = "Let this guest change the room, curtain and presenters too."
			co.toggled.connect(func(on: bool) -> void: NetSession.set_cohost(id, on))
			row.add_child(co)
			var rm := _button("Remove", func() -> void: NetSession.remove_peer(id))
			rm.tooltip_text = "Send this guest out of the session."
			row.add_child(rm)
		_net_peers.add_child(row)
	_refresh_locks()


## A guest who isn't a co-host can't change shared things: those controls are greyed out.
func _refresh_locks() -> void:
	for d: Dictionary in [_sliders, _checks, _options, _colors, _texts]:
		for key: String in d:
			if NetSession.is_shared(key):
				_lock(d[key], key)
	if _room_select:
		_lock(_room_select, "room")
	for b in _curtain_buttons:
		_lock(b, "curtain")


func _lock(c: Control, what: String) -> void:
	var locked := NetSession.is_locked(what)
	if not c.has_meta("tip"):
		c.set_meta("tip", c.tooltip_text)
	if c is Range:
		(c as Range).editable = not locked
	elif c is LineEdit:
		(c as LineEdit).editable = not locked
	elif c is BaseButton:
		(c as BaseButton).disabled = locked
	c.tooltip_text = "The host controls this while you're a guest." if locked else String(c.get_meta("tip"))

# ── EventBus handlers ────────────────────────────────────────
func _on_chat_status(info: Dictionary) -> void:
	var now_connected := bool(info.get("connected", false))
	if _core_was_connected and not now_connected and bool(AppState.get_setting("chat_enabled")):
		EventBus.status_message.emit("Lost the connection to Stream Core: chat, bubbles and reactions stop until it's back (retrying).", true)
	elif now_connected and not _core_was_connected and not _messages.is_empty():
		EventBus.status_message.emit("Stream Core connected.", false)
	_core_was_connected = now_connected
	_refresh_strip()
	if _chat_label == null:
		return
	if info.get("connected", false):
		_chat_label.text = "Connected to Stream Core."
	elif not AppState.get_setting("chat_enabled"):
		_chat_label.text = "Off."
	else:
		var err := String(info.get("error", ""))
		_chat_label.text = "Waiting for Stream Core%s (retrying)." % ((": " + err) if err != "" else "")


func _update_presenter_feeds(info: Dictionary) -> void:
	var connected := bool(info.get("connected", false))
	var cams: Array = info.get("cameras", []) if info.get("cameras") is Array else []
	var feeds: Array = info.get("presenters", []) if info.get("presenters") is Array else []
	var cams_json := JSON.stringify(cams)
	var cams_changed := cams_json != _last_cams_json
	_last_cams_json = cams_json
	if cams_changed and _avatar_camera and not _avatar_camera.get_popup().visible:
		_fill_camera_items(_avatar_camera, String(AppState.get_setting("together_avatar_camera")), cams)
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var menu: OptionButton = _pres_camera_menus[n - 1]
		if cams_changed and not menu.get_popup().visible:
			_fill_camera_menu(n, cams)
		var src := String(AppState.get_setting(AppState.presenter_key(n, "source")))
		menu.disabled = src != "camera"
		var text := ""
		if src == "camera" or src == "tab" or src == "web" or src == "peer":
			var f: Dictionary = feeds[n - 1] if n - 1 < feeds.size() and feeds[n - 1] is Dictionary else {}
			if not connected:
				text = "Open the sender page (Source tab) - the feed comes from there."
			elif String(f.get("error", "")) != "":
				text = "Sender page: " + String(f["error"])
			elif bool(f.get("active", false)):
				text = "Live: " + String(f.get("label", ""))
			elif src == "tab":
				text = "Waiting - click Presenter %d's button in the sender page and pick a tab or window." % n
			elif src == "web" and String(AppState.get_setting(AppState.presenter_key(n, "url"))) == "":
				text = "Type the web page's address above."
			elif src == "web":
				text = "Waiting - in the sender page click Presenter %d's \"Open page\", then \"Share it\"." % n
			else:
				text = "Starting the camera..."
		elif src == "ndi":
			text = _ndi_presenter_text(n)
		elif src == "spout":
			text = _spout_presenter_text(n)
		_pres_feed_labels[n - 1].text = text


# ── NDI ──────────────────────────────────────────────────────
func _on_ndi_sources(names: PackedStringArray, available: bool) -> void:
	_ndi_names = names
	_ndi_available = available
	if not _ndi_menu.get_popup().visible:
		var cur: Variant = _ndi_menu.get_item_metadata(_ndi_menu.selected) if _ndi_menu.selected >= 0 else null
		_fill_ndi_menu(_ndi_menu, String(cur) if cur != null else String(AppState.get_setting("ndi_source")), "(pick a source)")
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var m: OptionButton = _pres_ndi_menus[n - 1]
		if not m.get_popup().visible:
			_fill_ndi_menu(m, String(AppState.get_setting(AppState.presenter_key(n, "ndi"))), "(none)")
		if String(AppState.get_setting(AppState.presenter_key(n, "source"))) == "ndi":
			_pres_feed_labels[n - 1].text = _ndi_presenter_text(n)
	_refresh_ndi_label()


## NDI sources in a dropdown (metadata = source name). A wanted source that isn't on the network
## right now stays listed as "(offline)" so the choice isn't lost.
func _fill_ndi_menu(menu: OptionButton, want: String, empty_text: String) -> void:
	_fill_name_menu(menu, _ndi_names, want, empty_text)


## Names in a dropdown (metadata = the name; the first item, empty_text, has none). A wanted name
## that isn't there right now stays listed as "(offline)" so the choice isn't lost.
func _fill_name_menu(menu: OptionButton, names: PackedStringArray, want: String, empty_text: String) -> void:
	menu.clear()
	menu.add_item(empty_text)
	menu.set_item_metadata(0, null)
	menu.select(0)
	for src in names:
		menu.add_item(src)
		menu.set_item_metadata(menu.item_count - 1, src)
		if src == want:
			menu.select(menu.item_count - 1)
	if want != "" and not names.has(want):
		menu.add_item("%s (offline)" % want)
		menu.set_item_metadata(menu.item_count - 1, want)
		menu.select(menu.item_count - 1)


func _refresh_ndi_label() -> void:
	if _ndi_label == null:
		return
	if not _ndi_available:
		_ndi_label.text = "NDI plugin not loaded (addons/godot-ndi). Restart Redot after installing it; the NDI Runtime must be installed too."
	elif AppState.get_source_mode() == "ndi":
		_ndi_label.text = "Showing %s on the screen (%s)." % [String(AppState.get_setting("ndi_source")),
			"game-paced sound" if NdiReceiver.supports_pull_audio() else "plugin sound, unpatched plugin"]
	elif _ndi_names.is_empty():
		_ndi_label.text = "Looking for NDI sources... (in OBS: DistroAV > NDI main output, or an NDI filter on a source)"
	else:
		_ndi_label.text = "%d NDI source(s) found. Pick one and click Show." % _ndi_names.size()


func _ndi_presenter_text(n: int) -> String:
	var want := String(AppState.get_setting(AppState.presenter_key(n, "ndi")))
	if not _ndi_available:
		return "NDI plugin not loaded."
	if want == "":
		return "Pick an NDI source above."
	if not _ndi_names.has(want):
		return "Waiting for NDI source %s..." % want
	return "Live: NDI %s" % want


# ── Spout ────────────────────────────────────────────────────
func _on_spout_senders(names: PackedStringArray, available: bool) -> void:
	_spout_names = names
	_spout_available = available
	if _spout_menu and not _spout_menu.get_popup().visible:
		var cur: Variant = _spout_menu.get_item_metadata(_spout_menu.selected) if _spout_menu.selected >= 0 else null
		_fill_name_menu(_spout_menu, names, String(cur) if cur != null else String(AppState.get_setting("spout_source")), "(pick a sender)")
	for n in range(1, mini(AppState.PRESENTER_COUNT, _pres_spout_menus.size()) + 1):
		var m: OptionButton = _pres_spout_menus[n - 1]
		if not m.get_popup().visible:
			_fill_name_menu(m, names, String(AppState.get_setting(AppState.presenter_key(n, "spout"))), "(none)")
		if String(AppState.get_setting(AppState.presenter_key(n, "source"))) == "spout":
			_pres_feed_labels[n - 1].text = _spout_presenter_text(n)
	_refresh_spout_label()


func _refresh_spout_label() -> void:
	if _spout_label == null:
		return
	if not _spout_available:
		_spout_label.text = "Spout plugin not loaded (addons/godot-spout)."
	elif AppState.get_source_mode() == "spout":
		_spout_label.text = "Showing %s on the screen. Spout carries no sound: the program's sound reaches your stream as it already does." \
			% String(AppState.get_setting("spout_source"))
	elif _spout_names.is_empty():
		_spout_label.text = "No Spout senders running. Turn on Spout output in the other program (VTube Studio: Settings > Spout2; OBS: the Spout2 plugin)."
	else:
		_spout_label.text = "%d Spout sender(s) running. Pick one and click Show." % _spout_names.size()


func _spout_presenter_text(n: int) -> String:
	var want := String(AppState.get_setting(AppState.presenter_key(n, "spout")))
	if not _spout_available:
		return "Spout plugin not loaded."
	if want == "":
		return "Pick a Spout sender above."
	if not _spout_names.has(want):
		return "Waiting for Spout sender %s..." % want
	return "Live: Spout %s" % want


func _on_room_presenters(count: int) -> void:
	_pres_count_label.text = "This room has no podiums." if count == 0 else \
		"%d podiums in this room. Tick who's on set, then pick what each one shows." % count


func _on_audience_count(seated: int, capacity: int) -> void:
	if capacity <= 0:
		_seat_label.text = "No seats in this room."
	else:
		_seat_label.text = "%d / %d seats taken" % [seated, capacity]


func _on_capture_status(info: Dictionary) -> void:
	_capture_url = String(info.get("url", _capture_url))
	_capture_info = info
	_refresh_now()
	_update_presenter_feeds(info)
	if not info.get("connected", false):
		_capture_label.text = "Sender page not connected."
		return
	if not info.get("capturing", false):
		_capture_label.text = "Sender connected - not sharing yet."
		return
	var text := "Live: %s (%d fps)" % [String(info.get("label", "tab")), int(info.get("fps", 0))]
	if String(info.get("label", "")).to_lower().ends_with("avatar"):
		pass          # (someone's avatar on the big screen: picture only, no sound to share)
	elif not info.get("has_audio", false):
		text += "\nNo audio - turn on \"Share tab audio\" in the picker."
	elif not info.get("suppress_local_audio", false):
		text += "\nBrowser couldn't silence the tab - mute it to avoid double audio."
	_capture_label.text = text


func _on_camera_presets(names: PackedStringArray) -> void:
	for c in _camera_box.get_children():
		c.queue_free()
	for i in names.size():
		var idx := i
		_camera_box.add_child(_button("%d  %s" % [i + 1, names[i]], func() -> void:
			EventBus.camera_preset_requested.emit(idx)))


func _on_room_changed(room_id: String) -> void:
	for i in _room_select.item_count:
		if String(_room_select.get_item_metadata(i)) == room_id:
			_room_select.select(i)


func _on_room_controls(controls: Array) -> void:
	for key in _room_keys:
		_sliders.erase(key)
		_colors.erase(key)
		_checks.erase(key)
	_room_keys.clear()
	for c in _room_box.get_children():
		c.queue_free()
	for spec: Dictionary in controls:
		if spec.has("heading"):
			_room_box.add_child(_heading(String(spec["heading"])))
			continue
		var key := String(spec.get("key", ""))
		if key == "" or AppState.get_setting(key) == null:
			push_warning("Room control for unknown setting: %s" % key)
			continue
		var w: Control
		if String(spec.get("type", "slider")) == "color":
			w = _color(key, String(spec.get("label", key)))
		elif String(spec.get("type", "slider")) == "check":
			w = _check(key, String(spec.get("label", key)))
		else:
			w = _slider(key, String(spec.get("label", key)), float(spec.get("min", 0.0)), float(spec.get("max", 1.0)),
				float(spec.get("step", 0.01)), String(spec.get("format", "%.2f")), float(spec.get("scale", 1.0)))
		w.tooltip_text = String(spec.get("tooltip", ""))
		_room_box.add_child(w)
		_room_keys.append(key)
	_add_help_buttons(_room_box)


func _on_react_pause_changed(paused: bool) -> void:
	_react_btn.text = "Resume (Space)" if paused else "Pause to react (Space)"


func _on_mic_level(db: float) -> void:
	_mic_bar.value = db


func _on_ducking(ducking: bool) -> void:
	_duck_label.text = "ducking" if ducking else ""


## Together tab: a note while the password is too short to host with.
func _update_pw_hint() -> void:
	if _net_pw_hint == null:
		return
	var pw := String(AppState.get_setting("together_password")).strip_edges()
	_net_pw_hint.visible = pw != "" and NetSession.password_too_short()
	_net_pw_hint.text = "This password is short. To host, pick one with at least %d characters (guests just type the same one)." % NetSession.MIN_PASSWORD


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "together_password":
		_update_pw_hint()
	if key == "chat_enabled":
		_refresh_strip()
	if key == "ndi_source" or key == "spout_source":
		_refresh_now()
	if key == "panel_scale":
		_scale_pending = 0.3      # applied once the slider stops moving (it moves under the mouse otherwise)
	if key.begins_with("presenter_") and (key.ends_with("_source") or key.ends_with("_ndi")):
		var pn := int(key.get_slice("_", 1))
		if pn >= 1 and pn <= _pres_feed_labels.size() and String(AppState.get_setting(AppState.presenter_key(pn, "source"))) == "ndi":
			_pres_feed_labels[pn - 1].text = _ndi_presenter_text(pn)
	if key == "spout_source" and _spout_menu and not _spout_menu.get_popup().visible:
		_fill_name_menu(_spout_menu, _spout_names, String(value), "(pick a sender)")
	if key.begins_with("presenter_") and (key.ends_with("_source") or key.ends_with("_spout")):
		var sn := int(key.get_slice("_", 1))
		if sn >= 1 and sn <= _pres_feed_labels.size() and String(AppState.get_setting(AppState.presenter_key(sn, "source"))) == "spout":
			_pres_feed_labels[sn - 1].text = _spout_presenter_text(sn)
	if _sliders.has(key):
		var s: HSlider = _sliders[key]
		s.set_value_no_signal(float(value) * float(s.get_meta("scale", 1.0)))
		_syncing = true
		s.value_changed.emit(s.value)  # refresh the number label only
		_syncing = false
	if _checks.has(key):
		(_checks[key] as CheckBox).set_pressed_no_signal(bool(value))
	if _texts.has(key) and not (_texts[key] as LineEdit).has_focus():
		(_texts[key] as LineEdit).text = String(value)
	if _colors.has(key):
		(_colors[key] as ColorPickerButton).color = value
	if _peer_menus.has(key):
		_fill_peer_menu(key)         # (a saved name that isn't in the session gets its own entry)
	elif _options.has(key):
		var o: OptionButton = _options[key]
		for i in o.item_count:
			if o.get_item_metadata(i) == value:
				o.select(i)
	if key == "together_avatar_source":
		_refresh_avatar_rows()
	if _platform_boxes.has(key):
		var have := String(value).split(",", false)
		for g: String in (_platform_boxes[key] as Dictionary).keys():
			((_platform_boxes[key] as Dictionary)[g] as CheckBox).set_pressed_no_signal(have.has(g))
		_refresh_mix_warning(key)
	if key == "seating_by_platform" or key == "seating_plan":
		_refresh_capacity()
	if key == "graphics_quality" and _gfx_hint:
		_gfx_hint.text = GraphicsQuality.describe(String(value))
	if key.begins_with("presenter_") and (key.ends_with("_source") or key.ends_with("_key") or key.ends_with("_picture")):
		_refresh_presenter_rows(int(key.get_slice("_", 1)))


## Only the rows that matter for what a presenter shows: the camera picker for a camera, the NDI
## picker for NDI, the address for a web page, and the chroma key controls for a picture.
func _refresh_presenter_rows(n: int) -> void:
	if n < 1 or n > _pres_rows.size():
		return
	var rows: Dictionary = _pres_rows[n - 1]
	var src := String(AppState.get_setting(AppState.presenter_key(n, "source")))
	(rows["camera"] as Control).visible = src == "camera"
	(rows["peer"] as Control).visible = src == "peer"
	(rows["ndi"] as Control).visible = src == "ndi"
	(rows["spout"] as Control).visible = src == "spout"
	var has_pic := String(AppState.get_setting(AppState.presenter_key(n, "picture"))).strip_edges() != ""
	for pr in rows.get("picture_rows", []):
		(pr as Control).visible = has_pic
	if rows.has("picture_fold"):        # (not yet while the detail is being built)
		(rows["picture_fold"][0] as Control).visible = has_pic
		if not has_pic:
			(rows["picture_fold"][1] as Control).visible = false
		elif PackedStringArray(String(AppState.get_setting("panel_advanced")).split(",", false)).has("presenter_%d_picture" % n):
			(rows["picture_fold"][1] as Control).visible = true
	(rows["url"] as Control).visible = src == "web"
	var picture := src in ["camera", "tab", "web", "ndi", "spout", "peer"]
	var keyed := picture and bool(AppState.get_setting(AppState.presenter_key(n, "key")))
	for i in (rows["picture"] as Array).size():
		# the chroma key row itself shows for any picture; its sliders only while the key is on
		((rows["picture"] as Array)[i] as Control).visible = picture if i == 0 else keyed


func _refresh_visible() -> void:
	if _window:
		# its own window isn't in the stream picture, so clean feed doesn't hide it
		_panel.visible = true
		_window.visible = not _user_hidden
		return
	_panel.visible = not _user_hidden and not AppState.is_clean_feed()
	if not _panel.visible:
		get_viewport().gui_release_focus()


# ── Widget helpers ───────────────────────────────────────────
# ── What's going on: status strip, message line, big-screen line, video status ─────
## Three coloured dots above the tabs: Stream Core, the big screen, Together. Each one jumps to its tab.
func _build_status_strip() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for it: Array in [["core", "Chat", "Stream Core: is chat coming in? Click for the Chat tab."],
			["screen", "Source", "The big screen: is something showing? Click for the Source tab."],
			["together", "Together", "Streaming together: hosting, joined, or off. Click for the Together tab."]]:
		var key := String(it[0])
		var tab_name := String(it[1])
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.tooltip_text = String(it[2])
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void: _go_to_tab(tab_name))
		h.add_child(b)
		_strip[key] = b
	_refresh_strip.call_deferred()
	return h


func _go_to_tab(tab_name: String) -> void:
	var page := _tabs.get_node_or_null(tab_name)
	if page:
		_tabs.current_tab = page.get_index()


const STRIP_GREEN := Color(0.45, 0.9, 0.5)
const STRIP_AMBER := Color(1.0, 0.75, 0.3)
const STRIP_RED := Color(1.0, 0.45, 0.4)
const STRIP_GREY := Color(1, 1, 1, 0.5)


func _set_strip(key: String, text: String, color: Color) -> void:
	var b: Button = _strip.get(key)
	if b == null:
		return
	b.text = "● " + text
	for st in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(st, color)


func _refresh_strip() -> void:
	if _strip.is_empty():
		return
	# Stream Core
	if not bool(AppState.get_setting("chat_enabled")):
		_set_strip("core", "Core off", STRIP_GREY)
	elif ChatFeed.is_connected_to_core():
		_set_strip("core", "Core", STRIP_GREEN)
	else:
		_set_strip("core", "Core not connected", STRIP_RED)
	# the big screen
	var mode := AppState.get_source_mode()
	match mode:
		"none":
			_set_strip("screen", "Big screen empty", STRIP_AMBER)
		"capture":
			var ok := bool(_capture_info.get("connected", false)) and bool(_capture_info.get("capturing", false))
			_set_strip("screen", "Big screen: tab" if ok else "Big screen: tab stopped", STRIP_GREEN if ok else STRIP_RED)
		"file":
			_set_strip("screen", "Big screen: video", STRIP_GREEN)
		"ndi":
			_set_strip("screen", "Big screen: NDI", STRIP_GREEN)
		"spout":
			_set_strip("screen", "Big screen: Spout", STRIP_GREEN)
		_:
			_set_strip("screen", "Big screen: " + mode, STRIP_GREEN)
	# Together
	var info := NetSession.get_info()
	var role := String(info.get("role", "off"))
	var guests := maxi((info.get("peers", []) as Array).size() - 1, 0)
	if role == "host":
		var waiting := (info.get("pending", []) as Array).size()
		if waiting > 0:
			_set_strip("together", "Together: %d waiting" % waiting, STRIP_AMBER)
		else:
			_set_strip("together", "Hosting (%d guest%s)" % [guests, "" if guests == 1 else "s"], STRIP_GREEN)
	elif role == "guest":
		var waiting_me := bool(info.get("waiting", false))
		_set_strip("together", "Joining..." if waiting_me else "Joined", STRIP_AMBER if waiting_me else STRIP_GREEN)
	elif bool(info.get("error", false)):
		_set_strip("together", "Together: problem", STRIP_RED)
	else:
		_set_strip("together", "Together off", STRIP_GREY)


## The footer's message line: the latest status / error message (red for errors). Clicking it shows
## the last few, with times, and the tick that also puts messages on the room picture.
func _build_message_line(outer: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	outer.add_child(row)
	_msg_btn = Button.new()
	_msg_btn.flat = true
	_msg_btn.focus_mode = Control.FOCUS_ALL
	_msg_btn.clip_text = true
	_msg_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_msg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_btn.custom_minimum_size = Vector2(200, 0)
	_msg_btn.text = "No messages yet."
	_msg_btn.tooltip_text = "The latest message from the app (red = a problem). Click to see the last %d." % MESSAGE_HISTORY
	_msg_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	row.add_child(_msg_btn)
	_msg_fold = _fold(outer, "panel_messages", "Messages", row)
	_msg_btn.pressed.connect(func() -> void: (_msg_fold.get_meta("fold_button") as Button).pressed.emit())
	_msg_list = VBoxContainer.new()
	_msg_list.add_theme_constant_override("separation", 2)
	_msg_fold.add_child(_msg_list)
	var on_pic := _check("messages_on_picture", "Show messages on the picture")
	on_pic.tooltip_text = "Also show each message for a few seconds at the bottom of the room picture. Off by default: that's the window OBS captures, so messages (and errors) would show on your stream. Clean feed (F10) hides them either way."
	_msg_fold.add_child(on_pic)


func _on_status_message(text: String, is_error: bool) -> void:
	var t := Time.get_time_dict_from_system()
	_messages.push_front({"time": "%02d:%02d" % [int(t["hour"]), int(t["minute"])], "text": text, "error": is_error})
	if _messages.size() > MESSAGE_HISTORY:
		_messages.resize(MESSAGE_HISTORY)
	if _msg_btn == null:
		return
	_msg_btn.text = "%s  %s" % [_messages[0]["time"], text.get_slice("\n", 0)]
	_msg_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if is_error else Color(0.92, 0.94, 1.0))
	for c in _msg_list.get_children():
		c.queue_free()
	for m: Dictionary in _messages:
		var l := _hint("%s  %s" % [m["time"], m["text"]])
		if bool(m["error"]):
			l.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
		_msg_list.add_child(l)
	_refresh_strip()


## Source tab: "On the big screen now: ..." whichever section is open below.
func _refresh_now() -> void:
	_refresh_strip()
	if _now_label == null:
		return
	var what := "Nothing."
	match AppState.get_source_mode():
		"capture":
			if bool(_capture_info.get("capturing", false)):
				what = "Browser tab, \"%s\" (%d fps)" % [String(_capture_info.get("label", "tab")), int(_capture_info.get("fps", 0))]
			else:
				what = "Browser tab (waiting for the sender page)"
		"file":
			var f := _last_video_input.strip_edges()
			what = "Video, %s" % (f.get_file() if not f.begins_with("http") else f.substr(0, 60)) if f != "" else "Video"
		"ndi":
			what = "NDI, %s" % String(AppState.get_setting("ndi_source"))
		"spout":
			what = "Spout, %s" % String(AppState.get_setting("spout_source"))
	_now_label.text = "On the big screen now: " + what


func _on_video_job(state: String, message: String, details: String) -> void:
	if state == "downloading" or state == "converting":
		if _video_state != "downloading" and _video_state != "converting":
			_video_started_ms = Time.get_ticks_msec()
	_video_state = state
	_video_status.set_meta("message", message)
	_video_details.text = details
	(_video_details_fold.get_meta("fold_head") as Control).visible = state == "failed" and details != ""
	if state != "failed" or details == "":
		_video_details_fold.visible = false
	elif PackedStringArray(String(AppState.get_setting("panel_advanced")).split(",", false)).has("source_video_details"):
		_video_details_fold.visible = true
	_video_tick = 1.0
	_show_video_status()
	_refresh_now()


func _show_video_status() -> void:
	if _video_status == null:
		return
	@warning_ignore("integer_division")
	var secs := (Time.get_ticks_msec() - _video_started_ms) / 1000
	@warning_ignore("integer_division")
	var clock := "%d:%02d" % [secs / 60, secs % 60]
	var text := ""
	var color := Color(1, 1, 1, 0.78)
	match _video_state:
		"downloading":
			text = "Downloading... %s" % clock
		"converting":
			text = "Converting... %s (long videos take a while)" % clock
		"ready":
			text = String(_video_status.get_meta("message", "Ready."))
		"failed":
			text = String(_video_status.get_meta("message", "Couldn't load the video."))
			color = Color(1.0, 0.55, 0.5)
	_video_status.text = text
	_video_status.visible = text != ""
	_video_status.add_theme_color_override("font_color", color)
	_video_retry.visible = _video_state == "failed" and _last_video_input != ""


func _tab(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = title
	v.add_theme_constant_override("separation", 6)
	return v


## "Advanced ▸": a fold for the settings that aren't touched every stream (the owner's rule: no
## control goes away, it goes under one of these). Closed by default; the open ones are remembered
## in panel_advanced by id. The button sits in `head` when given (a summary row), else on its own row.
## The returned box is the fold's body; its head row is in the meta "fold_head".
func _fold(v: VBoxContainer, id: String, label: String = "Advanced", head: Container = null) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = "Show or hide the %s settings here. They stay as they are either way." % label.to_lower()
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	var open := PackedStringArray(String(AppState.get_setting("panel_advanced")).split(",", false)).has(id)
	body.visible = open
	btn.text = (label + " ▾") if open else (label + " ▸")
	btn.pressed.connect(func() -> void:
		body.visible = not body.visible
		btn.text = (label + " ▾") if body.visible else (label + " ▸")
		var list := PackedStringArray(String(AppState.get_setting("panel_advanced")).split(",", false))
		var i := list.find(id)
		if body.visible and i < 0:
			list.append(id)
		elif not body.visible and i >= 0:
			list.remove_at(i)
		AppState.set_setting("panel_advanced", ",".join(list))
		_fit_height.call_deferred())
	var row: Container = head
	if row == null:
		row = HBoxContainer.new()
		v.add_child(row)
	row.add_child(btn)
	v.add_child(body)
	body.set_meta("fold_head", row)
	body.set_meta("fold_button", btn)
	return body


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	return l


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL    # (a mouse click doesn't keep focus: see _drop_mouse_focus)
	b.pressed.connect(cb)
	return b


func _check(key: String, text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.focus_mode = Control.FOCUS_ALL
	c.button_pressed = bool(AppState.get_setting(key))
	c.toggled.connect(func(on: bool) -> void: AppState.set_setting(key, on))
	_checks[key] = c
	return c


func _color(key: String, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var b := ColorPickerButton.new()
	b.color = AppState.get_setting(key)
	b.edit_alpha = false
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(90, 24)
	b.color_changed.connect(func(c: Color) -> void: AppState.set_setting(key, c))
	h.add_child(b)
	_colors[key] = b
	return h


## scale: display multiplier (e.g. 100 to show 0..1 as 0..100%).
## A number typed into a slider's value box: the first number in it, in the units shown
## (e.g. "75" for 75%), clamped to the slider's range.
func _apply_typed(s: HSlider, num: LineEdit, fmt: String, t: String) -> void:
	var rx := RegEx.new()
	rx.compile("-?[0-9]*[.,]?[0-9]+")
	var m := rx.search(t)
	if m != null:
		s.value = clampf(float(m.get_string().replace(",", ".")), s.min_value, s.max_value)
	num.text = fmt % s.value


func _slider(key: String, label: String, lo: float, hi: float, step: float, fmt: String, display_scale: float = 1.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo * display_scale
	s.max_value = hi * display_scale
	s.step = step * display_scale
	s.set_meta("scale", display_scale)
	s.value = float(AppState.get_setting(key)) * display_scale
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	# the value is a box you can type an exact number into (Enter sets it, Esc / leaving keeps the old one)
	var num := LineEdit.new()
	num.flat = true
	num.custom_minimum_size = Vector2(78, 0)
	num.text = fmt % s.value
	num.select_all_on_focus = true
	num.tooltip_text = "Click and type an exact value, then Enter"
	num.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	h.add_child(num)
	var is_int := typeof(AppState.get_setting(key)) == TYPE_INT
	s.value_changed.connect(func(x: float) -> void:
		if not num.has_focus():
			num.text = fmt % x
		if _syncing:
			return      # only matching a setting that changed elsewhere (it may round differently)
		var raw := x / display_scale
		if is_int:
			AppState.set_setting(key, int(raw))
		else:
			AppState.set_setting(key, raw))
	num.text_submitted.connect(func(t: String) -> void:
		_apply_typed(s, num, fmt, t)
		num.release_focus())
	num.focus_exited.connect(func() -> void: num.text = fmt % s.value)
	_sliders[key] = s
	return h


# ── Accessibility helpers ────────────────────────────────────
func _panel_scale() -> float:
	return clampf(float(AppState.get_setting("panel_scale")), 0.75, 2.0)


## Panel size: the whole panel scales (text, buttons, hit areas); in its own window the window's
## content scales and the window grows to fit.
func _apply_scale() -> void:
	var k := _panel_scale()
	if _window:
		_panel.scale = Vector2.ONE
		_window.content_scale_factor = k
		var w := int((maxf(panel_width, _panel.get_combined_minimum_size().x) + 20.0) * k)
		_window.min_size = Vector2i(w, 360)
		if _window.size.x < w:
			_window.size = Vector2i(w, _window.size.y)
	else:
		_panel.scale = Vector2(k, k)
	_fit_height()
	# wrapped hint lines change height once the new size has been laid out: fit again after that
	await get_tree().process_frame
	_fit_height()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not key.ctrl_pressed:
		return
	if key.keycode == KEY_EQUAL or key.keycode == KEY_PLUS or key.keycode == KEY_KP_ADD:
		AppState.set_setting("panel_scale", clampf(snappedf(_panel_scale() + 0.1, 0.05), 0.75, 2.0))
	elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT:
		AppState.set_setting("panel_scale", clampf(snappedf(_panel_scale() - 0.1, 0.05), 0.75, 2.0))
	else:
		return
	get_viewport().set_input_as_handled()


## A bright outline around whatever has the keyboard focus.
func _focus_theme() -> Theme:
	var t := Theme.new()
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.85, 0.2)
	sb.set_corner_radius_all(4)
	sb.set_expand_margin_all(2.0)
	for type in ["Button", "CheckBox", "CheckButton", "OptionButton", "HSlider", "LineEdit", "TabBar", "ColorPickerButton", "TextEdit"]:
		t.set_stylebox("focus", type, sb)
	return t


## Help you can see without hovering: every row with a tooltip gets a "?" that shows the same
## text as a line under the row (the tooltips stay too).
func _add_help_buttons(root: Node) -> void:
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.tooltip_text == "" or c.has_meta("help_done") or c.has_meta("help_q"):
			continue
		if c is SeatingChart:
			continue      # (the chart explains itself in its own hint)
		if c is LineEdit and (c as LineEdit).flat:
			continue      # (a slider's number box: its tip is the same everywhere)
		c.set_meta("help_done", true)
		var row: Control = c
		while row.get_parent() and not (row.get_parent() is VBoxContainer) and row.get_parent() != root:
			row = row.get_parent() as Control
			if row == null:
				break
		if row == null or not (row.get_parent() is VBoxContainer):
			continue
		var tip := c.tooltip_text
		if row.has_meta("help_label"):
			var lbl := row.get_meta("help_label") as Label
			if not lbl.text.contains(tip):
				lbl.text += "\n" + tip
			continue
		var box := row.get_parent() as VBoxContainer
		var holder: Container = row as Container
		if not (row is HBoxContainer or row is HFlowContainer):
			# a lone tick box / button: put it in a row so the "?" can sit beside it
			var wrap_row := HBoxContainer.new()
			var idx := row.get_index()
			box.add_child(wrap_row)
			box.move_child(wrap_row, idx)
			row.reparent(wrap_row, false)
			holder = wrap_row
			wrap_row.set_meta("help_done", true)
			row = wrap_row
		var hint := _hint(tip)
		hint.visible = false
		box.add_child(hint)
		box.move_child(hint, row.get_index() + 1)
		var q := Button.new()
		q.text = "?"
		q.flat = true
		q.set_meta("help_q", true)
		q.tooltip_text = ""
		q.custom_minimum_size = Vector2(26, 0)
		q.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		q.pressed.connect(func() -> void:
			hint.visible = not hint.visible
			if box == _tabs.get_parent():
				_fit_height.call_deferred())
		holder.add_child(q)
		row.set_meta("help_label", hint)


## Chat tab: warn when a window's text would be too small to read on a 1080p stream from the
## camera in use (checked once a second while the panel shows the Chat tab).
const MIN_STREAM_TEXT_PX: float = 16.0

func _check_text_sizes() -> void:
	if _size_warnings.is_empty() or not _panel.is_visible_in_tree():
		return
	var page := _tabs.get_current_tab_control()
	if page == null or page.name != "Chat":
		return
	var seen: Dictionary = {}
	for n in get_tree().get_nodes_in_group("chat_windows"):
		var w := n as ChatScreen
		if w == null or not is_instance_valid(w):
			continue
		var px := w.estimate_text_px()
		if px > 0.0:
			seen[w.get_window_key()] = px
	for key: String in _size_warnings.keys():
		var lbl := _size_warnings[key] as Label
		var px := float(seen.get(key, -1.0))
		lbl.visible = px > 0.0 and px < MIN_STREAM_TEXT_PX
		(lbl.get_meta("row") as Control).visible = lbl.visible
		if _size_marks.has(key):
			(_size_marks[key] as Label).visible = lbl.visible
		if lbl.visible:
			var ok_size := float(AppState.get_setting(key + "_text")) * MIN_STREAM_TEXT_PX / px
			var need := ceili(ok_size * 20.0) * 5
			_size_need[key] = float(need) / 100.0
			(lbl.get_meta("fix") as Control).visible = need <= 300
			lbl.text = ("⚠ From this camera the text is only about %d px tall on a 1080p stream (hard to read). " % roundi(px)) + \
				("Try Text size %d%% or more, or a closer camera." % need if need <= 300 else "Use a closer camera (even 300% text won't be enough from here).")
			if _size_marks.has(key):
				(_size_marks[key] as Label).tooltip_text = lbl.text
