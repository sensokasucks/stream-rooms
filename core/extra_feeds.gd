class_name ExtraFeeds
extends Node
## Extra live pictures for screens a room builds itself (the Forge Hall's three small live
## screens), each with a source of its own that has nothing to do with the big screen or the
## podiums. Pictures only: these feeds carry no sound.
##
## Who uses it: ScreenFeed makes one as a child and hands it its NdiReceiver and SpoutReceiver.
## A room asks through EventBus.extra_feed_requested(slot, kind, address) and gets pictures back
## through EventBus.extra_feed_texture_changed(slot, texture) (null = nothing to show yet).
##   slot     any name the room picks ("forge_live_1"); one feed per slot
##   kind     "ndi"    address = an NDI source name, or part of one ("cam 2" finds
##                     "STUDIO-PC (cam 2)"); needs the optional godot-ndi extension
##            "spout"  address = a Spout sender name, or part of one (optional godot-spout)
##            "stream" address = something ffmpeg can open: rtmp://, rtsp://, srt://, an
##                     http(s) stream (.m3u8) or a video file (which loops). Put "listen:" in
##                     front ("listen:rtmp://0.0.0.0:1935/live/cam") to wait for a camera or
##                     phone app to connect to this PC instead of connecting out to a server.
##                     Needs ffmpeg (tools/ffmpeg.exe, see tools/get_tools.ps1).
##            "tab"    a browser tab or window picked on the sender page (web/sender.html, also
##                     inside Stream Core's "Share to Stream Rooms" card). address = the name
##                     the page shows on that row ("Floor screen"). The page gets one "Extra
##                     screens" row per tab slot (at most CaptureServer.MAX_EXTRA_TABS) with a
##                     "Pick a tab or window" button; its pictures arrive through
##                     CaptureServer / ScreenFeed (tab_frame). See tab_wishes.
##            ""       stop this slot
## An NDI source or Spout sender that isn't there yet is picked up when it appears. A stream
## that ends or can't be opened is tried again every RETRY_S seconds.
##
## Room changes: a room that leaves doesn't have to stop its feeds (and mustn't, because a
## reload of the same room has already asked for them again by then). Instead, on
## EventBus.room_changed every slot is marked stale, and a slot nobody asks for again within
## STALE_S seconds is stopped. A room asks again a frame after room_changed (call_deferred).
##
## Not shared in a co-stream session: every PC shows its own extra feeds.
## Addresses can hold stream keys: they are never put in a status message (those can show on
## the stream), only in DebugLog.note, which cleans them.

## The picture size every "stream" feed is scaled to (letterboxed), in pixels, and its frame
## rate. Small on purpose: the screens are small, and each frame crosses a pipe uncompressed
## (640 x 360 x 3 bytes x 20 = 14 MB a second).
const STREAM_SIZE: Vector2i = Vector2i(640, 360)
const STREAM_FPS: int = 20
## Seconds between tries when a stream can't be opened or has ended.
const RETRY_S: float = 3.0
## Seconds a new stream address waits before ffmpeg starts, so a quick second change (or a
## room reload) doesn't start and kill a process for nothing.
const START_DELAY_S: float = 0.4

## Seconds after a room change before feeds the new room didn't ask for are stopped.
const STALE_S: float = 1.5
## Seconds without a picture before a "tab" feed counts as gone. Long, because a tab that
## doesn't change only gets its last picture sent again once a second by the sender page.
const TAB_QUIET_S: float = 15.0

## The set of "tab" feeds changed (one was asked for, renamed or stopped). ScreenFeed sends
## the sender page its instructions again (ScreenFeed._sync_presenter_feeds reads tab_wishes).
## Sent at most once a frame, from _process.
signal tab_wishes_changed

var _ndi: NdiReceiver
var _spout: SpoutReceiver
## slot -> {"kind", "address", then per kind:
##   ndi:    "name" (the source found, "" = none yet), "player" (VideoStreamPlayer), "size"
##   spout:  "name", "tex" (the Spout texture), "size"
##   stream: "pipe" (_Pipe), "tex" (ImageTexture or null), "wait" (seconds until ffmpeg starts)
##   tab:    "tab" (which "Extra screens" row of the sender page, 0-based), "tex" (ImageTexture
##           or null), "last_s" (when the last picture came, seconds of Time.get_ticks_msec)}
var _slots: Dictionary = {}
var _tabs_dirty: bool = false      # tab_wishes_changed is due (sent from _process)
var _ffmpeg: String = ""           # found once (see _find_ffmpeg); "" = not looked for or missing
var _ffmpeg_looked: bool = false


## One running ffmpeg and the thread reading its pictures. The thread only touches this
## object; the main thread reads `latest` under the mutex in ExtraFeeds._process.
class _Pipe extends RefCounted:
	var thread: Thread
	var mutex := Mutex.new()
	var stop: bool = false           # set by the main thread (under the mutex) to end the loop
	var pid: int = -1                # the ffmpeg running now (under the mutex), -1 = none
	var latest: Image                # the newest picture not yet shown (under the mutex)
	var frames: int = 0              # pictures read since the start (under the mutex)
	var failed: int = 0              # tries in a row that gave no picture (under the mutex)


## Called once by ScreenFeed right after it made its receivers.
func setup(ndi: NdiReceiver, spout: SpoutReceiver) -> void:
	_ndi = ndi
	_spout = spout


func _ready() -> void:
	EventBus.extra_feed_requested.connect(_on_requested)
	EventBus.ndi_sources_changed.connect(func(_n: PackedStringArray, _a: bool) -> void: _sync_named())
	EventBus.spout_senders_changed.connect(func(_n: PackedStringArray, _a: bool) -> void: _sync_named())
	EventBus.feed_textures_requested.connect(_resend)
	EventBus.room_changed.connect(_on_room_changed)


## Quitting: every ffmpeg is stopped and its thread waited for.
func _exit_tree() -> void:
	for slot: String in _slots.keys():
		_stop(slot, false)
	_slots.clear()


## EventBus.room_changed: feeds the new room doesn't ask for again are stopped (see the top).
func _on_room_changed(_room_id: String) -> void:
	for slot: String in _slots:
		(_slots[slot] as Dictionary)["stale"] = true
	get_tree().create_timer(STALE_S).timeout.connect(func() -> void:
		for slot: String in _slots.keys():
			if bool((_slots[slot] as Dictionary).get("stale", false)):
				_stop(slot, true))


## EventBus.extra_feed_requested: start, change or stop (kind "") one slot's feed.
func _on_requested(slot: String, kind: String, address: String) -> void:
	address = address.strip_edges()
	if kind != "" and address == "":
		kind = ""          # nothing to connect to yet
	var cur: Dictionary = _slots.get(slot, {})
	if not cur.is_empty() and String(cur["kind"]) == kind and String(cur["address"]) == address:
		cur["stale"] = false
		EventBus.extra_feed_texture_changed.emit(slot, _texture_of(cur))      # asked again (room reload)
		return
	_stop(slot, true)
	if kind == "":
		return
	var e: Dictionary = {"kind": kind, "address": address}
	match kind:
		"ndi":
			e.merge({"name": "", "player": null, "size": Vector2i.ZERO})
			if not NdiReceiver.is_available():
				EventBus.status_message.emit("NDI isn't available: the godot-ndi plugin didn't load (addons/godot-ndi).", true)
		"spout":
			e.merge({"name": "", "tex": null, "size": Vector2i.ZERO})
			if not SpoutReceiver.is_available():
				EventBus.status_message.emit("Spout isn't available: the godot-spout plugin didn't load (addons/godot-spout).", true)
		"stream":
			e.merge({"pipe": null, "tex": null, "wait": START_DELAY_S})
			if address.trim_prefix("listen:").strip_edges().begins_with("-"):
				EventBus.status_message.emit("That stream address can't start with a dash.", true)
				return
			if _find_ffmpeg() == "":
				EventBus.status_message.emit("A stream address needs ffmpeg: run tools/get_tools.ps1, or put ffmpeg in the tools folder.", true)
				return
		"tab":
			var row := _free_tab()
			if row < 0:
				EventBus.status_message.emit("Only %d screens can show a browser tab of their own at a time." % CaptureServer.MAX_EXTRA_TABS, true)
				return
			e.merge({"tab": row, "tex": null, "last_s": 0.0})
			_tabs_dirty = true
		_:
			push_warning("ExtraFeeds: unknown kind '%s'" % kind)
			return
	_slots[slot] = e
	DebugLog.note("extra feed", "%s shows %s %s" % [slot, kind, address])
	_sync_named()


## Stops one slot's feed. tell = say so on the signal (false while quitting).
func _stop(slot: String, tell: bool) -> void:
	var e: Dictionary = _slots.get(slot, {})
	if e.is_empty():
		return
	_slots.erase(slot)
	match String(e["kind"]):
		"ndi":
			_drop_ndi(e)
		"stream":
			_end_pipe(e["pipe"])
		"tab":
			_tabs_dirty = true
	if tell:
		EventBus.extra_feed_texture_changed.emit(slot, null)


## The picture a slot has right now, or null.
func _texture_of(e: Dictionary) -> Texture2D:
	match String(e["kind"]):
		"ndi":
			return (e["player"] as VideoStreamPlayer).get_video_texture() if e["player"] else null
		"spout", "stream", "tab":
			return e["tex"]
	return null


# ── Browser tabs (kind "tab") ────────────────────────────────
## The lowest "Extra screens" row of the sender page no slot uses yet, or -1 when all
## CaptureServer.MAX_EXTRA_TABS are taken.
func _free_tab() -> int:
	var used: Array[int] = []
	for slot: String in _slots:
		var e: Dictionary = _slots[slot]
		if String(e["kind"]) == "tab":
			used.append(int(e["tab"]))
	for row in CaptureServer.MAX_EXTRA_TABS:
		if not used.has(row):
			return row
	return -1


## The slot whose tab comes from "Extra screens" row `row` of the sender page, or "".
func _slot_of_tab(row: int) -> String:
	for slot: String in _slots:
		var e: Dictionary = _slots[slot]
		if String(e["kind"]) == "tab" and int(e["tab"]) == row:
			return slot
	return ""


## What the sender page's "Extra screens" rows should do, one entry per row:
## {"kind": "tab", "name": the address the room gave} or {"kind": "off"}. ScreenFeed puts it
## into its "presenters" message as "extras" (ScreenFeed._sync_presenter_feeds).
func tab_wishes() -> Array:
	var out: Array = []
	for row in CaptureServer.MAX_EXTRA_TABS:
		var slot := _slot_of_tab(row)
		out.append({"kind": "tab", "name": String((_slots[slot] as Dictionary)["address"])} if slot != "" else {"kind": "off"})
	return out


## A picture from "Extra screens" row `row` of the sender page (ScreenFeed._on_presenter_frame).
## Pictures for a row nobody asked for are dropped.
func tab_frame(row: int, img: Image) -> void:
	var slot := _slot_of_tab(row)
	if slot == "":
		return
	var e: Dictionary = _slots[slot]
	e["last_s"] = Time.get_ticks_msec() / 1000.0
	var tex := e["tex"] as ImageTexture
	if tex == null or Vector2i(tex.get_size()) != img.get_size():
		e["tex"] = ImageTexture.create_from_image(img)
		EventBus.extra_feed_texture_changed.emit(slot, e["tex"])
	else:
		tex.update(img)


## The sender page's status, once a second (ScreenFeed._on_sender_status): sharing[row] = that
## "Extra screens" row has a tab running. Rows that don't (or a page that is gone: an empty
## list) lose their picture, so the screen goes dark instead of freezing.
func tabs_status(sharing: Array[bool]) -> void:
	for slot: String in _slots:
		var e: Dictionary = _slots[slot]
		if String(e["kind"]) != "tab" or e["tex"] == null:
			continue
		var row := int(e["tab"])
		if row >= sharing.size() or not sharing[row]:
			e["tex"] = null
			EventBus.extra_feed_texture_changed.emit(slot, null)


## EventBus.feed_textures_requested (a room just built its screens): announce what is running.
func _resend() -> void:
	for slot: String in _slots:
		var tex := _texture_of(_slots[slot])
		if tex:
			EventBus.extra_feed_texture_changed.emit(slot, tex)


## The name in `names` that `want` means: the exact one, else the first that contains it
## (letter case ignored), else "".
static func match_name(want: String, names: PackedStringArray) -> String:
	if names.has(want):
		return want
	var low := want.to_lower()
	for n in names:
		if n.to_lower().contains(low):
			return n
	return ""


## NDI and Spout slots: connect the ones whose source is on the list now, drop the ones whose
## source left. Runs when a slot changes and whenever either list changes.
func _sync_named() -> void:
	for slot: String in _slots:
		var e: Dictionary = _slots[slot]
		match String(e["kind"]):
			"ndi":
				if _ndi == null or not NdiReceiver.is_available():
					continue
				var found := match_name(String(e["address"]), _ndi.get_source_names())
				if found == String(e["name"]):
					continue
				_drop_ndi(e)
				e["name"] = ""
				var p: VideoStreamPlayer = _ndi.make_player(found, self, AudioManager.VIDEO_BUS, true) if found != "" else null
				if p:
					p.volume_db = -80.0        # pictures only (the unpatched plugin would play its sound)
					p.play()
					e["name"] = found
					e["player"] = p
					e["size"] = Vector2i.ZERO
				EventBus.extra_feed_texture_changed.emit(slot, _texture_of(e))
			"spout":
				if _spout == null or not SpoutReceiver.is_available():
					continue
				var found := match_name(String(e["address"]), _spout.get_sender_names())
				if found == String(e["name"]):
					continue
				e["name"] = found
				e["tex"] = SpoutReceiver.make_texture(found) if found != "" else null
				e["size"] = Vector2i.ZERO
				DebugLog.note("spout", "%s %s" % [slot, ("receives " + found) if found != "" else "stops receiving"])
				EventBus.extra_feed_texture_changed.emit(slot, e["tex"])


func _drop_ndi(e: Dictionary) -> void:
	var p := e["player"] as VideoStreamPlayer
	if p:
		p.stop()
		p.queue_free()
	e["player"] = null


## Every frame: tell ScreenFeed when the tab feeds changed, start streams whose wait is over, show each stream's newest picture, and tell
## the room when an NDI or Spout picture changes size (its screen keeps the picture's shape).
func _process(delta: float) -> void:
	if _tabs_dirty:
		_tabs_dirty = false
		tab_wishes_changed.emit()
	for slot: String in _slots:
		var e: Dictionary = _slots[slot]
		match String(e["kind"]):
			"tab":
				# pictures stopped coming without the page saying so (it froze or was closed hard)
				if e["tex"] != null and Time.get_ticks_msec() / 1000.0 - float(e["last_s"]) > TAB_QUIET_S:
					e["tex"] = null
					EventBus.extra_feed_texture_changed.emit(slot, null)
			"stream":
				_process_stream(slot, e, delta)
			"ndi", "spout":
				var tex := _texture_of(e)
				var sz := Vector2i(tex.get_size()) if tex else Vector2i.ZERO
				if sz != e["size"] and sz.x > 0:
					e["size"] = sz
					EventBus.extra_feed_texture_changed.emit(slot, tex)


func _process_stream(slot: String, e: Dictionary, delta: float) -> void:
	var pipe := e["pipe"] as _Pipe
	if pipe == null:
		e["wait"] = float(e["wait"]) - delta
		if float(e["wait"]) > 0.0:
			return
		pipe = _Pipe.new()
		pipe.thread = Thread.new()
		pipe.thread.start(_read_stream.bind(pipe, _ffmpeg, _stream_args(String(e["address"]))))
		e["pipe"] = pipe
		return
	pipe.mutex.lock()
	var img := pipe.latest
	pipe.latest = null
	var first := img != null and e["tex"] == null
	var warn := pipe.failed == 2 and pipe.frames == 0      # said once, on the second try in a row
	if warn:
		pipe.failed += 1
	pipe.mutex.unlock()
	if warn:
		EventBus.status_message.emit("A small screen's stream address gives no picture yet. It keeps trying.", true)
	if img == null:
		return
	if first:
		e["tex"] = ImageTexture.create_from_image(img)
		DebugLog.note("extra feed", "%s: the stream's picture arrived" % slot)
		EventBus.extra_feed_texture_changed.emit(slot, e["tex"])
	else:
		(e["tex"] as ImageTexture).update(img)


## ffmpeg's arguments for a stream address: read it with as little delay as it allows, drop
## the sound, and write plain RGB pictures of STREAM_SIZE at STREAM_FPS to its standard output.
static func _stream_args(address: String) -> PackedStringArray:
	var args := PackedStringArray(["-hide_banner", "-loglevel", "quiet", "-nostats", "-nostdin"])
	var listen := address.begins_with("listen:")
	if listen:
		address = address.trim_prefix("listen:").strip_edges()
	if address.contains("://"):
		args.append_array(["-fflags", "nobuffer", "-flags", "low_delay", "-probesize", "500000", "-analyzeduration", "500000"])
		if address.begins_with("rtsp://"):
			args.append_array(["-rtsp_transport", "tcp"])      # UDP drops pictures on many home networks
		if listen:
			args.append_array(["-listen", "1"])
	else:
		args.append_array(["-re", "-stream_loop", "-1"])       # a file: at its own speed, round and round
	args.append_array(["-i", address, "-an", "-sn",
		"-vf", "fps=%d,scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2:black" \
			% [STREAM_FPS, STREAM_SIZE.x, STREAM_SIZE.y, STREAM_SIZE.x, STREAM_SIZE.y],
		"-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"])
	return args


## The reading thread: runs ffmpeg, reads one picture after another from its output and leaves
## the newest in pipe.latest. When ffmpeg ends (the stream stopped, the address is wrong) it
## waits RETRY_S and starts it again, until pipe.stop is set.
func _read_stream(pipe: _Pipe, ffmpeg: String, args: PackedStringArray) -> void:
	var frame_bytes := STREAM_SIZE.x * STREAM_SIZE.y * 3
	while true:
		pipe.mutex.lock()
		var stopping := pipe.stop
		pipe.mutex.unlock()
		if stopping:
			return
		var proc := OS.execute_with_pipe(ffmpeg, args)
		var out: FileAccess = proc.get("stdio")
		var got := 0
		if out:
			pipe.mutex.lock()
			pipe.pid = int(proc.get("pid", -1))
			stopping = pipe.stop
			pipe.mutex.unlock()
			if stopping:
				OS.kill(int(proc.get("pid", -1)))
			var buf := PackedByteArray()
			while true:
				# a pipe hands over what it has, which is often less than a whole picture
				var part := out.get_buffer(frame_bytes - buf.size())
				if part.is_empty():
					break            # ffmpeg ended (or was stopped)
				buf.append_array(part)
				if buf.size() < frame_bytes:
					continue
				var img := Image.create_from_data(STREAM_SIZE.x, STREAM_SIZE.y, false, Image.FORMAT_RGB8, buf)
				buf = PackedByteArray()
				got += 1
				pipe.mutex.lock()
				pipe.latest = img
				pipe.frames += 1
				pipe.failed = 0
				pipe.mutex.unlock()
			out.close()
			OS.kill(int(proc.get("pid", -1)))        # make sure it is gone (harmless if it already is)
		pipe.mutex.lock()
		pipe.pid = -1
		if got == 0:
			pipe.failed += 1
		pipe.mutex.unlock()
		var waited := 0.0
		while waited < RETRY_S:
			pipe.mutex.lock()
			stopping = pipe.stop
			pipe.mutex.unlock()
			if stopping:
				return
			OS.delay_msec(100)
			waited += 0.1


## Stops a stream: flags the thread, kills the ffmpeg it is reading (which ends the read) and
## waits for the thread.
func _end_pipe(pipe: _Pipe) -> void:
	if pipe == null:
		return
	pipe.mutex.lock()
	pipe.stop = true
	var pid := pipe.pid
	pipe.mutex.unlock()
	if pid > 0:
		OS.kill(pid)
	pipe.thread.wait_to_finish()


## Where ffmpeg is: the tools folder beside the exe, the project's tools folder, or the PATH
## (the same places as VideoLoader._find_tool: keep the two in step). "" = not found.
func _find_ffmpeg() -> String:
	if _ffmpeg_looked:
		return _ffmpeg
	_ffmpeg_looked = true
	var exe := "ffmpeg" + (".exe" if OS.get_name() == "Windows" else "")
	for d: String in [OS.get_executable_path().get_base_dir().path_join("tools"), ProjectSettings.globalize_path("res://tools")]:
		if FileAccess.file_exists(d.path_join(exe)):
			_ffmpeg = d.path_join(exe)
			return _ffmpeg
	if OS.execute("ffmpeg", PackedStringArray(["-version"]), []) == 0:
		_ffmpeg = "ffmpeg"
	return _ffmpeg
