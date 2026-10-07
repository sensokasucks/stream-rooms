extends Node
## Room changes under chat load. Switches between the lecture hall and the theater every two
## seconds while chat flows in (replayed from _tests/assets/chat_sample.json when it exists, else
## made up), then quits the safe way. Redot 26.2 crashed when a room with shadow-casting lights was
## freed right after being shown; RoomHost now hides the old room and frees it later, and
## AppState.request_quit darkens the room before quitting. The runner's "exit 0" is the real check
## here; the PASS lines say each room actually arrived.
##   <redot console exe> --path . _tests/test_room_swaps.tscn -- C:/temp/sr_tests --mp-profile=test

const SWAPS: int = 8
const ROOMS: Array[String] = ["lecture_hall_panel", "theater"]

var _fails: int = 0
var _rooms_seen: PackedStringArray = []


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	EventBus.room_changed.connect(func(id: String) -> void: _rooms_seen.append(id))
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("chat_screen", true)
	AppState.set_setting("audience_enabled", true)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room(ROOMS[0])
	await _secs(5.0)
	var host: RoomHost = main.get_node("RoomHost")
	var msgs := _messages()
	var i := 0
	var next := 1
	for swap in SWAPS:
		AppState.request_room(ROOMS[next % ROOMS.size()])
		# two seconds of chat, one message a frame, while the room loads and the old one is let go
		var t := 0.0
		while t < 2.0:
			var m: Dictionary = msgs[i % msgs.size()]
			EventBus.chat_message_received.emit({"platform": "twitch", "user_id": String(m["name"]).to_lower(), "name": m["name"],
				"color": "", "text": m["text"], "emotes": [], "avatar": "", "timestamp": Time.get_unix_time_from_system(),
				"history": false, "system": false})
			i += 1
			t += get_process_delta_time()
			await get_tree().process_frame
		var room := host.get_current_room()
		_check(room != null and String(AppState.get_setting("room_id")) == ROOMS[next % ROOMS.size()],
			"swap %d: the %s is the current room" % [swap + 1, ROOMS[next % ROOMS.size()]])
		next += 1
	await _secs(3.0)        # (the last old room is freed in here)
	_check(get_tree().root.find_children("*", "Room", true, false).size() == 1, "only one room is left in the tree")
	_check(_rooms_seen.size() >= SWAPS, "every room change was announced (%d)" % _rooms_seen.size())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/room_swaps.png")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)


func _messages() -> Array:
	var path := "res://_tests/assets/chat_sample.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array and not (parsed as Array).is_empty():
			return parsed
	var out: Array = []
	for n in 60:
		out.append({"name": "Viewer%d" % n, "text": "message %d with some words so it wraps now and then %s" % [n, "LEAN BACK ".repeat(n % 4)]})
	return out
