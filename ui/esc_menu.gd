class_name EscMenu
extends Node
## The Esc game menu: Resume, Display, Sound, Co-stream, Keys, Open Stream Core dashboard, Quit.
## It opens in its own OS window (like the F9 panel window and the panel's questions), so an OBS
## Window Capture of the room never shows it. Esc (core/hotkeys.gd -> EventBus.menu_requested)
## opens it, and Esc or Resume closes it.
## Created by core/main.gd at start. It also owns the window settings (window_mode, window_screen,
## window_size): DisplayMode.apply runs at start and whenever one of them changes, from here or
## from anywhere else.
## Everything here is a setting the control panel also has (except the window ones), read and
## written through AppState, so both stay in step. Work list item 4 (rooms-menu/WORK_LIST.md).

## The pages, in the order of the left column.
const PAGES: PackedStringArray = ["Display", "Sound", "Co-stream", "Keys"]
## Settings that move the window (DisplayMode.apply).
const WINDOW_KEYS: PackedStringArray = ["window_mode", "window_screen", "window_size"]
## The keys on the Keys page: [key, what it does]. Keep in step with core/hotkeys.gd's list.
const KEYS: Array = [
	["Esc", "This menu (and Esc again to go back)"],
	["Tab", "Show / hide the control panel"],
	["F9", "Control panel in its own window, or back in the room window"],
	["F6", "Move through the control panel with the keyboard (Esc leaves)"],
	["Space", "Pause to react"],
	["F", "Focus view: the big screen flat and full-frame"],
	["F10", "Clean feed: hide everything that isn't the room"],
	["F11", "Fullscreen for now (Display > Window keeps it)"],
	["1 – 9, 0", "Camera views (0 is the 10th)"],
	["Page Up / Page Down", "Previous / next room"],
	["B", "Close / open the stage curtain"],
	["Shift + B", "Curtain reveal (lights and drum roll)"],
	["C", "Chat screen on / off (rooms that have one)"],
	["R", "Reply screen on / off (rooms that have one)"],
	["Shift + click", "On a chatter, presenter or the big screen: their menu (throw, glow, seat...)"],
	["P, then click", "The same, without holding Shift"],
]
const BG := Color(0.07, 0.075, 0.09)
const ACCENT := Color(0.96, 0.72, 0.3)

var _win: Window = null
var _nav: Dictionary = {}              # page name -> its Button in the left column
var _page_box: VBoxContainer = null    # the right side; rebuilt by _show_page
var _page: String = "Display"
var _confirm: ConfirmationDialog = null
var _rebuild_queued: bool = false
var _writing: bool = false             # true while this menu writes a setting (no rebuild for our own change)


func _ready() -> void:
	EventBus.menu_requested.connect(toggle)
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.net_state_changed.connect(func(_info: Dictionary) -> void:
		if _page == "Co-stream":
			_queue_rebuild())
	DisplayMode.apply.call_deferred(get_window())


## Is the menu showing (for Hotkeys' Esc and the tests)?
func is_open() -> bool:
	return _win != null and _win.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


## Opens the menu on a page ("" = the last one shown), centred on the room window.
func open(page: String = "") -> void:
	if page != "" and PAGES.has(page):
		_page = page
	if _win == null:
		_build()
	_show_page(_page)
	var main := get_window()
	_win.position = main.position + (main.size - _win.size) / 2
	_win.show()
	_win.grab_focus()
	(_nav[_page] as Button).grab_focus.call_deferred()


func close() -> void:
	if _win != null:
		_win.hide()


# ── Building ─────────────────────────────────────────────────────────

func _build() -> void:
	_win = Window.new()
	_win.title = AppState.with_profile("Stream Rooms — menu")
	_win.size = Vector2i(860, 580)
	_win.min_size = Vector2i(640, 420)
	_win.wrap_controls = false
	_win.transient = true          # stays above the room window
	_win.exclusive = false
	_win.visible = false
	# its own OS window, so it never shows in the captured room picture
	if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		_win.force_native = true
	_win.close_requested.connect(close)
	_win.window_input.connect(_on_window_input)
	add_child(_win)

	var bg := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	bg.add_theme_stylebox_override("panel", style)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win.add_child(bg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	bg.add_child(row)

	# left column: title, pages, then the two actions
	var left := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		left.add_theme_constant_override("margin_" + side, 18)
	left.custom_minimum_size = Vector2(230, 0)
	row.add_child(left)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	left.add_child(nav)
	var title := Label.new()
	title.text = "Stream Rooms"
	title.add_theme_font_size_override("font_size", 24)
	nav.add_child(title)
	nav.add_child(_nav_button("Resume", "Close this menu and go back to the room (Esc does the same).", close))
	var group := ButtonGroup.new()
	for p: String in PAGES:
		var b := _nav_button(p, _page_tip(p), _show_page.bind(p))
		b.toggle_mode = true
		b.button_group = group
		# the open page: warm background with an orange bar on the left, like the mock-up
		var on := _box(Color(0.23, 0.18, 0.11), 6)
		on.border_width_left = 4
		on.border_color = ACCENT
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		_nav[p] = b
		nav.add_child(b)
	nav.add_child(HSeparator.new())
	nav.add_child(_nav_button("Open Stream Core dashboard",
		"Opens Stream Core's dashboard in your browser. If it asks for the admin token, press \"Sign in on this PC\" there.",
		_open_dashboard))
	var quit := _nav_button("Quit", "Close Stream Rooms. Your settings are saved first.", _quit)
	quit.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	nav.add_child(quit)

	row.add_child(VSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var right := MarginContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		right.add_theme_constant_override("margin_" + side, 22)
	scroll.add_child(right)
	_page_box = VBoxContainer.new()
	_page_box.add_theme_constant_override("separation", 12)
	right.add_child(_page_box)


func _page_tip(p: String) -> String:
	match p:
		"Display":
			return "Window, monitor, window size, graphics quality, frame rate."
		"Sound":
			return "Big screen volume, room ambience and curtain sounds."
		"Co-stream":
			return "Host or join a co-stream, see who's in, co-hosts, what everyone follows."
		_:
			return "Every keyboard shortcut."


## Shows one page on the right (rebuilt from the settings each time).
func _show_page(p: String) -> void:
	_page = p
	if _page_box == null:
		return
	for n: String in _nav:     # (set_pressed_no_signal doesn't let go of the others in the group)
		(_nav[n] as Button).set_pressed_no_signal(n == p)
	for c in _page_box.get_children():
		_page_box.remove_child(c)
		c.queue_free()
	var head := Label.new()
	head.text = p
	head.add_theme_font_size_override("font_size", 22)
	_page_box.add_child(head)
	match p:
		"Display":
			_build_display()
		"Sound":
			_build_sound()
		"Co-stream":
			_build_costream()
		_:
			_build_keys()
	_page_box.add_child(_hint("Esc or Resume to go back. This menu opens in its own window, so it never shows on stream."))


func _build_display() -> void:
	var mode := String(AppState.get_setting("window_mode"))
	if mode == "":
		mode = DisplayMode.current(get_window())
	_row("Window", _choice([["windowed", "Windowed"], ["borderless", "Borderless"], ["fullscreen", "Fullscreen"]], mode,
		func(v: Variant) -> void: _write("window_mode", v),
		"Windowed: a normal window. Borderless: no frame, covering the monitor (best for OBS Window Capture). Fullscreen: the whole monitor. Kept for the next start."))
	var screens: Array = [[-1, "The one it opens on"]]
	screens.append_array(DisplayMode.screens())
	_row("Monitor", _dropdown("window_screen", screens, "Which monitor the room window goes on."))
	_row("Window size", _dropdown("window_size", DisplayMode.SIZES,
		"The room window's size for Windowed and Borderless. Pick your OBS canvas size (often 1920 × 1080) so the capture fits exactly."))
	_page_box.add_child(_hint("Window size is used for Windowed and Borderless. \"Fill the screen\" makes the window as big as the monitor."))
	_row("Graphics quality", _choice([["low", "Low"], ["medium", "Medium"], ["high", "High"], ["custom", "Custom"]],
		String(AppState.get_setting("graphics_quality")),
		func(v: Variant) -> void:
			_writing = true
			GraphicsQuality.set_level(String(v))
			_writing = false,
		"High is what the rooms are built with. Medium and Low turn off the most expensive effects for slower PCs. Custom keeps your own switches."))
	_row("Frame rate cap", _choice([[30, "30"], [60, "60"], [0, "Unlimited"]], int(AppState.get_setting("fps_cap")),
		func(v: Variant) -> void: _write("fps_cap", int(v)),
		"The most frames per second the room draws. 60 is smooth; 30 saves power for OBS and games."))
	_row("V-Sync", _tick("vsync", "On", "Waits for the monitor's refresh, so the picture never tears."))
	_page_box.add_child(_hint("Graphics details (bounce light, shadows, fog, 3D resolution) are in the control panel: Room tab > Performance."))


func _build_sound() -> void:
	_row("Video volume", _slider("volume", 0.0, 1.0, 0.01, "How loud the big screen's sound is (video, browser tab, NDI or Spout)."))
	_row("Room ambience", _slider("ambience_volume", 0.0, 1.0, 0.01, "Background sound of the room (a murmuring crowd, city noise...). 0% = off."))
	_row("Curtain sounds", _slider("curtain_sound", 0.0, 1.0, 0.01, "The stage curtain's swish and the reveal's drum roll. 0% = silent."))
	_page_box.add_child(_hint("Room acoustics, speaker sound and lip-sync delays are in the control panel's Sound tab."))


func _build_costream() -> void:
	var info := NetSession.get_info()
	var role := String(info["role"])
	var peers: Array = info["peers"]
	var guests := maxi(peers.size() - 1, 0)
	var line := ""
	match role:
		"host":
			line = "Hosting · %d %s" % [guests, "guest" if guests == 1 else "guests"]
		"guest":
			line = "In %s's session" % String(info["host_name"]) if String(info["host_name"]) != "" else "Joining..."
		_:
			line = "Not in a co-stream"
	if bool(info.get("reconnecting", false)):
		line = "Reconnecting..."
	elif bool(info.get("syncing", false)):
		line = "Syncing... %d%%" % roundi(float(info.get("sync_progress", 0.0)) * 100.0)
	var state := Label.new()
	state.text = line
	state.add_theme_color_override("font_color", ACCENT)
	_page_box.add_child(state)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_page_box.add_child(buttons)
	if role == "off" and not bool(info.get("reconnecting", false)):
		buttons.add_child(_btn("Host a session", "Start a session others can join, with the address and password from the control panel's Co-stream tab.", func() -> void: NetSession.host()))
		var join := _btn("Join", "Join the host whose address is in the control panel's Co-stream tab.", func() -> void: NetSession.join())
		join.disabled = String(AppState.get_setting("together_address")).strip_edges() == ""
		buttons.add_child(join)
		_page_box.add_child(_hint("Your name, the password and the host's address are set in the control panel's Co-stream tab."))
	else:
		if role == "host":
			buttons.add_child(_btn("Copy invite address", "Copies the address guests need. It isn't shown on screen, so it can't end up on your stream.", func() -> void:
				var a := String(NetSession.get_info().get("address", ""))
				if a != "":
					DisplayServer.clipboard_set(a)
					EventBus.status_message.emit("Address copied. Paste it to your guests.", false)))
		if role == "guest":
			buttons.add_child(_btn("Resync", "If something looks different from the host's PC, ask the host for everything again.", func() -> void: NetSession.resync()))
		buttons.add_child(_btn("End session" if role == "host" else "Leave",
			"Stop hosting (guests keep what they see now)." if role == "host" else "Leave the session. Your room stays as it is now.", _leave))

	# who's in
	if not peers.is_empty():
		for p: Dictionary in peers:
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 10)
			var who := Label.new()
			var tags: Array = []
			if bool(p["me"]):
				tags.append("you")
			if int(p["id"]) == 1:
				tags.append("host")
			elif bool(p["cohost"]):
				tags.append("co-host")
			if not bool(p["synced"]):
				tags.append("syncing %d%%" % int(p["sync"]))
			if bool(p.get("remote", false)) and peers.size() > 1:
				tags.append("has the remote")
			elif bool(p.get("asked", false)):
				tags.append("asked for the remote")
			who.text = String(p["name"]) + (" (%s)" % ", ".join(tags) if not tags.is_empty() else "")
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(who)
			var rb := _remote_button(p, role)
			if rb != null:
				r.add_child(rb)
			if role == "host" and int(p["id"]) != 1:
				var id := int(p["id"])
				var co := CheckBox.new()
				co.text = "Co-host"
				co.button_pressed = bool(p["cohost"])
				co.tooltip_text = "A co-host can change the room, curtain and podiums for everyone."
				co.toggled.connect(func(on: bool) -> void: NetSession.set_cohost(id, on))
				r.add_child(co)
				var nm := String(p["name"])
				r.add_child(_btn("Remove", "Send them out of the session. They can't come back in until you host again.", func() -> void:
					_ask("Remove %s?" % nm, "%s leaves the session and can't rejoin it." % nm, "Remove", func() -> void: NetSession.remove_peer(id))))
			_page_box.add_child(r)
	for w: Dictionary in info.get("pending", []):
		var r := HBoxContainer.new()
		var who := Label.new()
		who.text = "%s wants to join" % String(w["name"])
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(who)
		var wid := int(w["id"])
		r.add_child(_btn("Let in", "Let them into the session.", func() -> void: NetSession.approve(wid, true)))
		r.add_child(_btn("No", "Turn them away.", func() -> void: NetSession.approve(wid, false)))
		_page_box.add_child(r)

	# Hide my address (NetSession "Hide my address"): the host's switch and what it covers
	if role != "guest":
		_page_box.add_child(_tick("together_hide_address", "Hide my address",
			"Guests join through a one-off Cloudflare address and the video goes through a relay, so nobody in the session learns where you are."))
		for e: Array in NetSession.hide_checklist():
			_page_box.add_child(_hint(("✓ " if bool(e[0]) else "⚠ ") + String(e[1])))
	elif NetSession.hides_address():
		_page_box.add_child(_hint("This co-stream hides everyone's address."))
	if role != "off" and peers.size() > 1:
		_page_box.add_child(_hint("Big screen remote: %s. Whoever has it decides what everyone's big screen shows (their shared tab, a web video, someone's avatar) and pauses it for everyone." % ("you have it" if bool(info.get("has_remote", false)) else String(info.get("remote", "")) + " has it")))
	_build_podiums(info, role)
	if role != "guest":
		var head := Label.new()
		head.text = "Everyone follows the host's"
		head.add_theme_font_size_override("font_size", 16)
		_page_box.add_child(head)
		var ticks := HFlowContainer.new()
		ticks.add_theme_constant_override("h_separation", 14)
		ticks.add_child(_tick("together_share_room", "Room", "Guests' rooms change with yours (and the big screen choice)."))
		ticks.add_child(_tick("together_share_curtain", "Curtain and lights", "Guests' curtain and house lights follow yours."))
		ticks.add_child(_tick("together_share_presenters", "Podiums", "Guests see your podiums (presenters) as you set them."))
		ticks.add_child(_tick("together_shared_audience", "One audience", "Everyone's chat sits in one audience, the same on every PC."))
		_page_box.add_child(ticks)
	var status := String(info.get("status", ""))
	if status != "":
		_page_box.add_child(_hint(status))
	_page_box.add_child(_hint("Quality, relay and Cloudflare settings are in the control panel's Co-stream tab."))


func _build_keys() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for k: Array in KEYS:
		var key := Label.new()
		key.text = String(k[0])
		key.add_theme_color_override("font_color", ACCENT)
		grid.add_child(key)
		var what := Label.new()
		what.text = String(k[1])
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART     # (else a long line widens the page past the window)
		what.custom_minimum_size = Vector2(200, 0)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(what)
	_page_box.add_child(grid)
	_page_box.add_child(_hint("Keys don't work while you type in a text box. Esc leaves the box first."))


## Claimed podiums (NetSession "Claimed podiums"): who has each podium, with Claim / Give up for a
## guest and Lock / Unlock / Free for the host. Shown while in a session with the podiums shared.
func _build_podiums(info: Dictionary, role: String) -> void:
	var list: Array = info.get("podiums", [])
	if role == "off" or list.is_empty() or not NetSession.group_shared("presenters"):
		return
	var head := Label.new()
	head.text = "Podiums"
	head.add_theme_font_size_override("font_size", 16)
	_page_box.add_child(head)
	var have_one := NetSession.my_podium() > 0
	for p: Dictionary in list:
		var n := int(p["n"])
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		var l := Label.new()
		var state := "the host's"
		if bool(p["mine"]):
			state = "yours"
		elif String(p["owner"]) != "":
			state = String(p["owner"]) + "'s"
		elif bool(p["locked"]):
			state = "locked by the host"
		elif role == "guest":
			state = "free"
		l.text = "Podium %d: %s" % [n, state]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		if role == "guest" and bool(p["mine"]):
			r.add_child(_btn("Give up", "Give this podium back to the host.", func() -> void: NetSession.claim_podium(n, false)))
		elif role == "guest" and bool(p["free"]):
			var claim := _btn("Claim", "Make this podium yours: it shows your My avatar, and you set its name tag, light, picture and chroma key in your Presenters tab. Everyone sees what you set.",
				func() -> void: NetSession.claim_podium(n))
			claim.text = "Move here" if have_one else "Claim"
			r.add_child(claim)
		elif role == "host":
			if String(p["owner"]) != "":
				r.add_child(_btn("Free", "Take this podium back from them (it goes off set).", func() -> void: NetSession.free_podium(n)))
			r.add_child(_btn("Unlock" if bool(p["locked"]) else "Lock",
				"Locked: nobody can claim this podium, it stays yours." if not bool(p["locked"]) else "Let guests claim this podium again.",
				func() -> void: NetSession.lock_podium(n, not bool(p["locked"]))))
		_page_box.add_child(r)
	if role == "guest":
		_page_box.add_child(_hint("Your podium shows your My avatar (camera, a tab or window, or a see-through web page; Co-stream tab). Set its name tag, light, picture and chroma key in the control panel's Presenters tab."))


## The big screen remote button for one person's row, or null: the host gives it to a guest or takes
## it back on its own row; a guest asks for it or gives it back on its own row (NetSession "Big
## screen remote"; the control panel's Co-stream tab has the same buttons).
func _remote_button(p: Dictionary, role: String) -> Button:
	var id := int(p["id"])
	var holds := bool(p.get("remote", false))
	var asked := bool(p.get("asked", false))
	if role == "host" and id != 1 and not holds:
		var give := _btn("Give remote", "Give them the big screen remote: their shared tab goes on everyone's big screen, and they can play a web video or pause for everyone. You can take it back any time.",
			func() -> void: NetSession.pass_remote(id))
		if asked:
			give.add_theme_color_override("font_color", Color(0.55, 1.0, 0.45))
		return give
	if role == "host" and id == 1 and not holds:
		return _btn("Take it back", "Take the big screen remote back: your shared tab is on everyone's big screen again.", func() -> void: NetSession.pass_remote(1))
	if role == "guest" and bool(p["me"]) and holds:
		return _btn("Give it back", "Give the big screen remote back to the host.", func() -> void: NetSession.pass_remote(1))
	if role == "guest" and bool(p["me"]):
		return _btn("Asked for the remote" if asked else "Ask for the remote",
			"Ask the host for the big screen remote (press again to take the question back).", func() -> void: NetSession.ask_remote(not asked))
	return null


# ── Actions ──────────────────────────────────────────────────────────

func _open_dashboard() -> void:
	var url := ChatFeed.core_url("/admin/")
	if url.begins_with("http"):
		OS.shell_open(url)
		EventBus.status_message.emit("Opening Stream Core's dashboard in your browser.", false)
	else:
		EventBus.status_message.emit("Stream Core's address isn't set (control panel: Chat tab).", true)


## Leave / end the session; a host with guests is asked first.
func _leave() -> void:
	var guests := NetSession.guest_count()
	if NetSession.get_role() == "host" and guests > 0:
		_ask("End the session?", "This ends the session for your %s. They keep what they see now, but stop following you." % ("guest" if guests == 1 else "%d guests" % guests),
			"End session", func() -> void: NetSession.leave())
	else:
		NetSession.leave()


func _quit() -> void:
	var guests := NetSession.guest_count()
	if NetSession.get_role() == "host" and guests > 0:
		_ask("Quit while hosting?", "Quitting ends the session for your %s." % ("guest" if guests == 1 else "%d guests" % guests),
			"Quit", func() -> void: AppState.request_quit(0))
	else:
		AppState.request_quit(0)


## A yes / no question in its own window, above the menu.
func _ask(title: String, text: String, ok_text: String, action: Callable) -> void:
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	var d := ConfirmationDialog.new()
	d.exclusive = false
	d.title = title
	d.dialog_text = text
	d.ok_button_text = ok_text
	d.cancel_button_text = "Cancel"
	d.confirmed.connect(func() -> void:
		action.call()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	_confirm = d
	_win.add_child(d)
	d.popup_centered()


# ── Keeping in step ──────────────────────────────────────────────────

func _on_setting_changed(key: String, _value: Variant) -> void:
	if WINDOW_KEYS.has(key):
		DisplayMode.apply(get_window())
	if is_open() and not _writing:
		_queue_rebuild()


## Something changed elsewhere (the panel, a guest's co-host change...): redraw the page once.
func _queue_rebuild() -> void:
	if _rebuild_queued or not is_open():
		return
	_rebuild_queued = true
	(func() -> void:
		_rebuild_queued = false
		if is_open():
			_show_page(_page)).call_deferred()


## Esc in the menu's window goes back to the room (unless a text box or a dropdown has it).
func _on_window_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		close()
		_win.set_input_as_handled()


func _write(key: String, value: Variant) -> void:
	_writing = true
	AppState.set_setting(key, value)
	_writing = false


# ── Small builders ───────────────────────────────────────────────────

func _nav_button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	# not flat: a flat button never draws its "pressed" look, which marks the open page
	for state in ["normal", "disabled"]:
		b.add_theme_stylebox_override(state, _box(Color(0, 0, 0, 0), 6))
	b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.06), 6))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 17)
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _btn(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


## One labelled line: name on the left, the control on the right.
func _row(text: String, control: Control) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(170, 0)
	r.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(control)
	_page_box.add_child(r)


## A row of buttons where one is picked. options: [[value, label], ...]; pick(value) does the change.
func _choice(options: Array, current: Variant, pick: Callable, tip: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for o: Array in options:
		var b := Button.new()
		b.text = String(o[1])
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = tip
		b.button_pressed = str(o[0]) == str(current)
		# the picked one stands out (orange, dark text); the rest sit on a dark strip
		b.add_theme_stylebox_override("normal", _box(Color(0.14, 0.15, 0.18), 6))
		b.add_theme_stylebox_override("hover", _box(Color(0.2, 0.21, 0.25), 6))
		b.add_theme_stylebox_override("pressed", _box(ACCENT, 6))
		b.add_theme_stylebox_override("hover_pressed", _box(ACCENT.lightened(0.1), 6))
		for state in ["font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(state, Color(0.1, 0.08, 0.05))
		var value: Variant = o[0]
		b.pressed.connect(func() -> void: pick.call(value))
		box.add_child(b)
	return box


## A dropdown bound to a setting. options: [[value, label], ...].
func _dropdown(key: String, options: Array, tip: String) -> OptionButton:
	var ob := OptionButton.new()
	ob.tooltip_text = tip
	var now := str(AppState.get_setting(key))
	for i in options.size():
		ob.add_item(String(options[i][1]))
		ob.set_item_metadata(i, options[i][0])
		if str(options[i][0]) == now:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: _write(key, ob.get_item_metadata(i)))
	return ob


## A tick box bound to a bool setting.
func _tick(key: String, text: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.button_pressed = bool(AppState.get_setting(key))
	c.toggled.connect(func(on: bool) -> void: _write(key, on))
	return c


## A 0..1 slider bound to a float setting, with its value in percent.
func _slider(key: String, lo: float, hi: float, step: float, tip: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(AppState.get_setting(key))
	s.tooltip_text = tip
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new()
	v.custom_minimum_size = Vector2(52, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = "%d%%" % roundi(s.value * 100.0)
	s.value_changed.connect(func(x: float) -> void:
		v.text = "%d%%" % roundi(x * 100.0)
		_write(key, x))
	box.add_child(s)
	box.add_child(v)
	return box


## A rounded flat background for buttons (colour, corner radius in pixels, a little padding).
func _box(color: Color, radius: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(radius)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return l
