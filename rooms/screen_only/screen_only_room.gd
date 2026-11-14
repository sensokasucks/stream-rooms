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

var _layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _standby: Label            # stand-by text over the "standby" between-videos picture
var _stamp_play: Label         # tape PLAY text (so_stamp), top left
var _stamp_date: Label         # tape date text (so_stamp), bottom left
var _texture: Texture2D        # the big screen's picture (EventBus.screen_texture_changed)
var _applying_preset: bool = false
var _stamp_wait: float = 0.0   # seconds until the date stamp's clock is redrawn


func _ready() -> void:
	super._ready()
	_build_layer()
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.screen_texture_changed.connect(_on_screen_texture)
	_apply_all()
	# ask ScreenFeed for the picture it already has (a video playing before the room switch)
	EventBus.feed_textures_requested.emit()


## The room is freed on a room swap: drop the EventBus connections with it.
func _exit_tree() -> void:
	EventBus.setting_changed.disconnect(_on_setting_changed)
	EventBus.screen_texture_changed.disconnect(_on_screen_texture)


## Every frame: the window's size (resizing), the picture's size (a tab can change size) and
## whether there is a picture to show at all (no source, or the curtain closed -> between videos).
func _process(delta: float) -> void:
	super._process(delta)
	if _mat == null:
		return
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
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.BLACK
	_mat = ShaderMaterial.new()
	_mat.shader = FX_SHADER
	_rect.material = _mat
	_layer.add_child(_rect)

	# full-window labels (anchors AND offsets, so they stretch with the window), aligned inside
	_standby = _make_label(HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	_stamp_play = _make_label(HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	_stamp_play.offset_left = 40.0
	_stamp_play.offset_top = 30.0
	_stamp_play.text = "PLAY ▶"
	_stamp_date = _make_label(HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_BOTTOM)
	_stamp_date.offset_left = 40.0
	_stamp_date.offset_bottom = -30.0


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
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return l


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


## EventBus.setting_changed: a Look writes its whole set; any so_* key or the safety settings
## re-send the uniforms.
func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "so_preset" and not _applying_preset:
		apply_preset(String(AppState.get_setting("so_preset")))
		return
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
	var f := func(key: String) -> float: return float(AppState.get_setting(key))
	_mat.set_shader_parameter("fit_mode", int(FIT_MODES.get(String(AppState.get_setting("so_fit")), 0)))
	_mat.set_shader_parameter("bars_mode", int(BAR_MODES.get(String(AppState.get_setting("so_bars")), 0)))
	_mat.set_shader_parameter("bar_color", AppState.get_setting("so_bar_color"))
	_mat.set_shader_parameter("idle_mode", int(IDLE_MODES.get(String(AppState.get_setting("so_idle")), 0)))
	_mat.set_shader_parameter("mask_type", int(MASK_TYPES.get(String(AppState.get_setting("so_mask_type")), 0)))
	_mat.set_shader_parameter("palette", int(PALETTES.get(String(AppState.get_setting("so_palette")), 0)))
	_mat.set_shader_parameter("fun_mode", int(FUN_MODES.get(String(AppState.get_setting("so_fun")), 0)))
	for pair: Array in [["curve", "so_curve"], ["corner", "so_corner"], ["scanlines", "so_scanlines"],
			["scan_px", "so_scan_px"], ["mask", "so_mask"], ["glow", "so_glow"], ["vignette", "so_vignette"],
			["fringe", "so_fringe"], ["bezel", "so_bezel"], ["led", "so_led"], ["led_count", "so_led_count"],
			["holo", "so_holo"], ["bend", "so_bend"], ["vhs", "so_vhs"], ["bleed", "so_bleed"], ["grain", "so_grain"],
			["scratches", "so_scratches"], ["sepia", "so_sepia"], ["pixelate", "so_pixelate"], ["dither", "so_dither"],
			["fun", "so_fun_amount"], ["saturation", "so_saturation"], ["brightness", "so_brightness"],
			["contrast", "so_contrast"]]:
		_mat.set_shader_parameter(pair[0], f.call(pair[1]))
	# flashing parts: scaled by Flash strength, and cut to a quarter (with slower motion) in safe mode
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	var flash := clampf(float(AppState.get_setting("flash_strength")), 0.0, 1.0) * (0.25 if safe else 1.0)
	_mat.set_shader_parameter("flicker", f.call("so_flicker") * flash)
	_mat.set_shader_parameter("roll", f.call("so_roll") * flash)
	_mat.set_shader_parameter("motion_scale", 0.35 if safe else 1.0)
	var sign_text := String(AppState.get_setting("curtain_sign")).strip_edges()
	_standby.text = sign_text if sign_text != "" else "Please stand by"
	var stamp := bool(AppState.get_setting("so_stamp"))
	_stamp_play.visible = stamp
	_stamp_date.visible = stamp
	_stamp_wait = 0.0


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
