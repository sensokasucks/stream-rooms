extends Node
## Clearer video downloads (Source tab > File or URL): "Just get it ready" converts a video into
## the cache without playing it, reporting progress as it goes; the finished video shows in Ready
## videos with its title and size and can be deleted; Cancel stops a convert and leaves nothing
## half-done behind. Needs ffmpeg (tools/ or on the PATH).
##   <redot console exe> --path . _tests/test_video_steps.tscn -- C:/temp/sr_tests --mp-profile=test

const VIDEO_LOADER := preload("res://core/video_loader.gd")

var _fails: int = 0
var _states: Array = []
var _fractions: Array = []


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_for(cond: Callable, secs: float) -> bool:
	var left := secs
	while left > 0.0:
		if cond.call():
			return true
		await _secs(0.2)
		left -= 0.2
	return bool(cond.call())


## A test clip made with ffmpeg (seconds long, 720p), or "" when there's no ffmpeg.
func _make_clip(file: String, seconds: int) -> String:
	var exe := ProjectSettings.globalize_path("res://tools/ffmpeg.exe")
	if not FileAccess.file_exists(exe):
		exe = "ffmpeg"
	var out := ProjectSettings.globalize_path("user://" + file)
	var code := OS.execute(exe, PackedStringArray(["-y", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=size=1280x720:rate=30", "-f", "lavfi", "-i", "sine=frequency=440",
		"-t", str(seconds), "-c:v", "mpeg4", "-q:v", "5", "-c:a", "aac", out]))
	return out if code == 0 and FileAccess.file_exists(out) else ""


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("max_height", 480)
	EventBus.video_job_changed.connect(func(st: String, m: String, d: String) -> void:
		print("video job: ", st, " | ", m, " | ", d.left(300))
		_states.append(st))
	EventBus.video_progress.connect(func(_st: String, f: float) -> void: _fractions.append(f))
	for e in VIDEO_LOADER.list_ready():
		VIDEO_LOADER.delete_ready(String(e["path"]))
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	_states.clear()          # (main.gd tries to play the first command-line word, the output folder: not ours)
	var clip := _make_clip("steps_clip.mp4", 20)
	_check(clip != "", "made a test clip")
	if clip == "":
		print("DONE fails=", _fails)
		AppState.request_quit(1)
		return

	# Just get it ready: converted into the cache, not played
	EventBus.file_ready_requested.emit(clip)
	_check(await _wait_for(func() -> bool: return _states.has("prepared") or _states.has("failed"), 120.0), "the convert finished")
	_check(_states.has("converting") and _states.has("prepared") and not _states.has("ready"),
		"it was converted and kept, not played (%s)" % str(_states))
	_check(not _fractions.is_empty() and float(_fractions.max()) >= 0.9, "progress went up to the end (%d updates)" % _fractions.size())
	_check(AppState.get_source_mode() != "file", "nothing plays on the big screen")
	var list := VIDEO_LOADER.list_ready()
	_check(list.size() == 1 and String(list[0]["title"]) == "steps_clip" and int(list[0]["bytes"]) > 1000,
		"Ready videos lists it with its name and size")
	var panel: Node = main.find_child("ControlPanel", true, false)
	var shown := false
	if panel:
		for l in panel.find_children("*", "Label", true, false):
			if (l as Label).text.begins_with("steps_clip"):
				shown = true
	_check(shown, "the Source tab shows it under Ready videos")

	# Cancel: a longer convert stops and leaves no half-done file
	var long_clip := _make_clip("steps_long.mp4", 240)
	_states.clear()
	_fractions.clear()
	EventBus.file_ready_requested.emit(long_clip)
	_check(await _wait_for(func() -> bool: return not _fractions.is_empty() and float(_fractions[-1]) > 0.0, 60.0), "the long convert is under way")
	EventBus.file_cancel_requested.emit()
	_check(await _wait_for(func() -> bool: return _states.has("cancelled"), 20.0), "Cancel stopped it (%s)" % str(_states))
	var parts := 0
	for f in DirAccess.get_files_at(VIDEO_LOADER.cache_dir()):
		if f.ends_with(".part.ogv"):
			parts += 1
	_check(parts == 0 and VIDEO_LOADER.list_ready().size() == 1, "nothing half-done stayed in the cache")

	_check(VIDEO_LOADER.delete_ready(String(list[0]["path"])) and VIDEO_LOADER.list_ready().is_empty(), "Delete removes it")
	_check(not VIDEO_LOADER.delete_ready("user://settings.cfg"), "Delete won't touch anything outside the video cache")
	DirAccess.remove_absolute(clip)
	DirAccess.remove_absolute(long_clip)
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
