extends Node
## AppState: single source of truth for settings and runtime app state.
## Other systems read with get_setting() / the getters and change things only
## through the methods here, which emit EventBus signals.

const BASE_DEFAULTS: Dictionary = {
	"room_id": "theater",
	"volume": 0.8,               # 0..1, video/stream audio
	"ambience_volume": 0.5,      # 0..1, room background sound
	"room_acoustics": 1.0,       # 0 = dry, 1 = the room's own reverb, 2 = exaggerated
	"room_speaker": 1.0,         # 0 = clean, 1 = the room's own speaker character (e.g. old projector speaker)
	"audio_delay_ms": 150.0,     # delays stream audio to line up with video
	"video_delay_ms": 0.0,       # delays stream video (if audio is behind instead)
	"screen_light": 1.0,         # how strongly the screen lights the room
	"screen_glow": 1.6,          # screen emission brightness
	"duck_enabled": true,
	"duck_threshold_db": -38.0,  # mic level that counts as talking
	"duck_amount_db": -14.0,     # how far the video audio drops while talking
	"react_lights_up": true,     # raise house lights during a react pause
	"react_camera": true,        # jump to the "Reaction" camera during a react pause
	"auto_dim_house": true,
	"house_lights": 1.0,         # 0..1 dimmer for every room's house lights (chandeliers, lamps)
	# Room-specific looks (the Room tab shows them only in rooms that use them)
	"film_look": 1.0,            # old-film rooms: 0 = clean picture, 1 = the room's look, 2 = extra dirt
	"sun_rays": 1.0,             # Lecture Hall light rays from the windows: 0 = off, 1 = normal, 2 = strong
	"rain_amount": 1.0,          # rainy rooms: 0 = no rain, 1 = normal, 2 = downpour
	"holo_amount": 0.0,          # hologram screens: scan-line colour strength (0 = off)
	"holo_transparency": 0.0,    # hologram screens: 0 = solid, 1 = invisible
	"holo_glitch": 0.0,          # hologram screens: glitch strength
	"holo_lines": 100,           # hologram scan lines down the screen
	"holo_speed": 0.4,           # hologram scan-line scroll speed
	"holo_noise": 0.05,          # hologram static
	"holo_color1": Color(0.0, 0.0, 1.0),
	"holo_color2": Color(1.0, 0.0, 0.0),
	# Chat audience (Fridge Stream Core chat -> silhouettes with speech bubbles)
	"chat_enabled": true,        # connect to Stream Core's WebSocket
	"chat_core_url": "ws://127.0.0.1:3850/ws",
	"audience_enabled": true,    # show the audience in rooms that have seats
	"audience_idle_min": 10.0,   # minutes without chatting before someone leaves their seat
	"audience_bubble_s": 8.0,    # seconds a speech bubble stays up
	"audience_bubble_size": 1.0, # speech bubble size multiplier
	"audience_names": true,      # name tags over the silhouettes
	"audience_show_empty": true, # dim placeholders on empty seats
	"audience_hide_commands": true,   # !commands seat the chatter but show no bubble
	"audience_platform_colors": true, # (old; see audience_color_by)
	"audience_color_by": "chat", # silhouette / name colours: chat (the chatter's own chat colour) | name (picked from the name) | platform
	"platform_color_kick": Color("53fc18"),
	"platform_color_twitch": Color("9146ff"),
	"platform_color_youtube": Color("ff3b3b"),
	"platform_color_other": Color("d0d4dc"),
	# Seating by platform (the audience kept physically apart, e.g. Twitch's rules on mixing chats)
	"seating_by_platform": false,  # use the seating plan
	"seating_plan": "",          # JSON {section id: "kick,twitch,youtube,other"}; a missing / blank section = anyone
	"seating_strict": true,      # a chatter whose sections are full waits (or takes an idle chatter's seat there) instead of sitting elsewhere
	"audience_avatars": true,    # chatters' profile pictures as the silhouette's head (Kick + YouTube)
	"audience_hide_avatars": "", # names whose picture is never shown (comma separated)
	"audience_seating": "random",  # new chatters sit: random | front (front row, centre out) | front_random (front row first, random seat in it)
	"audience_crowd": true,      # rooms with a big crowd (lecture hall tiers, balcony, gallery): show the filler crowd
	"audience_crowd_fill": 0.6,  # share of the crowd seats with a filler person (chatters take their places)
	"audience_crowd_idle_min": 10.0,   # minutes without chatting before a chatter leaves a crowd seat
	"audience_crowd_move_down": true,  # chatters in the crowd move down into main seats as they free up
	"audience_crowd_max": 0,     # most chatters in crowd seats at once (0 = no limit); the rest stay filler people
	"audience_fill_main": false, # empty main seats show filler people too (chatters still take them)
	"chat_screen": false,        # chat panel under the main screen (rooms with a CHAT_Screen marker)
	"chat_screen_text": 1.0,     # chat screen text size multiplier
	"chat_screen_columns": 2.0,  # messages flow top-to-bottom through this many columns
	"chat_screen_bg": 0.75,      # chat screen background opacity
	"chat_screen_pictures": true,  # chatter profile pictures next to names
	"chat_screen_hide_commands": false,  # hide !commands on the chat screen (separate from bubbles)
	"reply_screen": true,        # Stream Core's replies to chat commands on a panel above the main screen (rooms with REPLY_Screen)
	"reply_screen_text": 1.4,    # reply screen text size multiplier
	"reply_screen_bg": 0.75,     # reply screen background opacity
	"reply_screen_hold_s": 45.0, # seconds a reply stays up (0 = until pushed off by newer ones)
	# What each chat window shows: <window>_chat = platforms (kick,twitch,youtube,other; "" = no chat),
	# <window>_replies = Stream Core replies + chat games boards: off | on | fallback (only when the
	# room has no reply screen showing)
	"chat_screen_chat": "kick,twitch,youtube,other",
	"chat_screen_replies": "off",
	"reply_screen_chat": "",
	"reply_screen_replies": "on",
	# Tall chat windows beside the main screen (every room with a screen)
	"chat_left": true,
	"chat_left_chat": "twitch",
	"chat_left_replies": "fallback",
	"chat_left_text": 1.0,
	"chat_left_bg": 0.75,
	"chat_left_columns": 1.0,
	"chat_left_width": 2.4,      # metres
	"chat_left_height": 1.0,     # share of the screen's height
	"chat_left_gap": 0.35,       # metres from the screen's edge
	"chat_left_lift": 0.0,       # metres up (+) / down (-)
	"chat_right": true,
	"chat_right_chat": "kick,youtube,other",
	"chat_right_replies": "fallback",
	"chat_right_text": 1.0,
	"chat_right_bg": 0.75,
	"chat_right_columns": 1.0,
	"chat_right_width": 2.4,
	"chat_right_height": 1.0,
	"chat_right_gap": 0.35,
	"chat_right_lift": 0.0,
	# a header line across the top of each chat window; empty text = named after what it shows
	# whose Stream Core replies a window shows: "all" = every platform's, "chat" = only replies to
	# chatters of the platforms the window shows (a window with no chat always takes them all)
	"chat_left_replies_for": "chat",
	"chat_right_replies_for": "chat",
	"chat_screen_replies_for": "all",
	"reply_screen_replies_for": "all",
	"chat_left_outline": 0.0,    # dark edge round chat text (0 = none, 1 = thick); helps over a see-through background
	"chat_right_outline": 0.0,
	"chat_screen_outline": 0.0,
	"reply_screen_outline": 0.0,
	"flash_strength": 1.0,       # how bright flashing reactions get (flashbang, police lights, flicker, fireworks), 0-1
	"photosensitive_safe": false,  # caps flashes at 30%, slows strobes to under 3 a second, no camera shake
	# Performance (Room tab): per machine. graphics_quality is the preset last picked; the gfx_*
	# switches are what's applied (core/graphics_quality.gd). High = what the rooms are built with.
	"graphics_quality": "high",  # low | medium | high | custom
	"gfx_gi": true,              # SDFGI bounce light in rooms that use it
	"gfx_fog": "full",           # volumetric fog: off | low (coarser grid) | full
	"gfx_ssao": true,            # screen-space ambient occlusion
	"gfx_ssr": true,             # screen-space reflections (Neon City's wet street)
	"gfx_msaa": 2,               # 3D anti-aliasing: 0 (FXAA instead) | 2 | 4
	"gfx_shadows": "high",       # soft shadow quality / atlas size: low | medium | high
	"gfx_render_scale": 1.0,     # 3D resolution, 0.5-1 (below 1 is scaled up with FSR)
	"fps_cap": 60,               # frames per second cap: 30 | 60 | 0 (unlimited)
	"vsync": true,               # wait for the display refresh (no tearing)
	"panel_scale": 1.0,          # control panel size (text, buttons, sliders), 0.75-2
	"panel_folded": "",          # Chat tab window sections folded away (CSV of window keys)
	"chat_left_header_on": true,
	"chat_left_header": "",
	"chat_right_header_on": true,
	"chat_right_header": "",
	"chat_screen_header_on": false,
	"chat_screen_header": "",
	"reply_screen_header_on": false,
	"reply_screen_header": "",
	"reactions_enabled": true,   # play chat reactions (🍅, !tomato ...) sent by Stream Core
	"reaction_size": 1.0,        # size of thrown / falling reaction objects
	"reaction_camera_shake": true,  # let camera_shake reactions move the camera
	"board_hud": "auto",         # chat games boards (polls, predictions ...) in a corner: auto (rooms without a reply screen) | on | off
	"board_hud_scale": 1.0,      # size of the corner boards
	"audience_titles": true,     # regulars' titles (Stream Core streaks) on name tags
	# Stage curtain in front of the main screen (B closes / opens, Shift+B = reveal)
	"curtain_enabled": true,     # hang the curtain in rooms with a main screen
	"curtain_start_closed": false,  # start the app with the curtain closed (for a reveal)
	"curtain_mute": true,        # mute the stream sound while the curtain is closed
	"curtain_sign": "",          # sign on the closed curtain ("" = none), e.g. "Be right back"
	"curtain_color": Color(0.5, 0.02, 0.05),
	"curtain_speed": 1.0,        # open / close speed multiplier
	"curtain_sound": 0.8,        # swish / drum roll volume (0 = silent)
	"curtain_show_lights": true, # the reveal dims the house lights and uses a spotlight
	"camera_fov": 65.0,          # camera field of view in degrees (mouse wheel while right-dragging changes it too)
	"camera_see_through": true,  # outside the room, see in through the walls instead of hitting black
	# Control panel in its own window (F9), so it never shows up in a window capture
	"panel_window": false,
	"panel_window_pos": "",      # "x,y" of the panel window
	"audience_ignore": "nightbot, streamelements, streamlabs, moobot, fossabot, wizebot, botrix, kicklet, sery_bot",
	"webcam_in_room": true,      # false = show webcam as a corner overlay instead
	"capture_http_port": 8765,
	"capture_ws_port": 8766,
	# NDI (addons/godot-ndi): the main screen can show an NDI source instead of the browser tab
	"ndi_source": "",            # last NDI source picked for the main screen
	"ndi_auto": true,            # reconnect to it by itself when it shows up (and nothing else is playing)
	"ndi_audio_buffer_ms": 500.0,  # NDI sound kept queued (patched plugin): rides out network / OBS hiccups, adds delay
	"max_height": 720,           # file/URL conversion height
	"loop_files": true,
}

## Presenter podiums (rooms with PRESENTER_<n> markers). Keys are "presenter_<n>_<field>", n = 1..4.
const PRESENTER_COUNT: int = 4
const PRESENTER_FIELDS: Dictionary = {
	"on": false,                 # on set (podium, picture and lamp shown)
	"source": "silhouette",      # "silhouette" | "green" | "camera" | "tab" | "web" | "ndi"
	"camera": "",                # camera device id for "camera" ("" = default camera)
	"url": "",                   # web page for "web" (shown over the key colour, e.g. a transparent avatar page)
	"ndi": "",                   # NDI source name for "ndi"
	"self_lit": false,           # glows like a light panel instead of taking the room's light
	"light": 1.0,                # podium lamp brightness (0..3)
	"key": true,                 # chroma key on camera / tab pictures
	"key_color": Color(0.0, 1.0, 0.0),
	"key_similarity": 0.28,      # how close to the key colour counts as background
	"key_smoothness": 0.08,      # soft edge width
	"key_spill": 0.6,            # remove the key colour's glow from the edges
	"zoom": 1.0,                 # picture size inside the frame
	"offset_y": 0.0,             # move the picture up (+) / down (-)
	"chat": "",                  # their chat name(s), comma separated ("kick:name" = that platform only):
	                             # they sit on this podium instead of in the audience, and their
	                             # chat commands and bubbles come from here
	"chat_look": true,           # silhouette mode: look like the chat audience (their colour + picture)
	"chat_bubbles": true,        # their chat messages pop up as speech bubbles over the podium
}

## Every setting and its default (base settings + one set per presenter).
var DEFAULTS: Dictionary = _build_defaults()
var _settings: Dictionary = DEFAULTS.duplicate(true)
var _source_mode: String = "none"
var _playback_active: bool = false
var _react_paused: bool = false
var _focus_view: bool = false
var _clean_feed: bool = false
var _curtain_closed: bool = false
var _curtain_covering: bool = false
var _curtain_present: bool = false
var _curtain_owner: int = 0
var _show_dimmed: bool = false
var _room_has_webcam_frame: bool = false
var _room_has_reply_screen: bool = false


# ── Settings ─────────────────────────────────────────────────
static func _build_defaults() -> Dictionary:
	var d := BASE_DEFAULTS.duplicate(true)
	for n in range(1, PRESENTER_COUNT + 1):
		for f: String in PRESENTER_FIELDS.keys():
			d["presenter_%d_%s" % [n, f]] = PRESENTER_FIELDS[f]
	d["presenter_2_on"] = true     # two presenters (the inner podiums) on set by default
	d["presenter_3_on"] = true
	return d


## Shortcut for presenter settings: presenter(2, "source") -> "presenter_2_source".
static func presenter_key(n: int, field: String) -> String:
	return "presenter_%d_%s" % [n, field]


func get_setting(key: String) -> Variant:
	return _settings.get(key, DEFAULTS.get(key))


func set_setting(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Unknown setting: %s" % key)
		return
	if _settings.get(key) == value:
		return
	_settings[key] = value
	EventBus.setting_changed.emit(key, value)


func get_all_settings() -> Dictionary:
	return _settings.duplicate(true)


## Used by SaveManager. Unknown keys are ignored, missing keys keep defaults.
func apply_saved_settings(saved: Dictionary) -> void:
	for key in saved.keys():
		if DEFAULTS.has(key) and typeof(saved[key]) == typeof(DEFAULTS[key]):
			_settings[key] = saved[key]
	# older saves: "Use chat colours" off meant colours picked from names
	if saved.get("audience_platform_colors") == false and not saved.has("audience_color_by"):
		_settings["audience_color_by"] = "name"


# ── Source / playback ────────────────────────────────────────
func get_source_mode() -> String:
	return _source_mode


func set_source_mode(mode: String) -> void:
	if mode == _source_mode:
		return
	_source_mode = mode
	EventBus.source_changed.emit(mode)


func is_playback_active() -> bool:
	return _playback_active


func set_playback_active(active: bool) -> void:
	if active == _playback_active:
		return
	_playback_active = active
	EventBus.playback_active_changed.emit(active)


# ── Reaction features ────────────────────────────────────────
func is_react_paused() -> bool:
	return _react_paused


func toggle_react_pause() -> void:
	set_react_paused(not _react_paused)


func set_react_paused(paused: bool) -> void:
	if paused == _react_paused:
		return
	if paused and _source_mode == "none":
		EventBus.status_message.emit("Nothing is playing to pause.", false)
		return
	_react_paused = paused
	EventBus.react_pause_changed.emit(paused)


func is_focus_view() -> bool:
	return _focus_view


func toggle_focus_view() -> void:
	_focus_view = not _focus_view
	EventBus.focus_view_changed.emit(_focus_view)


func is_clean_feed() -> bool:
	return _clean_feed


# ── Stage curtain ────────────────────────────────────────────
func is_curtain_closed() -> bool:
	return _curtain_closed


## style: "normal" | "instant" | "reveal" (only for opening).
func set_curtain(closed: bool, style: String = "normal") -> void:
	if closed == _curtain_closed and style != "reveal":
		return
	if closed and not bool(get_setting("curtain_enabled")):
		EventBus.status_message.emit("The curtain is switched off (Room tab > Curtain).", false)
		return
	_curtain_closed = closed
	EventBus.curtain_changed.emit(closed, style)
	EventBus.status_message.emit("Curtain closed" if closed else "Curtain opening", false)
	if not _curtain_present:
		set_curtain_covering(closed)     # no curtain in this room: hide / show right away


## True while the curtain hides the screen: the stream sound mutes, focus view shows the
## curtain, and the screen's light on the room is swapped for a warm glow. The room's
## StageCurtain sets it (it stays true through a reveal's drum roll).
func is_curtain_covering() -> bool:
	return _curtain_covering


func set_curtain_covering(on: bool) -> void:
	if on == _curtain_covering:
		return
	_curtain_covering = on
	EventBus.curtain_covering_changed.emit(on)


## StageCurtain registers itself while its room is up. The old room is freed after the new
## one has registered, so only the curtain that registered last can unregister.
func set_curtain_present(owner: Object, on: bool) -> void:
	if on:
		_curtain_owner = owner.get_instance_id()
	elif owner.get_instance_id() != _curtain_owner:
		return
	_curtain_present = on
	if not on:
		set_curtain_covering(_curtain_closed)


func toggle_curtain() -> void:
	set_curtain(not _curtain_closed)


## The show: lights down, spotlight, drum roll, then the curtain opens. Closes it first if needed.
func reveal_curtain() -> void:
	set_curtain(false, "reveal")


## True during a curtain reveal: rooms dim their house lights.
func is_show_dimmed() -> bool:
	return _show_dimmed


func set_show_dimmed(on: bool) -> void:
	_show_dimmed = on


func toggle_clean_feed() -> void:
	_clean_feed = not _clean_feed
	EventBus.clean_feed_changed.emit(_clean_feed)


# ── Rooms ────────────────────────────────────────────────────
## Whether the loaded room has a WEBCAM_Frame marker (otherwise the webcam
## is shown as a corner overlay).
func room_has_webcam_frame() -> bool:
	return _room_has_webcam_frame


func set_room_has_webcam_frame(on: bool) -> void:
	_room_has_webcam_frame = on


## Whether the loaded room has a reply screen (REPLY_Screen marker). Chat windows set to show
## replies as a "fallback" show them when it hasn't, or when it's switched off.
func room_has_reply_screen() -> bool:
	return _room_has_reply_screen


func set_room_has_reply_screen(on: bool) -> void:
	if on != _room_has_reply_screen:
		_room_has_reply_screen = on
		EventBus.setting_changed.emit("reply_screen", get_setting("reply_screen"))   # windows re-check their fallback


func request_room(room_id: String) -> void:
	if RoomCatalog.get_info(room_id) == null:
		EventBus.status_message.emit("Unknown room: %s" % room_id, true)
		return
	set_setting("room_id", room_id)
	EventBus.room_requested.emit(room_id)


func cycle_room(step: int) -> void:
	var ids := RoomCatalog.get_ids()
	if ids.is_empty():
		return
	var i := ids.find(get_setting("room_id"))
	request_room(ids[posmod(i + step, ids.size())])
