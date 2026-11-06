extends Node
## Click on people in the room (core/people_picker.gd): a Shift+click on a chatter's head finds
## them (ReactionLayer.pick_at) and opens their menu; Throw plays a reaction at them, Seat reserves
## their seat, Show their last message puts it on the message line, Highlight makes their seat
## glow; a click on the big screen finds the screen; a click on empty floor finds nothing.
##   <redot console exe> --path . _tests/test_people_menu.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("reactions_enabled", true)
	AppState.set_setting("audience_reserved", "")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var picker: PeoplePicker = main.find_child("PeoplePicker", true, false)
	var rig: CameraRig = main.get_node("CameraRig")
	var room: Room = main.get_node("RoomHost").get_current_room()
	var layer: ReactionLayer = room.find_child("Reactions", true, false)
	var view: AudienceView = room.find_child("Audience", true, false)
	_check(picker != null and layer != null and view != null, "the picker and the room's reaction layer are there")

	EventBus.chat_message_received.emit({"platform": "twitch", "user_id": "clicky", "name": "Clicky", "color": "",
		"text": "hello from seat land", "emotes": [], "timestamp": Time.get_unix_time_from_system(), "tint": "",
		"history": false, "system": false, "is_mod": false, "is_vip": false, "is_subscriber": false})
	await _secs(0.5)
	var slot := AudienceManager.find_slot_by_name("Clicky")
	_check(slot >= 0, "Clicky sits down")
	var head := view.get_seat_head(slot)
	AppState.set_setting("camera_glide", 0.0)
	rig.global_transform = Transform3D.IDENTITY.translated(head + Vector3(0, 0.6, 2.5)).looking_at(head)
	await get_tree().process_frame
	await get_tree().process_frame

	var info := picker.pick(rig.unproject_position(head) + Vector2(6, -4))
	_check(String(info.get("kind", "")) == "user" and String(info.get("name", "")) == "Clicky", "a click on their head finds Clicky (%s)" % str(info))

	var plays: Array = []
	EventBus.reaction_play.connect(func(d: Dictionary) -> void: plays.append(d))
	picker._on_item(PeoplePicker.THROW_ID)
	await get_tree().process_frame
	_check(plays.size() == 1 and String(plays[0]["effect"]) == "throw"
		and String((plays[0]["target"] as Dictionary).get("name", "")) == "Clicky", "Throw ▸ Tomato throws at them")

	var messages: Array = []
	EventBus.status_message.connect(func(t: String, _e: bool) -> void: messages.append(t))
	picker._on_item(PeoplePicker.ID_SAID)
	_check(not messages.is_empty() and String(messages[-1]).contains("hello from seat land"), "Show their last message (%s)" % str(messages))
	picker._on_item(PeoplePicker.ID_RESERVE)
	await get_tree().process_frame
	_check(String(AudienceManager.get_reservation(slot).get("name", "")) == "Clicky", "Seat ▸ Reserve reserves their seat")
	var glows: Array = []
	EventBus.chat_highlight_changed.connect(func(d: Dictionary) -> void: glows.append(d))
	picker._on_item(PeoplePicker.ID_GLOW)
	picker._on_item(PeoplePicker.ID_GLOW)
	_check(glows.size() == 2 and not (glows[0] as Dictionary).is_empty() and (glows[1] as Dictionary).is_empty(), "Highlight / glow turns on, then off")

	# Stream Core reads Clicky's line aloud: their seat glows blue for a while (tts_speaking packet)
	AppState.set_setting("audience_tts_glow", true)
	ChatFeed._handle(JSON.stringify({"type": "tts_speaking", "data": {"platform": "twitch", "username": "Clicky", "seconds": 1.2}}))
	await get_tree().process_frame
	var seat_root := (view._seats[slot] as Dictionary)["root"] as Node3D
	_check(seat_root.get_node_or_null("SpeakingGlow") != null, "a chatter read aloud glows")
	await _secs(1.8)
	_check(seat_root.get_node_or_null("SpeakingGlow") == null, "and stops glowing after their line")

	# the big screen, and nothing at all
	var screen: Dictionary = layer._screen
	rig.global_transform = Transform3D.IDENTITY.translated((screen["pos"] as Vector3) + (screen["normal"] as Vector3) * 6.0).looking_at(screen["pos"])
	await get_tree().process_frame
	var sinfo := picker.pick(rig.unproject_position(screen["pos"]))
	_check(String(sinfo.get("kind", "")) == "screen", "a click on the big screen finds the screen (%s)" % str(sinfo))
	rig.global_transform = Transform3D.IDENTITY.translated((screen["pos"] as Vector3) + (screen["normal"] as Vector3) * 6.0) \
		.looking_at((screen["pos"] as Vector3) - (screen["normal"] as Vector3) * 50.0)
	await get_tree().process_frame
	_check(picker.pick(Vector2(5, 5)).is_empty(), "a click on nothing opens no menu")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
