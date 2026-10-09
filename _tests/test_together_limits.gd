extends Node
## Together host limits, in one copy of the app (a pretend guest connects from inside this test):
## password length (8+ for a new password, an old saved short one still hosts with a note), wrong
## passwords from one address get paused, a full session refuses more guests, connections that
## never answer the password check are capped and dropped, and a guest's "right host?" popup
## closes when the session ends before they're let in.
##   <redot console exe> --path . _tests/test_together_limits.tscn -- C:/temp/sr_tests --mp-profile=test

const PORT: int = 7393                # not the default, so a real session on this PC isn't disturbed
const PASSWORD: String = "limits-pass"

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_for(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call():
			return true
		await _secs(0.1)
		t += 0.1
	return bool(cond.call())


## A pretend guest: connects with this password and returns the host's answer
## ("in" when the password check passed, else the refusal reason, "" for no answer).
func _try_join(password: String) -> String:
	var holder := Node.new()
	holder.name = "Guest%d" % Time.get_ticks_usec()
	add_child(holder)
	var mp := SceneMultiplayer.new()
	var result := {"answer": ""}
	mp.auth_callback = func(_id: int, data: PackedByteArray) -> void:
		var d: Variant = bytes_to_var(data)
		if not d is Dictionary:
			return
		match String(d.get("t", "")):
			"challenge":
				mp.send_auth(1, var_to_bytes({"t": "hello", "name": "Pretend", "protocol": NetSession.PROTOCOL,
					"version": NetSession._version(), "proof": NetSession.proof(d.get("nonce", PackedByteArray()), password)}))
				mp.complete_auth(1)
			"refused":
				result["answer"] = String(d.get("reason", "refused"))
	mp.connected_to_server.connect(func() -> void: result["answer"] = "in")
	get_tree().set_multiplayer(mp, holder.get_path())
	var peer := WebSocketMultiplayerPeer.new()
	peer.create_client("ws://127.0.0.1:%d" % PORT)
	mp.multiplayer_peer = peer
	await _wait_for(func() -> bool: return String(result["answer"]) != "", 8.0)
	peer.close()
	mp.multiplayer_peer = null
	get_tree().set_multiplayer(null, holder.get_path())
	holder.queue_free()
	await _secs(0.8)     # the host notices the connection closing
	return String(result["answer"])


func _ready() -> void:
	NetSession.auto_confirm = true
	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_port", PORT)

	# password length
	AppState.set_setting("together_password", "abc")
	NetSession.host()
	_check(NetSession.get_role() == "off", "a 3-character password can't host")
	AppState.set_setting("together_password", "abcdef")
	NetSession.host()
	_check(NetSession.get_role() == "off", "a new 6-character password can't host (needs %d)" % NetSession.MIN_PASSWORD)
	_check(NetSession.password_too_short(), "the panel is told the password is short")
	NetSession._old_password = "abcdef"      # as if it was saved before the minimum went up
	NetSession.host()
	_check(NetSession.get_role() == "host", "an old saved 6-character password still hosts")
	_check(String(NetSession.get_info()["status"]).contains("short"), "with a note to pick a longer one (%s)" % NetSession.get_info()["status"])
	NetSession.leave()
	NetSession._old_password = ""
	AppState.set_setting("together_password", PASSWORD)
	NetSession.host()
	_check(NetSession.get_role() == "host", "hosting with a long password (%s)" % NetSession.get_info()["status"])
	_check(not String(NetSession.get_info()["status"]).contains("short"), "no note for a long password")

	# the right password gets through the password check
	var ok := await _try_join(PASSWORD)
	_check(ok == "in", "the right password passes (%s)" % ok)

	# wrong passwords: a pause after MAX_WRONG of them
	var answers: Array[String] = []
	for i in NetSession.MAX_WRONG:
		answers.append(await _try_join("wrong-%d" % i))
	_check(answers.all(func(a: String) -> bool: return a.contains("Wrong session password")), "each wrong password is refused (%s)" % str(answers))
	var paused := await _try_join("another-wrong")
	_check(paused.contains("Too many wrong passwords"), "then that address has to wait (%s)" % paused)
	var even_right := await _try_join(PASSWORD)
	_check(even_right.contains("Too many wrong passwords"), "even the right password waits out the pause")
	NetSession._wrong.clear()
	_check(await _try_join(PASSWORD) == "in", "after the pause the right password works again")

	# a full session
	for fake in [901, 902, 903]:
		NetSession._peers[fake] = {"name": "Fake%d" % fake, "cohost": false, "avatar": ""}
	var full := await _try_join(PASSWORD)
	_check(full.contains("full"), "a full session (%d guests) refuses another (%s)" % [NetSession.MAX_GUESTS, full])
	for fake in [901, 902, 903]:
		NetSession._peers.erase(fake)

	# connections that never answer the password check: capped, then dropped
	var silent: Array[WebSocketPeer] = []
	for i in NetSession.MAX_UNAUTHENTICATED + 3:
		var ws := WebSocketPeer.new()
		ws.connect_to_url("ws://127.0.0.1:%d" % PORT)
		silent.append(ws)
	var most := 0
	for i in 40:
		for ws in silent:
			ws.poll()
		most = maxi(most, NetSession._nonces.size())
		await _secs(0.05)
	_check(most > 0 and most <= NetSession.MAX_UNAUTHENTICATED, "at most %d connections wait at the password check (saw %d)" % [NetSession.MAX_UNAUTHENTICATED, most])
	var dropped := await _wait_for(func() -> bool:
		for ws in silent:
			ws.poll()
		return NetSession._nonces.is_empty(), NetSession.AUTH_TIMEOUT + 5.0)
	_check(dropped, "they're dropped after %d s without an answer" % int(NetSession.AUTH_TIMEOUT))
	for ws in silent:
		ws.close()
	NetSession.leave()

	# a guest's "right host?" popup closes when the session ends before they're let in
	var closed: Array[int] = []
	EventBus.net_confirm_closed.connect(func(id: int) -> void: closed.append(id))
	NetSession._role = "guest"
	NetSession._admitted = false
	NetSession._close("The session ended.")
	_check(closed.has(1), "the guest's popup is told to close")

	# a picture that claims a huge size is refused before decoding
	var big := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var png := big.save_png_to_buffer()
	png[16] = 0x00; png[17] = 0x00; png[18] = 0x50; png[19] = 0x00
	_check(PictureFile.declared_size(big.save_png_to_buffer()) == Vector2i(8, 8), "reads a PNG's size from its header")
	_check(PictureFile.too_big(png) and PictureFile.texture_from_bytes(png) == null, "a PNG claiming 20480 px is refused")
	var jpg := Image.create(300, 200, false, Image.FORMAT_RGB8).save_jpg_to_buffer()
	_check(PictureFile.declared_size(jpg) == Vector2i(300, 200), "reads a JPEG's size from its header (%s)" % PictureFile.declared_size(jpg))
	var webp := Image.create(120, 90, false, Image.FORMAT_RGBA8).save_webp_to_buffer(true)
	_check(PictureFile.declared_size(webp) == Vector2i(120, 90), "reads a WebP's size from its header (%s)" % PictureFile.declared_size(webp))
	var webp2 := Image.create(120, 90, false, Image.FORMAT_RGBA8).save_webp_to_buffer(false, 0.8)
	_check(PictureFile.declared_size(webp2) == Vector2i(120, 90), "reads a lossy WebP's size too (%s)" % PictureFile.declared_size(webp2))

	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
