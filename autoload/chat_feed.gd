extends Node
## ChatFeed: live chat from Fridge Stream Core (FlaVR Leftovers workshop).
## Connects to Core's overlay WebSocket (ws://127.0.0.1:3850/ws, the same feed the
## chat overlay uses) and turns its "chat" / "chat_history" packets into
## EventBus.chat_message_received. Reconnects on its own while Core is closed.
## It also carries the chat-reactions link: Core's "reaction" packets go out as
## EventBus.reaction_received, and Reactions talks back through send_message().

const PING_INTERVAL: float = 20.0
const BACKOFF_MIN: float = 2.0
const BACKOFF_MAX: float = 20.0

const TEST_NAMES: PackedStringArray = ["PixelPanda", "moss_wizard", "Sgt_Crumpet", "neonNomad", "LadyLumen",
	"tater_tot_42", "QuietFox", "BrickTamland", "Zephyrine", "captain_kettle", "OrbitOtter", "MangoTango"]
const TEST_LINES: PackedStringArray = ["hello from the back row!", "LUL", "wait, rewind that", "this part is so good",
	"is that a real place?", "!points", "first time here, love the room", "the chandelier is fancy",
	"volume ok for everyone?", "no way", "that was amazing, run it back", "hi chat", "o7",
	"I've been waiting all week for this one and it did not disappoint at all, the ending got me"]

## Test lines with Twitch emotes (id, start, end) so "Test chat" shows emotes too.
const TEST_EMOTE_LINES: Array = [
	["Kappa that was smooth", [["25", 0, 4]]],
	["LUL LUL LUL", [["425618", 0, 2], ["425618", 4, 6], ["425618", 8, 10]]],
	["PogChamp", [["305954156", 0, 7]]],
]

var _ws: WebSocketPeer
var _retry_in: float = 0.0
var _backoff: float = BACKOFF_MIN
var _ping_in: float = PING_INTERVAL
var _connected: bool = false
var _error: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _boards: Dictionary = {}      # board id -> latest board from Stream Core (chat games)


func _ready() -> void:
	_rng.randomize()
	EventBus.setting_changed.connect(_on_setting_changed)


func _process(delta: float) -> void:
	if not bool(AppState.get_setting("chat_enabled")):
		return
	if _ws == null:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_open()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_backoff = BACKOFF_MIN
			_set_status(true, "")
		_ping_in -= delta
		if _ping_in <= 0.0:
			_ping_in = PING_INTERVAL
			_ws.send_text("ping")
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			if _ws.was_string_packet():
				_handle(pkt.get_string_from_utf8())
	elif st == WebSocketPeer.STATE_CLOSED:
		var why := "Stream Core not running" if not _connected else "Stream Core closed the connection"
		_ws = null
		_retry_in = _backoff
		_backoff = minf(_backoff * 1.5, BACKOFF_MAX)
		_set_status(false, why)


# ── Public API ───────────────────────────────────────────────
func is_connected_to_core() -> bool:
	return _connected


## Stream Core's chat games boards that are up right now (for views that open later).
func get_boards() -> Array:
	return _boards.values()


func get_status() -> Dictionary:
	return {"connected": _connected, "url": String(AppState.get_setting("chat_core_url")), "error": _error}


## Send a JSON message to Stream Core (hello, room_state, reaction_result ...).
## Returns false when not connected.
func send_message(msg: Dictionary) -> bool:
	if _ws == null or not _connected or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _ws.send_text(JSON.stringify(msg)) == OK


## Try to connect right away (e.g. after starting Stream Core).
func reconnect() -> void:
	_close()
	_backoff = BACKOFF_MIN
	_retry_in = 0.0


## A few fake chatters and messages, to try the audience without going live.
func send_test_chat(count: int = 6) -> void:
	for i in count:
		var who := TEST_NAMES[_rng.randi_range(0, TEST_NAMES.size() - 1)]
		var line := TEST_LINES[_rng.randi_range(0, TEST_LINES.size() - 1)]
		var emotes: Array = []
		if _rng.randf() < 0.35:
			var pick: Array = TEST_EMOTE_LINES[_rng.randi_range(0, TEST_EMOTE_LINES.size() - 1)]
			line = pick[0]
			for r: Array in pick[1]:
				emotes.append({"provider": "twitch", "id": r[0], "start": r[1], "end": r[2],
					"url": "", "static_url": "https://static-cdn.jtvnw.net/emoticons/v2/%s/static/dark/2.0" % r[0]})
		var delay := 0.35 * i + _rng.randf() * 0.3
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			EventBus.chat_message_received.emit({
				# each test name is on one platform, so seating / chat windows by platform can be tried out
				"platform": ["kick", "twitch", "youtube"][absi(hash(who)) % 3], "user_id": who.to_lower(), "name": who, "color": "",
				"text": line, "emotes": emotes, "timestamp": Time.get_unix_time_from_system(),
				"history": false, "system": false, "is_mod": false, "is_vip": false, "is_subscriber": false,
			}))


# ── Private ──────────────────────────────────────────────────
func _open() -> void:
	var url := String(AppState.get_setting("chat_core_url")).strip_edges()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 4 * 1024 * 1024    # Core also sends big stats snapshots
	_ping_in = PING_INTERVAL
	var err := _ws.connect_to_url(url)
	if err != OK:
		_ws = null
		_retry_in = BACKOFF_MAX
		_set_status(false, "Bad Stream Core address: %s" % url)


func _close() -> void:
	if _ws:
		_ws.close()
	_ws = null
	for id: String in _boards.keys():
		EventBus.board_cleared.emit(id)
	_boards.clear()
	if _connected:
		_set_status(false, "")


func _set_status(on: bool, error: String) -> void:
	var changed := on != _connected or error != _error
	_connected = on
	_error = error
	if changed:
		EventBus.chat_status_changed.emit(get_status())


func _handle(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	match String((msg as Dictionary).get("type", "")):
		"chat":
			_emit((msg as Dictionary).get("data", {}), false)
		"chat_history":
			for item: Variant in (msg as Dictionary).get("data", []):
				_emit(item, true)
		"reply":
			_emit_reply((msg as Dictionary).get("data"), false)
		"reply_history":
			var items: Variant = (msg as Dictionary).get("data")
			if items is Array:
				for item: Variant in items:
					_emit_reply(item, true)
		"reaction":
			var r: Variant = (msg as Dictionary).get("data")
			if r is Dictionary:
				EventBus.reaction_received.emit(r as Dictionary)
		"board":
			var b: Variant = (msg as Dictionary).get("data")
			if b is Dictionary and String((b as Dictionary).get("id", "")) != "":
				_boards[String(b["id"])] = b
				EventBus.board_changed.emit(b as Dictionary)
		"board_clear":
			var c: Variant = (msg as Dictionary).get("data")
			if c is Dictionary:
				_boards.erase(String((c as Dictionary).get("id", "")))
				EventBus.board_cleared.emit(String((c as Dictionary).get("id", "")))
		"board_history":
			for id: String in _boards.keys():
				EventBus.board_cleared.emit(id)
			_boards.clear()
			var items: Variant = (msg as Dictionary).get("data")
			if items is Array:
				for b2: Variant in items:
					if b2 is Dictionary and String((b2 as Dictionary).get("id", "")) != "":
						_boards[String(b2["id"])] = b2
						EventBus.board_changed.emit(b2 as Dictionary)
		"stage":
			# Stream Core's !curtain / admin button: {action: "curtain", value: open|close|reveal|toggle}
			var st: Variant = (msg as Dictionary).get("data")
			if st is Dictionary and String((st as Dictionary).get("action", "")) == "curtain":
				match String((st as Dictionary).get("value", "")):
					"open":
						AppState.set_curtain(false)
					"close":
						AppState.set_curtain(true)
					"reveal":
						AppState.reveal_curtain()
					"toggle":
						AppState.toggle_curtain()
		"user_update":
			var d: Variant = (msg as Dictionary).get("data")
			if d is Dictionary and String((d as Dictionary).get("profile_image_url", "")) != "":
				EventBus.chat_user_updated.emit({
					"platform": String(d.get("platform", "")),
					"user_id": String(d.get("id", "")),
					"avatar": String(d.get("profile_image_url", "")),
				})


func _emit(data: Variant, history: bool) -> void:
	if not data is Dictionary:
		return
	var m := _normalize(data as Dictionary, history)
	if not m.is_empty():
		EventBus.chat_message_received.emit(m)


## Stream Core's reply payload -> {message, platform, reply_to_user, source, timestamp, history}.
func _emit_reply(data: Variant, history: bool) -> void:
	if not data is Dictionary:
		return
	var d := data as Dictionary
	var text := String(d.get("message", "")).strip_edges()
	if text == "":
		return
	EventBus.core_reply_received.emit({
		"message": text,
		"platform": String(d.get("platform", "")),
		"reply_to_user": String(d.get("reply_to_user", "") if d.get("reply_to_user") != null else ""),
		"source": String(d.get("source", "core") if d.get("source") != null else "core"),
		"timestamp": float(d.get("timestamp", Time.get_unix_time_from_system())),
		"history": history,
	})


## Stream Core's chat payload -> the keys the rest of the app uses.
func _normalize(d: Dictionary, history: bool) -> Dictionary:
	var user: Dictionary = d.get("user", {}) if d.get("user") is Dictionary else {}
	var who := String(user.get("display_name", "")).strip_edges()
	if who == "":
		who = String(user.get("username", "")).strip_edges()
	var text := String(d.get("message", "")).strip_edges()
	if who == "" or text == "":
		return {}
	var badges: Array = user.get("badges", []) if user.get("badges") is Array else []
	var color: Variant = user.get("color")
	var avatar: Variant = user.get("profile_image_url")
	var emotes: Array = []
	if d.get("emotes") is Array:
		for e: Variant in d["emotes"]:
			if e is Dictionary and (e as Dictionary).has("start") and (e as Dictionary).has("end"):
				emotes.append(e)
	return {
		"platform": String(d.get("platform", "")),
		"user_id": String(user.get("id", "")) if user.get("id") != null else who.to_lower(),
		"name": who,
		"username": String(user.get("username", who)).strip_edges(),
		"color": String(color) if color is String else "",
		"text": text,
		"emotes": emotes,     # Twitch ranges (native + BTTV/FFZ/7TV) from Stream Core
		"avatar": String(avatar) if avatar is String else "",   # Kick / YouTube profile picture
		"timestamp": float(d.get("timestamp", Time.get_unix_time_from_system())),
		"history": history,
		"system": badges.has("system"),     # Core's own bot replies
		"is_mod": bool(user.get("is_mod", false)),
		"is_vip": bool(user.get("is_vip", false)),
		"is_subscriber": bool(user.get("is_subscriber", false)),
		"title": String(user.get("title", "")) if user.get("title") is String else "",   # regular's title (chat games)
	}


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "chat_core_url":
		reconnect()
	elif key == "chat_enabled":
		if bool(AppState.get_setting("chat_enabled")):
			reconnect()
		else:
			_close()
			_set_status(false, "Off")
