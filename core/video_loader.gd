extends Node
## Turns whatever the user typed (a YouTube / web URL or a local file path)
## into an Ogg Theora (.ogv) file that Redot can play.
##   - .ogv files are played as-is.
##   - Other local videos (mp4, mkv, webm, ...) are converted with ffmpeg.
##   - URLs are downloaded with yt-dlp, then converted with ffmpeg.
## Results are cached in user://video_cache so the same video is instant next time.
## Heavy work runs on a background thread so the scene keeps rendering.
## The tools run as child processes the thread watches: quitting (or freeing this node) stops
## them at once instead of waiting minutes for a long convert to finish. A convert writes to a
## ".part.ogv" file first, so a stopped one never leaves a broken video in the cache.

signal status(message: String)
## "downloading" or "converting": what the job is doing now (for the panel's status line).
signal stage(name: String)
signal ready_to_play(path: String)
signal failed(message: String)

## (A copy started with --mp-profile keeps its own cache, so two copies on one PC never convert
## into the same file at once.)
var _cache_dir: String = "user://video_cache" if AppState.get_profile().is_empty() else "user://video_cache_%s" % AppState.get_profile()

## Max height of converted video. Lower = faster conversion.
var max_height := 720
var busy := false
## Downloads are capped (a co-host's link, or a host's for its guests, can't fill the disk).
const MAX_DOWNLOAD := "2G"
## ... and so is their length (seconds).
const MAX_DURATION_S := 14400

var _thread: Thread
## Set on quit: the job's tool is stopped and the job ends early.
var _cancel: bool = false
## The tool the job is running now (0 = none), so quitting can stop it.
var _pid: int = 0


func request(raw: String) -> void:
	var input := raw.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if input == "":
		failed.emit("Paste a YouTube URL or a path to a video file first.")
		return
	if busy:
		failed.emit("Still working on the previous video - hang on.")
		return
	DirAccess.make_dir_recursive_absolute(_cache_dir)

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
	_cancel = true
	if _pid > 0:
		OS.kill(_pid)
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# ------------------------------------------------------------ thread jobs

func _say(msg: String) -> void:
	status.emit.call_deferred(msg)


func _stage(name: String) -> void:
	stage.emit.call_deferred(name)


func _done(ok: bool, payload: String) -> void:
	_finish.call_deferred(ok, payload)


func _job_local(path: String) -> void:
	var abs_src := ProjectSettings.globalize_path(path)
	var mtime := FileAccess.get_modified_time(path)
	var out := "%s/%s_%d.ogv" % [_cache_dir, ("%s|%d" % [abs_src, mtime]).md5_text(), max_height]
	if FileAccess.file_exists(out):
		_done(true, out)
		return
	var ffmpeg := _find_tool("ffmpeg", "-version")
	if ffmpeg == "":
		_done(false, _missing_msg("ffmpeg"))
		return
	_stage("converting")
	_say("Converting %s to .ogv (this can take a while for long videos)..." % path.get_file())
	var err := _convert(ffmpeg, abs_src, out)
	_done(err == "", out if err == "" else err)


func _job_url(url: String) -> void:
	var key := url.md5_text()
	var out := "%s/%s_%d.ogv" % [_cache_dir, key, max_height]
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

	_stage("downloading")
	_say("Downloading video with yt-dlp...")
	var template := ProjectSettings.globalize_path("%s/%s_src.%%(ext)s" % [_cache_dir, key])
	var fmt := "bv*[height<=%d]+ba/b[height<=%d]/b" % [max_height, max_height]
	var args := PackedStringArray([
		"--no-playlist", "--no-progress", "--no-warnings",
		"-f", fmt, "--merge-output-format", "mkv",
		"--max-filesize", MAX_DOWNLOAD, "--match-filter", "duration<%d" % MAX_DURATION_S,
		"-o", template,
		"--print", "after_move:filepath", "--no-simulate",
	])
	if ffmpeg.contains("/") or ffmpeg.contains("\\"):
		args.append_array(["--ffmpeg-location", ffmpeg])
	args.append(url)
	var output := []
	var code := _run(ytdlp, args, output)
	if _cancel:
		return
	var ytlog := "\n".join(output)
	var src := ""
	for line in ytlog.split("\n"):
		var l := line.strip_edges()
		# only the file this job asked for (a stray line naming another file must never be
		# picked: it gets deleted after the convert)
		if l != "" and l.replace("\\", "/").get_file().begins_with(key + "_src.") and FileAccess.file_exists(l):
			src = l
	if code == 0 and src == "" and ytlog.contains("does not pass filter"):
		_done(false, "That video is longer than %d hours, too long to download here." % int(MAX_DURATION_S / 3600.0))
		return
	if code == 0 and src == "" and ytlog.to_lower().contains("max-filesize"):
		_done(false, "That video is bigger than %s, too big to download here." % MAX_DOWNLOAD)
		return
	if code != 0 or src == "":
		_done(false, "yt-dlp failed (code %d):\n%s" % [code, _tail(ytlog)])
		return

	_stage("converting")
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
	var code := _run(ffmpeg, args, output)
	if _cancel or code != 0 or not FileAccess.file_exists(part):
		DirAccess.remove_absolute(abs_part)
		return "ffmpeg failed (code %d):\n%s" % [code, _tail("\n".join(output))]
	DirAccess.rename_absolute(abs_part, ProjectSettings.globalize_path(out))
	return ""


# ------------------------------------------------------------ helpers

## A failure in plain words (the raw yt-dlp / ffmpeg log is kept for a Details fold).
static func plain_error(raw: String) -> String:
	var low := raw.to_lower()
	if raw.begins_with("yt-dlp failed") or raw.begins_with("ffmpeg failed"):
		if low.contains("private video"):
			return "Couldn't download: that video is private."
		if low.contains("confirm your age") or low.contains("age-restricted") or low.contains("age restricted"):
			return "Couldn't download: that video is age-restricted (YouTube wants a sign-in)."
		if low.contains("live event will begin") or low.contains("premieres in"):
			return "Couldn't download: that stream or premiere hasn't started yet."
		if low.contains("video unavailable") or low.contains("this video is not available"):
			return "Couldn't download: YouTube says the video is unavailable (removed, or blocked where you are)."
		if low.contains("http error 403") or low.contains("sign in to confirm") or low.contains("unsupported url") \
				or low.contains("nsig extraction failed") or low.contains("unable to extract"):
			return "Couldn't download: yt-dlp may be out of date. Run tools\\get_tools.ps1 to update it, then click Try again."
		if low.contains("unable to download webpage") or low.contains("failed to resolve") or low.contains("getaddrinfo") \
				or low.contains("timed out") or low.contains("connection"):
			return "Couldn't download: the address couldn't be reached. Check the link and your internet connection."
		if raw.begins_with("ffmpeg failed"):
			return "Couldn't convert the video (ffmpeg gave an error). The details are under Details."
		return "Couldn't download the video (yt-dlp gave an error). The details are under Details."
	return raw.get_slice("\n", 0)


## Runs a tool (on the job thread) and waits for it, collecting what it prints (stdout and
## stderr) into output. Stops it when _cancel is set. Returns its exit code (-1 = stopped/failed).
func _run(exe: String, args: PackedStringArray, output: Array) -> int:
	var info := OS.execute_with_pipe(exe, args, false)
	if info.is_empty():
		return -1
	_pid = int(info["pid"])
	var pipes: Array[FileAccess] = [info["stdio"], info["stderr"]]
	var text := ""
	while OS.is_process_running(_pid):
		if _cancel:
			OS.kill(_pid)
			break
		text += _drain(pipes)
		OS.delay_msec(50)
	text += _drain(pipes)
	var code := -1 if _cancel else OS.get_process_exit_code(_pid)
	_pid = 0
	for f in pipes:
		f.close()
	output.append(text)
	return code


func _drain(pipes: Array[FileAccess]) -> String:
	var out := ""
	for f in pipes:
		var chunk := f.get_buffer(65536)
		while not chunk.is_empty():
			out += chunk.get_string_from_utf8()
			chunk = f.get_buffer(65536)
	return out


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
