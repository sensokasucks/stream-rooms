extends Node
## Streaming together through a Cloudflare tunnel: the host picks "Cloudflare tunnel", gets a
## one-off trycloudflare.com address from cloudflared, and a guest copy joins through it (over the
## internet, with TLS). Needs the internet and tools/cloudflared.exe, so it isn't in the default set.
##   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Tests test_tunnel -TimeLimit 300

const SESSION_PORT: int = 7397
const PASSWORD: String = "tunnelpass"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []
var _statuses: PackedStringArray = []


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
	NetSession.auto_confirm = true      # (no "let them in" popups in a test)
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	EventBus.status_message.connect(func(t: String, _e: bool) -> void: _statuses.append(t))
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("together_port", SESSION_PORT)
	AppState.set_setting("together_password", PASSWORD)
	add_child(load("res://core/main.tscn").instantiate())
	await _secs(3.0)
	if args.has("--role=guest"):
		await _guest()
	else:
		await _host()


func _host() -> void:
	AppState.set_setting("together_bind", "tunnel")
	AppState.set_setting("house_lights", 1.0)
	NetSession.host()
	_check(NetSession.get_role() == "host", "hosting started with the tunnel option")
	_check(await _wait_for(func() -> bool: return NetSession.is_tunnel(), 45.0), "Cloudflare gave a tunnel address")
	var addr := String(NetSession.get_info()["address"])
	_check(addr.ends_with(".trycloudflare.com"), "it's a trycloudflare.com address")
	var leaked := ""
	for t in _statuses:
		if t.contains("trycloudflare") or t.contains("127.0.0.1"):
			leaked = t
	_check(leaked == "", "no status message shows the address (%s)" % leaked)
	# the guest copy gets the address through a file, like a real guest would get it pasted
	var addr_file := _out.path_join("tunnel_address.txt")
	var f := FileAccess.open(addr_file, FileAccess.WRITE)
	f.store_string(addr)
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_tunnelguest.cfg"))
	var result := _out.path_join("together_tunnelguest.txt")
	DirAccess.remove_absolute(result)
	var pargs := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "980,0", "res://_tests/test_tunnel.tscn", "--", _out, "--mp-profile=tunnelguest", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), pargs) > 0, "started the guest copy")
	_check(await _wait_for(func() -> bool: return (NetSession.get_info()["peers"] as Array).size() == 2, 120.0), "the guest joined through the tunnel")
	await _secs(2.0)
	AppState.set_setting("house_lights", 0.41)
	await _secs(6.0)
	NetSession.leave()
	_check(not OS.is_process_running(NetSession._tunnel_pid) if NetSession._tunnel_pid > 0 else true, "cloudflared stopped with the session")
	await _wait_for(func() -> bool: return FileAccess.file_exists(result), 40.0)
	var text := FileAccess.get_file_as_string(result)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		_check(line.begins_with("PASS "), "guest: " + line.substr(5))
	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _guest() -> void:
	var addr := FileAccess.get_file_as_string(_out.path_join("tunnel_address.txt")).strip_edges()
	AppState.set_setting("together_address", addr)
	AppState.set_setting("together_name", "TunnelGuest")
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and (NetSession.get_info()["peers"] as Array).size() == 2, 60.0),
		"joined the host through Cloudflare (wss)")
	_check(await _wait_for(func() -> bool: return absf(float(AppState.get_setting("house_lights")) - 0.41) < 0.001, 20.0),
		"the host's change arrived through the tunnel")
	_check(await _wait_for(func() -> bool: return NetSession._rtt_s() > 0.0, 10.0), "round-trip time measured (%.0f ms)" % (NetSession._rtt_s() * 1000.0))
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "noticed the session ending")
	var f := FileAccess.open(_out.path_join("together_tunnelguest.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("DONE fails=", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
