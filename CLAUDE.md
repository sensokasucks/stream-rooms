# Stream Rooms: notes for Claude Code

Stream Rooms is a Redot 3D app for live streaming. A room (lecture hall, theater, classroom, drive-in, neon city, studio...) has a big screen showing a browser tab, a video file / URL or an NDI source. The screen lights the room. Chat from Twitch / Kick / YouTube sits in the room as a virtual audience, and chat reactions (🍅 tomatoes, confetti...) play in 3D. The streamer captures the window in OBS.

The owner streams with it. Changes should be practical, tested and explained in plain language (they are not a professional programmer).

**Current big task: multiplayer.** Read `docs/MULTIPLAYER.md` before starting on it.

## Engine and machine

- **Redot 26.2** (Godot 4.5-based), **Forward+** renderer, Windows, RTX 3080. GDScript only.
- `project.godot` features: `"26.2", "Forward Plus", "Redot"`. Don't change the renderer.
- New `.gd` files get a `.gd.uid` file when the editor opens them. Keep the `.uid` files (and commit them).
- Optional NDI support comes from the `addons/godot-ndi` GDExtension (patched; the original is in `_backup/`). The app must keep working when the extension isn't there.
- Optional Spout input comes from the `addons/godot-spout` GDExtension (built here for Redot's 4.5 API with Vulkan, patched; see its `STREAM_ROOMS_PATCH.md`). Same rule: the app must keep working without it. `core/spout_receiver.gd` looks it up by name.
- `tools/` holds `ffmpeg.exe` and `yt-dlp.exe` (used by `core/video_loader.gd`) and `cloudflared.exe` (the Together tab's Cloudflare tunnel, `autoload/net_session.gd`). `tools/get_tools.ps1` downloads all three.

## Related project: Fridge Stream Core

Stream Core is a separate Python app (FastAPI). On the owner's PC it lives at `G:\AI\claude\FlaVR_leftovers\fridge-stream-core`. It connects to the chat platforms and handles commands, points, games, alerts and the rules for reactions.

- Stream Rooms connects to it at `ws://127.0.0.1:3850/ws` (`autoload/chat_feed.gd`).
- Reaction protocol: `fridge-stream-core/docs/REACTIONS.md` (`autoload/reactions.gd` is the game side).
- Stream Core files use **CRLF** line endings, so keep them. Stream Rooms files use LF.
- Stream Core rules: bind servers to `127.0.0.1`; saving config merges rather than replacing; live secrets (tokens, keys) stay in local config only and are never committed.

## Layout

- `autoload/`: singletons. Load order is in `project.godot`.
  - `EventBus`: signals only; this is how systems talk. `AppState`: settings plus app state. `SaveManager`: writes `user://settings.cfg`, debounced on every `setting_changed`.
  - `RoomCatalog`, `AudioManager`, `SystemMedia`, `ChatFeed` (Stream Core WebSocket), `AudienceManager` (who sits where), `EmoteCache`, `Reactions`.
- `core/`
  - `main.tscn` / `main.gd`: the scene with WorldEnvironment, ScreenFeed (CaptureServer, VideoLoader, VideoPlayer, StreamAudio), RoomHost, CameraRig, Hotkeys, FocusView, Overlay, BoardHud, ControlPanel and Fade.
  - `room_host.gd` loads rooms on a thread and fades between them. It also applies the room's Environment with graphics quality on top (`graphics_quality.gd`).
  - `screen_feed.gd` owns what the screen shows. Sources: `file` (VideoLoader → Theora `.ogv`, cached in `user://video_cache`), `capture` (a browser tab sends JPEG frames and PCM audio from `web/sender.html` to CaptureServer on 127.0.0.1 ports 8765/8766), and `ndi`.
  - Other folders: `audience/` (audience view, crowd layer), `presenters/` (podium presenters, up to 4), `reactions/` (ReactionLayer per room), `camera_rig.gd`, `hotkeys.gd`, `side_chats.gd` / `chat_screen.gd`, `stage_curtain.gd`.
- `rooms/<id>/`: `room_info.tres` (a RoomInfo: id, name, scene, Environment, reverb...), the `.tscn` room scene, and its script (extends `rooms/room.gd`).
- `ui/control_panel.gd`: the whole control panel (tabs: Source, Room, React, Sound, Chat, Audience, Seating, Games, Presenters), plus the seating chart, focus view, board HUD and overlay.
- `_tests/`: scene tests (see below). `web/`: the sender page and backdrop. `exported/`: built exes (don't edit).
- Build a standalone exe with `tools/export.ps1` (headless export into a fresh `exported/StreamRooms_<date>` folder, checks the .pck, copies `tools/`). Keep the preset's **Shader Baker off** and **Export Mode = all resources**: baked shaders froze a PC with another GPU, and the editor's export dialog can silently put old settings back into `export_presets.cfg`.

## Conventions

- **Communication:** emit or connect through `EventBus` signals. Don't use `get_node("../..")` chains between systems. Read and write settings only through `AppState.get_setting` / `AppState.set_setting`.
- **New settings:** add them to `AppState.DEFAULTS` with a short comment. **The type matters:** saved values whose type doesn't match the default are ignored on load, so use `60` for an int and `1.0` for a float. React to changes with `EventBus.setting_changed`.
- **Control panel:** build UI with the helpers in `control_panel.gd`: `_tab`, `_heading`, `_hint`, `_slider(key, label, lo, hi, step, fmt, scale)`, `_check`, `_option(key, label, [[value, "Label"], ...])`, `_text_setting`, `_color`, `_button`. They bind to settings and stay in sync automatically.
  - Give every control a `tooltip_text`. `_add_help_buttons` turns those into "?" buttons (an accessibility feature).
  - Keyboard mode: F6 enters it and Esc leaves it. Hotkeys are skipped while focus is inside the `keyboard_panel` group.
- **Accessibility:** flashes and strobes must respect `flash_strength` and `photosensitive_safe` (see `core/reactions/reaction_layer.gd`). Camera shake turns off in safe mode.
- **Performance:** the filler crowd is one MultiMesh draw. Per-chatter cost is what grows. Work that runs every frame should only happen while something changes (for example, the camera moving).
- **Style:** typed GDScript, tabs, a `##` comment at the top of each file explaining what it is for, and short comments on the "why".
  - Gotcha: `var x := arr.filter(...)` fails type inference, so write `var x: Array = ...`.
- **Art:** original designs only. No copyrighted characters, logos or likenesses.
- **README.md** is for the user. It uses plain language, **bold** control names that match the panel labels exactly, and a section per feature. Update it with every feature.

## Tests

Each test in `_tests/` is a scene (`test_x.tscn` plus `test_x.gd`). It builds `core/main.tscn`, drives it, and prints results. The newer tests print `PASS ...` / `FAIL ...` lines; the older ones print values to compare between runs. The first user argument is an output folder for screenshots. Keep it **outside** the project folder, or the editor imports the PNGs.

**Run tests with `tools/run_tests.ps1`** (default: the regression set below):

```
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Tests test_crowd,test_reactions -SkipImport
```

It rebuilds the editor's class cache first, runs each test one at a time with `--mp-profile=test` from a fresh `settings_test.cfg` (so tests start from the defaults and **never touch the owner's live `settings.cfg`**), stops a test after a time limit, and prints a table of PASS / FAIL / script errors. Logs and screenshots go to `C:\temp\sr_tests`.

- Redot console exe: `G:\streamin dings\Redot_v26.2-stable_windows_win64\redot.windows.editor.x86_64.console.exe`.
- Write tests so they set every setting they depend on; they start from the defaults.
- If scripts fail with "Identifier ... not declared", the editor's class cache in `.godot/` is stale. The runner fixes that (or run the exe with `--headless --path . --import`).
- Every test should end with "exit 0" in the runner table. Anything else means Redot crashed (the old quit crash in the NDI plugin is fixed; see `addons/godot-ndi/STREAM_ROOMS_PATCH.md`).
- Running a test by hand without a profile still changes the live settings: back up `settings.cfg` first (Redot app_userdata folder, `Stream Rooms`).
- Good regression set after audience, panel or room changes: `test_performance`, `test_accessibility`, `test_crowd`, `test_platform_split`, `test_reactions`, `test_mp_profile`, `test_together`, `test_panel_clicks`, `test_spout`, `test_watch_together`, `test_mic_safety`, `test_shared_audience`.
- `test_sender_background` opens a visible Chrome that captures the first monitor (`?autoshare` + `--auto-select-desktop-capture-source=Screen 1`) and checks the frame rate holds with the tab in the background; run it on its own: `-Tests test_sender_background -TimeLimit 600`. The sender page's picture work runs in a Web Worker for this reason (`WORKER_SRC` in `web/sender.html`); Chrome can't hand a display track to a worker, so the page reads frames and hands each one over.
- `test_live_feed` needs the internet (VDO.Ninja) and Google Chrome, so run it on its own: `-Tests test_live_feed -TimeLimit 300`. `test_tunnel` needs the internet and `tools/cloudflared.exe`: `-Tests test_tunnel -TimeLimit 400`.
- Known open issue (Oct 2026): some tests (crowd, performance, reactions, accessibility, spout) sometimes end with an access-violation exit code after all their results are printed. It comes and goes between runs and isn't tied to one plugin; the Windows event log shows the fault inside the Redot exe. Judge those runs by their PASS / FAIL lines and rerun; still to be tracked down.
- Run tests while the owner's own Stream Rooms / VTube Studio / sender pages are closed: a running Spout sender or a sender page connected to a test profile's ports can make `test_spout` fail.
- Look at the screenshots a test saves. Many bugs are visual.

## Working rules

- The project wasn't under version control before this handoff. If git has been set up, commit after each working step. If it hasn't, suggest it first (a `.gitignore` is already in place).
- Don't delete the owner's files without asking. Keep `exported/`, `_backup/` and the big `.ogv` files out of edits.
- After a feature: update the README, add or extend a test, and run the regression set.
- The owner's to-do list and design notes live in their Claude project ("youtube player" → `claude/todo.md`). Tell them what changed so it can be updated there.
