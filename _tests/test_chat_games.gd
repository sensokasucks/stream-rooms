extends Node
## Chat games in Stream Rooms: the new crowd / seat effects, boards in the corner HUD and on
## the reply screen, seat moves and swaps, regulars' titles on name tags.
var outcomes: Dictionary = {}
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _ref(n: int) -> Dictionary:
	return {"platform": "twitch", "id": "viewer%d" % n, "username": "viewer%d" % n, "display_name": "Viewer%d" % n}
func _play(effect: String, params: Dictionary, from: int, target: Variant = null, crowd: Array = []) -> String:
	var id := "t-%s-%d" % [effect, randi()]
	var d := {"id": id, "reaction": effect, "label": effect, "effect": effect, "params": params, "count": 1,
		"from": _ref(from), "target": target, "route": "game"}
	if not crowd.is_empty():
		d["crowd"] = crowd
	EventBus.reaction_play.emit(d)
	return id
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("reactions_enabled", true)
	AppState.set_setting("board_hud", "auto")
	AppState.set_setting("audience_seating", "random")
	EventBus.reaction_finished.connect(func(id: String, o: String) -> void: outcomes[id] = o)
	var main = load("res://core/main.tscn").instantiate()
	main.get_node("ControlPanel").visible = false
	add_child(main)
	await _secs(0.5)
	AppState.request_room("theater")
	await _secs(4.0)
	for i in 10:
		EventBus.chat_message_received.emit({"platform": "twitch", "user_id": "viewer%d" % i, "name": "Viewer%d" % i,
			"username": "viewer%d" % i, "color": "", "text": "hi", "emotes": [], "avatar": "",
			"timestamp": Time.get_unix_time_from_system(), "history": false, "system": false,
			"title": "Regular" if i % 3 == 0 else ""})
	await _secs(0.8)
	var room = main.get_node("RoomHost").get_current_room()
	var view: AudienceView = room.find_child("*Audience*", true, false) as AudienceView
	if view == null:
		for n in room.find_children("*", "Node3D", true, false):
			if n is AudienceView:
				view = n
	var s0 := AudienceManager.find_slot_by_name("viewer0")
	print("seated=", AudienceManager.get_seated_count(), " tag0=", (view._seats[s0]["label"] as Label3D).text)
	# boards
	var now := Time.get_unix_time_from_system()
	EventBus.board_changed.emit({"id": "poll", "kind": "bars", "title": "📊 Snack?", "state": "open", "ends_at": now + 60,
		"lines": [{"label": "1. Popcorn", "pct": 0.6, "note": "6 (60%)", "value": 6}, {"label": "2. Nachos", "pct": 0.4, "note": "4 (40%)", "value": 4}],
		"footer": "Vote: !1 !2"})
	EventBus.board_changed.emit({"id": "hype", "kind": "meter", "title": "🔥 Hype", "state": "open",
		"lines": [{"label": "Level 1", "pct": 0.4, "note": "7 chatting", "value": 7}], "footer": "Level 2 at 10 people"})
	EventBus.board_changed.emit({"id": "tug", "kind": "tug", "title": "Cheer vs boo", "state": "closed",
		"lines": [{"label": "📣 Cheer", "pct": 0.7, "note": "7", "win": true}, {"label": "👎 Boo", "pct": 0.3, "note": "3"}], "footer": "Cheers win!"})
	await _secs(0.6)
	var hud = main.get_node("BoardHud")
	print("hud boards=", hud.get_board_count(), " visible=", hud.visible)
	# effects
	var ids := {}
	ids["crowd_dance"] = _play("crowd_motion", {"style": "dance", "who": "all", "duration_sec": 4}, 0)
	ids["sign"] = _play("sign", {"text": "GO TEAM", "color": "#ffd400", "duration_sec": 20}, 0)
	ids["sleep"] = _play("seat_prop", {"prop": "sleep", "duration_sec": 12}, 1)
	ids["snack"] = _play("seat_prop", {"prop": "snack", "duration_sec": 12}, 4)
	ids["phone"] = _play("seat_prop", {"prop": "phone", "duration_sec": 12}, 5)
	ids["highfive"] = _play("highfive", {}, 2, {"type": "user", "name": "viewer3"})
	ids["float_crowd"] = _play("float_up", {"object": "😂", "count": 3, "duration_sec": 3}, 6, null, [_ref(6), _ref(7), _ref(8)])
	ids["fireworks"] = _play("fireworks", {"count": 6, "duration_sec": 3}, 0)
	ids["fire"] = _play("stage_fire", {"duration_sec": 6}, 0)
	ids["police"] = _play("lights", {"mode": "police", "duration_sec": 3}, 0)
	var before9 := AudienceManager.find_slot_by_name("viewer9")
	ids["move"] = _play("seat_move", {"where": "front"}, 9)
	var s7 := AudienceManager.find_slot_by_name("viewer7")
	var s8 := AudienceManager.find_slot_by_name("viewer8")
	ids["swap"] = _play("seat_swap", {}, 7, {"type": "user", "name": "viewer8"})
	await _secs(1.5)
	var after9 := AudienceManager.find_slot_by_name("viewer9")
	print("move row ", AudienceManager.get_seat_row(before9), " -> ", AudienceManager.get_seat_row(after9))
	print("swap ok=", AudienceManager.find_slot_by_name("viewer7") == s8 and AudienceManager.find_slot_by_name("viewer8") == s7)
	var res := {}
	for k in ids:
		res[k] = outcomes.get(ids[k], "?")
	print("outcomes=", res)
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.0)
	await _shot(out + "/games_theater.png")
	# close-up of the seats: sign, props, titles
	var cam := Camera3D.new()
	add_child(cam)
	var head: Vector3 = view.get_seat_head(AudienceManager.find_slot_by_name("viewer0"))
	var stage_at: Vector3 = room.find_screen().global_position if room.find_screen() else head + Vector3(0, 0, -5)
	var towards := (stage_at - head)
	towards.y = 0
	cam.global_position = head + towards.normalized() * 3.2 + Vector3.UP * 0.9
	cam.look_at(head + Vector3.UP * 0.2)
	cam.current = true
	await _secs(0.8)
	await _shot(out + "/games_seats.png")
	cam.queue_free()
	# lecture hall panel: the reply screen shows the boards, the HUD steps aside
	AppState.request_room("lecture_hall_panel")
	await _secs(4.0)
	EventBus.core_reply_received.emit({"message": "📊 Snack? !1 Popcorn · !2 Nachos", "platform": "kick", "reply_to_user": "",
		"source": "chat_game", "timestamp": Time.get_unix_time_from_system(), "history": false})
	EventBus.board_changed.emit({"id": "predict", "kind": "bars", "title": "🔮 Will there be a twist?", "state": "open",
		"lines": [{"label": "1. Yes", "pct": 0.75, "note": "300 pts · 4"}, {"label": "2. No", "pct": 0.25, "note": "100 pts · 2"}],
		"footer": "!predict 1 50"})
	await _secs(1.0)
	var room2 = main.get_node("RoomHost").get_current_room()
	var screens = get_tree().get_nodes_in_group("reply_screen")
	print("reply screens=", screens.size(), " cards=", screens[0].get_message_count() if screens.size() else -1, " hud visible=", hud.visible)
	for n in room2.find_children("*", "Camera3D", true, false):
		pass
	var scr: Node3D = screens[0]
	var cam2 := Camera3D.new()
	add_child(cam2)
	var fwd: Vector3 = scr.global_basis.z.normalized()
	cam2.global_position = scr.global_position + fwd * 2.6 + Vector3.DOWN * 0.9 + scr.global_basis.x.normalized() * -1.8
	cam2.look_at(scr.global_position + Vector3.DOWN * 0.7 + scr.global_basis.x.normalized() * -1.8)
	cam2.current = true
	await _secs(0.8)
	await _shot(out + "/games_lecture.png")
	print("DONE")
	AppState.request_quit()
