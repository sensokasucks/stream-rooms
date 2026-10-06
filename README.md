# Stream Rooms (Redot)

Swappable 3D rooms with a screen that shows a **shared browser tab** (live, e.g. YouTube in
Brave) or a **video file / URL**. The picture lights the room, and there are tools for
reaction streams.

Needs Redot 4.3+ (Forward+). Open `project.godot` in Redot, let it import, and press **F5**.

---

## Showing a browser tab (recommended)
1. Run the game.
2. In the panel's **Source** tab, click **Open sender page**. It opens `http://127.0.0.1:8765/`.
   Open it in Brave (or Chrome/Edge). Firefox can't share tab audio.
3. Click **Share a tab or window**, pick the YouTube tab, and leave **"Share tab audio"** on.
4. The tab appears on the screen within a second or two. Keep the sender page open. A small
   separate window works best, because browsers slow down hidden tabs.

The sender page can sit behind other tabs: the picture work runs in a background worker, which
browsers don't slow down the way they slow down a tab that isn't in front. (Keeping it in its own
small window still works too.) Don't minimise the whole browser window: Windows stops drawing a
minimised window, and a shared tab in it may stop producing frames.

**No double audio:** the sender asks the browser to silence the shared tab
(`suppressLocalAudioPlayback`) and sends its sound to the game instead. The sender page and the
game's Source tab both warn you if the browser couldn't silence it. If that happens, mute the tab.

**Lip-sync:** the picture travels a longer path than the sound, so audio is delayed by 150 ms by
default. Adjust **Audio delay** or **Video delay** in the *Sound* tab.

**Webcam:** click **Start webcam** on the sender page. It shows on the room's picture frame
(`WEBCAM_Frame`), or as a corner overlay if the room doesn't have one.

## Playing a file or URL (fallback)
Type a path or a YouTube URL in the *Source* tab, or click **Browse...**. Non-`.ogv` files and URLs
need `yt-dlp` and `ffmpeg`: right-click `tools/get_tools.ps1` > *Run with PowerShell*.

## Hotkeys
| Key | Action |
|---|---|
| **Space** | Pause to react. Pauses a file directly. For a browser tab it sends the Windows Play/Pause media key. Lights come up, the camera moves to the room's *Reaction* camera, and a badge shows. |
| **F** | Focus view: the video flat and full-frame, so viewers can read it. |
| **1-9, 0** | Camera presets (smooth moves). **0** is the 10th preset. |
| **PgUp / PgDn** | Previous / next room. |
| **F10** | Clean feed: hides all UI (the webcam overlay stays). |
| **Tab** | Show/hide the control panel. |
| **F11** | Fullscreen. |
| **C** | Chat screen on/off (rooms that have one). |
| **R** | Reply screen on/off (rooms that have one). |
| **B** | Stage curtain: close / open. **Shift+B** = the reveal (lights down, spotlight, drum roll, curtain sweeps open). |
| **F9** | Control panel in its own window / back in the main window. |
| **F6** | Work the control panel with the keyboard (see *Accessibility*). Esc leaves. |
| **Ctrl+= / Ctrl+-** | Control panel bigger / smaller. |
| Right-drag, WASD, Q/E, Shift | Free-look camera: hold the right mouse button and move to look; W/S forward/back, A/D left/right, **Q down / E up**, Shift = 3x speed. **Mouse wheel while right-dragging** = zoom (field of view). |

Hotkeys are ignored while you're typing in a text box (Esc leaves the box).

**Field of view:** Room tab → *Field of view* (25–110°, default 65), or the mouse wheel while
right-dragging. **See into the room from outside** (Room tab, on by default): back the camera out
through a wall and the wall (and anything else between you and the room) is cut away instead of
the view going black. It kicks in when none of the room's camera markers can see the camera; the
walls get collision shapes for this (only these rays use them).

**Auto-duck:** in the *React* tab the video audio drops (14 dB by default) while your mic hears
you, then comes back up. Set **Talk threshold** by watching the mic meter. Windows may ask for
microphone permission the first time.
On some PCs starting the microphone freezes the game (it happened on a PC with no speakers set up).
The game notices: the next start switches **Lower the video while the mic hears me** off and says
so. Starting with `-- --no-mic` (or **Start without microphone.bat** next to an exported game)
does the same on purpose.

### Chat windows by platform (Chat tab)
Twitch's terms ask for its chat to be kept apart from other platforms' chat, so every chat
window picks its own sources. There are four windows:
- **Left of the screen** / **Right of the screen:** tall, thin windows beside the main screen,
  in every room with a screen. Width, height (share of the screen's), gap and up / down are
  per window. By default the left one shows Twitch and the right one Kick + YouTube + other.
- **Under the screen** (chat screen) and **Above the screen** (reply screen), in rooms that
  have them.

For each window:
- **Show** turns it on or off.
- **Chat from:** tick one platform to give it a window of its own, or several to mix them.
  None ticked = no chat in that window. A warning shows when Twitch is mixed with others.
- **Stream Core replies:** *Off*, *Always*, or *When there's no reply screen* (only in rooms
  without one, or with it switched off). Chat games boards come along with replies.
- **Replies to:** *Every platform's chatters*, or *Only this window's platforms* (so Twitch
  answers stay in the Twitch window). The side windows start on *Only this window's
  platforms*, the panels under and above the screen on *Every platform's chatters*. A window
  with no chat ticked always takes every reply.
- **▾ settings** next to a window's name folds its settings away (remembered), so the tab
  stays short when you only tweak one window.
- **Header:** a header line across the top of the window. Leave the text empty to name it
  after what it shows ("Twitch chat", "Kick · YouTube chat", "Stream Core replies"); a
  one-platform window's header takes that platform's colour. On by default for the side
  windows.
- Text size, background and columns.

The side windows always stand in front of the stage curtain (0.4 m in front of it). Rooms can
nudge them further with `side_chat_extra_gap`, `side_chat_height_scale` and
`side_chat_forward` on the room's root node (the Lecture Hall brings them 1.2 m forward and
makes them two-thirds of the screen's height). `presenter_forward` moves a room's presenter
spots and podiums towards the audience (Lecture Hall (Panel): 0.6 m, clear of the windows).

## Seating by platform (Seating tab)
Keeps each platform's chatters physically apart in the audience.
- **Sections:** the main seats are four quadrants as the audience faces the stage:
  **Q1** front left, **Q2** front right, **Q3** back left, **Q4** back right. The Lecture
  Hall's crowd seats are stadium sections: **101-105** lower tier, **201-205** balcony,
  **301-305** gallery, numbered from the audience's left round the back to the right.
- **Seat chatters by platform** turns the plan on. Click a section on the **seating chart**
  (or pick it in the list), then tick who may sit there: one platform, several (mix and match),
  or none (anyone).
- **Keep platforms apart when their seats are full:** on, a chatter whose platform's seats are
  all taken waits for one (or bumps their own platform's quietest chatter); off, they sit
  anywhere free.
- **Presets:** *Anyone anywhere*, *Twitch apart (left)* (Twitch in Q1 + Q3 and the left crowd
  sections, everyone else on the right), *A quadrant each* (Kick Q1, Twitch Q2, YouTube Q3,
  other Q4; the crowd sections take turns on each level: 101 Kick, 102 Twitch, 103 YouTube …).
  In *Twitch apart*, the crowd's left sections on each level (101-102, 201-202, 301-302) are
  Twitch's.
- **Re-seat everyone now** moves people already seated into their platform's sections
  (a plan change does this too). Moves and swaps across the plan are refused.
- **The chart:** top-down view with the stage at the top, one floor at a time: **Bottom
  floor** (the quadrants, the lower tier and the podiums) or **Top floor** (balcony and
  gallery), in rooms that have seats upstairs. Small dots are seats coloured by
  what their section allows (grey = anyone), big dots are chatters in their platform colour,
  and podium boxes are presenters. Below it, the number of seats each platform may use.

## Accessibility
- **Panel size** (bottom of the control panel, or Ctrl+= / Ctrl+-): 75-200%. Text, buttons
  and sliders all scale, in the main window and in the panel's own window.
- **Keyboard:** F6 puts the keyboard in the panel (a yellow outline shows where). Tab /
  Shift+Tab move between controls, Left / Right change a slider or switch tabs, Space / Enter
  press buttons and tick boxes, Esc gives the keys back to the hotkeys. Clicking with the mouse
  never leaves a button holding the keyboard, so Space still pauses after you click something.
  On the Seating tab the chart takes the arrow keys too (previous / next section).
- **Exact numbers:** click the value next to any slider (e.g. *75%*), type a number and press
  Enter. It's clamped to the slider's range.
- **Help you can see:** every setting with a tooltip has a yellow **?** beside it that shows
  the same help as a line under it.
- **Colour:** Audience tab → **Colour-blind safe colours** switches the platform colours to
  ones that stay distinct with red-green colour blindness (Okabe-Ito); **Brand colours** puts
  them back. The seating chart labels sections with letters (K T Y O: **K**ick,
  **T**witch, **Y**ouTube, **O**ther) as well as colour, and warnings start with ⚠.
- **Chat text on stream:** each chat window has **Text outline** (a dark edge round the
  letters, for a see-through background). The Chat tab warns when a window's text would be
  under about 16 px tall on a 1080p stream from the camera in use, and suggests a size.
- **Flashing lights** (Games tab): **Flash strength** (0-100%) sets how bright FLASHBANG,
  police lights, flicker, fireworks and fire get. **Photosensitive-safe mode** caps flashes at
  30%, slows strobes to under 3 flashes a second, makes FLASHBANG a soft swell and turns camera
  shake off.

## Performance and laptops (Room tab)
**Performance (this PC)** at the bottom of the Room tab. Remembered on this PC, not per room.
- **Graphics quality:** one switch for the expensive effects, applied on top of each room's
  look and right away (no restart).
  - **High** is what the rooms are built with: bounce light (SDFGI), volumetric fog, ambient
    occlusion, reflections, MSAA 2x, soft shadows.
  - **Medium** drops bounce light (rooms get a little extra ambient light instead), uses
    low-res fog and softer shadows.
  - **Low** also drops fog, ambient occlusion and reflections, uses FXAA instead of MSAA and
    draws the 3D room at 75% scaled back up with AMD FSR. Text, chat windows and the panel stay
    sharp.
  - Changing any switch below it (bounce light, ambient occlusion, reflections, fog, shadows,
    anti-aliasing, 3D resolution) makes it **Custom**. Room glow, neon and stage lights are
    never touched.
- **Frame rate cap:** 30, 60 (default) or Unlimited. Set it to your stream's frame rate. A
  144-165 Hz laptop screen otherwise makes the GPU draw two to three times the frames the stream
  needs. **V-Sync** (on by default) stops tearing on your own screen; if 60 fps stutters on a
  high-refresh screen, try it off.
- **Streaming from a laptop** (RTX 3060 class): start on **Medium** or **Low**, cap at your
  stream's frame rate, and set **Most chatters in crowd** (Audience tab) to about 100-150.
  Run plugged in, on Windows' best-performance power mode, and make sure Redot and OBS use the
  NVIDIA GPU (Windows Settings → System → Display → Graphics → High performance). Use NVENC
  in OBS so the encoder doesn't load the CPU.

## Control panel in its own window (F9)
**Own window (F9)** at the bottom of the panel moves it into a separate window, so a Window /
Game Capture of the room in OBS never shows it (put it on a second monitor). It opens where you
left it. **Tab** hides / shows it; closing the window hides it (Tab or F9 bring it back). Hotkeys
still work while the panel window has focus (not while you're typing in a box). The setting is
remembered, so it opens in its own window next time too. On systems that can't open a second
window it stays in the main window. Toasts and the "reacting" badge stay in the main window
(F10 clean feed hides those).

## Stage curtain (B, Shift+B)
A red velvet stage curtain hangs in front of the main screen in every room (pelmet with swags,
gold fringe and tassels). It sways a little at rest, the hem trails as it moves, and it overshoots
and settles when it opens.
- **Hide my screen:** **B** (or Room tab → *Close*) draws it shut. While it's closed nothing on
  your screen reaches the stream: it covers the picture from every camera, focus view (F) shows
  the curtain colour (and the sign) instead of the picture, the screen's light on the room turns
  into a warm glow, a soft spotlight washes the curtain, and the stream sound mutes
  (*Mute stream sound while closed*). **B** again opens it.
- **Reveal:** **Shift+B** (or *Reveal*): lights down, a spotlight on the curtain, a drum roll, a
  crash, the curtain sweeps open and the lights come back up. Tick **Start closed** to start the
  app behind the curtain, ready for a reveal when you go live.
- **Sign:** text on a board hanging on the closed curtain (e.g. *Be right back*; the **Be right
  back** button fills it in and closes the curtain). Blank = no sign.
- Room tab → *Stage curtain*: colour, speed, sound volume (the swish and drum roll are made in
  the game, no audio files), *Reveal dims the lights*, *Curtain in rooms* (off = no curtain).
- Stream Core can run it too: Admin → Live controls → *Stage curtain*, or mods type
  `!curtain open | close | reveal` (Chat games on). The game tells Core whether it's open.
- It stays closed / open across room changes. Rooms can add a `CURTAIN_Main` empty in Blender
  (bottom centre of the opening, +Z towards the audience) to place it exactly; otherwise it sits
  0.3 m in front of the screen, wide enough that the opened curtain clears the picture, above a
  CHAT_Screen and below a REPLY_Screen.
- Code: `core/stage_curtain.gd` (+ `.gdshader`), `core/curtain_sounds.gd`; state in AppState
  (`set_curtain`, `reveal_curtain`, `is_curtain_covering`). Test: `_tests/test_curtain.tscn`.

## Presenters (podium rooms)
**Lecture Hall (Panel)** is a copy of the lecture hall with four oak podiums, two each side of a
smaller screen that hangs higher. Each podium has a picture behind it for a presenter and a brass
reading lamp. It has no webcam monitor on the stage: your webcam uses the corner overlay.

Everything is in the **Presenters** tab:
- **On set:** which podiums are used (1-4, numbered left to right as the audience sees them).
  An unticked podium disappears with its picture and lamp.
- **Show:** what the presenter is.
  - *Silhouette:* a standing outline.
  - *Green screen:* a blank panel in the key colour.
  - *Camera:* a webcam.
  - *Tab / window:* a browser tab or app window, such as a vtuber.
  - *Web page (transparent):* a web page with a see-through background, such as a reactive
    PNGTuber / Discord avatar page (see below). Type its address in **Web page**.
- **Camera:** which webcam to use. The list comes from the sender page.
- **Self-lit (light panel):** the picture glows on its own, so the room's lights (and house-light
  dimming) don't change it. Off = the room and the podium lamp light it.
- **Podium light:** that podium's lamp brightness (0-300%).
- **Chroma key** for camera / tab pictures:
  - key colour
  - **Key similarity** (how close to the key colour counts as background)
  - **Key smoothness** (soft edge)
  - **Spill removal** (takes the green glow off hair and shoulders)
- **Zoom** / **Move up/down:** frame the picture.

Camera and tab pictures come through the **sender page** (Source tab > Open sender page):
- **Cameras** start by themselves when you choose *Camera* in the game. The browser asks for
  camera permission the first time (**Allow cameras** button).
- **Tabs / windows:** click that presenter's **Pick a tab or window** button in the sender
  page. Browsers only allow picking a tab after a click.
- **Web pages (transparent):** screen sharing can't carry transparency, so the sender page
  puts the page on a solid background in the presenter's **Key colour** and the chroma key
  cuts that colour out again.
  1. In the sender page, click that presenter's **1. Open page**. A small window opens with the
     page over the key colour. Keep it open (it can sit behind the game; resize it to frame
     the avatar).
  2. Click **2. Share it** and pick the tab called *Presenter N web page*.
  - Pick a key colour the avatar doesn't use. Magenta (`#ff00ff`) is often safer than green
    for colourful avatars. Changing the colour or address in the game updates the window.
  - Some sites refuse to be shown inside another page (the window says the site *refused to
    connect*). Those can't be used this way; share their tab with *Tab / window* instead.
- Feeds are sent at 480p, up to 20 fps, in high quality so keyed edges stay clean.
- A tab only produces new frames when its picture changes (a quiet avatar sends nothing), so the
  sender page re-sends the last frame every second and the game trusts the sender's status.
  A quiet presenter stays on screen.
- Everything shares one connection to the game. When it gets busy, presenter pictures give way
  first and audio is never dropped, so the main video's sound stays smooth.
- They only run while you're in a room with podiums and that presenter is on set.
- Presenter tabs send video only (no audio).

Adding podiums to another room:
- `PRESENTER_<n>` empties (n = 1-4) at the bottom centre of each picture, with local -Y
  (Blender) facing the audience.
- Optional `PODIUM_<n>` meshes (shown and hidden with the presenter) and `PODIUM_LIGHT_<n>`
  empties for the lamp (+Y aims at the presenter).
- Picture size is `presenter_size` on the room's root node.

The panel copy is built by `blender/lecture_hall_gen.py` with `PANEL = True` (see the top of
that file) into `../blender/lecture_hall_panel.blend`.

## NDI (OBS / NDI Tools)
The main screen and the presenters can show **NDI** sources. That's lighter than the browser
sender: OBS (or NDI Tools) does the encoding and a native plugin decodes it, with the sound in sync.
- Needs the **godot-ndi** extension in `addons/godot-ndi` (github.com/unvermuthet/godot-ndi,
  MPL-2.0) and the free **NDI Runtime** (ndi.video) on every PC that runs the game. Without them
  the game runs as before and the Source tab says the plugin isn't loaded.
- **Sending from OBS:** install **DistroAV** (formerly obs-ndi). Either *Tools > DistroAV NDI
  Settings > Main Output*, or add an **NDI Filter** to one scene/source for its own NDI feed.
- **Main screen:** Source tab > *NDI*: pick the source, click **Show**. **Stop** lets go.
  - Its sound goes through the game's volume, auto-duck and room acoustics like the other sources.
  - The plugin in `addons/godot-ndi` is patched (see `addons/godot-ndi/STREAM_ROOMS_PATCH.md`) so
    the game pulls the NDI sound at the sound card's pace into its own buffer.
  - **Sound buffer** (Source tab, default 500 ms): how much NDI sound is queued before it plays.
    It rides out hiccups on the network / OBS side, but the sound runs that far behind the picture;
    lower it if lip-sync matters more. If the stream still stops delivering for longer than the
    buffer, the sound pauses briefly to refill it, and the Output log says so every 10 s.
  - With the unpatched plugin the game falls back to the plugin's own per-frame sound.
  - The room lighting follows the picture like the other sources. For NDI and files the GPU
    shrinks each sampled frame to 36x20 first (`core/gpu_frame_sampler.gd`), so only a tiny image
    is read back, not the full frame.
  - *Reconnect to the last source by itself*: when that source shows up (OBS started later,
    or it dropped out) and nothing else is on the screen, it comes back on its own.
  - While NDI is showing, a browser share doesn't take over (click Stop first).
  - Space still sends the Play/Pause media key (for a browser window in OBS).
- **Presenters:** *Show > NDI source*, then pick the source. NDI keeps transparency, so an OBS
  browser source (e.g. a reactive avatar page) with an NDI filter shows with its real
  see-through background: turn **Chroma key** off. Presenter NDI sound is muted (their voice is
  already in your stream mix).
- The plugin's first connection to a source blocks the game for a moment (until the first
  frame), so the game only connects to sources it has already found.
- `core/ndi_receiver.gd` looks the plugin's classes up by name; `_tests/test_ndi.tscn` runs the
  whole path with a stand-in finder (`_tests/mock_ndi/`).

## Spout (programs on this PC)
The main screen and the presenters can show a **Spout** sender: another program on this PC that
shares its picture, such as VTube Studio, OBS (with the Spout2 plugin), TouchDesigner or some
games. The picture goes straight from the graphics card, so there's no delay, no blur and no
compression, and transparency is kept.
- **Main screen:** Source tab > *Spout (programs on this PC)*: pick the sender, click **Show**.
  **Stop** lets go. The room lighting follows the picture like the other sources.
  - Spout carries **no sound**. The program's sound reaches your stream the way it already does
    (OBS, desktop audio).
  - **Show the last sender again by itself**: when that sender starts again (the program was
    restarted) and nothing else is on the screen, it comes back on its own.
  - While Spout is showing, a browser share doesn't take over (click **Stop** first).
- **Presenters:** set **Show** to **Spout (this PC)**, then pick the sender. A see-through avatar
  (VTube Studio: Settings > Spout2 output) keeps its transparency: turn **Chroma key** off.
- Turning Spout on in other programs: VTube Studio has it in its settings; OBS needs the free
  *Spout2 Plugin for OBS*.
- Streaming together: Spout only exists on your PC, so guests see a silhouette on a podium that
  shows your Spout sender.
- Needs the **godot-spout** extension in `addons/godot-spout` (github.com/buresu/godot-spout,
  MIT), built for Redot 26.2 with a small patch (see `addons/godot-spout/STREAM_ROOMS_PATCH.md`).
  Without it the game runs as before and the Source tab says the plugin isn't loaded.

## Chat audience (Fridge Stream Core)
Rooms with audience seats (Home Theater, Lecture Hall, Old Classroom) can fill up with your chat:
- **Seats:** everyone who chats gets a seat with a head-and-shoulders silhouette in their own
  colour. **Colour silhouettes by** (Audience tab) picks the colour:
  - *Chat colour* (default): the platform's chat colour when it has one; otherwise a colour
    picked from their name, so it's the same every time.
  - *Name only*: always the colour from their name.
  - *Platform*: one colour per platform (Kick green, Twitch purple, YouTube red, other grey by
    default; change them with the four colour pickers below it).
- **Speech bubbles:** their messages pop up in a speech bubble above their head, with their name
  on top. Each person gets one of four bubble shapes.
- **Emotes:** chat emotes show inline in the bubbles, and emote-only messages show them bigger.
  That covers Twitch emotes plus BetterTTV, FrankerFaceZ and 7TV emotes (Stream Core sends them
  with each message) and Kick emotes.
  - Images download once and are kept in `user://emote_cache/` (`autoload/emote_cache.gd`).
  - Animated GIF emotes (Kick, BetterTTV, ...) play in the bubbles and on the chat screen. The
    engine can't read GIFs, so `core/gif_decoder.gd` decodes them on a worker thread.
    Animated WebP can't be decoded yet: those show a still frame when the site provides one,
    otherwise their name as text (the Redot output then says "Emote image not supported").
  - Normal emoji use your system's colour emoji font (Segoe UI Emoji on Windows).
- **Chatter pictures:** Kick and YouTube chatters' profile pictures fill the silhouette's head,
  cropped round inside their colour ring.
  - YouTube pictures come with each message. For Kick, Stream Core looks each new chatter up
    once, so their picture appears a moment after their first message.
  - Twitch pictures aren't supported yet.
  - Turn pictures off with **Chatter pictures**, or hide one person's picture with
    **Hide pictures of** (Audience tab).
- **Where they sit:** **New chatters sit** in the Audience tab picks the seat:
  - *Anywhere (random)*: any free seat.
  - *Front row first, from the middle*: the row nearest the screen fills first, middle seats
    outwards, then the next row.
  - *Front row first, random seat in the row*: rows fill front to back, but where someone lands
    in the row is random.
  Rows are worked out from where the seats are relative to the main screen, so this works in every
  room. Changing it doesn't move anyone already seated.
- **Leaving:** after **Idle timeout** minutes without chatting, they leave their seat. If every
  seat is taken, the person who has been quiet the longest makes room.
- **Your view stays clear:** silhouettes right in front of the camera fade out. Bubbles and
  name tags grow with distance so you can read them from the balcony.
- **Big crowd (Lecture Hall):** the tiers, balcony and gallery hold about 680 more seats.
  - A **filler crowd** sits there: muted silhouettes that sway a little, dim with the house
    lights, and join in crowd-wide reactions (dance, cheer, the stadium wave).
  - **Crowd fullness** (Audience tab) sets how many seats have a filler person; turn the whole
    thing off with **Filler crowd**.
  - When the main seats (the pit) are full, new chatters overflow into the crowd seats and
    take a filler person's place. They get the full treatment there: their colour, picture,
    name tag and bubbles.
  - **Crowd chatters move down** (on by default): when a main seat frees up, the most recently
    active chatter in the crowd moves down into it.
  - **Crowd timeout** is the crowd seats' own idle timeout (the main seats use **Idle timeout**).
  - **Most chatters in crowd** (0 = no limit) caps how many chatters sit in the crowd seats at
    once. No seats go away: filler people fill the rest, so the room looks the same. Chatters
    are what cost CPU and GPU (picture, name tag, bubble each); filler people are free. When
    the cap is reached, a new chatter takes the seat of whoever has been quiet the longest.
    On a laptop, 100-150 is a good start.
  - **Filler people in empty main seats** (off by default) fills the empty pit seats with
    filler people too, at the same share as the crowd; chatters take their places.
  - The filler crowd is one draw call (`core/audience/crowd_layer.gd` + `crowd.gdshader`); only
    seats with a chatter in them cost anything per person.
- **Only what the camera sees is drawn:** a bubble the camera can't see (off-screen, or behind
  the balcony or a post) isn't drawn until it comes into view. Animated bubbles far away
  redraw about 12 times a second instead of every frame. The per-seat work only runs while the
  camera moves.
- **Settings:** all in the **Audience** tab.
  - bubble time and bubble size
  - name tags, dim placeholders on empty seats, hiding `!commands`
  - use chat colours
  - an ignore list for bots
  - **Test chat** fills seats with made-up chatters

Chat comes from **Fridge Stream Core** (FlaVR Leftovers workshop):
- Start it with *START Stream Core.bat*. The game connects to its overlay WebSocket at
  `ws://127.0.0.1:3850/ws`, the same feed its chat overlay uses. So every platform Core has
  enabled (Kick, Twitch, YouTube) shows up, and Core itself needs no changes.
- Chat that arrived in the last few minutes before connecting seats those chatters too.
- Core's own bot replies are skipped by the audience and the chat screen; they go on the
  reply screen instead (see below).
- The game reconnects on its own if Core is started later or restarted.

The Presenters tab only shows the rows that matter for what a presenter shows: the camera
picker for a camera, the NDI picker for NDI, the address for a web page, and the chroma key
controls (and its sliders, while the key is on) for a picture.

**Presenters in chat:** in the **Presenters** tab, give a presenter their **Chat name**
(comma separate several; `kick:name` only matches on Kick).
- That chatter sits on the podium instead of taking an audience seat, so they never use up a
  seat, don't time out while the presenter is on set, and can't be moved or swapped.
- Their chat commands come from the podium: throws fly from there, signs go up over it, and
  jumps and dances move their picture (camera or silhouette) too.
- **Chat-style silhouette:** when the presenter shows a silhouette, it takes their chat colour,
  profile picture and name tag, like the audience.
- **Chat bubbles:** their messages pop up over the podium.

Adding seats to a room:
- Add an **AudienceRow** node (`core/audience/audience_row.gd`, a Marker3D) on the seat surface
  of the first seat, then set `count` + `spacing` (seats run along its local +X), or list
  `offsets` for uneven rows. `seat_scale` makes a row's silhouettes smaller or larger.
- Single seats can also be Blender empties named `AUDIENCE_<anything>`.
- Seats where a camera sits are skipped automatically.
- A big crowd: set the room's `crowd_seats_file` to a JSON file of seat positions
  (`{"seats": [{"p": [x, y, z]}, ...]}`, room space, on the seat surface). The lecture hall's
  comes from `blender/lecture_hall_gen.py` (`crowd_seats.json`, written by `build_all()`).

### Chat screen
**Lecture Hall (Panel)** has a chat panel under the main screen, the same width as the screen.
Turn it on in the **Chat** tab (*Under the screen*) or press **C**.
- It shows the same Stream Core chat as the audience: names in their colours, emotes,
  Kick / YouTube profile pictures. It follows the Audience tab's **Ignore names**.
  `!commands` (like `!tomato`) show on it unless you tick **Hide !commands** in the Chat tab
  (separate from the Audience tab's *Hide !commands in bubbles*).
- Messages flow down the columns like a newspaper, newest at the bottom right. The oldest drop
  off when it's full.
- Chat tab settings: which platforms it shows, Stream Core replies, chatter pictures, text
  size, columns (1-4) and background opacity (0% = text floating on its own).
- Other rooms can have one: add a `CHAT_Screen` empty at the top centre of the panel (local -Y
  in Blender faces the audience) and set `chat_screen_size` (metres) on the room's root node.

### Reply screen
**Lecture Hall (Panel)** also has a panel above the main screen for Stream Core's answers to
chat commands (`!points`, `!help`, reaction replies …). Stream Core can't post into Kick or
YouTube chat without an API login, so this is where viewers see those answers.
- Each reply shows the chatter it answers (`@name`) and stays up for **Keep each reply**
  seconds (Chat tab; 0 = until newer replies push it off). The panel is only there while it has
  something to show.
- Replies from the last few minutes appear when the game connects to Core.
- Chat tab settings: show it, which platforms' replies, keep time, text size, background.
  Hotkey **R**.
- Other rooms can have one: add a `REPLY_Screen` empty at the top centre of the panel (local -Y
  in Blender faces the audience) and set `reply_screen_size` on the room's root node.
  `reply_screen_raise` makes it taller upward without moving its bottom edge (the Lecture Hall
  panel uses 1.3 m: twice the original height). Chat games boards show on it too.

### Chat reactions (🍅)
Chat can throw things at the stage. Stream Core decides who may do what (permissions, cooldowns,
point costs, opt-outs) and the game plays it. Set reactions up in Stream Core:
**Admin → Config → Reactions** (spec: `FlaVR_leftovers/fridge-stream-core/docs/REACTIONS.md`).

- `🍅` in chat throws a tomato at the screen. `🍅 @bob` or `!tomato @bob` aims at someone in the
  audience (their silhouette flinches), `!tomato webcam` at your webcam frame, `!tomato presenter2`
  (or `guest2`) at a presenter's picture, `!tomato podium2` at their podium, `!tomato chat` at
  the chat screen. `!targets` lists what the room has.
- Effects: throw (splat / bounce / stick / shatter), pile up on the stage, float up, drift down,
  rain, confetti, wiggle / jump / spin, stand and cheer, big shout, stadium wave, spotlight,
  room lights (flicker / tint / dim), camera shake, and applause / boo meters.
- **Pictures:** a reaction whose Object is `img:<name>` throws / drops / floats a PNG, JPEG or
  animated GIF instead of an emoji (`!boot` / 🥾 throws the built-in boot). Upload more in Stream
  Core: **Admin → Config → Reactions → Pictures**. The game downloads them from the Core address in
  the Audience tab. Test: `_tests/test_reaction_images.tscn`.
- When the game connects, it tells Core which effects it can play and what the current room
  offers, and reports back after each reaction. If it can't play one (reactions off, a wiggle from
  someone without a seat), Core gives the points back.
- **Audience tab → Chat reactions:** *Play reactions*, *Allow camera shake*, *Reaction size*, and a
  **Test here** button that plays any effect in the current room without Core.
- Room targets are found automatically: `screen`, `webcam` (WEBCAM_Frame), `chat` (CHAT_Screen)
  and, for each presenter on set, `presenter<n>` (their picture) and `podium<n>` (the front of
  their `PODIUM_<n>` mesh, or a spot below the picture if the room has none). Add your own with empties named
  `TARGET_<Name>` (+Z / Blender -Y facing the audience), e.g. `TARGET_Piano` → `!tomato piano`.
- Crowd and seat effects (Stream Core sends these for `!sign`, `!sleep` / `!snack` / `!phone`,
  `!highfive @name`, `!seat front|back`, `!swap @name`, emote combos, the hype meter, `!launch` ...):
  the whole crowd dances / cheers, a sign over someone's head, props (💤 🍿 📱), high fives across the
  room, moving to a free front / back seat, trading seats, cartoon stage fire, fireworks, flash and
  police lights. Reactions that name several people (`crowd`) play from each of their seats.
- **Chat games boards** (polls, predictions, the hype meter, cheer vs boo, heists, trivia, ratings) from
  Stream Core's Chat games page show on the reply screen in rooms that have one, and in the top-right
  corner otherwise. **Audience tab → Chat games:** *Boards in the corner* (auto / always / never),
  *Board size*, *Regulars' titles on name tags* (Stream Core streak titles: "Name · Regular").
  They stay up in clean feed (they're part of the show). Code: `ui/board_hud.gd`, `core/chat_screen.gd`.
  Test: `_tests/test_chat_games.tscn`. Spec: `fridge-stream-core/docs/CHAT_GAMES.md`.
- Code: `autoload/reactions.gd` (the Core link, meters), `core/reactions/reaction_layer.gd`
  (effects, attached to each room by RoomHost). Test: `_tests/test_reactions.tscn` (runs a fake
  Stream Core).

## Streaming together (Together tab)

Up to four people share one room: a **host** who runs the show and up to three **guests**. Everyone runs their own copy of Stream Rooms, flies their own camera and streams their own view from their own OBS. Only small messages travel between the PCs (no video), so it needs almost no bandwidth.

### Connecting

Two ways, and nobody has to open ports on their router either way:

- **Cloudflare tunnel (hides your address).** The host sets **Listen on** to **Cloudflare tunnel
  (hide my address)**. Hosting then runs `cloudflared` in the background and gets a one-off address
  like `something.trycloudflare.com`. Guests reach you through Cloudflare, so nobody ever sees
  anybody's real address, and no Tailscale is needed. The address is new every session. It needs
  `cloudflared.exe` in the `tools` folder (`tools\get_tools.ps1` downloads it; exports include it).
  Try Cloudflare is a free service with no uptime promise, and a brand-new tunnel sometimes needs a
  second try from a guest.
- **Tailscale** ([tailscale.com](https://tailscale.com), free). Everyone joins the host's Tailscale
  network and the host leaves **Listen on** at **Tailscale (else this PC only)**. Guests on the
  same Tailscale network do see each other's Tailscale addresses.

Then:

1. In the **Together** tab, everyone types a **Your name** and the same **Password**. The host picks the password (at least 4 characters) and tells the guests.
2. The host clicks **Host a session**, then **Copy address**, and sends the copied address to the guests (in a private message, not on stream).
3. Each guest pastes it into **Host address** and clicks **Join**.

**Leave / stop hosting** ends your part. A wrong password, or a different Stream Rooms version, is turned away with a message saying why.

**Nothing to leak on stream:** the host address is never shown on screen, only copied, and the
**Host address** box shows dots, like the password. Messages on screen never contain an address
either. The password stays on your PC: only a scrambled check of it is sent.

**A proxy for guests** isn't something the game can do (Redot can't send its connection through
an HTTP or SOCKS proxy). With the tunnel, a guest's address is seen only by Cloudflare, never by the
host or the other guests. A guest who wants to hide from Cloudflare too can run a VPN.

### What's shared

- **Room**, **stage curtain**, **House lights** and the curtain's look (sign, colour, speed).
- **Presenters**: who's on set and what they show. A **web page** presenter (for example a VDO.Ninja link) shows for everyone. A presenter showing the host's **camera**, **browser tab** or **NDI** only exists on the host's PC, so guests see a silhouette there instead.
- **Chat reactions** from every channel play for everyone: a tomato thrown by a guest's viewer lands in everyone's room, in about the same place. A reaction with its own picture shows its emoji on the other PCs, because the picture lives on the sender's Stream Core.

Each person keeps their own camera, graphics, sound, chat windows and Stream Core connection.

### One audience for everyone's chat

With **One audience for everyone's chat** ticked (Together tab, on the host's PC), every
streamer's viewers sit in the same audience, and every stream shows the same people in the same
seats, with the same speech bubbles:

- Each guest's chat is sent to the host, and the host's PC seats everyone, using the host's
  seating settings (Audience and Seating tabs). Guests' own chat windows still show only their own chat.
- **Each streamer's viewers sit together** gives each streamer's viewers their own part of the
  audience: two of you get the left and right halves, three or four get a quarter each, and the
  big crowd sections are shared out the same way.
- A viewer of a guest's channel can be thrown at with a reaction from any channel, because
  everyone sees the same seats.
- When a guest leaves, their copy goes back to its own audience.

Untick it and each of you has your own audience again.

### Host and guests

Guests can't change the shared things. Those controls are greyed out, and the hotkeys show a message saying the host controls them. The host can tick **Co-host** next to a guest's name to let them change the room, curtain and presenters too, or click **Remove** to send them out.

**Show the others' cameras** shows a small floating camera with each person's name, so you can see where the others are looking.

Every guest draws the whole room while streaming. When you join on **High** or **Custom** graphics, the tab offers **Use Medium** (or **No thanks**).

### Watching a video together

When the host plays a **web link** (YouTube or any page yt-dlp understands) in **File or URL**,
everyone watches it in sync:

1. Every PC downloads and converts the video itself, so each one needs the `tools` folder
   (yt-dlp and ffmpeg). Each person hears the sound from their own copy.
2. Everyone waits on the first frame. When every PC is ready, the host starts them all at once.
   If someone takes longer than two minutes, the others start without them and they catch up.
3. The host's pause (Space), jumps and Stop reach everyone. Each guest stays within about a third
   of a second of the host and jumps to catch up if it drifts further.
4. Someone joining mid-video downloads it, then joins in at the host's spot.

A video **file** on the host's PC can't reach the guests, so only the host sees it (it says
so in a message). A co-host's **Play** sends the link to the host, who starts it for everyone.

### The host's live tab

When the host shares a browser tab or window in their **sender page** (Source tab > **Open sender
page**, as usual), the guests can watch it on their big screens too, with its sound. Use it for
anything live: a game, a stream you're reacting to, a website.

- **Host:** nothing extra to do while **Send my shared tab to the guests** (Together tab) is ticked.
  The sender page says "Your guests get this tab too."
- **Guest:** the Together tab says when the host is sharing. Open your own sender page (the
  **Open sender page** button there) and click **Watch the host's live feed**. The host's tab then
  takes the place of a tab of your own. It comes back by itself if the host stops and starts sharing
  again. **Stop watching** lets go.
  Browsers only let a page's sound through after a click on it, so if the sender page asks,
  click anywhere on it once.
- It goes through **VDO.Ninja**, straight from the host's browser to each guest's (peer to peer),
  about 0.2 to 1 second behind the host. Each guest costs the host roughly 3 to 6 Mbps of upload,
  so a host on a slow connection may want to untick it.
- Straight from browser to browser means the host's and the guests' browsers see each other's
  addresses. **Relay the live feed (hide addresses)** (Together tab, host) sends it through
  VDO.Ninja's relay servers instead, so they don't. It adds a little delay and can lower the quality.
- The stream's name and key are random for each session and only go to guests who got the
  password right.

NDI and Spout aren't shared: they only exist on the host's PC.

The VDO.Ninja SDK (`web/vdoninja-sdk.min.js`, version 1.6.2 from npm `@vdoninja/sdk`, MPL-2.0,
licence in `web/vdoninja-sdk-LICENSE.txt`) is only loaded when the live feed is used.

### Running two copies on one PC

To try a host and a guest side by side, start a second copy with a profile name:

```
redot.windows.editor.x86_64.exe --path . -- --mp-profile=guest1
```

A copy started with a profile:

- keeps its own settings in `settings_guest1.cfg`, so it never changes your normal settings,
- moves the browser-tab ports up so both copies can run at once (`guest1` uses 8775 / 8776, `guest2` uses 8785 / 8786, and so on; a name without a number uses +10),
- shows the name in the window title, for example **Stream Rooms [guest1]**.

Profile names can use letters, numbers, `_` and `-` (up to 24 characters).

To connect them, set the host's **Listen on** to **This PC only**, click **Host a session**, and have the second copy join `127.0.0.1`.

### A note on copyright

When several channels watch the same video together, each one is broadcasting it. That is the same risk as showing it on one channel, just on more channels at once. Only share videos you're allowed to stream.

## Adding a room
Create `rooms/<name>/` with:
- a scene whose root uses `rooms/room.gd`, containing:
  - `TVScreen`: the screen mesh (needs UVs). Screen lights place themselves from its size.
  - `CAM_<n>_<Name>`: empties/markers for camera presets, where -Z is the view direction. They
    sort by name, so use two digits (`CAM_01_...`) when a room has more than nine. A name
    containing `Reaction` becomes the react-pause camera.
  - `LIGHTS_House`: a node whose lights dim while a video plays.
    - `LAMP_<Name>` empties inside it become lights automatically. Set color, strength and
      range on the room's root node under "LAMP_ markers".
  - `WEBCAM_Frame` (optional): where the webcam picture goes. It faces the marker's +Z.
  - `BEAM_Projector` (optional): a projection-booth marker. A narrow beam shines from it at the
    screen, tinted by the picture, and shows up in volumetric fog.
  - `SCREEN_Mirror_<Name>` (optional): extra screen meshes (with UVs) that show the same picture,
    each with a soft light spill.
  - `AUDIENCE_<Name>` empties or `AudienceRow` nodes (optional): chat-audience seats (see above).
  - `CHAT_Screen` (optional): top centre of a chat panel under the screen (see *Chat screen*).
  - `REPLY_Screen` (optional): top centre of the command-reply panel (see *Reply screen*).
- `room_info.tres` (a **RoomInfo** resource): id, display name, scene path, and optional
  Environment, screen-light strength, reverb, ambience sound, and an **LED look** for big outdoor
  screens (`screen_led_amount` and `screen_led_count`). The LED dots fade out with distance so
  they don't shimmer.
  - Projector rooms can also use `screen_film_amount` (the old-film look), `screen_film_tint` and
    `screen_matte` (a white fabric screen instead of black glass). `speaker_lofi` gives the
    room a small old speaker. A room with a film look gets a **Film look** slider in the Room tab.
  - `screen_hologram` turns on the hologram screen controls in the Room tab (see Neon City).
- Optional: a room script can add its own controls to the Room tab by overriding
  `get_controls()` in `room.gd` (headings, sliders and colour pickers bound to AppState settings;
  see `rooms/neon_city/neon_city_room.gd` for the Rain slider).
- Optional: `glow_materials` on the room's root node lists imported materials (by name) whose
  glow dims with the house lights, such as chandelier bulbs.
- Optional: `material_overrides` on the room's root node swaps imported materials by name, for
  example a Blender material called `Win_Glass` for the interior-window shader. For that shader,
  the mesh's UVs must put one window bay by one floor into each 1x1 UV cell.

Blender empties exported to glTF keep their names, so you can put all the markers straight in the
.blend. For a camera empty, point its local **+Y** at what it should look at (Z up). For
`WEBCAM_Frame`, point its local **-Y** at the viewer. The room appears in the Room list
automatically.

Included rooms:
- **Home Theater**
- **Drive-In (1950s)**: night lot with a pickup with lawn chairs, a concession stand and a
  projector beam. The sky (`rooms/drive_in/night_sky.gdshader`) draws a textured, phase-lit
  moon, stars with a faint Milky Way, and a few moonlit drifting clouds. The moon sits wherever
  the room's `Moonlight` light comes from, so rotate that node to move the moon. Tune the moon
  size, phase, tint, edge softness (`moon_edge_softness`), atmospheric haze (`moon_haze`), cloud
  coverage and so on in `room_info.tres` > Environment > Sky > Shader Parameters. The moon surface (`moon_albedo.png`) is procedurally generated. Every marker lives in `../blender/drive_in.blend`, so move things
  there and re-export to `rooms/drive_in/drive_in.glb`. Export the `DriveIn` and
  `DriveIn_Markers` collections only, not `Preview_Only`.
- **Neon City (night)**: a rain-soaked megacity avenue.
  - The main screen is a giant LED video billboard on a tower whose base is a lit traffic portal.
    A street gantry screen mirrors the same video.
  - Cameras: a rooftop balcony (the default), a pedestrian overpass, a billboard close-up, a
    high skyline view, and a Reaction camera aimed at the webcam display on the balcony wall.
  - Every building window is a little 3D room (`core/interiors/interior_windows.gdshader`,
    adapted from an MIT-licensed interior-mapping shader). Lights are on or off per window,
    warm, cool or neon, with blinds, curtains and the odd flickering TV. The seven facade
    styles are the `Win_*` materials in `rooms/neon_city/materials/`, which the room swaps in
    by name (see `material_overrides` on the room's root node).
  - Buildings come from `../blender/city_gen.py` (run inside Blender: see the top of that
    file). Windows follow a floor grid, so they line up with corners and roofs. Every roof has
    a cornice, parapet and equipment or a crown (notched, slanted, spire, neon fins, helipad,
    halo). Building types include setback towers, a teal megablock with an exposed frame and
    braces, a ring tower with LED ticker bands, a gate building with sky bridges, a capsule
    tower and overhanging "hammerhead" tops.
  - `rooms/neon_city/neon_city_room.gd` adds rain that follows the camera, flying traffic
    (some craft carry lights that sweep across the buildings), street traffic, flickering flare
    stacks marked `FLARE_*`, and a generated rain ambience. All are tunable on the room's root
    node.
  - The sky (`smog_sky.gdshader`) is a smoggy cloud deck lit from below by the city.
  - Source file: `../blender/neon_city.blend`. Export the `City` and `City_Markers`
    collections, or run `export_glb()` from `city_gen.py`.
  - **Room tab controls:**
    - **Rain**: 0% (dry) to 200% (downpour). The rain sound follows it.
    - **Hologram**: how strongly the scan-line colours take over the picture (0% = normal
      screen). **Transparency** makes the screen see-through, and the dark box behind the
      screen fades with it so the picture floats in front of the tower. **Glitch** adds torn
      bands, RGB split, jumps and dropouts in bursts. **Scan lines**, **Scroll speed**,
      **Noise** and the two **Line colours** are the original shader's settings.
      The hologram look is ported from "Hologram Simple CanvasItem Shader" by Vaquers
      (godotshaders.com, CC0), in `core/screen_inc.gdshaderinc`.
    - The screens use the see-through shader (`core/screen_holo.gdshader`) only while
      Transparency is above 0%. See-through screens don't show in the wet-road reflections.
  - All brands, signs and designs are original.
- **Old Classroom (film day)**: a 1950s-style classroom with the blinds drawn.
  - The video plays on a roll-down projection screen in front of the chalkboard, thrown by a
    16 mm projector on an AV cart in the middle aisle. The reels turn while the film runs and
    run down when you pause to react. Dust drifts through the beam.
  - The picture has an old-film look: faded warm colour, grain, dust specks, hairs, a drifting
    scratch, gate weave, flicker and a projector hot-spot. The light on the room flickers with it.
  - The sound goes through a tinny old speaker: no bass or treble, mono, a little distortion
    and film flutter. Use **Speaker FX** in the *Sound* tab to set how much (0% = clean).
  - **Film look** in the Room tab sets how much of the old-film look the picture gets:
    0% = clean, 100% = the room's look, up to 200% for extra dust, hairs, scratches and flicker.
  - The projector beam lights exactly the picture area. The mask is traced from the projector's
    real position, so it doesn't spill onto the screen fabric or the wall.
  - The projector whirrs and clatters on the ambience track, and the wall clock shows the real
    time and ticks.
  - Cameras: a student's desk (the default), the back corner, the screen, the projector, and a
    Reaction camera aimed at the webcam picture pinned to the corkboard.
  - Source: `../blender/classroom.blend`, built by `../blender/classroom_gen.py`
    (run it inside Blender: see the top of that file).
- **Lecture Hall**: a Victorian Gothic university theatre in dark oak.
  - The plan follows a real 1870s hall: a U of straight side walls and a half-octagon back, a
    flat pit of straight pews with a centre aisle, four stepped rows of pews round the U
    (raised theatre-style, lowest at the pit, with half steps up the back), a narrow
    wrap-around balcony on slender posts, an arcaded top gallery, a hammer-beam ceiling and a
    curved wooden sounding canopy over the stage. The inscription, shields and statues are
    original stand-ins.
  - Aisles at the back corners lead to tall carved oak exit doors under stained glass
    fanlights, with lit EXIT signs. Pairs of pointed stained glass lancets run high on the
    walls, with rose windows under the gallery.
  - Set shaders (Inspector on the room's root, *Set shaders*): the stained glass is lit from
    behind, brighter on the sunny side, with clouds drifting across; dusty sunbeams slant in
    from the sunny lancets (they fade out in front of the screen); the wood is varnished, the
    carpet has a velvet sheen and the marble is translucent. The glass and beams follow the
    house lights, so they go down for a video.
  - **Light rays** (Room tab, both Lecture Halls): how visible the sunbeams are, 0-200%
    (0% = off).
  - The screen is 14.4 m x 8.1 m and stands right on the stage floor, with a matte white face.
  - The ring chandelier dims with the house lights. Use **House lights** in the *Room* tab to set
    the level by hand (it scales the automatic dimming too).
  - 12 cameras: pit, front row, centre rows, rear diagonal, side seat under the balcony,
    three balcony seats, the gallery rail, a Reaction camera by the webcam monitor, the lectern
    (looking out at the hall), and a view past the chandelier. Press **0** for the 10th.
  - A big-room reverb and a faint room tone.
  - Source: `../blender/lecture_hall.blend`, built by `blender/lecture_hall_gen.py`
    (textures for the glass, doors and EXIT sign: `blender/make_hall_textures.py`).
- **Studio**: a simple test room without a webcam frame, which shows the corner-overlay fallback.

## Exporting a standalone build (Windows)
**The easy way:** in PowerShell in the project folder, run

```
powershell -ExecutionPolicy Bypass -File tools\export.ps1
```

It builds into a new folder, `exported\StreamRooms_<date-time>\`, with `StreamRooms.exe`, the game
data `StreamRooms.pck`, the NDI and Spout plugin files and the `tools` folder (yt-dlp, ffmpeg).
It checks the build is complete. **Copy that whole folder** to the other PC. The editor can stay
open while it runs.

Why a script: the export window in the editor remembers its own settings, and two of them broke
builds on another PC. **Export Mode** set to "Export selected scenes" left the game out, and the
**Shader Baker** packed in shaders prepared for this PC's graphics card, which froze the other PC.
The script exports without the editor window, so neither can happen.

Exporting from the editor still works (*Project > Export...*, **Windows Desktop**, **Export Project**):
- **Resources > Export Mode:** **Export all resources in the project**.
- **Options > Shader Baker > Enabled:** off.
- **Options > Embed PCK:** off.
- Export into an empty folder, then copy the exe, the `.pck`, both DLLs and the `tools` folder.

Other PCs: the first start takes a little longer while it prepares its shaders. Keep the graphics
driver up to date (an old NVIDIA driver froze it once). NDI needs the free NDI Runtime installed.
Settings and caches live in the user data folder (`%APPDATA%\Redotpp_userdata\Stream Rooms`).

## Project layout
- `autoload/`: EventBus (signals only), AppState (settings and state), SaveManager
  (`user://settings.cfg`), RoomCatalog, AudioManager (buses, reverb, ducking), SystemMedia
  (media key), ChatFeed / AudienceManager / EmoteCache (chat audience), Reactions (chat reactions)
- `core/reactions/`: ReactionLayer, the per-room effects for chat reactions
- `core/`: main scene and wiring, RoomHost (threaded load and fade, graphics quality via
  `graphics_quality.gd`), ScreenFeed (file and capture sources, A/V delay), CaptureServer (local HTTP + WebSocket), ScreenLights, WebcamDisplay,
  CameraRig, Hotkeys, VideoLoader
- `core/interiors/`: the interior-window facade shader and its room atlas (8 room types)
- `ui/`: control panel, focus view, overlays (toasts, badge, webcam corner)
- `web/sender.html`: the browser sender page. **When exporting the game**, add `web/*` to
  *Export > Resources > Filters to export non-resource files*.
- `rooms/`: one folder per room

The link only listens on `127.0.0.1` (this PC). Ports 8765 and 8766 are in AppState's defaults (a copy started with `--mp-profile` shifts them, see Streaming together).
