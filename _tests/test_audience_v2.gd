extends Node
## Curtain opening with screen colours, crowd chatters moving down, separate crowd timeout,
## filler people in empty main seats.
func _secs(t): await get_tree().create_timer(t).timeout
func _chat(name: String) -> void:
	EventBus.chat_message_received.emit({"name": name, "platform": "kick", "user_id": name.to_lower(), "text": "hi",
		"timestamp": Time.get_unix_time_from_system()})
func _counts(aud: AudienceView) -> Array:
	var main := 0
	var crowd := 0
	for i in aud.get_seat_count():
		if aud.is_seat_taken(i):
			if AudienceManager.get_slot_kind(i) == 0:
				main += 1
			elif AudienceManager.get_slot_kind(i) == 1:
				crowd += 1
	return [main, crowd]
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("curtain_enabled", true)
	AppState.set_setting("audience_idle_min", 60.0)
	AppState.set_setting("audience_crowd_idle_min", 60.0)
	AppState.set_setting("audience_crowd_move_down", true)
	AppState.set_setting("audience_fill_main", false)
	AppState.set_setting("audience_crowd_fill", 0.6)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("lecture_hall")
	await _secs(4.0)
	var room = main.get_node("RoomHost").get_current_room()
	var aud: AudienceView = room.find_child("Audience", false, false)
	# 1) the curtain opening after the screen has sent its colours (the user's lock-up)
	var sl = room.find_child("ScreenLights", false, false)
	sl._on_colors(Color.RED, Color.GREEN, Color.BLUE)
	AppState.set_curtain(true, "instant")
	await _secs(0.3)
	AppState.set_curtain(false)
	await _secs(0.5)
	print("curtain open: targets=", sl._targets, " typed ok=", sl._targets.get_typed_builtin() == TYPE_COLOR)
	# 2) crowd chatters move down as main seats free up
	for n in 100:
		_chat("Viewer%03d" % n)
	await _secs(0.3)
	print("100 chatters: main/crowd=", _counts(aud))
	var now := Time.get_unix_time_from_system()
	var gone := 0
	for i in aud.get_seat_count():
		if gone < 5 and aud.is_seat_taken(i) and AudienceManager.get_slot_kind(i) == 0:
			AudienceManager._members[AudienceManager._slots[i]]["last"] = now - 7200.0
			gone += 1
	AudienceManager._expire_idle()
	await _secs(0.3)
	print("5 main-seat chatters time out: main/crowd=", _counts(aud), " (want 79/16)")
	# 3) the crowd has its own timeout
	AppState.set_setting("audience_crowd_move_down", false)
	AppState.set_setting("audience_crowd_idle_min", 1.0)
	for k: String in AudienceManager._members.keys():
		AudienceManager._members[k]["last"] = now - 120.0     # 2 min quiet
	AudienceManager._expire_idle()
	await _secs(0.3)
	print("2 min quiet, crowd timeout 1 min, main 60 min: main/crowd=", _counts(aud), " (want 79/0)")
	# 4) filler people in empty main seats
	AudienceManager.clear()
	AppState.set_setting("audience_fill_main", true)
	await _secs(0.3)
	var pit_fillers := 0
	for i in aud._rich:
		if bool(aud._seats[i].get("filler", false)):
			pit_fillers += 1
	print("fill main on: pit fillers=", pit_fillers, " of 79, total fillers=", aud.get_filler_count())
	_chat("Newcomer")
	await _secs(0.3)
	var ns := AudienceManager.find_slot_for_user("kick", "newcomer")
	print("newcomer slot kind=", AudienceManager.get_slot_kind(ns), " filler there now=", aud._seats[ns]["filler"])
	var cam: CameraRig = main.get_node("CameraRig")
	cam.global_position = Vector3(0, 3.6, -1.8)
	cam.look_at(Vector3(0, 1.2, 10), Vector3.UP)
	await _secs(1.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/v2_fill_main.png")
	print("DONE")
	AppState.request_quit()
