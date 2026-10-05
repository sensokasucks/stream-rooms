extends Node
## SystemMedia: sends the OS "Play/Pause" media key so a video playing in the
## browser can be paused from inside the game (used by pause-to-react).
##
## Windows routes the key to the active media session - normally the YouTube tab,
## but another media app (e.g. a music player) can take it instead. The game has
## no way to confirm the browser actually paused, so callers should say "sent",
## not "paused".

var _linux_tool_checked: bool = false
var _linux_tool_found: bool = false


## Returns true if the key press was launched. This does NOT confirm the video paused.
func send_play_pause() -> bool:
	match OS.get_name():
		"Windows":
			# Character 179 is VK_MEDIA_PLAY_PAUSE. Runs hidden and doesn't block the game.
			var pid := OS.create_process("powershell.exe", PackedStringArray([
				"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command",
				"(New-Object -ComObject WScript.Shell).SendKeys([char]179)",
			]))
			return pid > 0
		"Linux", "FreeBSD":
			# create_process forks before exec, so it "succeeds" even if the tool is
			# missing - check that playerctl exists first.
			if not _linux_tool_checked:
				_linux_tool_checked = true
				_linux_tool_found = OS.execute("sh", PackedStringArray(["-c", "command -v playerctl"])) == 0
			if not _linux_tool_found:
				return false
			return OS.create_process("playerctl", PackedStringArray(["play-pause"])) > 0
		_:
			return false
