extends Node
## Reserved seats (Seating tab > Reserved seats, AudienceManager "Reserved seats"): a regular gets
## their own seat, nobody else takes it while they're away (hold on), they go straight back to it
## when they chat, and with hold off a stranger sitting there moves to another seat for them.
## Also checks the reservation is saved per room in "audience_reserved" and drawn on the chart.
##   <redot console exe> --path . _tests/test_reserved_seats.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## One chat line from `who` on Twitch, as ChatFeed hands it on.
func _say(who: String) -> void:
	EventBus.chat_message_received.emit({"platform": "twitch", "user_id": who.to_lower(), "name": who, "color": "",
		"text": "hello", "emotes": [], "timestamp": Time.get_unix_time_from_system(), "tint": "",
		"history": false, "system": false, "is_mod": false, "is_vip": false, "is_subscriber": false})


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("seating_by_platform", false)
	AppState.set_setting("audience_seating", "random")
	AppState.set_setting("audience_reserved", "")
	AppState.set_setting("audience_reserved_hold", true)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	_check(AudienceManager.get_capacity() > 10, "the lecture hall has seats (%d)" % AudienceManager.get_capacity())

	# 1. reserve the seat a regular sits in
	_say("Regular")
	await _secs(0.3)
	var seat := AudienceManager.find_slot_by_name("Regular")
	_check(seat >= 0, "Regular sits down")
	_check(AudienceManager.reserve_seat(seat) == "Regular", "their seat is reserved for them")
	await _secs(0.2)
	_check(String(AudienceManager.get_reservation(seat).get("name", "")) == "Regular", "the reservation is there")
	_check(String(AppState.get_setting("audience_reserved")).contains("lecture_hall_panel")
		and String(AppState.get_setting("audience_reserved")).contains("Regular"), "it's saved under this room")
	var chart := AudienceManager.get_chart()
	_check((chart["reserved"] as PackedByteArray)[seat] == 2, "the chart shows it reserved with its owner in it")

	# 2. hold on: while Regular is away nobody else sits there
	AudienceManager._unseat(seat, true)        # (as if they went idle and left)
	for i in 40:
		_say("Passer%d" % i)
	await _secs(0.5)
	_check(AudienceManager.get_seat_member(seat).is_empty(), "nobody else took the reserved seat")
	_check((AudienceManager.get_chart()["reserved"] as PackedByteArray)[seat] == 1, "the chart shows it kept free")
	_say("Regular")
	await _secs(0.3)
	_check(AudienceManager.find_slot_by_name("Regular") == seat, "Regular goes straight back to their seat")

	# 3. hold off: a stranger sits there until Regular chats, then moves to another seat
	AppState.set_setting("audience_reserved_hold", false)
	AudienceManager._unseat(seat, true)
	_say("Squatter")
	await _secs(0.3)
	var sq := AudienceManager.find_slot_by_name("Squatter")
	if sq != seat and sq >= 0:
		AudienceManager._move(sq, seat)
	_check(AudienceManager.find_slot_by_name("Squatter") == seat, "with hold off someone else may sit there")
	_say("Regular")
	await _secs(0.3)
	_check(AudienceManager.find_slot_by_name("Regular") == seat, "Regular gets their seat back")
	var moved := AudienceManager.find_slot_by_name("Squatter")
	_check(moved >= 0 and moved != seat, "the stranger moved to another seat (%d)" % moved)

	# 4. the panel lists it; Free gives it up
	var panel: Node = main.find_child("ControlPanel", true, false)
	var listed := false
	if panel:
		for l in panel.find_children("*", "Label", true, false):
			if (l as Label).text.begins_with("★ Regular"):
				listed = true
	_check(listed, "the Seating tab lists Regular's seat")
	_check(AudienceManager.reserve_seat_of("Squatter") == "Squatter", "reserve a seat by name")
	_check(AudienceManager.get_reservations().size() == 2, "two reserved seats now")
	_check(AudienceManager.unreserve_seat(seat) == "Regular", "Free gives up Regular's reservation")
	await _secs(0.2)
	_check(AudienceManager.get_reservations().size() == 1, "one left")
	_check(not String(AppState.get_setting("audience_reserved")).contains("Regular"), "the setting forgot Regular")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
