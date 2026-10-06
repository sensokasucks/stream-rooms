extends Node
## EventBus: cross-system signals only. No state, no logic.

# ── Screen / video ───────────────────────────────────────────
## The texture currently shown on the screen changed (new source, or first frame).
signal screen_texture_changed(texture: Texture2D)
## Average colour of the left / centre / right thirds of the current frame.
signal screen_colors_changed(left: Color, center: Color, right: Color)
## Webcam texture from the browser sender (null when the webcam stops).
signal webcam_texture_changed(texture: Texture2D)
## Which source feeds the screen: "none", "file", "capture" or "ndi".
signal source_changed(mode: String)
## True while the screen is actively playing (not stopped / paused).
signal playback_active_changed(active: bool)

# ── Requests (UI / hotkeys -> systems) ───────────────────────
signal file_play_requested(input: String)
## Streaming together: load a file / URL like file_play_requested, but stop on its first frame
## (paused at 0) and announce file_prepared instead of playing, so every PC can start together.
signal file_prepare_requested(input: String)
signal file_prepared(input: String)
signal file_prepare_failed(input: String, message: String)
## Streaming together: put the playing file at this position (seconds), playing or paused.
## Small differences are left alone (see ScreenFeed.SYNC_TOLERANCE_S).
signal file_sync_requested(position: float, playing: bool)
## The playing file's position, about once a second and whenever it pauses / resumes.
signal file_progress(position: float, playing: bool)
signal file_stop_requested
signal file_pause_toggle_requested
signal camera_preset_requested(index: int)

# ── Reaction features ────────────────────────────────────────
signal react_pause_changed(paused: bool)
signal focus_view_changed(on: bool)
signal clean_feed_changed(on: bool)
## The stage curtain in front of the main screen: closed or open.
## style: "normal" | "instant" (no animation, e.g. a room change) | "reveal" (the lights-down,
## drum-roll opening). While closed, nothing on the screen reaches the stream.
signal curtain_changed(closed: bool, style: String)
## The curtain started / stopped hiding the screen (sound mute, focus view, screen light).
signal curtain_covering_changed(covering: bool)
signal mic_level_changed(db: float)
signal ducking_changed(ducking: bool)

# ── Rooms ────────────────────────────────────────────────────
signal room_requested(room_id: String)
signal room_changed(room_id: String)
signal camera_presets_changed(names: PackedStringArray)
## Room-specific controls for the Room tab: an Array of Dictionaries (see Room.get_controls()).
signal room_controls_changed(controls: Array)

# ── Capture link ─────────────────────────────────────────────
## Keys: connected (bool), fps (float), has_audio (bool),
## suppress_local_audio (bool), webcam (bool), url (String)
signal capture_status_changed(info: Dictionary)
## A presenter feed's picture (camera / tab from the sender page); null when it stops.
signal presenter_texture_changed(presenter: int, texture: Texture2D)   # presenter = 1..4
## How many presenter podiums the current room has (0 = none).
signal room_presenters_changed(count: int)
## A presenter spot started / stopped showing its linked chatter's chat look (AudienceView);
## the presenter hides its own silhouette picture meanwhile.
signal presenter_look_changed(presenter: int, chat_look: bool)

# ── NDI (addons/godot-ndi) ───────────────────────────────────
## NDI sources on the network changed (names), or the plugin isn't loaded (available = false).
signal ndi_sources_changed(names: PackedStringArray, available: bool)
## UI -> ScreenFeed: show this NDI source on the main screen / stop it.
signal ndi_connect_requested(source_name: String)
signal ndi_stop_requested

# ── Spout (addons/godot-spout) ───────────────────────────────
## Spout senders running on this PC changed (names), or the plugin isn't loaded (available = false).
signal spout_senders_changed(names: PackedStringArray, available: bool)
## UI -> ScreenFeed: show this Spout sender on the main screen / stop it.
signal spout_connect_requested(sender_name: String)
signal spout_stop_requested

# ── Settings / messages ──────────────────────────────────────
signal setting_changed(key: String, value: Variant)
signal status_message(text: String, is_error: bool)
## Chat source (ChatFeed): {"connected": bool, "url": String, "error": String}
signal chat_status_changed(info: Dictionary)
## One normalized chat message (see ChatFeed._normalize for the keys).
signal chat_message_received(msg: Dictionary)
## Late info about a chatter from Stream Core: {"platform", "user_id", "avatar"}
signal chat_user_updated(info: Dictionary)
## Stream Core answered a chat command (its API-free reply path: {message, platform,
## reply_to_user, source, timestamp, history}). Shown on the reply screen.
signal core_reply_received(reply: Dictionary)
## Audience roster (AudienceManager). Views look members up with AudienceManager.get_seat_member().
signal audience_seated(slot: int)
signal audience_left(slot: int)
## parts: Strings and emote Dictionaries {"url": String, "name": String}, in order.
signal audience_spoke(slot: int, parts: Array)
## EmoteCache finished downloading an emote image.
signal emote_ready(url: String)
signal audience_count_changed(seated: int, capacity: int)
## Something about the person in a seat changed (e.g. their picture arrived).
signal audience_updated(slot: int)
## The seating layout or plan changed (sections, platforms allowed): the seating chart redraws.
signal seating_changed()

# ── Chat reactions (Stream Core -> Reactions -> the room's ReactionLayer) ─────
## A "reaction" packet from Stream Core (ChatFeed). Reactions decides whether to play it.
signal reaction_received(data: Dictionary)
## Reactions -> the current room's ReactionLayer: play this reaction now.
signal reaction_play(data: Dictionary)
## ReactionLayer -> Reactions: how it went ("hit" | "fallback" | "dropped").
signal reaction_finished(reaction_id: String, outcome: String)
## An applause / boo meter moved (value 0..goal). value 0 after a payoff or when it empties.
signal reaction_meter_changed(meter_id: String, label: String, value: float, goal: float)
## Shake the camera a little (strength ~0.05..2, seconds).
signal camera_shake_requested(strength: float, seconds: float)

# ── Chat games (Stream Core boards: polls, predictions, hype meter, heists, trivia ...) ──
## A board appeared or changed: {id, kind, title, lines:[{key,label,value,pct,note,win}],
## footer, ends_at, state: "open" | "locked" | "closed"}. Drawn by BoardHud and the reply screen.
signal board_changed(board: Dictionary)
## A board went away.
signal board_cleared(board_id: String)


# ── Streaming together (NetSession, docs/MULTIPLAYER.md) ─────
## The session changed: {role: "off" | "host" | "guest", status: String, error: bool,
## address: String, cohost: bool, peers: [{id, name, cohost}]}. NetSession.get_info() has the same.
signal net_state_changed(info: Dictionary)
## Someone else's camera moved (peer id, their name, camera transform in the room).
signal net_camera_moved(peer_id: int, peer_name: String, xform: Transform3D)
## Someone left the session (their camera marker goes away).
signal net_peer_left(peer_id: int)
