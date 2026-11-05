extends Node
## Streaming together: pictures that only exist on one PC reach the others (NetSession).
##   - a reaction picture (a custom picture for a command, like a boot for !boot) from the host's
##     Stream Core shows on the guest, and one from the guest's shows on the host;
##   - while the host shares its audience, the guest shows the host's audience looks, custom
##     silhouette picture included, and gets its own looks back when the sharing stops.
## Run as the host (tools/run_tests.ps1 does this); it starts one guest copy itself, which writes its
## PASS / FAIL lines to a file the host prints at the end as "PASS guest: ...".
##   <redot console exe> --path . _tests/test_together_pictures.tscn -- C:/temp/sr_tests --mp-profile=test
## No Stream Core is needed: each copy puts its "Core" picture straight into its own EmoteCache
## under the address ReactionLayer would download it from.

const PORT: int = 7393                # not the default (nor test_together's), so nothing else is disturbed
const PASSWORD: String = "testpass"
## The Core address of each copy's reaction picture (relative, as Core sends it in params.object_image).
const HOST_PIC: String = "/reactions/images/boot.png?v=1"
const GUEST_PIC: String = "/reactions/images/sock.png?v=1"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _main: Node
var _remote: Array = []               # reactions that came from the other PC (EventBus.reaction_play, net_remote)


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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	EventBus.reaction_play.connect(func(d: Dictionary) -> void:
		if bool(d.get("net_remote", false)):
			_remote.append(d))
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("panel_window", false)
	AppState.set_setting("reactions_enabled", true)
	AppState.set_setting("together_port", PORT)
	NetSession.auto_confirm = true
	_unit_checks()
	if args.has("--role=guest"):
		await _guest()
	else:
		await _host()


func _start_main() -> void:
	_main = load("res://core/main.tscn").instantiate()
	add_child(_main)
	await _secs(3.0)


## A small PNG of one colour, w x h (a stand-in for a picture from Stream Core).
func _png(color: Color, w: int, h: int) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img.save_png_to_buffer()


## Plays a "throw" reaction with this copy's own Core picture, as if from its Stream Core.
func _throw_picture(core_path: String) -> void:
	Reactions.play_test("throw", {}, {"object": "img:boot", "object_image": {"name": "boot", "url": core_path}})


## The shared reaction from the other PC that names a picture, or {}.
func _remote_with_picture() -> Dictionary:
	for d: Dictionary in _remote:
		var pic: Variant = (d.get("params", {}) as Dictionary).get("object_image")
		if pic is Dictionary and String((pic as Dictionary).get("net", "")) != "":
			return d
	return {}


func _unit_checks() -> void:
	var r := NetSession._shareable_reaction({"id": "a", "effect": "throw",
		"params": {"object_image": {"url": "/reactions/images/x.png"}}}, "0123456789abcdef")
	_check(((r["params"] as Dictionary).get("object_image", {}) as Dictionary) == {"net": "0123456789abcdef"},
		"a shared reaction names its picture by key, never by its Core address")
	var again := NetSession._shareable_reaction(r)
	_check(((again["params"] as Dictionary).get("object_image", {}) as Dictionary).get("net", "") == "0123456789abcdef",
		"a key that came over the network is kept when it's passed on")
	var bad := NetSession._shareable_reaction({"id": "b", "effect": "throw", "params": {"object_image": {"net": "../../evil"}}})
	_check(not (bad["params"] as Dictionary).has("object_image"), "an odd picture key is dropped")


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_name", "PicHost")
	AppState.set_setting("together_shared_audience", true)
	# the host's looks: a custom silhouette picture and the dark bubbles
	var src := _out.path_join("host_figure.png")
	var fig := Image.create(200, 300, false, Image.FORMAT_RGBA8)
	fig.fill(Color(0, 0, 0, 0))
	fig.fill_rect(Rect2i(40, 20, 120, 280), Color(0.9, 0.2, 0.2))
	fig.save_png(src)
	var file := AudienceStyle.import_picture(src)
	_check(file.begins_with("user://silhouettes/"), "the host's silhouette picture was imported (%s)" % file)
	AppState.set_setting("audience_silhouette", JSON.stringify({"shape": "custom", "file": file, "paint": "picture"}))
	AppState.set_setting("audience_bubble_theme", "dark")
	await _start_main()
	EmoteCache.put_bytes(ReactionLayer.picture_url(HOST_PIC), _png(Color(0.1, 0.4, 0.9), 40, 30))
	NetSession.host()
	_check(NetSession.get_role() == "host", "hosting started")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_picguest.cfg"))
	DirAccess.remove_absolute(_out.path_join("together_picguest.txt"))
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "0,0", "res://_tests/test_together_pictures.tscn", "--", _out, "--mp-profile=picguest", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the guest copy")
	var joined := await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 120.0)
	_check(joined, "the guest joined")
	if joined:
		await _secs(5.0)
		_throw_picture(HOST_PIC)           # the guest checks it shows this picture
		# the guest's own picture comes back the other way
		_check(await _wait_for(func() -> bool: return not _remote_with_picture().is_empty(), 60.0), "the guest's picture reaction arrived")
		var d := _remote_with_picture()
		if not d.is_empty():
			var url := EmoteCache.NET_PREFIX + String(d["params"]["object_image"]["net"])
			_check(await _wait_for(func() -> bool: return EmoteCache.get_texture(url) != null, 20.0), "the guest's reaction picture is here")
			var tex := EmoteCache.get_texture(url)
			_check(tex != null and tex.get_width() == 24 and tex.get_height() == 36, "and it is the guest's picture (24 x 36)")
		await _secs(6.0)                   # (the guest checks the looks meanwhile)
		AppState.set_setting("together_shared_audience", false)
		await _secs(6.0)
	NetSession.leave()
	var f := _out.path_join("together_picguest.txt")
	await _wait_for(func() -> bool: return FileAccess.file_exists(f), 120.0)
	var text := FileAccess.get_file_as_string(f)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		_check(line.begins_with("PASS "), "guest: %s" % line.substr(5))
	await _finish()


# ── Guest ────────────────────────────────────────────────────
func _guest() -> void:
	AppState.set_setting("together_address", "127.0.0.1:%d" % PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_name", "PicGuest")
	# this PC's own looks, which must come back afterwards
	var own := JSON.stringify({"shape": "bot"})
	AppState.set_setting("audience_silhouette", own)
	AppState.set_setting("audience_bubble_theme", "light")
	await _start_main()
	EmoteCache.put_bytes(ReactionLayer.picture_url(GUEST_PIC), _png(Color(0.9, 0.8, 0.1), 24, 36))
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and (NetSession.get_info()["peers"] as Array).size() == 2, 60.0),
		"joined the host")

	# the host's audience looks, with its silhouette picture as a copy here
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting("audience_silhouette")).contains("user://silhouettes/net_"), 30.0),
		"the host's silhouette look arrived (%s)" % AppState.get_setting("audience_silhouette"))
	var fig := AudienceStyle.figure()
	_check(String(fig["shape"]) == "custom" and FileAccess.file_exists(String(fig["file"]))
		and FileAccess.file_exists(String(fig["file"]).replace(".png", "_shape.png")), "its picture is here, both versions (%s)" % fig["file"])
	var tex := AudienceStyle.figure_texture(fig)
	_check(tex != null and tex.get_width() == AudienceStyle.FIGURE_W, "and the audience can draw it")
	_check(String(AppState.get_setting("audience_bubble_theme")) == "dark", "the host's bubble theme arrived")
	_check(FileAccess.file_exists(NetSession.LOOKS_BACKUP), "this PC's own looks are kept aside meanwhile")

	# the host's reaction picture
	_check(await _wait_for(func() -> bool: return not _remote_with_picture().is_empty(), 30.0), "the host's picture reaction arrived")
	var d := _remote_with_picture()
	if not d.is_empty():
		var url := EmoteCache.NET_PREFIX + String(d["params"]["object_image"]["net"])
		_check(await _wait_for(func() -> bool: return EmoteCache.get_texture(url) != null, 20.0), "the host's reaction picture is here")
		var pic := EmoteCache.get_texture(url)
		_check(pic != null and pic.get_width() == 40 and pic.get_height() == 30, "and it is the host's picture (40 x 30)")
	_throw_picture(GUEST_PIC)             # the host checks this one

	# the host stops sharing its audience: this PC's own looks come back
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting("audience_silhouette")) == own, 40.0),
		"this PC's own silhouette came back when the host stopped sharing")
	_check(String(AppState.get_setting("audience_bubble_theme")) == "light", "and its own bubble theme")
	_check(not FileAccess.file_exists(NetSession.LOOKS_BACKUP), "the kept-aside copy is gone")
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "noticed the session ending")
	await _finish()


func _finish() -> void:
	var role := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mp-profile="):
			role = a.trim_prefix("--mp-profile=")
	if role != "test":
		var f := FileAccess.open(_out.path_join("together_%s.txt" % role), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(_lines) + "\n")
			f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
