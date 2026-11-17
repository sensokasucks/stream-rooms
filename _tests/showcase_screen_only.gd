extends Node
## Showcase reel for the Screen Only set (rooms/screen_only): not a test, a scripted tour that is
## recorded into a video file with Redot's movie writer. It plays a video clip on the big screen
## and steps through every Look, a few single effects, the extra screens and their layouts, and
## the "between videos" pictures, with a caption for each step.
##
## Run it on a PC with a real graphics card (Stream Rooms closed), from the project folder:
##   <redot console exe> --path . --resolution 1920x1080 --write-movie C:/temp/sr_showcase/reel.avi
##       --fixed-fps 30 _tests/showcase_screen_only.tscn -- "G:/clips/my_clip.ogv" --mp-profile=showcase
## then turn the big .avi into an .mp4:
##   tools\ffmpeg.exe -i reel.avi -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k reel.mp4
##
## User arguments (after "--"):
##   1st: the clip, an Ogg Theora .ogv (other files are converted first by VideoLoader, which needs
##        tools/ffmpeg.exe). It loops if the tour is longer than the clip.
##   glow=<0-1>: Glow (so_glow) for the baseline "clean" parts of the tour; default 0.
##   --mp-profile=<name>: keeps the owner's real settings.cfg untouched (as the tests do).
## Without --write-movie it just plays the tour in a window (handy for a quick look).
## The movie writer runs the game clock at a fixed step, so every wait below is in video seconds.
## Keep the Look names in step with PRESETS in rooms/screen_only/screen_only_room.gd: the tour
## reads the list from there, only the one-line descriptions (LOOK_NOTES) live here.

## One line under each Look's name. A Look missing here still shows, without the line.
const LOOK_NOTES: Dictionary = {
	"crt_tv": "Curved glass, scanlines, dot mask, glow, a rolling bar and a plastic frame",
	"arcade": "Heavy scanlines, stripe mask and rich colour",
	"pc_crt": "Fine scanlines, slot mask, a gentle curve",
	"amber": "Amber palette with dither, scanlines and glow",
	"vhs": "Tracking band, wobble, colour bleed and the PLAY and date text",
	"film": "Grain, dust and scratches, sepia and flicker",
	"cinema": "The picture bends like a wide cinema screen",
	"led": "A wall of LED dots",
	"holo": "See-through blue hologram with scan lines",
	"handheld": "Chunky pixels in a four-shade green palette",
	"night": "Green night-vision picture",
	"thermal": "Heat-camera colours",
	"comic": "Halftone print dots",
	"ascii": "The picture drawn out of letters",
}
## Seconds each Look stays on screen.
const LOOK_SECS: float = 4.0

var _title: Label            # big caption line
var _note: Label             # smaller line under it
var _box: PanelContainer     # dark box behind both
var _base_glow: float = 0.0  # so_glow for the baseline parts (argument glow=)
var _stills: Array[String] = []   # picture files grabbed from the clip for extra screens 2 and 3
var _effect_keys: PackedStringArray   # the set's EFFECT_KEYS (every setting a Look may change)
var _live_feed: Node         # ScreenFeed while extra screen 1 shows the clip (see _process), else null
var _live_wait: float = 0.0  # seconds until the clip's picture is handed to extra screen 1 again


## While the extra-screens part runs, extra screen 1 (source "tab", slot "so_extra_1") gets the
## clip's own picture, sent the way core/extra_feeds.gd would send a browser tab's. Sent again a
## few times a second, because the set asks for its feeds anew when a setting changes and no
## real tab is there to answer.
func _process(delta: float) -> void:
	if _live_feed == null:
		return
	_live_wait -= delta
	if _live_wait <= 0.0:
		_live_wait = 0.2
		EventBus.extra_feed_texture_changed.emit("so_extra_1", _live_feed.call("get_texture"))


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## Shows a caption (title, and a smaller line under it; "" hides that line).
func _say(title: String, note: String = "") -> void:
	_title.text = title
	_note.text = note
	_note.visible = note != ""
	_box.visible = title != ""


## Moves one float setting from a to b over secs, a little every frame (like dragging its slider).
func _sweep(key: String, a: float, b: float, secs: float) -> void:
	var t := 0.0
	while t < secs:
		AppState.set_setting(key, lerpf(a, b, smoothstep(0.0, 1.0, t / secs)))
		await get_tree().process_frame
		t += get_process_delta_time()
	AppState.set_setting(key, b)


## Back to the baseline: the Clean picture Look, plus the baseline Glow. Every effect setting is
## put back by hand as well: picking "clean" while the Look list already says "clean" changes
## nothing, so sliders moved since then would stay.
func _clean() -> void:
	AppState.set_setting("so_preset", "clean")
	for key: String in _effect_keys:
		AppState.set_setting(key, AppState.DEFAULTS[key])
	AppState.set_setting("so_glow", _base_glow)


## The caption box: bottom middle of the window, on a layer above everything the set draws.
func _build_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var holder := MarginContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_theme_constant_override("margin_bottom", 48)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	_box = PanelContainer.new()
	_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.size_flags_vertical = Control.SIZE_SHRINK_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.05, 0.82)
	style.set_corner_radius_all(14)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 16.0
	_box.add_theme_stylebox_override("panel", style)
	holder.add_child(_box)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	_box.add_child(lines)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 44)
	lines.add_child(_title)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 30)
	_note.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9))
	lines.add_child(_note)
	_box.visible = false


## Saves the clip's picture right now as a png in the user folder (for an extra screen with
## source "picture"). The effects are added by the shader afterwards, so this is the plain frame.
func _grab_still(feed: Node) -> void:
	var tex: Texture2D = feed.call("get_texture")
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	var path := OS.get_user_data_dir().path_join("so_showcase_still_%d.png" % (_stills.size() + 1))
	if img.save_png(path) == OK:
		_stills.append(path)


func _ready() -> void:
	var clip := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("glow="):
			_base_glow = clampf(a.trim_prefix("glow=").to_float(), 0.0, 1.0)
		elif not a.begins_with("--") and clip == "":
			clip = a
	if clip == "":
		print("FAIL no clip given: pass the video file as the first argument after --")
		AppState.request_quit(1)
		return

	# everything the tour depends on (it starts from a profile's settings, like a test)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", true)          # the panel in its own window, out of the picture
	AppState.set_setting("messages_on_picture", false)
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("loop_files", true)
	AppState.set_setting("so_fit", "fit")
	AppState.set_setting("so_bars", "black")
	AppState.set_setting("so_idle", "static")
	AppState.set_setting("so_extra_layout", "free")
	AppState.set_setting("so_extra_fx", true)
	AppState.set_setting("so_extra_frame", 0.25)
	for n in [1, 2, 3]:
		AppState.set_setting("so_extra_%d_source" % n, "off")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	_build_caption()
	await _secs(1.0)
	AppState.request_room("screen_only")
	await _secs(4.0)
	var room: Node = main.get_node("RoomHost").call("get_current_room")
	if room == null or room.get("PRESETS") == null:
		print("FAIL the Screen Only set did not load")
		AppState.request_quit(1)
		return
	_effect_keys = room.get("EFFECT_KEYS")
	_clean()

	# start the clip and wait until it is on screen (a file that isn't .ogv is converted first)
	var feed: Node = main.get_node("ScreenFeed")
	EventBus.file_play_requested.emit(clip)
	var waited := 0.0
	while AppState.get_source_mode() != "file" and waited < 600.0:
		await _secs(0.25)
		waited += 0.25
	if AppState.get_source_mode() != "file":
		print("FAIL the clip did not start: %s" % clip)
		AppState.request_quit(1)
		return
	print("PASS the clip plays")

	# ── 1. the set itself ──
	_say("Screen Only", "A flat set for Stream Rooms: the big screen fills the whole window")
	await _secs(2.5)
	_grab_still(feed)
	await _secs(2.5)

	# ── 2. every Look ──
	var presets: Dictionary = room.get("PRESETS")
	var count := presets.size() - 1
	var i := 0
	for id: String in presets:
		if id == "clean":
			continue
		i += 1
		AppState.set_setting("so_preset", id)
		_say("Look %d of %d: %s" % [i, count, String((presets[id] as Array)[0])], String(LOOK_NOTES.get(id, "")))
		await _secs(LOOK_SECS)
		if i == 7:
			_clean()                # a plain frame from later in the clip, for an extra screen
			await get_tree().process_frame
			_grab_still(feed)
	_clean()
	_say("Clean picture", "Every Look is a starting point: each effect has its own slider")
	await _secs(3.0)

	# ── 3. single effects, as if dragging the sliders ──
	_say("Curvature and Frame", "From flat to a bulging tube")
	AppState.set_setting("so_bezel", 0.6)
	AppState.set_setting("so_corner", 0.5)
	await _sweep("so_curve", 0.0, 1.0, 2.5)
	await _sweep("so_curve", 1.0, 0.0, 1.0)
	_clean()
	_say("Scanlines", "Strength and size")
	await _sweep("so_scanlines", 0.0, 0.9, 1.5)
	await _sweep("so_scan_px", 3.0, 8.0, 1.5)
	_clean()
	_say("LED wall dots", "From 60 to 300 LEDs across")
	AppState.set_setting("so_led", 1.0)
	for leds in range(60, 301, 4):
		AppState.set_setting("so_led_count", leds)
		await get_tree().process_frame
	await _secs(0.5)
	_clean()
	_say("Pixelate", "Chunky pixels")
	await _sweep("so_pixelate", 0.0, 0.7, 2.0)
	await _sweep("so_pixelate", 0.7, 0.15, 1.0)
	AppState.set_setting("so_dither", 0.5)
	for pal: Array in [["handheld", "Handheld green"], ["amber", "Amber"], ["green", "Green terminal"],
			["grey", "Greyscale"], ["retro4", "Four retro colours"]]:
		AppState.set_setting("so_palette", pal[0])
		_say("Colour palette: %s" % pal[1], "With dither and pixels")
		await _secs(1.4)
	_clean()
	for fun: Array in [["posterize", "Posterize"], ["invert", "Invert"]]:
		AppState.set_setting("so_fun", fun[0])
		_say("Fun look: %s" % fun[1])
		await _secs(1.6)
	_clean()
	_say("Colour, Brightness and Contrast", "From black and white to extra rich")
	await _sweep("so_saturation", 1.0, 0.0, 1.2)
	await _sweep("so_saturation", 0.0, 1.8, 1.6)
	await _sweep("so_saturation", 1.8, 1.0, 0.6)
	_say("Mix your own", "Here: VHS tape through a night-vision camera")
	AppState.set_setting("so_preset", "vhs")
	AppState.set_setting("so_fun", "night")
	await _secs(3.0)
	_clean()

	# ── 4. extra screens ──
	# Screen 1 gets the clip itself, handed over the way ExtraFeeds delivers a browser tab's
	# picture (see _process); 2 and 3 show the frames grabbed above as picture files.
	AppState.set_setting("so_extra_1_size", 0.26)
	AppState.set_setting("so_extra_1_x", 0.84)
	AppState.set_setting("so_extra_1_y", 0.8)
	AppState.set_setting("so_extra_1_source", "tab")
	_live_feed = feed
	_say("Extra screens", "Up to three more pictures: webcam, browser tab, NDI, Spout, a stream or a picture file")
	await _secs(2.5)
	for n in [2, 3]:
		if _stills.size() >= n - 1:
			AppState.set_setting("so_extra_%d_picture" % n, _stills[n - 2])
			AppState.set_setting("so_extra_%d_size" % n, 0.22)
			AppState.set_setting("so_extra_%d_x" % n, 0.14 if n == 2 else 0.86)
			AppState.set_setting("so_extra_%d_y" % n, 0.8 if n == 2 else 0.2)
			AppState.set_setting("so_extra_%d_source" % n, "picture")
			await _secs(1.2)
	_say("Layout: Insets", "Each one has its own size and place")
	await _sweep("so_extra_1_x", 0.84, 0.5, 1.2)
	await _sweep("so_extra_1_size", 0.26, 0.42, 1.0)
	await _sweep("so_extra_1_size", 0.42, 0.26, 0.8)
	await _sweep("so_extra_1_x", 0.5, 0.84, 1.0)
	AppState.set_setting("so_extra_layout", "side")
	_say("Layout: Column on the right", "The main picture moves over")
	await _secs(2.5)
	AppState.set_setting("so_bars", "glow")
	_say("Bars: Glow from the picture", "The empty space picks up the picture's colours")
	await _secs(2.5)
	AppState.set_setting("so_fit", "fill")
	_say("Fit: Fill", "Or crop the picture to fill its space")
	await _secs(2.0)
	AppState.set_setting("so_fit", "fit")
	AppState.set_setting("so_extra_layout", "grid")
	_say("Layout: Two by two", "Four quarters")
	await _secs(2.5)
	AppState.set_setting("so_preset", "crt_tv")
	_say("Extra screens get the Look too", "A wall of old TVs")
	await _secs(3.0)
	AppState.set_setting("so_preset", "led")
	await _secs(2.0)
	AppState.set_setting("so_extra_fx", false)
	_say("... or stay clean", "Only the main picture keeps the Look")
	await _secs(2.5)
	AppState.set_setting("so_extra_fx", true)
	_clean()
	_live_feed = null
	for n in [1, 2, 3]:
		AppState.set_setting("so_extra_%d_source" % n, "off")
	AppState.set_setting("so_extra_layout", "free")
	AppState.set_setting("so_bars", "black")
	await _secs(1.0)

	# ── 5. between videos ──
	EventBus.file_stop_requested.emit()
	AppState.set_setting("so_preset", "crt_tv")
	_say("Between videos: Static", "What the set shows while nothing plays")
	await _secs(2.5)
	AppState.set_setting("so_idle", "bars")
	_say("Between videos: Colour bars")
	await _secs(2.0)
	AppState.set_setting("so_idle", "standby")
	_say("Between videos: Please stand by", "With your own text")
	await _secs(2.5)

	# leave the profile tidy, then quit (request_quit fades the picture out first)
	_say("")
	_clean()
	AppState.set_setting("so_idle", "static")
	AppState.set_setting("room_id", "lecture_hall_panel")
	for path in _stills:
		DirAccess.remove_absolute(path)
	print("DONE fails=0")
	AppState.request_quit(0)
