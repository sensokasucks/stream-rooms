class_name DisplayMode
extends RefCounted
## The main window's mode, monitor and size (Esc menu > Display, ui/esc_menu.gd).
## Settings (per machine, AppState.DEFAULTS): window_mode ("" | windowed | borderless | fullscreen),
## window_screen (monitor index from 0, -1 = the one it opened on) and window_size ("1920x1080",
## "" = fill the screen). "" / -1 leave the window as project.godot opened it, so an old install
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


## "1920x1080" -> Vector2i(1920, 1080); anything else -> Vector2i.ZERO ("fill the screen").
static func parse_size(text: String) -> Vector2i:
	var parts := text.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var v := Vector2i(int(parts[0]), int(parts[1]))
	return v if v.x >= 320 and v.y >= 200 else Vector2i.ZERO


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
