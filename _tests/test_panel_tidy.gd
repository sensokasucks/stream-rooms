extends Node
## Panel tidy (review batch 7): every control has a tooltip ("?" help), the two picture ticks have
## different names, Empty all seats / seating presets / Stop hosting ask first, settings moved to
## the right tab (Screen light on Room, the boards on Games), Advanced folds on Audience / Sound /
## React, "No limit" at 0, distinct Presenters slider names, the hide-pictures list (kick:name,
## logins, the quick "Hide a picture..." list), and the accessibility details (chat window ticks
## carry the window's name, a clickable ⚠, the Flash strength cap note, the mic note).
##   <redot console exe> --path . _tests/test_panel_tidy.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_for(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call():
			return true
		await _secs(0.1)
		t += 0.1
	return bool(cond.call())


func _find_button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


## The tab (ScrollContainer page) a control sits on.
func _tab_of(panel: Node, c: Node) -> String:
	var n := c
	while n != null and n.get_parent() != panel._tabs:
		n = n.get_parent()
	return String(n.name) if n != null else ""


## A control's own tooltip, or its row's (the helpers put it on the row for a slider / dropdown / text box).
func _has_tip(c: Control, stop: Node) -> bool:
	var n: Node = c
	while n != null and n != stop:
		if n is Control and (n as Control).tooltip_text != "":
			return true
		if n.get_parent() is VBoxContainer:
			return false
		n = n.get_parent()
	return false


func _say(who: String, plat: String, text: String) -> void:
	EventBus.chat_message_received.emit({"name": who, "platform": plat, "user_id": who.to_lower(), "username": who.to_lower() + "_login",
		"text": text, "color": "#88ccff", "timestamp": Time.get_unix_time_from_system()})


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("seating_by_platform", false)
	AppState.set_setting("seating_plan", "")
	AppState.set_setting("audience_hide_avatars", "")
	AppState.set_setting("audience_crowd_max", 300)
	AppState.set_setting("panel_advanced", "")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(2.5)
	var panel: Node = main.get_node("ControlPanel")
	var root: Control = panel._panel

	# ── every control has a tooltip, so it gets its "?" help ──
	var missing: Array = []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not (c is BaseButton or c is Range or c is LineEdit):
			continue
		if c is ScrollBar or (c is LineEdit and (c as LineEdit).flat) or c.has_meta("help_q"):
			continue
		if c.get_parent() is SeatingChart or c is SeatingChart:
			continue
		if not _has_tip(c, root):
			var label := ""
			if c is Button:
				label = (c as Button).text
			if label == "" and c.get_parent() and c.get_parent().get_child_count() > 0 and c.get_parent().get_child(0) is Label:
				label = (c.get_parent().get_child(0) as Label).text
			missing.append("%s: %s %s" % [_tab_of(panel, c), c.get_class(), label])
	for m: String in missing:
		print("  no tooltip: ", m)
	_check(missing.is_empty(), "every control on the panel has a tooltip (%d without)" % missing.size())

	# ── the two picture ticks ──
	var chat_pics: CheckBox = panel._checks["chat_screen_pictures"]
	var aud_pics: CheckBox = panel._checks["audience_avatars"]
	_check(chat_pics.text == "Pictures in chat windows" and aud_pics.text == "Chatter pictures (everywhere)",
		"the two picture ticks have their own names (%s / %s)" % [chat_pics.text, aud_pics.text])
	_check(String(panel._checks["audience_bubble_tints"].tooltip_text).contains("chat windows"), "Colour paid ... says it changes the chat windows too")

	# ── settings in the right tab ──
	_check(_tab_of(panel, panel._sliders["screen_light"]) == "Room" and _tab_of(panel, panel._sliders["screen_glow"]) == "Room",
		"Screen light / Screen glow are on the Room tab")
	_check(panel._options.has("board_hud") and _tab_of(panel, panel._options["board_hud"]) == "Games", "the boards' dropdown is on the Games tab")
	AppState.set_setting("board_hud", "off")
	var bo: OptionButton = panel._options["board_hud"]
	_check(String(bo.get_item_metadata(bo.selected)) == "off", "Boards in the corner follows the setting when it changes elsewhere")
	AppState.set_setting("board_hud", "auto")
	_check(_tab_of(panel, panel._sliders["board_hud_scale"]) == "Games", "Board size is on the Games tab")

	# ── Advanced folds on Audience, Sound and React ──
	for key: String in ["audience_seat_gap", "audience_crowd_max", "room_acoustics", "audio_delay_ms", "duck_threshold_db"]:
		var s: Control = panel._sliders[key]
		var body: Control = s.get_parent()
		while body != null and not body.has_meta("fold_button"):
			body = body.get_parent()
		_check(body != null and not body.visible, "%s sits under a closed Advanced fold" % key)
	_check(_tab_of(panel, panel._sliders["volume"]) == "Sound" and panel._sliders["volume"].get_parent().get_parent().get_parent() is ScrollContainer,
		"Video volume stays on the Sound tab's main part")

	# ── "No limit" at 0 ──
	var cm: HSlider = panel._sliders["audience_crowd_max"]
	var num := cm.get_parent().get_child(2) as LineEdit
	AppState.set_setting("audience_crowd_max", 0)
	await get_tree().process_frame
	_check(num.text == "No limit", "Most chatters in crowd shows No limit at 0 (%s)" % num.text)
	AppState.set_setting("audience_crowd_max", 300)
	await get_tree().process_frame
	_check(num.text == "300", "and the number otherwise (%s)" % num.text)
	panel._apply_typed(cm, num, "%d", "0", "No limit")
	_check(int(AppState.get_setting("audience_crowd_max")) == 0 and num.text == "No limit", "typing 0 gives No limit")
	AppState.set_setting("audience_crowd_max", 300)

	# ── Presenters: distinct names ──
	var d0: Control = panel._pres_details[0]
	var labels: Dictionary = {}
	var dup := ""
	for l in d0.find_children("*", "Label", true, false):
		var t := (l as Label).text
		if t != "" and l.get_parent() is HBoxContainer and l.get_index() == 0:
			if labels.has(t):
				dup = t
			labels[t] = true
	_check(dup == "" and labels.has("Presenter up/down") and labels.has("Podium picture up/down"), "the Presenters sliders have distinct names (dup: '%s')" % dup)
	_check(panel._checks.has(AppState.presenter_key(1, "picture_self_lit")) and panel._checks[AppState.presenter_key(1, "picture_self_lit")].text == "Podium picture self-lit",
		"Podium picture self-lit is named apart from the presenter's Self-lit")

	# ── Together hint ──
	var tail := ""
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("Up to four people"):
			tail = (l as Label).text
	_check(tail != "" and not tail.contains("100.x") and tail.contains("Copy address"), "the Together hint describes Copy address, not typing a Tailscale address")

	# ── chat windows: the Show tick carries the name; the ⚠ opens the fold ──
	var left_show: CheckBox = panel._checks["chat_left"]
	_check(left_show.text == "Left of the screen", "a chat window's Show tick is labelled with the window's name (%s)" % left_show.text)
	var mark: Control = panel._size_marks["chat_left"]
	_check(mark is Button and mark.focus_mode == Control.FOCUS_ALL, "the ⚠ is a button you can reach with the keyboard")
	var left_text: HSlider = panel._sliders["chat_left_text"]
	var fold_body: Control = left_text.get_parent().get_parent()
	_check(not fold_body.visible, "the window's Advanced starts closed")
	(mark as Button).pressed.emit()
	_check(fold_body.visible, "clicking the ⚠ opens it (Make readable is there)")
	(mark as Button).pressed.emit()
	_check(fold_body.visible, "a second click leaves it open")
	(fold_body.get_meta("fold_button") as Button).pressed.emit()
	_check(panel._sliders.has("chat_left_columns") and panel._sliders.has("chat_right_columns"), "the side windows have a Columns slider")

	# ── Flash strength cap note ──
	AppState.set_setting("flash_strength", 1.0)
	AppState.set_setting("photosensitive_safe", true)
	_check(panel._flash_note.visible and String(panel._flash_note.text).contains("30%"), "safe mode says Flash strength is capped at 30%")
	AppState.set_setting("photosensitive_safe", false)
	_check(not panel._flash_note.visible, "the note goes when safe mode is off")

	# ── mic note ──
	AppState.set_setting("duck_enabled", true)
	_check(String(panel._duck_label.text) == AudioManager.get_mic_problem(), "the React tab's meter says why the mic can't be heard ('%s')" % panel._duck_label.text)
	AppState.set_setting("duck_enabled", false)
	_check(String(panel._duck_label.text) == "", "and nothing with auto-duck off")

	# ── hide pictures: Core's syntax, logins, and the quick list ──
	AudienceManager.clear()
	_say("Bob", "kick", "hello")
	_say("Ann", "twitch", "hi there")
	_check(await _wait_for(func() -> bool: return AudienceManager.get_seated_people().size() >= 2, 3.0), "two test chatters sat down")
	AppState.set_setting("audience_hide_avatars", "kick:Bob")
	_check(AudienceManager.is_picture_hidden("kick", "Bob") and not AudienceManager.is_picture_hidden("twitch", "Bob"), "kick:Bob hides Bob on Kick only")
	AppState.set_setting("audience_hide_avatars", "ann_login")
	_check(AudienceManager.is_picture_hidden("twitch", "Ann", "ann_login"), "a login name works as well as the display name")
	AppState.set_setting("audience_hide_avatars", "@Ann\nkick:bob")
	_check(AudienceManager.is_picture_hidden("twitch", "ann") and AudienceManager.is_picture_hidden("kick", "BOB"), "names pasted one per line from Core's list work too")
	AppState.set_setting("audience_hide_avatars", "")
	panel._fill_hide_pick()
	var hp: OptionButton = panel._hide_pick
	_check(hp.item_count >= 3 and hp.get_item_text(1).begins_with("Ann"), "Hide a picture... lists the seated people, newest first (%s)" % (hp.get_item_text(1) if hp.item_count > 1 else "none"))
	panel._on_hide_pick(1)
	_check(String(AppState.get_setting("audience_hide_avatars")) == "twitch:Ann" and AudienceManager.is_picture_hidden("twitch", "Ann"),
		"picking Ann hides her picture (%s)" % AppState.get_setting("audience_hide_avatars"))
	_check(hp.selected == 0, "the list goes back to Hide a picture...")
	AppState.set_setting("audience_hide_avatars", "")

	# ── ask first: Empty all seats ──
	var empty_btn := _find_button(root, "Empty all seats")
	_check(empty_btn != null, "Clear is now called Empty all seats")
	var seated := AudienceManager.get_seated_people().size()
	empty_btn.pressed.emit()
	await get_tree().process_frame
	var dlg: ConfirmationDialog = panel._confirm
	_check(dlg != null and dlg.visible and AudienceManager.get_seated_people().size() == seated, "it asks first and nobody has left yet")
	_check(dlg != null and (dlg.force_native or not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)), "the question is its own window (not on stream)")
	dlg.canceled.emit()
	dlg.hide()
	await get_tree().process_frame
	_check(AudienceManager.get_seated_people().size() == seated, "Cancel leaves everyone seated")
	empty_btn.pressed.emit()
	await get_tree().process_frame
	dlg = panel._confirm
	dlg.confirmed.emit()
	await get_tree().process_frame
	_check(AudienceManager.get_seated_people().is_empty(), "OK empties the seats")

	# ── ask first: seating presets over a hand-made plan ──
	AudienceManager.set_plan({})
	panel._confirm = null
	panel._apply_seating_preset("quadrant_each")
	_check(panel._confirm == null and bool(AppState.get_setting("seating_by_platform")), "an empty plan takes a preset without asking")
	_check(not AudienceManager.preset_replaces_plan("quadrant_each"), "the same preset again wouldn't change anything")
	panel._apply_seating_preset("quadrant_each")
	_check(panel._confirm == null, "so it doesn't ask")
	_check(AudienceManager.preset_replaces_plan("anyone"), "Anyone anywhere would throw the plan away")
	panel._apply_seating_preset("anyone")
	await get_tree().process_frame
	dlg = panel._confirm
	_check(dlg != null and String(AppState.get_setting("seating_plan")) != "" and String(AppState.get_setting("seating_plan")) != "{}", "it asks before wiping the plan")
	dlg.confirmed.emit()
	await get_tree().process_frame
	_check(not bool(AppState.get_setting("seating_by_platform")) and not AudienceManager.preset_replaces_plan("anyone"), "OK wipes it")

	# ── ask first: Stop hosting, only with guests in ──
	panel._confirm = null
	(panel._net_leave_btn as Button).pressed.emit()
	await get_tree().process_frame
	_check(panel._confirm == null, "Leave / stop hosting with nobody connected doesn't ask")

	for t: int in [4, 5, 7, 8]:
		(panel._tabs as TabContainer).current_tab = t
		await _secs(0.5)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out.path_join("panel_tidy_%s.png" % (panel._tabs as TabContainer).get_tab_title(t).to_lower()))
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
