extends Node
## Laser pointers (core/laser_pointers.gd): this PC's own laser, and everyone's in a co-stream.
##   Alone (host copy, before hosting): the dot lands on a wall where the window's middle points,
##   the beam starts beside the camera, Show the beam off hides it, and Beam starts at My podium
##   avatar starts it at podium 1's picture.
##   Together (a guest copy joins): the host's laser shows on the guest in the host's colour; the
##   guest claims podium 2 and its laser shows on the host coming from podium 2 in the guest's
##   colour; a still laser stays on (keep-alive), and turning it off hides it on the other PC.
## The guest writes its results to a file; the host prints them. Screenshots: laser_alone.png,
## laser_podium.png, laser_both.png (host).
##   <redot console exe> --path . _tests/test_laser_pointer.tscn -- C:/temp/sr_tests --mp-profile=test

const SESSION_PORT: int = 7397
const PASSWORD: String = "laserpass"
const HOST_COLOR := Color(0.1, 1.0, 0.2)
const GUEST_COLOR := Color(0.2, 0.4, 1.0)

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


func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if bool(cond.call()):
			return true
		await _secs(0.25)
		t += 0.25
	return bool(cond.call())


func _lasers() -> LaserPointers:
	return get_tree().root.find_child("LaserPointers", true, false) as LaserPointers


## Podium n's picture position in the room, or a far-away point when it isn't there.
func _podium_pos(n: int) -> Vector3:
	var stage := get_tree().root.find_child("Presenters", true, false) as PresenterStage
	var p := stage.get_presenter(n) if stage else null
	return p.get_picture().global_position if p else Vector3(999, 999, 999)


func _same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(file))


func _ready() -> void:
	NetSession.auto_confirm = true      # (no "let them in" popups in a test)
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)                       # (never the real Stream Core)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("together_port", SESSION_PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_address", "127.0.0.1:%d" % SESSION_PORT)
	AppState.set_setting("together_share_presenters", true)
	AppState.set_setting("laser_beam", true)
	AppState.set_setting("laser_from", "camera")
	AppState.set_setting("laser_podium", 0)
	AppState.set_setting("laser_toggle", false)
	AppState.request_room("lecture_hall_panel")
	add_child(load("res://core/main.tscn").instantiate())
	await _secs(5.0)
	var lasers := _lasers()
	if lasers == null:
		_check(false, "main made the LaserPointers node")
		print("DONE fails=", _fails)
		AppState.request_quit(1)
		return
	lasers.aim_override = get_viewport().get_visible_rect().size * Vector2(0.5, 0.4)
	var panel := get_tree().root.find_child("ControlPanel", true, false)
	if panel:
		panel.set("visible", false)      # (out of the screenshots)
	if OS.get_cmdline_user_args().has("--role=guest"):
		await _guest(lasers)
	else:
		await _host(lasers)


# ── Host ─────────────────────────────────────────────────────
func _host(lasers: LaserPointers) -> void:
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		AppState.set_setting(AppState.presenter_key(n, "on"), n == 1)
		AppState.set_setting(AppState.presenter_key(n, "source"), "silhouette")
	AppState.set_setting("laser_color", HOST_COLOR)

	# ── alone ──
	_check(not lasers.is_on() and lasers.get_laser(0).is_empty(), "no laser before L")
	var press := InputEventKey.new()
	press.keycode = KEY_L
	press.pressed = true
	Input.parse_input_event(press)
	await _secs(0.3)
	_check(lasers.is_on(), "holding L turns the laser on")
	var cam := get_viewport().get_camera_3d()
	var l := lasers.get_laser(0)
	_check(bool(l.get("visible", false)) and bool(l.get("beam", false)), "the dot and the beam show")
	var from: Vector3 = l.get("from", Vector3.ZERO)
	var to: Vector3 = l.get("to", Vector3.ZERO)
	_check(from.distance_to(cam.global_position) < 0.6, "the beam starts beside the camera (%.2f m away)" % from.distance_to(cam.global_position))
	var reach := to.distance_to(cam.global_position)
	_check(reach > 1.0 and reach < LaserPointers.RAY_M - 1.0, "the dot is on something in the room (%.1f m away)" % reach)
	_check(_same_color(l.get("color", Color.BLACK), HOST_COLOR), "in the host's colour")
	await _shot("laser_alone.png")
	var release := InputEventKey.new()
	release.keycode = KEY_L
	release.pressed = false
	Input.parse_input_event(release)
	await _secs(0.3)
	_check(not lasers.is_on() and not bool(lasers.get_laser(0)["visible"]), "letting go of L hides it")

	AppState.set_setting("laser_toggle", true)
	Input.parse_input_event(press)
	Input.parse_input_event(release)
	await _secs(0.3)
	_check(lasers.is_on(), "toggle mode: pressing L once keeps it on")
	AppState.set_setting("laser_beam", false)
	await _secs(0.2)
	_check(not bool(lasers.get_laser(0)["beam"]) and bool(lasers.get_laser(0)["visible"]), "Show the beam off leaves only the dot")
	AppState.set_setting("laser_beam", true)
	AppState.set_setting("laser_from", "podium")
	await _secs(0.2)
	from = lasers.get_laser(0)["from"]
	_check(from.distance_to(_podium_pos(1)) < 1.0, "My podium avatar: the beam starts at podium 1 (%.2f m away)" % from.distance_to(_podium_pos(1)))
	await _shot("laser_podium.png")
	AppState.set_setting(AppState.presenter_key(1, "on"), false)
	await _secs(0.2)
	from = lasers.get_laser(0)["from"]
	_check(from.distance_to(cam.global_position) < 0.6, "with that podium off set it falls back to the camera")
	Input.parse_input_event(press)
	Input.parse_input_event(release)
	await _secs(0.3)
	_check(not lasers.is_on(), "toggle mode: pressing L again turns it off")
	AppState.set_setting("laser_toggle", false)
	AppState.set_setting("laser_from", "camera")

	# ── together ──
	AppState.set_setting("together_bind", "local")
	NetSession.host()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_laserguest2.cfg"))
	DirAccess.remove_absolute(_out.path_join("together_laserguest.txt"))
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "980,0", "res://_tests/test_laser_pointer.tscn", "--", _out, "--mp-profile=laserguest2", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the guest copy")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 90.0), "the guest joined")
	var guest_id := 0
	for p: Dictionary in NetSession.get_info()["peers"]:
		if not bool(p["me"]):
			guest_id = int(p["id"])
	await _secs(3.0)
	lasers.set_on(true)
	# the guest claims podium 2 and turns its laser on once it sees the host's
	_check(await _wait_for(func() -> bool: return lasers.remote_count() == 1, 40.0), "the guest's laser shows here")
	await _secs(1.0)
	var g := lasers.get_laser(guest_id)
	_check(_same_color(g.get("color", Color.BLACK), GUEST_COLOR), "in the guest's colour")
	_check(bool(AppState.get_setting(AppState.presenter_key(2, "on"))), "the guest's podium 2 is on set")
	var gf: Vector3 = g.get("from", Vector3.ZERO)
	_check(gf.distance_to(_podium_pos(2)) < 1.0, "and its beam comes from podium 2 (%.2f m away)" % gf.distance_to(_podium_pos(2)))
	await _shot("laser_both.png")
	lasers.set_on(false)
	await _secs(LaserPointers.STALE_S + 1.5)
	# (a still laser keeps sending; on a slow test machine a frame can take seconds, so this waits
	# for it rather than checking one moment)
	_check(await _wait_for(func() -> bool: return lasers.remote_count() == 1, 10.0), "a laser held still stays on (keep-alive)")
	_check(await _wait_for(func() -> bool: return lasers.remote_count() == 0, 20.0), "the guest turning it off hides it here")
	await _secs(2.0)
	NetSession.leave()

	var f := _out.path_join("together_laserguest.txt")
	await _wait_for(func() -> bool: return FileAccess.file_exists(f), 40.0)
	var text := FileAccess.get_file_as_string(f)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		_check(line.begins_with("PASS "), "guest: " + line.substr(5))
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)


# ── Guest ────────────────────────────────────────────────────
func _guest(lasers: LaserPointers) -> void:
	AppState.set_setting("laser_color", GUEST_COLOR)
	AppState.set_setting("laser_from", "podium")
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and NetSession.get_info()["peers"].size() >= 2, 30.0), "joined")
	await _secs(2.0)
	NetSession.claim_podium(2)
	_check(await _wait_for(func() -> bool: return NetSession.my_podium() == 2, 15.0), "claimed podium 2")
	_check(await _wait_for(func() -> bool: return lasers.remote_count() == 1, 30.0), "the host's laser shows here")
	await _secs(0.5)
	var h := lasers.get_laser(1)
	_check(_same_color(h.get("color", Color.BLACK), HOST_COLOR), "in the host's colour")
	_check(bool(h.get("beam", false)), "with its beam")
	await _wait_for(func() -> bool: return bool(AppState.get_setting(AppState.presenter_key(2, "on"))), 10.0)
	lasers.set_on(true)
	await _secs(0.5)
	var mine: Vector3 = lasers.get_laser(0).get("from", Vector3.ZERO)
	_check(mine.distance_to(_podium_pos(2)) < 1.0, "my laser starts at my podium 2 (%.2f m away)" % mine.distance_to(_podium_pos(2)))
	_check(await _wait_for(func() -> bool: return lasers.remote_count() == 0, 20.0), "the host turning theirs off hides it here")
	await _secs(LaserPointers.STALE_S + 15.0)    # (the host checks the keep-alive meanwhile)
	lasers.set_on(false)
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "noticed the session ending")
	var f := FileAccess.open(_out.path_join("together_laserguest.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
