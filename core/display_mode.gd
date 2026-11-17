class_name DisplayMode
extends RefCounted
## The main window's mode, monitor and size (Esc menu > Display, ui/esc_menu.gd).
## Settings (per machine, AppState.DEFAULTS): window_mode ("" | windowed | borderless | fullscreen),
## window_screen (monitor index from 0, -1 = the one it opened on) and window_size ("1920x1080",
## "" = fill the screen). window_size_presets keeps the sizes saved from the menu's Custom size box
## ("1440x1080,1080x1920"); they join SIZES in the Window size dropdown (size_options). "" / -1 leave the window as project.godot opened it, so an old install
## looks the same until someone picks something in the menu.
## EscMenu calls apply() once at start and again whenever one of those three settings changes.
## Borderless covers the whole monitor (taskbar too) unless a size is picked: then it is that size
## in the monitor's top-left corner, which suits an OBS Window Capture of a fixed canvas size.
## F11 (core/hotkeys.gd) still flips fullscreen for the moment without saving anything.

## The sizes offered in the menu: [setting value, label]. "" = fill the screen.
const SIZES: Array = [
	["", "Fill the screen"],
	["1280x720", "1280 × 720 (720p)"],
	["1600x900", "1600 × 900"],
	["1920x1080", "1920 × 1080 (1080p)"],
	["2560x1440", "2560 × 1440 (1440p)"],
	["3840x2160", "3840 × 2160 (4K)"],
]


## The smallest and largest custom size the Esc menu's Custom size box accepts (pixels).
const MIN_SIZE := Vector2i(320, 200)
const MAX_SIZE := Vector2i(7680, 4320)


## "1440x1080" from a size (the form window_size and window_size_presets store).
static func size_text(v: Vector2i) -> String:
	return "%dx%d" % [v.x, v.y]


## "1440 × 1080" for the menu, plus a shape hint for the common odd ones (4:3, portrait...).
static func size_label(v: Vector2i) -> String:
	var label := "%d × %d" % [v.x, v.y]
	if v.y > v.x:
		label += " (portrait)"
	elif v.x * 3 == v.y * 4:
		label += " (4:3)"
	elif float(v.x) / float(v.y) >= 2.2:   # 2560 × 1080, 3440 × 1440 ("21:9" screens aren't exactly 21:9)
		label += " (ultrawide)"
	return label


## The saved custom sizes (setting window_size_presets, "1440x1080,1080x1920"), cleaned:
## unreadable entries, repeats and built-in sizes left out, in the order they were saved.
static func presets() -> PackedStringArray:
	var out := PackedStringArray()
	var built_in: Array = SIZES.map(func(o: Array) -> String: return String(o[0]))
	for part in String(AppState.get_setting("window_size_presets")).split(",", false):
		var v := parse_size(part.strip_edges())
		if v == Vector2i.ZERO:
			continue
		var t := size_text(v)
		if not out.has(t) and not built_in.has(t):
			out.append(t)
	return out


## Adds a size to the saved presets (no repeats; built-in sizes are already in the list). Returns
## false for a size parse_size refuses. Called by the Esc menu's "Save as preset" button.
static func add_preset(v: Vector2i) -> bool:
	if parse_size(size_text(v)) == Vector2i.ZERO:
		return false
	var list := presets()
	var t := size_text(v)
	if not list.has(t) and not SIZES.any(func(o: Array) -> bool: return String(o[0]) == t):
		list.append(t)
		AppState.set_setting("window_size_presets", ",".join(list))
	return true


## Takes a saved size out of the presets (the Esc menu's "Remove preset" button).
static func remove_preset(text: String) -> void:
	var list := presets()
	var i := list.find(text)
	if i >= 0:
		list.remove_at(i)
		AppState.set_setting("window_size_presets", ",".join(list))


## Everything the Window size dropdown offers: SIZES, then the saved presets, then the current
## size when it is neither (typed in the Custom size box but not saved), so the dropdown never
## shows a wrong pick.
static func size_options() -> Array:
	var opts: Array = SIZES.duplicate()
	for t in presets():
		opts.append([t, size_label(parse_size(t)) + " · saved"])
	var now := String(AppState.get_setting("window_size"))
	var v := parse_size(now)
	if v != Vector2i.ZERO and not opts.any(func(o: Array) -> bool: return String(o[0]) == size_text(v)):
		opts.append([now, size_label(v) + " · custom"])
	return opts


## "1920x1080" -> Vector2i(1920, 1080); anything else -> Vector2i.ZERO ("fill the screen").
static func parse_size(text: String) -> Vector2i:
	var parts := text.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var v := Vector2i(int(parts[0]), int(parts[1]))
	return v if v.x >= MIN_SIZE.x and v.y >= MIN_SIZE.y and v.x <= MAX_SIZE.x and v.y <= MAX_SIZE.y else Vector2i.ZERO


## The monitors for the menu: [[index, "1 · 2560 × 1440"], ...]. Redot can't read monitor names.
static func screens() -> Array:
	var list: Array = []
	for i in DisplayServer.get_screen_count():
		var s := DisplayServer.screen_get_size(i)
		list.append([i, "%d · %d × %d" % [i + 1, s.x, s.y]])
	return list


## What the window is doing now: "windowed" | "borderless" | "fullscreen" (for the menu's buttons
## while window_mode is still "").
static func current(win: Window) -> String:
	if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		return "fullscreen"
	return "borderless" if win.borderless else "windowed"


## Puts the window where the settings say. Does nothing for the parts left at ""/-1.
static func apply(win: Window) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := String(AppState.get_setting("window_mode"))
	var screen := int(AppState.get_setting("window_screen"))
	var size := parse_size(String(AppState.get_setting("window_size")))
	if screen < 0 or screen >= DisplayServer.get_screen_count():
		screen = win.current_screen
	if mode == "":
		# only the monitor was picked: move the window there as it is
		if int(AppState.get_setting("window_screen")) >= 0 and win.current_screen != screen:
			win.current_screen = screen
		return
	var rect := DisplayServer.screen_get_usable_rect(screen)
	var full := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	match mode:
		"fullscreen":
			win.borderless = false
			if win.mode != Window.MODE_WINDOWED:
				win.mode = Window.MODE_WINDOWED       # (leave maximized first, or the monitor move is ignored)
			win.current_screen = screen
			win.mode = Window.MODE_FULLSCREEN
		"borderless":
			win.mode = Window.MODE_WINDOWED
			win.borderless = true
			if size == Vector2i.ZERO:
				win.position = full.position
				win.size = full.size
			else:
				win.size = Vector2i(mini(size.x, full.size.x), mini(size.y, full.size.y))
				win.position = full.position
		_:   # windowed
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			if size == Vector2i.ZERO:
				win.current_screen = screen
				win.mode = Window.MODE_MAXIMIZED
			else:
				win.size = Vector2i(mini(size.x, rect.size.x), mini(size.y, rect.size.y))
				win.position = rect.position + (rect.size - win.size) / 2
