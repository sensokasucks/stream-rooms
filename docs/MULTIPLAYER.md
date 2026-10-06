# Multiplayer rooms: plan

Avatars (October 2026): every peer gets an avatar stream name (`_peers[id]["avatar"]`, in the roster); `NetSession.avatar_slots()` maps streamer k (host, then guests by peer id) to podium k+1, and the live-feed info carries `avatars` and the host's `quality`. `ScreenFeed._sync_presenter_feeds` marks my podium `publish` and the others' `view`; the sender page publishes my presenter feed on a second VDO.Ninja connection (`avatar.*`) as a constrained clone (height / fps / maxBitrate from the quality settings) and views the others', feeding them into the normal presenter frame pump. On guests, camera / tab sources of podiums that have a streamer stay (not silhouettes): `_source_here()` / `_refresh_sources()`. `_tests/test_avatars` (internet + Chrome) checks both directions. Profiles for extra copies must have different port offsets (a number at the end).

Share groups (October 2026): `together_share_room` / `_curtain` / `_presenters` (host). `NetSession._group_of(key)` maps a key to a group; an unshared group isn't broadcast, isn't in the snapshot, isn't locked on guests, and the guest's gate lets local changes through. Switching a group back on sends the flags plus a partial snapshot of that group. Presenter name tags (`presenter_n_name`) are an ordinary shared field; podium pictures (`presenter_n_picture`, a file path) travel as bytes (`_net_picture`, PictureFile checks type and size, ≤ 3 MB) and land in the guest's `user://podium_pictures/`.

Privacy (October 2026): the session runs on `WebSocketMultiplayerPeer` (was ENet) so it can go through a Try Cloudflare quick tunnel: `together_bind` = "tunnel" runs `tools/cloudflared.exe tunnel --url http://127.0.0.1:<port> --logfile ...`, reads the `https://*.trycloudflare.com` address from the log, warms it up with one HTTPRequest (a fresh tunnel's first connection is slow; handshake and auth timeouts are 20 s), then offers it through "Copy address" (never on screen or in a status message; the guest's address box is `secret`). Guests type anything: `join_url()` makes `wss://` for trycloudflare names, `ws://host:port` otherwise. Round-trip time comes from a ping RPC now (ENet stats are gone). `together_live_relay` sets `forceTURN` in the VDO.Ninja SDK on every browser. `_tests/test_tunnel` hosts a real tunnel and joins through it (internet; not in the default set). A proxy for guests isn't possible: Redot's WebSocket client has no proxy support (godot-proposals #10781).

Status: Phase 4 built (October 2026): one audience. The host's `AudienceManager` seats everyone (`add_chat`; guests forward their chat with `_net_guest_chat`, tagged with a streamer index), and can split sections per streamer (`set_streamer_areas`: quadrants, then crowd levels in runs). Guests run `AudienceManager` as a mirror (`set_mirror`): they seat nobody and apply the host's roster per room (`mirror_roster` / `_seat` / `_leave` / `_speak` / `_update`), so slot numbers match on every PC. Only https pictures (emotes, avatars) are accepted from the network. `_tests/test_shared_audience` checks matching seats before and after a room change.

Phase 3 built (October 2026): the host's sender page publishes its shared tab with the VDO.Ninja SDK (bundled as `web/vdoninja-sdk.min.js`, served by CaptureServer), under a random stream name and key per session (`NetSession` "Live feed"); a guest's sender page views it ("Watch the host's live feed") and feeds it into the normal capture path, so no new video code in the game. `_tests/test_live_feed` runs it end to end with headless Chrome (`?testshare` / `?autowatch` on the sender page); it needs the internet, so it's not in the default set. Camera markers near your own camera now hide.

Phase 2 built (October 2026): synced web videos (`NetSession` "Synced video" section, `ScreenFeed` prepare / sync), tested with a host and two guests on one PC (`_tests/test_watch_together`: they stay within ~0.02 s, including pause, a jump and a late joiner). Theora seeking in Redot 26.2 works and takes 20-80 ms. Each profile has its own video cache (`user://video_cache_<profile>`), so copies on one PC don't convert into the same file.

Phase 1 built (October 2026): `--mp-profile`, `autoload/net_session.gd` (host / join, password challenge, version check, co-hosts), the Together tab, shared room / curtain / house lights / presenters, reactions for everyone, camera markers (`core/net_markers.gd`). Tested with copies on one PC (`_tests/test_together`); still to do for Phase 1: two PCs over Tailscale. The owner's answers to the open questions are at the end.

Implementation notes:
- Guests are stopped by `AppState.net_gate` (room, curtain and shared setting keys). A co-host's change goes to the host as a request and comes back with the host's broadcast.
- The password is checked in SceneMultiplayer's authentication step (nonce + SHA-256), so nothing can be called before it passes. `server_relay` is off; the host forwards reactions and cameras.
- Reactions: each PC keeps its own Stream Core rules and results. A reaction played on any PC is sent to the host and on to the others with a `seed` (ReactionLayer seeds the RNG with it) and an id starting `net-`, so nobody reports it to Core twice. `object_image` is dropped (it's on the sender's Core).
- Close the ENet peer with `call_deferred` from network signals: closing inside SceneMultiplayer's poll crashes the engine.

## Goal

Up to 4 people are in the same room at once. One **host** runs the show and streams. Up to three **guests** each fly their own camera around the room and stream their own view to their own channel. The big screen is shared, and optionally the side screens and the audience too.

## Architecture

**Every person runs their own copy of Stream Rooms** and renders the room from their own camera. Each streams from their own OBS. **No video of the room is sent between machines**, only small state messages. This keeps bandwidth tiny and latency low.

**The host is authoritative.** Guests send requests, the host decides, and the host broadcasts the result. Guests never change shared state on their own.

| Shared (host) | Local (each person) |
|---|---|
| Room choice, curtain, house lights | Camera rig, camera presets, field of view |
| Big screen: source, video, play/pause/seek | Graphics quality, frame rate cap, panel layout |
| Reactions (what plays, where, when) | Side chat windows (their own chat) |
| Presenters / podiums | Their own Stream Core connection |
| Audience seating (phase 4, optional) | |

### Networking

- A new autoload, e.g. `NetSession` (`autoload/net_session.gd`). Don't name it `Multiplayer`, because that clashes with `Node.multiplayer`. Use Redot's high-level multiplayer (`ENetMultiplayerPeer`, `@rpc`). Peer 1 is the host.
- The owner and guests connect over **Tailscale** (free; guests join by the host's 100.x address) or a **Cloudflare tunnel** (see Privacy above). Nobody opens router ports.
- **Security.** This is the first server in Stream Rooms that isn't bound to 127.0.0.1, so:
  - Require a **session password**: a handshake RPC right after connecting, with a kick on failure or a timeout.
  - Bind to the Tailscale interface where possible.
  - Accept shared-state RPCs **only from peer 1**, and accept only **whitelisted** setting keys.
  - Guests must **never** run a file path from the network. A URL sent to play must be `http(s)://` and go through VideoLoader's normal URL path (yt-dlp). Reject local paths, `file://` and anything else, so a host can't make a guest's PC open local files.
- **Version check** in the handshake: refuse to join a different Stream Rooms build and say so in plain language.

### Shared settings

Most shared state is already an `AppState` setting or method, so sync works by key:

- Keep a whitelist of shared keys and methods (room via `AppState.request_room`, curtain via `set_curtain` / `reveal_curtain`, `house_lights`, the `presenter_*` keys, the screen source...).
- Host side: on `EventBus.setting_changed` for a shared key, broadcast it. Guest side: apply it with an "applying remote" flag so it isn't echoed back.
- A guest changing a shared control sends a request to the host (if the host allows it). Otherwise the control shows as locked, with a tooltip saying the host controls it.

### Reactions

`Reactions` receives reactions from the host's Stream Core and emits `EventBus.reaction_play`. The host forwards the same data to guests with a **random seed** and a start time, so throws land in roughly the same places on every screen. Exact physics matching isn't needed.

### Big screen

- **Synced playback (file / URL source).** The host sends `load(url)`, and each PC downloads and converts it with its own VideoLoader. That can take a while, so use a **ready barrier**: everyone reports "ready", then the host starts everyone at the same moment. Send a position heartbeat about once a second, and have guests seek when they drift more than about 0.3 s. Theora seeking in VideoStreamPlayer can be slow or imprecise, so test it early. Each person hears the audio from their own copy.
- **Live content (browser-tab capture, games).** Tab capture only exists on the host's PC. The cheapest route reuses what's already built: the host publishes their screen with **VDO.Ninja**, guests open the view link in a browser tab, and they capture that tab with the normal "Showing a browser tab" flow (`web/sender.html` → CaptureServer). Little or no new video code is needed; mostly a guided setup in the panel. It adds about 0.2–1 s of latency, and the host uploads roughly 3–6 Mbps per guest. Don't relay CaptureServer's JPEG frames over the network: that's tens of Mbps per guest.

### Seeing each other

- Guests appear as **presenters at podiums**, using the presenter "web page" source with a VDO.Ninja webcam link. Voice stays on Discord, and each person captures it in their own OBS.
- Optional and cheap: sync each person's camera transform at about 10 Hz and draw a small floating camera with their name, so everyone can see where the others are looking.

### Merged audience (phase 4, optional)

- The host's `AudienceManager` becomes the only source of truth for seating. Guests stop seating their own chat and instead receive `audience_seated` / `audience_left` / `audience_spoke`-style events from the host.
- Each guest forwards its chat messages (from its own Stream Core) to the host, tagged with the channel they came from.
- Use the seating sections to give each streamer's viewers their own area. Sections already exist (Q1–Q4 and the crowd sections), but the seating plan maps sections to *platforms* (kick / twitch / youtube / other); it would need a per-channel group added.

### Stream Core

Each streamer keeps their own Stream Core, and **mostly nothing changes**. Extras are only needed for cross-channel features: chat games across all four audiences, shared points, feedback on permissions, and an optional channel tag on chat events.

## Testing on one PC

Two copies on one PC would fight over `user://settings.cfg` and the capture ports (8765/8766). So add a command-line profile first, for example `-- --mp-profile=guest1`, that:

- uses `user://settings_guest1.cfg`,
- offsets the capture ports,
- shows the profile name in the window title.

Then run a host plus one or two guests side by side. Write automated scene tests where possible: start a host and a guest in one test scene, or in two processes with a script, and check that state arrives.

## Phases (each one shippable on its own)

1. **Profiles + session + shared state.** Covers the `--mp-profile` flag; host and join in a new panel tab ("Together"?) with address, password and a list of who's connected; version check; the shared room, curtain, house lights and presenters; reactions mirrored; camera markers. Done when two copies on one PC, then two PCs over Tailscale, stay in sync through room changes, curtain and reactions, and a wrong password or version is refused cleanly.
2. **Synced playback** of files and URLs, with the ready barrier and drift correction. Done when two PCs play a 10-minute YouTube video together and stay within about 0.3 s, including pause, seek and a late joiner.
3. **Live feed** from the host via VDO.Ninja, plus the guided guest setup.
4. **Merged audience** (optional): seating owned by the host, chat forwarded from guests, sections per streamer.

Update README.md (a new "Streaming together" section) and the tests in each phase.

## Decisions (owner, 5 October 2026)

- **Reactions:** a tomato thrown by a viewer on any channel (host or guest) plays for **everyone** in the room.
- **Guest permissions:** only the host changes the room, curtain and screen. The host can tick **co-host** per guest to let that guest change them too.
- **Panel:** the tab is called **Together**. Guests see host-only controls **locked** (greyed out) with a tooltip saying the host controls them, not hidden.
- **Guest hardware:** joining as a guest **suggests Medium** graphics quality, and the guest can say no.
- **Copyright:** the README states the risk plainly (done, in "Streaming together").
