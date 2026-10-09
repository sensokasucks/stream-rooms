extends Node
## VideoLoader: quitting while ffmpeg converts stops it at once (it used to wait for the whole
## convert, so the app hung on quit), leaves no broken video in the cache, and a normal convert
## still works. Needs ffmpeg (tools/ or PATH).
##   <redot console exe> --path . _tests/test_video_quit.tscn -- C:/temp/sr_tests --mp-profile=test

const LOADER := preload("res://core/video_loader.gd")

var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


## Makes a test clip with ffmpeg (seconds long); returns its path or "".
func _make_clip(ffmpeg: String, name: String, seconds: int) -> String:
	var path := _out.path_join(name)
	var code := OS.execute(ffmpeg, PackedStringArray(["-y", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30", "-f", "lavfi", "-i", "sine=frequency=440",
		"-t", str(seconds), "-c:v", "mpeg4", "-q:v", "3", "-c:a", "aac", path]))
	return path if code == 0 and FileAccess.file_exists(path) else ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 and not args[0].begins_with("--") else OS.get_user_data_dir().path_join("test_out")
	DirAccess.make_dir_recursive_absolute(_out)
	var probe: Node = LOADER.new()
	var ffmpeg: String = probe._find_tool("ffmpeg", "-version")
	probe.free()
	if ffmpeg == "":
		_check(false, "ffmpeg is installed (tools/ or PATH)")
		_finish()
		return
	var long_clip := _make_clip(ffmpeg, "vq_long_%d.mp4" % Time.get_ticks_msec(), 240)
	var short_clip := _make_clip(ffmpeg, "vq_short_%d.mp4" % Time.get_ticks_msec(), 2)
	_check(long_clip != "" and short_clip != "", "made test clips")

	# a long convert, then the loader goes away mid-way (what quitting does)
	var loader: Node = LOADER.new()
	add_child(loader)
	var said: Array[String] = []
	loader.status.connect(func(m: String) -> void: said.append(m))
	loader.request(long_clip)
	await _secs(2.0)
	_check(loader.busy and said.size() > 0, "the long convert is running (%s)" % ", ".join(said))
	var t0 := Time.get_ticks_msec()
	loader.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var took := Time.get_ticks_msec() - t0
	_check(took < 3000, "freeing the loader mid-convert returns quickly (%d ms)" % took)
	var cache: String = "user://video_cache_%s" % AppState.get_profile() if not AppState.get_profile().is_empty() else "user://video_cache"
	var broken := 0
	for f in DirAccess.get_files_at(cache):
		if f.ends_with(".ogv") and not f.ends_with(".part.ogv") and FileAccess.get_modified_time(cache.path_join(f)) >= int(Time.get_unix_time_from_system()) - 30:
			broken += 1
	_check(broken == 0, "no half-converted video left under a cached name")

	# a short convert still works
	var loader2: Node = LOADER.new()
	add_child(loader2)
	var result: Array = []
	loader2.ready_to_play.connect(func(p: String) -> void: result.append(p))
	loader2.failed.connect(func(m: String) -> void: result.append("FAILED " + m))
	loader2.request(short_clip)
	for i in 300:
		if not result.is_empty():
			break
		await _secs(0.1)
	_check(result.size() == 1 and not String(result[0]).begins_with("FAILED") and FileAccess.file_exists(String(result[0])),
		"a short clip converts and is ready to play (%s)" % str(result))
	if result.size() == 1 and FileAccess.file_exists(String(result[0])):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(result[0])))
	DirAccess.remove_absolute(long_clip)
	DirAccess.remove_absolute(short_clip)
	_finish()


func _finish() -> void:
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
