extends Node
## Streaming together: pictures that only exist on one PC reach the others.
##   - A reaction with its own picture (Core's "img:boot") shows that picture on every PC, both
##     ways: the host's reaction on the guest, and the guest's on the host (NetSession sends the
##     bytes once, named "net:<md5>", and EmoteCache keeps them).
##   - With the audience shared, the guest shows the host's custom silhouette picture, and its own
##     looks again once the session ends (its own settings are never changed).
## No Stream Core: each copy puts its "Core" picture straight into EmoteCache under the address
## ReactionLayer would download it from. The guest writes its results to a file; the host prints them.
##   <redot console exe> --path . _tests/test_net_pictures.tscn -- C:/temp/sr_tests --mp-profile=test

const SESSION_PORT: int = 7399
const PASSWORD: String = "picturepass"
## Where each copy's reaction picture "is" on its own Core (chat_core_url below is ws://127.0.0.1:9/ws).
const HOST_PIC: String = "/reactions/images/np_boot.png?v=1"
const GUEST_PIC: String = "/reactions/images/np_glove.png?v=1"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _remote: Array = []           # reactions that came from the other PC (net_remote)


func _check(ok: bool, what: String) -> void:
	var line := ("PASS " if ok else "FAIL ") + what
	print(line)
	_lines.append(line)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if bool(cond.call()):
			return true
		await _secs(0.25)
		t += 0.25
	return bool(cond.call())


## A plain one-colour PNG (the same bytes every time for the same size and colour).
func _png(size: int, color: Color) -> PackedByteArray:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png_to_buffer()


## Plays one of this PC's reactions with its own picture (as if it came from this PC's Core).
func _fire(pic_path: String) -> void:
	EventBus.reaction_play.emit({"id": "np%d" % randi(), "reaction": "boot", "label": "Boot", "effect": "fall_down",
		"params": {"object": "img:boot", "count": 3, "object_image": {"name": "boot", "url": pic_path, "animated": false}},
		"count": 3, "from": {"platform": "twitch", "username": "viewer0", "display_name": "Viewer0"},
		"target": {"type": "stage", "name": "stage"}, "route": "game"})


## The "net:<md5>" picture the first reaction from the other PC named, or "".
func _remote_key() -> String:
	for d: Dictionary in _remote:
		var key := NetSession._reaction_key(d)
		if key != "":
			return key
	return ""


func _ready() -> void:
	NetSession.auto_confirm = true      # (no "let them in" popups in a test)
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)      # (the guest writes its results file here)
	EventBus.reaction_play.connect(func(d: Dictionary) -> void:
		if bool(d.get("net_remote", false)):
			_remote.append(d))
	AppState.set_setting("chat_enabled", false)                       # (never the real Stream Core)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("reactions_enabled", true)
	AppState.set_setting("together_port", SESSION_PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_address", "127.0.0.1:%d" % SESSION_PORT)
	AppState.request_room("theater")
	add_child(load("res://core/main.tscn").instantiate())
	await _secs(5.0)
	if OS.get_cmdline_user_args().has("--role=guest"):
		await _guest()
	else:
		await _host()


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	# a custom silhouette picture of the host's own (a round blob), imported like CoreLooks does
	var blob := Image.create_empty(64, 80, false, Image.FORMAT_RGBA8)
	for y in 80:
		for x in 64:
			if Vector2(x - 32, y - 40).length() < 28.0:
				blob.set_pixel(x, y, Color(0.9, 0.4, 0.1))
	var src := ProjectSettings.globalize_path("user://np_host_blob.png")
	blob.save_png(src)
	var file := AudienceStyle.import_picture(src)
	_check(file != "", "imported the host's silhouette picture")
	AppState.set_setting("audience_silhouette", JSON.stringify({"shape": "custom", "file": file, "paint": "picture"}))
	EmoteCache.put_bytes(ReactionLayer._core_url(HOST_PIC), _png(32, Color.RED))

	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_shared_audience", true)
	NetSession.host()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_picguest2.cfg"))
	DirAccess.remove_absolute(_out.path_join("together_picguest.txt"))
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "980,0", "res://_tests/test_net_pictures.tscn", "--", _out, "--mp-profile=picguest2", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the guest copy")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0), "the guest joined")
	await _secs(4.0)
	_fire(HOST_PIC)
	# the guest answers with a reaction of its own once it saw this one
	_check(await _wait_for(func() -> bool: return _remote_key() != "", 30.0), "the guest's reaction arrived with a picture name")
	var key := _remote_key()
	var tex := EmoteCache.get_texture(key)
	_check(tex != null and tex.get_width() == 24, "the guest's reaction picture is here (%s)" % [tex.get_size() if tex else "none"])
	_check(not key.contains("np_glove") and NetSession._is_picture_key(key), "it's named by its bytes, not the guest's Core address")
	await _secs(3.0)
	NetSession.leave()

	var f := _out.path_join("together_picguest.txt")
	await _wait_for(func() -> bool: return FileAccess.file_exists(f), 40.0)
	var text := FileAccess.get_file_as_string(f)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		_check(line.begins_with("PASS "), "guest: " + line.substr(5))
	# tidy up: the test pictures (both copies share this user:// folder) and the look
	AppState.set_setting("audience_silhouette", "")
	for path in [src, file, file.replace(".png", "_shape.png")]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for fname in DirAccess.get_files_at("user://silhouettes/"):
		if fname.begins_with("net_"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://silhouettes/" + fname))
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)


# ── Guest ────────────────────────────────────────────────────
func _guest() -> void:
	AppState.set_setting("audience_silhouette", "")          # this PC's own look: the classic bust
	EmoteCache.put_bytes(ReactionLayer._core_url(GUEST_PIC), _png(24, Color.BLUE))
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and AudienceManager.is_mirror(), 30.0),
		"joined, and shows the host's audience")
	var host_look := func() -> bool:
		var fig := AudienceStyle.figure()
		return String(fig["shape"]) == "custom" and String(fig["file"]).begins_with("user://silhouettes/net_") \
			and FileAccess.file_exists(String(fig["file"]))
	_check(await _wait_for(host_look, 20.0), "shows the host's custom silhouette picture (%s)" % AudienceStyle.figure()["file"])
	_check(AudienceStyle.figure_texture(AudienceStyle.figure()) != AudienceStyle.CLASSIC_TEX, "and the picture loads")
	_check(String(AppState.get_setting("audience_silhouette")) == "", "while this PC's own setting stays as it was")

	_check(await _wait_for(func() -> bool: return _remote_key() != "", 30.0), "the host's reaction arrived with a picture name")
	var key := _remote_key()
	var tex := EmoteCache.get_texture(key)
	_check(tex != null and tex.get_width() == 32, "the host's reaction picture is here (%s)" % [tex.get_size() if tex else "none"])
	_fire(GUEST_PIC)

	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "noticed the session ending")
	_check(AudienceStyle.net_looks.is_empty() and String(AudienceStyle.figure()["shape"]) == "classic",
		"and shows its own silhouette again")
	var f := FileAccess.open(_out.path_join("together_picguest.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
