extends Node
## Microphone start safety (AudioManager): starting the microphone hung the game on one PC, every
## start. A marker file is written just before the microphone starts and removed once it runs; a
## start that finds the marker switches auto-duck off instead of hanging again.
## This copy checks the normal case, then starts a second copy with a marker left behind (as if the
## last start had hung) and reads its results from a file.
##   <redot console exe> --path . _tests/test_mic_safety.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []


func _check(ok: bool, what: String) -> void:
	var line := ("PASS " if ok else "FAIL ") + what
	print(line)
	_lines.append(line)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	if OS.get_cmdline_user_args().has("--role=after-hang"):
		# AudioManager has already started by now: it found the marker this copy's parent left
		_check(not bool(AppState.get_setting("duck_enabled")), "a start after a hung microphone switches auto-duck off")
		_check(not FileAccess.file_exists("user://mic_starting_mictest"), "and clears the marker")
		await _secs(4.0)
		_check(not FileAccess.file_exists("user://mic_starting_mictest"), "and doesn't start the microphone (no new marker)")
		var f := FileAccess.open(_out.path_join("mic_safety_child.txt"), FileAccess.WRITE)
		f.store_string("\n".join(_lines) + "\n")
		f.close()
		get_tree().quit()
		return

	# this copy: auto-duck on by default, the microphone started normally
	_check(bool(AppState.get_setting("duck_enabled")), "auto-duck is on by default")
	await _secs(4.0)
	_check(not FileAccess.file_exists("user://mic_starting_test"), "a microphone that starts fine leaves no marker")

	# a second copy that finds a marker, as if its last start had hung
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_mictest.cfg"))
	var result := _out.path_join("mic_safety_child.txt")
	DirAccess.remove_absolute(result)
	var marker := FileAccess.open("user://mic_starting_mictest", FileAccess.WRITE)
	marker.store_string("starting")
	marker.close()
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--path", ProjectSettings.globalize_path("res://"),
		"--headless", "res://_tests/test_mic_safety.tscn", "--", _out, "--mp-profile=mictest", "--role=after-hang"]))
	_check(pid > 0, "started the second copy")
	var t := 0.0
	while t < 60.0 and not FileAccess.file_exists(result):
		await _secs(0.5)
		t += 0.5
	for line in FileAccess.get_file_as_string(result).split("\n", false):
		_check(line.begins_with("PASS "), "second copy: " + line.substr(5))
	var cfg := ConfigFile.new()
	cfg.load("user://settings_mictest.cfg")
	_check(cfg.get_value("settings", "duck_enabled", true) == false, "the switch-off was saved, so later starts skip it too")
	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
