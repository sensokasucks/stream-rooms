# Stream Rooms (Redot)

Swappable 3D rooms with a screen that shows a **shared browser tab** (live, e.g. YouTube in
Brave) or a **video file / URL**. The picture lights the room, and there are tools for
reaction streams.

Needs Redot 4.3+ (Forward+). Open `project.godot` in Redot, let it import, and press **F5**.

---

## The control panel: Advanced ▸
Every tab shows the controls you touch while streaming; the set-up-once settings sit under an
**Advanced ▸** button, closed until you click it (what you open stays open next time). Nothing
was removed, it just folds away: the Room tab's curtain options, the room's own looks (windows,
light rays) and the whole **Performance** block; each chat window's replies, header, text size,
looks and position; a podium picture's size, lighting and position; the Co-stream tab's
**Quality** block; and on the Source tab each source's help text and its "by itself" ticks.

The **Source** tab shows one source at a time: **Big screen shows** picks **Browser tab**,
**NDI**, **Spout**, **File or URL** or **Someone's avatar (Co-stream)**, and only that
source's controls appear. It follows whatever starts playing, and remembers your last pick.
Picking one there only changes which controls you see, not the screen: press **Share**, **Show**
or **Play** in that section. The line under it, **On the big screen now:**, always says what is
really showing (for example *Browser tab, "YouTube - ..." (30 fps)*, *NDI, OBS (MAIN)* or
*Nothing.*). The **NDI** and **Spout** sections show their status line (plugin missing, no
sources found, what's showing) right under the picker, not inside **Advanced ▸**.

## What's going on: status strip and messages
**Status strip** (above the tabs, on every tab): three coloured dots.
- **Core**: green when Stream Core is connected, red when it isn't (chat, bubbles and reactions
  stop), grey when chat is off.
- **Big screen**: green while something shows, amber when the screen is empty, red when the
  browser tab stopped.
- **Co-stream**: hosting / joined (green), someone waiting or joining (amber), off (grey).

Click a dot to jump to its tab (Chat, Source, Co-stream).

**Messages** go to the line at the bottom of the panel, not onto the room picture, so viewers
never see things like "Address copied" or a download error. Errors are red. Click the line (or
**Messages ▸**) to see the last 10 with their times. When Stream Core drops, or the browser tab
stops sharing, a message says so (before, the screen just went blank).

**Show messages on the picture** (under **Messages ▸**) also shows each message for a few seconds
at the bottom of the room picture, as the app used to. It is **off by default**, because that is
the window OBS captures. Clean feed (F10) hides them either way.

Co-stream's "wants to join" and "is this the right host?" popups open as their own small window,
even while the panel sits inside the main window, so a guest's name never shows on stream.

### Log files for troubleshooting
**Save a log file for troubleshooting** (under **Messages ▸**, **on by default**) writes what the
app does to a file each time it runs: errors, the Stream Core connection, co-stream joins, leaves and
drops (with the ping), room and source changes, a "still alive" line every minute, and, after a
crash, the last lines from the run that crashed. **Open log folder** opens the folder
(`%APPDATA%\Redot\app_userdata\Stream Rooms\logs_to_share`). The last 15 runs are kept, newest
last in the list.

The files are cleaned before anything is written, so they are safe to send to whoever is helping:
IP addresses become tags like `<ip-home#1>` or `<ip-tailscale#2>` (the same address keeps the same
tag, so you can still follow one guest), and your Windows user name, computer name, personal
folders, Cloudflare tunnel names and any keys or tokens in links are replaced too. Chatter names
stay. When a friend has trouble connecting or crashing, ask them for the log from that run (and
send yours from the same time).

## Showing a browser tab (recommended)
1. Run the game.
2. In the panel's **Source** tab, click **Open sender page**. It opens `http://127.0.0.1:8765/`.
   Open it in Brave (or Chrome/Edge). Firefox can't share tab audio.
3. Click **Share a tab or window**, pick the YouTube tab, and leave **"Share tab audio"** on.
4. The tab appears on the screen within a second or two. Keep the sender page open. A small
   separate window works best, because browsers slow down hidden tabs.

The sender page is kept small: the link light, **Share a tab or window** / **Stop**, the preview
and **Start webcam**. Picture quality, frame rate and the sound switch sit under **Quality and
sound**. The **Presenter feeds** box only shows while a podium in the game is set to a camera,
tab or web page, and only the podiums in use get a row.

The sender page can sit behind other tabs: the picture work runs in a background worker, which
browsers don't slow down the way they slow down a tab that isn't in front. (Keeping it in its own
small window still works too.) Don't minimise the whole browser window: Windows stops drawing a
minimised window, and a shared tab in it may stop producing frames.

**No double audio:** the sender asks the browser to silence the shared tab
(`suppressLocalAudioPlayback`) and sends its sound to the game instead. The sender page and the
game's Source tab both warn you if the browser couldn't silence it. If that happens, mute the tab.

**Lip-sync:** the picture travels a longer path than the sound, so audio is delayed by 150 ms by
default. Adjust **Audio delay** or **Video delay** in the *Sound* tab ▸ Advanced.

**Only your sender page can use it:** each time the game starts it makes a new secret key and
writes it into the sender page. The game only takes pictures and sound from a page that has that
key, so another website open in your browser can't put its own picture on your big screen or
read your co-stream live-feed key. Nothing changes for you: open the page with **Open sender page**
(or your bookmark) as before. A sender page left open while you restart the game picks up the new
key by itself and reconnects. The page only opens as `127.0.0.1` or `localhost`.

**Webcam:** click **Start webcam** on the sender page. It shows on the room's picture frame
(`WEBCAM_Frame`), or as a corner overlay if the room doesn't have one.

## Playing a file or URL (fallback)
Type a path or a YouTube URL in the *Source* tab, or click **Browse...**. Non-`.ogv` files and URLs
need `yt-dlp` and `ffmpeg`: right-click `tools/get_tools.ps1` > *Run with PowerShell*.

A video goes through up to three steps: **Download** (links only), **Convert** (to the format the
game plays) and **Play**. While it works, a line under the File controls says which step it's on,
how far it got and for how long ("Step 1 of 2: Downloading 42% · 1:12", "Step 2 of 2: Converting
80% · 0:40"), with a progress bar and a **Cancel** button (nothing half-done is kept). Then
"Ready". **Just get it ready** does the download and convert without playing, so the video starts
at once later.

**Ready videos** (under the File controls) lists every video that's ready on this PC, with its
name, its size and the disk space they all use. **Play** starts one straight away; **Delete**
removes it from this PC (it asks first; a link can be downloaded again). In a co-stream, the host's
File section shows who has the video ready and who is still getting it ready.

If it fails, the line says why in
plain words (for example "yt-dlp may be out of date: run tools\get_tools.ps1", a private or
age-restricted video, no internet) with a **Try again** button; what yt-dlp / ffmpeg printed is
under **Details ▸**.

Downloads are limited to 2 GB and 4 hours per video, so a link (yours, or a co-host's in a
co-stream) can't fill your disk. Closing the app while a video downloads or converts stops
yt-dlp / ffmpeg straight away instead of waiting for them, and a stopped convert never leaves a
broken video in the cache.

## Hotkeys
| Key | Action |
|---|---|
| **Space** | Pause to react. Pauses a file directly. For a browser tab it sends the Windows Play/Pause media key. Lights come up, the camera moves to the room's *Reaction* camera, and a badge shows. |
| **F** | Focus view: the video flat and full-frame, so viewers can read it. |
| **1-9, 0** | Camera views (smooth moves), in the order of the Room tab's camera buttons. **0** is the 10th. |
| **PgUp / PgDn** | Previous / next room. |
| **F10** | Clean feed: hides all UI (the webcam overlay stays). |
| **Tab** | Show/hide the control panel. |
| **Esc** | The game menu (see *The Esc menu*). Esc again goes back. |
| **F11** | Fullscreen for now. To keep it, pick **Fullscreen** in the Esc menu's **Display** page. |
| **C** | Chat screen on/off (rooms that have one). |
| **R** | Reply screen on/off (rooms that have one). |
| **B** | Stage curtain: close / open. **Shift+B** = the reveal (lights down, spotlight, drum roll, curtain sweeps open). |
| **F9** | Control panel in its own window / back in the main window. |
| **F6** | Work the control panel with the keyboard (see *Accessibility*). Esc leaves. |
| **Ctrl+= / Ctrl+-** | Control panel bigger / smaller. |
| **Shift+click**, or **P** then click | On a chatter, a presenter or the big screen: their menu (see *Click on people in the room*). |
| **L** (hold) | Laser pointer: a dot where the mouse points, with a beam (see *Laser pointer*). |
| **M** (hold) | Lakeside Campfire only: roast a marshmallow over the fire. Let go while it is golden for a s'more. |
| **T** | Lakeside Campfire only: toss a stick on the fire, which flares up. |
| Right-drag, WASD, Q/E, Shift | Free-look camera: hold the right mouse button and move to look; W/S forward/back, A/D left/right, **Q down / E up**, Shift = 3x speed. **Mouse wheel while right-dragging** = zoom (field of view). |

Hotkeys are ignored while you're typing in a text box (Esc leaves the box).

**Field of view:** Room tab → *Field of view* (25–110°, default 65), or the mouse wheel while
right-dragging. **See into the room from outside** (Room tab ▸ Advanced, on by default): back the camera out
through a wall and the wall (and anything else between you and the room) is cut away instead of
the view going black. It kicks in when none of the room's camera markers can see the camera; the
walls get collision shapes for this (only these rays use them).

**Saved camera views:** fly the camera somewhere you like, type a name next to **Save this view**
(Room tab, under the camera buttons) and press it. The view gets its own button and number key in
this room, and keeps its zoom. **Glide time** sets how long the camera takes to glide between views
(0 cuts straight there). Room tab ▸ Advanced ▸ **Camera views** lists every view of the room: type
a new name and press Enter to rename it, **▲ / ▼** change the order (the number keys follow it),
untick **Shown** to hide one (no button, no key), **Update** moves a saved view to where the camera is
now, and **Delete** removes a saved view (it asks first). The room's own cameras can be renamed,
moved and hidden, never deleted. Each room keeps its own views.

**Big screen light:** Room tab ▸ Advanced → **Screen light** (how much light the big screen
throws into the room) and **Screen glow** (how bright the picture itself glows). They used to be
on the Sound tab.

**Auto-duck:** in the *React* tab the video audio drops (14 dB by default) while your mic hears
you, then comes back up. Set **Talk threshold** (React tab ▸ Advanced, with **Duck by**) by
watching the mic meter. When auto-duck is on but can't hear anything, the meter says
**No microphone** (or **No sound device**). Windows may ask for microphone permission the first time.
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

Each window is one line in the Chat tab: its **Show** tick (labelled with the window's name),
the platform ticks, a small ⚠ when its text would be too small to read on stream, and
**Advanced ▸** for the rest.
- The tick with the window's name (**Left of the screen**, **Right of the screen** ...) turns it
  on or off.
- The ⚠ is a button: click it to open that window's **Advanced ▸**, where **Make readable** is.
- The platform ticks (Kick, Twitch, YouTube, Other): tick one to give it a window of its own, or
  several to mix them. None ticked = no chat in that window. A warning shows (under Advanced)
  when Twitch is mixed with others.
- **Stream Core replies:** *Off*, *Always*, or *When there's no reply screen* (only in rooms
  without one, or with it switched off). Chat games boards come along with replies.
- **Replies to:** *Every platform's chatters*, or *Only this window's platforms* (so Twitch
  answers stay in the Twitch window). The side windows start on *Only this window's
  platforms*, the panels under and above the screen on *Every platform's chatters*. A window
  with no chat ticked always takes every reply.
- **Advanced ▸** opens the rest of the window's settings (remembered), so the tab stays one
  line per window until you tweak one. The readability warning sits in there too, with a
  **Make readable** button that sets the text size it suggests.
- **Header:** a header line across the top of the window. Leave the text empty to name it
  after what it shows ("Twitch chat", "Kick · YouTube chat", "Stream Core replies"); a
  one-platform window's header takes that platform's colour. On by default for the side
  windows.
- **Text size**, **Background**, **Text outline** and **Columns** (the side windows too), and
  for the side windows **Width**, **Height**, **Gap to screen** and **Up / down**.
- **Pictures in chat windows** (above the windows) shows chatters' profile pictures next to
  their names. The Audience tab's **Chatter pictures (everywhere)** turns pictures off
  everywhere, the chat windows included.

### Chat box on the picture (Chat tab)
A chat box in a corner of the picture itself, like the chat games boards: it isn't part of the
room, so it shows from every camera, in focus view and in clean feed (it's part of the show).
- **Chat box:** *Auto (when no chat window shows chat)* puts it up only while no window in the
  room shows chat (for example in a room without a screen, or with the side windows off).
  *Always* keeps it up; *Never* (the default) turns it off.
- **Shows:** the platform ticks, the same as a chat window's.
- **Advanced ▸:** **Corner** (bottom left by default; *Top right* shares the corner with the
  boards), **Box width** and **Box height** (shares of the picture), and the chat windows'
  own options: **Stream Core replies** (chat games boards come with them, and the corner boards
  step aside while the box shows them), **Replies to**, **Header**, **Text size**,
  **Background**, **Text outline** and **Columns**.

Code: `ui/chat_hud.gd` (a "flat" `core/chat_screen.gd`). Test: `_tests/test_chat_hud.tscn`.

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
- **Presets** (they ask "Replace your seating plan?" first when you made a plan by hand that
  they would change): *Anyone anywhere*, *Twitch apart (left)* (Twitch in Q1 + Q3 and the left crowd
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

### Reserved seats (Seating tab)
Give a regular their own seat. When they chat, they go straight to it, and whoever was sitting
there moves to another seat.
- **Reserve a seat:** click the seat on the chart (it gets a white cross; the line under the
  chart says who sits there) and press **Reserve**. Or type a seated chatter's name and press
  **Reserve their seat**. The person in the seat at that moment is who it's kept for.
- Reserved seats have a **gold ring** on the chart. They're listed under the chart with a ★,
  the seat number and section, "here now" while their owner sits in it, and a **Free** button.
  Click a reserved seat and **Free this seat** does the same.
- **Keep reserved seats empty while their owner is away** (on by default): nobody else sits
  there. Off: anyone may sit there until its owner chats.
- Each room keeps its own reserved seats, and they're saved, so a regular has the same seat
  next stream. People are matched by platform and name.
- A reserved seat is always its owner's, whatever the seating plan says.
- **In a co-stream** with one audience, the host's reserved seats count on every PC. A guest
  can reserve the seat of a chatter sitting in the shared audience too (the host's message line
  says so), and can free the ones they reserved.

## Accessibility
- **Panel size** (bottom of the control panel, or Ctrl+= / Ctrl+-): 75-200%. Text, buttons
  and sliders all scale, in the main window and in the panel's own window.
- **Small panel** (bottom of the control panel, on by default): while Stream Core is connected,
  Stream Core's **Setup › Stream Rooms settings** is where you change settings, so the panel keeps
  only what has to be done in the game. The **React**, **Sound**, **Chat**, **Audience**, **Games**
  and **Presenters** tabs hide (their buttons are on Core's Live page or are hotkeys), and on
  **Source**, **Room**, **Seating** and **Co-stream** the setting rows hide too. What stays: picking
  and showing a big screen source, the room picker, curtain and camera buttons, saving and editing
  camera views, the room's own controls, the seating chart, and the co-stream address, password,
  **Host** / **Join** and people list. A line above the tabs has **Open in Stream Core** and
  **Show everything**. When Core isn't connected, everything shows. Nothing is removed: untick it
  to get it all back (if you unticked it before, it stays unticked).
- **Keyboard:** F6 puts the keyboard in the panel (a yellow outline shows where). Tab /
  Shift+Tab move between controls, Left / Right change a slider or switch tabs, Space / Enter
  press buttons and tick boxes, Esc gives the keys back to the hotkeys. Clicking with the mouse
  never leaves a button holding the keyboard, so Space still pauses after you click something.
  On the Seating tab the chart takes the arrow keys too (previous / next section).
- **Exact numbers:** click the value next to any slider (e.g. *75%*), type a number and press
  Enter. It's clamped to the slider's range.
- **Help you can see:** every setting with a tooltip has a yellow **?** beside it that shows
  the same help as a line under it.
- **Colour:** Audience tab ▸ Advanced → **Colour-blind safe colours** switches the platform colours to
  ones that stay distinct with red-green colour blindness (Okabe-Ito); **Brand colours** puts
  them back. The seating chart labels sections with letters (K T Y O: **K**ick,
  **T**witch, **Y**ouTube, **O**ther) as well as colour, and warnings start with ⚠.
- **Chat text on stream:** each chat window has **Text outline** (a dark edge round the
  letters, for a see-through background). The Chat tab warns when a window's text would be
  under about 16 px tall on a 1080p stream from the camera in use, and suggests a size.
- **Flashing lights** (Games tab): **Flash strength** (0-100%) sets how bright FLASHBANG,
  police lights, flicker, fireworks and fire get. **Photosensitive-safe mode** caps flashes at
  30%, slows strobes to under 3 flashes a second, makes FLASHBANG a soft swell and turns camera
  shake off. While it's on and Flash strength is set higher, a note under it says so.

## Performance and laptops (Room tab)
**Performance (this PC)** under the Room tab's **Advanced ▸**. Remembered on this PC, not per room.
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
  stream's frame rate, and set **Most chatters in crowd** (Audience tab ▸ Advanced) to about 100-150.
  Run plugged in, on Windows' best-performance power mode, and make sure Redot and OBS use the
  NVIDIA GPU (Windows Settings → System → Display → Graphics → High performance). Use NVENC
  in OBS so the encoder doesn't load the CPU.

## Click on people in the room
Hold **Shift** and left-click a chatter's silhouette, a presenter or the big screen (or press
**P**, then click without Shift). A small menu opens in its own window, so your stream never shows
it:
- **Throw ▸** a tomato, confetti, a spotlight, balloons or a high five at them. In a co-stream it
  plays on every PC, like a chat reaction.
- **Highlight / glow** makes their seat glow (the same glow as Stream Core's Highlighted message);
  pick **Stop the glow** to end it.
- **Show their last message** puts it on the panel's message line.
- **Seat ▸** reserve their seat for them (or free it), or move them to the front row.
- **Read aloud ▸** stop Stream Core reading them aloud: for this stream, for 24 hours or for good.
- **Copy name** copies their name.

A plain left click does nothing, so it never fires while you move the camera.

## Laser pointer
Hold **L** in the room window and point with the mouse: a bright dot lands on whatever you point
at (the big screen, a wall, the floor), with a thin beam running to it. Let go of **L** and it's
gone. In a co-stream the host and every guest have their own, and everyone sees everyone's, so you
can point things out to each other and to your viewers. It works without a session too.

Set yours in the Co-stream tab under **Laser pointer** (Stream Core's Stream Rooms settings show
the same ones). Each person sets their own:
- **Laser colour**: your dot and beam. Pick one the others don't use, so it's clear whose is whose.
- **Show the beam**: off shows only the dot.
- **Beam starts at**: **My camera** (just beside your camera, like a pointer in your hand) or
  **My podium avatar** (from your avatar's picture on the podium). With **Podium** on **My podium**
  that's the podium you claimed as a guest; for the host it's the first podium on set that no guest
  claimed. Pick a number to use another one. When that podium isn't on set, your camera is used.
- **L turns it on and off**: press **L** once for on and again for off, instead of holding it.

While you free-look (right mouse button held), the laser points at the middle of the view.

## Run the room from Stream Core's Live page

While Stream Rooms is connected to Stream Core, Core's **Live** page shows a **Stream Rooms** card
(it is hidden the rest of the time). From there, or from the dashboard on your phone, you can:

- see what the big screen shows and whether the sender page is sharing (with its frame rate and
  whether it has sound),
- press **Pause to react**, **Focus view**, **Clean feed** and **Play / pause video** (a lit button
  is on),
- pick what the **Big screen** shows: a **Browser tab or window** (**Show** opens the sender page,
  where you click Share and pick the tab; from a phone or another PC, Stream Rooms opens the
  sender page in its own PC's browser instead), a **Video link or file**, any **NDI** source or **Spout** program the game can see
  (VTube Studio, VSeeFace...). **Stop** stops a video, NDI or Spout source,
- open or close the curtain (**Reveal**, **Close**, **Open**),
- change the **Room**, jump to a camera view (the same list as your number keys),
- move the **Stream sound** and **Room sound** sliders,
- put presenters on or off set (podium rooms), and in a co-stream see who has the big screen remote,
  take it back (host) or ask for it (guest).

Every button does exactly what the same control in the game does, so co-stream rules still apply.

## The Esc menu
Press **Esc** in the room for the game menu. It opens in its own window, so an OBS Window Capture
of the room never shows it. **Esc** or **Resume** goes back.

- **Display**: **Window** (**Windowed**, **Borderless** with no frame covering the monitor, or
  **Fullscreen**), **Monitor**, **Window size** (pick your OBS canvas size, often 1920 × 1080; used
  for Windowed and Borderless), **Graphics quality**, **Frame rate cap** and **V-Sync**. The window
  choice is kept for the next start. Until you pick something, the window opens as it always did.
- **Sound**: **Video volume**, **Room ambience** and **Curtain sounds**.
- **Co-stream**: host or join, who's in (with **Co-host** and **Remove** for the host), **Copy
  invite address**, **Resync**, **End session** / **Leave**, the big screen remote (**Give remote**,
  **Take it back**, **Ask for the remote**), **Hide my address** with its **Covered** list, the
  podiums to **Claim** / **Lock** / **Free**, and what everyone follows (**Room**,
  **Curtain and lights**, **Podiums**, **One audience**). The name, password and address are still
  set in the control panel's Co-stream tab.
- **Keys**: every keyboard shortcut.
- **Open Stream Core dashboard** opens Core in your browser. If it asks for the admin token, press
  **Sign in on this PC** there.
- **Quit** closes the app (it asks first while you host guests).

These are the same settings as in the control panel, so changing one in either place changes both.

## Closing the app

Closing the window saves your settings, then shows a black screen for a second and a half before
it shuts down. That's on purpose: the engine this app runs on (Redot 26.2) can crash while it
throws away a room that was just on screen, so the room is hidden first. Switching rooms keeps the
old room hidden for three seconds for the same reason; you won't see it.
The hidden old room stops reacting at once, so a reaction never plays twice during a room change.

Settings are saved to a new file that then replaces the old one, and the save before is kept as
`settings.cfg.bak`. If the app crashes in the middle of saving, the next start reads the backup
instead of losing your settings.

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
- Room tab ▸ Advanced ▸ **Curtain options**: **Curtain colour**, **Curtain speed**,
  **Curtain sounds** (the swish and drum roll are made in the game, no audio files),
  **Reveal dims the lights**, **Mute stream sound while closed**, **Start closed** and
  **Curtain in rooms** (off = no curtain).
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
**Throne Hall** is a podium room too: four stone podiums on the dais either side of the screen,
each with a candle lamp.

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
- **Zoom** / **Presenter up/down:** frame the picture (up/down is a share of the frame's height).

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

**Name tag:** a name shown above the presenter's picture, for example their channel name. Blank
for none.

**Podium picture:** a picture on the front of the podium: a logo, an avatar, a badge. **Browse...**
picks a PNG, JPG, WebP or GIF (animated GIFs play), up to 3 MB; **Clear** removes it. The picture
is stuck to the podium's front surface (it finds the surface itself, so a slanted front works) and
keeps its shape. **Picture size** scales it, **Podium picture self-lit** shows it in its own colours
whatever the room's light, and **Podium picture left/right** / **Podium picture up/down** slide it
along the front.
In a co-stream, guests get a copy of the picture (the file itself travels, so it works
even though it only exists on your PC).
Once a picture is chosen, its **Advanced ▸** holds **Picture size**, **Podium picture self-lit** and
the two **Podium picture** sliders.

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
- Co-stream: Spout only exists on your PC, so guests see a silhouette on a podium that
  shows your Spout sender.
- Needs the **godot-spout** extension in `addons/godot-spout` (github.com/buresu/godot-spout,
  MIT), built for Redot 26.2 with a small patch (see `addons/godot-spout/STREAM_ROOMS_PATCH.md`).
  Without it the game runs as before and the Source tab says the plugin isn't loaded.

## Chat audience (Fridge Stream Core)
Rooms with audience seats (Home Theater, Lecture Hall, Old Classroom) can fill up with your chat:
- **Seats:** everyone who chats gets a seat with a head-and-shoulders silhouette in their own
  colour. **Colour chatters by** (Audience tab ▸ Advanced) picks the colour:
  - *Their chat colour (else from their name)* (default): the platform's chat colour when it has
    one; otherwise a colour picked from their name, so it's the same every time.
  - *Picked from their name*: always the colour from their name.
  - *Their platform*: one colour per platform (Kick green, Twitch purple, YouTube red, other grey by
    default; change them with the four colour pickers below it).
- **Busy chat:** chatter pictures are cut round on background threads (a few finished per frame)
  instead of pixel by pixel on the main thread, and pictures and emotes in memory are kept to
  about 256 MB: the ones not seen for longest are dropped (never one that's on screen) and load
  again from the disk cache if needed. Chat that piles up during a hitch is worked through over
  the next frames instead of all at once. In a co-stream a guest sends its chat to the
  host in small batches.
- **Speech bubbles:** their messages pop up in a speech bubble above their head, with their name
  on top. Each person gets one of four bubble shapes. A message sent with Kick's or Twitch's
  reply button shows a small "↩ replying to Name: what they said" line under the name (the chat
  windows show the same line). YouTube live chat has no reply button. When bubbles would overlap on screen, the
  newest wins: older ones slide up out of its way, and one that would have to move more than a
  couple of bubble heights fades out early instead. At most 16 bubbles are up at once: in busy
  chat a new one ends the oldest, so the graphics card's work stays the same however fast chat
  goes. Finished bubbles are reused rather than built again for every message.
- **Audience looks in Stream Core...** (Audience tab, under **Bubble size**): the bubble colours,
  bubble shapes, silhouettes and group looks are set in Stream Core's dashboard, on the
  **Audience looks** page (under Overlays). This button opens that page in your browser. Every
  change saves on its own and shows in the room straight away while Stream Rooms is connected
  to Core; Stream Rooms remembers the last looks it got, so they stay when Core is closed.
  The page has a live preview and three parts:
  - **Bubbles**: **Bubble colours** (*Light*, the default white bubbles with dark text; *Dark*;
    or *My own style*, the settings below). **Start from** has ready-made looks (Light, Dark,
    Comic, Neon, Glass, Paper, Minimal, Thought cloud) and your own; **Save as...** keeps a
    look under a name and **Delete** removes one of yours. Then **Shape** (*Each chatter's own*,
    or one of rounded box, oval, slanted box, pinched box, cloud for everyone), **Corner
    roundness**, **Tail**, **Fill** (with a see-through slider), **Chatter colour in fill**,
    **Text**, **Name** and **Outline** colours (the chatter's colour or one colour), **Outline
    width**, the **Paid** and **Highlighted** colours, **Text size**, **Bold letters** and
    **Text width**.
  - **Silhouettes**: **Shape** (*Classic*, *Big head*, *Broad shoulders*, *Hoodie*, *Cat ears*,
    *Hair bun*, *Robot*, or *My own picture*). Your own pictures are kept in Core's **Stored
    files**: pick one under **Picture**, or **Upload a picture...** (PNG, JPG, WebP or GIF; a
    see-through PNG works best, a picture without see-through parts is read as a dark shape on
    a light background). An **animated GIF** moves on the seats near the stage (up to 32
    frames are kept); the filler crowd far back shows its first frame. In a co-stream the
    animation goes to the other PCs too. **Add many pictures...** uploads several at once and saves each as a
    look of yours, ready for a random mix. **Painted**, **Colour**, **Brightness**, **Size**,
    **The filler crowd uses it too**, and **Across** / **Down** / **Picture size** for where the
    chatter's profile picture sits on your own picture. Stream Rooms downloads each picture from
    Core once (again only when it's replaced in Stored files).
  - **Groups**: a **Bubble** and a **Silhouette** look for **Mods**, **VIPs**, **Subscribers**,
    **Kick**, **Twitch**, **YouTube**, **Other chat** and **Everyone else** (whoever is left).
    *Random mix...* lets you tick several silhouettes: each chatter in that group gets one of
    them, picked from their name, so they keep it every time they chat. Someone in more than
    one group gets the first one in the list that has a look set, so a mod who subscribes gets
    the Mods look. In a co-stream, each PC uses the looks from its own Core.
  Needs a Stream Core with the Audience looks page. Until you change something there, Stream
  Rooms keeps the looks it had.
- **Glow for highlighted chatter** (Audience tab, on by default): when you highlight a chat
  message in Stream Core (the **Highlighted message** lower third, ★ on a chat line), that
  chatter's seat gets a slow purple glow while their message is on screen. It moves to the next
  highlight and goes away when Core clears it. In photosensitive-safe mode the glow is steady.
  Only chatters with a seat glow. Needs Stream Core v2026.11.2 or newer.
- **Glow while read aloud** (Audience tab, on by default): while Stream Core's **Read aloud (TTS)**
  reads a chatter's line, their seat gets a soft blue glow that fades in and out (no flashing).
  Only chatters with a seat glow. Needs the matching Stream Core build.
- **Colour paid and highlighted messages** (Audience tab, on by default): Super Chats, Kicks and
  Bits get a gold bubble and a gold box on the chat windows; Twitch messages highlighted with
  channel points ("Highlight My Message") get a purple one, like on Twitch; a "Gigantify an
  Emote" message shows its last emote big. Needs the matching Stream Core update.
  **Test chat** sends one of these now and then so you can see them.
- **Bubbles show** (Audience tab): for a very busy chat, pick which messages get a speech bubble.
  Tick any mix of **Text messages** (ordinary messages with words in them), **Emote-only**,
  **Paid** (Super Chats, Kicks and Bits, also when they answer someone), **Highlighted** (Twitch
  highlighted messages and gigantified emotes) and **Replies** (ordinary messages that answer
  someone). Untick **Animated emotes** to show every emote as a still picture, which is lighter
  on the PC. A chatter whose message gets no bubble still sits down. Two buttons set it in one
  click: **Busy chat: paid and highlighted** (only those two, with still emotes) and **Show
  everything** (every box ticked again). The chat windows always show every message.
- **Seat spacing** (Audience tab): how much room there is between seated chatters along a row,
  1 m by default. Seats closer than that to a taken one stay empty, so nobody sits shoulder to
  shoulder; the room has fewer seats than it has places (the Lecture Hall's front pews seat every
  other place, 38 instead of 79). 0.5 m uses every seat. The room reloads when you change it.
- **Name tags** fade out on seats far from the camera, so a wide shot isn't covered in names.
- **Emotes:** chat emotes show inline in the bubbles, and emote-only messages show them bigger.
  That covers Twitch emotes plus BetterTTV, FrankerFaceZ and 7TV emotes (Stream Core sends them
  with each message) and Kick emotes.
  - Images download once and are kept in `user://emote_cache/` (`autoload/emote_cache.gd`).
  - Animated emotes (Twitch, Kick, BetterTTV, FrankerFaceZ, 7TV) play in the bubbles and on the
    chat screen. The engine can't read GIFs, so `core/gif_decoder.gd` decodes them on a worker thread.
    Animated WebP can't be decoded, so 7TV and FrankerFaceZ emotes are fetched as GIFs instead.
    If an animated emote doesn't load, its still picture is used instead.
  - Normal emoji use your system's colour emoji font (Segoe UI Emoji on Windows).
- **Chatter pictures (everywhere):** Kick, Twitch and YouTube chatters' profile pictures fill the silhouette's
  head, cropped round inside their colour ring.
  - Stream Core finds the pictures and saves a copy of each one, and Stream Rooms loads them
    from Core. YouTube pictures come with each message. For Kick and Twitch, Core looks each new
    chatter up once, so their picture appears a moment after their first message. Twitch needs
    **Connect Twitch** in Core's dashboard.
  - Turn pictures off everywhere with **Chatter pictures (everywhere)** (Audience tab), or only in
    the chat windows with **Pictures in chat windows** (Chat tab).
  - Hide one person's picture with **Hide pictures of** (Audience tab), the same list as Core's
    **Never show a picture for**: a name matches the display name or the login, and
    `kick:name` (or `twitch:` / `youtube:`) only matches on that platform. Mid-stream it's
    quicker to pick them from **Hide a picture...** under it: it lists the people seated now,
    newest first, and adds `platform:name` for you. Those names are also added to Core's list
    (the **Chatter profile pictures** card in Core's dashboard), so Core's chat overlay hides
    them too. To show someone again, remove the name in both places.
  - In a co-stream, guests' PCs get the platform's own picture link, since Core's copy
    only exists on your PC.
- **Red-flagged chatters:** Stream Core's dashboard (**Chat history** page, **🚩 Red flags**) has a
  list of phrases. Whoever says one is red-flagged: they leave their seat, their lines leave the
  chat windows, and Core sends nothing more from them (no chat, reactions or commands). Nothing to
  set up in Stream Rooms. **Unflag** them in Core's dashboard to let their new chat through again.
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
  - **Most chatters in crowd** (0 shows as **No limit**) caps how many chatters sit in the crowd seats at
    once. No seats go away: filler people fill the rest, so the room looks the same. Chatters
    are what cost CPU and GPU (picture, name tag, bubble each); filler people are free. When
    the cap is reached, a new chatter takes the seat of whoever has been quiet the longest.
    On a laptop, 100-150 is a good start. New installs start at 300; if you used the app before
    this change your saved value stays (0 = no limit is what most older setups have, so lower
    it if a busy chat makes the room stutter).
  - **Filler people in empty main seats** (off by default) fills the empty pit seats with
    filler people too, at the same share as the crowd; chatters take their places.
  - The filler crowd is one draw call (`core/audience/crowd_layer.gd` + `crowd.gdshader`); only
    seats with a chatter in them cost anything per person.
- **Only what the camera sees is drawn:** a bubble the camera can't see (off-screen, or behind
  the balcony or a post) isn't drawn until it comes into view. Animated bubbles far away
  redraw about 12 times a second instead of every frame. The per-seat work only runs while the
  camera moves.
- **Settings:** all in the **Audience** tab. The ones you use while live are on top:
  - **Show audience**, **Test chat** (fills seats with made-up chatters) and **Empty all seats**
    (everyone leaves their seat; it asks first)
  - **New chatters sit**, **Bubble size**, **Audience looks in Stream Core...**, **Bubbles show** (with **Show everything** and
    **Busy chat: paid and highlighted**), **Name tags**, **Chatter pictures (everywhere)**,
    **Hide pictures of** and **Hide a picture...**
  - **Advanced ▸** holds the rest: **Idle timeout**, **Seat spacing**, **Bubble time**,
    **Colour paid and highlighted messages** (the chat windows' cards too),
    **Show empty seats** (dim placeholders on empty seats), **Hide !commands in bubbles**,
    **Regulars' titles on name tags**, **Ignore names** (bots), the **Colours** block and the
    **Crowd** block

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
- Chat tab settings: which platforms it shows, Stream Core replies, **Pictures in chat windows**,
  text size, columns (1-4) and background opacity (0% = text floating on its own).
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
- **Games tab → Chat reactions:** *Play reactions*, *Allow camera shake*, *Reaction size*, and a
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
  corner otherwise. **Games tab → Chat games:** **Boards in the corner** (auto / always / never),
  **Board size**. **Regulars' titles on name tags** (Stream Core streak titles: "Name · Regular")
  is under Audience tab ▸ Advanced.
  They stay up in clean feed (they're part of the show). Code: `ui/board_hud.gd`, `core/chat_screen.gd`.
  Test: `_tests/test_chat_games.tscn`. Spec: `fridge-stream-core/docs/CHAT_GAMES.md`.
- Code: `autoload/reactions.gd` (the Core link, meters), `core/reactions/reaction_layer.gd`
  (effects, attached to each room by RoomHost). Test: `_tests/test_reactions.tscn` (runs a fake
  Stream Core).

## Co-stream (Co-stream tab)
Co-stream used to be called "Together". Your saved settings carry over as they are.

Up to four people share one room: a **host** who runs the show and up to three **guests**. Everyone runs their own copy of Stream Rooms, flies their own camera and streams their own view from their own OBS. Only small messages travel between the PCs (no video), so it needs almost no bandwidth.

### Connecting

Two ways, and nobody has to open ports on their router either way:

- **Hide my address** (Co-stream tab, host, **on by default**) does it all at once: guests join
  through the Cloudflare tunnel below, and the big screen and everyone's avatars go through
  VDO.Ninja's relay servers, whatever **Listen on** and **Relay the live feed** say. Under it, a
  **Covered:** list says what's hidden, with a ⚠ when something is missing (for example
  `cloudflared.exe`). Guests get the message "This co-stream hides everyone's address." Untick it
  to use **Listen on** as you set it (for example Tailscale). With **Listen on** set to **This PC
  only** (testing two copies) there's nothing to hide and it doesn't apply.
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

1. In the **Co-stream** tab, everyone types a **Your name** and the same **Password**. The host picks the password (at least 8 characters) and tells the guests. A shorter password you saved before this rule still works, but the Co-stream tab asks you to pick a longer one.
2. The host clicks **Host a session**, then **Copy address**, and sends the copied address to the guests (in a private message, not on stream).
3. Each guest pastes it into **Host address** and clicks **Join**.

4. **Both of you confirm.** Once the password checks out, a popup opens on the host's screen:
   "Someone calling themselves *Name* wants to join your session. Let them in?" with **Let them in**
   and **Decline**. The name is whatever they typed, so if you're not sure it's your friend, ask
   them (on Discord, say) before letting them in. At the
   same time the guest gets "You're connected to *Host name*. Is that who you meant to join?" with
   **Yes, join** and **No, leave**. Nothing is shared and nothing syncs until both have said yes;
   until then the guest only sits in a waiting line (the status line says who is waiting). A
   decline, or no answer within two minutes, closes the connection with a message saying why.
   The names are the **Your name** each person typed.

**Leave / stop hosting** ends your part (while you host with guests in, it asks first). A wrong password, or a different Stream Rooms version, is turned away with a message saying why.

### Staying in sync

- **Syncing.** Right after a guest is let in, the host sends everything at once: the room,
  presenters, podium pictures, the audience, its looks and silhouette pictures. The guest's
  Co-stream tab shows **Syncing with *Host*** with a progress bar, and the status strip says
  **Syncing...** until it has all arrived and the room has loaded. Then the status line says
  **In sync with *Host*'s session**. The host's list shows "syncing 40%" next to that guest until
  then. These messages only show on the panel, never on your stream (unless you ticked **Show
  messages on the picture**).
- **The audience checks itself.** While you share one audience, the host's PC sends a short check
  of who sits where every 5 seconds. If a guest's seats differ (a lost message, a room that loaded
  late), that guest gets the whole audience again by itself.
- **Resync** (Co-stream tab) is for when something still looks different on two PCs: a guest
  asks the host for everything again, and the host sends everything to every guest again.
- **Dropped connections.** If a guest's connection drops, their copy tries to get back in by
  itself (8 tries over about a minute and a half). Meanwhile it keeps showing the shared audience
  as it was, and its own chat from that time is kept (up to 100 lines) and seated once it's back.
  The host's PC lets them straight back in without the popup when they return under the same
  name within 10 minutes, and keeps their part of the audience (**Each streamer's viewers sit
  together**) and their looks for them in that time. If the tries run out, the guest goes back to
  its own audience and the status says to click **Join** again. **Leave** stops the tries.
- **Remove** is final: a removed guest doesn't reconnect by itself, and their part of the audience
  isn't kept.

**Limits that protect the host:** at most three guests (a fourth is told the session is full).
After five wrong passwords from one place, joining from there pauses for a minute (through the
Cloudflare tunnel everyone counts as one place, so a real guest may have to wait that minute too).
A connection that doesn't answer the password check within 10 seconds is dropped, and only four
can be at the password check at once. Pictures sent over the session (podium pictures, chatter
pictures) larger than 4096 pixels either way are refused.

**Nothing to leak on stream:** the host address is never shown on screen, only copied, and the
**Host address** box shows dots, like the password. Messages on screen never contain an address
either. The password stays on your PC: only a scrambled check of it is sent.

**A proxy for guests** isn't something the game can do (Redot can't send its connection through
an HTTP or SOCKS proxy). With the tunnel, a guest's address is seen only by Cloudflare, never by the
host or the other guests. A guest who wants to hide from Cloudflare too can run a VPN.

### What's shared

- **Room**, **stage curtain**, **House lights** and the curtain's look (sign, colour, speed).
- **Presenters**: who's on set and what they show. A **web page** presenter (for example a VDO.Ninja link) shows for everyone, and so does **Someone's avatar** (see below). A presenter showing the host's **camera**, **browser tab**, **NDI** or **Spout** only exists on the host's PC, so guests see a silhouette there instead. The same goes for a web page only the host's PC can open (an avatar app on `localhost`, or an address on the home network). When the host picks one of those while guests are in, the message line says so, and suggests the fix: make it your **My avatar** and show it with **Someone's avatar**.
- **Pause to react** (Space): the host's pause pauses every PC (lights up, the Reaction camera, the badge), and so does a co-host's. A guest who isn't a co-host pauses only their own PC. Only the PC whose tab is on the big screen sends the Play/Pause key to its browser, so nobody else's music stops.
- **Chat reactions** from every channel play for everyone: a tomato thrown by a guest's viewer lands in everyone's room, in about the same place. A reaction with its own picture (like the boot for `!boot`) shows that same picture on every PC: the picture is sent along with the reaction the first time it's used in a session. A picture over 3 MB stays on the sender's PC, and the others see a plain emoji (like the 🍅) instead.

Each person keeps their own camera, graphics, sound, chat windows and Stream Core connection.

**Shared with guests** (Co-stream tab, host): three ticks say which parts the guests follow:
**Room**, **Curtain and house lights** and **Presenters**. Untick one and every PC keeps its own:
for example, untick **Presenters** to let each guest pick their own presenter sources, name tags
and podium pictures. Tick it again and the guests get the host's state back.

### One audience for everyone's chat

With **One audience for everyone's chat** ticked (Co-stream tab, on the host's PC), every
streamer's viewers sit in the same audience, and every stream shows the same people in the same
seats, with the same speech bubbles:

- Each guest's chat is sent to the host, and the host's PC seats everyone, using the host's
  seating settings (Audience and Seating tabs). Guests' own chat windows still show only their own chat.
- **Each streamer's viewers sit together** gives each streamer's viewers their own part of the
  audience: two of you get the left and right halves, three or four get a quarter each, and the
  big crowd sections are shared out the same way.
- A viewer of a guest's channel can be thrown at with a reaction from any channel, because
  everyone sees the same seats.
- Everyone sees the host's **audience looks** too (the speech bubbles, silhouettes and group
  looks from the host's Stream Core), with the host's own silhouette pictures: they're sent to
  each guest's PC. A guest's own looks aren't changed, and come back when they leave.
- **Viewers keep their streamer's looks** (host) mixes the looks instead: each chatter shows in
  the bubbles and silhouettes of the streamer whose chat they came from, as set on that
  streamer's own Stream Core (Audience looks page, custom pictures included). For example, if
  you make your audience blue and your guest makes theirs red, the room fills with a mix of blue
  and red chatters, and you can see whose stream each one came from. Every PC shows the same mix.
  Untick it and everyone shows in the host's looks again.
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

- **Host:** nothing extra to do while **Send my shared tab to the guests** (Co-stream tab) is ticked.
  The sender page says "Everyone in the session gets this tab too."
- **Guest:** the Co-stream tab says when the host is sharing. Keep your own sender page open (the
  **Open sender page** button there): it shows the host's tab by itself, no click needed. It comes
  back by itself if the host stops and starts sharing again.
- **A guest's tab on the big screen:** pass that guest the **big screen remote** (below). They
  share a tab in their own sender page as usual, and everyone else's big screen shows it, sound
  included. Switch any time: everyone's own shared tab keeps running in the background (the sender
  page says "ready"), so it comes straight back without picking the tab again. You can also press
  **Share** while watching someone else's tab, to have yours ready for your turn.
  Browsers only let a page's sound through after a click on it, so if the sender page asks,
  click anywhere on it once.
- It goes through **VDO.Ninja**, straight from the host's browser to each guest's (peer to peer),
  about 0.2 to 1 second behind the host. Each guest costs the host roughly 3 to 6 Mbps of upload,
  so a host on a slow connection may want to untick it.
- Straight from browser to browser means the host's and the guests' browsers see each other's
  addresses. **Relay the live feed (hide addresses)** (Co-stream tab, host) sends it through
  VDO.Ninja's relay servers instead, so they don't. It adds a little delay and can lower the quality.
- The stream's name and key are random for each session and only go to guests who got the
  password right.

NDI and Spout aren't shared: they only exist on the host's PC.

### The big screen remote

One person at a time has the **big screen remote**: they decide what everyone's big screen shows
(their own shared tab, a web video, someone's avatar) and their **Pause to react** pauses
everyone. The host starts with it.
- In the list of people (Co-stream tab, or the Esc menu's **Co-stream** page), the host has
  **Give remote** next to each guest, and **Take it back**.
- A guest presses **Ask for the remote**; the host's list shows "asked for the remote", and the
  host decides. Whoever has it can **Give it back**.
- Without the remote, a guest's big screen choices are greyed out and the message line says who
  has it. If the holder leaves, the remote goes back to the host.

### Claim a podium

Each guest can run a podium of their own from their own PC: the Esc menu's **Co-stream** page
lists the podiums with **Claim** (or **Move here**) and **Give up**. A claimed podium shows its
owner's **My avatar**, and its owner sets the name tag, light, picture and chroma key in their own
Presenters tab; everyone sees the changes. Camera and tab sources become the owner's **My avatar**
(NDI and Spout can't travel). The host can **Lock** a podium so nobody can claim it, or **Free** a
claimed one. A podium is freed by itself when its owner leaves.

### For VTubers

Co-streaming without anyone learning where you live:
- Keep **Hide my address** on (it is by default) and check its **Covered:** list says ✓ for
  everything. Put `cloudflared.exe` in the `tools` folder (`tools\get_tools.ps1`).
- Send your avatar as **My avatar** (**Web page (transparent)** for a PNGTuber page, or the VTube
  Studio window as **Tab / window**), not a camera.
- The session address and password go to your guests in a private message, never on stream. The
  game never shows them on screen.
- Your own Stream Core stays on your PC; nothing from it is shared except chat lines and audience
  looks.
- A guest who wants to hide from Cloudflare too can use a VPN.

### Avatars: everyone's picture on podiums and the big screen

Each person picks **My avatar** in their own **Co-stream** tab: **Camera**, **Tab / window** or
**Web page (transparent)** (plus the **Camera** to use, or the **Web page** address). Their sender
page captures it, exactly like a presenter feed, and sends it to everyone in the session through
VDO.Ninja. The sender page gets a **My avatar** row for it, and says "sent to the others" once
somebody shows it.

The host then decides where the avatars show, and every PC follows:

- **On a podium:** Presenters tab, set a podium's **Show** to **Someone's avatar (Co-stream)** and
  pick the person under **Whose avatar** (the list is everyone in the session, you included). The
  podium's chroma key and other picture settings apply as usual, with one exception: a
  **Web page (transparent)** avatar is sent over pure green, and every PC cuts out exactly that
  green, whatever the podium's own **Key colour** says. So a see-through avatar looks the same on
  every stream without anyone having to match colours.
- **On the big screen:** Source tab, **Big screen shows** lists the same people. Pick one and their
  avatar takes the big screen on every PC (at the **Avatars** quality, so choose 720p there for
  this); pick **(nobody)** to go back to your own shared tab.

Your own avatar shows on your PC straight from your sender page (nothing travels), and someone
who isn't in the session right now leaves their podium waiting until they join. NDI and Spout
avatars can't travel this way (they live in the game, not the browser); for those, send them to OBS
and from there into a web page, for example a VDO.Ninja link.

**Quality** (Co-stream tab under **Advanced ▸**, host decides for everyone; everything is sent once per viewer, so lower
it on a slow upload): **Big screen to guests** 480p / 540p / 720p / 1080p, **Big screen frame rate**
and **Big screen bitrate** for the shared tab; **Avatars** 240p / 360p / 480p / 720p, **Avatar frame
rate** and **Avatar bitrate**. Rough costs per viewer: a 720p tab 3 to 6 Mbps, a 540p tab about 2;
a 480p avatar 0.5 to 1 Mbps, a 240p avatar 0.2 to 0.4. Changes apply while live.

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
  `get_controls()` in `room.gd` (headings, sliders, tick boxes and colour pickers bound to AppState
  settings; see `rooms/neon_city/neon_city_room.gd` for the Rain slider and
  `rooms/throne_hall/throne_hall_room.gd` for the Benches tick box). A setting that moves seats
  only takes effect when the room loads again: list it in `reload_keys()` and the room reloads
  when it changes.
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
    and film flutter. Use **Speaker FX** in the *Sound* tab ▸ Advanced to set how much (0% = clean).
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
  - One ring chandelier hangs high in the middle of the ceiling, above every seat's view of the
    screen. It dims with the house lights. Use **House lights** in the *Room* tab to set
    the level by hand (it scales the automatic dimming too).
  - 12 cameras: pit, front row, centre rows, rear diagonal, side seat under the balcony,
    three balcony seats, the gallery rail, a Reaction camera by the webcam monitor, the lectern
    (looking out at the hall), and a view past the chandelier. Press **0** for the 10th.
  - A big-room reverb and a faint room tone.
  - Source: `../blender/lecture_hall.blend`, built by `blender/lecture_hall_gen.py`
    (textures for the glass, doors and EXIT sign: `blender/make_hall_textures.py`).
- **Throne Hall**: a vast dark hall, 60 m long and 30 m high, with a tall throne on a dais.
  - A crimson runner leads down the nave between black marble columns, each with a tall banner
    hung from a gold bracket. Two railed galleries run along each side wall behind the columns
    (the filler crowd sits there), pale ribbed cladding towers above them, and three caged
    lanterns with candles hang in a row from the coffered ceiling.
  - The dais at the far end has three steps up to a tall pointed throne. A shaft of blue light
    falls on it from a slot in the ceiling.
    **Throne light** (Room tab) sets how strong the beam is, 0-200% (0% = off).
  - The screen (the same size as the Lecture Hall (Panel)'s) floats in front of the throne, so
    the throne's tall back rises behind the picture. The chat screen hangs under it and
    the reply screen above it.
  - A podium room: four stone podiums on the dais, two flanking the screen and two further
    out near the steps, each with a candle lamp (see *Presenters*). No webcam frame: the webcam
    uses the corner overlay.
  - The chat audience stands in two lines along each edge of the carpet, like a court, facing
    the throne. **Benches** (Room tab) puts stone benches under them: tick it and everyone sits
    down (the room reloads to re-seat them, as changing the seat spacing does).
  - Cameras: the carpet at the entrance (the default), beside a column, in front of the dais,
    the left and right galleries, past a chandelier, three podium views and a Reaction camera
    looking across the dais at the throne. Press **0** for the 10th.
  - Reaction targets: `!tomato throne`, `chandelier`, `banner left`, `banner right`.
  - A big stone-hall reverb and a faint cold draught.
  - Source: `blender/throne_hall_gen.py` (run inside Blender: see the top of that file; it
    writes the `.glb` and `crowd_seats.json`). The cloth, marble, carpet, stone and cladding
    textures come from `blender/make_throne_textures.py`, which paints the crest picture you
    give it onto the banner (`rooms/throne_hall/textures/crest_source.png`; swap that file and
    run the script again for another crest).
- **Forge Hall**: a long, tall hall of polished granite with a little science fiction in it,
  modelled on a reference picture and a cross-section sketch.
  - Walls and floor are big slabs of dark polished granite (fine speckle, a mirror shine).
    The pillars are a shade lighter, in veined marble, and the forge is a steelier granite
    with a metallic glint. Lines of cyan, orange and purple light are set flush into them like the traces of
    a circuit board, running to a "chip" in the floor in front of the screen and a second one
    halfway down the hall. A layer of much finer traces runs between the main lines on the
    floor, the walls and the forge.
  - Above the walls a ledge carries tall slanted windows that lean in to an upper level of
    stone and steel, under a ceiling of dark diamond plate on steel girders. Short-chained
    hexagonal lanterns hang close to the ceiling. There is no window next to the forge.
  - Brass and iron pipework with valves and gauges runs along the ledges and down the walls.
    Under the ceiling, between the two rows of windows (so it never blocks them), hang a square
    air duct with grilles and a fan unit, a round duct and a run of pipes.
  - **Time of day**: the windows look out on a sky the room draws itself, with a dark fantasy
    look: a deep blue day sky with billowing clouds lit by the sun and rays fanning out from
    it, pink and orange clouds at sunrise and sunset, and at night a moon, a dense field of
    stars with a few that sparkle, and purple and blue nebula clouds. The
    sunbeams and the barred patches of light on the floor follow the sun (pale and blue under
    the moon), and the room's own daylight dims at night so the inlays and the fire carry it.
    Room tab:
    - **Time of day**: 0 to 24 hours (6 = sunrise, 12 = noon, 18 = sunset).
    - **Day length**: how many minutes a whole day and night take when the clock runs by
      itself. **Clock stopped** (0) keeps the time where the slider is.
    - **Clouds**: how much cloud drifts across the sky (0% = clear, 200% = heavy).
    - **Nebula**: how strong the night's nebula clouds are (0% = stars only).
    - **Stars**: how bright the stars are (0% = none).
    - **Clouds** and **Nebula** at 0% are the lightest settings for a slow graphics card.
    - **Light rays**: the sunbeams and floor patches (0% = off).
  - **Please stand by**: this room has no curtain. Closing the curtain (the **Curtain** button,
    its hotkey or Stream Core) fades a "please stand by" test card in over the big screen
    instead, the kind TV stations showed when they went off the air, and opening it fades the
    card away. The stream sound mutes the same way, **Curtain speed** sets how fast it fades and
    the **Sign** text shows across the bottom of the card. The curtain's colour, sound and
    reveal settings do nothing here.
  - The screen hangs in a wide alcove. It can show LED dots and the hologram look like Neon
    City's, and it can be bent, resized and moved. Room tab:
    - **LED dots**: how strongly the picture is broken into dots (0% = smooth). The same slider
      now shows in Neon City.
    - **Hologram**, **Transparency**, **Glitch**, **Scan lines**, **Scroll speed**, **Noise**,
      **Line colour 1**, **Line colour 2**: the hologram look, shared with Neon City.
    - **Bend**: above 0% the screen's edges wrap towards the audience (concave), below 0% its
      middle bulges out (convex).
    - **Size**, **Move left/right**, **Move up/down**: the screen stays inside its alcove, so
      make it smaller to move it further. The room reloads a moment after you let go of one of
      these four, so the screen's light and the stand-by card follow.
  - **Small live screens**: three extra screens, each about a quarter of the big screen's
    width. One rises out of the square in the middle of the floor chip; two hang above the big
    screen. Room tab, **Small live screens**:
    - **Raise the floor screen**: brings the floor screen up, or lowers it back into the floor.
    - **Floor screen**, **Upper left screen**, **Upper right screen**: what each one shows:
      Off, Webcam (the webcam from the sender page; the corner overlay steps aside while a
      screen shows it), Podium 1 to 4's feed (whatever that podium shows live; the podium has
      to be on in the Presenters tab), Copy of the big screen, Picture file, or a feed of the
      screen's own: **NDI source**, **Spout sender**, **Stream address** or **Browser tab or
      window**. The three screens can each have a different one. These feeds are picture only
      (no sound).
    - **Browser tab or window**: each small screen can show a tab or window of its own, apart
      from the big screen and the podiums. Pick the source, then look at the sender page
      (**Share to Stream Rooms** on Stream Core's Live page, or the game's own sender page): a
      box **Extra screens** appears with a row named after the screen. Click **Pick a tab or
      window** on that row and choose what it shows. **Stop** on the row ends it, and the
      screen goes dark. The sender page has to stay open, as for the big screen.
    - Where these controls are: the game's **Room** tab, or in Stream Core under Setup > Stream
      Rooms > Room & sound, in the last section (**More from Stream Rooms**), while the Forge
      Hall is the room on screen.
    - **Floor screen picture** (and the two others): the file used for Picture file.
    - **Floor screen address** (and the two others): what the screen's own feed connects to.
      Press Enter to apply.
      **Pick** beside the box lists the NDI sources and Spout senders found right now;
      choosing one fills in the name and switches the screen to it. An address with a login
      in it (`rtsp://name:password@...`) shows as dots until you click into the box, so it
      can't be read off the panel on stream. (Stream Core's page shows it in full.)
      - For NDI source or Spout sender: the source's name as the Source tab lists it, or just
        part of it (`cam 2` finds `STUDIO-PC (cam 2)`). The screen lights up by itself when the
        source appears.
      - For Stream address: an `rtmp://`, `rtsp://`, `srt://` or `http` stream address (an IP
        camera, a media server, a phone camera app), or a video file, which loops. This needs
        `ffmpeg` in the `tools` folder (`tools/get_tools.ps1`). A stream that drops is tried
        again every few seconds.
      - A camera or phone app that *sends* RTMP needs somewhere to send it. Put `listen:` in
        front (`listen:rtmp://0.0.0.0:1935/live/cam`) and the screen waits for it to connect
        to this PC; point the app at `rtmp://<this PC's address>:1935/live/cam`. Windows may
        ask once to let ffmpeg through the firewall.
    - **Wall screens: place**: the two screens above the big screen can be moved, resized,
      tilted and turned. Each has **left/right**, **up/down**, **size**, **tilt** (+ leans the
      top towards the seats) and **turn** (+ turns its face to the right) sliders.
      **Keep the two wall screens aligned** (ticked by default) makes the upper right screen a
      mirror image of the upper left one, so you only set the left one; untick it to place
      each screen on its own.
    - These three screens are yours only: they are not sent to co-stream guests.
  - Thirteen alcoves are cut into the walls between the pillars, lined with wood panelling.
    Each holds a framed picture. Room tab, **Alcove art**:
    - **Frame**: Brass, Steel, Dark wood, Granite, Light strip (glows, follows **Inlay
      brightness**) or No frame.
    - **Art style**: Picture (flat on the wall, lit by the room) or Hologram (see-through and
      glowing, floating in front of the wall).
    - **Art 1** to **Art 13**: a picture file for each alcove (PNG, JPG, WebP or GIF, up to
      3 MB; **Browse...** picks one, **Clear** brings the built-in poster back). 1 to 6 are the
      left wall counted from the front, 7 to 11 the right wall, 12 and 13 the back wall.
  - A big forge fireplace is built out from the right wall, with a second fire slot under the
    hearth. Its chimney carries riveted iron bands, turning-gear shapes, a brass porthole,
    pistons, glowing power cells, copper coils and a small control panel. The fire is several
    flames side by side that curl and split as they rise, over a bed of glowing coals, with
    sparks drifting up. The flames and flickering light are drawn by the room (the flicker is gentle and stops in
    photosensitive-safe mode).
  - Room tab: **Fire** (flames, their light and the crackle, 0-200%, 0% = out),
    **Inlay brightness** (the light inlays, both the main lines and the fine layer, and the
    glowing pipes, 0-300%, 0% = off; above 100% they brighten fast, 300% is five times the
    100% glow) and **Inlay glow (halo round the lines)** (untick it and the inlays are bright,
    sharp lines without the soft bloom round them; they then stop getting brighter at about
    100%, and the room's other glows get a little smaller too).
  - A podium room: four stone podiums, two each side of the screen (see *Presenters*). No
    webcam frame: the webcam uses the corner overlay, or one of the small live screens.
  - Seats for 30: three rows of benches either side of a centre aisle, each row a step higher.
    There is no filler crowd. The back half of the hall is open floor.
  - The rest of the room: a boiler with pipes and a round cyan sign, a workbench, an anvil,
    barrels and crates, and in the back half a second workbench, a small steam engine with a
    flywheel and a tall double door.
  - Cameras: the centre aisle (the default), the forge corner (the reference picture's view),
    the front row, beside the fire, up under the ceiling at the back (the whole length of the
    hall), by the slanted windows, three podium views and a Reaction camera looking at the
    fire. Press **0** for the 10th.
  - Reaction targets: `!tomato forge`, `lantern`, `anvil`, `boiler`.
  - A medium stone-room reverb and the sound of the fire.
  - Source: `blender/forge_hall_gen.py` (run inside Blender: see the top of that file; it
    writes the `.glb`). The granite, wood, metal, sign, sun-patch and stand-by card textures
    come from `blender/make_forge_textures.py`. The sky is `rooms/forge_hall/forge_sky.gdshader`.
- **Lakeside Campfire**: an outdoor room. A campfire in a forest clearing at the edge of a
  lake, with mountains behind it and a sky that changes with the hour and the weather.
  - The big screen hangs between two wooden posts with the lake behind it. Untick **Big screen**
    (Room tab) and the screen is taken down, which opens the view over the water; the posts and
    the string lights stay, and the sound of whatever is playing carries on.
  - A podium room without podiums: the four presenters sit on camp chairs round the far side
    of the fire, facing the main camera (see *Presenters*). No webcam frame.
  - Seats for 30: three curved rows of split-log benches on the near side of the fire. There is
    no filler crowd.
  - Around the clearing: three modern dome tents with lanterns in them, a small stream that
    runs down the left side into the lake with a footbridge over it, a little jetty, a pile
    of sticks, a s'mores table with a cool box, and a forest of fir and round trees.
  - **Woods close around the camp** (off to start with) plants thick trees right round the
    clearing and a wall of firs along the shore behind the screen. The lake is hidden and the
    camp sits deep in the forest. The stream and the jetty still peek through a little, and
    the Lake and Sky camera stands at the water past the trees, so it keeps its view. In a
    co-stream it is the host's, like the weather.
  - **Fire** sets how big the campfire is (0% puts it out). It lights the clearing at night
    and it burns lower in the rain.
  - **Time of day** is the hour, 0 to 24: sunrise at 6, noon at 12, sunset at 18. The sun, the
    moon, the colour of the sky, the light on the ground and the reflection on the lake all
    follow it. **Day length** lets the clock run by itself: the number of minutes a whole day
    and night takes (0 = **Clock stopped**).
  - The sky is built from layers: the sky colour, stars with a Milky Way and the odd shooting
    star, an aurora, the sun and the moon, thin high cloud, big low cloud, two mountain ridges
    with mist between them and a far tree line. **Clouds**, **Stars**, **Aurora** and **Mist**
    set how much of each there is. On a slow graphics card, **Clouds** and **Aurora** at 0% are
    the lightest.
  - **Rain** makes it rain, as hard as you like: the clouds close in, the ground goes dark and
    shiny and rings spread on the lake. **Thunderstorm** adds heavy rain, wind in the trees and
    lightning with thunder. The lightning follows **Flash strength**, and in photosensitive-safe
    mode a strike is a slow, dim glow instead of a flash.
  - **String lights and lanterns** and **Fireflies at night** switch those on and off. The
    string lights follow the **House lights** slider.
  - **Fire games (M and T keys)**: hold **M** in the room window and a stick pokes out of your
    avatar picture with a marshmallow over the fire. It browns while you hold: white, golden,
    brown, black, and if you leave it too long it catches fire. Let go while it is golden and it
    counts as a s'more. Press **T** to toss a stick on the fire and watch it flare up. In a
    co-stream every guest has their own stick and everyone sees everyone's. Chat can feed the
    fire too: any reaction thrown at the campfire (`!tomato campfire`) makes it flare.
  - In a co-stream the fire, the screen, the time of day, the sky and the weather are the
    host's and everyone sees the same (a co-host can change them too).
  - Cameras: across the fire at the screen (the default), beside the fire from the right and
    the left, back from the screen at everyone, from a tent, the lake shore, a drone view from
    high up, close on the marshmallows, a Reaction camera, and the lake and the sky with the
    camp behind you. Press **0** for the 10th.
  - Reaction targets: `!tomato campfire`, `lake`, `tent`.
  - Almost no reverb (it is outdoors). The fire crackles, crickets sing at night, and the rain and
    the thunder have their own sound.
  - Source: the whole set is built in code when the room loads (`rooms/campfire/campfire_builder.gd`),
    so there is no Blender file. The sky is `rooms/campfire/camp_sky.gdshader`.
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
- `autoload/`: EventBus (signals only), AppState (settings and state), DebugLog (the cleaned
  troubleshooting log), SaveManager (`user://settings.cfg`), RoomCatalog, AudioManager (buses, reverb, ducking), SystemMedia
  (media key), ChatFeed / AudienceManager / EmoteCache (chat audience), Reactions (chat reactions)
- `core/reactions/`: ReactionLayer, the per-room effects for chat reactions
- `core/`: main scene and wiring, RoomHost (threaded load and fade, graphics quality via
  `graphics_quality.gd`), ScreenFeed (file and capture sources, A/V delay), CaptureServer (local HTTP + WebSocket), ScreenLights, WebcamDisplay,
  CameraRig, Hotkeys, VideoLoader
- `core/interiors/`: the interior-window facade shader and its room atlas (8 room types)
- `ui/`: control panel (with the status strip and message line), focus view, overlays (toasts when **Show messages on the picture** is on, badge, webcam corner)
- `web/sender.html`: the browser sender page. **When exporting the game**, add `web/*` to
  *Export > Resources > Filters to export non-resource files*.
- `rooms/`: one folder per room

The link only listens on `127.0.0.1` (this PC). Ports 8765 and 8766 are in AppState's defaults (a copy started with `--mp-profile` shifts them, see Co-stream).

## Checks on GitHub (for developers)
Every pull request (and every push to main) runs a short check on GitHub: the script warning check (`tools/lint_warnings.py`), a project import that fails on any script that doesn't load, and a few fast tests without a graphics card (`tools/ci_tests.sh`). The full test set (Forward+, pictures, crashes) still runs on the PC with `tools\run_tests.ps1`.

## License

Copyright (C) 2026 Sensoka (sensokasucks).

This project is free software under the [GNU General Public License v3.0](LICENSE) (GPL-3.0). You can use it for free, including on monetized streams and other commercial use, change it, and share it. If you pass it on to anyone, changed or not, free or paid, you must give them the full source code under the same GPL-3.0 terms.

Bundled third-party parts keep their own licenses, as noted next to them:

- Redot / Godot engine (used to build the app): MIT
- `addons/godot-spout/` (Spout2): MIT and BSD, see `addons/godot-spout/LICENSE` and `licenses/`
- `addons/godot-ndi/`: MPL-2.0, see `addons/godot-ndi/LICENSE` and `NOTICE.md`
- `web/vdoninja-sdk.min.js` (VDO.Ninja SDK): MPL-2.0, see `web/vdoninja-sdk-LICENSE.txt`
- Screen shader code from godotshaders.com: CC0; window interior shader adapted from MIT-licensed code

The NDI runtime is not part of this project and is installed separately under NDI's own terms. As an additional permission under GPL-3.0 section 7, you may combine and convey this program with the NDI runtime libraries.
