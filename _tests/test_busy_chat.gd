extends Node
## Busy chat (review batch 6): round profile pictures made off the main thread, the picture cache
## keeping to its size budget without dropping pictures still on screen, speech bubbles capped and
## reused, the seat counts kept in step with the seats, the default crowd limit, and the compiled
## patterns in message_parts.
##   <redot console exe> --path . _tests/test_busy_chat.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _chat(who: String, text: String) -> void:
	EventBus.chat_message_received.emit({"platform": "kick", "user_id": who.to_lower(), "name": who, "color": "",
		"text": text, "emotes": [], "avatar": "", "timestamp": Time.get_unix_time_from_system(), "tint": "",
		"history": false, "system": false})


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	_check(int(AppState.DEFAULTS["audience_crowd_max"]) == 300, "new settings start with a crowd limit of 300")

	# ── round pictures, off the main thread ──
	var url := "https://example.invalid/avatar_%d.png" % Time.get_ticks_usec()
	var src := Image.create(200, 160, false, Image.FORMAT_RGBA8)
	src.fill(Color(0.2, 0.6, 1.0))
	var f := FileAccess.open(EmoteCache._disk_path(url), FileAccess.WRITE)
	f.store_buffer(src.save_png_to_buffer())
	f.close()
	var ready: Array[String] = []
	EventBus.emote_ready.connect(func(u: String) -> void: ready.append(u))
	var first := EmoteCache.get_circle_texture(url, 128)
	_check(first == null, "the round picture isn't made on the spot (a worker thread makes it)")
	for i in 100:
		if ready.has(url):
			break
		await get_tree().process_frame
	var disc := EmoteCache.get_circle_texture(url, 128)
	_check(ready.has(url) and disc != null and disc.get_width() == 128, "it's ready a moment later, 128 px, and emote_ready says so")
	if disc:
		var img := disc.get_image()
		_check(img.get_pixel(1, 1).a < 0.05 and img.get_pixel(64, 64).a > 0.95 and absf(img.get_pixel(64, 64).b - 1.0) < 0.05,
			"it's round: corners see-through, middle solid (%s / %s)" % [img.get_pixel(1, 1), img.get_pixel(64, 64)])
		var rim := img.get_pixel(64, 0).a
		_check(rim > 0.05 and rim < 0.95, "with a soft rim (alpha %.2f at the top edge)" % rim)
	DirAccess.remove_absolute(EmoteCache._disk_path(url))

	# ── the cache keeps to its budget, but keeps what's on screen ──
	EmoteCache.max_cache_bytes = 1024 * 1024
	var held := Sprite3D.new()
	add_child(held)
	for i in 30:
		var im := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		im.generate_mipmaps()
		var t := ImageTexture.create_from_image(im)
		var key := "test://cache/%d" % i
		if i == 0:
			held.texture = t          # shown somewhere: must stay
		EmoteCache._store(key, t)
		await get_tree().process_frame
	var stats := EmoteCache.get_cache_stats()
	_check(int(stats["bytes"]) <= 1024 * 1024, "the cache stays within its budget (%d KB)" % int(stats["bytes"] / 1024.0))
	_check(EmoteCache._textures.has("test://cache/0"), "a picture still on screen is kept, even though it's the oldest")
	_check(not EmoteCache._textures.has("test://cache/1"), "the oldest unused one went")
	_check(EmoteCache._textures.has("test://cache/29"), "the newest is there")
	held.queue_free()
	EmoteCache.max_cache_bytes = EmoteCache.MAX_CACHE_BYTES

	# ── message_parts with the compiled patterns ──
	var parts := AudienceManager.message_parts("hi   [emote:123:wave]   there", [])
	_check(parts.size() == 3 and parts[1] is Dictionary and String(parts[1]["name"]) == "wave" and String(parts[0]) == "hi ",
		"Kick emote tokens and spaces still parse (%s)" % str(parts))

	# ── the room: bubbles capped and reused, seat counts in step ──
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var room: Room = main.get_node("RoomHost").get_current_room()
	var view: AudienceView = room.find_child("Audience", true, false)
	AudienceManager.clear()
	AppState.set_setting("audience_crowd_max", 300)
	var most := 0
	for n in 120:
		_chat("Busy%03d" % n, "message number %d" % n)
		most = maxi(most, view._bubbling.size())
		if n % 10 == 9:
			await get_tree().process_frame
	await _secs(0.5)
	for i in view._bubbling.duplicate():
		if bool(view._seats[i]["pending"]):
			view._show_bubble(i)
	_check(most <= view.max_bubbles and view._bubbling.size() <= view.max_bubbles, "at most %d bubbles at once (most seen %d)" % [view.max_bubbles, most])
	var vps := 0
	for n in view.find_children("*", "SubViewport", true, false):
		vps += 1
	_check(vps <= view.max_bubbles * 2 + 2, "bubble viewports are bounded too (%d in the room's audience)" % vps)
	# end every bubble now: they go to the pool, and the next ones come from it
	for i in view._bubbling.duplicate():
		view._end_bubble(i, false)
	var pooled: int = view._bubble_pool.size()
	_check(pooled > 0 and pooled <= view.max_bubbles, "finished bubbles wait in a pool for reuse (%d)" % pooled)
	var reused_vp: SubViewport = (view._bubble_pool[-1] as Dictionary)["vp"] if pooled > 0 else null
	_chat("Busy119", "and again")
	await get_tree().process_frame
	var again := AudienceManager.find_slot_for_user("kick", "busy119")
	if again >= 0 and bool(view._seats[again]["pending"]):
		view._show_bubble(again)
	_check(again >= 0 and view._seats[again]["viewport"] != null and view._seats[again]["viewport"] == reused_vp,
		"the next bubble reuses a pooled one instead of a new viewport")

	# seat counts kept in step with the seats
	var empty_seats := 0
	var empty_crowd := 0
	var crowd := 0
	for i in AudienceManager._slots.size():
		var k := AudienceManager.get_slot_kind(i)
		var taken := AudienceManager._slots[i] != ""
		if k == AudienceManager.KIND_SEAT and not taken:
			empty_seats += 1
		elif k == AudienceManager.KIND_CROWD:
			if taken:
				crowd += 1
			else:
				empty_crowd += 1
	_check(AudienceManager._empty_seats == empty_seats and AudienceManager._empty_crowd == empty_crowd and AudienceManager.get_crowd_count() == crowd,
		"seat counts match the seats (empty %d/%d, crowd %d)" % [empty_seats, empty_crowd, crowd])
	# full room: a newcomer still gets the seat of the quietest
	AppState.set_setting("audience_crowd_max", 10)
	await get_tree().process_frame
	for n in 40:
		_chat("Late%02d" % n, "hi")
	_check(AudienceManager.find_slot_for_user("kick", "late39") >= 0, "with every seat taken the newest chatter still gets a seat")
	_check(AudienceManager.get_crowd_count() <= 10, "and the crowd keeps to its limit (%d)" % AudienceManager.get_crowd_count())

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("busy_chat.png"))
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
