extends Node
## "What's going on" (review batch 3): messages go to the panel's message line instead of the
## captured picture (unless "Show messages on the picture" is ticked), the status strip above the
## tabs (Core / Big screen / Together), the "On the big screen now" line, NDI / Spout status out
## of the folds, the video download status line with plain-language errors and Try again, and
## Together's join popup in its own window while the panel is docked.
##   <redot console exe> --path . _tests/test_status_line.tscn -- C:/temp/sr_tests --mp-profile=test

const VIDEO_LOADER := preload("res://core/video_loader.gd")

var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", true)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("messages_on_picture", false)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(2.0)
	var panel: Node = main.get_node("ControlPanel")
	var overlay: Node = main.get_node("Overlay")

	# messages: the panel line, not the picture
	EventBus.status_message.emit("Something went wrong here.", true)
	await get_tree().process_frame
	_check(String(panel._msg_btn.text).contains("Something went wrong here."), "the message shows on the panel's message line (%s)" % panel._msg_btn.text)
	_check(not (overlay._toast as Label).visible, "and not on the room picture (Show messages on the picture is off by default)")
	for i in 14:
		EventBus.status_message.emit("Message %d" % i, false)
	_check((panel._messages as Array).size() == panel.MESSAGE_HISTORY and String(panel._messages[0]["text"]) == "Message 13",
		"the last %d messages are kept, newest first" % panel.MESSAGE_HISTORY)
	AppState.set_setting("messages_on_picture", true)
	EventBus.status_message.emit("Now on the picture too.", false)
	_check((overlay._toast as Label).visible, "with the tick on, a message also shows on the picture")
	AppState.set_setting("messages_on_picture", false)
	_check(not (overlay._toast as Label).visible, "turning the tick off hides it at once")

	# the status strip, on every tab
	var strip: Dictionary = panel._strip
	_check(strip.has("core") and strip.has("screen") and strip.has("together"), "the status strip has Core, Big screen and Together")
	_check(not (panel._tabs as TabContainer).is_ancestor_of(strip["core"]), "the strip sits outside the tabs (visible on every tab)")
	_check(String((strip["core"] as Button).text).contains("not connected"), "Core shows as not connected (%s)" % (strip["core"] as Button).text)
	_check(String((strip["screen"] as Button).text).contains("empty"), "the big screen shows as empty (%s)" % (strip["screen"] as Button).text)
	_check(String((strip["together"] as Button).text).contains("off"), "Together shows as off (%s)" % (strip["together"] as Button).text)
	(strip["together"] as Button).pressed.emit()
	_check((panel._tabs as TabContainer).get_current_tab_control().name == "Together", "clicking Together jumps to its tab")

	# Core dropping mid-stream is announced
	EventBus.chat_status_changed.emit({"connected": true, "url": "", "error": ""})
	EventBus.chat_status_changed.emit({"connected": false, "url": "", "error": "Stream Core closed the connection"})
	_check(String(panel._msg_btn.text).contains("Lost the connection to Stream Core"), "losing Stream Core shows a message (%s)" % panel._msg_btn.text)

	# On the big screen now
	_check(String(panel._now_label.text) == "On the big screen now: Nothing.", "the Source tab says what's on the big screen (%s)" % panel._now_label.text)

	# NDI / Spout status lines out of the closed folds
	_check((panel._ndi_label as Label).get_parent() == panel._source_sections["ndi"], "the NDI status line is in the NDI section itself, not its fold")
	_check((panel._spout_label as Label).get_parent() == panel._source_sections["spout"], "the Spout status line is in the Spout section itself, not its fold")

	# the video status line
	var raw := "yt-dlp failed (code 1):\nERROR: [youtube] abc: Sign in to confirm you're not a bot."
	_check(VIDEO_LOADER.plain_error(raw).contains("out of date"), "a yt-dlp bot check reads as 'yt-dlp may be out of date'")
	_check(VIDEO_LOADER.plain_error("yt-dlp failed (code 1):\nERROR: [youtube] abc: Private video. Sign in").contains("private"), "a private video says so")
	_check(VIDEO_LOADER.plain_error("File not found: C:/x.mp4") == "File not found: C:/x.mp4", "plain messages stay as they are")
	EventBus.file_play_requested.emit("https://example.invalid/watch?v=abc")
	await _secs(0.3)
	EventBus.video_job_changed.emit("downloading", "", "")
	await _secs(1.2)
	var clock := RegEx.create_from_string("^Downloading\\.\\.\\. \\d+:\\d\\d$")
	_check(clock.search(String(panel._video_status.text)) != null and not String(panel._video_status.text).ends_with("0:00"),
		"downloading shows a running clock (%s)" % panel._video_status.text)
	EventBus.video_job_changed.emit("failed", VIDEO_LOADER.plain_error(raw), raw)
	_check(String(panel._video_status.text).contains("out of date") and (panel._video_retry as Button).visible, "a failure shows in plain words with Try again")
	_check((panel._video_details_fold.get_meta("fold_head") as Control).visible and String(panel._video_details.text).contains("Sign in"),
		"the tool's own log is under Details")
	EventBus.video_job_changed.emit("ready", "Ready: clip.ogv", "")
	_check(not (panel._video_retry as Button).visible and not (panel._video_details_fold.get_meta("fold_head") as Control).visible, "Ready hides Try again and Details")

	# Together's join popup: its own window while the panel is docked
	EventBus.net_confirm_needed.emit("host", 77, "Pretend")
	await get_tree().process_frame
	var d: Window = (panel._net_dialogs as Dictionary).get(77)
	var native_ok := d != null and (d.force_native or not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS))
	_check(native_ok, "the 'wants to join' popup is its own window, not drawn in the captured picture")
	EventBus.net_confirm_closed.emit(77)

	(panel._tabs as TabContainer).current_tab = 0
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("status_line.png"))
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
