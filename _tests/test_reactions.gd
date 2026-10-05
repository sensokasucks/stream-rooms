extends Node
## Chat reactions end to end: a fake Stream Core (WebSocket server in this test) seats chatters,
## checks the game's hello / room_state, sends reactions and reads the results back.
## Run: godot --path . res://_tests/test_reactions.tscn -- <screenshot dir>

const PORT: int = 3899

var _server := TCPServer.new()
var _peer: WebSocketPeer
var _got: Array[Dictionary] = []
var _fails: int = 0
var _out: String = "/tmp"


func _secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(_out + "/" + shot_name)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _process(_d: float) -> void:
	if _peer == null and _server.is_connection_available():
		_peer = WebSocketPeer.new()
		_peer.accept_stream(_server.take_connection())
	if _peer:
		_peer.poll()
		while _peer.get_available_packet_count() > 0:
			var t := _peer.get_packet().get_string_from_utf8()
			if t == "ping":
				continue
			var m: Variant = JSON.parse_string(t)
			if m is Dictionary:
				_got.append(m)


func _send(msg: Dictionary) -> void:
	_peer.send_text(JSON.stringify(msg))


func _chat(user: String, text: String) -> void:
	_send({"type": "chat", "data": {"platform": "twitch", "message_id": str(randi()), "message": text,
		"timestamp": Time.get_unix_time_from_system(), "emotes": [],
		"user": {"id": user.to_lower(), "username": user.to_lower(), "display_name": user, "color": "",
			"is_mod": false, "is_vip": false, "is_subscriber": false, "badges": []}}})


func _react(id: String, effect: String, from: String, target: Variant, params: Dictionary = {}, route: String = "game", count: int = 1) -> void:
	_send({"type": "reaction", "data": {"id": id, "reaction": effect, "label": effect, "effect": effect, "params": params,
		"count": count, "from": {"platform": "twitch", "id": from.to_lower(), "username": from.to_lower(), "display_name": from},
		"target": target, "route": route, "message": "!" + effect + " hello chat", "cost": 0}})


func _last(type: String) -> Dictionary:
	for i in range(_got.size() - 1, -1, -1):
		if String(_got[i].get("type")) == type:
			return _got[i]
	return {}


func _result(id: String) -> String:
	for m in _got:
		if String(m.get("type")) == "reaction_result" and String(m["data"].get("id")) == id:
			return String(m["data"].get("outcome"))
	return "(none)"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_server.listen(PORT, "127.0.0.1")
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:%d/ws" % PORT)
	AppState.set_setting("chat_enabled", true)
	AppState.set_setting("audience_idle_min", 30.0)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	ChatFeed.reconnect()
	await _secs(0.5)
	AppState.request_room("theater")
	await _secs(4.0)
	_check(_peer != null, "game connected to fake Core")
	var hello := {}
	for m in _got:
		if String(m.get("type")) == "hello":
			hello = m
	_check(not hello.is_empty() and String(hello["data"]["client"]) == "stream_rooms", "hello sent")
	var ids: Array = (hello.get("data", {}).get("effects", []) as Array).map(func(e: Dictionary) -> String: return e["id"])
	_check(ids.has("throw") and ids.has("stadium_wave") and ids.size() == Reactions.EFFECTS.size(), "hello lists every effect (%d)" % ids.size())
	for who in ["Alice", "Bob", "Carol", "Dave", "Erin", "Frank", "Gina", "Hank"]:
		_chat(who, "hi from %s" % who)
	# wait (up to 10 s on slow machines) for a room_state that has the room and the seats
	var rs := {}
	for i in 50:
		await _secs(0.2)
		rs = _last("room_state")
		if String(rs.get("data", {}).get("room", "")) == "theater" and (rs["data"].get("seated", []) as Array).has("bob"):
			break
	_check(String(rs.get("data", {}).get("room", "")) == "theater", "room_state room = theater")
	var tids: Array = (rs["data"]["targets"] as Array).map(func(t: Dictionary) -> String: return t["id"])
	print("targets: ", tids, " guests: ", rs["data"]["guests"])
	_check(tids.has("screen"), "screen target offered")
	_check((rs["data"].get("seated", []) as Array).has("bob"), "bob is listed as seated")

	var layer: ReactionLayer = main.get_node("RoomHost").get_current_room().find_child("Reactions", true, false)
	_check(layer != null, "room has a ReactionLayer")
	AppState.toggle_clean_feed()
	var cam: Camera3D = get_viewport().get_camera_3d()
	var scr: Dictionary = layer.resolve_target({"type": "stage", "name": "screen"})
	await _secs(1.5)
	cam.global_position = scr["pos"] + (scr["normal"] as Vector3) * 7.5 + Vector3.UP * 0.6
	cam.look_at(scr["pos"] + Vector3.DOWN * 0.8)

	# tomatoes: at bob, at the screen (3 at once), at someone who isn't here
	_react("r1", "throw", "Alice", {"type": "user", "name": "bob"}, {"object": "🍅", "impact": "splat", "stick_sec": 6})
	_react("r2", "throw", "Carol", {"type": "stage", "name": ""}, {"object": "🍅", "impact": "splat", "stick_sec": 6}, "game", 3)
	_react("r3", "throw", "Dave", {"type": "user", "name": "nobody"}, {"object": "🥚", "impact": "splat"})
	await _secs(0.45)
	await _shot("rx_throw_flight.png")
	await _secs(0.9)
	await _shot("rx_throw_splat.png")
	_check(_result("r1") == "hit", "throw at @bob -> hit")
	_check(_result("r2") == "hit", "throw x3 at the stage -> hit")
	_check(_result("r3") == "fallback", "throw at a missing person -> fallback")

	_react("r4", "confetti", "Erin", {"type": "stage", "name": "screen"}, {"count": 120})
	_react("r5", "fall_down", "Frank", {"type": "user", "name": "gina"}, {"object": "🌹", "count": 14, "duration_sec": 4})
	_react("r6", "float_up", "Hank", null, {"object": "❤️", "count": 6, "duration_sec": 3})
	await _secs(0.6)
	await _shot("rx_confetti_roses.png")
	_react("r7", "big_shout", "Alice", null, {"text": "{message}", "color": "#ffd400", "duration_sec": 4})
	_react("r7b", "big_shout", "Alice", null, {"text": "again right away", "duration_sec": 1})
	await _secs(1.8)
	_react("r7c", "big_shout", "Alice", null, {"text": "and after the last one freed itself", "duration_sec": 2})
	_react("r7d", "big_shout", "Nobody", null, {"text": "no seat", "duration_sec": 1})
	_react("r8", "wiggle", "Bob", null, {"style": "jump", "duration_sec": 2})
	_react("r9", "stadium_wave", "Carol", null, {"speed": 1.0})
	await _secs(0.7)
	await _shot("rx_shout_wave.png")
	_react("r10", "spotlight", "Dave", {"type": "user", "name": "alice"}, {"color": "#fff6d0", "duration_sec": 3})
	_react("r11", "lights", "Erin", null, {"mode": "tint", "color": "#ff3b6b", "duration_sec": 2})
	_react("r12", "camera_shake", "Frank", null, {"strength": 0.8, "duration_sec": 0.6})
	_react("r13", "rain", "Gina", null, {"object": "🎉", "count": 60, "duration_sec": 4})
	await _secs(1.2)
	await _shot("rx_spot_rain.png")
	_react("r14", "pile_up", "Hank", {"type": "stage", "name": ""}, {"object": "🍅", "max_pile": 30}, "game", 5)
	_react("r15", "wiggle", "Zed", null, {})                     # not seated -> dropped
	_react("r16", "disco", "Alice", null, {})                    # unknown effect -> dropped
	_react("r17", "throw", "Alice", null, {}, "overlay")        # overlay route -> ignored
	for i in 3:
		_react("m%d" % i, "meter", "Bob", null, {"meter_id": "applause", "goal": 3, "payoff_effect": "confetti"})
	await _secs(1.8)
	await _shot("rx_pile_meter.png")
	for id in ["r4", "r5", "r6", "r7", "r7b", "r7c", "r8", "r9", "r10", "r11", "r12", "r13", "r14"]:
		_check(_result(id) == "hit", "%s -> hit (got %s)" % [id, _result(id)])
	_check(_result("r7d") == "fallback", "big shout from someone without a seat -> fallback (over the stage)")
	_check(_result("r15") == "dropped", "wiggle from someone without a seat -> dropped")
	_check(_result("r16") == "dropped", "unknown effect -> dropped")
	_check(_result("r17") == "(none)", "overlay-route reaction ignored")
	_check(_result("m2") == "hit", "meter fills")
	print("live objects now: ", layer.get_live_count())

	AppState.set_setting("reactions_enabled", false)
	_react("r18", "throw", "Alice", null, {})
	await _secs(0.4)
	_check(_result("r18") == "dropped", "reactions off -> dropped (refund)")
	AppState.set_setting("reactions_enabled", true)

	# podium room: guests + chat screen
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	for _i in 20:        # (a slow machine can take longer to build the room)
		if String(_last("room_state").get("data", {}).get("room", "")) == "lecture_hall_panel":
			break
		await _secs(0.5)
	await _secs(1.2)
	rs = _last("room_state")
	var gids: Array = (rs["data"]["guests"] as Array).map(func(g: Dictionary) -> String: return g["id"])
	tids = (rs["data"]["targets"] as Array).map(func(t: Dictionary) -> String: return t["id"])
	print("panel targets: ", tids, " guests: ", gids)
	_check(String(rs["data"]["room"]) == "lecture_hall_panel", "room_state follows the room swap")
	_check(gids.has("presenter2") and gids.has("presenter3") and not gids.has("presenter1"), "guests = presenters on set")
	_check(tids.has("podium2") and tids.has("podium3") and not tids.has("podium1"), "podiums on set are stage targets")
	_check(tids.has("chat"), "chat screen target offered")
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.5)
	var pod: Dictionary = main.get_node("RoomHost").get_current_room().find_child("Reactions", true, false).resolve_target({"type": "stage", "name": "podium2"})
	var pres: Dictionary = main.get_node("RoomHost").get_current_room().find_child("Reactions", true, false).resolve_target({"type": "guest", "name": "guest2"})
	print("podium2 at ", (pod["pos"] as Vector3).snapped(Vector3.ONE * 0.01), " presenter2 at ", (pres["pos"] as Vector3).snapped(Vector3.ONE * 0.01))
	# compare the spot centres: resolve_target adds random jitter, which made this check flaky
	var panel_layer: Node = main.get_node("RoomHost").get_current_room().find_child("Reactions", true, false)
	var pod_y: float = (panel_layer._find_spot("podium2")["pos"] as Vector3).y
	var pres_y: float = (panel_layer._find_spot("guest2")["pos"] as Vector3).y
	print("podium2 centre y=", snappedf(pod_y, 0.01), " presenter2 centre y=", snappedf(pres_y, 0.01))
	_check(not bool(pod["fallback"]) and pod_y < pres_y, "podium2 sits below presenter2's picture")
	var cam2: Camera3D = get_viewport().get_camera_3d()
	cam2.global_position = (pod["pos"] as Vector3) + (pod["normal"] as Vector3) * 5.0 + Vector3.UP * 0.8
	cam2.look_at((pod["pos"] as Vector3) + Vector3.UP * 0.7)
	var spaced: Dictionary = main.get_node("RoomHost").get_current_room().find_child("Reactions", true, false).resolve_target({"type": "guest", "name": "Presenter 2"})
	_check(not bool(spaced["fallback"]) and (spaced["pos"] as Vector3).distance_to(pres["pos"]) < 1.5, "'Presenter 2' (with a space) finds presenter2")
	_react("r19", "throw", "Alice", {"type": "guest", "name": "presenter2"}, {"object": "🍅", "stick_sec": 5})
	_react("r21", "throw", "Carol", {"type": "stage", "name": "podium2"}, {"object": "🍅", "stick_sec": 5}, "game", 2)
	_react("r22", "throw", "Dave", {"type": "stage", "name": "podium3"}, {"object": "🥚", "stick_sec": 5})
	_react("r20", "throw", "Bob", {"type": "stage", "name": "chat"}, {"object": "🥚", "stick_sec": 5})
	await _secs(1.4)
	await _shot("rx_podium.png")
	_check(_result("r19") == "hit" and _result("r20") == "hit", "throws at a presenter and the chat screen -> hit")
	_check(_result("r21") == "hit" and _result("r22") == "hit", "throws at podiums -> hit")
	AppState.set_setting(AppState.presenter_key(1, "on"), false)    # (saved settings may have it on already)
	await _secs(0.5)
	AppState.set_setting(AppState.presenter_key(1, "on"), true)
	for _i in 16:       # room_state goes out at most once a second (slow machines: longer)
		await _secs(0.5)
		gids = (_last("room_state")["data"]["guests"] as Array).map(func(g: Dictionary) -> String: return g["id"])
		tids = (_last("room_state")["data"]["targets"] as Array).map(func(t: Dictionary) -> String: return t["id"])
		if gids.has("presenter1"):
			break
	print("after presenter 1 on: guests=", gids, " targets=", tids)
	_check(gids.has("presenter1") and tids.has("podium1"), "putting presenter 1 on set adds presenter1 + podium1")
	AppState.set_setting(AppState.presenter_key(1, "on"), false)
	await _secs(1.2)
	print("DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
