extends Node
class_name RoomsRemote
## RoomsRemote: Stream Rooms' side of the "Stream Rooms" card on Stream Core's Live page
## (work list item 13; Core's side is core/reactions.py "rooms_state" and admin.js loadRoomsCard).
##
## A child of ChatFeed (made in chat_feed.gd _ready, like CoreLooks). It does two things:
##  1. Sends Core a short summary of what the app is doing as {"type": "rooms_state", "data": {...}}:
##     on every (re)connect and whenever something in it changes, at most every SEND_GAP seconds.
##     Keys (keep in step with Core's ReactionEngine.ROOMS_KEYS and admin.js loadRoomsCard):
##       room, rooms [[id, name]], paused, focus, clean, curtain, playing,
##       views [{id, name, key}] (the visible camera views, from CameraRig's camera_views_changed),
##       screen {mode, text, ok} (the big screen line, like the panel's status strip),
##       sender {connected, sharing, label, fps, audio},
##       volume, ambience (0..1 settings), presenters [{n, on, source}] (only rooms with podiums),
##       costream {role, text, remote, has_remote, guests}.
##  2. Runs the commands Core's card sends back. They arrive as the existing "stage" packet,
##     {action, value}; ChatFeed hands every action except "curtain" to run_command() here.
##
## Nothing here is new behaviour: each command presses the same thing the panel or a hotkey does
## (AppState / EventBus / NetSession), so co-stream rules (who may change the room, the remote)
## still apply.

## Seconds between two state packets at most (a slider being dragged in the game sends a few).
const SEND_GAP: float = 0.3

var _dirty: bool = false
var _wait: float = 0.0
var _views: Array = []            # last camera_views_changed list (CameraRig)
var _sender: Dictionary = {}      # summary of the last capture_status_changed
var _last_sent: String = ""       # JSON of the last packet: an unchanged state isn't sent again
var _podiums: int = 0             # podiums in the room on now (room_presenters_changed)


func _ready() -> void:
	# Anything that changes the summary marks it dirty; _process sends it after SEND_GAP.
	EventBus.chat_status_changed.connect(_on_chat_status)
	EventBus.room_changed.connect(func(_r: String) -> void: _mark())
	EventBus.react_pause_changed.connect(func(_p: bool) -> void: _mark())
	EventBus.focus_view_changed.connect(func(_f: bool) -> void: _mark())
	EventBus.clean_feed_changed.connect(func(_c: bool) -> void: _mark())
	EventBus.curtain_changed.connect(func(_c: bool, _s: String) -> void: _mark())
	EventBus.source_changed.connect(func(_m: String) -> void: _mark())
	EventBus.room_presenters_changed.connect(_on_podiums)
	EventBus.net_state_changed.connect(func(_i: Dictionary) -> void: _mark())
	EventBus.camera_views_changed.connect(_on_views)
	EventBus.capture_status_changed.connect(_on_capture_status)
	EventBus.setting_changed.connect(_on_setting_changed)


func _process(delta: float) -> void:
	_wait = maxf(_wait - delta, 0.0)
	if _dirty and _wait <= 0.0:
		_dirty = false
		_wait = SEND_GAP
		send_state(false)


## Ask for a state packet soon (batched by SEND_GAP).
func _mark() -> void:
	_dirty = true


## On every (re)connect the next packet is sent even if it looks unchanged: Core forgot it.
## The short wait also lets Reactions say "hello" first (Core ignores a socket that hasn't).
func _on_chat_status(info: Dictionary) -> void:
	if bool(info.get("connected", false)):
		_last_sent = ""
		_wait = SEND_GAP
		_mark()


func _on_podiums(count: int) -> void:
	_podiums = count
	_mark()


func _on_views(views: Array) -> void:
	_views = views
	_mark()


## The sender page's status arrives often (fps): only a change in what the card shows counts.
func _on_capture_status(info: Dictionary) -> void:
	var s := {"connected": bool(info.get("connected", false)), "sharing": bool(info.get("capturing", false)),
		"label": String(info.get("label", "")).left(60), "audio": bool(info.get("has_audio", false)),
		"fps": int(info.get("fps", 0)) / 5 * 5}
	if s != _sender:
		_sender = s
		_mark()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "volume" or key == "ambience_volume" or key.begins_with("presenter_"):
		_mark()


## The summary Core's card draws (keys in the file comment). Also used by test_rooms_remote.
func build_state() -> Dictionary:
	var rooms: Array = []
	for id: String in RoomCatalog.get_ids():
		var info := RoomCatalog.get_info(id)
		rooms.append([id, info.display_name if info != null and info.display_name != "" else id])
	var views: Array = []
	for v: Variant in _views:
		if v is Dictionary and not bool((v as Dictionary).get("hidden", false)):
			views.append({"id": String(v.get("id", "")), "name": String(v.get("name", "")), "key": int(v.get("key", 0))})
	var presenters: Array = []
	if _room_has_podiums():
		for n in range(1, AppState.PRESENTER_COUNT + 1):
			presenters.append({"n": n, "on": bool(AppState.get_setting(AppState.presenter_key(n, "on"))),
				"source": String(AppState.get_setting(AppState.presenter_key(n, "source")))})
	return {
		"room": String(AppState.get_setting("room_id")),
		"rooms": rooms,
		"paused": AppState.is_react_paused(),
		"focus": AppState.is_focus_view(),
		"clean": AppState.is_clean_feed(),
		"curtain": "closed" if AppState.is_curtain_closed() else "open",
		"playing": AppState.is_playback_active(),
		"views": views,
		"screen": _screen_line(),
		"sender": _sender.duplicate(),
		"volume": snappedf(float(AppState.get_setting("volume")), 0.01),
		"ambience": snappedf(float(AppState.get_setting("ambience_volume")), 0.01),
		"presenters": presenters,
		"costream": _costream_line(),
	}


## Sends the state (force = even when it equals the last one). False when Core isn't connected.
func send_state(force: bool) -> bool:
	if not ChatFeed.is_connected_to_core():
		return false
	var st := build_state()
	var text := JSON.stringify(st)
	if text == _last_sent and not force:
		return true
	_last_sent = text
	return ChatFeed.send_message({"type": "rooms_state", "data": st})


## Big screen, the same wording as the panel's status strip (control_panel.gd _refresh_strip).
func _screen_line() -> Dictionary:
	var mode := AppState.get_source_mode()
	match mode:
		"none":
			return {"mode": mode, "text": "Big screen empty", "ok": false}
		"capture":
			var ok := bool(_sender.get("connected", false)) and bool(_sender.get("sharing", false))
			return {"mode": mode, "text": "Sharing a tab" if ok else "Tab sharing stopped", "ok": ok}
		"file":
			return {"mode": mode, "text": "Playing a video", "ok": true}
		"ndi":
			return {"mode": mode, "text": "NDI source", "ok": true}
		"spout":
			return {"mode": mode, "text": "Spout source", "ok": true}
	return {"mode": mode, "text": mode, "ok": true}


## Co-stream line: off / hosting / joined, plus who holds the big screen remote.
func _costream_line() -> Dictionary:
	var info := NetSession.get_info()
	var role := String(info.get("role", "off"))
	var guests := maxi((info.get("peers", []) as Array).size() - 1, 0)
	var text := "Off"
	if role == "host":
		text = "Hosting (%d guest%s)" % [guests, "" if guests == 1 else "s"]
	elif role == "guest":
		text = "Syncing..." if bool(info.get("syncing", false)) else "Joined %s" % String(info.get("host_name", ""))
	return {"role": role, "text": text, "remote": String(info.get("remote", "")),
		"has_remote": bool(info.get("has_remote", true)), "guests": guests}


## True when the room on now has presenter podiums (RoomHost reports the count).
func _room_has_podiums() -> bool:
	return _podiums > 0


## One command from Core's card ("stage" packet, every action but "curtain").
## value is a string for toggles ("on" / "off" / "toggle") and ids, a number for volumes.
## Returns false for an action this version doesn't know (Core's card is newer than the app).
func run_command(action: String, value: Variant) -> bool:
	var v := str(value)
	match action:
		"pause":
			AppState.set_react_paused(_want(v, AppState.is_react_paused()))
		"focus":
			if _want(v, AppState.is_focus_view()) != AppState.is_focus_view():
				AppState.toggle_focus_view()
		"clean":
			if _want(v, AppState.is_clean_feed()) != AppState.is_clean_feed():
				AppState.toggle_clean_feed()
		"room":
			if v != String(AppState.get_setting("room_id")):
				AppState.request_room(v)
		"view":
			EventBus.camera_view_action.emit("go", v, "")
		"playpause":
			EventBus.file_pause_toggle_requested.emit()
		"volume", "ambience":
			var key := "volume" if action == "volume" else "ambience_volume"
			AppState.set_setting(key, clampf(float(value), 0.0, 1.0))
		"presenter":
			# "<n>:on" / "<n>:off"
			var parts := v.split(":")
			var n := int(parts[0]) if parts.size() == 2 else 0
			if n < 1 or n > AppState.PRESENTER_COUNT:
				return false
			AppState.set_setting(AppState.presenter_key(n, "on"), parts[1] == "on")
		"remote":
			# "take" = host takes the big screen remote back; "ask" = a guest asks for it
			if v == "take":
				NetSession.pass_remote(1)
			elif v == "ask":
				NetSession.ask_remote(true)
		"refresh":
			pass
		_:
			return false
	DebugLog.note("core", "Live card: %s %s" % [action, v])
	_mark()
	return true


## "on" -> true, "off" -> false, anything else ("toggle") flips the current value.
static func _want(v: String, now: bool) -> bool:
	if v == "on":
		return true
	if v == "off":
		return false
	return not now
