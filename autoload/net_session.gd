extends Node
## NetSession: streaming together (docs/MULTIPLAYER.md). One host and up to three guests, each
## running their own copy of Stream Rooms and drawing the room from their own camera. Only
## small state messages travel between the PCs, never video.
##
## The connection is a WebSocket (not UDP), so it can go through a Cloudflare tunnel: with
## "together_bind" = "tunnel" the host runs cloudflared (tools/cloudflared.exe), gets a one-off
## https://....trycloudflare.com address, and guests join through Cloudflare. Nobody sees anyone's
## real address then. Addresses never go in status messages (they show on the stream).
## "Hide my address" (together_hide_address, on by default) turns on the tunnel and the video relay
## together, whatever Listen on and the relay tick say (see bind_mode / relay_on).
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
##
## Map of this file (each part starts with a "# ── Name ──" line): Public API (what the Together
## tab calls), Connection (password step, joining, leaving), Shared state (gate, snapshot, settings,
## room, curtain), Podium pictures, Synced video, Shared audience, Audience looks, Each streamer's own looks, Live feed
## (VDO.Ninja), Reactions (with their pictures), Cameras, Laser pointers, Room events, Letting a guest in (both sides confirm), Staying in sync
## (first sync, audience checks, resync, reconnecting), Connection helpers (tunnel), Helpers.
## RPC names start with _net_. "Host:" / "Guest:" at the start of a comment says which side runs it.

## Network protocol number, checked in the password step along with the app version. Raise it when
## the RPCs change in a way older copies can't follow.
## 2: guests send chat in batches (_net_guest_chat_batch); 3: reaction pictures and audience looks travel;
## 4: guests send their own looks and the host sends each streamer's (_net_guest_looks, _net_streamer_looks);
## 5: staying in sync (_net_sync_start / _net_sync_done / _net_guest_synced, _net_aud_check, _net_aud_resync,
## _net_resync_request, _net_removed), streamer areas kept by name, pause to react for everyone
## (_net_react_pause), whose avatar is a see-through page (_net_avatar_keyed, roster "keyed").
## 6 (Co-stream batch 2): animated silhouettes travel (_net_look_picture / _net_guest_look_picture
## carry a frame sheet), plus the big screen remote, claimed podiums and reserved seats.
const PROTOCOL: int = 6
## Guests at most (plus the host = 4 people, see docs/MULTIPLAYER.md).
const MAX_GUESTS: int = 3
## Seconds a connection has to answer the password challenge (one round trip) before it's dropped.
const AUTH_TIMEOUT: float = 10.0
const HANDSHAKE_TIMEOUT: float = 20.0   # (a fresh Cloudflare tunnel can be slow for its first connection)
const CAMERA_SEND_GAP: float = 0.1      # camera updates at most 10 times a second
## Guest: chat for the shared audience goes to the host in batches this often (one message per
## batch instead of one per line, so busy chat doesn't queue up ahead of camera and video updates)...
const CHAT_BATCH_GAP: float = 0.15
## ... with at most this many lines a batch (the rest of a burst is dropped: the host only seats them).
const CHAT_BATCH_MAX: int = 30
## Shortest password for hosting. A password saved before this was raised from 4 still works
## (see _old_password), with a note asking for a longer one.
const MIN_PASSWORD: int = 8
const OLD_MIN_PASSWORD: int = 4
## At most this many connections may be answering the password challenge at once (each one
## holds big network buffers, and a guesser would open many in parallel).
const MAX_UNAUTHENTICATED: int = 4
## Wrong passwords from one address before it has to wait LOCKOUT_S seconds.
const MAX_WRONG: int = 5
const LOCKOUT_S: float = 60.0
const TUNNEL_TIMEOUT: float = 40.0      # cloudflared usually has the address within 5 s
const PING_GAP: float = 2.0             # guest: round-trip time to the host, for video sync
## Synced video: start without whoever isn't ready after this long (they catch up when they are).
const READY_TIMEOUT: float = 120.0
## A guest who passed the password check waits this long for both popups (the host's "let them in"
## and the guest's "is this the right host") before the host sends it away.
const CONFIRM_TIMEOUT: float = 120.0
## Host: seconds between audience checks. While the audience is shared the host sends each guest a
## short fingerprint of who sits where (AudienceManager.roster_fingerprint); a guest whose own
## differs asks for the whole roster again (_net_aud_check -> _net_aud_resync).
const AUD_CHECK_GAP: float = 5.0
## Guest: at most one roster request per this many seconds (a room that is still loading can
## differ for a moment; the next check catches it).
const AUD_RESYNC_GAP: float = 4.0
## Guest: seconds to wait before each try to get back in after the connection dropped. After the
## last one it gives up and goes back to its own audience (see "Staying in sync").
const RECONNECT_DELAYS: Array[float] = [2.0, 4.0, 8.0, 15.0, 15.0, 15.0, 15.0, 15.0]
## Host: a guest who dropped keeps their part of the shared audience (their streamer area, their
## viewers' looks) for this long, and is let back in without the popup if they return by the same
## name in that time. Seconds.
const AWAY_KEEP_S: float = 600.0
## Guest: chat lines kept while reconnecting, sent to the host once back in (older ones are dropped).
const HELD_CHAT_MAX: int = 100

## Settings everyone in the session shares (the presenter ones are added in _ready()).
const SHARED_BASE: Array[String] = ["screen_peer", "screen_tab_peer", "house_lights", "curtain_enabled", "curtain_sign", "curtain_color",
	"curtain_speed", "curtain_show_lights",
	# the Lakeside Campfire's fire, screen, hour and sky (rooms/campfire/campfire_room.gd):
	# with the "room" group shared everyone sits under the same sky (see _group_of)
	"camp_fire", "camp_screen", "camp_time", "camp_day_minutes", "camp_clouds", "camp_stars", "camp_aurora", "camp_mist",
	"camp_close_woods", "camp_autumn"]
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
## A "Web page (transparent)" avatar (My avatar) goes out over this colour (ScreenFeed tells the
## sender page; web/backdrop.html draws it). A podium showing such an avatar keys this colour on
## every PC, whatever that podium's own key colour says (presenter.gd, avatar_key).
const AVATAR_KEY_COLOR: Color = Color(0.0, 1.0, 0.0)
## Web addresses that only open on the PC that typed them (a local avatar app, the home network):
## a podium showing one is the host's alone, like a tab (see podium_warnings).
const LOCAL_URL_HOSTS: Array[String] = ["localhost", "127.", "0.0.0.0", "192.168.", "10.", "[::1]"]
## Curtain styles accepted from the network (same as EventBus.curtain_changed's style).
const CURTAIN_STYLES: Array[String] = ["normal", "instant", "reveal"]
## Sender of a reaction with a picture from its own Stream Core: seconds the reaction waits for the
## picture's first download to finish (it goes to the others along with the reaction). After that
## it goes without, and the other PCs show its emoji / word.
const REACTION_PICTURE_WAIT: float = 5.0
## Longest audience-looks setting accepted from the host, in characters (each is JSON text).
const LOOKS_MAX_CHARS: int = 200000
## Guest: where this PC keeps its copies of the host's silhouette pictures (AudienceStyle only takes
## pictures inside its PICTURE_DIR, user://silhouettes/): NET_LOOK_FILE % md5, plus a "_shape" copy.
const NET_LOOK_FILE: String = "user://silhouettes/net_%s.png"

# Session state below. Most of it only means something for one role; the comment says which.
## Host: each guest's own audience looks (peer id -> looks as _looks_from_wire makes them), for
## "Viewers keep their streamer's looks" (see "Each streamer's own looks").
var _guest_looks: Dictionary = {}
var _shared: Dictionary = {}            # setting key -> true
var _host_shares: Dictionary = {}       # guest: group -> bool, as the host last said (empty = all)
var _role: String = "off"               # "off" | "host" | "guest"
var _session_ms: int = 0                # Time.get_ticks_msec() when hosting / joining started (for DebugLog lines)
var _status: String = ""
var _error: bool = false
var _address: String = ""               # host: what guests type in; guest: where it connected
var _peers: Dictionary = {}             # peer id -> {"name": String, "cohost": bool}; the host is 1
var _nonces: Dictionary = {}            # host: peer id -> challenge bytes
## Host: wrong passwords per address: address -> {"count": int, "until": msec it may try again}.
## (Through the Cloudflare tunnel every guest comes from cloudflared's address, so there it works
## for everyone at once: a guesser also holds up real guests for a minute, but can't keep guessing.)
var _wrong: Dictionary = {}
## A short password (4 to 7 characters) that was already saved when the app started: it may still
## host, with a note. One typed in after the start needs MIN_PASSWORD characters.
var _old_password: String = ""
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
# guest: the "use Medium graphics" suggestion was dismissed (see get_info's suggest_medium)
var _medium_dismissed: bool = false
# seconds until this PC's camera may be sent again (CAMERA_SEND_GAP)
var _cam_wait: float = 0.0
var _last_cam: Transform3D
var _tunnel_pid: int = -1               # host: the cloudflared process
# host: the cloudflared log file the tunnel address is read from
var _tunnel_log: String = ""
# host: seconds left to find the tunnel address (-1 = not waiting)
var _tunnel_wait: float = -1.0
var _tunnel_warm: HTTPRequest           # host: one request through the new tunnel, so it's awake before guests use it
# guest: seconds until the next ping (PING_GAP)
var _ping_wait: float = 0.0
var _chat_out: Array = []               # guest: chat lines waiting for the next batch to the host
var _chat_wait: float = 0.0
var _rtt: float = 0.0                   # guest: seconds for a message to the host and back
## The host's live feed (its shared tab, through VDO.Ninja): a random stream name and key per
## session, only ever sent to guests who passed the password check.
var _live_id: String = ""
var _live_key: String = ""
var _live_on: bool = false              # guest: the host is sharing a tab right now
var _live_relay: bool = false           # guest: the host wants the feed relayed (addresses hidden)
var _live_hide: bool = false            # guest: the host has Hide my address on (told to the streamer once)
var _live_feed_on: bool = true          # guest: the host sends its shared tab (as opposed to only avatars)
## Whose shared tab is on everyone's big screen (setting screen_tab_peer, "" = the host's). That
## person's sender page publishes their own shared tab; everyone else's views it. Each person has
## their own stream name for it: the host's is _live_id, a guest's is _peers[id]["tab"] (made by
## the host, and only ever sent out while that guest is the one sharing).
var _live_from: int = 1                 # guest: the peer id whose tab is on the big screen (1 = host)
## Who holds the big screen remote (peer id, 1 = the host): host and guests (from the roster). See
## "Big screen remote".
var _remote_id: int = 1
var _remote_setting: bool = false
## Claimed podiums (see "Claimed podiums"): podium number -> {"owner": peer id (0 = the host's as
## usual), "locked": bool}. Host: the real table; guests: the host's copy (_net_podiums).
var _podiums: Dictionary = {}      # host: _set_remote / a holder's request is changing screen_tab_peer
var _live_from_name: String = ""        # guest: their name, for the sender page's messages
## This PC's sender page is sharing its OWN tab right now (not someone else's feed it's showing).
## From the sender page's status ("own"), via EventBus.capture_status_changed. A guest tells the
## host (_net_tab_sharing) so the others know whether there's anything to watch.
var _own_tab: bool = false
var _host_sources: Dictionary = {}      # guest: presenter source keys -> what the host said (before any silhouette stand-in)
var _live_quality: Dictionary = {}      # guest: the host's quality settings for the live feed and avatars
var _aud_shared: bool = false           # guest: the host shares its audience (this PC mirrors it)
var _roster_wait: float = -1.0          # host: send the whole roster to the guests in this long
## Pictures already sent, so each goes over once per session. Host: peer id -> {key: true}, where key
## is a reaction picture's "net:<md5>" or "look:" + a silhouette picture's; guest: {key: true} sent to the host.
var _pic_sent: Dictionary = {}
## Sender: reactions waiting for their picture's first download (see REACTION_PICTURE_WAIT):
## picture address -> {"list": [reaction Dictionaries], "wait": seconds left}.
var _pic_waiting: Dictionary = {}
# host: last synced-video id handed out (each new video gets the next number)
var _video_count: int = 0
## Host: the synced video. {id, url, ready: {peer id: true}, live (host's copy loaded), started, wait}
var _video: Dictionary = {}
## Guest: the host's video. {id, url, ready, state: [position, playing, time received in ms] or []}
var _guest_video: Dictionary = {}
## Host: each streamer's part of the shared audience, kept by name so it doesn't move when someone
## reconnects (a reconnecting guest gets a new peer id). The host is always 0.
## name key (_streamer_key) -> {"index": 1..MAX_GUESTS, "id": peer id (0 = away), "away": seconds away}
var _streamer_slots: Dictionary = {}
var _aud_check_wait: float = 0.0        # host: seconds until the next audience check
var _aud_resync_wait: float = 0.0       # guest: seconds until it may ask for the roster again
var _aud_resyncs: int = 0               # guest: rosters asked for again this session (shown in get_info)
## Guest: the first sync after joining (or a resync). {"total": things the host is sending,
## "got": things here so far, "done": the host's last one arrived} ({} = not syncing).
var _sync: Dictionary = {}
var _synced: bool = false               # guest: everything from the host has arrived and is shown
## Guest: getting back into the session after the connection dropped.
## {"host": the host's name, "try": tries so far, "wait": seconds to the next} ({} = not reconnecting)
var _rejoin: Dictionary = {}
var _chat_held: Array = []              # guest: this PC's chat while reconnecting (HELD_CHAT_MAX)
var _host_ended: bool = false           # guest: the host said it's stopping (_net_session_ended)
var _applying_pause: bool = false       # guest: applying the host's pause-to-react (see _net_react_pause)


## Builds the shared-key whitelist and hooks up SceneMultiplayer's signals (password step,
## peers joining and leaving) and the EventBus signals the session follows.
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
	var saved_pw := String(AppState.get_setting("together_password")).strip_edges()
	if saved_pw.length() >= OLD_MIN_PASSWORD and saved_pw.length() < MIN_PASSWORD:
		_old_password = saved_pw
	EventBus.room_requested.connect(_on_room_requested)
	EventBus.curtain_changed.connect(_on_curtain_changed)
	EventBus.react_pause_changed.connect(_on_react_pause)
	EventBus.reaction_play.connect(_on_reaction_play)
	EventBus.emote_ready.connect(_on_emote_ready)
	EventBus.file_prepared.connect(_on_file_prepared)
	EventBus.file_prepare_failed.connect(_on_file_prepare_failed)
	EventBus.file_progress.connect(_on_file_progress)
	EventBus.source_changed.connect(_on_source_changed)
	EventBus.capture_status_changed.connect(_on_capture_status)
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


## Only runs during a session (and while a guest is reconnecting): timers (video, tunnel, ping, chat
## batches, roster, popups, staying in sync), then this PC's camera to the others while it moves.
func _process(delta: float) -> void:
	_sync_tick(delta)
	if _role == "off":
		return             # (a guest waiting for its next reconnect try: nothing else to do)
	_video_timeout(delta)
	_tunnel_poll(delta)
	if _role == "guest" and _connected():
		_ping_wait -= delta
		if _ping_wait <= 0.0:
			_ping_wait = PING_GAP
			_net_ping.rpc_id(1, Time.get_ticks_msec())
		_chat_wait -= delta
		if _chat_wait <= 0.0 and not _chat_out.is_empty():
			_chat_wait = CHAT_BATCH_GAP
			_net_guest_chat_batch.rpc_id(1, _chat_out)
			_chat_out = []
		# chat from while the connection was down goes out a batch at a time once back in
		if _chat_out.is_empty() and not _chat_held.is_empty() and _aud_shared and _admitted:
			_chat_out = _chat_held.slice(0, CHAT_BATCH_MAX)
			_chat_held = _chat_held.slice(CHAT_BATCH_MAX)
	if _roster_wait >= 0.0:
		_roster_wait -= delta
		if _roster_wait < 0.0:
			_send_roster_to_guests()
	_pending_timeout(delta)
	_reaction_picture_timeout(delta)
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
	elif _role == "guest" and _connected():
		_net_guest_camera.rpc_id(1, x)


# ── Public API ───────────────────────────────────────────────
## {role, status, error, address, cohost, suggest_medium, host_live, peers: [{id, name, cohost, me}]}
func get_info() -> Dictionary:
	var me := multiplayer.get_unique_id() if _role != "off" else 0
	var peers: Array = []
	for id: int in _peers:
		# synced: the host's view of whether that guest has everything (true for the host itself)
		peers.append({"id": id, "name": String(_peers[id]["name"]), "cohost": bool(_peers[id]["cohost"]), "me": id == me,
			"synced": id == 1 or bool(_peers[id].get("synced", true)), "sync": int(_peers[id].get("sync", 100)),
			"remote": id == _remote_id, "asked": bool(_peers[id].get("asked", false))})
	var q := String(AppState.get_setting("graphics_quality"))
	# host, while a synced video waits to start: who has it ready (Source tab's File section)
	var vready: Array = []
	var vwait: Array = []
	if _role == "host" and not _video.is_empty() and not bool(_video.get("started", true)):
		for id: int in _peers:
			(vready if (_video["ready"] as Dictionary).has(id) else vwait).append(_peer_name(id))
	return {"video_ready": vready, "video_waiting": vwait, "role": _role, "status": _status, "error": _error, "address": _address, "cohost": _is_cohost(),
		"suggest_medium": _role == "guest" and _peers.size() > 0 and not _medium_dismissed and (q == "high" or q == "custom"),
		"host_live": is_host_live(), "shares": {"room": group_shared("room"), "curtain": group_shared("curtain"),
		"presenters": group_shared("presenters")}, "peers": peers, "pending": pending_guests(),
		"waiting": _role == "guest" and not _admitted, "host_name": _host_name,
		"syncing": _role == "guest" and _admitted and not _synced, "sync_progress": sync_progress(),
		"reconnecting": not _rejoin.is_empty(), "aud_resyncs": _aud_resyncs,
		"remote": _peer_name(_remote_id) if _role != "off" else "", "has_remote": has_remote(),
		"podiums": podium_list()}


## Host: who is waiting to be let in, [{id, name, host_ok, guest_ok}].
func pending_guests() -> Array:
	var list: Array = []
	for id: int in _pending:
		var p: Dictionary = _pending[id]
		list.append({"id": id, "name": String(p["name"]), "host_ok": bool(p["host_ok"]), "guest_ok": bool(p["guest_ok"])})
	return list


## "off" | "host" | "guest".
func get_role() -> String:
	return _role


## True for setting keys on the shared whitelist (SHARED_BASE + the shared presenter fields).
func is_shared(key: String) -> bool:
	return _shared.has(key)


## True when this PC may not change it: a guest who isn't a co-host, for a group the host shares.
## what: a setting key, "room" or "curtain".
## The big screen keys are the remote holder's instead (see "Big screen remote").
func is_locked(what: String) -> bool:
	if _role == "guest" and _is_screen(what):
		return not has_remote() and group_shared(_group_of(what))
	if _role == "guest" and my_podium() > 0 and what.begins_with("presenter_%d_" % my_podium()):
		return false          # (this PC's own claimed podium)
	return _role == "guest" and not _is_cohost() and _group_of(what) != "" and group_shared(_group_of(what))


## Which share group a setting key (or "room" / "curtain") belongs to; "" = not shared at all.
func _group_of(what: String) -> String:
	if what == "room" or what == "screen_peer" or what == "screen_tab_peer" or (what.begins_with("camp_") and _shared.has(what)):
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


## Host: {group: bool} from the together_share_* settings, sent to guests.
func _share_flags() -> Dictionary:
	var out := {}
	for g in SHARE_GROUPS:
		out[g] = bool(AppState.get_setting("together_share_" + g))
	return out


## The name others see: the Co-stream tab's name, else the profile name, else Host / Guest.
func display_name() -> String:
	var n := _clean_name(String(AppState.get_setting("together_name")))
	if n == "":
		n = _clean_name(AppState.get_profile())
	if n == "":
		n = "Host" if _role == "host" else "Guest"
	return n


# ── Hide my address ──
## Host: Hide my address is on and means something (listening on "This PC only" has no address to
## hide, and the tests use it). Guest: the host said it's on.
func hides_address() -> bool:
	if _role == "guest":
		return _live_hide
	return bool(AppState.get_setting("together_hide_address")) and String(AppState.get_setting("together_bind")) != "local"


## Where the host listens: together_bind, or "tunnel" while Hide my address is on.
func bind_mode() -> String:
	return "tunnel" if hides_address() else String(AppState.get_setting("together_bind"))


## Host: send the video (big screen and avatars) through VDO.Ninja's relay servers? The relay tick,
## or Hide my address.
func relay_on() -> bool:
	return bool(AppState.get_setting("together_live_relay")) or hides_address()


## What Hide my address covers right now, for the "Covered" list in the Co-stream tab and Esc menu:
## [[ok, text]] (ok false = a warning to act on).
func hide_checklist() -> Array:
	if not hides_address():
		return []
	var tunnel_ok := _cloudflared() != ""
	return [[tunnel_ok, "Joining goes through a one-off Cloudflare address: guests never see your real one." if tunnel_ok
			else "cloudflared.exe is missing: run tools\\get_tools.ps1 (or copy it next to the game) before hosting."],
		[true, "The big screen and everyone's avatars go through VDO.Ninja's relay servers."],
		[true, "Your address never shows on screen: Copy address puts it on the clipboard."],
		[true, "Troubleshooting logs swap addresses for <tags>."]]


## Co-stream tab "Host": checks the password, listens on together_port, and starts the tunnel when
## together_bind is "tunnel". "auto" listens on the Tailscale address if there is one, else 127.0.0.1.
func host() -> void:
	if _role != "off":
		return
	var pw := String(AppState.get_setting("together_password")).strip_edges()
	var short_ok := pw != "" and pw == _old_password
	if pw.length() < MIN_PASSWORD and not short_ok:
		_set_status("Pick a session password first (at least %d characters)." % MIN_PASSWORD, true)
		return
	var port := int(AppState.get_setting("together_port"))
	var ts := _tailscale_ip()
	var bind := bind_mode()
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
	_session_ms = Time.get_ticks_msec()
	DebugLog.note("net", "hosting: listen on %s, port %d, %s, version %s" % [bind, port, "Tailscale found" if ts != "" else "no Tailscale", _version()])
	_peers = {1: {"name": display_name(), "cohost": true, "avatar": _random_token(16), "keyed": _my_avatar_keyed()}}
	_streamer_slots.clear()
	_aud_check_wait = AUD_CHECK_GAP
	_remote_id = 1
	_podiums.clear()
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
	_set_status("Hosting. " + where + password_note())


## Co-stream tab "Join": connects to together_address. The password step follows in _on_host_auth.
## A click on Join stops any reconnecting first; the reconnect timer calls it with rejoining = true.
func join(rejoining: bool = false) -> void:
	if _role != "off":
		return
	if not rejoining:
		_stop_rejoin(true)
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
	_session_ms = Time.get_ticks_msec()
	DebugLog.note("net", "joining %s, version %s" % [url, _version()])   # (DebugLog hides the address)
	_peers.clear()
	_remote_id = 1
	_refused = ""
	_host_ended = false
	_rtt = 0.0
	_ping_wait = 0.5
	_address = url
	if not rejoining:
		_set_status("Connecting to the host...")


## Co-stream tab "Leave" / "Stop hosting".
func leave() -> void:
	if _role == "off":
		if not _rejoin.is_empty():
			_stop_rejoin(true, "Stopped reconnecting.")
		return
	_rejoin.clear()
	if _role == "host" and guest_count() > 0:
		# tell the guests first, so they don't take it for a dropped connection and try to reconnect;
		# a moment for the message to go out before the connection closes
		_to_guests("_net_session_ended", [])
		set_process(false)
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			if _role == "host":
				_close("Stopped hosting."))
		return
	_close("Left the session." if _role == "guest" else "Stopped hosting.")


## Guest: the host stopped hosting on purpose (see leave): no reconnecting when the connection closes.
@rpc("authority", "call_remote", "reliable")
func _net_session_ended() -> void:
	if _from_host():
		_host_ended = true


## " Your password is short ..." while hosting with an old short password, else "".
func password_note() -> String:
	var pw := String(AppState.get_setting("together_password")).strip_edges()
	if pw.length() < MIN_PASSWORD and pw == _old_password:
		return " Your password is short: pick one with at least %d characters before the next session." % MIN_PASSWORD
	return ""


## True when the password box holds something too short to host with.
func password_too_short() -> bool:
	var pw := String(AppState.get_setting("together_password")).strip_edges()
	return pw.length() < MIN_PASSWORD


## Host: let a guest change the room, curtain and other shared things too.
func set_cohost(peer_id: int, on: bool) -> void:
	if _role != "host" or peer_id == 1 or not _peers.has(peer_id):
		return
	_peers[peer_id]["cohost"] = on
	_send_roster()


## Host: send a guest away. They're told first, so they don't try to reconnect, and their part of
## the audience isn't kept for them.
func remove_peer(peer_id: int) -> void:
	if _role == "host" and peer_id != 1 and _peers.has(peer_id):
		_net_removed.rpc_id(peer_id, "The host removed you from the session.")
		for k: String in _streamer_slots.keys():
			if int(_streamer_slots[k]["id"]) == peer_id:
				_streamer_slots.erase(k)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _role == "host" and _peers.has(peer_id):
				_sm().disconnect_peer(peer_id)
				# (disconnecting a peer from this side doesn't always raise peer_disconnected here)
				if _peers.has(peer_id):
					_on_peer_disconnected(peer_id))


## Guest: the host removed this copy (see remove_peer): the session ends here, no reconnecting.
@rpc("authority", "call_remote", "reliable")
func _net_removed(reason: String) -> void:
	if _from_host():
		_refused = reason.left(200)


## Tests: the connection drops as if the network went away (the guest reconnects on its own).
func simulate_drop() -> void:
	if _role == "guest" and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		_on_server_disconnected()


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
		return "Different Stream Rooms versions: the host has %s, you have %s. Use the same version to co-stream." % [
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
## Host: a new connection arrived. Send it the password challenge (a random nonce), or a refusal.
func _on_peer_authenticating(id: int) -> void:
	if _role != "host":
		return
	# limits before any challenge: too many half-open connections, a full session, an address
	# that got the password wrong too often
	if _nonces.size() >= MAX_UNAUTHENTICATED:
		_sm().disconnect_peer.call_deferred(id)
		return
	var why := ""
	var wait_s := _locked_out(_peer_address(id))
	if wait_s > 0:
		why = "Too many wrong passwords. Try again in %d seconds." % wait_s
	elif guest_count() + _pending.size() + _hello_names.size() >= MAX_GUESTS:
		why = "The session is full (%d guests)." % MAX_GUESTS
	if why != "":
		_sm().send_auth(id, var_to_bytes({"t": "refused", "reason": why}))
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _role == "host":
				_sm().disconnect_peer(id))
		return
	var nonce := Crypto.new().generate_random_bytes(16)
	_nonces[id] = nonce
	_sm().send_auth(id, var_to_bytes({"t": "challenge", "nonce": nonce, "protocol": PROTOCOL, "version": _version()}))


## SceneMultiplayer's auth_callback: one message of the password step, on either side.
func _on_auth(id: int, data: PackedByteArray) -> void:
	var d: Variant = bytes_to_var(data)          # never decodes objects
	if not d is Dictionary:
		return
	if _role == "host":
		_on_hello(id, d)
	elif _role == "guest" and id == 1:
		_on_host_auth(d)


## Host: the guest's answer to the challenge ({t: "hello", name, protocol, version, proof}).
func _on_hello(id: int, d: Dictionary) -> void:
	if String(d.get("t", "")) != "hello" or not _nonces.has(id):
		return
	var nonce: PackedByteArray = _nonces[id]
	_nonces.erase(id)
	var why := check_hello(d, nonce, String(AppState.get_setting("together_password")), _version())
	if why == "" and guest_count() + _pending.size() + _hello_names.size() >= MAX_GUESTS:
		why = "The session is full (%d guests)." % MAX_GUESTS
	if why != "":
		if why == "Wrong session password.":
			_note_wrong(_peer_address(id))
		_sm().send_auth(id, var_to_bytes({"t": "refused", "reason": why}))
		DebugLog.note("net", "refused peer #%d from %s: %s (their version %s)" % [id, _peer_address(id), why, String(d.get("version", "?"))])
		EventBus.status_message.emit("Refused someone joining: " + why, true)
		# a moment for the reason to arrive before the connection closes
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _role == "host":
				_sm().disconnect_peer(id))
		return
	var n := _clean_name(String(d.get("name", "")))
	_hello_names[id] = n if n != "" else "Guest %d" % (_peers.size())
	_sm().complete_auth(id)


## Guests in the session now (not counting the host or anyone still joining).
func guest_count() -> int:
	return maxi(_peers.size() - 1, 0) if _role == "host" else 0


## Where a connection comes from ("" if unknown).
func _peer_address(id: int) -> String:
	var mp := multiplayer.multiplayer_peer
	if mp is WebSocketMultiplayerPeer:
		return (mp as WebSocketMultiplayerPeer).get_peer_address(id)
	return ""


## Seconds this address still has to wait after too many wrong passwords (0 = may try).
func _locked_out(address: String) -> int:
	var w: Variant = _wrong.get(address)
	if not w is Dictionary:
		return 0
	var left := int((w as Dictionary).get("until", 0)) - Time.get_ticks_msec()
	return ceili(left / 1000.0) if left > 0 else 0


## Host: counts a wrong password from this address; MAX_WRONG in a row locks it out for LOCKOUT_S.
func _note_wrong(address: String) -> void:
	var w: Dictionary = _wrong.get(address, {"count": 0, "until": 0})
	w["count"] = int(w["count"]) + 1
	if int(w["count"]) >= MAX_WRONG:
		w["count"] = 0
		w["until"] = Time.get_ticks_msec() + int(LOCKOUT_S * 1000.0)
		EventBus.status_message.emit("Several wrong passwords in a row: joining is paused for a minute.", true)
	_wrong[address] = w


## Guest: the host's challenge (answered with the proof) or its refusal (kept for the close message).
func _on_host_auth(d: Dictionary) -> void:
	match String(d.get("t", "")):
		"challenge":
			if int(d.get("protocol", -1)) != PROTOCOL or String(d.get("version", "")) != _version():
				_refused = "Different Stream Rooms versions: the host has %s, you have %s. Use the same version to co-stream." % [
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
	DebugLog.note("net", "password step failed for peer #%d (%s)" % [id, _role])
	_nonces.erase(id)
	if _role == "guest" and id == 1:
		_rejoin.clear()            # (a wrong password or a full session won't fix itself by retrying)
		# deferred: closing the connection inside Redot's own network callback crashes it
		_close.call_deferred(_refused if _refused != "" else "The host didn't let this copy in. Check the password.", true)


## Host: the password step passed. The guest is pending until both sides confirm (_maybe_admit).
func _on_peer_connected(id: int) -> void:
	if _role != "host":
		return
	DebugLog.note("net", "peer #%d connected from %s, waiting for both OKs" % [id, _peer_address(id)])
	var n := String(_hello_names.get(id, "Guest"))
	_hello_names.erase(id)
	# the password was right; now both people confirm before anything is shared. Someone the host
	# already let in who dropped and comes back by the same name (AWAY_KEEP_S) needs no new popup.
	var returning := _is_away(n)
	_pending[id] = {"name": n, "host_ok": auto_confirm or returning, "guest_ok": false, "wait": CONFIRM_TIMEOUT}
	_net_welcome.rpc_id(id, display_name())
	if returning:
		_set_status("%s is reconnecting." % n)
		return
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
	# tab: the stream name this guest's shared tab goes out under if the host puts it on the big screen
	var back := _is_away(who)
	_peers[id] = {"name": who, "cohost": false, "avatar": _random_token(16), "tab": _random_token(20), "sharing": false,
		"synced": false}
	_claim_streamer_slot(id, who)
	_send_roster()
	_update_audience_sharing()
	_send_everything(id)
	_set_status(("%s is back." if back else "%s joined.") % who)
	_warn_podiums()


## Host: a guest (or someone still waiting to be let in) left.
func _on_peer_disconnected(id: int) -> void:
	DebugLog.note("net", "peer #%d disconnected (%s)" % [id, _peer_name(id) if _peers.has(id) else "not in the session yet"])
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
	_pic_sent.erase(id)
	_release_streamer_slot(id)        # (before _guest_looks goes: their looks stay with their part)
	_guest_looks.erase(id)
	EventBus.net_peer_left.emit(id)
	_to_guests("_net_left", [id])
	if _remote_id == id:
		_set_remote(1)                # (the remote goes back to the host)
	for pn: int in _podiums.keys():
		if int(_podiums[pn].get("owner", 0)) == id:
			_free_podium(pn)
	_send_roster()
	_update_audience_sharing()
	_set_status("%s left. If they come back within %d minutes, their part of the audience is still there." % [n, int(AWAY_KEEP_S / 60.0)]
		if _sharing_audience() or bool(AppState.get_setting("together_shared_audience")) else "%s left." % n)


## Guest: the connection and password step are done; the host's welcome comes next.
func _on_connected() -> void:
	if _role != "guest":
		return
	DebugLog.note("net", "connected to the host, waiting for its hello")
	AppState.net_gate = _gate
	_last_cam = Transform3D()
	_admitted = false
	_host_name = ""
	set_process(true)
	_set_status("Connected. Waiting for the host to say hello...")


func _on_connection_failed() -> void:
	DebugLog.note("net", "connection failed (%s)%s" % [_role, ", while reconnecting" if not _rejoin.is_empty() else ""])
	if _role == "guest" and not _rejoin.is_empty():
		_rejoin_failed.call_deferred()
		return
	if _role == "guest":
		_close.call_deferred("Couldn't reach the host. Check the address, and that the host is hosting. A new Cloudflare tunnel can need a second try.", true)


func _on_server_disconnected() -> void:
	DebugLog.note("net", "host connection dropped after %s (ping was %d ms)%s" % [_session_age(), roundi(_rtt * 1000.0),
		", refused: " + _refused if _refused != "" else (", host stopped" if _host_ended else "")])
	# dropped (not sent away, not leaving): try to get back in, keeping the audience as it was
	if _role == "guest" and _refused == "" and not _host_ended and (_admitted or not _rejoin.is_empty()):
		_start_rejoin.call_deferred()
		return
	if _role == "guest":
		_close.call_deferred(_refused if _refused != "" else "The session ended (the host stopped, or the connection dropped).", _refused != "")


## Ends the session on this PC and resets every bit of session state. Call it deferred from network
## signals (see docs/MULTIPLAYER.md: closing inside SceneMultiplayer's poll crashes the engine).
## keep_audience (a guest reconnecting, _start_rejoin): the host's audience and looks stay on
## screen as they were instead of going back to this PC's own; _stop_rejoin clears them if it gives up.
func _close(message: String, is_error: bool = false, keep_audience: bool = false) -> void:
	# (checked before _role is reset below: a guest's "right host?" popup must close too)
	var was_waiting_guest := _role == "guest" and not _admitted
	if _role != "off":
		DebugLog.note("net", "session closed as %s after %s: %s" % [_role, _session_age(), message if message != "" else "(no message)"])
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var me := 1 if _role == "host" else 0
	for id: int in _peers:
		if id != me:
			EventBus.net_peer_left.emit(id)
	_role = "off"
	_peers.clear()
	_remote_id = 1
	_podiums.clear()
	_nonces.clear()
	_hello_names.clear()
	for id: int in _pending:
		EventBus.net_confirm_closed.emit(id)
	_pending.clear()
	if was_waiting_guest:
		EventBus.net_confirm_closed.emit(1)
	_host_name = ""
	_admitted = false
	_cams.clear()
	_video.clear()
	_guest_video.clear()
	_live_id = ""
	_live_key = ""
	_live_on = false
	_live_hide = false
	_live_from = 1
	_live_from_name = ""
	_chat_out.clear()
	_host_sources.clear()
	_emit_live()
	_roster_wait = -1.0
	_pic_sent.clear()
	_pic_waiting.clear()
	_guest_looks.clear()
	_streamer_slots.clear()
	_sync.clear()
	_synced = false
	_aud_resyncs = 0
	if not keep_audience:
		_rejoin.clear()
		_aud_shared = false
		_chat_held.clear()
		_clear_net_looks()
		_apply_streamer_looks({})
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
	var owned := _owned_podium_of(what)
	if owned > 0:
		_owner_change(owned, what, value)
		return false
	if _is_screen(what):
		# the big screen belongs to whoever holds the remote, not to the co-hosts
		if has_remote():
			_net_request.rpc_id(1, what, value)
		else:
			EventBus.status_message.emit("%s has the big screen remote. Ask for it in the Esc menu > Co-stream." % _peer_name(_remote_id), false)
		return false
	if _is_cohost():
		_net_request.rpc_id(1, what, value)
	else:
		EventBus.status_message.emit("The host controls this while you're a guest (Co-stream tab).", false)
	return false


## Host: passes shared settings on to the guests, and reacts to its own Co-stream tab settings.
func _on_setting_changed(key: String, value: Variant) -> void:
	if _role == "host" and _shared.has(key) and group_shared(_group_of(key)):
		_to_guests("_net_setting", [key, value])
	if _role == "host" and key.begins_with("together_share_"):
		_share_changed(key.trim_prefix("together_share_"))
	if _role == "guest" and not _applying and key.ends_with("_picture") and _podium_of(key) > 0 and _podium_of(key) == my_podium():
		_upload_podium_picture(my_podium(), String(value))
	if _role == "host" and key.begins_with("presenter_") and key.ends_with("_picture") and group_shared("presenters"):
		_send_picture(int(key.get_slice("_", 1)), -1)
	elif key == "graphics_quality" and _role == "guest":
		_emit_state()
	if (key == "together_shared_audience" or key == "together_audience_areas") and _role == "host":
		_update_audience_sharing()
	if AudienceStyle.LOOK_KEYS.has(key) and _sharing_audience():
		_send_looks()          # (the host saved new looks in its Stream Core)
	elif AudienceStyle.LOOK_KEYS.has(key) and _role == "guest" and _aud_shared:
		_send_own_looks()      # (this guest saved new looks in its own Stream Core)
	if key == "together_streamer_looks" and _role == "host":
		_update_streamer_looks()
	if key == "together_avatar_source":
		if _role == "host" and _peers.has(1):
			_peers[1]["keyed"] = _my_avatar_keyed()
			_send_roster()
		elif _role == "guest" and _admitted and _connected():
			_net_avatar_keyed.rpc_id(1, _my_avatar_keyed())
	if _role == "host" and key.begins_with("presenter_") and (key.ends_with("_source") or key.ends_with("_url") or key.ends_with("_on")):
		_warn_podiums(int(key.get_slice("_", 1)))
	if key.begins_with("together_screen_") or key in ["together_avatar_height", "together_avatar_fps", "together_avatar_kbps"]:
		if _role == "host":
			_emit_live()
			_to_guests("_net_live", [_live_info_for_guests()])
	# (screen_tab_peer: whose tab is on the big screen; a co-host can change it too, through the host)
	if key == "screen_tab_peer" and _role == "host" and not _remote_setting:
		# the host picked whose tab is on the big screen itself: the remote goes with it
		var to := 1
		for id: int in _peers:
			if id != 1 and String(_peers[id]["name"]) == String(value):
				to = id
		if to != _remote_id:
			_remote_id = to
			_send_roster()
	if (key == "together_live_feed" or key == "together_live_relay" or key == "together_hide_address" or key == "screen_tab_peer") and _role == "host":
		_emit_live()
		_to_guests("_net_live", [_live_info_for_guests()])


## Host: a room change goes to the guests (when the room group is shared).
func _on_room_requested(room_id: String) -> void:
	if _role == "host" and group_shared("room"):
		_to_guests("_net_room", [room_id])


## Host: the curtain goes to the guests (when the curtain group is shared).
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
	snap["react_paused"] = AppState.is_react_paused()
	return snap


## Guest: the host's state (from _snapshot) on joining, or one group's part when it's switched on.
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
	if snap.get("react_paused") is bool:
		_apply_react_pause(bool(snap["react_paused"]))
	var v: Variant = snap.get("video")
	if v is Dictionary and (v as Dictionary).get("id") is int and (v as Dictionary).get("url") is String:
		_guest_load_video(int(v["id"]), String(v["url"]))      # joined mid-video: catch up once loaded
	_sync_got()
	_emit_state()


## Guest: one shared setting changed on the host (checked by _setting_ok in _apply_setting).
@rpc("authority", "call_remote", "reliable")
func _net_setting(key: String, value: Variant) -> void:
	if _from_host():
		_apply_setting(key, value)


## Guest: which groups the host shares now.
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
## Returns false when nothing was sent (_send_everything counts what it sends).
func _send_picture(n: int, to: int) -> bool:
	if _role != "host":
		return false
	var path := String(AppState.get_setting(AppState.presenter_key(n, "picture"))).strip_edges()
	var bytes := PictureFile.read_file(path) if path != "" else PackedByteArray()
	if path != "" and bytes.is_empty():
		return false     # unreadable here: say nothing, the guests keep what they had
	var kind := PictureFile.kind_of(bytes) if not bytes.is_empty() else ""
	if to > 0:
		_net_picture.rpc_id(to, n, kind, bytes)
	else:
		_to_guests("_net_picture", [n, kind, bytes])
	return true


## Guest: presenter n's podium picture from the host (checked for type and size), or empty to clear it.
@rpc("authority", "call_remote", "reliable")
func _net_picture(n: int, kind: String, bytes: PackedByteArray) -> void:
	if not _from_host() or n < 1 or n > AppState.PRESENTER_COUNT or not group_shared("presenters"):
		return
	_sync_got()
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


## Guest: the host changed the room.
@rpc("authority", "call_remote", "reliable")
func _net_room(room_id: String) -> void:
	if _from_host():
		_apply_room(room_id)


## Guest: the host's curtain closed / opened.
@rpc("authority", "call_remote", "reliable")
func _net_curtain(closed: bool, style: String) -> void:
	if _from_host():
		_apply_curtain(closed, style)


## Guest: who is in the session ([{id, name, cohost, avatar}]). The first one means the host let us in.
@rpc("authority", "call_remote", "reliable")
func _net_roster(list: Array) -> void:
	if not _from_host():
		return
	var had_remote := _admitted and has_remote()
	_peers.clear()
	_remote_id = 1
	for p: Variant in list:
		if p is Dictionary and (p as Dictionary).get("id") is int:
			var av := String(p.get("avatar", ""))
			_peers[int(p["id"])] = {"name": _clean_name(String(p.get("name", ""))), "cohost": bool(p.get("cohost", false)),
				"avatar": av if _token_ok(av) else "", "keyed": bool(p.get("keyed", false)), "asked": bool(p.get("asked", false))}
			if bool(p.get("remote", false)):
				_remote_id = int(p["id"])
	if not _admitted:
		_admitted = true
		EventBus.net_confirm_closed.emit(1)
		if not _rejoin.is_empty():
			_rejoin.clear()
			_set_status("Reconnected to %s's session." % _host_name)
		else:
			_set_status("Joined %s's session. The host controls the room, curtain and presenters." % _host_name)
		_net_tab_sharing.rpc_id(1, _own_tab)    # (in case the host puts this PC's tab on the big screen)
		_net_avatar_keyed.rpc_id(1, _my_avatar_keyed())   # (podiums showing my avatar key it on every PC)
	if _admitted and has_remote() != had_remote:
		EventBus.status_message.emit("You have the big screen remote: what you show is on everyone's big screen." if has_remote()
			else "%s has the big screen remote now." % _peer_name(_remote_id), false)
	_refresh_sources()
	_emit_state()
	_emit_live()


## Guest: someone else left (their camera marker goes).
@rpc("authority", "call_remote", "reliable")
func _net_left(peer_id: int) -> void:
	if _from_host():
		EventBus.net_peer_left.emit(peer_id)


## Host: a co-host asks to change shared state. Applied here; the change then goes to everyone.
@rpc("any_peer", "call_remote", "reliable")
func _net_request(what: String, value: Variant) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id):
		return
	# the big screen (and pausing it for everyone) is the remote holder's; the rest is the co-hosts'
	var allowed := id == _remote_id if (_is_screen(what) or what == "react_pause") else bool(_peers[id]["cohost"])
	if not allowed and _podium_owner(_podium_of(what)) == id:
		allowed = _owner_value_ok(what, value, id)      # (their own claimed podium)
	if not allowed:
		return
	if what == "react_pause":
		if value is bool:
			AppState.set_react_paused(value)        # (goes to every guest from _on_react_pause)
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
		_remote_setting = true          # (a holder showing someone else's tab keeps the remote)
		AppState.set_setting(what, value)
		_remote_setting = false


## Guest: applies a host setting past the gate. A presenter source that only exists on the host's
## PC becomes a silhouette here (the host's value is kept in _host_sources).
func _apply_setting(key: String, value: Variant) -> void:
	if not _setting_ok(key, value):
		return
	if key.ends_with("_source"):
		_host_sources[key] = value
		value = _source_here(key, String(value))
	_applying = true
	AppState.set_setting(key, value)
	_applying = false


## Guest: changes to the host's room if it's a known one and not the current one.
func _apply_room(room_id: Variant) -> void:
	if not room_id is String or RoomCatalog.get_info(room_id) == null:
		return
	if room_id == String(AppState.get_setting("room_id")):
		return
	_applying = true
	AppState.request_room(room_id)
	_applying = false


## Guest: sets the curtain as the host has it.
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


## The big screen loaded the synced video and stopped on its first frame: say we're ready.
func _on_file_prepared(input: String) -> void:
	if _role == "host" and not _video.is_empty() and input == String(_video["url"]) and not bool(_video["live"]):
		_video["live"] = true
		_mark_ready(1)
	elif _role == "guest" and not _guest_video.is_empty() and input == String(_guest_video["url"]):
		_guest_video["ready"] = true
		_net_video_ready.rpc_id(1, int(_guest_video["id"]))
		_apply_video_state()      # (a late joiner catches up with the last position it heard)


## The synced video didn't load here. Host: stop it for everyone. Guest: tell the host.
func _on_file_prepare_failed(input: String, message: String) -> void:
	if _role == "host" and not _video.is_empty() and input == String(_video["url"]):
		_set_status("The video didn't load here: " + message, true)
		_video.clear()
		_to_guests("_net_video_stop", [_video_count])
	elif _role == "guest" and not _guest_video.is_empty() and input == String(_guest_video["url"]):
		_net_video_failed.rpc_id(1, int(_guest_video["id"]), message.left(200))


## Host: this PC (peer id; 1 = the host) has the video ready. Starts when everyone has.
func _mark_ready(peer_id: int) -> void:
	_video["ready"][peer_id] = true
	_emit_state()            # (the Source tab shows who's ready)
	for id: int in _peers:
		if not _video["ready"].has(id):
			return
	_start_video()


## Host: after READY_TIMEOUT seconds the video starts without whoever is still loading.
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


## Host: play from 0 here and on every guest at once.
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


## Host: the big screen's source changed (EventBus.source_changed).
func _on_source_changed(mode: String) -> void:
	if _role == "host":
		_to_guests("_net_live", [_live_info_for_guests()])     # sharing a tab started / stopped
	# the host's screen moved on from the synced video (Stop, another source): guests stop too
	if _role == "host" and bool(_video.get("live", false)) and mode != "file":
		_to_guests("_net_video_stop", [int(_video["id"])])
		_video.clear()


## Host: a guest has video `id` loaded and paused on its first frame.
@rpc("any_peer", "call_remote", "reliable")
func _net_video_ready(id: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(from) or _video.is_empty() or id != int(_video["id"]):
		return
	if bool(_video["started"]):
		return       # a late joiner: the next position update brings it along
	_mark_ready(from)


## Host: a guest couldn't load video `id`.
@rpc("any_peer", "call_remote", "reliable")
func _net_video_failed(id: int, message: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(from) or _video.is_empty() or id != int(_video["id"]):
		return
	EventBus.status_message.emit("%s couldn't load the video: %s" % [_peer_name(from), message.left(200)], true)
	if not bool(_video["started"]):
		_mark_ready(from)        # don't keep everyone waiting


## Guest: the host wants everyone to load this web link.
@rpc("authority", "call_remote", "reliable")
func _net_video_load(id: int, url: String) -> void:
	if _from_host():
		_guest_load_video(id, url)


## Guest: where the host's video is (seconds) and whether it plays. ScreenFeed only seeks when the
## difference is bigger than its SYNC_TOLERANCE_S.
@rpc("authority", "call_remote", "reliable")
func _net_video_state(id: int, position: float, playing: bool) -> void:
	if not _from_host() or _guest_video.is_empty() or id != int(_guest_video["id"]):
		return
	_guest_video["state"] = [position, playing, Time.get_ticks_msec()]
	_apply_video_state()


## Guest: the host stopped the synced video.
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


## Round trip to the host in seconds: a running average of the ping RPCs (see _net_pong).
func _rtt_s() -> float:
	return _rtt


## How long this session has run, "3m 12s" (DebugLog lines about drops).
func _session_age() -> String:
	@warning_ignore("integer_division")
	var secs := (Time.get_ticks_msec() - _session_ms) / 1000
	@warning_ignore("integer_division")
	return "%dm %02ds" % [secs / 60, secs % 60]


## Guest: the same round trip, for DebugLog's "still alive" line (0 = not measured yet).
func ping_seconds() -> float:
	return _rtt


## Host: a guest's ping; sent straight back.
@rpc("any_peer", "call_remote", "reliable")
func _net_ping(sent_ms: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role == "host" and _peers.has(id):
		_net_pong.rpc_id(id, sent_ms)


## Guest: the ping came back; _rtt is a running average (70% old, 30% new).
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


## Host: tells guests whether they mirror the audience, sets the streamer areas (one per person
## when together_audience_areas is on), and sends the roster soon after.
func _update_audience_sharing() -> void:
	if _role != "host":
		return
	var on := bool(AppState.get_setting("together_shared_audience"))
	_to_guests("_net_aud_mode", [on])
	var areas := _streamer_area_count() if on and bool(AppState.get_setting("together_audience_areas")) else 0
	AudienceManager.set_streamer_areas(areas)
	if on:
		_roster_wait = 0.1
		_send_looks()
	_update_streamer_looks()


## Whose viewer: 0 = the host, then each guest's own number, kept by name for the whole session
## (_streamer_slots), so a guest who reconnects (new peer id) keeps their part of the audience.
func _streamer_index(peer_id: int) -> int:
	if peer_id == 1:
		return 0
	for k: String in _streamer_slots:
		if int(_streamer_slots[k]["id"]) == peer_id:
			return int(_streamer_slots[k]["index"])
	return 0


## The current room id (the shared-audience messages carry it: a roster only fits its own room).
func _room() -> String:
	return String(AppState.get_setting("room_id"))


# The _on_aud_* handlers pass AudienceManager's changes to the guests while the audience is shared.
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


## Host: the whole seating (AudienceManager.get_roster) to every guest.
func _send_roster_to_guests() -> void:
	if _sharing_audience():
		_to_guests("_net_aud_roster", [_room(), AudienceManager.get_roster()])
		var res := AudienceManager.wire_reserved()      # (the reserved seats go along: see "Reserved seats")
		_to_guests("_net_aud_reserved", [String(res["room"]), res["list"]])


## Guest: this PC's chat goes to the host's audience (its own chat windows keep showing it).
func _on_local_chat(msg: Dictionary) -> void:
	var holding := _role == "off" and not _rejoin.is_empty()      # (reconnecting: keep it for later)
	if (_role != "guest" and not holding) or not _aud_shared or bool(msg.get("system", false)) or bool(msg.get("history", false)):
		return
	var out := {}
	for k in ["name", "username", "platform", "user_id", "color", "text", "title", "avatar", "reply_to", "reply_quote", "tint"]:
		out[k] = String(msg.get(k, "")).left(500)
	# the platform's link: Stream Core's own copy (http://127.0.0.1...) only exists on this PC
	out["avatar"] = _web_avatar(msg)
	out["timestamp"] = float(msg.get("timestamp", Time.get_unix_time_from_system()))
	out["emotes"] = msg.get("emotes", []) if msg.get("emotes") is Array else []
	if holding:
		_chat_held.append(out)
		if _chat_held.size() > HELD_CHAT_MAX:
			_chat_held.pop_front()
	elif _chat_out.size() < CHAT_BATCH_MAX:
		_chat_out.append(out)


## Guest: a chatter's picture changed (or they were hidden): pass it to the host's audience.
func _on_local_user(info: Dictionary) -> void:
	if _role == "guest" and _aud_shared:
		_net_guest_user.rpc_id(1, {"platform": String(info.get("platform", "")), "user_id": String(info.get("user_id", "")),
			"avatar": _web_avatar(info), "hidden": bool(info.get("hidden", false))})


## The https picture link from a chat message or user update ("" if it only has a local one).
func _web_avatar(info: Dictionary) -> String:
	var web := String(info.get("avatar_web", ""))
	if web == "":
		web = String(info.get("avatar", ""))
	return web.left(500) if web.begins_with("https://") else ""


## Unused since chat goes in batches. Kept so the call list stays the same as 2026.10.4's
## (removing an RPC changes it). Together already turns away any PC whose version string
## (project.godot application/config/version) differs, so from 2026.11.1 on this could go.
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_chat(msg: Dictionary) -> void:
	_guest_chat_from(multiplayer.get_remote_sender_id(), msg)


## Host: a guest's batch of chat lines (see CHAT_BATCH_GAP).
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_chat_batch(list: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	for msg: Variant in list.slice(0, CHAT_BATCH_MAX):
		if msg is Dictionary:
			_guest_chat_from(id, msg)


## Host: one chat line from guest `id`, rebuilt from plain, length-capped values (it comes from
## another PC) and seated in the shared audience tagged with that guest's streamer index.
func _guest_chat_from(id: int, msg: Dictionary) -> void:
	if not _sharing_audience() or not _peers.has(id):
		return
	var clean := {}
	for k in ["name", "username", "platform", "user_id", "color", "text", "title", "reply_to", "reply_quote", "tint"]:
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


## Host: a guest's chatter picture change for the shared audience (https pictures only).
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_user(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not _sharing_audience() or not _peers.has(id):
		return
	var avatar := String(info.get("avatar", ""))
	var hidden := bool(info.get("hidden", false))
	if hidden or avatar.begins_with("https://"):
		AudienceManager.update_user({"platform": String(info.get("platform", "")), "user_id": String(info.get("user_id", "")),
			"avatar": "" if hidden else avatar.left(500), "hidden": hidden})


## Guest: the host started / stopped sharing its audience; this PC mirrors it or seats its own again.
@rpc("authority", "call_remote", "reliable")
func _net_aud_mode(shared: bool) -> void:
	if _from_host():
		_aud_shared = shared
		AudienceManager.set_mirror(shared)
		if not shared:
			_clear_net_looks()     # (this PC's own audience, with its own looks again)
			_apply_streamer_looks({})
		else:
			_send_own_looks()      # (the host uses them if "Viewers keep their streamer's looks" is on)
		_emit_state()


# ── Reserved seats ──
## In a shared audience the host does the seating, so the host's reserved seats (AudienceManager
## "Reserved seats") count for everyone. Guests see them on their seating chart and can reserve the
## seat of a chatter sitting in it, or free one they reserved; the host's PC does it and says so.

## Guest: reserve (on) or free the seat at this slot of the room shown, on the host's PC.
func ask_reserve(slot: int, on: bool) -> void:
	if _role == "guest" and _admitted and _connected():
		_net_reserve_ask.rpc_id(1, AudienceManager.seats_room(), slot, on)


## Host: a guest's ask_reserve. Reserving works for any seat with someone in it; freeing only for a
## seat that guest reserved (or any, for a co-host).
@rpc("any_peer", "call_remote", "reliable")
func _net_reserve_ask(room: String, slot: int, on: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id) or not _sharing_audience() or room != AudienceManager.seats_room():
		return
	var guest := _peer_name(id)
	var who := ""
	if on:
		who = AudienceManager.reserve_seat(slot, guest)
		if who != "":
			EventBus.status_message.emit("%s reserved a seat for %s." % [guest, who], false)
	else:
		var r := AudienceManager.get_reservation(slot)
		if not r.is_empty() and (String(r["by"]) == guest or bool(_peers[id]["cohost"])):
			who = AudienceManager.unreserve_seat(slot)
			if who != "":
				EventBus.status_message.emit("%s freed %s's reserved seat." % [guest, who], false)
	if who == "":
		_net_reserve_refused.rpc_id(id, "Only seats with someone in them can be reserved." if on
			else "Only the host frees seats that someone else reserved.")


## Guest: the host didn't do what ask_reserve asked (why, for the message line).
@rpc("authority", "call_remote", "reliable")
func _net_reserve_refused(why: String) -> void:
	if _from_host():
		EventBus.status_message.emit(why.left(120), false)


## Guest: the host's reserved seats for its room (AudienceManager.wire_reserved).
@rpc("authority", "call_remote", "reliable")
func _net_aud_reserved(room: String, list: Array) -> void:
	if _from_host() and _aud_shared:
		AudienceManager.mirror_reserved(room, list)


# The _net_aud_* RPCs below hand the host's seating to AudienceManager's mirror_* functions.
@rpc("authority", "call_remote", "reliable")
func _net_aud_roster(room: String, list: Array) -> void:
	if _from_host() and _aud_shared:
		AudienceManager.mirror_roster(room, list)
		_sync_got()


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


# ── Audience looks ───────────────────────────────────────────
## While the host shares its audience, guests also show the host's looks: its bubbles and
## silhouettes (Stream Core's Audience looks page, AudienceStyle.LOOK_KEYS), custom silhouette
## pictures included, so every stream shows the same audience. A guest's own looks settings are
## never changed (AudienceStyle.net_looks sits on top of them), so they're back after the session.
## Pictures are named by their bytes' MD5 ("net:<md5>"), each sent once per guest per session.

## Host: its looks to one guest (peer id) or all of them (-1): the silhouette pictures they don't
## have yet first, then the settings with each picture's file swapped for its "net:<md5>" name.
## Called when the audience starts being shared, when a guest joins, and when the looks change.
func _send_looks(to: int = -1) -> void:
	if not _sharing_audience():
		return
	var looks := {}
	for k: String in AudienceStyle.LOOK_KEYS:
		looks[k] = String(AppState.get_setting(k))
	var pictures := {}          # "net:<md5>" -> [picture png, its "_shape" png]
	looks = _looks_to_wire(looks, pictures)
	for id: int in _peers:
		if id == 1 or (to > 0 and id != to):
			continue
		_give_look_pictures(id, pictures)
		_net_looks.rpc_id(id, looks)


## A set of looks (LOOK_KEYS key -> text) made ready to send: each custom silhouette picture file is
## swapped for its "net:<md5>" name, and its bytes are added to `pictures` ("net:<md5>" -> [png,
## shape png]) for _give_look_pictures. Used for the host's looks (_send_looks), a guest's own looks
## going to the host (_send_own_looks) and every streamer's looks (_update_streamer_looks).
static func _looks_to_wire(looks: Dictionary, pictures: Dictionary) -> Dictionary:
	return _map_figures(looks, func(f: Dictionary) -> Dictionary:
		var file := String(f.get("file", ""))
		if String(f.get("shape", "")) != "custom" or not file.begins_with(AudienceStyle.PICTURE_DIR):
			return f
		var png := PictureFile.read_file(file)
		var shape := PictureFile.read_file(file.replace(".png", "_shape.png"))
		if png.is_empty() or shape.is_empty():
			f["file"] = ""
			f["shape"] = "classic"      # (a picture that's gone here: the classic bust there too)
			return f
		var key := _picture_key(png)
		# an animated GIF's frames go along (AudienceStyle.anim_sheet / anim_info_file), else empty
		var sheet := PictureFile.read_file(AudienceStyle.anim_sheet(file))
		var info := FileAccess.get_file_as_string(AudienceStyle.anim_info_file(file)) if not sheet.is_empty() else ""
		pictures[key] = [png, shape, sheet if info != "" else PackedByteArray(), info]
		f["file"] = key
		return f)


## Sends silhouette pictures (from _looks_to_wire) to one PC unless it has them already: the host
## to a guest (_net_look_picture), a guest to the host (_net_guest_look_picture, peer 1).
func _give_look_pictures(id: int, pictures: Dictionary) -> void:
	if not _pic_sent.has(id):
		_pic_sent[id] = {}
	for key: String in pictures:
		if not (_pic_sent[id] as Dictionary).has("look:" + key):
			_pic_sent[id]["look:" + key] = true
			if _role == "host":
				_net_look_picture.rpc_id(id, key, pictures[key][0], pictures[key][1], pictures[key][2], pictures[key][3])
			else:
				_net_guest_look_picture.rpc_id(1, key, pictures[key][0], pictures[key][1], pictures[key][2], pictures[key][3])


## Every silhouette style inside a set of looks (the main one in audience_silhouette and each saved
## one in audience_saved_styles), passed through fix (a style -> the style to keep), as a new set.
## The host swaps picture files for "net:<md5>" names with it, a guest swaps them back for its copies.
static func _map_figures(looks: Dictionary, fix: Callable) -> Dictionary:
	var out := looks.duplicate()
	var main: Variant = _parse_json(String(looks.get("audience_silhouette", "")))
	if main is Dictionary:
		out["audience_silhouette"] = JSON.stringify(fix.call(main))
	var saved: Variant = _parse_json(String(looks.get("audience_saved_styles", "")))
	if saved is Dictionary and (saved as Dictionary).get("silhouette") is Dictionary:
		var figs: Dictionary = saved["silhouette"]
		for look_name: Variant in figs.keys():
			if figs[look_name] is Dictionary:
				figs[look_name] = fix.call(figs[look_name])
		out["audience_saved_styles"] = JSON.stringify(saved)
	return out


## JSON text -> its value (null for blank text, without the parser's error line).
static func _parse_json(text: String) -> Variant:
	return JSON.parse_string(text) if text.strip_edges() != "" else null


## Guest: one of the host's silhouette pictures (a looks message that uses it follows). Kept as
## NET_LOOK_FILE (and its "_shape" copy), where AudienceStyle reads pictures from.
@rpc("authority", "call_remote", "reliable")
func _net_look_picture(key: String, png: PackedByteArray, shape: PackedByteArray, sheet: PackedByteArray, info: String) -> void:
	if _from_host():
		_save_look_picture(key, png, shape, sheet, info)
		_sync_got()


## Host: one of a guest's own silhouette pictures (for "Viewers keep their streamer's looks"; the
## guest's looks follow in _net_guest_looks). Kept the same way as the host's pictures on a guest.
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_look_picture(key: String, png: PackedByteArray, shape: PackedByteArray, sheet: PackedByteArray, info: String) -> void:
	if _role == "host" and _peers.has(multiplayer.get_remote_sender_id()):
		_save_look_picture(key, png, shape, sheet, info)


## A silhouette picture from another PC, checked (its name must be its own MD5, both files PNGs
## within PictureFile's limits), then written as NET_LOOK_FILE and its "_shape" copy. sheet / info:
## an animated GIF's frames (a WebP sheet and its {"frames", "delays"} JSON, AudienceStyle.anim_sheet),
## or empty for a still picture; a sheet that fails the checks is dropped and the first frame stays.
func _save_look_picture(key: String, png: PackedByteArray, shape: PackedByteArray, sheet: PackedByteArray = PackedByteArray(), info: String = "") -> void:
	if not _picture_ok(key, png) or PictureFile.kind_of(png) != "png" \
			or PictureFile.kind_of(shape) != "png" or shape.size() > PictureFile.MAX_BYTES or PictureFile.too_big(shape):
		return
	var path := NET_LOOK_FILE % key.substr(EmoteCache.NET_PREFIX.length())
	DirAccess.make_dir_recursive_absolute(AudienceStyle.PICTURE_DIR)
	var files: Array = [[path, png], [path.replace(".png", "_shape.png"), shape]]
	DirAccess.remove_absolute(AudienceStyle.anim_sheet(path))
	DirAccess.remove_absolute(AudienceStyle.anim_info_file(path))
	if _anim_ok(sheet, info):
		files.append([AudienceStyle.anim_sheet(path), sheet])
		files.append([AudienceStyle.anim_info_file(path), info.to_utf8_buffer()])
	for pair: Array in files:
		var f := FileAccess.open(String(pair[0]), FileAccess.WRITE)
		if f != null:
			f.store_buffer(pair[1] as PackedByteArray)
			f.close()


## An animated silhouette from another PC is usable: a WebP sheet within PictureFile's limits and
## info naming 2..ANIM_MAX_FRAMES frames with a number for each delay.
static func _anim_ok(sheet: PackedByteArray, info: String) -> bool:
	if sheet.is_empty() or info.length() > 4000 or sheet.size() > PictureFile.MAX_BYTES \
			or PictureFile.kind_of(sheet) != "webp" or PictureFile.too_big(sheet):
		return false
	var v: Variant = JSON.parse_string(info)
	if not v is Dictionary or not (v as Dictionary).get("delays") is Array:
		return false
	var n := int((v as Dictionary).get("frames", 0))
	var delays: Array = (v as Dictionary)["delays"]
	if n < 2 or n > AudienceStyle.ANIM_MAX_FRAMES or delays.size() != n:
		return false
	for d: Variant in delays:
		if not (d is float or d is int):
			return false
	return true


## Guest: the host's looks (see _send_looks). Shown while this PC mirrors the host's audience.
@rpc("authority", "call_remote", "reliable")
func _net_looks(looks: Dictionary) -> void:
	if not _from_host() or not _aud_shared:
		return
	_apply_net_looks(_looks_from_wire(looks))
	_sync_got()


## Looks that came over the network, made safe to show here: only LOOK_KEYS, length-capped, and each
## "net:<md5>" picture name swapped for this PC's copy (or the classic bust when it didn't come).
## Never a path from the other PC.
static func _looks_from_wire(looks: Dictionary) -> Dictionary:
	var clean := {}
	for k: String in AudienceStyle.LOOK_KEYS:
		clean[k] = String(looks.get(k, "")).left(LOOKS_MAX_CHARS)
	return _map_figures(clean, func(f: Dictionary) -> Dictionary:
		var file := String(f.get("file", ""))
		var here := NET_LOOK_FILE % file.substr(EmoteCache.NET_PREFIX.length()) if _is_picture_key(file) else ""
		if here != "" and FileAccess.file_exists(here):
			f["file"] = here
		elif String(f.get("shape", "")) == "custom" or file != "":
			f["file"] = ""
			f["shape"] = "classic"
		return f)


## Guest: shows these looks (AudienceStyle.net_looks; {} = this PC's own again). Tells the audience
## to redraw with a setting_changed for each look setting that now reads differently (the same
## signal a change in Stream Core gives; AudienceView and the bubbles read the looks through
## AudienceStyle, and the values in AppState stay this PC's own).
func _apply_net_looks(looks: Dictionary) -> void:
	var before := {}
	for k: String in AudienceStyle.LOOK_KEYS:
		before[k] = AudienceStyle.look_setting(k)
	AudienceStyle.net_looks = looks
	for k: String in AudienceStyle.LOOK_KEYS:
		if AudienceStyle.look_setting(k) != String(before[k]):
			EventBus.setting_changed.emit(k, AppState.get_setting(k))


## Guest: back to this PC's own looks (the session ended, or the host stopped sharing its audience).
func _clear_net_looks() -> void:
	if not AudienceStyle.net_looks.is_empty():
		_apply_net_looks({})


# ── Each streamer's own looks ────────────────────────────
## "Viewers keep their streamer's looks" (together_streamer_looks, host's Co-stream tab): in the one
## shared audience, each chatter is drawn in the looks of the streamer whose chat they came from. A
## guest sends its own looks (from its own Stream Core) to the host; the host keeps them per guest
## and sends every guest the whole table, streamer index -> looks (AudienceStyle.streamer_looks).
## The host's own viewers (index 0) need no entry: they get the main looks, which are the host's
## on every PC.

## Guest: this PC's own looks (and their pictures) to the host. Sent when the host starts sharing its
## audience and each time this PC's Stream Core changes them; the host only uses them while the
## option is on.
func _send_own_looks() -> void:
	if _role != "guest" or not _aud_shared:
		return
	var looks := {}
	for k: String in AudienceStyle.LOOK_KEYS:
		looks[k] = String(AppState.get_setting(k))
	var pictures := {}
	looks = _looks_to_wire(looks, pictures)
	_give_look_pictures(1, pictures)
	_net_guest_looks.rpc_id(1, looks)


## Host: a guest's own looks (see _send_own_looks).
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_looks(looks: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id):
		return
	_guest_looks[id] = _looks_from_wire(looks)
	_update_streamer_looks()


## Host: works out the table (streamer index -> looks) and shows it here and on every guest; an
## empty table while the option or the shared audience is off. Called when a guest's looks arrive,
## someone joins or leaves, and the option or the shared audience is switched.
func _update_streamer_looks() -> void:
	if _role != "host":
		return
	var table := {}
	if _sharing_audience() and bool(AppState.get_setting("together_streamer_looks")):
		for looks_of: Array in _kept_guest_looks():
			table[int(looks_of[0])] = looks_of[1]
	_apply_streamer_looks(table)
	var wire := {}
	var pictures := {}
	for i: int in table:
		wire[i] = _looks_to_wire(table[i], pictures)
	for id: int in _peers:
		if id != 1:
			_give_look_pictures(id, pictures)
			_net_streamer_looks.rpc_id(id, wire)


## Guest: every streamer's looks from the host (see _update_streamer_looks).
@rpc("authority", "call_remote", "reliable")
func _net_streamer_looks(table: Dictionary) -> void:
	if not _from_host():
		return
	var clean := {}
	if _aud_shared:
		for i: Variant in table:
			if i is int and int(i) >= 1 and int(i) <= MAX_GUESTS and table[i] is Dictionary:
				clean[int(i)] = _looks_from_wire(table[i])
	_apply_streamer_looks(clean)


## Shows a table of streamer looks here (AudienceStyle.streamer_looks; {} = off) and redraws the
## audience: AudienceView redraws silhouettes and bubbles on an "audience_style_groups" change.
func _apply_streamer_looks(table: Dictionary) -> void:
	if table.is_empty() and AudienceStyle.streamer_looks.is_empty():
		return
	AudienceStyle.streamer_looks = table
	AudienceStyle.streamer_looks_version += 1
	EventBus.setting_changed.emit("audience_style_groups", AppState.get_setting("audience_style_groups"))


# ── Live feed ────────────────────────────────────────────────
## Host: the sender page publishes its shared tab under _live_id (VDO.Ninja, peer to peer).
## Guests: their sender page views it and hands it to their game like their own shared tab.
## "id" is the stream name of whoever's tab is on the big screen ("from" = their peer id, 1 = the host).
func _live_info_for_guests() -> Dictionary:
	var pub := _tab_publisher()
	var sharing := bool(AppState.get_setting("together_live_feed")) and _is_sharing(pub)
	# the session's stream name and key always go along (the avatars use the key too); "live" says
	# whether the big screen is being shared right now
	return {"id": _tab_token(pub), "key": _live_key, "live": sharing,
		"from": pub, "from_name": _peer_name(pub),
		"feed_on": bool(AppState.get_setting("together_live_feed")), "relay": relay_on(),
		"hide": hides_address(), "quality": _quality()}


## Host: the peer id whose shared tab is on the big screen: the guest named in screen_tab_peer
## (set in the Co-stream tab), or 1 (the host) when it's "" or that person isn't in the session.
func _tab_publisher() -> int:
	var want := String(AppState.get_setting("screen_tab_peer"))
	if want == "":
		return 1
	for id: int in _peers:
		if id != 1 and String(_peers[id]["name"]) == want:
			return id
	return 1


## Host: the stream name a person's shared tab goes out under (the host's own is _live_id).
func _tab_token(id: int) -> String:
	if id == 1 or not _peers.has(id):
		return _live_id
	return String(_peers[id].get("tab", ""))


## Host: is this person sharing their own tab in their sender page right now?
func _is_sharing(id: int) -> bool:
	if id == 1:
		return _own_tab
	return _peers.has(id) and bool(_peers[id].get("sharing", false))


## The sender page's status (ScreenFeed passes it on): notices when this PC starts / stops sharing
## its own tab. "own" is missing from an old cached sender page: then any share counts.
func _on_capture_status(info: Dictionary) -> void:
	var own := bool(info.get("connected", false)) and bool(info.get("own", info.get("capturing", false)))
	if own == _own_tab:
		return
	_own_tab = own
	if _role == "host":
		_emit_live()
		_to_guests("_net_live", [_live_info_for_guests()])
	elif _role == "guest" and _admitted:
		_net_tab_sharing.rpc_id(1, own)


## Guest -> host: this guest started / stopped sharing its own tab. Matters while the host has put
## that guest's tab on the big screen (the others then start or stop watching it).
@rpc("any_peer", "call_remote", "reliable")
func _net_tab_sharing(on: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id):
		return
	_peers[id]["sharing"] = on
	if _tab_publisher() == id:
		_emit_live()
		_to_guests("_net_live", [_live_info_for_guests()])


## Guest: the host's live-feed info changed (see _live_info_for_guests).
@rpc("authority", "call_remote", "reliable")
func _net_live(info: Dictionary) -> void:
	if _from_host():
		_apply_live(info)


## Guest: keeps the host's live-feed info (bad stream names / keys are dropped) and tells the sender page.
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
	var hide := bool(info.get("hide", false))
	if hide and not _live_hide:
		EventBus.status_message.emit("This co-stream hides everyone's address.", false)
	_live_hide = hide
	_live_feed_on = bool(info.get("feed_on", true))
	_live_from = int(info.get("from", 1)) if info.get("from") is int else 1
	_live_from_name = _clean_name(String(info.get("from_name", "")))
	_live_quality = info.get("quality", {}) if info.get("quality") is Dictionary else {}
	_refresh_sources()
	_emit_live()
	_emit_state()


## Tells ScreenFeed (and through it the sender page) what to do with VDO.Ninja: publish (host),
## view (guest) or nothing. Format in EventBus.live_feed_changed.
## Whoever's tab is on the big screen publishes; everyone else views it. "auto": the sender page
## starts watching without a "Watch" click (the host picked the guest's tab, so the host's page
## follows; a guest's page waits for its first click, then keeps following every switch).
## "from_name": whose tab it is ("" = the host's), for the page's messages.
func _emit_live() -> void:
	var info := {"role": "off", "id": "", "key": "", "live": false, "relay": false}
	if _role == "host" and bool(AppState.get_setting("together_live_feed")) and _live_id != "":
		var pub := _tab_publisher()
		var relay := relay_on()
		if pub == 1:
			info = {"role": "publish", "id": _live_id, "key": _live_key, "live": true, "relay": relay}
		else:
			info = {"role": "view", "id": _tab_token(pub), "key": _live_key, "live": _is_sharing(pub), "relay": relay,
				"from_name": _peer_name(pub), "auto": true}
	elif _role == "guest" and _live_id != "" and _live_feed_on:
		if _live_from == multiplayer.get_unique_id():
			info = {"role": "publish", "id": _live_id, "key": _live_key, "live": true, "relay": _live_relay}
		else:
			# auto: the sender page follows the big screen without a Watch click (sound may still need
			# one click on the page: browsers only play sound after one)
			info = {"role": "view", "id": _live_id, "key": _live_key, "live": _live_on, "relay": _live_relay,
				"from_name": "" if _live_from == 1 else _live_from_name, "auto": true}
	# the session key, the quality and the podium list go along even when the big screen isn't shared
	# (the avatars use them)
	if _role != "off":
		info["key"] = _live_key
		# (the avatars travel through the same page, so they're relayed too, big screen shared or not)
		info["relay"] = relay_on() if _role == "host" else _live_relay
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


## Guest: the host (or the guest whose tab the host put on the big screen) is sharing a tab that
## this PC can watch. False while it's this PC's own tab that everyone is watching.
func is_host_live() -> bool:
	return _role == "guest" and _live_on and _live_from != multiplayer.get_unique_id()


## Guest: whose tab is on the big screen: "" for the host's, "me" for this PC's own, else a name.
func live_from() -> String:
	if _role != "guest" or _live_from == 1:
		return ""
	return "me" if _live_from == multiplayer.get_unique_id() else _live_from_name


## n random letters and digits (look-alikes like 0/O and 1/l left out), from a secure random source.
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
## A reaction with its own picture (Core's "img:boot" object, params.object_image) only has an
## address on the sender's own Stream Core, which the other PCs can't reach. So the picture's bytes
## go along, once per PC per session (_send_reaction_picture), and the reaction names it as
## "net:<md5>" (_picture_key). The others keep it in EmoteCache under that name.
func _on_reaction_play(d: Dictionary) -> void:
	if _role == "off" or bool(d.get("net_remote", false)):
		return
	var url := _reaction_picture_url(d)
	if url != "" and EmoteCache.get_bytes(url).is_empty() and not EmoteCache.is_failed(url):
		# the picture's first use: it's still downloading from Core (ReactionLayer asked for it),
		# so the reaction waits for it (_on_emote_ready), at most REACTION_PICTURE_WAIT seconds
		if not _pic_waiting.has(url):
			_pic_waiting[url] = {"list": [], "wait": REACTION_PICTURE_WAIT}
			EmoteCache.get_texture(url)      # (starts the download if nothing here asked for it yet)
		(_pic_waiting[url]["list"] as Array).append(d)
		return
	_share_reaction(d, url)


## Sends one of this PC's reactions to the others, with its picture (url: its address on this PC's
## Core, "" for none) when that's here and small enough; else they show its emoji / word.
func _share_reaction(d: Dictionary, url: String) -> void:
	if _role == "off":
		return
	var out := _shareable_reaction(d)
	var bytes := EmoteCache.get_bytes(url) if url != "" else PackedByteArray()
	var key := ""
	if bytes.size() <= PictureFile.MAX_BYTES and PictureFile.kind_of(bytes) != "":
		key = _picture_key(bytes)
		(out["params"] as Dictionary)["object_image"] = {"url": key}
	if _role == "host":
		for id: int in _peers:
			if id != 1:
				_send_reaction_picture(id, key, bytes)
				_net_reaction.rpc_id(id, out)
	else:
		if key != "" and not _pic_sent.has(key):
			_pic_sent[key] = true
			_net_guest_reaction_picture.rpc_id(1, key, bytes)
		_net_guest_reaction.rpc_id(1, out)


## The full address of a reaction's own picture on this PC's Stream Core, or "" when it has none.
static func _reaction_picture_url(d: Dictionary) -> String:
	var params: Variant = d.get("params")
	var pic: Variant = (params as Dictionary).get("object_image") if params is Dictionary else null
	var path := String((pic as Dictionary).get("url", "")) if pic is Dictionary else ""
	if path == "" or path.begins_with(EmoteCache.NET_PREFIX):
		return ""
	return ReactionLayer._core_url(path)


## A picture finished downloading (EmoteCache): reactions waiting for it go out now.
func _on_emote_ready(url: String) -> void:
	if _pic_waiting.has(url):
		var list: Array = _pic_waiting[url]["list"]
		_pic_waiting.erase(url)
		for d: Dictionary in list:
			_share_reaction(d, url)


## (from _process) Reactions whose picture didn't arrive in time, or failed, go without it.
func _reaction_picture_timeout(delta: float) -> void:
	for url: String in _pic_waiting.keys():
		_pic_waiting[url]["wait"] = float(_pic_waiting[url]["wait"]) - delta
		if float(_pic_waiting[url]["wait"]) <= 0.0 or EmoteCache.is_failed(url):
			var list: Array = _pic_waiting[url]["list"]
			_pic_waiting.erase(url)
			for d: Dictionary in list:
				_share_reaction(d, "")


## Host: a reaction picture to guest `id`, unless it has it already. Sent just before the reaction
## that uses it (same reliable channel, so it arrives first).
func _send_reaction_picture(id: int, key: String, bytes: PackedByteArray) -> void:
	if key == "" or bytes.is_empty():
		return
	if not _pic_sent.has(id):
		_pic_sent[id] = {}
	if not (_pic_sent[id] as Dictionary).has(key):
		_pic_sent[id][key] = true
		_net_reaction_picture.rpc_id(id, key, bytes)


## Guest: a reaction picture from the host (its own, or another guest's that it passes on).
@rpc("authority", "call_remote", "reliable")
func _net_reaction_picture(key: String, bytes: PackedByteArray) -> void:
	if _from_host() and _picture_ok(key, bytes):
		EmoteCache.put_bytes(key, bytes)


## Host: a guest's reaction picture (the reaction that uses it follows). Kept here so it can be
## shown here and passed on to the other guests.
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_reaction_picture(key: String, bytes: PackedByteArray) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id) or not _picture_ok(key, bytes):
		return
	EmoteCache.put_bytes(key, bytes)
	if not _pic_sent.has(id):
		_pic_sent[id] = {}
	_pic_sent[id][key] = true          # (the guest that sent it has it)


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
	var key := _reaction_key(out)
	var bytes := EmoteCache.get_bytes(key) if key != "" else PackedByteArray()
	for other: int in _peers:
		if other != 1 and other != id:
			_send_reaction_picture(other, key, bytes)
			_net_reaction.rpc_id(other, out)


## Only what the effect needs, as plain values. The id is marked so nobody reports the result to
## their own Stream Core twice. A picture is only kept as a "net:<md5>" name (its bytes travel
## separately, see _on_reaction_play); an address on the sender's Stream Core (only reachable on
## their PC) is dropped, and the reaction shows its emoji / word instead.
static func _shareable_reaction(d: Dictionary) -> Dictionary:
	var params: Dictionary = (d.get("params") as Dictionary).duplicate(true) if d.get("params") is Dictionary else {}
	var pic: Variant = params.get("object_image")
	params.erase("object_image")
	if pic is Dictionary and _is_picture_key(String((pic as Dictionary).get("url", ""))):
		params["object_image"] = {"url": String(pic["url"])}
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
	var key := _reaction_key(d)
	if key != "" and EmoteCache.get_bytes(key).is_empty() and EmoteCache.get_texture(key) == null:
		(d["params"] as Dictionary).erase("object_image")    # (its picture never came: the emoji / word then)
	d["net_remote"] = true
	EventBus.reaction_play.emit(d)


## The "net:<md5>" picture a shared reaction names, or "".
static func _reaction_key(d: Dictionary) -> String:
	var params: Variant = d.get("params")
	var pic: Variant = (params as Dictionary).get("object_image") if params is Dictionary else null
	return String((pic as Dictionary).get("url", "")) if pic is Dictionary else ""


## A picture's name between the PCs: EmoteCache.NET_PREFIX + the MD5 of its bytes (the same picture
## gets the same name on every PC, whoever's Core it came from).
static func _picture_key(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(bytes)
	return EmoteCache.NET_PREFIX + h.finish().hex_encode()


## "net:" plus 32 hex digits (a name _picture_key makes), nothing else.
static func _is_picture_key(key: String) -> bool:
	return key.length() == 36 and key.begins_with(EmoteCache.NET_PREFIX) and key.substr(4).is_valid_hex_number()


## A picture from another PC: a known format, not too big, and its name matches its bytes.
static func _picture_ok(key: String, bytes: PackedByteArray) -> bool:
	return _is_picture_key(key) and bytes.size() <= PictureFile.MAX_BYTES and PictureFile.kind_of(bytes) != "" \
		and not PictureFile.too_big(bytes) and _picture_key(bytes) == key


# ── Cameras ──────────────────────────────────────────────────
## Guest: someone's camera moved (sent by the host for itself and for the other guests).
## Channel 1, unreliable: a lost update is fine, the next one follows.
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _net_camera(peer_id: int, x: Transform3D) -> void:
	if not _from_host() or peer_id == multiplayer.get_unique_id():
		return
	EventBus.net_camera_moved.emit(peer_id, _peer_name(peer_id), x)


## Host: a guest's camera moved; shown here and passed on to the other guests.
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


# ── Laser pointers ───────────────────────────────────────────
## Everyone's laser pointer (core/laser_pointers.gd) travels like the cameras: a guest sends its own
## to the host, the host shows it and passes it on to the other guests, and sends its own to all.
## The packet is [on, from, to, color, beam]: where the beam starts and where the dot is (both
## worked out on the sender's PC, since the room is the same on every PC), the colour and whether
## the beam shows. Channel 2: updates are unreliable (a lost one is fine, the next follows), the
## "off" is reliable on the same channel so it can't be overtaken by an older update. (The session
## runs over WebSocket, which keeps everything in order anyway; the channel says what's meant.)

## Called by LaserPointers whenever this PC's laser moves (at most LaserPointers.SEND_GAP apart),
## while it stays on (a keep-alive every LaserPointers.KEEP_ALIVE_S) and once when it goes off.
## Does nothing outside a session.
func send_laser(on: bool, from: Vector3, to: Vector3, color: Color, beam: bool) -> void:
	if _role == "off" or not _connected():
		return
	var packet: Array = [on, from, to, color, beam]
	if _role == "host":
		for id: int in _peers:
			if id != 1:
				if on:
					_net_laser.rpc_id(id, 1, packet)
				else:
					_net_laser_off.rpc_id(id, 1)
	elif _admitted:
		if on:
			_net_guest_laser.rpc_id(1, packet)
		else:
			_net_guest_laser_off.rpc_id(1)


## A laser packet from the wire as {on, from, to, color, beam}, or {} when it isn't one (wrong
## types, positions far outside any room). Both sides check what they receive.
static func laser_state(packet: Variant) -> Dictionary:
	if not packet is Array or (packet as Array).size() != 5:
		return {}
	var a := packet as Array
	if not (a[0] is bool and a[1] is Vector3 and a[2] is Vector3 and a[3] is Color and a[4] is bool):
		return {}
	var limit := 500.0       # metres; the rooms are far smaller
	for v: Vector3 in [a[1], a[2]]:
		if not v.is_finite() or absf(v.x) > limit or absf(v.y) > limit or absf(v.z) > limit:
			return {}
	var c := a[3] as Color
	return {"on": bool(a[0]), "from": a[1], "to": a[2], "color": Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)),
		"beam": bool(a[4])}


## Guest: someone's laser (the host's own, or another guest's passed on by the host).
@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _net_laser(peer_id: int, packet: Array) -> void:
	if not _from_host() or peer_id == multiplayer.get_unique_id():
		return
	var st := laser_state(packet)
	if not st.is_empty():
		EventBus.net_laser_changed.emit(peer_id, _peer_name(peer_id), st)


## Guest: someone's laser went off.
@rpc("authority", "call_remote", "reliable", 2)
func _net_laser_off(peer_id: int) -> void:
	if _from_host() and peer_id != multiplayer.get_unique_id():
		EventBus.net_laser_changed.emit(peer_id, _peer_name(peer_id), {"on": false})


## Host: a guest's laser moved; shown here and passed on to the other guests.
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _net_guest_laser(packet: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id):
		return
	var st := laser_state(packet)
	if st.is_empty():
		return
	EventBus.net_laser_changed.emit(id, _peer_name(id), st)
	for other: int in _peers:
		if other != 1 and other != id:
			_net_laser.rpc_id(other, id, packet)


## Host: a guest's laser went off; passed on like the updates.
@rpc("any_peer", "call_remote", "reliable", 2)
func _net_guest_laser_off() -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id):
		return
	EventBus.net_laser_changed.emit(id, _peer_name(id), {"on": false})
	for other: int in _peers:
		if other != 1 and other != id:
			_net_laser_off.rpc_id(other, id)


# ── Room events ──────────────────────────────────────────────
## Things a room's own game does that every PC should show (the Lakeside Campfire's marshmallow
## sticks and tossed sticks, rooms/campfire/campfire_games.gd). They travel like the lasers: a
## guest sends its own to the host, the host shows it and passes it on to the other guests, and
## sends its own to all. The packet is a short name and a few plain values; what they mean is
## the room's business, so this file only checks their shape (room_event_ok) and that one PC
## doesn't send more than ROOM_EVENT_MAX a second. Channel 2, reliable (they are small and rare).

## Most room events the host accepts from one guest in a second (the rest are dropped).
const ROOM_EVENT_MAX: int = 30
## Host: guest's peer id -> [the second it was last counted in (unix time), events in it].
var _room_event_counts: Dictionary = {}


## Called by a room's game when this PC does something the others should see. Does nothing
## outside a session.
func send_room_event(kind: String, data: Array) -> void:
	if _role == "off" or not _connected() or not room_event_ok(kind, data):
		return
	if _role == "host":
		for id: int in _peers:
			if id != 1:
				_net_room_event.rpc_id(id, 1, kind, data)
	elif _admitted:
		_net_guest_room_event.rpc_id(1, kind, data)


## True for a packet a room event may be: a name of 1 to 24 letters, digits or "_", and at most 8
## values that are each a bool, an int, a finite float, a text of at most 64 characters or a
## Vector3 within 500 m. Both sides check what they receive.
static func room_event_ok(kind: Variant, data: Variant) -> bool:
	if not kind is String or not data is Array:
		return false
	var k := kind as String
	if k.length() < 1 or k.length() > 24 or not k.is_valid_ascii_identifier():
		return false
	if (data as Array).size() > 8:
		return false
	for v: Variant in (data as Array):
		if v is bool or v is int:
			continue
		if v is float and is_finite(v):
			continue
		if v is String and (v as String).length() <= 64:
			continue
		if v is Vector3 and (v as Vector3).is_finite() and (v as Vector3).length() <= 500.0:
			continue
		return false
	return true


## Guest: someone's room event (the host's own, or another guest's passed on by the host).
@rpc("authority", "call_remote", "reliable", 2)
func _net_room_event(peer_id: int, kind: String, data: Array) -> void:
	if not _from_host() or peer_id == multiplayer.get_unique_id() or not room_event_ok(kind, data):
		return
	EventBus.net_room_event.emit(peer_id, _peer_name(peer_id), kind, data)


## Host: a guest's room event; shown here and passed on to the other guests.
@rpc("any_peer", "call_remote", "reliable", 2)
func _net_guest_room_event(kind: String, data: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id) or not room_event_ok(kind, data):
		return
	var now := int(Time.get_unix_time_from_system())
	var count: Array = _room_event_counts.get(id, [now, 0])
	if int(count[0]) != now:
		count = [now, 0]
	count[1] = int(count[1]) + 1
	_room_event_counts[id] = count
	if int(count[1]) > ROOM_EVENT_MAX:
		return
	EventBus.net_room_event.emit(id, _peer_name(id), kind, data)
	for other: int in _peers:
		if other != 1 and other != id:
			_net_room_event.rpc_id(other, id, kind, data)


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
	if auto_confirm or (not _rejoin.is_empty() and _host_name == String(_rejoin["host"])):
		confirm(true)          # (reconnecting to the same host: it was confirmed before)
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


## Host: a pending guest is refused (declined or timed out): tell them why, then disconnect.
func _turn_away(id: int, reason: String, status: String) -> void:
	_pending.erase(id)
	EventBus.net_confirm_closed.emit(id)
	_net_declined.rpc_id(id, reason)
	# a moment for the reason to arrive before the connection closes
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if _role == "host":
			_sm().disconnect_peer(id))
	_set_status(status)


## Host: pending guests not let in within CONFIRM_TIMEOUT seconds are turned away.
func _pending_timeout(delta: float) -> void:
	if _pending.is_empty():
		return
	for id: int in _pending.keys():
		_pending[id]["wait"] = float(_pending[id]["wait"]) - delta
		if float(_pending[id]["wait"]) <= 0.0:
			_turn_away(id, "Nobody confirmed the connection in time. Try joining again.",
				"%s waited too long to be let in." % String(_pending[id]["name"]))


# ── Pause to react ───────────────────────────────────────────
## Pause to react (Space) pauses for everyone in the session: the host's (or a co-host's, through
## the host) goes to every guest, and a guest joining mid-pause gets it in the snapshot. A plain
## guest's pause stays on their own PC. Only the PC whose tab is on the big screen sends the
## Play/Pause key to its browser (ScreenFeed asks owns_big_screen), so nobody else's music stops.

## EventBus.react_pause_changed on this PC.
func _on_react_pause(paused: bool) -> void:
	if _applying_pause:
		return
	if _role == "host":
		_to_guests("_net_react_pause", [paused])
	elif _role == "guest" and _admitted and _connected():
		if has_remote():
			_net_request.rpc_id(1, "react_pause", paused)
		else:
			EventBus.status_message.emit("Paused on your PC only. Whoever has the big screen remote pauses for everyone.", false)


## Guest: the host paused / unpaused for everyone.
@rpc("authority", "call_remote", "reliable")
func _net_react_pause(paused: bool) -> void:
	if _from_host():
		_apply_react_pause(paused)


func _apply_react_pause(paused: bool) -> void:
	_applying_pause = true
	AppState.set_react_paused(paused)
	_applying_pause = false


# ── Claimed podiums ──────────────────────────────────────────
## A guest can claim a free podium and run it from their own PC: it shows their My avatar (camera,
## tab / window or a see-through web page, set in their Co-stream tab, sent to everyone like
## avatars are), and they set its name tag, light, chroma key, picture and the rest in their own
## Presenters tab. Those changes go through the host (_net_request) like a co-host's, but only for
## that podium. The host can lock a podium (nobody can claim it) or free a claimed one; a podium is
## freed when its owner leaves. One podium per guest. Needs the presenters shared (together_share_presenters).

## This PC's claimed podium (1..PRESENTER_COUNT), or 0.
func my_podium() -> int:
	var me := multiplayer.get_unique_id() if _role == "guest" else -1
	for n: int in _podiums:
		if int(_podiums[n].get("owner", 0)) == me:
			return n
	return 0


## Every podium for the menus: [{n, owner (name, "" = the host's), mine, locked, free}].
func podium_list() -> Array:
	var out: Array = []
	if _role == "off":
		return out
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var holder := _podium_owner(n)
		var locked := bool((_podiums.get(n, {}) as Dictionary).get("locked", false))
		out.append({"n": n, "owner": _peer_name(holder) if holder > 0 else "", "mine": holder > 0 and holder == multiplayer.get_unique_id(),
			"locked": locked, "free": holder == 0 and not locked})
	return out


## Guest: claim podium n (want = false gives it up).
func claim_podium(n: int, want: bool = true) -> void:
	if _role == "guest" and _admitted and _connected() and n >= 1 and n <= AppState.PRESENTER_COUNT:
		_net_podium_claim.rpc_id(1, n, want)


## Host: lock podium n (nobody can claim it; a claimed one is freed first) or unlock it.
func lock_podium(n: int, on: bool) -> void:
	if _role != "host" or n < 1 or n > AppState.PRESENTER_COUNT:
		return
	if on and _podium_owner(n) > 0:
		_free_podium(n)
	if not _podiums.has(n):
		_podiums[n] = {"owner": 0, "locked": false}
	_podiums[n]["locked"] = on
	_send_roster()


## Host: give a claimed podium back to the host (it goes off set, as before it was claimed).
func free_podium(n: int) -> void:
	if _role == "host" and _podium_owner(n) > 0:
		_free_podium(n)
		_send_roster()


func _podium_owner(n: int) -> int:
	return int((_podiums.get(n, {}) as Dictionary).get("owner", 0)) if n > 0 else 0


## "presenter_3_name" -> 3; anything else -> 0.
static func _podium_of(key: String) -> int:
	if not key.begins_with("presenter_"):
		return 0
	var n := key.get_slice("_", 1)
	return int(n) if n.is_valid_int() else 0


## Guest: the podium a setting belongs to when it's this PC's claimed one and shared, else 0.
func _owned_podium_of(key: String) -> int:
	var n := _podium_of(key)
	return n if _role == "guest" and n > 0 and n == my_podium() and _shared.has(key) else 0


## Guest: a change to this PC's own podium. Camera and Tab / window can't be seen by the others as a
## podium source, so they become this PC's My avatar, which the podium then shows (source "peer").
func _owner_change(n: int, key: String, value: Variant) -> void:
	if key.ends_with("_source") and String(value) in ["camera", "tab"]:
		AppState.set_setting("together_avatar_source", String(value))
		EventBus.status_message.emit("Your podium shows your My avatar, now set to %s (Co-stream tab)." % ("your camera" if value == "camera" else "a tab or window"), false)
		_net_request.rpc_id(1, AppState.presenter_key(n, "peer"), display_name())
		value = "peer"
	elif key.ends_with("_source") and String(value) in ["ndi", "spout"]:
		EventBus.status_message.emit("The others can't see NDI or Spout. Send it to OBS Virtual Camera and pick Camera instead.", true)
		return
	_net_request.rpc_id(1, key, value)


## Host: may this guest set this on their claimed podium? Sources other PCs can see only, and
## "peer" only for their own avatar.
func _owner_value_ok(key: String, value: Variant, id: int) -> bool:
	if key.ends_with("_source"):
		return String(value) in ["peer", "silhouette", "green", "web"]
	if key.ends_with("_peer"):
		return String(value) == _peer_name(id)
	return true


## Host: a guest claims podium n, or gives it up.
@rpc("any_peer", "call_remote", "reliable")
func _net_podium_claim(n: int, want: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id) or n < 1 or n > AppState.PRESENTER_COUNT:
		return
	if not want:
		if _podium_owner(n) == id:
			_free_podium(n)
			_send_roster()
		return
	var why := ""
	if not group_shared("presenters"):
		why = "The host isn't sharing the podiums right now."
	elif bool((_podiums.get(n, {}) as Dictionary).get("locked", false)):
		why = "The host locked that podium."
	elif _podium_owner(n) > 0:
		why = "%s has that podium." % _peer_name(_podium_owner(n))
	if why != "":
		_net_podium_refused.rpc_id(id, why)
		return
	for other: int in _podiums.keys():
		if _podium_owner(other) == id:
			_free_podium(other)          # (one podium each: moving to another)
	_podiums[n] = {"owner": id, "locked": false}
	var who := _peer_name(id)
	AppState.set_setting(AppState.presenter_key(n, "on"), true)
	AppState.set_setting(AppState.presenter_key(n, "source"), "peer")
	AppState.set_setting(AppState.presenter_key(n, "peer"), who)
	AppState.set_setting(AppState.presenter_key(n, "name"), who)
	EventBus.status_message.emit("%s claimed podium %d." % [who, n], false)
	_send_roster()


## Guest: the host said no to a claim.
@rpc("authority", "call_remote", "reliable")
func _net_podium_refused(why: String) -> void:
	if _from_host():
		EventBus.status_message.emit(why.left(200), true)


## Guest: the host's podium table (who has which, which are locked).
@rpc("authority", "call_remote", "reliable")
func _net_podiums(table: Dictionary) -> void:
	if not _from_host():
		return
	var mine_before := my_podium()
	_podiums.clear()
	for k: Variant in table:
		if k is int and int(k) >= 1 and int(k) <= AppState.PRESENTER_COUNT and table[k] is Dictionary:
			_podiums[int(k)] = {"owner": int((table[k] as Dictionary).get("owner", 0)), "locked": bool((table[k] as Dictionary).get("locked", false))}
	if my_podium() != mine_before and my_podium() > 0:
		EventBus.status_message.emit("Podium %d is yours: set it up in the Presenters tab. It shows your My avatar." % my_podium(), false)
	_emit_state()


## Host: a claimed podium goes back to the host, off set.
func _free_podium(n: int) -> void:
	if not _podiums.has(n):
		return
	_podiums[n]["owner"] = 0
	AppState.set_setting(AppState.presenter_key(n, "on"), false)
	AppState.set_setting(AppState.presenter_key(n, "source"), "silhouette")
	AppState.set_setting(AppState.presenter_key(n, "peer"), "")
	AppState.set_setting(AppState.presenter_key(n, "picture"), "")


## Guest: this PC picked a picture for its own podium: the bytes go to the host, which puts them
## on the podium for everyone (_net_podium_picture).
func _upload_podium_picture(n: int, path: String) -> void:
	var bytes := PictureFile.read_file(path) if path.strip_edges() != "" else PackedByteArray()
	if path.strip_edges() != "" and bytes.is_empty():
		EventBus.status_message.emit("That picture can't be sent (PNG, JPG, WebP or GIF up to 3 MB).", true)
		return
	if _connected():
		_net_podium_picture.rpc_id(1, n, bytes)


## Host: the owner of podium n sent its picture (empty = none). Kept in user://podium_pictures and
## set as the podium's picture, which then goes to everyone like the host's own.
@rpc("any_peer", "call_remote", "reliable")
func _net_podium_picture(n: int, bytes: PackedByteArray) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or _podium_owner(n) != id:
		return
	var key := AppState.presenter_key(n, "picture")
	if bytes.is_empty():
		AppState.set_setting(key, "")
		return
	var kind := PictureFile.kind_of(bytes)
	if bytes.size() > PictureFile.MAX_BYTES or kind == "" or (kind != "gif" and PictureFile.too_big(bytes)):
		return
	DirAccess.make_dir_recursive_absolute("user://podium_pictures")
	var path := "user://podium_pictures/claimed_%d_%s.%s" % [n, bytes.slice(0, 4096).hex_encode().md5_text().left(8), kind]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	AppState.set_setting(key, path)


# ── Big screen remote ─────────────────────────────────────────
## One person holds the big screen remote: the host at the start, then whoever it's passed to. The
## holder decides what everyone's big screen shows (their own shared tab: screen_tab_peer follows
## the holder; a web video; someone's avatar, screen_peer) and pauses for everyone. Co-hosts keep
## the room, curtain and podiums, not the big screen. A guest can ask for it (the host sees "asked"
## in the Esc menu > Co-stream); the holder can pass it on or give it back; it goes back to the host
## when the holder leaves. The host can always take it back. Set by the Esc menu and the Co-stream tab.

## The settings the holder controls ("video" is a web video for the big screen, see _gate).
const SCREEN_KEYS: Array[String] = ["screen_peer", "screen_tab_peer"]


func _is_screen(what: String) -> bool:
	return what == "video" or SCREEN_KEYS.has(what)


## True when this PC holds the remote (also true outside a session: it's all this PC's then).
func has_remote() -> bool:
	if _role == "host":
		return _remote_id == 1
	if _role == "guest":
		return _remote_id == multiplayer.get_unique_id()
	return true


## Host: give the remote to someone (1 = take it back). The holder (a guest): pass it on or give it
## back (to 1).
func pass_remote(peer_id: int) -> void:
	if _role == "host":
		_set_remote(peer_id)
	elif _role == "guest" and has_remote() and _connected():
		_net_remote_pass.rpc_id(1, peer_id)


## Guest: ask the host for the remote (want = false takes the question back).
func ask_remote(want: bool = true) -> void:
	if _role == "guest" and _admitted and _connected() and not has_remote():
		_net_remote_ask.rpc_id(1, want)


## Host: the remote goes to this person (anyone not in the session = the host). Their shared tab
## becomes the big screen's, and everyone hears who has it.
func _set_remote(peer_id: int) -> void:
	if not _peers.has(peer_id):
		peer_id = 1
	_remote_id = peer_id
	_peers[peer_id]["asked"] = false
	_remote_setting = true
	AppState.set_setting("screen_tab_peer", "" if peer_id == 1 else String(_peers[peer_id]["name"]))
	_remote_setting = false
	_set_status("You have the big screen remote." if peer_id == 1 else "%s has the big screen remote." % _peer_name(peer_id))
	DebugLog.note("net", "big screen remote -> #%d" % peer_id)
	_send_roster()


## Host: a guest asks for the remote (or takes the question back).
@rpc("any_peer", "call_remote", "reliable")
func _net_remote_ask(want: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id) or id == _remote_id:
		return
	_peers[id]["asked"] = want
	if want:
		EventBus.status_message.emit("%s asks for the big screen remote (Esc menu > Co-stream: Give remote)." % _peer_name(id), false)
	_send_roster()


## Host: the guest holding the remote passes it on (1 = back to the host).
@rpc("any_peer", "call_remote", "reliable")
func _net_remote_pass(to: int) -> void:
	if _role == "host" and multiplayer.get_remote_sender_id() == _remote_id:
		_set_remote(to)


## True when this PC's own content is what the big screen shows (no session, the host showing its
## own tab, or a guest whose tab the host put on the big screen). ScreenFeed only sends the
## Play/Pause key to the browser then.
func owns_big_screen() -> bool:
	if _role == "host":
		return _tab_publisher() == 1
	if _role == "guest":
		return live_from() == "me"
	return true


## True when this PC's My avatar is a see-through web page (sent over AVATAR_KEY_COLOR).
func _my_avatar_keyed() -> bool:
	return String(AppState.get_setting("together_avatar_source")) == "web"


## Host: a guest's My avatar changed between a see-through web page and something else.
@rpc("any_peer", "call_remote", "reliable")
func _net_avatar_keyed(keyed: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role == "host" and _peers.has(id) and bool(_peers[id].get("keyed", false)) != keyed:
		_peers[id]["keyed"] = keyed
		_send_roster()


## How a podium showing `who`'s avatar (presenter source "peer") must key it: {"color": Color} when
## that avatar is a see-through web page (it travels over AVATAR_KEY_COLOR), {} when the podium's own
## key settings apply (a camera or tab avatar). Read by presenter.gd on every PC, so all key alike.
func avatar_key(who: String) -> Dictionary:
	for id: int in _peers:
		if String(_peers[id]["name"]) == who and bool(_peers[id].get("keyed", false)):
			return {"color": AVATAR_KEY_COLOR}
	return {}


## Host, in a session with guests and shared presenters: what's wrong with podium n for the guests
## ("" = nothing). A camera, tab, NDI or Spout source, or a web page only this PC can open (a local
## avatar app on localhost, an address on the home network), shows as a silhouette or a blank on
## their PCs. The fix is My avatar (Co-stream tab), shown with "Someone's avatar".
func podium_warning(n: int) -> String:
	if _role != "host" or guest_count() == 0 or not group_shared("presenters"):
		return ""
	if not bool(AppState.get_setting(AppState.presenter_key(n, "on"))):
		return ""
	var src := String(AppState.get_setting(AppState.presenter_key(n, "source")))
	var how := "set it as your My avatar (Co-stream tab) and pick Someone's avatar for the podium"
	if LOCAL_ONLY_SOURCES.has(src):
		return "Podium %d shows your %s, which only exists on your PC: guests see a silhouette there. To show it to them, %s." % [
			n, {"camera": "camera", "tab": "tab / window", "ndi": "NDI source", "spout": "Spout source"}[src], how]
	if src == "web":
		var url := String(AppState.get_setting(AppState.presenter_key(n, "url"))).to_lower()
		var host_part := url.get_slice("://", 1) if url.contains("://") else url
		for start: String in LOCAL_URL_HOSTS:
			if host_part.begins_with(start):
				return "Podium %d's web page is on your PC or home network, so guests' PCs can't open it. To show it to them, %s." % [n, how]
	return ""


## Host: says podium_warning out loud (status line) for podium n, or for every podium (n = 0).
func _warn_podiums(n: int = 0) -> void:
	for i in range(1, AppState.PRESENTER_COUNT + 1):
		if n == 0 or i == n:
			var why := podium_warning(i)
			if why != "":
				EventBus.status_message.emit(why, true)


# ── Staying in sync ──────────────────────────────────────────
## Three things keep every PC showing the same session (work list item 1 and 22, docs/MULTIPLAYER.md):
##   - The first sync. When a guest is let in (or asks for a resync) the host sends everything in one
##     go: _net_sync_start(how many things), the state, podium and silhouette pictures, the audience
##     and its looks, then _net_sync_done. Messages arrive in order, so when "done" is here everything
##     is. The guest shows "Syncing with <host>" with a progress bar until then (and until its room
##     has loaded), then tells the host (_net_guest_synced), whose list shows who is still syncing.
##   - Audience checks. While the audience is shared the host sends a short fingerprint of who sits
##     where every AUD_CHECK_GAP seconds (_net_aud_check); a guest whose own differs asks for the
##     whole roster again (_net_aud_resync). Resync on the Co-stream tab asks for everything again.
##   - Reconnecting. A guest whose connection drops tries to get back in (RECONNECT_DELAYS), keeping
##     the shared audience on screen meanwhile and holding its chat (_chat_held) to send once back.
##     The host keeps that person's part of the audience by name (_streamer_slots, AWAY_KEEP_S) and
##     lets them straight back in without the popup.

## Called every frame from _process (also while a guest waits to reconnect).
func _sync_tick(delta: float) -> void:
	if _role == "off":
		if not _rejoin.is_empty():
			_rejoin["wait"] = float(_rejoin["wait"]) - delta
			if float(_rejoin["wait"]) <= 0.0:
				_rejoin["wait"] = 9999.0          # (until this try ends one way or the other)
				join(true)
				if _role == "off":
					_schedule_rejoin()          # (couldn't even start: the next try)
		return
	if _role == "guest":
		_aud_resync_wait -= delta
		if not _sync.is_empty() and bool(_sync["done"]):
			_check_synced()
		return
	# host: audience checks, and parts of the audience kept for people who dropped
	if _sharing_audience():
		_aud_check_wait -= delta
		if _aud_check_wait <= 0.0:
			_aud_check_wait = AUD_CHECK_GAP
			if _roster_wait < 0.0:          # (a whole roster is about to go anyway)
				_to_guests("_net_aud_check", [_room(), AudienceManager.roster_fingerprint()])
	var freed := false
	for k: String in _streamer_slots.keys():
		if int(_streamer_slots[k]["id"]) == 0:
			_streamer_slots[k]["away"] = float(_streamer_slots[k]["away"]) + delta
			if float(_streamer_slots[k]["away"]) >= AWAY_KEEP_S:
				_streamer_slots.erase(k)
				freed = true
	if freed:
		_update_audience_sharing()


## Host: sends guest `id` everything it needs (see the top of this part), counted first so the
## guest can show how far along it is. Used when a guest is let in, and for a resync.
func _send_everything(id: int) -> void:
	if _role != "host" or not _peers.has(id):
		return
	_peers[id]["synced"] = false
	_peers[id]["sync"] = 0
	var sharing := _sharing_audience()
	var total := 1                                   # the state (_snapshot)
	if group_shared("presenters"):
		for n in range(1, AppState.PRESENTER_COUNT + 1):
			var path := String(AppState.get_setting(AppState.presenter_key(n, "picture"))).strip_edges()
			if path == "" or not PictureFile.read_file(path).is_empty():
				total += 1                           # (the same test _send_picture makes)
	if sharing:
		total += 2 + _unsent_look_pictures(id)       # roster + looks + their pictures
	_net_sync_start.rpc_id(id, total)
	_net_snapshot.rpc_id(id, _snapshot())
	if group_shared("presenters"):
		for n in range(1, AppState.PRESENTER_COUNT + 1):
			_send_picture(n, id)
	if sharing:
		_net_aud_mode.rpc_id(id, true)
		_send_looks(id)
		_net_aud_roster.rpc_id(id, _room(), AudienceManager.get_roster())
		_net_aud_reserved.rpc_id(id, String(AudienceManager.wire_reserved()["room"]), AudienceManager.wire_reserved()["list"])
	_last_cam = Transform3D()         # send the host's camera again, for the newcomer
	for other: int in _cams:
		if other != id:
			_net_camera.rpc_id(id, other, _cams[other])
	_net_sync_done.rpc_id(id)
	_emit_state()


## Host: how many silhouette pictures guest `id` doesn't have yet (the host's looks, and each
## streamer's while "Viewers keep their streamer's looks" is on). Only counts; _send_looks and
## _update_streamer_looks send them.
func _unsent_look_pictures(id: int) -> int:
	var pictures := {}
	var looks := {}
	for k: String in AudienceStyle.LOOK_KEYS:
		looks[k] = String(AppState.get_setting(k))
	_looks_to_wire(looks, pictures)
	if bool(AppState.get_setting("together_streamer_looks")):
		for looks_of: Array in _kept_guest_looks():
			_looks_to_wire(looks_of[1], pictures)
	var sent: Dictionary = _pic_sent.get(id, {})
	var count := 0
	for key: String in pictures:
		if not sent.has("look:" + key):
			count += 1
	return count


## Guest: the host is about to send `total` things (see _send_everything).
@rpc("authority", "call_remote", "reliable")
func _net_sync_start(total: int) -> void:
	if not _from_host():
		return
	_sync = {"total": clampi(total, 1, 10000), "got": 0, "done": false, "told": 0}
	_synced = false
	_set_status("Syncing with %s..." % _host_name)


## Guest: one of the things the host sends while syncing arrived.
func _sync_got() -> void:
	if _sync.is_empty() or bool(_sync["done"]):
		return
	_sync["got"] = int(_sync["got"]) + 1
	# the host's list shows how far along this PC is: tell it every 10 %
	var pct := int(sync_progress() * 100.0)
	if pct >= int(_sync["told"]) + 10:
		_sync["told"] = pct
		_net_guest_sync_progress.rpc_id(1, pct)
	_emit_state()


## Guest: the host's last thing of this sync (everything before it has arrived).
@rpc("authority", "call_remote", "reliable")
func _net_sync_done() -> void:
	if _from_host() and not _sync.is_empty():
		_sync["done"] = true
		_check_synced()


## Guest: once the host's things are all here, waits for the room to load (the audience roster waits
## for it too) and then counts as synced.
func _check_synced() -> void:
	var room_ready := AudienceManager.seats_room() == String(AppState.get_setting("room_id"))
	if _aud_shared and (AudienceManager.roster_fingerprint() == "" or not room_ready):
		return                       # (checked again next frame)
	_sync.clear()
	_synced = true
	_net_guest_synced.rpc_id(1)
	_set_status("In sync with %s's session. The host controls the room, curtain and presenters." % _host_name)


## Guest: 0..1 while syncing (0.99 at most until it's done), -1 when not syncing.
func sync_progress() -> float:
	if _role != "guest" or _synced or _sync.is_empty():
		return -1.0
	return minf(float(_sync["got"]) / float(_sync["total"]), 0.99)


## Host: how far along a guest's sync is (percent), for the list on the Co-stream tab.
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_sync_progress(pct: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role == "host" and _peers.has(id):
		_peers[id]["sync"] = clampi(pct, 0, 100)
		_emit_state()


## Host: a guest has everything and shows it.
@rpc("any_peer", "call_remote", "reliable")
func _net_guest_synced() -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role == "host" and _peers.has(id):
		_peers[id]["synced"] = true
		_peers[id]["sync"] = 100
		_emit_state()


## Guest: the host's audience fingerprint (see AudienceManager.roster_fingerprint). A different one
## here means a seat change got lost: ask for the whole roster (at most once per AUD_RESYNC_GAP).
@rpc("authority", "call_remote", "reliable")
func _net_aud_check(room: String, fingerprint: String) -> void:
	if not _from_host() or not _aud_shared or not _synced:
		return
	var mine := AudienceManager.roster_fingerprint()
	if mine == "" or room != AudienceManager.seats_room() or room != String(AppState.get_setting("room_id")):
		return                       # (this PC is still loading the room: the roster waits for it)
	if mine != fingerprint and _aud_resync_wait <= 0.0:
		_aud_resync_wait = AUD_RESYNC_GAP
		_aud_resyncs += 1
		print("Co-stream: the audience here differed from the host's; asked for it again (%d this session)." % _aud_resyncs)
		_net_aud_resync.rpc_id(1)
		_emit_state()


## Host: a guest's audience differed (see _net_aud_check): the whole roster to that guest.
@rpc("any_peer", "call_remote", "reliable")
func _net_aud_resync() -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role == "host" and _peers.has(id) and _sharing_audience():
		_net_aud_roster.rpc_id(id, _room(), AudienceManager.get_roster())
		_net_aud_reserved.rpc_id(id, String(AudienceManager.wire_reserved()["room"]), AudienceManager.wire_reserved()["list"])


## Co-stream tab "Resync": a guest asks the host for everything again; the host sends it to every
## guest. For when something looks different on two PCs.
func resync() -> void:
	if _role == "guest" and _admitted:
		_net_resync_request.rpc_id(1)
		_set_status("Asked %s to send everything again..." % _host_name)
	elif _role == "host":
		for id: int in _peers:
			if id != 1:
				_pic_sent.erase(id)
				_send_everything(id)
		_update_streamer_looks()
		_set_status("Sent everything to the guests again.")


## Host: a guest's Resync (at most one every few seconds per guest).
@rpc("any_peer", "call_remote", "reliable")
func _net_resync_request() -> void:
	var id := multiplayer.get_remote_sender_id()
	if _role != "host" or not _peers.has(id):
		return
	var now := Time.get_ticks_msec()
	if now - int(_peers[id].get("resync_ms", -100000)) < int(AUD_RESYNC_GAP * 1000.0):
		return
	_peers[id]["resync_ms"] = now
	_pic_sent.erase(id)            # (pictures go again too, in case one went missing)
	_send_everything(id)
	_update_streamer_looks()


## Host: the name key a streamer's part of the audience is kept under (_streamer_slots).
static func _streamer_key(n: String) -> String:
	return n.strip_edges().to_lower()


## Host: true when `n` is someone who dropped and whose part of the audience is still kept.
func _is_away(n: String) -> bool:
	var k := _streamer_key(n)
	return _streamer_slots.has(k) and int(_streamer_slots[k]["id"]) == 0


## Host: gives guest `id` (named `n`) their number in the shared audience: the one they had if
## they're coming back, else the lowest free one (1..MAX_GUESTS). If all are held by people who
## dropped, the one away longest gives theirs up.
func _claim_streamer_slot(id: int, n: String) -> void:
	var k := _streamer_key(n)
	if _streamer_slots.has(k) and int(_streamer_slots[k]["id"]) == 0:
		_streamer_slots[k]["id"] = id
		_streamer_slots[k]["away"] = 0.0
		return
	if _streamer_slots.has(k):
		k = "%s#%d" % [k, id]           # (two people with one name: each gets their own part)
	var used := {}
	for s: Dictionary in _streamer_slots.values():
		used[int(s["index"])] = true
	var index := -1
	for i in range(1, MAX_GUESTS + 1):
		if not used.has(i):
			index = i
			break
	if index < 0:
		var oldest := ""
		for kk: String in _streamer_slots:
			if int(_streamer_slots[kk]["id"]) == 0 and (oldest == "" or
					float(_streamer_slots[kk]["away"]) > float(_streamer_slots[oldest]["away"])):
				oldest = kk
		index = int(_streamer_slots[oldest]["index"]) if oldest != "" else MAX_GUESTS
		_streamer_slots.erase(oldest)
	_streamer_slots[k] = {"index": index, "id": id, "away": 0.0}


## Host: guest `id` left; their part of the audience (and their own looks, for "Viewers keep their
## streamer's looks") is kept for AWAY_KEEP_S seconds.
func _release_streamer_slot(id: int) -> void:
	for k: String in _streamer_slots:
		if int(_streamer_slots[k]["id"]) == id:
			_streamer_slots[k]["id"] = 0
			_streamer_slots[k]["away"] = 0.0
			if _guest_looks.has(id):
				_streamer_slots[k]["looks"] = _guest_looks[id]


## Host: [[streamer number, looks], ...] for every guest whose own looks are known: the ones here
## (_guest_looks) and the ones kept for people who dropped (_streamer_slots "looks").
func _kept_guest_looks() -> Array:
	var out: Array = []
	for id: int in _guest_looks:
		if _peers.has(id):
			out.append([_streamer_index(id), _guest_looks[id]])
	for s: Dictionary in _streamer_slots.values():
		if int(s["id"]) == 0 and s.get("looks") is Dictionary:
			out.append([int(s["index"]), s["looks"]])
	return out


## Host: how many streamer areas the audience needs: one more than the highest number in use,
## counting people who dropped (their area stays theirs while they're away).
func _streamer_area_count() -> int:
	var top := 0
	for s: Dictionary in _streamer_slots.values():
		top = maxi(top, int(s["index"]))
	return top + 1


## Guest: the connection dropped. Keeps the shared audience on screen and tries to get back in.
func _start_rejoin() -> void:
	if _role != "guest":
		return
	var host_name := _host_name if _rejoin.is_empty() else String(_rejoin["host"])
	var tries := 0 if _rejoin.is_empty() else int(_rejoin["try"])
	_close("", false, true)
	_rejoin = {"host": host_name if host_name != "" else "the host", "try": tries}
	_schedule_rejoin()


## Guest: the next reconnect try, or giving up after the last one.
func _schedule_rejoin() -> void:
	var tries := int(_rejoin.get("try", 0))
	if tries >= RECONNECT_DELAYS.size():
		_stop_rejoin(true, "Couldn't get back into %s's session. Click Join to try again." % String(_rejoin.get("host", "the host")))
		return
	_rejoin["try"] = tries + 1
	_rejoin["wait"] = RECONNECT_DELAYS[tries]
	set_process(true)
	_set_status("Lost the connection to %s. Trying to get back in (try %d of %d)..." % [
		String(_rejoin["host"]), tries + 1, RECONNECT_DELAYS.size()], true)


## Guest: a reconnect try couldn't reach the host.
func _rejoin_failed() -> void:
	if _role == "guest":
		_close("", false, true)
	if not _rejoin.is_empty():
		_schedule_rejoin()


## Guest: stops reconnecting. clear_audience: go back to this PC's own audience and looks.
func _stop_rejoin(clear_audience: bool, message: String = "") -> void:
	if _rejoin.is_empty() and not clear_audience:
		return
	var was := not _rejoin.is_empty()
	_rejoin.clear()
	_chat_held.clear()
	if clear_audience and _role == "off":
		_aud_shared = false
		_clear_net_looks()
		_apply_streamer_looks({})
		AudienceManager.set_mirror(false)
		AudienceManager.set_streamer_areas(0)
	if _role == "off":
		set_process(false)
	if message != "":
		_set_status(message, true)
	elif was:
		_emit_state()


# ── Connection helpers ───────────────────────────────────────
## A WebSocket peer with buffers big enough for a whole audience roster.
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


## Host: while waiting for the tunnel, looks for its address in cloudflared's log each frame.
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


## Host: stops cloudflared (on leaving or closing).
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
## True while the connection to the other side is up (a dropped one is still "guest" until the
## deferred _close runs: nothing may be sent then).
func _connected() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## The scene's multiplayer API (it's SceneMultiplayer, which has the auth step).
func _sm() -> SceneMultiplayer:
	return multiplayer as SceneMultiplayer


## Guest: true when the current RPC came from the host. Every host-only RPC checks this first.
func _from_host() -> bool:
	return _role == "guest" and multiplayer.get_remote_sender_id() == 1


## The host, or a guest the host ticked as co-host.
func _is_cohost() -> bool:
	if _role == "host":
		return true
	if _role != "guest":
		return false
	var me := multiplayer.get_unique_id()
	return _peers.has(me) and bool(_peers[me]["cohost"])


func _peer_name(id: int) -> String:
	return String(_peers[id]["name"]) if _peers.has(id) else "Guest"


## Host: who is in the session, to every guest (and the panel through _emit_state).
func _send_roster() -> void:
	var list: Array = []
	for id: int in _peers:
		list.append({"id": id, "name": String(_peers[id]["name"]), "cohost": bool(_peers[id]["cohost"]), "avatar": String(_peers[id].get("avatar", "")),
			"keyed": bool(_peers[id].get("keyed", false)), "remote": id == _remote_id, "asked": bool(_peers[id].get("asked", false))})
	_to_guests("_net_roster", [list])
	_to_guests("_net_podiums", [_podiums])
	_emit_state()
	_emit_live()            # (the podium list changed)
	_to_guests("_net_live", [_live_info_for_guests()])   # (the person sharing the big screen may have left)


## Host: call an RPC on every connected guest.
func _to_guests(method: String, args: Array) -> void:
	for id: int in _peers:
		if id != 1:
			callv("rpc_id", [id, method] + args)


## The Co-stream tab's status line; also shown as a status message, so never put an address in it.
func _set_status(text: String, is_error: bool = false) -> void:
	_status = text
	_error = is_error
	EventBus.status_message.emit(text, is_error)
	_emit_state()


## Tells the panel the session changed (EventBus.net_state_changed with get_info()).
func _emit_state() -> void:
	EventBus.net_state_changed.emit(get_info())


## The app version (Project Settings > application/config/version); host and guests must match.
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
