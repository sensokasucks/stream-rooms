class_name ScreenFeed
extends Node
## Owns whatever is shown on the screen, whichever room is loaded.
## Sources:
##   file    - local file / URL via VideoLoader + VideoStreamPlayer (Theora)
##   capture - browser tab via CaptureServer (JPEG frames + float PCM audio)
##   ndi     - an NDI source (OBS / NDI Tools) via NdiReceiver (optional godot-ndi extension)
##   spout   - a Spout sender on this PC via SpoutReceiver (optional godot-spout extension; picture only)
## A capture connection takes over from a playing file (not from NDI / Spout, which you pick on purpose).
## Presenters can also show NDI sources and Spout senders (presenter sources "ndi" / "spout").
## Publishes: EventBus.screen_texture_changed, screen_colors_changed,
## webcam_texture_changed, and AppState source / playback state.

const IDLE_COLOR: Color = Color(0.06, 0.08, 0.16)
const MAX_VIDEO_QUEUE: int = 90
## Streaming together: a synced video further than this from the host's position jumps to it.
const SYNC_TOLERANCE_S: float = 0.3
## ...and doesn't jump again for this long (a jump itself takes a moment to settle).
const SYNC_COOLDOWN_S: float = 1.5
## Extra audio kept beyond the target delay before old chunks are dropped (drift guard).
const AUDIO_SLACK_S: float = 0.35
## NDI sound (patched plugin): how much audio to keep queued for the sound card. It grows when
## the sound card runs dry (a hitch) and shrinks back slowly while things are calm.
const NDI_AUDIO_TARGET_MIN: float = 0.05
const NDI_AUDIO_TARGET_MAX: float = 1.5
## Sound left in the NDI frame-sync on purpose, because its queue depth is only approximate.
const NDI_QUEUE_MARGIN_S: float = 0.02

@export var capture_server: CaptureServer
@export var video_loader: Node          # core/video_loader.gd
@export var video_player: VideoStreamPlayer
@export var stream_audio_player: AudioStreamPlayer
@export var sample_rate_hz: float = 20.0

var _capture_texture: ImageTexture
var _webcam_texture: ImageTexture
var _gen_playback: AudioStreamGeneratorPlayback
var _audio_queue: Array = []        # [[recv_time_s, PackedVector2Array], ...]
var _video_queue: Array = []        # [[recv_time_s, Image, Array[Color]], ...]
var _sample_timer: float = 0.0
var _file_path: String = ""
var _last_capture_frame_s: float = -1000.0
var _webcam_last_s: float = -1000.0
var _presenter_textures: Dictionary = {}   # slot -> ImageTexture
var _presenter_last_s: Dictionary = {}     # presenter -> time of the last frame
var _presenter_live: Dictionary = {}       # presenter -> sender page says its feed is running
var _room_presenters: int = 0              # podiums in the current room
var _sender_was_connected: bool = false
var _ndi: NdiReceiver
var _gpu_sampler: GpuFrameSampler
var _ndi_pull: bool = false                 # main NDI sound pulled into StreamAudio (patched plugin)
var _ndi_gen_capacity: int = 0
var _ndi_target_s: float = 0.5
var _ndi_skips: int = 0
var _ndi_buffering: bool = false
var _ndi_buffer_apply_in: float = -1.0
var _ndi_padded: int = 0                    # pulls that came back with silence added at the end
var _ndi_dry_net: int = 0                   # sound ran dry while NDI had nothing ready (network / OBS)
var _ndi_dry_game: int = 0                  # sound ran dry after a slow game frame
var _ndi_late_s: float = 1000.0             # time since the last slow game frame
var _hitch_count: int = 0
var _hitch_worst: float = 0.0
var _hitch_report_in: float = 10.0
var _ndi_player: VideoStreamPlayer          # main screen
var _ndi_name: String = ""
var _ndi_size: Vector2i = Vector2i.ZERO
var _ndi_presenters: Dictionary = {}        # presenter -> {"name", "player", "size"}
var _prepare_input: String = ""            # loading to stop on the first frame (streaming together)
var _sync_cooldown: float = 0.0
var _progress_wait: float = 0.0
var _progress_playing: bool = false
var _spout: SpoutReceiver
var _spout_tex: Texture2D                   # main screen (a SpoutTexture: updates itself every frame)
var _spout_name: String = ""
var _spout_size: Vector2i = Vector2i.ZERO
var _spout_presenters: Dictionary = {}      # presenter -> {"name", "tex", "size"}


func _ready() -> void:
	video_player.bus = AudioManager.VIDEO_BUS
	video_player.finished.connect(_on_file_finished)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 48000.0
	gen.buffer_length = 2.0
	stream_audio_player.stream = gen
	stream_audio_player.bus = AudioManager.VIDEO_BUS

	video_loader.status.connect(func(m: String) -> void: EventBus.status_message.emit(m, false))
	video_loader.failed.connect(_on_loader_failed)
	video_loader.ready_to_play.connect(_play_file)

	capture_server.video_frame_ready.connect(_on_capture_frame)
	capture_server.webcam_frame_ready.connect(_on_webcam_frame)
	capture_server.presenter_frame_ready.connect(_on_presenter_frame)
	capture_server.audio_received.connect(_on_capture_audio)
	capture_server.sender_status_changed.connect(_on_sender_status)
	capture_server.start(AppState.get_capture_port("capture_http_port"), AppState.get_capture_port("capture_ws_port"))

	EventBus.file_play_requested.connect(_on_file_play_requested)
	EventBus.file_prepare_requested.connect(_on_file_prepare_requested)
	EventBus.file_sync_requested.connect(_on_file_sync_requested)
	EventBus.file_stop_requested.connect(stop_file)
	EventBus.file_pause_toggle_requested.connect(_on_file_pause_toggle)
	EventBus.react_pause_changed.connect(_on_react_pause_changed)
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.room_presenters_changed.connect(_on_room_presenters)

	_gpu_sampler = GpuFrameSampler.new()
	_gpu_sampler.name = "GpuFrameSampler"
	add_child(_gpu_sampler)

	_ndi = NdiReceiver.new()
	_ndi.name = "NdiReceiver"
	add_child(_ndi)
	EventBus.ndi_sources_changed.connect(_on_ndi_sources)
	EventBus.ndi_connect_requested.connect(start_ndi)

	_spout = SpoutReceiver.new()
	_spout.name = "SpoutReceiver"
	add_child(_spout)
	EventBus.spout_senders_changed.connect(_on_spout_senders)
	EventBus.spout_connect_requested.connect(start_spout)
	EventBus.spout_stop_requested.connect(stop_spout)
	EventBus.ndi_stop_requested.connect(stop_ndi)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_flush_video(now)
	_flush_audio(now)
	var sampled := _sampled_texture()
	if sampled:
		_sample_timer -= delta
		if _sample_timer <= 0.0:
			_sample_timer = 1.0 / sample_rate_hz
			_sample_frame(sampled)
	_watch_ndi_sizes()
	_watch_spout_sizes()
	_report_progress(delta)
	_watch_hitches(delta)
	_pump_ndi_audio(delta)
	if _webcam_texture and now - _webcam_last_s > 2.0:
		_webcam_texture = null
		EventBus.webcam_texture_changed.emit(null)
	for n: int in _presenter_textures.keys():
		# A quiet tab sends no new frames (the sender re-sends the last one every second), so
		# trust the sender's status and only give up after a long silence.
		var limit := 15.0 if bool(_presenter_live.get(n, false)) else 3.0
		if now - float(_presenter_last_s.get(n, 0.0)) > limit:
			_clear_presenter(n)
	_update_playback_active(now)


# ── Public API ───────────────────────────────────────────────
func get_texture() -> Texture2D:
	match AppState.get_source_mode():
		"file": return video_player.get_video_texture()
		"capture": return _capture_texture
		"ndi": return _ndi_player.get_video_texture() if _ndi_player else null
		"spout": return _spout_tex
	return null


func get_capture_url() -> String:
	return capture_server.get_sender_url()


func stop_file() -> void:
	if AppState.get_source_mode() != "file":
		return
	video_player.stop()
	_file_path = ""
	_set_source("none")


# ── File source ──────────────────────────────────────────────
func _on_file_play_requested(input: String) -> void:
	if AppState.get_source_mode() == "capture":
		EventBus.status_message.emit("A browser tab is being shared - stop sharing in the browser first.", true)
		return
	if not AppState.net_allows("video", input):
		return          # streaming together: the session loads it on every PC instead
	_prepare_input = ""
	stop_ndi()
	stop_spout()
	video_loader.max_height = AppState.get_setting("max_height")
	video_loader.request(input)


## Streaming together: like a play request, but it stops on the first frame (see _play_file).
func _on_file_prepare_requested(input: String) -> void:
	stop_ndi()
	stop_spout()
	_prepare_input = input
	video_loader.max_height = AppState.get_setting("max_height")
	video_loader.request(input)


func _on_loader_failed(message: String) -> void:
	EventBus.status_message.emit(message, true)
	if _prepare_input != "":
		var input := _prepare_input
		_prepare_input = ""
		EventBus.file_prepare_failed.emit(input, message)


func _play_file(path: String) -> void:
	var stream := VideoStreamTheora.new()
	stream.file = path
	video_player.stream = stream
	video_player.paused = false
	video_player.play()
	if not video_player.is_playing():
		EventBus.status_message.emit("Couldn't play %s (needs to be Ogg Theora .ogv)." % path.get_file(), true)
		if _prepare_input != "":
			_on_loader_failed("Couldn't play the converted video.")
		return
	_file_path = path
	_set_source("file")
	EventBus.screen_texture_changed.emit(video_player.get_video_texture())
	if _prepare_input != "":
		# streaming together: wait on the first frame until the host starts everyone at once
		video_player.paused = true
		video_player.stream_position = 0.0
		var input := _prepare_input
		_prepare_input = ""
		EventBus.status_message.emit("%s is ready; waiting for everyone else." % path.get_file(), false)
		EventBus.file_prepared.emit(input)
		return
	EventBus.status_message.emit("Playing %s" % path.get_file(), false)


## Streaming together: follow the host. Small differences are left alone; a jump is followed by
## a short pause in corrections so it can settle.
func _on_file_sync_requested(position: float, playing: bool) -> void:
	if AppState.get_source_mode() != "file" or not video_player.is_playing():
		return
	var length := video_player.get_stream_length()
	var target := clampf(position, 0.0, length - 0.05) if length > 0.0 else maxf(position, 0.0)
	if absf(video_player.stream_position - target) > SYNC_TOLERANCE_S and _sync_cooldown <= 0.0:
		video_player.stream_position = target
		_sync_cooldown = SYNC_COOLDOWN_S
	video_player.paused = not playing


## About once a second, and right away when it pauses or resumes: where the file is.
func _report_progress(delta: float) -> void:
	_sync_cooldown = maxf(_sync_cooldown - delta, 0.0)
	if AppState.get_source_mode() != "file" or not video_player.is_playing():
		return
	var playing := not video_player.paused
	_progress_wait -= delta
	if _progress_wait > 0.0 and playing == _progress_playing:
		return
	_progress_wait = 1.0
	_progress_playing = playing
	EventBus.file_progress.emit(video_player.stream_position, playing)


func _on_file_finished() -> void:
	if AppState.get_setting("loop_files") and _file_path != "":
		video_player.play()
	else:
		stop_file()


func _on_file_pause_toggle() -> void:
	if AppState.get_source_mode() == "file" and video_player.is_playing():
		video_player.paused = not video_player.paused


## The picture on the screen, when the room colours should follow it.
func _sampled_texture() -> Texture2D:
	match AppState.get_source_mode():
		"file":
			if video_player.is_playing() and not video_player.paused:
				return video_player.get_video_texture()
		"ndi":
			if _ndi_player and _ndi_player.is_playing():
				return _ndi_player.get_video_texture()
		"spout":
			if _spout_tex and _spout_size.x > 0:
				return _spout_tex
	return null


func _sample_frame(tex: Texture2D) -> void:
	# the GPU shrinks the frame first: only a 36x20 image is read back, not the whole picture
	var c := _gpu_sampler.sample(tex)
	if c.size() == 3:
		EventBus.screen_colors_changed.emit(c[0], c[1], c[2])


# ── Capture source ───────────────────────────────────────────
func _on_capture_frame(img: Image, colors: Array[Color]) -> void:
	_video_queue.append([Time.get_ticks_msec() / 1000.0, img, colors])
	while _video_queue.size() > MAX_VIDEO_QUEUE:
		_video_queue.pop_front()


func _flush_video(now: float) -> void:
	var delay: float = float(AppState.get_setting("video_delay_ms")) / 1000.0
	var latest: Array = []
	while not _video_queue.is_empty() and now - float(_video_queue[0][0]) >= delay:
		latest = _video_queue.pop_front()
	if latest.is_empty():
		return
	var img: Image = latest[1]
	var colors: Array[Color] = latest[2]
	if AppState.get_source_mode() == "ndi" or AppState.get_source_mode() == "spout":
		return          # NDI / Spout was picked on purpose: a browser share doesn't take over
	if AppState.get_source_mode() != "capture":
		if AppState.get_source_mode() == "file":
			video_player.stop()
			_file_path = ""
		_set_source("capture")
	var new_tex := _capture_texture == null or Vector2i(_capture_texture.get_size()) != img.get_size()
	if new_tex:
		_capture_texture = ImageTexture.create_from_image(img)
		EventBus.screen_texture_changed.emit(_capture_texture)
	else:
		_capture_texture.update(img)
	_last_capture_frame_s = now
	if colors.size() == 3:
		EventBus.screen_colors_changed.emit(colors[0], colors[1], colors[2])


func _on_capture_audio(frames: PackedVector2Array) -> void:
	if AppState.get_source_mode() == "ndi":
		return
	if not stream_audio_player.playing:
		stream_audio_player.play()
		_gen_playback = stream_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_audio_queue.append([Time.get_ticks_msec() / 1000.0, frames])


func _flush_audio(now: float) -> void:
	if _gen_playback == null:
		return
	var delay: float = float(AppState.get_setting("audio_delay_ms")) / 1000.0
	# Drift guard: if we're holding far more than the target delay, drop the oldest.
	while not _audio_queue.is_empty() and now - float(_audio_queue[0][0]) > delay + AUDIO_SLACK_S:
		_audio_queue.pop_front()
	while not _audio_queue.is_empty() and now - float(_audio_queue[0][0]) >= delay:
		var frames: PackedVector2Array = _audio_queue[0][1]
		if not _gen_playback.can_push_buffer(frames.size()):
			break
		_gen_playback.push_buffer(frames)
		_audio_queue.pop_front()


func _on_webcam_frame(img: Image) -> void:
	_webcam_last_s = Time.get_ticks_msec() / 1000.0
	if _webcam_texture == null or Vector2i(_webcam_texture.get_size()) != img.get_size():
		_webcam_texture = ImageTexture.create_from_image(img)
		EventBus.webcam_texture_changed.emit(_webcam_texture)
	else:
		_webcam_texture.update(img)


## slot is the sender's 0-based feed slot; presenters are numbered from 1.
func _on_presenter_frame(slot: int, img: Image) -> void:
	var n := slot + 1
	_presenter_last_s[n] = Time.get_ticks_msec() / 1000.0
	var tex: ImageTexture = _presenter_textures.get(n)
	if tex == null or Vector2i(tex.get_size()) != img.get_size():
		tex = ImageTexture.create_from_image(img)
		_presenter_textures[n] = tex
		EventBus.presenter_texture_changed.emit(n, tex)
	else:
		tex.update(img)


func _clear_presenter(n: int) -> void:
	if _presenter_textures.has(n):
		_presenter_textures.erase(n)
		EventBus.presenter_texture_changed.emit(n, null)


## Tells the sender page which presenter feeds to run: camera (started automatically),
## tab (the page asks you to pick one) or off. Only while the room has podiums.
func _sync_presenter_feeds() -> void:
	var slots: Array = []
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var kind := "off"
		if n <= _room_presenters and bool(AppState.get_setting(AppState.presenter_key(n, "on"))):
			var src := String(AppState.get_setting(AppState.presenter_key(n, "source")))
			if src == "camera" or src == "tab" or src == "web":
				kind = src
		var key_color: Color = AppState.get_setting(AppState.presenter_key(n, "key_color"))
		slots.append({"kind": kind, "device": String(AppState.get_setting(AppState.presenter_key(n, "camera"))),
			"url": String(AppState.get_setting(AppState.presenter_key(n, "url"))), "bg": key_color.to_html(false)})
	capture_server.send_to_sender({"type": "presenters", "slots": slots})


func _on_room_presenters(count: int) -> void:
	_room_presenters = count
	_sync_presenter_feeds()
	_sync_ndi_presenters()
	_sync_spout_presenters()


func _on_sender_status(info: Dictionary) -> void:
	var status := info.duplicate()
	status["connected"] = capture_server.is_connected_to_sender()
	if status["connected"] and not _sender_was_connected:
		_sync_presenter_feeds.call_deferred()
	_sender_was_connected = bool(status["connected"])
	var feeds: Array = info.get("presenters", []) if info.get("presenters") is Array else []
	for i in AppState.PRESENTER_COUNT:
		var live := bool(status["connected"]) and i < feeds.size() and feeds[i] is Dictionary and bool(feeds[i].get("active", false))
		_presenter_live[i + 1] = live
		if not live:
			_clear_presenter(i + 1)
	status["fps"] = capture_server.get_fps()
	status["url"] = capture_server.get_sender_url()
	EventBus.capture_status_changed.emit(status)
	var capturing: bool = bool(info.get("capturing", false))
	if (not status["connected"] or not capturing) and AppState.get_source_mode() == "capture":
		_video_queue.clear()
		_audio_queue.clear()
		stream_audio_player.stop()
		_gen_playback = null
		_capture_texture = null
		_set_source("none")


# ── Reaction pause ───────────────────────────────────────────
func _on_react_pause_changed(paused: bool) -> void:
	match AppState.get_source_mode():
		"file":
			video_player.paused = paused
		"capture", "ndi", "spout":
			# The game can't confirm the browser obeyed, so report what was sent.
			if SystemMedia.send_play_pause():
				EventBus.status_message.emit("Sent Play/Pause to the browser.", false)
			else:
				EventBus.status_message.emit("Couldn't send the Play/Pause key - pause the video in the browser.", true)


# ── Private ──────────────────────────────────────────────────
func _set_source(mode: String) -> void:
	AppState.set_source_mode(mode)
	if mode == "none":
		AppState.set_react_paused(false)
		EventBus.screen_texture_changed.emit(null)
		EventBus.screen_colors_changed.emit(IDLE_COLOR, IDLE_COLOR, IDLE_COLOR)


func _update_playback_active(now: float) -> void:
	var active := false
	match AppState.get_source_mode():
		"file": active = video_player.is_playing() and not video_player.paused
		"capture": active = now - _last_capture_frame_s < 1.0 and not AppState.is_react_paused()
		"ndi": active = _ndi_player != null and _ndi_player.is_playing() and not AppState.is_react_paused()
		"spout": active = _spout_tex != null and not AppState.is_react_paused()
	AppState.set_playback_active(active)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("presenter_") and (key.ends_with("_on") or key.ends_with("_source") or key.ends_with("_camera")
			or key.ends_with("_url") or key.ends_with("_key_color")):
		_sync_presenter_feeds()
	if key.begins_with("presenter_") and (key.ends_with("_on") or key.ends_with("_source") or key.ends_with("_ndi")):
		_sync_ndi_presenters()
	if key.begins_with("presenter_") and (key.ends_with("_on") or key.ends_with("_source") or key.ends_with("_spout")):
		_sync_spout_presenters()
	if key == "ndi_audio_buffer_ms":
		_ndi_buffer_apply_in = 0.4     # apply once the slider stops moving
	if key == "capture_http_port" or key == "capture_ws_port":
		capture_server.start(AppState.get_capture_port("capture_http_port"), AppState.get_capture_port("capture_ws_port"))


func _apply_ndi_buffer_setting() -> void:
	if _ndi_pull and _gen_playback:
		var old := _ndi_target_s
		_ndi_target_s = _ndi_buffer_setting_s()
		if _ndi_target_s > old + 0.01:
			_ndi_rebuffer()     # fill up to the new size
		elif _ndi_target_s < old - 0.01:
			_gen_playback.clear_buffer()     # drop the extra delay right away
			_ndi_rebuffer()



# ── NDI source ───────────────────────────────────────────────
## Shows an NDI source on the main screen (stops a playing file). Its sound goes through the
## same bus as the other sources (volume, ducking, room acoustics).
func start_ndi(source_name: String) -> void:
	if source_name == "":
		return
	if not NdiReceiver.is_available():
		EventBus.status_message.emit("NDI isn't available: the godot-ndi plugin didn't load (addons/godot-ndi).", true)
		return
	if _ndi_player and _ndi_name == source_name and _ndi_player.is_playing():
		return
	_stop_ndi_player()
	stop_spout()
	var pull := NdiReceiver.supports_pull_audio()
	var p := _ndi.make_player(source_name, self, AudioManager.VIDEO_BUS, pull)
	if p == null:
		EventBus.status_message.emit("NDI source \"%s\" isn't on the network right now." % source_name, true)
		return
	_ndi_pull = pull
	if pull:
		_start_ndi_audio()
	AppState.set_setting("ndi_source", source_name)
	if AppState.get_source_mode() == "file":
		video_player.stop()
		_file_path = ""
	_ndi_player = p
	_ndi_name = source_name
	_ndi_size = Vector2i.ZERO
	p.play()     # the plugin blocks here until the first frame arrives (short, the source was just found)
	_set_source("ndi")
	EventBus.screen_texture_changed.emit(p.get_video_texture())
	EventBus.status_message.emit("Showing NDI source %s" % source_name, false)


func stop_ndi() -> void:
	if _ndi_player == null:
		return
	_stop_ndi_player()
	if AppState.get_source_mode() == "ndi":
		_set_source("none")


func get_ndi_source() -> String:
	return _ndi_name if _ndi_player else ""


func _stop_ndi_player() -> void:
	if _ndi_player:
		_ndi_player.stop()
		_ndi_player.queue_free()
	_ndi_player = null
	_ndi_name = ""
	if _ndi_pull and _gen_playback:
		_gen_playback.clear_buffer()
	if _ndi_pull:
		stream_audio_player.stream_paused = false
	_ndi_pull = false
	_ndi_buffering = false


## Patched plugin: the NDI sound goes through StreamAudio (the browser path's AudioStreamGenerator,
## unused while NDI is on). Each frame it is topped up to a target level, so the NDI frame-sync
## is pulled exactly as fast as the sound card plays - no drift, and game hitches only use up slack.
func _start_ndi_audio() -> void:
	_audio_queue.clear()
	if not stream_audio_player.playing:
		stream_audio_player.play()
	_gen_playback = stream_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_gen_playback.clear_buffer()
	_ndi_gen_capacity = _gen_playback.get_frames_available()
	_ndi_target_s = _ndi_buffer_setting_s()
	_ndi_rebuffer()


## "NDI sound buffer" setting in seconds (Source tab).
func _ndi_buffer_setting_s() -> float:
	return clampf(float(AppState.get_setting("ndi_audio_buffer_ms")) / 1000.0, NDI_AUDIO_TARGET_MIN, NDI_AUDIO_TARGET_MAX)


## Hold the sound until the buffer is full again, so there really is target_s of sound queued
## (without this the buffer only ever holds what happened to pile up).
func _ndi_rebuffer() -> void:
	_ndi_buffering = true
	stream_audio_player.stream_paused = true


## Each frame: take whatever NDI sound has arrived, up to the target. While (re)buffering the
## sound is held until the buffer is full; after that the sound card plays it at its own pace
## and the buffer only empties if the NDI stream stops delivering for longer than the buffer.
func _pump_ndi_audio(delta: float) -> void:
	if _ndi_buffer_apply_in > 0.0:
		_ndi_buffer_apply_in -= delta
		if _ndi_buffer_apply_in <= 0.0:
			_apply_ndi_buffer_setting()
	if not _ndi_pull or _ndi_player == null or _gen_playback == null:
		return
	var rate := int((stream_audio_player.stream as AudioStreamGenerator).mix_rate)
	var target := int(rate * _ndi_target_s)
	var stream: Object = _ndi_player.stream
	var queued := _ndi_gen_capacity - _gen_playback.get_frames_available()
	# never ask for more than has arrived (the frame-sync pads with silence), and leave a little
	# behind: the reported queue depth is only approximate
	var depth := int(stream.call("get_audio_queue_depth")) - int(rate * NDI_QUEUE_MARGIN_S)
	var want := mini(target - queued, depth)
	if want > 0:
		var chunk: PackedVector2Array = _trim_ndi_padding(stream.call("pull_audio", want, rate))
		_gen_playback.push_buffer(chunk)
		queued += chunk.size()
	_ndi_late_s = 0.0 if delta > 0.05 else _ndi_late_s + delta
	if _ndi_buffering:
		if queued >= int(target * 0.95):
			_ndi_buffering = false
			stream_audio_player.stream_paused = false
			_ndi_skips = _gen_playback.get_skips()
		return
	var skips := _gen_playback.get_skips()
	if skips != _ndi_skips:
		# the sound card ran dry: the buffer emptied. Refill it before playing on.
		_ndi_skips = skips
		if _ndi_late_s < 0.3:
			_ndi_dry_game += 1
		else:
			_ndi_dry_net += 1
		_ndi_rebuffer()


func _on_ndi_sources(names: PackedStringArray, _available: bool) -> void:
	# the source went away (OBS closed...): let go, so it reconnects when it comes back
	if _ndi_player and not names.has(_ndi_name):
		EventBus.status_message.emit("NDI source %s went away." % _ndi_name, true)
		stop_ndi()
	# reconnect to the last source when it (re)appears and nothing else is on the screen
	var last := String(AppState.get_setting("ndi_source"))
	if bool(AppState.get_setting("ndi_auto")) and names.has(last) and AppState.get_source_mode() == "none":
		start_ndi.call_deferred(last)
	_sync_ndi_presenters()


## The NDI picture size is only known once frames arrive (and can change): tell the screen /
## presenters again when it does, so aspect ratios stay right.
func _watch_ndi_sizes() -> void:
	if _ndi_player and AppState.get_source_mode() == "ndi":
		var tex := _ndi_player.get_video_texture()
		var sz := Vector2i(tex.get_size()) if tex else Vector2i.ZERO
		if sz != _ndi_size and sz.x > 0:
			_ndi_size = sz
			EventBus.screen_texture_changed.emit(tex)
	for n: int in _ndi_presenters.keys():
		var e: Dictionary = _ndi_presenters[n]
		var tex: Texture2D = (e["player"] as VideoStreamPlayer).get_video_texture()
		var sz := Vector2i(tex.get_size()) if tex else Vector2i.ZERO
		if sz != e["size"] and sz.x > 0:
			e["size"] = sz
			EventBus.presenter_texture_changed.emit(n, tex)


## Presenters set to "NDI source": one player each, while on set in a room with podiums.
func _sync_ndi_presenters() -> void:
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var want := ""
		if n <= _room_presenters and bool(AppState.get_setting(AppState.presenter_key(n, "on"))) \
				and String(AppState.get_setting(AppState.presenter_key(n, "source"))) == "ndi":
			want = String(AppState.get_setting(AppState.presenter_key(n, "ndi")))
		var cur: Dictionary = _ndi_presenters.get(n, {})
		if not cur.is_empty() and String(cur["name"]) == want and _ndi.has_source(want):
			continue
		if not cur.is_empty():
			(cur["player"] as VideoStreamPlayer).stop()
			(cur["player"] as VideoStreamPlayer).queue_free()
			_ndi_presenters.erase(n)
			EventBus.presenter_texture_changed.emit(n, null)
		if want == "" or not _ndi.has_source(want):
			continue
		var p := _ndi.make_player(want, self, AudioManager.VIDEO_BUS, true)   # true: no sound from the player
		if p == null:
			continue
		p.volume_db = -80.0      # presenter pictures only; their voices come through your stream mix (unpatched plugin)
		p.play()
		_ndi_presenters[n] = {"name": want, "player": p, "size": Vector2i.ZERO}
		EventBus.presenter_texture_changed.emit(n, p.get_video_texture())


## The NDI plugin pulls its sound once per game frame, so a late frame can make it crackle.
## While NDI is on, count frames that take much longer than usual and report them every 10 s
## in the Output log, to line up crackles with game stalls.
func _watch_hitches(delta: float) -> void:
	if AppState.get_source_mode() != "ndi":
		_hitch_count = 0
		_hitch_worst = 0.0
		_hitch_report_in = 10.0
		return
	if delta > 0.05:
		_hitch_count += 1
		_hitch_worst = maxf(_hitch_worst, delta)
	_hitch_report_in -= delta
	if _hitch_report_in <= 0.0:
		if _hitch_count > 0:
			push_warning("NDI: %d slow frame(s) in the last 10 s (longest %d ms). NDI sound can crackle when a frame is late." \
				% [_hitch_count, roundi(_hitch_worst * 1000.0)])
		if _ndi_dry_net + _ndi_dry_game > 0:
			push_warning(("NDI sound ran out %d time(s) in the last 10 s even with a %d ms buffer: %d while the game was " \
				+ "running smoothly (the NDI stream stopped delivering: network / OBS side), %d after a slow game frame. " \
				+ "It paused to refill the buffer each time.") \
				% [_ndi_dry_net + _ndi_dry_game, roundi(_ndi_target_s * 1000.0), _ndi_dry_net, _ndi_dry_game])
		if _ndi_padded > 0:
			push_warning(("NDI: %d time(s) in the last 10 s the NDI plugin handed over sound with silence padded " \
				+ "on the end (it had less sound ready than it reported). The padding was cut out.") % _ndi_padded)
		_ndi_dry_net = 0
		_ndi_dry_game = 0
		_ndi_padded = 0
		_hitch_count = 0
		_hitch_worst = 0.0
		_hitch_report_in = 10.0


## A pull that ends in a run of exact digital silence after real sound means the frame-sync padded
## it (it had less than it reported). Real quiet audio is almost never exactly 0.0. The padding is
## cut off, so the sound carries on seamlessly with the next pull instead of clicking.
func _trim_ndi_padding(chunk: PackedVector2Array) -> PackedVector2Array:
	var n := chunk.size()
	if n < 64:
		return chunk
	var i := n - 1
	while i >= 0 and chunk[i] == Vector2.ZERO:
		i -= 1
	if n - 1 - i >= 32 and i >= 0:
		_ndi_padded += 1
		return chunk.slice(0, i + 1)
	return chunk


# ── Spout source ─────────────────────────────────────────────
## Shows a Spout sender on the main screen (stops a file or NDI). Spout carries no sound: the
## program's sound reaches the stream the way it already does (OBS, desktop audio).
func start_spout(sender_name: String) -> void:
	if sender_name == "":
		return
	if not SpoutReceiver.is_available():
		EventBus.status_message.emit("Spout isn't available: the godot-spout plugin didn't load (addons/godot-spout).", true)
		return
	if _spout_tex and _spout_name == sender_name:
		return
	_spout.refresh()
	if not _spout.has_sender(sender_name):
		EventBus.status_message.emit("Spout sender \"%s\" isn't running right now." % sender_name, true)
		return
	_stop_spout_texture()
	stop_ndi()
	if AppState.get_source_mode() == "file":
		video_player.stop()
		_file_path = ""
	_spout_tex = SpoutReceiver.make_texture(sender_name)
	_spout_name = sender_name
	_spout_size = Vector2i.ZERO
	AppState.set_setting("spout_source", sender_name)
	_set_source("spout")
	EventBus.screen_texture_changed.emit(_spout_tex)
	EventBus.status_message.emit("Showing Spout sender %s" % sender_name, false)


func stop_spout() -> void:
	if _spout_tex == null:
		return
	_stop_spout_texture()
	if AppState.get_source_mode() == "spout":
		_set_source("none")


func get_spout_sender() -> String:
	return _spout_name if _spout_tex else ""


func _stop_spout_texture() -> void:
	_spout_tex = null       # (freed with its last reference; the extension stops receiving then)
	_spout_name = ""
	_spout_size = Vector2i.ZERO


func _on_spout_senders(names: PackedStringArray, _available: bool) -> void:
	if _spout_tex and not names.has(_spout_name):
		EventBus.status_message.emit("Spout sender %s went away." % _spout_name, true)
		stop_spout()
	var last := String(AppState.get_setting("spout_source"))
	if bool(AppState.get_setting("spout_auto")) and names.has(last) and AppState.get_source_mode() == "none":
		start_spout.call_deferred(last)
	_sync_spout_presenters()


## The screen keeps its shape: tell it again when the sender's picture size changes
## (the texture is empty until the first frame arrives).
func _watch_spout_sizes() -> void:
	if _spout_tex and AppState.get_source_mode() == "spout":
		var sz := Vector2i(_spout_tex.get_size())
		if sz != _spout_size and sz.x > 0:
			_spout_size = sz
			EventBus.screen_texture_changed.emit(_spout_tex)
	for n: int in _spout_presenters.keys():
		var e: Dictionary = _spout_presenters[n]
		var tex: Texture2D = e["tex"]
		var sz := Vector2i(tex.get_size())
		if sz != e["size"] and sz.x > 0:
			e["size"] = sz
			EventBus.presenter_texture_changed.emit(n, tex)


func _sync_spout_presenters() -> void:
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var want := ""
		if n <= _room_presenters and bool(AppState.get_setting(AppState.presenter_key(n, "on"))) \
				and String(AppState.get_setting(AppState.presenter_key(n, "source"))) == "spout":
			want = String(AppState.get_setting(AppState.presenter_key(n, "spout")))
		var cur: Dictionary = _spout_presenters.get(n, {})
		if not cur.is_empty() and String(cur["name"]) == want and _spout.has_sender(want):
			continue
		if not cur.is_empty():
			_spout_presenters.erase(n)
			EventBus.presenter_texture_changed.emit(n, null)
		if want == "" or not _spout.has_sender(want):
			continue
		var tex := SpoutReceiver.make_texture(want)
		if tex == null:
			continue
		_spout_presenters[n] = {"name": want, "tex": tex, "size": Vector2i.ZERO}
