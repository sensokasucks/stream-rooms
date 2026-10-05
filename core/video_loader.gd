extends Node
## Turns whatever the user typed (a YouTube / web URL or a local file path)
## into an Ogg Theora (.ogv) file that Redot can play.
##   - .ogv files are played as-is.
##   - Other local videos (mp4, mkv, webm, ...) are converted with ffmpeg.
##   - URLs are downloaded with yt-dlp, then converted with ffmpeg.
## Results are cached in user://video_cache so the same video is instant next time.
## Heavy work runs on a background thread so the scene keeps rendering.

signal status(message: String)
signal ready_to_play(path: String)
signal failed(message: String)

const CACHE_DIR := "user://video_cache"

## Max height of converted video. Lower = faster conversion.
var max_height := 720
var busy := false

var _thread: Thread


func request(raw: String) -> void:
	var input := raw.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if input == "":
		failed.emit("Paste a YouTube URL or a path to a video file first.")
		return
	if busy:
		failed.emit("Still working on the previous video - hang on.")
		return
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)

	if input.begins_with("http://") or input.begins_with("https://"):
		_start(_job_url.bind(input))
		return

	var path := input
	if not (path.begins_with("res://") or path.begins_with("user://")):
		path = path.replace("\\", "/")
	if not FileAccess.file_exists(path):
		failed.emit("File not found: %s" % input)
		return
	if path.get_extension().to_lower() == "ogv":
		ready_to_play.emit(path)
	else:
		_start(_job_local.bind(path))


func _start(job: Callable) -> void:
	busy = true
	_thread = Thread.new()
	_thread.start(job)


# Called on the main thread when a job ends.
func _finish(ok: bool, payload: String) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	busy = false
	if ok:
		ready_to_play.emit(payload)
	else:
		failed.emit(payload)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# ------------------------------------------------------------ thread jobs

func _say(msg: String) -> void:
	status.emit.call_deferred(msg)


func _done(ok: bool, payload: String) -> void:
	_finish.call_deferred(ok, payload)


func _job_local(path: String) -> void:
	var abs_src := ProjectSettings.globalize_path(path)
	var mtime := FileAccess.get_modified_time(path)
	var out := "%s/%s_%d.ogv" % [CACHE_DIR, ("%s|%d" % [abs_src, mtime]).md5_text(), max_height]
	if FileAccess.file_exists(out):
		_done(true, out)
		return
	var ffmpeg := _find_tool("ffmpeg", "-version")
	if ffmpeg == "":
		_done(false, _missing_msg("ffmpeg"))
		return
	_say("Converting %s to .ogv (this can take a while for long videos)..." % path.get_file())
	var err := _convert(ffmpeg, abs_src, out)
	_done(err == "", out if err == "" else err)


func _job_url(url: String) -> void:
	var key := url.md5_text()
	var out := "%s/%s_%d.ogv" % [CACHE_DIR, key, max_height]
	if FileAccess.file_exists(out):
		_done(true, out)
		return
	var ytdlp := _find_tool("yt-dlp", "--version")
	if ytdlp == "":
		_done(false, _missing_msg("yt-dlp"))
		return
	var ffmpeg := _find_tool("ffmpeg", "-version")
	if ffmpeg == "":
		_done(false, _missing_msg("ffmpeg"))
		return

	_say("Downloading video with yt-dlp...")
	var template := ProjectSettings.globalize_path("%s/%s_src.%%(ext)s" % [CACHE_DIR, key])
	var fmt := "bv*[height<=%d]+ba/b[height<=%d]/b" % [max_height, max_height]
	var args := PackedStringArray([
		"--no-playlist", "--no-progress", "--no-warnings",
		"-f", fmt, "--merge-output-format", "mkv",
		"-o", template,
		"--print", "after_move:filepath", "--no-simulate",
	])
	if ffmpeg.contains("/") or ffmpeg.contains("\\"):
		args.append_array(["--ffmpeg-location", ffmpeg])
	args.append(url)
	var output := []
	var code := OS.execute(ytdlp, args, output, true)
	var ytlog := "\n".join(output)
	var src := ""
	for line in ytlog.split("\n"):
		var l := line.strip_edges()
		if l != "" and FileAccess.file_exists(l):
			src = l
	if code != 0 or src == "":
		_done(false, "yt-dlp failed (code %d):\n%s" % [code, _tail(ytlog)])
		return

	_say("Converting download to .ogv (this can take a while for long videos)...")
	var err := _convert(ffmpeg, src, out)
	DirAccess.remove_absolute(src) # keep only the converted copy
	_done(err == "", out if err == "" else err)


func _convert(ffmpeg: String, src: String, out: String) -> String:
	var part := out.get_basename() + ".part.ogv"
	var abs_part := ProjectSettings.globalize_path(part)
	var args := PackedStringArray([
		"-y", "-hide_banner", "-loglevel", "error",
		"-i", src,
		"-vf", "scale=-2:'min(%d,ih)'" % max_height,
		"-c:v", "libtheora", "-q:v", "7",
		"-c:a", "libvorbis", "-q:a", "4", "-ac", "2", "-ar", "44100",
		abs_part,
	])
	var output := []
	var code := OS.execute(ffmpeg, args, output, true)
	if code != 0 or not FileAccess.file_exists(part):
		DirAccess.remove_absolute(abs_part)
		return "ffmpeg failed (code %d):\n%s" % [code, _tail("\n".join(output))]
	DirAccess.rename_absolute(abs_part, ProjectSettings.globalize_path(out))
	return ""


# ------------------------------------------------------------ helpers

## Looks for the tool next to the exported game, in the project's tools/ folder,
## then on the system PATH. Returns "" if it can't be found.
func _find_tool(tool: String, version_flag: String) -> String:
	var exe := tool + (".exe" if OS.get_name() == "Windows" else "")
	var dirs := [
		OS.get_executable_path().get_base_dir().path_join("tools"),
		ProjectSettings.globalize_path("res://tools"),
	]
	for d in dirs:
		var p: String = d.path_join(exe)
		if p != "" and FileAccess.file_exists(p):
			return p
	var out := []
	if OS.execute(tool, PackedStringArray([version_flag]), out) == 0:
		return tool
	return ""


func _missing_msg(tool: String) -> String:
	return ("%s not found. Run tools/get_tools.ps1 (right-click > Run with PowerShell) " +
		"or put %s in the project's tools/ folder or on your PATH.") % [tool, tool]


func _tail(text: String, lines := 6) -> String:
	var parts := text.strip_edges().split("\n")
	return "\n".join(parts.slice(maxi(parts.size() - lines, 0)))
