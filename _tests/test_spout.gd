extends Node
## Spout input (addons/godot-spout): this test sends its own Spout picture (a SubViewport through
## the plugin's SpoutOutput) and checks Stream Rooms finds it, shows it on the big screen (the room
## light follows its colour), on a podium, notices when it stops and picks it up again.
##   <redot console exe> --path . _tests/test_spout.tscn -- C:/temp/sr_tests --mp-profile=test

const SENDER: String = "SR_Test_Spout"
const COLOR := Color(1.0, 0.45, 0.0)       # orange: tells red and blue apart

var _fails: int = 0
var _senders: PackedStringArray = []
var _statuses: PackedStringArray = []
var _center: Color = Color.BLACK
var _pres_tex: Dictionary = {}


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


## A Spout sender of our own: a coloured SubViewport sent by the plugin's SpoutOutput.
func _start_sender() -> Node:
	var holder := Node.new()
	add_child(holder)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(640, 360)
	rect.color = COLOR
	vp.add_child(rect)
	var out := ClassDB.instantiate("SpoutOutput") as Node
	holder.add_child(out)
	out.set("channel_name", SENDER)
	out.set("texture", vp.get_texture())
	return holder


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	EventBus.spout_senders_changed.connect(func(n: PackedStringArray, _a: bool) -> void: _senders = n)
	EventBus.status_message.connect(func(t: String, _e: bool) -> void: _statuses.append(t))
	EventBus.screen_colors_changed.connect(func(_l: Color, c: Color, _r: Color) -> void: _center = c)
	EventBus.presenter_texture_changed.connect(func(n: int, t: Texture2D) -> void: _pres_tex[n] = t)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("curtain_start_closed", false)

	_check(SpoutReceiver.is_available(), "the Spout plugin loaded")
	_check(NetSession.LOCAL_ONLY_SOURCES.has("spout"), "guests don't get the host's Spout podiums (only on the host's PC)")
	if not SpoutReceiver.is_available():
		print("DONE fails=", _fails)
		get_tree().quit(1)
		return
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var feed: Node = main.get_node("ScreenFeed")

	var sender := _start_sender()
	_check(await _wait_for(func() -> bool: return _senders.has(SENDER), 8.0), "the new sender shows up in the list (%s)" % ", ".join(_senders))
	var panel: Node = main.get_node("ControlPanel")
	_check(await _wait_for(func() -> bool: return (panel._spout_menu as OptionButton).item_count >= 2, 4.0),
		"the Source tab's Spout menu lists it")

	EventBus.spout_connect_requested.emit(SENDER)
	_check(AppState.get_source_mode() == "spout", "it's on the big screen")
	var sm: OptionButton = panel._spout_menu
	_check(sm.selected > 0 and String(sm.get_item_metadata(sm.selected)) == SENDER, "the Spout menu shows which sender is on")
	_check(await _wait_for(func() -> bool: return feed.get_texture() != null and feed.get_texture().get_width() == 640, 5.0),
		"the screen gets its picture (640x360)")
	# (the light colour comes out brightened and in linear light, so check it's orange, not blue)
	_check(await _wait_for(func() -> bool:
		return _center.r > 0.5 and _center.r > _center.g * 2.0 and _center.g > _center.b and _center.b < 0.05, 6.0),
		"the room light follows its orange colour, red and blue not swapped (%s)" % _center)
	_check(AppState.is_playback_active(), "counts as playing")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/spout_screen.png")

	# a podium shows the same sender
	AppState.set_setting(AppState.presenter_key(2, "on"), true)
	AppState.set_setting(AppState.presenter_key(2, "spout"), SENDER)
	AppState.set_setting(AppState.presenter_key(2, "source"), "spout")
	_check(await _wait_for(func() -> bool: return _pres_tex.get(2) != null, 6.0), "presenter 2 shows the Spout sender")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/spout_podium.png")

	# the sender stops: the screen notices, then picks it up again when it's back
	sender.queue_free()
	_check(await _wait_for(func() -> bool: return AppState.get_source_mode() == "none", 8.0), "the screen notices the sender stopped")
	_check(_statuses.has("Spout sender %s went away." % SENDER), "and says so")
	_check(await _wait_for(func() -> bool: return _pres_tex.get(2) == null, 6.0), "the podium lets it go too")
	sender = _start_sender()
	_check(await _wait_for(func() -> bool: return AppState.get_source_mode() == "spout", 10.0),
		"it comes back by itself (Show the last sender again by itself)")
	EventBus.spout_stop_requested.emit()
	_check(AppState.get_source_mode() == "none", "Stop clears the screen")
	AppState.set_setting(AppState.presenter_key(2, "source"), "silhouette")
	sender.queue_free()
	await _secs(1.0)
	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
