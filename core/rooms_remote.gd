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
##  3. Setup > Stream Rooms pages in Core (work list item 16): on (re)connect it sends
##     {"type": "rooms_settings", "data": {schema, values, defaults}} (schema from the control panel's
##     settings_schema(): every setting the panel has a control for), then {"type": "rooms_values",
##     "data": {key: value}} for the ones that change. Core's changes arrive as {"type": "rooms_set",
##     "data": {key, value}} (ChatFeed -> set_from_core); only keys in the schema are taken.
##
## Nothing here is new behaviour: each command presses the same thing the panel or a hotkey does
## (AppState / EventBus / NetSession), so co-stream rules (who may change the room, the remote)
## still apply.

## Settings that never go to Core's pages: the co-stream password and the host address (they stay on
## this PC, like Core's own secrets) and Core's own address (changing it from Core would cut the link).
const LOCAL_ONLY: PackedStringArray = ["together_password", "together_address", "chat_core_url"]

## Seconds between two state packets at most (a slider being dragged in the game sends a few).
const SEND_GAP: float = 0.3

var _dirty: bool = false
var _wait: float = 0.0
var _views: Array = []            # last camera_views_changed list (CameraRig)
var _sender: Dictionary = {}      # summary of the last capture_status_changed
var _last_sent: String = ""       # JSON of the last packet: an unchanged state isn't sent again
var _podiums: int = 0             # podiums in the room on now (room_presenters_changed)
var _schema_keys: Dictionary = {} # setting keys Core may change (from the last schema sent)
var _changed: Dictionary = {}     # schema keys changed since the last rooms_values packet
var _send_schema: bool = false    # a full rooms_settings packet is due (after a (re)connect)


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
	if (_dirty or _send_schema or not _changed.is_empty()) and _wait <= 0.0:
		_wait = SEND_GAP
		if _send_schema:
			_send_schema = false
			_changed.clear()
			send_settings()
		elif not _changed.is_empty():
			var vals := {}
			for k: String in _changed:
				vals[k] = _json_value(AppState.get_setting(k))
			_changed.clear()
			ChatFeed.send_message({"type": "rooms_values", "data": vals})
		if _dirty:
			_dirty = false
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
		_send_schema = true
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
	if _schema_keys.has(key):
		_changed[key] = true


## The full settings packet for Core's Setup > Stream Rooms pages. False without Core or a panel.
func send_settings() -> bool:
	if not ChatFeed.is_connected_to_core():
		return false
	var data := refresh_schema()
	return not data.is_empty() and ChatFeed.send_message({"type": "rooms_settings", "data": data})


## Reads the panel's settings_schema() and remembers its keys (the ones Core may set). Returns
## {schema, values, defaults}, or {} without a panel. Also used by test_rooms_remote.
func refresh_schema() -> Dictionary:
	var panel := get_tree().get_first_node_in_group("control_panel")
	if panel == null:
		return {}
	var schema: Array = []
	for e: Dictionary in panel.call("settings_schema"):
		if not LOCAL_ONLY.has(String(e["key"])):
			schema.append(e)
	var values := {}
	var defaults := {}
	_schema_keys.clear()
	for e: Dictionary in schema:
		var k := String(e["key"])
		_schema_keys[k] = true
		values[k] = _json_value(AppState.get_setting(k))
		defaults[k] = _json_value(AppState.DEFAULTS.get(k))
	return {"schema": schema, "values": values, "defaults": defaults}


## A setting from Core's pages ("rooms_set"). Only keys the panel shows; the value is turned into
## the setting's own type (a float for 1.0 settings, an int for 60 ones, a Color from "#rrggbb").
## Goes through AppState.set_setting, so co-stream rules still apply. False when refused.
func set_from_core(key: String, value: Variant) -> bool:
	if not _schema_keys.has(key) or not AppState.DEFAULTS.has(key):
		return false
	var def: Variant = AppState.DEFAULTS[key]
	var v: Variant = value
	match typeof(def):
		TYPE_BOOL:
			v = bool(value)
		TYPE_INT:
			v = int(value)
		TYPE_FLOAT:
			v = float(value)
		TYPE_STRING:
			v = str(value)
		TYPE_COLOR:
			if not (value is String and Color.html_is_valid(value)):
				return false
			v = Color.html(value)
		_:
			return false
	AppState.set_setting(key, v)
	DebugLog.note("core", "Setup page set %s" % key)
	return true


## A setting value as JSON can carry it (a Color becomes "#rrggbb").
static func _json_value(v: Variant) -> Variant:
	if v is Color:
		return "#" + (v as Color).to_html(false)
	return v


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
