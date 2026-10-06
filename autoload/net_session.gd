extends Node
## NetSession: streaming together (docs/MULTIPLAYER.md). One host and up to three guests, each
## running their own copy of Stream Rooms and drawing the room from their own camera. Only
## small state messages travel between the PCs, never video.
##
## The host is in charge: guests ask, the host decides and tells everyone. AppState.net_gate
## stops a guest changing shared state (room, curtain, the shared settings) on its own; a
## co-host's change goes to the host as a request, and comes back once the host applied it.
##
## Security (this is the first server here that isn't bound to 127.0.0.1):
##   - a password challenge during Redot's authentication step, so nobody can call anything
##     before it passes (the password itself never travels, only a hash of it plus a random nonce),
##   - a version check in the same step,
##   - shared-state calls are accepted only from the host (peer 1), requests only from co-hosts,
##     and only whitelisted setting keys with the right type,
##   - guests don't relay to each other directly (the host forwards what they need),
##   - web addresses must be http(s); a guest never opens a file path sent over the network.

const PROTOCOL: int = 1
const MAX_GUESTS: int = 3
const AUTH_TIMEOUT: float = 8.0
const CAMERA_SEND_GAP: float = 0.1      # camera updates at most 10 times a second
const MIN_PASSWORD: int = 4

## Settings everyone in the session shares (the presenter ones are added in _ready()).
const SHARED_BASE: Array[String] = ["house_lights", "curtain_enabled", "curtain_sign", "curtain_color",
	"curtain_speed", "curtain_show_lights"]
## Presenter fields that are shared. camera / ndi pick devices on one PC, and the chat link ties a
## podium to one streamer's own audience, so those stay local.
const SHARED_PRESENTER_FIELDS: Array[String] = ["on", "source", "url", "self_lit", "light", "key",
	"key_color", "key_similarity", "key_smoothness", "key_spill", "zoom", "offset_y"]
## Presenter sources that only exist on the host's PC (its camera, browser tab, NDI, Spout): guests show
## a silhouette instead. A "web" page (e.g. a VDO.Ninja link) works for everyone.
const LOCAL_ONLY_SOURCES: Array[String] = ["camera", "tab", "ndi", "spout"]
const CURTAIN_STYLES: Array[String] = ["normal", "instant", "reveal"]

var _shared: Dictionary = {}            # setting key -> true
var _role: String = "off"               # "off" | "host" | "guest"
var _status: String = ""
var _error: bool = false
var _address: String = ""               # host: what guests type in; guest: where it connected
var _peers: Dictionary = {}             # peer id -> {"name": String, "cohost": bool}; the host is 1
var _nonces: Dictionary = {}            # host: peer id -> challenge bytes
var _hello_names: Dictionary = {}       # host: peer id -> name from its hello (until it's connected)
var _cams: Dictionary = {}              # host: peer id -> last camera Transform3D
var _refused: String = ""               # guest: why the host said no
var _applying: bool = false             # guest: applying the host's state (the gate lets it through)
var _medium_dismissed: bool = false
var _cam_wait: float = 0.0
var _last_cam: Transform3D


func _ready() -> void:
	for k in SHARED_BASE:
		_shared[k] = true
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		for f in SHARED_PRESENTER_FIELDS:
			_shared[AppState.presenter_key(n, f)] = true
	var sm := _sm()
	sm.auth_callback = _on_auth
	sm.auth_timeout = AUTH_TIMEOUT
	sm.server_relay = false
	sm.peer_authenticating.connect(_on_peer_authenticating)
	sm.peer_authentication_failed.connect(_on_auth_failed)
	sm.peer_connected.connect(_on_peer_connected)
	sm.peer_disconnected.connect(_on_peer_disconnected)
	sm.connected_to_server.connect(_on_connected)
	sm.connection_failed.connect(_on_connection_failed)
	sm.server_disconnected.connect(_on_server_disconnected)
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.room_requested.connect(_on_room_requested)
	EventBus.curtain_changed.connect(_on_curtain_changed)
	EventBus.reaction_play.connect(_on_reaction_play)
	set_process(false)


func _exit_tree() -> void:
	if _role != "off":
		_close("")


func _process(delta: float) -> void:
	_cam_wait -= delta
	if _cam_wait > 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var x := cam.global_transform
	if x.is_equal_approx(_last_cam):
		return             # only while the camera moves
	_last_cam = x
	_cam_wait = CAMERA_SEND_GAP
	if _role == "host":
		_to_guests("_net_camera", [1, x])
	elif _role == "guest":
		_net_guest_camera.rpc_id(1, x)


# ── Public API ───────────────────────────────────────────────
## {role, status, error, address, cohost, suggest_medium, peers: [{id, name, cohost, me}]}
func get_info() -> Dictionary:
	var me := multiplayer.get_unique_id() if _role != "off" else 0
	var peers: Array = []
	for id: int in _peers:
		peers.append({"id": id, "name": String(_peers[id]["name"]), "cohost": bool(_peers[id]["cohost"]), "me": id == me})
	var q := String(AppState.get_setting("graphics_quality"))
	return {"role": _role, "status": _status, "error": _error, "address": _address, "cohost": _is_cohost(),
		"suggest_medium": _role == "guest" and _peers.size() > 0 and not _medium_dismissed and (q == "high" or q == "custom"),
		"peers": peers}


func get_role() -> String:
	return _role


func is_shared(key: String) -> bool:
	return _shared.has(key)


## True when this PC may not change it: a guest who isn't a co-host.
## what: a setting key, "room" or "curtain".
func is_locked(what: String) -> bool:
	return _role == "guest" and not _is_cohost() and (what == "room" or what == "curtain" or _shared.has(what))


## The name others see: the Together tab's name, else the profile name, else Host / Guest.
func display_name() -> String:
	var n := _clean_name(String(AppState.get_setting("together_name")))
	if n == "":
		n = _clean_name(AppState.get_profile())
	if n == "":
		n = "Host" if _role == "host" else "Guest"
	return n


func host() -> void:
	if _role != "off":
		return
	var pw := String(AppState.get_setting("together_password")).strip_edges()
	if pw.length() < MIN_PASSWORD:
		_set_status("Pick a session password first (at least %d characters)." % MIN_PASSWORD, true)
		return
	var port := int(AppState.get_setting("together_port"))
	var ts := _tailscale_ip()
	var bind := String(AppState.get_setting("together_bind"))
	var ip := "127.0.0.1"
	if bind == "all":
		ip = "*"
	elif bind == "auto" and ts != "":
		ip = ts
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(ip)
	if peer.create_server(port, MAX_GUESTS) != OK:
		_set_status("Couldn't start hosting on port %d. Is another copy already hosting on it?" % port, true)
		return
	multiplayer.multiplayer_peer = peer
	_role = "host"
	_peers = {1: {"name": display_name(), "cohost": true}}
	_cams.clear()
	if ip == "*":
		_address = "%s:%d" % [ts if ts != "" else _lan_ip(), port]
	else:
		_address = "%s:%d" % [ip, port]
	_last_cam = Transform3D()
	set_process(true)
	var where := "Guests join with %s." % _address
	if ip == "127.0.0.1":
		where += " Only copies on this PC can join" + (" (Tailscale isn't running)." if bind == "auto" else ".")
	_set_status("Hosting. " + where)


func join() -> void:
	if _role != "off":
		return
	var pw := String(AppState.get_setting("together_password")).strip_edges()
	if pw == "":
		_set_status("Type the session password first.", true)
		return
	var addr := String(AppState.get_setting("together_address")).strip_edges()
	var port := int(AppState.get_setting("together_port"))
	if addr.contains(":"):
		port = addr.get_slice(":", 1).to_int()
		addr = addr.get_slice(":", 0)
	if addr == "" or port <= 0 or port > 65535:
		_set_status("Type the host's address first (for example 100.101.102.103).", true)
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(addr, port) != OK:
		_set_status("Couldn't connect to %s:%d." % [addr, port], true)
		return
	multiplayer.multiplayer_peer = peer
	_role = "guest"
	_peers.clear()
	_refused = ""
	_address = "%s:%d" % [addr, port]
	_set_status("Connecting to %s..." % _address)


func leave() -> void:
	if _role == "off":
		return
	_close("Left the session." if _role == "guest" else "Stopped hosting.")


## Host: let a guest change the room, curtain and other shared things too.
func set_cohost(peer_id: int, on: bool) -> void:
	if _role != "host" or peer_id == 1 or not _peers.has(peer_id):
		return
	_peers[peer_id]["cohost"] = on
	_send_roster()


## Host: send a guest away.
func remove_peer(peer_id: int) -> void:
	if _role == "host" and peer_id != 1 and _peers.has(peer_id):
		_sm().disconnect_peer(peer_id)


## Guest: hide the "use Medium graphics" suggestion.
func dismiss_medium() -> void:
	_medium_dismissed = true
	_emit_state()


## "" when this hello may join, else the reason to refuse it (the guest sees it).
static func check_hello(d: Dictionary, nonce: PackedByteArray, password: String, version: String) -> String:
	if int(d.get("protocol", -1)) != PROTOCOL or String(d.get("version", "")) != version:
		return "Different Stream Rooms versions: the host has %s, you have %s. Use the same version to stream together." % [
			version, String(d.get("version", "?"))]
	var p: Variant = d.get("proof")
	if not p is PackedByteArray or (p as PackedByteArray) != proof(nonce, password):
		return "Wrong session password."
	return ""


## The answer to a password challenge: SHA-256 of the nonce plus the password.
static func proof(nonce: PackedByteArray, password: String) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(nonce)
	ctx.update(password.strip_edges().to_utf8_buffer())
	return ctx.finish()


## Only http(s) addresses travel to guests (an empty one is fine).
static func is_web_address(url: String) -> bool:
	if url == "":
		return true
	if not (url.begins_with("https://") or url.begins_with("http://")):
		return false
	for c in url:
		if c.unicode_at(0) <= 32:
			return false
	return true


# ── Connection ───────────────────────────────────────────────
func _on_peer_authenticating(id: int) -> void:
	if _role != "host":
		return
	var nonce := Crypto.new().generate_random_bytes(16)
	_nonces[id] = nonce
	_sm().send_auth(id, var_to_bytes({"t": "challenge", "nonce": nonce, "protocol": PROTOCOL, "version": _version()}))


func _on_auth(id: int, data: PackedByteArray) -> void:
	var d: Variant = bytes_to_var(data)          # never decodes objects
	if not d is Dictionary:
		return
	if _role == "host":
		_on_hello(id, d)
	elif _role == "guest" and id == 1:
		_on_host_auth(d)


func _on_hello(id: int, d: Dictionary) -> void:
	if String(d.get("t", "")) != "hello" or not _nonces.has(id):
		return
	var nonce: PackedByteArray = _nonces[id]
	_nonces.erase(id)
	var why := check_hello(d, nonce, String(AppState.get_setting("together_password")), _version())
	if why != "":
		_sm().send_auth(id, var_to_bytes({"t": "refused", "reason": why}))
		EventBus.status_message.emit("Refused someone joining: " + why, true)
		# a moment for the reason to arrive before the connection closes
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _role == "host":
				_sm().disconnect_peer(id))
		return
	var n := _clean_name(String(d.get("name", "")))
	_hello_names[id] = n if n != "" else "Guest %d" % (_peers.size())
	_sm().complete_auth(id)


func _on_host_auth(d: Dictionary) -> void:
	match String(d.get("t", "")):
		"challenge":
			if int(d.get("protocol", -1)) != PROTOCOL or String(d.get("version", "")) != _version():
				_refused = "Different Stream Rooms versions: the host has %s, you have %s. Use the same version to stream together." % [
					String(d.get("version", "?")), _version()]
				_close.call_deferred(_refused, true)
				return
			var nonce: Variant = d.get("nonce")
			if not nonce is PackedByteArray:
				return
			_sm().send_auth(1, var_to_bytes({"t": "hello", "name": display_name(), "protocol": PROTOCOL,
				"version": _version(), "proof": proof(nonce, String(AppState.get_setting("together_password")))}))
			_sm().complete_auth(1)
		"refused":
			_refused = String(d.get("reason", "The host said no."))


func _on_auth_failed(id: int) -> void:
	_nonces.erase(id)
	if _role == "guest" and id == 1:
		# deferred: closing the connection inside Redot's own network callback crashes it
		_close.call_deferred(_refused if _refused != "" else "The host didn't let this copy in. Check the password.", true)


func _on_peer_connected(id: int) -> void:
	if _role != "host":
		return
	_peers[id] = {"name": String(_hello_names.get(id, "Guest")), "cohost": false}
	_hello_names.erase(id)
	_net_snapshot.rpc_id(id, _snapshot())
	_send_roster()
	_last_cam = Transform3D()         # send the host's camera again, for the newcomer
	for other: int in _cams:
		_net_camera.rpc_id(id, other, _cams[other])
	_set_status("%s joined. Guests join with %s." % [_peers[id]["name"], _address])


func _on_peer_disconnected(id: int) -> void:
	if _role != "host" or not _peers.has(id):
		return
	var n := String(_peers[id]["name"])
	_peers.erase(id)
	_cams.erase(id)
	EventBus.net_peer_left.emit(id)
	_to_guests("_net_left", [id])
	_send_roster()
	_set_status("%s left." % n)


func _on_connected() -> void:
	if _role != "guest":
		return
	AppState.net_gate = _gate
	_last_cam = Transform3D()
	set_process(true)
	_set_status("Joined the session at %s. The host controls the room, curtain and presenters." % _address)


func _on_connection_failed() -> void:
	if _role == "guest":
		_close.call_deferred("Couldn't reach a host at %s. Check the address, and that the host is hosting." % _address, true)


func _on_server_disconnected() -> void:
	if _role == "guest":
		_close.call_deferred(_refused if _refused != "" else "The session ended (the host stopped, or the connection dropped).", _refused != "")


func _close(message: String, is_error: bool = false) -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var me := 1 if _role == "host" else 0
	for id: int in _peers:
		if id != me:
			EventBus.net_peer_left.emit(id)
	_role = "off"
	_peers.clear()
	_nonces.clear()
	_hello_names.clear()
	_cams.clear()
	_address = ""
	AppState.net_gate = Callable()
	set_process(false)
	if message != "":
		_set_status(message, is_error)
	else:
		_status = ""
		_emit_state()


# ── Shared state ─────────────────────────────────────────────
## Guest: asked by AppState before shared state changes here.
func _gate(what: String, value: Variant) -> bool:
	if _role != "guest" or _applying:
		return true
	if what != "room" and what != "curtain" and not _shared.has(what):
		return true
	if _is_cohost():
		_net_request.rpc_id(1, what, value)
	else:
		EventBus.status_message.emit("The host controls this while you're a guest (Together tab).", false)
	return false


func _on_setting_changed(key: String, value: Variant) -> void:
	if _role == "host" and _shared.has(key):
		_to_guests("_net_setting", [key, value])
	elif key == "graphics_quality" and _role == "guest":
		_emit_state()


func _on_room_requested(room_id: String) -> void:
	if _role == "host":
		_to_guests("_net_room", [room_id])


func _on_curtain_changed(closed: bool, style: String) -> void:
	if _role == "host":
		_to_guests("_net_curtain", [closed, style])


func _snapshot() -> Dictionary:
	var s := {}
	for k: String in _shared:
		s[k] = AppState.get_setting(k)
	return {"room": String(AppState.get_setting("room_id")), "curtain": AppState.is_curtain_closed(), "settings": s}


@rpc("authority", "call_remote", "reliable")
func _net_snapshot(snap: Dictionary) -> void:
	if not _from_host():
		return
	var s: Variant = snap.get("settings")
	if s is Dictionary:
		for k: Variant in s:
			_apply_setting(String(k), s[k])
	_apply_room(snap.get("room"))
	_apply_curtain(snap.get("curtain"), "instant")
	_emit_state()


@rpc("authority", "call_remote", "reliable")
func _net_setting(key: String, value: Variant) -> void:
	if _from_host():
		_apply_setting(key, value)


@rpc("authority", "call_remote", "reliable")
func _net_room(room_id: String) -> void:
	if _from_host():
		_apply_room(room_id)


@rpc("authority", "call_remote", "reliable")
func _net_curtain(closed: bool, style: String) -> void:
	if _from_host():
		_apply_curtain(closed, style)


@rpc("authority", "call_remote", "reliable")
func _net_roster(list: Array) -> void:
	if not _from_host():
		return
	_peers.clear()
	for p: Variant in list:
		if p is Dictionary and (p as Dictionary).get("id") is int:
			_peers[int(p["id"])] = {"name": _clean_name(String(p.get("name", ""))), "cohost": bool(p.get("cohost", false))}
	_emit_state()


@rpc("authority", "call_remote", "reliable")
func _net_left(peer_id: int) -> void:
	if _from_host():
		EventBus.net_peer_left.emit(peer_id)


## Host: a co-host asks to change shared state. Applied here; the change then goes to everyone.
@rpc("any_peer", "call_remote", "reliable")
func _net_request(what: String, value: Variant) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id) or not bool(_peers[id]["cohost"]):
		return
	if what == "room":
		if value is String:
			AppState.request_room(value)
	elif what == "curtain":
		if value is Array and (value as Array).size() == 2 and value[0] is bool and CURTAIN_STYLES.has(String(value[1])):
			AppState.set_curtain(value[0], String(value[1]))
	elif _setting_ok(what, value):
		AppState.set_setting(what, value)


func _apply_setting(key: String, value: Variant) -> void:
	if not _setting_ok(key, value):
		return
	if key.ends_with("_source") and LOCAL_ONLY_SOURCES.has(String(value)):
		value = "silhouette"
	_applying = true
	AppState.set_setting(key, value)
	_applying = false


func _apply_room(room_id: Variant) -> void:
	if not room_id is String or RoomCatalog.get_info(room_id) == null:
		return
	if room_id == String(AppState.get_setting("room_id")):
		return
	_applying = true
	AppState.request_room(room_id)
	_applying = false


func _apply_curtain(closed: Variant, style: String) -> void:
	if not closed is bool or not CURTAIN_STYLES.has(style):
		return
	_applying = true
	AppState.set_curtain(closed, style)
	_applying = false


## Whitelisted key, the same type as its default, and web addresses only as http(s).
func _setting_ok(key: String, value: Variant) -> bool:
	if not _shared.has(key) or typeof(value) != typeof(AppState.DEFAULTS[key]):
		return false
	if key.ends_with("_url") and not is_web_address(String(value)):
		return false
	return true


# ── Reactions ────────────────────────────────────────────────
## A reaction played here (from this PC's own Stream Core) plays for everyone: a guest sends it to
## the host, the host plays it and passes it on to the other guests.
func _on_reaction_play(d: Dictionary) -> void:
	if _role == "off" or bool(d.get("net_remote", false)):
		return
	var out := _shareable_reaction(d)
	if _role == "host":
		_to_guests("_net_reaction", [out])
	else:
		_net_guest_reaction.rpc_id(1, out)


@rpc("authority", "call_remote", "reliable")
func _net_reaction(d: Dictionary) -> void:
	if _from_host():
		_play_remote(_shareable_reaction(d))


@rpc("any_peer", "call_remote", "reliable")
func _net_guest_reaction(d: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id):
		return
	var out := _shareable_reaction(d)
	_play_remote(out)
	for other: int in _peers:
		if other != 1 and other != id:
			_net_reaction.rpc_id(other, out)


## Only what the effect needs, as plain values. The id is marked so nobody reports the result to
## their own Stream Core twice, and a picture from the sender's Stream Core (only reachable on
## their PC) is dropped: the reaction shows its emoji / word instead.
static func _shareable_reaction(d: Dictionary) -> Dictionary:
	var params: Dictionary = (d.get("params") as Dictionary).duplicate(true) if d.get("params") is Dictionary else {}
	params.erase("object_image")
	var from: Dictionary = d.get("from") if d.get("from") is Dictionary else {}
	var target: Variant = null
	if d.get("target") is Dictionary:
		var t: Dictionary = d["target"]
		target = {"type": String(t.get("type", "stage")), "name": String(t.get("name", ""))}
	var id := String(d.get("id", ""))
	return {"id": id if id.begins_with("net-") else "net-" + id,
		"reaction": String(d.get("reaction", "")), "label": String(d.get("label", "")),
		"effect": String(d.get("effect", "")), "count": clampi(int(d.get("count", 1)), 1, 50),
		"params": params, "target": target, "route": "game", "seed": int(d.get("seed", 0)),
		"from": {"platform": String(from.get("platform", "")), "username": String(from.get("username", "")),
			"display_name": String(from.get("display_name", ""))}}


func _play_remote(d: Dictionary) -> void:
	if not bool(AppState.get_setting("reactions_enabled")) or not Reactions.get_effect_ids().has(String(d["effect"])):
		return
	d["net_remote"] = true
	EventBus.reaction_play.emit(d)


# ── Cameras ──────────────────────────────────────────────────
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _net_camera(peer_id: int, x: Transform3D) -> void:
	if not _from_host() or peer_id == multiplayer.get_unique_id():
		return
	EventBus.net_camera_moved.emit(peer_id, _peer_name(peer_id), x)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _net_guest_camera(x: Transform3D) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id):
		return
	_cams[id] = x
	EventBus.net_camera_moved.emit(id, _peer_name(id), x)
	for other: int in _peers:
		if other != 1 and other != id:
			_net_camera.rpc_id(other, id, x)


# ── Helpers ──────────────────────────────────────────────────
func _sm() -> SceneMultiplayer:
	return multiplayer as SceneMultiplayer


func _from_host() -> bool:
	return _role == "guest" and multiplayer.get_remote_sender_id() == 1


func _is_cohost() -> bool:
	if _role == "host":
		return true
	if _role != "guest":
		return false
	var me := multiplayer.get_unique_id()
	return _peers.has(me) and bool(_peers[me]["cohost"])


func _peer_name(id: int) -> String:
	return String(_peers[id]["name"]) if _peers.has(id) else "Guest"


func _send_roster() -> void:
	var list: Array = []
	for id: int in _peers:
		list.append({"id": id, "name": String(_peers[id]["name"]), "cohost": bool(_peers[id]["cohost"])})
	_to_guests("_net_roster", [list])
	_emit_state()


## Host: call an RPC on every connected guest.
func _to_guests(method: String, args: Array) -> void:
	for id: int in _peers:
		if id != 1:
			callv("rpc_id", [id, method] + args)


func _set_status(text: String, is_error: bool = false) -> void:
	_status = text
	_error = is_error
	EventBus.status_message.emit(text, is_error)
	_emit_state()


func _emit_state() -> void:
	EventBus.net_state_changed.emit(get_info())


static func _version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


## Names show on floating labels and in lists: one line, up to 24 characters.
static func _clean_name(n: String) -> String:
	var out := ""
	for c in n.strip_edges():
		if c.unicode_at(0) >= 32:
			out += c
	return out.left(24).strip_edges()


## This PC's Tailscale address (100.64.0.0/10), or "".
static func _tailscale_ip() -> String:
	for a in IP.get_local_addresses():
		var parts := a.split(".")
		if parts.size() == 4 and parts[0] == "100" and int(parts[1]) >= 64 and int(parts[1]) <= 127:
			return a
	return ""


## A home-network address to show when listening on every network.
static func _lan_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
	return "this PC's address"
