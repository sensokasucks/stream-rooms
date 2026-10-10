extends Node
## Bubble filter (Audience tab > Bubbles show): which kinds of message get a speech bubble (text,
## emote-only, paid, highlighted, replies), the still-emotes switch, the two preset buttons, and
## that a filtered-out chatter still sits down.
##   <redot console exe> --path . _tests/test_bubble_filter.tscn -- C:/temp/sr_tests --mp-profile=test

const ANIM_URL := "https://example.invalid/test-anim.gif"

var _fails: int = 0
var _n: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## A chat message as ChatFeed hands it on. Each one is from a new chatter, so nobody's old bubble
## is still up.
func _say(text: String, tint: String = "", reply_to: String = "", emotes: Array = []) -> String:
	_n += 1
	var who := "Filter%d" % _n
	EventBus.chat_message_received.emit({
		"platform": "twitch", "user_id": who.to_lower(), "name": who, "color": "", "text": text,
		"emotes": emotes, "timestamp": Time.get_unix_time_from_system(), "tint": tint, "reply_to": reply_to,
		"history": false, "system": false, "is_mod": false, "is_vip": false, "is_subscriber": false,
	})
	return who


func _bubbled(view: AudienceView, who: String) -> bool:
	var slot := AudienceManager.find_slot_by_name(who)
	return slot >= 0 and bool(view._seats[slot]["active"])


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("audience_hide_commands", true)
	AppState.set_setting("audience_bubble_tints", true)
	AppState.set_setting("audience_bubble_s", 20.0)
	for key: String in AudienceManager.BUBBLE_FILTER_KEYS.values():
		AppState.set_setting(key, true)
	AppState.set_setting("audience_bubble_animated", true)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var room: Room = main.get_node("RoomHost").get_current_room()
	var view: AudienceView = room.find_child("Audience", true, false)
	_check(view != null, "the lecture hall has an audience")
	if view == null:
		AppState.request_quit(1)
		return
	view.max_bubbles = 64       # (every test bubble stays up)

	# what kind of message the parts are
	var emote := {"url": ANIM_URL, "name": "Wiggle"}
	var kinds := [
		[["hello there"], "text"],
		[["look ", emote], "text"],
		[[emote, " ", emote], "emotes"],
		[[{"tint": "paid"}, "take my money"], "paid"],
		[[{"tint": "paid"}, {"reply_to": "Sen", "quote": "hi"}, "for you"], "paid"],
		[[{"tint": "highlighted"}, "notice me"], "highlighted"],
		[[{"tint": "gigantified"}, emote], "highlighted"],
		[[{"reply_to": "Sen", "quote": "hi"}, "same"], "reply"],
	]
	var got: Array = []
	var want: Array = []
	for k: Array in kinds:
		got.append(AudienceManager.bubble_kind(k[0]))
		want.append(k[1])
	_check(got == want, "message kinds: %s" % str(got))

	# an animated emote ready in the cache (two frames)
	var anim := AnimatedTexture.new()
	anim.frames = 2
	for f in 2:
		var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color.RED if f == 0 else Color.BLUE)
		anim.set_frame_texture(f, ImageTexture.create_from_image(img))
		anim.set_frame_duration(f, 0.2)
	EmoteCache._store(ANIM_URL, anim)
	var e_range := [{"start": 0, "end": 5, "url": ANIM_URL, "static_url": "", "provider": "twitch"}]

	# everything on: every kind gets a bubble
	var all_on := {
		"text": _say("hello everyone"),
		"emotes": _say("Wiggle", "", "", e_range),
		"paid": _say("take my money", "paid"),
		"highlighted": _say("notice me", "highlighted"),
		"reply": _say("same here", "", "Sen"),
	}
	await _secs(1.0)
	var shown: Array = []
	for k: String in all_on:
		if _bubbled(view, String(all_on[k])):
			shown.append(k)
	_check(shown.size() == 5, "everything ticked: every kind gets a bubble (%s)" % str(shown))
	var e_slot := AudienceManager.find_slot_by_name(String(all_on["emotes"]))
	if e_slot >= 0:
		view._show_bubble(e_slot)      # (drawn now, even if the camera can't see that seat)
	_check(e_slot >= 0 and bool(view._seats[e_slot].get("animated", false)), "Animated emotes on: the emote bubble animates")

	# the busy-chat preset: only paid and highlighted, still emotes
	var panel: Node = main.get_node("ControlPanel")
	panel._bubble_preset(false)
	var on: Array = []
	for key: String in AudienceManager.BUBBLE_FILTER_KEYS.values():
		if bool(AppState.get_setting(key)):
			on.append(key)
	_check(on == ["audience_bubble_paid", "audience_bubble_highlighted"] and not bool(AppState.get_setting("audience_bubble_animated")),
		"Busy chat preset: only paid and highlighted, still emotes (%s)" % str(on))
	var busy := {
		"text": _say("hello again"),
		"emotes": _say("Wiggle", "", "", e_range),
		"paid": _say("more money", "paid"),
		"paid reply": _say("money for you", "paid", "Sen"),
		"highlighted": _say("look at me", "highlighted"),
		"reply": _say("agreed", "", "Sen"),
	}
	await _secs(1.0)
	shown.clear()
	for k: String in busy:
		if _bubbled(view, String(busy[k])):
			shown.append(k)
	_check(shown == ["paid", "paid reply", "highlighted"], "busy chat: only paid (replies too) and highlighted bubbles (%s)" % str(shown))
	_check(AudienceManager.find_slot_by_name(String(busy["text"])) >= 0, "a chatter whose message got no bubble still sits down")

	# mix and match: emotes back on, still frames
	AppState.set_setting("audience_bubble_emotes", true)
	var still_one := _say("Wiggle", "", "", e_range)
	var plain_text := _say("words, no bubble")
	await _secs(1.0)
	var s_slot := AudienceManager.find_slot_by_name(still_one)
	if s_slot >= 0:
		view._show_bubble(s_slot)
	_check(_bubbled(view, still_one) and not _bubbled(view, plain_text), "Emote-only ticked on its own: the emote gets a bubble, text doesn't")
	_check(s_slot >= 0 and not bool(view._seats[s_slot].get("animated", true)), "Animated emotes off: the bubble shows a still frame (drawn once)")

	# the panel has the controls, each with a tooltip
	var missing: Array = []
	for key: String in AudienceManager.BUBBLE_FILTER_KEYS.values() + ["audience_bubble_animated"]:
		var c: Variant = panel._checks.get(key)
		if c == null or String((c as Control).tooltip_text) == "":
			missing.append(key)
	_check(missing.is_empty(), "the Audience tab has a ticked box with a tooltip for each (%s missing)" % str(missing))
	EventBus.camera_preset_requested.emit(12)
	var tabs: TabContainer = panel._tabs
	for t in tabs.get_tab_count():
		if tabs.get_tab_title(t) == "Audience":
			tabs.current_tab = t
	await _secs(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/bubble_filter.png")

	# Show everything puts it all back
	panel._bubble_preset(true)
	var back := true
	for key: String in AudienceManager.BUBBLE_FILTER_KEYS.values() + ["audience_bubble_animated"]:
		back = back and bool(AppState.get_setting(key))
	_check(back, "Show everything ticks every box again")

	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
