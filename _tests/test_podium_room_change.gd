extends Node
## Podiums keep their settings and their live picture when the room changes (Sen, 2026-11-05:
## "when the room changes in multiplayer stream rooms, the podiums lose their settings").
## A sender-page feed for podium 2 keeps running across the change (as someone's avatar does in
## Together); the new room's podium must show that picture straight away, not "waiting for ...",
## and keep its name tag, key and zoom settings. ScreenFeed._on_room_presenters hands the
## already-running pictures to the new Presenter nodes.
##   <redot console exe> --path . _tests/test_podium_room_change.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _feed: Node            # ScreenFeed in main.tscn
var _pumping: bool = true  # keep sending frames, like the sender page does


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


## Podium 2 of the current room, or null while a room is loading.
func _presenter(main: Node) -> Presenter:
	var room: Node = main.get_node("RoomHost").get_current_room()
	if room == null:
		return null
	var stage: Node = room.find_child("Presenters", true, false)
	return stage.get_presenter(2) if stage else null


## Sends one 64x36 frame for podium 2 (sender slot 1) every 0.2 s, as the sender page would.
func _pump() -> void:
	var img := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.7, 0.3))
	while _pumping:
		_feed._on_presenter_frame(1, img)
		await _secs(0.2)


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("curtain_start_closed", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	_feed = main.get_node("ScreenFeed")
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	_check(await _wait_for(func() -> bool: return _presenter(main) != null, 10.0), "podium 2 exists in the lecture hall (panel)")
	AppState.set_setting(AppState.presenter_key(2, "on"), true)
	AppState.set_setting(AppState.presenter_key(2, "source"), "web")
	AppState.set_setting(AppState.presenter_key(2, "name"), "Sen")
	AppState.set_setting(AppState.presenter_key(2, "zoom"), 1.4)
	_pump()
	var before := _presenter(main)
	_check(await _wait_for(func() -> bool: return before._feed != null, 3.0), "podium 2 shows the feed in the first room")
	_check(not before._label.visible, "no 'waiting' label in the first room")

	var before_id := before.get_instance_id()   # (the old podium is freed with the old room)
	AppState.request_room("throne_hall")
	_check(await _wait_for(func() -> bool: return _presenter(main) != null and _presenter(main).get_instance_id() != before_id, 60.0),
		"the new room built its own podium 2")
	var after := _presenter(main)
	await _secs(1.0)
	_check(after._feed != null, "podium 2 shows the running feed after the room change")
	_check(not after._label.visible, "no 'waiting for ...' label after the room change")
	_check(int(after._mat.get_shader_parameter("mode")) == 2, "the picture is in live-feed mode (mode %s)" % str(after._mat.get_shader_parameter("mode")))
	_check(after._tag.text == "Sen" and after._tag.visible, "the name tag is kept (%s)" % after._tag.text)
	_check(absf(float(after._mat.get_shader_parameter("zoom")) - 1.4) < 0.001, "the zoom is kept")
	_pumping = false

	print("DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
