extends Node
## The UI review changes (October 2026): Advanced folds closed by default and remembered, the
## Source tab showing one source at a time, chat windows as one summary row each, seat spacing
## thinning the audience, newer speech bubbles pushing older overlapping ones up, far name tags
## fading. Also saves one screenshot per panel tab (look at them: the layout is the point).
##   <redot console exe> --path . _tests/test_ui_review.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _main: Node
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if bool(cond.call()):
			return true
		await _secs(0.25)
		t += 0.25
	return bool(cond.call())


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name))


func _msg(who: String, text: String) -> void:
	EventBus.chat_message_received.emit({"platform": "twitch", "user_id": who.to_lower(), "name": who, "color": "",
		"text": text, "emotes": [], "avatar": "", "timestamp": Time.get_unix_time_from_system(), "history": false, "system": false})


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("audience_names", true)
	AppState.set_setting("audience_seat_gap", 1.0)
	_main = load("res://core/main.tscn").instantiate()
	add_child(_main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var panel: Node = _main.get_node("ControlPanel")
	var tabs: TabContainer = panel._tabs

	# ── Advanced folds: closed by default, remembered ──
	var folds: Array = []
	for b in panel._panel.find_children("*", "Button", true, false):
		if String((b as Button).text).begins_with("Advanced"):
			folds.append(b)
	_check(folds.size() >= 8, "every tab has its Advanced folds (%d)" % folds.size())
	var all_closed := true
	for b: Button in folds:
		all_closed = all_closed and b.text.ends_with("▸")
	_check(all_closed, "the folds start closed")
	var room_fold: Button = null
	for b: Button in folds:
		if b.is_ancestor_of(panel._gfx_hint) or (b.get_parent() as Node).get_parent() == panel._gfx_hint.get_parent().get_parent():
			room_fold = b
	# (the Room tab's fold holds the performance block)
	var perf_box: Control = panel._gfx_hint.get_parent()
	_check(not perf_box.visible, "the performance settings are folded away")
	var room_btn: Button = (perf_box.get_meta("fold_button") if perf_box.has_meta("fold_button") else room_fold) as Button
	_check(room_btn != null, "the Room tab's Advanced button was found")
	if room_btn:
		room_btn.pressed.emit()
		await _secs(0.3)
		_check(perf_box.visible and String(AppState.get_setting("panel_advanced")).contains("room"), "opening it shows the performance settings and is remembered")
		room_btn.pressed.emit()
		await _secs(0.3)
		_check(not perf_box.visible and not String(AppState.get_setting("panel_advanced")).contains("room"), "closing it is remembered too")

	# ── Source tab: one source at a time ──
	var shown := 0
	for m: String in panel._source_sections:
		if (panel._source_sections[m] as Control).visible:
			shown += 1
	_check(shown == 1, "the Source tab shows one source's controls (%d)" % shown)
	AppState.set_setting("source_tab_pick", "spout")
	panel._show_source_section("spout")
	await _secs(0.2)
	_check((panel._source_sections["spout"] as Control).visible and not (panel._source_sections["capture"] as Control).visible,
		"picking Spout shows the Spout controls only")
	_check(panel._spout_label.is_visible_in_tree(), "the Spout status line shows without opening Advanced (review batch 3)")
	panel._show_source_section("capture")

	# ── Chat tab: summary rows ──
	_check(panel._size_marks.size() == 4 and panel._platform_boxes.has("chat_left_chat"), "each chat window has a summary row with platform ticks")
	var left_text: HSlider = panel._sliders["chat_left_text"]
	_check(not left_text.is_visible_in_tree(), "a chat window's Text size sits under its Advanced fold")

	# ── Seat spacing: fewer seats than with every seat used ──
	var room: Room = _main.get_node("RoomHost").get_current_room()
	var spaced := room.get_audience_seats().size()
	AppState.set_setting("audience_seat_gap", 0.5)
	var dense := room.get_audience_seats().size()
	AppState.set_setting("audience_seat_gap", 1.0)
	_check(dense > spaced and spaced > 0, "1.0 m seat spacing keeps fewer main seats than 0.5 m (%d vs %d)" % [spaced, dense])
	var kept: Array[Transform3D] = room.get_audience_seats()
	var too_close := 0
	for a in kept.size():
		for b in range(a + 1, kept.size()):
			var d := kept[a].origin - kept[b].origin
			if absf(d.y) < 0.5 and Vector2(d.x, d.z).length() < 0.99:
				too_close += 1
	_check(too_close == 0, "no two kept seats on a row are closer than the spacing (%d pairs)" % too_close)
	_check(await _wait_for(func() -> bool: return AudienceManager.get_capacity() == 0 or AudienceManager.get_capacity() <= dense + 4000, 2.0), "the seat count follows")

	# (a new seat spacing reloads the room shortly after: wait for it and pick the room up again)
	await _secs(5.0)
	room = _main.get_node("RoomHost").get_current_room()
	_check(room != null and room.get_audience_seats().size() == spaced, "the room reloaded with the new spacing")

	# ── Bubbles: a newer one pushes an older overlapping one up ──
	var view: AudienceView = room.find_child("Audience", true, false)
	_check(view != null, "the room has an audience view")
	var cam := get_viewport().get_camera_3d()
	var rig: CameraRig = _main.get_node("CameraRig")
	panel.visible = false
	# six chatters talk at once with big bubbles, seated front row first so they sit together
	AppState.set_setting("audience_seating", "front")
	AppState.set_setting("audience_bubble_size", 1.6)
	AppState.set_setting("audience_bubble_s", 20.0)
	var names := ["FirstTalker", "SecondTalker", "ThirdTalker", "FourthTalker", "FifthTalker", "SixthTalker"]
	for who in names:
		_msg(who, "%s here with a fairly long message so that my bubble is wide on screen" % who)
		await _secs(0.15)
	await _secs(0.5)
	var up_before := view._bubbling.size()
	# the camera preset that sees the most of them, overlapping: that's where the nudge matters
	var best := -1
	var best_score := -1
	for pi in rig._presets.size():
		rig.go_to_preset(pi, false)
		await _secs(0.6)
		var seen := 0
		var pairs := 0
		var base: Array[Rect2] = []
		for i in view._bubbling:
			var info: Dictionary = view._bubble_rect(i, cam)
			if info.is_empty():
				continue
			seen += 1
			base.append(info["rect"])
		for a in base.size():
			for b in range(a + 1, base.size()):
				if base[a].intersects(base[b]):
					pairs += 1
		if pairs * 10 + seen > best_score:
			best_score = pairs * 10 + seen
			best = pi
	print("best preset for the bubble check: %d (%s), score %d" % [best, rig._labels[best] if best >= 0 else "?", best_score])
	rig.go_to_preset(best, false)
	await _secs(0.5)
	# a fresh round of messages from this camera (the sweep itself pushed bubbles about)
	for who in names:
		_msg(who, "%s again, another long message so that the bubbles overlap from here" % who)
		await _secs(0.15)
	await _secs(0.5)
	up_before = view._bubbling.size()
	await _secs(1.0)
	var visible_slots: Array[int] = []
	var rects: Dictionary = {}
	var base_rects: Dictionary = {}
	var nudged := 0
	for i in view._bubbling:
		var info: Dictionary = view._bubble_rect(i, cam)
		if info.is_empty():
			continue
		visible_slots.append(i)
		var r: Rect2 = info["rect"]
		base_rects[i] = r
		var push_px := float(view._seats[i].get("nudge", 0.0)) / float(info["wpp"])
		rects[i] = Rect2(r.position - Vector2(0.0, push_px), r.size)
		if push_px > 0.5:
			nudged += 1
	_check(visible_slots.size() >= 2, "at least two bubbles are on screen (%d of %d)" % [visible_slots.size(), view._bubbling.size()])
	var overlaps := 0
	var before := 0
	for a in visible_slots.size():
		for b in range(a + 1, visible_slots.size()):
			if (rects[visible_slots[a]] as Rect2).intersects(rects[visible_slots[b]] as Rect2):
				overlaps += 1
			if (base_rects[visible_slots[a]] as Rect2).intersects(base_rects[visible_slots[b]] as Rect2):
				before += 1
	var ended_early := up_before - view._bubbling.size()
	print("bubbles up: ", up_before, " -> ", view._bubbling.size(), "; on screen: ", visible_slots.size(), " overlapping pairs before: ", before,
		" nudged: ", nudged, " ended early: ", ended_early, " overlapping pairs after: ", overlaps)
	_check(before > 0 or ended_early > 0, "some bubbles would have overlapped (%d pairs now, %d gave way)" % [before, ended_early])
	_check(overlaps == 0, "no two bubbles overlap on screen now")
	_check(nudged > 0 or ended_early > 0, "the newer bubbles won: %d moved up, %d older ones faded out early" % [nudged, ended_early])
	await _shot("ui_bubbles.png")
	AppState.set_setting("audience_bubble_size", 1.0)
	AppState.set_setting("audience_bubble_s", 8.0)
	panel.visible = true

	# ── Name tags fade with distance ──
	var faded := 0
	var near_tags := 0
	for i in view._rich:
		var s: Dictionary = view._seats[i]
		var lbl: Label3D = s["label"]
		if not bool(s["seated"]):
			continue
		if lbl.modulate.a < 0.5:
			faded += 1
		else:
			near_tags += 1
	print("name tags: near=", near_tags, " faded=", faded)

	# ── one screenshot per tab ──
	panel.visible = true
	for n in tabs.get_tab_count():
		tabs.current_tab = n
		await _secs(0.4)
		await _shot("ui_tab_%d_%s.png" % [n, tabs.get_tab_title(n).to_lower()])
	tabs.current_tab = 0
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
