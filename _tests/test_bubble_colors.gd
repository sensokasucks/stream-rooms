extends Node
## Bubble colours: the dark bubble theme, gold Super Chat / Bits and purple Twitch-highlight
## bubbles and chat-window cards (Stream Core's is_paid / highlight fields), the setting that turns
## the colours off, and the {tint} marker surviving the shared-audience mirror copy.
##   <redot console exe> --path . _tests/test_bubble_colors.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _spoken: Dictionary = {}       # slot -> last parts


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _payload(who: String, text: String, extra: Dictionary) -> Dictionary:
	var d := {"platform": "twitch", "message": text, "user": {"id": who.to_lower(), "username": who.to_lower(), "display_name": who}}
	d.merge(extra)
	return d


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	EventBus.audience_spoke.connect(func(slot: int, parts: Array) -> void: _spoken[slot] = parts)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("chat_screen", true)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("audience_bubble_theme", "light")
	AppState.set_setting("audience_bubble_tints", true)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var room: Room = main.get_node("RoomHost").get_current_room()
	var cs: ChatScreen = room.find_child("ChatScreen", true, false)
	var view: AudienceView = room.find_child("Audience", true, false)
	_check(cs != null and view != null, "the lecture hall has a chat window and an audience")

	# what ChatFeed makes of Stream Core's payload
	var feed: Node = ChatFeed
	var hl: Dictionary = feed._normalize(_payload("Proto", "Pippa would be the kind of person", {"highlight": "highlighted"}), false)
	var paid: Dictionary = feed._normalize(_payload("Soup", "every ps2 game back in the day", {"is_paid": true, "paid_amount": 500.0, "paid_currency": "bits"}), false)
	var plain: Dictionary = feed._normalize(_payload("Ann", "hi", {"highlight": null, "is_paid": false}), false)
	var odd: Dictionary = feed._normalize(_payload("Odd", "hm", {"highlight": "something-new"}), false)
	_check(hl.get("tint") == "highlighted", "a highlighted Twitch message gets the highlighted tint")
	_check(paid.get("tint") == "paid", "a paid message gets the paid tint")
	_check(plain.get("tint") == "" and odd.get("tint") == "", "plain messages and unknown styles get none")

	EventBus.chat_message_received.emit(hl)
	EventBus.chat_message_received.emit(paid)
	EventBus.chat_message_received.emit(plain)
	await _secs(1.5)

	# chat window cards
	var tints: Array[String] = []
	var boxes: Array[bool] = []
	for c in cs._cards:
		tints.append(String(c.get("tint", "")))
		boxes.append((c["tint_bg"] as ColorRect).visible)
	_check(tints == ["highlighted", "paid", ""], "the chat window cards carry the tints (%s)" % str(tints))
	_check(boxes == [true, true, false], "highlighted and paid cards get a coloured box, the plain one doesn't (%s)" % str(boxes))

	# bubbles
	var p_slot := AudienceManager.find_slot_by_name("Proto")
	var s_slot := AudienceManager.find_slot_by_name("Soup")
	var a_slot := AudienceManager.find_slot_by_name("Ann")
	_check(p_slot >= 0 and _spoken.has(p_slot) and _spoken[p_slot][0] is Dictionary and _spoken[p_slot][0].get("tint") == "highlighted",
		"the highlighted bubble's parts start with its tint")
	_check(a_slot >= 0 and _spoken.has(a_slot) and _spoken[a_slot][0] is String, "a plain bubble's parts start with its text")
	var fills := {}
	for pair: Array in [["Proto", p_slot], ["Soup", s_slot], ["Ann", a_slot]]:
		if int(pair[1]) >= 0:
			view._show_bubble(int(pair[1]))
			var b: SpeechBubble = view._seats[int(pair[1])]["bubble"]
			fills[pair[0]] = b._fill if b else Color.BLACK
	_check(fills.get("Proto", Color.BLACK).is_equal_approx(SpeechBubble.TINT_FILLS["highlighted"][0]), "the highlighted bubble is purple")
	_check(fills.get("Soup", Color.BLACK).is_equal_approx(SpeechBubble.TINT_FILLS["paid"][0]), "the paid bubble is gold")
	_check(fills.get("Ann", Color.BLACK).v > 0.9, "the plain bubble is white in the light theme")
	await _secs(0.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/bubble_colors_light.png")

	# the dark theme redraws the bubbles that are up
	AppState.set_setting("audience_bubble_theme", "dark")
	await _secs(0.3)
	if a_slot >= 0:
		var b: SpeechBubble = view._seats[a_slot]["bubble"]
		_check(b != null and b._fill.v < 0.3, "the plain bubble turns dark at once")
		var txt: Color = b._rtl.get_theme_color("default_color") if b else Color.BLACK
		_check(txt.v > 0.8, "with light text")
	if p_slot >= 0:
		var b: SpeechBubble = view._seats[p_slot]["bubble"]
		_check(b != null and b._fill.is_equal_approx(SpeechBubble.TINT_FILLS["highlighted"][1]), "the highlighted bubble takes its dark purple")
	EventBus.camera_preset_requested.emit(12)
	await _secs(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/bubble_colors_dark.png")

	# colours off: a highlighted message looks like any other
	AppState.set_setting("audience_bubble_tints", false)
	var hl2: Dictionary = feed._normalize(_payload("Lumen", "again with points", {"highlight": "highlighted"}), false)
	EventBus.chat_message_received.emit(hl2)
	await _secs(1.0)
	var l_slot := AudienceManager.find_slot_by_name("Lumen")
	# (the {tint} marker still comes along, for the bubble filter; the bubble draws it plain)
	_check(l_slot >= 0 and _spoken.has(l_slot) and _spoken[l_slot][0] is Dictionary and _spoken[l_slot][0].get("tint") == "highlighted",
		"with the colours off the parts still say it's highlighted (for the bubble filter)")
	if l_slot >= 0:
		view._show_bubble(l_slot)
		var lb: SpeechBubble = view._seats[l_slot]["bubble"]
		_check(lb != null and not lb._fill.is_equal_approx(SpeechBubble.TINT_FILLS["highlighted"][1]) and lb._fill.v < 0.3,
			"but the bubble is a plain dark one")
	var last: Dictionary = cs._cards[cs._cards.size() - 1]
	_check(String(last.get("tint", "")) == "" and not (last["tint_bg"] as ColorRect).visible, "and neither has the chat card")
	AppState.set_setting("audience_bubble_tints", true)

	# the mirror copy (shared audience) keeps a known tint before the reply marker, drops unknown ones
	if a_slot >= 0:
		_spoken.erase(a_slot)
		AudienceManager._mirror = true
		AudienceManager.mirror_speak(AudienceManager._capacity_room, a_slot, [{"tint": "paid"}, {"reply_to": "Sen", "quote": "q"}, "text"])
		var m1: Array = _spoken.get(a_slot, [])
		AudienceManager.mirror_speak(AudienceManager._capacity_room, a_slot, [{"tint": "rainbow"}, "text"])
		var m2: Array = _spoken.get(a_slot, [])
		AudienceManager._mirror = false
		_check(m1.size() == 3 and m1[0].get("tint") == "paid" and String(m1[1].get("reply_to", "")) == "Sen" and m1[2] == "text",
			"the mirror copy keeps the tint and the reply marker (%s)" % str(m1))
		_check(m2 == ["text"], "and drops a tint it doesn't know (%s)" % str(m2))

	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
