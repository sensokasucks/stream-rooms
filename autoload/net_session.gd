extends Node
## NetSession: streaming together (docs/MULTIPLAYER.md). One host and up to three guests, each
## running their own copy of Stream Rooms and drawing the room from their own camera. Only
## small state messages travel between the PCs, never video.
##
## The connection is a WebSocket (not UDP), so it can go through a Cloudflare tunnel: with
## "together_bind" = "tunnel" the host runs cloudflared (tools/cloudflared.exe), gets a one-off
## https://....trycloudflare.com address, and guests join through Cloudflare. Nobody sees anyone's
## real address then. Addresses never go in status messages (they show on the stream).
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
const AUTH_TIMEOUT: float = 20.0        # (a fresh Cloudflare tunnel can be slow for its first connection)
const HANDSHAKE_TIMEOUT: float = 20.0
const CAMERA_SEND_GAP: float = 0.1      # camera updates at most 10 times a second
const MIN_PASSWORD: int = 4
const TUNNEL_TIMEOUT: float = 40.0      # cloudflared usually has the address within 5 s
const PING_GAP: float = 2.0             # guest: round-trip time to the host, for video sync
## Synced video: start without whoever isn't ready after this long (they catch up when they are).
const READY_TIMEOUT: float = 120.0
## A guest who passed the password check waits this long for both popups (the host's "let them in"
## and the guest's "is this the right host") before the host sends it away.
const CONFIRM_TIMEOUT: float = 120.0

## Settings everyone in the session shares (the presenter ones are added in _ready()).
const SHARED_BASE: Array[String] = ["screen_peer", "house_lights", "curtain_enabled", "curtain_sign", "curtain_color",
	"curtain_speed", "curtain_show_lights"]
## Presenter fields that are shared. camera / ndi pick devices on one PC, and the chat link ties a
## podium to one streamer's own audience, so those stay local.
## ("picture" is a file on the host's PC: its bytes travel separately, see _send_picture.)
const SHARED_PRESENTER_FIELDS: Array[String] = ["on", "source", "peer", "url", "self_lit", "light", "key",
	"key_color", "key_similarity", "key_smoothness", "key_spill", "zoom", "offset_y", "name",
	"picture_scale", "picture_self_lit", "picture_x", "picture_y"]
## The host picks which of these groups guests follow (together_share_*). An unshared group is
## each PC's own: guests change theirs freely and the host's changes stay on the host.
const SHARE_GROUPS: Array[String] = ["room", "curtain", "presenters"]
## Presenter sources that only exist on the host's PC (its camera, browser tab, NDI, Spout): guests show
## a silhouette instead. A "web" page (e.g. a VDO.Ninja link) works for everyone.
const LOCAL_ONLY_SOURCES: Array[String] = ["camera", "tab", "ndi", "spout"]
const CURTAIN_STYLES: Array[String] = ["normal", "instant", "reveal"]

var _shared: Dictionary = {}            # setting key -> true
var _host_shares: Dictionary = {}       # guest: group -> bool, as the host last said (empty = all)
var _role: String = "off"               # "off" | "host" | "guest"
var _status: String = ""
var _error: bool = false
var _address: String = ""               # host: what guests type in; guest: where it connected
var _peers: Dictionary = {}             # peer id -> {"name": String, "cohost": bool}; the host is 1
var _nonces: Dictionary = {}            # host: peer id -> challenge bytes
var _hello_names: Dictionary = {}       # host: peer id -> name from its hello (until it's connected)
## Host: guests who passed the password check but aren't in yet. Both sides confirm first (the host
## sees the guest's name, the guest sees the host's), and nothing syncs until both said yes.
## peer id -> {"name": String, "host_ok": bool, "guest_ok": bool, "wait": float}
var _pending: Dictionary = {}
var _host_name: String = ""              # guest: the host's name, once it has introduced itself
var _admitted: bool = false              # guest: the host let this copy in (its first roster arrived)
## Tests: skip both confirmation popups (every guest is let in, every host is accepted). Not a
## setting, so there's no way to turn the popups off in the app itself.
var auto_confirm: bool = false
var _cams: Dictionary = {}              # host: peer id -> last camera Transform3D
var _refused: String = ""               # guest: why the host said no
var _applying: bool = false             # guest: applying the host's state (the gate lets it through)
var _medium_dismissed: bool = false
var _cam_wait: float = 0.0
var _last_cam: Transform3D
var _tunnel_pid: int = -1               # host: the cloudflared process
var _tunnel_log: String = ""
var _tunnel_wait: float = -1.0
var _tunnel_warm: HTTPRequest           # host: one request through the new tunnel, so it's awake before guests use it
var _ping_wait: float = 0.0
var _rtt: float = 0.0                   # guest: seconds for a message to the host and back
## The host's live feed (its shared tab, through VDO.Ninja): a random stream name and key per
## session, only ever sent to guests who passed the password check.
var _live_id: String = ""
var _live_key: String = ""
var _live_on: bool = false              # guest: the host is sharing a tab right now
var _live_relay: bool = false           # guest: the host wants the feed relayed (addresses hidden)
var _live_feed_on: bool = true          # guest: the host sends its shared tab (as opposed to only avatars)
var _host_sources: Dictionary = {}      # guest: presenter source keys -> what the host said (before any silhouette stand-in)
var _live_quality: Dictionary = {}      # guest: the host's quality settings for the live feed and avatars
var _aud_shared: bool = false           # guest: the host shares its audience (this PC mirrors it)
var _roster_wait: float = -1.0          # host: send the whole roster to the guests in this long
var _video_count: int = 0
## Host: the synced video. {id, url, ready: {peer id: true}, live (host's copy loaded), started, wait}
var _video: Dictionary = {}
## Guest: the host's video. {id, url, ready, state: [position, playing, time received in ms] or []}
var _guest_video: Dictionary = {}


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
	EventBus.file_prepared.connect(_on_file_prepared)
	EventBus.file_prepare_failed.connect(_on_file_prepare_failed)
	EventBus.file_progress.connect(_on_file_progress)
	EventBus.source_changed.connect(_on_source_changed)
	EventBus.audience_seated.connect(_on_aud_seated)
	EventBus.audience_left.connect(_on_aud_left)
	EventBus.audience_spoke.connect(_on_aud_spoke)
	EventBus.audience_updated.connect(_on_aud_updated)
	EventBus.seating_changed.connect(_on_seating_changed)
	EventBus.chat_message_received.connect(_on_local_chat)
	EventBus.chat_user_updated.connect(_on_local_user)
	set_process(false)


func _exit_tree() -> void:
	if _role != "off":
		_close("")


func _process(delta: float) -> void:
	_video_timeout(delta)
	_tunnel_poll(delta)
	if _role == "guest":
		_ping_wait -= delta
		if _ping_wait <= 0.0:
			_ping_wait = PING_GAP
			_net_ping.rpc_id(1, Time.get_ticks_msec())
	if _roster_wait >= 0.0:
		_roster_wait -= delta
		if _roster_wait < 0.0:
			_send_roster_to_guests()
	_pending_timeout(delta)
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
## {role, status, error, address, cohost, suggest_medium, host_live, peers: [{id, name, cohost, me}]}
func get_info() -> Dictionary:
	var me := multiplayer.get_unique_id() if _role != "off" else 0
	var peers: Array = []
	for id: int in _peers:
		peers.append({"id": id, "name": String(_peers[id]["name"]), "cohost": bool(_peers[id]["cohost"]), "me": id == me})
	var q := String(AppState.get_setting("graphics_quality"))
	return {"role": _role, "status": _status, "error": _error, "address": _address, "cohost": _is_cohost(),
		"suggest_medium": _role == "guest" and _peers.size() > 0 and not _medium_dismissed and (q == "high" or q == "custom"),
		"host_live": is_host_live(), "shares": {"room": group_shared("room"), "curtain": group_shared("curtain"),
		"presenters": group_shared("presenters")}, "peers": peers, "pending": pending_guests(),
		"waiting": _role == "guest" and not _admitted, "host_name": _host_name}


## Host: who is waiting to be let in, [{id, name, host_ok, guest_ok}].
func pending_guests() -> Array:
	var list: Array = []
	for id: int in _pending:
		var p: Dictionary = _pending[id]
		list.append({"id": id, "name": String(p["name"]), "host_ok": bool(p["host_ok"]), "guest_ok": bool(p["guest_ok"])})
	return list


func get_role() -> String:
	return _role


func is_shared(key: String) -> bool:
	return _shared.has(key)


## True when this PC may not change it: a guest who isn't a co-host, for a group the host shares.
## what: a setting key, "room" or "curtain".
func is_locked(what: String) -> bool:
	return _role == "guest" and not _is_cohost() and _group_of(what) != "" and group_shared(_group_of(what))


## Which share group a setting key (or "room" / "curtain") belongs to; "" = not shared at all.
func _group_of(what: String) -> String:
	if what == "room" or what == "screen_peer":
		return "room"
	if what == "curtain" or what == "house_lights" or what.begins_with("curtain_"):
		return "curtain"
	if what.begins_with("presenter_") and _shared.has(what):
		return "presenters"
	return ""


## Is this group followed by the guests right now? Host: its own setting; guest: what the host said.
func group_shared(group: String) -> bool:
	if _role == "guest":
		return bool(_host_shares.get(group, true))
	return bool(AppState.get_setting("together_share_" + group))


func _share_flags() -> Dictionary:
	var out := {}
	for g in SHARE_GROUPS:
		out[g] = bool(AppState.get_setting("together_share_" + g))
	return out


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
	if bind == "tunnel" and _cloudflared() == "":
		_set_status("cloudflared.exe isn't in the tools folder. Run tools\\get_tools.ps1 to download it, then try again.", true)
		return
	var peer := _make_peer()
	if peer.create_server(port, ip) != OK:
		_set_status("Couldn't start hosting on port %d. Is another copy already hosting on it?" % port, true)
		return
	multiplayer.multiplayer_peer = peer
	_role = "host"
	_peers = {1: {"name": display_name(), "cohost": true, "avatar": _random_token(16)}}
	_cams.clear()
	_video.clear()
	AppState.net_gate = _gate
	_live_id = _random_token(20)
	_live_key = _random_token(24)
	_emit_live()
	if ip == "*":
		_address = "%s:%d" % [ts if ts != "" else _lan_ip(), port]
	else:
		_address = "%s:%d" % [ip, port]
	_last_cam = Transform3D()
	set_process(true)
	if bind == "tunnel":
		_address = ""
		_tunnel_start(port)
		return
	var where := "Click Copy address and give it to your guests."
	if ip == "127.0.0.1":
		where = "Only copies on this PC can join" + (" (Tailscale isn't running)." if bind == "auto" else ".")
	_set_status("Hosting. " + where)


func join() -> void:
	if _role != "off":
		return
	var pw := String(AppState.get_setting("together_password")).strip_edges()
	if pw == "":
		_set_status("Type the session password first.", true)
		return
	var url := join_url(String(AppState.get_setting("together_address")), int(AppState.get_setting("together_port")))
	if url == "":
		_set_status("Type the host's address first (a 100.x Tailscale address, or the host's trycloudflare.com address).", true)
		return
	var peer := _make_peer()
	if peer.create_client(url) != OK:
		_set_status("Couldn't connect to the host.", true)
		return
	multiplayer.multiplayer_peer = peer
	_role = "guest"
	_peers.clear()
	_refused = ""
	_rtt = 0.0
	_ping_wait = 0.5
	_address = url
	_set_status("Connecting to the host...")


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


## Host: the answer to "<name> wants to join": let them in, or send them away.
func approve(peer_id: int, yes: bool) -> void:
	if _role != "host" or not _pending.has(peer_id):
		return
	if not yes:
		_turn_away(peer_id, "The host declined.", "Declined %s." % String(_pending[peer_id]["name"]))
		return
	_pending[peer_id]["host_ok"] = true
	_maybe_admit(peer_id)


## Guest: the answer to "you're connected to <host>": join, or leave.
func confirm(yes: bool) -> void:
	if _role != "guest" or _admitted:
		return
	if not yes:
		_close("Left: that wasn't the host you meant to join.")
		return
	_net_guest_confirm.rpc_id(1)
	_set_status("Waiting for %s to let you in..." % _host_name)


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
	var n := String(_hello_names.get(id, "Guest"))
	_hello_names.erase(id)
	# the password was right; now both people confirm before anything is shared
	_pending[id] = {"name": n, "host_ok": auto_confirm, "guest_ok": false, "wait": CONFIRM_TIMEOUT}
	_net_welcome.rpc_id(id, display_name())
	if not auto_confirm:
		EventBus.net_confirm_needed.emit("host", id, n)
	_set_status("%s wants to join. Let them in or decline in the popup." % n)


## Host: when both have said yes, the guest is in and gets everything.
func _maybe_admit(id: int) -> void:
	if not _pending.has(id) or not bool(_pending[id]["host_ok"]) or not bool(_pending[id]["guest_ok"]):
		_emit_state()
		return
	var who := String(_pending[id]["name"])
	_pending.erase(id)
	EventBus.net_confirm_closed.emit(id)
	_peers[id] = {"name": who, "cohost": false, "avatar": _random_token(16)}
	_net_snapshot.rpc_id(id, _snapshot())
	if group_shared("presenters"):
		for n in range(1, AppState.PRESENTER_COUNT + 1):
			_send_picture(n, id)
	_send_roster()
	_update_audience_sharing()
	_last_cam = Transform3D()         # send the host's camera again, for the newcomer
	for other: int in _cams:
		_net_camera.rpc_id(id, other, _cams[other])
	_set_status("%s joined." % _peers[id]["name"])


func _on_peer_disconnected(id: int) -> void:
	if _role == "host" and _pending.has(id):
		var who := String(_pending[id]["name"])
		_pending.erase(id)
		EventBus.net_confirm_closed.emit(id)
		_set_status("%s left before joining." % who)
		return
	if _role != "host" or not _peers.has(id):
		return
	var n := String(_peers[id]["name"])
	_peers.erase(id)
	_cams.erase(id)
	EventBus.net_peer_left.emit(id)
	_to_guests("_net_left", [id])
	_send_roster()
	_update_audience_sharing()
	_set_status("%s left." % n)


func _on_connected() -> void:
	if _role != "guest":
		return
	AppState.net_gate = _gate
	_last_cam = Transform3D()
	_admitted = false
	_host_name = ""
	set_process(true)
	_set_status("Connected. Waiting for the host to say hello...")


func _on_connection_failed() -> void:
	if _role == "guest":
		_close.call_deferred("Couldn't reach the host. Check the address, and that the host is hosting. A new Cloudflare tunnel can need a second try.", true)


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
	for id: int in _pending:
		EventBus.net_confirm_closed.emit(id)
	_pending.clear()
	if _role == "guest" and not _admitted:
		EventBus.net_confirm_closed.emit(1)
	_host_name = ""
	_admitted = false
	_cams.clear()
	_video.clear()
	_guest_video.clear()
	_live_id = ""
	_live_key = ""
	_live_on = false
	_host_sources.clear()
	_emit_live()
	_aud_shared = false
	_roster_wait = -1.0
	AudienceManager.set_mirror(false)
	AudienceManager.set_streamer_areas(0)
	_address = ""
	_tunnel_stop()
	AppState.net_gate = Callable()
	set_process(false)
	if message != "":
		_set_status(message, is_error)
	else:
		_status = ""
		_emit_state()


# ── Shared state ─────────────────────────────────────────────
## Asked by AppState before shared state changes here. Host: only a video for the big screen
## (a web link is loaded on every PC and started together). Guest: anything shared.
func _gate(what: String, value: Variant) -> bool:
	if _role == "host":
		return what != "video" or _host_video_request(String(value))
	if _role != "guest" or _applying:
		return true
	if what != "video" and (_group_of(what) == "" or not group_shared(_group_of(what))):
		return true          # not shared (or not any more): this PC's own
	if _is_cohost():
		_net_request.rpc_id(1, what, value)
	else:
		EventBus.status_message.emit("The host controls this while you're a guest (Together tab).", false)
	return false


func _on_setting_changed(key: String, value: Variant) -> void:
	if _role == "host" and _shared.has(key) and group_shared(_group_of(key)):
		_to_guests("_net_setting", [key, value])
	if _role == "host" and key.begins_with("together_share_"):
		_share_changed(key.trim_prefix("together_share_"))
	if _role == "host" and key.begins_with("presenter_") and key.ends_with("_picture") and group_shared("presenters"):
		_send_picture(int(key.get_slice("_", 1)), -1)
	elif key == "graphics_quality" and _role == "guest":
		_emit_state()
	if (key == "together_shared_audience" or key == "together_audience_areas") and _role == "host":
		_update_audience_sharing()
	if key.begins_with("together_screen_") or key in ["together_avatar_height", "together_avatar_fps", "together_avatar_kbps"]:
		if _role == "host":
			_emit_live()
			_to_guests("_net_live", [_live_info_for_guests()])
	if (key == "together_live_feed" or key == "together_live_relay") and _role == "host":
		_emit_live()
		_to_guests("_net_live", [_live_info_for_guests()])


func _on_room_requested(room_id: String) -> void:
	if _role == "host" and group_shared("room"):
		_to_guests("_net_room", [room_id])


func _on_curtain_changed(closed: bool, style: String) -> void:
	if _role == "host" and group_shared("curtain"):
		_to_guests("_net_curtain", [closed, style])


## Host: a share group was switched on or off. Guests hear the flags; a group switched on also
## gets that part of the host's state right away.
func _share_changed(group: String) -> void:
	_to_guests("_net_share_flags", [_share_flags()])
	if group_shared(group):
		_to_guests("_net_snapshot", [_snapshot([group])])
		if group == "presenters":
			for n in range(1, AppState.PRESENTER_COUNT + 1):
				_send_picture(n, -1)
	_emit_state()


## What a guest needs to match the host: the shared groups (all of them by default).
func _snapshot(groups: Array = SHARE_GROUPS) -> Dictionary:
	var s := {}
	for k: String in _shared:
		if groups.has(_group_of(k)) and group_shared(_group_of(k)):
			s[k] = AppState.get_setting(k)
	var snap := {"settings": s, "shares": _share_flags(), "live": _live_info_for_guests()}
	if groups.has("room") and group_shared("room"):
		snap["room"] = String(AppState.get_setting("room_id"))
	if groups.has("curtain") and group_shared("curtain"):
		snap["curtain"] = AppState.is_curtain_closed()
	if bool(_video.get("live", false)):
		snap["video"] = {"id": int(_video["id"]), "url": String(_video["url"])}
	return snap


@rpc("authority", "call_remote", "reliable")
func _net_snapshot(snap: Dictionary) -> void:
	if not _from_host():
		return
	if snap.get("shares") is Dictionary:
		_apply_share_flags(snap["shares"])
	var s: Variant = snap.get("settings")
	if s is Dictionary:
		for k: Variant in s:
			_apply_setting(String(k), s[k])
	if snap.has("room"):
		_apply_room(snap.get("room"))
	if snap.has("curtain"):
		_apply_curtain(snap.get("curtain"), "instant")
	var lv: Variant = snap.get("live")
	if lv is Dictionary:
		_apply_live(lv)
	var v: Variant = snap.get("video")
	if v is Dictionary and (v as Dictionary).get("id") is int and (v as Dictionary).get("url") is String:
		_guest_load_video(int(v["id"]), String(v["url"]))      # joined mid-video: catch up once loaded
	_emit_state()


@rpc("authority", "call_remote", "reliable")
func _net_setting(key: String, value: Variant) -> void:
	if _from_host():
		_apply_setting(key, value)


@rpc("authority", "call_remote", "reliable")
func _net_share_flags(flags: Dictionary) -> void:
	if _from_host():
		_apply_share_flags(flags)
		_emit_state()


func _apply_share_flags(flags: Dictionary) -> void:
	_host_shares.clear()
	for g in SHARE_GROUPS:
		_host_shares[g] = bool(flags.get(g, true))


# ── Podium pictures ──────────────────────────────────────────
## Host: presenter n's podium picture, as bytes, to one guest (peer id) or all (-1). An empty
## picture clears it. Guests keep the bytes in user://podium_pictures and point their own setting
## there (never at a path on the host's PC).
func _send_picture(n: int, to: int) -> void:
	if _role != "host":
		return
	var path := String(AppState.get_setting(AppState.presenter_key(n, "picture"))).strip_edges()
	var bytes := PictureFile.read_file(path) if path != "" else PackedByteArray()
	if path != "" and bytes.is_empty():
		return           # unreadable here: say nothing, the guests keep what they had
	var kind := PictureFile.kind_of(bytes) if not bytes.is_empty() else ""
	if to > 0:
		_net_picture.rpc_id(to, n, kind, bytes)
	else:
		_to_guests("_net_picture", [n, kind, bytes])


@rpc("authority", "call_remote", "reliable")
func _net_picture(n: int, kind: String, bytes: PackedByteArray) -> void:
	if not _from_host() or n < 1 or n > AppState.PRESENTER_COUNT or not group_shared("presenters"):
		return
	var key := AppState.presenter_key(n, "picture")
	if bytes.is_empty():
		_set_local(key, "")
		return
	if bytes.size() > PictureFile.MAX_BYTES or PictureFile.kind_of(bytes) != kind or kind == "":
		return
	DirAccess.make_dir_recursive_absolute("user://podium_pictures")
	var path := "user://podium_pictures/host_%d.%s" % [n, kind]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	# (the same path as before means no change: nudge it so the presenter reloads the picture)
	if String(AppState.get_setting(key)) == path:
		_set_local(key, "")
	_set_local(key, path)


## Guest: a setting the host decided, written past the gate ("picture" isn't a shared field: its
## value here is this PC's own copy of the host's file).
func _set_local(key: String, value: Variant) -> void:
	_applying = true
	AppState.set_setting(key, value)
	_applying = false


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
			var av := String(p.get("avatar", ""))
			_peers[int(p["id"])] = {"name": _clean_name(String(p.get("name", ""))), "cohost": bool(p.get("cohost", false)),
				"avatar": av if _token_ok(av) else ""}
	if not _admitted:
		_admitted = true
		EventBus.net_confirm_closed.emit(1)
		_set_status("Joined %s's session. The host controls the room, curtain and presenters." % _host_name)
	_refresh_sources()
	_emit_state()
	_emit_live()


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
	if what != "video" and (_group_of(what) == "" or not group_shared(_group_of(what))):
		return          # not a shared group: the guest changes that on their own PC
	if what == "room":
		if value is String:
			AppState.request_room(value)
	elif what == "curtain":
		if value is Array and (value as Array).size() == 2 and value[0] is bool and CURTAIN_STYLES.has(String(value[1])):
			AppState.set_curtain(value[0], String(value[1]))
	elif what == "video":
		if value is String and value != "" and is_web_address(value):
			EventBus.file_play_requested.emit(value)
	elif _setting_ok(what, value):
		AppState.set_setting(what, value)


func _apply_setting(key: String, value: Variant) -> void:
	if not _setting_ok(key, value):
		return
	if key.ends_with("_source"):
		_host_sources[key] = value
		value = _source_here(key, String(value))
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


# ── Synced video ─────────────────────────────────────────────
## Host: a video for the big screen. A web link is downloaded and converted on every PC (each with
## its own yt-dlp / ffmpeg), everyone waits on the first frame, and the host starts them all at
## once. A file on the host's PC can't reach the guests, so it plays here only.
func _host_video_request(input: String) -> bool:
	if _peers.size() < 2:
		return true                  # nobody to watch with: play as usual
	if not (input.begins_with("http://") or input.begins_with("https://")) or not is_web_address(input):
		EventBus.status_message.emit("Guests can't see a file from your PC, so only you will see it. Use a web link (YouTube...) to watch together.", false)
		if not _video.is_empty():
			_to_guests("_net_video_stop", [int(_video["id"])])     # (they'd keep watching the old one)
			_video.clear()
		return true
	_video_count += 1
	_video = {"id": _video_count, "url": input, "ready": {}, "live": false, "started": false, "wait": READY_TIMEOUT}
	_to_guests("_net_video_load", [_video_count, input])
	_set_status("Loading the video on every PC. It starts when everyone's ready.")
	EventBus.file_prepare_requested.emit(input)
	return false


func _on_file_prepared(input: String) -> void:
	if _role == "host" and not _video.is_empty() and input == String(_video["url"]) and not bool(_video["live"]):
		_video["live"] = true
		_mark_ready(1)
	elif _role == "guest" and not _guest_video.is_empty() and input == String(_guest_video["url"]):
		_guest_video["ready"] = true
		_net_video_ready.rpc_id(1, int(_guest_video["id"]))
		_apply_video_state()      # (a late joiner catches up with the last position it heard)


func _on_file_prepare_failed(input: String, message: String) -> void:
	if _role == "host" and not _video.is_empty() and input == String(_video["url"]):
		_set_status("The video didn't load here: " + message, true)
		_video.clear()
		_to_guests("_net_video_stop", [_video_count])
	elif _role == "guest" and not _guest_video.is_empty() and input == String(_guest_video["url"]):
		_net_video_failed.rpc_id(1, int(_guest_video["id"]), message.left(200))


func _mark_ready(peer_id: int) -> void:
	_video["ready"][peer_id] = true
	for id: int in _peers:
		if not _video["ready"].has(id):
			return
	_start_video()


func _video_timeout(delta: float) -> void:
	if _role != "host" or _video.is_empty() or bool(_video["started"]) or not bool(_video["live"]):
		return
	_video["wait"] = float(_video["wait"]) - delta
	if float(_video["wait"]) <= 0.0:
		var late := PackedStringArray()
		for id: int in _peers:
			if not _video["ready"].has(id):
				late.append(_peer_name(id))
		EventBus.status_message.emit("Starting without %s (still loading; they'll catch up)." % ", ".join(late), false)
		_start_video()


func _start_video() -> void:
	if bool(_video["started"]):
		return
	_video["started"] = true
	_set_status("Everyone's ready: playing.")
	EventBus.file_sync_requested.emit(0.0, true)
	_to_guests("_net_video_state", [int(_video["id"]), 0.0, true])


## Host: where the video is, about once a second (and on pause / resume), to every guest.
func _on_file_progress(position: float, playing: bool) -> void:
	if _role == "host" and bool(_video.get("started", false)):
		_to_guests("_net_video_state", [int(_video["id"]), position, playing])


func _on_source_changed(mode: String) -> void:
	if _role == "host":
		_to_guests("_net_live", [_live_info_for_guests()])     # sharing a tab started / stopped
	# the host's screen moved on from the synced video (Stop, another source): guests stop too
	if _role == "host" and bool(_video.get("live", false)) and mode != "file":
		_to_guests("_net_video_stop", [int(_video["id"])])
		_video.clear()


@rpc("any_peer", "call_remote", "reliable")
func _net_video_ready(id: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(from) or _video.is_empty() or id != int(_video["id"]):
		return
	if bool(_video["started"]):
		return       # a late joiner: the next position update brings it along
	_mark_ready(from)


@rpc("any_peer", "call_remote", "reliable")
func _net_video_failed(id: int, message: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(from) or _video.is_empty() or id != int(_video["id"]):
		return
	EventBus.status_message.emit("%s couldn't load the video: %s" % [_peer_name(from), message.left(200)], true)
	if not bool(_video["started"]):
		_mark_ready(from)        # don't keep everyone waiting


@rpc("authority", "call_remote", "reliable")
func _net_video_load(id: int, url: String) -> void:
	if _from_host():
		_guest_load_video(id, url)


@rpc("authority", "call_remote", "reliable")
func _net_video_state(id: int, position: float, playing: bool) -> void:
	if not _from_host() or _guest_video.is_empty() or id != int(_guest_video["id"]):
		return
	_guest_video["state"] = [position, playing, Time.get_ticks_msec()]
	_apply_video_state()


@rpc("authority", "call_remote", "reliable")
func _net_video_stop(id: int) -> void:
	if not _from_host() or _guest_video.is_empty() or id != int(_guest_video["id"]):
		return
	_guest_video.clear()
	EventBus.file_stop_requested.emit()


## Guest: download / convert the host's web link here, and wait on its first frame.
func _guest_load_video(id: int, url: String) -> void:
	if url == "" or not (url.begins_with("http://") or url.begins_with("https://")) or not is_web_address(url):
		return           # never a file path from the network
	_guest_video = {"id": id, "url": url, "ready": false, "state": []}
	EventBus.status_message.emit("Loading the host's video...", false)
	EventBus.file_prepare_requested.emit(url)


## Guest: go where the host is, allowing for the time the message took (half the round trip)
## and for how long ago it arrived.
func _apply_video_state() -> void:
	if _guest_video.is_empty() or not bool(_guest_video["ready"]) or (_guest_video["state"] as Array).is_empty():
		return
	var st: Array = _guest_video["state"]
	var playing := bool(st[1])
	var pos := float(st[0])
	if playing:
		pos += _rtt_s() * 0.5 + float(Time.get_ticks_msec() - int(st[2])) / 1000.0
	EventBus.file_sync_requested.emit(pos, playing)


## Round trip to the host in seconds (ENet keeps a running average).
func _rtt_s() -> float:
	return _rtt


@rpc("any_peer", "call_remote", "reliable")
func _net_ping(sent_ms: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role == "host" and _peers.has(id):
		_net_pong.rpc_id(id, sent_ms)


@rpc("authority", "call_remote", "reliable")
func _net_pong(sent_ms: int) -> void:
	if _from_host():
		var sample := float(Time.get_ticks_msec() - sent_ms) / 1000.0
		_rtt = sample if _rtt == 0.0 else _rtt * 0.7 + sample * 0.3


# ── Shared audience ──────────────────────────────────────────
## Host: everyone's viewers sit in one audience. Guests send their chat here; the host seats it
## (its own seating rules, plan and areas) and tells every guest who sits where and what they say.
## Guests "mirror" that roster, so all streams show the same audience.
func _sharing_audience() -> bool:
	return _role == "host" and bool(AppState.get_setting("together_shared_audience")) and _peers.size() > 1


func _update_audience_sharing() -> void:
	if _role != "host":
		return
	var on := bool(AppState.get_setting("together_shared_audience"))
	_to_guests("_net_aud_mode", [on])
	var areas := _peers.size() if on and bool(AppState.get_setting("together_audience_areas")) else 0
	AudienceManager.set_streamer_areas(areas)
	if on:
		_roster_wait = 0.1


## Whose viewer: 0 = the host, then the guests in the order they joined (peer ids grow).
func _streamer_index(peer_id: int) -> int:
	var ids: Array = _peers.keys()
	ids.sort()
	return maxi(ids.find(peer_id), 0)


func _room() -> String:
	return String(AppState.get_setting("room_id"))


func _on_aud_seated(slot: int) -> void:
	if _sharing_audience():
		_to_guests("_net_aud_seat", [_room(), slot, AudienceManager.wire_member(slot)])


func _on_aud_left(slot: int) -> void:
	if _sharing_audience():
		_to_guests("_net_aud_leave", [_room(), slot])


func _on_aud_spoke(slot: int, parts: Array) -> void:
	if _sharing_audience():
		_to_guests("_net_aud_speak", [_room(), slot, parts])


func _on_aud_updated(slot: int) -> void:
	if _sharing_audience():
		_to_guests("_net_aud_update", [_room(), slot, AudienceManager.wire_member(slot)])


func _on_seating_changed() -> void:
	if _sharing_audience():
		_roster_wait = 0.3          # (a room change seats many at once: one roster after it settles)


func _send_roster_to_guests() -> void:
	if _sharing_audience():
		_to_guests("_net_aud_roster", [_room(), AudienceManager.get_roster()])


## Guest: this PC's chat goes to the host's audience (its own chat windows keep showing it).
func _on_local_chat(msg: Dictionary) -> void:
	if _role != "guest" or not _aud_shared or bool(msg.get("system", false)) or bool(msg.get("history", false)):
		return
	var out := {}
	for k in ["name", "username", "platform", "user_id", "color", "text", "title", "avatar", "reply_to", "reply_quote"]:
		out[k] = String(msg.get(k, "")).left(500)
	out["timestamp"] = float(msg.get("timestamp", Time.get_unix_time_from_system()))
	out["emotes"] = msg.get("emotes", []) if msg.get("emotes") is Array else []
	_net_guest_chat.rpc_id(1, out)


func _on_local_user(info: Dictionary) -> void:
	if _role == "guest" and _aud_shared:
		_net_guest_user.rpc_id(1, {"platform": String(info.get("platform", "")), "user_id": String(info.get("user_id", "")),
			"avatar": String(info.get("avatar", ""))})


@rpc("any_peer", "call_remote", "reliable")
func _net_guest_chat(msg: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _sharing_audience() or not _peers.has(id):
		return
	var clean := {}
	for k in ["name", "username", "platform", "user_id", "color", "text", "title", "reply_to", "reply_quote"]:
		clean[k] = String(msg.get(k, "")).left(500)
	var avatar := String(msg.get("avatar", ""))
	clean["avatar"] = avatar.left(500) if avatar.begins_with("https://") else ""
	clean["timestamp"] = minf(float(msg.get("timestamp", 0.0)), Time.get_unix_time_from_system())
	var emotes: Array = []
	if msg.get("emotes") is Array:
		for e: Variant in (msg["emotes"] as Array).slice(0, 60):
			if not e is Dictionary:
				continue
			# only what an emote needs, and pictures only from https addresses (this PC downloads them)
			var ce := {"provider": String(e.get("provider", "")).left(20), "id": String(e.get("id", "")).left(80),
				"start": int(e.get("start", 0)), "end": int(e.get("end", 0))}
			for u in ["url", "static_url"]:
				var link := String(e.get(u, ""))
				ce[u] = link.left(500) if link.begins_with("https://") else ""
			emotes.append(ce)
	clean["emotes"] = emotes
	clean["streamer"] = _streamer_index(id)
	if String(clean["name"]) != "":
		AudienceManager.add_chat(clean)


@rpc("any_peer", "call_remote", "reliable")
func _net_guest_user(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _sharing_audience() or not _peers.has(id):
		return
	var avatar := String(info.get("avatar", ""))
	if avatar.begins_with("https://"):
		AudienceManager.update_user({"platform": String(info.get("platform", "")), "user_id": String(info.get("user_id", "")),
			"avatar": avatar.left(500)})


@rpc("authority", "call_remote", "reliable")
func _net_aud_mode(shared: bool) -> void:
	if _from_host():
		_aud_shared = shared
		AudienceManager.set_mirror(shared)
		_emit_state()


@rpc("authority", "call_remote", "reliable")
func _net_aud_roster(room: String, list: Array) -> void:
	if _from_host() and _aud_shared:
		AudienceManager.mirror_roster(room, list)


@rpc("authority", "call_remote", "reliable")
func _net_aud_seat(room: String, slot: int, wm: Dictionary) -> void:
	if _from_host() and _aud_shared:
		AudienceManager.mirror_seat(room, slot, wm)


@rpc("authority", "call_remote", "reliable")
func _net_aud_leave(room: String, slot: int) -> void:
	if _from_host() and _aud_shared:
		AudienceManager.mirror_leave(room, slot)


@rpc("authority", "call_remote", "reliable")
func _net_aud_speak(room: String, slot: int, parts: Array) -> void:
	if _from_host() and _aud_shared:
		AudienceManager.mirror_speak(room, slot, parts)


@rpc("authority", "call_remote", "reliable")
func _net_aud_update(room: String, slot: int, wm: Dictionary) -> void:
	if _from_host() and _aud_shared:
		AudienceManager.mirror_update(room, slot, wm)


# ── Live feed ────────────────────────────────────────────────
## Host: the sender page publishes its shared tab under _live_id (VDO.Ninja, peer to peer).
## Guests: their sender page views it and hands it to their game like their own shared tab.
func _live_info_for_guests() -> Dictionary:
	var sharing := bool(AppState.get_setting("together_live_feed")) and AppState.get_source_mode() == "capture"
	# the session's stream name and key always go along (the avatars use the key too); "live" says
	# whether the big screen is being shared right now
	return {"id": _live_id, "key": _live_key, "live": sharing and bool(AppState.get_setting("together_live_feed")),
		"feed_on": bool(AppState.get_setting("together_live_feed")), "relay": bool(AppState.get_setting("together_live_relay")),
		"quality": _quality()}


@rpc("authority", "call_remote", "reliable")
func _net_live(info: Dictionary) -> void:
	if _from_host():
		_apply_live(info)


func _apply_live(info: Dictionary) -> void:
	var id := String(info.get("id", ""))
	var key := String(info.get("key", ""))
	if not (_token_ok(id) and _token_ok(key)):
		id = ""
		key = ""
	_live_id = id
	_live_key = key
	_live_on = id != "" and bool(info.get("live", false))
	_live_relay = bool(info.get("relay", false))
	_live_feed_on = bool(info.get("feed_on", true))
	_live_quality = info.get("quality", {}) if info.get("quality") is Dictionary else {}
	_refresh_sources()
	_emit_live()
	_emit_state()


func _emit_live() -> void:
	var info := {"role": "off", "id": "", "key": "", "live": false, "relay": false}
	if _role == "host" and bool(AppState.get_setting("together_live_feed")) and _live_id != "":
		info = {"role": "publish", "id": _live_id, "key": _live_key, "live": true, "relay": bool(AppState.get_setting("together_live_relay"))}
	elif _role == "guest" and _live_id != "" and _live_feed_on:
		info = {"role": "view", "id": _live_id, "key": _live_key, "live": _live_on, "relay": _live_relay}
	# the session key, the quality and the podium list go along even when the big screen isn't shared
	# (the avatars use them)
	if _role != "off":
		info["key"] = _live_key
		info["quality"] = _quality() if _role == "host" else _live_quality
		info["avatars"] = avatar_list()
	EventBus.live_feed_changed.emit(info)


## The host's quality settings for what goes between the PCs.
func _quality() -> Dictionary:
	return {"screen": {"height": int(AppState.get_setting("together_screen_height")), "fps": int(AppState.get_setting("together_screen_fps")),
			"kbps": int(AppState.get_setting("together_screen_kbps"))},
		"avatar": {"height": int(AppState.get_setting("together_avatar_height")), "fps": int(AppState.get_setting("together_avatar_fps")),
			"kbps": int(AppState.get_setting("together_avatar_kbps"))}}


## Everyone in the session with the stream name their avatar is published under:
## [{id, name, mine}]. Empty when not in a session. A podium (Show > Someone's avatar) or the big
## screen names a person; ScreenFeed looks them up here.
func avatar_list() -> Array:
	if _role == "off" or _live_key == "":
		return []
	var ids: Array = _peers.keys()
	ids.sort()
	var me := multiplayer.get_unique_id()
	var out: Array = []
	for id: int in ids:
		var av := String(_peers[id].get("avatar", ""))
		if av != "":
			out.append({"id": av, "name": String(_peers[id]["name"]), "mine": id == me})
	return out


## Guest: what a presenter source the host set means on this PC. A camera, tab, NDI or Spout source
## is on the host's PC only, so a silhouette stands in; "peer" (someone's avatar) travels, so it stays.
func _source_here(_key: String, host_value: String) -> String:
	return "silhouette" if LOCAL_ONLY_SOURCES.has(host_value) else host_value


## Guest: re-apply the host's presenter sources (kept for roster changes).
func _refresh_sources() -> void:
	if _role != "guest":
		return
	for key: String in _host_sources:
		var want := _source_here(key, String(_host_sources[key]))
		if String(AppState.get_setting(key)) != want:
			_set_local(key, want)


## Guest: the host is sharing a tab that this PC can watch.
func is_host_live() -> bool:
	return _role == "guest" and _live_on


static func _random_token(n: int) -> String:
	var chars := "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var bytes := Crypto.new().generate_random_bytes(n)
	var out := ""
	for b in bytes:
		out += chars[b % chars.length()]
	return out


## Stream names and keys from the network: letters and digits only.
static func _token_ok(t: String) -> bool:
	return t.length() >= 8 and t.length() <= 64 and RegEx.create_from_string("^[A-Za-z0-9]+$").search(t) != null


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


# ── Letting a guest in (both sides confirm) ──────────────────
## Guest: the host introduces itself right after the password check. The guest confirms it's the
## right person before anything else happens.
@rpc("authority", "call_remote", "reliable")
func _net_welcome(host_name: String) -> void:
	if not _from_host() or _admitted:
		return
	_host_name = _clean_name(host_name)
	if _host_name == "":
		_host_name = "the host"
	if auto_confirm:
		confirm(true)
	else:
		_set_status("Connected to %s. Confirm in the popup that it's who you meant to join." % _host_name)
		EventBus.net_confirm_needed.emit("guest", 1, _host_name)


## Host: a waiting guest said "yes, this is the right host".
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_confirm() -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _pending.has(id):
		return
	_pending[id]["guest_ok"] = true
	_maybe_admit(id)


## Guest: the host sent this copy away before it was in (declined, or took too long).
@rpc("authority", "call_remote", "reliable")
func _net_declined(reason: String) -> void:
	if _from_host() and not _admitted:
		_refused = reason


func _turn_away(id: int, reason: String, status: String) -> void:
	_pending.erase(id)
	EventBus.net_confirm_closed.emit(id)
	_net_declined.rpc_id(id, reason)
	# a moment for the reason to arrive before the connection closes
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if _role == "host":
			_sm().disconnect_peer(id))
	_set_status(status)


func _pending_timeout(delta: float) -> void:
	if _pending.is_empty():
		return
	for id: int in _pending.keys():
		_pending[id]["wait"] = float(_pending[id]["wait"]) - delta
		if float(_pending[id]["wait"]) <= 0.0:
			_turn_away(id, "Nobody confirmed the connection in time. Try joining again.",
				"%s waited too long to be let in." % String(_pending[id]["name"]))


# ── Connection helpers ───────────────────────────────────────
func _make_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 4 * 1024 * 1024       # (a whole audience roster in one message)
	peer.outbound_buffer_size = 4 * 1024 * 1024
	peer.max_queued_packets = 4096
	peer.handshake_timeout = HANDSHAKE_TIMEOUT   # (the default 3 s isn't enough through a cold tunnel)
	return peer


## The WebSocket address for what a guest typed: "ws://..." / "wss://..." as is, a trycloudflare
## address as wss://, anything else as ws://host:port (the session port when none is given).
static func join_url(typed: String, default_port: int) -> String:
	var a := typed.strip_edges().trim_suffix("/")
	if a == "":
		return ""
	if a.contains("://"):
		return a
	if a.ends_with(".trycloudflare.com"):
		return "wss://" + a
	if not a.contains(":"):
		a = "%s:%d" % [a, default_port]
	return "ws://" + a


## Host: cloudflared.exe next to the exported game or in the project's tools folder ("" = missing).
static func _cloudflared() -> String:
	for d in [OS.get_executable_path().get_base_dir().path_join("tools"), ProjectSettings.globalize_path("res://tools")]:
		var p: String = d.path_join("cloudflared.exe")
		if FileAccess.file_exists(p):
			return p
	return ""


## Host: a Try Cloudflare quick tunnel to this PC's session port. cloudflared writes its log to a
## file; the one-off address is read from there (it takes a few seconds).
func _tunnel_start(port: int) -> void:
	_tunnel_log = ProjectSettings.globalize_path("user://cloudflared%s.log" % ("" if AppState.get_profile().is_empty() else "_" + AppState.get_profile()))
	DirAccess.remove_absolute(_tunnel_log)
	_tunnel_pid = OS.create_process(_cloudflared(), PackedStringArray(["tunnel", "--url", "http://127.0.0.1:%d" % port,
		"--no-autoupdate", "--logfile", _tunnel_log]))
	if _tunnel_pid <= 0:
		_close("Couldn't start cloudflared.exe.", true)
		return
	_tunnel_wait = TUNNEL_TIMEOUT
	_set_status("Hosting. Asking Cloudflare for a tunnel address...")


func _tunnel_poll(delta: float) -> void:
	if _tunnel_wait < 0.0:
		return
	_tunnel_wait -= delta
	var text := FileAccess.get_file_as_string(_tunnel_log) if FileAccess.file_exists(_tunnel_log) else ""
	var m := RegEx.create_from_string("https://[a-z0-9-]+\\.trycloudflare\\.com").search(text)
	if m:
		_tunnel_wait = -1.0
		_tunnel_warm_up(m.get_string())
		return
	if _tunnel_wait <= 0.0 or (_tunnel_pid > 0 and not OS.is_process_running(_tunnel_pid)):
		_tunnel_wait = -1.0
		_close("Cloudflare didn't give a tunnel address (is this PC online?). Try again, or pick another Listen on option.", true)


## A new quick tunnel takes a while to answer its first request (name lookup, Cloudflare's edge).
## The host makes that first request itself, so the address works as soon as a guest gets it.
func _tunnel_warm_up(url: String) -> void:
	_tunnel_warm = HTTPRequest.new()
	_tunnel_warm.timeout = 25.0
	add_child(_tunnel_warm)
	var announce := func() -> void:
		if _tunnel_warm:
			_tunnel_warm.queue_free()
			_tunnel_warm = null
		if _role != "host":
			return
		_address = url.trim_prefix("https://")
		_set_status("Hosting through a Cloudflare tunnel. Click Copy address and give it to your guests. Nobody sees your real address.")
	_tunnel_warm.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void: announce.call())
	if _tunnel_warm.request(url) != OK:
		announce.call()
	else:
		_set_status("Hosting. Waking the tunnel up...")


func _tunnel_stop() -> void:
	_tunnel_wait = -1.0
	if _tunnel_warm:
		_tunnel_warm.queue_free()
		_tunnel_warm = null
	if _tunnel_pid > 0:
		OS.kill(_tunnel_pid)
		_tunnel_pid = -1


## True while this host's address is a Cloudflare tunnel.
func is_tunnel() -> bool:
	return _role == "host" and _address.ends_with(".trycloudflare.com")


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
		list.append({"id": id, "name": String(_peers[id]["name"]), "cohost": bool(_peers[id]["cohost"]), "avatar": String(_peers[id].get("avatar", ""))})
	_to_guests("_net_roster", [list])
	_emit_state()
	_emit_live()            # (the podium list changed)


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
