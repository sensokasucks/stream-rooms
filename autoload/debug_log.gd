extends Node
## DebugLog: writes a cleaned-up log file for troubleshooting, one per run, that is safe to send
## to someone helping (a friend, Claude). It lives in "logs_to_share" inside the app's own folder
## (%APPDATA%\Redot\app_userdata\Stream Rooms\logs_to_share on Windows); the panel's Messages fold
## has an "Open log folder" button.
##
## What goes in it:
##   - a header: app and engine version, Windows version, CPU, graphics card and driver, screens,
##     the settings that differ from the defaults (simple values only, never passwords or addresses)
##   - everything the engine prints: print(), warnings, errors, script errors with their backtrace
##     (caught with a Logger, OS.add_logger, Godot 4.5+ / Redot 26.2)
##   - app events: panel / status messages, room and source changes, Stream Core connection,
##     Together (co-stream) joins, leaves, drops and the ping, video loading
##   - a "still alive" line every minute (frame rate, memory, session and ping)
##   - when the last run didn't close normally (a crash, or the window was killed): a note, and the
##     last lines of the engine's own log from that run (user://logs/godot*.log), cleaned too
##
## What is taken out (clean()): IP addresses (each one becomes a numbered tag like <ip-lan#1>, so
## two lines about the same address still match), the Windows user name and computer name, the
## user / Documents / app folders, Try Cloudflare tunnel names, e-mail addresses and anything that
## looks like a token, key or password in a link. Chatter names stay: they are needed to follow
## what happened, and they are public on stream anyway.
##
## Turned on and off with the setting debug_log (panel: footer > Messages > "Save a log file for
## troubleshooting"). KEEP_FILES files are kept per profile; a test profile (--mp-profile=test) writes
## into its own sub-folder so test runs never push the real logs out.
##
## Loads right after AppState (project.godot) so it catches almost everything. Lines are held in
## memory until the first frame, when the saved settings are known (SaveManager loads after this).

## How many log files are kept (per profile). Older ones are deleted at start-up.
const KEEP_FILES: int = 15
## A run's file stops growing at this size (bytes); a last line says so. Keeps a runaway error
## loop from filling the disk.
const MAX_BYTES: int = 25 * 1024 * 1024
## Bytes in a megabyte, as a float (for the MB numbers in the log).
const MB: float = 1024.0 * 1024.0
## Seconds between "still alive" lines.
const HEARTBEAT_S: float = 60.0
## Lines taken from the end of the engine's log after a run that didn't close normally.
const CRASH_TAIL_LINES: int = 200
## Folder name inside user:// (the Windows path is in the file comment above).
const FOLDER: String = "logs_to_share"
## A setting change is logged once per key in this many seconds (sliders send a stream of them).
const SETTING_QUIET_MS: int = 2000
## Setting keys never logged even by name (they change all the time and say nothing useful).
const SETTING_SKIP: PackedStringArray = ["panel_advanced", "camera_position", "panel_window_rect"]
## Words in a setting key that keep its value out of the header (passwords, names, addresses...).
const PRIVATE_KEY_WORDS: PackedStringArray = ["password", "token", "key", "secret", "name", "address", "url",
	"path", "file", "folder", "channel", "header", "text", "source"]

var _mutex := Mutex.new()
var _file: FileAccess
var _path: String = ""               # this run's file (absolute), "" while off
var _started: bool = false           # false until the first frame (lines wait in _pending)
var _pending: PackedStringArray = []  # lines written before _start
var _writing: bool = false           # guards against a write error being logged into itself
var _bytes: int = 0
var _full: bool = false
var _last_line: String = ""          # repeated lines are counted, not written again
var _repeats: int = 0
var _catcher: _Catcher
var _beat: float = HEARTBEAT_S
var _setting_seen: Dictionary = {}   # setting key -> Time.get_ticks_msec() of its last line
var _net_last: Dictionary = {}       # the parts of NetSession's state last logged (see _on_net_state)
var _ip_tags: Dictionary = {}        # address -> "<ip#n>" tag, the same all run long
var _known: Array = []               # [[text, replacement], ...] known private strings, longest first
var _ip4: RegEx
var _ip6: RegEx
var _patterns: Array = []            # [[RegEx, replacement], ...] applied after _known


## Catches everything the engine prints or reports. Runs on whatever thread printed, so it only
## hands the text to DebugLog._add (which takes the mutex).
class _Catcher extends Logger:
	var sink: Callable

	func _log_message(message: String, error: bool) -> void:
		sink.call(("ERR  " if error else "     ") + message.strip_edges(false, true))

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		var text := "%s: %s" % [kind, rationale if rationale != "" else code]
		if rationale != "" and code != "":
			text += " (%s)" % code
		text += "\n       at %s (%s:%d)" % [function, file, line]
		for bt in script_backtraces:
			if bt and not bt.is_empty():
				text += "\n" + bt.format(7, 2)
		sink.call("!!   " + text)


func _ready() -> void:
	_build_cleaner()
	_catcher = _Catcher.new()
	_catcher.sink = _add
	OS.add_logger(_catcher)
	_start.call_deferred()


func _exit_tree() -> void:
	note("app", "closing normally")
	_mutex.lock()
	_flush_repeats()
	if _file:
		_file.close()
		_file = null
	_mutex.unlock()
	if _catcher:
		OS.remove_logger(_catcher)
	DirAccess.remove_absolute(_marker_path())


## The panel's "Open log folder" button and the README point here. Made if missing.
func get_folder() -> String:
	var dir := ProjectSettings.globalize_path("user://" + FOLDER)
	if not AppState.get_profile().is_empty():
		dir = dir.path_join(AppState.get_profile())
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## This run's log file (absolute path), "" while logging is off.
func get_log_path() -> String:
	return _path


## An app event for the log: area is a short tag ("net", "core", "room"...). The text is cleaned
## like everything else, so passing an address is fine. Other scripts call this (NetSession...).
func note(area: String, text: String) -> void:
	_add("[%s] %s" % [area, text])


# ── Start-up ─────────────────────────────────────────────────
## First frame: settings are loaded now. Opens the file (or drops the waiting lines if off).
func _start() -> void:
	_started = true
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.status_message.connect(func(text: String, is_error: bool) -> void:
		note("message", ("ERROR " if is_error else "") + text))
	EventBus.room_changed.connect(func(room_id: String) -> void: note("room", "room is now " + room_id))
	EventBus.source_changed.connect(func(mode: String) -> void: note("screen", "big screen source: " + mode))
	EventBus.chat_status_changed.connect(func(info: Dictionary) -> void:
		note("core", "Stream Core %s%s" % ["connected" if bool(info.get("connected", false)) else "not connected",
			(": " + String(info.get("error", ""))) if String(info.get("error", "")) != "" else ""]))
	EventBus.net_state_changed.connect(_on_net_state)
	EventBus.video_job_changed.connect(func(state: String, message: String, details: String) -> void:
		note("video", "%s %s%s" % [state, message, ("\n" + details.right(2000)) if state == "failed" and details != "" else ""]))
	EventBus.file_prepare_failed.connect(func(input: String, message: String) -> void:
		note("video", "couldn't prepare %s: %s" % [input.get_file() if not input.begins_with("http") else input, message]))
	EventBus.quit_requested.connect(func() -> void: note("app", "quit requested"))
	if bool(AppState.get_setting("debug_log")):
		_open()
	else:
		_pending.clear()


## Makes this run's file, writes the header, the crash note and the lines held so far.
func _open() -> void:
	var dir := get_folder()
	_prune(dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path := dir.path_join("stream_rooms_%s.log" % stamp)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_pending.clear()
		return
	var crashed := FileAccess.file_exists(_marker_path())
	var marker := FileAccess.open(_marker_path(), FileAccess.WRITE)
	if marker:
		marker.store_string(path.get_file())
		marker.close()
	_mutex.lock()
	_file = f
	_path = path
	_write_raw(clean(_header()))
	if crashed:
		_write_raw(_crash_report())
	for line in _pending:
		_write_raw(line)
	_pending.clear()
	_mutex.unlock()


## Deletes the oldest files so at most KEEP_FILES - 1 remain (this run makes the next one).
func _prune(dir: String) -> void:
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("stream_rooms_") and f.ends_with(".log"):
			files.append(f)
	files.sort()             # the date is in the name, so oldest first
	while files.size() >= KEEP_FILES:
		DirAccess.remove_absolute(dir.path_join(String(files.pop_front())))


## Present while the app runs; removed when it closes normally. Still there at the next start =
## the last run crashed or was killed.
func _marker_path() -> String:
	return get_folder().path_join(".running")


## Who / what / where: everything someone helping would ask first. All cleaned.
func _header() -> String:
	var v := Engine.get_version_info()
	var mem := OS.get_memory_info()
	var lines: PackedStringArray = [
		"=== Stream Rooms log for troubleshooting ===",
		"Started:    %s (local time), UTC%s" % [Time.get_datetime_string_from_system(false, true), _utc_offset()],
		"App:        Stream Rooms %s%s" % [ProjectSettings.get_setting("application/config/version", "dev"),
			"  (profile %s)" % AppState.get_profile() if not AppState.get_profile().is_empty() else ""],
		"Engine:     %s %s%s" % [v.get("string", ""), "editor" if OS.has_feature("editor") else "exported",
			"  debug build" if OS.is_debug_build() else ""],
		"System:     %s %s, %s, %d threads, %d MB memory" % [OS.get_name(), OS.get_version(), OS.get_processor_name(),
			OS.get_processor_count(), roundi(float(mem.get("physical", 0)) / MB)],
		"Graphics:   %s (%s), driver %s, %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
			" ".join(OS.get_video_adapter_driver_info()), RenderingServer.get_current_rendering_driver_name()],
		"Screens:    %s" % _screens(),
		"Add-ons:    NDI %s, Spout %s" % ["yes" if ClassDB.class_exists("NDIFinder") else "no",
			"yes" if ClassDB.class_exists("SpoutTexture") else "no"],
		"Settings changed from the defaults: " + _changed_settings(),
		"(IP addresses, user and computer names, personal folders, tunnel names and keys are replaced with <tags>.)",
		"",
	]
	return "\n".join(lines)


## "+01:00" style offset of this PC's clock, so times can be matched with a friend's log.
func _utc_offset() -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	@warning_ignore("integer_division")
	return "%s%02d:%02d" % ["+" if bias >= 0 else "-", absi(bias) / 60, absi(bias) % 60]


func _screens() -> String:
	var out: PackedStringArray = []
	for i in DisplayServer.get_screen_count():
		var hz := DisplayServer.screen_get_refresh_rate(i)     # -1 when the system doesn't say
		out.append("%dx%d @%s Hz%s" % [DisplayServer.screen_get_size(i).x, DisplayServer.screen_get_size(i).y,
			str(roundi(hz)) if hz > 0.0 else "?", " (window here)" if i == DisplayServer.window_get_current_screen() else ""])
	return ", ".join(out)


## key=value for settings that differ from AppState.DEFAULTS. Only numbers, switches and short
## plain words; keys that could hold something private (PRIVATE_KEY_WORDS) show as "(changed)".
func _changed_settings() -> String:
	var out: PackedStringArray = []
	var all := AppState.get_all_settings()
	for key: String in all.keys():
		var value: Variant = all[key]
		if not AppState.DEFAULTS.has(key) or value == AppState.DEFAULTS[key] or SETTING_SKIP.has(key):
			continue
		out.append("%s=%s" % [key, _setting_text(key, value)])
	out.sort()
	return "none" if out.is_empty() else ", ".join(out)


## How a setting's value shows in the log (see _changed_settings).
func _setting_text(key: String, value: Variant) -> String:
	var t := typeof(value)
	if t == TYPE_BOOL or t == TYPE_INT or t == TYPE_FLOAT:
		return str(value)
	for w in PRIVATE_KEY_WORDS:
		if key.contains(w):
			return "(changed)"
	if t == TYPE_STRING:
		var s := String(value)
		if s.length() <= 24 and not s.contains("/") and not s.contains("\\") and not s.contains(":"):
			return s
	return "(changed)"


## After a crash: the end of the engine's own log from the run before (Redot renames the old
## godot.log to godot<date>.log when it starts, and keeps a few).
func _crash_report() -> String:
	var out := "!!   The last run didn't close normally (a crash, or it was closed from Task Manager).\n"
	var dir := ProjectSettings.globalize_path("user://logs")
	var names: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("godot") and f.ends_with(".log") and f != "godot.log":
			names.append(f)
	if names.is_empty():
		return out + "     (no engine log from that run was found)\n"
	names.sort()
	var text := FileAccess.get_file_as_string(dir.path_join(String(names.back())))
	var lines := text.split("\n")
	var first := maxi(lines.size() - CRASH_TAIL_LINES, 0)
	out += "     Last %d lines of that run's engine log:\n" % (lines.size() - first)
	for i in range(first, lines.size()):
		out += "  |  " + clean(lines[i].strip_edges(false, true)) + "\n"
	return out + "  |  (end of the last run's engine log)\n"


# ── Writing ──────────────────────────────────────────────────
## Every line comes through here (engine output, note(), events). Thread-safe.
func _add(text: String) -> void:
	_mutex.lock()
	if _writing:         # something inside a write printed: don't loop
		_mutex.unlock()
		return
	_writing = true
	var line := clean(text)
	if line == _last_line:
		_repeats += 1
	else:
		_flush_repeats()
		_last_line = line
		var stamped := "%s %s" % [Time.get_time_string_from_system(), line]
		if not _started:
			if _pending.size() < 5000:
				_pending.append(stamped)
		elif _file:
			_write_raw(stamped)
	_writing = false
	_mutex.unlock()


## "(the line above repeated N more times)" once a different line comes. Mutex held by the caller.
func _flush_repeats() -> void:
	if _repeats > 0 and _file:
		_write_raw("         (the line above repeated %d more time%s)" % [_repeats, "" if _repeats == 1 else "s"])
	_repeats = 0


## Appends one line (or block) and flushes, so the file is complete even if the app crashes right
## after. Mutex held by the caller.
func _write_raw(text: String) -> void:
	if _file == null or _full:
		return
	_file.store_line(text)
	_file.flush()
	_bytes += text.length() + 1
	if _bytes > MAX_BYTES:
		_full = true
		_file.store_line("!!   This log reached %d MB; nothing more is written this run." % roundi(MAX_BYTES / MB))
		_file.flush()


# ── Events ───────────────────────────────────────────────────
## The Messages fold's tick turns logging on and off right away. Other settings: the key only
## (values can be private), at most once per SETTING_QUIET_MS per key.
func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "debug_log":
		if bool(value) and _file == null:
			_open()
			note("app", "log file turned on")
		elif not bool(value) and _file != null:
			note("app", "log file turned off")
			_mutex.lock()
			_file.close()
			_file = null
			_path = ""
			_mutex.unlock()
			DirAccess.remove_absolute(_marker_path())   # (or the next start would report a crash)
		return
	if SETTING_SKIP.has(key) or _file == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_setting_seen.get(key, -SETTING_QUIET_MS)) < SETTING_QUIET_MS:
		return
	_setting_seen[key] = now
	note("setting", "%s = %s" % [key, _setting_text(key, value)])


## Together / co-stream: logs the role, who is in and who waits, only when one of those changed
## (the panel gets this signal for every small thing).
func _on_net_state(info: Dictionary) -> void:
	var names: PackedStringArray = []
	for p: Dictionary in info.get("peers", []):
		names.append("%s#%d%s" % [String(p.get("name", "?")), int(p.get("id", 0)), " (co-host)" if bool(p.get("cohost", false)) else ""])
	var now := {"role": String(info.get("role", "off")), "peers": ", ".join(names),
		"pending": (info.get("pending", []) as Array).size(), "waiting": bool(info.get("waiting", false))}
	if now == _net_last:
		return
	_net_last = now
	note("net", "role=%s, in the session: [%s], waiting to be let in: %d%s" % [now["role"], now["peers"],
		now["pending"], ", this guest waits for the host's OK" if now["waiting"] else ""])


## The "still alive" line: frame rate and memory, and the session with its ping.
func _process(delta: float) -> void:
	if _file == null:
		return
	_beat -= delta
	if _beat > 0.0:
		return
	_beat = HEARTBEAT_S
	var line := "fps %d, memory %d MB, video memory %d MB, nodes %d, room %s, source %s, Core %s" % [
		Engine.get_frames_per_second(), roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / MB),
		roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / MB),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), String(AppState.get_setting("room_id")),
		AppState.get_source_mode(), "connected" if ChatFeed.is_connected_to_core() else "not connected"]
	if NetSession.get_role() != "off":
		line += ", together %s with %d other(s)" % [NetSession.get_role(), maxi((NetSession.get_info().get("peers", []) as Array).size() - 1, 0)]
		if NetSession.get_role() == "guest":
			line += ", ping %d ms" % roundi(NetSession.ping_seconds() * 1000.0)
	note("alive", line)


# ── Cleaning ─────────────────────────────────────────────────
## The text with private details swapped for tags. Safe to call from any thread.
func clean(text: String) -> String:
	var out := text
	for pair: Array in _known:
		out = _replace_ci(out, String(pair[0]), String(pair[1]))
	for pair: Array in _patterns:
		out = (pair[0] as RegEx).sub(out, String(pair[1]), true)
	out = _tag_matches(out, _ip4, _ip4_tag)
	out = _tag_matches(out, _ip6, _ip6_tag)
	return out


## Folders and names from this PC that would say who the user is, longest first, both slash styles.
func _build_cleaner() -> void:
	var known: Dictionary = {}
	var add := func(text: String, tag: String) -> void:
		text = text.strip_edges().trim_suffix("/").trim_suffix("\\")
		if text.length() < 4:
			return
		known[text] = tag
		known[text.replace("\\", "/")] = tag
		known[text.replace("/", "\\")] = tag
	add.call(OS.get_user_data_dir(), "<app data>")
	add.call(OS.get_executable_path().get_base_dir(), "<app folder>")
	add.call(ProjectSettings.globalize_path("res://"), "<project folder>")
	add.call(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), "<documents>")
	add.call(OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP), "<desktop>")
	add.call(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), "<downloads>")
	add.call(OS.get_environment("USERPROFILE"), "<home>")
	add.call(OS.get_environment("HOME"), "<home>")
	add.call(OS.get_environment("OneDrive"), "<onedrive>")
	var keys: Array = known.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for k: String in keys:
		_known.append([k, known[k]])
	# user and computer names on their own (in messages, odd paths): whole words only, and only
	# when long enough not to hit ordinary words
	for pair: Array in [[OS.get_environment("USERNAME"), "<user>"], [OS.get_environment("USER"), "<user>"],
			[OS.get_environment("COMPUTERNAME"), "<pc>"], [OS.get_environment("USERDOMAIN"), "<pc>"]]:
		var word := String(pair[0]).strip_edges()
		if word.length() >= 3:
			_patterns.append([RegEx.create_from_string("(?i)(?<![\\w])" + _escape(word) + "(?![\\w])"), pair[1]])
	for pair: Array in [
		# any Windows / Mac / Linux user folder (another user's, OneDrive...)
		# (a folder name may have spaces when another folder follows it; at the end it stops at a space)
		["(?i)([A-Z]:[\\\\/]+(?:Users|Documents and Settings)[\\\\/]+)(?:[^\\\\/\"'<>|\\r\\n]+(?=[\\\\/])|[^\\\\/\\s\"'<>|]+)", "$1<user>"],
		["(/(?:home|Users)/)[^/\\s\"'<>]+", "$1<user>"],
		# secrets in links and text: key=..., token=..., oauth:..., Bearer ...
		["(?i)\\b((?:access_|refresh_|id_|run_|ws_)?(?:token|key|password|passwd|pwd|pass|secret|auth|code|sig|signature|nonce|proof|client_secret)=)[^&\\s\"'<>]+", "$1<hidden>"],
		["(?i)\\b(oauth:)[a-z0-9]+", "$1<hidden>"],
		["(?i)\\b(Bearer\\s+)[A-Za-z0-9._~+/=-]+", "$1<hidden>"],
		# a Try Cloudflare tunnel's name is the session's address
		["(?i)\\b[a-z0-9-]+\\.trycloudflare\\.com", "<tunnel>.trycloudflare.com"],
		["(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b", "<email>"],
	]:
		_patterns.append([RegEx.create_from_string(String(pair[0])), pair[1]])
	_ip4 = RegEx.create_from_string("(?<![\\w.])(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})(?![\\w.]*\\d)")
	# IPv6 / MAC-style candidates; _ip6_tag decides (times like 18:12:09 are left alone)
	_ip6 = RegEx.create_from_string("(?<![\\w:.])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?:%[\\w]+)?(?![\\w:])")


## Every match of re replaced with tagger(match) (or kept when it gives back "").
func _tag_matches(text: String, re: RegEx, tagger: Callable) -> String:
	var found := re.search_all(text)
	if found.is_empty():
		return text
	var out := ""
	var at := 0
	for m in found:
		var tag: String = tagger.call(m)
		out += text.substr(at, m.get_start() - at) + (tag if tag != "" else m.get_string())
		at = m.get_end()
	return out + text.substr(at)


## IPv4: this PC (127.x) and "any" (0.0.0.0) stay; others get a numbered tag that says what kind
## of address it was (home network, Tailscale, internet).
func _ip4_tag(m: RegExMatch) -> String:
	var parts: Array = []
	for i in range(1, 5):
		var n := int(m.get_string(i))
		if n > 255:
			return ""
		parts.append(n)
	if parts[0] == 127 or (parts[0] == 0 and parts[3] == 0) or m.get_string() == "255.255.255.255":
		return ""
	var kind := "ip"
	if parts[0] == 10 or (parts[0] == 172 and parts[1] >= 16 and parts[1] < 32) or (parts[0] == 192 and parts[1] == 168):
		kind = "ip-home"
	elif parts[0] == 100 and parts[1] >= 64 and parts[1] < 128:
		kind = "ip-tailscale"
	return _tag_for(m.get_string(), kind)


## IPv6 (and MAC) addresses: "::1" (this PC) stays; anything with "::", 5+ colons or a hex letter
## is tagged. A clock time (18:12:09) has none of those.
func _ip6_tag(m: RegExMatch) -> String:
	var s := m.get_string()
	if s == "::1" or s == "::" or s.length() < 5:
		return ""
	var colons := s.count(":")
	var has_letter := false
	for c in s.split("%")[0]:
		if "abcdefABCDEF".contains(c):
			has_letter = true
	if not (s.contains("::") or colons >= 5 or (has_letter and colons >= 2)):
		return ""
	return _tag_for(s.split("%")[0].to_lower(), "ip6")


## The same address gets the same tag all run: <ip-home#1>, <ip#2>... Mutex-safe (Mutex is re-entrant).
func _tag_for(address: String, kind: String) -> String:
	_mutex.lock()
	if not _ip_tags.has(address):
		_ip_tags[address] = "<%s#%d>" % [kind, _ip_tags.size() + 1]
	var tag: String = _ip_tags[address]
	_mutex.unlock()
	return tag


## Case-insensitive replace of every place `what` appears.
static func _replace_ci(text: String, what: String, with: String) -> String:
	return text.replacen(what, with)


## what, safe to put inside a RegEx pattern.
static func _escape(what: String) -> String:
	var out := ""
	for c in what:
		if "\\^$.|?*+()[]{}".contains(c):
			out += "\\"
		out += c
	return out
