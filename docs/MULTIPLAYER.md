# Multiplayer rooms: plan

Status: planned, not started (October 2026). The owner agreed on the overall shape. Questions still open are listed at the end; **ask the owner before deciding them**.

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
- The owner and guests connect over **Tailscale** (free; guests join by the host's 100.x address). Nobody opens router ports. WebRTC (`WebRTCMultiplayerPeer`) could come later so guests don't need Tailscale.
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

## Open decisions (ask the owner)

- **Reactions:** when a viewer on a guest's channel throws a tomato, does everyone see it, or only that guest?
- **Guest permissions:** can guests change the room, curtain or screen, or only the host? Maybe a per-guest "co-host" tick.
- **Panel name** for the multiplayer tab, and whether guests see the host's controls as locked or hidden.
- **Guest hardware:** every guest renders the full room while streaming. Should joining suggest Medium or Low graphics quality?
- **Copyright:** synced playback means up to four channels broadcasting the same video. It's the same risk as one channel today, multiplied. Worth stating in the README.
