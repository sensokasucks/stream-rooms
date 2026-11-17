extends Room
## Screen Only set: no 3D room, no audience, nothing else. The big screen's picture (video, browser
## tab, NDI, Spout) fills the whole Stream Rooms window, with a stack of picture effects on top:
## CRT glass, scanlines and phosphor masks, the rooms' LED / hologram / bend looks, VHS tape, old
## film, retro palettes and a few fun ones (screen_fx.gdshader does the drawing).
##
## How it fits in:
##   - RoomCatalog lists it like any room (room_info.tres, flat_screen = true). RoomHost loads it,
##     but skips the curtain / stand-by card and the side chat windows for a flat set.
##   - The scene keeps a tiny hidden TVScreen and one CAM_ marker only so RoomHost and CameraRig
##     find what every room has; the 3D world behind is empty and black, so it costs next to nothing.
##   - The picture is drawn on a CanvasLayer at layer -1: above the 3D world, below every other
##     2D layer (chat HUD, focus view, overlay, the control panel), so those still show on top.
##   - Settings are the so_* keys in AppState.DEFAULTS. get_controls() puts them on the Room tab;
##     the control panel's settings_schema() then hands them to Stream Core's Stream Rooms pages.
##   - Picking a Look (so_preset) writes a whole set of effect values (PRESETS below); every slider
##     can still be moved afterwards.
##   - Resizing the window: the ColorRect fills the window, and _process() hands its current size to
##     the shader every frame, so curvature, fit and bezel follow; pixel-sized effects use real
##     window pixels (see the shader's header).
##   - Flicker, rolling bar and moving static respect flash_strength and photosensitive_safe.
##   - Extra screens: up to EXTRA_COUNT smaller pictures in the same window, each with a source
##     of its own (so_extra_n_source: webcam, a picture file, or a feed from core/extra_feeds.gd:
##     browser tab, NDI, Spout, stream address), like the Forge Hall's small live screens. Each is
##     one more ColorRect with its own copy of the effect shader; _layout() places them (and the
##     main picture) from so_extra_layout every frame. Each PC's own: not sent to co-stream guests.

const FX_SHADER: Shader = preload("res://rooms/screen_only/screen_fx.gdshader")

## Effect settings a Look sets. Keys missing from a preset go back to their AppState default, so
## each Look starts from a clean picture. (Fit, bars and "between videos" are never touched.)
const EFFECT_KEYS: PackedStringArray = ["so_curve", "so_corner", "so_scanlines", "so_scan_px", "so_mask",
	"so_mask_type", "so_glow", "so_vignette", "so_fringe", "so_flicker", "so_roll", "so_bezel", "so_led",
	"so_led_count", "so_holo", "so_bend", "so_vhs", "so_bleed", "so_stamp", "so_grain", "so_scratches",
	"so_sepia", "so_pixelate", "so_palette", "so_dither", "so_fun", "so_fun_amount", "so_saturation",
	"so_brightness", "so_contrast"]

## The Look list: id -> [label, {setting: value}]. Values must match the default's type (float / int /
## String / bool), or AppState ignores them when the settings are loaded again.
const PRESETS: Dictionary = {
	"clean": ["Clean picture", {}],
	"crt_tv": ["Old CRT TV", {"so_curve": 0.6, "so_corner": 0.6, "so_scanlines": 0.55, "so_scan_px": 3.0,
		"so_mask": 0.35, "so_mask_type": "shadow", "so_glow": 0.35, "so_vignette": 0.5, "so_fringe": 0.25,
		"so_flicker": 0.15, "so_roll": 0.25, "so_bezel": 0.7}],
	"arcade": ["Arcade monitor", {"so_curve": 0.35, "so_corner": 0.3, "so_scanlines": 0.75, "so_scan_px": 4.0,
		"so_mask": 0.5, "so_mask_type": "grille", "so_glow": 0.5, "so_vignette": 0.3, "so_fringe": 0.15,
		"so_bezel": 0.5, "so_saturation": 1.2}],
	"pc_crt": ["Computer monitor", {"so_curve": 0.2, "so_corner": 0.35, "so_scanlines": 0.3, "so_scan_px": 2.0,
		"so_mask": 0.3, "so_mask_type": "slot", "so_glow": 0.2, "so_vignette": 0.2, "so_bezel": 0.6}],
	"amber": ["Amber terminal", {"so_palette": "amber", "so_dither": 0.3, "so_scanlines": 0.6, "so_scan_px": 3.0,
		"so_curve": 0.3, "so_corner": 0.4, "so_glow": 0.5, "so_vignette": 0.4, "so_bezel": 0.5}],
	"vhs": ["VHS tape", {"so_vhs": 0.7, "so_bleed": 0.7, "so_stamp": true, "so_grain": 0.15, "so_saturation": 0.85,
		"so_vignette": 0.2, "so_curve": 0.15, "so_scanlines": 0.2, "so_scan_px": 3.0}],
	"film": ["Old film", {"so_grain": 0.6, "so_scratches": 0.7, "so_sepia": 0.7, "so_vignette": 0.6,
		"so_flicker": 0.35, "so_contrast": 1.1}],
	"cinema": ["Curved cinema screen", {"so_bend": 0.6, "so_vignette": 0.35, "so_glow": 0.15}],
	"led": ["LED wall", {"so_led": 1.0, "so_led_count": 160, "so_glow": 0.3, "so_saturation": 1.15}],
	"holo": ["Hologram", {"so_holo": 0.8, "so_scanlines": 0.3, "so_scan_px": 3.0, "so_glow": 0.4, "so_fringe": 0.3}],
	"handheld": ["Handheld game", {"so_pixelate": 0.25, "so_palette": "handheld", "so_dither": 0.6, "so_corner": 0.2,
		"so_bezel": 0.4}],
	"night": ["Night vision", {"so_fun": "night", "so_fun_amount": 1.0}],
	"thermal": ["Thermal camera", {"so_fun": "thermal", "so_fun_amount": 1.0}],
	"comic": ["Comic book", {"so_fun": "halftone", "so_fun_amount": 1.0, "so_saturation": 1.3}],
	"ascii": ["Text mode (ASCII)", {"so_fun": "ascii", "so_fun_amount": 1.0}],
}

## Dropdown values -> the shader's int uniforms (keep in step with screen_fx.gdshader).
const FIT_MODES: Dictionary = {"fit": 0, "fill": 1, "stretch": 2}
const BAR_MODES: Dictionary = {"black": 0, "color": 1, "glow": 2}
const IDLE_MODES: Dictionary = {"static": 0, "bars": 1, "black": 2, "standby": 3}
const MASK_TYPES: Dictionary = {"grille": 0, "shadow": 1, "slot": 2}
const PALETTES: Dictionary = {"none": 0, "handheld": 1, "amber": 2, "green": 3, "grey": 4, "retro4": 5}
const FUN_MODES: Dictionary = {"none": 0, "night": 1, "thermal": 2, "halftone": 3, "ascii": 4, "posterize": 5, "invert": 6}

## How many extra screens there are (settings so_extra_1.. so_extra_3). ExtraFeeds slots are
## "so_extra_n"; a browser-tab one shows on the sender page as EXTRA_NAMES[n - 1].
const EXTRA_COUNT: int = 3
const EXTRA_NAMES: PackedStringArray = ["Extra screen 1", "Extra screen 2", "Extra screen 3"]
## Extra-screen sources that are a feed fetched by ExtraFeeds (core/extra_feeds.gd).
const OWN_FEEDS: Array[String] = ["ndi", "spout", "stream", "tab"]
## Share of the window's width the extra screens' column takes in the "side" layout.
const SIDE_SHARE: float = 0.25
## Thickest outline round an extra screen (so_extra_frame = 1), in window pixels.
const FRAME_PX: float = 8.0

var _layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _standby: Label            # stand-by text over the "standby" between-videos picture
var _stamp_play: Label         # tape PLAY text (so_stamp), top left
var _stamp_date: Label         # tape date text (so_stamp), bottom left
var _texture: Texture2D        # the big screen's picture (EventBus.screen_texture_changed)
var _applying_preset: bool = false
var _stamp_wait: float = 0.0   # seconds until the date stamp's clock is redrawn
## The extra screens, index n - 1: {"n", "back" (ColorRect outline behind), "rect" (ColorRect
## with the shader), "mat" (its ShaderMaterial), "tex" (the picture now, or null),
## "file" (ImageTexture loaded for source "picture"), "file_path" (what "file" was loaded from)}.
var _extras: Array[Dictionary] = []
var _webcam: Texture2D         # the sender page's webcam (EventBus.webcam_texture_changed)
var _retired: bool = false     # another room took over (retire()): stop asking for feeds


func _ready() -> void:
	super._ready()
	_build_layer()
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.screen_texture_changed.connect(_on_screen_texture)
	EventBus.webcam_texture_changed.connect(_on_webcam_texture)
	EventBus.extra_feed_texture_changed.connect(_on_extra_texture)
	EventBus.room_changed.connect(_on_so_room_changed)
	_apply_all()
	_request_feeds.call_deferred()
	# ask ScreenFeed for the picture it already has (a video playing before the room switch)
	EventBus.feed_textures_requested.emit()


## The room is freed on a room swap: drop the EventBus connections with it.
func _exit_tree() -> void:
	EventBus.setting_changed.disconnect(_on_setting_changed)
	EventBus.screen_texture_changed.disconnect(_on_screen_texture)
	EventBus.webcam_texture_changed.disconnect(_on_webcam_texture)
	EventBus.extra_feed_texture_changed.disconnect(_on_extra_texture)
	EventBus.room_changed.disconnect(_on_so_room_changed)


## RoomHost._retire calls this (propagate_call) when another room takes over; this one is freed
## a little later.
func retire() -> void:
	_retired = true


## Every frame: the window's size (resizing), the picture's size (a tab can change size) and
## whether there is a picture to show at all (no source, or the curtain closed -> between videos).
func _process(delta: float) -> void:
	super._process(delta)
	if _mat == null:
		return
	_layout()
	var size := _rect.size
	_mat.set_shader_parameter("rect_px", Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0)))
	var showing := _texture != null and AppState.get_source_mode() != "none" and not AppState.is_curtain_covering()
	if showing:
		var ts := _texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			_mat.set_shader_parameter("video_size", ts)
	_mat.set_shader_parameter("has_video", showing)
	_standby.visible = not showing and String(AppState.get_setting("so_idle")) == "standby"
	# text sizes follow the window height, so they stay in proportion while resizing
	var h := maxf(size.y, 200.0)
	_standby.add_theme_font_size_override("font_size", int(h * 0.06))
	if _stamp_play.visible:
		_stamp_play.add_theme_font_size_override("font_size", int(h * 0.045))
		_stamp_date.add_theme_font_size_override("font_size", int(h * 0.04))
		_stamp_wait -= delta
		if _stamp_wait <= 0.0:
			_stamp_wait = 1.0
			_stamp_date.text = _stamp_text()


## Builds the full-window picture: CanvasLayer -1 > ColorRect with the effect shader, plus the
## stand-by and tape stamp labels on top of it.
func _build_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ScreenOnlyLayer"
	_layer.layer = -1
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.name = "Picture"
	# placed by _layout() every frame (the whole window, or its share in a split layout)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.BLACK
	_mat = ShaderMaterial.new()
	_mat.shader = FX_SHADER
	_rect.material = _mat
	# a black sheet behind everything, so a split layout's gaps are black, not the empty 3D world
	var floor_rect := ColorRect.new()
	floor_rect.name = "Backdrop"
	floor_rect.color = Color.BLACK
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(floor_rect)
	floor_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_rect)
	# the extra screens sit above the main picture and below the labels
	for n in range(1, EXTRA_COUNT + 1):
		var back := ColorRect.new()
		back.name = "Extra%dFrame" % n
		back.color = Color(0.02, 0.02, 0.025)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.visible = false
		_layer.add_child(back)
		var r := ColorRect.new()
		r.name = "Extra%d" % n
		r.color = Color.BLACK
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.visible = false
		var m := ShaderMaterial.new()
		m.shader = FX_SHADER
		r.material = m
		_layer.add_child(r)
		_extras.append({"n": n, "back": back, "rect": r, "mat": m, "tex": null, "file": null, "file_path": ""})

	# full-window labels (anchors AND offsets, so they stretch with the window), aligned inside
	_standby = _make_label(HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	_stamp_play = _make_label(HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	_stamp_play.text = "PLAY ▶"
	_stamp_date = _make_label(HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_BOTTOM)


## Where everything sits, in window pixels. Run every frame from _process (a handful of rects,
## so it costs nothing), which is what makes the set follow a window being resized.
## so_extra_layout:
##   "free"  the main picture fills the window; each extra screen is an inset at its own
##           so_extra_n_x / _y (its centre, 0-1 across / down the window) and _size (its width
##           as a share of the window's), in the shape of its own picture
##   "side"  the main picture takes the left of the window; the extra screens that are on are
##           stacked in a column on the right (SIDE_SHARE of the width)
##   "grid"  two by two: the main picture top left, the extra screens in the other cells
func _layout() -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	var mode := String(AppState.get_setting("so_extra_layout"))
	var on: Array[Dictionary] = []
	for e in _extras:
		if String(AppState.get_setting("so_extra_%d_source" % int(e["n"]))) != "off":
			on.append(e)
	var main := Rect2(Vector2.ZERO, win)
	if on.is_empty():
		mode = "free"
	var frame := float(AppState.get_setting("so_extra_frame")) * FRAME_PX
	match mode:
		"side":
			var col_w := floorf(win.x * SIDE_SHARE)
			main = Rect2(0.0, 0.0, win.x - col_w, win.y)
			var cell_h := win.y / float(on.size())
			for i in on.size():
				_place_extra(on[i], Rect2(win.x - col_w, cell_h * i, col_w, cell_h).grow(-frame), frame)
		"grid":
			var half := win * 0.5
			main = Rect2(Vector2.ZERO, half)
			var cells: Array[Vector2] = [Vector2(half.x, 0.0), Vector2(0.0, half.y), half]
			for i in on.size():
				_place_extra(on[i], Rect2(cells[i], half).grow(-frame), frame)
		_:
			for e in on:
				var n := int(e["n"])
				var w := clampf(float(AppState.get_setting("so_extra_%d_size" % n)), 0.05, 1.0) * win.x
				var shape := 16.0 / 9.0
				var tex: Texture2D = e["tex"]
				if tex != null and tex.get_height() > 0:
					shape = float(tex.get_width()) / float(tex.get_height())
				var box := Vector2(w, w / shape)
				if box.y > win.y:              # a tall picture: never taller than the window
					box *= win.y / box.y
				var centre := Vector2(float(AppState.get_setting("so_extra_%d_x" % n)), float(AppState.get_setting("so_extra_%d_y" % n))) * win
				var pos := (centre - box * 0.5).clamp(Vector2.ZERO, (win - box).max(Vector2.ZERO))
				_place_extra(e, Rect2(pos, box), frame)
	for e in _extras:
		if not on.has(e):
			(e["rect"] as ColorRect).visible = false
			(e["back"] as ColorRect).visible = false
	_rect.position = main.position
	_rect.size = main.size
	# the labels sit over the main picture, the tape stamps a little in from its corners
	_standby.position = main.position
	_standby.size = main.size
	var inset := Vector2(40.0, 30.0)
	for l: Label in [_stamp_play, _stamp_date]:
		l.position = main.position + inset
		l.size = (main.size - inset * 2.0).max(Vector2.ONE)


## Puts one extra screen (and its outline, `frame` pixels wider all round) at `box`, and tells
## its shader the box's size and whether it has a picture.
func _place_extra(e: Dictionary, box: Rect2, frame: float) -> void:
	var r: ColorRect = e["rect"]
	var back: ColorRect = e["back"]
	var m: ShaderMaterial = e["mat"]
	box.size = box.size.max(Vector2.ONE)
	r.position = box.position
	r.size = box.size
	r.visible = true
	back.position = box.position - Vector2(frame, frame)
	back.size = box.size + Vector2(frame, frame) * 2.0
	back.visible = frame > 0.0
	m.set_shader_parameter("rect_px", box.size)
	var tex: Texture2D = e["tex"]
	var showing := tex != null and tex.get_width() > 0 and tex.get_height() > 0
	if showing:
		m.set_shader_parameter("video_size", tex.get_size())
	m.set_shader_parameter("has_video", showing)


func _make_label(h: HorizontalAlignment, v: VerticalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = h
	l.vertical_alignment = v
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.visible = false
	_layer.add_child(l)
	return l       # placed over the main picture by _layout()


## "NOV 14 2026  3:26 PM": the tape date stamp (this PC's clock).
func _stamp_text() -> String:
	var t := Time.get_datetime_dict_from_system()
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	var hour := int(t["hour"])
	var ampm := "AM" if hour < 12 else "PM"
	hour = hour % 12
	if hour == 0:
		hour = 12
	return "%s %d %d  %d:%02d %s" % [months[int(t["month"]) - 1], int(t["day"]), int(t["year"]), hour, int(t["minute"]), ampm]


func _on_screen_texture(tex: Texture2D) -> void:
	_texture = tex
	if _mat:
		_mat.set_shader_parameter("video", tex)


func _on_webcam_texture(tex: Texture2D) -> void:
	_webcam = tex
	_refresh_extras()


## ExtraFeeds' picture for one of this set's slots ("so_extra_n"): a tab, NDI, Spout or stream.
func _on_extra_texture(slot: String, tex: Texture2D) -> void:
	for e in _extras:
		if slot == "so_extra_%d" % int(e["n"]) and String(AppState.get_setting("so_extra_%d_source" % int(e["n"]))) in OWN_FEEDS:
			_set_extra_texture(e, tex)


## EventBus.room_changed: ExtraFeeds stops every feed nobody asks for again shortly after a
## room change, so ask again a frame later (unless this set is the one that just left).
func _on_so_room_changed(_room_id: String) -> void:
	if not _retired:
		_request_feeds.call_deferred()


## Asks ExtraFeeds (through EventBus.extra_feed_requested) for each extra screen's own feed:
## slot "so_extra_n", kind = its source when that is one of OWN_FEEDS, address =
## so_extra_n_address (for a browser tab: the screen's name, shown on the sender page). Any
## other source stops the slot. Called at start, after a room change and when a so_extra_
## setting changes.
func _request_feeds() -> void:
	if _retired or not is_inside_tree():
		return
	for e in _extras:
		var n := int(e["n"])
		var src := String(AppState.get_setting("so_extra_%d_source" % n))
		var own := src in OWN_FEEDS
		var address := EXTRA_NAMES[n - 1] if src == "tab" else String(AppState.get_setting("so_extra_%d_address" % n))
		EventBus.extra_feed_requested.emit("so_extra_%d" % n, src if own else "", address if own else "")
	_refresh_extras()


## Gives every extra screen the picture its source asks for, for the sources this script holds
## itself (webcam, picture file). ExtraFeeds' ones arrive through _on_extra_texture; switching
## to one of those starts from "no picture yet".
func _refresh_extras() -> void:
	for e in _extras:
		var n := int(e["n"])
		match String(AppState.get_setting("so_extra_%d_source" % n)):
			"webcam":
				_set_extra_texture(e, _webcam)
			"picture":
				_set_extra_texture(e, _picture_for(e))
			"off":
				_set_extra_texture(e, null)


func _set_extra_texture(e: Dictionary, tex: Texture2D) -> void:
	e["tex"] = tex
	(e["mat"] as ShaderMaterial).set_shader_parameter("video", tex)


## The picture file of an extra screen (so_extra_n_picture: png, jpg or webp), loaded once per
## path. A missing or unreadable file gives null (the screen shows "between videos").
func _picture_for(e: Dictionary) -> Texture2D:
	var path := String(AppState.get_setting("so_extra_%d_picture" % int(e["n"]))).strip_edges()
	if path == String(e["file_path"]):
		return e["file"]
	e["file_path"] = path
	e["file"] = null
	if path != "" and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			if img.get_width() > 2560:       # a huge photo: no point keeping more than the window shows
				img.resize(2560, int(2560.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
			e["file"] = ImageTexture.create_from_image(img)
	return e["file"]


## EventBus.setting_changed: a Look writes its whole set; any so_* key or the safety settings
## re-send the uniforms.
func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "so_preset" and not _applying_preset:
		apply_preset(String(AppState.get_setting("so_preset")))
		return
	if key.begins_with("so_extra_"):
		# a source, address or picture changed: (re)ask for feeds; _request_feeds ignores the rest cheaply
		if key.ends_with("_source") or key.ends_with("_address") or key.ends_with("_picture"):
			if key.ends_with("_source"):
				for e in _extras:
					if key == "so_extra_%d_source" % int(e["n"]):
						_set_extra_texture(e, null)
			_request_feeds()
	if key.begins_with("so_") or key in ["photosensitive_safe", "flash_strength", "curtain_sign"]:
		_apply_all()


## Writes a Look's values (and the defaults for every effect it doesn't name) into the settings.
## Also used by the test. Unknown ids are ignored.
func apply_preset(id: String) -> void:
	if not PRESETS.has(id):
		return
	var values: Dictionary = (PRESETS[id] as Array)[1]
	_applying_preset = true
	for key in EFFECT_KEYS:
		AppState.set_setting(key, values.get(key, AppState.DEFAULTS[key]))
	_applying_preset = false
	_apply_all()


## All so_* settings -> shader uniforms and label visibility.
func _apply_all() -> void:
	if _mat == null:
		return
	_apply_to(_mat, true, int(FIT_MODES.get(String(AppState.get_setting("so_fit")), 0)))
	# the extra screens: the same Look when "Extra screens get the Look too" is on, else a clean
	# picture; always shown whole (fit) in their box
	var extras_fx := bool(AppState.get_setting("so_extra_fx"))
	for e in _extras:
		_apply_to(e["mat"], extras_fx, 0)
	var sign_text := String(AppState.get_setting("curtain_sign")).strip_edges()
	_standby.text = sign_text if sign_text != "" else "Please stand by"
	var stamp := bool(AppState.get_setting("so_stamp"))
	_stamp_play.visible = stamp
	_stamp_date.visible = stamp
	_stamp_wait = 0.0


## The so_* settings -> one material's uniforms. effects = false leaves every effect at its
## AppState default (a clean picture) and only sets fit, bars and the between-videos picture.
func _apply_to(mat: ShaderMaterial, effects: bool, fit: int) -> void:
	var s := func(key: String) -> Variant: return AppState.get_setting(key) if effects else AppState.DEFAULTS[key]
	var f := func(key: String) -> float: return float(s.call(key))
	mat.set_shader_parameter("fit_mode", fit)
	mat.set_shader_parameter("bars_mode", int(BAR_MODES.get(String(AppState.get_setting("so_bars")), 0)))
	mat.set_shader_parameter("bar_color", AppState.get_setting("so_bar_color"))
	mat.set_shader_parameter("idle_mode", int(IDLE_MODES.get(String(AppState.get_setting("so_idle")), 0)))
	mat.set_shader_parameter("mask_type", int(MASK_TYPES.get(String(s.call("so_mask_type")), 0)))
	mat.set_shader_parameter("palette", int(PALETTES.get(String(s.call("so_palette")), 0)))
	mat.set_shader_parameter("fun_mode", int(FUN_MODES.get(String(s.call("so_fun")), 0)))
	for pair: Array in [["curve", "so_curve"], ["corner", "so_corner"], ["scanlines", "so_scanlines"],
			["scan_px", "so_scan_px"], ["mask", "so_mask"], ["glow", "so_glow"], ["vignette", "so_vignette"],
			["fringe", "so_fringe"], ["bezel", "so_bezel"], ["led", "so_led"], ["led_count", "so_led_count"],
			["holo", "so_holo"], ["bend", "so_bend"], ["vhs", "so_vhs"], ["bleed", "so_bleed"], ["grain", "so_grain"],
			["scratches", "so_scratches"], ["sepia", "so_sepia"], ["pixelate", "so_pixelate"], ["dither", "so_dither"],
			["fun", "so_fun_amount"], ["saturation", "so_saturation"], ["brightness", "so_brightness"],
			["contrast", "so_contrast"]]:
		mat.set_shader_parameter(pair[0], f.call(pair[1]))
	# flashing parts: scaled by Flash strength, and cut to a quarter (with slower motion) in safe mode
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	var flash := clampf(float(AppState.get_setting("flash_strength")), 0.0, 1.0) * (0.25 if safe else 1.0)
	mat.set_shader_parameter("flicker", f.call("so_flicker") * flash)
	mat.set_shader_parameter("roll", f.call("so_roll") * flash)
	mat.set_shader_parameter("motion_scale", 0.35 if safe else 1.0)


## Room tab > Screen Only (and Core's Stream Rooms settings, through the panel's schema).
func get_controls() -> Array[Dictionary]:
	var looks: Array = []
	for id: String in PRESETS:
		looks.append([id, String((PRESETS[id] as Array)[0])])
	var pct := func(key: String, label: String, tip: String) -> Dictionary:
		return {"key": key, "label": label, "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0, "tooltip": tip}
	return [
		{"heading": "Screen Only"},
		{"key": "so_preset", "label": "Look", "type": "option", "options": looks,
			"tooltip": "A ready-made look. Picking one sets all the effect sliders below; you can move any of them afterwards."},
		{"key": "so_fit", "label": "Fit", "type": "option",
			"options": [["fit", "Whole picture (bars)"], ["fill", "Fill the window (crop)"], ["stretch", "Stretch"]],
			"tooltip": "How the picture fits the window when their shapes differ. Resize the window and it re-fits."},
		{"key": "so_bars", "label": "Bars", "type": "option",
			"options": [["black", "Black"], ["color", "A colour"], ["glow", "Glow from the picture"]],
			"tooltip": "What fills the space beside the picture when Fit shows bars."},
		{"key": "so_bar_color", "label": "Bar colour", "type": "color",
			"tooltip": "The bars' colour when Bars is set to A colour."},
		{"key": "so_idle", "label": "Between videos", "type": "option",
			"options": [["static", "Static snow"], ["bars", "Colour bars"], ["black", "Black"], ["standby", "Please stand by"]],
			"tooltip": "What shows while nothing plays, and while the curtain is closed (B). Please stand by uses the curtain sign text if you set one."},
		{"heading": "Extra screens"},
		{"key": "so_extra_layout", "label": "Layout", "type": "option",
			"options": [["free", "Insets over the picture"], ["side", "Column on the right"], ["grid", "Two by two"]],
			"tooltip": "Where the extra screens go. Insets: small pictures over the main one, placed with their own sliders. Column on the right: the main picture moves left and the extra screens stack beside it. Two by two: four equal quarters. Only screens that are switched on take up room."},
		{"key": "so_extra_fx", "label": "Extra screens get the Look too", "type": "check",
			"tooltip": "Ticked: the extra screens wear the same effects as the main picture (each its own little CRT). Unticked: they stay a clean picture."},
		{"key": "so_extra_frame", "label": "Outline", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "A dark outline round each extra screen. 0% = none."},
		{"key": "so_extra_1_source", "label": "Extra screen 1", "type": "option",
			"options": [["off", "Off"], ["webcam", "Webcam"], ["picture", "Picture file"], ["tab", "Browser tab or window (pick it in the sender)"],
				["ndi", "NDI source (name below)"], ["spout", "Spout sender (name below)"], ["stream", "Stream address (below)"]],
			"tooltip": "What this extra screen shows. Webcam = the webcam from the sender page. Browser tab or window: a row called Extra screen 1 appears under Extra screens on the sender page (Share to Stream Rooms in Stream Core); click its Pick a tab or window button there. NDI source, Spout sender and Stream address use the name or address in the box below. Picture only, no sound. Extra screens are this PC's own: co-stream guests don't get them."},
		{"key": "so_extra_1_address", "label": "Extra screen 1 address", "type": "text",
			"placeholder": "NDI or Spout name, or rtmp:// rtsp:// address",
			"pick_feeds": "so_extra_1_source", "hide_login": true,
			"tooltip": "Pick lists the NDI sources and Spout senders found right now; choosing one fills this box and switches the screen to it. Or type it: the source's name or just part of it, or for Stream address an rtmp://, rtsp://, srt:// or http stream address or a video file (it loops; needs ffmpeg in the tools folder). Put listen: in front to wait for a camera or phone app to connect to this PC. An address with a login in it shows as dots until you click into the box. Press Enter to apply."},
		{"key": "so_extra_1_picture", "label": "Extra screen 1 picture", "type": "picture",
			"placeholder": "used when it shows Picture file",
			"tooltip": "The picture this extra screen shows when it is set to Picture file. PNG, JPG or WebP."},
		{"key": "so_extra_1_size", "label": "Extra screen 1: size", "min": 0.05, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How wide this inset is, as a share of the window's width. Used by the Insets layout."},
		{"key": "so_extra_1_x", "label": "Extra screen 1: left/right", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Where this inset's middle sits across the window: 0% = left edge, 100% = right edge. It never leaves the window. Used by the Insets layout."},
		{"key": "so_extra_1_y", "label": "Extra screen 1: up/down", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Where this inset's middle sits down the window: 0% = top, 100% = bottom. Used by the Insets layout."},
		{"key": "so_extra_2_source", "label": "Extra screen 2", "type": "option",
			"options": [["off", "Off"], ["webcam", "Webcam"], ["picture", "Picture file"], ["tab", "Browser tab or window (pick it in the sender)"],
				["ndi", "NDI source (name below)"], ["spout", "Spout sender (name below)"], ["stream", "Stream address (below)"]],
			"tooltip": "What this extra screen shows. Webcam = the webcam from the sender page. Browser tab or window: a row called Extra screen 2 appears under Extra screens on the sender page (Share to Stream Rooms in Stream Core); click its Pick a tab or window button there. NDI source, Spout sender and Stream address use the name or address in the box below. Picture only, no sound. Extra screens are this PC's own: co-stream guests don't get them."},
		{"key": "so_extra_2_address", "label": "Extra screen 2 address", "type": "text",
			"placeholder": "NDI or Spout name, or rtmp:// rtsp:// address",
			"pick_feeds": "so_extra_2_source", "hide_login": true,
			"tooltip": "Pick lists the NDI sources and Spout senders found right now; choosing one fills this box and switches the screen to it. Or type it: the source's name or just part of it, or for Stream address an rtmp://, rtsp://, srt:// or http stream address or a video file (it loops; needs ffmpeg in the tools folder). Put listen: in front to wait for a camera or phone app to connect to this PC. An address with a login in it shows as dots until you click into the box. Press Enter to apply."},
		{"key": "so_extra_2_picture", "label": "Extra screen 2 picture", "type": "picture",
			"placeholder": "used when it shows Picture file",
			"tooltip": "The picture this extra screen shows when it is set to Picture file. PNG, JPG or WebP."},
		{"key": "so_extra_2_size", "label": "Extra screen 2: size", "min": 0.05, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How wide this inset is, as a share of the window's width. Used by the Insets layout."},
		{"key": "so_extra_2_x", "label": "Extra screen 2: left/right", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Where this inset's middle sits across the window: 0% = left edge, 100% = right edge. It never leaves the window. Used by the Insets layout."},
		{"key": "so_extra_2_y", "label": "Extra screen 2: up/down", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Where this inset's middle sits down the window: 0% = top, 100% = bottom. Used by the Insets layout."},
		{"key": "so_extra_3_source", "label": "Extra screen 3", "type": "option",
			"options": [["off", "Off"], ["webcam", "Webcam"], ["picture", "Picture file"], ["tab", "Browser tab or window (pick it in the sender)"],
				["ndi", "NDI source (name below)"], ["spout", "Spout sender (name below)"], ["stream", "Stream address (below)"]],
			"tooltip": "What this extra screen shows. Webcam = the webcam from the sender page. Browser tab or window: a row called Extra screen 3 appears under Extra screens on the sender page (Share to Stream Rooms in Stream Core); click its Pick a tab or window button there. NDI source, Spout sender and Stream address use the name or address in the box below. Picture only, no sound. Extra screens are this PC's own: co-stream guests don't get them."},
		{"key": "so_extra_3_address", "label": "Extra screen 3 address", "type": "text",
			"placeholder": "NDI or Spout name, or rtmp:// rtsp:// address",
			"pick_feeds": "so_extra_3_source", "hide_login": true,
			"tooltip": "Pick lists the NDI sources and Spout senders found right now; choosing one fills this box and switches the screen to it. Or type it: the source's name or just part of it, or for Stream address an rtmp://, rtsp://, srt:// or http stream address or a video file (it loops; needs ffmpeg in the tools folder). Put listen: in front to wait for a camera or phone app to connect to this PC. An address with a login in it shows as dots until you click into the box. Press Enter to apply."},
		{"key": "so_extra_3_picture", "label": "Extra screen 3 picture", "type": "picture",
			"placeholder": "used when it shows Picture file",
			"tooltip": "The picture this extra screen shows when it is set to Picture file. PNG, JPG or WebP."},
		{"key": "so_extra_3_size", "label": "Extra screen 3: size", "min": 0.05, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How wide this inset is, as a share of the window's width. Used by the Insets layout."},
		{"key": "so_extra_3_x", "label": "Extra screen 3: left/right", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Where this inset's middle sits across the window: 0% = left edge, 100% = right edge. It never leaves the window. Used by the Insets layout."},
		{"key": "so_extra_3_y", "label": "Extra screen 3: up/down", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Where this inset's middle sits down the window: 0% = top, 100% = bottom. Used by the Insets layout."},
		{"heading": "Tube (CRT)"},
		pct.call("so_curve", "Glass curve", "Bends the picture like thick, curved CRT glass. The corners bend most."),
		pct.call("so_corner", "Round corners", "Rounds the picture's corners."),
		pct.call("so_bezel", "Frame", "A dark plastic frame round the glass, with a faint reflection of the picture."),
		pct.call("so_scanlines", "Scanlines", "Dark lines between the picture's rows, like an old tube."),
		{"key": "so_scan_px", "label": "Scanline size", "min": 1.0, "max": 8.0, "step": 0.5, "format": "%.1f px",
			"tooltip": "One scanline every this many window pixels. Stays the same size when you resize the window."},
		pct.call("so_mask", "Phosphor mask", "The fine red, green and blue pattern of a tube's screen."),
		{"key": "so_mask_type", "label": "Mask type", "type": "option",
			"options": [["grille", "Stripes (aperture grille)"], ["shadow", "Dots (shadow mask)"], ["slot", "Slots (slot mask)"]],
			"tooltip": "The shape of the phosphor pattern."},
		pct.call("so_glow", "Glow", "Bright parts glow softly into their surroundings."),
		pct.call("so_vignette", "Dark edges", "Darkens the picture towards its edges."),
		pct.call("so_fringe", "Colour fringing", "Red and blue edges drift apart towards the sides, like a worn tube."),
		pct.call("so_flicker", "Flicker", "The brightness flickers slightly. Turned down in photosensitive-safe mode."),
		pct.call("so_roll", "Rolling bar", "A soft bright bar rolls slowly down the picture. Turned down in photosensitive-safe mode."),
		{"heading": "Room looks"},
		pct.call("so_led", "LED dots", "Breaks the picture into round LED lights, like a giant billboard."),
		{"key": "so_led_count", "label": "LEDs across", "min": 40.0, "max": 400.0, "step": 1.0, "format": "%d",
			"tooltip": "How many LEDs across the window. More = finer."},
		pct.call("so_holo", "Hologram", "A cyan hologram look with drifting lines and the odd glitch."),
		pct.call("so_bend", "Cinema bend", "The left and right edges curve away, like a wide curved cinema screen."),
		{"heading": "Tape and film"},
		pct.call("so_vhs", "Tape tracking", "A wobbly picture with a tracking band rolling through and tape noise."),
		pct.call("so_bleed", "Colour bleed", "Colours smear sideways, like video tape or a cheap cable."),
		{"key": "so_stamp", "label": "PLAY and date text", "type": "check",
			"tooltip": "Puts a tape PLAY sign and today's date in the corners."},
		pct.call("so_grain", "Film grain", "Fine moving grain over the picture."),
		pct.call("so_scratches", "Dust and scratches", "Dust specks, scratches and a slightly jumpy film gate."),
		pct.call("so_sepia", "Faded film colour", "Fades the colours to old brown film."),
		{"heading": "Retro and fun"},
		pct.call("so_pixelate", "Chunky pixels", "Big square pixels. 100% = 24-pixel blocks."),
		{"key": "so_palette", "label": "Colour palette", "type": "option",
			"options": [["none", "Full colour"], ["handheld", "Handheld green"], ["amber", "Amber monitor"],
				["green", "Green monitor"], ["grey", "Greyscale"], ["retro4", "Four-colour computer"]],
			"tooltip": "Limits the picture to a few colours, like old screens."},
		pct.call("so_dither", "Dither", "A fine dot pattern that blends a palette's few colours."),
		{"key": "so_fun", "label": "Fun look", "type": "option",
			"options": [["none", "None"], ["night", "Night vision"], ["thermal", "Thermal camera"], ["halftone", "Comic halftone"],
				["ascii", "Text mode (ASCII)"], ["posterize", "Poster colours"], ["invert", "Negative"]],
			"tooltip": "A playful filter over the whole picture."},
		pct.call("so_fun_amount", "Fun look amount", "How much of the fun look shows over the normal picture."),
		{"heading": "Colour"},
		{"key": "so_saturation", "label": "Colour", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "0% = black and white, 100% = normal, 200% = extra colourful."},
		{"key": "so_brightness", "label": "Brightness", "min": 0.5, "max": 1.5, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the picture is. 100% = normal."},
		{"key": "so_contrast", "label": "Contrast", "min": 0.5, "max": 1.5, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How strong the difference between dark and light is. 100% = normal."},
	]
